import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/test_run.dart';
import '../shared/theme/app_theme.dart' as grid;
import '../shared/widgets/app_dialog.dart';
import '../state/app_state.dart';
import 'link_machine_dialog.dart';
import 'link_machine_screen.dart';

/// The one-liner a server runs to get the CLI. The same script the app's own
/// first-run setup drives (`environment_provisioner.dart`), without the
/// `--desktop` half: a server has no app to set up around it.
const String kLinkServerInstallCommand =
    'curl -fsSL https://cdn.autonomous.ai/harness/cli/install.sh | bash';
const String kLinkServerLoginCommand = 'harness login';
const String kLinkServerStartCommand =
    'harness start && harness remote-password set';

/// Where the app is downloaded from, for the other computer.
final Uri kHarnessDownloadUrl = Uri.parse('https://www.autonomous.ai/harness');

/// Link another machine — reach its agents from here.
///
/// The old dialog said "on the other machine, sign in to Harness and start
/// the daemon" and printed two commands. It never said WHICH machine, HOW
/// Harness gets onto it, or that a third step — the remote password — is what
/// actually makes the link; people read it as one obscure instruction.
///
/// This one leads with the question that decides every step after it: is the
/// other machine a computer with a screen, or a server reached over SSH? Then
/// it shows the steps for that answer only — install, sign in as THIS
/// account, set a remote password — each something the person does, in order,
/// with a copy button wherever there is a command. The list at the bottom is
/// live: the moment the other machine signs in it appears, and the row itself
/// carries the last step (Enter password → [showLinkMachineScreenDialog]).
Future<void> showLinkAnotherMachineDialog(
  BuildContext context,
  AppNotifier notifier,
) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _LinkAnotherMachineDialog(notifier: notifier),
  );
}

enum _Where { computer, server }

class _LinkAnotherMachineDialog extends StatefulWidget {
  const _LinkAnotherMachineDialog({required this.notifier});

  final AppNotifier notifier;

  @override
  State<_LinkAnotherMachineDialog> createState() =>
      _LinkAnotherMachineDialogState();
}

class _LinkAnotherMachineDialogState extends State<_LinkAnotherMachineDialog> {
  AppNotifier get notifier => widget.notifier;

  _Where _where = _Where.computer;

  /// The remote machines on the list when the dialog opened. A machine not in
  /// this set is the one the person is linking right now: its arrival is what
  /// collapses the steps and puts the row in front of them.
  late final Set<String> _known = _remoteIds();

  /// Steps hidden behind "Show the steps again" once a machine has appeared.
  bool _stepsCollapsed = false;

  /// The command most recently copied, for the button to say so.
  String? _copied;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Set<String> _remoteIds() => {
    for (final state in notifier.machineStates.values)
      if (!state.isLocalMachine) state.machine.machineId,
  };

  List<MachineState> _remotes() =>
      notifier.machineStates.values.where((m) => !m.isLocalMachine).toList();

  MachineState? _arrived() {
    for (final state in _remotes()) {
      if (!_known.contains(state.machine.machineId)) return state;
    }
    return null;
  }

