import type { GridLaunchOverride } from './gridLaunch.js'
import { forgetGridModels, listGridModels } from './gridModels.js'
import { resolveGridTarget } from './gridTarget.js'
import { localGridSections } from './localGridModels.js'
import { localGridTargetId, readLocalGridProfiles } from './gridProfiles.js'
import type { NewAgentModel } from './newAgentModel.js'

/** Models-service work only. The core imports the semantic parser, never these discovery dependencies. */
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
  forgetGridModels()
  const models = await listGridModels(selection.grid)
  if (!models.some((model) => model.id === selection.model)) return null
  return selection.targetId
    ? resolveGridTarget(selection.grid, selection.model, selection.targetId)
    : resolveGridTarget(selection.grid, selection.model)
}
