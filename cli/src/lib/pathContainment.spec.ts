import { mkdir, mkdtemp, realpath, rm, symlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, posix, win32 } from 'node:path'
import { afterEach, beforeEach, expect, it } from 'vitest'
import { env } from '../config/env.js'
import { tempRoots, within, withinRoots } from './pathContainment.js'

let root: string
const unrestricted = env.HARNESS_FS_BROWSE_UNRESTRICTED
beforeEach(async () => {
  root = await realpath(await mkdtemp(join(tmpdir(), 'harness-containment-')))
  env.HARNESS_FS_BROWSE_UNRESTRICTED = undefined
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
  env.HARNESS_FS_BROWSE_UNRESTRICTED = unrestricted
})

it('counts a root itself and what is under it, and nothing else', () => {
  expect(within('/a/b', '/a/b')).toBe(true)
  expect(within('/a/b', '/a/b/c/d')).toBe(true)
  // The reason this is `relative()` and not `startsWith`: a sibling shares the prefix.
  expect(within('/a/b', '/a/bc')).toBe(false)
  expect(within('/a/b', '/a')).toBe(false)
  expect(within('/a/b', '/other')).toBe(false)
})

it('refuses a parent escape, another drive, and a UNC share under Windows path rules', () => {
  // win32 relative() climbs out as `..\x`, never `../x`, and answers with an absolute path when the
  // target is on another drive or share. Pinned with path.win32 so POSIX hosts check it too.
  expect(within('C:\\a\\b', 'C:\\a\\b', win32)).toBe(true)
  expect(within('C:\\a\\b', 'C:\\a\\b\\c\\d', win32)).toBe(true)
  expect(within('C:\\a\\b', 'c:\\A\\B\\c', win32)).toBe(true)
  expect(within('C:\\a\\b', 'C:\\a\\b\\..name', win32)).toBe(true)
  expect(within('C:\\a\\b', 'C:\\a\\other.txt', win32)).toBe(false)
  expect(within('C:\\a\\b', 'C:\\a\\bc', win32)).toBe(false)
  expect(within('C:\\a\\b', 'C:\\a', win32)).toBe(false)
  expect(within('C:\\a\\b', 'D:\\a\\b\\c', win32)).toBe(false)
  expect(within('C:\\a\\b', '\\\\server\\share\\a\\b', win32)).toBe(false)
  expect(within('\\\\server\\share\\a', '\\\\server\\share\\a\\x', win32)).toBe(true)
  expect(within('\\\\server\\share\\a', '\\\\server\\other\\a\\x', win32)).toBe(false)
})

it('applies the same rule under POSIX path rules', () => {
  expect(within('/a/b', '/a/b/c', posix)).toBe(true)
  expect(within('/a/b', '/a/b/..name', posix)).toBe(true)
  expect(within('/a/b', '/a/other.txt', posix)).toBe(false)
  expect(within('/a/b', '/a/bc', posix)).toBe(false)
  // A backslash is an ordinary filename character on POSIX, not a separator.
  expect(within('/a/b', '/a/b/..\\x', posix)).toBe(true)
})

it('measures the target against roots resolved through their symlinks', async () => {
  const real = join(root, 'real')
  await mkdir(real)
  await writeFile(join(real, 'file'), 'x')
  const link = join(root, 'link')
  await symlink(real, link)
  // The root is named by its link; a file inside the folder it points at is still inside it.
  expect(await withinRoots(join(real, 'file'), [link])).toBe(true)
  expect(await withinRoots(join(root, 'elsewhere'), [real])).toBe(false)
})

it('refuses when no root resolves, rather than allowing everything', async () => {
  expect(await withinRoots(join(root, 'file'), [])).toBe(false)
  expect(await withinRoots(join(root, 'file'), [join(root, 'not-there')])).toBe(false)
  // One good root among unresolvable ones still admits what is inside it.
  expect(await withinRoots(join(root, 'file'), [join(root, 'not-there'), root])).toBe(true)
})

it('honours the folder-browser opt-out', async () => {
  expect(await withinRoots('/etc/passwd', [root])).toBe(false)
  env.HARNESS_FS_BROWSE_UNRESTRICTED = '1'
  expect(await withinRoots('/etc/passwd', [root])).toBe(true)
})

it('names both temp directories, because macOS has a private one and agents still write /tmp', () => {
  expect(tempRoots()).toContain(tmpdir())
  expect(tempRoots()).toContain('/tmp')
})
