#!/bin/sh
# The pane. Harness sets HARNESS_VIEWER_PORT and HARNESS_WORKSPACE.
set -eu
here="$(CDPATH= cd "$(dirname "$0")" && pwd)"
if ! command -v node >/dev/null 2>&1; then
  echo "kepler viewer needs node on PATH" >&2
  exit 1
fi
exec node "$here/viewer.mjs"
