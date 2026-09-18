import 'dart:async';

import 'package:flutter/material.dart';

import 'package:harness_mobile/state/app_state.dart';
import 'agent_index.dart';
import 'terminal_page.dart';

/// The agents a terminal page can swipe between, in the order the list drew them.
///
/// A SNAPSHOT, taken when the page opens. The Agents tab sorts partly on state that moves by itself
/// — an idle agent that starts working sorts upward — so a pager recomputing this list would
/// renumber its own pages under the finger: the page to the right could become a different agent
/// between one swipe and the next, for a reason nothing on screen explains.
///
/// Only entries that can actually be opened are kept. A row with no terminal does nothing when
/// tapped in the list, and a page for it would be a screen of "Attaching…" that never resolves —
/// worse mid-swipe than in a list, where at least the row is still readable.
class AgentSwipeList {
  AgentSwipeList(List<AgentEntry> entries)
    : entries = [
        for (final entry in entries)
          if (entry.agent.terminalAvailable) entry,
      ];

  final List<AgentEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// Whether the pager wraps around — past the last agent is the first one again.
  ///
  /// Needs at least TWO agents, and that is not a formality. With one, every page of an endless
  /// pager is the same agent: the screen would take a swipe, move, and land on what it just left,
  /// which reads as the gesture having failed rather than as a list with one thing in it. One agent
  /// gets one page and no swipe at all.
  bool get wraps => entries.length > 1;

  /// Where an agent sits in the snapshot, or null if it is not in it.
  ///
  /// Used once, to find the page to open on: the tapped row may be a "Waiting for you" row, an
  /// agent with no terminal may have been dropped by the constructor above, and neither the list's
  /// index nor the row's position can be assumed to survive either.
  int? indexOf(String machineId, String agentId) {
    for (final (index, entry) in entries.indexed) {
      if (entry.machineId == machineId && entry.agent.id == agentId) {
        return index;
      }
    }
    return null;
  }
}

/// One agent's terminal, with the agents beside it a swipe away.
///
/// ⚠️ **The pager holds the route, and [TerminalPage] no longer does.** The page draws one agent's
/// header and terminal, but a swipe has to move something ABOVE it — so this sits between the route
/// and the page. Without [neighbours] it is a passthrough, which is how the Machines tab still gets
/// the old single-page behaviour.
///
/// Exactly one page is ACTIVE at a time, and that word is load-bearing: [TerminalPanel] claims the
/// keyboard whenever it is built focused, so three mounted pages all claiming it would put the
/// software keyboard on a terminal nobody is looking at — and the characters typed into it would
/// reach that agent. See [TerminalPage.isActive].
class AgentSwipeHost extends StatefulWidget {
  const AgentSwipeHost({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
    required this.neighbours,
  });

  final AppNotifier notifier;

  /// The agent the route was opened on — the page that is shown first. Never changes; where the
  /// pager has moved to since is [_AgentSwipeHostState._current].
  final String machineId;
  final String agentId;

  /// Null for a page opened without neighbours, which is then simply the page.
  final AgentSwipeList? neighbours;

  @override
  State<AgentSwipeHost> createState() => _AgentSwipeHostState();
}

class _AgentSwipeHostState extends State<AgentSwipeHost> {
  /// How many laps of the list the opening page sits above zero — see [initState].
  static const _origin = 1000;

  PageController? _controller;

  /// The page being looked at, which is what decides [TerminalPage.isActive].
  ///
  /// ⚠️ **A page, not an agent, and on a short list the difference is a bug.** A wrapped pager of
  /// two agents mounts pages N-1, N and N+1 — and N-1 and N+1 are the SAME agent as each other.
  /// Testing "is this page's agent the current agent" would then mark two mounted pages active at
  /// once, and two live [TerminalPanel]s both claiming the keyboard is exactly what `isActive`
  /// exists to prevent: the one that wins can be the page off-screen.
  int _page = 0;

  /// The agent showing now — [_page]'s entry, named rather than numbered.
  ///
  /// Both forms are kept because the two questions genuinely differ once the pager wraps: which PAGE
  /// is on screen decides who may hold the keyboard, and which AGENT is on screen decides which pane
  /// [_detachAll] spares on the way out. A page number cannot answer the second — the agent it names
  /// has panes attached under other page numbers too.
  late ({String machineId, String agentId}) _current = (
    machineId: widget.machineId,
    agentId: widget.agentId,
  );

  /// Every agent this pager attached, so leaving can detach them again.
  ///
  /// ⚠️ **Without this the pager leaks terminals.** The phone's old rule was one pane, enforced by
  /// closing every other one on the way in; a pager has to keep its neighbours attached, so nothing
  /// would ever close them. Each pane left behind is a remote stream with a 10,000-line scrollback
  /// and a heartbeat, held for a screen that is gone — and swiping through ten agents and going back
  /// would leave ten of them.
  ///
  /// Recorded rather than recomputed: by the time this page is disposed the list may have moved on,
  /// and the panes to close are the ones actually opened, not the ones a fresh list would name.
  final Set<({String machineId, String agentId})> _attached = {};

