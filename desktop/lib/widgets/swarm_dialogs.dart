import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../shared/widgets/app_select_field.dart';
import '../state/app_state.dart';
import '../state/swarm_catalog.dart';
import 'link_another_machine_dialog.dart';
import 'remote_folder_picker.dart';
import 'clone_repository_dialog.dart';

Future<String?> showSwarmRenameDialog(BuildContext context, String name) =>
    showAppDialog<String>(
      context: context,
      transitionDuration: Duration.zero,
      veilBlur: 0,
      veilTint: const Color(0x99000000),
      builder: (_) => _RenameSwarmDialog(name: name),
    );

class _RenameSwarmDialog extends StatefulWidget {
  const _RenameSwarmDialog({required this.name});
  final String name;
  @override
  State<_RenameSwarmDialog> createState() => _RenameSwarmDialogState();
}

class _RenameSwarmDialogState extends State<_RenameSwarmDialog> {
  late final _text = TextEditingController(
    text: widget.name,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.name.length);
  final _focus = FocusNode(debugLabel: 'Rename Tab name');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.isCurrentOf(context) != false) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final name = _text.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    final accent = grid.AppPalette.accentOnSurface;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return ListenableBuilder(
      listenable: _text,
      builder: (context, _) => AlertDialog(
        title: const Text('Rename Tab'),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        content: SizedBox(
          width: 360,
          child: Semantics(
            label: 'Harness name',
            child: TextSelectionTheme(
              data: TextSelectionTheme.of(context)
                  .copyWith(selectionColor: accent.withValues(alpha: .3)),
              child: TextField(
                controller: _text,
                focusNode: _focus,
                autofocus: true,
                maxLength: 80,
                cursorColor: accent,
                textInputAction: TextInputAction.done,
                style: TextStyle(
                  fontSize: 15,
                  color: grid.AppPalette.textPrimary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: grid.AppSurface.recess,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: border,
                  enabledBorder: border,
                  focusedBorder: border.copyWith(
                    borderSide: BorderSide(color: accent),
                  ),
                  counterText: '',
                  suffixText: _text.text.characters.length >= 70
                      ? '${_text.text.characters.length}/80'
                      : null,
                  suffixStyle: TextStyle(
                    fontSize: 11,
                    color: grid.AppPalette.textSecondary,
                  ),
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: grid.AppPalette.textSecondary,
              minimumSize: const Size(88, 38),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              side: const BorderSide(color: Colors.white24),
              shape: const StadiumBorder(),
            ),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _text.text.trim().isEmpty ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: grid.AppPalette.swarmAccent,
              foregroundColor: grid.AppPalette.swarmTabBar,
              minimumSize: const Size(88, 38),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: const StadiumBorder(),
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

Future<SavedSwarmProject?> showSwarmProjectDialog(
  BuildContext context,
  AppNotifier notifier,
) => showAppDialog<SavedSwarmProject>(
  context: context,
  builder: (_) => _ProjectDialog(notifier: notifier),
);

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({required this.notifier});
  final AppNotifier notifier;
  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late String? machineId =
      (widget.notifier.machineStates.values
                  .where((m) => m.isLocalMachine)
                  .firstOrNull ??
              widget.notifier.machineStates.values.firstOrNull)
          ?.machine
          .machineId;
  String? path;
  String? error;
  bool picking = false;
  int _machineRevision = 0;
  String get folderName =>
      (path
                  ?.split(RegExp(r'[/\\]'))
                  .where((part) => part.isNotEmpty)
                  .lastOrNull ??
              path ??
              '')
          .characters
          .take(80)
          .join();

  Future<void> browse() async {
    final id = machineId;
    if (id == null || picking) return;
    final revision = _machineRevision;
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final folder = widget.notifier.machineSharesGuiFilesystem(id)
          ? await getDirectoryPath(initialDirectory: path)
          : await showRemoteFolderPicker(
              context,
              notifier: widget.notifier,
              machineId: id,
              initialPath: path,
            );
      if (!mounted || revision != _machineRevision) return;
      setState(() {
        if (folder != null) _acceptFolder(id, folder);
      });
    } catch (_) {
      if (mounted && revision == _machineRevision) {
        setState(
          () =>
              error = 'Could not browse this machine. Reconnect and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> clone() async {
    final id = machineId;
    if (id == null ||
        picking ||
        !widget.notifier.machineSharesGuiFilesystem(id)) {
      return;
    }
    final revision = _machineRevision;
    setState(() => picking = true);
    final folder = await showCloneRepositoryDialog(
      context,
      initialFolder: path,
    );
    if (!mounted) return;
    setState(() {
      picking = false;
      if (folder != null && revision == _machineRevision) {
        _acceptFolder(id, folder);
      }
    });
  }

  void _acceptFolder(String id, String folder) {
    if (widget.notifier.stateOf(id) == null) {
      path = null;
      error = 'This machine is no longer available. Choose a machine again.';
      return;
    }
    final resolved = widget.notifier.backendFolderFor(id, folder);
    error = resolved.error;
    path = resolved.error == null ? resolved.path : null;
  }

  void _save() {
    final id = machineId;
    final folder = path;
    if (id == null || folder == null || picking) return;
    // Discovery may identify a WSL backend while the picker/dialog is open.
    // Persist the location that this machine can actually use, or refuse it.
    setState(() => _acceptFolder(id, folder));
    if (error != null || path == null || folderName.isEmpty) return;
    Navigator.pop(
      context,
      SavedSwarmProject(machineId: id, path: path!, name: folderName),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add project'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose an existing working folder.',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),
          const SizedBox(height: 20),
          if (machineId != null)
            AppSelectField<String>(
              value: machineId!,
              options: [
                for (final machine in widget.notifier.machineStates.values)
                  SelectOption(
                    value: machine.machine.machineId,
                    label: machine.isLocalMachine
                        ? 'This computer'
                        : machine.machine.displayName,
                  ),
              ],
              onChanged: (value) => setState(() {
                if (machineId == value) return;
                _machineRevision++;
                machineId = value;
                path = null;
                error = null;
              }),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: machineId == null || picking ? null : browse,
            icon: const Icon(Icons.folder_open, size: 17),
            label: Text(
              path ?? 'Choose folder',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.notifier.machineSharesGuiFilesystem(machineId ?? ''))
            TextButton(
              onPressed: picking ? null : clone,
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
              child: const Text('Clone repository…'),
            ),
          if (error != null)
            Text(
              error!,
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: path == null || folderName.isEmpty || picking ? null : _save,
        child: const Text('Add project'),
      ),
    ],
  );
}

/// Link another machine. The dialog itself lives in
/// `link_another_machine_dialog.dart`; this name is what every caller — the
/// Machines menu, ⌘ commands, the machines manager — has always used.
Future<void> showSwarmLinkDialog(BuildContext context, AppNotifier notifier) =>
    showLinkAnotherMachineDialog(context, notifier);
