import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/api/api_client.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/auth/cli_login.dart';
import 'package:harness/bootstrap/environment_provisioner.dart';
import 'package:harness/core/config.dart';
import 'package:harness/screens/login_screen.dart';
import 'package:harness/settings/sections/account_section.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/ws/local_cli_discovery.dart';
import 'package:harness/ws/ws_conn.dart';

/// Local mode, as this fork labels it: upstream's guest desk.
///
/// A signed-out desktop window opens on this computer's desk, and an account
/// is asked for only when another machine is reached for. The fork adds two
/// things on top: the labels ("Local mode") and, on the login screen a desktop
/// window can still meet (a cancelled or failed sign-in, a CLI that could not
/// answer), the way back to that desk.

/// The CLI's answer to `auth status --json`, scripted; never a real process.
class _ScriptedCli extends CliLogin {
  _ScriptedCli(this.answer);

  CliAuthStatus answer;
  int checks = 0;
  int logouts = 0;

  @override
  Future<CliAuthStatus> checkStatus() async {
    checks++;
    return answer;
  }

  @override
  Future<void> logout() async {
    logouts++;
    answer = const CliAuthStatus(loggedIn: false);
  }
}

class _ReadyProvisioner extends EnvironmentProvisioner {
  _ReadyProvisioner() : super(isMacOS: true);

  @override
  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness value) onProgress,
    EnvironmentReadiness? resumeFrom,
    bool install = true,
    EnvironmentSetupMode? mode,
  }) async {
    final ready = EnvironmentReadiness(
      steps: {
        for (final step in EnvironmentStep.values)
          step: EnvironmentStepStatus.ready,
      },
      phase: EnvironmentSetupPhase.ready,
    );
    onProgress(ready);
    return ready;
  }
}

/// A daemon that is up at once, with the supervisor stubbed out.
class _ReadyDiscovery extends LocalCliDiscovery {
  _ReadyDiscovery() : super(config: AppConfig.dev);

  Timer? supervision;

  @override
  Future<LocalCliProbe> ensureRunning({
    Duration timeout = const Duration(seconds: 15),
    Duration readyTimeout = LocalCliDiscovery.defaultReadyTimeout,
  }) async => LocalCliProbe.ready(_endpoint);

  @override
  Timer startSupervising({
    Duration checkInterval = const Duration(seconds: 5),
    Duration graceStep = const Duration(milliseconds: 500),
    Duration graceWindow = const Duration(seconds: 5),
    Duration initialBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 30),
    int spawnAfter = 2,
    bool Function(DateTime now)? spawnAllowedAt,
    Future<bool> Function()? stillSignedIn,
    void Function()? onSignedOut,
    void Function(LocalCliEndpoint endpoint)? onReady,
    void Function(LocalCliEndpoint endpoint)? onSnapshot,
    void Function(bool online)? onBackendOnline,
  }) => supervision = Timer(const Duration(days: 1), () {});
}

/// A socket that answers nothing: the load a connect triggers must not reach for a real pool.
class _QuietConnection extends WsConn {
  _QuietConnection()
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: 'm-local',
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  @override
  Future<void> waitUntilReady({required Duration timeout}) async {}

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async => const {'agents': []};
}

/// Counts the profile reads instead of making them.
class _CountingApi extends ApiClient {
  _CountingApi() : super(config: AppConfig.dev, session: AuthSession());

  int meCalls = 0;

  @override
  Future<Map<String, dynamic>?> me() async {
    meCalls++;
    return null;
  }
}

class _Notifier extends AppNotifier {
  _Notifier({required this.discovery, required CliLogin cli})
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
        localCliDiscovery: discovery,
        cliLogin: cli,
        environmentProvisioner: _ReadyProvisioner(),
        connectionForTest: (_) => _QuietConnection(),
      ) {
    api = profileReads;
  }

  final _ReadyDiscovery discovery;
  final profileReads = _CountingApi();
  int refreshes = 0;

  @override
  Future<bool> refreshMachines() async {
    refreshes++;
    return true;
  }

  @override
  void dispose() {
    discovery.supervision?.cancel();
    super.dispose();
  }
}

final _endpoint = LocalCliEndpoint(
  computerId: '0123456789abcdef0123456789abcdef',
  wsUri: Uri.parse('ws://127.0.0.1:18473/api/local-ws'),
  protocolVersion: 1,
  terminalProtocolVersion: 3,
  machineId: '0123456789abcdef0123456789abcdef',
  backendOnline: false,
);

