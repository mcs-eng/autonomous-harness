import { createHash, randomUUID } from 'node:crypto'
import { closeSync, constants, fchmodSync, fsyncSync, openSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { isAbsolute, join } from 'node:path'
import { env } from '../config/env.js'
import { hardenPrivateStateFileIfPresent, readPrivateStateFile, secureStateDirectory } from './secureState.js'

const FILE = 'grid-profiles.json'
const MAX_BYTES = 64 * 1024
const MAX_PROFILES = 16
const ID = /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}$/
const CONTROL = /[\u0000-\u001f\u007f]/

export interface LocalGridProfile {
  id: string
  label: string
  gridHome: string
  gridName: string
}

interface Document { version: 1; profiles: LocalGridProfile[] }

export function gridProfilesPath(dataDir = env.ADAPTER_DATA_DIR): string {
  return join(dataDir, FILE)
}

function text(value: unknown, max: number): string | null {
  if (typeof value !== 'string') return null
  const trimmed = value.trim()
  return trimmed && trimmed.length <= max && !CONTROL.test(trimmed) ? trimmed : null
}

function parseProfile(raw: unknown, resolvePath: boolean): LocalGridProfile | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null
  const row = raw as Record<string, unknown>
  const id = text(row.id, 64)
  const label = text(row.label, 120)
  const gridName = text(row.gridName, 240)
  const gridHome = text(row.gridHome, 4096)
  if (!id || !ID.test(id) || !label || !gridName || gridName.startsWith('-') || !gridHome || !isAbsolute(gridHome)) return null
  if (!resolvePath) return { id, label, gridHome, gridName }
  try {
    if (!statSync(gridHome).isDirectory()) return null
    return { id, label, gridHome: realpathSync(gridHome), gridName }
  } catch {
    return null
  }
}

/**
 * Machine-owned local Grid profiles. Bad entries are skipped independently.
 *
 * An unavailable home is still valid configuration. Reads deliberately do not touch the path: a
 * temporarily unmounted profile must survive an unrelated set/remove, and its one empty catalogue
 * must not erase another profile. [setLocalGridProfile] is the boundary that requires and
 * canonicalises a live directory.
 */
export function readLocalGridProfiles(dataDir = env.ADAPTER_DATA_DIR): LocalGridProfile[] {
  try {
    secureStateDirectory(dataDir, false)
    const raw = JSON.parse(readPrivateStateFile(gridProfilesPath(dataDir), MAX_BYTES)) as Partial<Document>
    if (raw.version !== 1 || !Array.isArray(raw.profiles)) return []
    const profiles = new Map<string, LocalGridProfile>()
    for (const item of raw.profiles.slice(0, MAX_PROFILES)) {
      const profile = parseProfile(item, false)
      if (profile && !profiles.has(profile.id)) profiles.set(profile.id, profile)
    }
    return [...profiles.values()]
  } catch {
    return []
  }
}

/** Stable route identity. Changing the destination invalidates rows from the former destination. */
export function localGridTargetId(profile: LocalGridProfile): string {
  const destination = `${profile.id}\u0000${profile.gridHome}\u0000${profile.gridName}`
  const fingerprint = createHash('sha256').update(destination).digest('hex').slice(0, 16)
  return `local:${profile.id}:${fingerprint}`
}

function writeProfiles(profiles: LocalGridProfile[], dataDir: string): void {
  secureStateDirectory(dataDir)
  const file = gridProfilesPath(dataDir)
  hardenPrivateStateFileIfPresent(file, MAX_BYTES)
  const temporary = `${file}.${process.pid}.${randomUUID()}.tmp`
  let renamed = false
  try {
    const fd = openSync(temporary, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600)
    try {
      writeFileSync(fd, `${JSON.stringify({ version: 1, profiles }, null, 2)}\n`)
      fchmodSync(fd, 0o600)
      fsyncSync(fd)
    } finally { closeSync(fd) }
    renameSync(temporary, file)
    renamed = true
  } finally {
    if (!renamed) rmSync(temporary, { force: true })
  }
}

export function setLocalGridProfile(input: LocalGridProfile, dataDir = env.ADAPTER_DATA_DIR): LocalGridProfile {
  const profile = parseProfile(input, true)
  if (!profile) throw new Error('Profile needs a simple id, label, grid name, and an existing absolute Grid home directory.')
  const profiles = readLocalGridProfiles(dataDir).filter((row) => row.id !== profile.id)
  if (profiles.length >= MAX_PROFILES) throw new Error(`At most ${MAX_PROFILES} local Grid profiles may be configured.`)
  profiles.push(profile)
  profiles.sort((a, b) => a.label.localeCompare(b.label) || a.id.localeCompare(b.id))
  writeProfiles(profiles, dataDir)
  return profile
}

export function removeLocalGridProfile(id: string, dataDir = env.ADAPTER_DATA_DIR): boolean {
  if (!ID.test(id)) return false
  const profiles = readLocalGridProfiles(dataDir)
  const kept = profiles.filter((row) => row.id !== id)
  if (kept.length === profiles.length) return false
  writeProfiles(kept, dataDir)
  return true
}
