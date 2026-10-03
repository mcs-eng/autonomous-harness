import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/wsl_smoke_isolation.dart';

/// Runs the admission script itself against a throwaway fixture, so its exit
/// status is checked and not only the argv that carries it.
///
/// Needs a POSIX bash with GNU `readlink -e` and `sha256sum`: Linux, or Git for
/// Windows found by absolute path. `bash` on a Windows PATH can be the WSL
/// launcher, which would run this in a real Linux account, so it is never used.
void main() {
  final bash = _posixBash();
  const id = '0123456789abcdef0123456789abcdef';
  const refusal =
      'Disposable WSL smoke contract unavailable; refusing command.';
  late Directory scratch;
  late String home;
  late String guardDirectory;

  Future<ProcessResult> shell(String script, List<String> arguments) =>
      Process.run(
        bash!,
        ['--noprofile', '--norc', '-c', script, 'fixture', ...arguments],
        environment: const {'BASH_ENV': '', 'ENV': ''},
      );

  /// The path as bash spells it after resolving links, which is what the
  /// script compares the declared home against.
  Future<String> posixPath(String path) async {
    final result = await shell(r'cd -- "$1" && pwd -P', [path]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return '${result.stdout}'.trim();
  }

  setUp(() async {
    if (bash == null) return;
    scratch = Directory.systemTemp.createTempSync('hwp-gui-');
    final homeDirectory = Directory('${scratch.path}/home')..createSync();
    File('${homeDirectory.path}/.smoke-fixture-id').writeAsStringSync('$id\n');
    home = await posixPath(homeDirectory.path);
    guardDirectory = await posixPath(scratch.path);
  });

  tearDown(() {
    if (bash == null) return;
    scratch.deleteSync(recursive: true);
  });

  /// Writes [body] as the guard and runs admission with its real digest.
  Future<ProcessResult> admit(String body) async {
    final guard = '$guardDirectory/guard.sh';
    File('${scratch.path}/guard.sh').writeAsStringSync(body);
    final digest = await shell(r'/usr/bin/sha256sum < "$1"', [guard]);
    expect(digest.exitCode, 0, reason: '${digest.stderr}');
    return shell(WslSmokeIsolation.admissionScript, [
      guard,
      home,
      id,
      '${digest.stdout}'.split(' ').first,
      '/usr/bin/printf',
      '%s',
      'admitted',
    ]);
  }

  String validating() => "HOME='$home'\nHARNESS_SMOKE_VALIDATED_ID=$id\n";

  void expectRefused(ProcessResult result) {
    expect(result.exitCode, 125, reason: '${result.stderr}');
    expect('${result.stdout}', isEmpty);
    expect(refusal.allMatches('${result.stderr}'), hasLength(1));
  }

  final skip = bash == null
      ? 'Needs Linux bash or Git for Windows bash with GNU coreutils.'
      : false;

  test('a validating guard admits the command', () async {
    final result = await admit(validating());
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect('${result.stdout}', 'admitted');
    expect('${result.stderr}', isNot(contains(refusal)));
  }, skip: skip);

  test(
    'a guard that exits 0 while sourced refuses instead of passing',
    () async {
      expectRefused(await admit('exit 0\n'));
      expectRefused(await admit('${validating()}exit 0\n'));
    },
    skip: skip,
  );

  test('a failing guard refuses with one message', () async {
    expectRefused(await admit('${validating()}false\n'));
  }, skip: skip);

  test('a guard that never validates refuses with one message', () async {
    expectRefused(await admit("HOME='$home'\n"));
  }, skip: skip);
}

String? _posixBash() {
  if (Platform.isLinux) {
    return File('/bin/bash').existsSync() ? '/bin/bash' : null;
  }
  if (Platform.isWindows) {
    for (final root in {
      Platform.environment['ProgramFiles'],
      Platform.environment['ProgramW6432'],
    }) {
      if (root == null) continue;
      final candidate = File('$root\\Git\\bin\\bash.exe');
      if (candidate.existsSync()) return candidate.path;
    }
  }
  return null;
}
