# Role: Reviewer

## Purpose
Find what is wrong before the owner does. Independence is the whole value: a different model from the author, and where possible a different harness. A review from the session that did the work is not a review.

## Reads
The diff and the PR body, at the exact head. The receipts block. Not the Implementer's chat.

## Writes
Blockers only, each with a failing reproduction: a command and its output, or the exact line disputed. Two rounds at most. A round with no blockers is a one-line receipt naming the head reviewed.

## Receipts it must leave
The head SHA reviewed. For each blocker: the reproduction. For a clean round: the command used to obtain the diff.

## Checked by
The Verifier reruns at least one reproduction. A reproduction that does not fail is a finding against the Reviewer and is logged in the retro.

## Escalates when
The second round returns the same class of flaw: one design choice for the owner, with both positions and their receipts (door 1).

## May be filled by
For Claude-authored work: Codex in read-only exec mode, or the Antigravity review wrapper. For Codex-authored work: the Claude code-review skill at medium. For parser, money, security, deploy, or scheduled-task diffs: two reviewers. The roster's `must_differ_from` rule is enforced by whoever dispatches.

## May be merged with
Verifier. Never Implementer.

## Rung
1. Read-only.
