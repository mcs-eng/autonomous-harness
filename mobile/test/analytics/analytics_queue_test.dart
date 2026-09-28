import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/analytics/analytics_client.dart';
import 'package:harness_mobile/analytics/analytics_config.dart';
import 'package:harness_mobile/analytics/analytics_event.dart';
import 'package:harness_mobile/analytics/analytics_identity.dart';
import 'package:harness_mobile/analytics/analytics_log.dart';
import 'package:harness_mobile/analytics/analytics_service.dart';

/// A transport that answers from a script, one result per send, and remembers
/// every body it was handed. An empty script answers `sent`.
class _Client implements AnalyticsClient {
  final results = <Object>[];
  final bodies = <Map<String, Object?>>[];

  /// While set, a send waits on it instead of reading the script — an event
  /// held on the wire.
  Completer<AnalyticsSendResult>? hold;
  bool disposed = false;

  List<String> get names => [
    for (final body in bodies) '${body['event_name']}',
  ];

  @override
  Future<AnalyticsSendResult> send(Map<String, Object?> payload) async {
    bodies.add(payload);
    final held = hold;
    if (held != null) return held.future;
    if (results.isEmpty) return AnalyticsSendResult.sent;
    final next = results.removeAt(0);
    if (next is AnalyticsSendResult) return next;
    throw next;
  }

  @override
  void dispose() => disposed = true;
}

const _context = AnalyticsContext(
  platform: 'ios',
  appVersion: '1.0.0',
  appBuild: '45',
  osVersion: '26.0',
  arch: 'iosArm64',
  locale: 'en_US',
  release: false,
);

