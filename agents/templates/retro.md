# Retro

Ten lines or fewer, appended by the Historian to the machine log under a `retro:` tag after every run. The next run's Reviewer reads it first.

```
retro: <date> card <id> PR #<n>
waited: <each time a role stopped and waited, and for what>
owner typed: <count of owner turns during the run, from the meter or the transcript tail>
re-supplied: <each rule restated in a prompt, with the file that already states it>
tool failures: <auth | MCP | hook | sandbox | none>
proposed change: <one template line, skill edit, or trip-wire; or none>
```

Rules:
- A retro that blames the owner, or proposes a rule with no receipt, is struck by the Reviewer.
- Three retros naming the same friction become one PR against the rule's Git source. The owner ratifies by merging.
- A merged rule that is still re-supplied three more times is a finding against its wording, not against the agents.
