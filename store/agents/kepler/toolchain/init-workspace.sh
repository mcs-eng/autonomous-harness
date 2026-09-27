#!/bin/sh
# Fresh workspace: seed the verdict from the starter mission.
set -eu
root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
node "$root/skills/kepler/scripts/check.mjs"
echo "Kepler workspace initialized"
