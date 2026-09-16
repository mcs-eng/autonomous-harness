# Windows 11 migration

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

Windows release installation, signing, self-update, and a clean-machine launch remain separate work. Windows shortcut conflicts, media paths, and other filesystem-sensitive features need platform validation. Drive conversion assumes WSL's conventional `/mnt/<drive>` mounts; use the backend folder browser for custom mounts.

macOS and Linux builds and their native integration tests have not been run on their respective operating systems during this migration. Retaining their source paths is not evidence of passing those platform checks.
