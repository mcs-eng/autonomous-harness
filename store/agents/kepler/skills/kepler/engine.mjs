// Two-body mission kernel for the Kepler studio.
//
// Heliocentric positions use J2000 Keplerian elements (Standish / JPL approximate
// elements) advanced only in mean anomaly. That is a concept ephemeris: no
// perturbations, no Earth-Moon split, no light-time. Lambert transfers are the
// universal-variable solution (one revolution, short or long way). Nothing here
// is a navigation product.

export const AU_KM = 149597870.7
export const MU_SUN = 1.32712440018e11 // km^3/s^2
export const DAY_S = 86400
export const J2000_JD = 2451545.0

/** @typedef {{ x: number, y: number, z: number }} V3 */

const ELEMENTS = {
  // a (AU), e, i, L, varpi, node — degrees, ecliptic of J2000.
  mercury: [0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
  venus: [0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
  earth: [1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
  mars: [1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
  jupiter: [5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
  saturn: [9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
  uranus: [19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
  neptune: [30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
}

const PHYSICAL = {
  sun: { radiusKm: 695700, mu: MU_SUN, color: '#ffd29a', label: 'Sun' },
  mercury: { radiusKm: 2439.7, mu: 22031.868, color: '#c4b6a6', label: 'Mercury' },
  venus: { radiusKm: 6051.8, mu: 324858.592, color: '#f0d7a8', label: 'Venus' },
  earth: { radiusKm: 6371.0, mu: 398600.4418, color: '#7eb6ff', label: 'Earth' },
  mars: { radiusKm: 3389.5, mu: 42828.375, color: '#e07a4c', label: 'Mars' },
  jupiter: { radiusKm: 69911, mu: 1.26686534e8, color: '#d4a574', label: 'Jupiter' },
  saturn: { radiusKm: 58232, mu: 3.7931187e7, color: '#e6d3a1', label: 'Saturn' },
  uranus: { radiusKm: 25362, mu: 5.793939e6, color: '#9fd6d2', label: 'Uranus' },
  neptune: { radiusKm: 24622, mu: 6.836529e6, color: '#6f8cff', label: 'Neptune' },
}

export const BODY_IDS = Object.keys(ELEMENTS)

export function bodyInfo(id) {
  const key = String(id || '').toLowerCase()
  if (!PHYSICAL[key] || key === 'sun' && !ELEMENTS[key]) {
    if (key === 'sun') return { id: 'sun', ...PHYSICAL.sun }
    return null
  }
  if (!ELEMENTS[key]) return null
  return { id: key, ...PHYSICAL[key] }
}

export function listBodies() {
  return BODY_IDS.map((id) => bodyInfo(id))
}

export function v3(x = 0, y = 0, z = 0) {
  return { x, y, z }
}

export function add(a, b) {
  return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z }
}

export function sub(a, b) {
  return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z }
}

export function mul(a, s) {
  return { x: a.x * s, y: a.y * s, z: a.z * s }
}

export function dot(a, b) {
  return a.x * b.x + a.y * b.y + a.z * b.z
}

export function cross(a, b) {
  return {
    x: a.y * b.z - a.z * b.y,
    y: a.z * b.x - a.x * b.z,
    z: a.x * b.y - a.y * b.x,
  }
}

export function norm(a) {
  return Math.hypot(a.x, a.y, a.z)
}

export function unit(a) {
  const n = norm(a)
  if (n === 0) throw new Error('zero vector')
  return mul(a, 1 / n)
}

export function clamp(n, lo, hi) {
  return Math.min(hi, Math.max(lo, n))
}

export function deg(rad) {
  return rad * 180 / Math.PI
}

export function rad(degrees) {
  return degrees * Math.PI / 180
}

/** UTC milliseconds → Julian Date. Treated as TT for this approximation. */
export function julianDate(when) {
  const ms = when instanceof Date ? when.getTime() : typeof when === 'number' ? when : Date.parse(when)
  if (!Number.isFinite(ms)) throw new Error(`bad date: ${when}`)
  return ms / 86400000 + 2440587.5
}

export function fromJulian(jd) {
  return new Date((jd - 2440587.5) * 86400000)
}

export function stumpff(z) {
  if (!Number.isFinite(z)) throw new Error('stumpff: z is not finite')
  if (Math.abs(z) < 1e-4) {
    const z2 = z * z
    const z3 = z2 * z
    return {
      C: 0.5 - z / 24 + z2 / 720 - z3 / 40320,
      S: 1 / 6 - z / 120 + z2 / 5040 - z3 / 362880,
    }
  }
  if (z > 0) {
    const s = Math.sqrt(z)
    return {
      C: (1 - Math.cos(s)) / z,
      S: (s - Math.sin(s)) / (s * z),
    }
  }
  const s = Math.sqrt(-z)
  return {
    C: (Math.cosh(s) - 1) / (-z),
    S: (Math.sinh(s) - s) / (s * (-z)),
  }
}

function solveKepler(meanAnomaly, eccentricity) {
  const M = Math.atan2(Math.sin(meanAnomaly), Math.cos(meanAnomaly))
  let E = eccentricity < 0.8 ? M : Math.PI
  for (let i = 0; i < 40; i++) {
    const f = E - eccentricity * Math.sin(E) - M
    const fp = 1 - eccentricity * Math.cos(E)
    const d = f / fp
    E -= d
    if (Math.abs(d) < 1e-14) break
  }
  return E
}

function rotatePerifocal(x, y, Omega, inc, omega) {
  const cO = Math.cos(Omega)
  const sO = Math.sin(Omega)
  const ci = Math.cos(inc)
  const si = Math.sin(inc)
  const cw = Math.cos(omega)
  const sw = Math.sin(omega)
  return {
    x: (cO * cw - sO * sw * ci) * x + (-cO * sw - sO * cw * ci) * y,
    y: (sO * cw + cO * sw * ci) * x + (-sO * sw + cO * cw * ci) * y,
    z: (sw * si) * x + (cw * si) * y,
  }
}

/** Heliocentric ecliptic state of a planet at a date. km and km/s. */
export function bodyState(id, when) {
  const key = String(id || '').toLowerCase()
  const el = ELEMENTS[key]
  if (!el) throw new Error(`unknown body: ${id}`)
  const [aAu, e, iDeg, Ldeg, wpiDeg, nodeDeg] = el
  const a = aAu * AU_KM
  const jd = julianDate(when)
  const dt = (jd - J2000_JD) * DAY_S
  const n = Math.sqrt(MU_SUN / (a * a * a))
  const M0 = rad(Ldeg - wpiDeg)
  const E = solveKepler(M0 + n * dt, e)
  const cosE = Math.cos(E)
  const sinE = Math.sin(E)
  const r = a * (1 - e * cosE)
  const nu = Math.atan2(Math.sqrt(1 - e * e) * sinE, cosE - e)
  const Omega = rad(nodeDeg)
  const inc = rad(iDeg)
  const omega = rad(wpiDeg - nodeDeg)
  const rx = r * Math.cos(nu)
  const ry = r * Math.sin(nu)
  const position = rotatePerifocal(rx, ry, Omega, inc, omega)
  const p = a * (1 - e * e)
  const scale = Math.sqrt(MU_SUN / p)
  const vx = -scale * Math.sin(nu)
  const vy = scale * (e + Math.cos(nu))
  const velocity = rotatePerifocal(vx, vy, Omega, inc, omega)
  return { id: key, r: position, v: velocity, radiusKm: r, elements: { aKm: a, e, inc } }
}

/** Sample a body's orbit at the epoch's elements (fixed ellipse, not the drifting year). */
export function bodyOrbit(id, steps = 180) {
  const key = String(id).toLowerCase()
  const el = ELEMENTS[key]
  if (!el) throw new Error(`unknown body: ${id}`)
  const [aAu, e, iDeg, , wpiDeg, nodeDeg] = el
  const a = aAu * AU_KM
  const Omega = rad(nodeDeg)
  const inc = rad(iDeg)
  const omega = rad(wpiDeg - nodeDeg)
  const pts = []
  for (let i = 0; i <= steps; i++) {
    const nu = (i / steps) * Math.PI * 2
    const r = a * (1 - e * e) / (1 + e * Math.cos(nu))
    pts.push(rotatePerifocal(r * Math.cos(nu), r * Math.sin(nu), Omega, inc, omega))
  }
  return pts
}

/**
 * Universal-variable Kepler step. Returns { r, v } after dt seconds.
 * One revolution of a bound orbit is the supported, tested case; hyperbolic
 * arcs use the same iteration.
 */
export function propagate(mu, r0, v0, dt) {
  if (!Number.isFinite(mu) || mu <= 0) throw new Error('propagate: mu')
  if (!Number.isFinite(dt)) throw new Error('propagate: dt')
  if (dt === 0) return { r: { ...r0 }, v: { ...v0 } }
  const r0n = norm(r0)
  const v0n = norm(v0)
  const rv = dot(r0, v0)
  const alpha = 2 / r0n - (v0n * v0n) / mu
  const sqrtMu = Math.sqrt(mu)
  let chi = alpha > 1e-12
    ? sqrtMu * dt * alpha
    : Math.sign(dt || 1) * sqrtMu * Math.abs(dt) / r0n
  if (!Number.isFinite(chi) || chi === 0) chi = sqrtMu * dt / r0n

  let rn = r0n
  for (let i = 0; i < 80; i++) {
    const z = alpha * chi * chi
    const { C, S } = stumpff(z)
    const F = (rv / sqrtMu) * chi * chi * C
      + (1 - alpha * r0n) * chi * chi * chi * S
      + r0n * chi
      - sqrtMu * dt
    const dF = (rv / sqrtMu) * chi * (1 - z * S) + (1 - alpha * r0n) * chi * chi * C + r0n
    const step = F / dF
    chi -= step
    if (Math.abs(step) < 1e-10) break
    if (i === 79 && Math.abs(step) > 1e-4) throw new Error('propagate: did not converge')
  }
  const z = alpha * chi * chi
  const { C, S } = stumpff(z)
  const f = 1 - (chi * chi / r0n) * C
  const g = dt - (chi * chi * chi / sqrtMu) * S
  const r = add(mul(r0, f), mul(v0, g))
  rn = norm(r)
  const fdot = (sqrtMu / (rn * r0n)) * chi * (z * S - 1)
  const gdot = 1 - (chi * chi / rn) * C
  const v = add(mul(r0, fdot), mul(v0, gdot))
  return { r, v }
}

function transferAngle(r1, r2, prograde) {
  const r1n = norm(r1)
  const r2n = norm(r2)
  const cosd = clamp(dot(r1, r2) / (r1n * r2n), -1, 1)
  let dth = Math.acos(cosd)
  const sense = cross(r1, r2).z
  const ccw = sense >= 0
  if (prograde && !ccw) dth = 2 * Math.PI - dth
  if (!prograde && ccw) dth = 2 * Math.PI - dth
  return dth
}

function yLambert(r1n, r2n, A, z) {
  const { C, S } = stumpff(z)
  return r1n + r2n + A * (z * S - 1) / Math.sqrt(C)
}

/**
 * One-revolution Lambert transfer. dt in seconds, vectors in km and km/s.
 * Returns departure and arrival heliocentric velocities.
 */
export function lambert(mu, r1, r2, dt, { prograde = true } = {}) {
  if (!(dt > 0)) throw new Error('lambert: time of flight must be positive')
  const r1n = norm(r1)
  const r2n = norm(r2)
  const dth = transferAngle(r1, r2, prograde)
  const denom = 1 - Math.cos(dth)
  if (denom <= 1e-10) throw new Error('lambert: transfer angle is 0° or 360°')
  const A = Math.sin(dth) * Math.sqrt(r1n * r2n / denom)
  if (!Number.isFinite(A) || Math.abs(A) < 1e-8) {
    throw new Error('lambert: transfer is too close to 180° for this solver; nudge a date by a day')
  }

  function F(z) {
    const { C, S } = stumpff(z)
    if (!(C > 0)) return NaN
    const y = yLambert(r1n, r2n, A, z)
    if (!(y > 0)) return NaN
    return (y / C) ** 1.5 * S + A * Math.sqrt(y) - Math.sqrt(mu) * dt
  }

  // y > 0 sets a floor on z. Scan for a sign change up to one revolution.
  let zLo = -4 * Math.PI
  for (let i = 0; i < 40; i++) {
    const y = yLambert(r1n, r2n, A, zLo)
    if (y > 0 && Number.isFinite(F(zLo))) break
    zLo += Math.PI / 2
  }
  const zHiMax = 4 * Math.PI * Math.PI * 0.999
  let lo = zLo
  let hi = zLo
  let flo = F(lo)
  let found = false
  const steps = 64
  for (let i = 1; i <= steps; i++) {
    hi = zLo + (zHiMax - zLo) * (i / steps)
    const fhi = F(hi)
    if (Number.isFinite(flo) && Number.isFinite(fhi) && flo * fhi <= 0) {
      found = true
      break
    }
    if (Number.isFinite(fhi)) {
      lo = hi
      flo = fhi
    }
  }
  if (!found) throw new Error('lambert: no one-revolution solution for this time of flight')

  let z = 0.5 * (lo + hi)
  for (let i = 0; i < 80; i++) {
    const mid = 0.5 * (lo + hi)
    const fmid = F(mid)
    if (!Number.isFinite(fmid)) {
      lo = mid
      continue
    }
    if (flo * fmid <= 0) hi = mid
    else {
      lo = mid
      flo = fmid
    }
    z = 0.5 * (lo + hi)
    if (Math.abs(hi - lo) < 1e-12) break
  }

  const y = yLambert(r1n, r2n, A, z)
  const f = 1 - y / r1n
  const g = A * Math.sqrt(y / mu)
  const gdot = 1 - y / r2n
  if (!(Math.abs(g) > 1e-8)) throw new Error('lambert: degenerate Lagrange coefficient')
  const v1 = mul(sub(r2, mul(r1, f)), 1 / g)
  const v2 = mul(sub(mul(r2, gdot), r1), 1 / g)
  return { v1, v2, dth, z, y }
}

/** Circular coplanar Hohmann between two heliocentric radii (km). */
export function hohmann(mu, r1, r2) {
  if (!(r1 > 0) || !(r2 > 0) || !(mu > 0)) throw new Error('hohmann: radii')
  if (Math.abs(r1 - r2) / Math.max(r1, r2) < 1e-9) throw new Error('hohmann: radii are equal')
  const a = (r1 + r2) / 2
  const vCirc1 = Math.sqrt(mu / r1)
  const vCirc2 = Math.sqrt(mu / r2)
  const vPeri = Math.sqrt(mu * (2 / r1 - 1 / a))
  const vApo = Math.sqrt(mu * (2 / r2 - 1 / a))
  const outward = r2 > r1
  return {
    aKm: a,
    tofSeconds: Math.PI * Math.sqrt(a ** 3 / mu),
    dvDepart: Math.abs(vPeri - vCirc1),
    dvArrive: Math.abs(vCirc2 - vApo),
    vDepart: vPeri,
    vArrive: vApo,
    outward,
  }
}

/**
 * Impulsive burn from a circular parking orbit onto a hyperbola with the
 * given excess speed. altitudeKm is above the body's mean radius.
 * The same expression is the circular-capture burn at arrival.
 */
export function orbitBurn(bodyId, altitudeKm, vInf) {
  const info = bodyInfo(bodyId)
  if (!info || bodyId === 'sun') throw new Error(`orbitBurn: ${bodyId}`)
  if (!(altitudeKm >= 0)) throw new Error('orbitBurn: altitude')
  if (!(vInf >= 0) || !Number.isFinite(vInf)) throw new Error('orbitBurn: vInf')
  const r = info.radiusKm + altitudeKm
  const vCirc = Math.sqrt(info.mu / r)
  const vEsc = Math.sqrt(2 * info.mu / r)
  const vBurn = Math.sqrt(vInf * vInf + vEsc * vEsc)
  return {
    radiusKm: r,
    altitudeKm,
    vCirc,
    vEsc,
    dv: vBurn - vCirc,
    c3: vInf * vInf,
  }
}

/** Lead angle of `target` ahead of `origin`, 0..360°, prograde about +Z. */
export function phaseAhead(origin, target) {
  const a = Math.atan2(origin.y, origin.x)
  const b = Math.atan2(target.y, target.x)
  let d = b - a
  while (d < 0) d += Math.PI * 2
  while (d >= Math.PI * 2) d -= Math.PI * 2
  return d
}

/** Required lead angle (radians) of the target for a circular Hohmann. */
export function hohmannPhase(mu, rOrigin, rTarget, tofSeconds) {
  const nTarget = Math.sqrt(mu / (rTarget ** 3))
  let phase = Math.PI - nTarget * tofSeconds
  phase %= Math.PI * 2
  if (phase < 0) phase += Math.PI * 2
  return phase
}

function assertMission(mission) {
  if (!mission || typeof mission !== 'object') throw new Error('mission is not an object')
  if (mission.spec !== 1) throw new Error('mission.spec must be 1')
  if (!mission.name || typeof mission.name !== 'string') throw new Error('mission.name is required')
  if (!Array.isArray(mission.ships) || mission.ships.length === 0) throw new Error('mission.ships is empty')
  if (mission.ships.length > 8) throw new Error('mission.ships: at most 8')
}

function parseDate(value, label) {
  const t = Date.parse(value)
  if (!Number.isFinite(t)) throw new Error(`${label} is not a date`)
  return new Date(t)
}

function legMode(leg) {
  const mode = (leg.mode || 'lambert').toLowerCase()
  if (mode !== 'lambert' && mode !== 'hohmann') throw new Error(`unknown leg mode: ${leg.mode}`)
  return mode
}

/**
 * Solve every leg. Findings use severity error | warning | info.
 * A mission can be drawn when Lambert/Hohmann produced a path; `ok` is false
 * when any error finding remains.
 */
export function solveMission(mission, { samples = 180 } = {}) {
  assertMission(mission)
  const findings = []
  const ships = []
  for (const ship of mission.ships) {
    if (!ship || typeof ship.id !== 'string' || !/^[a-z0-9][a-z0-9-]{0,31}$/.test(ship.id)) {
      findings.push({ severity: 'error', kind: 'ship', message: 'Each ship needs an id of lowercase letters, numbers, and hyphens.' })
      continue
    }
    const legsIn = Array.isArray(ship.legs) ? ship.legs : []
    if (legsIn.length === 0) {
      findings.push({ severity: 'error', kind: 'ship', ref: ship.id, message: `${ship.name || ship.id} has no legs.` })
    }
    const legs = []
    for (let i = 0; i < legsIn.length; i++) {
      const leg = legsIn[i] || {}
      const ref = `${ship.id}.${i}`
      try {
        legs.push(solveLeg(leg, ref, samples, findings))
      } catch (err) {
        findings.push({ severity: 'error', kind: 'leg', ref, message: err.message })
      }
    }
    ships.push({
      id: ship.id,
      name: ship.name || ship.id,
      color: typeof ship.color === 'string' ? ship.color : '#e8b86d',
      legs,
    })
  }
  const dv = ships.reduce((sum, ship) => sum + ship.legs.reduce((s, leg) => s + (leg.dvTotal || 0), 0), 0)
  const errors = findings.filter((f) => f.severity === 'error').length
  return {
    spec: 1,
    name: mission.name,
    notes: typeof mission.notes === 'string' ? mission.notes : '',
    ships,
    findings,
    dvTotal: dv,
    ok: errors === 0 && ships.some((s) => s.legs.length > 0),
  }
}

function solveLeg(leg, ref, samples, findings) {
  const from = String(leg.from || '').toLowerCase()
  const to = String(leg.to || '').toLowerCase()
  if (!ELEMENTS[from] || !ELEMENTS[to]) throw new Error(`${ref}: from/to must be planets, not "${from}" → "${to}"`)
  if (from === to) throw new Error(`${ref}: from and to are the same body`)
  const mode = legMode(leg)
  const depart = parseDate(leg.depart, `${ref} depart`)
  const prograde = leg.prograde !== false
  const parkingKm = leg.parkingKm == null ? 200 : Number(leg.parkingKm)
  const captureKm = leg.captureKm == null || leg.captureKm === false ? null : Number(leg.captureKm)
  if (!Number.isFinite(parkingKm) || parkingKm < 50) throw new Error(`${ref}: parkingKm must be at least 50`)
  if (captureKm != null && (!(captureKm >= 50))) throw new Error(`${ref}: captureKm must be at least 50, or omit it for a flyby`)

  const departState = bodyState(from, depart)
  let arrive
  let tof
  let v1
  let v2
  let r1
  let r2
  let dth = Math.PI
  let heliocentric = null

  if (mode === 'hohmann') {
    const h = hohmann(MU_SUN, departState.elements.aKm, bodyState(to, depart).elements.aKm)
    tof = h.tofSeconds
    if (tof > 15 * 365.25 * DAY_S) throw new Error(`${ref}: time of flight is over 15 years; this solver is one revolution`)
    arrive = new Date(depart.getTime() + tof * 1000)
    // Idealized coplanar ellipse in the departure body's plane, starting prograde.
    const radial = unit(departState.r)
    const normal = unit(cross(departState.r, departState.v))
    const pro = unit(cross(normal, radial))
    const a = h.aKm
    const e = Math.abs(h.aKm - departState.elements.aKm) / h.aKm
    const outward = departState.elements.aKm < bodyState(to, depart).elements.aKm
    const periDir = outward ? radial : mul(radial, -1)
    r1 = departState.r
    const path = []
    const nSamp = Math.max(16, samples)
    for (let s = 0; s <= nSamp; s++) {
      const nu = outward ? Math.PI * (s / nSamp) : Math.PI * (1 - s / nSamp)
      const scale = a * (1 - e * e) / (1 + e * Math.cos(nu))
      const local = add(mul(periDir, Math.cos(nu)), mul(pro, Math.sin(nu)))
      path.push(mul(unit(local), scale))
    }
    r2 = path[path.length - 1]
    v1 = mul(pro, h.vDepart)
    v2 = mul(pro, -h.vArrive) // direction is approximate; magnitudes are what the budget uses
    heliocentric = { dvDepart: h.dvDepart, dvArrive: h.dvArrive }
    dth = Math.PI
    const targetAtDepart = bodyState(to, depart)
    const required = hohmannPhase(MU_SUN, departState.elements.aKm, targetAtDepart.elements.aKm, tof)
    const actual = phaseAhead(departState.r, targetAtDepart.r)
    let miss = Math.abs(actual - required)
    if (miss > Math.PI) miss = Math.PI * 2 - miss
    const missDeg = deg(miss)
    if (missDeg > 12) {
      findings.push({
        severity: 'warning',
        kind: 'phase',
        ref,
        message: `${bodyInfo(to).label} leads ${bodyInfo(from).label} by ${deg(actual).toFixed(1)}°; a coplanar Hohmann on this date wants about ${deg(required).toFixed(1)}°. The drawn ellipse is the textbook transfer, not a rendezvous. Use mode "lambert" with an arrival date, or read the porkchop.`,
      })
    } else {
      findings.push({
        severity: 'info',
        kind: 'phase',
        ref,
        message: `Hohmann phase is within ${missDeg.toFixed(1)}° of the coplanar target.`,
      })
    }
    const vInfDep = h.dvDepart
    const vInfArr = h.dvArrive
    return finishLeg({
      leg, ref, from, to, mode, depart, arrive, tof, r1, r2, v1, v2, dth,
      path, parkingKm, captureKm, vInfDep, vInfArr, heliocentric, findings, samples,
    })
  }

  if (!leg.arrive) throw new Error(`${ref}: lambert legs need an arrive date`)
  arrive = parseDate(leg.arrive, `${ref} arrive`)
  tof = (arrive.getTime() - depart.getTime()) / 1000
  if (!(tof > 0)) throw new Error(`${ref}: arrival is not after departure`)
  if (tof > 15 * 365.25 * DAY_S) throw new Error(`${ref}: time of flight is over 15 years; this solver is one revolution`)
  r1 = departState.r
  const arriveState = bodyState(to, arrive)
  r2 = arriveState.r
  const solved = lambert(MU_SUN, r1, r2, tof, { prograde })
  v1 = solved.v1
  v2 = solved.v2
  dth = solved.dth
  const vInfDep = norm(sub(v1, departState.v))
  const vInfArr = norm(sub(v2, arriveState.v))
  let path
  try {
    path = sampleLambert(r1, v1, tof, samples)
  } catch (err) {
    if (err.message === 'propagate: did not converge') {
      throw new Error(`${ref}: Lambert miss; the one-revolution transfer does not reach ${bodyInfo(to).label}`)
    }
    throw err
  }
  const arrival = path[path.length - 1]
  const missKm = norm(sub(arrival, r2))
  if (!(missKm < 1e5)) {
    throw new Error(`${ref}: Lambert miss; the one-revolution transfer does not reach ${bodyInfo(to).label}`)
  }
  return finishLeg({
    leg, ref, from, to, mode, depart, arrive, tof, r1, r2, v1, v2, dth,
    path, parkingKm, captureKm, vInfDep, vInfArr, heliocentric, findings, samples,
  })
}

function sampleLambert(r0, v0, tof, samples) {
  const n = Math.max(16, samples)
  const path = []
  for (let i = 0; i <= n; i++) {
    const dt = tof * (i / n)
    path.push(propagate(MU_SUN, r0, v0, dt).r)
  }
  return path
}

function finishLeg(ctx) {
  const {
    ref, from, to, mode, depart, arrive, tof, r1, r2, v1, v2, dth,
    path, parkingKm, captureKm, vInfDep, vInfArr, findings,
  } = ctx
  const infoFrom = bodyInfo(from)
  const infoTo = bodyInfo(to)
  let minSun = Infinity
  for (const p of path) minSun = Math.min(minSun, norm(p))
  if (minSun < PHYSICAL.sun.radiusKm * 1.2) {
    findings.push({
      severity: 'error',
      kind: 'sun_approach',
      ref,
      message: `${ref} passes ${(minSun / PHYSICAL.sun.radiusKm).toFixed(2)} solar radii from the Sun's center.`,
    })
  } else if (minSun < 0.2 * AU_KM) {
    findings.push({
      severity: 'warning',
      kind: 'sun_approach',
      ref,
      message: `${ref} dips inside 0.2 AU (minimum ${(minSun / AU_KM).toFixed(3)} AU).`,
    })
  }

  const injection = orbitBurn(from, parkingKm, vInfDep)
  let capture = null
  if (captureKm != null) capture = orbitBurn(to, captureKm, vInfArr)
  if (injection.dv > 12) {
    findings.push({
      severity: 'warning',
      kind: 'high_deltav',
      ref,
      message: `Departure burn from ${infoFrom.label} is ${injection.dv.toFixed(2)} km/s. Chemical stages rarely carry that from a parking orbit.`,
    })
  }
  if (capture && capture.dv > 8) {
    findings.push({
      severity: 'warning',
      kind: 'high_deltav',
      ref,
      message: `Circular capture at ${infoTo.label} is ${capture.dv.toFixed(2)} km/s.`,
    })
  }

  const dvTotal = injection.dv + (capture ? capture.dv : 0)
  return {
    ref,
    from,
    to,
    mode,
    prograde: ctx.leg.prograde !== false,
    depart: depart.toISOString(),
    arrive: arrive.toISOString(),
    tofDays: tof / DAY_S,
    dthDeg: deg(dth),
    parkingKm,
    captureKm,
    vInfDepart: vInfDep,
    vInfArrive: vInfArr,
    injection,
    capture,
    dvTotal,
    minSunKm: minSun,
    path: path.map((p) => [round(p.x), round(p.y), round(p.z)]),
    departKm: [round(r1.x), round(r1.y), round(r1.z)],
    arriveKm: [round(r2.x), round(r2.y), round(r2.z)],
    v1: [v1.x, v1.y, v1.z],
    v2: [v2.x, v2.y, v2.z],
  }
}

function round(n) {
  return Math.round(n * 1000) / 1000
}

/**
 * Porkchop of departure date × time of flight.
 * Cell value is injection Δv plus circular-capture Δv (km/s), or null if the departure is in the past,
 * Lambert fails, the arc does not propagate to the target, or the flight is over 15 years.
 * `captureKm: null` is a flyby: the cell is injection Δv only.
 */
export function porkchop({
  from,
  to,
  depart0,
  departSpanDays = 180,
  tof0Days = 120,
  tofSpanDays = 280,
  nDep = 28,
  nTof = 22,
  parkingKm = 200,
  captureKm = 250,
  prograde = true,
} = {}) {
  const origin = String(from || 'earth').toLowerCase()
  const dest = String(to || 'mars').toLowerCase()
  if (!ELEMENTS[origin] || !ELEMENTS[dest] || origin === dest) throw new Error('porkchop: bodies')
  const t0 = parseDate(depart0, 'depart0').getTime()
  const dep = []
  const tof = []
  let best = null
  const cells = []
  for (let i = 0; i < nDep; i++) {
    const day = departSpanDays * (nDep === 1 ? 0 : i / (nDep - 1))
    dep.push(new Date(t0 + day * DAY_S * 1000).toISOString())
  }
  for (let j = 0; j < nTof; j++) {
    const days = tof0Days + tofSpanDays * (nTof === 1 ? 0 : j / (nTof - 1))
    tof.push(days)
  }
  for (let i = 0; i < nDep; i++) {
    const row = []
    for (let j = 0; j < nTof; j++) {
      const depart = new Date(dep[i])
      const arrive = new Date(depart.getTime() + tof[j] * DAY_S * 1000)
      let cell = null
      try {
        const r1 = bodyState(origin, depart)
        const r2 = bodyState(dest, arrive)
        const flight = tof[j] * DAY_S
        if (depart.getTime() < Date.now()) throw new Error('departure is in the past')
        if (flight > 15 * 365.25 * DAY_S) throw new Error('time of flight is over 15 years')
        const solved = lambert(MU_SUN, r1.r, r2.r, flight, { prograde })
        const path = sampleLambert(r1.r, solved.v1, flight, 180)
        const arrival = path[path.length - 1]
        if (!(norm(sub(arrival, r2.r)) < 1e5)) throw new Error('lambert miss')
        const vInfDep = norm(sub(solved.v1, r1.v))
        const vInfArr = norm(sub(solved.v2, r2.v))
        const inj = orbitBurn(origin, parkingKm, vInfDep)
        const cap = captureKm == null ? null : orbitBurn(dest, captureKm, vInfArr)
        const total = inj.dv + (cap ? cap.dv : 0)
        cell = {
          dv: total,
          injection: inj.dv,
          capture: cap ? cap.dv : null,
          vInfDepart: vInfDep,
          vInfArrive: vInfArr,
          c3: inj.c3,
        }
        if (!best || total < best.dv) {
          best = { i, j, depart: dep[i], arrive: arrive.toISOString(), tofDays: tof[j], ...cell }
        }
      } catch {
        cell = null
      }
      row.push(cell)
    }
    cells.push(row)
  }
  return {
    from: origin,
    to: dest,
    departures: dep,
    tofDays: tof,
    parkingKm,
    captureKm,
    cells,
    best,
  }
}

export function missionSpan(solved) {
  let t0 = Infinity
  let t1 = -Infinity
  for (const ship of solved.ships) {
    for (const leg of ship.legs) {
      const a = Date.parse(leg.depart)
      const b = Date.parse(leg.arrive)
      if (a < t0) t0 = a
      if (b > t1) t1 = b
    }
  }
  if (!Number.isFinite(t0)) {
    const now = Date.now()
    return { t0: now, t1: now + 200 * DAY_S * 1000 }
  }
  const pad = Math.max(10 * DAY_S * 1000, (t1 - t0) * 0.04)
  return { t0: t0 - pad, t1: t1 + pad }
}

export function formatReport(solved) {
  const lines = []
  lines.push(`# ${solved.name}`)
  lines.push('')
  lines.push('Concept trajectory from Kepler, a two-body studio. J2000 elements advanced in mean anomaly only. Not a flight ephemeris and not a navigation solution.')
  lines.push('')
  if (solved.notes) {
    lines.push(solved.notes)
    lines.push('')
  }
  lines.push(`Total impulsive Δv counted here: ${solved.dvTotal.toFixed(3)} km/s.`)
  lines.push('')
  for (const ship of solved.ships) {
    lines.push(`## ${ship.name}`)
    lines.push('')
    for (const leg of ship.legs) {
      const from = bodyInfo(leg.from).label
      const to = bodyInfo(leg.to).label
      lines.push(`### ${from} → ${to} (${leg.mode})`)
      lines.push('')
      lines.push(`- Depart ${leg.depart.slice(0, 10)}`)
      lines.push(`- Arrive ${leg.arrive.slice(0, 10)}`)
      lines.push(`- Time of flight ${leg.tofDays.toFixed(1)} days, transfer angle ${leg.dthDeg.toFixed(1)}°`)
      lines.push(`- v∞ depart ${leg.vInfDepart.toFixed(3)} km/s, C3 ${leg.injection.c3.toFixed(2)} km²/s²`)
      lines.push(`- Injection from ${leg.parkingKm} km: ${leg.injection.dv.toFixed(3)} km/s`)
      if (leg.capture) {
        lines.push(`- v∞ arrive ${leg.vInfArrive.toFixed(3)} km/s`)
        lines.push(`- Circular capture at ${leg.captureKm} km: ${leg.capture.dv.toFixed(3)} km/s`)
      } else {
        lines.push(`- Flyby. Arrival v∞ ${leg.vInfArrive.toFixed(3)} km/s. No capture burn is counted.`)
      }
      lines.push(`- Leg total ${leg.dvTotal.toFixed(3)} km/s`)
      lines.push(`- Closest solar approach ${(leg.minSunKm / AU_KM).toFixed(3)} AU`)
      lines.push('')
    }
  }
  if (solved.findings.length) {
    lines.push('## Findings')
    lines.push('')
    for (const f of solved.findings) {
      lines.push(`- ${f.severity}${f.ref ? ` (${f.ref})` : ''}: ${f.message}`)
    }
    lines.push('')
  }
  return lines.join('\n')
}

export function trajectoryCsv(solved) {
  const rows = ['ship,leg,t_iso,x_km,y_km,z_km']
  for (const ship of solved.ships) {
    for (const leg of ship.legs) {
      const t0 = Date.parse(leg.depart)
      const t1 = Date.parse(leg.arrive)
      leg.path.forEach((p, i) => {
        const t = new Date(t0 + (t1 - t0) * (i / Math.max(1, leg.path.length - 1))).toISOString()
        rows.push(`${ship.id},${leg.ref},${t},${p[0]},${p[1]},${p[2]}`)
      })
    }
  }
  return rows.join('\n') + '\n'
}

const FINDING_SEVERITY = new Set(['error', 'warning', 'info'])

export function verdictFromSolve(solved) {
  const errors = solved.findings.filter((f) => f.severity === 'error')
  const warnings = solved.findings.filter((f) => f.severity === 'warning')
  const ready = solved.ok && errors.length === 0
  let summary
  if (!solved.ships.some((s) => s.legs.length)) summary = 'No trajectory yet'
  else if (errors.length) summary = `${errors.length} error${errors.length === 1 ? '' : 's'} · ${solved.dvTotal.toFixed(2)} km/s`
  else if (warnings.length) summary = `${solved.dvTotal.toFixed(2)} km/s · ${warnings.length} warning${warnings.length === 1 ? '' : 's'}`
  else summary = `${solved.dvTotal.toFixed(2)} km/s · trajectory holds`
  const phases = [
    { id: 'ephemeris', name: 'Ephemeris', state: solved.ships.length ? 'done' : 'failed' },
    { id: 'transfer', name: 'Transfer', state: errors.some((f) => f.kind === 'leg' || f.kind === 'sun_approach') ? 'failed' : (solved.ok ? 'done' : 'active') },
    { id: 'budget', name: 'Budget', state: solved.ok ? (warnings.length ? 'active' : 'done') : 'pending' },
    { id: 'review', name: 'Review', state: ready ? 'done' : 'pending' },
  ]
  return {
    spec: 1,
    ready,
    summary: summary.slice(0, 200),
    findings: solved.findings.filter((f) => FINDING_SEVERITY.has(f.severity)).map((f) => ({
      severity: f.severity,
      kind: f.kind || 'note',
      message: f.message,
      ...(f.ref ? { ref: f.ref } : {}),
    })),
    artifact: 'mission.json',
    phases,
    updatedAt: new Date().toISOString(),
  }
}
