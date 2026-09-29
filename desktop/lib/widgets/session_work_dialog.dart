import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart' show TerminalTheme;

import '../core/agent_git_context.dart';
import '../core/models.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../terminal/terminal_text.dart';
import '../terminal/terminal_theme.dart';
import '../terminal/terminal_theme_store.dart';
import 'box_chrome.dart';
import 'terminal_text_action.dart';

/// Inspection only. This surface never sends terminal input or mutates a checkout.
class SessionWorkDialog extends StatefulWidget {
  const SessionWorkDialog({
    super.key,
    required this.agent,
    required this.read,
    this.online = true,
    this.open,
  });
  final Agent agent;
  final Future<Map<String, dynamic>> Function(int offset) read;
  final bool online;
  final Future<bool> Function(Uri)? open;
  @override
  State<SessionWorkDialog> createState() => _SessionWorkDialogState();
}

class _SessionWorkDialogState extends State<SessionWorkDialog> {
  AgentGitContext? _data;
  bool _loading = false, _branches = false;
  String? _error;
  int? _nextOffset;
  int _revision = 0;
  final _unavailable = <String>{};
  final _prScroll = ScrollController(), _branchScroll = ScrollController();
  final _prTab = FocusNode(), _branchTab = FocusNode();

  @override
  void initState() {
    super.initState();
    _data = widget.agent.gitContext;
    if (widget.online) unawaited(_refresh(0));
  }

