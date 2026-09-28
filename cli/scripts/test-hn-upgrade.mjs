/** Packaged CLI upgrade smoke test. Run after `npm run bundle`, optionally with the previous
 * published cli.js and a frozen native hn binary as the second and third arguments. All state,
 * launchers and requests stay in a disposable home and a guarded loopback fixture. */
import assert from 'node:assert/strict'
import { execFile } from 'node:child_process'
import { createHash } from 'node:crypto'
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, rmSync, symlinkSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { promisify } from 'node:util'

const run = promisify(execFile)
const candidate = resolve(process.argv[2] || 'dist/cli.js')
const previous = process.argv[3] && resolve(process.argv[3])
const native = process.argv[4] && resolve(process.argv[4])
const bytes = readFileSync(candidate)
const notify = readFileSync(join(dirname(candidate), 'notify.mjs'))
const root = mkdtempSync(join(tmpdir(), 'hn-upgrade-'))
const home = join(root, "home with ' quotes")
const cliDir = join(home, '.harness', 'cli')
const bin = join(home, '.local', 'bin')
const cli = join(cliDir, 'cli.js')
const harness = join(bin, 'harness')
const hn = join(bin, 'hn')
const prefix = `hn-upgrade-${process.pid}`
const port = 19449
assert(port >= 19440 && port <= 19449)
const base = `http://127.0.0.1:${port}`
const quote = value => `'${value.replace(/'/g, `'\\''`)}'`
const sha = data => createHash('sha256').update(data).digest('hex')
const tui = join(root, 'tui-fixture')
const recorder = join(root, 'record.mjs')
// Do not inherit auth, sockets, tmux, data directories or a real daemon's port.
const env = {
  HOME: home, PATH: `${bin}:${dirname(process.execPath)}:/usr/bin:/bin`,
  PORT: String(port), HN_SOCKET_NAME: prefix, HN_TMPDIR: root,
  HARNESS_TUI_BIN: tui, ADAPTER_UPDATE_DISABLE: 'true',
  ADAPTER_UPDATE_URL: `${base}/metadata.json`, HARNESS_STORE_CATALOG_URL: `${base}/catalog.json`,
  ADAPTER_RUNTIME_METADATA_URL: `${base}/runtime.json`, ADAPTER_GRID_RUNTIME_METADATA_URL: `${base}/grid.json`,
  SHELL: '/bin/sh', TERM: 'xterm-256color',
}
const options = { env, cwd: root, timeout: 20_000, encoding: 'utf8' }
const server = createServer()
let version
const requests = []
server.on('request', (request, response) => {
  requests.push(request.url)
  if (request.url === '/metadata.json') {
    response.end(JSON.stringify({ cli: {
      version,
      cli: { url: `${base}/cli.js`, sha256: sha(bytes), size: bytes.length },
      notify: { url: `${base}/notify.mjs`, sha256: sha(notify), size: notify.length },
    } }))
  } else if (request.url === '/cli.js') response.end(bytes)
  else if (request.url === '/notify.mjs') response.end(notify)
  else { response.statusCode = 404; response.end() }
})

try {
  for (const dir of [cliDir, bin]) mkdirSync(dir, { recursive: true })
  writeFileSync(join(cliDir, 'package.json'), '{"type":"module"}\n')
  copyFileSync(previous || candidate, cli)
  writeFileSync(join(cliDir, 'notify.mjs'), notify)
  writeFileSync(harness, `#!/bin/sh\nexport ADAPTER_UPDATE_DISABLE=true\nexec ${quote(process.execPath)} ${quote(cli)} "$@"\n`, { mode: 0o755 })
  writeFileSync(recorder, 'console.log(JSON.stringify({args:process.argv.slice(2),home:process.env.HOME,port:process.env.PORT,socket:process.env.HN_SOCKET_NAME,pin:process.env.ADAPTER_UPDATE_DISABLE}))\n')
  writeFileSync(tui, `#!/bin/sh\nexec ${quote(process.execPath)} ${quote(recorder)} "$@"\n`, { mode: 0o755 })
  version = (await run(process.execPath, [candidate, 'version'], options)).stdout.trim()
  assert.match(version, /^\d+\.\d+\.\d+/)
  assert(!existsSync(hn), 'running a checkout must not migrate the installed copy')
  await new Promise((done, reject) => { server.once('error', reject); server.listen(port, '127.0.0.1', done) })

  if (previous) {
    const oldVersion = (await run(harness, ['version'], options)).stdout.trim()
    assert(!existsSync(hn), 'previous release fixture must predate launcher repair')
    const nextVersion = version
    version = oldVersion
    const alreadyCurrent = await run(harness, ['update'], options)
    assert(alreadyCurrent.stdout.includes(`Already on the latest version (v${oldVersion})`))
    assert(!existsSync(hn), 'reproduce the missing command after an already-current update')
    version = nextVersion
    console.log('PASS reproduced missing hn on the already-current previous release')
    const update = await run(harness, ['update'], options)
    assert(update.stdout.includes(`installed v${version}`), update.stdout)
    assert.equal(sha(readFileSync(cli)), sha(bytes))
    assert(!existsSync(hn), 'a staging canary must not migrate the live installation')
    console.log(`PASS published CLI ${oldVersion} stages ${version} with its original updater`)
  }

  // The first command on the new bundle also covers a machine already on the latest version.
  const current = await run(harness, ['update'], options)
  assert(current.stdout.includes(`Already on the latest version (v${version})`), current.stdout)
  assert(existsSync(hn), 'an already-current update must add the missing hn command')
  const args = ['-L', prefix, '--port', String(port), '--version']
  const launched = JSON.parse((await run(hn, args, options)).stdout)
  assert.deepEqual(launched, { args, home, port: String(port), socket: prefix, pin: 'true' })
  assert.equal(readFileSync(hn, 'utf8'), `#!/bin/sh\nexec ${quote(harness)} tui "$@"\n`)
  console.log('PASS already-current update creates hn; installed command preserves arguments, home and pin')

  rmSync(hn)
  await Promise.all(Array.from({ length: 8 }, () => run(harness, ['version'], options)))
  assert.equal(lstatSync(hn).mode & 0o100, 0o100)
  assert.deepEqual(readdirSync(bin).sort(), ['harness', 'hn'])
  console.log('PASS concurrent CLI starts publish one complete launcher and clean staging files')

  rmSync(hn)
  const other = join(root, 'unrelated-hn')
  writeFileSync(other, 'unrelated command\n')
  symlinkSync(other, hn)
  await run(harness, ['update'], options)
  assert.equal(readlinkSync(hn), other)
  assert.equal(readFileSync(other, 'utf8'), 'unrelated command\n')
  console.log('PASS an existing hn symlink and its target remain unchanged')

  if (native) {
    rmSync(hn)
    await run(harness, ['version'], options)
    const output = (await run(hn, args, { ...options, env: { ...env, HARNESS_TUI_BIN: native } })).stdout.trim()
    assert.match(output, /^hn \d+\.\d+\.\d+ \(tmux /)
    console.log(`PASS repaired hn launcher runs the frozen native release: ${output}`)
  }
  assert(requests.every(url => ['/metadata.json', '/cli.js', '/notify.mjs'].includes(url)), JSON.stringify(requests))
} finally {
  server.closeAllConnections()
  if (server.listening) await new Promise(done => server.close(done))
  rmSync(root, { recursive: true, force: true })
}
