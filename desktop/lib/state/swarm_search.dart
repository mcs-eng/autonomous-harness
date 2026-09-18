import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'pane_arrangement.dart';
import 'swarm_catalog.dart';
import 'swarm_navigation.dart';

/// Search text and selection retained while the start-page picker is dismissed.
/// Membership and availability are revalidated against a fresh catalog on return.
class SwarmSearchDraft {
  const SwarmSearchDraft._(this.targetId, this.query, this.selectedId);
  final String targetId, query;
  final String? selectedId;
}

/// One search session, shared by the native/Flutter input and its results.
/// Keystrokes only filter the cached catalog; they never query a machine.
class SwarmSearchController extends ChangeNotifier {
  SwarmSearchController(
    this.app,
    this.recent, {
    this.projects,
    this.history,
    this.commands,
    this.adding = false,
    this.navigating = false,
    this.commandsOnly = false,
    this.split,
    SwarmSearchCatalog? catalog,
    SwarmLocationCatalog? locations,
  }) : _cache = catalog ?? SwarmSearchCatalog(),
       _locations = locations ?? SwarmLocationCatalog(),
       targetId = app.activeSwarmId,
       targetName = app.activeSwarm.name {
    _refresh();
    app.addListener(_refresh);
    projects?.addListener(_refresh);
    app.sessionPreviews.addListener(_previewChanged);
  }

  final AppNotifier app;
  final List<String> recent;
  final SwarmProjectStore? projects;
  final SwarmNavigationHistory? history;

  /// Availability is read from workspace state and rechecked at activation.
  /// Commands never enter the ordinary agent/swarm catalog or History.
  final List<SwarmDestination> Function()? commands;
  final bool adding;
  final bool navigating;
  final bool commandsOnly;
  final PaneSplitRequest? split;
  bool get allowsCommands => split == null && history == null;
  bool get isCommandMode =>
      allowsCommands && (commandsOnly || query.trimLeft().startsWith('>'));
  bool get hasPreview => !isCommandMode && history == null && selected != null;

  // Paging the preview must not rebuild the result list or its text editor.
  final _previewPage = ValueNotifier<int>(0);
  ValueListenable<int> get previewPage => _previewPage;
  void pagePreview(int pages) {
    if (hasPreview) _previewPage.value += pages;
  }

  final String targetId, targetName;
  // The workspace can retain normalized metadata across picker openings. Each
  // read still validates its snapshot; query, selection and output stay local.
  final SwarmSearchCatalog _cache;
  final SwarmLocationCatalog _locations;
  List<SwarmDestination> _catalog = const [];
  Set<String> _commandIds = const {};
  List<SwarmDestination> rows = const [];
  String query = '';
  String? _selectedId;
  int cursor = 0;
  bool? _splitCurrent;
  Set<String> _presentIds = const {};
  SwarmSearchDraft get draft =>
      SwarmSearchDraft._(targetId, query, selected?.id);

  void restoreDraft(SwarmSearchDraft draft) {
    if (!adding || draft.targetId != targetId) return;
    query = draft.query;
    _selectedId = draft.selectedId;
    cursor = 0;
    _filter();
    notifyListeners();
  }

  int get capacity {
    final target = app.swarms
        .where((swarm) => swarm.id == targetId)
        .firstOrNull;
    return target == null ? 0 : AppNotifier.maxPanes - target.panes.length;
  }

  bool get canAccept => canSubmit(selected);

  SwarmDestination? get selected => rows.isEmpty ? null : rows[cursor];
  String get hint => isCommandMode
      ? 'Search commands…'
      : history != null
      ? 'Search history…'
      : 'Find a harness';

  bool get canCreate =>
      history == null &&
      app.swarms.any(
        (swarm) =>
            swarm.id == targetId && swarm.panes.length < AppNotifier.maxPanes,
      ) &&
      (split == null || app.isPaneSplitCurrent(split!));

  String get commandQuery =>
      query.trimLeft().replaceFirst(RegExp(r'^>\s*'), '');

  String get primaryAction => switch (split?.axis) {
    PaneResizeAxis.x => 'Split right',
    PaneResizeAxis.y => 'Split down',
    null => 'Open Harness',
  };

  String actionLabel(SwarmDestination? row) => row?.isCommand == true
      ? action(row!)
      : adding
      ? row != null &&
                row.agentId == null &&
                split == null &&
                _missingIds(row).length > 1
            ? 'Open ${_missingIds(row).length} Harnesses'
            : primaryAction
      : row == null
      ? 'Go to'
      : action(row);

  String get unavailableMessage =>
      split != null && !app.isPaneSplitCurrent(split!)
      ? 'The layout changed. Split the pane again.'
      : selected != null && alreadyHere(selected!)
      ? 'This harness is already open here.'
      : 'No room for another harness.';

  void _refresh() {
    final next = navigating
        ? _locations.read(app, projects?.projects ?? const [])
        : history == null
        ? _cache.read(app, projects?.projects ?? const [], recent: recent)
        : [...history!.menuDestinations(app), ...closedWorkDestinations(app)];
    final splitCurrent = split == null || app.isPaneSplitCurrent(split!);
    if (identical(next, _catalog) &&
        !isCommandMode &&
        splitCurrent == _splitCurrent) {
      return;
    }
    _catalog = next;
    _splitCurrent = splitCurrent;
    _presentIds = {
      for (final swarm in app.swarms.where((s) => s.id == targetId))
        for (final pane in swarm.panes)
          if (pane.agentId != null)
            agentDestinationId(pane.machineId, pane.agentId!),
    };
    _filter();
    notifyListeners();
  }

