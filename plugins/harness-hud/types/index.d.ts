export type HudMode = 'full' | 'compact' | 'off'

export type HudPlace = 'below' | 'above'

export type Limit = { kind: string; percent: number; resetsAt?: number }

export type Meter = {
  model: string
  tokens?: number
  window: number
  percent?: number
  /** Where auto-compaction starts, in tokens, from the local context breakdown. */
  compactAt?: number
  /** Context tokens at the end of each main turn, oldest first. */
  history: number[]
  limits: Limit[]
  usd?: number
  startedAt: number
}

export type ToolRun = {
  id: string
  tool: string
  label: string
  startedAt: number
  endedAt?: number
  isError?: boolean
  isSubagent?: boolean
}

export type AgentRow = { id: string; description: string; type: string; status: string }

export type Todo = { id: string; content: string; active?: string; status: 'pending' | 'in_progress' | 'completed' }

export type Repo = { branch?: string; dirty: number }

export type Phase = { id: string; name: string; state: string }

export type Verdict = {
  ready: boolean
  summary?: string
  phases: Phase[]
  errors: number
  warnings: number
}

export type Sibling = { name: string; agent: string; state: string; mine: boolean }

export type Fleet = {
  self?: string
  siblings: Sibling[]
  open: number
  maxOpen: number
  canStart: boolean
}

export type HarnessInfo = { dsh?: string; verdict?: Verdict; fleet?: Fleet }

export type ContextRow = { name: string; tokens: number }

declare module 'claude-code' {
  interface PluginState {
    'harness-hud': {
      mode: HudMode
      place: HudPlace
      now: number
      meter: Shaped<Meter>
      tools: Shaped<ToolRun[]>
      agents: Shaped<AgentRow[]>
      todos: Shaped<Todo[]>
      repo: Shaped<Repo>
      harness: Shaped<HarnessInfo>
      breakdown: Shaped<ContextRow[]>
    }
  }
}
