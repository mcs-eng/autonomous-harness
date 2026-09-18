import 'dart:async';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/auth/auth_session.dart';
import 'package:harness/core/config.dart';
import 'package:harness/core/engine_availability.dart';
import 'package:harness/core/models.dart';
import 'package:harness/shared/widgets/app_choice_picker.dart';
import 'package:harness/shared/widgets/app_select_field.dart';
import 'package:harness/state/app_state.dart';
import 'package:harness/shortcuts/app_keymap.dart';
import 'package:harness/core/project_folder.dart';
import 'package:harness/state/pane_arrangement.dart';
import 'package:harness/state/swarm_catalog.dart';
import 'package:harness/terminal/terminal_binary.dart';
import 'package:harness/terminal/terminal_session.dart';
import 'package:xterm/xterm.dart';

import 'swarm_screen_test.dart' show mount, terminal;
import 'swarm_interactions_test.dart' show chord;
import 'keymap_host_test.dart' show MemoryKeymap;
import 'keymap_runtime_test.dart' as runtime;

final _newHarness = find.byKey(const ValueKey('harness-start-new'));
final _startInput = find.byKey(const ValueKey('harness-start-search'));

class _FirstUseApp extends AppNotifier {
  _FirstUseApp()
    : super(
        config: AppConfig.dev,
        authSession: AuthSession(),
        configStore: null,
      ) {
    hasNavigationRail = false;
    const machine = Machine(
      machineId: 'm',
      name: 'My computer',
      authMode: MachineAuthMode.remote,
    );
    machines = [machine];
    machineStates['m'] = MachineState(machine)
      ..localOnly = true
      ..nodeOnline = true
      ..agentLoadStatus = AgentLoadStatus.loaded;
  }

  Completer<void>? probe;
  var probes = 0;
  Completer<String?>? creation;
  final launches =
      <({String machine, String engine, String folder, bool bypass})>[];
  final input = <TerminalBinaryFrame>[];

  @override
  Future<void> probeEngines(String machineId, {bool force = false}) async {
    probes++;
    await probe?.future;
  }

  @override
  Future<String?> createAgent(
    String machineId, {
    required String engine,
    required String folder,
    ProjectFolderRequest? projectFolder,
    bool bypassPermission = false,
    String? codexHome,
    String? swarmId,
    PaneSplitRequest? split,
    AgentCreationAttempt? attempt,
  }) async {
    launches.add((
      machine: machineId,
      engine: engine,
      folder: folder,
      bypass: bypassPermission,
    ));
    if (creation != null) {
      final error = await creation!.future;
      if (error != null) return error;
    }
    adoptSessionForTest(terminal('created', input));
    notifyListeners();
    return null;
  }
}

class _FolderPicker extends FileSelectorPlatform {
  var opened = 0;
  Completer<String?>? pending;
  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    opened++;
    if (pending != null) return pending!.future;
    return '/work/my-project';
  }
}

class _KeyboardCreationApp extends _FirstUseApp {
  final folderRequests = <({String machine, String? path})>[];

  @override
  Future<Map<String, dynamic>> listRemoteFolder(
    String machineId,
    String? path,
  ) async {
    folderRequests.add((machine: machineId, path: path));
    return {'path': path ?? '/home/dev', 'entries': <Object>[]};
  }
}

