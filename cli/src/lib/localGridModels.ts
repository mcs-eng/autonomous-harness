import { gridExec } from './gridExec.js'
import type { GridModel, GridSection } from './gridModels.js'
import { localGridCapableEngines } from './gridLaunchWire.js'
import { localGridTargetId, type LocalGridProfile } from './gridProfiles.js'

export function localProcessEnv(profile: LocalGridProfile): NodeJS.ProcessEnv {
  return { ...process.env, GRID_HOME: profile.gridHome }
}

async function listLocalProfile(profile: LocalGridProfile): Promise<GridModel[]> {
  // Grid 0.3.47's local `models` can hang and `engines` can omit a live engine while the hub is
  // already serving it. `info --env` is fast and authoritative for the profile's hub; its OpenAI
  // catalogue preserves the exact model ids engines must send.
  const result = await gridExec(['--local', 'info', profile.gridName, '--env'], {
    processEnv: localProcessEnv(profile), timeoutMs: 5_000,
  })
  if (result.code !== 'OK') return []
  const endpoint = readEnvExports(result.stdout)
  if (!endpoint.baseUrl || !endpoint.apiKey) return []
  return (await modelIdsAt(endpoint.baseUrl, endpoint.apiKey, 4_000)).map((id) => ({ id, node: profile.label }))
}

async function modelIdsAt(baseUrl: string, apiKey: string, timeoutMs: number): Promise<string[]> {
  try {
    const response = await fetch(`${baseUrl.replace(/\/$/, '')}/models`, {
      headers: { authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(timeoutMs),
    })
    if (!response.ok) return []
    const body = await response.json() as { data?: Array<{ id?: unknown }> }
    return (body.data ?? []).map((m) => (typeof m.id === 'string' ? m.id : '')).filter(Boolean)
  } catch {
    return []
  }
}


/** `grid info --env` prints shell exports; these are the two that matter. */
const ENV_LINE = /^export\s+(OPENAI_BASE_URL|OPENAI_API_KEY)=(.*)$/gm

/** 0.3.47 emits tab-separated rows for local `ls --json`; accept JSON once it is repaired. */
export function localGridId(stdout: string, gridName: string): string | null {
  try {
    const rows = JSON.parse(stdout) as Array<{ grid?: unknown; name?: unknown; id?: unknown }>
    if (Array.isArray(rows)) {
      const row = rows.find((item) => item?.grid === gridName || item?.name === gridName)
      return typeof row?.id === 'string' && row.id.trim() ? row.id.trim() : null
    }
  } catch { /* text fallback */ }
  for (const line of stdout.split(/\r?\n/)) {
    const [name, id] = line.split('\t')
    if (name?.trim() === gridName && id?.trim()) return id.trim()
  }
  return null
}

/** The two exports out of `grid info --env`. ⚠️ Values are SHELL-QUOTED — a base URL read with the
 *  quotes still on produces a request to a host that does not exist. */
export function readEnvExports(stdout: string): { baseUrl: string; apiKey: string } {
  let baseUrl = ''
  let apiKey = ''
  for (const match of stdout.matchAll(ENV_LINE)) {
    const value = match[2]!.trim().replace(/^["']|["']$/g, '')
    if (match[1] === 'OPENAI_BASE_URL') baseUrl = value
    else apiKey = value
  }
  return { baseUrl, apiKey }
}

export async function localGridSections(profiles: readonly LocalGridProfile[]): Promise<GridSection[]> {
  return Promise.all(profiles.map(async (profile): Promise<GridSection> => ({
    name: profile.gridName, type: 'local', own: false, source: 'local', label: profile.label,
    profileId: profile.id, targetId: localGridTargetId(profile), engines: localGridCapableEngines(),
    models: await listLocalProfile(profile).catch(() => []),
  })))
}
