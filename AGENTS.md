# Agent entry point

Read [CLAUDE.md](CLAUDE.md) for this fork's standing context and boundaries. It applies to every agent. Keep this file a pointer rather than duplicating the guidance.

## Cursor Cloud specific instructions

Development commands stay in [docs/development.md](docs/development.md). On a Cloud Agent VM:

- Node **22.23.2** (the CLI runtime pin in `.github/workflows/ci.yml`) is `/opt/node-v22.23.2`. Flutter **3.47.2** is `/opt/flutter`. Both are prepended to `PATH` in `~/.bashrc`. The image Node at `/exec-daemon/node` is older; do not use it for this repo.
- `~/.bashrc` unsets `npm_config_prefix` before loading nvm. CLI tests spawn a login shell and compare its output. Leaving that variable set makes nvm print into the output and fail those tests.
- `tmux`, `sqlite3`, and `libclang-rt-18-dev` (firmware host tests) are installed.
- Refresh dependencies from the repo root: `npm ci --prefix cli`, `npm ci --prefix backend`, `npm ci --prefix provider/e2e`, and `flutter pub get` in `desktop/`.
- Account-free check: from `cli/`, `npm run dev -- dsh check ../store/examples/hello-world` ends with `examples/hello-world conforms to spec 1`. A signed-out daemon is `ADAPTER_UPDATE_DISABLE=true npm run dev -- start -f` (loopback `http://127.0.0.1:18473/api/health`).
- The VM root is overlayfs. A few CLI tests that require a same-tick rewrite to change file `mtime` can fail here (`machineList` disk writes, media preview revision). That is this filesystem, not a missing package.
