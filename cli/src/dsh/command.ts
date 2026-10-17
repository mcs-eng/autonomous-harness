/**
 * `harness dsh …` — the terminal face of domain-specific harnesses, for a server with no desktop
 * and for the development loop (`--link` a checkout, iterate, no re-clone).
 */
import { ensureBundledCoreHarnesses } from './builtins.js'
import { listDshState, installedDsh } from './installed.js'
import { DSH_ID_RE, dshTier } from './manifest.js'
import { registrySourceUrl } from './registry.js'
import { catalogEntry, currentDshRegistry, refreshDshRegistry } from './catalog.js'
import { installDsh, removeDsh, resolveInstallSource, runDshDoctor } from './install.js'
import { updateDsh } from './update.js'
import { dshUpdateInfo } from './updates.js'
import { dshCheckCommandUnchecked } from './checkCommand.js'
import { dshUsage } from './usage.js'

export { dshUsage } from './usage.js'

function flagValue(argv: readonly string[], flag: string): string | undefined {
  const at = argv.indexOf(flag)
  return at >= 0 ? argv[at + 1] : undefined
}

/** `verb` is the word after `dsh`; `rest` is everything after THAT, flags included. */
export async function dshCommand(verb: string | undefined, rest: readonly string[]): Promise<number> {
  // Positional words only: a flag and the value it takes (`--ref main`) are not arguments.
  const valued = new Set(['--ref', '--path'])
  const args = rest.filter((arg, at) => !arg.startsWith('-') && !valued.has(rest[at - 1] ?? ''))
  switch (verb) {
    case 'builtins':
      return ensureBundledCoreHarnesses() ? 0 : 1
    case 'list': {
      const { installed, broken } = listDshState()
      const registry = await refreshDshRegistry()
      const seen = new Set<string>()
      const rows: string[] = []
      for (const dsh of installed) {
        seen.add(dsh.id)
        const update = dshUpdateInfo(dsh, registry.find(entry => entry.id === dsh.id))
        rows.push(`  ${dsh.id.padEnd(28)} ${dsh.manifest.name.padEnd(12)} ${(dsh.manifest.kind === 'viewer' ? 'viewer' : `on ${dsh.manifest.engine}`).padEnd(11)} tier ${dshTier(dsh.manifest)}  installed${dsh.linked ? ' (linked)' : ''}${dsh.commit ? ` @ ${dsh.commit.slice(0, 8)}` : ''}${update.updateAvailable ? ` · update available (${update.availableCommit!.slice(0, 8)})` : ''} · ${dsh.dir}`)
      }
      for (const row of broken) {
        seen.add(row.id)
        rows.push(`  ${row.id.padEnd(28)} ${'?'.padEnd(12)} ${''.padEnd(11)} ${''.padEnd(6)}  BROKEN · ${row.error}`)
      }
      for (const entry of registry) {
        if (seen.has(entry.id)) continue
        rows.push(`  ${entry.id.padEnd(28)} ${entry.name.padEnd(12)} ${(entry.kind === 'viewer' ? 'viewer' : `on ${entry.engine}`).padEnd(11)} tier ${entry.tier ?? '?'}  available · ${registrySourceUrl(entry)}`)
      }
      console.log(rows.length ? rows.join('\n') : '  (nothing installed, registry empty)')
      return 0
    }
    case 'install': {
      const target = args[0]
      if (!target) { console.error(dshUsage()); return 1 }
      if (DSH_ID_RE.test(target) && !rest.includes('--link')) await refreshDshRegistry(!catalogEntry(target))
      const resolved = resolveInstallSource(target)
      if (!resolved) { console.error(`harness dsh install: ${target} is not an id, URL or path`); return 1 }
      const link = rest.includes('--link')
      const ref = flagValue(rest, '--ref') ?? resolved.ref
      const path = flagValue(rest, '--path') ?? resolved.path
      const catalog = new Map(currentDshRegistry().map(entry => [entry.id, entry]))
      const result = await installDsh({
        source: resolved.source,
        expectedId: resolved.id,
        registry: resolved.id ? id => catalog.get(id) : undefined,
        ref: link ? undefined : ref,
        path: link ? undefined : path,
        link,
        onProgress: (p) => console.log(`[dsh] ${p.id ?? target} · ${p.phase}${p.detail ? ` · ${p.detail}` : ''}`),
        onLine: (line) => console.log(`    ${line}`),
      })
      if (!result.ok) { console.error(`harness dsh install failed · ${result.error} · ${result.detail}`); return 1 }
      console.log(`Installed ${result.installed.id} (${result.installed.manifest.name}, ${result.installed.manifest.kind === 'viewer' ? 'a viewer package' : `runs on ${result.installed.manifest.engine}`}) at ${result.installed.dir}`)
      return 0
    }
    case 'update': {
      const id = args[0]
      if (!id || !DSH_ID_RE.test(id) || args.length !== 1) { console.error(dshUsage()); return 1 }
      const result = await updateDsh({ id,
        onProgress: p => console.log(`[dsh] ${id} · ${p.phase}${p.detail ? ` · ${p.detail}` : ''}`),
        onLine: line => console.log(`    ${line}`),
      })
      if (!result.ok) { console.error(`harness dsh update failed · ${result.error} · ${result.detail}`); return 1 }
      console.log(`${id} is up to date${result.installed.commit ? ` @ ${result.installed.commit.slice(0, 8)}` : ''}. Workspaces preserved.`)
      return 0
    }
    case 'doctor': {
      const id = args[0]
      const dsh = id ? installedDsh(id) : undefined
      if (!dsh) { console.error(`harness dsh doctor: ${id ?? '<id>'} is not installed`); return 1 }
      const doctor = await runDshDoctor(dsh, (line) => console.log(`  ${line}`))
      console.log(doctor.ok ? `${dsh.id} is ready` : `${dsh.id} is not ready`)
      return doctor.ok ? 0 : 1
    }
    case 'check': return dshCheckCommandUnchecked(rest)
    case 'remove': {
      const id = args[0]
      if (!id) { console.error(dshUsage()); return 1 }
      const result = removeDsh(id)
      if (!result.ok) { console.error(`harness dsh remove failed · ${result.error} · ${result.detail}`); return 1 }
      console.log(`Removed ${id}`)
      return 0
    }
    default:
      console.error(dshUsage())
      return verb === undefined || verb === 'help' ? 0 : 1
  }
}
