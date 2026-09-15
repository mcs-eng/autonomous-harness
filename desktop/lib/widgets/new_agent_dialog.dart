import 'dart:async';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../analytics/analytics.dart';
import '../state/pane_arrangement.dart';
import '../core/engine_availability.dart';
import '../core/codex_profiles.dart';
import '../core/project_folder.dart';
import '../core/repository_clone.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_checkbox.dart';
import '../shared/widgets/app_choice_picker.dart';
import '../shared/widgets/app_dialog.dart';
import '../shared/widgets/app_select_field.dart';
import '../state/app_state.dart';
import 'engine_identity.dart';
import 'codex_profile_field.dart';
import 'agent_picker.dart';
import 'remote_folder_picker.dart';
import 'new_agent_project_picker.dart';

/// Mirrors the harness CLI's `BYPASS_PERMISSION_FLAGS`
/// (autonomous-harness/cli/src/lib/engineLaunch.ts) 1:1 — this is UI-only display + gating, the CLI
/// is the actual enforcement point. An engine absent here shows no checkbox at all rather than
/// guessing a flag for a CLI we haven't verified. Keep both maps in sync.
const Map<String, String> kEngineBypassPermissionFlag = {
  'claude': '--dangerously-skip-permissions',
  'codex': '--dangerously-bypass-approvals-and-sandbox',
  'cursor': '--force',
  'opencode': '--auto',
};

enum NewAgentDialogResult { created, findExisting, backToSearch }

enum _FolderSource { newProject, local, remote }

/// Opens the Create Agent dialog for [machineId].
///
/// [source] names the door it was opened by — `machine_row`, `rail_empty`,
/// `pane_empty` or `shortcut` — and is required rather than defaulted, so a
/// fifth entry point has to say which one it is instead of quietly filing
/// itself under an existing name.
///
/// Hosts with an Add picker can set [offerFindExisting] and handle
/// [NewAgentDialogResult.findExisting] after the dialog closes.
Future<NewAgentDialogResult?> showNewAgentDialog(
  BuildContext context,
  AppNotifier notifier,
  String machineId, {
  required String source,
  String? initialFolder,
  String? swarmId,
  PaneSplitRequest? split,
  Future<void>? initialEngineProbe,
  bool offerFindExisting = false,
  bool offerBackToSearch = false,
}) {
  // Reported here rather than at each call site: the doors are four and
  // growing, and one that forgets to track is a hole in the funnel that only
  // shows up as a number quietly being too small.
  analytics.newAgentOpened(source: source);
  return showAppDialog<NewAgentDialogResult>(
    context: context,
    transitionDuration: Duration.zero,
    veilBlur: 0,
    builder: (context) => _NewAgentDialog(
      notifier: notifier,
      machineId: machineId,
      initialFolder: initialFolder,
      swarmId: swarmId ?? notifier.activeSwarmId,
      split: split,
      initialEngineProbe: initialEngineProbe,
      offerFindExisting: offerFindExisting,
      offerBackToSearch: offerBackToSearch,
    ),
  );
}

class _NewAgentDialog extends StatefulWidget {
  final AppNotifier notifier;
  final String machineId;
  final String? initialFolder;
  final String swarmId;
  final PaneSplitRequest? split;
  final Future<void>? initialEngineProbe;
  final bool offerFindExisting;
  final bool offerBackToSearch;

  const _NewAgentDialog({
    required this.notifier,
    required this.machineId,
    this.initialFolder,
    required this.swarmId,
    this.split,
    this.initialEngineProbe,
    required this.offerFindExisting,
    required this.offerBackToSearch,
  });

  @override
  State<_NewAgentDialog> createState() => _NewAgentDialogState();
}

class _NewAgentDialogState extends State<_NewAgentDialog> {
  final _folderFocus = FocusNode(debugLabel: 'Working folder');
  final _actionFocus = FocusNode(debugLabel: 'Create or check agent');
  GitHubRepository? _repository;
  final _choicesScroll = ScrollController();
  final _projectChoices = PageStorageBucket();
  late _FolderSource _folderSource = widget.initialFolder == null
      ? _FolderSource.newProject
      : _FolderSource.local;
  String? _preparedFolder;
  AgentCreationAttempt? _creation;
  bool _checkingCreation = false;
  bool get _confirmationPending => _creation?.awaitingConfirmation == true;
  bool get _choicesLocked => _submitting || _confirmationPending;
  late String _engine = allEngines.first.id;
  bool _engineChosenByUser = false;
  late String _machineId = widget.machineId;
  int _machineRevision = 0;
  late String? _folder = widget.initialFolder;
  LocalCodexProfile? _codexProfile;
  bool _codexProfilesBusy = true;
  bool _bypassPermission = false;

