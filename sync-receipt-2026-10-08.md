# Upstream integration receipt: 2026-10-08

## Scope and immutable inputs

Source-only candidate, stacked on PR #42. PR #41 and #42 keep their branches and heads.
No merge of a pull request, installation, release, daemon restart, host linking, or live qualification is included.

- Fork parent / PR #42: `036afbab00fdd15c350c2d1b843c5bdbe7b0580e`.
- Upstream parent: `9afa898d78a32ee6cfda88ee4671b7b5a16e205e`.
- Previous upstream integration / common ancestor: `4d463682a07c9bbd965c266eb1d57368e9682a58`.
- Branch: `hermes/sync-upstream-2026-10-08`, isolated worktree.
- Reviewed integration tree: `9d1328b217a3c102e4a411de1e75a666429bbacf`.
- Post-review application tree is unchanged. The only subsequent integration change removes duplicate/trailing blank lines in root `AGENTS.md`; tree before adding this receipt: `53fd2d56c61f4602e6e6e9bb93cd9abe7e23abfc`.

The integration retains both parents with a merge commit. Do not squash away upstream ancestry when eventually merging this sync.

## Integration choices

- Adopt upstream's coherent engine contract, readers, live transport, runtime-profile, model-control, and screen refactor rather than selectively cherry-picking coupled pieces.
- Preserve the fork's Windows/WSL path and argv boundaries, local-mode recovery and revision-scoped supervision.
- Preserve local Grid profile identity, stale-target rejection without cloud namesake fallback, local-target cloud-readiness bypass, and unsupported-engine refusal.
- Combine start-tick process identity with boundary-faithful argv evidence. Add a clock-step / reused-PID regression.
- Combine DSH killed-job output filtering with stream-aware shell noise filtering, cancellation barriers and the stop trap. Add a mocked-child regression. Retain tmux security specs; explicitly guard POSIX-only fixtures on Windows.
- Combine upstream decision-model filtering with local-profile capabilities and empty states. Add desktop regressions for decision-only profiles and namesake rejection.
- Adopt upstream's creation-picker labels (`Your models`, `Shared with you`). This is a source-level UX adoption, not a new installed UI.

## Executed validation

Host: native Windows. Node `v26.7.0`; Flutter `3.47.2`; Dart `3.13.2`.
Node differs from upstream CI's `22.23.2` pin. CLI dependencies were installed only in the isolated worktree with `npm ci --no-audit --no-fund` (exit 0).
Desktop `pubspec.yaml` and `pubspec.lock` are unchanged from the fork parent. Existing Flutter dependency caches were reused, with the package root and vendored xterm path rebound to the candidate; no Flutter dependency download was performed.

Commands run in `cli/`:

```text
npm run typecheck
npm run bundle
```

Both exited 0. Bundle emitted `dist/cli.js` and `dist/notify.mjs`; this is not a Windows release package or an installation.

```text
node node_modules/vitest/vitest.mjs run src/core/agents/swap.spec.ts src/core/agents/restart.spec.ts src/core/agents/retarget.spec.ts src/services/fleet.spec.ts src/services/models.spec.ts src/lib/jevRouter.spec.ts src/lib/newAgentModel.spec.ts src/lib/pathContainment.spec.ts src/engines/codex/portableHistory.spec.ts src/core/engines src/engines/registry.spec.ts src/engines/hooks.spec.ts src/engines/live.spec.ts src/engines/worker/runtimeRequests.spec.ts src/engines/worker/screenRequests.spec.ts src/engines/worker/modelControlRequests.spec.ts src/lib/terminalRuntime.spec.ts --maxWorkers=2 --reporter=json --outputFile=<scratch>/harness-sync-native-integration.json
```

Exit 0: **398 passed, 0 failed, 0 skipped**. The earlier narrower 164-test evidence is superseded by this run, not added to its count.

```text
node node_modules/vitest/vitest.mjs run src/dsh/shell.spec.ts src/lib/tmux.spec.ts --reporter=json --outputFile=<scratch>/harness-sync-native-shell.json
```

Exit 0: **103 passed, 0 failed, 18 skipped**. Windows skips do not qualify POSIX execution.

Commands run in `desktop/`:

```text
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub --reporter expanded test/new_harness_models_test.dart test/grid_model_picker_test.dart test/local_cli_discovery_test.dart test/local_mode_test.dart test/windows_runtime_test.dart test/windows_backend_path_test.dart
```

Analyze exited 0: **44 informational lints, no errors or warnings**. Informational lints remain; a strict default analyze pass is not claimed.
Focused tests exited 0: **194 passed, 2 skipped**.
An initial test command incorrectly named nonexistent `test/backend_path_test.dart`; that run exited 1 on file loading. The corrected run above uses `test/windows_backend_path_test.dart`.

`git diff --cached <upstream-parent> --check` exits 0 after root guidance whitespace cleanup. The full diff against the fork parent still reports whitespace imported unchanged from upstream in other files; those were not rewritten.
A static scan of fork additions over upstream found no literal secret assignments or unsafe Python execution. Its lone `exec` match was a regular-expression `.exec()` in a test fixture, not execution of input.

## Broader native CLI sample: not passing

The same five-file sample was run against candidate and both pinned parents using temporary profile/state roots and scratch parent snapshots. Parent snapshots reused the candidate dependency installation, so this compares source under one toolchain, not each parent's independent lockfile installation.

```text
node node_modules/vitest/vitest.mjs run src/architecture.spec.ts src/lib/registry.spec.ts src/lib/gridProfiles.spec.ts src/lib/engineLaunch.spec.ts src/backendSocket.gridReads.spec.ts --maxWorkers=2 --reporter=json --outputFile=<scratch>/<revision>.json
```

| Source | Exit | Passed | Failed | Skipped |
| --- | --- | --- | --- | --- |
| Candidate | 1 | 87 | 168 | 4 |
| Fork parent / #42 | 1 | 82 | 166 | 4 |
| Upstream parent | 1 | 85 | 157 | 4 |

Programmatic comparison found **no candidate failing test name absent from both parents' failure sets**. This is failure-name attribution, not proof of identical causes or a passing integration. Failures include missing `/bin/sh`, native Windows file-mode/security assumptions and architecture assertions. These checks remain red and require POSIX validation and any necessary separate baseline repairs before readiness or merge.

## Independent review and remaining gates

Claude Fable (`claude-fable-5-1`, subscription-direct SDK provider) returned fail-closed JSON with `passed: true`, empty `security_concerns` and `logic_errors`, for integration correctness of the scoped Windows/local Grid/DSH seams at the reviewed tree. The reviewer compared both parents and checked preserved fork deltas. It did not execute tests or review every imported upstream file.

The desktop discovery rewrite raised in review has now been exercised by the passing focused Flutter run. The following are still open:

- POSIX backendSocket specs, DSH/tmux and restart/retarget/swap execution. WSL has tmux but Linux Node was unavailable on PATH; no runtime installation was performed.
- Full CLI and desktop suites, CLI coverage gates, backend/mobile/TUI/website/firmware/OS validation and platform-native checks for imported upstream changes.
- Upstream CI toolchain confirmation, hosted component CI, Windows packaging, isolated packaged smoke, real-account compatibility and rollback qualification.
- Existing `cline` gaps in Grid/subscription maps are not repaired in this integration.

Keep this PR draft. Scoped review approval and focused checks justify publishing a source candidate, not merge readiness or an installed-version claim. Review stops for this pass at the scoped integration verdict; readiness requires the open validation gates above. After #41 and #42 are merged, retarget this sync only with explicit stack coordination and refreshed base/head evidence.
