import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/theme/app_theme.dart' as grid;
import 'package:harness/state/pane_preset.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/widgets/terminal_panel.dart';

import 'harness_activity_test.dart' show activityQuestion;
import 'keymap_host_test.dart' show key;
import 'support/real_fonts.dart';
import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_state_test.dart' show createApp;
import 'workspace_activity_test.dart' show captureWorkspace;

void main() {
  final capture = Platform.environment['HARNESS_PANE_FOCUS_CAPTURE_DIR'];
  setUpAll(() async {
    await loadRealFonts();
    if (capture != null && Platform.isMacOS) {
      final mono = ByteData.sublistView(
        await File('/System/Library/Fonts/SFNSMono.ttf').readAsBytes(),
      );
      for (final family in [
        'SF Mono',
        '.AppleSystemUIFontMonospaced',
        'Menlo',
      ]) {
        await (FontLoader(family)..addFont(Future.value(mono))).load();
      }
    }
  });

  testWidgets(
    'pane emphasis follows clicks and keys without remounting terminals',
    (tester) async {
      final app = createApp(connected: true);
      final input = List.generate(3, (_) => <TerminalBinaryFrame>[]);
      final sessions = [for (var i = 0; i < 3; i++) terminal('a$i', input[i])];
      const names = [
        'Review pull requests',
        'Improve pane focus',
        'Run desktop tests',
      ];
      app.machineStates['m']!.agents = [
        for (var i = 0; i < 3; i++)
          Agent(
            id: 'a$i',
            name: names[i],
            engine: 'codex',
            terminalAvailable: true,
          ),
      ];
      for (final session in sessions) {
        app.adoptSessionForTest(session);
      }
      app.renameSwarm(app.activeSwarmId, 'desktop');
      app.setPreset(3, PanePreset.balanced3);
      final panes = app.panes.toList();
      app.focusPane(panes.first.id);
      await mount(tester, app);
      tester.view.physicalSize = const Size(1500, 700);
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        sessions[i].terminal.write(
          '\x1b[36m${names[i]}\x1b[0m\r\n\r\n'
          '  Changes\r\n'
          '  \x1b[32m+\x1b[0m Keep the active pane clear\r\n'
          '  \x1b[32m+\x1b[0m Quietly dim the other panes\r\n'
          '  \x1b[32m+\x1b[0m Preserve terminal state\r\n\r\n'
          '  Pointer and keyboard checks passed.\r\n\r\n'
          '  Existing sessions keep running.\r\n\r\n'
          '> ',
        );
      }
      await tester.pump(const Duration(milliseconds: 250));

      Finder frame(int i) => find.byKey(ValueKey('pane-frame:${panes[i].id}'));
      Finder panel(int i) =>
          find.descendant(of: frame(i), matching: find.byType(TerminalPanel));
      BoxDecoration? foreground(int i) =>
          tester.widget<Container>(frame(i)).foregroundDecoration
              as BoxDecoration?;
      final renderers = [for (var i = 0; i < 3; i++) tester.state(panel(i))];
      void expectSelected(int selected) {
        expect(app.focusedPaneId, panes[selected].id);
        for (var i = 0; i < 3; i++) {
          expect(foreground(i)?.color, i == selected ? isNull : isNotNull);
          expect(tester.state(panel(i)), same(renderers[i]));
        }
      }

      expectSelected(0);
      // The first click both removes the dimming and hands input to this pane.
      await tester.tap(panel(1));
      await tester.pump();
      expectSelected(1);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 20));
      expect(input[1].single.bytes, [27, 91, 68]);
      expect(input[0], isEmpty);
      expect(input[2], isEmpty);

      if (capture != null) {
        await tester.runAsync(() => Directory(capture).create(recursive: true));
        await captureWorkspace(tester, '$capture/workspace-pane-focus.png');
      }

      await key(tester, LogicalKeyboardKey.arrowRight, cmd: true);
      expectSelected(2);
      await key(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 20));
      expect(input[2].single.bytes, [27, 91, 68]);
      expect(input[1], hasLength(1));

      // Attention remains full strength on a dimmed pane.
      app.machineStates['m']!.blockedAgents['a0'] = activityQuestion('a0');
      app.notifyListeners();
      await tester.pump();
      expect(foreground(0)!.color, isNotNull);
      expect((foreground(0)!.border as Border).top.color, grid.AppPalette.warn);
      expectSelected(2);

      // Zoom and temporary tab-strip focus preserve the selected pane's contrast.
      await key(tester, LogicalKeyboardKey.enter, cmd: true);
      expect(app.zoomedPaneId, panes[2].id);
      expect(foreground(2)?.color, isNull);
      await key(tester, LogicalKeyboardKey.enter, cmd: true);
      app.newSwarm(name: 'Temporary');
      app.adoptSessionForTest(terminal('a3', []));
      await tester.pump();
      await app.closeSwarm(app.activeSwarmId);
      await tester.pump();
      expect(app.tabStripFocused, isTrue);
      expectSelected(2);
      app.focusPane(panes[2].id);
      await tester.pump();

      // A single pane needs no dimming or extra focus treatment.
      await app.closePane(panes[0].id);
      await app.closePane(panes[1].id);
      await tester.pump();
      expect(foreground(2)?.color, isNull);
      expect(tester.state(panel(2)), same(renderers[2]));
      expect(tester.takeException(), isNull);
      // Let xterm's click-count window and resize debounce finish.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );
}
