import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, posix } from 'node:path'

// Ship the manager itself with the CLI. No clone, package manager, or model
// download is needed to make its conversation and viewer available.
export function readModelManagerBundle(root) {
  const files = {}
  const visit = relative => {
    const path = join(root, relative)
    const stat = statSync(path)
    if (stat.isDirectory()) {
      for (const name of readdirSync(path).sort()) visit(posix.join(relative, name))
    } else {
      // Windows builds ship this text package into WSL: preserve usable script
      // bytes and executable intent even when the checkout has no POSIX modes.
      const content = readFileSync(path, 'utf8').replace(/\r\n/g, '\n')
      files[relative] = { content, executable: Boolean(stat.mode & 0o111) || content.startsWith('#!') }
    }
  }
  for (const path of ['harness.json', 'AGENTS.md', 'LICENSE', 'VERSIONS', 'viewer.sh', 'viewer.mjs', 'viewer', 'lib', 'toolchain', 'template', 'skills']) visit(path)
  return files
}
