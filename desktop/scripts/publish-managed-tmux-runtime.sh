#!/usr/bin/env bash
# Publish the macOS tmux archives that `cli/scripts/build-managed-tmux.sh` produced, the same way
# publish-managed-node-runtime.sh publishes Node: immutable archives under harness/runtime/tmux/,
# and a manifest whose sha256 is what the installer trusts — never a checksum file fetched at
# install time. Its own manifest, harness/runtime/tmux/metadata.json, rather than an entry in Node's:
# install.sh slices a manifest by the FIRST "<platform>" key it finds, and Node's already has one.
#
# Usage: bash scripts/publish-managed-tmux-runtime.sh 3.5a <dir holding tmux-3.5a-darwin-{arm64,x64}.tar.gz>
#
# Nothing consumes this manifest yet; install.sh learns to download it in the next step.
set -euo pipefail
set +x

. "$(dirname "${BASH_SOURCE[0]}")/lib/publish-common.sh"

VERSION="${1:-}"
ARCHIVES_DIR="${2:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+[a-z]?$ ]] || [[ -z "$ARCHIVES_DIR" ]]; then
  echo "usage: $0 <tmux version, e.g. 3.5a> <archives dir>" >&2
  exit 2
fi
[[ -d "$ARCHIVES_DIR" ]] || { echo "error: $ARCHIVES_DIR is not a directory" >&2; exit 2; }

publish_require_tools shasum python3
publish_require_gcloud
publish_init_env "harness/runtime/tmux/metadata.json"

# Both platforms or nothing: a manifest naming one Mac and not the other would make the installer's
# behaviour depend on which laptop it runs on.
declare -a ENTRIES=()
for platform in darwin-arm64 darwin-x64; do
  archive="tmux-${VERSION}-${platform}.tar.gz"
  archive_path="$ARCHIVES_DIR/$archive"
  [[ -f "$archive_path" ]] || { echo "error: missing $archive_path" >&2; exit 1; }
  root="tmux-${VERSION}-${platform}"
  # Captured, not piped into `grep -q`: under `pipefail` grep closing the pipe early fails the whole
  # pipeline on a fine archive — seen on the grid publisher's larger archives, latent here.
  listing="$(tar -tzf "$archive_path")"
  grep -qx "${root}/bin/tmux" <<< "$listing" || {
    echo "error: $archive has no ${root}/bin/tmux" >&2
    exit 1
  }
  sha256="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  size="$(wc -c < "$archive_path" | tr -d ' ')"
  url="${PUBLIC_BASE%/}/harness/runtime/tmux/v${VERSION}/${archive}"
  ENTRIES+=("$platform|$VERSION|$url|$sha256|$size|$root")
done

for entry in "${ENTRIES[@]}"; do
  IFS='|' read -r platform version url sha256 size root <<< "$entry"
  archive="${url##*/}"
  echo ">> uploading $archive ($size bytes, sha256 $sha256)"
  gcs_cp "$ARCHIVES_DIR/$archive" "gs://${GCS_BUCKET}/harness/runtime/tmux/v${version}/${archive}" \
    'public, max-age=31536000, immutable'
done

publish_fetch_current_metadata
publish_merge_metadata tmux
publish_upload_metadata

echo ">> published managed tmux ${VERSION}"
