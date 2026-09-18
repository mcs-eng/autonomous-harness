import { afterEach, describe, expect, it } from 'vitest'
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import {
  BYPASS_PERMISSION_FLAGS,
  LAUNCH_RESUME_FLAG,
  buildEngineCommandArgv,
  buildEngineLaunchArgv,
  commandAvailableInInteractiveShell,
} from './engineLaunch.js'
import { ENGINES } from '../engines/types.js'
import { engineBin } from './engineBin.js'
import type { EngineInstallRecipe } from './engineInstall.js'

describe('buildEngineLaunchArgv', () => {
  it('wraps zsh in its interactive login form and execs the resolved binary', () => {
    expect(buildEngineLaunchArgv('claude', {}, '/bin/zsh')).toEqual([
      '/bin/zsh', '-lic', 'exec "$@"', 'harness-engine', engineBin('claude'),
    ])
  })

  it('uses Ubuntu bash interactive startup files without making it a login shell', () => {
    expect(buildEngineLaunchArgv('claude', {}, '/bin/bash')).toEqual([
      '/bin/bash', '-ic', 'exec "$@"', 'harness-engine', engineBin('claude'),
    ])
  })

  it('enters the workspace only after interactive startup has completed', () => {
    const argv = buildEngineLaunchArgv('claude', { cwd: '/work/project' }, '/bin/zsh')
    expect(argv).toEqual([
      '/bin/zsh', '-lic',
      'if ! cd -- "$1"; then printf \'%s\\n\' \'harness: the selected working directory is unavailable.\' >&2; exit 1; fi\nshift\nexec "$@"',
      'harness-engine', '/work/project', engineBin('claude'),
    ])
  })

  it('falls back to direct execution when no absolute shell is available', () => {
    expect(buildEngineLaunchArgv('claude', {}, '')).toEqual([engineBin('claude')])
    expect(buildEngineLaunchArgv('claude', {}, 'zsh')).toEqual([engineBin('claude')])
  })

  it('appends the confirmed flag for engines with a known bypass flag', () => {
    expect(buildEngineCommandArgv('claude', { bypassPermission: true }))
      .toEqual([engineBin('claude'), '--dangerously-skip-permissions'])
    expect(buildEngineCommandArgv('codex', { bypassPermission: true }))
      .toEqual([engineBin('codex'), '--dangerously-bypass-approvals-and-sandbox'])
    expect(buildEngineCommandArgv('cursor', { bypassPermission: true }))
      .toEqual([engineBin('cursor'), '--force'])
    expect(buildEngineCommandArgv('opencode', { bypassPermission: true }))
      .toEqual([engineBin('opencode'), '--auto'])
  })

  it('is a no-op for engines with no confirmed flag, even when bypass is requested', () => {
    expect(buildEngineCommandArgv('pi', { bypassPermission: true })).toEqual([engineBin('pi')])
    expect(buildEngineCommandArgv('hermes', { bypassPermission: true })).toEqual([engineBin('hermes')])
  })

  it('has an entry (possibly null) for every known engine — no engine silently falls through', () => {
    for (const engine of ENGINES) {
      expect(Object.prototype.hasOwnProperty.call(BYPASS_PERMISSION_FLAGS, engine)).toBe(true)
    }
  })

  it('appends a flag-style resume argument after the binary', () => {
    expect(buildEngineCommandArgv('claude', { resumeSessionId: 'abc-123' }))
      .toEqual([engineBin('claude'), '--resume', 'abc-123'])
    expect(buildEngineCommandArgv('opencode', { resumeSessionId: 'ses_1' }))
      .toEqual([engineBin('opencode'), '--session', 'ses_1'])
  })

  it('puts a subcommand-style resume FIRST, ahead of any other flag', () => {
    expect(buildEngineCommandArgv('codex', { resumeSessionId: 'abc-123' }))
      .toEqual([engineBin('codex'), 'resume', 'abc-123'])
    expect(buildEngineCommandArgv('codex', { resumeSessionId: 'abc-123', bypassPermission: true }))
      .toEqual([engineBin('codex'), 'resume', 'abc-123', '--dangerously-bypass-approvals-and-sandbox'])
    expect(buildEngineCommandArgv('amp', { resumeSessionId: 'T-1' }))
      .toEqual([engineBin('amp'), 'threads', 'continue', 'T-1'])
  })

  it('still applies bypassPermission with no resume requested (regression)', () => {
    expect(buildEngineCommandArgv('claude', { bypassPermission: true }))
      .toEqual([engineBin('claude'), '--dangerously-skip-permissions'])
  })

  it('is a no-op when resumeSessionId is set but the engine has no known launch resume flag', () => {
    expect(buildEngineCommandArgv('devin', { resumeSessionId: 'abc-123' })).toEqual([engineBin('devin')])
  })

  it('has a launch resume flag for every engine RESUME_ARGS also covers, plus claude/codex', () => {
    for (const engine of ['claude', 'codex', 'cursor', 'opencode', 'kilo', 'pi', 'hermes', 'commandcode',
      'muse', 'amp', 'grok', 'agy', 'copilot'] as const) {
      expect(LAUNCH_RESUME_FLAG[engine]?.length).toBeGreaterThan(0)
    }
    expect(LAUNCH_RESUME_FLAG.devin).toBeUndefined()
  })
})

