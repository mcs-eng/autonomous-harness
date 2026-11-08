# Harness HUD for Claude Code

A heads-up display for Claude Code sessions, in the spirit of claude-hud, built as a Claude Code mod (a hooks
module) rather than a status-line script. It draws up to three lines under the prompt (or above it) and a detail pane on request. It knows about Harness: the domain harness's verdict and the other harnesses running on the
machine.

```
Opus 5.5  ctx ██████░░░░ 61% 122k/200k  ~6 turns to compact  5h 42% ↺1h12m  7d 18%  api≈$1.84 $2.10/h  ⎇ main ±3
▶ Bash npm test 12s  ✓ 14 tools ✗ 1 (Read×6 Edit×4 Bash×3)  agents 2: Explore auth, review diff  todo 3/7 ▸ Writing tests
Harness autonomous/marp  ○ not ready · Draft !1 · 10 slides so far  fleet 1 working, 1 idle
```

## What it shows

- **Line 1, the meters.** Model, context fill (green, amber past 65%, red past 85%), tokens used of the window,
  and a forecast of how many turns remain before auto-compaction. The forecast takes the median growth of the
  last few turns and measures it against the compaction point from Claude Code's own context breakdown. Then
  each rate-limit window with its reset countdown, plus a pace warning (`→140%`) when use so far projects past
  the limit before the window resets. Session cost and the hourly burn rate: Claude Code's own `/cost`
  total, the tokens used priced at API rates. On a subscription (whenever rate-limit windows are reported)
  it is dimmed and marked `api≈`, because it shows what the session would cost on the API, not what the
  subscription bills. Git branch and the number of changed files.
- **Line 2, activity.** Running tools with what they are working on and how long they have run, finished and
  failed tool counts with the busiest tools, running subagents, and todo progress with the current item. It
  reads both `TodoWrite` and the `TaskCreate`/`TaskUpdate` task list.
- **Line 3, Harness.** Shown only when there is something to say. The harness package this session runs
  (`HARNESS_DSH`), the `.harness/verdict.json` state (ready or not, the active phase, errors and warnings,
  the summary line), and the other harnesses on this machine from `harness ps --json`.
- **Toasts** when context crosses 80% and 90%, and when a rate-limit window crosses 80% and 95%.

`/hud` opens the detail pane: the context bar with a per-turn sparkline and the largest context categories,
each rate-limit window with its pace, the last tool calls with durations, subagents (press one to open its
transcript), the todo list, the verdict's phases, and the other harnesses with their states.

| Command | Does |
|---|---|
| `/hud` | open the detail pane |
| `/hud close` | close it |
| `/hud full` | three-line band (the default) |
| `/hud compact` | one-line band |
| `/hud off` | no band |
| `/hud below` | draw the HUD under the prompt, after the hint line (the default) |
| `/hud above` | draw it above the prompt instead |

Both settings are remembered across sessions.

## Install

From this fork's marketplace, in a terminal:

```
claude plugin marketplace add mcs-eng/autonomous-harness --sparse .claude-plugin plugins
claude plugin install harness-hud@openharness
```

From a working tree, for development: `claude --plugin-dir plugins/harness-hud`.

Hooks modules are an early-access Claude Code feature; this mod was written against Claude Code 2.1.319. The
Harness line needs the Harness CLI on `PATH`. Without it, the line shows only what the workspace says.

## Checking it

```
claude plugin validate plugins/harness-hud
claude plugin test plugins/harness-hud
```

The tests use fictional fixtures for `harness ps` and the verdict, and draw the band and pane on the
terminal and desktop surfaces.

## How it works

Everything is pushed, not polled, where Claude Code allows it. Usage figures arrive with `session.measure`
after each turn. Tool calls are timed around `tool.call`. Agents are listed on `agent.spawn` and when a
subagent's turn ends. Git and the verdict are re-read after each turn and after file edits. `harness ps` is the
one poll: every 30 seconds and after each turn, because it takes about a second. Render hooks only read state;
all fetching happens in events and timers.
