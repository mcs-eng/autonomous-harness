---
description: Start an overnight run with the team's standing rules, so the owner types one word instead of two paragraphs. Arguments: an optional goal.
---

You are starting an overnight run. The owner is going to sleep. Goal, if given: $ARGUMENTS. If no goal is given, read the repository's status file and the custody board's agent-owned cards and pick the one unfinished item that is most visible to the owner in the morning.

Standing rules for the night:

- Work in one worktree on one branch named `<agent>/<topic>`. Never on `main`. Never push to `main`. Never touch a production clone, an installed copy, a scheduled task, or a profile file.
- Checkpoint the custody card at least hourly. A silent run is interrupted after two hours.
- Every claim carries a receipt: command and exit code, or file and line. Fill the receipts block from `agents/templates/receipts.md`.
- Before marking anything ready, get a second look from a different model or harness (the Reviewer role) and rerun the repository's checks on the exact head (the Verifier role). You may not review your own work.
- Anything that needs the owner goes into one decision packet (`agents/templates/decision-packet.md`) on the card. Do not stop and wait for an answer; park that item and continue with what does not depend on it.
- Stop when the goal is met, when the checks are green on the final head, or when the next step needs the owner. Do not start a second goal.
- End with the handoff block (`agents/templates/handoff.md`) in the PR body and on the card, plus one "Morning read:" line naming the single file or page to open first.

Begin by writing the card checkpoint that names the goal, the branch, and the stop rule. Then work.
