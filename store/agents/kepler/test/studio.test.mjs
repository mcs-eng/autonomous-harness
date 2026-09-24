import assert from 'node:assert/strict'
import { spawn, spawnSync } from 'node:child_process'
import { createServer } from 'node:net'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

function copyTemplate(dir) {
  fs.mkdirSync(dir, { recursive: true })
  fs.copyFileSync(path.join(root, 'template/mission.json'), path.join(dir, 'mission.json'))
}

test('the starter mission checks ready and writes a report', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kepler-'))
  copyTemplate(dir)
  const out = spawnSync(process.execPath, [path.join(root, 'skills/kepler/scripts/check.mjs'), dir], { encoding: 'utf8' })
  assert.equal(out.status, 0, out.stderr + out.stdout)
  const verdict = JSON.parse(fs.readFileSync(path.join(dir, '.harness/verdict.json'), 'utf8'))
  assert.equal(verdict.spec, 1)
  assert.equal(verdict.ready, true, JSON.stringify(verdict.findings))
  assert.match(verdict.summary, /km\/s/)
  assert.equal(verdict.artifact, 'mission.json')
  assert.match(fs.readFileSync(path.join(dir, 'delivery/report.md'), 'utf8'), /Ares 2033/)
  assert.match(fs.readFileSync(path.join(dir, 'delivery/trajectory.csv'), 'utf8'), /ares,ares\.0,/)
})

test('Best window treats a blank Capture field as a flyby', () => {
  const src = fs.readFileSync(path.join(root, 'viewer/studio.js'), 'utf8')
  const call = src.slice(src.indexOf('grid = porkchop'), src.indexOf('porkOpen = true'))
  assert.match(call, /captureRaw === '' \? null : Number\(captureRaw\)/)
  assert.doesNotMatch(call, /\|\|\s*250/)
})

test('a broken mission stays not ready', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kepler-'))
  fs.writeFileSync(path.join(dir, 'mission.json'), '{')
  const out = spawnSync(process.execPath, [path.join(root, 'skills/kepler/scripts/check.mjs'), dir], { encoding: 'utf8' })
  assert.notEqual(out.status, 0)
  const verdict = JSON.parse(fs.readFileSync(path.join(dir, '.harness/verdict.json'), 'utf8'))
  assert.equal(verdict.ready, false)
})

test('the studio serves the orrery and saves a mission back', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'kepler-'))
  copyTemplate(dir)
  const port = await freePort()
  const child = spawn(process.execPath, [path.join(root, 'viewer/viewer.mjs')], {
    env: { ...process.env, HARNESS_VIEWER_PORT: String(port), HARNESS_WORKSPACE: dir },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  let log = ''
  child.stdout.on('data', (chunk) => { log += chunk })
  child.stderr.on('data', (chunk) => { log += chunk })
  try {
    await waitFor(`http://127.0.0.1:${port}/`)
    const html = await fetch(`http://127.0.0.1:${port}/`).then((r) => r.text())
    assert.match(html, /Kepler/)
    const engine = await fetch(`http://127.0.0.1:${port}/engine.mjs`).then((r) => r.text())
    assert.match(engine, /export function lambert/)
    const mission = await fetch(`http://127.0.0.1:${port}/mission.json`).then((r) => r.json())
    mission.name = 'Saved from the pane'
    mission.ships[0].legs[0].to = 'venus'
    mission.ships[0].legs[0].depart = '2033-05-01'
    mission.ships[0].legs[0].arrive = '2033-10-01'
    const saved = await fetch(`http://127.0.0.1:${port}/mission.json`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(mission),
    })
    assert.equal(saved.status, 200, log)
    const disk = JSON.parse(fs.readFileSync(path.join(dir, 'mission.json'), 'utf8'))
    assert.equal(disk.name, 'Saved from the pane')
    assert.equal(disk.ships[0].legs[0].to, 'venus')
    const verdict = JSON.parse(fs.readFileSync(path.join(dir, '.harness/verdict.json'), 'utf8'))
    assert.equal(typeof verdict.ready, 'boolean')
    const refused = await fetch(`http://127.0.0.1:${port}/mission.json`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"spec":1}',
    })
    assert.equal(refused.status, 400)
    const outside = await fetch(`http://127.0.0.1:${port}/../harness.json`)
    assert.equal(outside.status, 404)
  } finally {
    child.kill('SIGTERM')
  }
})

function freePort() {
  return new Promise((resolve) => {
    const server = createServer()
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address()
      server.close(() => resolve(port))
    })
  })
}

async function waitFor(url) {
  const start = Date.now()
  let last = ''
  while (Date.now() - start < 5000) {
    try {
      const res = await fetch(url)
      if (res.ok) return
      last = String(res.status)
    } catch (err) {
      last = err.message
    }
    await new Promise((r) => setTimeout(r, 40))
  }
  throw new Error(`studio did not start: ${last}`)
}
