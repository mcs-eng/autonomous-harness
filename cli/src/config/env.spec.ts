import { spawnSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, describe, expect, it } from 'vitest'

// env.ts reads the environment once, as it loads: each case is a process of its own, in a throwaway
// home, so the legacy-state adoption it runs on load never sees a real ~/.harness.
const tsx = fileURLToPath(new URL('../../node_modules/tsx/dist/cli.mjs', import.meta.url))
const module = fileURLToPath(new URL('./env.ts', import.meta.url))
const roots: string[] = []
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }) })

const READ = ['NODE_ENV', 'PORT', 'WEB_URL', 'HARNESS_STORE_REF', 'HARNESS_STORE_CATALOG_URL', 'HOOK_INSTALL_ENGINES', 'TERMINAL_BACKENDS', 'RECAP_WITHOUT_DEVICE', 'DISABLE_HOOK_INSTALL', 'TERMINAL_RECONCILE_INTERVAL_MS', 'ADAPTER_DATA_DIR']

function load(variables: Record<string, string>, fileContents?: string) {
  const home = mkdtempSync(join(tmpdir(), 'harness-env-'))
  roots.push(home)
  const childEnv: NodeJS.ProcessEnv = { PATH: process.env.PATH, HOME: home, ADAPTER_DATA_DIR: join(home, 'data'), ...variables }
  if (fileContents !== undefined) {
    const file = join(home, 'harness.env')
    writeFileSync(file, fileContents)
    childEnv.HARNESS_ENV_FILE = file
  }
  const script = `import { env } from ${JSON.stringify(module)}; console.log(JSON.stringify(Object.fromEntries(${JSON.stringify(READ)}.map((k) => [k, env[k] instanceof Set ? [...env[k]] : env[k] ?? null]))))`
  const run = spawnSync(process.execPath, [tsx, '--eval', script], { cwd: home, env: childEnv, encoding: 'utf8', timeout: 20_000 })
  return { status: run.status, stderr: run.stderr, env: run.status === 0 ? JSON.parse(run.stdout) as Record<string, unknown> : null, home }
}

function expectFileFailure(contents: string, messages: string[]): void {
  const loaded = load({}, contents)
  expect(loaded.status).toBe(1)
  expect(loaded.stderr).toContain('Invalid Harness environment file')
  for (const message of messages) expect(loaded.stderr).toContain(message)
  expect(loaded.stderr).not.toMatch(/node:internal|^\s+at /m)
  expect(loaded.stderr.trim().split(/\r?\n/)).toHaveLength(1)
}

