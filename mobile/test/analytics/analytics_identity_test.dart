import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/analytics/analytics_config.dart';
import 'package:harness_mobile/analytics/analytics_identity.dart';

/// `analytics.json` on a phone: the device id, the visit, and the user's own
/// switch — in a temporary home, never the real one.
void main() {
  late Directory home;
  late File file;
  late File computerId;

  setUp(() {
    home = Directory.systemTemp.createTempSync('analytics_identity_test');
    file = File('${home.path}/desktop-app/analytics.json');
    computerId = File('${home.path}/computer-id');
  });

  tearDown(() => home.deleteSync(recursive: true));

  AnalyticsIdentityStore store({Random? random}) => AnalyticsIdentityStore(
    file: file,
    computerIdFile: computerId,
    random: random,
  );

  Map<String, Object?> saved() =>
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;

  final start = DateTime.utc(2026, 9, 27, 9);
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('a fresh phone mints a v4 device id, and no visit until an event', () {
    final ids = store().peek();

    expect(ids.pseudoId, matches(uuid));
    expect(ids.sessionId, isEmpty);
    expect(file.existsSync(), isFalse, reason: 'peeking writes nothing');
  });

  test('the machine id is borrowed when there is one', () {
    computerId.writeAsStringSync('  computer-42\n');
    expect(store().peek().pseudoId, 'computer-42');
  });

  test('an empty machine id file is no id at all', () {
    computerId.writeAsStringSync('   ');
    expect(store().peek().pseudoId, matches(uuid));
  });

  test('the first event starts a visit and writes both ids down', () {
    final ids = store().touch(start);

    expect(ids.sessionId, matches(uuid));
    expect(saved(), {
      'user_pseudo_id': ids.pseudoId,
      'session_id': ids.sessionId,
      'last_active_ms': start.millisecondsSinceEpoch,
      'enabled': true,
    });
  });

  test('a visit survives quiet shorter than the idle window, not longer', () {
    final identity = store();
    final first = identity.touch(start);

    final soon = identity.touch(
      start.add(AnalyticsLimits.sessionIdle - const Duration(seconds: 1)),
    );
    expect(soon.sessionId, first.sessionId);

    final later = identity.touch(
      start.add(
        AnalyticsLimits.sessionIdle * 2 + const Duration(milliseconds: 1),
      ),
    );
    expect(later.sessionId, isNot(first.sessionId));
    expect(later.pseudoId, first.pseudoId, reason: 'the device never changes');
  });

  test('the clock is written sparingly: not per event, at most per minute', () {
    final identity = store();
    identity.touch(start);
    identity.touch(start.add(const Duration(seconds: 30)));
    expect(saved()['last_active_ms'], start.millisecondsSinceEpoch);

    final minute = start.add(const Duration(minutes: 1));
    identity.touch(minute);
    expect(saved()['last_active_ms'], minute.millisecondsSinceEpoch);
  });

  test('a busy visit still keeps the file within a minute of the clock', () {
    // An event every 30 seconds for twenty minutes. Measured from the
    // in-memory clock, each event found the previous one only 30s old, the
    // file kept the visit's FIRST minute forever — and a relaunch 16 minutes
    // in read that as a visit gone quiet and started a new one.
    final identity = store();
    for (var s = 0; s <= 20 * 60; s += 30) {
      final now = start.add(Duration(seconds: s));
      identity.touch(now);
      final lag =
          now.millisecondsSinceEpoch - (saved()['last_active_ms']! as int);
      expect(lag, lessThan(const Duration(minutes: 1).inMilliseconds));
    }
    final visit = store().peek().sessionId;
    final relaunch = store().touch(start.add(const Duration(minutes: 21)));
    expect(relaunch.sessionId, visit);
  });

  test('a relaunch picks up the same device and the same visit', () {
    final first = store().touch(start);
    final again = store().touch(start.add(const Duration(minutes: 2)));

    expect(again, first);
  });

  test('the user\'s switch is read, and kept by every write', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode({'enabled': false}));
    final identity = store();

    expect(identity.optedOut, isTrue);
    identity.touch(start);
    expect(saved()['enabled'], isFalse);
  });

  test('a corrupt or hand-edited file reads as no ids yet', () {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{not json');
    expect(store().peek().pseudoId, matches(uuid));

    file.writeAsStringSync(jsonEncode(['a', 'list']));
    expect(store().optedOut, isFalse);

    file.writeAsStringSync(jsonEncode({'user_pseudo_id': '  '}));
    expect(store().peek().pseudoId, matches(uuid));
  });

  test('a home that cannot be written costs id stability, never the event', () {
    // The parent of the file is a FILE, so creating the directory fails.
    File('${home.path}/desktop-app').writeAsStringSync('in the way');
    final ids = store().touch(start);

    expect(ids.sessionId, matches(uuid));
    expect(file.existsSync(), isFalse);
  });
}
