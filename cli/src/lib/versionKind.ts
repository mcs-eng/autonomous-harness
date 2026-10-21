/** A build made from a working tree rather than downloaded from the release channel: the
 *  `<published-core>-dev.<sha>[.dirty]` label that scripts/lib/build-label.sh stamps on every local
 *  install, plus the `0.0.0-dev` sentinel version.ts falls back to. */
export function isLocalDevBuild(version: string): boolean {
  return /^\d+\.\d+\.\d+-dev(\.|$)/.test(version.trim())
}
