/**
 * Run a DSH's own commands — setup, doctor, workspace init, the viewer — the way the user's terminal
 * would: through their interactive shell, so `uv`, `npm`, `node` and `kicad-cli` resolve from the
 * PATH their rc files build, not from the detached daemon's. This is the same reasoning (and the
 * same shell selection) `engineLaunch.ts` uses to exec an engine in a pane.
 */
import { spawn, type ChildProcess } from 'node:child_process'
import { harnessNodePrelude, interactiveEngineShell } from '../lib/engineLaunch.js'
import { managedNodePath } from '../lib/nodeRuntime.js'

export interface DshCommandOptions {
  cwd: string
  env?: Record<string, string>
  /** Each line of combined stdout+stderr, as it arrives. */
  onLine?: (line: string) => void
  timeoutMs?: number
}

export interface DshCommandResult {
  code: number | null
  signal: NodeJS.Signals | null
  lines: string[]
  timedOut: boolean
}

/**
 * What the shell itself says about being interactive without a terminal — not the DSH's output.
 * `zsh -lic` with no tty cannot enable the line editor, and an rc file that sets `zle` makes zsh
 * complain once per option; the engine never sees this because its pane HAS a tty. Dropped so a
 * doctor's lines, which the desktop shows verbatim, are the doctor's.
 *
 * bash says more, all of it on stderr. Two lines at startup, when it tries to take a terminal
 * process group it does not have (`cannot set terminal process group`, `no job control in this
 * shell`); one more (`tcsetattr`) when a foreground child ends on a signal, as under the timeout
 * below; and its `exit` builtin, interactive, echoes `exit` — `logout` in a login shell, which this
 * is — so a doctor ending in `exit 1` said `logout`. Measured 2026-09-20 with SHELL=/bin/bash and
 * no tty: the hosted CI runner's situation, and a Linux daemon's whenever it was not started from a
 * terminal. Neither `+m` nor `set +m` silences the first two. The echo is matched as a whole line
 * and, when the caller says which stream a line came from, only on stderr, where bash writes it: a
 * doctor whose own stdout line is exactly `exit` or `logout` keeps it. A caller that does not say
 * (the viewer's log) loses such a line on either stream; nothing else is close.
 */
export function isShellNoise(line: string, stream?: 'stdout' | 'stderr'): boolean {
  return /can't change option: zle$/.test(line)
    || /^\(eval\):\d+: can't change option: zle$/.test(line)
    || /^bash: cannot set terminal process group \(-?\d+\): /.test(line)
    || line === 'bash: no job control in this shell'
    || /^bash: \[\d+: \d+ \(\d+\)\] tcsetattr: /.test(line)
    || (stream !== 'stdout' && (line === 'exit' || line === 'logout'))
}

/**
 * The first line of a script run in the user's interactive shell: what lets a timeout end the SHELL,
 * not only the command it was running.
 *
 * An interactive shell ignores SIGTERM for its whole life — bash and zsh both, so that `kill 0` at a
 * prompt does not take the prompt with it. That prompt is what the ignore is for, and this shell has
 * none. Left alone, killProcessGroup's SIGTERM ended the command that was running (children get the
 * default disposition back) and the shell went on with the REST of the script — `npm ci; rm -rf
 * build; …` with a hung `npm ci` ran the `rm` — until the SIGKILL that follows the grace period.
 * `trap - TERM` cannot undo the ignore (bash counts it as ignored on entry); an explicit trap can, and
 * both shells run it as soon as the foreground command has ended, which that same SIGTERM sees to.
 * 143 is what a SIGTERM death reports, so a stopped script reads as one whichever way it ended.
 *
 * The trap is in place only once the shell has read its rc files. A SIGTERM that lands before that is
 * still ignored, and the SIGKILL after KILL_GRACE_MS is what ends such a shell — which is why the
 * timeout tests advance through the grace period too, and why nothing here shortens it.
 */
export const DSH_STOP_TRAP = "trap 'exit 143' TERM"

/** How long killProcessGroup waits after its SIGTERM before the SIGKILL. */
export const KILL_GRACE_MS = 3_000

/**
 * `[path, ...args]` that runs `script` through the user's shell, or `/bin/sh -c` when none is known.
 *
 * AS A LOGIN SHELL, whatever the shell. interactiveEngineShell gives bash `-ic` on purpose for a pane
 * (see tmuxOnPath.ts on why), but a bash user's PATH conventionally lives in `.bash_profile`, which
 * only `-l` reads — and Terminal.app opens a login shell, so that file is what "on my terminal it
 * works" means. Measured 2026-09-16: Solid's doctor answered `miss codex on PATH` from the daemon
 * while `harness dsh doctor` in Terminal found it, because codex was an npm global under nvm and nvm
 * is sourced from `.bash_profile`. A setup or a doctor is one process, so the reason bash panes avoid
 * `-l` (a PATH built in .bashrc compounding across subshells) does not apply here.
 */
