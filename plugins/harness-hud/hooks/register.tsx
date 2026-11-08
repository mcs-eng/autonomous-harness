import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { AgentRow, ContextRow, HudMode, HudPlace, Meter, Repo, Todo, ToolRun } from '../types'
import {
  activePhase,
  applyTaskResult,
  bar,
  burn,
  clean,
  duration,
  fleetSummary,
  level,
  limitLabel,
  money,
  pace,
  parseFleet,
  parseVerdict,
  sparkline,
  todosFromWrite,
  tokens,
  toolLabel,
  toolName,
  toolStats,
  turnsLeft,
  forecastLabel,
} from './hud'

const PANE = 'harness-hud'

const mode = atom({ plugin: 'harness-hud', key: 'mode' } as const, 'full')
const place = atom({ plugin: 'harness-hud', key: 'place' } as const, 'below')
const now = atom({ plugin: 'harness-hud', key: 'now' } as const, 0)
const meter = atom({ plugin: 'harness-hud', key: 'meter' } as const, { model: '', window: 0, history: [], limits: [], startedAt: 0 }, { shape: 'meter-1' })
const tools = atom({ plugin: 'harness-hud', key: 'tools' } as const, [], { shape: 'tools-1' })
const agents = atom({ plugin: 'harness-hud', key: 'agents' } as const, [], { shape: 'agents-1' })
const todos = atom({ plugin: 'harness-hud', key: 'todos' } as const, [], { shape: 'todos-1' })
const repo = atom({ plugin: 'harness-hud', key: 'repo' } as const, { dirty: 0 }, { shape: 'repo-1' })
const harness = atom({ plugin: 'harness-hud', key: 'harness' } as const, {}, { shape: 'harness-1' })
const breakdown = atom({ plugin: 'harness-hud', key: 'breakdown' } as const, [], { shape: 'breakdown-1' })

type $ = EngineInterface

/** `claude-opus-5-5[1m]` as `Opus 5.5`; anything else as given. */
function prettyModel(id: string): string {
  const m = /claude-([a-z]+)-(\d+)(?:-(\d+))?/i.exec(id)
  if (!m || !m[1]) return id
  const family = m[1].charAt(0).toUpperCase() + m[1].slice(1)
  return `${family} ${m[2]}${m[3] && m[3].length <= 2 ? `.${m[3]}` : ''}${/\[1m\]/i.test(id) ? ' 1M' : ''}`
}

// Module state: lost on reload, which only costs a re-toast or one re-probe.
let toasted = { context: 0, limit: 0 }
let hasHarnessCli = true
let lastAgentPoll = 0

async function refreshRepo($: $) {
  try {
    const cwd = await $.session.cwd()
    // A repository's own config can name programs git runs (core.fsmonitor); turn those off so
    // opening a session in an untrusted checkout runs nothing of the checkout's choosing.
    const safe = ['git', '--no-optional-locks', '-c', 'core.fsmonitor=false', '-c', 'core.untrackedCache=false']
    const branch = await $.process.run([...safe, 'branch', '--show-current'], { cwd, timeoutMs: 4000 })
    if (branch.exitCode !== 0) {
      await update($, repo, () => ({ dirty: 0 }))
      return
    }
    const status = await $.process.run([...safe, 'status', '--porcelain'], { cwd, timeoutMs: 4000 })
    const dirty = status.exitCode === 0 ? status.stdout.split('\n').filter(l => l.trim()).length : 0
    const next: Repo = { branch: clean(branch.stdout.trim(), 60) || '(detached)', dirty }
    await update($, repo, () => next)
  } catch {
    // git missing: the HUD shows no branch.
  }
}

async function refreshVerdict($: $) {
  try {
    const workspace = (await $.env.get('HARNESS_WORKSPACE')) ?? (await $.session.cwd())
    const dsh = await $.env.get('HARNESS_DSH')
    const path = `${workspace}/.harness/verdict.json`
    const verdict = (await $.fs.exists(path)) ? parseVerdict(await $.fs.read(path)) : undefined
    await update($, harness, prev => ({ ...prev, dsh, verdict }))
  } catch {
    // An unreadable verdict is the same as none.
  }
}

