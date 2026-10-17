import './config/loadEnv.js'
import { ensureUtf8Locale } from './lib/childLocale.js'
import { ensureHnLauncher } from './lib/launchers.js'

/** Startup effects every human-facing CLI command performs before it prints or dispatches. */
export function initializeCli(scriptPath: string): void {
  ensureUtf8Locale()
  ensureHnLauncher(scriptPath)
}
