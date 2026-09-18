import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';
import 'package:harness_mobile/phone/phone_status.dart';

TerminalSession _session(TerminalSessionStatus status) => TerminalSession(
  machineId: 'm',
  agentId: 'a',
  agentName: 'Agent',
  engineId: 'codex',
  send: (_, _) async => true,
  sendBinary: (_) async => true,
)..status = status;

void main() {
  test('a session nobody else is driving offers nothing to reclaim', () {
    expect(phoneReclaimAction(null), isNull);
    for (final status in [
      TerminalSessionStatus.opening,
      TerminalSessionStatus.resyncing,
      TerminalSessionStatus.controlling,
    ]) {
      expect(
        phoneReclaimAction(_session(status)),
        isNull,
        reason: '$status has nothing to take back',
      );
    }
  });

  test('a taken-over session offers control back', () {
    final action = phoneReclaimAction(
      _session(TerminalSessionStatus.takenOver),
    );

    expect(action?.label, 'Take control');
    expect(action?.tone, PhoneTone.attention);
  });

  test('a dropped session offers a reconnect', () {
    for (final status in [
      TerminalSessionStatus.error,
      TerminalSessionStatus.closed,
    ]) {
      final action = phoneReclaimAction(_session(status));

      expect(action?.label, 'Reconnect', reason: '$status');
      expect(action?.tone, PhoneTone.bad, reason: '$status');
    }
  });
}
