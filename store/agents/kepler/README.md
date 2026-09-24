# Kepler

A mission-design harness. The workspace is a `mission.json` file. The pane is an orrery that flies the solved trajectory, budgets the burns, and opens a porkchop for the departure window.

Planet positions use the JPL approximate Keplerian elements at JD 2451545.0 (Standish), advanced in mean anomaly only. Transfers are one-revolution Lambert solutions, or a coplanar Hohmann ellipse that says so when the planets are out of phase. It is a concept studio, not a flight ephemeris.

```bash
node --test test/*.test.mjs
node skills/kepler/scripts/check.mjs template
```

The package is unlisted (`store.json`) until a real studio screenshot is published. The kernel and the pane do not need the Store to run.
