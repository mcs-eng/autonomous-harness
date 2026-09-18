import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/core/codex_profiles.dart';
import 'package:harness_mobile/core/models.dart';
import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';
import 'package:harness_mobile/widgets/remote_folder_picker.dart';

import 'phone_header.dart';
import 'phone_navigation.dart';
import 'settings_row.dart';

/// Starting an agent from the phone: a folder on that machine, and an engine to
/// run there.
///
/// A page rather than a sheet. There are two choices to make and one of them can
/// open a folder browser on top — a sheet that has to be dismissed to reach the
/// browser, and rebuilt after it, loses the other choice on the way.
///
/// The desktop asks the same two things (`widgets/new_agent_dialog.dart`) and a
/// few more it has room for — a Codex profile, a split to place the pane into,
/// a permission bypass. A phone shows one agent at a time, so there is no split
/// to aim at, and the rest belong to the machine that already knows them.
class NewAgentPage extends StatefulWidget {
  const NewAgentPage({
    super.key,
    required this.notifier,
    required this.machineId,
  });

  final AppNotifier notifier;
  final String machineId;

  @override
  State<NewAgentPage> createState() => _NewAgentPageState();
}

class _NewAgentPageState extends State<NewAgentPage> {
  String? _folder;
  String? _engine;
  String? _error;
  bool _creating = false;

  /// Codex state folders this machine reported, and the one chosen. Null is the
  /// machine's own default `CODEX_HOME`, which is what the desktop dialog calls
  /// "default profile" and what it starts on.
  List<LocalCodexProfile> _codexProfiles = const [];
  LocalCodexProfile? _codexProfile;
  bool _codexProfilesLoaded = false;

  @override
  void initState() {
    super.initState();
    // Which engines this machine actually has. Best effort: an unanswered probe
    // leaves the list to the engines its own agents are already running, and a
    // machine with neither still gets the browse-and-create path.
    unawaited(widget.notifier.probeEngines(widget.machineId));
    unawaited(_loadCodexProfiles());
  }

  /// Discovery runs on the MACHINE, never on this device — the phone has no
  /// Codex config of its own and the agent will not run here anyway.
  Future<void> _loadCodexProfiles() async {
    final result = await widget.notifier.listCodexProfiles(widget.machineId);
    if (!mounted) return;
    final raw = result['profiles'] as List<dynamic>? ?? const [];
    final loaded = raw.map(
      (entry) =>
          LocalCodexProfile.fromJson(Map<String, dynamic>.from(entry as Map)),
    );
    // Keyed by path: the machine can report one folder under two labels.
    final profiles = {for (final p in loaded) p.path: p}.values.toList();
    setState(() {
      _codexProfiles = profiles;
      _codexProfilesLoaded = true;
      // Exactly one, and there is nothing to choose between — the desktop
      // dialog settles on it the same way.
      if (profiles.length == 1) _codexProfile = profiles.single;
    });
  }

  /// Codex can be pointed at a state folder; nothing else can, and the CLI has
  /// to be new enough to be told.
  bool get _showsCodexProfile =>
      _engine == 'codex' &&
      _machine?.engines['codex']?.supportsCodexHome == true;

  MachineState? get _machine => widget.notifier.stateOf(widget.machineId);

  /// The folders this machine's agents already work in, most recently seen
  /// first — on a machine with agents, the answer is nearly always one of them.
  List<AgentProject> get _knownProjects {
    final machine = _machine;
    if (machine == null) return const [];
    final byPath = <String, AgentProject>{};
    for (final agent in machine.agents) {
      final project = machine.projectOf(agent);
      if (project != null) byPath.putIfAbsent(project.cwd, () => project);
    }
    return byPath.values.toList();
  }

  /// Every engine Harness knows, the way the desktop dialog offers them.
  ///
  /// Offered, not filtered to what is installed: an engine Harness can install
  /// is installed on launch, and hiding the rest would make a machine that has
  /// not answered the probe yet look like it runs one engine. The row carries
  /// the caveat instead — see [_engineNote].
  List<EngineIdentity> get _engines => allEngines;

  /// The one caveat worth printing beside an engine's name, or none.
  ///
  /// Absent and installable earns nothing: Harness puts it there before it
  /// launches. Absent and NOT installable is the one state nobody else can fix,
  /// so it keeps words. An unanswered probe says nothing at all — a row must
  /// not call an engine missing on the strength of an answer that never came.
  String? _engineNote(String engine) {
    final machine = _machine;
    if (machine == null || !machine.engines.loaded) return null;
    final entry = machine.engines[engine];
    if (entry == null || entry.installed || entry.installable) return null;
    return 'not installed';
  }

