#!/bin/sh
set -eu
root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
node "$root/skills/kepler/scripts/check.mjs"
echo "Kepler workspace initialized"
