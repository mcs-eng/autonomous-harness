import {
  AU_KM, BODY_IDS, DAY_S,
  bodyInfo, bodyOrbit, bodyState, missionSpan, porkchop, solveMission,
} from '/engine.mjs'

const sky = document.querySelector('#sky')
const ctx = sky.getContext('2d')
const title = document.querySelector('#title')
const clock = document.querySelector('#clock')
const budget = document.querySelector('#budget')
const findingsEl = document.querySelector('#findings')
const almanac = document.querySelector('#almanac')
const status = document.querySelector('#status')
const scrub = document.querySelector('#scrub')
const playBtn = document.querySelector('#play')
const pork = document.querySelector('#pork')
const porkCtx = pork.getContext('2d')
const porkHint = document.querySelector('#porkhint')
const form = document.querySelector('#plan')

const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']

const stars = Array.from({ length: 220 }, () => ({
  x: Math.random(),
  y: Math.random(),
  r: Math.random() * 1.3 + 0.2,
  a: Math.random() * 0.55 + 0.15,
}))

const orbits = Object.fromEntries(BODY_IDS.map((id) => [id, bodyOrbit(id, 220)]))

let mission = null
let solved = null
let missionText = ''
let dirty = false
let playing = false
let last = performance.now()
let span = { t0: Date.now(), t1: Date.now() + 1 }
let when = span.t0
let yaw = 0.5
let pitch = 0.55
let dist = 2.6 * AU_KM
let look = { x: 0, y: 0, z: 0 }
let lookTarget = { x: 0, y: 0, z: 0 }
let track = null
let grid = null
let porkOpen = false
let drag = null

const fromSel = document.querySelector('#from')
const toSel = document.querySelector('#to')
for (const id of BODY_IDS) {
  for (const sel of [fromSel, toSel]) {
    const opt = document.createElement('option')
    opt.value = id
    opt.textContent = bodyInfo(id).label
    sel.append(opt)
  }
}

function fmt(ms) {
  const d = new Date(ms)
  return `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()}`
}

function say(text) {
  status.textContent = text || ''
}

function legOf() {
  return mission?.ships?.[0]?.legs?.[0] || null
}

function fillForm() {
  const leg = legOf()
  if (!leg) return
  fromSel.value = leg.from
  toSel.value = leg.to
  document.querySelector('#depart').value = String(leg.depart).slice(0, 10)
  document.querySelector('#arrive').value = String(leg.arrive || leg.depart).slice(0, 10)
  document.querySelector('#mode').value = leg.mode || 'lambert'
  document.querySelector('#prograde').value = String(leg.prograde !== false)
  document.querySelector('#parking').value = leg.parkingKm ?? 200
  document.querySelector('#capture').value = leg.captureKm ?? ''
  document.querySelector('#arrive').disabled = (leg.mode || 'lambert') === 'hohmann'
}

function readForm(base) {
  const next = structuredClone(base)
  const ship = next.ships[0]
  const leg = ship.legs[0]
  leg.from = fromSel.value
  leg.to = toSel.value
  leg.depart = document.querySelector('#depart').value
  leg.arrive = document.querySelector('#arrive').value
  leg.mode = document.querySelector('#mode').value
  leg.prograde = document.querySelector('#prograde').value === 'true'
  leg.parkingKm = Number(document.querySelector('#parking').value)
  const cap = document.querySelector('#capture').value
  if (cap === '') delete leg.captureKm
  else leg.captureKm = Number(cap)
  if (leg.mode === 'hohmann') delete leg.arrive
  return next
}

function applySolve(nextMission) {
  mission = nextMission
  try {
    solved = solveMission(mission, { samples: 240 })
  } catch (err) {
    solved = { name: mission.name || 'Mission', ships: [], findings: [{ severity: 'error', kind: 'mission', message: err.message }], ok: false, dvTotal: 0 }
  }
  title.textContent = mission.name || 'Mission'
  span = missionSpan(solved)
  if (when < span.t0 || when > span.t1) when = span.t0
  renderDossier()
}

