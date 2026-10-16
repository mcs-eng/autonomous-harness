#!/usr/bin/env python3
"""Reject private terms in pull request text, commits, paths, and changed files.

The term list is never stored in this repository. Hosted scans read the
PRIVATE_TERMS repository secret (newline- or comma-separated). Matching is
case-insensitive and uses ASCII word boundaries, so a shorter term does not
match inside a longer word. A hit fails the process and prints only the
location. The matched term is never written to stdout or stderr.

The hosted workflow runs this scanner from the base branch on
pull_request_target. Fork pull requests get an empty term list, because their
logs are public and a match location would confirm a guess. When PRIVATE_TERMS is
unset or empty, this scan warns and passes. That happens only when the
secret is missing.

Pull request mode reads --terms-file, else the PRIVATE_TERMS variable, else
the file named by $PRIVATE_TERMS_FILE.

The commit-msg hook uses the same matcher. It reads $PRIVATE_TERMS_FILE,
~/.config/privacy-guard/private-terms.txt, or ~/.config/private-terms.txt
(home is $HOME, else %USERPROFILE%) and does nothing when none exists.

Term lists are newline- or comma-separated. A line whose first non-space
character is # is a comment.

A finding prints its location (title, body, commit, file path, or file line and
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


_PATTERN_CACHE = {}


def term_patterns(terms):
    key = tuple(terms)
    cached = _PATTERN_CACHE.get(key)
    if cached is not None:
        return cached
    patterns = []
    for term in terms:
        # Boundaries sit outside the term, so a term that starts or ends with
        # punctuation still matches as a whole token. re.escape keeps dots,
        # brackets, and other metacharacters literal.
        pattern = r"(?<![A-Za-z0-9_])" + re.escape(term) + r"(?![A-Za-z0-9_])"
        # No re.ASCII: case folding must work for non-ASCII terms too. The
        # boundary classes above are spelled out, so they stay ASCII-only.
        patterns.append(re.compile(pattern, re.IGNORECASE))
    _PATTERN_CACHE[key] = patterns
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


def shown_path(path, terms):
    """A path or SHA as printed: hidden entirely when any term appears inside it.

    Only the path is checked. Replacing term substrings across a whole
    finding line would mark which letters of fixed words or SHAs spell a
    term, which reveals terms that are not even in the pull request.
    """
    lowered = path.casefold()
    if any(term.casefold() in lowered for term in terms if term):
        return "[redacted path]"
    return path


def path_match(path, terms):
    """Return the first case-insensitive term substring in a path."""
    best = None
    for term in terms:
        match = re.search(re.escape(term), path, re.IGNORECASE)
        if match and (best is None or match.start() < best[0]):
            best = (match.start(), match.end() - match.start())
    return None if best is None else (best[0] + 1, best[1])


def redact(text, terms):
    """Remove every term from a location string, including as a substring."""
    rendered = text
    for term in sorted(terms, key=len, reverse=True):
        if not term:
            continue
        rendered = re.sub(re.escape(term), "[redacted]", rendered, flags=re.IGNORECASE)
    return rendered


_GIT_ESCAPES = {"a": 7, "b": 8, "t": 9, "n": 10, "v": 11, "f": 12, "r": 13, '"': 34, "\\": 92}


def unquote_git_path(text):
    """Undo git's C-style path quoting. Octal escapes are UTF-8 bytes."""
    out = bytearray()
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            digits = text[i + 1:i + 4]
            if len(digits) == 3 and all(c in "01234567" for c in digits):
                out.append(int(text[i + 1:i + 4], 8) & 0xFF)
                i += 4
                continue
            if nxt in _GIT_ESCAPES:
                out.append(_GIT_ESCAPES[nxt])
                i += 2
                continue
        out.extend(ch.encode("utf-8"))
        i += 1
    return out.decode("utf-8", errors="replace")


def destination_path(header):
    raw = header[4:].split("\t", 1)[0].strip()
    if raw == "/dev/null":
        return None
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        raw = unquote_git_path(raw[1:-1])
    if raw.startswith("b/"):
        raw = raw[2:]
    return raw or None


HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def added_lines(diff):
    """Yield (path, new_line_number, text) for lines added by a unified diff.

    Hunk headers give the old and new line counts. Lines inside a hunk are
    consumed by those counts, so an added line that itself starts with
    "++ " or "diff --git" is scanned as content, not read as a header.
    Lines split only on newline, so form feeds and Unicode line separators
    stay inside the line they belong to.
    """
    path = None
    new_line = None
    old_left = new_left = 0
    for line in diff.split("\n"):
        if line.endswith("\r"):
            line = line[:-1]
        if old_left > 0 or new_left > 0:
            if line.startswith("+"):
                if path is not None:
                    yield path, new_line, line[1:]
                new_line += 1
                new_left -= 1
            elif line.startswith("-"):
                old_left -= 1
            elif line.startswith("\\"):
                pass
            else:
                new_line += 1
                old_left -= 1
                new_left -= 1
            continue
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
            if match:
                old_left = int(match.group(1)) if match.group(1) is not None else 1
                new_line = int(match.group(2))
                new_left = int(match.group(3)) if match.group(3) is not None else 1
            continue


