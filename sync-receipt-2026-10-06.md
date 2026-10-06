# Upstream sync pass receipt — 2026-10-06

## Immutable revisions

- Fork main HEAD: `786133139dc5ff41388db5899f841e87374cc02c` (merge of PR #40; same tree as `5bbabbdcc`)
- Upstream main HEAD: `4d463682a07c9bbd965c266eb1d57368e9682a58`
- Common base: `6bcdafb16db6a9790fc9b3b79a0ac55f807878fd`
- Ancestry counts: 141 fork-only / 243 upstream-only
- Open fork PRs at inspection: none
- Integration branch: `sync/upstream-2026-10-06` in worktree `.worktrees/sync-2026-10-04`
- Object-only merge simulation exited 1 with 25 conflicted paths

## What this pass kept

- Upstream's move of the daemon body into `core/` and `services/`.
- Windows path containment: transcript checks go through `pathContainment.within`, and Codex
  rollout rejection treats `..\` as a climb.
- Boundary-faithful argv for grid assignment on restart and retarget (`restartedGridAssignment`).
- Local Grid profiles: picker short-circuit, launch/move target ids, profile CLI, docs.
- `TASK_ROUTER=jev` opt-in, now in `services/fleet.ts` ahead of the standard ranker.

## Validation

- Windows 11, `npm run typecheck` in `cli/`: exit 0.
- `npx vitest run` of portableHistory, pathContainment, newAgentModel, restart, retarget, swap,
  fleet, models: 155 passed, then 90 passed on the three files re-run after expectation fixes.
- Not run: full CLI suite, `flutter analyze`, desktop suite, packaging, push, PR.

## Next action

Review the merge diff against both parents, then push `sync/upstream-2026-10-06` and open the
sync PR. Do not package or install from this branch until that review.