function renderDossier() {
  const leg = solved?.ships?.[0]?.legs?.[0]
  budget.replaceChildren()
  const rows = []
  if (leg) {
    rows.push(['Time of flight', `${leg.tofDays.toFixed(1)} days`])
    rows.push(['Injection', `${leg.injection.dv.toFixed(2)} km/s`])
    rows.push(['C3', `${leg.injection.c3.toFixed(2)} km²/s²`])
    rows.push(['Arrival v∞', `${leg.vInfArrive.toFixed(2)} km/s`])
    if (leg.capture) rows.push(['Capture', `${leg.capture.dv.toFixed(2)} km/s`])
    else rows.push(['Capture', 'Flyby'])
    rows.push(['Leg total', `${leg.dvTotal.toFixed(2)} km/s`])
  } else {
    rows.push(['Leg total', '—'])
  }
  for (const [k, v] of rows) {
    const p = document.createElement('div')
    p.className = 'stat'
    const a = document.createElement('span')
    a.textContent = k
    const b = document.createElement('b')
    b.textContent = v
    p.append(a, b)
    budget.append(p)
  }
  findingsEl.replaceChildren()
  for (const f of solved?.findings || []) {
    const p = document.createElement('p')
    p.className = f.severity
    p.textContent = f.message
    findingsEl.append(p)
  }
}

function project(p) {
  const x = p.x - look.x
  const y = p.y - look.y
  const z = (p.z || 0) - look.z
  const cy = Math.cos(yaw)
  const sy = Math.sin(yaw)
  const xr = cy * x + sy * y
  const yr = -sy * x + cy * y
  const cp = Math.cos(pitch)
  const sp = Math.sin(pitch)
  const depth = cp * yr - sp * z
  const up = sp * yr + cp * z
  const k = 1 / (1 + depth / (dist * 1.15))
  const scale = Math.min(window.innerWidth, window.innerHeight) * 0.42 / dist
  return {
    sx: window.innerWidth * 0.38 + xr * k * scale,
    sy: window.innerHeight * 0.52 - up * k * scale,
    depth,
    k,
    scale,
  }
}

function resize() {
  const dpr = Math.min(2, window.devicePixelRatio || 1)
  sky.width = Math.floor(window.innerWidth * dpr)
  sky.height = Math.floor(window.innerHeight * dpr)
}

function cssSize() {
  return { w: window.innerWidth, h: window.innerHeight }
}

function draw() {
  const { w, h } = cssSize()
  ctx.setTransform(sky.width / w, 0, 0, sky.height / h, 0, 0)
  ctx.clearRect(0, 0, w, h)
  const g = ctx.createRadialGradient(w * 0.38, h * 0.48, 40, w * 0.4, h * 0.5, Math.max(w, h) * 0.75)
  g.addColorStop(0, '#16130f')
  g.addColorStop(1, '#07080c')
  ctx.fillStyle = g
  ctx.fillRect(0, 0, w, h)
  for (const s of stars) {
    ctx.globalAlpha = s.a
    ctx.fillStyle = '#f4efe6'
    ctx.beginPath()
    ctx.arc(s.x * w, s.y * h, s.r, 0, Math.PI * 2)
    ctx.fill()
  }
  ctx.globalAlpha = 1

  const sun = project({ x: 0, y: 0, z: 0 })
  const glow = ctx.createRadialGradient(sun.sx, sun.sy, 2, sun.sx, sun.sy, 70)
  glow.addColorStop(0, 'rgba(255, 214, 160, 0.95)')
  glow.addColorStop(0.35, 'rgba(255, 170, 80, 0.28)')
  glow.addColorStop(1, 'rgba(255, 140, 40, 0)')
  ctx.fillStyle = glow
  ctx.beginPath()
  ctx.arc(sun.sx, sun.sy, 70, 0, Math.PI * 2)
  ctx.fill()

  ctx.lineWidth = 1
  for (const id of BODY_IDS) {
    const info = bodyInfo(id)
    ctx.beginPath()
    orbits[id].forEach((p, i) => {
      const q = project(p)
      if (i === 0) ctx.moveTo(q.sx, q.sy)
      else ctx.lineTo(q.sx, q.sy)
    })
    ctx.strokeStyle = hexAlpha(info.color, 0.28)
    ctx.stroke()
  }

  const bodies = []
  for (const id of ['sun', ...BODY_IDS]) {
    const info = bodyInfo(id)
    const state = id === 'sun' ? { r: { x: 0, y: 0, z: 0 } } : bodyState(id, when)
    const q = project(state.r)
    const radius = id === 'sun' ? 11 : Math.max(3.1, Math.pow(info.radiusKm, 0.22))
    bodies.push({ id, info, q, radius, r: state.r })
  }
  bodies.sort((a, b) => b.q.depth - a.q.depth)
  for (const b of bodies) {
    ctx.beginPath()
    ctx.fillStyle = b.info.color
    ctx.arc(b.q.sx, b.q.sy, b.radius, 0, Math.PI * 2)
    ctx.fill()
    if (track === b.id) {
      ctx.strokeStyle = '#f4efe6'
      ctx.stroke()
    }
    ctx.font = '12px ui-sans-serif, system-ui, sans-serif'
    ctx.fillStyle = 'rgba(231,225,214,0.82)'
    ctx.fillText(b.info.label, b.q.sx + b.radius + 5, b.q.sy - b.radius)
  }

  for (const ship of solved?.ships || []) {
    for (const leg of ship.legs) {
      strokePath(leg.path, ship.color || '#e8b86d', leg)
      const marker = placeOnLeg(leg, when)
      if (!marker) continue
      const q = project({ x: marker[0], y: marker[1], z: marker[2] })
      ctx.save()
      ctx.translate(q.sx, q.sy)
      ctx.rotate(Math.PI / 4)
      ctx.fillStyle = ship.color || '#e8b86d'
      ctx.fillRect(-4.5, -4.5, 9, 9)
      ctx.restore()
      ctx.font = '13px Palatino, Georgia, serif'
      ctx.fillStyle = '#f4efe6'
      ctx.fillText(ship.name, q.sx + 10, q.sy - 8)
    }
  }

  const day = fmt(when)
  if (almanac.dataset.day !== day) {
    almanac.dataset.day = day
    almanac.replaceChildren()
    for (const id of BODY_IDS) {
      const st = bodyState(id, when)
      const au = Math.hypot(st.r.x, st.r.y, st.r.z) / AU_KM
      const speed = Math.hypot(st.v.x, st.v.y, st.v.z)
      const p = document.createElement('p')
      p.textContent = `${bodyInfo(id).label}  ${au.toFixed(2)} AU · ${speed.toFixed(1)} km/s`
      almanac.append(p)
    }
  }
}

