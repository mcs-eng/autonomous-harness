#!/usr/bin/env python3
"""Measure-Prodding.py: a weekly "bottleneck meter" for an agent team.

Counts how many of the owner's typed turns in Claude Code session transcripts
were spent prodding agents (approving, nudging, verifying, routing,
re-supplying context, fixing tooling, pasting hand-step output) versus giving
new work. It never prints transcript text unless --explain is given.

Run it as:  python -I Measure-Prodding.py [--since YYYY-MM-DD] [--until YYYY-MM-DD]
See README.md beside this file for the full option list.
"""
import argparse
import collections
import datetime as dt
import json
import re
import sys
from pathlib import Path

# --------------------------------------------------------------------------
# Rules
# --------------------------------------------------------------------------

BUCKETS = ["approve", "nudge", "verify", "route", "resupply",
           "hygiene", "handstep", "handoff"]

MAX_TYPED_CHARS = 4000     # longer turns are pastes: skipped entirely
MAX_BUCKET_CHARS = 700     # longer turns count as typed but are not bucketed
EXPLAIN_MAX_SNIPPETS = 20
EXPLAIN_SNIPPET_CHARS = 60

SKIP_PREFIXES = ("<task-notification", "<system-reminder", "/compact",
                 "[Request interrupted", "This session is being continued",
                 "<command-name>")
DISPATCH_PREFIX = "User's message, verbatim:"
DISPATCH_MARKER = "Orchestrator context"

# A rule is one regex, or a list of regexes that must ALL match. A bucket
# matches a turn when ANY of its rules matches. Matching is case-insensitive
# and runs on text with curly apostrophes folded to straight ones.
RULES = {
    "approve": [
        r"\bapproved?\b",
        r"\bmerge (it|\d+|them)\b",
        r"\bmerged by me\b",
        r"^\W*yes\W*$",
        r"\bgo ahead\b",
        r"\blgtm\b",
        r"\bship it\b",
    ],
    "nudge": [
        r"\bcontinue\b",
        r"\bkeep going\b",
        r"\bkeep pushing\b",
        r"\btry again\b",
        r"\bretry\b",
        r"\bproceed\b",
        r"\bare you (done|waiting|stuck)\b",
        r"\bwaiting on me\b",
        r"\bwhy did you stop\b",
        r"^\W*go\W*$",
        r"\bgo on\b",
        r"\bfinish it\b",
    ],
    "verify": [
        r"\bstill (failing|broken|open|not)\b",
        r"\bdidn'?t (work|do|run|merge)\b",
        r"\byou said\b",
        r"\bthat'?s not\b",
        r"\bit'?s empty\b",
        r"\bnot merged\b",
        r"\bwrong\b",
        r"\bdoesn'?t work\b",
        r"\bdeflecting\b",
    ],
    "route": [
        r"\bwhich (repo|session|branch|model|folder)\b",
        r"\bdispatch\b",
        r"\bin (the )?[a-z-]+ repo\b",
        [r"\b(opus|sonnet|haiku|codex)\b", r"\b(use|switch|delegate|lane)\b"],
        r"\bnew session\b",
        [r"\bworktree\b", r"\buse\b"],
    ],
    "resupply": [
        r"\bi (already )?(told|said|asked)\b",
        [r"\bagain\b", r"\bwe (did|covered|decided)\b"],
        r"\bupdate the (readme|sop|claude\.md|docs?) (to|so)\b",
        r"\bread (its|the) claude\.md\b",
        r"\bremember\b",
        r"\bas (i|we) (said|decided)\b",
    ],
    "hygiene": [
        r"\bre-?auth(ed|'d)?\b",
        r"\bgh auth\b",
        r"\bcredentials?\b",
        r"\bcmdkey\b",
        r"\bonedrive\b",
        r"\bworktrees?\b",
        r"\bdisk\b",
        r"\b\d+ ?gb\b",
        r"\bmcp\b",
        r"\bsandbox\b",
        r"\bpopups?\b",
        r"\busage\b",
        r"\btokens?\b",
        r"\bci (mins|minutes|cost)\b",
        r"\bbroke again\b",
        r"\beverything breaking\b",
        r"\bindex\.lock\b",
    ],
    "handstep": [
        r"\bcmdkey:",
        r"PS C:\\",
        r"\bexit code\b",
        r"\bcredential added\b",
        r"\bsuccessfully\b",
        r"^\W*(done|started|logged in|connected|running|in|ok)\W*$",
    ],
    "handoff": [
        r"\bmake me proud\b",
        r"\bgoing to (bed|sleep)\b",
        r"\bpick up (from|where)\b",
        r"\bhand-?off\b",
        r"\bcatch me up\b",
        r"\bcatchup\b",
        r"\bovernight\b",
        r"\bwhat('?s| is) left\b",
    ],
}

