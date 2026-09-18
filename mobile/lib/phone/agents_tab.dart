import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/empty_state.dart';
import 'package:harness_mobile/state/app_state.dart';

import 'agent_index.dart';
import 'agent_row.dart';
import 'agents_page.dart';
import 'machine_filter_bar.dart';
import 'phone_card.dart';
import 'phone_fab.dart';
import 'phone_header.dart';
import 'phone_search_button.dart';
import 'phone_sheet.dart';
import 'phone_navigation.dart';
import 'phone_status.dart';

/// Every agent on the account, whichever machine it runs on.
///
/// The phone's home, and the direction's whole bet: people remember what an agent is CALLED, not
/// which computer it happens to be on. The machine is still there — as a filter above the list and
/// as a line under each name — it just stops being the thing you have to navigate through first.
class AgentsTab extends StatefulWidget {
  const AgentsTab({super.key, required this.notifier});

  final AppNotifier notifier;

  @override
  State<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<AgentsTab> {
  /// The machine the list is narrowed to, or null for all of them.
  ///
  /// Held as an id rather than a [MachineState]: the state objects are rebuilt as machines answer,
  /// and a filter holding a stale instance would quietly stop matching anything.
  String? _machineId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final machines = filterableMachines(widget.notifier);
      // A machine that goes away — unlinked, or dropped from the account — must not leave the list
      // filtered to nothing with no way to see it is.
      final selected = machines.any((m) => m.machine.machineId == _machineId)
          ? _machineId
          : null;
      final all = agentIndex(widget.notifier);
      final shown = selected == null
          ? all
          : all.where((entry) => entry.machineId == selected).toList();
      final error = widget.notifier.lastError;
      // Only machines that are answering. Creating needs one to list its folders and name the
      // engines it has, so a machine that is offline or still wants its password cannot host a new
      // agent — the same gate the machine's own page puts on its `+`.
      final ready = [
        for (final machine in machines)
          if (phoneMachineStatusOf(machine) == PhoneMachineStatus.ready)
            machine,
      ];
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        // ⚠️ Absent rather than disabled when nothing can host an agent. The empty state already
        // says where that is fixed (the Machines tab), and a button whose only outcome is an
        // explanation of why it does nothing is worse than no button.
        //
        // It floats above the tab bar without being told to: this Scaffold is the BODY of the
        // shell's (`phone_shell.dart`), whose own `bottomNavigationBar` sits below it.
        floatingActionButton: ready.isEmpty
            ? null
            : PhoneFab(
                icon: LucideIcons.plus300,
                tooltip: 'New agent',
                onPressed: () => _pickMachine(context, ready),
              ),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // No account avatar here. Settings ▸ Account carries the address
              // and the sign-out, and a second copy in the corner of the home
              // screen bought nothing but a place for them to disagree.
              //
              // The one control the title line does carry is search, because
              // what it searches is not this list: it spans agents AND machines,
              // which is the half of the question this tab cannot answer. It
              // appears only once there is something to find — a glyph that
              // opens an empty screen is worse than no glyph.
              PhoneHeader(
                large: true,
                title: 'Agents',
                trailing: [
                  if (machines.isNotEmpty)
                    PhoneSearchButton(notifier: widget.notifier),
                ],
              ),
              if (error != null)
                _ErrorStrip(message: error, notifier: widget.notifier),
              if (machines.isNotEmpty)
                MachineFilterBar(
                  machines: machines,
                  selectedId: selected,
                  countFor: (id) =>
                      all.where((entry) => entry.machineId == id).length,
                  totalCount: all.length,
                  onSelect: (id) => setState(() => _machineId = id),
                ),
              Expanded(
                child: _Body(
                  notifier: widget.notifier,
                  entries: shown,
                  machines: machines,
                  filtered: selected != null,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  /// Which machine the new agent runs on, asked before anything else.
  ///
  /// This list is the one screen that does NOT already know: it is every agent on the account, and
  /// the machine is a filter above it rather than the thing navigated through. So the `+` cannot
  /// carry a machine the way [AgentsPage]'s does, and guessing one — the first, the filtered one —
  /// would put an agent on a computer nobody named.
  ///
  /// ⚠️ Shown even when only one machine qualifies. A sheet of one still says WHERE the agent is
  /// about to be created, and that is the question this step exists to answer.
  void _pickMachine(BuildContext context, List<MachineState> ready) =>
      showPhoneSheet(
        context,
        title: 'New agent on…',
        actions: [
          for (final machine in ready)
            PhoneSheetAction(
              icon: LucideIcons.laptopMinimal300,
              label: machine.machine.displayName,
              onTap: () => openNewAgent(
                context,
                widget.notifier,
                machine.machine.machineId,
              ),
            ),
        ],
      );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.notifier,
    required this.entries,
    required this.machines,
    required this.filtered,
  });

  final AppNotifier notifier;
  final List<AgentEntry> entries;
  final List<MachineState> machines;
  final bool filtered;

  /// Whether anything is still on its way in — a machine connecting, or its agent list not yet
  /// answered. "Loading" and "answered with nothing" must not render the same.
  bool get _stillArriving => machines.any(
    (machine) => switch (phoneMachineStatusOf(machine)) {
      PhoneMachineStatus.connecting => true,
      _ => false,
    },
  );

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      if (notifier.machines.isEmpty && notifier.machinesLoading) {
        return const PhoneListSkeleton();
      }
      if (notifier.machines.isEmpty) {
        return const EmptyState(
          icon: LucideIcons.laptopMinimal300,
          title: 'No machines yet',
          message:
              'Run Harness on a computer signed in to this account and it '
              'will appear here.',
        );
      }
      if (_stillArriving) return const PhoneListSkeleton();
      if (filtered) {
        return const EmptyState(
          icon: LucideIcons.squareTerminal300,
          title: 'No agents on this machine',
          message: 'Start one from Harness there and it will appear here.',
        );
      }
      // Machines exist and have answered, but none of them can be reached — every one needs its
      // password or is offline. The Machines tab is where that is fixed, so say so.
      final reachable = machines.any(
        (machine) => phoneMachineStatusOf(machine) == PhoneMachineStatus.ready,
      );
      if (!reachable) {
        return const EmptyState(
          icon: LucideIcons.lockKeyhole300,
          title: 'No machines are open yet',
          message:
              'Open the Machines tab to enter a machine password, or start '
              'Harness on a computer that is offline.',
        );
      }
      return const EmptyState(
        icon: LucideIcons.squareTerminal300,
        title: 'No agents yet',
        message: 'Start one from Harness on a machine and it will appear here.',
      );
    }

