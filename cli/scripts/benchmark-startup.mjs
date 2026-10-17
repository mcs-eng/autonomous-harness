#!/usr/bin/env node
import { createHash } from 'node:crypto'
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, resolve } from 'node:path'
import { spawn } from 'node:child_process'
import { fileURLToPath } from 'node:url'

function option(name, fallback) {
  const at = process.argv.indexOf(name)
  return at < 0 ? fallback : process.argv[at + 1]
}

const before = option('--before')
const after = option('--after')
const repoRoot = fileURLToPath(new URL('../..', import.meta.url))
const target = resolve(option('--target', join(repoRoot, 'store', 'examples', 'hello-world')))
const runs = Number(option('--runs', '11'))
const warmups = Number(option('--warmups', '2'))

if (!before || !Number.isInteger(runs) || runs < 5 || !Number.isInteger(warmups) || warmups < 0) {
  console.error('usage: node scripts/benchmark-startup.mjs --before <entry.js> [--after <entry.js>] [--target <harness>] [--runs N] [--warmups N]')
  process.exit(2)
}

const builds = [
  { name: 'before', entry: resolve(before) },
  ...(after ? [{ name: 'after', entry: resolve(after) }] : []),
]
const workloads = [
  { name: 'help', argv: ['--help'] },
  { name: 'config-check', argv: ['dsh', 'check', target] },
  { name: 'local-update-noop', argv: ['update'] },
]
const DEV_VERSION = /^\d+\.\d+\.\d+-dev(?:\..+)?$/

function isolatedEnvironment(profile) {
  const keep = ['PATH', 'Path', 'SystemRoot', 'WINDIR', 'ComSpec', 'PATHEXT']
  const inherited = Object.fromEntries(keep.flatMap(key => process.env[key] === undefined ? [] : [[key, process.env[key]]]))
  const paths = {
    APPDATA: join(profile, 'appdata'),
    LOCALAPPDATA: join(profile, 'localappdata'),
    ADAPTER_DATA_DIR: join(profile, 'data'),
    ADAPTER_CLI_DIR: join(profile, 'not-installed'),
    HARNESS_AUTH_DIR: join(profile, 'auth'),
    HARNESS_BIN_DIR: join(profile, 'bin'),
    XDG_CONFIG_HOME: join(profile, 'config'),
    XDG_DATA_HOME: join(profile, 'share'),
    TEMP: join(profile, 'tmp'),
    TMP: join(profile, 'tmp'),
    TMPDIR: join(profile, 'tmp'),
  }
  for (const path of Object.values(paths)) mkdirSync(path, { recursive: true })
  return {
    ...inherited,
    ...paths,
    HOME: profile,
    USERPROFILE: profile,
    ADAPTER_COMPUTER_ID_FILE: join(profile, 'computer-id'),
    ADAPTER_COMPUTER_ID: '00000000000000000000000000000000',
    ADAPTER_UPDATE_DISABLE: 'true',
    ADAPTER_UPDATE_URL: 'http://127.0.0.1:1/metadata.json',
    DISABLE_GRID_INSTALL: 'true',
    DISABLE_HOOK_INSTALL: 'true',
    PORT: '1',
    BACKEND_WS_URL: 'http://127.0.0.1:1',
    WEB_URL: 'http://127.0.0.1:1',
    NO_COLOR: '1',
  }
}

function run(build, workload) {
  const profile = mkdtempSync(join(tmpdir(), 'harness-startup-'))
  const started = process.hrtime.bigint()
  let firstByte
  let stdout = Buffer.alloc(0)
  let stderr = Buffer.alloc(0)
  const markFirstByte = chunk => {
    if (firstByte === undefined) firstByte = process.hrtime.bigint()
    return chunk
  }
  return new Promise((accept, reject) => {
    let settled = false
    const finish = callback => {
      if (settled) return
      settled = true
      rmSync(profile, { recursive: true, force: true })
      callback()
    }
    const child = spawn(process.execPath, [build.entry, ...workload.argv], {
      cwd: repoRoot,
      env: isolatedEnvironment(profile),
      stdio: ['ignore', 'pipe', 'pipe'],
      windowsHide: true,
    })
    child.stdout.on('data', chunk => { stdout = Buffer.concat([stdout, markFirstByte(chunk)]) })
    child.stderr.on('data', chunk => { stderr = Buffer.concat([stderr, markFirstByte(chunk)]) })
    child.once('error', error => finish(() => reject(error)))
    child.once('close', (code, signal) => {
      const finished = process.hrtime.bigint()
      if (code !== 0 || signal || firstByte === undefined) {
        finish(() => reject(new Error(`${build.name}/${workload.name} failed: code=${code} signal=${signal}\n${stderr}`)))
        return
      }
      finish(() => accept({
        firstMs: Number(firstByte - started) / 1e6,
        totalMs: Number(finished - started) / 1e6,
        stdout,
        stderr,
        outputHash: createHash('sha256').update(stdout).update(Buffer.from([0])).update(stderr).digest('hex'),
      }))
    })
  })
}

const median = values => {
  const sorted = [...values].sort((a, b) => a - b)
  return sorted[Math.floor(sorted.length / 2)]
}

const versions = {}
for (const build of builds) {
  const sample = await run(build, { name: 'version-preflight', argv: ['version'] })
  const version = sample.stdout.toString('utf8').trim()
  if (sample.stderr.length || !DEV_VERSION.test(version)) {
    throw new Error(`${build.name} must report one local dev version before local-update-noop; got ${JSON.stringify(version)}`)
  }
  versions[build.name] = version
}

const samples = Object.fromEntries(builds.flatMap(build => workloads.map(workload => [`${build.name}/${workload.name}`, []])))
for (let round = 0; round < warmups + runs; round++) {
  const order = builds.length === 2 && round % 2 ? [builds[1], builds[0]] : builds
  for (const workload of workloads) {
    for (const build of order) {
      const sample = await run(build, workload)
      if (round >= warmups) samples[`${build.name}/${workload.name}`].push(sample)
    }
  }
}

const result = { runtime: process.version, runs, warmups, versions, workloads: {} }
for (const workload of workloads) {
  const row = {}
  for (const build of builds) {
    const values = samples[`${build.name}/${workload.name}`]
    row[build.name] = {
      firstByteMs: median(values.map(value => value.firstMs)),
      totalMs: median(values.map(value => value.totalMs)),
      outputHash: values[0].outputHash,
    }
    if (values.some(value => value.outputHash !== values[0].outputHash)) throw new Error(`${build.name}/${workload.name} output changed between runs`)
  }
  if (row.after) {
    if (row.before.outputHash !== row.after.outputHash) throw new Error(`${workload.name} output differs between before and after`)
    row.firstByteImprovementPct = (row.before.firstByteMs - row.after.firstByteMs) / row.before.firstByteMs * 100
    row.totalImprovementPct = (row.before.totalMs - row.after.totalMs) / row.before.totalMs * 100
  }
  result.workloads[workload.name] = row
}

console.log(JSON.stringify(result, null, 2))
