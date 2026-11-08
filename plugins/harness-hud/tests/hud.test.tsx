import { expect, mock, test } from 'claude-code/testing'

import { applyTaskResult, burn, clean, forecastLabel, pace, parseFleet, parseVerdict, todosFromWrite, toolLabel, turnsLeft } from '../hooks/hud'

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
  // Two growth samples, 10k and 20k: the median is 15k, so 60k of room is 4 turns.
  expect(turnsLeft([10_000, 20_000, 40_000], 40_000, 100_000)).toBe(4)
  expect(turnsLeft([10_000], 10_000, 130_000)).toBe(undefined)
  // No compaction point (auto-compaction off): the forecast speaks of a full window, never compaction.
  expect(turnsLeft([175_000, 185_000, 195_000], 195_000, 200_000)).toBe(0)
  expect(forecastLabel(0, false)).toBe('  context nearly full')
  expect(forecastLabel(3, false)).toBe('  ~3 turns to full')
  expect(forecastLabel(0, true)).toBe('  compacting soon')
  expect(forecastLabel(1, true)).toBe('  ~1 turn to compact')
  expect(turnsLeft([30_000, 20_000], 20_000, 130_000)).toBe(undefined)

  const hour = 3_600_000
  // 40% used with 1h of the 5h window gone: on pace for 200%.
  expect(pace({ kind: 'five_hour', percent: 40, resetsAt: 4 * hour }, 0)).toBe(200)
  expect(pace({ kind: 'spend_limit', percent: 40, resetsAt: hour }, 0)).toBe(undefined)
  // A reading that outlived its window says nothing about pace.
  expect(pace({ kind: 'five_hour', percent: 100, resetsAt: 10 * hour }, 11 * hour)).toBe(undefined)
  expect(pace({ kind: 'five_hour', percent: 100, resetsAt: 10 * hour }, 10 * hour)).toBe(undefined)

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
  const pending = [{ id: '1', content: 'Ship', status: 'pending' as const }]
  const ok = (to: string) => ({ success: true, taskId: '1', updatedFields: ['status'], statusChange: { from: 'pending', to } })
  const tasks = applyTaskResult(pending, ok('completed'))
  expect(tasks[0]?.status).toBe('completed')
  expect(applyTaskResult(tasks, ok('deleted'))).toEqual([])
  // A hook rewrote the request to in_progress: the result's own status wins.
  expect(applyTaskResult(pending, ok('in_progress'))[0]?.status).toBe('in_progress')
  // Refused, or reporting no status change: nothing moves.
  expect(applyTaskResult(pending, { success: false, taskId: '1', updatedFields: [], error: 'no' })[0]?.status).toBe('pending')
  expect(applyTaskResult(pending, { success: true, taskId: '1', updatedFields: ['subject'] })[0]?.status).toBe('pending')

  expect(toolLabel('Bash', { command: 'npm test\nmore' })).toBe('npm test')
  expect(toolLabel('Edit', { file_path: 'C:\\work\\src\\app.ts' })).toBe('app.ts')

  // Outside text loses escapes and bidi overrides before it is drawn.
  expect(clean('a\u001b[2Jb\u202ec\u0007')).toBe('a[2Jbc')
  expect(clean('ready\u061c-123')).toBe('ready-123')
  expect(clean('x'.repeat(300), 10)).toBe(`${'x'.repeat(9)}…`)
  expect(parseVerdict(JSON.stringify({ ready: true, summary: 'ok\u001b]0;title\u0007' }))?.summary).toBe('ok]0;title')
})

const ran = (stdout: string) => ({
  value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
})

const hud = (args: string) => ({
  command: 'hud',
  args,
  origin: { kind: 'composer' } as const,
  presentation: { isFullscreen: true, columns: 160 },
})

const BAND = {
  plugin: 'harness-hud',
  component: 'AbovePrompt',
  requestId: 'band',
  props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 160, scroll: { offset: 0, bodyRows: 10 }, view: {} },
} as const

