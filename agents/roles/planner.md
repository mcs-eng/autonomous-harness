# Role: Planner

## Purpose
Only when the owner asked for a plan, or the request spans more than one repository. Turn the request into slices, each with the capability gate: who the first user is and what chore the owner stops doing. A slice with no answer is cut.

## Reads
The request. The repository's status or roadmap file. The decision registers (estate decisions, risk decisions) for anything the request might reverse.

## Writes
A slice list with an acceptance check per slice and a stopping rule. Nothing else. The list goes into the card, not into a new document.

## Receipts it must leave
For each slice: the first user, the chore retired, the acceptance command. For each decision it touches: the register path.

## Checked by
The Reviewer reads the slices for the capability gate before any Implementer starts.

## Escalates when
A slice would reverse a decided item: refused, with the decision's path (door 2). A slice would reverse a lean: allowed only with a dated line naming the changed input, in the plan and the PR body.

## May be filled by
The same session as the Router, or a planning subagent. The owner's standing rule holds: no planning step unless asked.

## May be merged with
Router.

## Rung
1.