COMPILED = {
    bucket: [[re.compile(p, re.I) for p in (rule if isinstance(rule, list) else [rule])]
             for rule in rules]
    for bucket, rules in RULES.items()
}

COLUMNS = (["sessions", "typed_turns", "dispatch"] + BUCKETS
           + ["any_prodding", "prodding_share"])


def fold(text):
    """Fold curly quotes so "didn't" with a typographic apostrophe matches."""
    return text.replace("\u2019", "'").replace("\u2018", "'")


def bucket_span(bucket, text):
    """Return the first match span for a bucket, or None."""
    for rule in COMPILED[bucket]:
        found = [p.search(text) for p in rule]
        if all(found):
            return found[0].span()
    return None


def classify(text):
    """Return the set of buckets a typed turn falls in."""
    text = fold(text.strip())
    if len(text) > MAX_BUCKET_CHARS:
        return set()
    found = {b for b in BUCKETS if bucket_span(b, text)}
    # Pasted command output is not the owner talking about tooling.
    if "handstep" in found:
        found.discard("hygiene")
    return found


# --------------------------------------------------------------------------
# Transcript reading
# --------------------------------------------------------------------------

def human_text(rec):
    """Return the turn text if the record is structurally a human turn."""
    if rec.get("type") != "user":
        return None
    msg = rec.get("message")
    if not isinstance(msg, dict):
        return None
    content = msg.get("content")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        texts = []
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_result":
                return None
            if block.get("type") == "text" and isinstance(block.get("text"), str):
                texts.append(block["text"])
        if texts:
            return "\n".join(texts)
    return None


def system_injected(rec):
    """True for records the harness wrote, not the owner."""
    if rec.get("isMeta") or rec.get("isCompactSummary"):
        return True
    origin = rec.get("origin")
    if isinstance(origin, dict) and origin.get("kind") not in (None, "human"):
        return True
    return False


def parse_ts(value):
    if not isinstance(value, str):
        return None
    value = value.strip()
    if value[-1:] in ("Z", "z"):
        value = value[:-1] + "+00:00"
    try:
        stamp = dt.datetime.fromisoformat(value)
    except ValueError:
        return None
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=dt.timezone.utc)
    return stamp


def week_start(day):
    """Monday of the ISO week containing the given date."""
    return day - dt.timedelta(days=day.weekday())


def short_project_name(dirname):
    """Shorten a Claude Code project directory name to its last path segment.

    Claude Code encodes a working directory by turning path separators into
    dashes, so the split is a heuristic: worktrees fold into their parent
    repo, the drive and user-profile prefix is dropped, and one common
    container folder (dev, src, repos, ...) is dropped.
    """
    name = dirname
    if "/" in name or "\\" in name:
        parts = [p for p in re.split(r"[\\/]+", name) if p]
        return parts[-1] if parts else name
    if "-scratch-workspaces-" in name:
        return "claude-scratch"
    name = re.sub(r"--claude-worktrees-.*$", "", name)
    name = re.sub(r"^[A-Za-z]--", "", name)
    name = re.sub(r"^Users-[^-]+-", "", name)
    name = re.sub(r"^(dev|src|repos|code|projects|work|Documents|Tools)-", "", name)
    return name or dirname


class Tally:
    def __init__(self):
        self.sessions = set()
        self.typed = 0
        self.dispatch = 0
        self.buckets = dict.fromkeys(BUCKETS, 0)
        self.any = 0

    def add_typed(self, session, found):
        self.sessions.add(session)
        self.typed += 1
        for b in found:
            self.buckets[b] += 1
        if found:
            self.any += 1

    def add_dispatch(self, session):
        self.sessions.add(session)
        self.dispatch += 1

    def row(self, key, label):
        row = {key: label, "sessions": len(self.sessions),
               "typed_turns": self.typed, "dispatch": self.dispatch}
        row.update(self.buckets)
        row["any_prodding"] = self.any
        row["prodding_share"] = (round(100.0 * self.any / self.typed, 1)
                                 if self.typed else None)
        return row


class Result:
    def __init__(self):
        self.weeks = collections.defaultdict(Tally)
        self.projects = collections.defaultdict(Tally)
        self.total = Tally()
        self.skipped = collections.Counter()
        self.files = 0
        self.explain = []   # (timestamp, text, buckets); filled only on request


