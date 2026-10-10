import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { ApiConnections } from './apiConnections.js'
import { forgetApiModels, refreshApiLaunch, resolveApiTarget } from './apiModels.js'
import { buildLaunchOverrides } from './launchOverrides.js'
import { gridLaunchInProcess } from '../testing/gridLaunchInProcess.js'
import type { GridLaunchOverride } from './gridLaunch.js'

const model = 'fixture-coder'
const originalUrl = 'https://first.example.test/v1'
let directory: string, store: ApiConnections, id: string

function response(contextWindow?: number, models = [model]) {
  return new Response(JSON.stringify({ data: models.map(id => ({ id, context_length: contextWindow })) }), {
    headers: { 'content-type': 'application/json' },
  })
}

function edit(baseUrl: string, apiKey: string, name = 'Fixture API') {
  return store.save({ id, provider: 'custom', name, baseUrl, apiKey })
}

async function prepare() {
  return resolveApiTarget(store, id, model, { fetch: vi.fn(async () => response(262_144)) })
}

async function codexLaunch(target: GridLaunchOverride) {
  return buildLaunchOverrides({
    machine: () => ({ hermesSystemManaged: false }),
    // The models service's builder, in this process: the launch is already refreshed above.
    gridLaunch: gridLaunchInProcess(),
    tmuxSupportsSessionEnv: async () => true,
    writeGridConfigDir: async () => { throw new Error('Unexpected config write') },
    installCodexHooks: () => { throw new Error('Unexpected hook install') },
    readCodexConfig: () => { throw new Error('Unexpected profile read') },
  }, 'codex', { gridLaunch: target }, 'fixture-agent')
}

beforeEach(() => {
  directory = mkdtempSync(join(tmpdir(), 'harness-api-snapshot-'))
  store = new ApiConnections(directory)
  id = store.save({ provider: 'custom', name: 'Fixture API', baseUrl: originalUrl, apiKey: 'fixture-old-key' }).id
  forgetApiModels()
  vi.stubGlobal('fetch', vi.fn(() => { throw new Error('Unexpected network access') }))
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
  rmSync(directory, { recursive: true, force: true })
})

describe('saved API configuration changes before engine dispatch', () => {
  it.each(['http://127.0.0.1:12345/v1', 'https://second.example.test/v1'])(
    'refreshes the selected model and its token budget together with endpoint %s', async baseUrl => {
      const prepared = await prepare()
      edit(baseUrl, 'fixture-new-key')
      const fetch = vi.fn(async () => response(65_536))
      const refreshed = await refreshApiLaunch(store, prepared, { fetch })
      const built = await codexLaunch(refreshed)
      expect(built.ok).toBe(true)
      if (!built.ok) throw new Error(built.detail)
      expect(built.overrides.extraArgs).toEqual(expect.arrayContaining([
        `model_providers.grid.base_url="${baseUrl}"`, '-m', model,
        'model_context_window=65536', 'model_auto_compact_token_limit=58982',
      ]))
      expect(Object.values(built.overrides.env)).toContain('fixture-new-key')
      expect(built.overrides.gridLaunchRecord?.override).toMatchObject({ baseUrl, apiKey: 'fixture-new-key', model, contextWindow: 65_536 })
      expect(fetch).toHaveBeenCalledWith(`${baseUrl}/models`, expect.objectContaining({
        headers: { authorization: 'Bearer fixture-new-key', accept: 'application/json' },
      }))
      expect(prepared).toMatchObject({ baseUrl: originalUrl, apiKey: 'fixture-old-key', contextWindow: 262_144 })
    },
  )

  it('does not carry the previous endpoint context window when the new endpoint omits it', async () => {
    const prepared = await prepare()
    edit('https://second.example.test/v1', 'fixture-new-key')
    const refreshed = await refreshApiLaunch(store, prepared, { fetch: vi.fn(async () => response()) })
    expect(refreshed).not.toHaveProperty('contextWindow')
    const built = await codexLaunch(refreshed)
    expect(built.ok).toBe(true)
    if (!built.ok) throw new Error(built.detail)
    expect(built.overrides.extraArgs.some(arg => arg.startsWith('model_context_window='))).toBe(false)
  })

  it('refuses a model the new endpoint does not list instead of dispatching the stale choice', async () => {
    const prepared = await prepare()
    edit('https://second.example.test/v1', 'fixture-new-key')
    await expect(Promise.resolve(refreshApiLaunch(store, prepared, {
      fetch: vi.fn(async () => response(65_536, ['different-coder'])),
    }))).rejects.toThrow(`does not list ${model} for coding agents`)
  })

  it('refreshes account-specific limits when only the key changes', async () => {
    const prepared = await prepare()
    edit(originalUrl, 'fixture-new-key')
    const fetch = vi.fn(async () => response(65_536))
    expect(await refreshApiLaunch(store, prepared, { fetch })).toMatchObject({
      baseUrl: originalUrl, apiKey: 'fixture-new-key', model, contextWindow: 65_536,
    })
    expect(fetch).toHaveBeenCalledTimes(1)
  })

  it('keeps one endpoint, key and capability result across an awaited lookup; the next call takes later edits', async () => {
    const prepared = await prepare()
    const secondUrl = 'http://127.0.0.1:12345/v1'
    edit(secondUrl, 'fixture-second-key')
    let finish!: (value: Response) => void
    const pending = new Promise<Response>(resolve => { finish = resolve })
    const fetch = vi.fn(() => pending)
    const inFlight = refreshApiLaunch(store, prepared, { fetch })
    expect(fetch).toHaveBeenCalledTimes(1)
    edit('https://third.example.test/v1', 'fixture-third-key')
    finish(response(65_536))
    const second = await inFlight
    expect(second).toMatchObject({ baseUrl: secondUrl, apiKey: 'fixture-second-key', model, contextWindow: 65_536 })
    const built = await codexLaunch(second)
    expect(built.ok).toBe(true)
    if (!built.ok) throw new Error(built.detail)
    expect(built.overrides.extraArgs).toContain(`model_providers.grid.base_url="${secondUrl}"`)
    expect(Object.values(built.overrides.env)).toContain('fixture-second-key')
    expect(await refreshApiLaunch(store, second, { fetch: vi.fn(async () => response(131_072)) })).toMatchObject({
      baseUrl: 'https://third.example.test/v1', apiKey: 'fixture-third-key', model, contextWindow: 131_072,
    })
  })

  it('keeps a prepared route without network access when only its display name changes', async () => {
    const prepared = await prepare()
    edit(originalUrl, 'fixture-old-key', 'Renamed API')
    const fetch = vi.fn(() => { throw new Error('Unchanged route must not fetch') })
    expect(await refreshApiLaunch(store, prepared, { fetch })).toEqual({ ...prepared, networkName: 'Renamed API' })
    expect(fetch).not.toHaveBeenCalled()
  })
})