  Future<void> _copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {
      return; // no clipboard here; the text is on screen to select
    }
    if (!mounted) return;
    _copiedTimer?.cancel();
    setState(() => _copied = text);
    _copiedTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copied = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    grid.AppTheme.watch(context);
    return ListenableBuilder(
      listenable: notifier,
      builder: (context, _) {
        final arrived = _arrived();
        // A machine just signed in: the steps have done their job, and the
        // row that finishes the link takes their room. Only ever collapses
        // on its own — the person reopens them with the link below.
        if (arrived != null && !_stepsCollapsed && !_reopenedSteps) {
          _stepsCollapsed = true;
        }
        final remotes = _remotes();
        final email = notifier.currentUser?.email;
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link another machine',
                        style: TextStyle(
                          color: grid.AppPalette.textPrimary,
                          fontSize: 16,
                          fontWeight: grid.AppFont.semibold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _stepsCollapsed
                            ? 'Reach its agents from here, end-to-end encrypted.'
                            : 'Reach its agents from here, end-to-end encrypted. '
                                  'Where does it live?',
                        style: TextStyle(
                          color: grid.AppPalette.textFaint,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_stepsCollapsed) ...[
                          _ArrivedSummary(machine: arrived),
                        ] else ...[
                          _WhereChooser(
                            where: _where,
                            onChanged: (w) => setState(() => _where = w),
                          ),
                          const SizedBox(height: 16),
                          if (_where == _Where.computer)
                            _ComputerSteps(email: email)
                          else
                            _ServerSteps(
                              email: email,
                              copied: _copied,
                              onCopy: _copy,
                            ),
                        ],
                        const SizedBox(height: 16),
                        if (remotes.isEmpty)
                          const _WaitingStrip()
                        else
                          _MachineList(
                            machines: remotes,
                            arrivedId: arrived?.machine.machineId,
                            onEnterPassword: (id) =>
                                showLinkMachineScreenDialog(
                                  context,
                                  notifier,
                                  id,
                                ),
                          ),
                        if (_stepsCollapsed) ...[
                          const SizedBox(height: 12),
                          _NotSeeingIt(
                            email: email,
                            onShowSteps: () => setState(() {
                              _stepsCollapsed = false;
                              _reopenedSteps = true;
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                _Footer(
                  linked: remotes.where((m) => !m.needsLink).length,
                  showCopyAll: !_stepsCollapsed && _where == _Where.server,
                  copiedAll: _copied == _allServerCommands,
                  onCopyAll: () => _copy(_allServerCommands),
                  onRefresh: _stepsCollapsed ? notifier.refreshMachines : null,
                  onThisMachine: () =>
                      unawaited(showLinkMachineDialog(context, notifier)),
                  onClose: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Once the person asked for the steps back, an arrival must not fold them
  /// away again under their eyes.
  bool _reopenedSteps = false;

  static const String _allServerCommands =
      '$kLinkServerInstallCommand\n$kLinkServerLoginCommand\n$kLinkServerStartCommand';
}

// ── the fork ────────────────────────────────────────────────────────────────

class _WhereChooser extends StatelessWidget {
  const _WhereChooser({required this.where, required this.onChanged});

  final _Where where;
  final ValueChanged<_Where> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _WhereCard(
            icon: LucideIcons.monitor300,
            title: 'A computer with a screen',
            detail: 'Mac or Linux desktop. Install the OpenHarness app there.',
            selected: where == _Where.computer,
            onTap: () => onChanged(_Where.computer),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _WhereCard(
            icon: LucideIcons.server300,
            title: 'A server over SSH',
            detail: 'Headless box. Install the CLI with one command.',
            selected: where == _Where.server,
            onTap: () => onChanged(_Where.server),
          ),
        ),
      ],
    );
  }
}

class _WhereCard extends StatelessWidget {
  const _WhereCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = grid.AppPalette.accentOnSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.08)
                : grid.AppCard.inset,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : grid.AppPalette.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.16)
                      : grid.AppSurface.recess,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 16,
                  color: selected ? accent : grid.AppPalette.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: grid.AppPalette.textPrimary,
                        fontSize: 13,
                        fontWeight: grid.AppFont.semibold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        color: grid.AppPalette.textFaint,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── the steps ───────────────────────────────────────────────────────────────

class _ComputerSteps extends StatelessWidget {
  const _ComputerSteps({required this.email});

  final String? email;

  @override
  Widget build(BuildContext context) {
    final who = email ?? 'the same account';
    return Column(
      children: [
        _Step(
          number: 1,
          title: 'Install OpenHarness on that computer',
          detail: TextSpan(
            children: [
              const TextSpan(text: 'Download from '),
              _linkSpan(context, 'autonomous.ai/harness', kHarnessDownloadUrl),
              const TextSpan(text: ' — macOS and Linux.'),
            ],
          ),
        ),
        _Step(
          number: 2,
          title: 'Sign in with the same account',
          detail: TextSpan(
            children: [
              const TextSpan(text: 'You are '),
              _strongSpan(who),
              const TextSpan(
                text:
                    ' here. The other computer must sign in as the same '
                    'person — that is what puts it on your list.',
              ),
            ],
          ),
        ),
        _Step(
          number: 3,
          title: 'Set a remote password there',
          detail: TextSpan(
            children: [
              const TextSpan(
                text: 'In that app: account menu (bottom of the rail) → ',
              ),
              _strongSpan('Remote into another machine…'),
              const TextSpan(text: ' → '),
              _strongSpan('Set password'),
              const TextSpan(
                text:
                    '. You will type it here, once, when the machine appears '
                    'below.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerSteps extends StatelessWidget {
  const _ServerSteps({
    required this.email,
    required this.copied,
    required this.onCopy,
  });

  final String? email;
  final String? copied;
  final ValueChanged<String> onCopy;

  @override
  Widget build(BuildContext context) {
    final who = email ?? 'the same account';
    return Column(
      children: [
        _Step(
          number: 1,
          title: 'Install the Harness CLI',
          detail: TextSpan(
            children: [
              const TextSpan(
                text: 'Run this on the server. Installs Node, tmux and ',
              ),
              _codeSpan('harness'),
              const TextSpan(text: ' under '),
              _codeSpan('~/.harness'),
              const TextSpan(text: '; nothing system-wide.'),
            ],
          ),
          command: kLinkServerInstallCommand,
          copied: copied == kLinkServerInstallCommand,
          onCopy: () => onCopy(kLinkServerInstallCommand),
        ),
        _Step(
          number: 2,
          title: 'Sign in as $who',
          detail: TextSpan(
            children: [
              const TextSpan(text: 'Prints a link — open it in a browser on '),
              _strongSpan('any'),
              const TextSpan(
                text: ' device, sign in, and the server picks it up.',
              ),
            ],
          ),
          command: kLinkServerLoginCommand,
          copied: copied == kLinkServerLoginCommand,
          onCopy: () => onCopy(kLinkServerLoginCommand),
        ),
        _Step(
          number: 3,
          title: 'Start it, and set a remote password',
          detail: const TextSpan(
            text:
                'The password is what this computer will type, once, to open '
                'the encrypted link. Choose any; it stays on the server.',
          ),
          command: kLinkServerStartCommand,
          copied: copied == kLinkServerStartCommand,
          onCopy: () => onCopy(kLinkServerStartCommand),
        ),
      ],
    );
  }
}

TextSpan _strongSpan(String text) => TextSpan(
  text: text,
  style: TextStyle(
    color: grid.AppPalette.textSecondary,
    fontWeight: grid.AppFont.medium,
  ),
);

TextSpan _codeSpan(String text) => TextSpan(
  text: text,
  style: TextStyle(
    fontFamily: grid.AppFont.mono,
    fontFamilyFallback: grid.AppFont.monoFallback,
    fontSize: 11.5,
    color: grid.AppPalette.textSecondary,
  ),
);

TextSpan _linkSpan(BuildContext context, String text, Uri url) => TextSpan(
  text: text,
  style: TextStyle(
    color: grid.AppPalette.accentOnSurface,
    decoration: TextDecoration.underline,
    decorationColor: grid.AppPalette.accentOnSurface.withValues(alpha: 0.4),
  ),
  recognizer: TapGestureRecognizer()
    ..onTap = () =>
        unawaited(launchUrl(url, mode: LaunchMode.externalApplication)),
);

/// One numbered step: a title, a line under it, and — for a server — the
/// command with its own copy button.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.detail,
    this.command,
    this.copied = false,
    this.onCopy,
    this.done = false,
  });

  final int number;
  final String title;
  final InlineSpan detail;
  final String? command;
  final bool copied;
  final VoidCallback? onCopy;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(0, number == 1 ? 2 : 10, 0, 10),
      decoration: number == 1
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: grid.AppCard.insetHair)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepNumber(number: number, done: done),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: grid.AppPalette.textPrimary,
                    fontSize: 13,
                    fontWeight: grid.AppFont.medium,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  detail,
                  style: TextStyle(
                    color: grid.AppPalette.textFaint,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                if (command != null) ...[
                  const SizedBox(height: 8),
                  _CommandLine(
                    command: command!,
                    copied: copied,
                    onCopy: onCopy,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.number, required this.done});

  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final ok = grid.AppPalette.online;
    return Container(
      width: 22,
      height: 22,
      margin: const EdgeInsets.only(top: 1),
      decoration: BoxDecoration(
        color: done ? ok.withValues(alpha: 0.15) : grid.AppSurface.recess,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: done
          ? Icon(LucideIcons.check300, size: 13, color: ok)
          : Text(
              '$number',
              style: TextStyle(
                color: grid.AppPalette.textSecondary,
                fontSize: 11.5,
                fontWeight: grid.AppFont.semibold,
              ),
            ),
    );
  }
}

/// A command the person copies. The whole line is selectable too, for the
/// person who would rather drag than click.
class _CommandLine extends StatelessWidget {
  const _CommandLine({
    required this.command,
    required this.copied,
    required this.onCopy,
  });

  final String command;
  final bool copied;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: grid.AppCard.inset,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: grid.AppCard.insetHair),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: r'$ ',
                    style: TextStyle(color: grid.AppPalette.textFaint),
                  ),
                  TextSpan(text: command),
                ],
              ),
              style: TextStyle(
                fontFamily: grid.AppFont.mono,
                fontFamilyFallback: grid.AppFont.monoFallback,
                fontSize: 12,
                height: 1.5,
                color: grid.AppPalette.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(
            label: copied ? 'Copied' : 'Copy',
            icon: copied ? LucideIcons.check300 : LucideIcons.copy300,
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}

// ── the list ────────────────────────────────────────────────────────────────

class _WaitingStrip extends StatelessWidget {
  const _WaitingStrip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: grid.AppPalette.divider),
      ),
      child: Row(
        children: [
          // Still under test: a spinner that never stops is a pumpAndSettle
          // that never settles, the same reason the install panel's clock
          // holds still there.
          SizedBox(
            width: 14,
            height: 14,
            child: kUnderTest
                ? DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: grid.AppPalette.accentOnSurface,
                        width: 2,
                      ),
                    ),
                  )
                : CircularProgressIndicator(
                    strokeWidth: 2,
                    color: grid.AppPalette.accentOnSurface,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Waiting for a new machine to sign in… it appears here on its own.',
              style: TextStyle(
                color: grid.AppPalette.textFaint,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrivedSummary extends StatelessWidget {
  const _ArrivedSummary({required this.machine});

  final MachineState? machine;

  @override
  Widget build(BuildContext context) {
    final name = machine?.machine.displayName ?? 'A machine';
    return _Step(
      number: 1,
      done: true,
      title: '$name signed in just now',
      detail: const TextSpan(
        text:
            'Set a remote password on it if you have not, then enter it here.',
      ),
    );
  }
}

class _MachineList extends StatelessWidget {
  const _MachineList({
    required this.machines,
    required this.arrivedId,
    required this.onEnterPassword,
  });

  final List<MachineState> machines;
  final String? arrivedId;
  final ValueChanged<String> onEnterPassword;

  @override
  Widget build(BuildContext context) {
    // The one just linked first, then unlinked, then the rest as listed.
    final rows = [...machines]
      ..sort((a, b) {
        int rank(MachineState m) => m.machine.machineId == arrivedId
            ? 0
            : m.needsLink
            ? 1
            : 2;
        return rank(a).compareTo(rank(b));
      });
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: grid.AppCard.insetHair),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++)
              _MachineRow(
                machine: rows[i],
                first: i == 0,
                onEnterPassword: () =>
                    onEnterPassword(rows[i].machine.machineId),
              ),
          ],
        ),
      ),
    );
  }
}

class _MachineRow extends StatelessWidget {
  const _MachineRow({
    required this.machine,
    required this.first,
    required this.onEnterPassword,
  });

