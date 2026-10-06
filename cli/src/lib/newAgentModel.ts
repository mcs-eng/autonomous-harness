import type { AgentEngine } from '../engines/types.js'
import { gridCapableEngines, localGridCapableEngines, type GridLaunchOverride } from './gridLaunch.js'
import { forgetGridModels, listGridModels } from './gridModels.js'
import { resolveGridTarget } from './gridTarget.js'
import { localGridSections } from './localGridModels.js'
import { localGridTargetId, readLocalGridProfiles } from './gridProfiles.js'

/** A model picked for a new agent, and the grid serving it. Where its inference goes is the models
 * service's to resolve (services/models.ts `launchTarget`), on the machine the agent runs on.
 * `targetId` names a local profile or a remote grid; absent for a plain remote pick. */
export interface NewAgentModel { model: string; grid: string; targetId?: string }

/** Model routing is resolved on the agent's machine; the model can live elsewhere.
 * Only the semantic choice goes into the creation receipt, never a rotating key. */
export function parseNewAgentModel(engine: AgentEngine, payload: Record<string, unknown>):
  { state: 'absent' } | { state: 'invalid'; detail: string } | { state: 'ok'; selection: NewAgentModel } {
  if (payload.gridModel === undefined && payload.gridName === undefined && payload.gridTarget === undefined) return { state: 'absent' }
  const valid = (value: unknown): value is string => typeof value === 'string'
    && value.trim().length > 0 && value.length <= 2048 && !/[\x00-\x1f\x7f]/.test(value)
  if (!valid(payload.gridModel) || !valid(payload.gridName)) {
    return { state: 'invalid', detail: 'Choose a model and the grid serving it.' }
  }
  if (payload.grid !== undefined || payload.codexHome != null) {
    return { state: 'invalid', detail: 'A model selection cannot be combined with a grid credential or a subscription profile.' }
  }
  if (!gridCapableEngines().includes(engine)) {
    return { state: 'invalid', detail: `${engine} cannot use a model on your machines.` }
  }
  const targetId = payload.gridTarget === undefined ? undefined : payload.gridTarget
  if (targetId !== undefined && (!valid(targetId) || targetId.length > 320
    || (!/^local:[A-Za-z0-9][A-Za-z0-9_.-]{0,63}:[a-f0-9]{16}$/.test(targetId)
      && targetId !== `remote:${payload.gridName.trim()}`))) {
    return { state: 'invalid', detail: 'Choose a valid model target from this machine.' }
  }
  if (typeof targetId === 'string' && targetId.startsWith('local:') && !localGridCapableEngines().includes(engine)) {
    return { state: 'invalid', detail: `${engine} cannot use this local Grid profile's inference protocol.` }
  }
  return { state: 'ok', selection: { model: payload.gridModel.trim(), grid: payload.gridName.trim(), ...(typeof targetId === 'string' ? { targetId } : {}) } }
}

export async function resolveNewAgentModel(selection: NewAgentModel): Promise<GridLaunchOverride | null> {
  // Refresh at launch: a model stopped after opening the picker must not silently
  // fall back to a subscription or to the grid's default router.
  if (selection.targetId?.startsWith('local:')) {
    const profiles = readLocalGridProfiles()
    const profile = profiles.find(row => row.gridName === selection.grid && localGridTargetId(row) === selection.targetId)
    if (!profile) return null
    const sections = await localGridSections([profile])
    if (!sections.some(section => section.targetId === selection.targetId && section.models.some(model => model.id === selection.model))) return null
    return resolveGridTarget(selection.grid, selection.model, selection.targetId, profiles)
  }
  forgetGridModels();
  const models = await listGridModels(selection.grid);
  if (!models.some((model) => model.id === selection.model)) return null;
  return selection.targetId
    ? resolveGridTarget(selection.grid, selection.model, selection.targetId)
    : resolveGridTarget(selection.grid, selection.model);
}
