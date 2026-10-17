export type FastCliRoute =
  | { kind: 'help' }
  | { kind: 'dsh-check'; argv: string[] }
  | { kind: 'local-update-noop' }

/** A user command that can run without evaluating the full daemon/control-plane CLI graph. */
export function fastCliRoute(argv: readonly string[], harnessSelf = process.env.HARNESS_SELF): FastCliRoute | null {
  const executable = argv[1]?.split(/[\\/]/).pop() ?? ''
  if (/^hn(\.js)?$/.test(executable) && harnessSelf !== '1') return null
  const [, , command, ...rest] = argv
  if (!command || command === '--help' || command === '-h' || command === 'help') return { kind: 'help' }
  if (command === 'dsh' && rest[0] === 'check') return { kind: 'dsh-check', argv: rest.slice(1) }
  if (command === 'update' && !rest.includes('--force')) return { kind: 'local-update-noop' }
  return null
}
