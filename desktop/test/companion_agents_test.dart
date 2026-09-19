import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/companion_agents.dart';

class FakeCompanionProcess implements Process {
  final output = StreamController<List<int>>();
  final errors = StreamController<List<int>>();
  final exited = Completer<int>();
  final input = StreamController<List<int>>();
  late final IOSink sink;
  bool killed = false;

  FakeCompanionProcess() {
    sink = IOSink(input.sink);
    input.stream.listen(
      (_) {},
      onDone: () {
        finish();
      },
    );
  }

  void say(String line) => output.add(utf8.encode('$line\n'));
  void fail(String line) => errors.add(utf8.encode('$line\n'));
  void finish() {
    if (!exited.isCompleted) exited.complete(0);
  }

  @override
  Future<int> get exitCode => exited.future;
  @override
  int get pid => 1234;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  IOSink get stdin => sink;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish();
    return true;
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  const endpoint = 'http://127.0.0.1:54321/?token=private-test-token';

  test(
    'passes distro and hostile folder as literal argv, not shell source',
    () {
      const folder = r"/home/a space/'$(touch /tmp/unwanted); & project";
      final args = deepSeekCompanionArguments(
        distro: 'Ubuntu personal',
        folder: folder,
      );
      expect(args.take(7), [
        '-d',
        'Ubuntu personal',
        '-e',
        'setsid',
        '--wait',
        'bash',
        '-ic',
      ]);
      expect(args.last, folder);
      expect(args[7], isNot(contains(folder)));
      expect(args[7], contains(r'cd -- "$1"'));
      expect(args[7], contains('dsh web --host 127.0.0.1 --port 0 --no-open'));
      expect(args[7], isNot(contains('npm install')));
      expect(args[7], contains('kill -TERM -- -\$\$'));
      expect(args[7], isNot(contains('pkill')));
    },
  );

  test('rejects missing distro and non-Linux project folders', () {
    expect(
      () => deepSeekCompanionArguments(distro: '', folder: '/tmp'),
      throwsArgumentError,
    );
    for (final folder in ['relative', r'C:\work', '/tmp\x00oops']) {
      expect(
        () => deepSeekCompanionArguments(distro: 'Ubuntu', folder: folder),
        throwsArgumentError,
      );
    }
  });

  test('accepts only exact authenticated loopback startup URLs', () {
    expect(parseDeepSeekLaunchUri('dsh web: $endpoint'), Uri.parse(endpoint));
    for (final line in [
      endpoint,
      'prefix dsh web: $endpoint',
      'dsh web: https://127.0.0.1:42/?token=a',
      'dsh web: http://localhost:42/?token=a',
      'dsh web: http://0.0.0.0:42/?token=a',
      'dsh web: http://127.0.0.1.evil:42/?token=a',
      'dsh web: http://user@127.0.0.1:42/?token=a',
      'dsh web: http://127.0.0.1:0/?token=a',
      'dsh web: http://127.0.0.1:65536/?token=a',
      'dsh web: http://127.0.0.1:42/',
      'dsh web: http://127.0.0.1:42/?token=',
      'dsh web: http://127.0.0.1:42/?token=%zz',
      'dsh web: http://127.0.0.1:42/?token=a&token=b',
      'dsh web: http://127.0.0.1:42/?token=a&redirect=evil',
      'dsh web: http://127.0.0.1:42/?token=a#fragment',
      'dsh web: $endpoint trailing',
    ]) {
      expect(parseDeepSeekLaunchUri(line), isNull, reason: line);
    }
  });

  test('retains one ready server and stops via stdin ownership', () async {
    final process = FakeCompanionProcess();
    var starts = 0;
    final companion = DeepSeekCompanion(
      startProcess: (executable, args) async {
        expect(executable, 'wsl.exe');
        starts++;
        return process;
      },
    );
    addTearDown(companion.dispose);
    final operation = companion.start(distro: 'Ubuntu', folder: '/tmp/project');
    expect(companion.starting, isTrue);
    await tick();
    process.say('dsh web: $endpoint');
    await operation;
    expect(companion.running, isTrue);
    expect(companion.starting, isFalse);
    expect(companion.launchUri, Uri.parse(endpoint));
    expect(companion.status, isNot(contains('private-test-token')));
    await companion.start(distro: 'Ubuntu', folder: '/tmp/project');
    expect(starts, 1);
    await expectLater(
      companion.start(distro: 'Ubuntu', folder: '/elsewhere'),
      throwsStateError,
    );
    await companion.stop();
    expect(companion.running, isFalse);
    expect(companion.launchUri, isNull);
    expect(process.exited.isCompleted, isTrue);
    expect(process.killed, isFalse);
  });

  test(
    'missing install produces actionable status without raw stderr',
    () async {
      final process = FakeCompanionProcess();
      final companion = DeepSeekCompanion(
        startProcess: (_, _) async => process,
      );
      addTearDown(companion.dispose);
      final operation = companion.start(distro: 'Ubuntu', folder: '/tmp');
      final expectation = expectLater(operation, throwsStateError);
      await tick();
      process.fail('arbitrary secret-token must not appear');
      process.fail('HARNESS_DEEPSEEK_ERROR:MISSING_DSH');
      await expectation;
      expect(companion.status, contains(deepSeekInstallCommand));
      expect(companion.status, isNot(contains('secret-token')));
      expect(companion.starting, isFalse);
    },
  );

