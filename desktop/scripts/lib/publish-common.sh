#!/usr/bin/env bash
# Shared plumbing for desktop/scripts/publish-managed-{node,tmux,grid}-runtime.sh.
# Source it, don't execute it. Each publisher keeps only what is genuinely its
# own: version validation, archive production and validation, and its upload loop.

# publish_require_tools <command>... — every named tool must be on PATH.
publish_require_tools() {
  for command in "$@"; do
    command -v "$command" >/dev/null 2>&1 || {
      echo "error: $command is required" >&2
      exit 1
    }
  done
}

publish_require_gcloud() {
  # --- GCS client: `gcloud storage`, and only `gcloud storage` ---
  # gsutil was retired from this repo on 2026-09-17. It is a standalone Python tool that only
  # understands gcloud's *user* and *service-account-key* credentials: it cannot use the
  # external-account (federated) credential Workload Identity Federation issues, so every call
  # fails under WIF while the identical `gcloud storage` call works — it is the same gcloud
  # binary that performed the token exchange. Do not reintroduce it.
  command -v gcloud >/dev/null 2>&1 || {
    echo "error: gcloud not found — install/authenticate the gcloud SDK" >&2
    exit 1
  }
  gcloud storage --help >/dev/null 2>&1 || {
    echo "error: this gcloud is too old for 'gcloud storage' — update the gcloud SDK" >&2
    exit 1
  }
}

# gcs_cp <src> <dst> [cache-control] [content-type] — either side may be gs:// or a local path or `-`.
gcs_cp() {
  local src="$1" dst="$2" cc="${3:-}" ct="${4:-}" args=(storage cp)
  if [ -n "$cc" ]; then args+=("--cache-control=$cc"); fi
  if [ -n "$ct" ]; then args+=("--content-type=$ct"); fi
  gcloud "${args[@]}" "$src" "$dst"
}

# publish_init_env <metadata-path> — bucket/manifest coordinates and the temp
# work dir. Sets GCS_BUCKET, PUBLIC_BASE, METADATA_PATH, WORK_DIR, SRC, DST in
# the caller's shell and traps EXIT to clean the work dir up.
publish_init_env() {
  GCS_BUCKET="${GCS_BUCKET:-s3-autonomous-upgrade-3}"
  PUBLIC_BASE="${GCS_PUBLIC_BASE_URL:-https://storage.googleapis.com/${GCS_BUCKET}}"
  METADATA_PATH="${METADATA_PATH:-$1}"
  WORK_DIR="$(mktemp -d)"
  SRC="$WORK_DIR/metadata.json"
  DST="$WORK_DIR/metadata.next.json"
  trap 'rm -rf "$WORK_DIR"' EXIT
}

# Fetch the current manifest into $SRC, starting from {} when none exists yet.
publish_fetch_current_metadata() {
  if ! gcs_cp "gs://${GCS_BUCKET}/${METADATA_PATH}" "$SRC" 2>/dev/null; then
    printf '{}' > "$SRC"
  fi
}

# publish_merge_metadata <top-level key> — merges ${ENTRIES[@]} into the
# manifest at $SRC and writes the result to $DST. Each entry is
# "key|version|url|sha256|size|archive-root"; the sha256 is what the installer
# trusts — never a checksum file fetched at install time.
publish_merge_metadata() {
  python3 - "$SRC" "$DST" "$1" "${ENTRIES[@]}" <<'PY'
import json, sys
src, dst, section_name, *entries = sys.argv[1:]
try:
    with open(src) as f:
        document = json.load(f)
except (OSError, json.JSONDecodeError):
    document = {}
if not isinstance(document, dict):
    document = {}
section = document.get(section_name)
if not isinstance(section, dict):
    section = {}
document[section_name] = section
for entry in entries:
    key, version, url, sha256, size, archive_root = entry.split("|", 5)
    section[key] = {
        "version": version,
        "url": url,
        "sha256": sha256,
        "size": int(size),
        "archiveRoot": archive_root,
    }
with open(dst, "w") as f:
    json.dump(document, f, indent=2)
    f.write("\n")
PY
}

# Upload the merged manifest and print where it landed.
publish_upload_metadata() {
  gcs_cp "$DST" "gs://${GCS_BUCKET}/${METADATA_PATH}" \
    'no-cache, no-store, must-revalidate' 'application/json'
  echo ">> manifest: ${PUBLIC_BASE%/}/${METADATA_PATH}"
}
