#!/bin/sh
# Exit 0 when this machine can run Kepler. One line per check.
set -u
fail=0
if command -v node >/dev/null 2>&1; then
  major="$(node -p 'process.versions.node.split(".")[0]')"
  if [ "$major" -ge 20 ]; then
    echo "ok   node $(node -v)"
  else
    echo "miss node $(node -v) — Kepler needs Node 20 or newer"
    fail=1
  fi
else
  echo "miss node — Kepler needs Node 20 or newer on PATH"
  fail=1
fi
root="$(CDPATH= cd "$(dirname "$0")/.." && pwd)"
if [ -f "$root/skills/kepler/engine.mjs" ]; then
  echo "ok   kepler kernel"
else
  echo "miss kepler kernel"
  fail=1
fi
exit "$fail"
