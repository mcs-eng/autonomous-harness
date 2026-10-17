import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const checkDsh = vi.hoisted(() => vi.fn())

vi.mock('./check.js', () => ({
  checkDsh,
  formatCheck: vi.fn(),
}))

import { dshCheckCommand, dshCheckCommandUnchecked } from './checkCommand.js'

describe('dshCheckCommand unexpected errors', () => {
  beforeEach(() => { checkDsh.mockReset() })
  afterEach(() => { vi.restoreAllMocks() })

  it('leaves the full dispatcher a rejection for its existing error handler', () => {
    const error = new Error('broken fixture')
    checkDsh.mockImplementationOnce(() => { throw error })
    expect(() => dshCheckCommandUnchecked([])).toThrow(error)
  })

  it('reports and exits identically when called by the synchronous lean entry', () => {
    const error = new Error('broken fixture')
    const report = vi.spyOn(console, 'error').mockImplementation(() => {})
    const exit = vi.spyOn(process, 'exit').mockImplementation(((code: number) => {
      throw new Error(`process.exit ${code}`)
    }) as never)
    checkDsh.mockImplementationOnce(() => { throw error })

    expect(() => dshCheckCommand([])).toThrow('process.exit 1')
    expect(report).toHaveBeenCalledWith('Failed to start adapter:', error)
    expect(exit).toHaveBeenCalledWith(1)
  })
})
