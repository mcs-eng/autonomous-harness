#!/usr/bin/env node
// Read mission.json, solve it, and write the verdict plus a report and a trajectory.
import fs from 'node:fs'
import path from 'node:path'
import { solveMission, formatReport, trajectoryCsv, verdictFromSolve } from '../engine.mjs'

const workspace = path.resolve(process.argv[2] || process.env.HARNESS_WORKSPACE || process.cwd())
const missionPath = path.join(workspace, 'mission.json')

function fail(message) {
  const verdict = {
    spec: 1,
    ready: false,
    summary: message.slice(0, 200),
    findings: [{ severity: 'error', kind: 'mission', message }],
    artifact: 'mission.json',
    phases: [
      { id: 'ephemeris', name: 'Ephemeris', state: 'failed' },
      { id: 'transfer', name: 'Transfer', state: 'pending' },
      { id: 'budget', name: 'Budget', state: 'pending' },
      { id: 'review', name: 'Review', state: 'pending' },
    ],
    updatedAt: new Date().toISOString(),
  }
  writeVerdict(verdict)
  console.error(message)
  process.exitCode = 1
}

function writeVerdict(verdict) {
  const dir = path.join(workspace, '.harness')
  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(path.join(dir, 'verdict.json'), JSON.stringify(verdict, null, 2) + '\n')
}

if (!fs.existsSync(missionPath)) {
  fail('mission.json is missing')
} else {
  let mission
  try {
    mission = JSON.parse(fs.readFileSync(missionPath, 'utf8'))
  } catch (err) {
    fail(`mission.json is not JSON (${err.message})`)
    process.exit(process.exitCode || 1)
  }
  let solved
  try {
    solved = solveMission(mission)
  } catch (err) {
    fail(err.message)
    process.exit(process.exitCode || 1)
  }
  const verdict = verdictFromSolve(solved)
  writeVerdict(verdict)
  const delivery = path.join(workspace, 'delivery')
  fs.mkdirSync(delivery, { recursive: true })
  fs.writeFileSync(path.join(delivery, 'report.md'), formatReport(solved))
  fs.writeFileSync(path.join(delivery, 'trajectory.csv'), trajectoryCsv(solved))
  fs.writeFileSync(path.join(delivery, 'solved.json'), JSON.stringify(solved, null, 2) + '\n')
  console.log(verdict.summary)
  if (!verdict.ready) process.exitCode = 1
}