def discover(projects_dir):
    """Session files, oldest first, so a copied history is credited to its original."""
    found = []
    for path in Path(projects_dir).glob("*/*.jsonl"):
        try:
            st = path.stat()
        except OSError:
            continue
        found.append((getattr(st, "st_birthtime", st.st_mtime), str(path), path))
    found.sort()
    return [p for _, _, p in found]


def iter_records(path, result):
    try:
        handle = open(path, encoding="utf-8", errors="replace")
    except OSError:
        result.skipped["unreadable_file"] += 1
        return
    with handle:
        for line in handle:
            if '"user"' not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                result.skipped["bad_json_line"] += 1
                continue
            if isinstance(rec, dict):
                yield rec


def collect(projects_dir, since, until, tz=None, keep_text=False):
    """Read every transcript and tally typed turns.

    since and until are inclusive dates (until may be None). tz is a tzinfo,
    or None for the machine's local time zone.
    """
    result = Result()
    seen = set()
    for path in discover(projects_dir):
        result.files += 1
        session = path.stem
        project = short_project_name(path.parent.name)
        for rec in iter_records(path, result):
            if rec.get("isSidechain") is True:
                continue
            text = human_text(rec)
            if text is None:
                continue
            stamp = parse_ts(rec.get("timestamp"))
            if stamp is None:
                result.skipped["undated"] += 1
                continue
            stamp = stamp.astimezone(tz)
            day = stamp.date()
            if day < since or (until is not None and day > until):
                continue
            uuid = rec.get("uuid")
            if isinstance(uuid, str):
                if uuid in seen:
                    result.skipped["duplicate_record"] += 1
                    continue
                seen.add(uuid)
            if system_injected(rec):
                result.skipped["system_injected"] += 1
                continue
            body = text.strip()
            if not body:
                result.skipped["empty"] += 1
                continue
            if body.startswith(SKIP_PREFIXES):
                result.skipped["skipped_prefix"] += 1
                continue
            week = week_start(day)
            if body.startswith(DISPATCH_PREFIX) or DISPATCH_MARKER in body:
                result.weeks[week].add_dispatch(session)
                result.projects[project].add_dispatch(session)
                result.total.add_dispatch(session)
                continue
            if len(body) > MAX_TYPED_CHARS:
                result.skipped["too_long_paste"] += 1
                continue
            found = classify(body)
            result.weeks[week].add_typed(session, found)
            result.projects[project].add_typed(session, found)
            result.total.add_typed(session, found)
            if keep_text:
                result.explain.append((stamp, body, found))
    return result


# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------

def week_rows(result):
    """One row per week from the first to the last week that has data."""
    if not result.weeks:
        return []
    first, last = min(result.weeks), max(result.weeks)
    rows, week = [], first
    while week <= last:
        tally = result.weeks[week] if week in result.weeks else Tally()
        rows.append(tally.row("week", week.isoformat()))
        week += dt.timedelta(days=7)
    return rows


def project_rows(result):
    ordered = sorted(result.projects.items(),
                     key=lambda kv: (-kv[1].typed, kv[0]))
    return [t.row("project", name) for name, t in ordered]


def format_table(rows, first):
    headers = [first] + COLUMNS
    body = []
    for row in rows:
        cells = [str(row[first])]
        for col in COLUMNS:
            val = row[col]
            if col == "prodding_share":
                val = "-" if val is None else "%.1f%%" % val
            cells.append(str(val))
        body.append(cells)
    widths = [max(len(headers[i]), *(len(r[i]) for r in body))
              for i in range(len(headers))]
    lines = []
    for cells in [headers] + body:
        parts = [cells[0].ljust(widths[0])]
        parts += [c.rjust(w) for c, w in zip(cells[1:], widths[1:])]
        lines.append("  ".join(parts))
    return "\n".join(lines)


def snippet(text, bucket):
    flat = " ".join(fold(text).split())
    if len(flat) <= EXPLAIN_SNIPPET_CHARS:
        return flat
    span = bucket_span(bucket, flat)
    start = 0
    if span:
        start = max(0, min(span[0] - 15, len(flat) - EXPLAIN_SNIPPET_CHARS))
    return flat[start:start + EXPLAIN_SNIPPET_CHARS]


def explain_snippets(result, bucket):
    """The most recent matched snippets for one bucket."""
    hits = [(s, t) for s, t, found in result.explain if bucket in found]
    hits.sort(key=lambda h: h[0])
    return [snippet(t, bucket) for _, t in hits[-EXPLAIN_MAX_SNIPPETS:]]


