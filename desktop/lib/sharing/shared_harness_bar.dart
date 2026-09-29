import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/theme/workspace_bar_style.dart';
import '../widgets/terminal_text_action.dart';
import '../widgets/workspace_bar_control.dart';

/// What a reader of a shared harness is looking at, most urgent first.
enum SharedPaneStatus {
  ended('Sharing ended'),
  reconnecting('Reconnecting'),
  notRunning('Not running'),
  live('Live');

  const SharedPaneStatus(this.label);
  final String label;

  static SharedPaneStatus of({
    required bool ended,
    required bool connected,
    required bool terminalStopped,
  }) {
    if (ended) return SharedPaneStatus.ended;
    if (!connected) return SharedPaneStatus.reconnecting;
    if (terminalStopped) return SharedPaneStatus.notRunning;
    return SharedPaneStatus.live;
  }

  /// Why the screen may be empty, shown under the bar; null when it is not.
  String? get notice => this == SharedPaneStatus.notRunning
      ? 'The owner’s harness isn’t running right now. '
            'This view reconnects when it starts again.'
      : null;

  Color get color => switch (this) {
    SharedPaneStatus.live => grid.AppPalette.online,
    SharedPaneStatus.reconnecting => grid.AppPalette.warn,
    SharedPaneStatus.notRunning ||
    SharedPaneStatus.ended => grid.AppPalette.textFaint,
  };
}

/// The one bar above a shared harness: name, state and read-only label on the
/// left, the reader's actions on the right. Workspace bar type and height, so a
/// shared pane reads like any other pane header.
class SharedHarnessBar extends StatelessWidget {
  const SharedHarnessBar({
    super.key,
    required this.name,
    required this.status,
    required this.commentsSelected,
    required this.onToggleComments,
    required this.onClose,
    this.detail,
    this.viewerSelected,
    this.onSelectViewer,
    this.onRetry,
  });

  final String name;
  final String? detail;
  final SharedPaneStatus status;
  final bool commentsSelected;
  final VoidCallback onToggleComments;
  final VoidCallback onClose;

  /// Null hides the Terminal/Viewer switch: the pane shows one of them only.
  final bool? viewerSelected;
  final ValueChanged<bool>? onSelectViewer;
  final VoidCallback? onRetry;

  /// Below this width the actions move to a second row instead of squeezing
  /// the name to nothing.
  static const narrowWidth = 640.0;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final cell = workspaceBarCellSizeOf(context);
    final height = workspaceBarControlHeight(context);
    Widget row(List<Widget> children) => SizedBox(
      height: height,
      child: Row(children: children),
    );
    return Container(
      padding: EdgeInsets.symmetric(horizontal: cell.width),
      color: grid.AppSurface.recess,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = _identity(cell);
          final actions = _actions(cell);
          if (constraints.maxWidth >= narrowWidth) {
            return row([Expanded(child: Row(children: identity)), ...actions]);
          }
          return Column(
            children: [
              row(identity),
              row([const Spacer(), ...actions]),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _identity(Size cell) {
    final muted = workspaceBarTextStyle(color: grid.AppPalette.textSecondary);
    return [
      Flexible(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: workspaceBarTextStyle(
            color: grid.AppPalette.textPrimary,
            emphasized: true,
          ),
        ),
      ),
      if (detail case final detail?)
        Text(' · $detail', maxLines: 1, style: muted),
      SizedBox(width: cell.width * 2),
      Text('●', style: workspaceBarTextStyle(color: status.color)),
      SizedBox(width: cell.width),
      Text(status.label, style: muted),
      Text(' · ', style: muted),
      Text('View only', style: muted),
    ];
  }

  List<Widget> _actions(Size cell) {
    final viewer = viewerSelected;
    return [
      if (viewer != null && onSelectViewer != null) ...[
        _ViewTab(
          label: 'Terminal',
          selected: !viewer,
          onPressed: () => onSelectViewer!(false),
        ),
        _ViewTab(
          label: 'Viewer',
          selected: viewer,
          onPressed: () => onSelectViewer!(true),
        ),
        SizedBox(width: cell.width),
      ],
      if (onRetry case final retry?)
        TerminalTextAction(label: 'Retry', onPressed: retry),
      TerminalTextAction(
        label: commentsSelected ? 'Watch' : 'Comments',
        onPressed: onToggleComments,
      ),
      Tooltip(
        message: 'Close shared harness',
        child: TerminalTextAction(label: 'Close', onPressed: onClose),
      ),
    ];
  }
}

/// A Terminal/Viewer choice drawn like a workspace tab: the selection is a
/// fill, hover and focus are bold text.
class _ViewTab extends StatelessWidget {
  const _ViewTab({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cell = workspaceBarCellSizeOf(context);
    final size = workspaceBarTextSizeOf(context, label);
    return WorkspaceBarControl(
      label: label,
      selected: selected,
      selectedBackground: grid.AppPalette.windowBg,
      onPressed: onPressed,
      builder: (context, emphasized) => SizedBox(
        width: size.width + cell.width * 2,
        height: workspaceBarControlHeight(context),
        child: Center(
          child: Text(
            label,
            style: workspaceBarTextStyle(
              color: selected
                  ? grid.AppPalette.textPrimary
                  : grid.AppPalette.textSecondary,
              emphasized: emphasized,
            ),
          ),
        ),
      ),
    );
  }
}

/// One quiet line under the bar: why the terminal is empty or has ended.
class SharedHarnessNotice extends StatelessWidget {
  const SharedHarnessNotice(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final cell = workspaceBarCellSizeOf(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: cell.width,
        vertical: cell.height / 2,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: Text(
        message,
        style: workspaceBarTextStyle(color: grid.AppPalette.textSecondary),
      ),
    );
  }
}
