import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/models.dart';
import 'package:harness/models/model_search_catalog.dart';
import 'package:harness/models/api_connections_controller.dart';
import 'package:harness/state/swarm_search.dart';
import 'package:harness/usage/models_menu_controller.dart';
import 'package:harness/widgets/resting_model_words.dart';

import 'support/model_manager.dart';

class _NoSubscriptions extends ModelsMenuController {
  @override
  List<Map<String, Object?>> get rows => const [];
}

class _WithSubscriptions extends ModelsMenuController {
  @override
  List<Map<String, Object?>> get rows => const [
    {'engine': 'codex', 'title': 'OpenAI'},
  ];
}

class _MachineSubscriptions extends ModelsMenuController {
  bool signedOut = false;

  @override
  List<Map<String, Object?>> get rows => [
    {
      'engine': 'codex',
      'title': 'OpenAI',
      'account': 'local-account',
      'status': signedOut ? 'Not signed in' : '50% remaining',
    },
    {
      'engine': 'codex',
      'title': 'OpenAI',
      'account': 'remote-account',
      'status': '75% remaining',
    },
  ];

  @override
  Map<String, Object?>? subscriptionFor(
    String engine, {
    required bool local,
    required String machineName,
  }) => engine != 'codex'
      ? null
      : local
      ? rows.first
      : machineName == 'Other computer'
      ? rows.last
      : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ModelManagerTestApp app;
  late ModelsMenuController subscriptions;
  late ModelSearchCatalog catalog;
  setUp(() {
    app = ModelManagerTestApp(ModelManagerConnection());
    subscriptions = _NoSubscriptions();
    catalog = ModelSearchCatalog(
      app.modelManager,
      subscriptions,
      pollHosts: false,
    );
  });
  tearDown(() {
    catalog.dispose();
    subscriptions.dispose();
    app.dispose();
  });

  test('local profiles are visibly distinct and searchable without managed-host privileges', () async {
    app.inventory = const GridModels(
      gridName: 'same-grid',
      models: [],
      grids: [
        GridSection(
          name: 'same-grid',
          own: false,
          source: 'local',
          label: 'Studio',
          profileId: 'a',
          targetId: 'local:a:fixture',
          models: [GridModel(id: 'SameModel', node: 'Studio')],
        ),
        GridSection(
          name: 'same-grid',
          own: false,
          source: 'local',
          label: 'Studio',
          profileId: 'b',
          targetId: 'local:b:fixture',
          models: [GridModel(id: 'SameModel', node: 'Studio')],
        ),
        GridSection(
          name: 'same-grid',
          own: false,
          source: 'shared',
          targetId: 'remote:same-grid',
          models: [GridModel(id: 'SameModel', node: 'Remote')],
        ),
      ],
    );
    await app.modelManager.refresh();
    final profiles = catalog.entries.values
        .where(
          (entry) => entry.gridModel?.targetId?.startsWith('local:') == true,
        )
        .toList();
    expect(profiles, hasLength(2));
    expect(
      profiles.map((entry) => entry.section),
      everyElement(ModelSearchSection.local),
    );
    expect(profiles.map((entry) => entry.source), [
      'Local · Studio · a',
      'Local · Studio · b',
    ]);
    for (final entry in profiles) {
      expect(entry.own, isFalse);
      expect(entry.controller, isNull);
      expect(entry.sharedBy, isNull);
      expect(entry.destination.detail, contains(entry.source));
      expect(entry.destination.fields, contains(entry.source.toLowerCase()));
    }
    expect(
      catalog.entries.values
          .singleWhere(
            (entry) => entry.gridModel?.targetId == 'remote:same-grid',
          )
          .section,
      ModelSearchSection.shared,
    );
    expect(app.actions, isEmpty);
  });

