import assert from 'node:assert/strict'
import { test } from 'node:test'
import {
  AU_KM, MU_SUN, DAY_S,
  bodyState, bodyOrbit, stumpff, propagate, lambert, hohmann, orbitBurn,
  phaseAhead, hohmannPhase, solveMission, porkchop, formatReport, trajectoryCsv,
  verdictFromSolve, julianDate,
} from '../skills/kepler/engine.mjs'

const close = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= tol, `${msg || ''} ${a} != ${b} (tol ${tol})`)

test('stumpff series matches the closed form away from zero and the known limits at zero', () => {
  const z0 = stumpff(0)
  close(z0.C, 0.5, 1e-15)
  close(z0.S, 1 / 6, 1e-15)
  const z = stumpff(0.25)
  close(z.C, (1 - Math.cos(0.5)) / 0.25, 1e-12)
  close(z.S, (0.5 - Math.sin(0.5)) / (0.5 * 0.25), 1e-12)
  const h = stumpff(-0.25)
  close(h.C, (Math.cosh(0.5) - 1) / 0.25, 1e-12)
})

test('a circular orbit returns to its start after one period', () => {
  const R = AU_KM
  const v = Math.sqrt(MU_SUN / R)
  const T = 2 * Math.PI * Math.sqrt(R ** 3 / MU_SUN)
  const r0 = { x: R, y: 0, z: 0 }
  const v0 = { x: 0, y: v, z: 0 }
  const back = propagate(MU_SUN, r0, v0, T)
  close(back.r.x, R, 1, 'x')
  close(back.r.y, 0, 1, 'y')
  close(back.r.z, 0, 1e-6, 'z')
  close(back.v.x, 0, 1e-6, 'vx')
  close(back.v.y, v, 1e-6, 'vy')
  const quarter = propagate(MU_SUN, r0, v0, T / 4)
  close(quarter.r.x, 0, 1, 'qx')
  close(quarter.r.y, R, 1, 'qy')
})

test('Lambert on a circular quarter-orbit recovers circular velocity', () => {
  const R = AU_KM
  const v = Math.sqrt(MU_SUN / R)
  const T = 2 * Math.PI * Math.sqrt(R ** 3 / MU_SUN)
  const r1 = { x: R, y: 0, z: 0 }
  const r2 = { x: 0, y: R, z: 0 }
  const solved = lambert(MU_SUN, r1, r2, T / 4)
  close(solved.v1.x, 0, 1e-4)
  close(solved.v1.y, v, 1e-4)
  close(solved.v1.z, 0, 1e-8)
  close(solved.v2.x, -v, 1e-4)
  close(solved.v2.y, 0, 1e-4)
  close(solved.dth, Math.PI / 2, 1e-12)
})

test('the long way around the same circle takes three quarters of the period', () => {
  const R = AU_KM
  const v = Math.sqrt(MU_SUN / R)
  const T = 2 * Math.PI * Math.sqrt(R ** 3 / MU_SUN)
  const r1 = { x: R, y: 0, z: 0 }
  const r2 = { x: 0, y: R, z: 0 }
  const solved = lambert(MU_SUN, r1, r2, 3 * T / 4, { prograde: false })
  close(solved.dth, 1.5 * Math.PI, 1e-12)
  close(normOf(solved.v1), v, 1e-3)
  assert.ok(solved.v1.y < 0, 'retrograde departure should start clockwise')
})

test('Earth–Mars Hohmann matches the textbook band', () => {
  const earth = bodyState('earth', '2000-01-01T12:00:00Z')
  const mars = bodyState('mars', '2000-01-01T12:00:00Z')
  const h = hohmann(MU_SUN, earth.elements.aKm, mars.elements.aKm)
  assert.ok(h.dvDepart > 2.9 && h.dvDepart < 3.1, h.dvDepart)
  assert.ok(h.dvArrive > 2.4 && h.dvArrive < 2.8, h.dvArrive)
  const days = h.tofSeconds / DAY_S
  assert.ok(days > 250 && days < 270, days)
  const phase = hohmannPhase(MU_SUN, earth.elements.aKm, mars.elements.aKm, h.tofSeconds)
  assert.ok(phase > 0 && phase < Math.PI, phase)
})

