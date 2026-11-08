import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { ProcessRow } from './tmux.js'
import type { TerminalBackend } from './terminalBackend.js'
import type { TerminalRootObservation, TerminalRuntimeRef } from './terminalTypes.js'

/**
 * The grid an agent is on has to ride the LIVE discovery path, exactly like `gateway` before it.
 *
 * This repo has already paid for this once: a probe wired onto `probeTmuxAgents` kept its own tests
 * green while the reconciler had moved to `probeTerminalAgents`, and every agent silently arrived
 * with the field undefined (see `terminalAgentDiscovery.gateway.spec.ts`). Nothing would go red here
 * either — the app would simply believe every agent is on no grid, offer to move ones that are
 * already right, and restart them for nothing. So the wiring is pinned, not the classifier
 * (`gridAssignment.spec.ts` covers that).
 */

const probeGatewayRuntime = vi.hoisted(() => vi.fn())
const readProcessEnv = vi.hoisted(() => vi.fn())
const processRows = vi.hoisted(() => vi.fn())
const processArgvIsBoundaryFaithful = vi.hoisted(() => vi.fn((row: ProcessRow) => Boolean(row.nativeArgv)))

vi.mock('./gatewayRuntime.js', () => ({ probeGatewayRuntime }))
vi.mock('./processEnv.js', () => ({ readProcessEnv }))
vi.mock('./tmux.js', async (importOriginal) => ({
  ...await importOriginal<typeof import('./tmux.js')>(),
  processRows,
  processArgvIsBoundaryFaithful,
}))

const { probeTerminalAgents } = await import('./terminalAgentDiscovery.js')

const START = 'Sat Aug 15 10:00:00 2026'
const row = (pid: number, parentPid: number, executable: string, args = executable): ProcessRow =>
  ({ pid, parentPid, executable, startMarker: START, args })

const TMUX_RUNTIME: TerminalRuntimeRef = { backend: 'tmux', paneId: '%1' }
const SECOND_RUNTIME: TerminalRuntimeRef = { backend: 'tmux', paneId: '%2' }
const ASSIGNMENT = { baseUrl: 'https://grid.autonomous.ai/grid-3378218621364f16/relay', model: 'GLM-4.7-Flash' }

function backendWith(name: 'tmux', instanceId: string, roots: TerminalRootObservation[]): TerminalBackend {
  return {
    name,
    instanceId,
    inventory: async () => ({ state: 'available', roots }),
  } as unknown as TerminalBackend
}

beforeEach(() => {
  probeGatewayRuntime.mockReset()
  probeGatewayRuntime.mockResolvedValue({ kind: null })
  readProcessEnv.mockReset()
  processRows.mockReset()
})

