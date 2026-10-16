// The credential resolver is where a misconfiguration is supposed to become a startup error rather
// than a failed turn, so these tests are mostly about the REFUSALS, not the happy path.
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterAll, describe, expect, it } from 'vitest'

const { anthropicSpawnEnv, loadAgents, resolveAnthropicEnv } = await import('./config.js')

const root = mkdtempSync(join(tmpdir(), 'example-provider-config-'))
afterAll(() => rmSync(root, { recursive: true, force: true }))

let fixture = 0
function agentsFile(value: unknown): string {
  const file = join(root, `agents-${fixture++}.json`)
  writeFileSync(file, JSON.stringify(value))
  return file
}

const AGENT = { id: 'scratch', name: 'Scratch', description: '', cwd: root }

const FULL = {
  ANTHROPIC_BASE_URL: 'https://gateway.example.com',
  ANTHROPIC_AUTH_TOKEN: 'sk-secret',
  ANTHROPIC_MODEL: 'my-custom-model',
}

describe('resolveAnthropicEnv', () => {
  it('returns nothing when nothing is configured — the local login is a valid setup', () => {
    // The zero-config path this example shipped with. It must stay reachable, or every reader who
    // just wants to try the thing has to go find a gateway first.
    expect(resolveAnthropicEnv({})).toBeUndefined()
  })

  it('resolves a complete set', () => {
    expect(resolveAnthropicEnv(FULL)).toEqual({
      baseUrl: 'https://gateway.example.com',
      authToken: 'sk-secret',
      model: 'my-custom-model',
    })
  })

  it('accepts ANTHROPIC_API_KEY as the token', () => {
    // Which of the two names an endpoint hands out is its own business; both authenticate the CLI.
    const { ANTHROPIC_AUTH_TOKEN, ...rest } = FULL
    expect(resolveAnthropicEnv({ ...rest, ANTHROPIC_API_KEY: 'sk-other' })?.authToken).toBe('sk-other')
  })

  it('carries the small-model slot when given, and omits it otherwise', () => {
    expect(resolveAnthropicEnv({ ...FULL, ANTHROPIC_SMALL_FAST_MODEL: 'tiny' })?.smallFastModel).toBe('tiny')
    expect('smallFastModel' in resolveAnthropicEnv(FULL)!).toBe(false)
  })

  it('REFUSES a base URL with no token, and names what is missing', () => {
    const { ANTHROPIC_AUTH_TOKEN, ...partial } = FULL
    expect(() => resolveAnthropicEnv(partial)).toThrow(/ANTHROPIC_AUTH_TOKEN/)
  })

  it('REFUSES a base URL with no model', () => {
    // The case this rule exists for. Without it the provider starts happily and sends the default
    // `claude-sonnet-5` to a gateway that does not serve it — a failure that surfaces mid-turn, in
    // front of a user, instead of at boot in front of whoever is configuring it.
    const { ANTHROPIC_MODEL, ...partial } = FULL
    expect(() => resolveAnthropicEnv(partial)).toThrow(/ANTHROPIC_MODEL/)
  })

  it('REFUSES a token with no endpoint to send it to', () => {
    expect(() => resolveAnthropicEnv({ ANTHROPIC_AUTH_TOKEN: 'sk-secret' })).toThrow(/ANTHROPIC_BASE_URL/)
  })

  it('lists EVERY missing variable at once, not just the first', () => {
    // Reporting them one per restart turns configuration into a guessing game.
    try {
      resolveAnthropicEnv({ ANTHROPIC_BASE_URL: 'https://gateway.example.com' })
      throw new Error('expected a refusal')
    } catch (err) {
      const message = (err as Error).message
      expect(message).toContain('ANTHROPIC_AUTH_TOKEN')
      expect(message).toContain('ANTHROPIC_MODEL')
      // …and it says how to get out of the state, not just what is wrong with it.
      expect(message).toMatch(/\.env|local .?claude.? login/)
    }
  })

  it('treats whitespace-only values as absent rather than as configuration', () => {
    // A trailing-space edit in a .env is not a credential, and quietly accepting one would send an
    // empty Authorization header to the gateway.
    expect(() => resolveAnthropicEnv({ ...FULL, ANTHROPIC_AUTH_TOKEN: '   ' })).toThrow(/ANTHROPIC_AUTH_TOKEN/)
  })
})

describe('anthropicSpawnEnv', () => {
  it('spreads to nothing when unconfigured, leaving the CLI exactly as it was', () => {
    expect(anthropicSpawnEnv(undefined)).toEqual({})
  })

  it('maps to the CLI’s own variable names', () => {
    // The one place this mapping lives — both spawn sites call it, so they cannot drift apart.
    expect(anthropicSpawnEnv(resolveAnthropicEnv(FULL))).toEqual({
      ANTHROPIC_BASE_URL: 'https://gateway.example.com',
      ANTHROPIC_AUTH_TOKEN: 'sk-secret',
      ANTHROPIC_MODEL: 'my-custom-model',
    })
  })
})

describe('loadAgents', () => {
  it('reports a missing agents file with setup guidance', () => {
    expect(() => loadAgents(join(root, 'missing.json'))).toThrow(/agents file not found:.*Copy agents\.example\.json/s)
  })

  it.each<{ label: string; value: unknown; error: RegExp }>([
    { label: 'top-level object', value: AGENT, error: /non-empty array of agents/ },
    { label: 'null entry', value: [null], error: /agent must be an object/ },
    { label: 'numeric id', value: [{ ...AGENT, id: 7 }], error: /id must match/ },
    { label: 'numeric name', value: [{ ...AGENT, name: 7 }], error: /name is required/ },
    { label: 'numeric description', value: [{ ...AGENT, description: 7 }], error: /description must be a string/ },
    { label: 'numeric cwd', value: [{ ...AGENT, cwd: 7 }], error: /cwd must be an absolute path/ },
  ])('rejects a bad type: $label', ({ value, error }) => {
    expect(() => loadAgents(agentsFile(value))).toThrow(error)
  })

  it('rejects unknown agent keys instead of silently discarding a typo', () => {
    expect(() => loadAgents(agentsFile([{ ...AGENT, workingDirectory: root }]))).toThrow(/unknown key "workingDirectory"/)
  })

  it.each<{ label: string; value: unknown; error: RegExp }>([
    { label: 'agent list', value: [], error: /non-empty array of agents/ },
    { label: 'id', value: [{ ...AGENT, id: '' }], error: /id must match/ },
    { label: 'name', value: [{ ...AGENT, name: '   ' }], error: /name is required/ },
    { label: 'cwd', value: [{ ...AGENT, cwd: '' }], error: /cwd must be an absolute path/ },
  ])('rejects an empty $label', ({ value, error }) => {
    expect(() => loadAgents(agentsFile(value))).toThrow(error)
  })
})