test('J2000 Earth sits near 1 AU and the orbit closes', () => {
  assert.equal(julianDate('2000-01-01T12:00:00Z'), 2451545.0)
  const earth = bodyState('earth', '2000-01-01T12:00:00Z')
  const au = normOf(earth.r) / AU_KM
  assert.ok(au > 0.98 && au < 1.02, au)
  const orbit = bodyOrbit('earth', 8)
  assert.equal(orbit.length, 9)
  close(normOf(orbit[0]), normOf(orbit[8]), 1)
})

test('a 200 km Earth departure with a Mars-like excess is a few km/s, not a heliocentric burn', () => {
  const burn = orbitBurn('earth', 200, 3)
  assert.ok(burn.dv > 3.5 && burn.dv < 4.2, burn.dv)
  close(burn.c3, 9, 1e-12)
  assert.throws(() => orbitBurn('earth', -1, 1))
  assert.throws(() => lambert(MU_SUN, { x: 1, y: 0, z: 0 }, { x: 2, y: 0, z: 0 }, 10))
})

test('phase ahead is the prograde lead about +Z', () => {
  close(phaseAhead({ x: 1, y: 0 }, { x: 0, y: 1 }), Math.PI / 2, 1e-12)
  close(phaseAhead({ x: 1, y: 0 }, { x: 1, y: 0 }), 0, 1e-12)
  close(phaseAhead({ x: 0, y: 1 }, { x: 1, y: 0 }), 1.5 * Math.PI, 1e-12)
})

test('a Lambert Earth–Mars leg solves, budgets, and refuses a reversed date', () => {
  const mission = {
    spec: 1,
    name: 'Probe',
    ships: [{
      id: 'probe',
      name: 'Probe',
      legs: [{
        from: 'earth',
        to: 'mars',
        depart: '2033-01-01',
        arrive: '2033-09-01',
        parkingKm: 200,
        captureKm: 300,
      }],
    }],
  }
  const solved = solveMission(mission, { samples: 40 })
  assert.equal(solved.ok, true)
  const leg = solved.ships[0].legs[0]
  assert.ok(leg.path.length === 41)
  assert.ok(leg.dvTotal > 4 && leg.dvTotal < 20, leg.dvTotal)
  assert.ok(leg.minSunKm > 0.5 * AU_KM)
  const report = formatReport(solved)
  assert.match(report, /Earth → Mars/)
  assert.match(trajectoryCsv(solved), /^ship,leg,t_iso/)
  const verdict = verdictFromSolve(solved)
  assert.equal(verdict.spec, 1)
  assert.equal(typeof verdict.ready, 'boolean')
  assert.equal(verdict.artifact, 'mission.json')

  const bad = structuredClone(mission)
  bad.ships[0].legs[0].arrive = '2032-01-01'
  const failed = solveMission(bad)
  assert.equal(failed.ok, false)
  assert.ok(failed.findings.some((f) => f.severity === 'error'))
})

test('porkchop returns a finite Earth–Mars window cheaper than a winter corner', () => {
  const grid = porkchop({
    from: 'earth',
    to: 'mars',
    depart0: '2033-01-01',
    departSpanDays: 120,
    tof0Days: 160,
    tofSpanDays: 140,
    nDep: 9,
    nTof: 7,
    parkingKm: 200,
    captureKm: 250,
  })
  assert.ok(grid.best, 'expected a solvable cell')
  assert.ok(grid.best.dv > 3 && grid.best.dv < 15, grid.best.dv)
  const finite = grid.cells.flat().filter(Boolean)
  assert.ok(finite.length > 10)
  const worst = finite.reduce((m, c) => Math.max(m, c.dv), 0)
  assert.ok(worst + 1e-6 >= grid.best.dv)
})

test('a blank capture prices the window on injection only and can move the best date', () => {
  const args = {
    from: 'earth',
    to: 'mars',
    depart0: '2033-04-19',
    departSpanDays: 180,
    tof0Days: 140,
    tofSpanDays: 220,
    nDep: 24,
    nTof: 18,
    parkingKm: 200,
  }
  const captured = porkchop({ ...args, captureKm: 250 })
  const flyby = porkchop({ ...args, captureKm: null })
  assert.equal(flyby.captureKm, null)
  assert.equal(flyby.best.capture, null)
  assert.equal(flyby.best.dv, flyby.best.injection)
  assert.notEqual(flyby.best.depart.slice(0, 10), captured.best.depart.slice(0, 10))
  const cells = flyby.cells.flat().filter(Boolean)
  assert.ok(cells.every((cell) => cell.capture == null && cell.dv === cell.injection))
})

