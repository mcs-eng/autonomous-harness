import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/wsl_runtime.dart';
import 'package:harness/core/wsl_preferences.dart';
import 'package:harness/core/wsl_smoke_isolation.dart';

/// Verifies argv only against an explicitly selected disposable WSL fixture.
///
/// The unit suite injects fake process hooks, so it can never see what
/// `wsl.exe` does to the command line it is handed — and `--` handing the
/// remainder to the distro's default shell for a second parse round silently
/// stripped every argument the app sent (the CLI answered the help banner with
/// exit 0). This file runs the ACTUAL shape `buildArguments` produces against
/// an actual distro and asserts the arguments arrive. Ordinary unit runs must
/// never enter an account's default login shell or load its real startup files.
/// Supply the smoke contract plus HARNESS_TEST_WSL_ARGV=1 and explicit
/// HARNESS_TEST_WSL_DISTRO / HARNESS_TEST_WSL_USER to opt in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = Platform.environment;
  final optedIn =
      environment['HARNESS_TEST_WSL_ARGV'] == '1' &&
      WslSmokeIsolation.keys.every(
        (key) => environment[key]?.isNotEmpty == true,
      ) &&
      environment['HARNESS_TEST_WSL_DISTRO']?.isNotEmpty == true &&
      environment['HARNESS_TEST_WSL_USER']?.isNotEmpty == true;

  test(
    'buildArguments delivers argv to the distro shell intact',
    () async {
      final distro = environment['HARNESS_TEST_WSL_DISTRO']!;
      final runtime = WslRuntime(
        selection: WslSelection(
          distro: distro,
          username: environment['HARNESS_TEST_WSL_USER']!,
        ),
      );
      if (!Platform.isWindows) {
        markTestSkipped('Windows-to-WSL fixture requires a Windows host.');
        return;
      }
      if (!await runtime.available()) {
        markTestSkipped('WSL is unavailable; no argv behavior was exercised.');
        return;
      }
      final distros = await runtime.usableDistros();
      if (!distros.contains(distro)) {
        markTestSkipped(
          'The explicitly selected fixture distro is unavailable.',
        );
        return;
      }

      final marker = runtime.buildArguments(
        distro: distro,
        script: r'echo "count=$#; zero=$0; one=$1; two=$2"',
        scriptName: 'probe-name',
        scriptArguments: ['first arg', 'second arg'],
      );

      final result = await Process.run(WslRuntime.executable, marker);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(
        '${result.stdout}'.trim(),
        contains('count=2; zero=probe-name; one=first arg; two=second arg'),
        reason:
            'wsl must deliver the -c script and its \$0-trailing arguments '
            'verbatim; a second shell parse round strips them',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: optedIn ? false : 'Requires explicit disposable WSL smoke contract and account selection.',
  );
}
