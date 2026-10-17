import { spawnSync } from 'node:child_process'
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, describe, expect, it } from 'vitest'

const tsx = fileURLToPath(new URL('../../node_modules/tsx/dist/cli.mjs', import.meta.url))
const loader = fileURLToPath(new URL('./loadEnv.ts', import.meta.url))
const roots: string[] = []
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }) })

function project(): string {
  const root = mkdtempSync(join(tmpdir(), 'harness-env-'))
  roots.push(root)
  writeFileSync(join(root, '.env'), 'BACKEND_WS_URL=ws://sandbox.invalid:8090\nAUTONOMOUS_ENV=stag\nADAPTER_DATA_DIR=/sandbox/data\nHARNESS_AUTH_DIR=/sandbox/auth\nPORT=3000\n')
  return root
}

function run(cwd: string, overrides: NodeJS.ProcessEnv = {}) {
  const childEnv = { ...process.env }
  for (const key of ['BACKEND_WS_URL', 'AUTONOMOUS_ENV', 'ADAPTER_DATA_DIR', 'HARNESS_AUTH_DIR', 'PORT', 'HARNESS_ENV_FILE', 'DOTENV_CONFIG_PATH']) delete childEnv[key]
  const script = `import ${JSON.stringify(loader)}; console.log(JSON.stringify(Object.fromEntries(['BACKEND_WS_URL','AUTONOMOUS_ENV','ADAPTER_DATA_DIR','HARNESS_AUTH_DIR','PORT'].map(k => [k, process.env[k] ?? null]))));`
  return spawnSync(process.execPath, [tsx, '--eval', script], { cwd, env: { ...childEnv, ...overrides }, encoding: 'utf8', timeout: 10_000 })
}

function runReading(cwd: string, overrides: NodeJS.ProcessEnv, read: string[]) {
  const childEnv = { ...process.env }
  for (const key of [...read, 'HARNESS_ENV_FILE', 'DOTENV_CONFIG_PATH']) delete childEnv[key]
  const script = `import ${JSON.stringify(loader)}; console.log(JSON.stringify(Object.fromEntries(${JSON.stringify(read)}.map(k => [k, process.env[k] ?? null]))));`
  return spawnSync(process.execPath, [tsx, '--eval', script], { cwd, env: { ...childEnv, ...overrides }, encoding: 'utf8', timeout: 10_000 })
}

function expectCleanFailure(result: ReturnType<typeof run>, messages: string[]): void {
  expect(result.status).not.toBe(0)
  for (const message of messages) expect(result.stderr).toContain(message)
  expect(result.stderr).not.toMatch(/node:internal|^\s+at /m)
  expect(result.stderr.trim().split(/\r?\n/)).toHaveLength(1)
}

