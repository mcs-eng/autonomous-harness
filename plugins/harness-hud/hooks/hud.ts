// Pure helpers: formatting, forecasting and parsing. No `$`, so tests call them directly.
import type { Fleet, Limit, Meter, Phase, Todo, ToolRun, Verdict } from '../types'

const HOUR = 3_600_000
const WINDOW_MS: Record<string, number> = { five_hour: 5 * HOUR, seven_day: 7 * 24 * HOUR }
const LIMIT_LABEL: Record<string, string> = { five_hour: '5h', seven_day: '7d', spend_limit: 'spend' }

export function tokens(n: number | undefined): string {
  if (n === undefined) return '?'
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n >= 10_000_000 ? 0 : 1)}M`
  if (n >= 1000) return `${Math.round(n / 1000)}k`
  return String(n)
}

export function duration(ms: number): string {
  const s = Math.max(0, Math.round(ms / 1000))
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m${s % 60 ? `${String(s % 60).padStart(2, '0')}s` : ''}`
  const h = Math.floor(m / 60)
  if (h < 48) return `${h}h${m % 60 ? `${String(m % 60).padStart(2, '0')}m` : ''}`
  return `${Math.floor(h / 24)}d${h % 24 ? `${h % 24}h` : ''}`
}

export function money(usd: number | undefined): string {
  if (usd === undefined) return ''
  return usd < 10 ? `$${usd.toFixed(2)}` : `$${usd.toFixed(1)}`
}

/** A bar of `width` cells, filled to `percent`. */
export function bar(percent: number, width: number): string {
  const cells = Math.max(1, width)
  const filled = Math.min(cells, Math.round((Math.max(0, percent) / 100) * cells))
  return '█'.repeat(filled) + '░'.repeat(cells - filled)
}

const SPARKS = '▁▂▃▄▅▆▇█'

/** A sparkline of the last `width` values, scaled to `max` (or their own peak). */
export function sparkline(values: readonly number[], width: number, max?: number): string {
  const tail = values.slice(-Math.max(1, width))
  if (tail.length === 0) return ''
  const top = max ?? Math.max(...tail, 1)
  return tail
    .map(v => SPARKS[Math.min(SPARKS.length - 1, Math.max(0, Math.round((v / top) * (SPARKS.length - 1))))])
    .join('')
}

/** Severity of a fill: what colour a meter is drawn in. */
export function level(percent: number | undefined): 'success' | 'warning' | 'error' | 'subtle' {
  if (percent === undefined) return 'subtle'
  if (percent >= 85) return 'error'
  if (percent >= 65) return 'warning'
  return 'success'
}

/**
 * Turns left before the context reaches `limit`, from the median growth of the
 * last few turns. Undefined when there is not enough history or no growth.
 */
export function turnsLeft(history: readonly number[], current: number | undefined, limit: number | undefined): number | undefined {
  if (current === undefined || limit === undefined || history.length < 2) return undefined
  const deltas: number[] = []
  for (let i = Math.max(1, history.length - 6); i < history.length; i++) {
    const d = (history[i] ?? 0) - (history[i - 1] ?? 0)
    if (d > 0) deltas.push(d)
  }
  if (deltas.length === 0) return undefined
  deltas.sort((a, b) => a - b)
  const mid = Math.floor(deltas.length / 2)
  const median = deltas.length % 2 === 1 ? (deltas[mid] ?? 0) : ((deltas[mid - 1] ?? 0) + (deltas[mid] ?? 0)) / 2
  if (median <= 0) return undefined
  return Math.max(0, Math.floor((limit - current) / median))
}

/**
 * Where a rate-limit window will land at its reset if use keeps its pace so far.
 * Undefined for windows of unknown length or too early in the window to say.
 */
export function pace(limit: Limit, now: number): number | undefined {
  const length = WINDOW_MS[limit.kind]
  if (length === undefined || limit.resetsAt === undefined) return undefined
  const elapsed = length - (limit.resetsAt - now)
  if (elapsed < length * 0.1 || elapsed <= 0) return undefined
  return Math.round((limit.percent / elapsed) * length)
}

