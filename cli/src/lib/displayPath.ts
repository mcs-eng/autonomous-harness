import { homedir } from 'node:os'

/** Compact a home-relative path with `~` for display. */
export function tildify(path: string): string {
  const home = homedir()
  return path.startsWith(home) ? '~' + path.slice(home.length) : path
}
