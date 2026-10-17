import { afterEach, describe, expect, it, vi } from 'vitest'
import { localUpdateNoop } from './localUpdateNoop.js'

describe('local update no-op', () => {
  afterEach(() => vi.restoreAllMocks())

  it('keeps source execution a no-op, including an explicit force', () => {
    const output: string[] = []
    vi.spyOn(console, 'log').mockImplementation(line => { output.push(String(line)) })
    expect(localUpdateNoop('/checkout/src/cli.ts', '1.2.3', true)).toBe(true)
    expect(output).toEqual(['This is a dev/repo build (running from source) — `harness update` is a no-op. Rebuild the bundle instead.'])
  })

  it('prints the existing four-line protection for an installed working-tree build', () => {
    const output: string[] = []
    vi.spyOn(console, 'log').mockImplementation(line => { output.push(String(line)) })
    expect(localUpdateNoop('/install/cli.js', '1.2.3-dev.abc123', false)).toBe(true)
    expect(output).toEqual([
      'This is a local build (v1.2.3-dev.abc123), installed from a working tree by scripts/install-cli.sh.',
      'Updating would replace it with a published release and lose whatever it was built to test.',
      '  keep it:    rebuild with `make install-cli` after you pull',
      '  replace it: harness update --force',
    ])
  })

  it('leaves published and explicitly forced installed builds to the real updater', () => {
    const output = vi.spyOn(console, 'log').mockImplementation(() => {})
    expect(localUpdateNoop('/install/cli.js', '1.2.3', false)).toBe(false)
    expect(localUpdateNoop('/install/cli.js', '1.2.3-dev.abc123', true)).toBe(false)
    expect(output).not.toHaveBeenCalled()
  })
})