function strokePath(path, color, leg) {
  if (!path?.length) return
  const t0 = Date.parse(leg.depart)
  const t1 = Date.parse(leg.arrive)
  const points = path.map((p, i) => {
    const t = t0 + (t1 - t0) * (i / Math.max(1, path.length - 1))
    return { t, q: project({ x: p[0], y: p[1], z: p[2] }) }
  })
  const trace = (style, width, limit) => {
    ctx.beginPath()
    let pen = false
    for (const point of points) {
      if (limit != null && point.t > limit) break
      if (!pen) {
        ctx.moveTo(point.q.sx, point.q.sy)
        pen = true
      } else ctx.lineTo(point.q.sx, point.q.sy)
    }
    ctx.strokeStyle = style
    ctx.lineWidth = width
    ctx.stroke()
  }
  ctx.lineJoin = 'round'
  ctx.lineCap = 'round'
  trace(hexAlpha(color, 0.22), 7, null)
  trace(hexAlpha(color, 0.9), 2.4, null)
  trace('#f7f1e6', 2.6, when)
}

function placeOnLeg(leg, t) {
  const t0 = Date.parse(leg.depart)
  const t1 = Date.parse(leg.arrive)
  if (t < t0 || t > t1 || leg.path.length < 2) return t < t0 ? leg.path[0] : leg.path[leg.path.length - 1]
  const u = (t - t0) / (t1 - t0)
  const f = u * (leg.path.length - 1)
  const i = Math.min(leg.path.length - 2, Math.floor(f))
  const a = leg.path[i]
  const b = leg.path[i + 1]
  const w = f - i
  return [a[0] + (b[0] - a[0]) * w, a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w]
}

function hexAlpha(hex, alpha) {
  const n = hex.replace('#', '')
  const r = parseInt(n.slice(0, 2), 16)
  const g = parseInt(n.slice(2, 4), 16)
  const b = parseInt(n.slice(4, 6), 16)
  return `rgba(${r},${g},${b},${alpha})`
}

