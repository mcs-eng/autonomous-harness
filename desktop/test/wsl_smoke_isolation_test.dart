import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/wsl_preferences.dart';
import 'package:harness/core/wsl_runtime.dart';
import 'package:harness/core/wsl_smoke_isolation.dart';

void main() {
  const home = '/tmp/hwp-gui-synthetic/home';
  const guard = '/mnt/c/synthetic task/isolation-guard.sh';
  final contract = {
    'HARNESS_SMOKE_GUARD': guard,
    'HARNESS_SMOKE_HOME': home,
    'HARNESS_SMOKE_ID': '0123456789abcdef0123456789abcdef',
    'HARNESS_SMOKE_GUARD_SHA256': List.filled(64, 'a').join(),
  };
  WslRuntime runtime(Map<String, String> environment) => WslRuntime(
    selection: const WslSelection(distro: 'Ubuntu', username: 'fixture'),
    smokeEnvironment: environment,
  );

  test('ordinary WSL invocation retains the login shell and exact argv', () {
    expect(runtime({}).buildArguments(distro: 'Ubuntu', script: 'echo ok'), [
      '-d',
      'Ubuntu',
      '--user',
      'fixture',
      '-e',
      'bash',
      '-lc',
      'echo ok',
      'harness',
    ]);
  });

  test('every partially declared contract refuses before process creation', () {
    for (final key in WslSmokeIsolation.keys) {
      expect(() => runtime({key: contract[key]!}), throwsStateError);
      final missing = Map<String, String>.from(contract)..remove(key);
      expect(() => runtime(missing), throwsStateError);
    }
  });

  test('blank, malformed, traversing, or real-home contracts refuse', () {
    for (final change in [
      {'HARNESS_SMOKE_GUARD': ''},
      {'HARNESS_SMOKE_GUARD': '/tmp/optional.sh'},
      {'HARNESS_SMOKE_GUARD': '/mnt/c/task/../other.sh'},
      {'HARNESS_SMOKE_HOME': '/root'},
      {'HARNESS_SMOKE_HOME': '/tmp/../hwp-gui-synthetic/home'},
      {'HARNESS_SMOKE_ID': 'incorrect'},
      {'HARNESS_SMOKE_GUARD_SHA256': 'incorrect'},
    ]) {
      expect(() => runtime({...contract, ...change}), throwsStateError);
    }
  });

  test(
    'script admission avoids login files and retains shell literals as argv',
    () {
      final args = runtime(contract).buildArguments(
        distro: 'Ubuntu',
        script: r'printf "%s" "$1"',
        scriptName: 'literal name',
        scriptArguments: [r'$(touch ignored)', 'two words'],
      );
      expect(args.take(5), ['-d', 'Ubuntu', '--user', 'fixture', '-e']);
      expect(args.sublist(5, 14), [
        '/usr/bin/env',
        '-u',
        'BASH_ENV',
        '-u',
        'ENV',
        '/bin/bash',
        '--noprofile',
        '--norc',
        '-c',
      ]);
      expect(args[14], WslSmokeIsolation.admissionScript);
      expect(args.sublist(16, 20), [
        guard,
        home,
        contract['HARNESS_SMOKE_ID'],
        contract['HARNESS_SMOKE_GUARD_SHA256'],
      ]);
      expect(args.sublist(20), [
        '/bin/bash',
        '--noprofile',
        '--norc',
        '-c',
        r'printf "%s" "$1"',
        'literal name',
        r'$(touch ignored)',
        'two words',
      ]);
    },
  );

  test(
    'direct companion commands pass through the same mandatory admission',
    () {
      final args = runtime(contract)
          .commandArguments(distro: 'Ubuntu', command: ['synthetic', 'arg']);
      expect(args[14], WslSmokeIsolation.admissionScript);
      expect(args.sublist(args.length - 2), ['synthetic', 'arg']);
    },
  );

  test('packaged CLI and machine-ID probes use the guarded script path', () {
    final args = runtime(contract).bundledCliArguments(
      const WslHarnessProbe(distro: 'Ubuntu', found: true),
      r'C:\synthetic bundle',
      ['version'],
    );
    expect(args[14], WslSmokeIsolation.admissionScript);
    expect(args, isNot(contains('-lc')));
    expect(args.sublist(args.length - 2), [r'C:\synthetic bundle', 'version']);
  });
}