const dirs: string[] = []
const originalProbePath = process.env.HARNESS_ENGINE_TEST_PATH

afterEach(() => {
  if (originalProbePath === undefined) delete process.env.HARNESS_ENGINE_TEST_PATH
  else process.env.HARNESS_ENGINE_TEST_PATH = originalProbePath
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true })
})

function executable(dir: string, name: string): string {
  const path = join(dir, name)
  writeFileSync(path, '#!/bin/sh\nexit 0\n')
  chmodSync(path, 0o700)
  return path
}

function bashProbeShell(): string {
  const dir = mkdtempSync(join(tmpdir(), 'harness-engine-shell-'))
  dirs.push(dir)
  const shell = join(dir, 'bash')
  writeFileSync(shell, `#!/bin/sh
[ "$1" = '-ic' ] || exit 97
shift
script="$1"
shift
PATH="$HARNESS_ENGINE_TEST_PATH"
export PATH
exec /bin/sh -c "$script" "$@"
`)
  chmodSync(shell, 0o700)
  return shell
}

describe('commandAvailableInInteractiveShell', () => {
  it('uses the same bash interactive PATH that launches a new engine', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-bin-'))
    dirs.push(binDir)
    executable(binDir, 'kilo')
    process.env.HARNESS_ENGINE_TEST_PATH = binDir

    await expect(commandAvailableInInteractiveShell('kilo', bashProbeShell())).resolves.toBe(true)
    await expect(commandAvailableInInteractiveShell('missing-engine', bashProbeShell())).resolves.toBe(false)
  })

  it('recognizes an installed vendor path before the shell profile has it on PATH', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-vendor-bin-'))
    dirs.push(binDir)
    const installed = executable(binDir, 'cursor-agent')
    process.env.HARNESS_ENGINE_TEST_PATH = '/usr/bin:/bin'
    const recipe: EngineInstallRecipe = {
      command: 'false',
      source: 'test fixture',
      executable: { names: ['cursor-agent'], absolutePaths: [installed] },
    }

    await expect(
      commandAvailableInInteractiveShell('cursor-agent', bashProbeShell(), recipe),
    ).resolves.toBe(true)
  })

  it('rejects a resolved executable that fails its bounded health probe', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-unhealthy-'))
    dirs.push(binDir)
    const unhealthy = join(binDir, 'copilot')
    writeFileSync(unhealthy, '#!/bin/sh\nexit 1\n')
    chmodSync(unhealthy, 0o700)
    process.env.HARNESS_ENGINE_TEST_PATH = binDir
    const recipe: EngineInstallRecipe = {
      command: 'false',
      source: 'test fixture',
      executable: { names: ['copilot'], probeArgs: ['--version'] },
    }

    await expect(commandAvailableInInteractiveShell('copilot', bashProbeShell(), recipe))
      .resolves.toBe(false)
  })

  it('accepts a resolved executable that passes its health probe', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-healthy-'))
    dirs.push(binDir)
    executable(binDir, 'copilot')
    process.env.HARNESS_ENGINE_TEST_PATH = binDir
    const recipe: EngineInstallRecipe = {
      command: 'false',
      source: 'test fixture',
      executable: { names: ['copilot'], probeArgs: ['--version'] },
    }

    await expect(commandAvailableInInteractiveShell('copilot', bashProbeShell(), recipe))
      .resolves.toBe(true)
  })

  it('probes the same resolved command and recipe name only once', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-dedup-'))
    dirs.push(binDir)
    const attempts = join(binDir, 'attempts')
    const unhealthy = join(binDir, 'copilot')
    writeFileSync(unhealthy, `#!/bin/sh\n/usr/bin/printf x >> ${JSON.stringify(attempts)}\nexit 1\n`)
    chmodSync(unhealthy, 0o700)
    process.env.HARNESS_ENGINE_TEST_PATH = binDir
    const recipe: EngineInstallRecipe = {
      command: 'false',
      source: 'test fixture',
      executable: { names: ['copilot'], probeArgs: ['--version'] },
    }

    await expect(commandAvailableInInteractiveShell('copilot', bashProbeShell(), recipe))
      .resolves.toBe(false)
    expect(readFileSync(attempts, 'utf8')).toBe('x')
  })

  it('bounds a health probe that never returns', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-engine-hung-'))
    dirs.push(binDir)
    const hung = join(binDir, 'copilot')
    writeFileSync(hung, '#!/bin/sh\ntrap \'\' TERM\n/bin/sleep 30\n')
    chmodSync(hung, 0o700)
    process.env.HARNESS_ENGINE_TEST_PATH = binDir
    const recipe: EngineInstallRecipe = {
      command: 'false',
      source: 'test fixture',
      executable: { names: ['copilot'], probeArgs: ['--version'] },
    }

    const started = Date.now()
    await expect(commandAvailableInInteractiveShell('copilot', bashProbeShell(), recipe))
      .resolves.toBe(false)
    expect(Date.now() - started).toBeLessThan(8_000)
  }, 10_000)
})