  @override
  void initState() {
    super.initState();
    _attached.add(_current);
    final neighbours = widget.neighbours;
    if (neighbours == null || neighbours.isEmpty) return;
    // The snapshot is fixed for as long as this pager lives, so the opening page is the only index
    // that ever has to be looked up — from there the controller and the list stay in step, and
    // [_page] and [_current] both follow from `onPageChanged` alone.
    final start = neighbours.indexOf(widget.machineId, widget.agentId) ?? 0;
    // Opening in the MIDDLE of the endless run, not at its start, is what lets the first swipe go
    // either way: page 0 has nothing to its left, and the last agent has to be reachable by swiping
    // back from the first one. `_origin` is far enough from both ends that neither is reachable by
    // hand — ~1,000 laps of the list — and it is a whole number of laps, so `page % length` still
    // names the agent.
    _page = neighbours.wraps
        ? _origin * neighbours.entries.length + start
        : start;
    _controller = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detachAll();
    super.dispose();
  }

  /// Closes what this pager opened, keeping the one the phone is still pointed at.
  ///
  /// The agent last read stays attached — that is the pane the Agents tab's row now refers to, and
  /// re-opening it should be instant rather than a fresh "Attaching…". Everything swiped past goes.
  ///
  /// Not awaited, and deliberately: `dispose` cannot wait, and `closePane` only has to be STARTED —
  /// it detaches the session and tells the daemon on its own. The notifier outlives this widget, so
  /// nothing here is torn down underneath it.
  void _detachAll() {
    final notifier = widget.notifier;
    final keep = _current;
    for (final agent in _attached) {
      if (agent == keep) continue;
      final pane = notifier.panes
          .where((p) => p.machineId == agent.machineId && p.agentId == agent.agentId)
          .firstOrNull;
      if (pane != null) unawaited(notifier.closePane(pane.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final neighbours = widget.neighbours;
    final controller = _controller;
    if (neighbours == null || controller == null || neighbours.isEmpty) {
      return TerminalPage(
        notifier: widget.notifier,
        machineId: widget.machineId,
        agentId: widget.agentId,
        isActive: true,
      );
    }
    return PageView.builder(
      controller: controller,
      // The terminal below scrolls vertically and selects text only with a mouse, so the horizontal
      // axis is free — and here it is the pager's ALONE. The route's own edge-swipe back used to
      // compete for it and win at the left margin, being registered above this in the tree: a drag
      // started near the edge to reach the previous AGENT left the screen instead. The route is
      // pushed without that gesture now (see `phoneRoute`'s `swipeToGoBack`), so going back is the
      // header's back band, or Android's back button.
      physics: const PageScrollPhysics(),
      // No count is what makes it endless: the builder answers for any page, and the modulo below
      // wraps it back onto the list. A one-agent list keeps its single page instead — see
      // [AgentSwipeList.wraps].
      itemCount: neighbours.wraps ? null : neighbours.entries.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        final entry = neighbours.entries[i % neighbours.entries.length];
        return TerminalPage(
          // ⚠️ Keyed by PAGE, not by agent, and the difference only shows once the pager wraps: an
          // endless run holds several pages for the same agent — the lap before and the lap after —
          // and an agent-shaped key would make Flutter treat two live pages as one widget, which
          // throws on a duplicate key the moment both are mounted. Each page then learns its own
          // `_hadPane`, which is what that flag wants anyway: it is about this page's attach, not
          // about the agent.
          key: ValueKey(i),
          notifier: widget.notifier,
          machineId: entry.machineId,
          agentId: entry.agent.id,
          // Exactly one mounted page, by page number — see [_page].
          isActive: i == _page,
        );
      },
    );
  }

  void _onPageChanged(int index) {
    final neighbours = widget.neighbours;
    if (neighbours == null || neighbours.isEmpty) return;
    // The page number runs off in both directions once the pager wraps; the agent it names does not.
    final entry = neighbours.entries[index % neighbours.entries.length];
    final arrived = (machineId: entry.machineId, agentId: entry.agent.id);
    // Recorded BEFORE the attach, so a pane always has an owner to close it — see [_attached]. An
    // agent added here that never finishes attaching costs nothing: [_detachAll] looks for its pane
    // and finds none.
    _attached.add(arrived);
    setState(() {
      _page = index;
      _current = arrived;
    });
    // Attaching is what makes the terminal live, and it only happens once the page has SETTLED —
    // `onPageChanged` fires at the halfway point of a settled swipe, not on every dragged pixel, so
    // flicking across five agents attaches the ones passed through rather than all of them at once.
    // `selectAgent` reuses a pane that is already there, so coming back costs nothing.
    unawaited(widget.notifier.selectAgent(entry.machineId, entry.agent.id));
  }
}