async function refreshFleet($: $) {
  if (!hasHarnessCli) return
  try {
    const ps = await $.process.run(['harness', 'ps', '--json'], { timeoutMs: 10_000 })
    const fleet = ps.exitCode === 0 ? parseFleet(ps.stdout) : undefined
    await update($, harness, prev => ({ ...prev, fleet }))
  } catch {
    // No Harness CLI on this machine: stop asking until the next reload.
    hasHarnessCli = false
    await update($, harness, prev => ({ ...prev, fleet: undefined }))
  }
}

async function refreshAgents($: $) {
  try {
    const list = await $.agent.list()
    const rows: AgentRow[] = list.map(a => ({ id: a.id, description: clean(a.description, 120), type: clean(a.type, 60), status: a.status }))
    await update($, agents, () => rows)
  } catch {
    // Listing agents is best effort.
  }
}

async function refreshBreakdown($: $) {
  try {
    const usage = await $.session.usage({ breakdown: 'summary' })
    const b = usage.context.breakdown
    if (!b) return
    const buffer = b.categories.filter(c => c.kind === 'buffer').reduce((n, c) => n + c.tokens, 0)
    const compactAt = buffer > 0 ? b.rawMaxTokens - buffer : undefined
    const rows: ContextRow[] = b.categories
      .filter(c => c.kind === 'used' && c.tokens > 0)
      .sort((x, y) => y.tokens - x.tokens)
      .map(c => ({ name: c.name, tokens: c.tokens }))
    await update($, breakdown, () => rows)
    await update($, meter, m => ({ ...m, compactAt }))
  } catch {
    // The breakdown only sharpens the forecast.
  }
}

async function applyUsage($: $, usage: { context: { tokens?: number; window: number; percent?: number }; rateLimits: readonly { kind: string; percentUsed: number; resetsAt?: string }[]; cost?: { usd: number } }, isTurnEnd: boolean) {
  const t = usage.context.tokens
  await update($, meter, m => {
    let history = m.history
    if (isTurnEnd && t !== undefined) {
      const last = history[history.length - 1]
      // A drop of more than 40% is a compaction or /clear: the trend starts over.
      history = last !== undefined && t < last * 0.6 ? [t] : [...history, t].slice(-60)
    }
    const next: Meter = {
      ...m,
      tokens: t,
      window: usage.context.window,
      percent: usage.context.percent,
      history,
      limits: usage.rateLimits.map(r => ({ kind: r.kind, percent: r.percentUsed, resetsAt: r.resetsAt ? Date.parse(r.resetsAt) : undefined })),
      usd: usage.cost?.usd,
    }
    return next
  })
  const ctx = usage.context.percent ?? 0
  const ctxMark = ctx >= 90 ? 90 : ctx >= 80 ? 80 : 0
  if (ctxMark > toasted.context) $.ui.toast(`Context at ${ctx}%: consider /compact before the next big step.`)
  toasted.context = ctxMark
  const worst = usage.rateLimits.reduce((n, r) => Math.max(n, r.percentUsed), 0)
  const limitMark = worst >= 95 ? 95 : worst >= 80 ? 80 : 0
  if (limitMark > toasted.limit) {
    const r = usage.rateLimits.find(x => x.percentUsed === worst)
    $.ui.toast(`${limitLabel(r?.kind ?? '')} rate limit at ${worst}%.`)
  }
  toasted.limit = limitMark
}

