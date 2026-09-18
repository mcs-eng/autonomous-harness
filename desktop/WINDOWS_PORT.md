# Windows 11 migration

## Community preview delivery (2026-09-18)

The public preview packages the Windows desktop and the CLI from the same source
checkout. `WINDOWS_BUNDLED_CLI=true` makes the application require the adjacent
`harness-cli/cli.js` and `notify.mjs`; it executes them with the selected WSL
distribution's managed Node runtime. Both upstream CLI automatic updates and
Windows desktop update polling are disabled for this package. User authentication,
projects, and tmux sessions remain in WSL. Installation and replacement instructions
are in [WINDOWS_QUICKSTART.md](WINDOWS_QUICKSTART.md).

The September 15 ZIP was never refreshed after the September 17 argument fix.
Running that old executable made CLI commands return help instead of JSON and
caused `Bad state: Sign-in did not complete`. A source push was not an installed
fix. Use the new complete release bundle, not the old extracted executable.

Shared resume discovery now treats flattened process arguments as a hint only:
the engine store and the observed process's open transcript must corroborate the
same session. Processes without that evidence remain unbound until an authoritative
hook or other session signal arrives. This is not a claim of full macOS qualification.

The records below describe earlier prototypes and retain their historical results;
their statements that the CLI is unchanged or that packaging is unfinished do not
describe this preview's source. Windows signing, automatic updates, and clean-machine
qualification remain outside the preview's claims.

This branch migrates the Windows desktop prototype to the active `autonomous-ai/autonomous-harness` repository at `86ad284603fe5beccf3ba9c9ee18db567ad3d0b1`. It retains the monorepo's MIT license and its current desktop, CLI, and backend layout. It is an unsigned development prototype, not an upstream Windows release.

## Scope

The Flutter interface runs on Windows; the intended agent runtime is the existing Harness CLI and tmux inside a named WSL2 development distribution. This preserves the current CLI architecture instead of adding a second terminal backend.

The migration keeps upstream's setup plan and agent-creation receipt flows. Windows-specific changes cover CLI discovery, distribution selection, setup instructions, process deadlines, backend folder selection, and packaging. The CLI, backend, provider, release workflows, and vendored terminal implementation are unchanged.

- Docker Desktop distributions are excluded from probes and installation.
- Read-only preflight presents a setup plan. Automatic setup is an explicit user action; Recheck does not install components. Distribution installation and Linux user creation remain attended steps.
- A failed tmux installation stops before CLI installation. Version and prerequisite probes bound their wait for an owned child's exit and output streams; a timeout requests termination and returns exit code 124. This does not establish termination of every Linux descendant of `wsl.exe`.
- A WSL identity remains tied to its backend filesystem. New-project creation uses the backend, and Windows paths in agent or Codex-profile requests are converted or refused before dispatch. Creation retries retain upstream's receipt-based status lookup.
- Windows bundles contain the complete Flutter release directory, app-local MSVC runtime files, the repository license, and the vendored xterm license. The packaging script checks the portable checksum and archive contents, and reports native import-inspection failures.

## Validation method

The comparison uses an untouched worktree at the same upstream commit and an isolated user profile for each checkout, with Flutter 3.47.2 and Dart 3.13.2 on Windows 11 x64. Source checks are separate from running a signed-in desktop session. Full-suite failures are retained, including failures already present in upstream's Windows baseline.

Results on 2026-09-15:

| Check | Untouched upstream | Migrated source |
| --- | --- | --- |
| Dependency resolution | Exit 0 | Exit 0 |
| `flutter analyze` | Exit 1: 12 informational notices | Exit 1: the same 12 informational notices, no errors or warnings |
| `flutter test` | Exit 1: 1,515 passed, 13 skipped, 64 failed | Exit 1: 1,580 passed, 13 skipped, 64 failed |
| Windows-specific, bounded-process, and project-creation test files within the full suite | Not a separate upstream group | 65 passed, no skips or failures |
| Packaging fault fixtures | Not present upstream | Six cases passed; fixture runner exit 0 |
| `flutter build windows --release` | Initial isolated-environment attempt exited 1 | Exit 0 with the corrected build environment |
| Unsigned ZIP, portable checksum, contents, MSVC import closure, and license files | Not packaged | Verified; packaging command exits 2 because the test suite is failing |

