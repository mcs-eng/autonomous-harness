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
4. Follow the setup screen, then either select **Sign in** and finish in your
   browser, or select **Use this computer without an account** for
   [local mode](#local-mode-no-account).
5. Create a project and agent. Install and authenticate the coding agent in the
   selected development distribution if its engine is missing. Prefer native Linux
   agent installations; WSL interop discovery is also supported.

To compare the downloaded archive with its checksum in Windows PowerShell:

```powershell
Get-FileHash -Algorithm SHA256 .\harness-desktop-windows-x64-1.0.0-windows.7.zip
Get-Content .\harness-desktop-windows-x64-1.0.0-windows.7.zip.sha256
```

## Projects sidebar (source builds after Preview 7)

The sidebar switches between **Projects** and the existing **Machines** view.
Choose a session to return to its existing tab, or reopen its view if closed.
Project headings expand the list without starting agents. Non-Git folders work
too; repositories with multiple checkouts list each host and working folder.

**Add folder** saves an existing location. **New project** opens the creation
dialog; its folder is created only when you submit. The **+** beside a location
opens **New agent here** with that exact machine and folder preselected, in a new
tab. Shared or disconnected hosts cannot create agents from this action.
On Windows with WSL, the folder picker browses the selected distribution.

Rows show branch and current activity, including **Needs input**, **Start failed**,
and **Offline**. Closing a view keeps its agent running; stopping remains a
separate **Stop** action. The sidebar button opens a drawer in narrow windows.
Narrow pane headers retain Model, Viewer, Stop, and Close controls when available;
other actions move into **More pane actions**. Tab and Enter operate the navigation
controls without taking terminal input.

This source change does not update an installed Preview 7 bundle or desktop shortcut.

### Getting back to work and recovering

An empty tab now shows **Continue working** with up to three existing sessions,
their machine, folder, branch, and current state. Sessions needing input appear
first; your visits during this app session come next. **Needs your input** opens
the existing attention list. Opening a session reuses its existing view and does
not create, restart, or send instructions to an agent. Search and the Harness
Store remain available. A new installation keeps the introductory start page.

Unavailable project sessions now explain the problem and offer **Refresh status**
or **Show machines**. Agent selection shows installation status even in a narrow
window. Installed does not mean signed in or funded. DeepSeek and ZCode explicitly
open their separate browser/desktop workspaces; a successful handoff closes the
managed-agent draft, while cancellation preserves it.

Startup identifies the sign-in check and offers **Try again** when it cannot read
the saved session, rather than assuming you signed out. A failed local-service
start reconnects through the existing supervisor. Sign-out or window disposal
invalidates pending checks, so late replies cannot restart the service or change
old session views. Windows preflight reuses its verified WSL result for the version
check: fixture process calls fall from six to four, while rechecks still discover
afresh and validate the packaged CLI. This is not a measured launch-time claim.

These changes improve explicit project and agent choice. They do not automatically
route tasks between providers, share credentials, or add model-server load.

### Recovering an existing Linux installation

If setup suddenly reports a missing CLI after changing Ubuntu's default user,
the existing installation may belong to a different Linux account. In setup,
choose **Change Linux account**, turn off **Use WSL default accounts**, then
select the distribution and enter the account that owns that installation.
The same choice is under **Customize OpenHarness → Terminal**.

Save, close, and reopen OpenHarness. The selected distribution and account are
used together for tool checks, CLI commands, project folders, and machine
identity. Saving never switches an active session. This preference does not
change WSL's default user, copy credentials, or migrate project files. Select
`root` only when deliberately reconnecting to an existing root installation;
agents in that account have administrator access inside the distribution.

An unavailable selected account/distribution is an error, not permission to
switch to another installation. A timed-out or malformed tool check shows
**Not checked** with **Recheck** rather than an install action. A confirmed
missing CLI no longer incorrectly marks an available tmux as missing.

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
Preview 6 also includes the upstream review's Unicode WSL distribution-name fix.
Preview 7 fixes native Windows project-folder creation and incorporates upstream
`0e00e2bb` (September 19): updated harness identities, viewer changes, and the
Store's listed/unlisted distinction. Withdrawn experimental presets stay hidden;
existing installed workspaces are retained. Jev Sheets and the Isolated Web Viewer
are the new listed packages in the bundled catalog. Their own setup and account
requirements still apply; inclusion in the catalog is not live qualification.
The next preview's CLI also stops showing bash's own `no job control` and `logout`
lines in package doctor and setup output when the daemon runs without a terminal,
as it does under WSL, and a timed-out doctor, setup, or workspace init now ends the
whole script rather than only the command that was running.

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

Current Windows source builds embed Grid and other Store viewers beside their
terminals using Microsoft Edge WebView2. Click inside the page to interact with
it; click a terminal or another app control to return keyboard focus. The pane
header provides **Reload viewer**, **Open viewer in browser**, zoom, and close.
Closing a viewer releases its browser surface and leaves the agent running.

Keep Harness and the workspace running while using the dashboard. Viewer
addresses can change after a restart; the pane follows the current address.
If the embedded browser cannot start, use **Retry** or **Open in browser**.
Windows 11 normally includes the [WebView2 Runtime](https://developer.microsoft.com/microsoft-edge/webview2/);
the app reports when it is missing and does not install it silently. Older
Windows previews and Linux retain the external-browser fallback.

The embedded viewer uses its own browser profile, separate from your regular
browser. Popups and device permissions (camera, microphone, location, clipboard
reads, and notifications) are denied; use the external browser for pages that
need them. Ordinary page navigation and downloads follow WebView2 behavior;
downloads show a notice in the pane. No native command bridge, filesystem
mapping, or disabled browser security is added. The Windows plugin is pinned in
`pubspec.lock`; its WebView2/WIL build packages use the public NuGet feed in
`desktop/nuget.config` without changing global NuGet settings.

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

## Local mode (no account)

The login screen offers **Use this computer without an account**. The app then
runs the bundled CLI with `HARNESS_LOCAL_ONLY=true` (forwarded into WSL through
`WSLENV`, never as an argument): the daemon starts on this computer's own id,
never dials the Harness backend, installs no grid, and lists this computer as
its one machine. Everything on this PC works as it does when signed in: create
agents, attach terminals, switch panes. The choice is remembered across
launches in `state.json` beside the theme.

What needs the account stays off until you sign in: other machines, linking,
shared harnesses, the Harness Store, and the signed-in profile. The account
menu and Settings say **Local mode** and offer **Leave local mode**, which
stops the local daemon and returns to the login screen; signing in there ends
local mode, because the CLI lets a saved sign-in win over the flag and the app
agrees with it.

Only the CLI included in this ZIP knows the flag. The upstream launcher does
not, and a remembered local mode against it returns to the login screen with a
sentence saying so. From a WSL terminal, the same daemon is
`HARNESS_LOCAL_ONLY=true harness start`; `harness auth status --json` then
answers `localOnly: true`, and `harness status` reads `local mode, no account`.

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