const HINT = {
  plugin: 'harness-hud',
  component: 'PromptHint',
  requestId: 'hint',
  props: { isDraft: false, isWorking: false, hint: '? for shortcuts' },
  viewport: { columns: 160, rows: 40 },
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
      ? ran(PS)
      : e.argv.includes('branch')
        ? ran('feature/hud\n')
        : ran(' M a.ts\n'),
  )
  on('tool.call', () => ({ result: {} }))
  // Stands for the engine's own drawing of every site the mod passes on.
  on('ui.render', ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine line</Text>
  })

  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  await $.session.measure({ ...usage, changed: ['context', 'rateLimits', 'cost'] })
  await $.tool.call({ tool: 'Bash', command: 'npm test' })
  await $.command.run(hud(''))

  for (const surface of ['terminal', 'desktop'] as const) {
    // Below the prompt by default: the engine's hint line first, then the HUD.
    const hint = await $.ui.mount({ ...HINT, surface })
    expect(await hint.find({ type: 'Text', text: /engine line/ })).toBeDefined()
    expect(await hint.find({ type: 'Text', text: /25%/ })).toBeDefined()
    await hint.unmount()
    const empty = await $.ui.mount({ ...BAND, surface })
    expect(await empty.find({ type: 'Text', text: /25%/ })).toBe(undefined)
    await empty.unmount()
  }

  await $.command.run(hud('above'))
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
  await $.command.run(hud('off'))
  for (const site of [BAND, HINT]) {
    const drawn = await $.ui.mount({ ...site, surface: 'terminal' })
    expect((await drawn.find({ type: 'Text' }))?.text).toBe('engine')
    await drawn.unmount()
  }
})

test('burn is the engine total over the time since the session started', async () => {
  const hour = 3_600_000
  const meter = { model: '', window: 1, history: [], limits: [], startedAt: hour, usd: 5 }
  expect(burn(meter, 3 * hour)).toBe(2.5)
  expect(burn(meter, hour + 60_000)).toBe(undefined)
})

test('a rejected TaskUpdate leaves the todo; /clear and /resume start the lists over', async ($, on) => {
  mock.clock(on)
  mock.store(on)
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('agent.list', () => ({ value: [] }))
  on('session.usage', () => ({ value: { startedAt: 0, context: { window: 200_000 }, rateLimits: [], cost: { usd: 2 } } }))
  on('session.end', (_, e) => ({ sessionId: e.sessionId }))
  on('tool.call', (_, e) =>
    e.tool === 'TaskCreate'
      ? { result: { task: { id: '1', subject: 'Ship it' } } }
      : { result: { success: false, taskId: '1', updatedFields: [], error: 'update rejected' } },
  )

  await $.tool.call({ tool: 'TaskCreate', subject: 'Ship it', description: 'd' })
  await $.tool.call({ tool: 'TaskUpdate', taskId: '1', status: 'completed' })
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pane.find({ type: 'Text', text: /Todos {2}0\/1/ })).toBeDefined()
  await pane.unmount()

  for (const reason of ['clear', 'resume'] as const) {
    await $.tool.call({ tool: 'TaskCreate', subject: 'Ship it', description: 'd' })
    await $.session.end({ reason, sessionId: 's1', resume: { id: 's1' } })
    const cleared = await $.ui.mount({ ...PANE, surface: 'terminal' })
    expect(await cleared.find({ type: 'Text', text: /No tool calls yet/ })).toBeDefined()
    expect(await cleared.find({ type: 'Text', text: /Todos/ })).toBe(undefined)
    await cleared.unmount()
  }
})

test('burn follows the engine start, which /clear moves', async ($, on) => {
  const hour = 3_600_000
  const clock = mock.clock(on, { now: 2 * hour })
  mock.store(on)
  on('ui.open', () => ({ value: { isPlaced: true } }))
  // The engine's session started over at a /clear one hour in; its total is $6.
  on('session.usage', () => ({ value: { startedAt: hour, context: { window: 200_000 }, rateLimits: [], cost: { usd: 6 } } }))
  on('session.measure', (_, e) => ({ changed: e.changed }))

  await $.session.measure({ context: { window: 200_000 }, rateLimits: [], cost: { usd: 6 }, changed: ['cost'] })
  expect(clock.now()).toBe(2 * hour)
  const pane = await $.ui.mount({ ...PANE, surface: 'terminal' })
  expect(await pane.find({ type: 'Text', text: /\$6\.00\/h/ })).toBeDefined()
  await pane.unmount()
})
