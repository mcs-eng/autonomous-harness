/**
 * How the environment's variables become `env` (./env.ts): one small function per variable.
 *
 * The schema was zod's. Every process loads env.ts at start, harnessd's master and each service in its
 * own process among them, and zod with a schema of a hundred variables cost each of them 15 to 19 MiB
 * resident, against 3 for the master's own code (measured 2026-10-05). These are the few kinds of
 * variable the schema had, with zod's meaning: a default stands in only for a variable that is unset (an
 * empty one is kept), and a value that cannot be what its variable must be is an issue, reported with
 * every other before the process exits.
 */

/** Why a variable's value cannot be used; collected per variable, as zod's `fieldErrors` were. */
export class EnvIssue extends Error {}

/** One variable: its value from the environment (undefined when unset) to what `env` holds. */
export interface EnvField<T> {
  (raw: string | undefined): T
  /** Stricter check used only for a value written in an explicitly selected Harness env file. */
  fileIssue?: (raw: string) => string | undefined
}

function checked<T>(field: EnvField<T>, fileIssue: (raw: string) => string | undefined): EnvField<T> {
  field.fileIssue = fileIssue
  return field
}

export interface NumberConstraints {
  integer?: boolean
  min?: number
  max?: number
}

function numberIssue(raw: string, constraints: NumberConstraints = {}): string | undefined {
  if (raw.trim() === '' || !Number.isFinite(Number(raw))) return 'expected a finite number'
  const value = Number(raw)
  if (constraints.integer && !Number.isInteger(value)) return 'expected an integer'
  if (constraints.min !== undefined && value < constraints.min) return `expected a value of at least ${constraints.min}`
  if (constraints.max !== undefined && value > constraints.max) return `expected a value of at most ${constraints.max}`
}

/** A string, [fallback] when unset. */
export const text = (fallback: string): EnvField<string> => (raw) => raw ?? fallback
/** A string, or undefined when unset. */
export const maybe: EnvField<string | undefined> = (raw) => raw
/** A number (`Number`, so not a number is NaN, as before), [fallback] when unset. */
export const number = (fallback: string): EnvField<number> => (raw) => Number(raw ?? fallback)
/** A number whose explicitly selected file value must be finite, with optional bounds. */
export const fileNumber = (fallback: string, constraints: NumberConstraints = {}): EnvField<number> => checked(
  number(fallback),
  (raw) => numberIssue(raw, constraints),
)
/** A number, or undefined when unset. */
export const maybeNumber: EnvField<number | undefined> = checked(
  (raw) => raw === undefined ? undefined : Number(raw),
  numberIssue,
)
/** True only for `true`, [fallback] when unset. */
export const flag = (fallback: 'true' | 'false'): EnvField<boolean> => checked(
  (raw) => (raw ?? fallback) === 'true',
  (raw) => raw === 'true' || raw === 'false' ? undefined : 'expected "true" or "false"',
)
/** True for anything but `false`: on unless turned off. */
export const unlessFalse: EnvField<boolean> = checked(
  (raw) => raw !== 'false',
  (raw) => raw === 'true' || raw === 'false' ? undefined : 'expected "true" or "false"',
)
/** One of [values], [fallback] when unset; anything else is an issue. */
export function oneOf<const T extends string>(values: readonly T[], fallback: T): EnvField<T> {
  return (raw) => {
    const value = raw ?? fallback
    if (!(values as readonly string[]).includes(value)) {
      throw new EnvIssue(`Invalid option: expected one of ${values.map((one) => JSON.stringify(one)).join('|')}`)
    }
    return value as T
  }
}
/** A string that matches [pattern], or undefined: unset, or a value that does not. */
export const matching = (pattern: RegExp): EnvField<string | undefined> => checked(
  (raw) => raw !== undefined && pattern.test(raw) ? raw : undefined,
  (raw) => {
    pattern.lastIndex = 0
    return pattern.test(raw) ? undefined : 'value has an invalid format'
  },
)
/** A URL [accept] takes, trimmed, or undefined: unset, not a URL, or one it refuses. */
export const url = (accept: (url: URL) => boolean): EnvField<string | undefined> => checked((raw) => {
  if (raw === undefined) return undefined
  const value = raw.trim()
  try { return accept(new URL(value)) ? value : undefined } catch { return undefined }
}, (raw) => {
  const value = raw.trim()
  try { return accept(new URL(value)) ? undefined : 'URL is not allowed' } catch { return 'expected a valid URL' }
})

export type EnvOf<F extends Record<string, EnvField<unknown>>> = { [K in keyof F]: ReturnType<F[K]> }

/** [source] read through [fields]: every variable's value, or the issues, by variable, if any has one. */
export function parseEnv<F extends Record<string, EnvField<unknown>>>(fields: F, source: NodeJS.ProcessEnv):
  { ok: true; data: EnvOf<F> } | { ok: false; issues: Record<string, string[]> } {
  const data: Record<string, unknown> = {}
  const issues: Record<string, string[]> = {}
  for (const [name, field] of Object.entries(fields)) {
    try {
      data[name] = field(source[name])
    } catch (error) {
      if (!(error instanceof EnvIssue)) throw error
      issues[name] = [error.message]
    }
  }
  return Object.keys(issues).length ? { ok: false, issues } : { ok: true, data: data as EnvOf<F> }
}
