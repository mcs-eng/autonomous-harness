import { isLocalDevBuild } from './versionKind.js'

/** Print the complete local-build update result; false means the real updater must run. */
export function localUpdateNoop(scriptPath: string, version: string, force: boolean): boolean {
  if (scriptPath.endsWith('.ts')) {
    console.log('This is a dev/repo build (running from source) — `harness update` is a no-op. Rebuild the bundle instead.')
    return true
  }
  if (force || !isLocalDevBuild(version)) return false
  console.log(`This is a local build (v${version}), installed from a working tree by scripts/install-cli.sh.`)
  console.log('Updating would replace it with a published release and lose whatever it was built to test.')
  console.log('  keep it:    rebuild with `make install-cli` after you pull')
  console.log('  replace it: harness update --force')
  return true
}
