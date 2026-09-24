# Kepler mission files

`mission.json` is the whole design. Spec 1.

```json
{
  "spec": 1,
  "name": "Ares 2033",
  "notes": "One sentence the report will quote.",
  "ships": [
    {
      "id": "ares",
      "name": "Ares",
      "color": "#e8b86d",
      "legs": [
        {
          "from": "earth",
          "to": "mars",
          "mode": "lambert",
          "depart": "2033-04-19",
          "arrive": "2033-11-05",
          "parkingKm": 200,
          "captureKm": 250,
          "prograde": true
        }
      ]
    }
  ]
}
```

Bodies: `mercury`, `venus`, `earth`, `mars`, `jupiter`, `saturn`, `uranus`, `neptune`. Not the Sun, not the Moon. Earth is the Earth-Moon barycenter of the J2000 table.

- `mode: "lambert"` needs both dates. The kernel solves the universal-variable boundary problem and samples the arc.
- `mode: "hohmann"` needs `depart` only. It draws the coplanar ellipse between the two semi-major axes and warns when the real phase angle is more than 12° off the textbook lead. That ellipse is not a rendezvous.
- Omit `captureKm` for a flyby. Set it (kilometres above the mean radius) to count a circular capture burn.
- `parkingKm` is the departure circular orbit. Minimum 50.
- `prograde: false` takes the long way when the short way is the other sense.
- Up to 8 ships. Ship ids are lowercase letters, digits, and hyphens.
- A leg over 15 years, a reversed date, an unknown body, a path through the Sun, or a Lambert miss is an error. The verdict stays not ready.

## Commands

From the workspace:

```bash
node "$KEPLER_SKILLS/kepler/scripts/check.mjs"
```

`KEPLER_SKILLS` points at the package `skills/` directory. The script prints one summary line and writes:

- `.harness/verdict.json` — what the pane header shows
- `delivery/report.md` — the budget in words
- `delivery/trajectory.csv` — heliocentric kilometres
- `delivery/solved.json` — the path the studio already computed

## How to choose dates

A good Earth–Mars chemical window in this model is roughly 5.5–7 km/s for injection from 200 km plus circular capture near 250 km, and a flight of about half a year. If the first guess is far above that, move the dates. The studio's porkchop searches departure × time of flight and reports the cheapest cell in the grid. Use it, then save the dates it found. Do not claim a global optimum: the grid is coarse and one-revolution only.

Jupiter and beyond will usually warn on Δv. That warning is the result, not a bug. Leave it in the report.

## What to say

Quote the check output. Name the approximation in the same message as any number a person might repeat: two-body, J2000 elements, no perturbations, no launch vehicle, no navigation.

Elements are the JPL approximate Keplerian set (Standish), evaluated as published for JD 2451545.0, with rates ignored. Cite that if asked where the planets are.
