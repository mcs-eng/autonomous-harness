import { describe, expect, it } from 'vitest'
import { fastCliRoute } from './entryRoute.js'

const argv = (...args: string[]): string[] => ['node', 'harness', ...args]

describe('fast CLI entry routes', () => {
  it.each([[[]], [['--help']], [['-h']], [['help']]])('recognizes root help %j', (args) => {
    expect(fastCliRoute(argv(...args))).toEqual({ kind: 'help' })
  })

  it('keeps hn on its existing implicit TUI route', () => {
    expect(fastCliRoute(['node', 'hn', '--help'])).toBeNull()
    expect(fastCliRoute(['node', 'hn.js', '--help'], '1')).toEqual({ kind: 'help' })
  })

  it('passes every check argument to the isolated DSH handler', () => {
    expect(fastCliRoute(argv('dsh', 'check', '--ref', 'ignored', 'fixture')))
      .toEqual({ kind: 'dsh-check', argv: ['--ref', 'ignored', 'fixture'] })
    expect(fastCliRoute(argv('dsh', 'list'))).toBeNull()
  })

  it('offers only non-forced updates to the local-build no-op', () => {
    expect(fastCliRoute(argv('update'))).toEqual({ kind: 'local-update-noop' })
    expect(fastCliRoute(argv('update', '--force'))).toBeNull()
    expect(fastCliRoute(argv('version'))).toBeNull()
    expect(fastCliRoute(argv('__run'))).toBeNull()
  })
})
