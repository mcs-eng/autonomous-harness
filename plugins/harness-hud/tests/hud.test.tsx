import { expect, mock, test } from 'claude-code/testing'

import { applyTaskUpdate, pace, parseFleet, parseVerdict, todosFromWrite, toolLabel, turnsLeft } from '../hooks/hud'

// Fictional fixture: no real machine, folder or person.
const PS = JSON.stringify({
  context: { canStart: { ok: false }, quota: { open: 1, maxOpen: 4 } },
  harnesses: [
    { name: 'this one', agent: 'Claude Code', state: 'working', self: true, yours: false },
    { name: 'api-tests', agent: 'Codex', state: 'idle', self: false, yours: true },
    { name: 'docs-writer', agent: 'Claude Code', state: 'working', self: false, yours: false },
  ],
})

const VERDICT = JSON.stringify({
  spec: 1,
  ready: false,
  summary: '10 slides so far',
  findings: [{ severity: 'warning', kind: 'dense', message: 'slide 4 has 61 words' }],
  phases: [
    { id: 'outline', name: 'Outline', state: 'done' },
    { id: 'draft', name: 'Draft', state: 'active' },
    { id: 'polish', name: 'Polish', state: 'pending' },
  ],
})

test('helpers forecast, parse and label', async () => {
  expect(turnsLeft([10_000, 20_000, 30_000], 30_000, 130_000)).toBe(10)
  expect(turnsLeft([10_000], 10_000, 130_000)).toBe(undefined)
  expect(turnsLeft([30_000, 20_000], 20_000, 130_000)).toBe(undefined)

  const hour = 3_600_000
  // 40% used with 1h of the 5h window gone: on pace for 200%.
  expect(pace({ kind: 'five_hour', percent: 40, resetsAt: 4 * hour }, 0)).toBe(200)
  expect(pace({ kind: 'spend_limit', percent: 40, resetsAt: hour }, 0)).toBe(undefined)

  const fleet = parseFleet(PS)
  expect(fleet?.self).toBe('this one')
  expect(fleet?.siblings.map(s => s.name)).toEqual(['api-tests', 'docs-writer'])
  expect(fleet?.siblings[0]?.mine).toBe(true)
  expect(fleet?.canStart).toBe(false)
  expect(parseFleet('not json')).toBe(undefined)

  const verdict = parseVerdict(VERDICT)
  expect(verdict?.ready).toBe(false)
  expect(verdict?.warnings).toBe(1)
  expect(verdict?.phases[1]?.state).toBe('active')

  const list = todosFromWrite({ newTodos: [{ content: 'Write tests', status: 'in_progress', activeForm: 'Writing tests' }] })
  expect(list?.[0]?.active).toBe('Writing tests')
  const tasks = applyTaskUpdate([{ id: '1', content: 'Ship', status: 'pending' }], { taskId: '1', status: 'completed' })
  expect(tasks[0]?.status).toBe('completed')
  expect(applyTaskUpdate(tasks, { taskId: '1', status: 'deleted' })).toEqual([])

  expect(toolLabel('Bash', { command: 'npm test\nmore' })).toBe('npm test')
  expect(toolLabel('Edit', { file_path: 'C:\\work\\src\\app.ts' })).toBe('app.ts')
})

const BAND = {
  plugin: 'harness-hud',
  component: 'AbovePrompt',
  requestId: 'band',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 160, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const PANE = {
  plugin: 'harness-hud',
  component: 'Pane',
  requestId: 'harness-hud',
  props: { title: 'HUD', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

test('the band and pane show context, tools, verdict and fleet on every surface', async ($, on) => {
  const usage = {
    startedAt: 0,
    context: { tokens: 50_000, window: 200_000, percent: 25 },
    rateLimits: [{ kind: 'five_hour', percentUsed: 40 }],
    cost: { usd: 1.5 },
  }
  // Nothing sits beneath the plugin: each hook here stands for the engine.
  on('command.register', () => ({ value: { command: 'hud' } }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.usage', () => ({ value: usage }))
  on('session.model', () => ({ value: 'claude-opus-5-5' }))
  on('session.cwd', () => ({ value: '/work' }))
  on('session.measure', (_, e) => ({ changed: e.changed }))
  mock.clock(on)
  mock.store(on)
  mock.env(on, {})
  on('fs.exists', () => ({ value: true }))
  on('fs.read', () => ({ value: VERDICT }))
  on('agent.list', () => ({ value: [] }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('process.run', (_, e) =>
    e.argv[0] === 'harness'
      ? { value: { exitCode: 0, stdout: PS, stderr: '' } }
      : e.argv.includes('branch')
        ? { value: { exitCode: 0, stdout: 'feature/hud\n', stderr: '' } }
        : { value: { exitCode: 0, stdout: ' M a.ts\n', stderr: '' } },
  )
  on('tool.call', () => ({ result: {} }))

  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await $.session.measure({ ...usage, changed: ['context', 'rateLimits', 'cost'] })
  await $.tool.call({ tool: 'Bash', command: 'npm test' })
  await $.command.run({ command: 'hud', args: '' })

  for (const surface of ['terminal', 'desktop'] as const) {
    const band = await $.ui.mount({ ...BAND, surface })
    expect(await band.find({ type: 'Text', text: /Opus 5\.5/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /25%/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /feature\/hud/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /Bash×1/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /not ready/ })).toBeDefined()
    expect(await band.find({ type: 'Text', text: /1 idle|1 working/ })).toBeDefined()
    await band.unmount()

    const pane = await $.ui.mount({ ...PANE, surface })
    expect(await pane.find({ type: 'Text', text: /docs-writer/ })).toBeDefined()
    expect(await pane.find({ type: 'Text', text: /Draft/ })).toBeDefined()
    await pane.unmount()
  }
})

test('the band yields when switched off', async ($, on) => {
  on('command.register', () => ({ value: { command: 'hud' } }))
  mock.store(on)
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine</Text>
  })
  await $.command.run({ command: 'hud', args: 'off' })
  const band = await $.ui.mount({ ...BAND, surface: 'terminal' })
  expect((await band.find({ type: 'Text' }))?.text).toBe('engine')
  await band.unmount()
})
