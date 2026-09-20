import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/core/wsl_preferences.dart';
import 'package:harness/widgets/wsl_account_dialog.dart';

class _Storage implements LocalKeyValueStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('disk unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (fail) throw StateError('disk unavailable');
    values.remove(key);
  }
}

Future<void> _mount(
  WidgetTester tester,
  WslPreferencesStore store, {
  List<String> distros = const ['Ubuntu', 'docker-desktop'],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showWslAccountDialog(
              context,
              store: store,
              listDistros: () async => distros,
            ),
            child: const Text('Account'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Account'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'explicit root selection persists only for next launch, cancel preserves it',
    (tester) async {
      final storage = _Storage();
      final store = WslPreferencesStore(storage: storage);
      addTearDown(store.dispose);
      await store.load();
      await _mount(tester, store);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(find.text('docker-desktop'), findsNothing);
      await tester.enterText(find.byType(TextField), 'root');
      await tester.pump();
      expect(find.textContaining('administrator access'), findsOneWidget);
      await tester.tap(find.text('Save for next launch'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(store.value, isNull);
      expect(
        store.savedSelection,
        const WslSelection(distro: 'Ubuntu', username: 'root'),
      );
      expect(store.restartRequired, isTrue);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'different');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(store.savedSelection?.username, 'root');
      final reopened = WslPreferencesStore(storage: storage);
      addTearDown(reopened.dispose);
      await reopened.load();
      expect(reopened.value?.username, 'root');
      expect(reopened.restartRequired, isFalse);
    },
  );

  testWidgets('invalid username and failed save do not change active account', (
    tester,
  ) async {
    final storage = _Storage();
    final store = WslPreferencesStore(storage: storage);
    addTearDown(store.dispose);
    await _mount(tester, store);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'root; touch /tmp/other');
    await tester.tap(find.text('Save for next launch'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(storage.values, isEmpty);
    storage.fail = true;
    await tester.enterText(find.byType(TextField), 'developer');
    await tester.tap(find.text('Save for next launch'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not save this choice'), findsOneWidget);
    expect(store.value, isNull);
    expect(store.restartRequired, isFalse);
  });

  testWidgets(
    'an unavailable saved distro is not replaced with another distro',
    (tester) async {
      final storage = _Storage();
      final previous = WslPreferencesStore(storage: storage);
      addTearDown(previous.dispose);
      await previous.save(
        const WslSelection(distro: 'OldUbuntu', username: 'developer'),
      );
      final store = WslPreferencesStore(storage: storage);
      addTearDown(store.dispose);
      await store.load();
      await _mount(tester, store);
      expect(find.text('OldUbuntu'), findsOneWidget);
      await tester.tap(find.text('Save for next launch'));
      await tester.pumpAndSettle();
      expect(
        find.text('Choose an available Linux distribution.'),
        findsOneWidget,
      );
      expect(store.value?.distro, 'OldUbuntu');
      expect(store.restartRequired, isFalse);
    },
  );
}
