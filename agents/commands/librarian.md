---
description: Run the read-only Librarian check (profile hashes, hook paths, hook errors, worktrees, scheduled tasks, folder sizes) and summarize the findings with receipts.
---

Run the Librarian check and report its findings. The script is read-only; it never moves or deletes anything.

1. Run, on the local Windows host (Windows PowerShell 5.1):

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<checkout>\agents\librarian\Invoke-LibrarianCheck.ps1" $ARGUMENTS
```

Replace `<checkout>` with the path of the autonomous-harness checkout on this machine. Pass `-SkipSizes` for a fast run; omit it for the folder-size section.

2. Quote the exit code. 0 means clean, 1 means findings, 2 means the script failed.

3. Report the findings list exactly as printed, then one line per section. Do not propose moves or deletions; a finding that needs the owner becomes one manifest row in the filing standard's shape, on the custody card for the estate hour.

4. If the profile hashes changed since the previous run, say which file and stop: that is a trip-wire, and the current PR cannot go ready until it is explained.
