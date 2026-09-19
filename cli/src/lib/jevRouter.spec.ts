import { describe, expect, it, vi } from 'vitest'
import { routeTaskWithJev } from './jevRouter.js'

const candidates = [
  { id: 'private-a', name: 'Frontend', engine: 'claude' },
  { id: 'private-b', name: 'Database', engine: 'codex' },
]

describe('Jev task router', () => {
  it('sends only task and minimal descriptions and maps opaque options back locally', async () => {
    const fetchImpl = vi.fn(async (_url: string | URL | Request, init?: RequestInit) => {
      const request = JSON.parse(String(init?.body))
      expect(request).toEqual({
        state: { task: 'fix the schema migration' },
        model: 'jev-latest',
        questions: { agent: {
          type: 'choice',
          instructions: 'Which available agent is best suited to handle this task?',
          criteria: { agent_1: 'Frontend — claude', agent_2: 'Database — codex' },
        } },
      })
      expect(String(init?.body)).not.toContain('private-a')
      expect((init?.headers as Record<string, string>).authorization).toBe('Bearer secret')
      return new Response(JSON.stringify({
        answers: { agent: { type: 'choice', choice: 'agent_2', probabilities: { agent_1: 0.08, agent_2: 0.92 }, confidence: 0.84 } },
      }))
    }) as typeof fetch

    await expect(routeTaskWithJev('fix the schema migration', candidates, { apiKey: 'secret', fetchImpl }))
      .resolves.toEqual({
        agentId: 'private-b', confidence: 0.92,
        scores: [{ agentId: 'private-a', confidence: 0.08 }],
      })
  })

  it('resolves null for a malformed or unknown choice so the caller falls through', async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({
      answers: { agent: { choice: 'private-b', probabilities: { 'private-b': 1 } } },
    }))) as typeof fetch
    await expect(routeTaskWithJev('database schema', candidates, { apiKey: 'secret', fetchImpl }))
      .resolves.toBeNull()
  })

  it('resolves null for out-of-range probabilities instead of clamping', async () => {
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify({
      answers: { agent: { choice: 'agent_2', probabilities: { agent_1: -0.2, agent_2: 1.2 } } },
    }))) as typeof fetch
    await expect(routeTaskWithJev('database schema', candidates, { apiKey: 'secret', fetchImpl }))
      .resolves.toBeNull()
  })

  it('bounds a hung request and resolves null', async () => {
    const fetchImpl = vi.fn((_url: string | URL | Request, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(new Error('aborted')))
    })) as typeof fetch
    await expect(routeTaskWithJev('frontend', candidates, { apiKey: 'secret', fetchImpl, timeoutMs: 5 }))
      .resolves.toBeNull()
  })

  it('defers to the standard ranking without a key or with one candidate', async () => {
    const fetchImpl = vi.fn() as unknown as typeof fetch
    await expect(routeTaskWithJev('frontend', candidates, { apiKey: '   ', fetchImpl }))
      .resolves.toBeNull()
    await expect(routeTaskWithJev('frontend', [candidates[0]], { apiKey: 'secret', fetchImpl }))
      .resolves.toBeNull()
    expect(fetchImpl).not.toHaveBeenCalled()
  })
})