  test(
    'four sections separate installed and shared models from downloads',
    () async {
      final usage = _WithSubscriptions();
      final grouped = ModelSearchCatalog(
        app.modelManager,
        usage,
        pollHosts: false,
      );
      final search = SwarmSearchController(
        app,
        const [],
        models: grouped,
        offersCreate: true,
        adding: true,
      )..setQuery(':');
      try {
        app.localInventory = {
          'models': [
            {'id': 'available', 'name': 'AAA catalog'},
            {
              'id': 'installed',
              'name': 'ZZZ installed',
              'state': 'downloaded',
              'canStart': true,
            },
          ],
        };
        app.inventory = const GridModels(
          gridName: 'home',
          models: [],
          grids: [
            GridSection(
              name: 'Team',
              own: false,
              models: [GridModel(id: 'Shared Qwen', node: 'team.lan')],
            ),
          ],
        );
        app.modelManager.apis.connections = [
          const ApiConnection({'id': 'custom', 'name': 'Custom API'}),
        ];
        await app.modelManager.refresh();
        expect(search.rows.map((row) => row.title), [
          'OpenAI',
          'Custom API',
          '[ Add ]',
          'ZZZ installed',
          'AAA catalog',
          '[ Get models ]',
          'Shared Qwen · team.lan',
        ]);
        expect(search.rows.map(search.modelSection), [
          ModelSearchSection.subscriptions,
          ModelSearchSection.apis,
          ModelSearchSection.apis,
          ModelSearchSection.local,
          ModelSearchSection.local,
          ModelSearchSection.local,
          ModelSearchSection.shared,
        ]);
        search.move(
          search.rows.indexWhere(search.isModelDownloadsRow) - search.cursor,
        );
        expect(search.submit(), isNull);
        expect(search.modelDownloadsVisible, isTrue);
        expect(search.rows.map((row) => row.title), [
          'OpenAI',
          'Custom API',
          '[ Add ]',
          'ZZZ installed',
          'AAA catalog',
          '[ Hide catalog ]',
          'Shared Qwen · team.lan',
        ]);
        expect(search.selected!.title, 'AAA catalog');
        expect(search.modelRowAction(search.selected!), isNull);
        search.move(
          search.rows.indexWhere(search.isModelDownloadsRow) - search.cursor,
        );
        search.submit();
        expect(search.modelDownloadsVisible, isFalse);
        // The top-5 catalog model stays visible even after hiding the catalog.
        expect(search.rows.any((row) => row.title == 'AAA catalog'), isTrue);
        search.setQuery(':Local AI');
        expect(
          search.rows.where((row) => !row.isCreate).map((row) => row.title),
          ['ZZZ installed', 'AAA catalog'],
        );
        expect(app.actions, isEmpty);
      } finally {
        search.dispose();
        grouped.dispose();
        usage.dispose();
      }
    },
  );

  test(
    'own models precede shared models even without local inventory',
    () async {
      app.localReadFails = true;
      app.inventory = const GridModels(
        gridName: 'home',
        models: [],
        grids: [
          GridSection(
            name: 'Team',
            own: false,
            models: [GridModel(id: 'Shared model', node: 'team.lan')],
          ),
          GridSection(
            name: 'home',
            own: true,
            models: [GridModel(id: 'qwen3.8-27b', node: 'mac.lan')],
          ),
        ],
      );
      await app.modelManager.refresh();
      expect(catalog.rows.map((row) => row.title), [
        'qwen3.8-27b',
        'Shared model · team.lan',
      ]);
      final own = catalog.entries[catalog.rows.first.modelId]!;
      expect(own.source, 'On your machines');
      expect(own.node, 'mac.lan');
      expect(own.local, isNull);
      final search = SwarmSearchController(app, const [], models: catalog)
        ..setQuery(':local');
      addTearDown(search.dispose);
      expect(search.rows.map((row) => row.title), ['qwen3.8-27b']);
      search.setQuery(':mac.lan');
      expect(search.rows.map((row) => row.title), ['qwen3.8-27b']);
      expect(app.actions, isEmpty);
      expect(app.downloads, isEmpty);
    },
  );

  test('legacy own-grid replies remain visible in models', () async {
    app.localInventory = {'models': <Object>[]};
    app.inventory = const GridModels(
      gridName: 'home',
      models: [GridModel(id: 'Qwen', node: 'mac.lan')],
    );
    await app.modelManager.refresh();
    expect(catalog.rows.single.title, 'Qwen');
    expect(catalog.entries.values.single.source, 'On your machines');
  });

