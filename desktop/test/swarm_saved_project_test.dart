import 'dart:async';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/widgets/app_select_field.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/widgets/swarm_dialogs.dart';
import 'package:harness/ws/local_cli_discovery.dart';

import 'swarm_state_test.dart' show createApp;

class _Folders extends FileSelectorPlatform {
  _Folders({this.pick});
  final Future<String?> Function()? pick;
  int calls = 0;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    calls++;
    return pick == null ? '/work/autonomous-harness/' : pick!();
  }
}

class _BackendFolders extends AppNotifier {
  _BackendFolders()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      ) {
    machineStates['local'] = MachineState(
      const Machine(
        machineId: 'local',
        name: 'Local computer',
        authMode: MachineAuthMode.self,
      ),
    )..localOnly = true;
    debugSetLocalCliInWsl(true);
    debugLocalCliWslDistro = 'Ubuntu';
  }

  final requests = <({String machine, String? path})>[];

  @override
  Future<Map<String, dynamic>> listRemoteFolder(
    String machineId,
    String? path,
  ) async {
    requests.add((machine: machineId, path: path));
    return {'path': '/home/ana/fictional-project', 'entries': <Object>[]};
  }
}

Future<void> _openProjectDialog(
  WidgetTester tester,
  AppNotifier app,
  ValueChanged<SavedSwarmProject?> onResult,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async =>
              onResult(await showSwarmProjectDialog(context, app)),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'a local WSL project browses the backend filesystem and cannot clone natively',
    (tester) async {
      final original = FileSelectorPlatform.instance;
      final native = _Folders();
      FileSelectorPlatform.instance = native;
      addTearDown(() => FileSelectorPlatform.instance = original);
      final app = _BackendFolders();
      addTearDown(app.dispose);
      SavedSwarmProject? saved;
      await _openProjectDialog(tester, app, (value) => saved = value);
      expect(find.text('Clone repository…'), findsNothing);
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();
      expect(app.requests, [(machine: 'local', path: null)]);
      expect(native.calls, 0);
      await tester.tap(find.text('Select this folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
      await tester.pumpAndSettle();
      expect(saved!.machineId, 'local');
      expect(saved!.path, '/home/ana/fictional-project');
    },
    skip: !Platform.isWindows,
  );

  for (final folder in [
    r'C:\work\fictional-project',
    r'\\wsl.localhost\Debian\home\ana\fictional-project',
  ]) {
    testWidgets(
      'late WSL discovery converts or refuses the selected GUI path: $folder',
      (tester) async {
        final app = _BackendFolders()..debugSetLocalCliInWsl(false);
        addTearDown(app.dispose);
        final original = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = _Folders(pick: () async => folder);
        addTearDown(() => FileSelectorPlatform.instance = original);
        SavedSwarmProject? saved;
        await _openProjectDialog(tester, app, (value) => saved = value);
        await tester.tap(find.text('Choose folder'));
        await tester.pumpAndSettle();
        // The backend identity settles after the native picker returned.
        app.debugSetLocalCliInWsl(true);
        await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
        await tester.pumpAndSettle();
        if (folder.startsWith('C:')) {
          expect(saved!.path, '/mnt/c/work/fictional-project');
          expect(saved!.machineId, 'local');
        } else {
          expect(saved, isNull);
          expect(find.textContaining('WSL2 (Ubuntu)'), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Add project'),
                )
                .onPressed,
            isNull,
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
      skip: !Platform.isWindows,
    );
  }

  testWidgets('a picker result cannot follow a changed machine', (
    tester,
  ) async {
    final app = _BackendFolders()..debugSetLocalCliInWsl(false);
    addTearDown(app.dispose);
    app.machineStates['other'] = MachineState(
      const Machine(machineId: 'other', authMode: MachineAuthMode.remote),
    );
    final result = Completer<String?>();
    final original = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _Folders(pick: () => result.future);
    addTearDown(() => FileSelectorPlatform.instance = original);
    await _openProjectDialog(tester, app, (_) {});
    await tester.tap(find.text('Choose folder'));
    await tester.pump();
    tester
        .widget<AppSelectField<String>>(find.byType(AppSelectField<String>))
        .onChanged('other');
    await tester.pump();
    result.complete('/work/old-machine');
    await tester.pumpAndSettle();
    expect(find.text('/work/old-machine'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Add project'),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
  });

  test(
    'an explicitly added folder names the group across aliased checkouts',
    () {
      final app = createApp();
      app.machineStates['m']!.localEndpoint = LocalCliEndpoint(
        computerId: 'local',
        wsUri: Uri.parse('ws://fixture.invalid'),
        protocolVersion: 1,
        terminalProtocolVersion: 3,
        agentProjects: const {
          'a0': AgentProject(
            name: 'harness-app-v2',
            cwd: '/work/harness-app-v2',
            remote: 'https://github.com/autonomous-ai/openharness.git',
          ),
          'a1': AgentProject(
            name: 'autonomous-harness',
            cwd: '/work/autonomous-harness',
            remote: 'https://github.com/autonomous-ai/openharness.git',
          ),
        },
      );
      final groups = swarmProjects(app, const [
        SavedSwarmProject(
          machineId: 'm',
          path: '/work/autonomous-harness',
          name: 'autonomous-harness',
        ),
      ]);
      expect(groups, hasLength(1));
      expect(groups.single.name, 'autonomous-harness');
      expect(groups.single.agents.map((a) => a.agent.id), ['a0', 'a1']);
      app.dispose();
    },
  );

  testWidgets('adding a project derives its name from the selected folder', (
    tester,
  ) async {
    final original = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _Folders();
    addTearDown(() => FileSelectorPlatform.instance = original);
    final app = createApp();
    app.machineStates['m']!.localEndpoint = LocalCliEndpoint(
      computerId: 'local',
      wsUri: Uri.parse('ws://fixture.invalid'),
      protocolVersion: 1,
      terminalProtocolVersion: 3,
    );
    SavedSwarmProject? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              saved = await showSwarmProjectDialog(context, app);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Choose folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add project'));
    await tester.pumpAndSettle();
    expect(saved!.name, 'autonomous-harness');
    expect(saved!.path, '/work/autonomous-harness/');
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
