import 'swarm_search_field.dart';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/services.dart';

import '../shortcuts/app_keymap.dart';
import '../shortcuts/keymap.dart';
import 'search_result_text.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../state/swarm_navigation.dart';
import '../state/swarm_search.dart';
import '../store/store_mark.dart';
import 'engine_identity.dart';
import 'swarm_icon.dart';
import 'swarm_search_preview.dart';

Future<SwarmSearchSelection?> showSwarmHistory(
  BuildContext context,
  AppNotifier app,
  SwarmNavigationHistory history,
) async {
  final search = SwarmSearchController(app, history.recent, history: history);
  try {
    return await showAppDialog<SwarmSearchSelection>(
      context: context,
      transitionDuration: Duration.zero,
      veilBlur: 0,
      builder: (_) => _SwarmHistory(search: search),
    );
  } finally {
    search.dispose();
  }
}

class _SwarmHistory extends StatefulWidget {
  const _SwarmHistory({required this.search});
  final SwarmSearchController search;
  @override
  State<_SwarmHistory> createState() => _SwarmHistoryState();
}

class _SwarmHistoryState extends State<_SwarmHistory> {
  final _query = TextEditingController();
  final _focus = FocusNode(debugLabel: 'History search');
  void _choose(SwarmSearchSelection choice) => Navigator.pop(context, choice);
  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    alignment: const Alignment(0, -0.5),
    insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
    child: SizedBox(
      width: 680,
      height: 480,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SwarmSearchKeys(
          search: widget.search,
          editing: _query,
          onChoose: _choose,
          onClose: () => Navigator.pop(context),
          onRefocus: _focus.requestFocus,
          child: Column(
            children: [
              const Row(
                children: [
                  Text(
                    'History',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                  Spacer(),
                  Text(
                    'This session',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwarmSearchField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                hintText: 'Search history…',
                onChanged: widget.search.setQuery,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SwarmSearchResults(
                  search: widget.search,
                  onChoose: _choose,
                  onRefocus: _focus.requestFocus,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Search and History share editing and navigation keys.
class SwarmSearchKeys extends StatelessWidget {
  const SwarmSearchKeys({
    super.key,
    required this.search,
    required this.editing,
    required this.onChoose,
    required this.onClose,
    this.onOpen,
    this.onNewAgent,
    this.onRefocus,
    required this.child,
  });
  final SwarmSearchController? search;
  final TextEditingController editing;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onClose;

  /// A focused field may be ready for typing while its suggestions are closed.
  /// The first navigation/accept key reveals them without choosing unseen work.
  final VoidCallback? onOpen;
  final VoidCallback? onNewAgent;
  final VoidCallback? onRefocus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final search = this.search;
    bool composing() =>
        editing.value.composing.isValid && !editing.value.composing.isCollapsed;
    void run(VoidCallback action) {
      if (!composing()) action();
    }

    void choose(bool add) => run(() {
      if (search == null) {
        onOpen?.call();
        return;
      }
      final choice = add ? search.addHere() : search.submit();
      if (choice != null) onChoose(choice);
    });
    void move(int delta) => run(() {
      if (search == null) {
        onOpen?.call();
      } else {
        search.move(delta);
        onRefocus?.call();
      }
    });
    if (KeymapTheme.of(context) != null) {
      return KeymapRegion(
        contextKind: KeymapContext.picker,
        composing: composing,
        actions: {
          if (onNewAgent != null) 'agent.new': () => run(onNewAgent!),
          if (search != null || onOpen != null) ...{
            'picker.accept': () => choose(false),
            'picker.add_here': () => choose(true),
            'picker.next': () => move(1),
            'picker.previous': () => move(-1),
            if (search != null) ...{
              'picker.preview_page_up': () => run(() => search.pagePreview(-1)),
              'picker.preview_page_down': () =>
                  run(() => search.pagePreview(1)),
            },
            'picker.cancel': onClose,
            if (search == null || search.allowsCommands)
              'navigation.commands': () {
                editing.value = const TextEditingValue(
                  text: '> ',
                  selection: TextSelection.collapsed(offset: 2),
                );
                if (search == null) {
                  onOpen?.call();
                } else {
                  search.setQuery('> ');
                  onRefocus?.call();
                }
              },
          },
        },
        child: Actions(
          // EditableText's Escape action has no route-level handler when the
          // picker lives in an overlay. The keymap owns dismissal; composition
          // and user-unbound Escape must stay with the text editor.
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => null),
          },
          child: child,
        ),
      );
    }
    return CallbackShortcuts(
      bindings: search == null && onOpen == null
          ? {}
          : {
              if (onNewAgent != null)
                const SingleActivator(
                  LogicalKeyboardKey.keyN,
                  meta: true,
                  shift: true,
                  includeRepeats: false,
                ): () =>
                    run(onNewAgent!),
              const SingleActivator(
                LogicalKeyboardKey.enter,
                includeRepeats: false,
              ): () =>
                  choose(false),
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                includeRepeats: false,
              ): () =>
                  choose(false),
              const SingleActivator(
                LogicalKeyboardKey.enter,
                meta: true,
                includeRepeats: false,
              ): () =>
                  choose(true),
              const SingleActivator(
                LogicalKeyboardKey.numpadEnter,
                meta: true,
                includeRepeats: false,
              ): () =>
                  choose(true),
              const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                  move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => move(-1),
              if (search != null) ...{
                const SingleActivator(LogicalKeyboardKey.pageUp): () =>
                    run(() => search.pagePreview(-1)),
                const SingleActivator(LogicalKeyboardKey.pageDown): () =>
                    run(() => search.pagePreview(1)),
              },
              const SingleActivator(
                LogicalKeyboardKey.keyN,
                control: true,
              ): () =>
                  move(1),
              const SingleActivator(
                LogicalKeyboardKey.keyP,
                control: true,
              ): () =>
                  move(-1),
              const SingleActivator(
                LogicalKeyboardKey.keyJ,
                control: true,
              ): () =>
                  move(1),
              const SingleActivator(
                LogicalKeyboardKey.keyK,
                control: true,
              ): () =>
                  move(-1),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  run(onClose),
              const SingleActivator(
                LogicalKeyboardKey.keyG,
                control: true,
              ): () =>
                  run(onClose),
            },
      child: child,
    );
  }
}

double swarmSearchRowHeight(TextScaler scale, {required bool commands}) =>
    commands
    ? (scale.scale(14) + 20).clamp(40, double.infinity)
    : (scale.scale(14) + scale.scale(12) + 30).clamp(56, double.infinity);

double swarmSearchResultsHeight(
  SwarmSearchController search,
  TextScaler scale,
) =>
    search.rows.length.clamp(4, 7) *
        swarmSearchRowHeight(scale, commands: search.isCommandMode) +
    (search.selected != null && !search.canAccept ? 48 : 0);

/// Shared harness search results, also used for commands and History.
class SwarmSearchResults extends StatefulWidget {
  const SwarmSearchResults({
    super.key,
    required this.search,
    required this.onChoose,
    required this.onRefocus,
    this.sideBySideMinWidth = 800,
  });
  final SwarmSearchController search;
  final ValueChanged<SwarmSearchSelection> onChoose;
  final VoidCallback onRefocus;
  final double sideBySideMinWidth;
  @override
  State<SwarmSearchResults> createState() => _SwarmSearchResultsState();
}

class _SwarmSearchResultsState extends State<SwarmSearchResults> {
  // Keep a small set of recently built rows, not the whole search catalog.
  // A new highlight only changes two rows; their neighbors keep their widgets.
  final _rowWidgets = <String, ({Object presentation, Widget child})>{};
  final _scroll = ScrollController();
  double _rowHeight = 56;
  bool _revealScheduled = false;
  (Size, double)? _geometry;
  SwarmSearchController get search => widget.search;
  @override
  void initState() {
    super.initState();
    search.addListener(_changed);
  }

  void _changed() {
    setState(() {});
    _scrollToSelection();
    _revealSelection();
  }

  void _revealSelection() {
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (mounted) _scrollToSelection();
    });
  }

  void _scrollToSelection() {
    if (!_scroll.hasClients || search.rows.isEmpty) return;
    final top = 8 + search.cursor * _rowHeight;
    final bottom = top + _rowHeight + 8;
    final position = _scroll.position;
    final offset = top - 8 < position.pixels
        ? top - 8
        : bottom > position.pixels + position.viewportDimension
        ? bottom - position.viewportDimension
        : position.pixels;
    final target = offset.clamp(0.0, position.maxScrollExtent);
    if (target != position.pixels) _scroll.jumpTo(target);
  }

  void _submit([SwarmDestination? row]) {
    final choice = search.submit(row);
    if (choice != null) {
      widget.onChoose(choice);
    } else {
      widget.onRefocus();
    }
  }

  void _focusResult(String id) {
    // Tab focus must highlight the same row Enter will open.
    // Look up the current position because cached rows can move after discovery.
    final index = search.rows.indexWhere((row) => row.id == id);
    if (index >= 0 && index != search.cursor) {
      search.move(index - search.cursor);
    }
  }

  @override
  void dispose() {
    search.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    _rowHeight = swarmSearchRowHeight(scale, commands: search.isCommandMode);
    final selected = search.selected;
    final unavailable =
        (selected != null && !search.canSubmit(selected)) ||
        search.adding && !search.canCreate;
    final terms = swarmQueryTerms(
      search.isCommandMode ? search.commandQuery : search.query,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= widget.sideBySideMinWidth;
        final compactAction =
            (sideBySide ? constraints.maxWidth / 2 : constraints.maxWidth) <
            380 * scale.scale(14) / 14;
        final geometry = (constraints.biggest, _rowHeight);
        if (_geometry != geometry) {
          _geometry = geometry;
          _revealSelection();
        }
        final results = Semantics(
          container: true,
          label: 'Search results',
          child: Column(
            children: [
              Expanded(
                child: search.rows.isEmpty
                    ? Center(
                        child: Text(
                          search.isCommandMode
                              ? 'No matching commands'
                              : search.adding && search.query.isEmpty
                              ? 'Create a new harness to start fresh.'
                              : search.adding
                              ? 'No matching harnesses'
                              : 'No matching results',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white60,
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('swarm-search-result-list'),
                        padding: const EdgeInsets.all(8),
                        controller: _scroll,
                        itemCount: search.rows.length,
                        itemExtent: _rowHeight,
                        itemBuilder: (context, index) {
                          final row = search.rows[index];
                          final highlighted = index == search.cursor;
                          final canSubmit = search.canSubmit(row);
                          final alreadyHere = search.alreadyHere(row);
                          final presentation = (
                            row,
                            search.query,
                            highlighted,
                            canSubmit,
                            alreadyHere,
                            highlighted
                                ? (search.canAccept, search.actionLabel(row))
                                : null,
                            _rowHeight,
                            compactAction,
                            scale.scale(11),
                            grid.AppTheme.palette.value,
                          );
                          final previous = _rowWidgets.remove(row.id);
                          if (previous?.presentation == presentation) {
                            _rowWidgets[row.id] = previous!;
                            return previous.child;
                          }
                          final matches = searchResultMatches(row, terms);
                          final tile = ListTile(
                            key: ValueKey(row.id),
                            minTileHeight: _rowHeight,
                            enabled: canSubmit,
                            onFocusChange: (focused) {
                              if (focused) _focusResult(row.id);
                            },
                            selected: highlighted,
                            selectedColor: Colors.white,
                            hoverColor: Colors.transparent,
                            selectedTileColor: Colors.white.withValues(
                              alpha: .055,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                row.isCommand
                                    ? const Icon(
                                        Icons.keyboard_command_key,
                                        size: 20,
                                        color: Colors.white60,
                                      )
                                    : row.isStore
                                    ? StoreMark(size: 22, enabled: canSubmit)
                                    : row.agentId != null ||
                                          (row.isSwarm &&
                                              row.members.length == 1)
                                    ? EngineMark(
                                        engine: row.engine,
                                        size: 22,
                                        enabled: canSubmit,
                                      )
                                    : const SwarmIcon(
                                        size: 22,
                                        color: Colors.white60,
                                      ),
                              ],
                            ),
                            title: SearchResultText(
                              row.title,
                              matches: matches.where((match) => match.title),
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: row.isCommand
                                ? null
                                : SearchResultText(
                                    row.detail,
                                    iconOffset: row.detailBranchOffset ?? 0,
                                    inlineIcon: row.detailBranchOffset == null
                                        ? null
                                        : const Icon(
                                            LucideIcons.gitBranch300,
                                            size: 12,
                                            color: Colors.white60,
                                          ),
                                    matches: matches.where(
                                      (match) => !match.title,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                    ),
                                  ),
                            trailing: alreadyHere
                                ? const Text(
                                    'Already added',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white38,
                                    ),
                                  )
                                : highlighted
                                ? ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: 170 * scale.scale(11) / 11,
                                    ),
                                    child: TextButton(
                                      key: const ValueKey('swarm-row-action'),
                                      onPressed: search.canAccept
                                          ? _submit
                                          : null,
                                      style: TextButton.styleFrom(
                                        foregroundColor: Colors.white,
                                      ),
                                      child: SwarmSearchActionLabel(
                                        search.actionLabel(row),
                                        compact: compactAction,
                                      ),
                                    ),
                                  )
                                : row.shortcut == null
                                ? null
                                : Text(
                                    row.shortcut!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white60,
                                    ),
                                  ),
                            onTap: canSubmit ? () => _submit(row) : null,
                          );
                          _rowWidgets[row.id] = (
                            presentation: presentation,
                            child: MouseRegion(
                              onEnter: (_) => _focusResult(row.id),
                              child: tile,
                            ),
                          );
                          if (_rowWidgets.length > 48) {
                            _rowWidgets.remove(_rowWidgets.keys.first);
                          }
                          return _rowWidgets[row.id]!.child;
                        },
                      ),
              ),
              if (unavailable) ...[
                SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            search.adding
                                ? search.unavailableMessage
                                : selected!.isGroup &&
                                      selected.members.length >
                                          AppNotifier.maxPanes
                                ? 'Open up to ${AppNotifier.maxPanes} harnesses at once'
                                : 'No room to open this ${selected.isSwarm || selected.isGroup ? 'group' : 'harness'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white60,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
        final preview = search.hasPreview
            ? SwarmSearchPreview(
                key: const ValueKey('swarm-search-preview'),
                search: search,
                compactHeader: constraints.maxWidth < 800,
              )
            : null;
        final content = preview == null
            ? results
            : sideBySide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: results),
                  const SizedBox(width: 8),
                  Expanded(flex: 5, child: preview),
                ],
              )
            : Column(
                children: [
                  Expanded(flex: 5, child: results),
                  const SizedBox(height: 8),
                  Expanded(flex: 6, child: preview),
                ],
              );
        if (KeymapTheme.of(context) == null) return content;
        // The early keymap handler owns these keys across the whole picker.
        // If unbound, do not fall through to ListTile's default activation or
        // directional focus traversal and silently perform the removed action.
        return Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): DoNothingIntent(),
            SingleActivator(LogicalKeyboardKey.arrowDown): DoNothingIntent(),
            SingleActivator(LogicalKeyboardKey.arrowUp): DoNothingIntent(),
          },
          child: content,
        );
      },
    );
  }
}

class SwarmSearchActionLabel extends StatelessWidget {
  const SwarmSearchActionLabel(
    this.label, {
    super.key,
    this.command = 'picker.accept',
    this.compact = false,
  });
  final String label;
  final String command;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final hint = effectiveCommandHint(
      context,
      command,
      contextKind: KeymapContext.picker,
    );
    return Semantics(
      label: compact ? label : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact || hint == null)
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
          if (hint != null) ...[
            if (!compact) const SizedBox(width: 8),
            if (RegExp(r'^[⌃⌥⇧⌘]*↵$').hasMatch(hint)) ...[
              if (hint.length > 1)
                Text(
                  hint.substring(0, hint.length - 1),
                  style: const TextStyle(fontSize: 11),
                ),
              const Icon(Icons.keyboard_return, size: 14),
            ] else
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  hint.replaceAll('↵', 'Return').replaceAll('⇥', 'Tab'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
