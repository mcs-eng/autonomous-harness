import { existsSync, readdirSync, statSync } from 'node:fs'
import { join } from 'node:path'

/** Subdirectories of `dir` that carry a SKILL.md, or `dir` itself when it is a single skill. */
export function skillDirsIn(dir: string): string[] {
  if (existsSync(join(dir, 'SKILL.md'))) return [dir]
  let entries: string[]
  try {
    entries = readdirSync(dir)
  } catch {
    return []
  }
  return entries
    .map((name) => join(dir, name))
    .filter((path) => {
      try { return statSync(path).isDirectory() && existsSync(join(path, 'SKILL.md')) } catch { return false }
    })
    .sort()
}