describe('buildEngineLaunchArgv with installFirst', () => {
  // Everything here is about ONE rule: the engine must not be exec'd after an install that failed.
  // Doing so reproduces the `command not found` this feature exists to replace, with a screenful of
  // installer output above it to bury the cause.
  const script = (install: string): string =>
    buildEngineLaunchArgv('opencode', { installFirst: install }, '/bin/zsh')[2]

  it('leaves the plain launch alone when nothing has to be installed', () => {
    expect(buildEngineLaunchArgv('opencode', {}, '/bin/zsh')[2]).toBe('exec "$@"')
  })

  it('keeps the engine argv positional, so the shell never re-parses a path or a flag', () => {
    const argv = buildEngineLaunchArgv('opencode', {
      installFirst: 'npm install -g opencode-ai',
      bypassPermission: true,
    }, '/bin/zsh')
    expect(argv.slice(0, 2)).toEqual(['/bin/zsh', '-lic'])
    expect(argv.slice(3)).toEqual(['harness-engine', ...buildEngineCommandArgv('opencode', { bypassPermission: true })])
    expect(argv[2]).toContain('exec "$@"')
  })

  it('runs the engine only when the install succeeded', async () => {
    await expect(runPaneScript(script('true'))).resolves.toMatchObject({ code: 0, ranEngine: true })
  })

  it('does not run the engine when the install returns a failure', async () => {
    const result = await runPaneScript(script('false'))
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
    expect(result.stdout).toContain('the install failed')
  })

  it('does not run the engine when the install command is not there at all', async () => {
    const result = await runPaneScript(script('harness-no-such-installer --please'))
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
  })

  it('prints the command before running it, so a long install is not a hung pane', () => {
    expect(script('npm install -g opencode-ai')).toContain('npm install -g opencode-ai')
  })

  it("survives an install line carrying a quote, rather than ending the shell's string", async () => {
    // `curl … | bash` is already in the table; a quoted argument is the next shape to arrive, and an
    // install line is a constant in our own source — so the failure mode is a broken pane, not an
    // injection. It still must not break.
    const result = await runPaneScript(script(`sh -c 'exit 3'`))
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
  })
})