function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000)
  last = now
  if (playing) {
    const dur = 28
    when += ((span.t1 - span.t0) / dur) * dt
    if (when > span.t1) when = span.t0
    scrub.value = String(Math.round(1000 * (when - span.t0) / (span.t1 - span.t0)))
  }
  if (track && track !== 'sun') {
    const st = bodyState(track, when)
    lookTarget = { ...st.r }
  } else if (track === 'sun') lookTarget = { x: 0, y: 0, z: 0 }
  look.x += (lookTarget.x - look.x) * 0.08
  look.y += (lookTarget.y - look.y) * 0.08
  look.z += (lookTarget.z - look.z) * 0.08
  clock.textContent = fmt(when)
  draw()
  if (porkOpen) drawPork()
  requestAnimationFrame(frame)
}

function drawPork() {
  if (!grid) return
  const w = pork.clientWidth || 320
  const h = 180
  const dpr = Math.min(2, window.devicePixelRatio || 1)
  pork.width = Math.floor(w * dpr)
  pork.height = Math.floor(h * dpr)
  porkCtx.setTransform(dpr, 0, 0, dpr, 0, 0)
  const finite = grid.cells.flat().filter(Boolean).map((c) => c.dv)
  const lo = Math.min(...finite)
  const hi = Math.max(...finite)
  const cols = grid.tofDays.length
  const rows = grid.departures.length
  const cw = w / cols
  const ch = h / rows
  porkCtx.clearRect(0, 0, w, h)
  for (let i = 0; i < rows; i++) {
    for (let j = 0; j < cols; j++) {
      const cell = grid.cells[i][j]
      porkCtx.fillStyle = cell ? ramp(cell.dv, lo, hi) : '#1a120f'
      porkCtx.fillRect(j * cw, i * ch, cw + 0.5, ch + 0.5)
    }
  }
  const leg = legOf()
  if (leg && grid.best) {
    const dep = Date.parse(String(leg.depart))
    const arr = Date.parse(String(leg.arrive || ''))
    let bi = 0
    let bj = 0
    let best = Infinity
    grid.departures.forEach((d, i) => {
      grid.tofDays.forEach((days, j) => {
        const err = Math.abs(Date.parse(d) - dep) + Math.abs(days * DAY_S * 1000 - (arr - dep))
        if (err < best) {
          best = err
          bi = i
          bj = j
        }
      })
    })
    porkCtx.strokeStyle = '#f4efe6'
    porkCtx.strokeRect(bj * cw + 1, bi * ch + 1, cw - 2, ch - 2)
  }
}

function ramp(dv, lo, hi) {
  const t = hi === lo ? 0 : (dv - lo) / (hi - lo)
  const r = Math.round(28 + t * 150)
  const g = Math.round(90 - t * 40)
  const b = Math.round(88 - t * 50)
  return `rgb(${r},${g},${b})`
}

async function loadMission() {
  const res = await fetch('/mission.json', { cache: 'no-store' })
  const text = await res.text()
  if (dirty || text === missionText) return
  missionText = text
  applySolve(JSON.parse(text))
  fillForm()
  say('')
}

form.addEventListener('input', () => {
  dirty = true
  document.querySelector('#arrive').disabled = document.querySelector('#mode').value === 'hohmann'
})

form.addEventListener('submit', async (event) => {
  event.preventDefault()
  const next = readForm(mission)
  try {
    solveMission(next)
  } catch (err) {
    say(err.message)
    return
  }
  const res = await fetch('/mission.json', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(next),
  })
  if (!res.ok) {
    const body = await res.json().catch(() => ({ error: res.statusText }))
    say(body.error || 'Save failed')
    return
  }
  dirty = false
  missionText = ''
  await loadMission()
  say('Saved mission.json')
})

document.querySelector('#mode').addEventListener('change', () => {
  document.querySelector('#arrive').disabled = document.querySelector('#mode').value === 'hohmann'
})

document.querySelector('#window').addEventListener('click', async () => {
  const leg = legOf()
  if (!leg) return
  say('Searching the window…')
  await new Promise((r) => setTimeout(r, 20))
  const captureRaw = document.querySelector('#capture').value
  grid = porkchop({
    from: fromSel.value,
    to: toSel.value,
    depart0: document.querySelector('#depart').value,
    departSpanDays: 180,
    tof0Days: 140,
    tofSpanDays: 220,
    nDep: 24,
    nTof: 18,
    parkingKm: Number(document.querySelector('#parking').value) || 200,
    captureKm: captureRaw === '' ? null : Number(captureRaw),
    prograde: document.querySelector('#prograde').value === 'true',
  })
  porkOpen = true
  pork.hidden = false
  porkHint.hidden = false
  if (!grid.best) {
    say('No one-revolution transfer in this grid.')
    return
  }
  document.querySelector('#depart').value = grid.best.depart.slice(0, 10)
  document.querySelector('#arrive').value = grid.best.arrive.slice(0, 10)
  document.querySelector('#mode').value = 'lambert'
  document.querySelector('#arrive').disabled = false
  dirty = true
  applySolve(readForm(mission))
  say(`Best cell ${grid.best.dv.toFixed(2)} km/s. Save to keep it.`)
})

