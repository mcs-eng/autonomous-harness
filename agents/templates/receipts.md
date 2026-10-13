# Receipts block

Copy into the PR body under "Test evidence", and into the card checkpoint. One line per check. A claim without a line here is an opinion.

```
RECEIPTS (head <sha>)
- <command as run> | exit <code> | baseline: <none | "<n> inherited failures on Windows per <doc>">
- <command as run> | exit <code>
- hosted CI: <run link> | <conclusion> on <sha>
- review: <reviewer harness/model> | round <n> | blockers <count> | head <sha>
- measured: <figure> from <command or file:line>
- unmeasured: <figure> (where it came from)
```

Rules:
- The head SHA is the one the PR will merge. If it changes, the block is rewritten.
- A figure that matters is marked measured or unmeasured. No third state.
- A skipped check is listed as skipped with the reason, never omitted.
