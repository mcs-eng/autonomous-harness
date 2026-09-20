import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/companion_agents.dart';
import '../core/backend_path.dart';
import '../core/wsl_runtime.dart';

/// Vendor interfaces that run beside Harness, rather than pretending to be
/// terminal engines with transcript, routing or resume support.
Future<bool?> showCompanionAgentDialog(
  BuildContext context, {
  required String agent,
  String? initialFolder,
  bool closeOnLaunch = false,
}) => showDialog<bool>(
  context: context,
  builder: (_) => CompanionAgentDialog(
    agent: agent,
    initialFolder: initialFolder,
    closeOnLaunch: closeOnLaunch,
  ),
);

class CompanionAgentDialog extends StatefulWidget {
  const CompanionAgentDialog({
    super.key,
    required this.agent,
    this.initialFolder,
    this.companion,
    this.loadDistros,
    this.openBrowser,
    this.openZcode,
    this.closeOnLaunch = false,
  });

  final String agent;
  final String? initialFolder;
  final DeepSeekCompanion? companion;
  final Future<List<String>> Function()? loadDistros;
  final Future<bool> Function(Uri)? openBrowser;
  final Future<void> Function()? openZcode;
  final bool closeOnLaunch;

  @override
  State<CompanionAgentDialog> createState() => _CompanionAgentDialogState();
}

class _CompanionAgentDialogState extends State<CompanionAgentDialog> {
  late final _service = widget.companion ?? DeepSeekCompanion.instance;
  late final _folder = TextEditingController(
    text: _service.folder ?? widget.initialFolder ?? '',
  );
  List<String> _distros = [];
  String? _distro;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _opened = false;
  bool get _deepSeek => widget.agent == 'deepseek-web';

  @override
  void initState() {
    super.initState();
    if (_deepSeek) {
      unawaited(_loadDistros());
    } else {
      _loading = false;
    }
  }

  Future<void> _loadDistros() async {
    try {
      final available =
          await (widget.loadDistros ?? WslRuntime().usableDistros)();
      final account = _service.linuxAccount;
      final names = account == null
          ? available
          : available.where((name) => name == account.distro).toList();
      if (!mounted) return;
      setState(() {
        _distros = names;
        _distro = names.contains(_service.distro)
            ? _service.distro
            : names.firstOrNull;
        _loading = false;
        if (_service.linuxAccountError != null) {
          _distros = [];
          _distro = null;
          _error = _service.linuxAccountError;
        } else if (names.isEmpty) {
          _error = account == null
              ? 'Set up a WSL2 development distribution first.'
              : 'The selected Linux distribution is unavailable. Check the Linux account in Customize OpenHarness → Terminal.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              'Could not list WSL distributions. Check that WSL2 is available.';
        });
      }
    }
  }

  Future<void> _openBrowser() async {
    final uri = _service.launchUri;
    if (uri == null) return;
    var opened = false;
    try {
      opened =
          await (widget.openBrowser ??
              (uri) =>
                  launchUrl(uri, mode: LaunchMode.externalApplication))(uri);
    } catch (_) {
      // Platform launch failures can include the URL. Keep the token private
      // and leave the running server available for another browser attempt.
    }
    if (!opened && mounted) {
      setState(
        () => _error = 'Could not open your browser. Try Open browser again.',
      );
    }
    if (opened) _didLaunch();
  }

  void _didLaunch() {
    if (!mounted) return;
    _opened = true;
    if (widget.closeOnLaunch && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _deepSeek ? _service.status : 'Could not open ZCode. Install the official Windows desktop app first.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service,
    builder: (context, _) => AlertDialog(
      title: Text(_deepSeek ? 'DeepSeek Harness · Browser' : 'ZCode · Desktop'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _deepSeek
                    ? 'Use the official DeepSeek workspace in your browser. Sign in or configure your provider there. This is a separate workspace; Harness does not route tasks to it or read its conversations.'
                    : 'Open the official ZCode app on this PC. Choose your project and model there. ZCode runs in its own window; Harness does not manage its conversations, approvals, or task routing.',
              ),
              const SizedBox(height: 16),
              if (_deepSeek) ...[
                if (_service.linuxAccount != null)
                  Text(
                    'Linux account: ${_service.linuxAccount!.username} in ${_service.linuxAccount!.distro}',
                  ),
                if (_loading) const LinearProgressIndicator(),
                if (!_loading && _distros.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _distro,
                    decoration: const InputDecoration(
                      labelText: 'WSL distribution',
                    ),
                    items: [
                      for (final name in _distros)
                        DropdownMenuItem(value: name, child: Text(name)),
                    ],
                    onChanged: _busy || _service.running
                        ? null
                        : (value) => setState(() => _distro = value),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _folder,
                  enabled: !_busy && !_service.running,
                  decoration: const InputDecoration(
                    labelText: 'Existing project folder',
                    hintText: '/home/you/project or C:\\work\\project',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                const Text(
                  'First use: install DeepSeek in this distribution with Node 22.19+ (22.x) or Node 24+:',
                ),
                const SelectableText(deepSeekInstallCommand),
                TextButton(
                  onPressed: () => Clipboard.setData(
                    const ClipboardData(text: deepSeekInstallCommand),
                  ),
                  child: const Text('Copy install command'),
                ),
                Text(_service.status),
                if (_service.running)
                  const Text(
                    'Closing this dialog leaves the server running. Return here to reopen the browser or stop it.',
                  ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(_opened),
          child: const Text('Close'),
        ),
        if (_deepSeek && _service.running) ...[
          TextButton(
            onPressed: _busy ? null : () => _act(_service.stop),
            child: const Text('Stop server'),
          ),
          FilledButton(
            onPressed: _busy || _service.launchUri == null
                ? null
                : () => _act(_openBrowser),
            child: const Text('Open browser'),
          ),
        ] else
          FilledButton(
            onPressed:
                _busy ||
                    (_deepSeek &&
                        (_loading ||
                            _distro == null ||
                            _folder.text.trim().isEmpty))
                ? null
                : () => _act(() async {
                    if (_deepSeek) {
                      final path = BackendPath.toBackend(
                        _folder.text,
                        backendIsWsl: true,
                        distro: _distro,
                      );
                      if (path == null || !path.startsWith('/')) {
                        setState(
                          () => _error = 'Choose an absolute project folder in the selected distribution or a Windows drive.',
                        );
                        return;
                      }
                      await _service.start(distro: _distro!, folder: path);
                      await _openBrowser();
                    } else {
                      await (widget.openZcode ?? launchZcode)();
                      _didLaunch();
                    }
                  }),
            child: Text(
              _busy
                  ? 'Opening…'
                  : _deepSeek
                  ? 'Start and open browser'
                  : 'Open ZCode',
            ),
          ),
      ],
    ),
  );
}