  /// Whether the fold is open. Closed on every open of the dialog, deliberately:
  /// it is shut for the case it exists to serve, and a drawer that remembers
  /// being open is a drawer that is open for somebody who never asked.
  bool _advancedOpen = false;
  bool _submitting = false;

  @override
  void dispose() {
    _folderFocus.dispose();
    _actionFocus.dispose();
    _choicesScroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final remembered = widget.notifier.agentPreference.value;
    if (allEngines.any((identity) => identity.id == remembered)) {
      _engine = remembered!;
      _engineChosenByUser = true;
    } else {
      _engine = _preferredInstalledEngine();
    }
    // Which engines this machine actually has. Asked here rather than at
    // connect because the answer costs the far side one interactive shell per
    // engine and is only ever read on this screen. Deferred a frame so the
    // probe's first notifyListeners() does not land mid-build.
    //
    // `force`, every time this dialog opens. A cached answer is worth nothing
    // here: engines arrive and leave through a terminal this app never sees —
    // `npm i -g opencode-ai`, `npm uninstall -g`, a venv deleted out from under
    // a symlink — and an install this very dialog started makes its own stored
    // answer stale the moment it finishes. Re-asking is bounded (one sweep, on
    // a deliberate user action) and the stored rows keep rendering until the new
    // answer lands, so nothing blanks.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // The modal's fallback focus can win autofocus. Claim the first
        // actionable control once the route and its focus tree are mounted.
        _folderFocus.requestFocus();
        unawaited(_probeEngines(initialProbe: widget.initialEngineProbe));
        unawaited(_loadAgentPreference());
      }
    });
  }

  Future<void> _loadAgentPreference() async {
    await widget.notifier.agentPreference.load();
    if (!mounted || _choicesLocked || _engineChosenByUser) return;
    final remembered = widget.notifier.agentPreference.value;
    if (allEngines.any((identity) => identity.id == remembered)) {
      setState(() {
        _engineChosenByUser = true;
        if (_engine != remembered) {
          _engine = remembered!;
          _codexProfile = null;
          _codexProfilesBusy = true;
        }
      });
    }
  }

  String _preferredInstalledEngine() {
    final engines = widget.notifier.stateOf(_machineId)?.engines;
    if (engines?.loaded != true || engines?[_engine]?.installed == true) {
      return _engine;
    }
    return allEngines
            .where((identity) => engines?[identity.id]?.installed == true)
            .firstOrNull
            ?.id ??
        _engine;
  }

  Future<void> _probeEngines({Future<void>? initialProbe}) async {
    final machineId = _machineId;
    final revision = _machineRevision;
    await (initialProbe ??
        widget.notifier.probeEngines(machineId, force: true));
    if (!mounted ||
        revision != _machineRevision ||
        _choicesLocked ||
        _engineChosenByUser) {
      return;
    }
    final preferred = _preferredInstalledEngine();
    if (preferred == _engine) return;
    setState(() {
      _engine = preferred;
      _codexProfile = null;
      _codexProfilesBusy = true;
    });
  }

  /// What this machine said about the selected engine, or null while the probe
  /// is still out (or when the machine could not answer).
  ///
  /// Null is deliberately not "missing": until the machine has spoken, this
  /// dialog behaves exactly as it did before the probe existed. Claiming an
  /// engine is absent on no evidence would send someone to install one they
  /// already have.
  EngineAvailability? _availability(String engine) {
    final machine = widget.notifier.stateOf(_machineId);
    if (machine == null || !machine.engines.loaded) return null;
    return machine.engines[engine];
  }

  /// A failed availability check can be retried without changing the choices.
  bool get _engineCheckFailed {
    final machine = widget.notifier.stateOf(_machineId);
    if (machine == null) return false;
    return !machine.engines.loaded && machine.engines.error != null;
  }

  bool get _checkingEngines =>
      widget.notifier.stateOf(_machineId)?.engines.inFlight != null;

  void _retryEngineCheck() {
    if (_choicesLocked || _checkingEngines) return;
    unawaited(_probeEngines());
  }

  bool _picking = false;
  bool _bypassHovered = false;
  String? _error;

  /// Whether the folder for this agent is picked by the GUI's own panel.
  ///
  /// This differs from "this machine is this computer". On Windows the CLI may
  /// run inside WSL2, which the app reaches over loopback but whose filesystem is
  /// not the GUI's: a native panel would browse THIS PC and hand back a `C:\…`
  /// path no Linux process can open. The question that decides the picker is
  /// `machineSharesGuiFilesystem`.
  ///
  /// Read per build rather than cached: `localOnly`/`localEndpoint` are settled
  /// by `_refreshMachines`, which can land while this dialog is open.
  bool get _machineIsThisComputer =>
      widget.notifier.machineSharesGuiFilesystem(_machineId);

  /// Create waits while the Codex profile list is still loading on a machine
  /// that can launch into one, so a click cannot land before the choice does.
  bool get _waitingForCodexProfile =>
      _engine == 'codex' &&
      _availability('codex')?.supportsCodexHome == true &&
      _codexProfilesBusy;

  /// [Machine.displayName], not `name` — the latter is nullable and a machine
  /// that never got one would title the dialog "Create Agent on null".
  String get _machineName =>
      widget.notifier.stateOf(_machineId)?.machine.displayName ??
      'this machine';

  Future<String?> _browse() async {
    if (_picking || _choicesLocked) return null;
    setState(() => _picking = true);
    final revision = _machineRevision;
    try {
      final picked = _machineIsThisComputer
          ? await getDirectoryPath(initialDirectory: _folder)
          : await showRemoteFolderPicker(
              context,
              notifier: widget.notifier,
              machineId: _machineId,
              initialPath: _folder,
            );
      return mounted && !_choicesLocked && revision == _machineRevision
          ? picked
          : null;
    } catch (_) {
      if (mounted && revision == _machineRevision) {
        setState(() => _error = 'Could not open the folder picker. Try again.');
      }
      return null;
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    final project = _preparedFolder == null ? _projectFolder : null;
    final folder =
        _preparedFolder ??
        (_folderSource == _FolderSource.local ? _folder : null);
    if ((folder == null && project == null) ||
        _submitting ||
        (!_confirmationPending && _waitingForCodexProfile)) {
      return;
    }
    final engine = _engine;
    final profile = _codexProfile;
    final bypassPermission =
        _bypassPermission && kEngineBypassPermissionFlag.containsKey(engine);
    if (!_confirmationPending) _creation = AgentCreationAttempt();
    setState(() {
      _checkingCreation = _confirmationPending;
      _submitting = true;
      _error = null;
    });
    final error = await widget.notifier.createAgent(
      _machineId,
      engine: engine,
      folder: folder ?? '',
      projectFolder: project,
      swarmId: widget.swarmId,
      split: widget.split,
      bypassPermission: bypassPermission,
      // Keep the explicit choice even if machine discovery changes mid-submit.
      // The notifier must reject a now-remote target, never use its default login.
      codexHome: engine == 'codex' ? profile?.path : null,
      attempt: _creation,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        if (!_confirmationPending) {
          _preparedFolder = _creation?.preparedFolder;
          if (_preparedFolder != null) {
            _folder = _preparedFolder;
            _repository = null;
            _folderSource = _FolderSource.local;
          }
        }
        _submitting = false;
        _error = error;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _actionFocus.requestFocus();
      });
      return;
    }
    analytics.agentCreated(engine: engine, bypassPermission: bypassPermission);
    Navigator.of(context).pop(NewAgentDialogResult.created);
  }

  ProjectFolderRequest? get _projectFolder => switch (_folderSource) {
    _FolderSource.newProject => const ProjectFolderRequest.newProject(),
    _FolderSource.local => null,
    _FolderSource.remote => switch (_repository) {
      final repository? => ProjectFolderRequest.remote(repository),
      null => null,
    },
  };

  void _toggleAdvanced() => setState(() => _advancedOpen = !_advancedOpen);

  @override
  Widget build(BuildContext context) {
    // Reads colour tokens, and lives in an Overlay — a top-down rebuild never
    // reaches it, so it has to watch for itself or it strands on the palette it
    // opened with.
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) => PopScope(
        // The launch request cannot be cancelled after it is sent. Keep its
        // outcome visible instead of allowing an accidental second launch.
        canPop: !_submitting,
        child: _buildDialog(context),
      ),
    );
  }

  Widget _buildDialog(BuildContext context) {
    final bypassFlag = kEngineBypassPermissionFlag[_engine];
    final canCreate =
        (_preparedFolder != null ||
            (_folderSource == _FolderSource.local
                ? _folder != null
                : _projectFolder != null)) &&
        !_picking &&
        !_submitting &&
        (_confirmationPending || !_waitingForCodexProfile);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
          if (canCreate) _submit();
        },
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
          if (canCreate) _submit();
        },
      },
      child: AlertDialog(
        constraints: const BoxConstraints.tightFor(width: _dialogWidth + 56),
        backgroundColor: grid.AppPalette.swarmField,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(switch (widget.split?.axis) {
          PaneResizeAxis.x => 'New Agent to the right',
          PaneResizeAxis.y => 'New Agent below',
          null => 'New Agent',
        }),
        titleTextStyle: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: 24,
          fontWeight: grid.AppFont.semibold,
          color: grid.AppPalette.textPrimary,
        ),
        titlePadding: const EdgeInsets.fromLTRB(28, 28, 28, 0),
        contentPadding: const EdgeInsets.fromLTRB(28, 24, 28, 16),
        actionsPadding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
        actionsOverflowButtonSpacing: 8,
        content: SizedBox(
          width: _dialogWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: math.min(
                650,
                math.max(220, MediaQuery.sizeOf(context).height - 230),
              ),
            ),
            child: Scrollbar(
              controller: _choicesScroll,
              thickness: 4,
              radius: const Radius.circular(2),
              child: SingleChildScrollView(
                controller: _choicesScroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AbsorbPointer(
                      absorbing: _choicesLocked,
                      child: ExcludeFocus(
                        excluding: _choicesLocked,
                        child: _choices(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: _gapBlock),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: _confirmationPending
                                    ? grid.AppPalette.textSecondary
                                    : Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: _dialogWidth,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final actions = Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (_confirmationPending)
                      TextButton(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: grid.AppPalette.textSecondary,
                        ),
                        child: const Text('Close'),
                      ),
                    if (widget.offerFindExisting &&
                        _confirmationPending &&
                        (!_submitting || _checkingCreation))
                      TextButton.icon(
                        onPressed: _submitting
                            ? null
                            : () =>
                                  Navigator.of(context)
                                      .pop(NewAgentDialogResult.findExisting),
                        icon: const Icon(LucideIcons.search, size: 16),
                        label: const Text('Find an agent'),
                      ),
                    FilledButton(
                      key: const ValueKey('create-agent-submit'),
                      focusNode: _actionFocus,
                      onPressed: canCreate ? _submit : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(192, 56),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        backgroundColor: grid.AppPalette.accent,
                        foregroundColor: Colors.white,
                        textStyle: TextStyle(
                          fontFamily: grid.AppFont.sans,
                          fontFamilyFallback: grid.AppFont.sansFallback,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        shape: const StadiumBorder(),
                        disabledForegroundColor: _submitting
                            ? grid.AppPalette.textPrimary
                            : null,
                      ),
                      child: _submitting
                          ? Semantics(
                              liveRegion: true,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _checkingCreation
                                        ? 'Checking status…'
                                        : _folderSource ==
                                                  _FolderSource.remote &&
                                              _preparedFolder == null
                                        ? 'Cloning and starting…'
                                        : 'Creating agent…',
                                  ),
                                ],
                              ),
                            )
                          : Text(
                              _confirmationPending ? 'Check status' : 'Create',
                            ),
                    ),
                  ],
                );
                final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
                final stacked =
                    (_advancedOpen || _confirmationPending) &&
                    constraints.maxWidth < 740 * math.min(1.4, scale);
                // Keep the controls mounted when the footer wraps or hides.
                // In particular, an explicit Default profile must stay chosen.
                return Flex(
                  direction: stacked ? Axis.vertical : Axis.horizontal,
                  mainAxisSize: stacked ? MainAxisSize.min : MainAxisSize.max,
                  crossAxisAlignment: stacked
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      fit: stacked ? FlexFit.loose : FlexFit.tight,
                      child: _settingsRow(bypassFlag),
                    ),
                    SizedBox(width: stacked ? 0 : 16, height: stacked ? 12 : 0),
                    Align(alignment: Alignment.centerRight, child: actions),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: grid.AppPalette.textSecondary,
      ),
    ),
  );

  Widget _choices() => LayoutBuilder(
    builder: (context, constraints) {
      final scaler = MediaQuery.textScalerOf(context);
      final minimumTileWidth = 180 * math.min(1.3, scaler.scale(14) / 14);
      final columns = constraints.maxWidth >= minimumTileWidth * 4 + 30
          ? 4
          : constraints.maxWidth >= minimumTileWidth * 2 + 10
          ? 2
          : 1;
      final tileSize = Size(
        (constraints.maxWidth - 10 * (columns - 1)) / columns,
        math.max(76, scaler.scale(14) * 2.5 + scaler.scale(12) * 1.25 + 24),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Choose an engine'),
          AgentPicker(
            compact: true,
            tileSize: tileSize,
            value: _engine,
            options: [
              for (final identity in allEngines)
                SelectOption(
                  value: identity.id,
                  label: identity.label,
                  leading: () => EngineMark(engine: identity.id, size: 14),
                ),
            ],
            onChanged: (value) {
              if (_choicesLocked) return;
              setState(() {
                unawaited(widget.notifier.agentPreference.select(value));
                _engineChosenByUser = true;
                _engine = value;
                _error = null;
                _codexProfile = null;
                _codexProfilesBusy = true;
                if (!kEngineBypassPermissionFlag.containsKey(value)) {
                  _bypassPermission = false;
                }
              });
            },
          ),
          if (!_confirmationPending && _engineCheckFailed) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Couldn’t check whether ${engineIdentity(_engine).label} is installed. '
                    'You can still try creating an agent.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: grid.AppPalette.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  key: const Key('new-agent-retry-check'),
                  onPressed: _checkingEngines ? null : _retryEngineCheck,
                  child: Text(_checkingEngines ? 'Checking…' : 'Retry'),
                ),
              ],
            ),
          ],
          const SizedBox(height: _gapField),
          _sectionLabel('Where will this agent run?'),
          _machineOptions(tileSize),
          const SizedBox(height: _gapField),
          _sectionLabel('Which project will this agent work in?'),
          PageStorage(
            bucket: _projectChoices,
            child: NewAgentProjectPicker(
              key: ValueKey('new-agent-projects-$_machineId'),
              notifier: widget.notifier,
              machineId: _machineId,
              initialFolder: _folder,
              focusNode: _folderFocus,
              tileSize: tileSize,
              locked: _choicesLocked,
              onBrowse: _browse,
              onSelected: (folder, repository) {
                if (_choicesLocked) return;
                setState(() {
                  _folder = folder;
                  _repository = repository;
                  _folderSource = repository != null
                      ? _FolderSource.remote
                      : folder != null
                      ? _FolderSource.local
                      : _FolderSource.newProject;
                  _preparedFolder = null;
                  _error = null;
                });
              },
            ),
          ),
        ],
      );
    },
  );

  Widget _profileOptions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_availability('codex')?.supportsCodexHome == true)
        CodexProfileField(
          notifier: widget.notifier,
          machineId: _machineId,
          machineIsThisComputer: _machineIsThisComputer,
          value: _codexProfile,
          observedPaths: {
            for (final agent in widget.notifier.stateOf(_machineId)!.agents)
              if (agent.engine == 'codex' && agent.codexHome != null)
                agent.codexHome!,
          },
          onChanged: (profile) {
            if (!_choicesLocked) {
              setState(() => _codexProfile = profile);
            }
          },
          onBusyChanged: (busy) {
            if (_codexProfilesBusy != busy) {
              setState(() => _codexProfilesBusy = busy);
            }
          },
        )
      else
        Text(
          _availability('codex') == null
              ? _engineCheckFailed && !_checkingEngines
                    ? 'Retry the agent check above to load Codex profiles.'
                    : 'Checking whether $_machineName supports Codex profiles…'
              : 'Update Harness CLI on $_machineName to choose a Codex profile.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );

  Widget _settingsRow(String? bypassFlag) => Wrap(
    spacing: 12,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Semantics(
        label: 'Advanced settings',
        button: true,
        toggled: _advancedOpen,
        child: IconButton(
          key: const Key('new-agent-advanced'),
          onPressed: _choicesLocked ? null : _toggleAdvanced,
          icon: const Icon(LucideIcons.settings, size: 16),
          color: grid.AppPalette.textFaint,
          style: IconButton.styleFrom(
            minimumSize: const Size(28, 28),
            padding: const EdgeInsets.all(6),
          ),
        ),
      ),
      _setting(
        _BypassCheck(
          value: bypassFlag != null && _bypassPermission,
          hovered: _bypassHovered,
          onHover: (value) => setState(() => _bypassHovered = value),
          onChanged: bypassFlag == null
              ? null
              : (value) => setState(() => _bypassPermission = value),
        ),
      ),
      if (_engine == 'codex') _setting(_profileOptions()),
    ],
  );

  Widget _setting(Widget child) => Offstage(
    offstage: !_advancedOpen,
    child: ExcludeFocus(
      excluding: !_advancedOpen || _choicesLocked,
      child: IgnorePointer(ignoring: _choicesLocked, child: child),
    ),
  );

  bool _machineOnline(MachineState machine) =>
      machine.isLocalMachine ||
      (machine.nodeOnline == true && !machine.needsLink);

  List<MachineState> get _orderedMachines {
    final machines = widget.notifier.machineStates.values.toList();
    int priority(MachineState machine) => machine.isLocalMachine
        ? 0
        : _machineOnline(machine)
        ? 1
        : 2;
    final originalOrder = {
      for (var i = 0; i < machines.length; i++)
        machines[i].machine.machineId: i,
    };
    machines.sort((a, b) {
      final order = priority(a).compareTo(priority(b));
      return order != 0
          ? order
          : originalOrder[a.machine.machineId]!.compareTo(
              originalOrder[b.machine.machineId]!,
            );
    });
    return machines;
  }

  Widget _machineOptions(Size tileSize) => AppChoicePicker<String>(
    key: const Key('new-agent-machine-field'),
    value: _machineId,
    moreKey: const Key('new-agent-machine-more'),
    moreLabel: 'More machines',
    moreLeading: const Icon(LucideIcons.monitor, size: 18),
    optionKey: (id) => ValueKey('new-agent-machine-$id'),
    showDetails: true,
    compact: true,
    wrap: true,
    tileSize: tileSize,
    preferredValues: _orderedMachines
        .map((machine) => machine.machine.machineId)
        .toList(),
    options: [
      for (final machine in widget.notifier.machineStates.values)
        SelectOption(
          value: machine.machine.machineId,
          label: machine.machine.displayName,
          detail: machine.isLocalMachine ? 'This machine' : null,
          leading: () => Icon(
            _machineOnline(machine)
                ? (machine.isLocalMachine
                      ? LucideIcons.laptop
                      : LucideIcons.monitor)
                : LucideIcons.monitorOff,
            size: 18,
            color: _machineOnline(machine)
                ? grid.AppPalette.textPrimary
                : grid.AppPalette.textFaint,
            semanticLabel: _machineOnline(machine) ? 'Online' : 'Offline',
          ),
        ),
    ],
    onChanged: (id) {
      if (id == _machineId || _choicesLocked) return;
      setState(() {
        _machineRevision++;
        _engineChosenByUser = true;
        _machineId = id;
        _folder = null;
        _repository = null;
        _folderSource = _FolderSource.newProject;
        _preparedFolder = null;
        _codexProfile = null;
        _codexProfilesBusy = true;
        _error = null;
      });
      unawaited(_probeEngines());
    },
  );
}

/// The project picker shares Open Agent’s generous reading space.
const double _dialogWidth = 1080;

/// Blocks inside one card: the command, the facts, the reason.
const double _gapBlock = 12;

/// One field and the next, down the choices column.
const double _gapField = 24;

class _BypassCheck extends StatelessWidget {
  const _BypassCheck({
    required this.value,
    required this.hovered,
    required this.onHover,
    required this.onChanged,
  });
  final bool value;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return MouseRegion(
      cursor: onChanged == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppCheckbox(value: value, hovered: hovered, onChanged: onChanged),
              const SizedBox(width: 10),
              Text(
                'Bypass approvals',
                style: TextStyle(
                  fontSize: 13,
                  color: onChanged == null
                      ? grid.AppPalette.textFaint
                      : grid.AppPalette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
