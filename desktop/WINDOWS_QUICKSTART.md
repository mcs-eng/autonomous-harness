# OpenHarness for Windows 11 — community preview

This is an independent, MIT-licensed fork of Autonomous's OpenHarness. It is not an
official Autonomous Windows release. The native Windows interface uses a Linux
CLI and tmux inside WSL2. Your coding agents still require their own accounts.

## Download and start

1. Download the Windows x64 ZIP and its `.sha256` file from
   [this fork's releases](https://github.com/mcs-eng/autonomous-harness/releases).
2. Extract the entire ZIP to a permanent local folder. Keep `Release/harness.exe`,
   `data`, the DLLs, and `harness-cli` together. Do not run it inside the ZIP.
3. Open `Release/harness.exe`. The preview is unsigned; Windows may warn about an
   unknown publisher. Review the source and checksum before deciding to run it.
4. Follow the setup screen, then select **Sign in** and finish in your browser.
5. Create a project and agent. Install and authenticate the coding agent in the
   selected development distribution if its engine is missing. Prefer native Linux
   agent installations; WSL interop discovery is also supported.

To compare the downloaded archive with its checksum in Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\harness-desktop-windows-x64-1.0.0-windows.5.zip
Get-Content .\harness-desktop-windows-x64-1.0.0-windows.5.zip.sha256
```

## Prerequisites

Windows 11 x64, virtualization enabled, internet access, and a WSL2 Ubuntu
development distribution are required. If WSL is absent, run this in an elevated
Windows PowerShell and finish Ubuntu's user setup after any requested restart:

```powershell
wsl --install -d Ubuntu
```

Docker Desktop's internal distributions are excluded. Setup installs tmux and the
managed Linux Node runtime through the upstream installer. The app runs the
**matching CLI included in this ZIP**, with its automatic updates disabled; it
does not replace your standalone `harness` launcher. Keep this folder in place
while the app or its agents are running.

## Replacing an older preview

Preview 3 includes the terminal typing fix, repairs Claude installation when
WSL inherits Windows npm without Linux Node, and replaces broken Copilot npm
launchers with a verified native installation. Preview 1 can display agent output
while rejecting keyboard text; replace the complete bundle to receive both fixes.
Preview 4 adds **Open in browser** to viewer panes, including Grid's fleet dashboard.
Preview 5 adds isolated local fleets to compatible agents' model pickers and moves
recurring engine discovery off the daemon's main event loop.

Close the old Harness window. If a previous Harness daemon is running, stop that
daemon from its WSL distribution (`harness stop`) before opening the new preview.
This stops the connection service; do not kill your tmux sessions or delete
`~/.harness`. Existing authentication and session data stay in the distribution.
Then open the new extracted `Release/harness.exe`, not an old shortcut or an
executable under a build scratch directory.

If your previous panes are absent, choose **Open Harness** and select an existing
agent to attach it to the current tab. Repeat for the remaining agents. The saved
tab arrangement and the agent sessions are separate; creating a new Store workspace
does not reopen an existing one or inherit its fleet configuration.

## Additional agent options in preview 3

Choose these from **New Agent** on this PC:

- **Cline** runs its official CLI in a terminal pane with approval prompts enabled.
  Complete provider setup in Cline. This preview does not provide Harness history,
  turn tracking, grid routing, or automatic session resume for Cline.
- **DeepSeek Harness** opens its official browser workspace. First install
  `@deepseek-ai/dsh@0.1.5-rc.2` in your chosen WSL distribution using
  `npm install -g @deepseek-ai/dsh@0.1.5-rc.2` with Node 22.19+ (22.x) or 24+.
  Then select an existing project folder and **Start and open browser**. Return to
  the same option to reopen the browser or stop the server. Closing Harness stops
  that server and its tool processes.
- **ZCode** opens the [official Windows app](https://zcode.z.ai/en/docs/install),
  installed separately. Select your workspace and provider inside ZCode.

DeepSeek and ZCode run beside Harness; their conversations and approvals remain
in their own applications. They are not Harness task-routing targets.

The September 15 prototype loses WSL command arguments and can show **Bad state:
Sign-in did not complete**. Retrying sign-in in that old executable cannot fix it.

## Grid and other Store viewers

The upstream **Grid** harness (`autonomous/autonomous-grid`) is available from
**Store → Grid → Install/Open**. It uses Codex and the Grid toolchain in your WSL
distribution to inspect connected machines, model placement, and fleet telemetry.
Install and authenticate Codex there before starting the agent.

On Windows, choose **Open in browser** in the viewer pane. Keep Harness and the
workspace running while using the dashboard. Viewer addresses can change after a
restart; use the pane's button again instead of a saved browser bookmark. Viewers
are embedded in Harness on macOS; Windows and Linux use the external browser.

Connect your own Grid before expecting live fleet data. Installing this package
does not deploy models or enroll your GPU machines automatically.

### Local fleets in the model picker

Preview 5 can register an existing isolated Grid home without changing the default
remote/cloud profile. In the WSL distribution used by Harness, run the bundled CLI
with its managed Node runtime. Replace the release path, profile home, and fleet
name below with your existing configuration:

```sh
# Inside the selected WSL distribution (bash)
node_path="$(cat "$HOME/.harness/runtime/current-node")"
"$node_path" "/mnt/c/path/to/Release/harness-cli/cli.js" grid profile set local-fleet \
  --label "My local fleet" --home "$HOME/.harness/grid-fleet/local" --grid my-fleet
```

The profile home must already exist. Open the model dropdown at the top of a
compatible agent pane and choose the model under that local fleet. Registration
does not install models, start a fleet, or prove an agent can complete a turn.
Local Grid 0.3.47 provides OpenAI-compatible inference, so this preview offers it to
engines such as Codex and OpenCode; Claude Code's remote Grid options are separate.
The daemon resolves endpoints and credentials from registered profiles; the picker
sends the profile's opaque identity, never a caller-supplied endpoint or key.

To reopen a configured fleet dashboard, use **Open Harness** and select its existing
workspace. A newly created Grid workspace may show an empty fleet until connected.
Codex may display its own update prompt in the adjacent terminal; that prompt is
separate from the dashboard and can be skipped to continue with the installed version.

## Preview limitations and recovery

- Windows desktop and bundled CLI updates are manual: download a new complete ZIP.
- WSL2 Ubuntu with normal Windows localhost forwarding is the supported setup.
  Other distributions, custom networking and clean-machine configurations require
  further validation. This preview is not a broad Windows compatibility guarantee.
- Keep the terminal focused when typing. If another client owns input, choose
  **Take control**. Some shortcuts still use the Windows/Meta key; Ctrl+Tab and
  Ctrl+Shift+Tab switch panes.
- Use the backend folder browser for Linux projects. Drive conversion assumes
  WSL's normal `/mnt/<drive>` mounts.
- See [agent verification](WINDOWS_AGENT_VERIFICATION.md) for tested versions and
  the distinction between executable startup and authenticated model turns.
- Roll back by closing this preview, stopping its daemon, and opening your previous
  complete bundle. Do not delete authentication, projects, or tmux sessions.

Report a problem at the fork's issue tracker with the preview version,
`source-commit.txt`, Windows/WSL versions, and redacted error text. Do not upload
credentials, authentication files, or unredacted logs.
