import { env } from './config/env.js'
import { dshUsage } from './dsh/usage.js'
import { apiUsage } from './lib/apiUsage.js'
import { connectionsUsage } from './lib/connectionsUsage.js'
import { tildify } from './lib/displayPath.js'
import { ENGINE_CLI_COMMANDS, PROCESS_ENGINES } from './lib/engineCommands.js'
import { VERSION } from './version.js'

// Upstream (#1354) wraps this text in agentClient/help.ts's helpFor, printing the curated agent
// screen inline when the caller is an agent. helpFor's module pulls the whole agent-command graph
// (newCommand, messages/command, agentClient/commands) into this route, which is exactly what the
// fork's usage split (PR #66) keeps `--help` out of — architecture.spec's fast-route closure. So
// the fork prints upstream's pointer line for everyone; an agent caller gets the curated screen
// from `harness help agents` (cli.ts prints it there).
const AGENT_POINTER = 'An agent? Run: harness help agents\n'

export function usage(exitCode = 0): never {
  console.log(AGENT_POINTER + `harness v${VERSION} — connect this computer to your machine

Agents — after "harness start", run the vendor CLI directly inside tmux. Harness discovers supported
top-level processes automatically; it does not launch them or change their permission flags:
${PROCESS_ENGINES.map((engine) => `  ${ENGINE_CLI_COMMANDS[engine]}`).join('\n')}
A launcher that hands the pane to one of these works the same — "ori claude" is a Claude Code agent.
An agent can start, wait for, read and close other agents here: harness new, wait, show and close below, or
harness mcp. Starting is off until the person turns it on: Settings ▸ Experimental, or harness settings
agents-start-agents on. How: https://harness.autonomous.ai/agents

Machine:
  harness login                sign in (asks: Google or Apple in your browser, or scan a QR with your phone)
  harness login --google       sign in with Google in your browser, without asking
  harness login --apple        sign in with Apple in your browser, without asking
  harness login --qr           sign in by scanning a QR with Harness on your phone, without asking
  harness login --code         for a device with no screen: say a short code the person types into Harness
                               (phone: Settings ▸ Sign in a computer ▸ Type a code instead; desktop or web:
                               Machines ▸ Approve a device); with --json the code is an event
  harness login --force        stop the daemon and sign in with a different account
  harness login --json         emit machine-readable NDJSON instead of opening a browser (for GUI clients)
  harness login --entry-point=desktop   record which surface started the sign-in (GUI clients; default cli)
  harness auth status --json   print {loggedIn,...} for this computer's saved session
  harness privacy status|on|off   view or change product usage sharing for this account
  harness start                start the adapter using the saved SSO session
  harness start -f             run the daemon in the FOREGROUND (for a supervisor; logs to stdout): harnessd's
                               master, as launchd and systemd run it, its core and services its children
  harness start --device-dump[=<file>]
                               record every frame to/from the paired Autonomous device, decrypted, as
                               JSON lines (default ~/.harness/logs/device-dump-<time>.jsonl). Contains
                               prompts and answers in the clear — diagnostics only. Stop the daemon first.
  harness start --repair       also re-verify the managed Node runtime and repoint the launcher at it
                               (normally done once by the installer; use this if a start fails because
                               the launcher points at a Node that no longer runs)
  harness logout               stop the adapter and clear this computer's SSO session
  harness stop                 stop the background adapter (keeps the SSO session)
  harness reset                stop the adapter and clear local CLI state
  harness status               show whether it's running (+ version)
  harness service install      run the daemon under launchd (macOS) or systemd (Linux): it starts at login
                               and comes back if it dies; start and stop then go through it (opt-in)
  harness service uninstall    undo that: the daemon goes back to \`harness start\`
  harness service status       what launchd or systemd has registered, and whether it runs (--json)
  harness logs export          zip the last 7 days of logs (app, CLI, dial, daemon) to the Desktop
  harness tui                  all of Harness in this terminal: swarms, panes, every machine (⌥O ⌥P ⌥N)
  harness new [agent] [--machine <name>] [folder|name] [-- task]
                               make a harness from a shell: \`harness new\` is claude here; see \`harness new -h\`
  harness machines             list the machines on this account (this computer's is marked)
  harness search <words>       find the conversation on this computer that said them: every turn of
                               every harness, live or stopped (--limit=N, --json)
  harness send <name> "text"   from an agent's pane: message a teammate in this tab (Agent Messages,
                               Settings ▸ Experimental); \`harness send\` alone lists who is here
  harness whoami               who you are to Harness: which agent, which machine, whether you may start harnesses
  harness ps [--all]           the harnesses here: state, who started each, what each is about
  harness show <name>          a harness's state and last turn: what it was asked and what it answered
  harness wait <name>[,<name>] wait until they stop working (--any, --timeout 30m); exit 3 = needs the person
  harness close <name> [--now] save a harness's screen and stop it; an agent closes only what it started
  harness reply <name> -- <w>  say words to a cloud harness (Devin Cloud, Cursor Cloud, Fo): its answer or what next
                               new, ps, show, wait, reply and close take --machine <name> for another of your
                               machines: \`harness show --machine office x\`
  harness mcp                  the agent verbs as an MCP server on stdin/stdout, for agents that use MCP
  harness help agents          the agent commands, states, exit codes and rules on one screen
  harness settings [<name> on|off]  what agents may do (agents-start-agents, pull-request-line, agent-messages): your account's experiments in Settings ▸ Experimental, each off by default
  harness machines delete <id> remove ANOTHER machine (refuses this one; use \`harness logout\`)
  harness e2e plan             which coding tools have a new version out (the grid-switch e2e trigger)
  harness e2e grid-switch      move a fresh agent subscription -> grid -> back home with its tool + MCP; leaves a review bundle
  harness remote               from a Harness terminal tile: open a terminal on another of your machines and move this tile to it
  harness version              print the installed version (v${VERSION})
  harness update [--force]     update to the latest build now (it also self-updates in the background;
                               neither touches a local install-cli.sh build without --force)
  harness flash [flags]        re-flash a plugged-in circle device over USB. Flags go straight to the
                               flasher: --detect-only, --port, --version, --yes, --erase-nvs

Grid (the fleet of AI engines the \`grid\` CLI serves — needs \`grid\` on PATH):
  harness grid login           sign in to your grid reusing THIS computer's Autonomous account —
                               no second browser, no second approval
  harness grid login --force   sign the harness in as a different account first, then the grid
  harness grid login --json    emit the same machine-readable NDJSON \`harness login --json\` emits
  harness grid setup           have grid ready here through the running daemon: installed, signed in
                               with THIS computer's Harness account, and the account's grid made
  harness grid logout [flags]  sign out of your grid — the whole of \`grid logout\`, which stops what
                               this box is serving BEFORE deleting anything. Flags go straight to it:
                               --force signs out over a serve child it could not confirm stopped
  harness grid profile list    list server-owned local Grid profiles (paths remain on this machine)
  harness grid profile set ID --label LABEL --home ABSOLUTE_PATH --grid GRID
                               register or replace one isolated local Grid profile
  harness grid profile remove ID
                               remove a local Grid profile (does not change its Grid home)
  harness grid env <grid>      print <grid>'s relay address and key as shell exports, for
                               eval "$(harness grid env <grid>)" — through the harness's own \`grid\`

${dshUsage()}

${apiUsage}

${connectionsUsage}

Browser end-to-end encryption:
  harness autonomous-device <command>     pair/status/list/revoke an Autonomous device
  harness pair <code>          pair a BROWSER (code shown on the machine page)
  harness pairings             list paired clients
  harness unpair <#|fp>        unpair one browser (by list number or fingerprint)
  harness unpair --all         unpair every browser

Machine-to-machine linking (lets this machine's relay reach ANOTHER of your machines with the CLI,
not the app, terminating E2EE). A machine's remote password is persistent — set once, reused for
every future connect, until you change or clear it:
  harness remote-password set   set/rotate this machine's persistent remote password
  harness remote-password status   show whether one is set, and its fingerprint
  harness remote-password clear   remove this machine's remote password
  harness link connect <id>    join a machine using ITS remote password (fully automatic)
                               (--name=<label> names the machine in messages instead of its id)
  harness link list            list machines this one has linked
  harness link unlink <id>     remove a linked machine's trust
  harness group list           machines and phones that trust each other through links: link one
                               machine and every member reaches it both ways, no more passwords
  harness group sync           compare with every reachable member now (it also happens on its own)
  harness group remove <id>    drop a member (machine id, # or fingerprint) from every member
  harness devices list         the account's devices — signing in on one is what makes the others trust
                               it; a device you do not recognise is someone else signed in as you
  harness devices show <#|fp>  one device in full: its key code and how to check it on that device
  harness devices remove <fp>  take a device out of the account on every device, by key code (or its
                               first 4+ characters); a # or a shorter start asks first, --yes skips it
  harness devices history      every device added to or removed from the account, newest first, as this
                               machine verified it (--json for the rows)
  harness devices dismiss [<#|fp>]  mark every new device as seen here, or say one is yours — your
                               other devices then stop showing it as new too
  harness devices rebaseline   the device list froze (the backend served one that does not match what
                               this machine verified): show what changed, --yes to trust it again
  (both \`remote-password set\` and \`link connect\` prompt for the password interactively, or read one
  line from stdin with --stdin; add --json for NDJSON output instead of the human-readable text)

  harness --help

This computer's id lives at ${tildify(env.ADAPTER_COMPUTER_ID_FILE)} and is created once. Nothing here
regenerates it — that is what keeps "harness start" reconnecting to the same machine instead of
making a new one. Deleting it (or ~/.harness) makes this look like a brand-new computer. On a box with
no durable home, a container or CI job, pin ADAPTER_COMPUTER_ID instead.

Env: BACKEND_WS_URL (${env.BACKEND_WS_URL}), WEB_URL (${env.WEB_URL}), ADAPTER_DATA_DIR,
     ADAPTER_COMPUTER_ID, CLAUDE_PROJECTS_DIR, PORT`)
  process.exit(exitCode)
}