Of the candidate's 64 failed test names, 63 also failed in the original full baseline. The remaining name, `startSupervising never spawns over a daemon that answers but is not ready`, reported a scratch-directory teardown `PathAccessException`; the same cleanup error reproduced in both a focused pristine-file run and an isolated pristine-test run. The baseline project-folder failure that did not repeat is not claimed as a fix. An earlier complete run of the same application source recorded 1,581 passed and 63 failed; the terminal-input timing failure returned in the packaging run and is also present in the original baseline. This comparison identified no newly attributable test regression, but the full suite remains failing.

The initial native build attempts were affected by the validation environment: long generated paths and redirected Windows profile directories caused MSBuild FileTracker errors, which CMake summarized as a missing C++ compiler. Compiler probes passed with a short checkout alias and the normal build profile. The failed first configure also retained CMake's default system install prefix; clearing that generated cache entry restored this project's intended in-build bundle destination. No CMake source change was needed. Keep tests isolated, use a short checkout path for native builds, and avoid redirecting the Windows build profile wholesale.

The final command was `ALLOW_TEST_FAILURES=1 bash scripts/build-windows-release.sh`, with the pinned Flutter tool and Python provided through the documented environment overrides. It produced `dist/harness-desktop-windows-x64-1.0.0.zip` and its portable `.sha256` file. The archive has 51 entries, including 37 under `Release/data/`. `dumpbin` verified the MSVC-family imports of the executable and bundled DLLs. Its exit code 2 preserves the failed test result; it is not a green release verdict.

### 2026-09-15 follow-up session (Windows 11 host)

Toolchain brought up per this document's constraints: Flutter 3.47.2 / Dart 3.13.2 extracted to a short path (`C:\flutter`), VS Build Tools 18.10 with the C++ workload already present under `Program Files (x86)`, WSL 2.7.13 with Ubuntu 24.04 installed (Docker's distributions present and excluded by design). The native release build needed no workaround on this host — `flutter build windows --release` exited 0 on the first attempt.

| Check | This session |
| --- | --- |
| Dependency resolution | Exit 0 |
| `flutter analyze` | Exit 1: the same 12 informational notices, 0 errors, 0 warnings |
| `flutter test` | Exit 1: 1,641 passed, 13 skipped, 62 failed (baseline: 1,580 / 13 / 64) |
| `flutter build windows --release` | Exit 0 |
| Packaging + bundle verification | 51 entries (37 `Release/data/`), portable sha256 checked, contents and MSVC import closure verified; script exit 2 with `ALLOW_TEST_FAILURES=1` (suite not green) |
| Release exe smoke test | Launched, stayed up, exited cleanly |

Two Windows test-harness fixes were made this session, both in `desktop/test/`: `support/real_fonts.dart` gained `%WINDIR%\Fonts` candidates (arial/cour, with segoeui/consola fallbacks) after the macOS/Linux candidates, which lets ten render-test files start on Windows; and three `environment_provisioner_test.dart` assertions that syntax-check generated Linux scripts via `/bin/bash -n` are now skipped where that interpreter cannot exist. macOS/Linux candidate precedence and the POSIX checks themselves are unchanged. The change was reviewed independently by `gpt-6-astra` through `codex exec --sandbox read-only` (ChatGPT subscription seat), returning passed with no security or logic findings under the fail-closed contract.

Accounting for the failure-count change: the two fixes removed 14 named failures. One flaky timing test (`terminal input batches…`) passed on this run and is not claimed as a fix. Letting the font-loading files run revealed 12 deeper failures in `entry_surfaces_render_test.dart` (palette/text-scale matrix). The bulk of the remaining 62 names fail at this commit on any OS: they still assert the pre-redesign New Agent dialog (`new-agent-folder` InkWell, `⌘N` add-agent binding) that upstream commits `bd147b9`–`86ad284` replaced with choice tiles. They are upstream test debt, and reproducing them on macOS remains the way to confirm that.

