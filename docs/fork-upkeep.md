# Keeping the Windows fork current

This fork is [mcs-eng/autonomous-harness](https://github.com/mcs-eng/autonomous-harness),
based on [autonomous-ai/openharness](https://github.com/autonomous-ai/openharness).
Use a manual source inspection and one reviewable change per pass. Source integration,
Windows packaging, installed version, and runtime qualification are separate results.
This guide does not install a scheduler or authorize activation.

## Inspect before choosing work

Read [the fork instructions](../CLAUDE.md), [contributing](../CONTRIBUTING.md),
[development](development.md), and the [Windows quickstart](../desktop/WINDOWS_QUICKSTART.md).
Record the source checkout's HEAD, remotes, dirty/untracked files and worktrees. Preserve
another session's branch, pending review and local notes. Honor any deployment freeze.
Check [open fork PRs](https://github.com/mcs-eng/autonomous-harness/pulls) and recent merges
before creating a sync branch; a local branch or old PR body may be stale.

Windows development host (PowerShell), in the existing source checkout; read-only:

```powershell
git remote -v
git status --short --branch
git rev-parse HEAD
git worktree list --porcelain
```

Do subsequent work in a fresh clone or task-owned worktree. A separate clone avoids
changing shared refs/worktree metadata when another session owns the source checkout.
Verify the two public identities above before fetching. Capture immutable revisions;
if lookup fails, freshness is unknown.

Windows development host (PowerShell), in that isolated clone, with Git 2.38 or newer:

```powershell
git fetch --no-tags https://github.com/mcs-eng/autonomous-harness.git main:refs/remotes/verified-fork/main
if ($LASTEXITCODE -ne 0) { throw 'Fork fetch failed' }
git fetch --no-tags https://github.com/autonomous-ai/openharness.git main:refs/remotes/verified-upstream/main
if ($LASTEXITCODE -ne 0) { throw 'Upstream fetch failed' }
$forkHead = git rev-parse verified-fork/main
$upstreamHead = git rev-parse verified-upstream/main
$commonBase = git merge-base $forkHead $upstreamHead
if ($LASTEXITCODE -ne 0) { throw 'No common base established' }
git rev-list --left-right --count "$forkHead...$upstreamHead"
git diff --stat $commonBase $forkHead
git diff --stat $commonBase $upstreamHead
git merge-tree --write-tree --name-only $forkHead $upstreamHead
$simulationExit = $LASTEXITCODE
```

The counts are **fork-only, upstream-only** ancestry counts; they are not counts of
unique customizations. Save both heads, common base, command output and exit codes in
a fresh local receipt. `merge-tree` writes Git objects in the isolated clone but creates
no integration branch or merge commit. Exit 0 means no textual conflicts; exit 1 means
conflicts, not a passing candidate. Other failures leave the comparison incomplete.
Neither result exercises the application.

## Preserve the fork's behavior

Use the fork diff from the common base, recent PRs, and the quickstart to map overlapping
changes. Pay particular attention to Windows/WSL account and path selection, local-mode
entry and sign-out, projects/Continue working, local-profile model routing, embedded
viewers, terminal copy/interrupt behavior, and the matched desktop/CLI packaging path.
Keep the regression tests for those contracts. A clean textual merge alone cannot prove
they survived; taking every conflicted file from one side can discard working behavior.

Prefer a bounded upstream batch with retained ancestry when integration is the selected
task. Resolve overlapping behavior deliberately and review the integration diff against
both parents. Reuse an existing sync PR rather than opening a competing one. If the
chosen pass repairs evidence or documentation, leave application integration for its
own reviewed change.

## Keep validation claims attached to revisions

- Run the checks required by the touched packages. Record OS, tool versions, command,
  exit code, tested SHA/tree, passes, failures and skips. Reproduce failures on the exact
  baseline in the same environment before calling them inherited; timing alone is not proof.
- Reuse old evidence only for an unchanged relevant tree and applicable environment.
  A different head or a green workflow badge alone is insufficient. State checks not run.
- For Windows changes, use [the existing packaging script](../desktop/scripts/build-windows-release.sh)
  and quickstart. Match desktop, bundled WSL CLI, source/version stamps and archive checksum.
  Do not bypass failing gates with `ALLOW_TEST_FAILURES=1` just to obtain a green label.
- Qualify the candidate with disposable Windows and Linux state before considering a live
  switch. Normal startup may restore saved agents. Isolated startup does not prove
  real-account compatibility or persistent-state downgrade safety. Preserve the complete
  known-good bundle; binary rollback and state rollback require separate evidence.

## Evidence snapshot: 2026-10-06

The inspected fork main was `786133139dc5ff41388db5899f841e87374cc02c` (PR #40, same tree as
`sync/upstream-2026-10-04` at `5bbabbdcc`). Upstream main was
`4d463682a07c9bbd965c266eb1d57368e9682a58`. Their common base is
`6bcdafb16db6a9790fc9b3b79a0ac55f807878fd`. There were **141 fork-only / 243
upstream-only commits** and **25 conflicted paths**. No fork PR was open.

The pass continues on `sync/upstream-2026-10-06` (worktree `.worktrees/sync-2026-10-04`),
cut from the merged sync tip. Upstream's service split is kept. The fork keeps Windows
path containment (`within` / Codex rollout `..\` rejection), boundary-faithful grid
assignment, local Grid profiles, and the Jev task-router opt-in. CLI `tsc --noEmit` was
clean. Focused vitest: portable history, path containment, new-agent model, restart,
retarget, swap, fleet, and models — 155 tests, then a 90-test rerun after expectation
fixes, all passing. Full CLI suite, Flutter, packaging, push, and a PR were not run.

## Evidence snapshot: 2026-10-04

The inspected fork main was `ac2a8a865a6b0f86753e4fd7b4997555d5cf5655`; upstream main
was `6bcdafb16db6a9790fc9b3b79a0ac55f807878fd`. Their common base is unchanged:
`7debeb1750fbb1625158876819ba14b29e0a0211`. There were **127 fork-only / 426
upstream-only commits** and **51 conflicted paths** in the object-only merge simulation
(exit 1). No fork PR was open at inspection.

The 2026-10-04 pass integrated the batch on branch `sync/upstream-2026-10-04` (worktree
`.worktrees/sync-2026-10-04`, HEAD `6a4819cdb`): merge commit `c1d3a004c` plus three
repair commits (`dccd2a0bb`, `c53b1783b`, `6a4819cdb`). Validation on Windows 11:
CLI typecheck clean; cli suite 7369 pass / 1326 fail vs baseline 6112 / 1158 (delta is
upstream-new specs red on Windows, an inherited class); `flutter analyze` 0 errors /
0 warnings; desktop suite 534 files in six chunks — all regressions fixed or classified
against baseline and the upstream parent, with 5 inherited reds recorded
(`buffered_log_test` NUL path; 4 `linux_app_image_test` quoting-on-Windows). Behavior
adoptions logged in `sync-receipt-2026-10-04.md` (unattended in-app installs,
discoveryReady non-gating, picker empty-open layout, harness→agent share copy,
colorScheme.error check row). This pass did not package, install, publish or PR.

## Evidence snapshot: 2026-10-02

The inspected fork main was `2c347db6079603ced7085282cba02c65d0b1ed34`; upstream main
was `3d3c81b33a38d59d36a396ec584a3a24bd58c6cd`. Their common base is
`7debeb1750fbb1625158876819ba14b29e0a0211`, integrated by
[PR #31](https://github.com/mcs-eng/autonomous-harness/pull/31).
There were **125 fork-only / 268 upstream-only commits** and **44 conflicted paths**
in the object-only merge simulation (exit 1). No fork PR was open at inspection.
Refresh these facts next pass; this snapshot is not a claim that a runner is active.

[PR #26](https://github.com/mcs-eng/autonomous-harness/pull/26) merged on September 29.
Its 45 CLI / 17 desktop / 6 mobile failures describe that older head and environment.
Later [PR #31](https://github.com/mcs-eng/autonomous-harness/pull/31) records passing
CLI validation, and [PR #32](https://github.com/mcs-eng/autonomous-harness/pull/32)
records **4,533 Windows desktop passes, 42 existing skips and zero failures**.
Do not carry the older desktop failures forward as current blockers or infer a newer
mobile pass. [PR #36](https://github.com/mcs-eng/autonomous-harness/pull/36) adds
Windows selection-copy/otherwise-interrupt behavior and held-key protection;
[PR #37](https://github.com/mcs-eng/autonomous-harness/pull/37) fixes connection-test waits.
Their scoped checks do not by themselves establish a new installed Windows build.

End each pass with the exact next action, owner and evidence location in the existing
upkeep handoff. If nothing is running, say so. Keep scheduling/cadence decisions with
that owner; do not create a second upkeep task, board or automation. A source pass does
not authorize publishing, paid CI, installation changes, daemon restarts or host linking.
