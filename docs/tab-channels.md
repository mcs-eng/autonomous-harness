# Swarm tabs and their conversation channels

September 28, 2026. This is the experimental A2A experience, off by default; the underlying
[team protocol](agent-teams.md) also remains available through the CLI.

## User experience

A tab is a swarm. Its existing agent panes supply membership;
there is no separate team creation, role form, recipient picker, or Connect step.
Agents in different engines and on paired machines can participate in the same tab.
Ordinary terminals and shared observation sessions do not become answering peers.
The swarm's shared conversation uses a tab-scoped channel. The CLI and protocol keep
the `channel` name; the interface calls the group a swarm and its history a conversation.

Enable **Settings → Experimental → Swarm collaboration** to try it. This is an
explicit account preference, stored independently from the desk. Missing preferences
mean OFF. Opening Settings only reads the choice. The switch is enabled only after
the saved choice is loaded, and changes are acknowledged by the daemon/backend.

When enabled and a tab contains at least two recognized agents, the daemon provides each agent
its scoped commands at a safe input boundary. The agent reads current members and
shared history, chooses a relevant peer when its task needs help, asks, and continues
with the correlated answer. A message goes to its recipient; reading shared history
does not notify all participants or start model work. Introductions, questions, and
continuations can use the participants' existing model subscriptions.

Agents discover relevant peers and consult automatically within their tab. There is no
consult shortcut or recipient picker. Cross-swarm requests and Cmd+Shift+A are deferred.
Busy, draft, permission-dialog, offline, and uncertain delivery states use the existing
durable mailbox; an uncertain retry keeps the same operation ID.

Press **Cmd+Shift+P**, type **Swarm conversation**, and press Enter to read the roster and
exchange history, inspect return delivery, open a participant, cancel a question,
or pause/resume collaboration. The history contains actual peer questions, replies,
and delivery states, not full terminal transcripts. Opening and closing the view only reads state.
Mobile provides **Swarms** from machine views and **Swarm conversation** from the terminal.

Turning the experiment off prevents new automatic swarm input and new questions.
Known-unsent work and history are retained. Existing model turns are not interrupted.
Daemons start with swarm delivery disabled, reconcile the saved preference on account
invalidation and a 15-second poll, and hold deliveries when the directory cannot be read.
The receiver also checks the gate immediately before writing to an agent. Re-enabling
may resume unexpired pending deliveries; a per-swarm pause remains in effect.

## Membership and lifetime

The saved desk, rather than the active window or focus, supplies membership.
Renaming, reordering, zooming, switching tabs, and closing the app do not move the
channel's ledger or restart an exchange. Removing a pane stops that membership from
discovering shared history or starting new questions. Its existing exchanges may
finish and return their answers. Rejoining creates a fresh membership capability;
old requests stay attributable. Closing a tab removes its active memberships while
retaining history on the host. Closing a history dialog leaves membership unchanged.

A session shown in multiple tabs has a separate capability and roster in each.
Every question carries its channel identity; rosters are never unioned. Every scoped command supplies an originating tab. Native terminal engines do not
report the tab in which arbitrary typed text originated: when a session participates
in several channels, agents must use the channel specified by the task or request
clarification rather than infer scope from the last visible tab.

The first owned machine chosen for a channel remains its host after panes move or
leave. If that machine is offline, requests wait or report unavailable; the system
does not invent another host and duplicate the ledger. Automatic host migration is
not implemented. Daemons reconcile saved membership on desk-change notifications and
a 15-second poll, with fresh reads for new asks/consults. They keep known-unsent queues
and pending replies across restarts. An unavailable directory never clears membership
or causes a silent global fallback.

## Swarm boundaries

Member discovery and questions stay inside the named tab. A member capability from one
tab cannot inspect or message a different tab. Cross-swarm request actions are not
available in this release, even with an explicit cross-channel flag. If no local peer
fits, the agent continues independently or explains the missing context.

This is a collaboration scope, not an OS sandbox between same-user processes. Like
other CLI commands, the advanced owner/team interface uses the user's local or paired
machine authority. Agents are instructed to keep using their supplied scoped commands.

Code answers are instructed to name their repository, worktree, branch/commit, and
relevant uncommitted changes. There is no automatic checkout, merge, or file transfer;
the asking agent uses the answer within its existing task and permissions.

