import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/project_navigation.dart';
import 'package:harness/state/swarm_navigation.dart';
import 'package:harness/state/swarm_search.dart';
import 'package:harness/widgets/harness_start_page.dart';
import 'package:harness/widgets/workspace_resume.dart';

import 'project_sidebar_test.dart' show projectApp;
import 'swarm_attention_test.dart' show waitingQuestion;

void main() {
  test(
    'attention precedes visits, and output cannot masquerade as a visit',
    () {
      final app = projectApp();
      addTearDown(app.dispose);
      final machine = app.machineStates['m']!;
      machine.blockedAgents['a1'] = waitingQuestion('a1');
      final recent = [agentDestinationId('m', 'a0')];
      expect(workspaceResumeAgents(app, recent).map((r) => r.agent.id), [
        'a1',
        'a0',
      ]);
      machine.blockedAgents.clear();
      machine.agents = machine.agents.reversed.toList();
      expect(workspaceResumeAgents(app, recent).map((r) => r.agent.id), [
        'a0',
        'a1',
      ]);
      expect(workspaceWaitingCount(app), 0);
    },
  );

  testWidgets(
    'a resume card names the session and shows only the last folder part',
    (tester) async {
      final app = projectApp();
      addTearDown(app.dispose);
      final machine = app.machineStates['m']!
        ..nodeOnline = true
        ..connectionStatus = ConnectionStatus.connected;
      machine.agents = const [
        Agent(
          id: 'a0',
          name: 'Codex harness 9-21 16:20',
          engine: 'codex',
          terminalAvailable: true,
        ),
        Agent(
          id: 'a1',
          name: 'Codex harness 9-21 17:05',
          engine: 'codex',
          terminalAvailable: true,
        ),
      ];
      machine.localProjects = const {
        'a0': AgentProject(
          name: 'Notebook',
          cwd: '/work/clients/notebook',
          branch: 'main',
        ),
        'a1': AgentProject(
          name: 'codex-2026-09-21-17-05',
          cwd: '/work/harnesses/codex-2026-09-21-17-05',
        ),
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: grid.buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: WorkspaceResume(
              app: app,
              rows: workspaceResumeAgents(app, const []),
              onOpen: (_) {},
              onAttention: () {},
            ),
          ),
        ),
      );
      expect(find.text('Codex · 16:20'), findsOneWidget);
      expect(find.text('Codex · 17:05'), findsOneWidget);
      expect(find.text('Codex harness 9-21 16:20'), findsNothing);
      expect(find.text('notebook · main'), findsOneWidget);
      expect(find.text('/work/clients/notebook · main'), findsNothing);
      expect(find.textContaining('codex-2026-09-21-17-05'), findsNothing);
      expect(
        find.byTooltip('Test host\n/work/clients/notebook'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final size in [const Size(1100, 800), const Size(600, 560)]) {
    testWidgets('resume and search work at $size with large text', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = projectApp();
      addTearDown(app.dispose);
      final machine = app.machineStates['m']!;
      machine.nodeOnline = true;
      machine.connectionStatus = ConnectionStatus.connected;
      machine.blockedAgents['a1'] = waitingQuestion('a1');
      await app.addAgentToSwarm('m', 'a0');
      final existing = app.activeSwarm;
      app.newSwarm();
      final tabCount = app.swarms.length;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      var searches = 0;
      var attention = 0;
      Widget page() => MaterialApp(
        theme: grid.buildAppTheme(brightness: Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: const TextScaler.linear(19 / 14),
          ),
          child: Scaffold(
            body: HarnessStartPage(
              focusNode: focus,
              createSearch: () {
                searches++;
                return SwarmSearchController(app, [], adding: true);
              },
              onNew: () {},
              onChoose: (_) {},
              resume: WorkspaceResume(
                app: app,
                rows: workspaceResumeAgents(app, [
                  agentDestinationId('m', 'a0'),
                ]),
                onOpen: (row) => openProjectAgent(app, row),
                onAttention: () => attention++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pump();
      expect(searches, 0);
      expect(find.text('Continue working'), findsOneWidget);
      await tester.tap(find.text('1 session needs your input'));
      expect(attention, 1);
      final row = find.byKey(const ValueKey('resume:m:a0'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pump();
      expect(app.activeSwarm, same(existing));
      expect(app.swarms.length, tabCount);
      expect(machine.agents.length, 2);
      final input = find.byKey(const ValueKey('harness-start-search'));
      final top = tester.getTopLeft(input);
      await tester.tap(input);
      await tester.pump();
      expect(searches, 1);
      expect(find.text('Continue working'), findsNothing);
      expect(tester.getTopLeft(input), top);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
