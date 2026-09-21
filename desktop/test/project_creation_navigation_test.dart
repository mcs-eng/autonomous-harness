import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/widgets/app_icon_button.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/ws/ws_conn.dart';

import 'swarm_screen_test.dart' show mount, terminal;

class _Connection extends WsConn {
  _Connection(String machineId)
    : super(
        wsBaseUrl: 'ws://fixture.invalid',
        autonomousEnv: 'test',
        machineId: machineId,
        accessTokenProvider: (_, _) async => '',
        onAuthFailure: (_) {},
        onEvent: (_) {},
        onStatus: (_) {},
      );

  final creations = <Map<String, dynamic>>[];

  @override
  Future<Map<String, dynamic>> request(
    String type, {
    Map<String, dynamic> payload = const {},
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (type == 'dsh_list') return {'dsh': <Object>[]};
    if (type != 'agent_create') {
      throw StateError('Unexpected fixture request: $type');
    }
    creations.add(Map.of(payload));
    return {
      'creationId': payload['creationId'],
      'state': 'created',
      'agent': {
        'id': 'created-second',
        'name': 'Fictional second project agent',
        'engine': payload['engine'],
        'project': {'name': 'Second project', 'cwd': payload['cwd']},
        'terminal': {'available': true},
      },
    };
  }
}

class _App extends AppNotifier {
  _App(Map<String, _Connection> connections)
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
        connectionForTest: (id) => connections[id]!,
      ) {
    for (final id in ['m', 'second']) {
      final machine = Machine(
        machineId: id,
        name: id == 'm' ? 'First host' : 'Second host',
        authMode: MachineAuthMode.remote,
      );
      machines.add(machine);
      machineStates[id] = MachineState(machine)
        ..localOnly = id == 'm'
        ..nodeOnline = true
        ..connectionStatus = ConnectionStatus.connected
        ..agentLoadStatus = AgentLoadStatus.loaded;
    }
    machineStates['m']!.agents = const [
      Agent(
        id: 'original',
        name: 'Original work',
        engine: 'codex',
        terminalAvailable: true,
        project: AgentProject(name: 'First project', cwd: '/work/first'),
      ),
    ];
  }

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {}
}

void main() {
  const secondFolder = '/srv/fictional-second';

  Future<
    ({
      _App app,
      SwarmProjectStore projects,
      Map<String, _Connection> connections,
    })
  >
  prepare(WidgetTester tester) async {
    final connections = {
      for (final id in ['m', 'second']) id: _Connection(id),
    };
    final app = _App(connections);
    app.adoptSessionForTest(terminal('original', []));
    app.renameSwarm(app.activeSwarmId, 'First project');
    await app.agentPreference.select('claude');
    final projects = SwarmProjectStore();
    await projects.add(
      const SavedSwarmProject(
        machineId: 'second',
        path: secondFolder,
        name: 'Second project',
      ),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      app.dispose();
      projects.dispose();
    });
    return (app: app, projects: projects, connections: connections);
  }

  testWidgets(
    'New agent here launches on the second host in its exact folder',
    (tester) async {
      final (:app, :projects, :connections) = await prepare(tester);
      final original = app.activeSwarm;
      final originalPane = app.focusedPane;
      await mount(tester, app, projects: projects, size: const Size(1600, 800));
      await tester.tap(
        find.byKey(const ValueKey('new-project-agent:second:$secondFolder')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
      // The fixture intentionally has no terminal transport. Its waiting
      // indicator animates; the receipt and pane placement still complete.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(connections['m']!.creations, isEmpty);
      final payload = connections['second']!.creations.single;
      expect(payload['cwd'], secondFolder);
      expect(payload['engine'], 'claude');
      expect(payload.containsKey('projectSource'), isFalse);
      expect(original.panes, [originalPane]);
      expect(originalPane!.machineId, 'm');
      expect(originalPane.agentId, 'original');
      expect(app.activeSwarm, isNot(same(original)));
      expect(app.focusedPane!.machineId, 'second');
      expect(app.focusedPane!.agentId, 'created-second');
      expect(app.swarms, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel restores work and unavailable hosts cannot create agents',
    (tester) async {
      final (:app, :projects, :connections) = await prepare(tester);
      for (final id in ['offline', 'shared']) {
        final machine = Machine(
          machineId: id,
          name: '$id host',
          authMode: MachineAuthMode.remote,
          isShared: id == 'shared',
        );
        app.machines.add(machine);
        app.machineStates[id] = MachineState(machine)
          ..nodeOnline = id != 'offline'
          ..connectionStatus = ConnectionStatus.connected;
        await projects.add(
          SavedSwarmProject(machineId: id, path: '/work/$id', name: id),
        );
      }
      final original = app.activeSwarm;
      final originalPane = app.focusedPane;
      await mount(tester, app, projects: projects, size: const Size(1600, 800));
      for (final id in ['offline', 'shared']) {
        final button = tester.widget<AppIconButton>(
          find.byKey(ValueKey('new-project-agent:$id:/work/$id')),
        );
        expect(button.onPressed, isNull);
      }
      await tester.tap(
        find.byKey(const ValueKey('new-project-agent:second:$secondFolder')),
      );
      await tester.pumpAndSettle();
      expect(app.swarms, hasLength(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(app.swarms, [original]);
      expect(app.activeSwarm, same(original));
      expect(app.focusedPane, same(originalPane));
      expect(connections.values.expand((c) => c.creations), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
