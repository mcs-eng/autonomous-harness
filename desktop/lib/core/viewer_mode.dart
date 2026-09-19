import 'dart:io';

/// Whether this build is a VIEWER: a window onto the user's machines and nothing more.
///
/// No harness CLI runs beside it and no agent is ever hosted here, so every machine — this computer
/// included, if it is a Harness machine at all — is reached through the relay, with this app
/// terminating the end-to-end encryption the CLI terminates everywhere else (see `lib/viewer/`).
///
/// True on iOS and Android, where a phone will not host a Node runtime or spawn a process at all.
/// On macOS and Linux only with `--dart-define=HARNESS_VIEWER_MODE=true`, which is how the path is
/// developed and tested on a Mac against real machines.
///
/// Windows is deliberately NOT a viewer in this fork, diverging from upstream: the port hosts the
/// CLI inside WSL2 (see `WINDOWS_PORT.md`), so the Windows desktop app is a full peer — local
/// discovery, loopback transport, and "this machine" all work. Upstream's viewer-only Windows
/// stance disabled the entire local-CLI subsystem here and every machine degraded to relay-only.
/// A viewer-on-Windows remains available with `--dart-define=HARNESS_VIEWER_MODE=true`.
final bool kViewerMode =
    const bool.fromEnvironment('HARNESS_VIEWER_MODE') ||
    Platform.isIOS ||
    Platform.isAndroid;
