import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

const deepSeekInstallCommand = 'npm install -g @deepseek-ai/dsh@0.1.5-rc.2';

/// Arguments stay separate from shell source, including project paths.
List<String> deepSeekCompanionArguments({
  required String distro,
  required String folder,
}) {
  if (distro.trim().isEmpty || distro.contains('\x00')) {
    throw ArgumentError('Choose a WSL distribution.');
  }
  if (!folder.startsWith('/') || folder.contains('\x00')) {
    throw ArgumentError('Choose an absolute Linux project folder.');
  }
  return [
    '-d',
    distro,
    '-e',
    'setsid',
    '--wait',
    'bash',
    '-ic',
    _deepSeekSupervisor,
    'harness-deepseek',
    folder,
  ];
}

// The session leader owns the server and its children. Closing Harness's stdin
// ends that group, including when the desktop exits unexpectedly. No global
// process name, port lookup, or user-owned server is ever killed.
const _deepSeekSupervisor = r'''
# Load the user's interactive tool PATH, then keep all children in this session's
# process group so stopping the companion also stops its tools.
set +m
export PATH="$HOME/.local/bin:$PATH"
node_file="$HOME/.harness/runtime/current-node"
if [ -s "$node_file" ]; then
  IFS= read -r managed_node < "$node_file"
  if [ -x "$managed_node" ]; then export PATH="${managed_node%/*}:$PATH"; fi
fi
fail() { printf 'HARNESS_DEEPSEEK_ERROR:%s\n' "$1" >&2; exit 1; }
cd -- "$1" 2>/dev/null || fail INVALID_FOLDER
command -v node >/dev/null 2>&1 || fail MISSING_NODE
node -e 'const [a,b]=process.versions.node.split(".").map(Number); process.exit((a===22&&b>=19)||a>=24?0:1)' || fail UNSUPPORTED_NODE
command -v dsh >/dev/null 2>&1 || fail MISSING_DSH
exec 3<&0
child=''
cleanup() {
  trap - EXIT HUP INT
  trap '' TERM
  kill -TERM -- -$$ 2>/dev/null || true
  if [ -n "$child" ]; then
    # The direct server can exit while a tool ignores TERM. Keep the session
    # leader alive through the grace period, then stop the whole owned group.
    sleep 2
    kill -KILL -- -$$ 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' HUP INT TERM
dsh web --host 127.0.0.1 --port 0 --no-open </dev/null &
child=$!
( IFS= read -r stop <&3; kill -TERM $$ 2>/dev/null ) &
wait "$child"
''';

