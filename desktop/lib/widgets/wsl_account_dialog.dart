import 'package:flutter/material.dart';

import '../core/wsl_preferences.dart';
import '../core/wsl_runtime.dart';

Future<bool?> showWslAccountDialog(
  BuildContext context, {
  WslPreferencesStore? store,
  Future<List<String>> Function()? listDistros,
}) => showDialog<bool>(
  context: context,
  builder: (_) => WslAccountDialog(
    store: store ?? wslPreferencesStore,
    listDistros: listDistros ?? WslRuntime().usableDistros,
  ),
);

/// Selects the account for the next app launch, never a live session.
class WslAccountDialog extends StatefulWidget {
  const WslAccountDialog({
    super.key,
    required this.store,
    required this.listDistros,
  });

  final WslPreferencesStore store;
  final Future<List<String>> Function() listDistros;

  @override
  State<WslAccountDialog> createState() => _WslAccountDialogState();
}

class _WslAccountDialogState extends State<WslAccountDialog> {
  late final TextEditingController _username;
  String? _distro;
  List<String> _distros = [];
  bool _useDefault = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final selection = widget.store.savedSelection;
    _useDefault = selection == null;
    _distro = selection?.distro;
    _username = TextEditingController(text: selection?.username ?? '');
    _loadDistros();
  }

  Future<void> _loadDistros() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final names = await widget.listDistros();
      if (!mounted) return;
      setState(() {
        _distros = names
            .where((name) => !WslRuntime.isDockerDistro(name))
            .toSet()
            .toList();
        // Keep a saved but unavailable distro visible; never silently retarget.
        _distro ??= _distros.firstOrNull;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not list Linux distributions. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    WslSelection? selection;
    if (!_useDefault) {
      final distro = _distro ?? '';
      final username = _username.text.trim();
      final error = WslSelection.validationError(
        distro: distro,
        username: username,
      );
      if (error != null || !_distros.contains(distro)) {
        setState(
          () => _error = error ?? 'Choose an available Linux distribution.',
        );
        return;
      }
      selection = WslSelection(distro: distro, username: username);
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.save(selection);
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not save this choice. Your current account is unchanged.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Linux account for Harness'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Choose the account that owns your Harness installation and projects. This does not change Ubuntu or other WSL apps.',
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Use WSL default accounts'),
                value: _useDefault,
                onChanged: _saving
                    ? null
                    : (value) => setState(() {
                        _useDefault = value!;
                        _error = null;
                      }),
              ),
              if (!_useDefault) ...[
                const SizedBox(height: 12),
                if (_loading)
                  const LinearProgressIndicator()
                else
                  DropdownButtonFormField<String>(
                    key: ValueKey('wsl-distro:${_distro ?? ''}'),
                    initialValue: _distro,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Linux distribution',
                    ),
                    items: {..._distros, ?_distro}
                        .map(
                          (name) => DropdownMenuItem(
                            value: name,
                            child: Text(name, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _distro = value),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _username,
                  enabled: !_saving,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Linux username',
                    hintText: 'The account used for your existing installation',
                  ),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _save(),
                ),
                if (_username.text.trim() == 'root') ...[
                  const SizedBox(height: 12),
                  const Text(
                    'root has administrator access inside this distribution. Select it only for an installation you already use with that account.',
                  ),
                ],
              ],
              const SizedBox(height: 16),
              const Text(
                'After saving, close and reopen OpenHarness. Running agents stay in their current account.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (!_loading && _distros.isEmpty)
                  TextButton(
                    onPressed: _saving ? null : _loadDistros,
                    child: const Text('Reload distributions'),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || (_loading && !_useDefault) ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save for next launch'),
        ),
      ],
    ),
  );
}