export function limitLabel(kind: string): string {
  return LIMIT_LABEL[kind] ?? kind
}

/** Dollars per hour since the session started; undefined in its first minutes. */
/**
 * What this session has spent since it started or was last cleared. The engine's total may or may
 * not start over at /clear, so a total below the baseline taken there is read as already reset.
 */
export function spent(meter: Meter): number | undefined {
  if (meter.usd === undefined) return undefined
  const base = meter.usdBase ?? 0
  return meter.usd >= base ? meter.usd - base : meter.usd
}

export function burn(meter: Meter, now: number): number | undefined {
  const hours = (now - meter.startedAt) / HOUR
  const usd = spent(meter)
  if (usd === undefined || hours < 0.05) return undefined
  return usd / hours
}

// C0 and C1 controls (ESC among them) and every bidi control (the Arabic letter mark, the LRM/RLM
// marks, the embeddings, overrides and isolates), which could restyle or reorder the terminal.
const UNSAFE = /[\u0000-\u0008\u000b-\u001f\u007f-\u009f\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]/g

/** Text from outside the mod (files, tools, other programs), safe to draw: no control characters, capped. */
export function clean(text: string, max = 200): string {
  const plain = text.replace(UNSAFE, '').replace(/[\t\n\r]+/g, ' ')
  return plain.length > max ? `${plain.slice(0, max - 1)}…` : plain
}

function field(input: unknown, key: string): string | undefined {
  if (typeof input !== 'object' || input === null) return undefined
  const value = (input as Record<string, unknown>)[key]
  return typeof value === 'string' ? clean(value, 1000) : undefined
}

function basename(path: string): string {
  const parts = path.split(/[\\/]/)
  return parts[parts.length - 1] || path
}

function raw(input: unknown, key: string): string | undefined {
  if (typeof input !== 'object' || input === null) return undefined
  const value = (input as Record<string, unknown>)[key]
  return typeof value === 'string' ? value : undefined
}

/** A few words saying what a tool call is doing. */
export function toolLabel(tool: string, input: unknown): string {
  const file = field(input, 'file_path') ?? field(input, 'notebook_path') ?? field(input, 'path')
  const short = (s: string, n: number) => (s.length > n ? `${s.slice(0, n - 1)}…` : s)
  switch (tool) {
    case 'Bash':
    case 'PowerShell':
      return short(clean((raw(input, 'command') ?? '').split('\n')[0] ?? ''), 36)
    case 'Read':
    case 'Write':
    case 'Edit':
    case 'NotebookEdit':
      return file ? basename(file) : ''
    case 'Grep':
    case 'Glob':
      return short(field(input, 'pattern') ?? '', 28)
    case 'Agent':
    case 'Task':
      return short(field(input, 'description') ?? '', 32)
    case 'WebFetch':
      return short(field(input, 'url') ?? '', 36)
    case 'WebSearch':
      return short(field(input, 'query') ?? '', 32)
    case 'Skill':
      return field(input, 'skill') ?? ''
    default:
      return tool.startsWith('mcp__') ? '' : file ? basename(file) : ''
  }
}

/** `mcp__server__tool` as `server:tool`; built-ins as they are. */
export function toolName(tool: string): string {
  const m = /^mcp__(.+?)__(.+)$/.exec(tool)
  return m ? `${m[1]}:${m[2]}` : tool
}

export type ToolStats = { done: number; failed: number; running: ToolRun[]; counts: [string, number][] }

export function toolStats(runs: readonly ToolRun[]): ToolStats {
  const counts = new Map<string, number>()
  let done = 0
  let failed = 0
  const running: ToolRun[] = []
  for (const run of runs) {
    if (run.endedAt === undefined) {
      running.push(run)
      continue
    }
    done += 1
    if (run.isError) failed += 1
    const name = toolName(run.tool)
    counts.set(name, (counts.get(name) ?? 0) + 1)
  }
  return { done, failed, running, counts: [...counts].sort((a, b) => b[1] - a[1]) }
}

