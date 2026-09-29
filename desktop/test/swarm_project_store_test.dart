import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/state/swarm_catalog.dart';

class _Memory implements LocalKeyValueStore {
  _Memory([String? initial]) {
    if (initial != null) values['swarm_projects_v1'] = initial;
  }

  final values = <String, String>{};
  bool failWrites = false;
  int writes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('disk full');
    writes++;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

const _notebook = SavedSwarmProject(
  machineId: 'm',
  path: '/work/notebook',
  name: 'Notebook',
);
const _other = SavedSwarmProject(
  machineId: 'm',
  path: '/work/other',
  name: 'Other',
);

void main() {
  test('remove forgets only that project and persists the rest', () async {
    final memory = _Memory();
    final store = SwarmProjectStore(storage: memory);
    await store.add(_notebook);
    await store.add(_other);
    expect(await store.remove(_notebook.id), isTrue);
    expect(store.projects.map((p) => p.path), ['/work/other']);
    expect(store.error, isNull);
    final reloaded = SwarmProjectStore(storage: memory);
    await reloaded.load();
    expect(reloaded.projects.map((p) => p.path), ['/work/other']);
  });

  test('a trailing slash in the saved path still matches its id', () async {
    final store = SwarmProjectStore(storage: _Memory());
    await store.add(
      const SavedSwarmProject(
        machineId: 'm',
        path: '/work/notebook/',
        name: 'Notebook',
      ),
    );
    expect(await store.remove(_notebook.id), isTrue);
    expect(store.projects, isEmpty);
  });

  test('removing a project that is not saved writes nothing', () async {
    final memory = _Memory();
    final store = SwarmProjectStore(storage: memory);
    await store.add(_notebook);
    final before = memory.writes;
    expect(await store.remove(_other.id), isTrue);
    expect(memory.writes, before);
    expect(store.projects.map((p) => p.path), ['/work/notebook']);
  });

  test(
    'a failed write keeps the project, says so, and a retry succeeds',
    () async {
      final memory = _Memory();
      final store = SwarmProjectStore(storage: memory);
      await store.add(_notebook);
      var notified = 0;
      store.addListener(() => notified++);
      memory.failWrites = true;
      expect(await store.remove(_notebook.id), isFalse);
      expect(store.projects.map((p) => p.path), ['/work/notebook']);
      expect(store.error, 'Could not remove this project. Try again.');
      expect(notified, 1);
      expect(memory.values['swarm_projects_v1'], contains('/work/notebook'));
      memory.failWrites = false;
      expect(await store.remove(_notebook.id), isTrue);
      expect(store.projects, isEmpty);
      expect(store.error, isNull);
      expect(memory.values['swarm_projects_v1'], '[]');
    },
  );

  test('remove runs after a write that is already queued', () async {
    final memory = _Memory();
    final store = SwarmProjectStore(storage: memory);
    unawaited(store.add(_notebook));
    unawaited(store.add(_other));
    expect(await store.remove(_notebook.id), isTrue);
    expect(store.projects.map((p) => p.path), ['/work/other']);
    expect(memory.values['swarm_projects_v1'], isNot(contains('notebook')));
  });

  test('a catalog that could not be read is never written over', () async {
    final memory = _Memory('{"not":"a list"}');
    final store = SwarmProjectStore(storage: memory);
    expect(await store.remove(_notebook.id), isFalse);
    expect(memory.writes, 0);
    expect(memory.values['swarm_projects_v1'], '{"not":"a list"}');
    expect(store.error, isNotNull);
  });
}
