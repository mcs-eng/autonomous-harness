import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/auth/cli_login.dart';
import 'package:harness/bootstrap/environment_provisioner.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/wsl_preferences.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/app_state.dart';
import 'package:harness/widgets/environment_setup_screen.dart';

const _review = EnvironmentReadiness(
  steps: {
    EnvironmentStep.clipboard: EnvironmentStepStatus.notApplicable,
    EnvironmentStep.tmux: EnvironmentStepStatus.failed,
    EnvironmentStep.harness: EnvironmentStepStatus.failed,
  },
  phase: EnvironmentSetupPhase.review,
  // Nothing on this computer — the longest plan the screen renders on macOS.
  plan: [EnvironmentPlanItem.tmuxManaged, EnvironmentPlanItem.harnessCli],
);

class _MemoryPreferences implements LocalKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Login extends CliLogin {
  @override
  Future<CliAuthStatus> checkStatus() async =>
      const CliAuthStatus(loggedIn: false);
}

class _Attempt {
  _Attempt(this.install, this.progress);
  final bool install;
  final void Function(EnvironmentReadiness) progress;
  final result = Completer<EnvironmentReadiness>();
  void finish(EnvironmentReadiness state) {
    progress(state);
    result.complete(state);
  }
}

class _Provisioner extends EnvironmentProvisioner {
  _Provisioner() : super(isMacOS: true);
  final attempts = <_Attempt>[];
  @override
  Future<EnvironmentReadiness> ensureReady({
    required void Function(EnvironmentReadiness) onProgress,
    EnvironmentReadiness? resumeFrom,
    bool install = true,
    EnvironmentSetupMode? mode,
  }) {
    final attempt = _Attempt(install, onProgress);
    attempts.add(attempt);
    onProgress(
      (resumeFrom ?? _review).copyWith(
        phase: install
            ? EnvironmentSetupPhase.installing
            : EnvironmentSetupPhase.preflight,
      ),
    );
    return attempt.result.future;
  }
}

Future<void> _mount(
  WidgetTester tester,
  AppNotifier app, {
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(880, 560);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: grid
          .buildAppTheme(brightness: Brightness.dark)
          .copyWith(platform: TargetPlatform.macOS),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: true,
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: ListenableBuilder(
        listenable: app,
        builder: (_, _) => app.status == AppStatus.unauthenticated
            ? const Scaffold(body: Text('Sign-in reached'))
            : EnvironmentSetupScreen(notifier: app),
      ),
    ),
  );
  await tester.pump();
}

AppNotifier _app(_Provisioner provisioner) =>
    AppNotifier(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
        cliLogin: _Login(),
        environmentProvisioner: provisioner,
      )
      ..status = AppStatus.preparingEnvironment
      ..environmentReadiness = _review;

