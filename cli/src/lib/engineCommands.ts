import { PROCESS_ENGINES, type AgentEngine } from '../engines/types.js'

export { PROCESS_ENGINES }

/** Public vendor command shown to users and matched by the real-binary smoke matrix. */
export const ENGINE_CLI_COMMANDS: Readonly<Record<AgentEngine, string>> = {
  claude: 'claude',
  codex: 'codex',
  // Cursor and Grok both publish `agent`; Cursor's documented, unambiguous command is
  // `cursor-agent`, so creation must use that and keep `agent` for discovery only.
  cursor: 'cursor-agent',
  opencode: 'opencode',
  pi: 'pi',
  hermes: 'hermes',
  commandcode: 'cmd',
  devin: 'devin',
  muse: 'muse',
  amp: 'amp',
  kilo: 'kilo',
  grok: 'grok',
  agy: 'agy',
  copilot: 'copilot',
  cline: 'cline',
  // A terminal has no command: the pane runs the user's login shell (engineLaunch.ts). The empty
  // string is what keeps every "is this binary installed" probe honest — nothing to look for.
  terminal: '',
}
