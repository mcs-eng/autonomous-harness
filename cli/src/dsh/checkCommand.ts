import { checkDsh, formatCheck } from './check.js'
import { exitWithCliError } from '../lib/cliError.js'

/** The check verb's work. The full dsh dispatcher lets its existing promise handler report failures. */
export function dshCheckCommandUnchecked(rest: readonly string[]): number {
  const valued = new Set(['--ref', '--path'])
  const args = rest.filter((arg, at) => !arg.startsWith('-') && !valued.has(rest[at - 1] ?? ''))
  const target = args[0] ?? '.'
  const result = checkDsh(target)
  console.log(formatCheck(result))
  const name = result.manifest?.id ?? target
  console.log(result.ok ? `${name} conforms to spec 1` : `${name} does not conform`)
  return result.ok ? 0 : 1
}

/** The lean entry calls synchronously, so preserve the full dispatcher's unexpected-error behavior here. */
export function dshCheckCommand(rest: readonly string[]): number {
  try {
    return dshCheckCommandUnchecked(rest)
  } catch (error) {
    return exitWithCliError(error)
  }
}
