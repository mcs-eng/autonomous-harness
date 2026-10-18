import { config, parse, populate } from 'dotenv'
import { readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import type { EnvField } from './envFields.js'

// Harness is started from users' projects. Their .env belongs to the project, not to the daemon:
// reading it can move this machine to a different backend, account store or encryption identity.
// Dev and release builds use the same defaults. An isolated backend is always an explicit choice.
// Keep this grammar aligned with dotenv's parser. The separate value captures let us distinguish a
// quoted value from dotenv's permissive unquoted fallback, which otherwise accepts a missing quote.
const ASSIGNMENT = /^(\s*(?:export\s+)?)([\w.-]+)(?:\s*=\s*?|:\s+?)(?:(\s*'(?:\\'|[^'])*')|(\s*"(?:\\"|[^"])*")|(\s*`(?:\\`|[^`])*`)|([^#\r\n]+))?\s*(?:#.*)?$/gm

interface LoadedEnvironmentFile {
  path: string
  lines: ReadonlyMap<string, number>
  appliedKeys: ReadonlySet<string>
}

interface ParsedEnvironmentFile {
  path: string
  values: Record<string, string>
  lines: ReadonlyMap<string, number>
}

class EnvironmentFileError extends Error {
  constructor(readonly path: string, detail: string, prefix = 'Invalid Harness environment file') {
    const displayPath = path.replace(/[\u0000-\u001f\u007f]/g, (character) => `\\u${character.charCodeAt(0).toString(16).padStart(4, '0')}`)
    super(`${prefix} ${displayPath}: ${detail}`)
  }
}

function lineAt(source: string, offset: number): number {
  let line = 1
  for (let i = 0; i < offset; i++) if (source.charCodeAt(i) === 10) line++
  return line
}

function parseStrict(path: string, source: string): ParsedEnvironmentFile {
  const normalized = source.replace(/\r\n?/g, '\n')
  const remaining = normalized.split('')
  const lines = new Map<string, number>()
  ASSIGNMENT.lastIndex = 0

  let match: RegExpExecArray | null
  while ((match = ASSIGNMENT.exec(normalized)) !== null) {
    const key = match[2]
    const line = lineAt(normalized, match.index + match[1].length)
    const unquoted = match[6]?.trim()
    if (unquoted && [`'`, '"', '`'].includes(unquoted[0])) {
      throw new EnvironmentFileError(path, `line ${line} has a malformed or unclosed quoted value for ${key}`)
    }

    lines.set(key, line)
    for (let i = match.index; i < ASSIGNMENT.lastIndex; i++) {
      if (remaining[i] !== '\n') remaining[i] = ' '
    }
  }

  const unmatched = remaining.join('').split('\n')
  for (let index = 0; index < unmatched.length; index++) {
    if (!/^\s*(?:#.*)?$/.test(unmatched[index])) {
      throw new EnvironmentFileError(path, `line ${index + 1} is not a valid KEY=VALUE assignment`)
    }
  }

  return { path, values: parse(normalized), lines }
}

function readSelectedEnvironmentFile(): LoadedEnvironmentFile | null {
  const harnessFile = process.env.HARNESS_ENV_FILE?.trim()
  const dotenvFile = process.env.DOTENV_CONFIG_PATH?.trim()
  const selected = harnessFile || dotenvFile
  if (!selected) return null
  const path = resolve(selected)

  // dotenv's encrypted-vault path is credential handling. Preserve it byte-for-byte instead of
  // inspecting or validating secret material here.
  if (process.env.DOTENV_KEY) {
    const result = config({ path, quiet: true, override: false })
    if (result.error) throw new Error(`Cannot read Harness environment file: ${path}`, { cause: result.error })
    return null
  }


  try {
    if (!statSync(path).isFile()) throw new EnvironmentFileError(path, 'path is not a regular file')
    const bytes = readFileSync(path)
    // Windows editors can save as UTF-16, which dotenv reads as no assignments at all.
    if (bytes.length >= 2 && ((bytes[0] === 0xff && bytes[1] === 0xfe) || (bytes[0] === 0xfe && bytes[1] === 0xff))) {
      throw new EnvironmentFileError(path, 'file is UTF-16; save it as UTF-8')
    }
    const parsed = parseStrict(path, bytes.toString('utf8'))
    const appliedKeys = new Set(Object.keys(parsed.values).filter((key) => !Object.prototype.hasOwnProperty.call(process.env, key)))
    populate(process.env, parsed.values, { override: false })
    return { path: parsed.path, lines: parsed.lines, appliedKeys }
  } catch (error) {
    if (error instanceof EnvironmentFileError) throw error
    const code = error instanceof Error && 'code' in error ? String(error.code) : ''
    if (code === 'ENOENT') throw new EnvironmentFileError(path, 'file does not exist', 'Cannot read Harness environment file')
    if (code === 'EACCES' || code === 'EPERM') throw new EnvironmentFileError(path, 'file is not readable', 'Cannot read Harness environment file')
    throw new EnvironmentFileError(path, 'file cannot be read', 'Cannot read Harness environment file')
  }
}

function exitWith(error: EnvironmentFileError): never {
  console.error(error.message)
  process.exit(1)
}

let selectedEnvironmentFile: LoadedEnvironmentFile | null
try {
  selectedEnvironmentFile = readSelectedEnvironmentFile()
} catch (error) {
  if (error instanceof EnvironmentFileError) exitWith(error)
  throw error
}

const loadedEnvironmentFile = selectedEnvironmentFile

interface EnvironmentFileValidation {
  unknownKeyWarning?: (key: string, knownKeys: readonly string[]) => string | undefined
}

/** Validate only values supplied by the selected file; ambient process variables retain compatibility. */
export function validateLoadedEnvironment(
  fields: Readonly<Record<string, EnvField<unknown>>>,
  options: EnvironmentFileValidation = {},
): void {
  if (!loadedEnvironmentFile) return

  const knownKeys = Object.keys(fields)
  for (const key of loadedEnvironmentFile.appliedKeys) {
    const raw = process.env[key]
    if (raw === undefined) continue
    const line = loadedEnvironmentFile.lines.get(key) ?? 1
    const fieldKey = Object.prototype.hasOwnProperty.call(fields, key)
      ? key
      : process.platform === 'win32'
        ? knownKeys.find((known) => known.toUpperCase() === key.toUpperCase())
        : undefined
    if (!fieldKey) {
      const warning = options.unknownKeyWarning?.(key, knownKeys)
      if (warning) {
        console.warn(new EnvironmentFileError(
          loadedEnvironmentFile.path,
          `line ${line}, ${key}: ${warning}`,
          'Harness environment file warning',
        ).message)
      }
      continue
    }

    const field = fields[fieldKey]
    if (!field.fileIssue) continue
    // A blank typed value (`KEY=` or `KEY=""`) is a template placeholder: it means unset, as it did
    // before validation for every kind but numbers, which read it as 0. Removing it lets this process
    // and the children that inherit its environment use the default.
    if (raw === '') {
      delete process.env[key]
      continue
    }
    const issue = field.fileIssue(raw)
    if (issue) exitWith(new EnvironmentFileError(loadedEnvironmentFile.path, `line ${line}, ${key}: ${issue}`))
  }
}
