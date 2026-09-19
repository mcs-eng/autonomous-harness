# Engines

Harness never wraps an agent. It reads the transcript the agent already writes and installs the
vendor's own hooks or plugin to learn when a turn starts and ends. Your credentials stay in your
`~/.claude`, `~/.codex`, and so on.

| Engine | Binary | How Harness follows it | Resume | Auto-approve | Grid |
|---|---|---|---|---|---|
| Claude Code | `claude` | hooks in `~/.claude/settings.json` + JSONL transcript | `--resume` | `--permission-mode auto` | yes |
| Codex | `codex` | `hooks.json` per `CODEX_HOME` + JSONL rollouts | `resume` | `--approve-for-me` | yes |
| Cursor | `cursor-agent` | `~/.cursor/hooks.json` + transcript | `--resume` | `--force` | — |
| OpenCode | `opencode` | plugin + SQLite | `--session` | `--auto` | yes |
| Pi | `pi` | extension + transcript | `--session` | — | yes |
| Hermes | `hermes` | hooks + SQLite | `--resume` | — | yes |
| Command Code | `cmd` | hooks + transcript | `--resume` | — | — |
| Devin | `devin` | hooks + SQLite | — | — | — |
| Muse Code | `muse` | transcript | `resume` | — | — |
| Amp | `amp` | plugin writes the transcript Harness tails | `threads continue` | — | — |
| Kilo | `kilo` | plugin + SQLite | `--session` | — | — |
| Grok Build | `grok` | hooks + `updates.jsonl` | `--resume` | — | yes |
| Antigravity | `agy` | hooks + transcript | `--conversation` | — | — |
| GitHub Copilot | `copilot` | hooks + transcript | `--resume` | — | yes |

**Auto-approve** is the default permission mode for a new harness: the engine's own auto mode, not its
skip-every-check flag. New Harness ▸ Advanced offers the engine's other modes (`PERMISSION_MODES` in
`cli/src/lib/engineLaunch.ts`).

A launcher that hands the pane to one of these is that engine: `ori claude` is a Claude Code agent,
and the daemon reads the gateway off the live process so recaps and routing go through it too.

**Grids.** An agent can be pointed at an [Autonomous Grid](https://www.autonomous.ai/grid) relay
instead of the engine's own login, at creation or later with **Retarget**, which respawns the same
pane with the grid's environment and `--resume`. The engines marked above support it; the key travels
in the tmux session environment, never in argv or a file. Needs tmux ≥ 3.2.

## Additional options in the Windows fork

New Agent includes experimental options with different capabilities:

| Option | Interface | Current integration |
|---|---|---|
| Cline | Terminal pane in WSL | Interactive CLI and process discovery. Approval prompts stay enabled. Harness conversation history, turn status and automatic session resume are not supported. |
| DeepSeek Harness | Official browser workspace | Starts an already-installed `dsh` in a chosen WSL distribution and existing project folder. Harness can reopen its browser and stop its server. Conversations and provider setup belong to DeepSeek. |
| ZCode | Installed Windows desktop app | Opens the official app on this PC. Choose the workspace and authenticate in ZCode. It does not create a Harness terminal pane. |

The DeepSeek and ZCode entries appear only for this PC on Windows. They are companion apps, not remotely managed engines; their conversations are not sent to Jev or another Harness agent. Other machines' existing engine choices are unchanged.

### DeepSeek Harness

Install the official preview in the WSL distribution you intend to use, with Node 22.19+ in the 22 series, or Node 24+:

```sh
npm install -g @deepseek-ai/dsh@0.1.5-rc.2
```

Choose **DeepSeek Harness** in New Agent, select that distribution and an existing project folder, then choose **Start and open browser**. The server binds to `127.0.0.1` on an available port. Its browser login URL stays in memory, not in Harness settings or diagnostics. Closing the dialog leaves the server running; return to the same option for **Open browser** or **Stop server**. Default WSL localhost forwarding is required.

This uses the vendor's [official Web UI](https://deepseek.com/harness/en/), not a terminal-UI plugin. DeepSeek manages its own credentials, permissions, providers and sessions. Setup does not authenticate an account or submit a model task for you.

### ZCode

Install the [official ZCode desktop app](https://zcode.z.ai/en/docs/install) in its normal per-user Windows location. The launcher opens that installation without copying its credentials to WSL. The inspected desktop 3.14.0 bundle contains CLI 0.16.9, but its advertised terminal interface lacks `@zcode/tui`; an unofficial repackaging is not silently substituted. A future embedded integration needs the vendor's app-server protocol and explicit approval/session handling.

### Cline

The terminal option uses the [official Cline CLI](https://github.com/cline/cline/tree/main/apps/cli). Complete authentication interactively in Cline inside WSL. Cline's CLI normally auto-approves tools; Harness explicitly launches with `--auto-approve false`. The initial integration does not parse Cline's versioned JSON session files as JSONL or guess which concurrent session belongs to a process.

These additions are fork features. They are separate from the Windows-support submission upstream.
