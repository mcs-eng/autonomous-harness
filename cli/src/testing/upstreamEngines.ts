/**
 * Fork: the engines upstream's golden records were taken over. The Windows fork adds Cline, a terminal-only
 * preview with no Harness history, hooks or grid routing (desktop/WINDOWS_QUICKSTART.md), and upstream's
 * goldens pin upstream's former code, which never had it. A golden that walks every engine walks these instead,
 * so its fixture stays byte-identical to upstream's and a sync conflicts on one import line at most.
 */
import { ENGINES as ALL_ENGINES, PROCESS_ENGINES as ALL_PROCESS_ENGINES, type AgentEngine, type ProcessEngine } from '../engines/types.js'

export type { AgentEngine, ProcessEngine }

/** The fork's own engines, which no upstream golden records. */
export const FORK_ONLY_ENGINES: readonly AgentEngine[] = ['cline']

export const ENGINES: readonly AgentEngine[] = ALL_ENGINES.filter((engine) => !FORK_ONLY_ENGINES.includes(engine))
export const PROCESS_ENGINES: readonly ProcessEngine[] = ALL_PROCESS_ENGINES.filter((engine) => !FORK_ONLY_ENGINES.includes(engine))