describe('the environment, as env.ts reads it', () => {
  it('fills what is unset with its default, and reads what is set as its kind', () => {
    const plain = load({})
    expect(plain.status, plain.stderr).toBe(0)
    expect(plain.env).toEqual({
      NODE_ENV: 'development', PORT: 18473, WEB_URL: 'https://harness.autonomous.ai', HARNESS_STORE_REF: null, HARNESS_STORE_CATALOG_URL: null,
      HOOK_INSTALL_ENGINES: null, TERMINAL_BACKENDS: null, RECAP_WITHOUT_DEVICE: true, DISABLE_HOOK_INSTALL: false,
      TERMINAL_RECONCILE_INTERVAL_MS: null, ADAPTER_DATA_DIR: join(plain.home, 'data'),
    })
    const set = load({
      NODE_ENV: 'test', PORT: '9123', BACKEND_WS_URL: 'ws://localhost:8090', HARNESS_STORE_REF: 'feature/x', HARNESS_STORE_CATALOG_URL: ' http://127.0.0.1:9/c ',
      HOOK_INSTALL_ENGINES: 'claude, codex,', TERMINAL_BACKENDS: 'tmux', RECAP_WITHOUT_DEVICE: 'false', DISABLE_HOOK_INSTALL: 'true', TERMINAL_RECONCILE_INTERVAL_MS: '6000',
    })
    expect(set.status, set.stderr).toBe(0)
    expect(set.env).toMatchObject({
      NODE_ENV: 'test', PORT: 9123, WEB_URL: 'http://localhost:3000', HARNESS_STORE_REF: 'feature/x', HARNESS_STORE_CATALOG_URL: 'http://127.0.0.1:9/c',
      HOOK_INSTALL_ENGINES: ['claude', 'codex'], TERMINAL_BACKENDS: ['tmux'], RECAP_WITHOUT_DEVICE: false, DISABLE_HOOK_INSTALL: true,
      TERMINAL_RECONCILE_INTERVAL_MS: 6000,
    })
  })

  it('ignores a store setting it cannot use, which under zod stopped every `harness` command as it loaded', () => {
    const loaded = load({ HARNESS_STORE_CATALOG_URL: 'not a url', HARNESS_STORE_REF: 'not a ref!' })
    expect(loaded.status, loaded.stderr).toBe(0)
    expect(loaded.env).toMatchObject({ HARNESS_STORE_CATALOG_URL: null, HARNESS_STORE_REF: null })
  })

  it('keeps valid selected-file configuration and unrelated child-tool variables working', () => {
    const loaded = load({}, 'PORT=0\nAUTONOMOUS_ENV=stag\nDISABLE_HOOK_INSTALL=true\nTHIRD_PARTY_SETTING=value\n')
    expect(loaded.status, loaded.stderr).toBe(0)
    expect(loaded.env).toMatchObject({ PORT: 0, DISABLE_HOOK_INSTALL: true })
  })

  it('keeps an exported value authoritative when the selected file has an invalid fallback', () => {
    const loaded = load({ PORT: '9123' }, 'PORT=not-a-number\n')
    expect(loaded.status, loaded.stderr).toBe(0)
    expect(loaded.env).toMatchObject({ PORT: 9123 })
  })

  it('does not confuse inherited object names with schema fields', () => {
    const loaded = load({}, 'hasOwnProperty=value\nconstructor=value\ntoString=value\n__proto__=value\n')
    expect(loaded.status, loaded.stderr).toBe(0)
  })

  it.each([
    ['a non-number', 'PORT=not-a-number\n', ['PORT', 'expected a finite number']],
    ['an out-of-range port', 'PORT=70000\n', ['PORT', 'expected a value of at most 65535']],
    ['a fractional port', 'PORT=12.5\n', ['PORT', 'expected an integer']],
    ['an invalid flag', 'DISABLE_HOOK_INSTALL=maybe\n', ['DISABLE_HOOK_INSTALL', 'expected "true" or "false"']],
    ['an invalid default-on flag', 'RECAP_WITHOUT_DEVICE=1\n', ['RECAP_WITHOUT_DEVICE', 'expected "true" or "false"']],
    ['an invalid optional number', 'TERMINAL_RECONCILE_INTERVAL_MS=soon\n', ['TERMINAL_RECONCILE_INTERVAL_MS', 'expected a finite number']],
    ['an invalid ref', 'HARNESS_STORE_REF=not a ref!\n', ['HARNESS_STORE_REF', 'value has an invalid format']],
    ['an invalid URL', 'HARNESS_STORE_CATALOG_URL=not-a-url\n', ['HARNESS_STORE_CATALOG_URL', 'expected a valid URL']],
  ])('rejects %s from a selected file before startup', (_case, contents, messages) => {
    expectFileFailure(contents, messages)
  })

  it('rejects a likely misspelling of a known key with a suggestion', () => {
    expectFileFailure('PORTT=18473\n', ['PORTT', 'unknown key; did you mean PORT?'])
  })

  it('stops, naming every variable it cannot use and why', () => {
    const loaded = load({ NODE_ENV: 'staging', TERMINAL_BACKENDS: 'nonsense' })
    expect(loaded.status).toBe(1)
    expect(loaded.stderr).toContain('Invalid environment variables:')
    expect(loaded.stderr).toContain('NODE_ENV')
    expect(loaded.stderr).toContain('expected one of "development"|"production"|"test"')
    expect(loaded.stderr).toContain('TERMINAL_BACKENDS')
    const tooOften = load({ TERMINAL_RECONCILE_INTERVAL_MS: '100' })
    expect(tooOften.status).toBe(1)
    expect(tooOften.stderr).toContain('TERMINAL_RECONCILE_INTERVAL_MS must be at least 5000')
  })
})
