import 'package:flutter/material.dart';

import '../core/models.dart';
import '../shared/layouts/widgets/sidebar_item.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_icon_button.dart';
import '../state/app_state.dart';
import '../state/project_navigation.dart';
import '../state/swarm_catalog.dart';
import 'engine_identity.dart';
import 'machine_rail.dart';

/// A view of the existing project catalog. Expanding a project has no terminal
/// side effects; only choosing a session or explicitly creating one opens work.
class ProjectSidebar extends StatefulWidget {
  const ProjectSidebar({
    super.key,
    required this.app,
    required this.projects,
    required this.onAddProject,
    required this.onNewProject,
    required this.onNewAgent,
    required this.onOpenAgent,
    required this.onCollapse,
  });

  final AppNotifier app;
  final SwarmProjectStore projects;
  final VoidCallback onAddProject, onNewProject, onCollapse;
  final ValueChanged<ProjectLocation> onNewAgent;
  final ValueChanged<SwarmAgentRef> onOpenAgent;

  @override
  State<ProjectSidebar> createState() => _ProjectSidebarState();
}

class _ProjectSidebarState extends State<ProjectSidebar> {
  bool _machines = false;
  String _query = '';
  final _collapsed = <String>{};
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([widget.app, widget.projects]),
      builder: (context, _) => Material(
        color: grid.AppPalette.swarmTabBar,
        child: FocusTraversalGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Projects')),
                          ButtonSegment(value: true, label: Text('Machines')),
                        ],
                        selected: {_machines},
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? grid.AppPalette.swarmAccent
                                : Colors.transparent,
                          ),
                          foregroundColor: WidgetStateProperty.resolveWith(
                            (states) => states.contains(WidgetState.selected)
                                ? grid.AppPalette.swarmTabBar
                                : grid.AppPalette.textSecondary,
                          ),
                        ),
                        onSelectionChanged: (value) =>
                            setState(() => _machines = value.single),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: Icons.chevron_left,
                      tooltip: 'Hide sidebar',
                      onPressed: widget.onCollapse,
                    ),
                  ],
                ),
              ),
              if (_machines)
                Expanded(
                  child: MachineRail(
                    notifier: widget.app,
                    onOpenAgent: widget.onOpenAgent,
                    onEscape: widget.onCollapse,
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                    key: const ValueKey('project-filter'),
                    controller: _filter,
                    decoration: const InputDecoration(
                      hintText: 'Find project or session',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _query = value.trim().toLowerCase()),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: grid.AppPalette.accentOnSurface,
                        ),
                        onPressed: widget.onAddProject,
                        icon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 16,
                        ),
                        label: const Text('Add folder'),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: grid.AppPalette.accentOnSurface,
                        ),
                        onPressed: widget.onNewProject,
                        child: const Text('New project'),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _projectList()),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Closing a view keeps its agent running.',
                    style: TextStyle(
                      color: grid.AppPalette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectList() {
    final groups = swarmProjects(widget.app, widget.projects.projects);
    final grouped = {
      for (final g in groups)
        for (final a in g.agents) (a.machineId, a.agent.id),
    };
    final other = swarmAgents(
      widget.app,
      _query,
    ).where((a) => !grouped.contains((a.machineId, a.agent.id))).toList();
    final visible = groups
        .where(
          (g) =>
              _query.isEmpty ||
              g.name.toLowerCase().contains(_query) ||
              projectLocations(g).any(
                (p) =>
                    '${p.folder} ${widget.app.projectMachineLabel(p.machineId)}'
                        .toLowerCase()
                        .contains(_query),
              ) ||
              g.agents.any((a) => a.searchText.contains(_query)),
        )
        .toList();
    if (visible.isEmpty && other.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _query.isNotEmpty
                ? 'No matching projects or sessions.'
                : 'Add a working folder or create a project to get started.',
            style: TextStyle(color: grid.AppPalette.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      children: [
        for (final group in visible) ...[
          SidebarItem(
            key: ValueKey('project:${group.id}'),
            label: group.name,
            icon: _collapsed.contains(group.id)
                ? Icons.chevron_right
                : Icons.expand_more,
            tooltip: '${group.name} · ${group.agents.length} sessions',
            onTap: () => setState(() {
              if (!_collapsed.remove(group.id)) _collapsed.add(group.id);
            }),
          ),
          if (!_collapsed.contains(group.id) || _query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final location in projectLocations(group)) ...[
                    _location(location),
                    for (final agent in group.agents.where(
                      (a) =>
                          a.machineId == location.machineId &&
                          a.project != null &&
                          projectFolderPath(a.project!.cwd) == location.folder,
                    ))
                      _agent(agent),
                  ],
                  for (final agent in group.agents.where(
                    (a) => a.project == null,
                  ))
                    _agent(agent),
                ],
              ),
            ),
        ],
        if (other.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Other sessions'),
          ),
          for (final agent in other) _agent(agent),
        ],
      ],
    );
  }

  Widget _location(ProjectLocation location) {
    final machine = widget.app.stateOf(location.machineId);
    final available =
        machine != null &&
        !machine.machine.isShared &&
        machine.nodeOnline != false &&
        machine.connectionStatus == ConnectionStatus.connected;
    final host = widget.app.projectMachineLabel(location.machineId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: '$host\n${location.folder}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    location.folder,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppIconButton(
            key: ValueKey(
              'new-project-agent:${location.machineId}:${location.folder}',
            ),
            icon: Icons.add,
            tooltip: available
                ? 'New agent here\n$host\n${location.folder}'
                : machine?.machine.isShared == true
                ? 'Cannot create agents on a shared machine'
                : 'Connect this machine to create an agent',
            onPressed: available ? () => widget.onNewAgent(location) : null,
          ),
        ],
      ),
    );
  }

  Widget _agent(SwarmAgentRef row) {
    final status = projectAgentStatus(widget.app, row);
    final branch = row.project?.branch;
    final detail =
        row.agent.launchDetail ?? row.agent.terminalUnavailableReason;
    final selected =
        widget.app.focusedPane?.machineId == row.machineId &&
        widget.app.focusedPane?.agentId == row.agent.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarItem(
          key: ValueKey('project-agent:${row.machineId}:${row.agent.id}'),
          label: row.agent.name,
          selected: selected,
          leading: EngineMark.forAgent(row.agent, size: 16),
          enabled: row.agent.terminalAvailable,
          tooltip:
              '${row.agent.name}\n$status${branch == null ? '' : ' · $branch'}\n${widget.app.projectMachineLabel(row.machineId)}\n${row.project?.cwd ?? 'Folder not reported'}${detail == null ? '' : '\n$detail'}',
          onTap: () => widget.onOpenAgent(row),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 36, bottom: 6),
          child: Text(
            '$status${branch == null || branch.isEmpty ? '' : ' · $branch'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: status == 'Needs input'
                  ? grid.AppPalette.accentOnSurface
                  : grid.AppPalette.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