void main() {
  late Directory home;
  late _Client client;
  late AnalyticsLogStream log;
  late ({String? id, String? email}) account;

  setUp(() {
    home = Directory.systemTemp.createTempSync('analytics_queue_test');
    client = _Client();
    // Room for every row a full queue produces: the screen's own ring keeps
    // 200, and a row pushed out of it can no longer be read back here.
    log = AnalyticsLogStream(maxEntries: 2 * AnalyticsLimits.queueCap);
    account = (id: null, email: null);
  });

  tearDown(() => home.deleteSync(recursive: true));

  QueuedAnalytics queue({
    Future<AnalyticsContext>? context,
    DateTime Function()? clock,
  }) => QueuedAnalytics(
    client: client,
    identityStore: AnalyticsIdentityStore(
      file: File('${home.path}/analytics.json'),
      computerIdFile: File('${home.path}/computer-id'),
    ),
    contextFuture: context ?? Future.value(_context),
    userLookup: () => account,
    recorder: log,
    clock: clock ?? DateTime.now,
  );

  AnalyticsLogEntry row(String name) =>
      log.entries.firstWhere((entry) => entry.name == name);

  test('sends in order, one at a time, and settles each row', () async {
    final analytics = queue();
    analytics.track('app_opened', params: {'signed_in': true});
    analytics.track('signed_in');
    await analytics.flush();

    expect(client.names, ['app_opened', 'signed_in']);
    expect(analytics.pending, 0);
    expect(row('app_opened').status, AnalyticsEventStatus.sent);
    expect(row('app_opened').attempts, 1);
    expect(row('app_opened').payload, contains('"event_name": "app_opened"'));
    expect(row('app_opened').took, isNotNull);
  });

  test('a badly named event is recorded as dropped and never sent', () async {
    final analytics = queue();
    analytics.track('Opened the app');
    await analytics.flush();

    expect(client.bodies, isEmpty);
    expect(analytics.pending, 0);
    expect(row('Opened the app').status, AnalyticsEventStatus.dropped);
    expect(row('Opened the app').note, contains('snake_case'));
  });

  test(
    'who is signed in is read when the event happens, not when it is sent',
    () async {
      final analytics = queue();
      analytics.track('app_opened');
      account = (id: 'u1', email: 'person@example.com');
      analytics.track('signed_in');
      await analytics.flush();

      final data = [
        for (final body in client.bodies) body['data']! as Map<String, Object?>,
      ];
      expect(data[0].containsKey('user_id'), isFalse);
      expect(data[1]['user_id'], 'u1');
      // One device, one visit, across the sign-in.
      expect(data[0]['user_pseudo_id'], data[1]['user_pseudo_id']);
      expect(data[0]['session_id'], data[1]['session_id']);
    },
  );

  test('a refused event is dropped; the queue behind it carries on', () async {
    client.results.add(AnalyticsSendResult.rejected);
    final analytics = queue();
    analytics.track('app_opened');
    analytics.track('signed_in');
    await analytics.flush();

    expect(client.names, ['app_opened', 'signed_in']);
    expect(row('app_opened').status, AnalyticsEventStatus.refused);
    expect(row('signed_in').status, AnalyticsEventStatus.sent);
  });

  test('a client that throws costs that event, not the queue', () async {
    client.results.add(StateError('broken client'));
    final analytics = queue();
    analytics.track('app_opened');
    analytics.track('signed_in');
    await analytics.flush();

    expect(row('app_opened').status, AnalyticsEventStatus.dropped);
    expect(row('app_opened').note, contains('broken client'));
    expect(row('signed_in').status, AnalyticsEventStatus.sent);
  });

  test('a context that fails still lets the event go, anonymously', () async {
    final analytics = queue(context: Future.error(StateError('no bundle')));
    analytics.track('app_opened');
    await analytics.flush();

    final data = client.bodies.single['data']! as Map<String, Object?>;
    expect(data['platform'], '');
    expect(row('app_opened').status, AnalyticsEventStatus.sent);
  });

  test('a user lookup that throws drops the one event and says so', () async {
    final analytics = QueuedAnalytics(
      client: client,
      identityStore: AnalyticsIdentityStore(
        file: File('${home.path}/analytics.json'),
        computerIdFile: File('${home.path}/computer-id'),
      ),
      contextFuture: Future.value(_context),
      userLookup: () => throw StateError('no account'),
    );
    analytics.track('app_opened');
    await analytics.flush();

    expect(analytics.pending, 0);
    expect(client.bodies, isEmpty);
  });

  test('a transport failure keeps the event and retries, backing off', () {
    fakeAsync((async) {
      client.results.addAll([
        AnalyticsSendResult.retry,
        AnalyticsSendResult.retry,
        AnalyticsSendResult.retry,
      ]);
      final analytics = queue();
      analytics.track('app_opened');
      async.flushMicrotasks();
      expect(client.bodies, hasLength(1));
      expect(analytics.pending, 1);
      expect(row('app_opened').status, AnalyticsEventStatus.queued);

      // First retry after 2s, the next after 4s, the one after that after 8s.
      async.elapse(const Duration(milliseconds: 1999));
      expect(client.bodies, hasLength(1));
      async.elapse(const Duration(milliseconds: 1));
      expect(client.bodies, hasLength(2));
      async.elapse(const Duration(seconds: 3));
      expect(client.bodies, hasLength(2));
      async.elapse(const Duration(seconds: 1));
      expect(client.bodies, hasLength(3));
      async.elapse(const Duration(seconds: 8));
      expect(client.bodies, hasLength(4));
      expect(analytics.pending, 0);
      expect(row('app_opened').attempts, 4);
      expect(row('app_opened').status, AnalyticsEventStatus.sent);
    });
  });

  test('the backoff stops growing at its cap, and a success resets it', () {
    fakeAsync((async) {
      client.results.addAll(List.filled(12, AnalyticsSendResult.retry));
      final analytics = queue();
      analytics.track('app_opened');
      // 2+4+…+64 = 126s, then 120s apiece: all twelve failures are spent well
      // inside this, and the thirteenth attempt succeeds.
      async.elapse(const Duration(minutes: 20));
      expect(client.bodies, hasLength(13));
      expect(analytics.pending, 0);

      // Back to 2s after the success.
      client.results.add(AnalyticsSendResult.retry);
      analytics.track('signed_in');
      async.flushMicrotasks();
      expect(client.bodies, hasLength(14));
      async.elapse(const Duration(seconds: 2));
      expect(client.bodies, hasLength(15));
    });
  });

  test('flush sends now instead of waiting out the retry', () {
    fakeAsync((async) {
      client.results.add(AnalyticsSendResult.retry);
      final analytics = queue();
      analytics.track('app_opened');
      async.flushMicrotasks();
      expect(analytics.pending, 1);

      unawaited(analytics.flush());
      async.flushMicrotasks();
      expect(client.bodies, hasLength(2));
      expect(analytics.pending, 0);
    });
  });

  test('past the cap the oldest go, and the rows say why', () {
    fakeAsync((async) {
      client.results.add(AnalyticsSendResult.retry);
      final analytics = queue();
      for (var i = 0; i < AnalyticsLimits.queueCap + 3; i++) {
        analytics.track('event_$i');
      }
      async.flushMicrotasks();

      expect(analytics.pending, AnalyticsLimits.queueCap);
      final dropped = log.entries
          .where((entry) => entry.status == AnalyticsEventStatus.dropped)
          .toList();
      expect(dropped, hasLength(3));
      expect(dropped.every((e) => e.note == 'the queue was full'), isTrue);
    });
  });

  test('an event trimmed while it is on the wire does not take the next one with it', () {
    fakeAsync((async) {
      final analytics = queue();
      client.hold = Completer<AnalyticsSendResult>();
      analytics.track('first_event');
      async.flushMicrotasks();
      expect(client.names, ['first_event']);

      // An outage long enough to fill the queue while `first_event` waits on
      // the wire: the cap pushes it — the one in flight — out of the queue.
      for (var i = 0; i < AnalyticsLimits.queueCap; i++) {
        analytics.track('later_$i');
      }
      expect(analytics.pending, AnalyticsLimits.queueCap);

      final held = client.hold!;
      client.hold = null;
      held.complete(AnalyticsSendResult.sent);
      async.flushMicrotasks();

      // Every one of the later events reached the wire — none was removed in
      // place of the event that was already gone.
      expect(client.names.skip(1), [
        for (var i = 0; i < AnalyticsLimits.queueCap; i++) 'later_$i',
      ]);
      expect(analytics.pending, 0);
      expect(row('later_0').status, AnalyticsEventStatus.sent);
    });
  });

  test(
    'close drains what it can, releases the client, and ends the queue',
    () async {
      final analytics = queue();
      analytics.track('app_opened');
      await analytics.close();

      expect(client.names, ['app_opened']);
      expect(client.disposed, isTrue);
      analytics.track('signed_in');
      await analytics.flush();
      expect(client.names, ['app_opened'], reason: 'the instance is spent');
      // A second close is nothing.
      await analytics.close();
    },
  );

  test('a wedged network cannot hold a close past its deadline', () {
    fakeAsync((async) {
      client.hold = Completer<AnalyticsSendResult>();
      final analytics = queue();
      analytics.track('app_opened');
      var closed = false;
      analytics.close().then((_) => closed = true);
      async.elapse(AnalyticsLimits.closeDeadline);
      expect(closed, isTrue);
      expect(client.disposed, isTrue);
    });
  });
}