  test('bounds startup and cleans up an unready child', () async {
    final process = FakeCompanionProcess();
    final companion = DeepSeekCompanion(
      startProcess: (_, _) async => process,
      startupTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(companion.dispose);
    await expectLater(
      companion.start(distro: 'Ubuntu', folder: '/tmp'),
      throwsStateError,
    );
    expect(companion.status, contains('timed out'));
    expect(process.exited.isCompleted, isTrue);
    expect(companion.launchUri, isNull);
  });

  test(
    'stopping during pending spawn shuts down that eventual child',
    () async {
      final process = FakeCompanionProcess();
      final spawn = Completer<Process>();
      final companion = DeepSeekCompanion(startProcess: (_, _) => spawn.future);
      addTearDown(companion.dispose);
      final operation = companion.start(distro: 'Ubuntu', folder: '/tmp');
      await companion.stop();
      spawn.complete(process);
      await operation;
      expect(process.exited.isCompleted, isTrue);
      expect(companion.running, isFalse);
      expect(companion.launchUri, isNull);
    },
  );

  test('unexpected exit clears stale authenticated URL', () async {
    final process = FakeCompanionProcess();
    final companion = DeepSeekCompanion(startProcess: (_, _) async => process);
    addTearDown(companion.dispose);
    final operation = companion.start(distro: 'Ubuntu', folder: '/tmp');
    await tick();
    process.say('dsh web: $endpoint');
    await operation;
    process.finish();
    await tick();
    expect(companion.running, isFalse);
    expect(companion.launchUri, isNull);
  });

  test('finds official Windows app without a shell or credentials', () {
    final checked = <String>[];
    final found = findZcodeExecutable(
      environment: {
        'LOCALAPPDATA': r'C:\Users\Test User\AppData\Local',
        'ProgramFiles': r'C:\Program Files',
      },
      exists: (path) {
        checked.add(path);
        return path == r'C:\Program Files\ZCode\ZCode.exe';
      },
    );
    expect(found, r'C:\Program Files\ZCode\ZCode.exe');
    expect(
      checked.first,
      r'C:\Users\Test User\AppData\Local\Programs\ZCode\ZCode.exe',
    );
    expect(findZcodeExecutable(environment: {}, exists: (_) => true), isNull);
  });

  test(
    'real WSL companion authenticates locally and stops its server',
    () async {
      final env = Platform.environment;
      final fixtureHome = env['HARNESS_TEST_DSH_HOME']!;
      final fixtureBin = env['HARNESS_TEST_DSH_BIN']!;
      final nodeBin = env['HARNESS_TEST_DSH_NODE_BIN']!;
      final project = env['HARNESS_TEST_DSH_PROJECT']!;
      final companion = DeepSeekCompanion(
        startProcess: (executable, arguments) {
          final args = List<String>.of(arguments);
          args[7] =
              r'''export HOME="$2"
export DSH_HOME="$2/dsh"
export PATH="$3:$4:$PATH"
''' +
              args[7];
          args.addAll([fixtureHome, fixtureBin, nodeBin]);
          return Process.start(executable, args);
        },
      );
      final client = HttpClient();
      addTearDown(() async {
        await companion.stop();
        companion.dispose();
        client.close(force: true);
      });
      await companion.start(
        distro: env['HARNESS_TEST_DSH_DISTRO'] ?? 'Ubuntu',
        folder: project,
      );
      final uri = companion.launchUri!;
      expect(companion.running, isTrue);
      final first = await client.getUrl(uri);
      first.followRedirects = false;
      final response = await first.close();
      expect(response.statusCode, anyOf(HttpStatus.found, HttpStatus.seeOther));
      final cookies = response.cookies;
      final location = response.headers.value(HttpHeaders.locationHeader);
      await response.drain<void>();
      expect(cookies.isNotEmpty, isTrue);
      expect(location != null, isTrue);
      final second = await client.getUrl(uri.resolve(location!));
      second.cookies.addAll(cookies);
      final page = await second.close();
      expect(page.statusCode, HttpStatus.ok);
      final html = await utf8.decoder.bind(page).join();
      expect(html.toLowerCase().contains('<html'), isTrue);
      final port = uri.port;
      await companion.stop();
      expect(companion.launchUri, isNull);
      expect(companion.running, isFalse);
      var closed = false;
      for (var attempt = 0; attempt < 20; attempt++) {
        try {
          final socket = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 250),
          );
          socket.destroy();
        } on SocketException {
          closed = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(
        closed,
        isTrue,
        reason: 'The owned server must stop listening after stdin closes.',
      );
    },
    skip:
        !Platform.isWindows ||
        Platform.environment['HARNESS_TEST_DEEPSEEK_COMPANION'] != '1',
  );
}
