#!/usr/bin/env bash
# Publish the macOS and Linux Node archives consumed by Harness Desktop's
# first-run provisioner. The desktop app trusts the sha256 in this manifest,
# never a downloaded checksum file at install time.
#
# Usage: bash scripts/publish-managed-node-runtime.sh 22.16.0
set -euo pipefail
set +x

. "$(dirname "${BASH_SOURCE[0]}")/lib/publish-common.sh"

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <Node version, e.g. 22.16.0>" >&2
  exit 2
fi

publish_require_tools curl shasum python3
publish_require_gcloud
publish_init_env "harness/runtime/metadata.json"

NODE_BASE="https://nodejs.org/dist/v${VERSION}"

curl -fsSL "$NODE_BASE/SHASUMS256.txt" -o "$WORK_DIR/SHASUMS256.txt"

declare -a ENTRIES=()
for pair in \
  "darwin:arm64:darwin-arm64" \
  "darwin:x64:darwin-x64" \
  "linux:arm64:linux-arm64" \
  "linux:x64:linux-x64"; do
  IFS=: read -r platform upstream_arch manifest_arch <<< "$pair"
  archive="node-v${VERSION}-${platform}-${upstream_arch}.tar.gz"
  archive_path="$WORK_DIR/$archive"
  curl -fsSL "$NODE_BASE/$archive" -o "$archive_path"
  expected="$(awk -v name="$archive" '$2 == name { print $1 }' "$WORK_DIR/SHASUMS256.txt")"
  actual="$(shasum -a 256 "$archive_path" | awk '{print $1}')"
  [[ "$expected" =~ ^[a-f0-9]{64}$ ]] || {
    echo "error: official SHASUMS256.txt has no checksum for $archive" >&2
    exit 1
  }
  [[ "$actual" == "$expected" ]] || {
    echo "error: checksum mismatch for $archive" >&2
    exit 1
  }

  object_path="harness/runtime/node/v${VERSION}/$archive"
  url="${PUBLIC_BASE%/}/${object_path}"
  size="$(wc -c < "$archive_path" | tr -d ' ')"
  echo ">> uploading $archive ($size bytes)"
  gcloud storage cp --cache-control='public, max-age=31536000, immutable' \
    "$archive_path" "gs://${GCS_BUCKET}/${object_path}"
  ENTRIES+=("$manifest_arch|v$VERSION|$url|$actual|$size|node-v${VERSION}-${platform}-${upstream_arch}")
done

publish_fetch_current_metadata
publish_merge_metadata node
publish_upload_metadata

echo ">> published managed Node v${VERSION}"