    // The order a swipe on the terminal page walks, split back into the two sections this list
    // draws. Taken from [visibleAgents] rather than assembled here so the page and the list cannot
    // drift apart — the split below is presentation, the order is not.
    final ordered = visibleAgents(entries);
    final waiting = ordered.where((entry) => entry.isWaiting).toList();
    final rest = ordered.where((entry) => !entry.isWaiting).toList();
    return RefreshIndicator(
      onRefresh: notifier.retryMachines,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: phoneListPadding(context),
        children: [
          if (waiting.isNotEmpty) ...[
            const _SectionLabel('Waiting for you'),
            for (final entry in waiting) _row(context, ordered, entry),
            const SizedBox(height: 6),
          ],
          if (rest.isNotEmpty) ...[
            if (waiting.isNotEmpty) const _SectionLabel('All agents'),
            for (final entry in rest) _row(context, ordered, entry),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    List<AgentEntry> ordered,
    AgentEntry entry,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: kPhoneCardGap),
    child: AgentRow(
      entry: entry,
      // The whole visible list goes with the tap, so the page opens as a pager over exactly the
      // agents on screen — the filter chip included. Swiping there walks this order.
      onTap: () => openAgentPager(context, notifier, ordered, entry),
      // The same sheet a machine's own page opens, from [AgentsPage] rather than written again
      // here: one agent reached two ways must not offer two different sets of actions, and the
      // delete wording in particular is the one that has to match.
      onLongPress: () =>
          showAgentActions(context, notifier, entry.machineId, entry.agent),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: AppPalette.textFaint,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.notifier});

  final String message;
  final AppNotifier notifier;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert300, size: 18, color: AppPalette.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: notifier.retryMachines,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
