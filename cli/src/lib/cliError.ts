/** Report an unexpected CLI failure and terminate, with optional cleanup before the exit. */
export function exitWithCliError(error: unknown, code = 1, beforeExit?: () => void): never {
  console.error('Failed to start adapter:', error)
  beforeExit?.()
  process.exit(code)
}