export function dshShellArgv(script: string): { path: string; args: string[] } {
  const shell = interactiveEngineShell()
  if (shell) {
    const args = shell.args.map((a) => (a === '-ic' ? '-lic' : a))
    return { path: shell.path, args: [...args, `${DSH_STOP_TRAP}\n${dshNodeFallback()}\n${script}`] }
  }
  // `sh -c` is not interactive and dies of a SIGTERM as any process does; no trap needed.
  return { path: '/bin/sh', args: ['-c', `${dshNodeFallback()}\n${script}`] }
}

/**
 * The line run before a DSH's command: when the login shell's PATH has no `node`, the Node this
 * daemon runs on joins the END of it. Since the product moved to a private runtime, a machine with no
 * node on PATH is the normal case (see nodeRuntime.ts), and a package whose setup says `npm ci` or
 * whose viewer is `node viewer.mjs` would otherwise fail on exactly the machines Harness set up
 * itself. Appended, not prepended, so a node the person installed always wins; and run after the rc
 * files, so a profile that assigns PATH outright cannot drop it.
 */
export function dshNodeFallback(): string {
  return harnessNodePrelude(managedNodePath()).trimEnd()
}

export function spawnDshCommand(script: string, opts: { cwd: string; env?: Record<string, string> }): ChildProcess {
  const { path, args } = dshShellArgv(script)
  return spawn(path, args, {
    cwd: opts.cwd,
    env: { ...process.env, ...(opts.env ?? {}) },
    stdio: ['ignore', 'pipe', 'pipe'],
    // Its own process group, so stopping it stops what it started (`sh -c node …`).
    detached: true,
  })
}

/** Run to completion, collecting output lines. Never rejects: a spawn failure is a non-zero exit. */
export function runDshCommand(script: string, opts: DshCommandOptions): Promise<DshCommandResult> {
  return new Promise((resolve) => {
    const lines: string[] = []
    let timedOut = false
    let settled = false
    let child: ChildProcess
    try {
      child = spawnDshCommand(script, { cwd: opts.cwd, env: opts.env })
    } catch (error) {
      // spawn throws only Errors (an invalid argument: a NUL in the cwd, say).
      const line = `could not start: ${(error as Error).message}`
      opts.onLine?.(line)
      resolve({ code: 127, signal: null, lines: [line], timedOut: false })
      return
    }
    const feed = (chunk: Buffer, carry: { rest: string; stream: 'stdout' | 'stderr' }): void => {
      carry.rest += chunk.toString('utf8')
      let at: number
      while ((at = carry.rest.indexOf('\n')) >= 0) {
        const line = carry.rest.slice(0, at).replace(/\r$/, '')
        carry.rest = carry.rest.slice(at + 1)
        if (isShellNoise(line, carry.stream)) continue
        lines.push(line)
        opts.onLine?.(line)
      }
    }
    const out = { rest: '', stream: 'stdout' as const }
    const err = { rest: '', stream: 'stderr' as const }
    child.stdout?.on('data', (chunk: Buffer) => feed(chunk, out))
    child.stderr?.on('data', (chunk: Buffer) => feed(chunk, err))
    const finish = (code: number | null, signal: NodeJS.Signals | null): void => {
      if (settled) return
      settled = true
      if (timer) clearTimeout(timer)
      for (const carry of [out, err]) {
        if (carry.rest) { lines.push(carry.rest); opts.onLine?.(carry.rest) }
      }
      resolve({ code, signal, lines, timedOut })
    }
    const timer = opts.timeoutMs
      ? setTimeout(() => {
        timedOut = true
        killProcessGroup(child)
      }, opts.timeoutMs)
      : null
    timer?.unref?.()
    child.on('error', (error) => {
      const line = `could not start: ${error.message}`
      lines.push(line)
      opts.onLine?.(line)
      finish(127, null)
    })
    child.on('exit', (code, signal) => finish(code, signal))
  })
}

/** SIGTERM the child's whole group, then SIGKILL what is left a moment later. */
export function killProcessGroup(child: ChildProcess, graceMs = KILL_GRACE_MS): void {
  const pid = child.pid
  if (!pid) return
  const timer = killPidGroup(pid, graceMs)
  child.once('exit', () => clearTimeout(timer))
}

/** The same, for a group this process did not spawn (a viewer left over from an earlier daemon —
 *  see viewerLedger.ts): nothing to wait on, so the SIGKILL follow-up fires unconditionally. */
export function killPidGroup(pid: number, graceMs = 3_000): NodeJS.Timeout {
  // pid 1 would make `-pid` "every process in my session"; nothing this daemon reaps is init.
  if (!Number.isInteger(pid) || pid <= 1) return setTimeout(() => {}, 0)
  const signalGroup = (signal: NodeJS.Signals): void => {
    try { process.kill(-pid, signal) } catch { /* already gone */ }
    try { process.kill(pid, signal) } catch { /* already gone */ }
  }
  signalGroup('SIGTERM')
  const timer = setTimeout(() => signalGroup('SIGKILL'), graceMs)
  timer.unref?.()
  return timer
}