  test('Use identifies only the subscription available on the pane host', () {
    final usage = _MachineSubscriptions();
    final accounts = ModelSearchCatalog(
      app.modelManager,
      usage,
      pollHosts: false,
    );
    final search = SwarmSearchController(app, const [], models: accounts)
      ..setQuery(':OpenAI')
      ..setModelSelection('codex', app.inventory, machineId: 'm');
    try {
      final local = search.rows.firstWhere(
        (row) =>
            accounts.entries[row.modelId]?.subscription?['account'] ==
            'local-account',
      );
      final remote = search.rows.firstWhere(
        (row) =>
            accounts.entries[row.modelId]?.subscription?['account'] ==
            'remote-account',
      );
      expect(search.modelRowAction(local), 'Use');
      expect(search.modelRowAction(remote), isNull);
      search.setModelSelection('codex', app.inventory, machineId: 'other');
      expect(search.modelRowAction(local), isNull);
      expect(search.modelRowAction(remote), 'Use');
      search.setModelSelection('claude', app.inventory, machineId: 'm');
      expect(search.rows.any(search.canSelectModel), isFalse);
      search.setModelSelection('codex', app.inventory, machineId: 'm');
      usage.signedOut = true;
      expect(search.canSelectModel(local), isFalse);
      expect(app.actions, isEmpty);
    } finally {
      search.dispose();
      accounts.dispose();
      usage.dispose();
    }
  });