void main() {
  testWidgets(
    'inconclusive Windows setup offers recheck and blocks work after account change',
    (tester) async {
      final provisioner = _Provisioner();
      final app = _app(provisioner)
        ..environmentReadiness = const EnvironmentReadiness(
          windowsHost: true,
          steps: {
            EnvironmentStep.clipboard: EnvironmentStepStatus.notApplicable,
            EnvironmentStep.tmux: EnvironmentStepStatus.unavailable,
            EnvironmentStep.harness: EnvironmentStepStatus.unavailable,
          },
          phase: EnvironmentSetupPhase.failed,
          failure: EnvironmentFailure(
            title: 'Could not check Linux tools',
            detail: 'Recheck the Linux connection.',
          ),
        );
      final store = WslPreferencesStore(storage: _MemoryPreferences());
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: EnvironmentSetupScreen(notifier: app, wslPreferences: store),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not checked'), findsNWidgets(2));
      expect(find.text('Missing'), findsNothing);
      expect(find.text('Switch to Manual'), findsNothing);
      await store.save(
        const WslSelection(distro: 'Ubuntu', username: 'developer'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Reopen OpenHarness to continue'), findsOneWidget);
      final recheck = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Recheck'),
      );
      expect(recheck.onPressed, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(provisioner.attempts, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets('manual setup keeps keyboard focus and never starts an install', (
    tester,
  ) async {
    final provisioner = _Provisioner();
    final app = _app(provisioner);
    await _mount(tester, app);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.environmentReadiness.mode, EnvironmentSetupMode.manual);
    expect(find.text('Check again').hitTestable(), findsOneWidget);
    // The method button retains focus when its label changes. Enter again
    // switches back instead of accidentally running the newly enabled action.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.environmentReadiness.mode, EnvironmentSetupMode.automatic);
    expect(provisioner.attempts, isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('Retry after manual setup failure remains a read-only check', (
    tester,
  ) async {
    final provisioner = _Provisioner();
    final app = _app(provisioner)
      ..environmentReadiness = _review.copyWith(
        phase: EnvironmentSetupPhase.failed,
        mode: EnvironmentSetupMode.manual,
      );
    await _mount(tester, app);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(provisioner.attempts, hasLength(1));
    expect(provisioner.attempts.single.install, isFalse);
    provisioner.attempts.single.finish(
      _review.copyWith(mode: EnvironmentSetupMode.manual),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Check again').hitTestable(), findsOneWidget);
    expect(app.environmentReadiness.mode, EnvironmentSetupMode.manual);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('setup details can expand and copy without hiding Retry', (
    tester,
  ) async {
    final provisioner = _Provisioner();
    final diagnostics = List.generate(40, (i) => 'Installer output line $i');
    final app = _app(provisioner)
      ..environmentReadiness = _review.copyWith(
        phase: EnvironmentSetupPhase.failed,
        failure: const EnvironmentFailure(
          title: 'Could not install Harness',
          detail: 'Check your connection, then retry setup.',
        ),
        output: diagnostics,
      );
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _mount(tester, app);
    expect(find.byType(SelectableText), findsNothing);
    await tester.ensureVisible(find.text('Setup details'));
    await tester.tap(find.text('Setup details'));
    await tester.pump();
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Retry').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Copy diagnostics'));
    await tester.pump();
    expect(clipboard, diagnostics.join('\n'));
    expect(find.text('Copied'), findsOneWidget);
    expect(provisioner.attempts, isEmpty);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('setup actions stay visible at minimum size with $scale text', (
      tester,
    ) async {
      final provisioner = _Provisioner();
      final app = _app(provisioner);
      addTearDown(app.dispose);
      await _mount(tester, app, textScale: scale);
      expect(find.text('Install 2 tools').hitTestable(), findsOneWidget);
      expect(provisioner.attempts, isEmpty);
      app.environmentReadiness = _review.copyWith(
        phase: EnvironmentSetupPhase.failed,
        failure: const EnvironmentFailure(
          title: 'Could not install Harness',
          detail: 'Check your connection, then retry setup.',
        ),
        output: List.generate(40, (i) => 'Installer output line $i'),
      );
      app.notifyListeners();
      await tester.pump();
      expect(find.text('Retry').hitTestable(), findsOneWidget);
      expect(find.text('Switch to Manual').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Enter installs and retries once before reaching sign-in', (
    tester,
  ) async {
    final provisioner = _Provisioner();
    final app = _app(provisioner);
    await _mount(tester, app);
    expect(provisioner.attempts, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(provisioner.attempts, hasLength(1));
    expect(provisioner.attempts.single.install, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(provisioner.attempts, hasLength(1));
    provisioner.attempts.single.finish(
      _review.copyWith(
        phase: EnvironmentSetupPhase.failed,
        failure: const EnvironmentFailure(
          title: 'Could not install Harness',
          detail: 'Check your connection, then retry setup.',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(provisioner.attempts, hasLength(2));
    provisioner.attempts.last.finish(
      const EnvironmentReadiness(
        steps: {
          EnvironmentStep.clipboard: EnvironmentStepStatus.notApplicable,
          EnvironmentStep.tmux: EnvironmentStepStatus.ready,
          EnvironmentStep.harness: EnvironmentStepStatus.ready,
        },
        phase: EnvironmentSetupPhase.ready,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Sign-in reached'), findsOneWidget);
    expect(provisioner.attempts.map((attempt) => attempt.install), [
      true,
      true,
    ]);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