  void refreshCommands() {
    if (!isCommandMode) return;
    _filter();
    notifyListeners();
  }

  void _previewChanged() {
    if (query.trim().isEmpty || isCommandMode || history != null) return;
    final previous = rows;
    final previousSelection = selected?.id;
    _filter(keepOrder: true);
    // Live text can add/remove a match, but never shuffle matching rows under
    // the keyboard or repaint the editor when the result set is unchanged.
    if (!listEquals(previous, rows) || previousSelection != selected?.id) {
      notifyListeners();
    }
  }

  void _filter({bool keepOrder = false}) {
    final previous = rows;
    final availableCommands = isCommandMode
        ? commands?.call() ?? const <SwarmDestination>[]
        : const <SwarmDestination>[];
    _commandIds = {for (final command in availableCommands) command.id};
    rows = isCommandMode
        ? rankSwarmDestinations(availableCommands, commandQuery)
        : navigating
        ? rankSwarmLocations(
            _catalog,
            query,
            recent: recent,
            previews: app.sessionPreviews,
          )
        : rankSwarmDestinations(
            adding
                ? _catalog
                      .where(
                        (row) =>
                            (split == null || row.agentId != null) &&
                            (_hasMissing(row) ||
                                (query.isNotEmpty && row.agentId != null)),
                      )
                      .toList()
                : _catalog,
            query,
            recent: recent,
            previews: history == null ? app.sessionPreviews : null,
          );
    if (keepOrder && !navigating) {
      final remaining = {for (final row in rows) row.id: row};
      rows = [
        for (final row in previous) ?remaining.remove(row.id),
        ...remaining.values,
      ];
    }
    // The parent stays above its children visually, but Enter after a query
    // still targets the best match, including an agent nested under that parent.
    final preferred =
        _selectedId ??
        (navigating && !isCommandMode
            ? rankSwarmDestinations(
                rows,
                query,
                recent: recent,
                previews: app.sessionPreviews,
              ).firstOrNull?.id
            : null);
    final index = rows.indexWhere((row) => row.id == preferred);
    cursor = rows.isEmpty
        ? 0
        : index >= 0
        ? index
        : cursor.clamp(0, rows.length - 1);
    _selectedId = selected?.id;
  }

  void setQuery(String value) {
    if (query == value) return;
    query = value;
    cursor = 0;
    _selectedId = null;
    _filter();
    notifyListeners();
  }

  void move(int delta) {
    if (rows.isEmpty) return;
    cursor = (cursor + delta) % rows.length;
    _selectedId = selected!.id;
    notifyListeners();
  }

  SwarmSearchSelection? submit([SwarmDestination? row]) {
    final destination = row ?? selected;
    if (destination == null || !canSubmit(destination)) return null;
    if (destination.isCommand &&
        !(commands?.call().any((command) => command.id == destination.id) ??
            false)) {
      return null;
    }
    return SwarmSearchSelection(
      destination,
      adding ? SwarmSearchAction.addHere : SwarmSearchAction.open,
    );
  }

  bool canSubmit(SwarmDestination? row) =>
      row != null &&
      (!adding || row.isCommand || canAdd(row)) &&
      (!row.isCommand || (isCommandMode && _commandIds.contains(row.id))) &&
      (adding ||
          !row.isGroup ||
          canOpenSwarmGroup(app, row, destinationSwarmId: targetId)) &&
      (row.closedId == null || app.canReopenClosed(row.closedId!));

  Set<String> _missingIds(SwarmDestination row) {
    final members = row.agentId == null ? row.members : {row.id};
    return members.difference(_presentIds);
  }

  bool _hasMissing(SwarmDestination row) => row.agentId != null
      ? !_presentIds.contains(row.id)
      : row.members.any((id) => !_presentIds.contains(id));

  bool alreadyHere(SwarmDestination row) =>
      adding && row.agentId != null && _presentIds.contains(row.id);

  bool canAdd(SwarmDestination? row) =>
      !navigating &&
      history == null &&
      row != null &&
      !row.isCommand &&
      row.closedId == null &&
      _missingIds(row).isNotEmpty &&
      (split == null || row.agentId != null) &&
      (split == null || app.isPaneSplitCurrent(split!)) &&
      app.swarms.any(
        (swarm) =>
            swarm.id == targetId &&
            swarm.panes.length + _missingIds(row).length <=
                AppNotifier.maxPanes,
      );

  SwarmSearchSelection? addHere() => adding
      ? submit()
      : canAdd(selected)
      ? SwarmSearchSelection(selected!, SwarmSearchAction.addHere)
      : null;

  static String action(SwarmDestination row) => row.isCommand
      ? 'Run command'
      : row.closedId != null
      ? 'Reopen'
      : 'Open Harness';

  @override
  void dispose() {
    app.removeListener(_refresh);
    projects?.removeListener(_refresh);
    app.sessionPreviews.removeListener(_previewChanged);
    _previewPage.dispose();
    super.dispose();
  }
}