/** The HUD's lines, for whichever site draws them. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function drawHud($: $, Box: any, Text: any, cols: number, isWorking: boolean, m: HudMode) {
      const t = Math.max(await read($, now), await $.clock.now())
  const me = await read($, meter)
  const r = await read($, repo)
  const hx = await read($, harness)

  const pct = me.percent
  const barWidth = cols >= 130 ? 12 : cols >= 100 ? 10 : 6
  const left = turnsLeft(me.history, me.tokens, me.compactAt ?? me.window)
  const rate = burn(me, t)

  const line1 = (
    <Text wrap="truncate-end">
      <Text color="claude" bold>{me.model || 'Claude'}</Text>
      <Text dimColor>  ctx </Text>
      <Text color={level(pct)}>{bar(pct ?? 0, barWidth)}</Text>
      <Text color={level(pct)} bold> {pct === undefined ? '--' : `${pct}%`}</Text>
      <Text dimColor> {tokens(me.tokens)}/{tokens(me.window)}</Text>
      {left !== undefined && (
        <Text color={left <= 3 ? 'warning' : 'subtle'}>{forecastLabel(left, me.compactAt !== undefined)}</Text>
      )}
      {me.limits.map(l => {
        const p = pace(l, t)
        const isHot = p !== undefined && p > 100
        return (
          <Text>
            <Text dimColor>  {limitLabel(l.kind)} </Text>
            <Text color={isHot ? 'warning' : level(l.percent)}>{Math.round(l.percent)}%</Text>
            {l.resetsAt !== undefined && <Text dimColor> ↺{duration(l.resetsAt - t)}</Text>}
            {isHot && <Text color="warning"> →{p}%</Text>}
          </Text>
        )
      })}
      {me.usd !== undefined && (
        <Text>
          <Text dimColor>  {me.limits.length > 0 ? 'api≈' : ''}</Text>
          <Text dimColor={me.limits.length > 0}>{money(me.usd)}</Text>
          {rate !== undefined && <Text dimColor> {money(rate)}/h</Text>}
        </Text>
      )}
      {r.branch !== undefined && (
        <Text>
          <Text dimColor>  ⎇ </Text>
          <Text color="suggestion">{r.branch}</Text>
          {r.dirty > 0 && <Text color="warning"> ±{r.dirty}</Text>}
        </Text>
      )}
    </Text>
  )

  if (m === 'compact') return <Box flexDirection="column">{line1}</Box>

  const runs = await read($, tools)
  const stats = toolStats(runs)
  const ag = await read($, agents)
  const td = await read($, todos)
  const live = ag.filter(a => a.status === 'running' || a.status === 'pending' || a.status === 'waiting')
  const doneTodos = td.filter(x => x.status === 'completed').length
  const current = td.find(x => x.status === 'in_progress')

  const line2 = (
    <Text wrap="truncate-end">
      {stats.running.length > 0 ? (
        stats.running.slice(0, 2).map((run, i) => (
          <Text>
            {i > 0 && <Text dimColor>, </Text>}
            <Text color="warning">▶ </Text>
            <Text bold>{toolName(run.tool)}</Text>
            {run.label !== '' && <Text dimColor> {run.label}</Text>}
            <Text color="subtle"> {duration(t - run.startedAt)}</Text>
          </Text>
        ))
      ) : (
        <Text dimColor>{isWorking ? '◇ thinking' : '◇ idle'}</Text>
      )}
      {stats.running.length > 2 && <Text dimColor> +{stats.running.length - 2}</Text>}
      <Text dimColor>  ✓ {stats.done} tools</Text>
      {stats.failed > 0 && <Text color="error"> ✗ {stats.failed}</Text>}
      {stats.counts.length > 0 && (
        <Text dimColor> ({stats.counts.slice(0, 3).map(([n, c]) => `${n}×${c}`).join(' ')})</Text>
      )}
      {live.length > 0 && (
        <Text>
          <Text dimColor>  agents </Text>
          <Text color="claude">{live.length}</Text>
          <Text dimColor>: {live.slice(0, 2).map(a => a.description || a.type).join(', ')}</Text>
        </Text>
      )}
      {td.length > 0 && (
        <Text>
          <Text dimColor>  todo </Text>
          <Text color={doneTodos === td.length ? 'success' : 'text'}>{doneTodos}/{td.length}</Text>
          {current && <Text dimColor> ▸ {current.active ?? current.content}</Text>}
        </Text>
      )}
    </Text>
  )

  const v = hx.verdict
  const phase = v ? activePhase(v) : undefined
  const hasHarnessLine = hx.dsh !== undefined || v !== undefined || (hx.fleet !== undefined && hx.fleet.siblings.length > 0)
  const line3 = hasHarnessLine && (
    <Text wrap="truncate-end">
      <Text color="merged" bold>Harness</Text>
      {hx.dsh !== undefined && <Text dimColor> {hx.dsh}</Text>}
      {v !== undefined && (
        <Text>
          <Text>  </Text>
          <Text color={v.ready ? 'success' : 'warning'}>{v.ready ? '● ready' : '○ not ready'}</Text>
          {phase && <Text dimColor> · {phase.name}</Text>}
          {v.errors > 0 && <Text color="error"> ✗{v.errors}</Text>}
          {v.warnings > 0 && <Text color="warning"> !{v.warnings}</Text>}
          {v.summary && <Text dimColor> · {v.summary}</Text>}
        </Text>
      )}
      {hx.fleet !== undefined && hx.fleet.siblings.length > 0 && (
        <Text dimColor>  fleet {fleetSummary(hx.fleet)}</Text>
      )}
    </Text>
  )

  return (
    <Box flexDirection="column">
      {line1}
      {line2}
      {line3}
    </Box>
  )
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const ran = await next(e)
    await $.command.register({
      name: 'hud',
      description: 'Harness HUD: open the detail pane, or set the band to full, compact or off',
      argumentHint: '[full|compact|off|below|above|close]',
    })
    const saved = await $.store.get('mode')
    if (saved === 'full' || saved === 'compact' || saved === 'off') await update($, mode, () => saved)
    const where = await $.store.get('place')
    if (where === 'below' || where === 'above') await update($, place, () => where)
    const usage = await $.session.usage()
    const model = prettyModel(await $.session.model())
    await update($, meter, m => ({ ...m, model, startedAt: usage.startedAt }))
    await applyUsage($, usage, false)
    await Promise.all([refreshRepo($), refreshVerdict($), refreshAgents($), refreshBreakdown($)])

    $.clock.every(1000, () => {
        void (async () => {
          const t = await $.clock.now()
          const runs = await read($, tools)
          const live = await read($, agents)
          const hasAgents = live.some(a => a.status === 'running' || a.status === 'pending')
          if (hasAgents && t - lastAgentPoll > 3000) {
            lastAgentPoll = t
            await refreshAgents($)
          }
          if (hasAgents || runs.some(r => r.endedAt === undefined)) await update($, now, () => t)
        })()
    })
    $.clock.every(30_000, () => void Promise.all([refreshFleet($), refreshVerdict($)]))
    $.clock.after(50, () => void refreshFleet($))
    return ran
  })

  // Timers are never cancelled here: a reload or the process's exit already ends them, and /clear or
  // /resume end a conversation with no session.start after it. Those two only empty the mod's own
  // lists, which belonged to the conversation that ended; usage figures stay the engine's.
  on('session.end', async ($, e, next) => {
    const ran = await next(e)
    if (e.reason === 'clear' || e.reason === 'resume') {
      await update($, meter, m => ({ ...m, history: [] }))
      await update($, tools, () => [])
      await update($, todos, () => [])
    }
    return ran
  }).catch(($, e, next) => next(e))

  on('command.run', { command: 'hud' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    if (arg === 'full' || arg === 'compact' || arg === 'off') {
      const value: HudMode = arg
      await update($, mode, () => value)
      await $.store.set('mode', value)
      return { text: `HUD band: ${value}.` }
    }
    if (arg === 'below' || arg === 'above') {
      const value: HudPlace = arg
      await update($, place, () => value)
      await $.store.set('place', value)
      return { text: `HUD drawn ${value} the prompt.` }
    }
    if (arg === 'close') {
      await $.ui.close({ id: PANE })
      return { text: 'HUD pane closed.' }
    }
    await Promise.all([refreshBreakdown($), refreshFleet($), refreshVerdict($), refreshAgents($)])
    await $.ui.open({ id: PANE, title: 'HUD' })
    return { text: 'HUD pane opened. /hud full|compact|off sets the band, /hud below|above moves it, /hud close closes the pane.' }
  })

  on('session.measure', async ($, e, next) => {
    const ran = await next(e)
    await applyUsage($, e, e.changed.includes('context'))
    // The engine's own start, read fresh each time: /clear starts it over, and the call is free.
    const { startedAt } = await $.session.usage()
    await update($, meter, m => (m.startedAt === startedAt ? m : { ...m, startedAt }))
    if (e.changed.includes('context')) await refreshBreakdown($)
    return ran
  })

  on('session.compact', async ($, e, next) => {
    const ran = await next(e)
    await update($, meter, m => ({ ...m, history: [] }))
    return ran
  }).catch(($, e, next) => next(e))

  on('tool.call', async ($, e, next) => {
    const tool = String(e.tool)
    const run: ToolRun = {
      id: e.tool_use_id,
      tool,
      label: toolLabel(tool, e),
      startedAt: await $.clock.now(),
      isSubagent: e.agentId !== undefined,
    }
    await update($, tools, list => [...list, run].slice(-200))
    await update($, now, () => run.startedAt)

    const ran = await next(e)

    const endedAt = await $.clock.now()
    const isError = ran.deny !== undefined || ran.isError === true
    await update($, tools, list => list.map(r => (r.id === run.id ? { ...r, endedAt, isError } : r)))

    if (!isError) {
      if (tool === 'TodoWrite') {
        const list = todosFromWrite(ran.result)
        if (list) await update($, todos, () => list)
      } else if (tool === 'TaskCreate') {
        const task = (ran.result as { task?: { id?: unknown; subject?: unknown } } | undefined)?.task
        if (typeof task?.id === 'string' && typeof task.subject === 'string') {
          const todo: Todo = { id: task.id, content: clean(task.subject), status: 'pending' }
          await update($, todos, list => [...list.filter(t => t.id !== todo.id), todo])
        }
      } else if (tool === 'TaskUpdate') {
        // Only what the result says happened: a rejected or rewritten update reports its own outcome.
        await update($, todos, list => applyTaskResult(list, ran.result))
      } else if (tool === 'Agent' || tool === 'Task') {
        await refreshAgents($)
      }
      if (tool === 'Write' || tool === 'Edit' || tool === 'NotebookEdit') await refreshVerdict($)
    }
    return ran
  }).catch(($, e, next) => next(e))

  on('agent.spawn', async ($, e, next) => {
    const ran = await next(e)
    await refreshAgents($)
    return ran
  }).catch(($, e, next) => next(e))

  on('turn.complete', async ($, e, next) => {
    const ran = await next(e)
    if (e.agentId !== undefined) {
      await refreshAgents($)
    } else {
      $.clock.after(10, () => void Promise.all([refreshRepo($), refreshVerdict($), refreshFleet($), refreshAgents($)]))
    }
    return ran
  })

  // ---- drawing ------------------------------------------------------------

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const m = await read($, mode)
    if (m === 'off' || e.props.hasSurvey || (await read($, place)) !== 'above') return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return drawHud($, Box, Text, e.props.bodyColumns, e.props.isWorking, m)
  })

  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    const m = await read($, mode)
    if (m === 'off' || (await read($, place)) !== 'below') return next(e)
    const { Box, Text } = $.ui.resolve(e)
    const hint = await next(e)
    const cols = e.viewport?.columns ?? 120
    const hud = await drawHud($, Box, Text, cols, e.props.isWorking, m)
    return (
      <Box flexDirection="column">
        {hint}
        {hud}
      </Box>
    )
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const cols = e.props.bodyColumns
    const t = Math.max(await read($, now), await $.clock.now())
    const me = await read($, meter)
    const rows = await read($, breakdown)
    const runs = await read($, tools)
    const ag = await read($, agents)
    const td = await read($, todos)
    const r = await read($, repo)
    const hx = await read($, harness)
    const stats = toolStats(runs)
    const barWidth = Math.max(10, Math.min(40, cols - 14))
    const left = turnsLeft(me.history, me.tokens, me.compactAt ?? me.window)
    const rate = burn(me, t)
    const heading = (s: string) => <Text color="claude" bold>{s}</Text>

    return (
      <Box flexDirection="column">
        {heading('Context')}
        <Text>
          <Text color={level(me.percent)}>{bar(me.percent ?? 0, barWidth)}</Text>
          <Text bold> {me.percent ?? '--'}%</Text>
        </Text>
        <Text dimColor wrap="truncate-end">
          {tokens(me.tokens)} of {tokens(me.window)}
          {me.compactAt !== undefined ? ` · compacts at ${tokens(me.compactAt)}` : ''}
          {left !== undefined ? ` ·${forecastLabel(left, me.compactAt !== undefined).slice(1)}` : ''}
        </Text>
        {me.history.length > 1 && (
          <Text>
            <Text color="subtle">{sparkline(me.history, Math.max(8, cols - 12), me.window)}</Text>
            <Text dimColor> per turn</Text>
          </Text>
        )}
        {rows.slice(0, 6).map(row => (
          <Text wrap="truncate-end">
            <Text dimColor>  {row.name}</Text>
            <Text> {tokens(row.tokens)}</Text>
          </Text>
        ))}

        <Text> </Text>
        {heading('Limits and cost')}
        {me.limits.length === 0 && <Text dimColor>No rate-limit reading yet.</Text>}
        {me.limits.map(l => {
          const p = pace(l, t)
          return (
            <Text wrap="truncate-end">
              <Text>{limitLabel(l.kind).padEnd(6)}</Text>
              <Text color={level(l.percent)}>{bar(l.percent, 10)} {Math.round(l.percent)}%</Text>
              {l.resetsAt !== undefined && <Text dimColor> resets in {duration(l.resetsAt - t)}</Text>}
              {p !== undefined && <Text color={p > 100 ? 'warning' : 'subtle'}> · pace {p}%</Text>}
            </Text>
          )
        })}
        <Text dimColor>
          {me.usd !== undefined ? `${money(me.usd)} this session` : 'No cost ledger'}
          {rate !== undefined ? ` · ${money(rate)}/h` : ''}
          {me.startedAt > 0 ? ` · ${duration(t - me.startedAt)} elapsed` : ''}
        </Text>

        <Text> </Text>
        {heading(`Tools  ${stats.done} done${stats.failed ? `, ${stats.failed} failed` : ''}`)}
        {runs.length === 0 && <Text dimColor>No tool calls yet.</Text>}
        {runs.slice(-8).reverse().map(run => (
          <Text wrap="truncate-end">
            <Text color={run.endedAt === undefined ? 'warning' : run.isError ? 'error' : 'success'}>
              {run.endedAt === undefined ? '▶' : run.isError ? '✗' : '✓'}
            </Text>
            <Text> {toolName(run.tool)}</Text>
            {run.isSubagent && <Text color="claude"> (agent)</Text>}
            <Text dimColor> {run.label}</Text>
            <Text color="subtle"> {duration((run.endedAt ?? t) - run.startedAt)}</Text>
          </Text>
        ))}

        {ag.length > 0 && <Text> </Text>}
        {ag.length > 0 && heading('Agents')}
        {ag.map(a => (
          <Button key={`agent-${a.id}`} plain onPress={() => void $.ui.view({ agentId: a.id })}>
            <Text color={a.status === 'running' ? 'claude' : a.status === 'failed' ? 'error' : 'subtle'}>{a.status.padEnd(9)}</Text>
            {a.description || a.type}
            <Text dimColor> {a.type}</Text>
          </Button>
        ))}

        {td.length > 0 && <Text> </Text>}
        {td.length > 0 && heading(`Todos  ${td.filter(x => x.status === 'completed').length}/${td.length}`)}
        {td.map(x => (
          <Text wrap="truncate-end" dimColor={x.status === 'completed'}>
            <Text color={x.status === 'completed' ? 'success' : x.status === 'in_progress' ? 'warning' : 'subtle'}>
              {x.status === 'completed' ? '✓' : x.status === 'in_progress' ? '▸' : '·'}
            </Text>
            <Text> {x.content}</Text>
          </Text>
        ))}

        <Text> </Text>
        {heading('Workspace')}
        <Text wrap="truncate-end">
          <Text dimColor>branch </Text>
          <Text color="suggestion">{r.branch ?? 'not a git repository'}</Text>
          {r.dirty > 0 && <Text color="warning"> · {r.dirty} changed</Text>}
        </Text>
        {hx.dsh !== undefined && <Text dimColor>harness package {hx.dsh}</Text>}
        {hx.verdict !== undefined && (
          <Text>
            <Text color={hx.verdict.ready ? 'success' : 'warning'}>{hx.verdict.ready ? '● ready' : '○ not ready'}</Text>
            {hx.verdict.summary && <Text dimColor> {hx.verdict.summary}</Text>}
          </Text>
        )}
        {hx.verdict !== undefined && hx.verdict.phases.length > 0 && (
          <Text wrap="wrap">
            {hx.verdict.phases.map((p, i) => (
              <Text>
                {i > 0 && <Text dimColor> › </Text>}
                <Text color={p.state === 'done' ? 'success' : p.state === 'active' ? 'warning' : 'subtle'} bold={p.state === 'active'}>
                  {p.name}
                </Text>
              </Text>
            ))}
          </Text>
        )}
        {hx.fleet !== undefined && (
          <Text dimColor>
            {hx.fleet.siblings.length} other harness{hx.fleet.siblings.length === 1 ? '' : 'es'} here · yours open {hx.fleet.open}/{hx.fleet.maxOpen}
            {hx.fleet.canStart ? '' : ' · agents may not start agents'}
          </Text>
        )}
        {hx.fleet?.siblings.slice(0, 8).map(s => (
          <Text wrap="truncate-end">
            <Text color={s.state === 'working' ? 'claude' : s.state === 'idle' ? 'success' : 'subtle'}>{s.state.padEnd(8)}</Text>
            <Text> {s.name}</Text>
            <Text dimColor> {s.agent}{s.mine ? ' · yours' : ''}</Text>
          </Text>
        ))}
      </Box>
    )
  })
}
