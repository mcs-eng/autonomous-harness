# hn layout changes survive desk synchronization

C-b Space could briefly select a layout and then return to the previous arrangement. Two
independent reproductions explain this:

- A backend predating `layout.tmux` rejects the field. hn retries without it, then treats its own
  accepted reply as a remote layout change and rebuilds the previous desktop preset.
- Fitting a received layout to a differently sized terminal queued a resize notification that
  also published another desk layout. Two clients could repeatedly send their fitted sizes back.

The fix distinguishes the last observed desk document from a local edit, recognizes accepted
layout writes, and keeps unsent input until it can be saved. Desk writes run in order, including
legacy retries, in batches of at most 200 operations. Only a schema rejection (HTTP 400) triggers
legacy fallback; an outage does not permanently disable native layouts. Terminal fitting still
fires the tmux resize hook, but only explicit arrangement/divider edits publish a desk layout.
Genuine remote layout changes and pane membership changes still reconcile normally.

## Reproduction and verification

`tui/tests/layout-sync.py` runs real hn clients inside private tmux PTYs. It covers the actual
C-b Space sequence, all seven named layouts, divider sizes, delayed older saves, a transient
500, read-only desk mode, unrelated desk updates, intentional remote layouts, large edit bursts,
and differently sized clients without an echo loop. It rejects ports outside 19800–19809, freezes
the tested binary, uses disposable homes and explicit socket names, and waits for its clients to
exit before deleting their homes.

```sh
CARGO_TARGET_DIR=/tmp/hn-layout-target cargo test --manifest-path tui/Cargo.toml --release --offline
CARGO_TARGET_DIR=/tmp/hn-layout-target cargo build --manifest-path tui/Cargo.toml --release --offline
HN_LAYOUT_TEST_BINARY=/tmp/hn-layout-target/release/harness-tui \
  HN_LAYOUT_TEST_PORT=19801 python3 -u tui/tests/layout-sync.py
```

There are 132 Rust tests, including reconciliation, legacy acknowledgements, queued input and
terminal fitting. The existing e2e suite also passed on macOS. The on-demand CI workflow runs the
new layout suite on both Linux x86-64 and ARM64 along with the existing checks.

`tui/tests/viewer-live.mjs` additionally seeds two disposable harnesses in the real backend desk,
opens a real hn PTY over the real daemon, sends C-b Space, verifies the stored native layout, and
checks that a remote rename leaves its geometry and pane identities intact. Its existing browser
and terminal recovery checks remain enabled. The stack is isolated on one physical Mac with real
MongoDB, Redis, backend, daemon, tmux and Chrome; OAuth and the model process are fixtures. This
is not a production-account or separate-physical-computer test.

An old backend still cannot store the exact tmux geometry for a future client. This change keeps
that geometry stable in the current client; full native layout persistence requires a backend
that supports `layout.tmux`. No release or installed hn binary is changed by these tests.