  final MachineState machine;
  final bool first;
  final VoidCallback onEnterPassword;

  @override
  Widget build(BuildContext context) {
    final online = machine.nodeOnline;
    final presence = online == true
        ? 'Online'
        : online == false
        ? 'Offline'
        : 'Connecting…';
    final needsLink = machine.needsLink;
    // The row is the target as well as the button: the old list opened the
    // password screen from a tap on the name, and hands still go there.
    return InkWell(
      key: ValueKey('link-row-${machine.machine.machineId}'),
      onTap: needsLink ? onEnterPassword : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: grid.AppCard.inset,
          border: first
              ? null
              : Border(top: BorderSide(color: grid.AppCard.insetHair)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: grid.AppSurface.recess,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Icon(
                LucideIcons.server300,
                size: 15,
                color: grid.AppPalette.textSecondary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    machine.machine.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: grid.AppPalette.textPrimary,
                      fontSize: 13,
                      fontWeight: grid.AppFont.medium,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: online == true
                              ? grid.AppPalette.online
                              : grid.AppPalette.textFaint,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '$presence · '),
                              TextSpan(
                                text: needsLink ? 'Not linked yet' : 'Linked',
                                style: TextStyle(
                                  color: needsLink
                                      ? grid.AppPalette.warn
                                      : grid.AppPalette.online,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: grid.AppPalette.textFaint,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (needsLink) ...[
              const SizedBox(width: 12),
              FilledButton(
                key: ValueKey('link-enter-${machine.machine.machineId}'),
                onPressed: onEnterPassword,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11.5),
                ),
                child: const Text('Enter password'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotSeeingIt extends StatelessWidget {
  const _NotSeeingIt({required this.email, required this.onShowSteps});

  final String? email;
  final VoidCallback onShowSteps;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Not seeing it? It signs in as '),
          _strongSpan(email ?? 'the same account'),
          const TextSpan(text: ' and needs '),
          _codeSpan('harness start'),
          const TextSpan(text: ' running. '),
          TextSpan(
            text: 'Show the steps again',
            style: TextStyle(
              color: grid.AppPalette.accentOnSurface,
              decoration: TextDecoration.underline,
              decorationColor: grid.AppPalette.accentOnSurface.withValues(
                alpha: 0.4,
              ),
            ),
            recognizer: TapGestureRecognizer()..onTap = onShowSteps,
          ),
        ],
      ),
      style: TextStyle(
        color: grid.AppPalette.textFaint,
        fontSize: 12,
        height: 1.45,
      ),
    );
  }
}

// ── the footer ──────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.linked,
    required this.showCopyAll,
    required this.copiedAll,
    required this.onCopyAll,
    required this.onRefresh,
    required this.onThisMachine,
    required this.onClose,
  });

