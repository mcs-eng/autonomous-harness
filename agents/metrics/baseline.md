# Baseline

Recorded 2026-10-12 with `python -I Measure-Prodding.py --since 2026-09-20 --until 2026-10-12` on the owner's machine (222 transcript files read, exit 0).

| week | sessions | typed_turns | any_prodding | prodding_share |
|---|---|---|---|---|
| 2026-09-21 | 23 | 212 | 75 | 35.4% |
| 2026-09-28 | 26 | 252 | 109 | 43.3% |
| 2026-10-05 | 22 | 210 | 68 | 32.4% |
| total (incl. partial weeks) | 73 | 686 | 257 | 37.5% |

Bucket totals over the window: approve 106, nudge 38, verify 16, route 12, resupply 3, hygiene 50, handstep 57, handoff 10.

Targets from the design: nudges and receipt-less claims under five per week after Phase 1; weekly `any_prodding` under half the baseline after Phase 2. Kill criterion: no one-third drop after three weeks of Phase 1.

The `hygiene` bucket is loose (a sampled read found about a quarter of its matches were ordinary instructions that mention a worktree), so treat its weekly number as an upper bound until the patterns are tuned with `--explain hygiene`.
