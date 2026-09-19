/**
 * `resolveGridTarget` against the plan-driven fake `grid`: the order of its calls, and what the
 * resolved target carries. There was no spec for this module before web tools gave it a second
 * subprocess whose ORDER matters — `mcp config` renews the token, `info --env` reads it.
 */
import { mkdirSync, mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { fakeGridAnswers, installFakeGrid, type FakeGrid, type FakeGridPlan } from './__fixtures__/fakeGrid.js'
import { clearGridMcpUrlCache } from './gridMcpUrl.js'
import { listAllGridModels, resolveGridTarget } from './gridModels.js'
import { localGridTargetId } from './gridProfiles.js'

const { gridName: GRID, networkId, baseUrl: BASE_URL, mcpUrl: MCP_URL, token: TOKEN, plan } = fakeGridAnswers()

let fake: FakeGrid | null = null
const directories: string[] = []
function install(overrides: FakeGridPlan = {}): FakeGrid {
  fake = installFakeGrid({ ...plan, ...overrides })
  return fake
}

afterEach(() => {
  fake?.dispose()
  fake = null
  clearGridMcpUrlCache()
  vi.restoreAllMocks()
  for (const path of directories.splice(0)) rmSync(path, { recursive: true, force: true })
})

describe('isolated local Grid profiles', () => {
  function profile() {
    const root = mkdtempSync(join(tmpdir(), 'local-grid-profile-')); directories.push(root)
    const gridHome = join(root, 'grid-home'); mkdirSync(gridHome)
    return { id: 'bran-local', label: 'Bran local fleet', gridHome, gridName: GRID }
  }

  it('lists exact hub model ids under a distinct opaque target', async () => {
    fake = installFakeGrid(plan)
    vi.spyOn(globalThis, 'fetch').mockImplementation(async (input) => {
      const url = String(input)
      if (url === `${BASE_URL}/models`) return Response.json({ data: [{ id: 'same-name' }, { id: 'qwen3.5:12b' }] })
      return new Promise<Response>(() => {})
    })
    const configured = profile()
    const sections = await listAllGridModels(null, [configured])
    expect(sections[0]).toMatchObject({
      source: 'local', label: 'Bran local fleet', profileId: 'bran-local',
      targetId: localGridTargetId(configured),
    })
    expect(sections[0]?.engines).toContain('codex')
    expect(sections[0]?.engines).not.toContain('claude')
    expect(sections[0]?.models.map((m) => m.id)).toEqual(['same-name', 'qwen3.5:12b'])
  })

  it('resolves a same-named local model through its profile, never the remote target', async () => {
    fake = installFakeGrid(plan)
    const configured = profile()
    const targetId = localGridTargetId(configured)
    const target = await resolveGridTarget(GRID, 'same-name', targetId, [configured])
    expect(target).toMatchObject({
      networkId,
      networkName: 'Bran local fleet',
      baseUrl: BASE_URL,
      apiKey: TOKEN,
      model: 'same-name',
      targetId,
    })
    expect(fake.calls()).toEqual([
      ['--local', 'info', GRID, '--env'],
      ['--local', 'ls', '--json'],
    ])
  })

  it('refuses an invented local target id', async () => {
    fake = installFakeGrid(plan)
    expect(await resolveGridTarget(GRID, 'same-name', 'local:not-configured', [profile()])).toBeNull()
    expect(fake.calls()).toEqual([])
  })

  it('invalidates the old target identity when a profile destination changes', async () => {
    fake = installFakeGrid(plan)
    const before = profile()
    const after = { ...before, gridName: `${GRID}-moved` }
    expect(await resolveGridTarget(after.gridName, 'same-name', localGridTargetId(before), [after])).toBeNull()
    expect(fake.calls()).toEqual([])
  })
})

describe('resolveGridTarget', () => {
  it('fills mcpUrl with the printed url, calling `mcp config` BEFORE `info --env`', async () => {
    const grid = install()
    const target = await resolveGridTarget(GRID, 'GLM-4.7-Flash')
    expect(target).toEqual({
      networkId,
      networkName: GRID,
      baseUrl: BASE_URL,
      apiKey: TOKEN,
      model: 'GLM-4.7-Flash',
      mcpUrl: MCP_URL,
    })
    // `mcp config` may renew the token and persist it; `info --env` then reads the renewed one. The
    // other order can hand inference an older token than the one the web tools hold.
    expect(grid.verbs()).toEqual(['mcp', 'info', 'ls'])
    expect(grid.calls()[0]).toEqual(['--remote', 'mcp', 'config', GRID, '--json'])
  })

  it('still resolves, without mcpUrl, when the binary is too old for `mcp config`', async () => {
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    install({ mcp: { exit: 2, stderr: "grid: error: invalid choice: 'mcp'\n" } })
    const target = await resolveGridTarget(GRID, 'GLM-4.7-Flash')
    expect(target).toMatchObject({ baseUrl: BASE_URL, apiKey: TOKEN, model: 'GLM-4.7-Flash' })
    expect(target).not.toHaveProperty('mcpUrl')
  })

  it('does not call `mcp config` again on a second retarget with a fresh entry', async () => {
    const grid = install()
    await resolveGridTarget(GRID, 'GLM-4.7-Flash')
    const again = await resolveGridTarget(GRID, 'DeepSeek-V4-Flash-0731')
    expect(again?.mcpUrl).toBe(MCP_URL)
    expect(grid.verbs()).toEqual(['mcp', 'info', 'ls', 'info', 'ls'])
  })

  it('still answers null, untouched, when `info --env` fails', async () => {
    // The retarget error path is not this feature's to change: no endpoint → GRID_UNAVAILABLE, as today.
    install({ info: { exit: 1, stderr: 'no access token locally\n' } })
    expect(await resolveGridTarget(GRID, 'GLM-4.7-Flash')).toBeNull()
  })

  it('asks nothing of `grid` without a grid name or a model', async () => {
    const grid = install()
    expect(await resolveGridTarget(null, 'GLM-4.7-Flash')).toBeNull()
    expect(await resolveGridTarget(GRID, '  ')).toBeNull()
    expect(grid.calls()).toEqual([])
  })
})
