/**
 * A bounded TypeSafe Jev Choice call for the task palette.
 * Schema: https://docs.typesafe.ai/api and https://docs.typesafe.ai/primitives/choice
 */

export interface JevRouteCandidate {
  id: string
  name: string
  engine?: string
}

export interface JevRouteResult {
  agentId: string
  confidence: number
  scores: Array<{ agentId: string; confidence: number }>
}

interface JevOptions {
  apiKey: string
  timeoutMs?: number
  fetchImpl?: typeof fetch
}

const JEV_URL = 'https://api.typesafe.ai/v1/systemone'
const DEFAULT_TIMEOUT_MS = 8_000

/**
 * Asks Jev to rank the offered agents for one task, and resolves null whenever
 * it cannot answer — no key, one or zero candidates, any non-2xx, malformed,
 * or non-probabilistic response, or the timeout. Null is the caller's signal to
 * fall through to the standard ranking, which sees the same candidates with
 * more signal than any local stand-in could; there is deliberately no local
 * fallback in here to maintain.
 *
 * Sends only the task and minimal candidate descriptions. Opaque option keys
 * are mapped back locally; no Harness agent id, transcript, path, history,
 * machine name, or credential appears in the body.
 */
export async function routeTaskWithJev(
  task: string,
  candidates: JevRouteCandidate[],
  options: JevOptions,
): Promise<JevRouteResult | null> {
  if (candidates.length <= 1 || !options.apiKey.trim()) return null

  const byOption = new Map<string, JevRouteCandidate>()
  const criteria: Record<string, string> = {}
  candidates.forEach((candidate, index) => {
    const option = `agent_${index + 1}`
    byOption.set(option, candidate)
    criteria[option] = candidate.engine
      ? `${candidate.name} — ${candidate.engine}`
      : candidate.name
  })

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), options.timeoutMs ?? DEFAULT_TIMEOUT_MS)
  try {
    const response = await (options.fetchImpl ?? fetch)(JEV_URL, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${options.apiKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        state: { task },
        model: 'jev-latest',
        questions: {
          agent: {
            type: 'choice',
            instructions: 'Which available agent is best suited to handle this task?',
            criteria,
          },
        },
      }),
      signal: controller.signal,
    })
    if (!response.ok) return null
    const body = await response.json() as Record<string, unknown>
    const answers = body.answers
    const answer = answers && typeof answers === 'object'
      ? (answers as Record<string, unknown>).agent
      : null
    if (!answer || typeof answer !== 'object') return null
    const value = answer as Record<string, unknown>
    const picked = typeof value.choice === 'string' ? byOption.get(value.choice) : undefined
    const probabilities = value.probabilities
    if (!picked || !probabilities || typeof probabilities !== 'object') return null

    let malformed = false
    const scores = [...byOption.entries()].map(([option, candidate]) => {
      const raw = (probabilities as Record<string, unknown>)[option]
      if (typeof raw !== 'number' || !Number.isFinite(raw) || raw < 0 || raw > 1) malformed = true
      const probability = typeof raw === 'number' ? raw : 0
      return { agentId: candidate.id, confidence: probability }
    }).sort((a, b) => b.confidence - a.confidence)
    const total = scores.reduce((sum, entry) => sum + entry.confidence, 0)
    if (malformed || Math.abs(total - 1) > 0.01) return null
    const winner = scores.find((entry) => entry.agentId === picked.id)
    if (!winner || winner.confidence <= 0) return null
    return {
      agentId: picked.id,
      confidence: winner.confidence,
      scores: scores.filter((entry) => entry.agentId !== picked.id),
    }
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}
