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
  via: 'jev' | 'jev-fallback'
}

interface JevOptions {
  apiKey: string
  timeoutMs?: number
  fetchImpl?: typeof fetch
}

const JEV_URL = 'https://api.typesafe.ai/v1/systemone'
const DEFAULT_TIMEOUT_MS = 8_000

const words = (value: string): string[] => value
  .normalize('NFD')
  .replace(/[\u0300-\u036f]/g, '')
  .toLowerCase()
  .split(/[^a-z0-9]+/)
  .filter((word) => word.length > 1)

/** Failure stays local: rank only the offered name and engine metadata for manual confirmation. */
export function localJevFallback(task: string, candidates: JevRouteCandidate[]): JevRouteResult {
  const taskWords = new Set(words(task))
  const ranked = candidates.map((candidate, index) => ({
    candidate,
    index,
    hits: words(`${candidate.name} ${candidate.engine ?? ''}`).filter((word) => taskWords.has(word)).length,
  })).sort((a, b) => b.hits - a.hits || a.index - b.index)
  const bestHits = ranked[0]?.hits ?? 0
  const confidence = bestHits > 0 ? 0.4 : 0.2
  return {
    agentId: ranked[0]?.candidate.id ?? '',
    confidence,
    scores: ranked.slice(1).map((entry) => ({
      agentId: entry.candidate.id,
      confidence: bestHits > 0 ? Math.min(0.35, entry.hits / bestHits * confidence) : 0.1,
    })),
    via: 'jev-fallback',
  }
}

/**
 * Sends only the task and minimal candidate descriptions. Opaque option keys are mapped back locally;
 * no Harness agent id, transcript, path, history, machine name, or credential appears in the body.
 */
export async function routeTaskWithJev(
  task: string,
  candidates: JevRouteCandidate[],
  options: JevOptions,
): Promise<JevRouteResult> {
  if (candidates.length <= 1 || !options.apiKey.trim()) return localJevFallback(task, candidates)

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
    if (!response.ok) return localJevFallback(task, candidates)
    const body = await response.json() as Record<string, unknown>
    const answers = body.answers
    const answer = answers && typeof answers === 'object'
      ? (answers as Record<string, unknown>).agent
      : null
    if (!answer || typeof answer !== 'object') return localJevFallback(task, candidates)
    const value = answer as Record<string, unknown>
    const picked = typeof value.choice === 'string' ? byOption.get(value.choice) : undefined
    const probabilities = value.probabilities
    if (!picked || !probabilities || typeof probabilities !== 'object') {
      return localJevFallback(task, candidates)
    }

    let malformed = false
    const scores = [...byOption.entries()].map(([option, candidate]) => {
      const raw = (probabilities as Record<string, unknown>)[option]
      if (typeof raw !== 'number' || !Number.isFinite(raw) || raw < 0 || raw > 1) malformed = true
      const probability = typeof raw === 'number' ? raw : 0
      return { agentId: candidate.id, confidence: probability }
    }).sort((a, b) => b.confidence - a.confidence)
    const total = scores.reduce((sum, entry) => sum + entry.confidence, 0)
    if (malformed || Math.abs(total - 1) > 0.01) return localJevFallback(task, candidates)
    const winner = scores.find((entry) => entry.agentId === picked.id)
    if (!winner || winner.confidence <= 0) return localJevFallback(task, candidates)
    return {
      agentId: picked.id,
      confidence: winner.confidence,
      scores: scores.filter((entry) => entry.agentId !== picked.id),
      via: 'jev',
    }
  } catch {
    return localJevFallback(task, candidates)
  } finally {
    clearTimeout(timer)
  }
}
