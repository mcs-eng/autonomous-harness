import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/widgets/machine_rail.dart';

import 'swarm_state_test.dart' show createApp;

void main() {
  testWidgets('a rail host owns click, keyboard open, and Escape', (
    tester,
  ) async {
    final app = createApp();
    addTearDown(app.dispose);
    app.machineStates['m']!.agents = [app.machineStates['m']!.agents.first];
    app.expandedMachines.add('m');
    final opened = <SwarmAgentRef>[];
    var escapes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: MachineRail(
              notifier: app,
              onOpenAgent: opened.add,
              onEscape: () => escapes++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agent 0'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(opened.map((row) => (row.machineId, row.agent.id)), [('m', 'a0')]);
    expect(app.allPanes, isEmpty);

    app.focusRail();
    app.moveRailCursor(1);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened.map((row) => (row.machineId, row.agent.id)), [
      ('m', 'a0'),
      ('m', 'a0'),
    ]);
    expect(app.allPanes, isEmpty);
    expect(app.railFocused, isFalse);

    app.focusRail();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(escapes, 1);
    expect(app.railFocused, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
