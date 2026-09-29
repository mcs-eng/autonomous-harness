import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import '../state/harness_activity.dart';
import '../state/notification_inbox.dart';
import '../terminal/terminal_text.dart';
import '../terminal/terminal_theme.dart';
import '../terminal/terminal_theme_store.dart';
import 'box_chrome.dart';
import 'harness_activity_mark.dart';
import 'terminal_text_action.dart';

Future<void> showNotificationInbox(
  BuildContext context, {
  required AppNotifier app,
  required Future<bool> Function(InboxNotification) onOpen,
  double topInset = 0,
}) => showAppDialog<void>(
  context: context,
  veilTint: Colors.transparent,
  builder: (_) =>
      NotificationInbox(app: app, onOpen: onOpen, topInset: topInset),
);

/// The existing unread notifications in a quiet, live list beside the bell.
class NotificationInbox extends StatefulWidget {
  const NotificationInbox({
    super.key,
    required this.app,
    required this.onOpen,
    this.topInset = 0,
  });

  final AppNotifier app;
  final Future<bool> Function(InboxNotification) onOpen;
  final double topInset;

  @override
  State<NotificationInbox> createState() => _NotificationInboxState();
}

class _NotificationInboxState extends State<NotificationInbox> {
  final _scroll = ScrollController();
  final _focus = FocusNode(debugLabel: 'Notifications');
  List<InboxNotification> _rows = [];
  String? _selected, _opening, _error;