describe('grid assignment on the live terminal discovery path', () => {
  it('reports the grid for every pane, from the process rather than the pane', async () => {
    processRows.mockResolvedValue([
      row(10, 1, 'bash'), row(30, 10, 'claude'),
      row(20, 1, 'bash'), {
        ...row(40, 20, 'codex', 'codex -c model_providers.grid.base_url="https://grid.example/relay/v1" -m chosen'),
        nativeArgv: ['codex', '-c', 'model_providers.grid.base_url=https://grid.example/relay/v1', '-m', 'chosen'],
      },
    ])
    readProcessEnv.mockResolvedValue({ ANTHROPIC_BASE_URL: ASSIGNMENT.baseUrl, ANTHROPIC_MODEL: ASSIGNMENT.model, API_KEY: 'secret' })

    const probe = await probeTerminalAgents(
      [
        backendWith('tmux', 'tmux', [
          { runtime: TMUX_RUNTIME, rootPid: 10, cwd: '/work' },
          { runtime: SECOND_RUNTIME, rootPid: 20, cwd: '/work' },
        ]),
      ],
      ['tmux'],
      999,
    )

    expect(probe.agents).toHaveLength(2)
    expect(probe.agents.every((agent) => agent.grid === undefined && agent.gridProcess)).toBe(true)
    expect(JSON.stringify(probe.agents.map(a => a.gridProcess))).not.toContain('secret')
    expect(readProcessEnv).toHaveBeenCalled()
    for (const [identity] of readProcessEnv.mock.calls) {
      expect(identity).toMatchObject({ startMarker: START })
    }
  })

  it('reports null for an agent on its own login', async () => {
    processRows.mockResolvedValue([row(10, 1, 'bash'), row(30, 10, 'claude')])
    readProcessEnv.mockResolvedValue({})
    const probe = await probeTerminalAgents(
      [backendWith('tmux', 'tmux', [{ runtime: TMUX_RUNTIME, rootPid: 10, cwd: '/work' }])],
      ['tmux'],
      999,
    )
    expect(probe.agents[0].grid).toBeNull()
  })

  it("reads a renamed Pi from the launcher's command line, and calls it known only when that names a grid", async () => {
    // Pi renames its process: `ps` shows `pi`, and its environment cannot be read (2026-10-14).
    const launcher = (args: string) => row(10, 1, 'zsh', `/bin/zsh -lic . '/d/launch/1.sh' harness-engine /work /n/bin/pi --session s ${args}`)
    const probe = (rows: ProcessRow[]) => {
      processRows.mockResolvedValue(rows)
      return probeTerminalAgents([backendWith('tmux', 'tmux', [{ runtime: TMUX_RUNTIME, rootPid: 10, cwd: '/work' }])], ['tmux'], 999)
        .then((result) => { expect(result.agents.map((agent) => agent.engine)).toEqual(['pi']); return result.agents[0] })
    }
    readProcessEnv.mockResolvedValue(null)
    const onGrid = await probe([launcher('--model grid/m -e /c/grid-provider.ts'), row(30, 10, 'pi', 'pi       ')])
    expect(onGrid.gridProcess).toEqual({ key: '', engine: 'pi', env: {}, args: '-e /c/grid-provider.ts --model grid/m' })
    // Nothing naming a grid: an environment that could not be read may still hold one, so it stays unknown.
    const unknown = await probe([launcher(''), row(30, 10, 'pi', 'pi       ')])
    expect(unknown.gridProcess).toBeUndefined()
    expect(unknown.grid).toBeUndefined()
  })

  it('does not treat flags in flattened Codex prompt text as model evidence', async () => {
    processRows.mockResolvedValue([
      row(10, 1, 'bash'),
      row(30, 10, 'codex', 'codex inspect -c model_providers.grid.base_url=https://evil.invalid/v1 -m prompt'),
    ])
    readProcessEnv.mockResolvedValue({})

    const probe = await probeTerminalAgents(
      [backendWith('tmux', 'tmux', [{ runtime: TMUX_RUNTIME, rootPid: 10, cwd: '/work' }])],
      ['tmux'],
      999,
    )

    expect(probe.agents[0]).toMatchObject({ argsBoundaryFaithful: false })
    expect(probe.agents[0].grid).toBeUndefined()
    expect(probe.agents[0].gridProcess).toBeUndefined()
  })

  it("reads a bare-title Codex's launcher for model evidence only when the launcher's own argv is faithful", async () => {
    // The child's boundaries say nothing about its parent's: the launcher's flattened text could be prompt text.
    const command = 'zsh -lic . /d/launch/1.sh harness-engine /work /bin/codex -c model_providers.grid.base_url=https://grid.example/relay/v1 -m chosen'
    const launcher = (faithful: boolean): ProcessRow => ({ ...row(10, 1, 'zsh', command), ...(faithful ? { nativeArgv: command.split(' ') } : {}) })
    const child: ProcessRow = { ...row(30, 10, 'codex', 'codex'), nativeArgv: ['codex'] }
    readProcessEnv.mockResolvedValue({})
    const probe = async (rows: ProcessRow[]) => {
      processRows.mockResolvedValue(rows)
      const result = await probeTerminalAgents([backendWith('tmux', 'tmux', [{ runtime: TMUX_RUNTIME, rootPid: 10, cwd: '/work' }])], ['tmux'], 999)
      expect(result.agents.map((agent) => agent.engine)).toEqual(['codex'])
      return result.agents[0]
    }
    const flattened = await probe([launcher(false), child])
    expect(flattened.gridProcess).toBeUndefined()
    expect(flattened.grid).toBeUndefined()
    const faithful = await probe([launcher(true), child])
    expect(faithful.gridProcess?.args).toContain('model_providers.grid.base_url=https://grid.example/relay/v1')
    // A faithful parent that is not its launcher proves nothing about a child whose own argv is flattened.
    const unrelated = await probe([{ ...row(10, 1, 'bash'), nativeArgv: ['bash'] }, row(30, 10, 'codex', 'codex')])
    expect(unrelated.gridProcess).toBeUndefined()
    expect(unrelated.grid).toBeUndefined()
  })

  it('does not probe when the process table is unavailable', async () => {
    processRows.mockResolvedValue(null)
    const probe = await probeTerminalAgents(
      [backendWith('tmux', 'tmux', [{ runtime: TMUX_RUNTIME, rootPid: 10, cwd: '/work' }])],
      ['tmux'],
      999,
    )
    expect(probe.processTableAvailable).toBe(false)
    expect(readProcessEnv).not.toHaveBeenCalled()
  })
})