test('an Earth–Mars Lambert just under 15 years is a miss, not a ready path', () => {
  const depart = Date.parse('2033-01-01')
  const arrive = Date.parse('2048-01-01')
  const days = (arrive - depart) / (DAY_S * 1000)
  assert.ok(days < 15 * 365.25, days)
  const mission = {
    spec: 1,
    name: 'Long Mars',
    ships: [{
      id: 'probe',
      legs: [{ from: 'earth', to: 'mars', depart: '2033-01-01', arrive: '2048-01-01' }],
    }],
  }
  const solved = solveMission(mission)
  assert.equal(solved.ok, false)
  assert.equal(solved.ships[0].legs.length, 0)
  assert.ok(solved.findings.some((f) => f.severity === 'error' && /Lambert miss/.test(f.message)))
  assert.equal(solved.findings.some((f) => /did not converge/.test(f.message)), false)
  assert.equal(verdictFromSolve(solved).ready, false)
})

test('a porkchop does not price a sub-15-year Lambert miss', () => {
  const depart = Date.parse('2033-01-01')
  const arrive = Date.parse('2048-01-01')
  const days = (arrive - depart) / (DAY_S * 1000)
  assert.ok(days < 15 * 365.25, days)
  const grid = porkchop({
    from: 'earth',
    to: 'mars',
    depart0: '2033-01-01',
    departSpanDays: 0,
    tof0Days: days,
    tofSpanDays: 0,
    nDep: 1,
    nTof: 1,
    parkingKm: 200,
    captureKm: 250,
  })
  assert.equal(grid.cells[0][0], null)
  assert.equal(grid.best, null)
})

test('a porkchop does not price a transfer over 15 years', () => {
  const shortDays = 14 * 365.25
  const longDays = 16 * 365.25
  assert.ok(shortDays < 15 * 365.25)
  assert.ok(longDays > 15 * 365.25)
  const grid = porkchop({
    from: 'earth',
    to: 'mars',
    depart0: '2033-01-01',
    departSpanDays: 0,
    tof0Days: shortDays,
    tofSpanDays: longDays - shortDays,
    nDep: 1,
    nTof: 2,
    parkingKm: 200,
    captureKm: 250,
  })
  assert.ok(grid.cells[0][0], 'a 14-year Earth–Mars arc still has a one-revolution price')
  assert.equal(grid.cells[0][1], null)
  assert.equal(grid.best.tofDays, shortDays)
  assert.notEqual(grid.best.dv, undefined)
})

test('a porkchop does not let a past departure win Best window', () => {
  const past = '2018-05-07T19:02:36.521Z'
  const future = '2033-04-19T00:00:00.000Z'
  assert.ok(Date.parse(past) < Date.now())
  assert.ok(Date.parse(future) > Date.now())
  const span = (Date.parse(future) - Date.parse(past)) / (DAY_S * 1000)
  const grid = porkchop({
    from: 'earth',
    to: 'mars',
    depart0: past,
    departSpanDays: span,
    tof0Days: 200,
    tofSpanDays: 0,
    nDep: 2,
    nTof: 1,
    parkingKm: 200,
    captureKm: 250,
  })
  assert.equal(grid.cells[0][0], null)
  assert.ok(grid.cells[1][0] && Number.isFinite(grid.cells[1][0].dv))
  assert.equal(grid.best.depart, future)
  assert.equal(grid.best.dv, grid.cells[1][0].dv)
})

test('an Earth–Neptune Hohmann over 15 years stays not ready', () => {
  const mission = {
    spec: 1,
    name: 'Neptune flyby',
    ships: [{
      id: 'probe',
      legs: [{ from: 'earth', to: 'neptune', mode: 'hohmann', depart: '2033-01-01' }],
    }],
  }
  const solved = solveMission(mission, { samples: 24 })
  assert.equal(solved.ok, false)
  assert.equal(solved.ships[0].legs.length, 0)
  assert.ok(solved.findings.some((f) => f.severity === 'error' && /15 years/.test(f.message)))
  assert.equal(verdictFromSolve(solved).ready, false)

  const mars = structuredClone(mission)
  mars.ships[0].legs[0].to = 'mars'
  const short = solveMission(mars, { samples: 24 })
  assert.equal(short.ok, true)
  assert.ok(short.ships[0].legs[0].tofDays < 15 * 365.25)
})

function normOf(v) {
  const x = v.x ?? v[0]
  const y = v.y ?? v[1]
  const z = v.z ?? v[2] ?? 0
  return Math.hypot(x, y, z)
}