def git_output(repo, *args):
    result = subprocess.run(
        ["git", *args],
        cwd=repo,
        check=False,
        capture_output=True,
        timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError("git failed")
    # Decode bytes directly. Text mode would turn a lone CR inside a line
    # into a line break and throw off the hunk line counts.
    return result.stdout.decode("utf-8", errors="replace")


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


MAX_BINARY_BLOB_SIZE = 5 * 1024 * 1024


def changed_blobs(repo, base, head):
    """Yield (status, destination path, head blob id) from Git's raw diff."""
    args = ["-c", "core.quotepath=false", "diff", "--raw", "-z", "--no-abbrev",
            "--no-ext-diff", "--find-renames", "--find-copies-harder"]
    try:
        result = subprocess.run(
            ["git", *args, f"{base}...{head}"], cwd=repo, check=False,
            capture_output=True, timeout=120,
        )
        if result.returncode != 0:
            result = subprocess.run(
                ["git", *args, base, head], cwd=repo, check=False,
                capture_output=True, timeout=120,
            )
        if result.returncode != 0:
            raise RuntimeError("git failed")
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise RuntimeError("git failed") from exc
    fields = result.stdout.split(b"\0")
    i = 0
    while i < len(fields) and fields[i]:
        metadata = fields[i].decode("ascii", errors="replace").split()
        i += 1
        if len(metadata) < 5 or i >= len(fields):
            raise RuntimeError("git failed")
        status = metadata[4]
        old_path = fields[i]
        i += 1
        path = old_path
        if status[:1] in ("R", "C"):
            if i >= len(fields):
                raise RuntimeError("git failed")
            path = fields[i]
            i += 1
        yield status[:1], path.decode("utf-8", errors="replace"), metadata[2], metadata[3], metadata[1]


def blob_bytes(repo, oid, display_path):
    """Read a bounded Git blob by object id; oversize blobs fail closed."""
    size = git_output(repo, "cat-file", "-s", oid).strip()
    if not size.isdigit():
        raise RuntimeError("git failed")
    if int(size) > MAX_BINARY_BLOB_SIZE:
        raise RuntimeError(f"changed blob {display_path} exceeded the {MAX_BINARY_BLOB_SIZE}-byte size cap")
    result = subprocess.run(
        ["git", "cat-file", "blob", oid], cwd=repo, check=False,
        capture_output=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError("git failed")
    return result.stdout


def decoded_blob_views(content):
    """Decode blob bytes in each supported encoding, tolerating malformed bytes."""
    return [content.decode(encoding, errors="replace") for encoding in ("utf-8", "utf-16-le", "utf-16-be")]


def occurrence_counts(content, terms):
    """Count each term in the decoding that yields its greatest occurrence count."""
    views = decoded_blob_views(content)
    return [max(sum(1 for _ in pattern.finditer(view)) for view in views) for pattern in term_patterns(terms)]


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
            findings.append(f"commit {shown_path(sha, terms)} message: {masked(hit[1])}")
    raw_changes = list(changed_blobs(repo, base, head))
    line_findings = []
    line_hit_paths = set()
    for path, line_no, text in added_lines(diff_text(repo, base, head)):
        hit = first_match(text, terms)
        if hit:
            line_hit_paths.add(path)
            line_findings.append(f"file {shown_path(path, terms)} line {line_no} column {hit[0]}: {masked(hit[1])}")
    for status, path, base_oid, head_oid, head_mode in raw_changes:
        if status in ("A", "R", "C"):
            path_hit = path_match(path, terms)
            if path_hit:
                findings.append(f"file {shown_path(path, terms)}: {masked(path_hit[1])}")
        if head_mode == "160000":
            if status == "A":
                raise RuntimeError(f"submodule add at {shown_path(path, terms)} cannot be scanned")
            continue
        if status in ("A", "M", "R", "C", "T"):
            display_path = shown_path(path, terms)
            content = blob_bytes(repo, head_oid, display_path)
            previous = b"" if status == "A" else blob_bytes(repo, base_oid, display_path)
            head_counts = occurrence_counts(content, terms)
            base_counts = occurrence_counts(previous, terms)
            if any(head > old for head, old in zip(head_counts, base_counts)) and path not in line_hit_paths:
                views = decoded_blob_views(content)
                hit = next((first_match(view, terms) for view in views if first_match(view, terms)), None)
                if hit:
                    findings.append(f"file {shown_path(path, terms)}: {masked(hit[1])}")
    findings.extend(line_findings)
    return findings


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


def annotation_text(text):
    """Escape a value for a GitHub Actions workflow command."""
    return text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")


def safe_line(text):
    """Replace control characters so a crafted file name cannot start a new log line."""
    return "".join(ch if ch.isprintable() else "?" for ch in text)


def emit(findings):
    for location in findings:
        location = safe_line(location)
        print(location)
        if os.environ.get("GITHUB_ACTIONS") == "true":
            print(f"::error::{annotation_text(location)}", file=sys.stderr)
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
    return emit([f"commit message: {masked(hit[1])}"])


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
    except RuntimeError as exc:
        message = str(exc)
        if "exceeded the " in message or message.startswith("submodule add at "):
            print(f"privacy guard: {message}", file=sys.stderr)
        else:
            print("privacy guard could not read the git range", file=sys.stderr)
        return 1
    except OSError:
        print("privacy guard could not read an input file", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
