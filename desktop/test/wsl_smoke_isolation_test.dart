import 'dart:io';

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

  // Refusal happens when a WSL command is built. Every platform constructs a
  // runtime at startup, so construction itself must survive a bad contract.
  void expectCommandsRefused(Map<String, String> environment) {
    final wsl = runtime(environment);
    expect(
      () => wsl.buildArguments(distro: 'Ubuntu', script: 'echo ok'),
      throwsStateError,
    );
    expect(
      () => wsl.commandArguments(distro: 'Ubuntu', command: ['synthetic']),
      throwsStateError,
    );
    expect(
      () => wsl.bundledCliArguments(
        const WslHarnessProbe(distro: 'Ubuntu', found: true),
        r'C:\synthetic bundle',
        ['version'],
      ),
      throwsStateError,
    );
  }

  test('every partially declared contract refuses before process creation', () {
    for (final key in WslSmokeIsolation.keys) {
      expectCommandsRefused({key: contract[key]!});
      expectCommandsRefused(Map<String, String>.from(contract)..remove(key));
    }
  });

  test('an invalid contract does not prevent constructing the runtime', () {
    for (final key in WslSmokeIsolation.keys) {
      expect(() => runtime({key: contract[key]!}), returnsNormally);
    }
    expect(
      () => runtime({...contract, 'HARNESS_SMOKE_ID': 'incorrect'}),
      returnsNormally,
    );
  });

  test(
    'probes and scripts report an invalid contract without a process',
    () async {
      final calls = <List<String>>[];
      final wsl = WslRuntime(
        selection: const WslSelection(distro: 'Ubuntu', username: 'fixture'),
        smokeEnvironment: {'HARNESS_SMOKE_GUARD': guard},
        runProcess: (executable, arguments, {environment}) async {
          calls.add(arguments);
          return ProcessResult(0, 0, '', '');
        },
      );
      for (final probe in [
        await wsl.findHarness(),
        await wsl.findHarness(distros: ['Ubuntu']),
        await wsl.probeHarness(distro: 'Ubuntu'),
      ]) {
        expect(probe.found, isFalse);
        expect(probe.failure, WslProbeFailure.smokeContractInvalid);
        expect(probe.failureDetail, contains('HARNESS_SMOKE_'));
      }
      final ran = await wsl.runIn(distro: 'Ubuntu', script: 'echo ok');
      expect(ran.exitCode, 125);
      expect(await wsl.computerId(distro: 'Ubuntu'), isNull);
      expect(await wsl.hasTmux(distro: 'Ubuntu'), isFalse);
      expect(calls, isEmpty);
    },
  );

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
      expectCommandsRefused({...contract, ...change});
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