Widget _host(AppNotifier app, Widget Function() child) => MaterialApp(
  theme: grid.buildAppTheme(brightness: Brightness.light),
  home: MediaQuery(
    data: const MediaQueryData(size: Size(880, 560)),
    child: grid.BrightnessScope(
      child: ListenableBuilder(listenable: app, builder: (_, _) => child()),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the login screen\'s way back to this computer', () {
    test(
      'a signed-out CLI lands on the guest desk, with no profile read',
      () async {
        final app = _Notifier(
          discovery: _ReadyDiscovery(),
          cli: _ScriptedCli(const CliAuthStatus(loggedIn: false)),
        );
        addTearDown(app.dispose);
        // Where a cancelled sign-in leaves a desktop window.
        app.status = AppStatus.unauthenticated;

        await app.continueWithoutAccount();

        expect(app.status, AppStatus.authenticated);
        expect(app.isGuest, isTrue);
        expect(app.currentUser, isNull);
        expect(app.profileReads.meCalls, 0);
        expect(app.refreshes, 1);
      },
    );

    test('a CLI that signed in meanwhile lands on the account desk', () async {
      final app = _Notifier(
        discovery: _ReadyDiscovery(),
        cli: _ScriptedCli(const CliAuthStatus(loggedIn: true)),
      );
      addTearDown(app.dispose);
      app.status = AppStatus.unauthenticated;

      await app.continueWithoutAccount();

      expect(app.status, AppStatus.authenticated);
      expect(app.isGuest, isFalse);
      expect(app.profileReads.meCalls, 1);
    });

    testWidgets('the wall offers it, and the tap opens the desk', (
      tester,
    ) async {
      grid.AppTheme.brightness.value = Brightness.light;
      final app = _Notifier(
        discovery: _ReadyDiscovery(),
        cli: _ScriptedCli(const CliAuthStatus(loggedIn: false)),
      );
      addTearDown(app.dispose);
      app.status = AppStatus.unauthenticated;

      await tester.pumpWidget(_host(app, () => LoginScreen(notifier: app)));

      final door = find.byKey(const Key('use-without-account-button'));
      expect(door, findsOneWidget);
      expect(find.text('Use this computer without an account'), findsOneWidget);
      await tester.tap(door);
      // Not pumpAndSettle: the fleet diagram on this screen animates for as
      // long as it is shown, so the frame never settles. Pump until the boot
      // lands, bounded.
      for (var i = 0; i < 40 && app.status != AppStatus.authenticated; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(app.status, AppStatus.authenticated);
      expect(app.isGuest, isTrue);
      // The stub supervisor's timer would otherwise still be pending when the
      // fake clock is checked at the end of this test.
      app.discovery.supervision?.cancel();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the sheet over the desk does not repeat it', (tester) async {
      grid.AppTheme.brightness.value = Brightness.light;
      final app = _Notifier(
        discovery: _ReadyDiscovery(),
        cli: _ScriptedCli(const CliAuthStatus(loggedIn: false)),
      );
      addTearDown(app.dispose);

      // The sheet is the screen with a close button; its X is the way back.
      await tester.pumpWidget(
        _host(app, () => LoginScreen(notifier: app, onClose: () {})),
      );

      expect(find.byKey(const Key('login-close-button')), findsOneWidget);
      expect(find.byKey(const Key('use-without-account-button')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  test(
    'signing out keeps a desktop window on its desk, in local mode',
    () async {
      final cli = _ScriptedCli(const CliAuthStatus(loggedIn: true));
      final app = _Notifier(discovery: _ReadyDiscovery(), cli: cli)
        ..status = AppStatus.authenticated;
      addTearDown(app.dispose);
      expect(app.isGuest, isFalse);

      await app.logout();
      // The desk is sat back down in the background once the daemon answers.
      for (var i = 0; i < 100 && app.refreshes == 0; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(cli.logouts, 1);
      expect(app.status, AppStatus.authenticated);
      expect(app.isGuest, isTrue);
      expect(app.signOutError, isNull);
      expect(app.refreshes, 1);
    },
  );

  testWidgets('Settings names local mode and offers the sign-in', (
    tester,
  ) async {
    grid.AppTheme.brightness.value = Brightness.light;
    final app = _Notifier(
      discovery: _ReadyDiscovery(),
      cli: _ScriptedCli(const CliAuthStatus(loggedIn: false)),
    )..signedIn = false;
    addTearDown(app.dispose);

    await tester.pumpWidget(
      _host(app, () => Scaffold(body: AccountSection(notifier: app))),
    );

    expect(find.text('Local mode'), findsOneWidget);
    expect(find.byKey(const Key('settings-sign-in-button')), findsOneWidget);
    expect(find.byKey(const Key('settings-sign-out-button')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