  final int linked;
  final bool showCopyAll;
  final bool copiedAll;
  final VoidCallback onCopyAll;
  final VoidCallback? onRefresh;
  final VoidCallback onThisMachine;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: grid.AppCard.insetHair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: showCopyAll
                  ? _SmallButton(
                      label: copiedAll
                          ? 'Copied all three'
                          : 'Copy all three commands',
                      icon: copiedAll
                          ? LucideIcons.check300
                          : LucideIcons.copy300,
                      tinted: true,
                      onPressed: onCopyAll,
                    )
                  : onRefresh != null
                  ? TextButton(
                      onPressed: onRefresh,
                      child: const Text('Refresh'),
                    )
                  : linked > 0
                  ? Text(
                      '$linked machine${linked == 1 ? '' : 's'} already linked',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: grid.AppPalette.textFaint,
                        fontSize: 11.5,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onThisMachine,
            style: TextButton.styleFrom(
              foregroundColor: grid.AppPalette.textSecondary,
            ),
            child: const Text('This computer’s password'),
          ),
          const SizedBox(width: 4),
          OutlinedButton(onPressed: onClose, child: const Text('Close')),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.tinted = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final accent = grid.AppPalette.accentOnSurface;
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 11.5),
        foregroundColor: tinted ? accent : grid.AppPalette.textPrimary,
        backgroundColor: tinted ? accent.withValues(alpha: 0.14) : null,
        side: BorderSide(
          color: tinted ? Colors.transparent : grid.AppPalette.divider,
        ),
      ),
      icon: Icon(icon, size: 13),
      label: Text(label),
    );
  }
}