void main() {
  testWidgets(
    'machine, remote folder and agent can be chosen entirely by keyboard',
    (tester) async {
      final app = _KeyboardCreationApp();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
      await app.agentPreference.select('claude');
      const remote = Machine(
        machineId: 'workshop',
        name: 'Workshop machine',
        authMode: MachineAuthMode.remote,
      );
      app.machines = [...app.machines, remote];
      app.machineStates['workshop'] = MachineState(remote)
        ..nodeOnline = true
        ..agentLoadStatus = AgentLoadStatus.loaded;
      app.machineStates['workshop']!.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: true),
        EngineAvailability(engine: 'hermes', installed: true),
      ]);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      FocusNode fieldFocus(String key) => tester
          .widget<InkWell>(
            find
                .descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(InkWell),
                )
                .first,
          )
          .focusNode!;
      Future<void> tabTo(FocusNode node, {bool back = false}) async {
        if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (var i = 0; i < 40 && !node.hasPrimaryFocus; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(node.hasPrimaryFocus, isTrue);
      }

      // Machines are direct choice tiles; both are reachable without a menu.
      expect(find.byKey(const Key('new-agent-machine-m')), findsOneWidget);
      AppChoiceTile? focusedTile() {
        final focus = FocusManager.instance.primaryFocus;
        if (focus?.context is! Element) return null;
        AppChoiceTile? found;
        (focus!.context as Element).visitAncestorElements((el) {
          if (el.widget is AppChoiceTile) {
            found = el.widget as AppChoiceTile;
            return false;
          }
          return true;
        });
        return found;
      }

      Future<void> tabToTile(String label, {bool back = false}) async {
        if (back) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        for (var i = 0; i < 40 && focusedTile()?.label != label; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        if (back) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(focusedTile()?.label, label);
      }

      await tabToTile('Workshop machine');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AppChoicePicker<String>>(
              find.byKey(const Key('new-agent-machine-field')),
            )
            .value,
        'workshop',
      );
      expect(app.launches, isEmpty);

      // The remote folder goes through the Local tile and the in-app picker.
      await tabToTile('Local');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      tester.testTextInput.enterText('/work/selected-project');
      await tester.pump();
      // Return in a platform text field arrives as the input method's action.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Choose a folder'), findsNothing);
      expect(app.folderRequests, [
        (machine: 'workshop', path: null),
        (machine: 'workshop', path: '/work/selected-project'),
      ]);

      // The engine's More menu supports type-ahead selection.
      final more = find.descendant(
        of: find.byKey(const Key('new-agent-engine-field')),
        matching: find.byType(InkWell),
      ).first;
      await tabTo(
        tester.widget<InkWell>(more).focusNode!,
        back: true,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      for (final code in 'hermes'.codeUnits) {
        await tester.sendKeyEvent(
          LogicalKeyboardKey(code),
          character: String.fromCharCode(code),
        );
      }
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Hermes'), findsOneWidget);
      expect(app.launches, isEmpty);
      final submit = tester.widget<FilledButton>(
        find.byKey(const ValueKey('create-agent-submit')),
      );
      await tabTo(submit.focusNode!);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.launches, [
        (
          machine: 'workshop',
          engine: 'hermes',
          folder: '/work/selected-project',
          bypass: false,
        ),
      ]);
      expect(app.input, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('first use starts idle with separate Open and New actions', (
    tester,
  ) async {
    final app = _FirstUseApp();
    final projects = SwarmProjectStore();
    await projects.add(
      const SavedSwarmProject(
        machineId: 'm',
        path: '/work/saved-project',
        name: 'Saved project',
      ),
    );
    await mount(tester, app, projects: projects);
    expect(_startInput, findsOneWidget);
    expect(_newHarness, findsOneWidget);
    expect(find.byKey(const ValueKey('harness-start-open')), findsOneWidget);
    expect(tester.widget<TextField>(_startInput).focusNode!.hasFocus, isTrue);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Saved project'), findsNothing);
    expect(find.byKey(const ValueKey('harness-device-link')), findsOneWidget);
    expect(app.launches, isEmpty);
    expect(app.probes, 0);
    await tester.pumpWidget(const SizedBox());
    projects.dispose();
    app.dispose();
  });

  testWidgets('first discovery keeps entry idle until New is chosen', (
    tester,
  ) async {
    final app = _FirstUseApp();
    final local = app.machineStates.remove('m')!;
    app.machinesLoading = true;
    final oldPicker = FileSelectorPlatform.instance;
    final picker = _FolderPicker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = oldPicker);
    await mount(tester, app);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picker.opened, 0);
    expect(app.probes, 0);
    expect(find.byType(AlertDialog), findsNothing);
    app.machineStates['m'] = local;
    app.machinesLoading = false;
    app.dismissError();
    await tester.pump();
    expect(tester.widget<TextField>(_startInput).focusNode!.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.tap(_newHarness);
    await tester.pump();
    expect(picker.opened, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(app.probes, 1);
    // The dialog's initial focus is the New project tile, whose Enter only
    // selects the source. The chooser opens from the Local tile: Tab to it
    // and activate it there.
    AppChoiceTile? focusedTile() {
      final focus = FocusManager.instance.primaryFocus;
      if (focus?.context is! Element) return null;
      AppChoiceTile? found;
      (focus!.context as Element).visitAncestorElements((el) {
        if (el.widget is AppChoiceTile) {
          found = el.widget as AppChoiceTile;
          return false;
        }
        return true;
      });
      return found;
    }

    for (var i = 0; i < 40 && focusedTile()?.label != 'Local'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusedTile()?.label, 'Local');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(picker.opened, 1);
    expect(find.text('my-project'), findsOneWidget);
    expect(app.launches, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('discovery preserves the focused harness search', (tester) async {
    final app = _FirstUseApp();
    final local = app.machineStates.remove('m')!;
    app.machinesLoading = true;
    await mount(tester, app);
    final browsing = _startInput;
    final focus = tester.widget<TextField>(browsing).focusNode!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    app.machineStates['m'] = local;
    app.machinesLoading = false;
    app.dismissError();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue);
    expect(find.text('Machines'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(app.launches, isEmpty);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'another unavailable computer does not hide the local start path',
    (tester) async {
      final app = _FirstUseApp();
      const remote = Machine(
        machineId: 'r',
        name: 'Remote computer',
        authMode: MachineAuthMode.remote,
      );
      app.machineStates['r'] = MachineState(remote)
        ..nodeOnline = false
        ..agentLoadStatus = AgentLoadStatus.error;
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      expect(_newHarness, findsOneWidget);
      expect(find.text('Machines'), findsNothing);
      await tester.tap(_newHarness);
      await tester.pump();
      expect(picker.opened, 0);
      // The Local project tile opens the native folder chooser.
      await tester.tap(find.byKey(const Key('new-agent-project-browse')));
      await tester.pump();
      expect(picker.opened, 1);
      // The Local tile shows the chosen folder's basename.
      expect(find.text('my-project'), findsOneWidget);
      // Both machines are direct tiles: choose the local one explicitly.
      await tester.tap(find.byKey(const ValueKey('new-agent-machine-m')));
      await tester.pump();
      // The choice survives the machine switch on this computer.
      expect(find.text('my-project'), findsOneWidget);
      expect(
        tester
            .widget<AppChoicePicker<String>>(
              find.byKey(const Key('new-agent-machine-field')),
            )
            .value,
        'm',
      );
      // The option list keeps both machines, in discovery order.
      final options = tester
          .widget<AppChoicePicker<String>>(
            find.byKey(const Key('new-agent-machine-field')),
          )
          .options;
      expect(options.map((option) => option.value), ['m', 'r']);
      // The offline remote keeps its distinct offline glyph, not a live one.
      final offlineIcon = options
          .where((option) => option.value == 'r')
          .map((option) => option.leading!())
          .single as Icon;
      expect(offlineIcon.semanticLabel, 'Offline');
      expect(app.launches, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'pending creation stays visible and an error preserves choices for retry',
    (tester) async {
      final app = _FirstUseApp()..creation = Completer<String?>();
      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: true),
      ]);
      final oldPicker = FileSelectorPlatform.instance;
      FileSelectorPlatform.instance = _FolderPicker();
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyN);
      await tester.pump();
      // The Local tile opens the native folder chooser.
      await tester.tap(find.byKey(const Key('new-agent-project-browse')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.tapAt(const Offset(8, 100));
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Creating agent…'), findsOneWidget);
      expect(app.launches, hasLength(1));
      expect(app.panes, isEmpty);
      // The choice tiles cannot be changed while a creation is pending.
      final newProjectTile = tester.widget<AppChoiceTile>(
        find.byKey(const Key('new-agent-folder-newProject')),
      );
      expect(newProjectTile.onPressed, isNull);

      app.creation!.complete('Choose another project folder and try again.');
      await tester.pump();
      expect(
        find.text('Choose another project folder and try again.'),
        findsOneWidget,
      );
      expect(find.text('my-project'), findsOneWidget);
      expect(
        tester
            .widget<AppSelectField<String>>(
              find.byKey(const Key('new-agent-engine-field')),
            )
            .value,
        'claude',
      );
      // Choosing a different project folder clears the error for the retry.
      await tester.tap(find.byKey(const Key('new-agent-folder-newProject')));
      await tester.pump();
      expect(
        find.text('Choose another project folder and try again.'),
        findsNothing,
      );
      app.creation = null;
      await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(TerminalView), findsOneWidget);
      expect(app.launches, hasLength(2));
      expect(app.input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  for (final native in [false, true]) {
    testWidgets(
      'New Agent ${native ? 'native menu' : 'header'} defaults to this computer',
      (tester) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('harness/swarm_tabs'),
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('harness/swarm_tabs'),
            null,
          ),
        );
        final app = _FirstUseApp();
        final map = MemoryKeymap();
        app.machineStates['m']!.engines.replace(const [
          EngineAvailability(engine: 'codex', installed: true),
        ]);
        const remote = Machine(
          machineId: 'remote',
          name: 'Remote computer',
          authMode: MachineAuthMode.remote,
        );
        app.machines = [...app.machines, remote];
        app.machineStates['remote'] = MachineState(remote)
          ..nodeOnline = true
          ..agentLoadStatus = AgentLoadStatus.loaded
          ..agents = const [
            Agent(
              id: 'existing',
              name: 'Existing work',
              engine: 'codex',
              terminalAvailable: true,
              project: AgentProject(name: 'Workspace', cwd: '/work/existing'),
            ),
          ];
        final pane = app.adoptSessionForTest(
          TerminalSession(
              machineId: 'remote',
              agentId: 'existing',
              agentName: 'Existing work',
              engineId: 'codex',
              send: (_, _) async => true,
              sendBinary: (frame) async {
                if (frame.kind == TerminalBinaryKind.input) {
                  app.input.add(frame);
                }
                return true;
              },
            )
            ..status = TerminalSessionStatus.controlling
            ..streamId = 'stream-existing',
        );
        await runtime.mount(tester, app, map, native: native);
        if (native) {
          final opening = runtime.native(tester, 'newAgent');
          await tester.pump();
          await opening;
        } else {
          final addButton = find.byKey(
            const ValueKey('swarm-new-agent-button'),
          );
          final bell = find.byKey(const ValueKey('swarm-notifications-button'));
          expect(
            tester.getRect(bell).right,
            lessThan(tester.getRect(addButton).left),
          );
          expect(
            find.byKey(const ValueKey('swarm-new-harness-button')),
            findsNothing,
          );
          expect(find.byType(FloatingActionButton), findsNothing);
          await tester.tap(addButton);
          await tester.pump();
        }
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('/work/existing'), findsNothing);
        // The project section offers the folder chooser through the Local tile.
        expect(find.text('Which project will this agent work in?'), findsOneWidget);
        // Both machines are direct choice tiles; the local one is preselected.
        final machineField = tester.widget<AppChoicePicker<String>>(
          find.byKey(const Key('new-agent-machine-field')),
        );
        expect(machineField.value, 'm');
        expect(machineField.options.map((option) => option.detail), [
          'This machine',
          null,
        ]);
        expect(machineField.options.map((option) => option.label), [
          'My computer',
          'Remote computer',
        ]);
        expect(
          tester
              .widget<AppSelectField<String>>(
                find.byKey(const Key('new-agent-engine-field')),
              )
              .value,
          'codex',
        );
        expect(app.panes, [pane]);
        expect(app.launches, isEmpty);
        expect(app.input, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byKey(const ValueKey('swarm-search-input')), findsNothing);
        expect(
          tester
              .widget<TerminalView>(find.byType(TerminalView))
              .focusNode!
              .hasFocus,
          isTrue,
        );
        await tester.pumpWidget(const SizedBox());
        app.dispose();
        map.dispose();
      },
    );
  }

  testWidgets(
    'new agent supports immediate keyboard creation',
    (tester) async {
      final app = _FirstUseApp();
      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'codex', installed: true),
      ]);
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker()..pending = Completer<String?>();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyN);
      await tester.pump();

      // The dialog opens on the New project tile, the first actionable control.
      AppChoiceTile? focusedTile() {
        final focus = FocusManager.instance.primaryFocus;
        if (focus?.context is! Element) return null;
        AppChoiceTile? found;
        (focus!.context as Element).visitAncestorElements((el) {
          if (el.widget is AppChoiceTile) {
            found = el.widget as AppChoiceTile;
            return false;
          }
          return true;
        });
        return found;
      }

      Future<void> tabToTile(String label) async {
        for (var i = 0; i < 40 && focusedTile()?.label != label; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusedTile()?.label, label);
      }

      expect(focusedTile()?.label, 'New project');
      expect(picker.opened, 0);
      // The Local tile opens the native folder chooser.
      await tabToTile('Local');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picker.opened, 1);
      picker.pending!.complete('/work/my-project');
      await tester.pump();
      await tester.pump();
      // The Local tile shows the chosen folder's basename.
      expect(find.text('my-project'), findsOneWidget);
      final submit = tester.widget<FilledButton>(
        find.byKey(const ValueKey('create-agent-submit')),
      );
      for (var i = 0; i < 40 && !submit.focusNode!.hasPrimaryFocus; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(submit.focusNode!.hasPrimaryFocus, isTrue);
      expect(app.launches, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(app.launches.single.folder, '/work/my-project');
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.input, isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(app.input.single.bytes, [27, 91, 66]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );

  for (final outcome in ['cancel', 'error']) {
    testWidgets('keyboard folder $outcome restores the chooser, not submit', (
      tester,
    ) async {
      final app = _FirstUseApp();
      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: true),
      ]);
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await chord(tester, LogicalKeyboardKey.keyN);
      await tester.pump();
      // The Local tile opens the native folder chooser; focus stays on it so a
      // failed browse can be retried from the keyboard.
      AppChoiceTile? focusedTile() {
        final focus = FocusManager.instance.primaryFocus;
        if (focus?.context is! Element) return null;
        AppChoiceTile? found;
        (focus!.context as Element).visitAncestorElements((el) {
          if (el.widget is AppChoiceTile) {
            found = el.widget as AppChoiceTile;
            return false;
          }
          return true;
        });
        return found;
      }

      for (var i = 0; i < 40 && focusedTile()?.label != 'Local'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedTile()?.label, 'Local');
      // A first browse chooses a folder; the tile shows its basename.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picker.opened, 1);
      expect(find.text('my-project'), findsOneWidget);
      picker.pending = Completer<String?>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picker.opened, 2);
      if (outcome == 'error') {
        picker.pending!.completeError(StateError('Picker unavailable'));
      } else {
        picker.pending!.complete(null);
      }
      await tester.pump();
      await tester.pump();
      // The cancelled browse returns focus to the dialog's first choice tile,
      // never to the submit action.
      expect(focusedTile()?.label, 'New project');
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('create-agent-submit')),
            )
            .focusNode!
            .hasPrimaryFocus,
        isFalse,
      );
      expect(find.text('my-project'), findsOneWidget);
      expect(app.launches, isEmpty);
      // Tab back to the Local tile: Enter retries browsing, not creation.
      for (var i = 0; i < 40 && focusedTile()?.label != 'Local'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusedTile()?.label, 'Local');
      picker.pending = Completer<String?>();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(picker.opened, 3, reason: 'Enter retries browsing, not creation');
      expect(app.launches, isEmpty);
      picker.pending!.complete(null);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }

  testWidgets('fresh workspace reaches an agent with an installed default', (
    tester,
  ) async {
    final app = _FirstUseApp();
    app.machineStates['m']!.engines.replace(const [
      EngineAvailability(engine: 'claude', installed: false, installable: true),
      EngineAvailability(engine: 'codex', installed: true),
    ]);
    final oldPicker = FileSelectorPlatform.instance;
    final picker = _FolderPicker();
    FileSelectorPlatform.instance = picker;
    addTearDown(() => FileSelectorPlatform.instance = oldPicker);
    await mount(tester, app);

    expect(find.text('New Agent'), findsWidgets);
    expect(find.text('Machines'), findsNothing);
    expect(find.text('Projects'), findsNothing);
    expect(app.launches, isEmpty);
    expect(_startInput, findsOneWidget);
    expect(tester.widget<TextField>(_startInput).focusNode!.hasFocus, isTrue);
    await tester.tap(_newHarness);
    await tester.pump();
    final engine = tester.widget<AppSelectField<String>>(
      find.byKey(const Key('new-agent-engine-field')),
    );
    expect(engine.value, 'codex');
    expect(
      tester.getTopLeft(find.text('Choose an engine')).dy,
      lessThan(
        tester.getTopLeft(find.text('Which project will this agent work in?')).dy,
      ),
    );
    expect(picker.opened, 0);
    await tester.tap(find.byKey(const Key('new-agent-project-browse')));
    await tester.pump();
    expect(picker.opened, 1);
    expect(app.probes, 1);
    expect(find.text('my-project'), findsOneWidget);
    expect(app.launches, isEmpty);
    await tester.tap(find.byKey(const ValueKey('create-agent-submit')));
    await tester.pump();

    expect(app.launches, [
      (
        machine: 'm',
        engine: 'codex',
        folder: '/work/my-project',
        bypass: false,
      ),
    ]);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.text('Your first workspace'), findsNothing);
    expect(app.input, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets('every empty page opens existing work through the same search', (
    tester,
  ) async {
    final app = _FirstUseApp();
    app.machineStates['m']!.agents = const [
      Agent(
        id: 'existing',
        name: 'My ongoing work',
        engine: 'codex',
        terminalAvailable: true,
      ),
    ];
    await mount(tester, app);
    expect(app.panes, isEmpty);
    expect(_startInput, findsOneWidget);
    expect(find.text('Go to an agent'), findsNothing);
    await tester.tap(_startInput);
    await tester.enterText(_startInput, 'My ongoing work');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.panes.single.agentId, 'existing');
    final source = app.activeSwarm;
    final pane = app.panes.single;
    app.newSwarm();
    await tester.pump();
    await tester.pump();
    expect(_startInput, findsOneWidget);
    expect(_newHarness, findsOneWidget);
    expect(find.text('Go to an agent'), findsNothing);
    await tester.tap(_startInput);
    await tester.enterText(_startInput, 'My ongoing work');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(app.panes.single, same(pane));
    expect(source.panes.single, same(pane));
    final used = app.activeSwarmId;
    await app.closeSwarm(used);
    app.newSwarm();
    await tester.pump();
    await tester.pump();
    expect(app.closedHistory, isNotEmpty);
    expect(_startInput, findsOneWidget);
    expect(app.launches, isEmpty);
    expect(find.text('Go to an agent'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });

  testWidgets(
    'folder selection reuses discovery and ignores repeated activation',
    (tester) async {
      final app = _FirstUseApp()..probe = Completer<void>();
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker()..pending = Completer<String?>();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);

      await tester.tap(_newHarness);
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      // The Local tile opens the chooser; Enter on the focused New project
      // tile only selects the source and must not double-open.
      await tester.tap(find.byKey(const Key('new-agent-project-browse')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('new-agent-folder-newProject')));
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyN);
      expect(picker.opened, 1);
      expect(app.probes, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(app.launches, isEmpty);

      app.machineStates['m']!.engines.replace(const [
        EngineAvailability(engine: 'claude', installed: false),
        EngineAvailability(engine: 'codex', installed: true),
      ]);
      app.probe!.complete();
      await tester.pump();
      picker.pending!.complete('/work/chosen');
      await tester.pump();
      await tester.pump();
      expect(find.text('chosen'), findsOneWidget);
      expect(
        tester
            .widget<AppSelectField<String>>(
              find.byKey(const Key('new-agent-engine-field')),
            )
            .value,
        'codex',
      );
      expect(app.probes, 1);
      expect(app.launches, isEmpty);
      expect(app.input, isEmpty);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'late folder completion cannot revive a disposed creation dialog',
    (tester) async {
      final app = _FirstUseApp();
      final oldPicker = FileSelectorPlatform.instance;
      final picker = _FolderPicker()..pending = Completer<String?>();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = oldPicker);
      await mount(tester, app);
      await tester.tap(_newHarness);
      await tester.pump();
      // The Local tile opens the chooser.
      await tester.tap(find.byKey(const Key('new-agent-project-browse')));
      await tester.pump();
      expect(picker.opened, 1);
      await tester.pumpWidget(const SizedBox());
      picker.pending!.complete('/work/stale');
      await tester.pump();
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.allPanes, isEmpty);
      expect(app.launches, isEmpty);
      expect(app.input, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    },
  );

  testWidgets(
    'a late probe uses an installed agent without overriding a choice',
    (tester) async {
      for (final chooseExplicitly in [false, true]) {
        final app = _FirstUseApp()..probe = Completer<void>();
        await mount(tester, app);
        await chord(tester, LogicalKeyboardKey.keyN);
        await tester.pump();
        if (chooseExplicitly) {
          // The engine More menu carries the engines beyond the tiles.
          await tester.tap(find.byKey(const Key('new-agent-engine-field')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Cursor'));
          await tester.pumpAndSettle();
        }
        app.machineStates['m']!.engines.replace(const [
          EngineAvailability(engine: 'claude', installed: false),
          EngineAvailability(engine: 'codex', installed: true),
        ]);
        app.probe!.complete();
        await tester.pump();
        await tester.pump();
        expect(app.probes, 1);
        final engine = tester.widget<AppSelectField<String>>(
          find.byKey(const Key('new-agent-engine-field')),
        );
        expect(engine.value, chooseExplicitly ? 'cursor' : 'codex');
        expect(app.launches, isEmpty);
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      }
    },
  );
}
