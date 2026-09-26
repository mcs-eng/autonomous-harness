import assert from 'node:assert/strict'
import { existsSync, readFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import test from 'node:test'

const page = fileURLToPath(new URL('./cli.md', import.meta.url))

test('relative links in docs/cli.md resolve to files', () => {
  const markdown = readFileSync(page, 'utf8')
  const missing = []
  for (const match of markdown.matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)) {
    const target = match[1]
    if (/^(https?:|mailto:|#)/.test(target)) continue
    const path = decodeURIComponent(target.split('#')[0])
    if (!path) continue
    const resolved = resolve(dirname(page), path)
    if (!existsSync(resolved)) missing.push(`${target} -> ${resolved}`)
  }
  assert.deepEqual(missing, [])
})