describe('buildEngineLaunchArgv with installIfMissing', () => {
  const recipe = (
    command: string,
    executable: EngineInstallRecipe['executable'] = { names: ['harness-no-such-engine'] },
  ): EngineInstallRecipe => ({ command, source: 'test fixture', executable })
  const script = (install: EngineInstallRecipe, runtimeNode?: string): string =>
    buildEngineLaunchArgv('opencode', { installIfMissing: install }, '/bin/zsh', runtimeNode)[2]
  const scriptWithoutProcessRuntime = (install: EngineInstallRecipe): string => {
    const original = Object.getOwnPropertyDescriptor(process, 'execPath')
    try {
      Object.defineProperty(process, 'execPath', { ...original, value: '/missing/process/node' })
      return script(install, '/missing/runtime/node')
    } finally {
      if (original) Object.defineProperty(process, 'execPath', original)
    }
  }

  it('execs an installed engine without running the installer', async () => {
    await expect(runPaneScript(script(recipe('false')))).resolves.toMatchObject({ code: 0, ranEngine: true })
  })

  it('runs the installer inside the pane when the engine is absent', async () => {
    const result = await runPaneScript(script(recipe('false')), 'harness-no-such-engine')
    expect(result.ranEngine).toBe(false)
    expect(result.code).toBe(1)
    expect(result.stdout).toContain('engine is missing')
  })

  it('execs a vendor path after install even when the current PATH did not reload', async () => {
    const dir = mkdtempSync(join(tmpdir(), 'harness-engine-installed-'))
    dirs.push(dir)
    const source = join(dir, 'source-engine')
    const installed = join(dir, 'new-engine')
    writeFileSync(source, '#!/bin/sh\n/usr/bin/printf "%s" "$1"\n')
    chmodSync(source, 0o700)
    const install = `cp ${JSON.stringify(source)} ${JSON.stringify(installed)}`
    const result = await runPaneScript(
      script(recipe(install, { names: ['harness-no-such-engine'], absolutePaths: [installed] })),
      'harness-no-such-engine',
    )
    expect(result).toMatchObject({ code: 0, ranEngine: true })
  })

  it('reports a successful install that did not provide an executable', async () => {
    const result = await runPaneScript(script(recipe('true')), 'harness-no-such-engine')
    expect(result).toMatchObject({ code: 1, ranEngine: false })
    expect(result.stdout).toContain('install completed, but its executable could not be found')
  })

  it.each([
    ['no npm', false],
    ['a Windows npm shim without Linux node', true],
  ])('enables the managed Node.js/npm pair when PATH has %s', async (_description, windowsNpm) => {
    const runtimeBin = mkdtempSync(join(tmpdir(), 'harness-managed-node-bin-'))
    const interopBin = mkdtempSync(join(tmpdir(), 'harness-windows-npm-bin-'))
    dirs.push(runtimeBin, interopBin)
    const runtimeNode = executable(runtimeBin, 'node')
    if (windowsNpm) {
      writeFileSync(join(interopBin, 'npm'), '#!/bin/sh\nprintf "WINDOWS-NPM-MUST-NOT-RUN\\n"\nexit 91\n')
      chmodSync(join(interopBin, 'npm'), 0o700)
    }
    const engineSource = join(runtimeBin, 'engine-source')
    writeFileSync(engineSource, '#!/bin/sh\n/usr/bin/printf "HARNESS-TEST-ENGINE-RAN\\n"\n')
    chmodSync(engineSource, 0o700)
    const installed = join(runtimeBin, 'installed-engine')
    const npm = join(runtimeBin, 'npm')
    writeFileSync(npm, `#!/bin/sh
if [ "$1" = prefix ]; then exit 0; fi
/bin/cp ${JSON.stringify(engineSource)} ${JSON.stringify(installed)}
/bin/chmod 700 ${JSON.stringify(installed)}
`)
    chmodSync(npm, 0o700)

    const result = await runPaneScript(
      script(recipe('npm install -g fixture', {
        names: ['harness-no-such-engine'],
        absolutePaths: [installed],
        npmGlobal: true,
      }), runtimeNode),
      'harness-no-such-engine',
      { PATH: interopBin },
    )

    expect(result).toMatchObject({ code: 0, ranEngine: true })
    expect(result.stdout).not.toContain('WINDOWS-NPM-MUST-NOT-RUN')
  })

  it('installs and launches a healthy vendor candidate when the PATH executable fails its probe', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-probed-engine-path-'))
    const installDir = mkdtempSync(join(tmpdir(), 'harness-probed-engine-install-'))
    dirs.push(binDir, installDir)
    const unhealthy = join(binDir, 'copilot')
    writeFileSync(unhealthy, '#!/bin/sh\nexit 1\n')
    chmodSync(unhealthy, 0o700)
    const source = join(installDir, 'source')
    const installed = join(installDir, 'copilot')
    writeFileSync(source, '#!/bin/sh\nif [ "$1" = "--version" ]; then exit 0; fi\n/usr/bin/printf "HARNESS-TEST-ENGINE-RAN\\n"\n')
    chmodSync(source, 0o700)
    const install = `/bin/cp ${JSON.stringify(source)} ${JSON.stringify(installed)} && /bin/chmod 700 ${JSON.stringify(installed)}`
    const result = await runPaneScript(
      script(recipe(install, {
        names: ['copilot'],
        absolutePaths: [installed],
        probeArgs: ['--version'],
      }), process.execPath),
      'copilot',
      { ...process.env, PATH: binDir },
    )

    expect(result).toMatchObject({ code: 0, ranEngine: true })
  })

  it('does not install over an existing executable that passes its probe', async () => {
    const binDir = mkdtempSync(join(tmpdir(), 'harness-probed-engine-healthy-'))
    dirs.push(binDir)
    const healthy = join(binDir, 'copilot')
    const installMarker = join(binDir, 'installer-ran')
    writeFileSync(healthy, '#!/bin/sh\nif [ "$1" = "--version" ]; then exit 0; fi\n/usr/bin/printf "HARNESS-TEST-ENGINE-RAN\\n"\n')
    chmodSync(healthy, 0o700)
    const result = await runPaneScript(
      script(recipe(`/usr/bin/touch ${JSON.stringify(installMarker)}`, {
        names: ['copilot'],
        probeArgs: ['--version'],
      }), process.execPath),
      'copilot',
      { ...process.env, PATH: binDir },
    )

    expect(result).toMatchObject({ code: 0, ranEngine: true })
    expect(existsSync(installMarker)).toBe(false)
  })

  it('bootstraps node before first exec of an already-installed node-shebang engine', async () => {
    const runtimeBin = mkdtempSync(join(tmpdir(), 'harness-managed-node-shebang-'))
    const interopBin = mkdtempSync(join(tmpdir(), 'harness-node-shebang-path-'))
    dirs.push(runtimeBin, interopBin)
    const runtimeNode = join(runtimeBin, 'node')
    writeFileSync(runtimeNode, '#!/bin/sh\nscript="$1"\nshift\nexec /bin/sh "$script" "$@"\n')
    chmodSync(runtimeNode, 0o700)
    executable(runtimeBin, 'npm')
    writeFileSync(join(interopBin, 'npm'), '#!/bin/sh\nexit 91\n')
    chmodSync(join(interopBin, 'npm'), 0o700)
    const engine = join(interopBin, 'harness-node-engine')
    writeFileSync(engine, '#!/usr/bin/env node\n/usr/bin/printf "HARNESS-TEST-ENGINE-RAN\\n"\n')
    chmodSync(engine, 0o700)

    const result = await runPaneScript(
      script(recipe('false', { names: ['harness-node-engine'], npmGlobal: true }), runtimeNode),
      'harness-node-engine',
      { PATH: interopBin },
    )

    expect(result).toMatchObject({ code: 0, ranEngine: true })
  })

  it('still execs an installed native engine when no Node.js/npm runtime is available', async () => {
    const nativeBin = mkdtempSync(join(tmpdir(), 'harness-native-engine-'))
    dirs.push(nativeBin)
    const nativeEngine = join(nativeBin, 'harness-native-engine')
    writeFileSync(nativeEngine, '#!/bin/sh\n/usr/bin/printf "HARNESS-TEST-ENGINE-RAN\\n"\n')
    chmodSync(nativeEngine, 0o700)

    const result = await runPaneScript(
      scriptWithoutProcessRuntime(recipe('false', { names: ['harness-native-engine'], npmGlobal: true })),
      'harness-native-engine',
      { PATH: nativeBin },
    )

    expect(result).toMatchObject({ code: 0, ranEngine: true })
  })

  it('does not add the npm bootstrap to non-npm installers', () => {
    expect(script(recipe('true'))).not.toContain('managed Node.js/npm')
  })
})

/** Run one generated pane script under /bin/sh and report what it did. */
async function runPaneScript(
  paneScript: string,
  command = '/usr/bin/printf',
  env: NodeJS.ProcessEnv = process.env,
): Promise<{ code: number; stdout: string; ranEngine: boolean }> {
  const { execFile } = await import('node:child_process')
  const marker = 'HARNESS-TEST-ENGINE-RAN'
  return await new Promise((resolve) => {
    execFile(
      '/bin/sh',
      ['-c', paneScript, 'harness-engine', command, `${marker}\n`],
      { timeout: 10_000, env },
      (error, stdout) => {
        const code = error && typeof (error as { code?: unknown }).code === 'number'
          ? (error as unknown as { code: number }).code
          : 0
        resolve({ code, stdout, ranEngine: stdout.includes(marker) })
      },
    )
  })
}
