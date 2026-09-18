import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/empty_state.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';

import 'phone_navigation.dart';
import 'phone_search_index.dart';
import 'search_result_text.dart';
import 'status_pill.dart';

/// One query over everything the account can reach — agents and machines
/// together.
///
/// A screen of its own rather than a field above either list, and that is the
/// whole point: the two tabs each answer half the question, and somebody who
/// remembers "that review thing" does not know which half holds it. This is the
/// phone's version of the desktop's Open Agent picker, down to the ranking — the
/// two share [phoneFieldMatchScore] so a query that finds an agent on the laptop
/// finds the same agent here.
///
/// ⚠️ It never asks a machine anything. Keystrokes filter the cached index and
/// nothing else, so typing on a phone with two bars of signal stays instant and
/// costs no data.
void openPhoneSearch(BuildContext context, AppNotifier notifier) =>
    Navigator.of(context).push(
      phoneRoute((_) => PhoneSearchPage(notifier: notifier)),
    );

class PhoneSearchPage extends StatefulWidget {
  const PhoneSearchPage({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<PhoneSearchPage> createState() => _PhoneSearchPageState();
}

class _PhoneSearchPageState extends State<PhoneSearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'Phone search');
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final all = phoneSearchIndex(widget.notifier);
      final rows = rankPhoneSearch(all, _query);
      final terms = phoneSearchTerms(_query);
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        // The keyboard is up for this page's whole life, so the body must shrink
        // rather than let the list run underneath it.
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _SearchField(
                controller: _controller,
                focus: _focus,
                onChanged: (value) => setState(() => _query = value),
                onClear: () {
                  _controller.clear();
                  setState(() => _query = '');
                  // Clearing is a step back into browsing, not out of the
                  // screen — the caret stays where the next query will go.
                  _focus.requestFocus();
                },
                onCancel: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: _Results(
                  notifier: widget.notifier,
                  rows: rows,
                  terms: terms,
                  query: _query,
                  total: all.length,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The field, and the way out beside it.
///
/// Drawn here rather than through [PhoneHeader]: this page has no title. The
/// field IS the header, because nothing else on the screen is worth the 32pt
/// line a large title would take from the results.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focus,
    required this.onChanged,
    required this.onClear,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            // The rim lives on the BOX, never on the TextField inside it — see
            // the decoration below for why the field draws no border of its own.
            // Listening to the node here is what lets the box carry the focus
            // state instead.
            child: ListenableBuilder(
              listenable: focus,
              builder: (context, child) => AnimatedContainer(
                duration: AppMotion.hover,
                curve: AppMotion.curve,
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                decoration: BoxDecoration(
                  color: AppGlass.rowFill,
                  borderRadius: BorderRadius.circular(AppCard.radius),
                  // Focus is said once, by the rim of the box the field fills.
                  // The accent is the same one the caret already uses, so the
                  // two read as one state rather than as two decorations.
                  border: Border.all(
                    color: focus.hasFocus
                        ? AppPalette.accentOnSurface
                        : AppGlass.hair,
                  ),
                ),
                child: child,
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.search300,
                    size: 18,
                    color: AppPalette.textFaint,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focus,
                      autofocus: true,
                      onChanged: onChanged,
                      // The list is already filtered by the time a key is
                      // released; there is nothing left for the return key to
                      // submit, so it stays a plain "done" that drops the
                      // keyboard and leaves the results up.
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => focus.unfocus(),
                      autocorrect: false,
                      enableSuggestions: false,
                      // Agent names are ids as often as sentences —
                      // `Dijkstra-visualization.html` — and a capital forced
                      // onto the first letter of one is a wrong query.
                      textCapitalization: TextCapitalization.none,
                      // With the decoration's padding zeroed below, the field
                      // is exactly one line tall inside a 44pt box; this is
                      // what centres that line on the glyph beside it instead
                      // of letting it sit on the box's top edge.
                      textAlignVertical: TextAlignVertical.center,
                      style: TextStyle(
                        color: AppPalette.textPrimary,
                        fontSize: 16,
                      ),
                      cursorColor: AppPalette.accentOnSurface,
                      decoration: InputDecoration(
                        isDense: true,
                        // ⚠️ **Every** border state, not just `border`.
                        //
                        // `border` alone is the wrong half of the fix: it is
                        // the fallback, and the app's `inputDecorationTheme`
                        // fills the named states in — `focusedBorder` is a
                        // 1.5px accent outline at [AppControl.radius] (8).
                        // This box is [AppCard.radius] (12), so focusing drew
                        // a second, tighter blue rectangle INSIDE the rim —
                        // the reported bug. Naming each state is what keeps
                        // the theme from reaching past `border`.
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        // The theme also fills these, and both would draw on
                        // top of the box: a `surfaceContainerHighest` fill over
                        // the rim's own, and Material's phone-sized padding
                        // over the 44pt height set above.
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        hintText: 'Search agents and machines',
                        hintStyle: TextStyle(
                          color: AppPalette.textFaint,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  // Only once there is something to clear: a button that does
                  // nothing on an empty field is a button people learn to skip.
                  ValueListenableBuilder(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox(width: 4)
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClear,
                            child: Padding(
                              // Padding, not size: the glyph stays small while
                              // the target reaches a thumb.
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                LucideIcons.circleX300,
                                size: 18,
                                color: AppPalette.textFaint,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: AppPalette.accentOnSurface,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(44, 44),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.notifier,
    required this.rows,
    required this.terms,
    required this.query,
    required this.total,
  });

  final AppNotifier notifier;
  final List<PhoneSearchResult> rows;
  final List<String> terms;
  final String query;
  final int total;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    if (total == 0) {
      return const EmptyState(
        icon: LucideIcons.laptopMinimal300,
        title: 'Nothing to search yet',
        message:
            'Link a machine and its agents will be findable from here.',
      );
    }
    if (rows.isEmpty) {
      return EmptyState.noMatches(
        compact: false,
        message: 'Nothing matches “${query.trim()}”.',
      );
    }

    final agents = phoneSearchOfKind(rows, PhoneSearchKind.agent);
    final machines = phoneSearchOfKind(rows, PhoneSearchKind.machine);
    return ListView(
      // The keyboard is up and the finger is already on the glass; dragging the
      // list is how somebody reaches a result without putting it away first.
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      children: [
        // Grouped by kind rather than interleaved by score. The two kinds open
        // different things, and a machine row appearing between two agents is
        // read as another agent until the icon is noticed.
        if (agents.isNotEmpty) ...[
          _GroupLabel('Agents', count: agents.length),
          for (final row in agents)
            _ResultRow(
              row: row,
              terms: terms,
              onTap: () => _openAgent(context, row),
            ),
        ],
        if (machines.isNotEmpty) ...[
          _GroupLabel('Machines', count: machines.length),
          for (final row in machines)
            _ResultRow(
              row: row,
              terms: terms,
              onTap: () => _openMachine(context, row),
            ),
        ],
      ],
    );
  }

  /// Opens the agent as a pager over the OTHER matching agents.
  ///
  /// The neighbours are the search results, not the Agents tab's list: swiping
  /// walks exactly what the query returned, which is the list the person was
  /// looking at when they tapped. Handing it the unfiltered index instead would
  /// swipe into agents the query had just excluded.
  void _openAgent(BuildContext context, PhoneSearchResult row) {
    final entry = row.entry;
    if (entry == null || !entry.agent.terminalAvailable) return;
    // ⚠️ Built from [phoneSearchAgentEntries] rather than by unwrapping each
    // row here. A `?result.entry` collapse would silently SHORTEN this list if
    // an agent row ever arrived without its entry, and the pager walks it by
    // index — a shorter list than the one on screen sends a swipe to the wrong
    // agent, with nothing on screen to explain why.
    openAgentPager(context, notifier, phoneSearchAgentEntries(rows), entry);
  }

  /// Opens the machine, on whichever of its two screens it needs — its password
  /// form or its agent list. [openMachine] decides that from the machine's own
  /// state, so a machine that gets linked while this page is open opens on the
  /// right one.
  ///
  /// No pager here. The machines a query returns are a scattering of the
  /// Machines tab's order, and swiping along a set somebody assembled by typing
  /// a word is not a list — it is three unrelated computers.
  void _openMachine(BuildContext context, PhoneSearchResult row) =>
      openMachine(context, notifier, row.machineId);
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {required this.count});

  final String text;
  final int count;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: TextStyle(
              color: AppPalette.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            '$count',
            style: TextStyle(
              color: AppPalette.textFaint,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              fontFeatures: AppFont.tabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

/// One result: the mark, the two lines, and what a tap will do.
///
/// Shorter than the tabs' 70pt [PhoneCard] and without its fill. A result list
/// is read top to bottom against a query and abandoned the moment the right row
/// is seen, so it is built for scanning: more rows in a thumb's reach, and the
/// emphasis carried by the bolded match rather than by a card edge.
class _ResultRow extends StatefulWidget {
  const _ResultRow({
    required this.row,
    required this.terms,
    required this.onTap,
  });

  final PhoneSearchResult row;
  final List<String> terms;
  final VoidCallback onTap;

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _pressed = false;

  /// An agent whose terminal has gone cannot be opened, the same rule
  /// [AgentRow] applies. A machine can always be opened — a locked one opens on
  /// its password form, which is the thing to do about it.
  bool get _openable => switch (widget.row.kind) {
    PhoneSearchKind.agent => widget.row.entry?.agent.terminalAvailable ?? false,
    PhoneSearchKind.machine => true,
  };

  void _press(bool pressed) {
    if (!_openable || _pressed == pressed) return;
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final row = widget.row;
    final matches = phoneResultMatches(row, widget.terms);
    final waiting = row.entry?.isWaiting ?? false;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _press(true),
      onTapUp: (_) => _press(false),
      onTapCancel: () => _press(false),
      onTap: _openable
          ? () {
              // The keyboard goes away with the screen, not a frame after it —
              // dismissing it first keeps the push from animating over a
              // collapsing inset.
              FocusManager.instance.primaryFocus?.unfocus();
              widget.onTap();
            }
          : null,
      child: AnimatedContainer(
        duration: AppMotion.press,
        curve: AppMotion.curve,
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          // No resting fill. The tabs' cards earn one because they are the
          // screen's content; a result row is a line of an answer, and forty of
          // them each in their own box is a wall rather than a list.
          color: _pressed ? AppGlass.rowFill : Colors.transparent,
          borderRadius: BorderRadius.circular(AppCard.radius),
        ),
        child: Opacity(
          opacity: _openable ? 1 : 0.55,
          child: Row(
            children: [
              _Mark(row: row, waiting: waiting),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SearchResultText(
                      row.title,
                      matches: matches,
                      style: TextStyle(
                        color: AppPalette.textPrimary,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SearchResultText(
                      row.subtitle,
                      matches: matches,
                      style: TextStyle(
                        // The subtitle already carries the status in words, and
                        // a coloured status pill on every row of a result list
                        // turns the colour into wallpaper. The tone is spent on
                        // the mark instead, where one row at a time wears it.
                        color: AppPalette.textFaint,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _Action(row: row, openable: _openable),
            ],
          ),
        ),
      ),
    );
  }
}

/// The square mark at the head of a result: an agent's engine, a machine's
/// screen. Smaller than the tabs' 44pt [PhoneCardGlyph], to match the shorter
/// row.
class _Mark extends StatelessWidget {
  const _Mark({required this.row, required this.waiting});

  final PhoneSearchResult row;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppSurface.recess,
        borderRadius: BorderRadius.circular(10),
        // The same attention rim the Agents tab puts on a waiting row, so an
        // agent that has stopped to ask something is findable here too.
        border: waiting
            ? Border.all(color: AppPalette.warn.withValues(alpha: 0.42))
            : null,
      ),
      child: Center(
        child: switch (row.kind) {
          PhoneSearchKind.agent => EngineMark(
            engine: row.entry?.agent.engine,
            displayName: row.entry?.agent.engineDisplayName,
            size: 18,
          ),
          PhoneSearchKind.machine => Icon(
            LucideIcons.laptopMinimal300,
            size: 18,
            color: phoneToneColor(row.summary.tone),
          ),
        },
      ),
    );
  }
}

/// What a tap will do, said in a word.
///
/// The desktop's picker labels its rows the same way, and on a list mixing two
/// kinds the label is what separates "this opens a terminal" from "this asks you
/// for a password" before anything is tapped.
class _Action extends StatelessWidget {
  const _Action({required this.row, required this.openable});

  final PhoneSearchResult row;
  final bool openable;

  String get _label {
    if (!openable) return 'No terminal';
    return switch (row.kind) {
      PhoneSearchKind.agent => 'Open',
      PhoneSearchKind.machine =>
        row.machine?.needsLink ?? false ? 'Unlock' : 'View',
    };
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppGlass.hair),
      ),
      child: Text(
        _label,
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
