#!/usr/bin/env node
// Loopback studio for a Kepler workspace. Serves the pane, the mission, and the kernel.
import fs from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { solveMission, formatReport, trajectoryCsv, verdictFromSolve } from '../skills/kepler/engine.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const port = Number(process.env.HARNESS_VIEWER_PORT || process.argv[2] || 0)
const workspace = path.resolve(process.env.HARNESS_WORKSPACE || process.cwd())
if (!Number.isInteger(port) || port <= 0 || port > 65535) {
  console.error('HARNESS_VIEWER_PORT is required')
  process.exit(1)
}

const FILES = {
  '/': { file: path.join(here, 'studio.html'), type: 'text/html; charset=utf-8' },
  '/studio.js': { file: path.join(here, 'studio.js'), type: 'text/javascript; charset=utf-8' },
  '/studio.css': { file: path.join(here, 'studio.css'), type: 'text/css; charset=utf-8' },
  '/engine.mjs': { file: path.join(here, '../skills/kepler/engine.mjs'), type: 'text/javascript; charset=utf-8' },
}

function send(res, status, body, type, extra = {}) {
  const buf = Buffer.isBuffer(body) ? body : Buffer.from(body)
  res.writeHead(status, {
    'Content-Type': type,
    'Content-Length': buf.length,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    ...extra,
  })
  res.end(buf)
}

function publish(mission) {
  const solved = solveMission(mission)
  const verdict = verdictFromSolve(solved)
  const harness = path.join(workspace, '.harness')
  const delivery = path.join(workspace, 'delivery')
  fs.mkdirSync(harness, { recursive: true })
  fs.mkdirSync(delivery, { recursive: true })
  fs.writeFileSync(path.join(harness, 'verdict.json'), JSON.stringify(verdict, null, 2) + '\n')
  fs.writeFileSync(path.join(delivery, 'report.md'), formatReport(solved))
  fs.writeFileSync(path.join(delivery, 'trajectory.csv'), trajectoryCsv(solved))
  fs.writeFileSync(path.join(delivery, 'solved.json'), JSON.stringify(solved, null, 2) + '\n')
  return { solved, verdict }
}

function readMission() {
  const file = path.join(workspace, 'mission.json')
  const text = fs.readFileSync(file, 'utf8')
  return { text, mission: JSON.parse(text) }
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url || '/', 'http://127.0.0.1')
  try {
    if (req.method === 'GET' && url.pathname === '/mission.json') {
      const { text } = readMission()
      send(res, 200, text, 'application/json; charset=utf-8')
      return
    }
    if (req.method === 'POST' && url.pathname === '/mission.json') {
      const chunks = []
      let size = 0
      req.on('data', (chunk) => {
        size += chunk.length
        if (size > 200_000) {
          send(res, 413, JSON.stringify({ error: 'mission is over 200 KB' }), 'application/json')
          req.destroy()
          return
        }
        chunks.push(chunk)
      })
      req.on('end', () => {
        try {
          const mission = JSON.parse(Buffer.concat(chunks).toString('utf8'))
          publish(mission)
          fs.writeFileSync(path.join(workspace, 'mission.json'), JSON.stringify(mission, null, 2) + '\n')
          send(res, 200, JSON.stringify({ ok: true }), 'application/json')
        } catch (err) {
          send(res, 400, JSON.stringify({ error: err.message }), 'application/json')
        }
      })
      return
    }
    if (req.method === 'GET' && FILES[url.pathname]) {
      const item = FILES[url.pathname]
      send(res, 200, fs.readFileSync(item.file), item.type)
      return
    }
    send(res, 404, 'not found', 'text/plain; charset=utf-8')
  } catch (err) {
    send(res, 500, err.message, 'text/plain; charset=utf-8')
  }
})

server.listen(port, '127.0.0.1', () => {
  try {
    const { mission } = readMission()
    publish(mission)
  } catch (err) {
    console.error(err.message)
  }
  console.log(`kepler studio http://127.0.0.1:${port}/`)
})
