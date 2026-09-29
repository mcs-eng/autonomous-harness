import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/analytics/analytics.dart';
import 'package:harness_mobile/analytics/analytics_config.dart';
import 'package:harness_mobile/analytics/analytics_event.dart';
import 'package:harness_mobile/analytics/analytics_log.dart';
import 'package:harness_mobile/analytics/analytics_sink.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Every call the extension makes, by name and params — the stream as the
/// queue would receive it, with no queue.
class _Recording implements Analytics {
  final events = <({String name, Map<String, Object?> params})>[];

  @override
  void track(String name, {Map<String, Object?> params = const {}}) =>
      events.add((name: name, params: params));

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

const _context = AnalyticsContext(
  platform: 'ios',
  appVersion: '1.0.0',
  appBuild: '45',
  osVersion: 'Version 26.0',
  arch: 'iosArm64',
  locale: 'vi_VN',
  release: true,
);

AnalyticsEvent _event({
  String name = 'app_opened',
  Map<String, Object?> params = const {},
  String? userId,
  String? userEmail,
}) => AnalyticsEvent(
  name: name,
  params: params,
  at: DateTime.fromMillisecondsSinceEpoch(1790000000999),
  identity: AnalyticsIdentity(
    pseudoId: 'device-1',
    sessionId: 'visit-1',
    userId: userId,
    userEmail: userEmail,
  ),
);

/// `{key: value}` back out of the wire's `[{key, value}]` list.
Map<String, Object?> _paramsOf(Map<String, Object?> payload) {
  final data = payload['data']! as Map<String, Object?>;
  return {
    for (final entry in data['event_params']! as List<Map<String, Object?>>)
      entry['key']! as String: entry['value'],
  };
}

void main() {
  group('the name rule', () {
    test('snake_case, 3 to 64 characters, starting with a letter', () {
      expect(analyticsEventNamePattern.hasMatch('app_opened'), isTrue);
      expect(analyticsEventNamePattern.hasMatch('a' * 64), isTrue);
      // What the website sends, and exactly what this rule exists to refuse.
      expect(analyticsEventNamePattern.hasMatch('Click button'), isFalse);
      expect(analyticsEventNamePattern.hasMatch('ab'), isFalse);
      expect(analyticsEventNamePattern.hasMatch('a' * 65), isFalse);
      expect(analyticsEventNamePattern.hasMatch('1st_event'), isFalse);
    });
  });

  group('the wire payload', () {
    test('an envelope naming the event, with everything else under data', () {
      final payload = analyticsPayload(
        _event(userId: 'user-9', userEmail: 'person@example.com'),
        _context,
      );

      expect(payload['event_name'], 'app_opened');
      // Seconds, not milliseconds — and floored, so the 999ms go.
      expect(payload['event_timestamp'], 1790000000);
      final data = payload['data']! as Map<String, Object?>;
      expect(data['session_id'], 'visit-1');
      expect(data['user_pseudo_id'], 'device-1');
      expect(data['user_id'], 'user-9');
      expect(data['platform'], 'ios');
      expect(_paramsOf(payload), {
        'app_version': '1.0.0',
        'app_build': '45',
        'os': 'ios',
        'os_version': 'Version 26.0',
        'arch': 'iosArm64',
        'locale': 'vi_VN',
        'build': 'release',
        'user_id': 'user-9',
        'user_email': 'person@example.com',
        'category': AnalyticsConfig.category,
      });
    });

    test('signed out: no user id in data and none in the params', () {
      final payload = analyticsPayload(_event(), _context);

      final data = payload['data']! as Map<String, Object?>;
      expect(data.containsKey('user_id'), isFalse);
      final params = _paramsOf(payload);
      expect(params.containsKey('user_id'), isFalse);
      expect(params.containsKey('user_email'), isFalse);
    });

    test('an event may say more than the context did, but never its category', () {
      final payload = analyticsPayload(
        _event(params: {'locale': 'en_US', 'category': 'someone-else'}),
        _context,
      );

      final params = _paramsOf(payload);
      expect(params['locale'], 'en_US');
      // The one field that keeps this app separable inside the shared project.
      expect(params['category'], AnalyticsConfig.category);
    });

    test(
      'a context that could not be read costs its fields, not the event',
      () {
        final payload = analyticsPayload(_event(), AnalyticsContext.unknown);

        final params = _paramsOf(payload);
        expect(params.keys, containsAll(['build', 'category']));
        expect(params.containsKey('app_version'), isFalse);
        expect(params.containsKey('os'), isFalse);
        expect(params['build'], kReleaseMode ? 'release' : 'debug');
      },
    );

    test('a debug build says so on every event', () {
      const debug = AnalyticsContext(
        platform: 'android',
        appVersion: '',
        appBuild: '',
        osVersion: '',
        arch: '',
        locale: '',
        release: false,
      );
      expect(debug.asParams()['build'], 'debug');
      expect(debug.asParams()['app_version'], isNull);
    });
  });

  group('params', () {
    test('nulls and empty strings are dropped, the rest kept in order', () {
      expect(analyticsParams({'a': null, 'b': '', 'c': 'x', 'd': 0}), [
        {'key': 'c', 'value': 'x'},
        {'key': 'd', 'value': 0},
      ]);
    });

    test('never more than the cap, however many are passed', () {
      final params = {for (var i = 0; i < 60; i++) 'k$i': i};
      final out = analyticsParams(params);
      expect(out, hasLength(AnalyticsLimits.paramsMaxKeys));
      expect(out.last['key'], 'k${AnalyticsLimits.paramsMaxKeys - 1}');
    });

    test('numbers and bools go as they are; anything else as JSON', () {
      expect(analyticsValue(3), 3);
      expect(analyticsValue(2.5), 2.5);
      expect(analyticsValue(true), true);
      expect(analyticsValue(['a', 1]), '["a",1]');
      expect(analyticsValue({'k': 'v'}), '{"k":"v"}');
    });

    test('a long string is clipped to what the backend keeps', () {
      final long = 'x' * (AnalyticsLimits.paramsMaxStringLength + 20);
      expect(
        analyticsValue(long),
        hasLength(AnalyticsLimits.paramsMaxStringLength),
      );
      // The clip applies to an encoded value too.
      expect(
        analyticsValue([long]),
        hasLength(AnalyticsLimits.paramsMaxStringLength),
      );
    });

    test('a value that will not encode costs that value, never the event', () {
      final value = _Unencodable();
      expect(analyticsValue(value), 'unencodable');
    });
  });

  group('the config', () {
    test('muted under flutter test, and says why', () {
      final config = AnalyticsConfig.resolve();

      expect(config.enabled, isFalse);
      expect(config.offReason, isNotNull);
      expect(config.endpoint.path, endsWith('/event_tracking'));
      expect(config.endpoint.path, isNot(contains('//')));
      expect(config.writeKey, isNotEmpty);
    });

    test('a config with no reason is live', () {
      final config = AnalyticsConfig(
        endpoint: Uri.parse('https://analytics.invalid/api/v1/event_tracking'),
        writeKey: 'k',
      );
      expect(config.enabled, isTrue);
    });
  });

  group('the events the phone sends', () {
    late _Recording recording;

    setUp(() => recording = _Recording());

    test('each is written once, as a product fact and nothing more', () {
      recording
        ..appOpened(signedIn: true)
        ..signedIn()
        ..signInFailed('cli_missing')
        ..signedOut()
        ..appFirstMessage(from: 'launch', secondsSinceLogin: 42);

      expect(recording.events.map((e) => e.name), [
        'app_opened',
        'signed_in',
        'sign_in_failed',
        'signed_out',
        'app_first_message',
      ]);
      expect(recording.events[0].params, {'signed_in': true});
      expect(recording.events[1].params, isEmpty);
      expect(recording.events[2].params, {'reason': 'cli_missing'});
      expect(recording.events[4].params, {
        'from': 'launch',
        'seconds_since_login': 42,
      });
      for (final event in recording.events) {
        expect(analyticsEventNamePattern.hasMatch(event.name), isTrue);
      }
    });
  });

  group('the recorder', () {
    test('a release build records nothing, and hands out no ids', () {
      const log = NoopAnalyticsLog();
      expect(log.queued('app_opened', const {}, DateTime(2026)), 0);
      log.attempted(0, const {});
      log.settled(0, AnalyticsEventStatus.sent);
    });

    test(
      'the ring keeps the newest rows; a row pushed out settles nothing',
      () {
        final log = AnalyticsLogStream(maxEntries: 2);
        final first = log.queued('first_event', const {}, DateTime(2026));
        log.queued('second_event', const {}, DateTime(2026));
        log.queued('third_event', const {}, DateTime(2026));

        expect(log.entries.map((e) => e.name), ['third_event', 'second_event']);
        log.attempted(first, const {});
        log.settled(first, AnalyticsEventStatus.sent);
        expect(log.entries.every((e) => e.attempts == 0), isTrue);
      },
    );

    test('a body that will not re-indent is shown as it is', () {
      final log = AnalyticsLogStream();
      final id = log.queued('app_opened', const {}, DateTime(2026));
      log.attempted(id, {'value': _Unencodable()});
      expect(log.entries.single.payload, '{value: unencodable}');
    });
  });

  group('the sink', () {
    tearDown(() {
      setAnalyticsForTest(null);
      analyticsAccount.clear();
    });

    test('under test it is muted, and shows its work where it can', () {
      setAnalyticsForTest(null);
      final sink = analytics;

      // A debug run has the debug surface, so the muted sink records rather
      // than dropping silently — see `_muted`.
      expect(sink, isA<MutedAnalytics>());
      expect(identical(analytics, sink), isTrue, reason: 'built once');
      final before = analyticsLog.entries.length;
      sink.track('app_opened', params: {'signed_in': false});
      final row = analyticsLog.entries.first;
      expect(analyticsLog.entries.length, before + 1);
      expect(row.name, 'app_opened');
      expect(row.status, AnalyticsEventStatus.dropped);
      expect(row.note, (sink as MutedAnalytics).reason);
      expect(analyticsRecorder, same(analyticsLog));
    });

    test('a test can swap the sink and put the old one back', () async {
      final previous = setAnalyticsForTest(const NoopAnalytics());
      expect(analytics, isA<NoopAnalytics>());
      await analytics.flush();
      await analytics.close();
      analytics.track('app_opened');
      expect(setAnalyticsForTest(previous), isA<NoopAnalytics>());
    });

    test('a muted sink has nothing to flush or close', () async {
      final muted = MutedAnalytics(
        AnalyticsLogStream(),
        'off',
        clock: () => DateTime(2026),
      );
      await muted.flush();
      await muted.close();
      muted.track('signed_in');
      expect(
        (muted.recorder as AnalyticsLogStream).entries.single.queuedAt,
        DateTime(2026),
      );
    });

    test('the account is who events are filed under, until sign-out', () {
      analyticsAccount.set(id: 'u1', email: 'a@example.com');
      expect(analyticsAccount.current, (id: 'u1', email: 'a@example.com'));
      analyticsAccount.clear();
      expect(analyticsAccount.current, (id: null, email: null));
    });

    test('the context never fails, with or without a readable bundle', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      // No plugin behind the channel: the version lookup throws, and costs the
      // version only.
      final bare = await resolveAnalyticsContext();
      expect(bare.appVersion, isEmpty);
      expect(bare.platform, isNotEmpty);
      expect(bare.release, kReleaseMode);

      PackageInfo.setMockInitialValues(
        appName: 'Harness',
        packageName: 'ai.autonomous.harness',
        version: '1.0.0',
        buildNumber: '45',
        buildSignature: '',
      );
      final read = await resolveAnalyticsContext();
      expect(read.appVersion, '1.0.0');
      expect(read.appBuild, '45');
    });
  });
}

class _Unencodable {
  @override
  String toString() => 'unencodable';
}
