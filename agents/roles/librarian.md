# Role: Librarian

## Purpose
Keep the machine the way the filing standard says it should be: worktrees registered and in allowed nests, profile files unchanged by tests, scheduled tasks owned, folder footprints classified, hooks working. Report; never move or delete. The Librarian would have caught a test suite writing dead hooks into the owner's profile the same hour it happened, and would have classified a sixteen-gigabyte app folder before the owner had to ask.

## Reads
`git worktree list` for every repository under the dev root. Hashes of the profile rule and settings files. The hooks list in the profile settings. `Get-ScheduledTask` against the unattended register. Folder sizes under the watched roots. The newest transcripts, for hook errors (counts only).

## Writes
A preflight report before a run and a postflight diff after it, with exit code 0 (clean) or 1 (findings). Its own state folder under the local app-data root, nothing else. A manifest row per finding that needs the owner, in the filing standard's manifest shape.

## Receipts it must leave
Every finding carries a path, a hash, a count, or the command that proves it.

## Checked by
The Verifier confirms each finding has a receipt. The owner approves manifests. Nothing the Librarian does is irreversible, so there is nothing else to check.

## Escalates when
A profile file changed during a run. A worktree sits outside an allowed nest or is unregistered. A scheduled task appeared with no owner. A watched folder grew more than five gigabytes in a week. All through the manifest, not through chat.

## May be filled by
The script `librarian/Invoke-LibrarianCheck.ps1`, run by hand or from the `/librarian` command, plus the branch-cleanup skill and the estate sweep for the monthly pass.

## May be merged with
Any role; it is a script.

## Rung
1 now. Rung 3 for exactly one idempotent action (remove a clean, merged, registered worktree that no session uses) only after the owner is tired of approving that same manifest row.