EXPLAIN_WARNING = ("WARNING: --explain prints snippets of personal transcript "
                   "text. Do not paste this output into a public place.")


def parse_day(value):
    try:
        return dt.date.fromisoformat(value)
    except ValueError:
        raise argparse.ArgumentTypeError("expected YYYY-MM-DD, got %r" % value)


def build_parser():
    p = argparse.ArgumentParser(
        prog="Measure-Prodding.py",
        description="Count how many typed turns in Claude Code transcripts "
                    "were prodding agents versus giving new work. Prints "
                    "counts only; no transcript text unless --explain is used.")
    p.add_argument("--since", type=parse_day,
                   help="first day to count, YYYY-MM-DD (default: 28 days ago)")
    p.add_argument("--until", type=parse_day,
                   help="last day to count, YYYY-MM-DD, inclusive (default: no limit)")
    p.add_argument("--projects-dir", type=Path,
                   default=Path.home() / ".claude" / "projects",
                   help="transcript root (default: ~/.claude/projects)")
    p.add_argument("--json", action="store_true", help="print JSON instead of tables")
    p.add_argument("--by-project", action="store_true",
                   help="add a table with one row per project directory")
    p.add_argument("--explain", choices=BUCKETS, metavar="BUCKET",
                   help="print up to %d snippets (%d chars each) matched by "
                        "one bucket. Shows personal text; off by default."
                        % (EXPLAIN_MAX_SNIPPETS, EXPLAIN_SNIPPET_CHARS))
    p.add_argument("--baseline", type=Path, metavar="PATH",
                   help="write the totals row as JSON to PATH")
    p.add_argument("--force", action="store_true",
                   help="let --baseline overwrite an existing file")
    p.add_argument("--utc", action="store_true",
                   help="date turns in UTC instead of local time")
    return p


def main(argv=None):
    if hasattr(sys.stdout, "reconfigure"):
        try:
            sys.stdout.reconfigure(errors="replace")
        except (OSError, ValueError):
            pass
    args = build_parser().parse_args(argv)
    tz = dt.timezone.utc if args.utc else None
    today = dt.datetime.now(tz).date()
    since = args.since or (today - dt.timedelta(days=28))
    until = args.until
    if until is not None and until < since:
        print("error: --until is before --since", file=sys.stderr)
        return 2
    if not args.projects_dir.is_dir():
        print("error: projects directory not found", file=sys.stderr)
        return 2
    if args.baseline is not None and args.baseline.exists() and not args.force:
        print("error: baseline file exists; use --force to overwrite",
              file=sys.stderr)
        return 2

    result = collect(args.projects_dir, since, until, tz,
                     keep_text=args.explain is not None)
    weeks = week_rows(result)
    totals = result.total.row("week", "total")
    zone = "UTC" if args.utc else "local time"
    skipped = dict(sorted(result.skipped.items()))
    projects = project_rows(result) if args.by_project else None
    snippets = (explain_snippets(result, args.explain)
                if args.explain else None)

    if args.json:
        out = {"since": since.isoformat(),
               "until": until.isoformat() if until else None,
               "timezone": zone, "files_read": result.files,
               "weeks": weeks, "totals": totals, "skipped": skipped}
        if projects is not None:
            out["projects"] = projects
        if snippets is not None:
            out["explain"] = {"bucket": args.explain, "warning": EXPLAIN_WARNING,
                              "snippets": snippets}
        print(json.dumps(out, indent=2))
    else:
        print("Prodding meter: %s to %s, %s, weeks start Monday"
              % (since.isoformat(), until.isoformat() if until else "now", zone))
        print()
        print(format_table(weeks + [totals], "week"))
        if projects is not None:
            print()
            print(format_table(projects + [result.total.row("project", "total")],
                               "project"))
        print()
        print("transcript files read: %d" % result.files)
        if skipped:
            print("not counted: " + ", ".join("%s=%d" % kv for kv in skipped.items()))
        if snippets is not None:
            print()
            print(EXPLAIN_WARNING)
            print("bucket '%s': %d snippet(s)" % (args.explain, len(snippets)))
            for s in snippets:
                print("  | " + s)

    if args.baseline is not None:
        base = dict(totals, since=since.isoformat(),
                    until=until.isoformat() if until else None)
        try:
            with open(args.baseline, "w" if args.force else "x",
                      encoding="utf-8") as fh:
                json.dump(base, fh, indent=2)
                fh.write("\n")
        except FileExistsError:
            print("error: baseline file exists; use --force to overwrite",
                  file=sys.stderr)
            return 2
        print("baseline written: %s" % args.baseline, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
