import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/companion_agents.dart';
import 'package:harness/widgets/companion_agent_dialog.dart';

class _Companion extends DeepSeekCompanion {
  @override
  bool running = false;
  @override
  bool starting = false;
  @override
  String status = 'Not running';
  @override
  Uri? launchUri;
  @override
  String? distro;
  @override
  String? folder;

  @override
  Future<void> start({required String distro, required String folder}) async {
    this.distro = distro;
    this.folder = folder;
    running = true;
    status = 'Ready';
    launchUri = Uri.parse('http://127.0.0.1:43001/?token=fixture-secret');
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    running = false;
    launchUri = null;
    status = 'Stopped';
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'a dismissed companion cannot pop its parent when launch finishes late',
    (tester) async {
      final launch = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              child: const Text('Open draft'),
              onPressed: () => showDialog<String>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Managed draft'),
                  actions: [
                    TextButton(
                      child: const Text('Companion'),
                      onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (_) => CompanionAgentDialog(
                          agent: 'zcode-desktop',
                          closeOnLaunch: true,
                          openZcode: () => launch.future,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Companion'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open ZCode'));
      await tester.pump();
      Navigator.of(tester.element(find.byType(CompanionAgentDialog))).pop();
      // Still mounted during the reverse transition; completing now used to pop
      // the String-typed parent route with a bool and discard the draft.
      launch.complete();
      await tester.pumpAndSettle();
      expect(find.text('Managed draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a browser handoff closes only after a successful OS launch', (
    tester,
  ) async {
    final service = _Companion();
    addTearDown(service.dispose);
    bool? result;
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => CompanionAgentDialog(
                  agent: 'deepseek-web',
                  companion: service,
                  closeOnLaunch: true,
                  initialFolder: '/work/example',
                  loadDistros: () async => ['Ubuntu'],
                  openBrowser: (_) async => ++attempts > 1,
                ),
              );
            },
            child: const Text('Open companion'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open companion'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start and open browser'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('Could not open your browser'), findsOneWidget);
    await tester.tap(find.text('Open browser'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(find.byType(CompanionAgentDialog), findsNothing);
    expect(service.running, isTrue);
  });

  testWidgets(
    'starts selected workspace, retries a private browser failure, and stops',
    (tester) async {
      final service = _Companion();
      addTearDown(service.dispose);
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CompanionAgentDialog(
            agent: 'deepseek-web',
            initialFolder: '/home/user/project with spaces',
            companion: service,
            loadDistros: () async => ['Ubuntu', 'Debian'],
            openBrowser: (uri) async {
              opened.add(uri);
              if (opened.length == 1) throw StateError('Browser refused $uri');
              return true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start and open browser'));
      await tester.pumpAndSettle();
      expect(service.distro, 'Ubuntu');
      expect(service.folder, '/home/user/project with spaces');
      expect(opened.single, service.launchUri);
      expect(find.textContaining('fixture-secret'), findsNothing);
      expect(find.text('Open browser'), findsOneWidget);
      expect(
        find.textContaining('Could not open your browser'),
        findsOneWidget,
      );
      expect(service.running, isTrue);
      await tester.tap(find.text('Open browser'));
      await tester.pumpAndSettle();
      expect(opened.length, 2);
      expect(find.textContaining('Could not open your browser'), findsNothing);
      await tester.tap(find.text('Stop server'));
      await tester.pumpAndSettle();
      expect(service.running, isFalse);
      expect(service.launchUri, isNull);
    },
  );

  testWidgets('cannot launch without an installed WSL distribution', (
    tester,
  ) async {
    final service = _Companion();
    addTearDown(service.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: CompanionAgentDialog(
          agent: 'deepseek-web',
          initialFolder: '/home/user/project',
          companion: service,
          loadDistros: () async => [],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Start and open browser'),
          )
          .onPressed,
      isNull,
    );
    expect(find.textContaining('Set up a WSL2'), findsOneWidget);
  });

  testWidgets('ZCode opens its app without starting a DeepSeek server', (
    tester,
  ) async {
    final service = _Companion();
    addTearDown(service.dispose);
    var launches = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CompanionAgentDialog(
          agent: 'zcode-desktop',
          companion: service,
          openZcode: () async {
            launches++;
          },
        ),
      ),
    );
    await tester.tap(find.text('Open ZCode'));
    await tester.pumpAndSettle();
    expect(launches, 1);
    expect(service.running, isFalse);
    expect(find.textContaining('ZCode runs in its own window'), findsOneWidget);
  });
}
