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

With --upstream-ref, a line finding is suppressed when the blamed commit that
introduced the line is an ancestor of that ref and the flagged line is still
present verbatim in the ref's version of the file. A path finding on an added,
renamed or copied file is likewise suppressed when the blob the pull request
carries at that path is identical to the ref's blob at the same path: then the
whole file, name included, is the ref's own public content. This exempts
content the pull request carries from the named upstream history (for a fork,
upstream's own public commits) without weakening any other check: PR text,
commit messages, paths the fork authored or re-shaped, binary findings, other
encodings of the same file, and fork-authored lines are never exempted, and an
unresolvable ref fails the scan. Carried lines exempt only the UTF-8 view of
a textual file in the per-file re-scan, never the whole file. The ref must
name a commit the scanner can read; the hosted workflow fetches the fork's
upstream main into one as pure git data.
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
    if path_match(path, terms):
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
        out.extend(ch.encode("utf-8", errors="surrogateescape"))
        i += 1
    return out.decode("utf-8", errors="surrogateescape")


def destination_path(header):
    raw = header[4:].split("\t", 1)[0]
    if raw == "/dev/null":
        return None
    if len(raw) >= 2 and raw[0] == '"' and raw[-1] == '"':
        raw = unquote_git_path(raw[1:-1])
    if raw.startswith("b/"):
        raw = raw[2:]
    return raw or None


HUNK = re.compile(r"^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@")


def added_lines(diff, textual_paths=None):
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
                if textual_paths is not None and path is not None:
                    textual_paths.add(path)
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
    # Keep path identity lossless: distinct invalid UTF-8 names must not alias.
    # safe_line replaces non-printable surrogate escapes before displaying them.
    return result.stdout.decode("utf-8", errors="surrogateescape")


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
        yield status[:1], path.decode("utf-8", errors="surrogateescape"), metadata[2], metadata[3], metadata[1]


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
    """Decode supported encodings, including UTF-16 after an odd-byte header."""
    return [content.decode("utf-8", errors="replace")] + [
        content[offset:].decode(encoding, errors="replace")
        for encoding in ("utf-16-le", "utf-16-be") for offset in (0, 1)
    ]


def new_occurrences(content, previous, terms, utf8_is_diffed=False):
    """Return whether any occurrence has a new position or spelling in a blob.

    Compare each decoding separately. A count-only comparison misses a term
    moved within a binary blob when the old and new blobs contain the same
    number of matches. For text hunks, added_lines already checks the UTF-8
    view: shifting an unchanged line is not a new occurrence. Other encodings
    still need blob scanning even when attributes force Git to emit text hunks.
    """
    patterns = term_patterns(terms)
    views = zip(decoded_blob_views(content), decoded_blob_views(previous))
    for index, (current_view, previous_view) in enumerate(views):
        if index == 0 and utf8_is_diffed:
            continue
        for pattern in patterns:
            old = {(match.start(), match.end(), match.group().casefold())
                   for match in pattern.finditer(previous_view)}
            if any((match.start(), match.end(), match.group().casefold()) not in old
                   for match in pattern.finditer(current_view)):
                return True
    return False


def line_origin_commit(repo, head, path, line_no):
    """Return the commit that last touched line line_no of path at head, or None."""
    try:
        result = subprocess.run(
            ["git", "blame", "--line-porcelain", "-L", f"{line_no},{line_no}",
             head, "--", path],
            cwd=repo, check=False, capture_output=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    first = result.stdout.split(b"\n", 1)[0].split()
    if not first:
        return None
    sha = first[0].decode("ascii", errors="replace")
    if not sha or set(sha) == {"0"}:
        return None
    return sha


def is_ancestor(repo, ancestor, ref):
    try:
        result = subprocess.run(
            ["git", "merge-base", "--is-ancestor", ancestor, ref],
            cwd=repo, check=False, capture_output=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def ref_file_lines(repo, ref, path):
    """Return the set of text lines in ref's version of path, or None if absent."""
    try:
        result = subprocess.run(
            ["git", "show", f"{ref}:{path}"],
            cwd=repo, check=False, capture_output=True, timeout=120,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return set(result.stdout.decode("utf-8", errors="replace").splitlines())


def carried_by_upstream(repo, head, path, line_no, text, upstream_ref, cache):
    """Whether the flagged line is carried verbatim from upstream history.

    True only when the blame origin of the line is an ancestor of upstream_ref
    and the exact line still exists in upstream_ref's version of the file. Any
    doubt (no blame, no ancestry, line rewritten or removed upstream) is False.
    """
    origin = line_origin_commit(repo, head, path, line_no)
    if origin is None or not is_ancestor(repo, origin, upstream_ref):
        return False
    if path not in cache:
        cache[path] = ref_file_lines(repo, upstream_ref, path)
    upstream_lines = cache[path]
    if upstream_lines is None:
        return False
    return text.rstrip("\r\n") in upstream_lines


def path_blob_carried_by_upstream(repo, head_oid, upstream_ref, path):
    """Whether a flagged added/renamed/copied path names upstream's exact blob.

    True only when upstream_ref resolves the path and its blob is identical to
    the pull request's blob there, so the whole file — name included — is the
    upstream's own public content and the fork added nothing of its own under
    that name. Any doubt (missing path upstream, changed or unreadable blob)
    is False: a fork could otherwise park a private file behind a name the
    upstream also uses.
    """
    result = subprocess.run(
        ["git", "rev-parse", "-q", "--verify", f"{upstream_ref}:{path}"],
        cwd=repo, check=False, capture_output=True, timeout=120,
    )
    if result.returncode != 0:
        return False
    upstream_oid = result.stdout.decode("ascii", errors="replace").strip()
    return upstream_oid == head_oid


def scan_pull_request(repo, base, head, title, body, terms, upstream_ref=None):
    """Return location strings. Terms themselves are redacted out of each one."""
    carried_cache = {}
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
    carried_paths = set()
    textual_paths = set()
    for path, line_no, text in added_lines(diff_text(repo, base, head), textual_paths):
        hit = first_match(text, terms)
        if hit:
            if upstream_ref is not None and carried_by_upstream(
                    repo, head, path, line_no, text, upstream_ref, carried_cache):
                carried_paths.add(path)
                continue
            line_hit_paths.add(path)
            line_findings.append(f"file {shown_path(path, terms)} line {line_no} column {hit[0]}: {masked(hit[1])}")
    # A path stays in the full-file scan below even when its only added-line
    # hits were carried: the carried lines only exempt the UTF-8 view of a
    # textual file, never its other encodings.
    carried_only = carried_paths - line_hit_paths
    for status, path, base_oid, head_oid, head_mode in raw_changes:
        if status in ("A", "R", "C"):
            path_hit = path_match(path, terms)
            if path_hit and not (upstream_ref is not None and path_blob_carried_by_upstream(
                    repo, head_oid, upstream_ref, path)):
                findings.append(f"file {shown_path(path, terms)}: {masked(path_hit[1])}")
        if head_mode == "160000":
            if status == "A":
                raise RuntimeError(f"submodule add at {shown_path(path, terms)} cannot be scanned")
            continue
        if status in ("A", "M", "R", "C", "T"):
            display_path = shown_path(path, terms)
            content = blob_bytes(repo, head_oid, display_path)
            previous = b"" if status in ("A", "C") else blob_bytes(repo, base_oid, display_path)
            utf8_is_diffed = path in textual_paths and (
                status in ("M", "R", "T") or path in carried_only)
            if new_occurrences(content, previous, terms, utf8_is_diffed) and path not in line_hit_paths:
                views = decoded_blob_views(content)
                if utf8_is_diffed:
                    views = views[1:]
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
    upstream_ref = args.upstream_ref
    if upstream_ref:
        resolved = subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", f"{upstream_ref}^{{commit}}"],
            cwd=args.repo, check=False, capture_output=True, timeout=120,
        )
        if resolved.returncode != 0:
            print("privacy guard: upstream ref does not resolve; failing closed",
                  file=sys.stderr)
            return 1
    findings = scan_pull_request(args.repo, base, head, title, body, terms,
                                 upstream_ref=upstream_ref or None)
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
    parser.add_argument("--upstream-ref",
                        help="commit ref (fetched upstream history); lines carried "
                             "verbatim from it are exempt from line findings")
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
            print(f"privacy guard: {safe_line(message)}", file=sys.stderr)
        else:
            print("privacy guard could not read the git range", file=sys.stderr)
        return 1
    except OSError:
        print("privacy guard could not read an input file", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