One test run was invalidated by a concurrent move of its generated build directory; another was stopped before completion to include the last identity fix. Neither partial run contributes to the final counts above. The reported full suite ran with exclusive ownership of the build directory.

## Remaining work

The next functional milestone is an attended session using a development distribution: finish setup, sign in, create a project and agent, exchange terminal input/output, reconnect, and verify that files are created in the selected backend. That complete workflow has not been established by this migration's unit and widget tests.

### 2026-09-17 session — attended live loop completed (this milestone)

The functional milestone above was executed end to end on the Windows 11 host with the `Ubuntu` (26.04) distro. Every step ran through the shipping product paths; the only human steps were the SSO browser approval and one model-switch confirmation.

| Step | Result |
| --- | --- |
| Setup / distro selection | `Ubuntu` selected (Docker distributions excluded per scope); CLI installed to `/root/.local/bin/harness` |
| Sign in | `harness login --force --json` → loopback callback caught from the browser SSO flow (2m24s, attended) |
| Daemon | `harness start` → connected (self-updated v0.2.43 → v0.2.55 mid-flight; later replaced by the patched local build below); `/api/status` reachable from Windows loopback; machine/computer IDs bound |
| Project + agent creation | New Agent dialog → engine probe against "Arya · This machine" → backend folder `/root/harnesses/codex-2026-09-17-08-20` created, tmux session `harness-codex-1789647626896` registered |
| Terminal output | xterm renders the live Codex TUI (v0.154.0) streamed by the daemon over the local WS; keyframe/output flow verified by wire capture |
| Terminal input | Keystrokes delivered, executed, and answered by the agent ("harness wsl input works" turn completed; session auto-titled "Verify WSL terminal input"); model switched astra→luna via the `/model` TUI over the same path |
| Reconnect | `harness stop` + `harness start` with the app open → app returned to home without crashing; agent reopened, session state intact (Take control → controlling) |

**Product bug found and fixed — engines resolved through WSL interop were invisible to the daemon (`deddb44`).** With interop on, the pane shell's `command -v codex` resolves to the Windows npm shim, so the engine runs as Windows `node.exe` relaid under `/init` (`comm=node.exe`, `/proc/pid/exe → /init`, entrypoint `…/@openai/codex/bin/codex.js`). `lookupPaneEngineProcess` scored that row 0, the launch stayed `failed` ("did not expose an engine process"), and `acceptsInput` stayed false — the terminal **silently refused every keystroke while the TUI visibly ran**. Root cause was confirmed by a loopback wire capture (only `terminal_ack`/`terminal_alive` frames during typing; zero HTRL input frames) plus direct `/proc` inspection. The fix rewrites interop rows in `repairMangledRows` from `/proc/<pid>/cmdline` (drops `/init`, de-duplicates node's `process.title` rewrite, quotes space-bearing Windows paths so `argvTokens` re-splits them) and lets `processEntrypoint`'s interpreter set accept `.exe`. A regression test pins both halves: the raw `ps` row still scores 0, the repaired shape scores 2 via the codex package entrypoint. CLI vitest on this host: 2,002 passed / 252 failed / 77 skipped vs a clean-tree baseline of 259 failed — the fix flips 7 previously-failing specs and breaks none; the remainder are pre-existing POSIX-host artifacts.

**Known limitation (client-side, open):** physical keyboard → xterm delivery on Windows is unreliable when the window is not foreground, and UIA/PostMessage automation cannot reach the Flutter xterm at all. The daemon input path itself is proven good (the protocol-level driver above exercised the exact binary input protocol the app uses). The single-controller lease also shows "Take control" whenever another client (or a second window) holds the pane — clicking it hands the lease over; keystrokes are refused silently until then.

Windows release installation, signing, self-update, and a clean-machine launch remain separate work. Windows shortcut conflicts, media paths, and other filesystem-sensitive features need platform validation. Drive conversion assumes WSL's conventional `/mnt/<drive>` mounts; use the backend folder browser for custom mounts.

macOS and Linux builds and their native integration tests have not been run on their respective operating systems during this migration. Retaining their source paths is not evidence of passing those platform checks.
