import { EventEmitter } from 'node:events'
import { mkdtempSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, beforeEach, expect, it, vi } from 'vitest'

const fake = vi.hoisted(() => ({ spawn: vi.fn() }))
vi.mock('node:child_process', async (importOriginal) => ({
  ...await importOriginal<typeof import('node:child_process')>(),
  spawn: fake.spawn,
}))
import { env } from '../config/env.js'
import { cloneInstall } from './install.js'

class GitChild extends EventEmitter {
  stderr = Object.assign(new EventEmitter(), { destroy: vi.fn() })
  kill = vi.fn(() => true)
}

let root: string
let savedDshDir: string
beforeEach(() => {
  fake.spawn.mockReset()
  root = mkdtempSync(join(tmpdir(), 'dsh-git-lifecycle-'))
  savedDshDir = env.DSH_DIR
  env.DSH_DIR = join(root, 'installed')
})
afterEach(() => {
  vi.useRealTimers()
  env.DSH_DIR = savedDshDir
  rmSync(root, { recursive: true, force: true })
})

it.each([true, false])('retains failure diagnostics and retries when stderr arrives before exit = %s', async (beforeExit) => {
  const diagnostic = 'fatal: unable to access https://example.test/thing.git/: Could not resolve host: example.test'
  fake.spawn.mockImplementation(() => {
    const child = new GitChild()
    queueMicrotask(() => {
      const data = () => child.stderr.emit('data', Buffer.from(diagnostic + '\n'))
      if (beforeExit) data()
      child.emit('exit', 128, null)
      if (!beforeExit) data()
      child.emit('close', 128, null)
    })
    return child
  })
  const lines: string[] = []
  const result = await cloneInstall('https://example.test/thing.git', undefined, undefined, line => lines.push(line), [0, 0])
  expect(result).toEqual({
    ok: false,
    error: 'CLONE_FAILED',
    detail: `git clone exited 128: ${diagnostic} · gave up after 3 attempts`,
  })
  expect(fake.spawn).toHaveBeenCalledTimes(3)
  expect(lines.filter(line => line === diagnostic)).toHaveLength(3)
  expect(lines.filter(line => line.startsWith('fetch failed'))).toEqual([
    `fetch failed · git clone exited 128: ${diagnostic} · retrying (2/3)`,
    `fetch failed · git clone exited 128: ${diagnostic} · retrying (3/3)`,
  ])
})

it.each([true, false])('keeps the overall deadline when stderr remains open and Git has exited = %s', async (exited) => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
  const child = new GitChild()
  fake.spawn.mockReturnValue(child)
  const lines: string[] = []
  const pending = cloneInstall('https://example.test/thing.git', undefined, undefined, line => lines.push(line), [0, 0])
  child.stderr.emit('data', Buffer.from('fatal: early EOF'))
  if (exited) child.emit('exit', 128, null)
  vi.advanceTimersByTime(10 * 60_000)
  expect(await pending).toEqual({ ok: false, error: 'CLONE_FAILED', detail: 'git clone was still running after 10 min: fatal: early EOF' })
  expect(fake.spawn).toHaveBeenCalledOnce()
  expect(child.stderr.destroy).toHaveBeenCalledOnce()
  if (exited) expect(child.kill).not.toHaveBeenCalled()
  else expect(child.kill).toHaveBeenCalledExactlyOnceWith('SIGTERM')
  child.stderr.emit('data', Buffer.from('late output\n'))
  child.emit('close', 0, null)
  expect(lines).toEqual(['fatal: early EOF'])
})

it('keeps a spawn error authoritative over later stream and close events', async () => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] })
  const child = new GitChild()
  fake.spawn.mockReturnValue(child)
  const lines: string[] = []
  const pending = cloneInstall('https://example.test/thing.git', undefined, undefined, line => lines.push(line), [])
  child.emit('error', new Error('spawn git ENOENT'))
  child.stderr.emit('data', Buffer.from('late output\n'))
  child.emit('close', -2, null)
  vi.advanceTimersByTime(10 * 60_000)
  expect(await pending).toEqual({ ok: false, error: 'CLONE_FAILED', detail: 'spawn git ENOENT' })
  expect(child.kill).not.toHaveBeenCalled()
  expect(child.stderr.destroy).not.toHaveBeenCalled()
  expect(lines).toEqual([])
})
