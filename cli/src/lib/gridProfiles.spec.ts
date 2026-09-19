import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { gridProfilesPath, localGridTargetId, readLocalGridProfiles, removeLocalGridProfile, setLocalGridProfile } from './gridProfiles.js'

const roots: string[] = []
const root = (): string => {
  const value = mkdtempSync(join(tmpdir(), 'grid-profiles-'))
  chmodSync(value, 0o700)
  roots.push(value)
  return value
}
afterEach(() => { for (const path of roots.splice(0)) rmSync(path, { recursive: true, force: true }) })

describe('local Grid profiles', () => {
  it('persists canonical server-owned homes and replaces a profile by id', () => {
    const data = root(); const home = join(data, 'grid-home'); mkdirSync(home)
    setLocalGridProfile({ id: 'bran', label: 'Bran fleet', gridHome: home, gridName: 'bran-fleet' }, data)
    setLocalGridProfile({ id: 'bran', label: 'Bran local', gridHome: home, gridName: 'bran-fleet' }, data)
    expect(readLocalGridProfiles(data)).toEqual([{ id: 'bran', label: 'Bran local', gridHome: home, gridName: 'bran-fleet' }])
    expect(localGridTargetId(readLocalGridProfiles(data)[0]!)).toMatch(/^local:bran:[a-f0-9]{16}$/)
    expect(JSON.parse(readFileSync(gridProfilesPath(data), 'utf8')).version).toBe(1)
    expect(removeLocalGridProfile('bran', data)).toBe(true)
    expect(readLocalGridProfiles(data)).toEqual([])
  })

  it('skips malformed entries but retains an unavailable profile through an unrelated update', () => {
    const data = root(); const home = join(data, 'grid-home'); mkdirSync(home)
    writeFileSync(gridProfilesPath(data), JSON.stringify({ version: 1, profiles: [
      { id: 'bad', label: 'Bad', gridHome: 'relative', gridName: 'bad' },
      { id: 'gone', label: 'Gone', gridHome: join(data, 'gone'), gridName: 'gone' },
      { id: 'bran', label: 'Bran', gridHome: home, gridName: 'bran-fleet' },
    ] }), { mode: 0o600 })
    expect(readLocalGridProfiles(data).map((row) => row.id)).toEqual(['gone', 'bran'])
    setLocalGridProfile({ id: 'other', label: 'Other', gridHome: home, gridName: 'other-grid' }, data)
    expect(readLocalGridProfiles(data).map((row) => row.id).sort()).toEqual(['bran', 'gone', 'other'])
  })

  it('refuses a group-writable profile store', () => {
    const data = root(); const home = join(data, 'grid-home'); mkdirSync(home)
    setLocalGridProfile({ id: 'bran', label: 'Bran', gridHome: home, gridName: 'bran-fleet' }, data)
    chmodSync(gridProfilesPath(data), 0o660)
    expect(readLocalGridProfiles(data)).toEqual([])
  })
})
