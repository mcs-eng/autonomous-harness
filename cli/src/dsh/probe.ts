/**
 * Which DSH a live engine process belongs to, read off its environment — the same cached read
 * `probeCodexHome` uses, one `ps` per process for its whole life.
 *
 * Three answers, the same contract as the other probes: an id when the process carries
 * `HARNESS_DSH`, `null` when it does not (a plain engine), and `undefined` when the process could
 * not be read — which must never overwrite what the registry already knows.
 */
import { readProcessEnv } from '../lib/processEnv.js'
import type { ProcessIdentity } from '../lib/registry.js'
import { DSH_ID_RE } from './manifest.js'

export const DSH_ENV_VAR = 'HARNESS_DSH'

/** Pure half, for specs and for callers that already hold the environment. */
export function dshFromEnv(processEnv: Record<string, string>): string | null {
  const id = processEnv[DSH_ENV_VAR]
  return typeof id === 'string' && DSH_ID_RE.test(id) ? id : null
}

export async function probeDsh(identity: ProcessIdentity): Promise<string | null | undefined> {
  const processEnv = await readProcessEnv(identity)
  if (!processEnv) return undefined
  return dshFromEnv(processEnv)
}
