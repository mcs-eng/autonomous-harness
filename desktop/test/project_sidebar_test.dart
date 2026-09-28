import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/shared/widgets/app_icon_button.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/state/project_navigation.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/state/terminal_pane.dart';
import 'package:harness/widgets/agent_drag.dart';
import 'package:harness/widgets/pane_grid.dart';
import 'package:harness/widgets/project_sidebar.dart';

import 'swarm_attention_test.dart' show waitingQuestion;
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;

AppNotifier projectApp() {
  final app = createApp();
  final host = app.machineStates['m']!;
  host.agents = host.agents.take(2).toList();
  host.localProjects = const {
    'a0': AgentProject(name: 'Notebook', cwd: '/work/notebook', branch: 'main'),
    'a1': AgentProject(name: 'Notebook', cwd: '/work/copy', branch: 'review'),
  };
  return app;
}

Future<void> mountSidebar(
  WidgetTester tester,
  AppNotifier app, {
  SwarmProjectStore? projects,
  ValueChanged<ProjectLocation>? onNew,
  ValueChanged<SwarmAgentRef>? onOpen,
  VoidCallback? onShowMachines,
  VoidCallback? onSignIn,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: grid.buildAppTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: SizedBox(
          width: 280,
          child: ProjectSidebar(
            app: app,
            projects: projects ?? SwarmProjectStore(),
            onAddProject: () {},
            onNewProject: () {},
            onCollapse: () {},
            onNewAgent: onNew ?? (_) {},
            onOpenAgent: onOpen ?? (_) {},
            onShowMachines: onShowMachines ?? () {},
            onSignIn: onSignIn ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'an unavailable session exposes its reason without creating an agent',
    (tester) async {
      final app = projectApp();
      addTearDown(app.dispose);
      app.machineStates['m']!
        ..nodeOnline = true
        ..connectionStatus = ConnectionStatus.connected
        ..agents = const [
          Agent(
            id: 'failed',
            name: 'Unavailable session',
            terminalAvailable: false,
            terminalUnavailableReason: 'The terminal process has exited.',
          ),
        ];
      var opens = 0;
      await mountSidebar(tester, app, onOpen: (_) => opens++);
      await tester.tap(find.byKey(const ValueKey('project-agent:m:failed')));
      await tester.pumpAndSettle();
      expect(find.text('The terminal process has exited.'), findsOneWidget);
      expect(find.text('Refresh status'), findsOneWidget);
      expect(opens, 0);
      expect(app.panes, isEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    },
  );

  test('same-named folders remain separate and picker trailing slash does not duplicate a project', () {
    final app = projectApp();
    addTearDown(app.dispose);
    final groups = swarmProjects(app, const [
      SavedSwarmProject(
        machineId: 'm',
        path: '/work/notebook/',
        name: 'Notebook',
      ),
    ]);
    expect(groups, hasLength(2));
    final saved = groups.singleWhere((g) => g.saved != null);
    expect(saved.agents.single.agent.id, 'a0');
    expect(projectLocations(saved), [
      (machineId: 'm', folder: '/work/notebook'),
    ]);
    expect(projectFolderPath(r'/work/notebook\'), r'/work/notebook\');
    expect(projectFolderPath('C:\\'), 'C:\\');
  });

  test(
    'opening an existing terminal and companion viewer reuses its tab',
    () async {
      final app = projectApp();
      addTearDown(app.dispose);
      await app.addAgentToSwarm('m', 'a0');
      final original = app.activeSwarm;
      final terminal = original.panes.single;
      final viewer = TerminalPane(
        id: 500,
        machineId: 'm',
        kind: PaneKind.web,
        ownerAgentId: 'a0',
        url: 'http://fixture.invalid',
      );
      original.panes.add(viewer);
      app.newSwarm(name: 'Other project');
      final row = swarmAgents(app).first;
      await openProjectAgent(app, row);
      await openProjectAgent(app, row);
      expect(app.activeSwarm, same(original));
      expect(original.panes, [terminal, viewer]);
      expect(app.swarms, hasLength(2));
      expect(app.machineStates['m']!.agents, hasLength(2));
    },
  );

  test(
    'opening and reopening existing agents preserves other project panes',
    () async {
      final app = projectApp();
      addTearDown(app.dispose);
      final rows = swarmAgents(app);
      await openProjectAgent(app, rows.first);
      final firstTab = app.activeSwarm;
      await openProjectAgent(app, rows.last);
      expect(app.activeSwarm, isNot(same(firstTab)));
      expect(firstTab.panes.single.agentId, 'a0');
      await app.closePane(app.focusedPaneId!);
      expect(app.machineStates['m']!.agents, hasLength(2));
      await openProjectAgent(app, rows.last);
      expect(app.allPanes.where((p) => p.agentId == 'a1'), hasLength(1));
      app.machineStates['m']!.agents.removeLast();
      final count = app.swarms.length;
      await openProjectAgent(app, rows.last);
      expect(app.swarms, hasLength(count));
    },
  );

  testWidgets(
    'repository checkouts show exact launch folders and current status',
    (tester) async {
      final app = projectApp();
      final host = app.machineStates['m']!;
      host.localProjects = const {
        'a0': AgentProject(
          name: 'Notebook',
          cwd: '/work/notebook',
          remote: 'example/repo',
          branch: 'main',
        ),
        'a1': AgentProject(
          name: 'Notebook',
          cwd: '/work/copy',
          remote: 'example/repo',
          branch: 'review',
        ),
      };
      host.nodeOnline = true;
      host.connectionStatus = ConnectionStatus.connected;
      host.processingAgentIds.add('a0');
      host.blockedAgents['a1'] = waitingQuestion('a1');
      ProjectLocation? chosen;
      await mountSidebar(tester, app, onNew: (location) => chosen = location);
      expect(find.text('Notebook'), findsOneWidget);
      expect(find.text('Working · main'), findsOneWidget);
      expect(find.text('Needs input · review'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('new-project-agent:m:/work/copy')),
      );
      expect(chosen, (machineId: 'm', folder: '/work/copy'));
      host.nodeOnline = false;
      await mountSidebar(tester, app);
      expect(find.text('Offline · main'), findsOneWidget);
      final button = tester.widget<AppIconButton>(
        find.byKey(const ValueKey('new-project-agent:m:/work/copy')),
      );
      expect(button.onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'filter and keyboard activation navigate without creating agents',
    (tester) async {
      final app = projectApp();
      String? opened;
      await mountSidebar(tester, app, onOpen: (row) => opened = row.agent.id);
      await tester.enterText(
        find.byKey(const ValueKey('project-filter')),
        'review',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('project-agent:m:a0')), findsNothing);
      // Tab from the filter traverses actions and the project header to the row.
      for (var i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(opened, 'a1');
      expect(app.machineStates['m']!.agents, hasLength(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'narrow workspace opens navigation in a drawer and keeps panes intact',
    (tester) async {
      final app = projectApp();
      app.adoptSessionForTest(terminal('a0', []));
      final pane = app.focusedPane;
      await mount(tester, app);
      tester.view.physicalSize = const Size(600, 800);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Projects'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('project-sidebar-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Projects'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('project-sidebar-machines')),
        findsOneWidget,
      );
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('project-agent:m:a0')).hitTestable(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isFalse,
      );
      expect(app.focusedPane, same(pane));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'generated folders and clock names stay out of the session list',
    (tester) async {
      final app = projectApp();
      addTearDown(app.dispose);
      final host = app.machineStates['m']!
        ..nodeOnline = true
        ..connectionStatus = ConnectionStatus.connected;
      // The automatic name says Codex; the label must come from the harness.
      const harness = Agent(
        id: 'notes',
        name: 'Codex harness 9-21 16:20',
        engine: 'codex',
        dsh: 'example/field-notes',
        dshName: 'Field Notes',
        terminalAvailable: true,
      );
      host.agents = const [harness];
      host.localProjects = const {
        'notes': AgentProject(name: 'agent-3', cwd: '/work/harnesses/agent-3'),
      };
      await mountSidebar(tester, app);
      // The project heading and its one session.
      expect(find.text('Field Notes'), findsNWidgets(2));
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('agent-3'), findsNothing);
      expect(find.text('Codex harness 9-21 16:20'), findsNothing);
      expect(find.text('/work/harnesses/agent-3'), findsNothing);
      expect(
        find.text('Closing a view keeps its agent running.'),
        findsOneWidget,
      );
      expect(projectAgentStatus(app, swarmAgents(app).single), 'Ready');
      // Dialogs and tabs keep the name a rename starts from.
      expect(harness.displayName, 'Untitled Pane');
      expect(sessionLabel(harness), 'Field Notes');

      // The engine exited; the daemon keeps the pane as a shell.
      host.agents = const [
        Agent(
          id: 'notes',
          name: 'Codex harness 9-21 16:20',
          engine: 'terminal',
          dsh: 'example/field-notes',
          dshName: 'Field Notes',
          terminalAvailable: true,
        ),
      ];
      await mountSidebar(tester, app);
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Field Notes'), findsNWidgets(2));
      // A plain terminal is not a stopped harness.
      final shell = SwarmAgentRef(
        host,
        const Agent(
          id: 'shell',
          name: 'Terminal harness 9-21 16:30',
          engine: 'terminal',
          terminalAvailable: true,
        ),
      );
      expect(projectAgentStatus(app, shell), 'Ready');
      expect(sessionLabel(shell.agent), 'Terminal');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('folder lines appear only when they tell locations apart', (
    tester,
  ) async {
    final app = projectApp();
    addTearDown(app.dispose);
    final host = app.machineStates['m']!
      ..nodeOnline = true
      ..connectionStatus = ConnectionStatus.connected;
    host.agents = const [
      Agent(id: 'a0', name: 'Main', terminalAvailable: true),
      Agent(id: 'a1', name: 'Worktree', terminalAvailable: true),
      Agent(id: 'b0', name: 'One', terminalAvailable: true),
      Agent(id: 'b1', name: 'Two', terminalAvailable: true),
    ];
    host.localProjects = const {
      // A user-named checkout and a dated worktree Harness made for it.
      'a0': AgentProject(
        name: 'notebook',
        cwd: '/work/notebook',
        remote: 'example/notebook',
      ),
      'a1': AgentProject(
        name: 'notebook',
        cwd: '/work/harnesses/codex-2026-09-21-16-20',
        remote: 'example/notebook',
      ),
      // Two checkouts whose folders end the same way.
      'b0': AgentProject(
        name: 'Service',
        cwd: '/work/one/app',
        remote: 'example/service',
      ),
      'b1': AgentProject(
        name: 'Service',
        cwd: '/work/two/app',
        remote: 'example/service',
      ),
    };
    await mountSidebar(tester, app);
    expect(find.text('notebook'), findsNWidgets(2));
    expect(find.text('codex-2026-09-21-16-20'), findsNothing);
    expect(find.text('/work/harnesses/codex-2026-09-21-16-20'), findsNothing);
    expect(find.text('app'), findsNothing);
    expect(find.text('/work/one/app'), findsOneWidget);
    expect(find.text('/work/two/app'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('identical labels are told apart within a project', (
    tester,
  ) async {
    final app = projectApp();
    addTearDown(app.dispose);
    final host = app.machineStates['m']!
      ..nodeOnline = true
      ..connectionStatus = ConnectionStatus.connected;
    host.agents = const [
      Agent(
        id: 'c0',
        name: 'Codex harness 9-21 16:20',
        engine: 'codex',
        terminalAvailable: true,
      ),
      Agent(
        id: 'c1',
        name: 'Codex harness 9-21 17:05',
        engine: 'codex',
        terminalAvailable: true,
      ),
      Agent(
        id: 'c2',
        name: 'Codex harness 9-20 17:05',
        engine: 'codex',
        terminalAvailable: true,
      ),
      Agent(id: 'r0', name: 'Review', terminalAvailable: true),
      Agent(id: 'r1', name: 'Review', terminalAvailable: true),
      // Each in a folder Harness made: its own project, headed by its session.
      Agent(
        id: 'g0',
        name: 'Codex harness 9-22 08:00',
        engine: 'codex',
        terminalAvailable: true,
      ),
      Agent(
        id: 'g1',
        name: 'Codex harness 9-22 09:30',
        engine: 'codex',
        terminalAvailable: true,
      ),
    ];
    const shared = AgentProject(
      name: 'Notebook',
      cwd: '/work/notebook',
      remote: 'example/notebook',
    );
    host.localProjects = const {
      'c0': shared,
      'c1': shared,
      'c2': shared,
      'r0': shared,
      'r1': shared,
      'g0': AgentProject(
        name: 'codex-2026-09-22-08-00',
        cwd: '/work/harnesses/codex-2026-09-22-08-00',
      ),
      'g1': AgentProject(
        name: 'codex-2026-09-22-09-30',
        cwd: '/work/harnesses/codex-2026-09-22-09-30',
      ),
    };
    await mountSidebar(tester, app);
    // Only the lone sessions of the two generated-folder projects below.
    expect(find.text('Codex'), findsNWidgets(2));
    expect(find.text('Codex · 16:20'), findsOneWidget);
    expect(find.text('Codex · 9-21 17:05'), findsOneWidget);
    expect(find.text('Codex · 9-20 17:05'), findsOneWidget);
    expect(find.text('Review · 1'), findsOneWidget);
    expect(find.text('Review · 2'), findsOneWidget);
    // Two generated-folder projects: their headings carry the clock.
    expect(find.text('Codex · 08:00'), findsOneWidget);
    expect(find.text('Codex · 09:30'), findsOneWidget);
    expect(find.text('codex-2026-09-22-08-00'), findsNothing);
    // The filter still finds a session by the label it shows.
    await tester.enterText(
      find.byKey(const ValueKey('project-filter')),
      'codex 08:00',
    );
    await tester.pumpAndSettle();
    expect(find.text('Codex · 08:00'), findsOneWidget);
    expect(find.text('Codex · 09:30'), findsNothing);
    expect(find.text('Review · 1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('failed and starting launches never report idle', () {
    final app = projectApp();
    addTearDown(app.dispose);
    final host = app.machineStates['m']!
      ..nodeOnline = true
      ..connectionStatus = ConnectionStatus.connected;
    for (final state in ['starting', 'failed']) {
      final row = SwarmAgentRef(
        host,
        Agent(
          id: 'a',
          name: 'Launch',
          launchState: state,
          terminalAvailable: true,
        ),
      );
      expect(
        projectAgentStatus(app, row),
        state == 'starting' ? 'Starting' : 'Start failed',
      );
    }
  });

  testWidgets('hidden sidebar preserves its filter without accepting focus', (
    tester,
  ) async {
    final app = projectApp();
    app.adoptSessionForTest(terminal('a0', []));
    await mount(tester, app, size: const Size(1600, 800));
    final filter = find.byKey(const ValueKey('project-filter'));
    await tester.enterText(filter, 'notebook');
    await tester.tap(find.byTooltip('Hide sidebar'));
    await tester.pump();
    expect(filter, findsNothing);
    final hidden = tester.element(
      find.byKey(const ValueKey('project-filter'), skipOffstage: false),
    );
    final hiddenFocus = Focus.of(hidden);
    expect(hiddenFocus.canRequestFocus, isFalse);
    await tester.tap(find.byKey(const ValueKey('project-sidebar-toggle')));
    await tester.pump();
    expect(tester.widget<TextField>(filter).controller!.text, 'notebook');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  // Fork: the sidebar's machine tree gave way to upstream's Machines Manager.
  testWidgets('Machines and Show machines open the machine list', (
    tester,
  ) async {
    final app = projectApp();
    addTearDown(app.dispose);
    app.machineStates['m']!.agents = const [
      Agent(
        id: 'failed',
        name: 'Unavailable session',
        terminalAvailable: false,
        terminalUnavailableReason: 'The terminal process has exited.',
      ),
    ];
    var shown = 0;
    await mountSidebar(tester, app, onShowMachines: () => shown++);
    expect(find.text('Machines'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('project-sidebar-machines')));
    await tester.pump();
    expect(shown, 1);
    await tester.tap(find.byKey(const ValueKey('project-agent:m:failed')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show machines'));
    await tester.pumpAndSettle();
    expect(shown, 2);
    await tester.pumpWidget(const SizedBox());
  });

  // Fork: local mode is upstream's guest desk, labelled, with its way out.
  testWidgets('local mode is labelled, with sign-in, only without an account', (
    tester,
  ) async {
    final app = projectApp()..signedIn = false;
    addTearDown(app.dispose);
    var signIns = 0;
    await mountSidebar(tester, app, onSignIn: () => signIns++);
    expect(app.isGuest, isTrue);
    expect(find.text('Local mode'), findsOneWidget);
    expect(find.text('This computer, no account'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('project-sidebar-sign-in')));
    await tester.pump();
    expect(signIns, 1);

    app.signedIn = true;
    await mountSidebar(tester, app);
    expect(find.text('Local mode'), findsNothing);
    expect(find.byKey(const ValueKey('project-sidebar-sign-in')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  // Fork: the machine tree was where an agent was dragged onto the grid; the
  // project rows carry that now, and only for a session that can fill a tile.
  testWidgets('only a session with a terminal can be dragged', (tester) async {
    final app = projectApp();
    addTearDown(app.dispose);
    app.machineStates['m']!.agents = const [
      Agent(id: 'live', name: 'Live', engine: 'codex', terminalAvailable: true),
      Agent(id: 'gone', name: 'Gone', terminalAvailable: false),
    ];
    await mountSidebar(tester, app);
    Finder draggable(String id) => find.ancestor(
      of: find.byKey(ValueKey('project-agent:m:$id')),
      matching: find.byType(Draggable<AgentDragRef>),
    );
    expect(draggable('live'), findsOneWidget);
    expect(draggable('gone'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a session dragged from the sidebar fills the tile it lands on', (
    tester,
  ) async {
    final app = projectApp();
    app.adoptSessionForTest(terminal('a0', []));
    await mount(tester, app, size: const Size(1600, 900));
    await tester.pump(const Duration(milliseconds: 400));
    final row = find.byKey(const ValueKey('project-agent:m:a1'));
    expect(row, findsOneWidget);
    final gesture = await tester.startGesture(tester.getCenter(row));
    await tester.pump();
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump();
    expect(agentDrag.value?.agentId, 'a1');
    await gesture.moveTo(tester.getCenter(find.byType(PaneGrid)));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(agentDrag.value, isNull);
    expect(app.panes.map((pane) => pane.agentId), contains('a1'));
    await tester.pumpWidget(const SizedBox());
    // Before the test ends, not in a tear-down: the offline machine's retry
    // timer the drop started must be gone when the fake clock is checked.
    app.dispose();
  });
}
