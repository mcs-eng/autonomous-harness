import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../state/app_state.dart';
import '../state/project_navigation.dart';
import '../state/swarm_catalog.dart';
import '../state/swarm_navigation.dart';
import 'engine_identity.dart';

int workspaceWaitingCount(AppNotifier app) => app.machineStates.values.fold(
  0,
  (count, machine) => count + machine.blockedAgents.length,
);

/// A small view of existing sessions, not another task or priority database.
/// Navigation history only breaks ties during this app session. Discovery and
/// terminal output must not pretend to be a recent visit.
List<SwarmAgentRef> workspaceResumeAgents(
  AppNotifier app,
  List<String> recent,
) {
  final rank = {for (var i = 0; i < recent.length; i++) recent[i]: i};
  final open = {
    for (final swarm in app.swarms)
      for (final pane in swarm.panes)
        if (pane.agentId != null) (pane.machineId, pane.agentId),
  };
  final rows = swarmAgents(app)
      .where(
        (row) =>
            row.agent.terminalAvailable ||
            open.contains((row.machineId, row.agent.id)),
      )
      .toList();
  int priority(SwarmAgentRef row) {
    if (app.questionFor(row.machineId, row.agent.id) != null) return 0;
    if (rank.containsKey(agentDestinationId(row.machineId, row.agent.id))) {
      return 1;
    }
    return open.contains((row.machineId, row.agent.id)) ? 2 : 3;
  }

  rows.sort((a, b) {
    var order = priority(a).compareTo(priority(b));
    if (order != 0) return order;
    order = (rank[agentDestinationId(a.machineId, a.agent.id)] ?? recent.length)
        .compareTo(
          rank[agentDestinationId(b.machineId, b.agent.id)] ?? recent.length,
        );
    if (order != 0) return order;
    order = a.agent.name.toLowerCase().compareTo(b.agent.name.toLowerCase());
    if (order != 0) return order;
    return agentDestinationId(
      a.machineId,
      a.agent.id,
    ).compareTo(agentDestinationId(b.machineId, b.agent.id));
  });
  return rows.take(3).toList();
}

class WorkspaceResume extends StatelessWidget {
  const WorkspaceResume({
    super.key,
    required this.app,
    required this.rows,
    required this.onOpen,
    required this.onAttention,
  });

  final AppNotifier app;
  final List<SwarmAgentRef> rows;
  final ValueChanged<SwarmAgentRef> onOpen;
  final VoidCallback onAttention;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final waiting = workspaceWaitingCount(app);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Continue working',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (waiting > 0)
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: grid.AppPalette.accentOnSurface,
                ),
                onPressed: onAttention,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: Text(
                  '$waiting ${waiting == 1 ? 'session needs' : 'sessions need'} your input',
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Return to a session, or start something new above.',
          style: TextStyle(color: grid.AppPalette.textSecondary),
        ),
        const SizedBox(height: 16),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: grid.AppPalette.swarmTabBar,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('resume:${row.machineId}:${row.agent.id}'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: EngineMark.forAgent(row.agent, size: 24),
                title: Text(
                  row.agent.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Tooltip(
                    message:
                        '${app.projectMachineLabel(row.machineId)}\n${row.project?.cwd ?? 'Folder not reported'}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${projectAgentStatus(app, row)} · ${app.projectMachineLabel(row.machineId)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                                row.project?.cwd ?? 'Folder not reported',
                                row.project?.branch,
                              ]
                              .whereType<String>()
                              .where((v) => v.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
                trailing: const Icon(Icons.arrow_forward, size: 18),
                onTap: () => onOpen(row),
              ),
            ),
          ),
      ],
    );
  }
}
