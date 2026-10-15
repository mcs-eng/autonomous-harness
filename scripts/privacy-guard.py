#!/usr/bin/env python3
"""Reject private terms in pull request text, commit messages, and added lines.

The term list is never stored in this repository. Hosted scans read the
PRIVATE_TERMS repository secret (newline- or comma-separated). Matching is
case-insensitive and uses ASCII word boundaries, so a shorter term does not
match inside a longer word. A hit fails the process and prints only the
location. The matched term is never written to stdout or stderr.

Fork pull requests do not receive repository secrets. When PRIVATE_TERMS is
unset or empty, this scan warns and passes. That is expected: the list cannot
be given to untrusted pull request code without revealing it.

Pull request mode reads --terms-file, else the PRIVATE_TERMS variable, else
the file named by $PRIVATE_TERMS_FILE.

The commit-msg hook uses the same matcher. It reads $PRIVATE_TERMS_FILE,
~/.config/privacy-guard/private-terms.txt, or ~/.config/private-terms.txt
(home is $HOME, else %USERPROFILE%) and does nothing when none exists.

Term lists are newline- or comma-separated. A line whose first non-space
character is # is a comment.

A finding prints its location (title, body, commit, or file, line, and
column) and a masked stand-in for the match that shows only its length.
"""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys


def parse_terms(raw):
    """Split a newline- or comma-separated term list. Blank entries are dropped."""
    if raw is None:
        return []
    terms = []
    seen = set()
    lines = str(raw).lstrip("\ufeff").splitlines()
    kept = "\n".join(line for line in lines if not line.lstrip().startswith("#"))
    for part in re.split(r"[\n,]+", kept):
        term = part.strip()
        if not term:
            continue
        key = term.casefold()
        if key in seen:
            continue
        seen.add(key)
        terms.append(term)
    return terms


def term_patterns(terms):
    patterns = []
    for term in terms:
        # Boundaries sit outside the term, so a term that starts or ends with
        # punctuation still matches as a whole token. re.escape keeps dots,
        # brackets, and other metacharacters literal.
        pattern = r"(?<![A-Za-z0-9_])" + re.escape(term) + r"(?![A-Za-z0-9_])"
        patterns.append(re.compile(pattern, re.IGNORECASE | re.ASCII))
    return patterns


def contains_term(text, terms):
    return first_match(text, terms) is not None


def first_match(text, terms):
    """Return (column, length) of the earliest match, 1-based column, or None."""
    if not text or not terms:
        return None
    best = None
    for pattern in term_patterns(terms):
        match = pattern.search(text)
        if match and (best is None or match.start() < best[0]):
            best = (match.start(), match.end() - match.start())
    if best is None:
        return None
    return best[0] + 1, best[1]


def masked(length):
    """A stand-in for a match that reveals only its length."""
    return f"[redacted {length} chars]"


def redact(text, terms):
    """Remove every term from a location string, including as a substring."""
    rendered = text
    for term in sorted(terms, key=len, reverse=True):
        if not term:
            continue
        rendered = re.sub(re.escape(term), "[redacted]", rendered, flags=re.IGNORECASE)
    return rendered


def destination_path(header):
    raw = header[4:].split("\t", 1)[0].strip()
    if raw == "/dev/null":
        return None
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        raw = raw[1:-1].encode("utf-8").decode("unicode_escape")
    if raw.startswith("b/"):
        raw = raw[2:]
    return raw or None


HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def added_lines(diff):
    """Yield (path, new_line_number, text) for lines added by a unified diff."""
    path = None
    new_line = None
    for line in diff.splitlines():
        if line.startswith("diff --git "):
            path = None
            new_line = None
            continue
        if line.startswith("+++ "):
            path = destination_path(line)
            new_line = None
            continue
        if line.startswith("@@"):
            match = HUNK.match(line)
            new_line = int(match.group(1)) if match and path else None
            continue
        if path is None or new_line is None:
            continue
        if line.startswith("+"):
            yield path, new_line, line[1:]
            new_line += 1
        elif line.startswith("-") or line.startswith("\\"):
            continue
        else:
            new_line += 1


