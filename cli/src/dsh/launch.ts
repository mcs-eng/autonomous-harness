/**
 * What a DSH adds to its base engine's launch: the three `HARNESS_*` variables every DSH script can
 * rely on, the manifest's own env with `${dsh}`/`${workspace}` expanded, and its extra argv.
 *
 * Applied on create AND on every relaunch (`launchOverrides.ts`), so an agent restored after a reboot
 * or restarted in place is still the DSH it was created as — and still discoverable as one, since
 * `HARNESS_DSH` is what `probe.ts` reads off the live process.
 */
import type { InstalledDsh } from './installed.js'
import { expandDshValue } from './manifest.js'

export interface DshLaunch {
  env: Record<string, string>
  args: string[]
}

export function dshLaunch(dsh: InstalledDsh, workspace: string): DshLaunch {
  const vars = { dsh: dsh.realDir, workspace }
  const env: Record<string, string> = {
    HARNESS_DSH: dsh.id,
    HARNESS_DSH_DIR: dsh.realDir,
    HARNESS_WORKSPACE: workspace,
  }
  for (const [key, value] of Object.entries(dsh.manifest.agent?.env ?? {})) {
    if (key.startsWith('HARNESS_')) continue // ours; a manifest cannot rename itself
    env[key] = expandDshValue(value, vars)
  }
  const args = (dsh.manifest.agent?.args ?? []).map((arg) => expandDshValue(arg, vars))
  return { env, args }
}
