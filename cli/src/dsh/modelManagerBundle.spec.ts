import { afterEach, beforeEach, expect, it } from 'vitest'
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { BundledFiles } from './builtins.js'

// @ts-expect-error - the release build helper is dependency-free ESM.
const { readModelManagerBundle } = await import('../../scripts/lib/modelManagerBundle.mjs') as {
  readModelManagerBundle(root: string): BundledFiles
}

let root: string
beforeEach(() => {
  root = mkdtempSync(join(tmpdir(), 'manager-build-'))
  for (const directory of ['viewer', 'lib', 'toolchain', 'template', 'skills']) {
    mkdirSync(join(root, directory))
  }
  for (const name of ['harness.json', 'AGENTS.md', 'LICENSE', 'VERSIONS', 'viewer.mjs']) {
    writeFileSync(join(root, name), 'ordinary text\r\n', { mode: 0o600 })
  }
  // A Windows checkout cannot convey the scripts' POSIX executable bits.
  for (const name of ['viewer.sh', 'toolchain/fleet']) {
    writeFileSync(join(root, name), '#!/bin/sh\r\nprintf "fixture\\n"\r\n', { mode: 0o600 })
  }
  writeFileSync(join(root, 'viewer/index.html'), '<p>viewer</p>\r\n', { mode: 0o600 })
})
afterEach(() => rmSync(root, { recursive: true, force: true }))

it('uses portable relative paths for files consumed in WSL', () => {
  const files = readModelManagerBundle(root)
  expect(files['toolchain/fleet']).toBeDefined()
  expect(files['viewer/index.html']).toBeDefined()
  expect(Object.keys(files).some(path => path.includes('\\'))).toBe(false)
})

it('keeps shebang scripts executable without POSIX checkout modes', () => {
  const files = readModelManagerBundle(root)
  expect(files['viewer.sh'].executable).toBe(true)
  expect(Object.values(files).filter(file => file.content.startsWith('#!')).every(file => file.executable)).toBe(true)
})

it('ships LF text so Linux can execute Windows-built shell scripts', () => {
  const files = readModelManagerBundle(root)
  expect(files['viewer.sh'].content).toBe('#!/bin/sh\nprintf "fixture\\n"\n')
  expect(Object.values(files).some(file => file.content.includes('\r\n'))).toBe(false)
})

it('keeps ordinary text non-executable', () => {
  const files = readModelManagerBundle(root)
  expect(files['AGENTS.md'].executable).toBe(false)
  expect(files['viewer.mjs'].executable).toBe(false)
})