  @override
  void initState() {
    super.initState();
    _refresh();
    widget.app.addListener(_changed);
    widget.app.agentUnread.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _refresh() {
    final next = {for (final row in notificationInbox(widget.app)) row.id: row};
    // Keep the list under the pointer still. New notifications append while
    // the popup is open; selection follows identity rather than an index.
    _rows = [for (final row in _rows) ?next.remove(row.id), ...next.values];
    if (!_rows.any((row) => row.id == _selected)) _selected = null;
  }

  void _changed() {
    if (mounted) setState(_refresh);
  }

  void _move(int delta) {
    if (_rows.isEmpty || _opening != null) return;
    final current = _rows.indexWhere((row) => row.id == _selected);
    final index = current < 0
        ? (delta > 0 ? 0 : _rows.length - 1)
        : (current + delta).clamp(0, _rows.length - 1);
    setState(() => _selected = _rows[index].id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final line = terminalCellSizeOf(context).height;
      final top = line + index * line * 3;
      final bottom = top + line * 3;
      final viewport = _scroll.position.viewportDimension;
      final offset = top < _scroll.offset
          ? top
          : bottom > _scroll.offset + viewport
          ? bottom - viewport
          : _scroll.offset;
      _scroll.jumpTo(offset.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  Future<void> _open(InboxNotification row) async {
    if (_opening != null) return;
    final current = notificationInbox(widget.app)
        .where((item) => item.id == row.id)
        .firstOrNull;
    if (current == null || current.unavailable != null) return;
    setState(() {
      _opening = row.id;
      _error = null;
    });
    try {
      final opened = await widget.onOpen(current);
      if (!mounted) return;
      if (opened) {
        Navigator.of(context).pop();
      } else {
        setState(() => _error = 'Could not open this harness. Try again.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open this harness. Try again.');
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_changed);
    widget.app.agentUnread.removeListener(_changed);
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TerminalFontScope.watch(context);
    grid.AppTheme.watch(context);
    return ValueListenableBuilder(
      valueListenable: terminalThemeStore,
      builder: (context, _, _) {
        final theme = terminalThemeFor(
          grid.AppTheme.palette.value,
          terminalThemeStore.value,
        );
        final cell = terminalCellSizeOf(context);
        final style = terminalContentStyle(color: theme.foreground);
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = math.min(
              cell.width * 64,
              math.max(0.0, constraints.maxWidth - cell.width * 2),
            );
            final available = math.max(
              0.0,
              constraints.maxHeight - widget.topInset - cell.height * 2,
            );
            final height = math.min(
              available,
              cell.height *
                  (_rows.isEmpty
                      ? 5
                      : math.min(
                          23,
                          3 + _rows.length * 3 + (_error == null ? 0 : 2),
                        )),
            );
            return Dialog(
              alignment: Alignment.topRight,
              insetPadding: EdgeInsets.fromLTRB(
                cell.width,
                widget.topInset + cell.height,
                cell.width,
                cell.height,
              ),
              backgroundColor: theme.background,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kTerminalCornerRadius),
                side: terminalPaneBorder(focused: true),
              ),
              child: SizedBox(
                key: const ValueKey('notification-inbox'),
                width: width,
                height: height,
                child: Focus(
                  focusNode: _focus,
                  autofocus: true,
                  onKeyEvent: (node, event) {
                    if (!node.hasPrimaryFocus ||
                        event is! KeyDownEvent ||
                        HardwareKeyboard.instance.isMetaPressed ||
                        HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isAltPressed) {
                      return KeyEventResult.ignored;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                        event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      _move(
                        event.logicalKey == LogicalKeyboardKey.arrowDown
                            ? 1
                            : -1,
                      );
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
                      final row = _rows
                          .where((row) => row.id == _selected)
                          .firstOrNull;
                      if (row != null) unawaited(_open(row));
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: DefaultTextStyle(
                    style: style,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: cell.width * 2,
                        vertical: cell.height,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: cell.height,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Notifications${_rows.isEmpty ? '' : '  ${_rows.length}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                TerminalTextAction(
                                  label: 'x',
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: _rows.isEmpty
                                ? Center(
                                    child: Text(
                                      'No notifications',
                                      style: style.copyWith(
                                        color: theme.foreground.withValues(
                                          alpha: .55,
                                        ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    controller: _scroll,
                                    itemCount: _rows.length,
                                    padding: EdgeInsets.only(top: cell.height),
                                    itemExtent: cell.height * 3,
                                    itemBuilder: (context, index) {
                                      final row = _rows[index];
                                      final opening = row.id == _opening;
                                      final activity = opening
                                          ? HarnessActivity.starting
                                          : switch (row.unavailable) {
                                              null => row.activity,
                                              'Starting' =>
                                                HarnessActivity.starting,
                                              'Start failed' =>
                                                HarnessActivity.failed,
                                              _ => HarnessActivity.offline,
                                            };
                                      final statusLabel = opening
                                          ? 'Opening…'
                                          : row.unavailable == null
                                          ? row.label
                                          : '${row.label} · ${row.unavailable}';
                                      final onTap =
                                          row.unavailable == null &&
                                              _opening == null
                                          ? () => unawaited(_open(row))
                                          : null;
                                      final selected = row.id == _selected;
                                      return Semantics(
                                        label:
                                            '${row.title}, ${row.label}, ${row.detail}${row.unavailable == null ? '' : ', ${row.unavailable}'}',
                                        button: true,
                                        excludeSemantics: true,
                                        enabled: onTap != null,
                                        onTap: onTap,
                                        selected: selected,
                                        child: MouseRegion(
                                          cursor: onTap != null
                                              ? SystemMouseCursors.click
                                              : SystemMouseCursors.basic,
                                          onEnter: (_) {
                                            if (_opening == null) {
                                              setState(
                                                () => _selected = row.id,
                                              );
                                            }
                                          },
                                          child: GestureDetector(
                                            key: ValueKey(
                                              'notification:${row.id}',
                                            ),
                                            behavior: HitTestBehavior.opaque,
                                            onTap: onTap,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.stretch,
                                              children: [
                                                ColoredBox(
                                                  color: selected
                                                      ? theme.selection
                                                      : Colors.transparent,
                                                  child: SizedBox(
                                                    height: cell.height,
                                                    child: Row(
                                                      children: [
                                                        Expanded(
                                                          child: Text(
                                                            row.title,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        SizedBox(
                                                          width: cell.width,
                                                        ),
                                                        Tooltip(
                                                          message: statusLabel,
                                                          child: SizedBox(
                                                            width: cell.width,
                                                            child: Text(
                                                              activity.mark,
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: style.copyWith(
                                                                color:
                                                                    activityColor(
                                                                      activity,
                                                                      theme,
                                                                    ),
                                                                fontFamilyFallback: [
                                                                  ...?style
                                                                      .fontFamilyFallback,
                                                                  'Apple Symbols',
                                                                  'DejaVu Sans',
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                Text(
                                                  row.detail,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: style.copyWith(
                                                    color: theme.foreground
                                                        .withValues(alpha: .55),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                          if (_error != null)
                            Text(
                              _error!,
                              style: style.copyWith(color: theme.red),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
