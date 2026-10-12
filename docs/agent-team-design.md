<!-- Public copy. The owner's private copy, with real machine, repository, and project names, is in the owner's outputs folder outside this repository. Role words stand in for private names here. -->

# Agent team design: checks and balances for the owner's agent organization

Status: proposal for the owner, written 2026-10-12 on branch `claude/agent-team-design`. Nothing in this document is installed, scheduled, or merged. It changes nothing until you green-light items in Part 5.

Evidence window: 2026-09-20 to 2026-10-12. Everything marked **measured** was read from a file, a command, or a live query on the control station today. Everything marked **read** comes from a document and was not re-verified. Appendix A lists the receipts.

What you can do after reading this: pick the Part 5 items you want this week, answer the five decisions in "Decisions only you can make", and ignore the rest until Phase 0 has run for a week.

---

## Summary

- You run seven kinds of agent work today: Claude Code sessions in repos, Cowork dispatch sessions, overnight "make me proud" builds, PR review sessions, Codex sessions, the Hermes nightly digests, and the TensorFold night-shift chain. In three weeks that produced 683 typed turns from you across 81 sessions. **Measured.**
- Roughly 40 percent of those turns are approvals, merge relays, and "done" pings after a hand step. You said the rule out loud on 2026-10-10: "youre owning the merge - why did i need to click it?" The standing agreement already grants routine merge authority. Agents keep asking anyway.
- Nothing wakes you, and nothing wakes an idle card. Fourteen Custody Board cards wait on you (oldest 2026-09-30), eleven agent-owned cards show "in motion" with zero runs actually running, and three runs are marked interrupted because Custody Board stopped before the agent finished. **Measured.**
- Agents are unchecked at the end of a run. An overnight session writes its own notes, marks its own card `reported_complete`, and the Custody Board itself says that is "an agent claim, not independent verification." The one independent-review tool that exists in source (Custody Board completion-review) has never been activated.
- The clearest unchecked side effect: a test run of this fork wrote five hook blocks into your real `settings.json` pointing at a temp folder that no longer exists. Every Claude Code event has failed with MODULE_NOT_FOUND in at least 16 session files since. Nobody noticed for days. A Librarian role that hashes your profile before and after a run would have caught it the same hour. **Measured.**
- The fix is not more process. It is seven roles with contracts, a two-key rule (nothing reaches you without a second role's receipt), and three doors through which work may reach you: a disagreement agents could not settle, a decision only you own, or a blocker only you can clear. Everything else stays inside the team.
- Roles are files, not identities. Any harness that can read the contract can fill the role. The team scales from three roles to twelve by changing a roster file, not the process.
- Almost every role already has a tool on this machine: the catchup skill, the branch-cleanup skill, the agy review wrapper, Codex exec in read-only mode, the Hermes nightly sweeper, the Custody Board MCP, the pr-writeup skill, and this fork's own team, orchestrator, and roundtable machinery. The design wires them together. It does not replace them.
- Phase 0 is scripts, templates, and one cleanup. You can turn it on tomorrow. It cannot delete anything, push anything, or run unattended.
- The design keeps one measure: the number of times per week you have to prod, approve, route, verify, or re-explain. Appendix A shows how it was counted. Phase 0 makes that count a script so the team can watch its own score.

---

## Part 1. Current state

### 1.1 The agent work you actually run

| Workflow | Where it runs | Evidence (window 2026-09-20 to 10-12) | Who checks the result today |
|---|---|---|---|
| Claude Code sessions in a repo (implement, fix, review) | Claude desktop, `claude/*` branches | 81 sessions with typed turns; by project: Cowork scratch 331 turns, the agent-ops repo 122, the estate repo 106, business dashboard about 77, DeepSeek workspaces 24, autonomous-harness 14, the custody-board repo 8, the house-model repo 7. **Measured** from `~/.claude/projects/*/*.jsonl`. | You, by reading the PR; CI on the exact head where a repo has required checks (the estate repo one, the dashboard three, the agent-ops repo none). |
| Cowork dispatch sessions (research, writing, catch-ups, "orchestrator layer") | Claude desktop scratch workspaces | 27 scratch workspaces since 2026-09-09; session titles include "48-hour catchup", "Weekend token usage analysis", "Sessions review and prioritization", "Cross-repo orchestration and cleanup". On 2026-09-23 you typed "You are my orchestrator layer now - i am getting confused and overwhelmed with multiple sessions". | You. |
| Overnight builds | Claude Code in a repo, started with "going to bed, build or complete something that will make me proud" | At least five: "Overnight autonomous-harness proud", "Overnight the agent-ops repo proud (fork)", "Overnight the estate repo make-me-proud", "an overnight house-model run", and a 2026-10-06 the estate repo run. The house-model repo has the only `OVERNIGHT_NOTES.md` (three rounds, 25.9 KB). | The same agent that did the work writes the notes. You read them in the morning. |
| PR review sessions | Claude Code, Codex, agy, Cursor, Devin | Session titles "Review PR 38", "Review PR 321", four "PR review and merge" sessions, "PR findings review". A GitHub app `devin-ai-integration[bot]` commented on 13 of the last 25 merged PRs in the estate repo and the business dashboard and 1 of 25 in the agent-ops repo. No repo document mentions Devin or how it is triggered. **Measured** via `gh`. | Sometimes a second model, when you ask: "Approved 482 after it's been reviewed by a different agent" (2026-09-28). |
| Codex sessions | Codex app and CLI on the control station | 109 session files on 2026-10-10 alone, 50 each on 10-11 and 10-12; 30 Codex worktrees under `~/.codex/worktrees`; about 45 dated task folders under `Documents\Codex` totalling about 34 GB. **Measured.** | A weekly Codex learning digest (the only active Codex automation). PRs go through the same review path as above. |
| TensorFold night-shift chain (Fable 5.1 pickups on the inference pair) | Claude Code in the custody-board repo and the agent-ops repo, with the DeepSeek Harness | Session titles "10-05 TensorFold handoff pickup", "Harden the tracked TensorFold climb tooling", "TensorFold Night 2 artifacts debug". The chain is six dated entries in the coordination repo's machine log (10-05, 10-09/10, three on 10-10, 10-11), PRs the agent-ops repo #346 to #348, #353 to #355, #358, #363, run folders under `the agent-ops repo/runs/`, and explainer pages in the Artifact Library Inbox. Free prose with "Open for the owner" bullets; no schema. **Read.** | You, from the log entries and the Inbox pages. |
| Hermes digests | Hermes gateway on the control station | Unfinished-Business Sweeper nightly 21:00, Sweeper Cold Backstop 21:20, Weekly Review Sundays 19:00. All three ran 2026-10-11 and delivered to Bot Chat. **Measured** from the live jobs file. | Nobody. They are rung-1 "watch and talk" and report only. |
| Document and page builds | Artifact Library Inbox, repo docs, PR bodies | 20 entries in the Inbox; the latest dated 2026-10-12. Ten pages landed 2026-10-06 to 10-11 (TensorFold nights, local-AI comparisons, Fleet Day recap). | You open the library. |
| Learning loop (model of you as an operator) | coordination-repo ledgers, cloud Routine | Last cycle 2026-08-15 (cycle 5). Cycle 6 did not fire on 09-15 because all cloud Routines were disabled on 08-16. The register says the loop Routine was re-enabled 09-20 with the next run 2026-10-15. Four questions (Q-0019 to Q-0022) have waited since August. **Read.** | Nothing consumes the ledgers except the loop itself. |

Two things stand out. First, the same hands do everything: the agent that implements also reports completion, writes the handoff, and updates memory. Second, the only standing cross-check that runs without you is Hermes at 21:00, and it only reports.

### 1.2 Where you are the bottleneck

The transcript scan sorted your 683 typed turns into buckets. The counts overlap and are order-of-magnitude, not exact. Each bucket has the number of turns and the number of sessions it appeared in.

| Shortfall | Turns / sessions | What it looks like in your words |
|---|---|---|
| Approving and relaying merges | about 93 / 37, with over 100 turns containing "approved" | "Merge 471", "469 merged by me", "Approved to merge 489 - you've got standing merge approval and authority", "okay well youre owning the merge - why did i need to click it? keep going please." |
| Doing the hand step yourself, then pasting the output back | about 20 pasted PowerShell or cmdkey blocks plus 16 pure status pings ("done", "started", "logged in") | "approved to fix it either way... also cant you run the start stops? why do you hand them to me". At least six "CMDKEY: Credential added successfully." pastes. |
| Nudging a stalled agent | about 47 / 29 | "are you done or waiting on me?", "Are you waiting on me for something?", "Try again" (six times), "keep going", "continue". |
| Verifying claims yourself, or catching a wrong one | about 50 / 25 | "its empty, no tasks showing - thats what I am trying to tell you", "what about 505? thats still being worked you said?", "And codex didnt do all of the sunday work... i think youre deflecting blame here." |
| Routing: which repo, session, model, or folder | about 22 / 11 | "Dispatch two separate Claude code sessions, one to review pr 38 ... and the other for pr 321", "(is this Opus 5.5 work, or any of it delegated to Sonnet 5.5?) just trying to keep the right models in the right lanes". |
| Re-supplying context that is already written down | about 22 / 14 | "Can we update the custody board SOPs or readme to include that note? So it isnt lost in this chat", "didnt we start with six open questions? Feel like i got no where". Estate rules get re-pasted into dispatch prompts: "Read its CLAUDE.md first... never in the business dashboard live clone". |
| Hygiene and tool fragility | about 77 / 29, the largest cluster | "i have reauth'd it like 10 times today" (GitHub), "have we determined WHY this keeps happening? RCCA" (NAS credential), "why is everything breaking all at once" (Codex sandbox), "keep getting node file popups?", "Im trying to fix my ~\dev\ folder mess", "Help me understand where all my usage went". |
| Starting and picking up handoffs by hand | about 18 / 14 | "going to bed, build or complete something that will make me proud in the morning" typed verbatim in at least five sessions; "Let us pick up from the overnight @...OVERNIGHT_NOTES.md"; "Can you or sonnet or haiku read the tails of them for me and compile what was done and was is left for the owner"; "oh shit - i didnt realize this was 5 days old". |
| Being asked to choose | 64 AskUserQuestion prompts across assistant turns, plus uncounted numbered-option lists | "Go with your recommendations on all ten", "Approved to continue with any and all things that don't make me a blocker". |

Your own summary from 2026-09-21: "I am paying for your help, not a growing operator to do list."

The pattern underneath every row: an agent reaches a point where a second opinion, a receipt, or a routine yes is needed, and instead of getting it from another agent, it stops and waits for you.

### 1.3 Where agents run unchecked

- **Overnight runs.** One agent plans, builds, tests, and writes the notes. The house-model repo's notes asked you for eight or nine decisions across three rounds. Two are still open today: `main` is 237 commits behind `claude/workspace`, and the branch `claude/survey-civil` still exists. **Measured** with `git`. No second role read the notes before you did.
- **Completion claims.** the Custody Board's own banner on every brief: "reported_complete is an agent claim, not independent verification." The `completion-review` command exists in source. It excludes the author harness and requires two different reviewer models. It has never been activated; its doc says activation "remains a separate W1 check."
- **This fork's orchestrator.** A specialist task is marked `succeeded` on the worker's self-report plus an artifact snapshot. No verifier node runs. All live validation was on macOS; the Windows port notes list the orchestrator suites among those failing here.
- **Memory writes.** Every session writes its own per-project `MEMORY.md`. There is no review of a promotion that claims something about you. The global agreement already forbids turning agent failures into claims about the owner; nothing checks it.
- **Second-model review is manual.** EstateMap calls Codex review "independent," yet the agent-ops repo's own 2026-10-08 review admits "Every 'independent' audit came from the same OpenAI Codex sessions that ran the studies." The agy review wrapper was verified live on 2026-10-08 (exit 0 after 371 seconds) but "Nothing is installed."
- **CI is not a gate everywhere.** the agent-ops repo CI runs only on open, reopen, and ready-for-review, never on later pushes to a ready PR, and GitHub enforces no required check there even though its CLAUDE.md calls 85 percent coverage "a hard gate." **Measured** via `gh`.
- **Side effects on your machine.** A Windows run of this fork's test suite wrote five hook blocks into `~/.claude/settings.json` (SessionStart, SessionEnd, UserPromptSubmit, Stop, StopFailure). Both the hook script path and its data folder were later removed. At least 16 session transcripts contain MODULE_NOT_FOUND from those hooks; this session alone logged nine. PR #49 (draft) stops the test from doing it again but says the existing hooks "need removing by hand." A Custody Board card created today waits on your yes or no. **Measured.**

### 1.4 What is fragile

| Area | What was measured today | Why it bites |
|---|---|---|
| Your Claude profile | Five dead hook blocks in `settings.json`; `kernel.md` still printed by a SessionStart hook although it says it was retired on 2026-10-04 (decision D26). | Every session starts with five failures and a duplicated rule file. |
| Worktrees | Nests in use: `<repo>\.claude\worktrees` (5, one unregistered, 0.46 GB), `<repo>\.worktrees` (3 in this fork, 1.2 GB before this branch), `dev\_wt` (3), `~\.codex\worktrees` (30, mostly empty shells), `Documents\Codex\<date>\task\<repo>` (registered worktrees for the estate repo and the house-model repo), the local wiki mirror drive (detached mirrors in six repos). Legacy nests the standard retired: `dev\worktrees` (two dashboard worktrees from 2026-09-28, detached HEAD, 660 MB) and `dev\autonomous-harness-worktrees` (an evidence zip, no worktrees). | The cleanup on 2026-10-02 removed 32 worktrees and 72 branches by hand. The same species regrows because nothing watches it. This fork's own worktree sweep only covers the WSL home. |
| Disk | `Roaming\Claude` 16 GB (13 GB is Cowork's VM bundle, app-managed), `Documents\Codex` about 34 GB, `dev` 18.6 GB, `~/.claude/projects` 2.5 GB, 457 GB free. | Space is not the problem. Classification is. The 2026-10-04 audit found "Roaming\Claude 15 GB" because you asked; it has grown 1 GB since and nobody can say what is safe to touch without a fresh audit. |
| Stale checkouts | The estate repo's local `main` is 32 commits behind origin; the business dashboard dev clone's `main` is 3 behind; the local generated registers are the 2026-10-04 copies while origin regenerated them on 10-06. **Measured.** | Agents read stale registers and stale rules. The standard's own section 0 records that an approved move contradicted "a standing rule that lived in a file the acting session never loaded." |
| Scheduled and unattended work | 70 register entries, 16 unowned. Four Claude scheduled-task definitions on disk never fire. EstateSweepMonthly has never run. The estate repoFolderHygiene returned 0x1 on 10-04 and 10-11. The PDG A3 NAS mirror returned 0x1 this morning. DocCurrencySweep disabled since 08-24 for a reason "not established." Four Codex heartbeat automations paused, one past its UNTIL date. | The things meant to watch the estate are half off, and the register that lists them is a one-shot export. |
| Credentials and tools | GitHub reauth loop (ten times in one day), NAS credential wipes (an open card since 10-06), Codex sandbox breakage, MCP servers that connect only when a session starts in the right folder ("i dont think starting or not in a folder should determine an MCP connection", 10-12). | Entire sessions get spent on tooling instead of work. |
| Handoff records | OVERNIGHT_NOTES in one repo, STATUS.md in another, a "Handoff" section in PR bodies in a third, Custody Board checkpoints in a fourth, and the machine log prose for the night shift. The `handoff` skill writes to the OS temp folder and is switched off. | A fresh session cannot find the one place to resume from without you naming it. |
| Output locations | No Cowork "outputs" folder exists. There are 42 per-task `outputs` folders under the Cowork session store (one holds 11,998 files), a curated `Claude\Claude outputs\` folder from 2026-09-10, dozens of Codex `outputs` folders, and the Artifact Library Inbox for HTML. | "Where did it put the thing" is a question only a search answers. |
| Rules that disagree | Three copies of the pr-writeup skill: two say "auto-merge off," the plugin copy says "squash-auto-merge when green." Three copies of the eight non-negotiables. Merge authority stated three ways (global: routine merges allowed; the dashboard: the owner merges; EstateMap: the owner merges). The harness reminder in this very session instructs a Co-Authored-By trailer that your rule forbids. | Agents pick whichever copy they loaded. |
| Windows test baseline | The fork's CLI suite is red on Windows by design (fork-upkeep records about 7,369 pass / 1,326 fail inherited). | "Tests pass" is ambiguous on this machine unless the Verifier names the baseline. |

### 1.5 Fluency gaps

- **Context re-supply.** Dispatch prompts restate estate rules that live in `~/.claude/CLAUDE.md` and EstateStandard. The rule exists; the habit of reading it first does not.
- **Naming.** `claude/angry-ishizaka-1a3da2` and `claude/jovial-gagarin-166e34` carry no agent, topic, or role, although the agreement asks for agent-identifying branch names. In this fork, "daemon" means a creature and the background process is `harnessd`; "Swarm collaboration" and "Tab collaboration" name the same switch in two docs.
- **Model lanes.** You asked which model did what. Nothing records the lane. The one place that grades models for a role is the house-model repo's `docs/sop/model-roles.md`, which rates the local Gemma 4 12B "pre-screen" as judge and reader with planted controls. That is the right idea and it lives in one repo.
- **Memory.** The standard allows exactly four stores: the coordination repo, Custody Board, Hermes's vault, and per-project Claude memory. Per-project memory is "non-authoritative." The learning loop is idle. The capability ledger, "the one measure," has one blank row. Nothing consumes observations or predictions.
- **Pickups.** The catchup skill (updated today) reads session tails and Custody Board facts and verifies against live state. It is the best pickup tool on the machine and it is run only when you type `/catchup`.

### 1.6 What already exists for the team to stand on

| Need | Existing mechanism | State today |
|---|---|---|
| Custody of work across harnesses | Custody Board MCP (`start_run`, `report_progress`, `checkpoint`, `close_card`, `resume_stream`, `list_today`, `brief_today`) | Live; Windows task running; 860 change-log rows; October writes: claude-code 329, hermes 21, codex 8. The only shared task store by decision (2026-10-04). |
| Telling you what waits | Hermes Unfinished-Business Sweeper, waiting-on-owner section from `digest-facts` | Live nightly; delivered 2026-10-11. OpenFindings F-041 ("nothing notifies him") is partly overtaken but the row is blank. |
| Catch-up on demand | `~/.claude/skills/catchup` with `tails.py` | Live, updated 2026-10-12. |
| Independent second review | The agent-ops repo `deploy/<control-station>/Invoke-AgyReview.ps1` (verified live 10-08); Codex exec read-only (the `codex:rescue` plugin is loaded in Claude Code); Custody Board `completion-review` (source only); this fork's `store/agents/roundtable` (headless multi-vendor panel with named dissent; needs WSL); the estate repo's `Invoke-HybridAIReview.ps1` (manual panel) | All manual. None runs by default. |
| Receipts discipline | Non-negotiable 8; the agent-ops repo CLAUDE.md "A claim without a receipt is an opinion"; the house-model repo AGENTS.md "status claims quote command and exit code" | Written in three places; enforced by nobody. |
| Definition of checked and verified | The house-model repo's `docs/sop/README.md`: a reading is **checked** only when a second reader who has not seen the first agrees; a worker's report is **verified** only when the lead reruns the checks. Hermes vault runbook: the verifier "must not be the worker"; "A worker handoff means work reported, not verified." | Adopted in one repo and one vault runbook. |
| Worktree and branch hygiene | `branch-cleanup` skill (fail-closed, report-only for worktrees); the estate repo's `Invoke-EstateSweep.ps1` checks R1 to R12 (monthly, never run); `Run-FolderHygieneAudit.ps1` (weekly, failing); this fork's `worktreeSweep.ts` (WSL home only); Custody Board `/git-hygiene` (two-step confirm, non-force) | Report-only everywhere, which is correct; none runs on a cadence that works. |
| Registers | `Export-UnattendedRegister.ps1`, `Export-AgentRuntimeRegister.ps1` (report-only), EstateMap, OpenFindings | Generated by hand; stale within days. |
| Deliverable writing | `pr-writeup` skill (what / why / blast radius / evidence / follow-ups / "Touched, Will bite you, Conflict watch"), `stop-slop`, Artifact Library Inbox contract | Live. |
| Agent-to-agent messaging in this fork | `harness team` (team.v1: ask, inbox, reply with evidence, bounded, durable ledger); tab channels (need sign-in); `harness pair` MCP with an autonomy dial (watch, suggest, act-on-key, act-within-rules) that never approves push, merge, deploy, or delete | Coded; live-verified once on 2026-09-27 on macOS tmux; unproven on this machine; invisible to Windows-native Claude Code sessions. |
| Director and specialists in this fork | `harness orchestrator plan|finish|fail|retry|complete` with immutable artifacts and dependency DAG | Coded; macOS-only live runs; suites fail on Windows. |
| Session-to-session control in Claude desktop | The `ccd_session_mgmt` tools (list sessions, send a message to a session, start linked sessions, search transcripts, set remote control) | Live. This is the orchestration substrate you already use when a Cowork session dispatches Claude Code sessions. |

The important constraint from the fork audit: the fork's daemon sees only tmux panes inside WSL. A Windows-native Claude Code or Cowork session, which is where nearly all of your work happens, cannot be a team member or an orchestrator worker there. So the team has to start in the sessions you already run, and the fork's machinery is Phase 3, not Phase 0.

---

## Part 2. The team

### 2.1 Four rules the design follows

1. **Capability boundaries, not vigilance.** RISK.md says security lives in what a thing can physically do, and "Do not invent additional governance." Every check below is agent-to-agent. Each one removes a reason for an agent to stop and ask you. None adds a new gate on you.
2. **A role is a file.** A role is defined by a contract (purpose, inputs, outputs, receipts it must produce, who checks it, when it escalates). Any harness that can read the contract can fill the role. No role is a named agent.
3. **Two keys to reach the owner.** Nothing is marked ready for you, placed in your Inbox, merged, or promoted into memory on one agent's word. A second role must leave a receipt.
4. **Receipts or it did not happen.** A claim names the command and its exit code, or the file and line. The Verifier bounces anything else. This is your non-negotiable 8 made mechanical.

### 2.2 How a piece of work moves

1. A request arrives (you, a Custody Board card, a trip-wire, a scheduled digest). The **Router** names the repo, the lane, the card, and the roles. It never implements.
2. The **Implementer** works in one worktree on one branch, writes a draft PR with receipts, writes the handoff block, and checkpoints the card. It may not mark its own work ready.
3. The **Reviewer** (a different model or harness from the Implementer) reports blockers only, each with a failing reproduction, for at most two rounds. The **Verifier** reruns the repo's required checks on the exact head and records command plus exit code, naming the known baseline on Windows.
4. The **Scribe** writes the PR body or the page from the receipts, in your standing format, and files the page in the Artifact Library Inbox when there is one.
5. The **Librarian** runs its postflight: profile hash unchanged, worktree registered, footprint recorded, no new unowned scheduled task, no hook errors in the transcript.
6. The **Historian** checks that a cold start could resume from the card and the PR alone, appends the log line, and writes the retro.
7. Only now does the PR go ready-for-review or the card go `next_actor` set to the owner. It reaches you through one of three doors (section 2.7) or it is merged under the routine-merge rule you already granted.

The lean version of this loop has three people: a Lead that routes, scribes, and keeps history; an Implementer; and a Reviewer-Verifier. The roles still exist; they are just filled by fewer sessions.

### 2.3 The roles

Each role lists what fills it today, so nothing here depends on new software.

#### Router (also called Lead or Orchestrator)

- **Purpose.** Resolve a request to a repo, a card, a lane (model and harness), and a set of roles. Keep one writer per branch. Stop duplicate work. Decide team size for this request.
- **Inputs.** The request; `~/.claude/CLAUDE.md`; EstateMap and EstateStandard sections 1 and 2; the roster (section 2.4); Custody Board `brief_today`; the live session list.
- **Outputs.** A Custody Board card with the role assignments in its next action; a dispatch prompt per role that points at files instead of restating them; a one-line routing log entry.
- **Who checks it.** The Historian samples routing decisions in the retro. A card re-routed twice trips a wire to you.
- **Escalates when.** Two roles disagree after two rounds; a request touches a subject in EstateStandard section 2 (the owner-override table); a request needs a capability above rung 1 that no ruling covers.
- **Fills it today.** A Claude Code desktop session with the session-management tools, which is what your "orchestrator layer" Cowork session already is. Stronger model (Opus or Fable); it reads a lot and writes little.

#### Planner

- **Purpose.** Only when the Router says the request is large, spans repos, or you asked for a plan. Turn it into slices, each with the capability gate from the architecture-review skill: who the first user is and what chore you stop doing.
- **Inputs.** The request, the repo's STATUS or roadmap, the registers.
- **Outputs.** A slice list with acceptance checks per slice and a stopping rule. Nothing else.
- **Who checks it.** The Reviewer reads the slices for the capability gate before any Implementer starts.
- **Escalates when.** A slice reverses a decided item (refused with the decision's path) or reverses a lean (allowed only with a dated line naming the changed input).
- **Fills it today.** The same session as the Router, or a Plan subagent. Your non-negotiable 1 stands: no planning step unless you asked. The Router invokes the Planner only on an explicit ask or a multi-repo request.

#### Implementer

- **Purpose.** Do the work. One branch, one worktree, one file set.
- **Inputs.** The dispatch prompt, the repo's CLAUDE.md or AGENTS.md, the card.
- **Outputs.** A draft PR with the receipts block and the handoff block; a Custody Board checkpoint at least hourly (Custody Board interrupts a silent run after two hours); the branch name carrying the agent and topic, such as `claude/impl-librarian-preflight`.
- **Who checks it.** Reviewer and Verifier, always. Librarian on postflight.
- **Escalates when.** It needs a credential, sudo, physical presence, a paid CI confirmation it cannot request, or a read of a production clone. It escalates by writing the decision packet, not by stopping silently.
- **Fills it today.** Claude Code on `claude/*`, Codex on `codex/*`, Hermes `pstack`, agy. Model per task; the Router records the lane on the card.

#### Reviewer (Red-team)

- **Purpose.** Find what is wrong before you do. Independence is the whole value: a different model from the author, and where possible a different harness.
- **Inputs.** The diff and the PR body. Not the Implementer's chat.
- **Outputs.** Blockers only, each with a failing reproduction (a command and its output, or the exact line disputed). Two rounds maximum. A round with no blockers is a one-line receipt.
- **Who checks it.** The Verifier reruns at least one of the Reviewer's reproductions. A reproduction that does not fail is itself a finding against the Reviewer.
- **Escalates when.** The second round returns the same class of flaw. Then it writes one design choice for you, as the agreement already says.
- **Fills it today.** For Claude-authored work: Codex exec in read-only mode (loaded here as the `codex:rescue` subagent) or the agy review wrapper. For Codex-authored work: the Claude `code-review` skill at medium. For parser, money, and security diffs: two reviewers, which is the existing rule. The roundtable package is the model for decision disputes once the fork runs here.

#### Verifier

- **Purpose.** Run the repo's required checks for the actual diff and say whether they passed, with receipts. Validate audits and benchmarks against known-good and known-bad cases before trusting them.
- **Inputs.** The exact head SHA, the repo's check commands (`/verify` in the dashboard repo, `tools/run_checks.py` in the house-model repo, `uv run pytest` and `ruff` in the custody-board and agent-ops repos, the CLI suite inside WSL for this fork), the Windows baseline where one exists.
- **Outputs.** A receipts block: each command, its exit code, the baseline it was compared with, and the hosted CI run link for the final head.
- **Who checks it.** The Reviewer reads the receipts. The trip-wire "passing without a receipt" bounces the PR automatically.
- **Escalates when.** A required check cannot run on this machine and CI minutes are the only path (dashboard CI runs cost 20 to 27 minutes per PR). It writes a blocker packet with the cost.
- **Fills it today.** A fresh, cheap session (Sonnet or Haiku) that runs commands and reads outputs. The local Gemma helper can pre-screen but never stands in, per the house-model repo's grading.

#### Historian

- **Purpose.** Keep memory small, true, and resumable. Own the handoff standard and the retrospective.
- **Inputs.** The card, the PR, the session transcript tail, the coordination repo's machine log, the per-project `MEMORY.md` diffs.
- **Outputs.** One append-only log line per run in the machine log (allowed by the coordination repo's rules); the retro (section 3.1); a cold-start check: it opens a fresh context, reads only the card and the PR, and confirms it could resume. Memory promotions are proposed as a diff, never written directly.
- **Who checks it.** The Reviewer reads any proposed memory line that makes a claim about you against a quoted line you typed. The Librarian checks that nothing was written outside the four allowed stores.
- **Escalates when.** A proposed memory change contradicts a decision in EstateDecisions or RISK-DECISIONS.
- **Fills it today.** The catchup skill's logic run at the end of a session instead of the start; a Sonnet session is enough.

#### Scribe

- **Purpose.** Write what you will read. PR bodies, pages, docs, decision packets. Keep the wording plain and the facts tied to receipts.
- **Inputs.** The receipts block, the handoff block, the Reviewer and Verifier outputs.
- **Outputs.** The PR body in your standing format; a self-contained HTML page in the Artifact Library Inbox when the deliverable is a page; the decision packet when one is needed.
- **Who checks it.** The Reviewer checks that every number in the body has a receipt. The Historian checks the location and the title.
- **Escalates when.** Never on its own. It writes the packet for whichever role is escalating.
- **Fills it today.** The pr-writeup and stop-slop skills in any session.

#### Librarian

- **Purpose.** Keep the machine the way the standard says it should be: worktrees registered and in allowed nests, profile files unchanged by tests, scheduled tasks owned, footprints classified, hooks working. Report; never move or delete.
- **Inputs.** `git worktree list` across every repo in EstateMap; the hashes of `~/.claude/settings.json`, `kernel.md`, `CLAUDE.md`, and the rule-file pairs in `config/estate/rule-file-pairs.json`; `Get-ScheduledTask` against the register; folder sizes under the roots the standard names; the latest transcripts for hook errors.
- **Outputs.** A preflight report before a run and a postflight diff after it, with exit code 0 (clean) or 1 (findings). A manifest row per finding that needs your approval, in the standard's manifest shape, so the estate hour has its packet ready.
- **Who checks it.** The Verifier confirms each finding has a receipt. You approve manifests. Nothing the Librarian does is irreversible, so there is nothing else to check.
- **Escalates when.** A profile file changed during a run (that is the dead-hooks case); a worktree sits outside an allowed nest; a scheduled task appeared with no owner; a folder under a watched root grew by more than a set amount in a week.
- **Fills it today.** The branch-cleanup skill, `Invoke-EstateSweep.ps1`, the two register exporters, and a new short PowerShell 5.1 script that ties them together (Phase 0). Rung 1 only. Rung 3 (remove a clean, merged, registered worktree without asking) only after you are tired of saying yes, which is the ladder's own rule.

#### Sentinel (optional, already exists)

The Hermes sweeper and weekly review, plus ntfy for failures. The design adds one section to the sweeper prompt: "DECISIONS WAITING" in the packet shape of section 2.7. No new job.

#### Panel or Judge (optional, wide roster only)

For a dispute the Reviewer and Implementer cannot settle and that is not yours to settle: a three-seat panel with named dissent. This fork's roundtable package is the model (sealed openings, claims table, decision with dissent, chair pause). The estate repo's `Invoke-HybridAIReview.ps1` is the Windows-side equivalent. Use it rarely; log that it was used.

### 2.4 Plug and play: the role contract and the roster

A role contract is one Markdown file with fixed headings. Appendix C has the template. The headings are the interface: Purpose, Reads, Writes, Receipts it must leave, Checked by, Escalates when, May be filled by, May be merged with. A harness is assigned to a role by reading the file and the dispatch prompt. Nothing in a contract names a model or a product.

The roster is one JSON file that says, for today, which harness and model fill each role and how many of each may run. Changing the roster does not change any contract. Example:

```json
{
  "updated": "2026-10-12",
  "roles": {
    "router":      {"fill": "claude-code", "model": "opus",   "max": 1},
    "implementer": {"fill": ["claude-code", "codex"],         "max": 3},
    "reviewer":    {"fill": ["codex-exec-readonly", "agy"],   "max": 2, "must_differ_from": "implementer"},
    "verifier":    {"fill": "claude-code", "model": "sonnet", "max": 2},
    "historian":   {"fill": "claude-code", "model": "sonnet", "max": 1},
    "scribe":      {"fill": "claude-code", "model": "sonnet", "max": 1},
    "librarian":   {"fill": "powershell-script",              "max": 1}
  }
}
```

The `must_differ_from` line is the only hard constraint in the roster. It is the rule the Custody Board's completion-review already enforces: the reviewer model and harness differ from the author's.

### 2.5 Team size slides

| Size | Roles filled by separate sessions | When |
|---|---|---|
| Lean (3) | Lead (Router + Scribe + Historian), Implementer, Reviewer-Verifier | A one-repo fix; a review; a page. Most days. |
| Standard (6) | Router, Implementer, Reviewer, Verifier, Historian-Scribe, Librarian | A feature PR; an overnight build. |
| Wide (8 to 12) | All seven, two or three Implementers, two Reviewers, a Panel | A multi-repo change; parser, money, or security diffs; a night shift with two lanes. |

Collapse rules, so a small team stays honest:

- Reviewer may merge with Verifier. Implementer may never merge with Reviewer or Verifier.
- Historian may merge with Scribe or with Router. Historian may not merge with Implementer.
- Librarian is a script, so it costs nothing to keep separate.
- The Router decides the size per request and writes it on the card. The agreement's "small fixed number of agents" and "log what it leaves out" stand.

### 2.6 The review contract between roles

| Producer | Consumer | What the consumer must receive | What the consumer returns | Hard stop |
|---|---|---|---|---|
| Implementer | Reviewer | Diff, PR body, head SHA | Blockers only, each with a failing reproduction; or a one-line clean receipt | Two rounds, then one design choice for the owner |
| Implementer | Verifier | Head SHA, check commands, baseline | Commands with exit codes; CI link for the final head | No receipt means not verified; no exceptions |
| Reviewer | Verifier | Each reproduction | Confirmation that it fails before the fix and passes after | A reproduction that does not fail is logged against the Reviewer |
| Any role | Scribe | Receipts and handoff blocks | The body or page, every number traceable | A number without a receipt is removed, not softened |
| Any session | Librarian | Nothing; it reads the machine | Preflight and postflight reports | A changed profile file blocks ready-for-review until explained |
| Any role | Historian | The card, the PR, the transcript tail | The log line, the retro, the cold-start verdict | A run that cannot be resumed from the card and PR is not done |
| Router | Everyone | Dispatch prompt pointing at files | Acknowledgement by `start_run` on the card | A second `start_run` on a running card is refused by Custody Board already |

### 2.7 The owner as the appellate court

Three doors. Anything that does not fit one of them stays inside the team.

1. **Disagreement.** Two roles still disagree after two rounds. You get one design choice, with the two positions, the receipts for each, and a recommendation.
2. **owner-only decision.** Anything in EstateStandard section 2 (repo class, PEL evidence, life-ops, the frozen tracker, the business dashboard pair, credentials, the learning-loop ledgers, Hermes capability, Custody Board records, OneDrive structure); any RISK.md ladder promotion; any money, production, or client-facing effect; any deletion with no undo; anything you have marked decided.
3. **Blocker.** Only you can do it: a credential, sudo, physical presence, a paid CI run beyond the budget, or a read of a production clone the classifier blocks.

The packet is the same for all three doors, and it is the only shape in which work may reach you:

```
DECISION <short id> | door: disagreement | owner-only | blocker
Question: one sentence you can answer with a word or a number.
Recommendation: <A>, because <one line>.
A: what happens, reversible yes/no, cost.
B: what happens, reversible yes/no, cost.
Already done: receipts (command and exit code, or file:line), so you do not redo it.
Owning rule: quoted verbatim, if the subject is in EstateStandard section 2.
If no answer by <date>: what the team does (usually: nothing, card stays parked).
Answer here: session <name> | Custody Board card <id> | PR #<n>
```

Delivery, using only surfaces you already look at:

- The packet is the card's next action with `next_actor` set to the owner. The nightly Hermes sweeper already lists those cards; its prompt gains one line asking it to print packets in full.
- A blocker with a deadline inside 24 hours goes to ntfy, which the monitoring rules reserve for urgent, actionable items.
- `/catchup` collates open packets, verified against live state, when you want them before 21:00.
- Remote control stays on for sessions that may raise a packet, so you can answer from your phone.

Two anti-patterns are banned by the contract: bundling a section-2 subject with ordinary yes/no items (the standard's rail 11 already forbids it), and asking you to choose when the contract names a default.

### 2.8 Memory and continuity

The four stores stay four. The design only says who writes which, and when a write needs a second key.

| Store | Writer | Second key | Notes |
|---|---|---|---|
| Custody Board (custody) | Implementer checkpoints; Router assigns; Historian closes or parks | None for checkpoints; Historian's cold-start check before `close_card` | Already the one task store. The packet shape lives in the next action text, so no schema change is needed now. |
| The coordination repo's machine log | Historian, one line per run, plus the retro | Reviewer samples retros that claim something about you | Append-only own-machine file; allowed by the repo's rules. |
| The coordination repo `reference/` and the global template | Proposed as a PR by the Historian | You merge | Rule files have a Git source; this is how a pattern becomes a rule. |
| Learning-loop ledgers | `/learning-loop` only | You | Unchanged. Revive or retire is your call (see Decisions). |
| Per-project `MEMORY.md` | Any session | Historian reviews promotions weekly | Non-authoritative by standard; stays that way. |
| Hermes vault | Hermes | Unchanged | Out of scope. |

The handoff block is one shape, written in two places (the PR body and the card checkpoint), so a fresh session finds it either way:

```
HANDOFF
State: branch <name> at <sha>; PR #<n> draft|ready; card <id>.
Done: three lines, each with a receipt.
Not done: what, and why it stopped (blocker, out of scope, time).
Next action: one imperative sentence a stranger could execute.
Needs the owner: none | packet <id>.
Will bite you: the one thing the next session must know.
```

The Historian's cold-start test is the check: a fresh context reads only the card and the PR, and must be able to state the next action without the transcript. If it cannot, the run is not done.

---

## Part 3. Getting better without you prodding

### 3.1 A retrospective after every run

The Historian writes ten lines or fewer, appended to the machine log under a `retro:` tag:

- What the run was and its card id.
- Each time a role stopped and waited, and for what.
- Each time the owner had to type (counted from the transcript tail).
- Each rule that had to be re-supplied in the prompt, with the file that already states it.
- Each tool failure (auth, MCP, hook, sandbox).
- One proposed change, if any: a template line, a skill edit, a trip-wire.

The Reviewer of the next run reads the previous retro first. That is the second key: a retro that blames you, or that proposes a rule with no receipt, is struck.

### 3.2 From retro to rule

1. Three retros name the same friction. The Historian opens one PR against the coordination repo's global template or against a skill under `~/.claude/skills` (which has its Git source in the coordination repo).
2. The Reviewer reviews the PR as any other.
3. You merge it, or you do not. That is the whole ratification. The template drift check already exists (`scripts/Test-TemplateDrift.ps1`, which reported "none" today), so the installed copy follows.
4. A rule that was merged and still gets re-supplied in prompts three more times is a finding against the rule's wording, not against the agents. The Scribe rewrites it.

This replaces the idle learning loop for day-to-day improvement. It does not replace the loop's model of you; that is a separate decision (see Decisions).

### 3.3 Trip-wires

A trip-wire is a condition that triggers a review automatically, without anyone deciding to ask for one.

| Condition | Automatic action | Role | Exists today |
|---|---|---|---|
| Any change to `~/.claude/settings.json`, `kernel.md`, `~/.claude/CLAUDE.md`, a hook, or a rule-file pair during a run | Librarian postflight fails; Verifier parse-checks the file; PR cannot go ready until explained | Librarian, Verifier | No. The dead-hooks incident is the proof. The estate-repo memory note "verify settings pastes parse" is the manual version. |
| A PR touches a parser, money, security, `deploy/`, `scripts/<control-station>/`, or a scheduled-task registration | Two independent Reviewers before ready | Router | The rule exists in the agreement; nothing applies the label. |
| Any write to a production path: the business dashboard live clone, an installed copy under `%LOCALAPPDATA%`, Task Scheduler, Hermes `jobs.json`, a Docker stack | Librarian and Verifier receipts before you see it; the business dashboard live clone itself stays owner-only (see Decisions) | Librarian, Verifier | Partly: the dashboard repo's destructive-guard hook blocks some git operations and is fail-open. |
| "Done", "passing", "merged", "nothing running" without a receipt | Bounced by the Verifier; the Scribe removes the claim | Verifier | Written as non-negotiable 8; not enforced. |
| A card re-routed twice, or a Reviewer-Implementer stalemate after two rounds | Decision packet, door 1 | Router | The two-rounds rule exists; the packet does not. |
| A Custody Board run still `running` when its session ends | Historian marks it interrupted with a resume note | Historian | Custody Board recovers stale runs at restart; three interrupted runs sit there now. |
| Hook errors in a session transcript | Librarian finding with the hook block quoted | Librarian | No. |
| A new scheduled task, cron job, or automation | Must appear in the unattended register with an owner before it is enabled (check R11) | Librarian | The register exists; it is regenerated by hand. |
| A worktree outside an allowed nest, unregistered, or detached with no live session for 7 days | Manifest row for the estate hour | Librarian | The standard says so (R5); the monthly sweep has never run. |
| A folder under a watched root grows more than 5 GB in a week | Classified report: app-managed, repo evidence, scratch, or unknown | Librarian | No. |
| A memory line that states a preference of yours | Historian must quote the line you typed; otherwise it is struck | Historian, Reviewer | The rule exists ("do not turn agent failures into claims about the owner"); nothing checks it. |
| A deliverable page in the Inbox that links a local file | Scribe fixes before import, since one such file blocks every import | Scribe | The library README states the rule. |

### 3.4 The bottleneck meter

One number per week, computed by a script, not by feel: the count of your typed turns that fall into the buckets of section 1.2 (approve, nudge, verify, route, re-supply, hygiene, hand-step paste). Appendix A describes the extraction. The baseline for the three weeks before this document is about 330 such turns, or roughly 110 per week.

Targets, so the team can be judged:

- Phase 0 done: the meter runs and the baseline is recorded.
- Phase 1 done: nudges ("are you waiting on me?") and receipt-less claims are both under five per week.
- Phase 2 done: the weekly total is under half the baseline, and the median age of a card waiting on you is under three days.
- Kill criterion: if the total has not fallen by a third after Phase 1 has run for three weeks, stop and bring you one design choice instead of adding roles. That is the same rule the agreement applies to repeated review flaws.

---

## Part 4. Rollout

Each phase lands in this repository as files you can read and run. Adoption in the other repositories goes through the places that already own cross-repo rules (the coordination repo's template and the estate repo's `docs/core`), by PRs that you merge. This fork never edits those repositories on its own; that is its standing boundary.

### Phase 0: turn on tomorrow (this week)

What gets built, all under `agents/` in this repository:

1. `agents/README.md`: the loop in one page, and the three doors.
2. `agents/roles/<role>.md`: eight contracts from the template in Appendix C.
3. `agents/roster.json`: the example in section 2.4.
4. `agents/templates/handoff.md`, `agents/templates/decision-packet.md`, `agents/templates/receipts.md`: the three blocks, copied into PR bodies and cards.
5. `agents/librarian/Invoke-LibrarianCheck.ps1` (Windows PowerShell 5.1, read-only, labeled for the control station): hashes the profile rule files and checks that every hook path exists; lists worktrees per repo with age, dirty state, and registration; names worktrees in retired nests; measures the roots the standard watches and classifies the top folders; diffs `Get-ScheduledTask` against the register; greps the newest transcripts for hook errors. Exit 0 clean, 1 findings, with a Markdown report. Run by hand, or as `/librarian` from a short command file.
6. `agents/metrics/Measure-Prodding.py`: the bottleneck meter, run with `python -I`, reads the session JSONL files read-only, prints the weekly bucket counts.
7. Two cleanups you decide: remove the five dead hook blocks (the Custody Board card already asks), and merge PR #49 so a Windows test run cannot write them again.

What you can do after Phase 0: type `/librarian` and get a classified report of worktrees, disk, hooks, and tasks in under a minute; see one number for how much you prodded last week; hand any session a handoff block and a packet shape instead of explaining them.

Gate to Phase 1: the Librarian has run clean three times; the meter baseline is recorded in `agents/metrics/baseline.md`; two PRs in any repo have gone through Implementer, Reviewer, and Verifier with receipts.

Risk: none to data. The script reads; it does not move. The templates are text.

### Phase 1: the two-key rule (weeks 2 and 3)

1. `agents/reviewer/second-look.md`: the standing procedure for an independent review, and a command file `/second-look <PR>` that runs Codex exec in read-only mode or the agy wrapper against the PR and returns blockers only. Nothing is posted to GitHub by the tool; the Scribe attaches the result.
2. `agents/verifier/check-receipts.py`: reads a PR body and fails if a status claim has no receipt, or if the receipts block or handoff block is missing. Run locally before ready-for-review.
3. `agents/historian/retro.md`: the retro shape; the catchup skill learns to read `retro:` lines and open decision packets.
4. A coordination-repo PR (yours to merge) adding the handoff block, the packet shape, and the two-key rule to the global template, and retiring the `kernel.md` hook as decision D26 already asked.

What you can do after Phase 1: stop reading PRs for correctness and read them for intent; answer packets from your phone in one word; know that any "passing" you see had a command behind it.

Gate to Phase 2: ten PRs through the path; zero receipt-less claims bounced in the last five; nudges under five per week for two weeks.

### Phase 2: the Router and the packets (weeks 4 to 6)

1. `agents/router/ROUTER.md`: the standing procedure for the lead session: read the roster, read `brief_today`, dispatch linked sessions by role, refuse to implement, write packets. It uses the Claude desktop session-management tools you already have.
2. Custody Board: the packet shape in the next action of every `next_actor` set to the owner card; one line in the sweeper prompt (an agent-ops repo PR) so the 21:00 digest prints packets in full. No Custody Board schema change.
3. The estate hour: the Librarian produces the manifest for the two legacy worktree nests and any unregistered worktrees; you approve it once.
4. Registers: a weekly regeneration of the unattended and runtime registers from the pinned installed copy, landing as a PR (estate-repo change, yours to merge). This closes the "register goes stale in days" gap.

What you can do after Phase 2: give the Router a one-line request and get back a card, a PR, and a packet only if one is needed; stop naming repos, sessions, and models in prompts.

Gate to Phase 3: the weekly meter under half the baseline for three weeks; the median age of cards waiting on you under three days; the fork's CLI suite baselined green inside WSL on this machine, with the agent-teams live verification rerun here.

### Phase 3: move onto the fork's own rails (when the fork is proven here)

1. The team's peer questions move to `harness team` (team.v1) and tab channels, which already give bounded, durable, attributable asks and replies with evidence.
2. The Director and specialists use `harness orchestrator`, with one change to this fork: a Verifier task node that must succeed before `complete`. Today `complete` trusts the worker's self-report.
3. The fork's worktree sweep learns the Windows nests (`<repo>\.worktrees`, `<repo>\.claude\worktrees`, `dev\_wt`), report-only first.
4. Disputes that are not yours go to the roundtable package, with named dissent in `decision.md`.

What you can do after Phase 3: watch the whole team in one window, pause a role, and read the ledger of who asked whom what, without a transcript.

Gate: none after this; the meter and the retros carry on.

---

## Part 5. Green-light list for this week

| # | Shortfall | Fix | Owning role | Effort | Risk if skipped |
|---|---|---|---|---|---|
| 1 | Five dead hook blocks fail on every Claude Code event; `kernel.md` is printed twice | Back up `settings.json`, remove the five test-written blocks and the `kernel.md` hook, keep your own coordination-repo pull hook. The Custody Board card from today already holds the exact steps. | Librarian (you say yes; an attended session does it one step at a time) | 15 minutes | Every session keeps logging five failures; any real hook you add later is lost in the noise. |
| 2 | A Windows test run of this fork can rewrite your profile | Review and merge PR #49 (draft, test-only, verified against the profile hashes). | Verifier | 30 minutes | Item 1 recurs the next time someone runs the suite on Windows. |
| 3 | Nothing watches worktrees, hooks, tasks, or disk between the monthly sweep (never run) and your own audits | Build `Invoke-LibrarianCheck.ps1` and the `/librarian` command (Phase 0 item 5). | Librarian | 3 hours | The 2026-10-02 cleanup repeats by hand; the next profile leak goes unnoticed again. |
| 4 | "Passing" and "done" arrive without receipts, so you verify by hand | Add the receipts and handoff blocks to the PR templates of the repos that have one and to the pr-writeup skill; build `check-receipts.py`. | Scribe, Verifier | 2 hours | You keep catching wrong claims ("its empty, no tasks showing"). |
| 5 | Second-model review is manual and often from the same vendor | Make `/second-look` the default before ready-for-review, using Codex exec read-only for Claude-authored PRs and the agy wrapper or Claude code-review for Codex-authored ones. | Reviewer | 4 hours | Reviews keep coming from the sessions that did the work; Devin remains an unexplained bot. |
| 6 | Agents still ask you to merge routine PRs | Consolidate the three merge statements: the global rule stands (routine task-owned merges allowed on the exact head), the business dashboard stays owner-merge by its own CLAUDE.md, EstateMap's "the owner merges" line is corrected. One coordination-repo PR and one estate-repo PR. | Historian | 1 hour plus your two merges | Another hundred "approved" turns. |
| 7 | Fourteen cards wait on you with no deadline and no shape; three runs sit interrupted | One `/catchup` sitting using the packet shape: close, park with a trigger, or answer each; the Historian marks the three interrupted runs. | Router, Historian | 20 minutes of yours | The nightly digest keeps repeating the same list. |
| 8 | Two legacy worktree nests and five detached worktrees linger; one `.claude\worktrees` folder is unregistered | Librarian manifest for `dev\worktrees` (two dashboard worktrees, 660 MB, one with 11 uncommitted files flagged on 10-02) and the detached ones; you approve; non-force removal only. | Librarian | 1 hour | Nothing breaks; the mess reappears in the next audit. |
| 9 | The overnight prompt and the pickup prompt are typed by hand each time | A `/night` command that writes the dispatch (lanes, grant, stop rule, handoff block) and a `/morning` alias for catchup, so "make me proud" is one word. | Scribe | 1 hour | You keep narrating the same two paragraphs. |
| 10 | Three pr-writeup copies disagree; the Co-Authored-By reminder fights your rule | Delete the stale `~\.agents\skills\pr-writeup` copy, leave the plugin copy off, and add one line to the global template that the harness reminder is overridden by non-negotiable 5. | Historian | 30 minutes | An agent picks the wrong copy and arms auto-merge or adds a trailer. |

Items 1, 2, 7, and 8 need your word. Items 3, 4, 5, 9, and 10 can be built without it and reviewed as PRs. Item 6 needs two merges from you.

---

## Decisions only you can make

1. **the business dashboard live clone.** The design never touches the live clone, the deploy script, or the Docker stack. A Reviewer may read the live clone's `git log` only with your per-session approval, which the classifier already enforces. If you want the team to deploy, that is a separate RISK ruling and a separate document. Not proposed here.
2. **Where unattended agents may run.** The 2026-09-25 ruling moved delegated execution to the Linux agent host; Paperclip was retired on 2026-09-30; nothing replaced it. Every role in this design runs attended, inside sessions you start, except Hermes at rung 1. A waker that starts agents on the control station at 03:00 needs your ruling in RISK-DECISIONS first. Phase 2's Router runs while you are awake.
3. **The learning loop.** The cloud Routine is recorded as re-enabled with a next run on 2026-10-15. Options: let it run and keep the ledgers single-writer with the retros feeding it; or retire it and let the retros be the loop. Recommendation: let the 10-15 run happen, then decide on its brief.
4. **Librarian rung.** Rung 1 now. Promotion to rung 3 for exactly one idempotent action (remove a clean, merged, registered worktree that no session uses) when you are tired of approving that same manifest row.
5. **Merge authority wording.** Item 6 above. The global rule already supersedes "owner-only" defaults. Say whether the business dashboard stays the one exception.

---

## One steelman against this design

The strongest objection: this adds roles, and roles add tokens and ceremony. RISK.md says not to invent governance. You retired Paperclip on 2026-09-30 because it "felt like more maintenance" after "3 days of setting up and debugging for one attempted task." A Router, a Historian, and a Librarian could become the same thing.

Why it still holds: every role maps to a tool that already exists and that you already pay for when you run it by hand. The lean team is three sessions, which is fewer than the "multiple sessions" you said overwhelmed you on 2026-09-23. Phase 0 is scripts and text; it installs no service, no schedule, and no daemon. The meter is the kill switch: if your prodding count does not fall by a third after Phase 1, the design stops and you get one choice, not another phase.

---

## Appendix A. Evidence receipts

Measured on the control station, 2026-10-12, read-only unless stated.

- **Session transcripts.** 197 JSONL files under `~/.claude/projects/*/` with mtime on or after 2026-09-20; 81 contain human-authored turns dated in the window; 683 such turns after dropping task notifications, `/compact`, interruptions, pastes, and continuation summaries. Buckets by regex over turns of 700 characters or fewer; counts overlap. About 12 percent of "human" turns are dispatch wrappers or orchestrator messages, which inflates the handoff bucket slightly. AskUserQuestion: 64 tool uses across assistant turns (the estate repo 17, the agent-ops repo 15, Cowork 12, another repo 10, others 10). The extraction script and the filtered turn list are in this session's scratchpad, not in the repository; Phase 0 item 6 turns the method into a committed script.
- **Custody Board.** `brief_today` and `list_today` through the custody-board MCP at 20:47 UTC: `blocked_total` 14, `agent_owned_total` 11, `running_total` 0, three `agent_runs` with status `interrupted` (2026-10-07, 10-09, 10-11). A read-only SQLite count: 82 cards (51 done, 30 inbox, 1 cancelled); 860 change-log rows; October writers claude-code 329, hermes 21, codex 8, the custody-board repo 7, cursor 5, grok-bot 5, claude 2.
- **Dead hooks.** `~/.claude/settings.json` hook commands reference `autonomous-harness\.worktrees\baseline-cb242cf4c\cli\hook\notify.mjs` and `%TEMP%\hook-golden-jpM1qa`; `ls` on both: no such file. `grep -l MODULE_NOT_FOUND` over `~/.claude/projects/*/*.jsonl`: 16 files; 9 occurrences in this session's transcript. PR mcs-eng/autonomous-harness#49 body confirms the cause.
- **Disk.** `du -sh`: `Roaming\Claude` 16G, of which `vm_bundles\claudevm.bundle` 13G; `~/.claude/projects` 2.5G. Explorer measurements: `Documents\Codex` about 34 GB (largest 10.39 GB on 2026-10-02 `task-3`), `dev` 18.56 GB, 457.3 GB free on C:. The 2026-10-04 "Machine cleanup and performance audit" session recorded "Roaming\Claude 15 GB" among the large folders.
- **Worktrees.** `git worktree list` in the estate repo (5 entries including two Codex task folders and a local wiki mirror), the agent-ops repo (3), the business dashboard dev clone (5, including the two in `dev\worktrees` from 2026-09-28 at the same detached commit), the house-model repo (2), the custody-board repo (2), the coordination repo (5), autonomous-harness (3 before this branch). `ls` of `dev\worktrees`, `dev\_wt`, `dev\autonomous-harness-worktrees`, `~/.codex/worktrees` (30 entries).
- **Checkout lag.** `git status -sb` in the estate repo: behind 32. The business dashboard dev clone `main` 3 behind `origin/main`. The house-model repo `main` 237 behind `claude/workspace`; `nas/main` equals local `main`; branch `claude/survey-civil` present.
- **Scheduled work.** `Get-ScheduledTask` and `Get-ScheduledTaskInfo` on the control station; the generated `UnattendedRegister.md` (local copy 2026-10-04; origin 10-06): 70 entries, 16 unowned. Hermes `cron\jobs.json` read-only: three jobs enabled, last runs 2026-10-11, no delivery error. Claude Code `list_scheduled_tasks`: one registered task; four definitions on disk unregistered.
- **GitHub.** `gh pr list` and `gh api` reads: open PRs #48 and #49 here, #281 in the estate repo, #513 in the business dashboard; Devin bot comments on 13/25, 13/25, 1/25 recent merged PRs; the agent-ops repo ruleset has no required status checks; dashboard repo settings `allow_auto_merge: true`; the dashboard's CI runs of about 20 and 27 minutes.
- **Codex volume.** Count of files per day under `~/.codex/sessions/2026/10/`: 109 on 10-10, 50 on 10-11, 50 on 10-12.
- **Fork machinery.** Read in `cli/src/teams/`, `cli/src/orchestrator/`, `cli/src/lib/worktreeSweep.ts`, `store/agents/roundtable/`, `docs/agent-teams.md`, `docs/agent-teams-live-verification.md`, `docs/tab-channels.md`, `desktop/WINDOWS_QUICKSTART.md`, `desktop/WINDOWS_PORT.md`, `docs/fork-upkeep.md`. `docs/reviews/` and `OVERNIGHT_NOTES.md` do not exist in this repository.
- **Rule-file copies.** Hashes compared by the explorer: `~/.claude/CLAUDE.md` equals the coordination repo's global template; `Test-TemplateDrift.ps1` reported no drift; three `pr-writeup` copies with two distinct hashes; `kernel.md` text says it was retired on 2026-10-04 and its SessionStart hook is still present.

Not verified today: the cloud Routine store, the laptop, the NAS share state, the Hermes sweeper's delivered text, how Devin is triggered, and the exact un-imported count in the Artifact Library Inbox.

## Appendix B. Contradictions the team will hit first

1. Merge authority: global agreement (routine merges allowed) versus the business dashboard CLAUDE.md and EstateMap ("the owner merges").
2. Auto-merge: every document says off; the business dashboard's repository setting allows it; one pr-writeup copy says arm it.
3. Attribution: non-negotiable 5 bans trailers; the harness reminder in Claude Code sessions asks for them; 32 older house-model commits and recent the dashboard, the agent-ops repo, and house-model commits carry them.
4. CI as a gate: the agent-ops repo calls coverage a hard gate and enforces no required check; its CI does not run on later pushes to a ready PR.
5. Worktree nests: EstateStandard retires `dev\worktrees`; the agent-ops repo's night-shift doc still prescribes it.
6. Output locations: the standard says gitignored `evidence\` or `runs\` in the repo; the agent-ops repo commits `docs/review/`, leaves `docs/reviews/` untracked, and ignores `runs/`; the estate repo's review panels land in `Documents\HybridAIReviews`.
7. Pinned copies: the standard says unattended jobs run from installed, commit-pinned copies; only EstateSweepMonthly and the inference-pair watcher task do; HermesContainmentDigest, FolderHygiene, and a nightly mirror task run from working trees (finding F-046).
8. Independence: EstateMap calls Codex review independent; the agent-ops repo's 2026-10-08 review says prior audits came from the same Codex sessions that did the work.
9. Docs versus live: the Hermes cron README says the Cold Backstop is paused; it is enabled and ran. The local registers say two tasks are Ready; they are Disabled.
10. Task stores: Custody Board is "the one"; `NOW.md`, per-repo `STATUS.md`, `OVERNIGHT_NOTES.md`, the Hermes vault's `WORKBOARD.md`, and the machine log prose all still carry custody information.

## Appendix C. Role contract template

```markdown
# Role: <name>

## Purpose
One paragraph. What this role exists to prevent or produce.

## Reads
Files, cards, commands. Nothing that is not listed here.

## Writes
Files, cards, PR sections. Nothing that is not listed here.

## Receipts it must leave
The exact blocks (receipts, handoff, packet) and where they go.

## Checked by
The role that reads this role's output before it counts.

## Escalates when
The conditions, each tied to one of the three doors.

## May be filled by
Any harness that can read this file. Independence constraints, if any.

## May be merged with
Which other roles one session may hold at the same time, and which it may not.

## Rung
1 watch and talk, 2 propose, 3 act (allowlisted). Default 1.
```