document.querySelector('#chart').addEventListener('click', async () => {
  porkOpen = !porkOpen
  pork.hidden = !porkOpen
  porkHint.hidden = !porkOpen
  if (porkOpen && !grid) document.querySelector('#window').click()
})

pork.addEventListener('click', (event) => {
  if (!grid) return
  const rect = pork.getBoundingClientRect()
  const j = Math.min(grid.tofDays.length - 1, Math.floor((event.clientX - rect.left) / rect.width * grid.tofDays.length))
  const i = Math.min(grid.departures.length - 1, Math.floor((event.clientY - rect.top) / rect.height * grid.departures.length))
  const cell = grid.cells[i][j]
  if (!cell) {
    say('That cell has no one-revolution solution.')
    return
  }
  const depart = grid.departures[i]
  const arrive = new Date(Date.parse(depart) + grid.tofDays[j] * DAY_S * 1000)
  document.querySelector('#depart').value = depart.slice(0, 10)
  document.querySelector('#arrive').value = arrive.toISOString().slice(0, 10)
  document.querySelector('#mode').value = 'lambert'
  dirty = true
  applySolve(readForm(mission))
  say(`${cell.dv.toFixed(2)} km/s. Save to keep this window.`)
})

playBtn.addEventListener('click', () => {
  playing = !playing
  playBtn.textContent = playing ? 'Pause' : 'Play'
})

scrub.addEventListener('input', () => {
  playing = false
  playBtn.textContent = 'Play'
  const u = Number(scrub.value) / 1000
  when = span.t0 + (span.t1 - span.t0) * u
})

for (const button of document.querySelectorAll('[data-view]')) {
  button.addEventListener('click', () => {
    track = null
    lookTarget = { x: 0, y: 0, z: 0 }
    const view = button.dataset.view
    dist = view === 'inner' ? 2.2 * AU_KM : view === 'outer' ? 36 * AU_KM : 8 * AU_KM
  })
}

sky.addEventListener('pointerdown', (event) => {
  drag = { x: event.clientX, y: event.clientY, yaw, pitch }
  sky.classList.add('dragging')
  sky.setPointerCapture(event.pointerId)
})

sky.addEventListener('pointermove', (event) => {
  if (!drag) return
  yaw = drag.yaw - (event.clientX - drag.x) * 0.005
  pitch = Math.max(0.15, Math.min(1.2, drag.pitch + (event.clientY - drag.y) * 0.004))
})

sky.addEventListener('pointerup', (event) => {
  const moved = drag && Math.hypot(event.clientX - drag.x, event.clientY - drag.y) > 4
  drag = null
  sky.classList.remove('dragging')
  if (moved) return
  const hit = pick(event.clientX, event.clientY)
  track = hit
  if (!hit) lookTarget = { x: 0, y: 0, z: 0 }
})

sky.addEventListener('wheel', (event) => {
  event.preventDefault()
  dist *= event.deltaY > 0 ? 1.08 : 0.92
  dist = Math.max(0.15 * AU_KM, Math.min(80 * AU_KM, dist))
}, { passive: false })

function pick(x, y) {
  let best = null
  let bestD = 18
  const ids = ['sun', ...BODY_IDS]
  for (const id of ids) {
    const r = id === 'sun' ? { x: 0, y: 0, z: 0 } : bodyState(id, when).r
    const q = project(r)
    const d = Math.hypot(q.sx - x, q.sy - y)
    if (d < bestD) {
      bestD = d
      best = id
    }
  }
  return best
}

window.addEventListener('resize', resize)
window.addEventListener('keydown', (event) => {
  if (event.target.matches('input, select')) return
  if (event.code === 'Space') {
    event.preventDefault()
    playBtn.click()
  }
})

resize()
await loadMission()
setInterval(() => { if (!dirty) loadMission().catch((err) => say(err.message)) }, 1500)
requestAnimationFrame(frame)
