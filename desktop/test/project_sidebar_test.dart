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
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
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
      for (var i = 0; i < 4; i++) {
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
      expect(find.text('Machines'), findsOneWidget);
      expect(
        tester.state<ScaffoldState>(find.byType(Scaffold).first).isDrawerOpen,
        isTrue,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Machines'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      if (find.text('Agent 0').hitTestable().evaluate().isEmpty) {
        await tester.tap(
          find.descendant(
            of: find.byType(ProjectSidebar),
            matching: find.text('Test host'),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }
      await tester.tap(find.text('Agent 0').hitTestable());
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
    await mount(tester, app);
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
}