/** The list a TodoWrite result leaves. */
export function todosFromWrite(result: unknown): Todo[] | undefined {
  if (typeof result !== 'object' || result === null) return undefined
  const list = (result as { newTodos?: unknown }).newTodos
  if (!Array.isArray(list)) return undefined
  return list.flatMap((item, i) => {
    const content = field(item, 'content')
    const status = field(item, 'status')
    if (!content || (status !== 'pending' && status !== 'in_progress' && status !== 'completed')) return []
    return [{ id: `w${i}`, content, active: field(item, 'activeForm'), status }]
  })
}

export function applyTaskUpdate(list: readonly Todo[], input: unknown): Todo[] {
  const id = field(input, 'taskId')
  if (!id) return [...list]
  const status = field(input, 'status')
  if (status === 'deleted') return list.filter(t => t.id !== id)
  return list.map(t => {
    if (t.id !== id) return t
    const next: Todo = { ...t }
    const subject = field(input, 'subject')
    const active = field(input, 'activeForm')
    if (subject) next.content = subject
    if (active) next.active = active
    if (status === 'pending' || status === 'in_progress' || status === 'completed') next.status = status
    return next
  })
}

export function parseVerdict(text: string): Verdict | undefined {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return undefined
  }
  if (typeof raw !== 'object' || raw === null) return undefined
  const v = raw as { ready?: unknown; summary?: unknown; phases?: unknown; findings?: unknown }
  const phases: Phase[] = Array.isArray(v.phases)
    ? v.phases.flatMap(p => {
        const id = field(p, 'id')
        const name = field(p, 'name') ?? id
        const state = field(p, 'state') ?? 'pending'
        return id && name ? [{ id, name, state }] : []
      })
    : []
  const findings = Array.isArray(v.findings) ? v.findings : []
  return {
    ready: v.ready === true,
    summary: typeof v.summary === 'string' ? clean(v.summary) : undefined,
    phases,
    errors: findings.filter(f => field(f, 'severity') === 'error').length,
    warnings: findings.filter(f => field(f, 'severity') === 'warning').length,
  }
}

export function activePhase(verdict: Verdict): Phase | undefined {
  return verdict.phases.find(p => p.state === 'active') ?? verdict.phases.find(p => p.state !== 'done')
}

/** `harness ps --json`, reduced to what the HUD shows. */
export function parseFleet(text: string): Fleet | undefined {
  let raw: unknown
  try {
    raw = JSON.parse(text)
  } catch {
    return undefined
  }
  if (typeof raw !== 'object' || raw === null) return undefined
  const ps = raw as {
    context?: { canStart?: { ok?: unknown }; quota?: { open?: unknown; maxOpen?: unknown } }
    harnesses?: unknown
  }
  if (!Array.isArray(ps.harnesses)) return undefined
  let self: string | undefined
  const siblings = ps.harnesses.flatMap(h => {
    const name = field(h, 'name') ?? '?'
    if ((h as { self?: unknown }).self === true) {
      self = name
      return []
    }
    return [{ name, agent: field(h, 'agent') ?? '', state: field(h, 'state') ?? 'unknown', mine: (h as { yours?: unknown }).yours === true }]
  })
  const num = (v: unknown) => (typeof v === 'number' ? v : 0)
  return {
    self,
    siblings,
    open: num(ps.context?.quota?.open),
    maxOpen: num(ps.context?.quota?.maxOpen),
    canStart: ps.context?.canStart?.ok === true,
  }
}

export function fleetSummary(fleet: Fleet): string {
  const by = new Map<string, number>()
  for (const s of fleet.siblings) by.set(s.state, (by.get(s.state) ?? 0) + 1)
  const parts = [...by].sort((a, b) => b[1] - a[1]).map(([state, n]) => `${n} ${state}`)
  return parts.length ? parts.join(', ') : 'alone'
}
