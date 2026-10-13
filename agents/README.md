# Agent team: roles, contracts, and checks

This folder is Phase 0 of the design in [docs/agent-team-design.md](../docs/agent-team-design.md). It holds files, not services. Nothing here runs on a schedule, installs a daemon, or edits a repository on its own.

## The idea in one paragraph

Work moves through roles, not through named agents. A role is a contract file under `roles/`. Any harness that can read the contract can fill the role, and a roster file says which harness fills which role today. Two rules keep the team honest without a human in the loop: a claim needs a receipt (the command and its exit code, or the file and line), and nothing reaches the owner on one agent's word (a second role leaves a receipt first). The owner is reached only through three doors: a disagreement two roles could not settle in two rounds, a decision only the owner holds, or a blocker only the owner can clear.

## What is here

| Path | What it is | Runs by itself |
|---|---|---|
| `roles/*.md` | One contract per role: Router, Planner, Implementer, Reviewer, Verifier, Historian, Scribe, Librarian | No |
| `roster.json` | Which harness and model fill each role today, and how many may run | No |
| `templates/` | The receipts block, the handoff block, the decision packet, and the retro, copied into PR bodies and custody cards | No |
| `librarian/Invoke-LibrarianCheck.ps1` | Read-only machine check: profile file hashes, hook paths, hook errors in recent transcripts, worktrees against allowed nests, scheduled tasks, folder sizes. Exit 0 clean, 1 findings | No. Run it by hand or from the `/librarian` command |
| `metrics/Measure-Prodding.py` | The bottleneck meter: counts the owner's typed turns spent approving, nudging, verifying, routing, re-supplying context, fixing tooling, and pasting hand-step output, per week | No. Run it by hand |
| `commands/` | Claude Code slash-command files for `/librarian` and `/night`. Copy them into `~/.claude/commands/` to use them from any session | No |

## How a piece of work moves

1. A request arrives. The Router names the repository, the lane (harness and model), the custody card, and the roles. It never implements.
2. The Implementer works in one worktree on one branch, opens a draft PR with the receipts block and the handoff block, and checkpoints the card.
3. The Reviewer, a different model or harness from the Implementer, reports blockers only, each with a failing reproduction, for at most two rounds. The Verifier reruns the repository's checks on the exact head and records command plus exit code.
4. The Scribe writes the PR body from the receipts. The Librarian confirms the machine is as it was. The Historian confirms a cold start could resume from the card and the PR, and writes the retro.
5. Only then does the PR go ready for review, or the card's next actor become the owner, and only in the decision-packet shape.

## Team size

The roles are fixed; the number of sessions is not. Lean is three sessions (Lead = Router + Scribe + Historian; Implementer; Reviewer-Verifier). Standard is six. Wide is eight to twelve. The Router sets the size per request and writes it on the card. Two collapse rules hold at every size: the Implementer never also reviews or verifies its own work, and the Historian never also implements.

## Phase 0 status

Source only. The scripts were run on the owner's machine on 2026-10-12 against known-good and known-bad states (see each script's README). Installing the two command files into a profile is a manual copy. Later phases are listed in the design document.
