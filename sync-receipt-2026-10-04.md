# Upstream sync pass receipt — 2026-10-04

Pass owner: Kimi Work session (source-inspection + integration pass, no publish authorization).

## Immutable revisions

- Fork main HEAD: `ac2a8a865a6b0f86753e4fd7b4997555d5cf5655`
- Upstream main HEAD: `6bcdafb16db6a9790fc9b3b79a0ac55f807878fd` (autonomous-ai/openharness)
- Common base: `7debeb1750fbb1625158876819ba14b29e0a0211` (same as 2026-10-02 snapshot)
- Ancestry counts: 127 fork-only / 426 upstream-only (was 125 / 268 on 2026-10-02)
- Open fork PRs at inspection: none (github.com/API, 2026-10-04)
- Main-checkout dirty state: untracked `blind-review-plan.txt`, `docs/reviews/` — another
  session's notes, preserved untouched.

## Merge simulation

- Command: `git merge-tree --write-tree --name-only ac2a8a86... 6bcdafb1...`
- Exit code: 1 (conflicts present — expected, not a passing candidate)
- Simulated tree: `9196433fec2f02e2a43067604c2de261095e433e`
- Conflicted paths: 51 total — see `merge-sim-output.txt` in the main checkout
  (`.worktrees\sync-2026-10-04-merge-sim.txt`).

Conflict shape vs 2026-10-02 snapshot (44 paths then):

- 49 content conflicts (add/add AGENTS.md; the rest content)
- 2 modify/delete: `cli/src/lib/summarize.ts` (+ its spec) deleted upstream, modified on fork
- 1 modify/delete: `desktop/test/harness_session_manager_test.dart` deleted upstream, modified on fork

## Work products of this pass

- Integration branch: `sync/upstream-2026-10-04` in worktree `.worktrees/sync-2026-10-04`
- Commits on the branch (fork main `ac2a8a86` → branch HEAD `6a4819cdb`):
  - `c1d3a004c` — merge of `7debeb1750..6bcdafb16`, 51 conflicted paths resolved
    (Windows behavior contracts preserved; see fork-upkeep.md)
  - `dccd2a0bb` — CLI merge fallout: await fork's async refreshApiLaunch, restore jevRouter
    import, union tmux token cursor, spec deps for restartedGridAssignment,
    self-contained grid profile fixture test
  - `c53b1783b` — CLI test alignment: tmux spec --continue, escape-aware argv prefix
    folding, backend socket fixture self-contained
  - `6a4819cdb` — Flutter merge fallout: widget repairs, upstream behavior adoptions,
    Windows test hermeticity (full message in commit)
- Validation evidence: below. Classification used two reference worktrees:
  baseline = fork HEAD `ac2a8a86` (`.worktrees/baseline-2026-10-04`), upstream parent
  `c1d3a004c^2` (`.worktrees/upstream-check`). Judgment: green on baseline/upstream and
  red on the merge → real regression (fixed); red on both → inherited (recorded).

## Validation — CLI (Windows 11, node via repo toolchain)

- `tsc --noEmit` (cli): clean, exit 0 (baseline identical).
- Full cli test suite (vitest): baseline **6112 pass / 1158 fail**; merged **7369 pass /
  1326 fail**. Upstream added ~1500 tests; the ~168 additional failures are upstream-new
  specs red on a Windows host (inherited class), failure rate 15.0% → 15.7%.
- Known single inherited red: `tmux.spec` "brackets every submitted message..." — red on
  baseline too.

## Validation — desktop (Windows 11, Flutter 3.47.2 / Dart 3.13.2, `C:\Flutter\flutter`)

- `flutter analyze`: **0 errors, 0 warnings** (36 infos, all pre-existing in
  third_party xterm).
- Full test suite, 534 files in 6 parallel chunks (`--concurrency=4`):
  - chunk 1: 1150 pass, 10 skip, 1 fail — `buffered_log_test` NUL path (baseline red:
    inherited, not fixed)
  - chunk 2: 1013 pass, 15 skip, 0 fail after fixes
  - chunk 3: 1064 pass, 9 skip; 2 regressions fixed (icon catalogue, discoveryReady),
    4 remaining fails in `linux_app_image_test` — upstream-new file; upstream's Exec
    quoting triggers on Windows backslash temp paths (inherited class, recorded)
  - chunk 4: 756 pass, 5 skip; 18 fails (sidebar trailing overflow) fixed by the 32px
    AppIconButton budget, re-verified green
  - chunk 5: 907 pass, 3 skip; 3 regressions fixed (share dialog harness→agent rename,
    Linux alt-workspace-prefix chords, picker full-width at empty open), re-verified green
  - chunk 6: 844 pass, 15 skip, 0 fail
- Fixed files re-run individually and green: environment_setup 12, desktop_search_polish 37,
  resource_picker 27, link_machine_dialog 13, local_cli_discovery 40 (+2 skip),
  project_sidebar 26, project_creation_navigation 2, share_harness 17,
  swarm_arrange_keyboard 5, swarm_picker_activation 4, new_agent_* 73,
  bootstrapping/web_viewer/workspace_resume 16.

## Behavior adoptions recorded (upstream decision taken over stale fork copy)

- First-run install: in-app plans now run unasked after the read-only probe; only
  Terminal-password plans wait on Install (upstream; old fork opt-in test dropped).
- `discoveryReady: false` no longer gates daemon readiness (upstream cold-start perf).
- Desktop picker: full-width results at empty open; 11:14 list/preview split after
  selection (upstream).
- Share dialog: "harness" → "agent" copy rename (upstream).
- `_CheckRow` failed color: `colorScheme.error` over the stale `AppColors.danger`
  (4.40:1 vs the 4.5 floor; upstream's deliberate change).

## Not run / not authorized

- No Windows packaging run, no install/activation, no push, no PR. Publishing stays
  with the owner per CLAUDE.md.

## Next action

Owner reviews `sync/upstream-2026-10-04` (diff vs `ac2a8a86`), then pushes and opens the
sync PR. Reference worktrees can be removed after review:
`git worktree remove .worktrees/baseline-2026-10-04` and `.worktrees/upstream-check`.