describe('Harness environment loading', () => {
  it('does not adopt a project .env when a user starts Harness from that folder', () => {
    const result = run(project())
    expect(result.status, result.stderr).toBe(0)
    expect(JSON.parse(result.stdout)).toEqual({ BACKEND_WS_URL: null, AUTONOMOUS_ENV: null, ADAPTER_DATA_DIR: null, HARNESS_AUTH_DIR: null, PORT: null })
  })

  it('uses an explicitly selected file from any project, with exported variables taking precedence', () => {
    const root = project()
    const other = join(root, 'another-project')
    mkdirSync(other)
    const file = join(root, 'harness.env')
    writeFileSync(file, 'BACKEND_WS_URL=ws://chosen.invalid:8090\nAUTONOMOUS_ENV=stag\nADAPTER_DATA_DIR=/chosen/data\nHARNESS_AUTH_DIR=/chosen/auth\n')
    for (const cwd of [root, other]) {
      const result = run(cwd, { HARNESS_ENV_FILE: file, AUTONOMOUS_ENV: 'prod' })
      expect(result.status, result.stderr).toBe(0)
      expect(JSON.parse(result.stdout)).toEqual({ BACKEND_WS_URL: 'ws://chosen.invalid:8090', AUTONOMOUS_ENV: 'prod', ADAPTER_DATA_DIR: '/chosen/data', HARNESS_AUTH_DIR: '/chosen/auth', PORT: null })
    }
  })

  it('keeps explicitly configured DOTENV_CONFIG_PATH working', () => {
    const root = project()
    const result = run(root, { DOTENV_CONFIG_PATH: '.env' })
    expect(result.status, result.stderr).toBe(0)
    expect(JSON.parse(result.stdout)).toMatchObject({ BACKEND_WS_URL: 'ws://sandbox.invalid:8090', AUTONOMOUS_ENV: 'stag' })
  })

  it('keeps an absolute DOTENV_CONFIG_PATH working', () => {
    const root = project()
    const result = run(root, { DOTENV_CONFIG_PATH: join(root, '.env') })
    expect(result.status, result.stderr).toBe(0)
    expect(JSON.parse(result.stdout)).toMatchObject({ BACKEND_WS_URL: 'ws://sandbox.invalid:8090', AUTONOMOUS_ENV: 'stag' })
  })

  it('preserves valid dotenv quoting, comments, export, colon, multiline and CRLF syntax', () => {
    const root = project()
    const file = join(root, 'syntax.env')
    writeFileSync(file, '\uFEFF# comment\r\nexport EMPTY=\r\nCOLON: value\r\nSINGLE=\' padded value \'\r\nDOUBLE="first\\nsecond"\r\nBACKTICK=`hash # stays`\r\nMULTILINE="first\r\nsecond" # comment\r\nDUPLICATE=first\r\nDUPLICATE=second\r\n')
    const keys = ['EMPTY', 'COLON', 'SINGLE', 'DOUBLE', 'BACKTICK', 'MULTILINE', 'DUPLICATE']
    const result = runReading(root, { HARNESS_ENV_FILE: file }, keys)
    expect(result.status, result.stderr).toBe(0)
    expect(JSON.parse(result.stdout)).toEqual({
      EMPTY: '', COLON: 'value', SINGLE: ' padded value ', DOUBLE: 'first\nsecond', BACKTICK: 'hash # stays', MULTILINE: 'first\nsecond', DUPLICATE: 'second',
    })
  })

  it('fails with one clear line if the explicitly selected environment file is missing', () => {
    const root = project()
    const result = run(root, { HARNESS_ENV_FILE: join(root, 'missing.env') })
    expectCleanFailure(result, ['Cannot read Harness environment file', 'file does not exist'])
  })

  it('rejects a directory where an environment file was required', () => {
    const root = project()
    expectCleanFailure(run(root, { HARNESS_ENV_FILE: root }), ['Invalid Harness environment file', 'path is not a regular file'])
  })

  it('requires HARNESS_ENV_FILE to use the documented absolute path', () => {
    const root = project()
    expectCleanFailure(run(root, { HARNESS_ENV_FILE: 'harness.env' }), ['HARNESS_ENV_FILE must be an absolute path'])
  })

  it.each([
    ['an assignment without an equals sign', 'PORT 3000\n', 'line 1 is not a valid KEY=VALUE assignment'],
    ['a bad line among valid assignments', 'PORT=3000\nthis is not an assignment\nAUTONOMOUS_ENV=prod\n', 'line 2 is not a valid KEY=VALUE assignment'],
    ['an unclosed quote', 'PORT="3000\n', 'line 1 has a malformed or unclosed quoted value for PORT'],
    ['text after a quoted value', 'PORT="3000" trailing\n', 'line 1 has a malformed or unclosed quoted value for PORT'],
  ])('rejects malformed syntax: %s', (_case, contents, message) => {
    const root = project()
    const file = join(root, 'malformed.env')
    writeFileSync(file, contents)
    expectCleanFailure(run(root, { HARNESS_ENV_FILE: file }), [message])
  })
})
