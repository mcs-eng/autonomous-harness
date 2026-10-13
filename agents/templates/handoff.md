# Handoff block

Written in two places: the PR body (last section) and the custody card checkpoint. A fresh session must be able to resume from either without the transcript. The Historian's cold-start check is the test.

```
HANDOFF
State: branch <name> at <sha>; PR #<n> <draft | ready>; card <id>.
Done: <three lines at most, each with a receipt>
Not done: <what, and why it stopped: blocker | out of scope | time>
Next action: <one imperative sentence a stranger could execute>
Needs owner: none | packet <id>
Will bite you: <the one thing the next session must know>
```

Rules:
- "Next action" is a command or an edit, not a goal.
- If "Needs owner" is not "none", the packet exists on the card in the decision-packet shape.
- The overnight variant adds one line, "Morning read:", naming the single file or page to open first.
