import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, posix } from 'node:path'

// Ship the manager itself with the CLI. No clone, package manager, or model
// download is needed to make its conversation and viewer available.
export function readModelManagerBundle(root) {
  return readBuiltinBundle(root, ['harness.json', 'AGENTS.md', 'LICENSE', 'VERSIONS', 'viewer.sh', 'viewer.mjs', 'viewer', 'lib', 'toolchain', 'template', 'skills'])
}

export function readHarnessMonitorBundle(root) {
  return readBuiltinBundle(root, ['harness.json', 'AGENTS.md', 'LICENSE', 'package.json', 'viewer.sh', 'viewer.mjs', 'viewer', 'lib', 'toolchain', 'template', 'skills'])
}

/** Memories: everything the harness and its `mem` command run on; its tests and Store page stay behind. */
export function readMemoriesBundle(root) {
  return readBuiltinBundle(root, ['harness.json', 'AGENTS.md', 'LICENSE', 'README.md', 'package.json', 'viewer.sh', 'viewer.mjs', 'viewer', 'lib', 'toolchain', 'template', 'skills'])
}

export function readBuiltinBundle(root, paths) {
  const files = {}
  const visit = relative => {
    const path = join(root, relative)
    const stat = statSync(path)
    if (stat.isDirectory()) {
      for (const name of readdirSync(path).sort()) visit(posix.join(relative, name))
    } else {
      const bytes = readFileSync(path)
      const text = bytes.toString('utf8')
      const binary = !Buffer.from(text, 'utf8').equals(bytes)
      // Windows builds ship this text package into WSL: preserve usable script
      // bytes and executable intent even when the checkout has no POSIX modes.
      const content = binary ? bytes.toString('base64') : text.replace(/\r\n/g, '\n')
      files[relative] = { content,
        ...(binary ? { encoding: 'base64' } : {}),
        executable: Boolean(stat.mode & 0o111) || (!binary && content.startsWith('#!')) }
    }
  }
  for (const path of paths) visit(path)
  return files
}
