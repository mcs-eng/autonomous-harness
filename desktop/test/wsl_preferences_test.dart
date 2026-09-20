import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/harness_file_store.dart';
import 'package:harness/core/wsl_preferences.dart';
import 'package:harness/core/wsl_runtime.dart';

class _MemoryStore implements LocalKeyValueStore {
  final values = <String, String>{};
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('synthetic read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('synthetic write failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failWrite) throw StateError('synthetic delete failure');
    values.remove(key);
  }
}

void main() {
  const root = WslSelection(distro: 'Ubuntu', username: 'root');
  const other = WslSelection(distro: 'Debian', username: 'developer');

  for (final choice in <WslSelection?>[root, null]) {
    test(
      'a corrupt account file stays blocked until explicit save and restart: $choice',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'wsl-account-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final storage = HarnessFileStore(
          directory: directory,
          recoverCorruption: false,
        );
        await storage.stateFile.writeAsString(
          '{synthetic malformed account file',
        );
        final store = WslPreferencesStore(storage: storage);
        await store.load();
        expect(store.loadError, isNotNull);
        expect(
          await storage.stateFile.readAsString(),
          '{synthetic malformed account file',
        );
        final secondLaunch = WslPreferencesStore(storage: storage);
        await secondLaunch.load();
        expect(secondLaunch.loadError, isNotNull);

        await store.save(choice);
        expect(store.restartRequired, isTrue);
        expect(WslRuntime(preferencesStore: store).selectionError, isNotNull);
        final backups = (await directory.list().toList()).where(
          (entry) => entry.path.contains('state.corrupt-'),
        );
        expect(backups, hasLength(1));
        expect(
          await File(backups.single.path).readAsString(),
          '{synthetic malformed account file',
        );
        final reopened = WslPreferencesStore(storage: storage);
        await reopened.load();
        expect(reopened.loadError, isNull);
        expect(reopened.value, choice);
      },
    );
  }

  test(
    'saving a choice affects only the next launch, including new runtimes',
    () async {
      final storage = _MemoryStore();
      final store = WslPreferencesStore(storage: storage);
      await store.load();
      expect(store.value, isNull);
      expect(store.loadError, isNull);
      await store.save(root);
      expect(store.value, isNull);
      expect(store.savedSelection, root);
      expect(store.restartRequired, isTrue);
      expect(WslRuntime(preferencesStore: store).selection, isNull);
      await store.load();
      expect(
        store.value,
        isNull,
        reason: 'a second load cannot switch a live account',
      );

      final reopened = WslPreferencesStore(storage: storage);
      await reopened.load();
      final running = WslRuntime(preferencesStore: reopened);
      expect(reopened.value, root);
      expect(reopened.restartRequired, isFalse);
      await reopened.save(other);
      expect(reopened.value, root);
      expect(reopened.savedSelection, other);
      expect(running.selection, root);
      expect(WslRuntime(preferencesStore: reopened).selection, root);
      await reopened.save(root);
      expect(reopened.restartRequired, isFalse);
      await reopened.save(null);
      expect(reopened.value, root);
      expect(reopened.savedSelection, isNull);
      expect(reopened.restartRequired, isTrue);
      final reset = WslPreferencesStore(storage: storage);
      await reset.load();
      expect(reset.value, isNull);
    },
  );

  test('failed writes propagate without publishing a pending choice', () async {
    final storage = _MemoryStore();
    final store = WslPreferencesStore(storage: storage);
    await store.load();
    storage.failWrite = true;
    await expectLater(store.save(root), throwsStateError);
    expect(store.savedSelection, isNull);
    expect(store.restartRequired, isFalse);
    expect(storage.values, isEmpty);
  });

  for (final raw in [
    '',
    'null',
    '{"version":2,"distro":"Ubuntu","username":"root"}',
    '{"version":1,"distro":"Ubuntu","username":"--root"}',
    '{"version":1,"distro":"docker-desktop","username":"root"}',
  ]) {
    test(
      'invalid saved configuration blocks execution until repaired and reopened: $raw',
      () async {
        final storage = _MemoryStore()..values[WslPreferencesStore.key] = raw;
        final store = WslPreferencesStore(storage: storage);
        await store.load();
        expect(store.loadError, isNotNull);
        var calls = 0;
        final runtime = WslRuntime(
          preferencesStore: store,
          runProcess: (_, _, {environment}) async {
            calls++;
            return ProcessResult(0, 0, '', '');
          },
        );
        final probe = await runtime.findHarness();
        expect(probe.failure, WslProbeFailure.invalidSelection);
        expect(calls, 0);
        expect(
          () => runtime.buildArguments(distro: 'Ubuntu', script: 'true'),
          throwsStateError,
        );
        await store.save(null);
        expect(store.restartRequired, isTrue);
        expect(WslRuntime(preferencesStore: store).selectionError, isNotNull);
        final reopened = WslPreferencesStore(storage: storage);
        await reopened.load();
        expect(reopened.loadError, isNull);
      },
    );
  }

  test(
    'unreadable preferences do not silently select the WSL default',
    () async {
      final storage = _MemoryStore()..failRead = true;
      final store = WslPreferencesStore(storage: storage);
      await store.load();
      expect(WslRuntime(preferencesStore: store).selectionError, isNotNull);
    },
  );

  test(
    'selection validation accepts real accounts and rejects unsafe inputs',
    () {
      for (final username in [
        'root',
        'developer',
        '_service',
        'service-user',
        'machine\$',
      ]) {
        expect(
          WslSelection.validationError(
            distro: 'Ubuntu Dev',
            username: username,
          ),
          isNull,
        );
      }
      for (final username in [
        '',
        '-root',
        'root\n',
        'root;true',
        'ROOT',
        'a b',
      ]) {
        expect(
          WslSelection.validationError(distro: 'Ubuntu', username: username),
          isNotNull,
        );
      }
      for (final distro in [
        '',
        '-Ubuntu',
        ' Ubuntu',
        'Ubuntu\n',
        'docker-desktop-data',
      ]) {
        expect(
          WslSelection.validationError(distro: distro, username: 'root'),
          isNotNull,
        );
      }
      expect(root, const WslSelection(distro: 'Ubuntu', username: 'root'));
    },
  );

  test(
    'selected discovery never falls back to another distro or account',
    () async {
      final seen = <List<String>>[];
      final runtime = WslRuntime(
        selection: root,
        runProcess: (_, args, {environment}) async {
          seen.add(args);
          return ProcessResult(0, 0, 'cli missing\ntmux yes\n', '');
        },
      );
      final absent = await runtime.findHarness(distros: ['Debian']);
      expect(absent.failure, WslProbeFailure.selectedDistroUnavailable);
      expect(seen, isEmpty);
      final missing = await runtime.findHarness(distros: ['Debian', 'Ubuntu']);
      expect(missing.distro, 'Ubuntu');
      expect(missing.found, isFalse);
      expect(seen, hasLength(1));
      expect(seen.single.take(4), ['-d', 'Ubuntu', '--user', 'root']);
      expect(
        () => runtime.buildArguments(distro: 'Debian', script: 'true'),
        throwsStateError,
      );
    },
  );

  test('identity, tool checks, managed CLI and bundled paths share the selected account', () async {
    final seen = <List<String>>[];
    final runtime = WslRuntime(
      selection: root,
      runProcess: (_, args, {environment}) async {
        seen.add(args);
        return ProcessResult(0, 0, '0', '');
      },
    );
    await runtime.computerId(distro: 'Ubuntu');
    await runtime.hasTmux(distro: 'Ubuntu');
    await runtime.canInstallUnattended(distro: 'Ubuntu');
    const probe = WslHarnessProbe(distro: 'Ubuntu');
    seen.add(runtime.cliArguments(probe, ['version']));
    seen.add(
      runtime.bundledCliArguments(probe, r'C:\Example App\cli', [
        'auth',
        'status',
      ]),
    );
    for (final args in seen) {
      expect(args.take(4), ['-d', 'Ubuntu', '--user', 'root']);
    }
    expect(seen.last, contains(r'C:\Example App\cli'));
    expect(seen.last.last, 'status');
  });
}
