import { afterEach, expect, it } from 'vitest'
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { InstalledDsh } from './installed.js'
import { harnessRuntimeDir, prepareHarnessLaunch } from './runtime.js'

const roots: string[] = []

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true })
})

it.runIf(process.platform === 'win32')('creates every native runtime path component and rewrites native legacy skill paths', () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), 'native-runtime-')))
  roots.push(root)
  const workspace = join(root, 'project with spaces')
  const packageDir = join(root, 'package')
  mkdirSync(workspace)
  mkdirSync(packageDir)
  writeFileSync(join(packageDir, 'AGENTS.md'), '# Native runtime\n')
  const installed: InstalledDsh = {
    id: 'acme/native-runtime', dir: packageDir, realDir: packageDir, source: packageDir,
    ref: null, commit: null, linked: true, installedAt: 1,
    manifest: {
      spec: 1, id: 'acme/native-runtime', name: 'Native runtime', engine: 'codex',
      agent: {
        instructions: 'AGENTS.md',
        env: {
          TOOLCHAIN: '${dsh}/tools',
          CLAUDE_SKILLS: '${workspace}/.claude/skills',
          AGENT_SKILLS: '${workspace}/.agents/skills',
        },
        args: ['--input', '${workspace}/input'],
      },
    },
  }

  const launch = prepareHarnessLaunch(installed, workspace, 'codex', 'session')

  expect(existsSync(join(harnessRuntimeDir(workspace, 'session'), 'runtime.json'))).toBe(true)
  expect(existsSync(launch.env.HARNESS_CONTEXT_FILE!)).toBe(true)
  expect(launch.env.TOOLCHAIN).toBe(join(packageDir, 'tools'))
  expect(launch.env.CLAUDE_SKILLS).toBe(launch.env.HARNESS_SKILLS_DIR)
  expect(launch.env.AGENT_SKILLS).toBe(launch.env.HARNESS_SKILLS_DIR)
  expect(launch.args).toContain(join(workspace, 'input'))
})