def git_output(repo, *args):
    result = subprocess.run(
        ["git", *args],
        cwd=repo,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError("git failed")
    return result.stdout


def commit_messages(repo, base, head):
    """Commit messages reachable from head and not from base (base..head)."""
    raw = git_output(repo, "log", "--reverse", "-z", "--format=%H%x1f%B", f"{base}..{head}")
    commits = []
    for chunk in raw.split("\0"):
        if not chunk.strip():
            continue
        sha, separator, message = chunk.partition("\x1f")
        sha = sha.strip()
        if separator and sha:
            commits.append((sha, message))
    return commits


def diff_text(repo, base, head):
    """Added and removed lines since the merge base, which is the pull request diff."""
    args = ["-c", "core.quotepath=false", "diff", "--unified=0", "--no-color", "--no-ext-diff"]
    try:
        return git_output(repo, *args, f"{base}...{head}")
    except RuntimeError:
        return git_output(repo, *args, base, head)


def scan_pull_request(repo, base, head, title, body, terms):
    """Return location strings. Terms themselves are redacted out of each one."""
    findings = []
    for label, text in (("PR title", title or ""), ("PR body", body or "")):
        hit = first_match(text, terms)
        if hit:
            findings.append(f"{label}: {masked(hit[1])}")
    for sha, message in commit_messages(repo, base, head):
        hit = first_match(message, terms)
        if hit:
            findings.append(f"commit {sha} message: {masked(hit[1])}")
    for path, line_no, text in added_lines(diff_text(repo, base, head)):
        hit = first_match(text, terms)
        if hit:
            findings.append(f"file {path} line {line_no} column {hit[0]}: {masked(hit[1])}")
    return [redact(location, terms) for location in findings]


def locate_hook_file():
    """$PRIVATE_TERMS_FILE, else the default files under the home directory."""
    candidates = []
    env_path = os.environ.get("PRIVATE_TERMS_FILE", "").strip()
    if env_path:
        candidates.append(Path(env_path).expanduser())
    home = os.environ.get("HOME", "").strip() or os.environ.get("USERPROFILE", "").strip()
    if home:
        candidates.append(Path(home) / ".config" / "privacy-guard" / "private-terms.txt")
        candidates.append(Path(home) / ".config" / "private-terms.txt")
    for path in candidates:
        if path.is_file():
            return path
    return None


def read_text(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


def warn_skipped():
    message = "PRIVATE_TERMS and PRIVATE_TERMS_FILE are unset or empty; privacy scan skipped"
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::warning::{message}", file=sys.stderr)
    else:
        print(f"warning: {message}", file=sys.stderr)


def emit(findings):
    for location in findings:
        print(location)
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::error::{location}", file=sys.stderr)
    return 1 if findings else 0


def load_pr_terms(args):
    """Return the hosted term list. An empty result means warn-and-pass.

    Pull request mode reads --terms-file, else a non-empty PRIVATE_TERMS
    variable, else the file named by PRIVATE_TERMS_FILE. It does not fall
    back to the hook's default home-directory files.
    """
    if args.terms_file:
        return parse_terms(read_text(args.terms_file))
    terms = parse_terms(os.environ.get("PRIVATE_TERMS", ""))
    if terms:
        return terms
    file_path = os.environ.get("PRIVATE_TERMS_FILE", "").strip()
    if file_path:
        return parse_terms(read_text(Path(file_path).expanduser()))
    return []


def pull_request_text(args, flag, file_flag, env_name):
    if file_flag:
        return read_text(file_flag)
    if flag is not None:
        return flag
    return os.environ.get(env_name, "")


def run_commit_message(args):
    if args.terms_file:
        terms = parse_terms(read_text(args.terms_file))
    else:
        found = locate_hook_file()
        if found is None:
            return 0
        terms = parse_terms(read_text(found))
    if not terms:
        return 0
    message = read_text(args.commit_message_file)
    hit = first_match(message, terms)
    if hit is None:
        return 0
    return emit([redact(f"commit message: {masked(hit[1])}", terms)])


def run_pull_request(args):
    terms = load_pr_terms(args)
    if not terms:
        warn_skipped()
        return 0
    base = args.base or os.environ.get("BASE_SHA", "")
    head = args.head or os.environ.get("HEAD_SHA", "")
    if not base or not head:
        print("privacy guard needs the pull request base and head", file=sys.stderr)
        return 1
    title = pull_request_text(args, args.title, args.title_file, "PR_TITLE")
    body = pull_request_text(args, args.body, args.body_file, "PR_BODY")
    findings = scan_pull_request(args.repo, base, head, title, body, terms)
    return emit(findings)


def parse_args(argv):
    parser = argparse.ArgumentParser(description="Scan public pull request text for private terms.")
    parser.add_argument("--pull-request", action="store_true",
                        help="scan PR_TITLE, PR_BODY, and BASE_SHA..HEAD_SHA using PRIVATE_TERMS")
    parser.add_argument("--commit-message-file",
                        help="scan one commit message (commit-msg hook)")
    parser.add_argument("--terms-file", help="newline- or comma-separated term list")
    parser.add_argument("--base", help="base revision for base..head")
    parser.add_argument("--head", help="head revision for base..head")
    parser.add_argument("--title", help="pull request title")
    parser.add_argument("--body", help="pull request body")
    parser.add_argument("--title-file", help="file containing the pull request title")
    parser.add_argument("--body-file", help="file containing the pull request body")
    parser.add_argument("--repo", default=".", help="repository to scan")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    try:
        if args.commit_message_file:
            return run_commit_message(args)
        return run_pull_request(args)
    except RuntimeError:
        print("privacy guard could not read the git range", file=sys.stderr)
        return 1
    except OSError:
        print("privacy guard could not read an input file", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
