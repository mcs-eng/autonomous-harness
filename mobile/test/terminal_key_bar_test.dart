import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/phone/terminal_key_bar.dart';
import 'package:xterm/xterm.dart';

void main() {
  late Terminal terminal;
  late List<String> outbound;
  late List<bool> armings;
  late int dismissals;

  setUp(() {
    terminal = Terminal(maxLines: 200, reflowEnabled: false)..resize(80, 12);
    outbound = [];
    armings = [];
    dismissals = 0;
    terminal.onOutput = outbound.add;
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    bool enabled = true,
    bool controlArmed = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: TerminalKeyBar(
              terminal: terminal,
              enabled: enabled,
              controlArmed: controlArmed,
              onControlToggle: armings.add,
              onDismissKeyboard: () => dismissals++,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> tapKey(WidgetTester tester, String name) async {
    await tester.tap(find.byKey(ValueKey('terminal-key-$name')));
    await tester.pump();
  }

  testWidgets('the keys a software keyboard cannot produce reach the pty', (
    tester,
  ) async {
    await pumpBar(tester);

    await tapKey(tester, 'esc');
    await tapKey(tester, 'tab');
    // CSI Z, built from the modifier — there is no `TerminalKey.shiftTab`.
    await tapKey(tester, '\u21e7tab');
    await tapKey(tester, 'Up');
    await tapKey(tester, '7');

    expect(outbound, ['\x1b', '\t', '\x1b[Z', '\x1b[A', '7']);
  });

  testWidgets('ctrl is handed to the session, which owns the modifier', (
    tester,
  ) async {
    await pumpBar(tester);

    await tapKey(tester, 'ctrl');

    // Nothing goes down the wire: the chord is made from the NEXT character,
    // and only the session sees that one arrive.
    expect(outbound, isEmpty);
    expect(armings, [true]);

    await pumpBar(tester, controlArmed: true);
    await tapKey(tester, 'ctrl');
    expect(armings, [true, false]);
  });

  testWidgets('a stream that takes no input answers nothing — except the key '
      'that puts the keyboard away', (tester) async {
    await pumpBar(tester, enabled: false);

    await tapKey(tester, 'esc');
    await tapKey(tester, 'ctrl');
    expect(outbound, isEmpty);
    expect(armings, isEmpty);

    // Hiding the keyboard is this page's own business, not the pane's, and it
    // is the way back to a full screen of output — it works either way.
    await tapKey(tester, 'Hide keyboard');
    expect(dismissals, 1);
  });
}
