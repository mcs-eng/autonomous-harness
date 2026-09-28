import { beforeEach, describe, expect, it, vi } from 'vitest'
import { ENGINES } from '../engines/types.js'
import { gridCapableEngines } from './gridLaunch.js'
import { forgetGridModels, listGridModels } from './gridModels.js'
import { resolveGridTarget } from './gridTarget.js'
import { parseNewAgentModel, resolveNewAgentModel } from './newAgentModel.js'
import { localGridSections } from './localGridModels.js'
import { localGridTargetId, readLocalGridProfiles } from './gridProfiles.js'

vi.mock('./gridModels.js', () => ({ forgetGridModels: vi.fn(), listGridModels: vi.fn() }))
vi.mock('./gridTarget.js', () => ({ resolveGridTarget: vi.fn() }))
vi.mock('./localGridModels.js', () => ({ localGridSections: vi.fn() }))
vi.mock('./gridProfiles.js', async original => ({ ...await original<typeof import('./gridProfiles.js')>(), readLocalGridProfiles: vi.fn() }))
const choice = { gridModel: 'Qwen-35B', gridName: 'my-grid' }
const target = { networkId: 'g', networkName: 'my-grid', baseUrl: 'https://fixture.invalid/relay/v1', apiKey: 'fixture-key', model: 'Qwen-35B' }
beforeEach(() => vi.resetAllMocks())

describe('new-session model routing', () => {
  const profile = { id: 'local-a', label: 'Local A', gridName: 'my-grid', gridHome: '/fixture/a' }
  const targetId = localGridTargetId(profile)
  it('preserves an explicit target and refuses malformed or incompatible targets', () => {
    expect(parseNewAgentModel('codex', { ...choice, gridTarget: targetId })).toEqual({ state: 'ok', selection: { model: 'Qwen-35B', grid: 'my-grid', targetId } })
    for (const gridTarget of ['', 42, 'local:\ninvalid', 'invented', 'remote:other-grid']) {
      expect(parseNewAgentModel('codex', { ...choice, gridTarget }).state).toBe('invalid')
    }
    expect(parseNewAgentModel('claude', { ...choice, gridTarget: targetId }).state).toBe('invalid')
  })
  it('validates only the selected local profile even when a remote namesake serves the same model', async () => {
    const other = { ...profile, id: 'local-b', gridHome: '/fixture/b' }
    vi.mocked(readLocalGridProfiles).mockReturnValue([profile, other])
    vi.mocked(localGridSections).mockResolvedValue([{ name: 'my-grid', own: false, type: 'local', targetId, models: [{ id: 'Qwen-35B', node: 'Local A' }] }])
    vi.mocked(listGridModels).mockResolvedValue([{ id: 'Qwen-35B', node: 'Remote' }])
    vi.mocked(resolveGridTarget).mockResolvedValue({ ...target, targetId })
    const parsed = parseNewAgentModel('codex', { ...choice, gridTarget: targetId })
    if (parsed.state !== 'ok') throw new Error('valid choice rejected')
    expect(await resolveNewAgentModel(parsed.selection)).toMatchObject({ targetId })
    expect(localGridSections).toHaveBeenCalledWith([profile])
    expect(listGridModels).not.toHaveBeenCalled()
    expect(resolveGridTarget).toHaveBeenCalledWith('my-grid', 'Qwen-35B', targetId, [profile, other])
  })
  it('refuses stale local identities and missing local models without remote fallback', async () => {
    const parsed = parseNewAgentModel('codex', { ...choice, gridTarget: targetId })
    if (parsed.state !== 'ok') throw new Error('valid choice rejected')
    vi.mocked(readLocalGridProfiles).mockReturnValue([{ ...profile, gridHome: '/fixture/moved' }])
    vi.mocked(listGridModels).mockResolvedValue([{ id: 'Qwen-35B', node: 'Remote' }])
    expect(await resolveNewAgentModel(parsed.selection)).toBeNull()
    expect(localGridSections).not.toHaveBeenCalled()
    vi.mocked(readLocalGridProfiles).mockReturnValue([profile])
    vi.mocked(localGridSections).mockResolvedValue([{ name: 'my-grid', own: false, type: 'local', targetId, models: [] }])
    expect(await resolveNewAgentModel(parsed.selection)).toBeNull()
    expect(listGridModels).not.toHaveBeenCalled()
    expect(resolveGridTarget).not.toHaveBeenCalled()
  })
  it('keeps ordinary launches absent and normalizes the explicit selection', () => {
    expect(parseNewAgentModel('codex', {})).toEqual({ state: 'absent' })
    expect(parseNewAgentModel('codex', { gridModel: ' Qwen-35B ', gridName: ' my-grid ' })).toEqual({ state: 'ok', selection: { model: 'Qwen-35B', grid: 'my-grid' } })
  })
  it.each(ENGINES)('uses the actual launch contract for %s', engine => {
    expect(parseNewAgentModel(engine, choice).state).toBe(gridCapableEngines().includes(engine) ? 'ok' : 'invalid')
  })
  it.each([null, undefined, 4, {}, '', ' ', '\nQwen', 'a'.repeat(2049)])('refuses invalid model/grid identities: %j', bad => {
    expect(parseNewAgentModel('codex', { ...choice, gridModel: bad }).state).toBe('invalid')
    expect(parseNewAgentModel('codex', { ...choice, gridName: bad }).state).toBe('invalid')
  })
  it.each([{ grid: null }, { grid: target }, { codexHome: '/profiles/work' }])('refuses conflicting routing: %j', conflict => {
    expect(parseNewAgentModel('codex', { ...choice, ...conflict }).state).toBe('invalid')
  })
  it('resolves the exact model on another machine through the chosen grid', async () => {
    vi.mocked(listGridModels).mockResolvedValue([{ id: 'Qwen-35B', node: 'Mac Studio' }])
    vi.mocked(resolveGridTarget).mockResolvedValue(target)
    expect(await resolveNewAgentModel({ model: 'Qwen-35B', grid: 'my-grid' })).toEqual(target)
    expect(forgetGridModels).toHaveBeenCalledOnce()
    expect(listGridModels).toHaveBeenCalledWith('my-grid')
    expect(resolveGridTarget).toHaveBeenCalledWith('my-grid', 'Qwen-35B')
  })
  it('refuses a stopped model without resolving a fallback', async () => {
    vi.mocked(listGridModels).mockResolvedValue([{ id: 'Another-model', node: 'Mac Studio' }])
    expect(await resolveNewAgentModel({ model: 'Qwen-35B', grid: 'my-grid' })).toBeNull()
    expect(resolveGridTarget).not.toHaveBeenCalled()
  })
  it('preserves a missing endpoint and failures for the caller to refuse', async () => {
    vi.mocked(listGridModels).mockResolvedValue([{ id: 'Qwen-35B', node: '' }])
    vi.mocked(resolveGridTarget).mockResolvedValue(null)
    expect(await resolveNewAgentModel({ model: 'Qwen-35B', grid: 'my-grid' })).toBeNull()
    vi.mocked(listGridModels).mockRejectedValue(new Error('offline'))
    await expect(resolveNewAgentModel({ model: 'Qwen-35B', grid: 'my-grid' })).rejects.toThrow('offline')
  })
})
