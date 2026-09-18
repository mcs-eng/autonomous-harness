https://github.com/user-attachments/assets/97848065-61c6-40df-be66-a8247f69aa4c

# Harness

> **Community Windows 11 preview:** this fork adds a native Windows desktop with
> a WSL2 backend and a matching bundled CLI. [Download the Windows preview](https://github.com/mcs-eng/autonomous-harness/releases)
> · [Setup and limitations](desktop/WINDOWS_QUICKSTART.md).
> Independent MIT-licensed fork of Autonomous's OpenHarness; not an official
> Autonomous Windows release. The upstream project is described below.

Harness is a desktop app for the coding agents you already run — Claude Code, Codex, Cursor, and
eleven more — on every machine you own, in one window. Each agent is a tmux pane on the machine it
runs on, kept there by a small daemon (`harness`). The window attaches to those panes, from this
computer or from any other, with everything between machines encrypted end to end. An optional USB
device puts the same agents on your desk.

Sessions live on the machine, not in the window. Close the laptop, open it on the train: same pane,
same scrollback.

It drives the agents you already run:

<p align="center">
  <img src=".github/assets/engines/claude.png"      height="72" alt="Claude Code"  title="Claude Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/codex.png"       height="72" alt="Codex"        title="Codex">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/cursor.png"      height="72" alt="Cursor"       title="Cursor">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/opencode.png"    height="72" alt="OpenCode"     title="OpenCode">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/pi.png"          height="72" alt="Pi"           title="Pi">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/hermes.png"      height="72" alt="Hermes"       title="Hermes">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/commandcode.png" height="72" alt="Command Code" title="Command Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/devin.png"       height="72" alt="Devin"        title="Devin">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/muse.png"        height="72" alt="Muse Code"    title="Muse Code">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/amp.png"         height="72" alt="Amp"          title="Amp">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/kilo.png"        height="72" alt="Kilo"         title="Kilo">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/grok.png"        height="72" alt="Grok"         title="Grok">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/agy.png"         height="72" alt="Antigravity"  title="Antigravity">
  &nbsp;&nbsp;
  <img src=".github/assets/engines/copilot.png"     height="72" alt="GitHub Copilot" title="GitHub Copilot">
</p>

## What you get

- **One window, N machines.** Panes from your laptop, the Mac mini at home and the box in the rack,
  side by side. Create sessions, make splits, move panes, change focus, zoom, pin, pick a layout.
- **Remote persistent sessions.** Agents run in tmux on the machine. Disconnect, reconnect, same
  session. After a reboot the daemon recreates each pane with the engine's own `--resume` and the same
  agent id, so the window comes back exactly as it was.
- **No SSH, no VPN, no open ports.** Every machine dials out to the relay over a WebSocket. A terminal
  is promoted to a direct WebRTC data channel between the two ends when ICE succeeds, and stays on the
  relay when it doesn't. The relay holds no key material and forwards ciphertext.
- **Remote directory lists and clone.** Start a session on another machine by browsing its filesystem
  from the New Harness dialog, or clone a repository into a folder there first.
- **Keyboard first.** A full default keymap, one-to-four-stroke sequences, a JSONC keymap file that
  live-reloads, and a command palette over every action. Native macOS menus follow the same keymap.
- **Agent-aware terminals.** Turn boundaries, the agent's own questions (`AskUserQuestion` and the
  engines' equivalents) surfaced and answerable from the window or the device, per-turn recaps,
  model and effort, subscription usage windows.
- **Boss mode (⌘B).** Type or say what you want. A router picks the agent already on it from the
  agents' names and their last recaps, and the text lands in that pane.
- **Fourteen engines, one rule.** Harness never wraps an agent. It reads the transcript the agent
  already writes and installs the vendor's own hooks or plugin to learn when a turn starts and ends.
  Your credentials stay in your `~/.claude`, `~/.codex`, and so on.

## Install

**macOS 12+ (Apple Silicon and Intel), Linux (Ubuntu 22.04+).** Download the app from
[harness.autonomous.ai/desktop](https://harness.autonomous.ai/desktop). On first launch it checks for
tmux, installs a managed Node 20 and the `harness` daemon under `~/.harness`, signs you in with SSO,
and starts the daemon. This computer is your first machine.

**Add another machine** — a server, a Mac mini, a container — with the daemon alone. Node ≥ 20 and
tmux are the prerequisites; `sqlite3` is needed only for the engines that keep their conversations in
SQLite (OpenCode, Kilo, Hermes, Devin).

```bash
curl -fsSL https://harness.autonomous.ai/cli/install.sh | bash
harness login      # browser SSO, saves this computer's session
harness start      # connects; reconnects to the same machine on every later start
```

It appears in the app's machine list within a minute. There is no token to copy: a durable computer
id under `~/.harness` keeps later starts attached to the same machine record.

One thing to know from the start: **the daemon only knows about panes it created.** Sessions you start
from the app or the web are tmux sessions named `harness-*`, owned by the daemon. A `claude` you launch
by hand in your own tmux is not picked up.

## The app

### Sessions

An agent is one engine process in one tmux pane on one machine. The app calls it a harness. A tab
holds any number of panes, from any mix of machines; the app remembers tabs, pane placement, sizes,
pinned slots, focus and zoom across restarts, in `~/.harness/desktop-app-v2/state.json`.

**New Harness (⌘N)** asks for four things: the machine, the working folder, the engine, and,
under Advanced, two settings most people never touch. The folder picker is the native panel on this
computer and a remote directory list on any other machine, served over the daemon's `fs_list_dir`.
**Clone repository** clones a GitHub URL into a parent folder first. The engine row shows every engine
the machine has, probes availability live, and marks the ones the daemon would install on first
launch. Advanced holds the engine's permission-bypass flag (`--dangerously-skip-permissions`,
`--dangerously-bypass-approvals-and-sandbox`, `--force`, `--auto`, whichever the engine has) and,
for Codex, a profile: a `CODEX_HOME` folder to launch under instead of `~/.codex`, each with its own
hooks.

Creation carries a receipt. If the reply is lost, the button turns into **Check status** rather than
creating a second session.

Closing a pane is a view operation; the agent keeps running. **Stop Harness** ends the engine process
and asks first. **Restart Harness** relaunches it in the same pane with the same id, resuming the
conversation where the engine supports it.

**Open Harness (⌘O)** is the search: agents, tabs, projects, machines, history and commands, fuzzy
matched, with a session preview on the right built from cached recent turns. Type `>` for commands
only (also ⇧⌘P).

### Panes and layouts

Hover the right or bottom edge of a pane for a split control, or ⌘R and ⌘D to split right and down;
both open the same picker at that position. Drag a pane's header onto another pane to swap them.
Resize grips live in the gaps and appear on hover or keyboard focus; sizes are remembered per pane
count.

**Layout (⌘S)** opens a palette of drawn shapes rather than names: Split, Columns, Rows, Main
left/right/top/bottom, Grid, 2 to 5 columns, Middle + sides, Two over three, Auto. Press ⌘S again to
cycle, a digit to pick directly, Enter to apply. A pinned pane keeps its slot when other panes close
around it.

### Keyboard

The defaults, in the workspace:

| Keys | Action |
|---|---|
| ⌘N | New Harness |
| ⌘O | Open Harness — search sessions, tabs, machines, history; `>` for commands |
| ⇧⌘P | Command palette |
| ⌘B | Boss mode: describe a task, it picks the agent |
| ⌘T · ⌘W · ⇧⌘T · ⇧⌘R | New tab · close tab · reopen last closed · rename tab |
| ⌘1 … ⌘9 | Select tab by position |
| ⇧⌘] · ⇧⌘[ · ⌃Tab · ⌃⇧Tab | Next · previous tab |
| ⌘] · ⌘[ · ⌘Y | Forward · back through visited harnesses · full history |
| ⌘H ⌘J ⌘K ⌘L · ⌘arrows | Focus the pane left · below · above · right |
| ⇧⌘arrows | Move the focused pane |
| ⌘R · ⌘D | Split right · split down |
| ⌘⏎ · ⌘; · ⇧⌘W | Zoom or restore · last pane · close pane |
| ⌘S | Layout palette |
| ⌘F · ⌘G · ⇧⌘G | Find in terminal · next · previous match |
| ⇧⌘I | Harnesses needing input |
| ⌘, · ⌘/ | Settings · keyboard shortcuts |

In a picker: ↓ ⌃N ⌃J and ↑ ⌃P ⌃K move, ⏎ opens, ⌘⏎ adds the result as a pane here, Esc or ⌃G closes.
The terminal keeps ⌘C, ⌘V, ⌘A, Esc, ⌥⏎ and ⌃C for itself. `pane.pin`, `pane.focus_1…9`,
`pane.resize`, `pane.reset_sizes`, `machine.link` and a few others ship unbound and are in the palette.

Remap anything in `~/.config/harness/keybindings.jsonc` (`$XDG_CONFIG_HOME` respected). The file is
JSONC: `{ "version": 1, "bindings": [{ "keys": "cmd+k cmd+l", "command": "pane.focus_right",
"when": "workspace" }] }`. Sequences are one to four strokes; `"command": null` unbinds a key or a
whole prefix; `when` is `workspace`, `terminal` or `picker`. The file is watched and reloaded on save;
a bad edit keeps the last good keymap and says what was wrong. **Keyboard shortcuts (⌘/)** lists the
effective bindings and **Open keyboard config** writes a commented template with every command id.

### Terminal

The renderer is a vendored, patched [xterm](desktop/third_party/xterm). Each pane has its own find bar
(⌘F). ⌘-click opens links; an image or video path in the output opens in a preview, downloaded from
the remote machine over the existing encrypted connection with progress and cancel (up to 512 MiB).
Paste or drop an image onto a pane to send it to the agent. On a remote machine a composer box under
the pane batches a message instead of paying a round trip per keystroke. Scrollback is restored from
the daemon's snapshots on attach, resize, zoom and reconnect. Font, size (⌘0, ⌘+, ⌘-), terminal
colours and six app palettes are in Settings.

### Attention, models, usage

When an agent asks a question the pane gets an amber ring, the titlebar bell lights, and ⇧⌘I lists
every harness waiting on you. Answers go back into the engine's own dialog; there is no side channel.

The **Models** menu shows each engine's subscription usage window, refreshed once a minute, for local
and remote machines alike. Settings ▸ Usage is a separate token ledger read from Claude's and Codex's
transcripts and OpenCode's database, off per provider until you switch it on.

### Machines

The app talks to the daemon on this computer over a loopback socket and never dials the relay itself.
Other machines are reached through that daemon: it links to them with a per-machine remote password,
terminates the encryption locally, and hands the app plaintext. Machines ▸ Link Machine… runs the
link flow; the CLI equivalent is under [The daemon and CLI](#the-daemon-and-cli).

## How it works

```
                                ( ◉ )   Harness device (USB)
                                  │
   ┌─────────── this computer ───────────┐
   │  Harness app ── loopback ──▶ harness daemon ──▶ tmux ──▶ claude · codex · …   │
   └──────────────────────────────┬──────┘
                                  │ WebSocket (E2EE)
                        ╔═════════╧═════════╗
                        ║   Harness Relay   ║   store and forward, no keys
                        ╚═════════╤═════════╝
          ┌───────────────────────┼───────────────────────┐
     your server             your platform            harness.autonomous.ai
   harness daemon            your HTTP API             the web client
   tmux · hermes · muse      (provider)                (paired browser)
          ▲
          └── terminal traffic goes direct over WebRTC when ICE succeeds
```

**The daemon** runs detached under your account. Every five seconds it reconciles the `harness-*`
tmux sessions with its registry; a pane has to be missing on two scans before its agent is marked
gone. It tails each agent's transcript with a byte offset (JSONL for most engines, SQLite for
OpenCode, Kilo, Hermes and Devin) and turns lines into a normalized event stream: turn started,
tool call, sub-agent, question, turn ended. Hooks it installs into the vendor CLI tell it about
session start, prompt submit and stop. Every five minutes it re-reads engine configs and pane
footers to keep model and effort right. On start it restores panes that died with the tmux server,
and it self-updates from a signed manifest, swapping the bundle atomically.

**The session model.** The registry (`~/.harness/cli/data/registry.json`, mode 0600) is the source of
truth for agents: engine, working directory, tmux pane, bound transcript, process identity. Layouts
belong to the app. The relay stores machine records, agent names and daily counters, never a
transcript, a recap or a keystroke.

**Transport.** Each daemon holds one WebSocket to the relay, authenticated with its SSO token.
Terminal bytes ride a binary channel on that socket until a WebRTC data channel negotiates, then move
to it. Encryption is on for every path and has no switch:

- **Ed25519** identity keys, pinned at first pairing and signing every ephemeral after it.
- A **CPace-style PAKE** over ristretto255 — the six-character pairing code bootstraps a shared secret
  across the untrusted relay, and an attacker gets one online guess.
- **X25519** ephemeral Diffie–Hellman per connection, through HKDF to pairwise session keys.
- A **per-process group key** so one event encrypts once for many readers.
- **ChaCha20-Poly1305** on every frame, with the associated data binding frame type and session.

The crypto core lives in [`cli/src/lib/e2ee/`](cli/src/lib/e2ee/) and is a byte-identical twin of the
browser's copy, with a drift-guard test and committed self-vectors.

## The daemon and CLI

`harness` is one pure-JS bundle run by the managed Node under `~/.harness/cli`. Everything below
works the same on a headless Linux server; the app is not required on a machine, only the daemon.

| Command | What it does |
|---|---|
| `harness login [--force] [--json]` | Browser SSO; save this computer's session. `--force` signs in as a different account. `--json` emits NDJSON for GUI clients. |
| `harness start [-f] [--repair]` | Start the daemon from the saved session. `-f` runs in the foreground for a supervisor. `--repair` re-verifies the managed Node runtime. |
| `harness stop` · `harness logout` · `harness reset` | Stop the daemon · stop and clear the SSO session · stop and clear all local state. |
| `harness status` · `harness version` · `harness update [--force]` | Running, pid, machine id, session count · version · update now. |
| `harness machines [list] [--json]` · `harness machines delete <id>` | This account's machines · remove another machine (never this one). |
| `harness pair <code>` · `harness pairings` · `harness unpair <#\|fp\|--all>` | Pair a browser with the code the web client shows; list; unpair. |
| `harness browser-link` | Print a reusable seven-day setup link for browsers. |
| `harness remote-password set\|status\|clear` | This machine's persistent password for machine-to-machine links. |
| `harness link connect <id> [--name=<label>]` · `harness link list` · `harness link unlink <id>` | Let this machine reach another of yours, terminating E2EE here; list; unlink. |
| `harness grid login [--force] [--json]` · `harness grid logout` | Sign the `grid` CLI in with this computer's account, no second browser. |
| `harness flash [flags]` | Re-flash a plugged-in Harness device over USB. Flags pass straight to the flasher. |
| `harness autonomous-device discover\|status\|list\|pair\|revoke` | Pair Autonomous OS devices found on the LAN, directly, with no relay. |

Interactive prompts read one line from stdin with `--stdin`; `--json` switches any of them to NDJSON.

The daemon also serves a loopback dashboard at `http://127.0.0.1:18473`: health, this machine's
fingerprint, paired clients, stop. It never renders a transcript. Configuration is environment
variables (`BACKEND_WS_URL`, `WEB_URL`, `ADAPTER_DATA_DIR`, `ADAPTER_COMPUTER_ID`, `PORT`, and the
per-engine home directories); [`cli/README.md`](cli/README.md) has the full table and the
`.env.example`.

## Automation

The app is one client of the daemon. Anything on the same computer can be another: the loopback
WebSocket at `ws://127.0.0.1:18473/api/local-ws` takes a `machine_select` frame first
(`{ machineId, localProtocolVersion: 1 }`, no `Origin` header), then request frames with a `requestId`
and answers them with `<type>_result`. Selecting one of your other machines proxies the request
through this daemon's link to it.

What it answers: `agents_list`, `agent_create`, `agent_restart`, `agent_retarget`, `agent_delete`,
`agent_update`, `agent_recent`, `agent_files`, `agent_read_file` (text, or media in 128 KiB chunks),
`fs_list_dir`, `engines_probe`, `codex_profiles_list`, `codex_profile_link`, `models_list`,
`usage_read`, `question_response`, `voice_route`, `message`, `cancel`, and `terminal_open` for a
binary terminal channel with scroll, resync and paste. The same frames travel from the web client
over the relay.

Engines report in over HTTP on the same port: `POST /api/hook/session-start`, `session-end`,
`turn-start`, `turn-stop`, `tool-start`, authenticated by a per-install token the daemon writes into
the hook it installs.

There is no `harness new` or `harness split` today. Sessions are created and arranged through the app,
the web client, or this socket.

## Engines

| Engine | Binary | How Harness follows it | Resume | Permission bypass | Grid |
|---|---|---|---|---|---|
| Claude Code | `claude` | hooks in `~/.claude/settings.json` + JSONL transcript | `--resume` | `--dangerously-skip-permissions` | yes |
| Codex | `codex` | `hooks.json` per `CODEX_HOME` + JSONL rollouts | `resume` | `--dangerously-bypass-approvals-and-sandbox` | yes |
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

A launcher that hands the pane to one of these is that engine: `ori claude` is a Claude Code agent,
and the daemon reads the gateway off the live process so recaps and routing go through it too.

**Grids.** An agent can be pointed at an [Autonomous Grid](https://www.autonomous.ai/grid) relay
instead of the engine's own login, at creation or later with **Retarget**, which respawns the same
pane with the grid's environment and `--resume`. The engines marked above support it; the key travels
in the tmux session environment, never in argv or a file. Needs tmux ≥ 3.2.

## The Harness device

A round 466×466 AMOLED with touch and a far-field microphone, USB-C on the bottom edge. It has no
WiFi and holds no credential. It is served entirely over the cable by the daemon on the computer it is
plugged into; plugging it in is the authorization. The wire is one USB serial device (`303a:1001`),
framed as `A5 5A | ver | type | len | payload | crc16` with a JSON vocabulary, a five-second ping,
and a hard 8 KiB frame ceiling, specified in [`docs/specs/cable-protocol.md`](docs/specs/cable-protocol.md).

What it shows: your agents as tiles in the order of the window's panes, with what each is doing and
for how long; a wheel of your machines; the agent's own question when it asks one, answerable with a
tap; the recap when a turn finishes, with one quiet tone. Scroll the face to scroll the terminal.
Double-tap and speak to send a task: the audio goes to the daemon as PCM, comes back as a transcript,
and Boss mode routes it. A voice turn can carry a mode — `/goal` runs an instruction to done,
`/loop` on a schedule — adapted per engine; `/loop` is Claude Code only today.

Firmware updates travel over the same cable in 16 KB credit windows, offered from the published
metadata and never for a dev build. `harness flash` re-flashes a device from a USB port. The firmware
is ESP-IDF ≥ 5.5 under [`device/esp32-circle/`](device/esp32-circle/) (`idf.py set-target esp32s3 &&
idf.py build`); `make device-test` runs the host-side tests with no board attached.

## Extend Harness

### Add your agent

Two paths. Both are first-class and both are in this repo.

|  | **CLI engine** | **API provider** |
|---|---|---|
| Your agent is | a command you run, anywhere `harness login` runs | a service on your own infrastructure |
| You write | a normalizer in TypeScript, here | an HTTP endpoint, in any language |
| You ship it | as a pull request to this repo | by deploying it yourself |
| Start at | [`cli/src/engines/README.md`](cli/src/engines/README.md) | [`provider/`](provider/README.md) |

A CLI engine touches about twenty shared files, and the engines README is that list in dependency
order. The one rule: every field name, event kind and tool name comes from a real recorded session of
the real binary, never inferred from another engine. If your agent writes nothing to disk, look at Amp:
its plugin writes the transcript, and from there it is an ordinary engine.

```bash
cd cli && npm install && npm run typecheck && npm test        # replay the recorded-session fixtures
```

An API provider implements eight JSON-RPC 2.0 methods over HTTPS with SSE for the one that streams:
`agent.list`, `agent.send`, `agent.history`, `turn.cancel`, `agent.create`, `agent.rename`,
`agent.delete`, `agent.recap`. No SDK, no discovery, no capability negotiation. The reference
implementation ships the conformance runner; zero failures is the bar.

```bash
cd provider/reference-provider && npm install && npm run dev            # http://127.0.0.1:4319
npm run conformance -- --url https://your-endpoint --key <credential>
```

### Add a terminal multiplexer

Harness watches tmux with nothing to configure. A second multiplexer is added beside tmux, not in
place of it. Before writing code, confirm two things: a process inside a pane can identify that pane
with a stable, multiplexer-namespaced id, and your tool's presence is detectable without running it,
so a machine that lacks it pays nothing. Then implement: list panes with PID and working directory,
send literal text and keys, capture a pane, display a message, create and kill sessions. Carry the new
pane identity through process discovery, registry persistence and hooks, and scrub it from recap
workers so they cannot register as phantom agents. The retired Herdr backend is still in the tree
(`cli/src/lib/herdrBackend.ts`) as the worked example of the contract; see
[Adding a multiplexer](CONTRIBUTING.md#adding-a-multiplexer).

```bash
cd cli && npm run test:tmux-real       # the real multiplexer discovery suite
```

### Add a domain harness

Circuit (PCB design) and Workshop (3D CAD) are being packaged as domain harnesses: a git repo with a
manifest, the domain's skills, a workspace template, a verifier that writes one verdict file, and an
optional viewer that opens in a pane beside the terminal, installed with `harness dsh install`. The
work is on the `dsh-mvp` branch and this section lands with it.

## Providers, relay, web

- **`provider/`** — the spec ([`spec/README.md`](provider/spec/README.md)), the deterministic
  [`reference-provider`](provider/reference-provider/) with the conformance runner on port 4319, and
  [`example-provider`](provider/example-provider/), a real one backed by the local `claude` CLI on
  port 4502 (read its README before running it; it skips permissions). `provider/e2e` runs both.
- **`backend/`** — the relay: Node, MongoDB via Prisma, Redis. It terminates four WebSocket paths
  (`/api/adapter-ws` for daemons, `/api/web-ws`, `/api/device-ws`, `/api/manager-ws`), signals WebRTC
  and hands out STUN/TURN, and persists machines, agent names and counters. `npm install && npm run
  dev` on `:8085`; [`backend/README.md`](backend/README.md) and `.env.example` for the rest.
  `harness-api.autonomous.ai` is the hosted instance.
- **The web client** at [harness.autonomous.ai](https://harness.autonomous.ai) reaches the same
  machines from a browser after `harness pair <code>` or a `harness browser-link`. It is not in this
  repository; it also hosts the CLI installer and the desktop downloads.

## Repository layout

```
desktop/    the app (Flutter; macOS and Linux). third_party/xterm is the patched terminal core
cli/        the harness daemon and CLI (TypeScript, one bundle). src/engines/ is one folder per engine
backend/    the relay (Node, Prisma/MongoDB, Redis)
provider/   the API-provider spec, reference and example providers, conformance runner
device/     firmware for the Harness device (ESP-IDF, esp32-circle)
docs/       specs (the cable protocol), design notes, plans, release map (cicd.md)
```

## Development

```bash
# cli
cd cli && npm install && npm run typecheck && npm test
make install-cli          # bundle this tree into ~/.harness/cli and restart the daemon on it

# desktop (Flutter ≥ 3.47 / Dart ≥ 3.13; SPM on for macOS)
cd desktop && flutter pub get && flutter analyze && flutter test
flutter run -d macos      # or -d linux

# backend
cd backend && npm install && npm run typecheck && npm test

# provider
cd provider/e2e && npm install && npm test

# device
make device-test
```

Each product releases on its own tag and the suffix routes the workflow: `vX.Y.Z_cli` bundles and
publishes the daemon (running daemons pick it up within a minute), `vX.Y.Z_backend` builds the image,
`vX.Y.Z_desktop` builds, signs and publishes both macOS bundles and both Linux architectures.
`make release-cli|release-backend|release-desktop` cut them; `make upload-circle` publishes device
firmware over the air. `ci.yml` runs the CLI suite on every pull request and holds no secrets, which
is what lets it run on a fork's code; see [`docs/cicd.md`](docs/cicd.md). `make remote-machine`
brings up a second machine in Docker so the remote path can be exercised from one laptop.

## Docs

- [`docs/specs/cable-protocol.md`](docs/specs/cable-protocol.md) — the device wire, the only thing the firmware and the daemon share.
- [`docs/cicd.md`](docs/cicd.md) — workflows, tags, credentials, dry runs.
- [`docs/harness-v2-handoff.md`](docs/harness-v2-handoff.md) — the current state of the app, superseding the other `harness-v2-*` notes; [`docs/harness-v2-keyboard-system.md`](docs/harness-v2-keyboard-system.md) for the keymap design.
- [`docs/harness-agent-creation.md`](docs/harness-agent-creation.md), [`docs/harness-agent-lifecycle.md`](docs/harness-agent-lifecycle.md), [`docs/harness-agent-first-tabs.md`](docs/harness-agent-first-tabs.md) — how sessions are created, kept and shown.
- [`docs/autonomous-device-integration.md`](docs/autonomous-device-integration.md) — direct LAN pairing with Autonomous OS devices.
- [`cli/README.md`](cli/README.md), [`desktop/README.md`](desktop/README.md), [`backend/README.md`](backend/README.md), [`provider/README.md`](provider/README.md) — per-package detail.

## Contributing, security, licence

Open an issue before writing an engine or a multiplexer so the integration shape and the real software
a maintainer needs to reproduce it are agreed first; the review and pull-request workflow is in
[CONTRIBUTING.md](CONTRIBUTING.md). Security reports go to [SECURITY.md](SECURITY.md), not the issue
tracker. [MIT](LICENSE).