## Components and activation

- `backend/src/lib/tabChannels.ts`, `routes/tabChannels.ts`, and the separate
  `tab_channels` collection store only `(user, tab, host machine)` routing metadata.
  The existing desk JSON, routes, and collections retain their format. A deterministic
  MongoDB `_id` makes simultaneous host claims converge; ownership filters exclude
  shared observation panes.
- `tab_channel_settings` stores the explicit account preference, defaulting to false
  when absent. Authenticated GET/PATCH `/api/tab-channels/settings` read and update it.
  A setting change uses the existing account invalidation transport; desk data is untouched.
- Generate the updated Prisma client and deploy the updated backend, CLI, and app.
  Module routes are available by default, while actual collaboration remains OFF
  until the user opts in. Operators can set **`HARNESS_CHANNELS=false`** to disable the
  module completely. Older or disabled servers produce an explicit unsupported message.
  No existing database or account setting was changed during development.
- `cli/src/teams/channels.ts` reads that directory and reconciles local ledgers. The
  existing `team.v1` RPC and paired E2EE carry member capabilities and message bodies;
  the backend never stores them. `channelCommand.ts` exposes the human/owner CLI.
- Desktop/web use the same controller and channel view. Mobile keeps its self-contained
  controller copy. `harness team ... members`, `history`, `ask`, `inbox`, `reply`, and
  `wait` are the scoped shell adapter used by Claude, Codex, Grok, and other engines.

```sh
harness channel --help
harness channel list --json
harness channel --tab TAB_ID history --json
```

The existing bounds apply: 100 retained ledgers per host, 500 exchanges per ledger,
8 outstanding questions per sender, 30 new questions per minute per ledger, and four
questions in a follow-up chain. A tab channel allows 32 current and 512 retained
memberships, and 500 retained consult instructions. No retention deletion or automatic host failover is performed.

## Verification

Tests cover default-off behavior, explicit opt-in persistence, safe disable/re-enable,
recipient restarts, failed directory reads, concurrent settings changes, automatic
registration, tab isolation, shared history, removal/rejoin,
closed tabs, stale membership, idempotent consults, rejected cross-swarm requests,
pause/resume, skipped shells, read-only views, inactive cross-swarm shortcuts,
and desktop/mobile rendering. The two-daemon fixture exercises actual local WebSockets,
pairing, encrypted relays, explicit replies, and continuation; cloud routing and agent
terminal responses are synthetic. Backend tests cover auth, owned-machine filtering,
concurrent host claims, retained hosts, and compatibility with the existing desk routes.

Release integration validation on current main passed:

- Backend and CLI TypeScript checks, Prisma client generation, and builds.
- Backend routing and desk compatibility: 19 tests.
- Complete CLI suite with two workers: 7,141 passed, 37 opt-in tests skipped.
- Real tmux 3.5a suite: 9 passed, 9 unavailable/not-applicable rows skipped.
  Installed Claude, Codex, OpenCode, Pi, Hermes, and Grok discovery ran, plus lifecycle,
  literal input, and Grok executable-alias checks. These checks send no model tasks.
- Desktop settings, conversation, keyboard, and encryption checks: 82 tests.
  The final Settings pair was rerun after preserving the existing switch order.
- Mobile conversation/controller and encryption checks: 18 tests.
- Changed desktop/mobile Dart files passed analysis. macOS debug and browser release builds passed.

The initial concurrent CLI run exposed two timing-sensitive existing checks; their targeted
rerun and the complete two-worker run passed. The existing CLI build warning in
`dsh/verdict.spec.ts` is unrelated to this feature. Paid model acceptance was not rerun.

The Settings switch was rendered with real fonts at widths 390/1100. Conversation renders
were inspected at desktop widths 390/1280 and phone width 390, using synthetic data.
Review screenshots are committed under `.github/assets/swarm-collaboration/`.
Local build outputs are `backend/dist`, `cli/dist`,
`desktop/build/macos/Build/Products/Debug/Harness.app`, and `desktop/build/web`.

The earlier [Claude/Codex/Grok live test](agent-teams-live-verification.md) verified the
underlying delivery protocol. The tab-channel prompts and automatic membership have not
been rerun against paid live models. No production server, installed CLI, or ongoing
user agent was changed or used as a fixture for this extension.
