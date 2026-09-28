import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/project_folder.dart';
import '../shared/layouts/widgets/sidebar_item.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_icon_button.dart';
import '../state/app_state.dart';
import '../state/project_navigation.dart';
import '../state/swarm_catalog.dart';
import 'agent_drag.dart';
import 'engine_identity.dart';

/// A view of the existing project catalog. Expanding a project has no terminal
/// side effects; only choosing a session or explicitly creating one opens work.
///
/// Machines are upstream's Machines Manager ([onShowMachines]); this sidebar
/// keeps no machine tree of its own.
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
    required this.onShowMachines,
    required this.onSignIn,
  });

  final AppNotifier app;
  final SwarmProjectStore projects;
  final VoidCallback onAddProject, onNewProject, onCollapse;
  final ValueChanged<ProjectLocation> onNewAgent;
  final ValueChanged<SwarmAgentRef> onOpenAgent;

  /// Opens the machine list and its actions (link, rename, delete).
  final VoidCallback onShowMachines;

  /// Raises the sign-in over the desk, from local mode.
  final VoidCallback onSignIn;

  @override
  State<ProjectSidebar> createState() => _ProjectSidebarState();
}

class _ProjectSidebarState extends State<ProjectSidebar> {
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
                padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Projects',
                        style: TextStyle(
                          color: grid.AppPalette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // Upstream's Machines Manager: every machine, its state,
                    // and link, rename, password and delete. The fork's own
                    // machine tree gave way to it with the 2026-09-23 sync.
                    AppIconButton(
                      key: const ValueKey('project-sidebar-machines'),
                      icon: Icons.dns_outlined,
                      tooltip: 'Machines',
                      onPressed: widget.onShowMachines,
                    ),
                    AppIconButton(
                      icon: Icons.chevron_left,
                      tooltip: 'Hide sidebar',
                      onPressed: widget.onCollapse,
                    ),
                  ],
                ),
              ),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              if (widget.app.isGuest) _LocalModeLine(onSignIn: widget.onSignIn),
            ],
          ),
        ),
      ),
    );
  }

  Widget _projectList() {
    final groups = swarmProjects(widget.app, widget.projects.projects);
    final headings = _headings(groups);
    final grouped = {
      for (final g in groups)
        for (final a in g.agents) (a.machineId, a.agent.id),
    };
    final other = swarmAgents(widget.app)
        .where(
          (a) => !grouped.contains((a.machineId, a.agent.id)) && _matches(a),
        )
        .toList();
    final visible = groups
        .where(
          (g) =>
              _query.isEmpty ||
              g.name.toLowerCase().contains(_query) ||
              headings[g.id]!.toLowerCase().contains(_query) ||
              projectLocations(g).any(
                (p) =>
                    '${p.folder} ${widget.app.projectMachineLabel(p.machineId)}'
                        .toLowerCase()
                        .contains(_query),
              ) ||
              g.agents.any(_matches),
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
            label: headings[group.id]!,
            icon: _collapsed.contains(group.id)
                ? Icons.chevron_right
                : Icons.expand_more,
            tooltip: headings[group.id] == group.name
                ? '${group.name} · ${group.agents.length} sessions'
                : '${headings[group.id]}\n${group.name} · ${group.agents.length} sessions',
            onTap: () => setState(() {
              if (!_collapsed.remove(group.id)) _collapsed.add(group.id);
            }),
          ),
          if (!_collapsed.contains(group.id) || _query.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _groupSessions(group),
              ),
            ),
        ],
        if (other.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Other sessions'),
          ),
          for (final (i, label) in sessionLabels(other).indexed)
            _agent(other[i], label),
        ],
      ],
    );
  }

  /// What each project heading says. A folder Harness named itself, with no
  /// saved project behind it, is headed by its sessions instead ("Codex").
  Map<String, String> _headings(List<SwarmProjectGroup> groups) {
    final generated = [
      for (final g in groups)
        if (g.saved == null &&
            g.agents.isNotEmpty &&
            isGeneratedWorkFolder(g.name))
          g,
    ];
    final labels = distinctLabels(
      [
        for (final g in generated)
          {for (final a in g.agents) sessionLabel(a.agent)}.join(', '),
      ],
      [for (final g in generated) g.agents.first.agent.name],
    );
    return {
      for (final g in groups) g.id: g.name,
      for (final (i, g) in generated.indexed) g.id: labels[i],
    };
  }

  /// A session matches on everything [SwarmAgentRef.searchText] covers, and
  /// on the label and raw name the sidebar shows.
  bool _matches(SwarmAgentRef row) {
    final text =
        '${row.searchText} ${sessionLabel(row.agent)} ${row.agent.name}'
            .toLowerCase();
    return _query.split(RegExp(r'\s+')).every(text.contains);
  }

  List<Widget> _groupSessions(SwarmProjectGroup group) {
    final locations = projectLocations(group);
    final hosts = locations.map((item) => item.machineId).toSet();
    final bases = [for (final l in locations) folderBase(l.folder)];
    final placed = [
      for (final location in locations)
        group.agents
            .where(
              (a) =>
                  a.machineId == location.machineId &&
                  a.project != null &&
                  projectFolderPath(a.project!.cwd) == location.folder,
            )
            .toList(),
    ];
    final unplaced = group.agents.where((a) => a.project == null).toList();
    final ordered = [...placed.expand((rows) => rows), ...unplaced];
    final labels = sessionLabels(ordered);
    final labelOf = {
      for (final (i, row) in ordered.indexed)
        (row.machineId, row.agent.id): labels[i],
    };
    return [
      for (final (i, location) in locations.indexed) ...[
        _location(
          location,
          showHost: hosts.length > 1,
          // A folder line only when it tells the locations apart or differs
          // from the heading; the whole path when two end the same way.
          folder: isGeneratedWorkFolder(location.folder)
              ? null
              : bases.where((base) => base == bases[i]).length > 1
              ? location.folder
              : locations.length > 1 || bases[i] != group.name
              ? bases[i]
              : null,
        ),
        for (final row in placed[i])
          _agent(row, labelOf[(row.machineId, row.agent.id)]!),
      ],
      for (final row in unplaced)
        _agent(row, labelOf[(row.machineId, row.agent.id)]!),
    ];
  }

  Widget _location(
    ProjectLocation location, {
    required bool showHost,
    required String? folder,
  }) {
    final machine = widget.app.stateOf(location.machineId);
    final available =
        machine != null &&
        !machine.machine.isShared &&
        machine.nodeOnline != false &&
        machine.connectionStatus == ConnectionStatus.connected;
    final host = widget.app.projectMachineLabel(location.machineId);
    final where = '$host\n${location.folder}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 0, 4),
      child: Row(
        children: [
          if (showHost || folder != null)
            Expanded(
              child: Tooltip(
                message: where,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showHost)
                      Text(
                        host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: grid.AppPalette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    if (folder != null)
                      Text(
                        folder,
                        maxLines: folder == location.folder ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: grid.AppPalette.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          if (machine == null ||
              machine.needsLink ||
              machine.nodeOnline == false ||
              machine.connectionStatus != ConnectionStatus.connected)
            AppIconButton(
              icon: Icons.info_outline,
              tooltip: 'Machine connection details',
              onPressed: () => _showRecovery(location.machineId),
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

  Widget _agent(SwarmAgentRef row, String shown) {
    final status = projectAgentStatus(widget.app, row);
    final branch = row.project?.branch;
    final detail =
        row.agent.launchDetail ?? row.agent.terminalUnavailableReason;
    final selected =
        widget.app.focusedPane?.machineId == row.machineId &&
        widget.app.focusedPane?.agentId == row.agent.id;
    final entry = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SidebarItem(
          key: ValueKey('project-agent:${row.machineId}:${row.agent.id}'),
          label: shown,
          selected: selected,
          leading: EngineMark.forAgent(row.agent, size: 16),
          tooltip: [
            shown,
            if (shown != row.agent.name) row.agent.name,
            '$status${branch == null ? '' : ' · $branch'}',
            widget.app.projectMachineLabel(row.machineId),
            row.project?.cwd ?? 'Folder not reported',
            ?detail,
          ].join('\n'),
          onTap: () => _openOrExplain(row),
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
    // A session without a terminal cannot fill a tile, so it cannot be dragged
    // to one either: the grid would answer a deliberate gesture with nothing.
    if (!row.agent.terminalAvailable) return entry;
    final drag = AgentDragRef(
      machineId: row.machineId,
      agentId: row.agent.id,
      name: shown,
    );
    // Onto a tile or the grid's empty slot, as the machine tree this sidebar
    // replaced allowed. Horizontal only: the list scrolls vertically, and the
    // tiles are to the right.
    return Draggable<AgentDragRef>(
      data: drag,
      affinity: Axis.horizontal,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => agentDrag.value = drag,
      onDragEnd: (_) => agentDrag.value = null,
      onDraggableCanceled: (_, _) => agentDrag.value = null,
      feedback: _DragChip(label: shown, agent: row.agent),
      childWhenDragging: Opacity(opacity: 0.4, child: entry),
      child: entry,
    );
  }

  /// Open a session that has a view or a live terminal; otherwise say why it
  /// cannot be opened, so a tap or Enter never closes the drawer and then does
  /// nothing.
  void _openOrExplain(SwarmAgentRef row) {
    final hasView = widget.app.swarms.any(
      (swarm) => swarm.panes.any(
        (pane) =>
            pane.machineId == row.machineId && pane.agentId == row.agent.id,
      ),
    );
    if (row.agent.terminalAvailable || hasView) {
      widget.onOpenAgent(row);
    } else {
      _showRecovery(row.machineId, row: row);
    }
  }

  Future<void> _showRecovery(String machineId, {SwarmAgentRef? row}) async {
    final machine = widget.app.stateOf(machineId);
    final needsLink = machine?.needsLink == true;
    final offline = machine == null || machine.nodeOnline == false;
    final reason = needsLink
        ? 'This machine needs to be linked before its sessions can reconnect. Open Machines to review its connection.'
        : offline
        ? 'This machine is offline. Make sure it is awake and connected, then refresh its status.'
        : row?.agent.launchDetail ??
              row?.agent.terminalUnavailableReason ??
              'The session is not available yet. Refresh its status or open Machines for connection details.';
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          row == null
              ? widget.app.projectMachineLabel(machineId)
              : sessionLabel(row.agent),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (row != null) ...[
                Text(widget.app.projectMachineLabel(machineId)),
                const SizedBox(height: 12),
              ],
              Text(reason),
              const SizedBox(height: 12),
              const Text(
                'Refreshing checks the existing session. It does not create or restart an agent.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'machines'),
            child: const Text('Show machines'),
          ),
          if (machine != null && !needsLink)
            FilledButton(
              onPressed: () => Navigator.pop(context, 'refresh'),
              child: const Text('Refresh status'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'machines') widget.onShowMachines();
    if (action == 'refresh') await widget.app.reloadMachineData(machineId);
  }
}

/// What travels with the pointer while a session is dragged to the grid.
class _DragChip extends StatelessWidget {
  const _DragChip({required this.label, required this.agent});

  final String label;
  final Agent agent;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: grid.AppPalette.windowBg,
          border: Border.all(color: grid.AppPalette.divider),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            EngineMark.forAgent(agent, size: 14),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: grid.AppPalette.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fork: the sidebar's statement that this window runs without an account —
/// upstream's guest desk, which the fork calls local mode — and its way to the
/// other machines.
class _LocalModeLine extends StatelessWidget {
  const _LocalModeLine({required this.onSignIn});

  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return Container(
      key: const ValueKey('project-sidebar-local-mode'),
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: grid.AppPalette.divider)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.laptop_outlined,
            size: 16,
            color: grid.AppPalette.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Local mode',
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'This computer, no account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: grid.AppPalette.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('project-sidebar-sign-in'),
            style: TextButton.styleFrom(
              foregroundColor: grid.AppPalette.accentOnSurface,
              visualDensity: VisualDensity.compact,
            ),
            onPressed: onSignIn,
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
