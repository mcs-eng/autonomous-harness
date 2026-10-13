# Librarian check

`Invoke-LibrarianCheck.ps1` is the Librarian role for an agent team on a Windows machine. It reports on the agent plumbing so that no agent has to ask the owner where the disk went, or find out days later that a hook has been failing. It reports and nothing else: it never moves, deletes, prunes, or edits anything.

It runs on Windows PowerShell 5.1 (it also runs on PowerShell 7). The file is ASCII, saved as UTF-8 with a byte-order mark and CRLF line endings.

## Run it

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\agents\librarian\Invoke-LibrarianCheck.ps1
```

Add `-SkipSizes` for a quick run (a few seconds). The full run measures folder sizes and took about one minute on the machine it was built on.

## What it may touch

- Reads: files under the profile folder, the transcript folder, the dev root, the watched size roots, and the scheduled task list.
- Runs only these git commands, always as `git -c core.fsmonitor=false -C <path> --no-optional-locks ...` (the fsmonitor setting is forced off, so no helper program a repository might configure can run): `worktree list --porcelain`, `status --porcelain`, and `log -1 --format=%cI <commit>`. No fetch, no prune, no write.
- Writes only to `-StateDir` (`latest.json`, `previous.json`) and, when given, to `-OutFile`. The `-OutFile` parent folder must exist, and a file that already exists outside `-StateDir` is refused with exit 2 before anything is written.
- Skips any checkout with `FROZEN-DEPLOYMENT.md` at its root and any folder whose name starts with `_Quarantine_`. It runs no git there and does not measure them. It lists them as "skipped by rule".
- Prints no file contents from transcripts or settings. Output holds paths, hashes, counts, and dates only. Hook commands appear in the JSON as SHA-256 hashes, not as text.

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `-DevRoot` | `$HOME\dev` | Repositories are its immediate child folders that contain a `.git` file or folder. |
| `-ProfileDir` | `$HOME\.claude` | The agent profile folder. |
| `-Hours` | `24` | Transcript window for the hook error scan. |
| `-StateDir` | `$env:LOCALAPPDATA\LibrarianCheck` | The only folder the script writes to. Created if missing. |
| `-SkipSizes` | off | Skip the folder size measurement. The cheap DevRoot layout check still runs. |
| `-SizeTopN` | `8` | How many of the largest child folders to show per watched root. |
| `-SizeFileCap` | `0` (no cap) | Stop counting a folder after this many files and mark its size as a lower bound. |
| `-RegisterFile` | none | A Markdown file whose table rows start with a backtick-quoted task name, for example a first cell of `` `\TaskName` ``. Any non-Microsoft task not named there is reported. |
| `-OutFile` | none | Also write the Markdown report to this file. |
| `-Json` | off | Print the JSON result to stdout instead of Markdown. |

## Exit codes

- `0`: no findings.
- `1`: one or more findings.
- `2`: the script itself failed. This includes an unknown parameter, a bad number, or a missing `-RegisterFile`. The state files are written last, after every check and after the output path is validated, so a run that fails writes nothing.

## Output

The Markdown report starts with the list of findings. Each finding is one line with its receipt: the path, the hash, the count, or the command that proves it. A section per area follows, then the summary line `Findings: N. Exit code: X.`

The JSON result holds the same data in structured form. It is saved as `latest.json` in the state folder on every run. Before the new one is written, the old `latest.json` is copied to `previous.json`. Each run compares itself with the run before it, so a postflight run reads against its preflight.

## Sections

1. **Profile files.** SHA-256 of `settings.json`, `settings.local.json`, `CLAUDE.md`, and `kernel.md` under the profile folder, whichever exist. A hash that differs from the previous run is a finding.
2. **Hooks.** Parses `hooks` in `settings.json` and in `settings.local.json`. From every hook command it extracts each absolute path ending in `.mjs`, `.js`, `.ps1`, `.py`, `.sh`, `.cmd`, `.bat`, or `.exe`, and each folder given to a `--*-dir` option or to `git -C`. It handles single quotes, double quotes, escaped backslashes, forward slashes, `%VAR%`, `$HOME`, `~`, Git Bash `/c/...` paths, and commands nested inside `-Command "..."` or `bash -c '...'`. A missing path is a finding, with the events that use it. It also reports the number of hook blocks and commands per event.
3. **Hook errors in recent transcripts.** Scans every `*.jsonl` under `projects\<project>\` (including subagent transcripts) modified within `-Hours`. It counts hook error records: lines with the unescaped pair `"type":"hook_non_blocking_error"`, and lines with `MODULE_NOT_FOUND` that are hook records (they have an unescaped `"hookEvent"` key). Conversation text that only mentions these words is JSON-escaped, so it is counted separately and is not a finding. A file with one or more error records is a finding.
4. **Worktrees.** For each repository, lists the linked worktrees with branch (or "detached"), last commit date, dirty file count, and whether the path lies in an allowed nest: `<repo>\.claude\worktrees\`, `<repo>\.worktrees\`, `$HOME\.codex\worktrees\`, or `<DevRoot>\_wt\`. Findings:
   - a worktree path missing on disk;
   - a worktree outside every allowed nest;
   - a detached worktree whose last commit is older than 7 days and that has 0 dirty files (eligible for a manifest row);
   - a folder in `<repo>\.claude\worktrees\` or `<repo>\.worktrees\` that git does not list (unregistered);
   - a retired nest (`<DevRoot>\worktrees` or `<DevRoot>\<name>-worktrees`) that is not empty.
5. **Scheduled tasks.** Every task outside `\Microsoft\`, with state, last run time, last result, and whether the action's program and script paths exist. Findings:
   - an enabled task whose last result is not 0x0, 0x41301 (running), or 0x41303 (never run);
   - an action path that is missing;
   - with `-RegisterFile`, a task the register does not name. Account SIDs in task names are matched in either their real or redacted form (`S-1-5-21-<redacted>-1001`).
6. **Folder layout and sizes.** Layout: any child of the dev root that is not a repository, a worktree nest, `Archive`, `Tools`, or `_wt` is a finding. Sizes, measured unless `-SkipSizes` is given, cover each child folder of these roots when they exist: `<ProfileDir>\projects`, `$env:APPDATA\Claude`, `$HOME\.codex`, `$HOME\Documents\Codex`, and the dev root. Each folder is classed as `app-managed`, `repo`, `worktree-nest`, `evidence`, `scratch`, or `unclassified`. Findings:
   - an `unclassified` folder over 1 GB;
   - a folder that grew by more than 5 GB since the previous run (only when the previous run measured sizes).

   Junctions, symbolic links, and other reparse points are not followed, and unreadable folders are counted and skipped.
7. **Summary.** Notes, the seconds each section took, and `Findings: N. Exit code: X.`

## Limits

- Growth is compared only with the run immediately before. If that run used `-SkipSizes`, growth is not compared.
- Cloud placeholder folders (for example OneDrive files on demand) are reparse points, so they are not measured.
- A program named without a path in a scheduled task is looked up through the current `PATH`, which can differ from the task's own environment.