  test(
    'matching model names never hide hosts or grant local controls',
    () async {
      app.localInventory = {
        'models': [
          {'id': 'qwen', 'name': 'Qwen'},
        ],
      };
      app.inventory = const GridModels(
        gridName: 'home',
        models: [
          GridModel(id: 'qwen', node: 'This Mac'),
          GridModel(id: 'qwen', node: 'mac.lan'),
        ],
      );
      await app.modelManager.refresh();
      expect(catalog.rows, hasLength(3));
      expect(catalog.entries, hasLength(3));
      expect(
        catalog.entries.values.where((entry) => entry.local != null),
        hasLength(1),
      );
      expect(
        catalog.entries.values.where(
          (entry) => entry.source == 'On your machines',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'each linked host exposes its own inventory without a served Grid row',
    () async {
      const model = {
        'id': 'weights.gguf',
        'name': 'Qwen',
        'state': 'downloaded',
        'canStart': true,
      };
      app.localInventory = {
        'models': [model],
        'supportsDownload': true,
      };
      app.machineStates['other']!
        ..connectionStatus = ConnectionStatus.connected
        ..nodeOnline = true;
      app.machineInventories['other'] = {
        'models': [model],
      };
      catalog.setVisible(true);
      await catalog.refresh();
      expect(
        catalog.entries.values.where((entry) => entry.local != null),
        hasLength(2),
      );
      final remote = catalog.entries.values.singleWhere(
        (entry) => entry.controller?.targetMachineId == 'other',
      );
      expect(remote.gridModel, isNull);
      expect(remote.controller!.supportsDownload, isFalse);
      await remote.controller!.control(remote.local!, 'start');
      expect(app.actions, [
        (machine: 'other', model: 'weights.gguf', start: true),
      ]);
      expect(app.localInventory['models'], [model]);
      expect(app.connection.creations, isEmpty);
    },
  );

  test(
    'unlinked and offline hosts are not queried or given controls',
    () async {
      final remote = app.machineStates['other']!
        ..connectionStatus = ConnectionStatus.connected
        ..nodeOnline = true
        ..needsLink = true;
      catalog.setVisible(true);
      await catalog.refresh();
      expect(app.inventoryReads, isNot(contains('other')));
      remote
        ..needsLink = false
        ..nodeOnline = false;
      app.notifyListeners();
      await catalog.refresh();
      expect(app.inventoryReads, isNot(contains('other')));
      expect(app.actions, isEmpty);
      expect(app.connection.creations, isEmpty);
    },
  );

  test(
    'selection follows the target pane machine model capabilities',
    () async {
      app.localInventory = {'models': <Object>[]};
      app.inventory = const GridModels(
        gridName: 'home',
        models: [GridModel(id: 'Qwen', node: 'mac.lan')],
      );
      await app.modelManager.refresh();
      final search = SwarmSearchController(app, const [], models: catalog)
        ..setQuery(':Qwen')
        ..setModelSelection(
          'codex',
          const GridModels.unreachable(),
          machineId: 'other',
        );
      addTearDown(search.dispose);
      expect(search.canSelectModel(search.selected), isFalse);
      // A live picture from the pane's host updates availability without reopening.
      app.gridPictures.adopt('other', app.inventory);
      expect(search.canSelectModel(search.selected), isTrue);
      expect(search.actionLabel(search.selected), 'Use');
      app.gridPictures.adopt(
        'other',
        const GridModels(
          gridName: 'home',
          models: [GridModel(id: 'Qwen', node: 'mac.lan')],
          localModelEngines: {'claude'},
        ),
      );
      expect(search.canSelectModel(search.selected), isFalse);
      expect(search.actionLabel(search.selected), 'Unavailable');
      expect(app.actions, isEmpty);
    },
  );

  test(
    'own model states use the existing offline and resting wording',
    () async {
      app.localInventory = {'models': <Object>[]};
      app.inventory = const GridModels(
        gridName: 'home',
        models: [],
        grids: [
          GridSection(
            name: 'home',
            own: true,
            state: GridSectionState.asleep,
            lastKnownAge: 120,
            models: [
              GridModel(id: 'Resting', node: 'mac.lan'),
              GridModel(
                id: 'Offline',
                node: 'rig.lan',
                unavailable: GridModelUnavailable(machine: 'Rig'),
              ),
            ],
          ),
        ],
      );
      await app.modelManager.refresh();
      final rows = catalog.entries.values.toList();
      expect(rows[0].status, restingSubtitle(120));
      expect(rows[1].status, offlineRowSentence('Rig'));
      final search = SwarmSearchController(app, const [], models: catalog)
        ..setQuery(':')
        ..setModelSelection('codex', app.inventory, machineId: 'm');
      try {
        final resting = search.rows.firstWhere((row) => row.title == 'Resting');
        final offline = search.rows.firstWhere((row) => row.title == 'Offline');
        expect(search.modelRowAction(resting), 'Use');
        expect(search.modelRowAction(offline), isNull);
        expect(search.canSelectModel(offline), isFalse);
      } finally {
        search.dispose();
      }
    },
  );
  test(
    'same-named local and remote models keep distinct routes through search',
    () async {
      app.localInventory = {'models': <Object>[]};
      app.inventory = GridModels.fromReply({
        'gridName': 'home',
        'grids': [
          for (final target in ['remote:home', 'local:fixture'])
            {
              'name': 'home',
              'own': target.startsWith('remote:'),
              'source': target.startsWith('remote:') ? 'private' : 'local',
              'label': 'Fixture fleet',
              'profileId': 'fixture',
              'targetId': target,
              'engines': ['codex'],
              'models': [
                {'id': 'same-model', 'node': 'fixture'},
              ],
            },
        ],
      });
      await app.modelManager.refresh();
      final entries = catalog.entries.values
          .where((entry) => entry.gridModel?.id == 'same-model')
          .toList();
      expect(entries, hasLength(2));
      expect(entries.map((entry) => entry.gridModel!.targetId).toSet(), {
        'local:fixture',
        'remote:home',
      });
      final search = SwarmSearchController(app, const [], models: catalog)
        ..setQuery(':')
        ..setModelSelection('codex', app.inventory, machineId: 'm');
      try {
        final rows = search.rows
            .where(
              (row) =>
                  catalog.entries[row.modelId]?.gridModel?.id == 'same-model',
            )
            .toList();
        expect(rows, hasLength(2));
        expect(
          rows.map((row) => search.selectableGridModel(row)?.targetId).toSet(),
          {'local:fixture', 'remote:home'},
        );
      } finally {
        search.dispose();
      }
    },
  );
}