  Future<void> _browse() async {
    final chosen = await showRemoteFolderPicker(
      context,
      notifier: widget.notifier,
      machineId: widget.machineId,
      initialPath: _folder,
    );
    if (chosen == null || !mounted) return;
    setState(() {
      _folder = chosen;
      _error = null;
    });
  }

  Future<void> _create() async {
    final folder = _folder, engine = _engine;
    if (folder == null || engine == null || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    // Held so the id of what it starts comes back here — see
    // [AgentCreationAttempt.agentId]. A fresh one per submit, which is what the
    // call made on its own before: a retry after a refusal is a new request.
    final creation = AgentCreationAttempt();
    final error = await widget.notifier.createAgent(
      widget.machineId,
      engine: engine,
      folder: folder,
      // Only for Codex, and only when chosen: omitted, the machine launches
      // with its own default CODEX_HOME.
      codexHome: _showsCodexProfile ? _codexProfile?.path : null,
      attempt: creation,
    );
    if (!mounted) return;
    if (error == null) {
      _open(creation.agentId);
      return;
    }
    setState(() {
      _creating = false;
      _error = error;
    });
  }

  /// Where a finished creation lands: inside the agent it just started.
  ///
  /// Asking for an agent and being handed back the list to find it in is a step
  /// nobody wants — the answer to "create this" is the thing created. It
  /// REPLACES this page rather than stacking on it, so back from the terminal
  /// is the list this was opened from, not a form for an agent that now exists.
  ///
  /// A machine can still confirm a creation without naming the agent — an older
  /// CLI's reply carries no record. Then there is nothing to open, and the list
  /// behind this page picks the new agent up the way it picks up every other.
  void _open(String? agentId) {
    if (agentId == null) {
      Navigator.of(context).pop();
      return;
    }
    openAgent(
      context,
      widget.notifier,
      widget.machineId,
      agentId,
      replacingCurrentPage: true,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.notifier,
    builder: (context, _) {
      AppTheme.watch(context);
      final machine = _machine;
      final ready = _folder != null && _engine != null && !_creating;
      return Scaffold(
        backgroundColor: AppPalette.windowBg,
        body: SafeArea(
          child: Column(
            children: [
              PhoneHeader(
                title: 'New agent',
                subtitle: Text(
                  machine?.machine.displayName ?? '',
                  style: TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    const SettingsCaption('FOLDER'),
                    SettingsGroup(
                      children: [
                        for (final project in _knownProjects)
                          SettingsRow(
                            title: project.name,
                            detail: project.cwd,
                            leading: Icon(
                              LucideIcons.folder300,
                              size: 18,
                              color: AppPalette.textSecondary,
                            ),
                            trailing: _check(_folder == project.cwd),
                            onTap: () => setState(() {
                              _folder = project.cwd;
                              _error = null;
                            }),
                          ),
                        SettingsRow(
                          title: 'Browse…',
                          detail: _knownProjects.any((p) => p.cwd == _folder)
                              ? null
                              : _folder,
                          leading: Icon(
                            LucideIcons.folderSearch300,
                            size: 18,
                            color: AppPalette.textSecondary,
                          ),
                          onTap: () => unawaited(_browse()),
                        ),
                      ],
                    ),
                    const SettingsCaption('ENGINE'),
                    SettingsGroup(
                      children: [
                        for (final identity in _engines)
                          SettingsRow(
                            title: identity.label,
                            detail: _engineNote(identity.id),
                            leading: EngineMark(engine: identity.id, size: 18),
                            trailing: _check(_engine == identity.id),
                            onTap: () => setState(() {
                              _engine = identity.id;
                              _error = null;
                            }),
                          ),
                      ],
                    ),
                    if (_showsCodexProfile) ...[
                      const SettingsCaption('CODEX PROFILE'),
                      SettingsGroup(
                        children: [
                          SettingsRow(
                            title: 'Default profile',
                            detail: _codexProfilesLoaded
                                ? null
                                : 'Looking for others…',
                            trailing: _check(_codexProfile == null),
                            onTap: () => setState(() => _codexProfile = null),
                          ),
                          for (final profile in _codexProfiles)
                            SettingsRow(
                              title: profile.label,
                              detail: profile.path,
                              trailing: _check(_codexProfile == profile),
                              onTap: () =>
                                  setState(() => _codexProfile = profile),
                            ),
                        ],
                      ),
                    ],
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: AppPalette.offline,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: ready ? () => unawaited(_create()) : null,
                    child: Text(_creating ? 'Starting…' : 'Create agent'),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget? _check(bool selected) => selected
      ? Icon(LucideIcons.check300, size: 18, color: AppPalette.accent)
      : null;
}
