# Measure-Prodding

A weekly bottleneck meter for an agent team.

`Measure-Prodding.py` reads Claude Code session transcripts and counts how many
of the owner's typed turns were spent prodding agents instead of giving new
work. Prodding means approving, nudging, checking a claim, routing work,
re-supplying context, fixing tooling, or pasting the output of a hand step. The
team uses the share of prodding turns to judge itself: if agents were doing
their job, the owner would have less to say between the first request and the
finished work.

The script uses only the Python standard library. It reads transcripts and
prints counts. It writes nothing unless you pass `--baseline`.

## Run it

```
python -I Measure-Prodding.py
python -I Measure-Prodding.py --since 2026-09-20 --until 2026-10-12
python -I Measure-Prodding.py --json
python -I Measure-Prodding.py --by-project
python -I Measure-Prodding.py --baseline baseline.json
python -I Measure-Prodding.py --explain approve
```

Always use `-I` (isolated mode) so Python does not load stray modules from the
current directory.

| Option | Meaning |
| --- | --- |
| `--since YYYY-MM-DD` | First day to count. Default: 28 days ago. |
| `--until YYYY-MM-DD` | Last day to count, inclusive. Default: no limit. |
| `--projects-dir PATH` | Transcript root. Default: `~/.claude/projects`. |
| `--json` | Print the same data as JSON. |
| `--by-project` | Add a table with one row per project directory. |
| `--explain BUCKET` | Print up to 20 matched snippets of at most 60 characters. Shows personal text. |
| `--baseline PATH` | Write the totals row as JSON to PATH. Refuses to overwrite unless you add `--force`. |
| `--utc` | Date turns in UTC. Default is the machine's local time. |

Run the tests with `python -I -m unittest` from this folder.

## What the output shows

One row per ISO week (weeks start on Monday), then a totals row. Weeks with no
turns between two weeks that have turns appear as zero rows.

- `sessions`: transcript files with at least one counted turn in that week. In
  the totals row this is the number of distinct sessions, not the sum of the weeks.
- `typed_turns`: turns the owner typed that the script counted.
- `dispatch`: turns that start with `User's message, verbatim:` or contain
  `Orchestrator context`. These are orchestrator wrappers, not typed turns. They
  are reported but kept out of every other column.
- `any_prodding`: typed turns that match at least one bucket, counted once.
- `prodding_share`: `any_prodding / typed_turns`, as a percent with one decimal.

A line under the table lists what was not counted, so a surprising total can be
explained: `skipped_prefix`, `too_long_paste`, `system_injected`,
`duplicate_record`, `empty`, `undated`, `bad_json_line`.

## The buckets

A turn can match several buckets, so the bucket columns do not add up to
`any_prodding`. Matching is case-insensitive and only applies to turns of 700
characters or fewer.

| Bucket | What it catches | Examples of the kind of turn |
| --- | --- | --- |
| `approve` | The owner is the approval step. | "approved", "merge 12", "yes" alone, "lgtm" |
| `nudge` | The owner is restarting stalled work. | "continue", "try again", "are you waiting on me" |
| `verify` | The owner is checking or disputing a claim. | "you said", "still failing", "it's empty" |
| `route` | The owner is choosing the repo, session, or model. | "which repo", "use sonnet", "new session" |
| `resupply` | The owner repeats context the team should have kept. | "I told you", "remember", "read the CLAUDE.md" |
| `hygiene` | The owner is fixing tooling, accounts, or quota. | "reauth", "disk", "mcp", "popups", "tokens" |
| `handstep` | The owner pastes output of a step an agent could not do. | pasted `PS C:\` prompts, "done", "ok" |
| `handoff` | The owner is leaving or returning and needs a handover. | "going to bed", "catch me up", "what's left" |

The exact patterns are in the `RULES` table at the top of the script.

Two choices in how turns are classified:

- A turn that matches `handstep` is not also counted as `hygiene`. Pasted
  output such as "Credential added" is the hand step itself, not the owner
  talking about tooling.
- Curly apostrophes are folded to straight ones, so "didn't" typed with a
  typographic apostrophe still matches.

## What counts as a typed turn

A record of type `user` whose content is a string, or a list with at least one
text block and no tool result. The script skips:

- sidechain records (subagent traffic);
- records the harness wrote: `isMeta`, compaction summaries, and records whose
  `origin.kind` is something other than `human` (peer messages, task
  notifications);
- text starting with `<task-notification`, `<system-reminder`, `/compact`,
  `[Request interrupted`, `This session is being continued`, or `<command-name>`;
- turns longer than 4,000 characters (pasted content);
- repeats: a resumed or forked session copies earlier records into a new file,
  so each record `uuid` is counted once, credited to the oldest file that holds it.

Turns are dated by the record's own `timestamp`, never by file modification time.

## Privacy rule

The script never prints transcript text by default. The tables, the JSON, the
per-project table, and the baseline file hold counts and directory names only.
Text appears only when you pass `--explain BUCKET`, which prints a warning
first and then at most 20 snippets of at most 60 characters. Treat that output
as personal: do not paste it into a pull request, an issue, or a shared channel.
The only file the meter ever writes is the `--baseline` path, which must end in `.json` and may not lie inside the projects folder. Nothing is written to the transcripts, and no network call is made.

## How the team uses the number

1. Before the team changes how it works, run
   `python -I Measure-Prodding.py --since <four weeks back> --baseline baseline.json`.
   The totals `prodding_share` in that file is the baseline.
2. Run the meter once a week and look at the weekly `prodding_share`. Use
   `--by-project` to see where the prodding happens, and `--explain BUCKET` in a
   private terminal to see which kinds of turns dominate.
3. Target: halve the baseline share within six weeks.
4. Kill criterion: if the share has not dropped by at least one third after
   three weeks of Phase 1 (the first round of changes aimed at cutting
   prodding), stop Phase 1 and rethink it instead of continuing.

## Limits to keep in mind

- It counts turns, not minutes or effort. A short "yes" and a long correction
  each count once.
- Matching is by keyword. Some turns that give new work also mention a worktree
  or a token and land in `hygiene`; some real prodding uses words no pattern
  knows. Read a sample with `--explain` before trusting a single bucket, and
  edit `RULES` if a pattern is too loose. The share is most useful as a trend
  measured with the same rules each week.
- Project names are shortened from Claude Code's directory names, which encode
  paths with dashes. The shortening is a heuristic: worktrees fold into their
  parent repo, and Claude desktop scratch workspaces fold into `claude-scratch`.
- Sessions that were deleted or never saved are invisible to the script.