  Future<void> _refresh(int offset) async {
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
    });
    Map<String, dynamic> result;
    try {
      result = await widget.read(offset);
    } catch (_) {
      result = {'status': 'unavailable'};
    }
    if (!mounted || revision != _revision) return;
    setState(() {
      _loading = false;
      final raw = result['gitContext'];
      if (raw is Map && result['history'] is Map) {
        _nextOffset = result['nextOffset'] is int
            ? result['nextOffset'] as int
            : null;
        _data =
            AgentGitContext.fromJson({...raw, 'history': result['history']}) ??
            _data;
        for (final lookup
            in result['lookups'] is List
                ? result['lookups'] as List
                : const []) {
          if (lookup is! Map || lookup['url'] is! String) continue;
          if (lookup['status'] == 'unavailable') {
            _unavailable.add(lookup['url']);
          } else {
            _unavailable.remove(lookup['url']);
          }
        }
      } else {
        _error = 'Could not refresh';
      }
    });
  }

  Future<void> _open(Uri uri) async {
    bool opened;
    try {
      opened =
          await (widget.open?.call(uri) ??
              launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      opened = false;
    }
    if (mounted && !opened) setState(() => _error = 'Could not open GitHub');
  }

  @override
  void dispose() {
    _revision++;
    _prScroll.dispose();
    _branchScroll.dispose();
    _prTab.dispose();
    _branchTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        final muted = style.copyWith(
          color: theme.foreground.withValues(alpha: .65),
        );
        final data = _data;
        final branches = [...?data?.branchRows]
          ..sort((a, b) {
            final checked = (b.checkedOut ? 1 : 0) - (a.checkedOut ? 1 : 0);
            return checked != 0 ? checked : a.branch.compareTo(b.branch);
          });
        final prs = [...?data?.pullRequests];
        int rank(AgentWorkPr pr) => switch (pr.state) {
          'Open' || 'Draft' => 0,
          'Merged' || 'Closed' => 2,
          _ => 1,
        };
        prs.sort((a, b) {
          final state = rank(a).compareTo(rank(b));
          final time = (pullRequestTime(b) ?? b.at).compareTo(
            pullRequestTime(a) ?? a.at,
          );
          return state != 0
              ? state
              : time != 0
              ? time
              : a.url.toString().compareTo(b.url.toString());
        });
        String repoName(String repository) =>
            repository.replaceFirst(RegExp(r'^github\.com/'), '');
        final repositories = {
          ...branches.map(
            (b) => b.repository == null ? null : repoName(b.repository!),
          ),
          ...prs.map((pr) => pr.url.pathSegments.take(2).join('/')),
        };
        final repository = repositories.length == 1
            ? repositories.single
            : null;
        final items = _branches ? branches.length : prs.length;
        final prIndices = {
          for (var i = 0; i < prs.length; i++) ValueKey('pr-${prs[i].url}'): i,
        };
        Widget line(String value, {bool dim = false, String? tooltip}) =>
            SizedBox(
              height: cell.height,
              child: Tooltip(
                message: tooltip ?? value,
                child: Text(
                  value,
                  style: dim ? muted : style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            );
        Widget tab(String label, bool branches) {
          final selected = _branches == branches;
          return Semantics(
            selected: selected,
            child: TextButton(
              key: ValueKey(branches ? 'git-branches-tab' : 'git-prs-tab'),
              focusNode: branches ? _branchTab : _prTab,
              onPressed: () => setState(() => _branches = branches),
              style: _actionStyle(theme).copyWith(
                foregroundColor: WidgetStatePropertyAll(
                  selected ? theme.foreground : muted.color,
                ),
              ),
              child: SizedBox(
                height: cell.height,
                child: Text(
                  label,
                  style: (selected ? style : muted).copyWith(
                    decoration: selected ? TextDecoration.underline : null,
                  ),
                ),
              ),
            ),
          );
        }

        return Dialog(
          backgroundColor: theme.background,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(
            horizontal: cell.width * 2,
            vertical: cell.height * 2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kTerminalCornerRadius),
            side: terminalPaneBorder(focused: true),
          ),
          child: ConstrainedBox(
            key: const ValueKey('work-dialog-surface'),
            constraints: BoxConstraints(
              maxHeight: math.max(
                0,
                math.min(
                  MediaQuery.sizeOf(context).height - cell.height * 4,
                  cell.height * 28,
                ),
              ),
            ),
            child: SizedBox(
              width: cell.width * 92,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: cell.width * 2,
                  vertical: cell.height,
                ),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      FocusScope.of(context).nextFocus();
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                      FocusScope.of(context).previousFocus();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(widget.agent.displayName),
                      if (repository != null) line(repository, dim: true),
                      SizedBox(height: cell.height),
                      Focus(
                        onKeyEvent: (node, event) {
                          if (event is! KeyDownEvent ||
                              !const [
                                LogicalKeyboardKey.arrowLeft,
                                LogicalKeyboardKey.arrowRight,
                              ].contains(event.logicalKey)) {
                            return KeyEventResult.ignored;
                          }
                          final branches =
                              event.logicalKey == LogicalKeyboardKey.arrowRight;
                          setState(() => _branches = branches);
                          (branches ? _branchTab : _prTab).requestFocus();
                          return KeyEventResult.handled;
                        },
                        child: LayoutBuilder(
                          builder: (context, constraints) => Wrap(
                            spacing: cell.width * 3,
                            children: [
                              tab(
                                '${constraints.maxWidth < cell.width * 36 ? 'PRs' : 'Pull requests'} (${prs.length})',
                                false,
                              ),
                              tab('Branches (${branches.length})', true),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: cell.height),
                      Flexible(
                        child: items == 0
                            ? line(
                                _loading
                                    ? 'Loading…'
                                    : _branches
                                    ? 'No branches'
                                    : 'No pull requests',
                                dim: true,
                              )
                            : ListView.builder(
                                key: ValueKey(
                                  _branches
                                      ? 'git-branches-list'
                                      : 'git-prs-list',
                                ),
                                controller: _branches
                                    ? _branchScroll
                                    : _prScroll,
                                shrinkWrap: true,
                                itemCount: items,
                                itemExtent: cell.height * (_branches ? 2 : 3),
                                findChildIndexCallback: _branches
                                    ? null
                                    : (key) => prIndices[key],
                                itemBuilder: (context, index) {
                                  if (_branches) {
                                    final branch = branches[index];
                                    return _BranchRow(
                                      branch: branch,
                                      cell: cell,
                                      style: style,
                                      muted: muted,
                                      repository: repository == null
                                          ? branch.repository
                                          : null,
                                    );
                                  }
                                  final pr = prs[index];
                                  return _PullRequestRow(
                                    key: ValueKey('pr-${pr.url}'),
                                    pr: pr,
                                    cell: cell,
                                    theme: theme,
                                    style: style,
                                    muted: muted,
                                    showRepository: repository == null,
                                    unavailable: _unavailable.contains(
                                      pr.url.toString(),
                                    ),
                                    onPressed: () => unawaited(_open(pr.url)),
                                  );
                                },
                              ),
                      ),
                      if (_nextOffset != null && widget.online)
                        TerminalTextAction(
                          label: 'Load more',
                          padding: EdgeInsets.zero,
                          onPressed: _loading
                              ? null
                              : () => unawaited(_refresh(_nextOffset!)),
                        ),
                      if (!widget.online)
                        line('Offline', dim: true)
                      else if (_error != null)
                        line(_error!, dim: true)
                      else if (data?.state == 'unavailable' ||
                          data?.state == 'uncertain')
                        line('Git unavailable', dim: true)
                      else if (_unavailable.isNotEmpty)
                        line('GitHub unavailable', dim: true),
                      if (data?.truncated == true)
                        line(
                          'Partial history',
                          dim: true,
                          tooltip: 'Only recorded branches and pull requests are available.',
                        ),
                      SizedBox(height: cell.height),
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          children: [
                            if (widget.online)
                              TerminalTextAction(
                                label: _loading ? 'Refreshing…' : 'Refresh',
                                padding: EdgeInsets.zero,
                                onPressed: _loading
                                    ? null
                                    : () => unawaited(_refresh(0)),
                              ),
                            TerminalTextAction(
                              label: 'Close',
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
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
  }
}

ButtonStyle _actionStyle(TerminalTheme theme) =>
    TextButton.styleFrom(
      alignment: Alignment.centerLeft,
      foregroundColor: theme.foreground,
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: const RoundedRectangleBorder(),
      splashFactory: NoSplash.splashFactory,
    ).copyWith(
      overlayColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.any(
              {
                WidgetState.focused,
                WidgetState.hovered,
                WidgetState.pressed,
              }.contains,
            )
            ? theme.selection
            : Colors.transparent,
      ),
    );

class _PullRequestRow extends StatelessWidget {
  const _PullRequestRow({
    super.key,
    required this.pr,
    required this.cell,
    required this.theme,
    required this.style,
    required this.muted,
    required this.showRepository,
    required this.unavailable,
    required this.onPressed,
  });
  final AgentWorkPr pr;
  final Size cell;
  final TerminalTheme theme;
  final TextStyle style, muted;
  final bool showRepository, unavailable;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final number = '#${pr.url.pathSegments.last}';
    final state = pr.state ?? 'Unknown';
    final title = pr.title ?? number;
    final at = pullRequestTime(pr);
    final date = at == null ? null : localWorkTime(at).split(' ').first;
    final metadata = [
      if (pr.title != null) number,
      if (showRepository) pr.url.pathSegments.take(2).join('/'),
      if (pr.headBranch != null)
        '${pr.headBranch}${pr.baseBranch == null ? '' : ' → ${pr.baseBranch}'}',
    ].join(' · ');
    final details = [
      '$number · $title · $state',
      pr.url.pathSegments.take(2).join('/'),
      if (pr.headBranch != null)
        '${pr.headBranch}${pr.baseBranch == null ? '' : ' → ${pr.baseBranch}'}',
      if (at != null)
        '${state == 'Merged' || state == 'Closed' ? state : 'Updated'} ${localWorkTime(at)}',
      if (unavailable) 'GitHub unavailable',
      if (pr.checkedAt != null) 'Checked ${localWorkTime(pr.checkedAt!)}',
      'Open on GitHub',
    ].join('\n');
    final color = switch (pr.state) {
      'Open' => theme.green,
      'Merged' => theme.brightMagenta,
      'Closed' => theme.brightRed,
      _ => muted.color,
    };
    Widget text(String value, TextStyle style) =>
        Text(value, style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: cell.height,
          child: Tooltip(
            message: details,
            child: TextButton(
              key: ValueKey('work-pr-${pr.url}'),
              onPressed: onPressed,
              style: _actionStyle(theme),
              child: Semantics(
                label: details.replaceAll('\n', ' · '),
                excludeSemantics: true,
                child: Row(
                  children: [
                    Expanded(child: text(title, style)),
                    SizedBox(width: cell.width * 2),
                    text(state, style.copyWith(color: color)),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          height: cell.height,
          child: Tooltip(
            message: details,
            child: ExcludeSemantics(
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: onPressed,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Expanded(child: text(metadata, muted)),
                      if (date != null) ...[
                        SizedBox(width: cell.width * 2),
                        text(date, muted),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BranchRow extends StatelessWidget {
  const _BranchRow({
    required this.branch,
    required this.cell,
    required this.style,
    required this.muted,
    required this.repository,
  });
  final AgentBranchRow branch;
  final Size cell;
  final TextStyle style, muted;
  final String? repository;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < cell.width * 45;
      final status = branch.checkedOut ? 'Checked out' : null;
      return Tooltip(
        message: [branch.branch, ?repository, ?status].join('\n'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: cell.height,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      branch.branch,
                      style: style,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!compact && status != null) ...[
                    SizedBox(width: cell.width * 2),
                    Text(status, style: muted),
                  ],
                ],
              ),
            ),
            if (repository != null || compact && status != null)
              SizedBox(
                height: cell.height,
                child: Text(
                  [?repository, if (compact) ?status].join(' · '),
                  style: muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    },
  );
}
