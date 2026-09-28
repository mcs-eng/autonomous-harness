# hn launcher repair for existing installations

CLI 0.3.21 could report “Already on the latest version” while the shell reported
`hn: command not found`. The fresh installer wrote both launchers, but self-update
replaced only `cli.js` and `notify.mjs`. Installations created before hn shipped
never received its launcher.

The installed CLI now adds a missing `hn` command on entry. This includes daemon
handoffs after automatic updates and commands such as `harness update`, even when
there is no newer bundle. The script delegates to the existing `harness` launcher
with `tui`, preserving its managed Node runtime and any `--no-updates` pin.

The migration checks that it is running the installed bundle and that the
existing executable harness launcher names that bundle. Checkout builds and
staging canaries do not migrate the installation. A complete script is published
with an exclusive hard link, so concurrent invocations cannot truncate it or
replace an existing file or symlink. A read-only directory does not prevent the
CLI or daemon from starting.

An old updater whose daemon is stopped only stages the new bundle; the migration
runs when the new CLI is first invoked. `harness version` suffices. A running
daemon invokes the new bundle during its normal update handoff.

## Regression check

After building the bundle in `cli/`:

```sh
npm run typecheck
npm test
npm run bundle
node scripts/test-hn-upgrade.mjs
```

CI runs the packaged regression check. It uses a disposable home with spaces and
an apostrophe, an existing harness launcher, a loopback update manifest on guarded
port 19449, and a recording TUI fixture. It checks the already-current update,
argument and update-pin preservation, concurrent starts, and an existing hn
symlink. All owned files and the HTTP fixture are removed afterward.

For a real upgrade comparison, provide a saved previous release bundle and an
optional frozen native hn binary:

```sh
node scripts/test-hn-upgrade.mjs dist/cli.js /tmp/previous-cli.js /tmp/frozen-hn
```

This additionally reproduces the previous release's missing command after an
already-current update, exercises its original download/checksum/canary/staging
path, and runs the repaired launcher against the frozen native binary. Every
native invocation has a disposable home, explicit socket prefix and port; no
real daemon, harness or installed hn is used.