/// Only the exact loopback endpoint emitted by the supervised server is usable.
/// The bearer token stays in memory; callers must not log or persist this URI.
Uri? parseDeepSeekLaunchUri(String line) {
  const prefix = 'dsh web: ';
  if (!line.startsWith(prefix) || line.length > 8192) return null;
  final text = line.substring(prefix.length);
  if (RegExp(r'\s|%(?![0-9a-fA-F]{2})').hasMatch(text)) return null;
  try {
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'http' ||
        uri.host != '127.0.0.1' ||
        uri.userInfo.isNotEmpty ||
        !uri.hasPort ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.path != '/' ||
        uri.hasFragment ||
        uri.queryParametersAll.length != 1 ||
        uri.queryParametersAll['token']?.length != 1 ||
        uri.queryParameters['token']?.isNotEmpty != true) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

typedef CompanionProcessStarter = Future<Process> Function(
  String executable,
  List<String> arguments,
);

/// One browser companion per desktop process, independent of dialog lifetime.
class DeepSeekCompanion extends ChangeNotifier {
  DeepSeekCompanion({
    CompanionProcessStarter? startProcess,
    this.startupTimeout = const Duration(seconds: 60),
    this.shutdownTimeout = const Duration(seconds: 6),
  }) : _startProcess = startProcess ?? _start;

  static final instance = DeepSeekCompanion();
  static Future<Process> _start(String executable, List<String> arguments) =>
      Process.start(executable, arguments);

  final CompanionProcessStarter _startProcess;
  final Duration startupTimeout;
  final Duration shutdownTimeout;
  Process? _process;
  Completer<void>? _ready;
  Future<void>? _stopping;
  bool _disposed = false;
  bool _starting = false;
  int _generation = 0;
  String _status = 'Not running';
  Uri? _launchUri;
  String? _distro;
  String? _folder;

  bool get running => _process != null && _launchUri != null;
  bool get starting => _starting;
  String get status => _status;
  Uri? get launchUri => _launchUri;
  String? get distro => _distro;
  String? get folder => _folder;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start({required String distro, required String folder}) async {
    if (_disposed) throw StateError('The companion has been disposed.');
    if (_starting || _stopping != null) {
      throw StateError('Wait for the current start or stop to finish.');
    }
    if (running) {
      if (_distro == distro && _folder == folder) return;
      throw StateError(
        'Stop the running DeepSeek server before changing projects.',
      );
    }
    final arguments = deepSeekCompanionArguments(
      distro: distro,
      folder: folder,
    );
    final generation = ++_generation;
    final ready = Completer<void>();
    // Attach the error handler before any output can arrive.
    final readyFuture = ready.future;
    unawaited(readyFuture.catchError((Object _) {}));
    _ready = ready;
    _starting = true;
    _status = 'Starting DeepSeek Harness in WSL…';
    _distro = distro;
    _folder = folder;
    _changed();
    try {
      final process = await _startProcess('wsl.exe', arguments);
      if (_disposed || generation != _generation) {
        await _terminate(process);
        return;
      }
      _process = process;
      _listen(process.stdout, (line) {
        if (generation != _generation) return;
        final uri = parseDeepSeekLaunchUri(line);
        if (uri == null || ready.isCompleted) return;
        _launchUri = uri;
        _starting = false;
        _status = 'DeepSeek Harness is running locally.';
        ready.complete();
        _changed();
      });
      _listen(process.stderr, (line) {
        if (generation != _generation || ready.isCompleted) return;
        final message = _knownFailure(line);
        if (message != null) ready.completeError(StateError(message));
      });
      unawaited(
        process.exitCode.then((_) {
          if (generation != _generation) return;
          _process = null;
          _launchUri = null;
          _starting = false;
          if (!ready.isCompleted) {
            ready.completeError(
              StateError(
                'DeepSeek did not start. Check dsh web in the selected WSL distribution.',
              ),
            );
          } else {
            _status = 'DeepSeek Harness stopped.';
            _changed();
          }
        }),
      );
      await readyFuture.timeout(startupTimeout);
    } catch (error) {
      if (generation != _generation) return;
      final message = error is StateError
          ? error.message.toString()
          : error is TimeoutException
          ? 'DeepSeek startup timed out. Check dsh web in the selected WSL distribution.'
          : 'Could not start DeepSeek. Check that WSL and the selected distribution are available.';
      await stop();
      _status = message;
      _changed();
      throw StateError(message);
    } finally {
      if (generation == _generation) {
        _starting = false;
        _ready = null;
        _changed();
      }
    }
  }

  static String? _knownFailure(String line) => switch (line) {
    'HARNESS_DEEPSEEK_ERROR:MISSING_DSH' =>
      'DeepSeek is not installed in this WSL distribution. Run: $deepSeekInstallCommand',
    'HARNESS_DEEPSEEK_ERROR:MISSING_NODE' ||
    'HARNESS_DEEPSEEK_ERROR:UNSUPPORTED_NODE' => 'DeepSeek requires Node.js 22.19 or newer in the 22 series, or Node.js 24 or newer.',
    'HARNESS_DEEPSEEK_ERROR:INVALID_FOLDER' =>
      'The project folder is not accessible in the selected WSL distribution.',
    _ => null,
  };

  // Bound lines even for a misbehaving subprocess. Raw output is discarded,
  // never retained in status or Harness logs (it can contain the bearer token).
  static void _listen(Stream<List<int>> source, void Function(String) onLine) {
    var pending = '';
    var discarding = false;
    source.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
      for (final part in chunk.split('\n').indexed) {
        if (part.$1 > 0) {
          if (!discarding) onLine(pending.replaceFirst(RegExp(r'\r$'), ''));
          pending = '';
          discarding = false;
        }
        if (!discarding) {
          pending += part.$2;
          if (pending.length > 8192) {
            pending = '';
            discarding = true;
          }
        }
      }
    }, onError: (Object _) {});
  }

  Future<void> stop() {
    final current = _stopping;
    if (current != null) return current;
    ++_generation;
    final process = _process;
    _process = null;
    _launchUri = null;
    _starting = false;
    final ready = _ready;
    _ready = null;
    if (ready != null && !ready.isCompleted) ready.complete();
    _status = 'DeepSeek Harness stopped.';
    _changed();
    final operation = process == null
        ? Future<void>.value()
        : _terminate(process);
    _stopping = operation;
    return operation.whenComplete(() {
      _stopping = null;
    });
  }

  Future<void> _terminate(Process process) async {
    try {
      await process.stdin.close();
    } catch (_) {
      // Already closed when the server exited on its own.
    }
    try {
      await process.exitCode.timeout(shutdownTimeout);
    } on TimeoutException {
      process.kill();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}

String? findZcodeExecutable({
  Map<String, String>? environment,
  bool Function(String)? exists,
}) {
  final env = environment ?? Platform.environment;
  final fileExists = exists ?? (path) => File(path).existsSync();
  for (final root in [env['LOCALAPPDATA'], env['ProgramFiles']]) {
    if (root == null || root.isEmpty) continue;
    final path = root == env['LOCALAPPDATA']
        ? '$root\\Programs\\ZCode\\ZCode.exe'
        : '$root\\ZCode\\ZCode.exe';
    if (fileExists(path)) return path;
  }
  return null;
}

Future<void> launchZcode() async {
  if (!Platform.isWindows) {
    throw StateError('This ZCode launcher is available on Windows.');
  }
  final executable = findZcodeExecutable();
  if (executable == null) {
    throw StateError(
      'Install the official ZCode desktop app from zcode.z.ai first.',
    );
  }
  await Process.start(executable, const [], mode: ProcessStartMode.detached);
}
