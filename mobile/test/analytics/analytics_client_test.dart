import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness_mobile/analytics/analytics_client.dart';
import 'package:harness_mobile/analytics/analytics_config.dart';

/// The real transport, over a `dart:io` client that never opens a socket:
/// [HttpOverrides] hands it [_FakeClient], which answers from [_FakeClient.answer].
///
/// What is pinned is the mapping from what the ingest host did to what the
/// queue does next — send, retry or drop — because a wrong answer there either
/// loses events (a retryable failure dropped) or wedges the queue forever (a
/// refusal retried).
class _FakeClient implements HttpClient {
  _FakeClient(this.answer);

  /// A status code, or something to throw from the request.
  Object answer;
  final requests = <_FakeRequest>[];
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    final request = _FakeRequest(url, answer);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.url, this.answer);

  final Uri url;
  final Object answer;
  final sentHeaders = <String, Object>{};
  final body = <int>[];

  @override
  int contentLength = -1;

  @override
  HttpHeaders get headers => _FakeHeaders(sentHeaders);

  @override
  void add(List<int> data) => body.addAll(data);

  @override
  Future<HttpClientResponse> close() async {
    final answer = this.answer;
    if (answer is int) return _FakeResponse(answer);
    throw answer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHeaders implements HttpHeaders {
  _FakeHeaders(this.values);

  final Map<String, Object> values;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      values[name] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode);

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([utf8.encode('{"ok":true}')]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final config = AnalyticsConfig(
    endpoint: Uri.parse('https://analytics.invalid/api/v1/event_tracking'),
    writeKey: 'write-key',
  );

  Future<(AnalyticsSendResult, _FakeClient)> sendWith(Object answer) async {
    final fake = _FakeClient(answer);
    final result = await HttpOverrides.runZoned(
      () => HttpAnalyticsClient(config).send({'event_name': 'app_opened'}),
      createHttpClient: (_) => fake,
    );
    return (result, fake);
  }

  test(
    'one POST to the endpoint, keyed the way the web client keys it',
    () async {
      final (result, fake) = await sendWith(200);

      expect(result, AnalyticsSendResult.sent);
      final request = fake.requests.single;
      expect(request.url, config.endpoint);
      // The key verbatim — no `Bearer` — which is what the server reads.
      expect(request.sentHeaders[HttpHeaders.authorizationHeader], 'write-key');
      expect(
        request.sentHeaders[HttpHeaders.contentTypeHeader],
        'application/json',
      );
      expect(jsonDecode(utf8.decode(request.body)), {
        'event_name': 'app_opened',
      });
      expect(request.contentLength, request.body.length);
      expect(fake.connectionTimeout, const Duration(seconds: 10));
    },
  );

  test(
    'a 2xx is sent, "come back later" retries, a refusal is dropped',
    () async {
      expect((await sendWith(204)).$1, AnalyticsSendResult.sent);
      expect((await sendWith(408)).$1, AnalyticsSendResult.retry);
      expect((await sendWith(429)).$1, AnalyticsSendResult.retry);
      expect((await sendWith(500)).$1, AnalyticsSendResult.retry);
      expect((await sendWith(503)).$1, AnalyticsSendResult.retry);
      expect((await sendWith(400)).$1, AnalyticsSendResult.rejected);
      expect((await sendWith(401)).$1, AnalyticsSendResult.rejected);
      expect((await sendWith(302)).$1, AnalyticsSendResult.rejected);
    },
  );

  test(
    'a phone off the network retries rather than losing the event',
    () async {
      expect(
        (await sendWith(const SocketException('offline'))).$1,
        AnalyticsSendResult.retry,
      );
      expect(
        (await sendWith(TimeoutException('slow'))).$1,
        AnalyticsSendResult.retry,
      );
      expect(
        (await sendWith(const HttpException('reset'))).$1,
        AnalyticsSendResult.retry,
      );
      // Anything else would fail identically every time: the event goes.
      expect(
        (await sendWith(const HandshakeException('bad cert'))).$1,
        AnalyticsSendResult.rejected,
      );
    },
  );

  test('one connection for the life of the app, released on dispose', () async {
    final fake = _FakeClient(200);
    await HttpOverrides.runZoned(() async {
      final client = HttpAnalyticsClient(config);
      await client.send({'event_name': 'app_opened'});
      await client.send({'event_name': 'signed_in'});
      client.dispose();
      expect(fake.requests, hasLength(2));
      expect(fake.closed, isTrue);
      // Spent: nothing more goes on the wire.
      expect(
        await client.send({'event_name': 'signed_out'}),
        AnalyticsSendResult.rejected,
      );
      expect(fake.requests, hasLength(2));
    }, createHttpClient: (_) => fake);
  });
}
