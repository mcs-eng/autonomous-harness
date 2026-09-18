import 'dart:async';

import 'package:flutter/material.dart';
// `PlatformException` — a refused camera permission arrives as one, and it is
// the one picker failure with something the person can do about it.
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'package:harness_mobile/shared/widgets/app_icon_button.dart';
import 'package:harness_mobile/state/app_state.dart';
import 'package:harness_mobile/terminal/image_transcode.dart';
import 'package:harness_mobile/terminal/terminal_session.dart';
import 'package:harness_mobile/widgets/engine_identity.dart';
import 'package:harness_mobile/widgets/rename_agent_dialog.dart';
import 'package:harness_mobile/widgets/terminal_panel.dart';

import 'delete_agent.dart';
import 'phone_header.dart';
import 'phone_sheet.dart';
import 'phone_status.dart';
import 'status_pill.dart';
import 'terminal_key_bar.dart';

/// One agent's terminal, filling the phone. The header says whose it is and whether it is live;
/// everything below it is the same [TerminalPanel] a desktop tile draws, minus that tile's own
/// header.
///
/// A pushed page, so the tab bar is covered: the bottom of this screen belongs to the composer, and
/// a nav bar under it would put two rows of chrome in the thumb's way.
class TerminalPage extends StatefulWidget {
  const TerminalPage({
    super.key,
    required this.notifier,
    required this.machineId,
    required this.agentId,
    this.isActive = true,
  });

  final AppNotifier notifier;
  final String machineId;
  final String agentId;

  /// Whether this is the page being LOOKED AT, rather than one parked beside it in the pager.
  ///
  /// ⚠️ **Load-bearing for correctness, not just for tidiness.** [TerminalPanel] claims the keyboard
  /// whenever it is built focused — `requestKeyboard()` reopens the input connection on purpose — so
  /// two mounted pages both passing `focused: true` race for the software keyboard, and the winner
  /// can be the page off-screen. What gets typed then reaches an agent nobody is looking at.
  ///
  /// It also drives the panel's `visible`, which is what releases focus and stops the renderer and
  /// the auto-resize for a page that has slid away — three terminals all resizing themselves to the
  /// layout would send SIGWINCH to three remote shells at once.
  final bool isActive;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage>
    with WidgetsBindingObserver {
  /// Whether this page's pane ever existed.
  ///
  /// ⚠️ Load-bearing, and the reason this page is stateful at all. The page is pushed BEFORE the
  /// attach — that is what lets it say "Attaching…" — so a null pane means two opposite things
  /// depending on when it is seen: not yet (wait) or no longer (leave).
  ///
  /// Without the distinction, the second case renders as a spinner that never resolves. It is
  /// reachable in normal use now that two tabs can each open a terminal: `openAgent` keeps exactly
  /// one pane, so opening an agent from the Machines tab closes the pane belonging to a
  /// TerminalPage still sitting in the Agents tab's stack.
  bool _hadPane = false;

  /// Whether this page has already used its one chance to summon the keyboard.
  ///
  /// It starts `false`, so the terminal is focused on arrival and the keyboard
  /// rises by itself. It flips the moment the keyboard IS up, and NEVER goes
  /// back: from then on `TerminalPanel` is passed `focused: false` and stops
  /// claiming, for the life of the page. Bringing the keyboard back is the
  /// terminal's own job — xterm's tap handler calls `requestKeyboard()` without
  /// consulting this flag, so nothing here needs to re-arm.
  ///
  /// ⚠️ Without this, Back could not put the keyboard away at all:
  /// `TerminalPanel._claimFocus` calls `TerminalView.requestKeyboard()`, which
  /// RE-TAKES focus when it finds none, so the keyboard returned a frame after
  /// the system dismissed it. Measured on a Pixel 8 Pro — `onRequestShow`
  /// ELEVEN times against a single `onRequestHide`.
  ///
  /// ⚠️ It flips on the keyboard APPEARING, not on it going away, and that is
  /// the difference between Back working on the first press and on the second.
  /// `_claimFocus` runs from a post-frame callback and BEATS `didChangeMetrics`
  /// to the news that the keyboard is gone:
  ///
  ///     onDispatched            keyboard hidden
  ///     CLAIM focused=true      claim ran first — re-took focus
  ///     onRequestShow           keyboard on its way back
  ///     KB raw=0.0              our metrics callback, one beat too late
  ///
  /// Arming on the way up removes the race: by the time any Back arrives,
  /// claiming has been off for as long as the keyboard has been visible.
  bool _claimSpent = false;

  /// Whether the software keyboard is up, and with it [TerminalKeyBar].
  ///
  /// Read from [View] for the reason [didChangeMetrics] gives: MediaQuery's
  /// bottom inset is pinned at zero inside this page.
  bool _keyboardUp = false;

  /// Whether the keyboard is mid-animation, and so the pane's height is still
  /// changing frame by frame. Handed to [TerminalPanel.settling], which freezes
  /// the renderer and the auto-resize until this clears.
  bool _keyboardSettling = false;

  /// The last bottom inset seen, in physical pixels, and the timer that decides
  /// the animation has stopped.
  ///
  /// The platform gives no "keyboard animation finished" callback on either OS —
  /// only a stream of [didChangeMetrics] ticks — so the end is detected by the
  /// inset going quiet. The window is a little longer than one frame at 60Hz so
  /// a slow frame mid-animation does not read as the end of it.
  double? _lastInset;
  Timer? _settleTimer;
  static const _settleWindow = Duration(milliseconds: 80);

  /// Stops the settle watch, leaving the renderer live.
  ///
  /// ⚠️ Called from [dispose], so it must not touch [setState].
  void _cancelSettle() {
    _settleTimer?.cancel();
    _settleTimer = null;
    _lastInset = null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  /// Releases the freeze when this page is parked mid-animation.
  ///
  /// A settle that never ends would otherwise be waiting on [didChangeMetrics]
  /// ticks that only the page ON SCREEN gets, and the pane would come back from
  /// the pager with its renderer still gated.
  @override
  void didUpdateWidget(TerminalPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      _cancelSettle();
      if (_keyboardSettling) setState(() => _keyboardSettling = false);
    }
  }

  @override
  void dispose() {
    _cancelSettle();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Watches the keyboard through [View], because MediaQuery lies to this page.
  ///
  /// ⚠️ `MediaQuery.viewInsetsOf(context).bottom` is ALWAYS ZERO here, keyboard
  /// up or down. `PhoneShell` puts this page's Navigator inside a `Scaffold`
  /// body, and a Scaffold that has already resized for the keyboard STRIPS the
  /// bottom inset from the MediaQuery it hands its body — the body must not
  /// subtract it twice. Every descendant therefore reads zero.
  ///
  /// [View.of] is the raw platform value, in PHYSICAL pixels, and no widget can
  /// intercept it.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final inset = View.of(context).viewInsets.bottom;
    // The FIRST frame of the keyboard rising is enough — it need not finish.
    // Spending the claim this early is the point: it is off long before any
    // Back press can arrive.
    final up = inset > 0;
    final claim = _claimSpent || up;

    // Every tick that MOVES the inset is the animation still running; the run
    // ends when one window passes without another move. Gated on a real change
    // so the ticks this page gets for everything else — a rotation, a status
    // bar resizing — never freeze a pane whose height is not moving.
    //
    // The very first tick is deliberately not a move: `_lastInset` starts null
    // and only seeds the baseline, so arriving on this page cannot begin a
    // settle of its own.
    final previous = _lastInset;
    _lastInset = inset;
    if (previous != null && inset != previous) {
      _settleTimer?.cancel();
      _settleTimer = Timer(_settleWindow, () {
        _settleTimer = null;
        if (!mounted || !_keyboardSettling) return;
        setState(() => _keyboardSettling = false);
      });
    }

    final settling = _settleTimer != null;
    if (up == _keyboardUp &&
        claim == _claimSpent &&
        settling == _keyboardSettling) {
      return;
    }
    setState(() {
      _keyboardUp = up;
      _claimSpent = claim;
      _keyboardSettling = settling;
    });
  }

  /// Puts the keyboard away without leaving the page — the `⌄` key on
  /// [TerminalKeyBar]. Dropping focus is what closes the input connection;
  /// xterm reopens it on the next tap in the pane.
  void _dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  /// Guards against a second picker while one is already up.
  ///
  /// The key bar stays on screen under the sheet the OS puts over it, so its
  /// button remains tappable — and `pickImage` answers a second call on iOS by
  /// throwing rather than by queueing.
  bool _picking = false;

  /// Picks a picture and sends it to the agent, re-encoded on the way.
  ///
  /// ⚠️ **The transcode is not an optimisation, it is what makes the picture
  /// arrive at all** — see `transcodeToPng`. Everything past this point names
  /// PNG: the binary kind, the file the CLI writes, and the three OS clipboard
  /// writers it hands the bytes to. A phone produces JPEG and HEIC.
  Future<void> _sendImage(TerminalSession session, ImageSource source) async {
    if (_picking || !session.acceptsInput) return;
    _picking = true;
    final messenger = ScaffoldMessenger.maybeOf(context);
    void report(String message) {
      if (mounted) messenger?.showSnackBar(SnackBar(content: Text(message)));
    }

    try {
      final XFile? picked;
      try {
        picked = await ImagePicker().pickImage(source: source);
      } on PlatformException catch (error) {
        // A refused camera permission lands here rather than as a null, and it
        // is the one failure somebody can do something about.
        report(
          error.code == 'camera_access_denied'
              ? 'Allow camera access in Settings to send a photo.'
              : 'Could not open the picker.',
        );
        return;
      }
      // Null is a CANCEL, not a failure: the person backed out of the sheet, and
      // a snackbar saying so would be noise over a deliberate act.
      if (picked == null) return;

      final result = await transcodeToPng(await picked.readAsBytes());
      switch (result) {
        case ImageTranscodeUnreadable():
          report("That file isn't an image this phone can read.");
        case ImageTranscodeTooLarge():
          report('That image is too large to send, even scaled down.');
        case ImageTranscodeOk(:final pngBytes):
          // Re-checked AFTER the picker, which the person may have had open for
          // a while: the stream can have been taken over or dropped since, and
          // `pasteImage` on a dead stream goes nowhere silently.
          if (!session.acceptsInput) {
            report('The terminal is no longer accepting input.');
            return;
          }
          if (!await session.pasteImage(pngBytes)) {
            report('The image could not be sent.');
          }
      }
    } finally {
      _picking = false;
    }
  }

  /// The composer starts OPEN here, and the phone owns that answer rather than the pane.
  ///
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.notifier,
      builder: (context, _) {
        AppTheme.watch(context);
        final pane = widget.notifier.panes
            .where(
              (p) =>
                  p.machineId == widget.machineId &&
                  p.agentId == widget.agentId,
            )
            .firstOrNull;
        if (pane != null) {
          _hadPane = true;
        } else if (_hadPane && widget.isActive) {
          // The pane this page was showing is gone — another tab opened a different agent, or the
          // agent was deleted. Leave rather than spin: there is nothing here to come back.
          //
          // ⚠️ Only the ACTIVE page may leave, and only it ever should. A page parked beside the one
          // being read shares the route, so popping from there would take the whole pager down —
          // including the terminal actually on screen. A parked page whose pane went away simply
          // waits: swiping to it is what makes it attach again.
          _leave();
        }
        final session = pane?.session;
        final machine = widget.notifier.stateOf(widget.machineId);
        final agent = machine?.agents
            .where((a) => a.id == widget.agentId)
            .firstOrNull;
        final status = phoneSessionSummary(session);
        final reclaim = phoneReclaimAction(session);
        return Scaffold(
          backgroundColor: AppPalette.windowBg,
          // ⚠️ Plain `SafeArea`. A `bottom: !keyboardUp` toggle was here,
          // computed from `MediaQuery.viewInsetsOf(context).bottom > 0` — and
          // that value is pinned at ZERO inside this page (see
          // [didChangeMetrics]). The toggle therefore never toggled.
          body: SafeArea(
            child: Column(
              children: [
                PhoneHeader(
                  title: agent?.name ?? 'Agent',
                  leading: EngineMark(
                    engine: agent?.engine,
                    displayName: agent?.engineDisplayName,
                    size: 22,
                  ),
                  subtitle: StatusPill(
                    fontSize: 12,
                    summary: (
                      // The machine alone once the button beside it is saying
                      // the state: two words for one fact, in a row this
                      // narrow, is what truncated "Taken over" to "Ta…".
                      label: reclaim == null
                          ? '${machine?.machine.displayName ?? ''} · ${status.label}'
                          : machine?.machine.displayName ?? '',
                      tone: status.tone,
                    ),
                  ),
                  trailing: [
                    // Read-only is a state to get OUT of, so its way out is a
                    // labelled button in the header rather than a line in the
                    // actions sheet: the sheet is where you go having decided
                    // to do something, and this is the thing telling you that
                    // typing will go nowhere until you do.
                    if (reclaim != null)
                      _ReclaimButton(
                        action: reclaim,
                        onPressed: () => widget.notifier.selectAgent(
                          widget.machineId,
                          widget.agentId,
                        ),
                      ),
                    // Null while the agent is not loaded: there is nothing to act on yet, and a
                    // menu of actions that all fail is worse than no menu.
                    if (agent != null)
                      AppIconButton(
                        icon: LucideIcons.ellipsis300,
                        size: 20,
                        tooltip: 'Agent actions',
                        color: AppPalette.textSecondary,
                        onPressed: () => _showActions(
                          machineName: machine?.machine.displayName ?? '',
                          agentName: agent.name,
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: Column(
                    children: [
                      Divider(height: 1, color: AppGlass.hair),
                      Expanded(
                        child: pane == null || session == null
                            ? const _Attaching()
                            // ⚠️ Nothing re-arms [_claimSpent] on tap, and that
                            // is deliberate. A `Listener` doing so was written
                            // and removed: xterm's own `_onTapDown` already
                            // calls `requestKeyboard()`, so the tap opened the
                            // keyboard and THEN the re-armed claim asked for it
                            // a second time — Android answers a show arriving
                            // mid-animation by cancelling and restarting it.
                            // Measured: two `onRequestShow` and two
                            // `onCancelled at PHASE_CLIENT_APPLY_ANIMATION` per
                            // tap. The claim exists only to raise the keyboard
                            // on arrival; after that the terminal handles it.
                            : TerminalPanel(
                                key: ValueKey(pane.id),
                                notifier: widget.notifier,
                                session: session,
                                // Only the page on screen takes the keyboard — see
                                // [TerminalPage.isActive]. `visible` is the same answer for the
                                // panel's other half: a page parked beside this one releases
                                // focus, stops rendering and stops resizing its remote shell.
                                //
                                // AND only until the keyboard is actually up —
                                // see [_claimSpent]. Both gates, not either:
                                // `isActive` keeps a parked page from stealing
                                // the keyboard, `_claimSpent` keeps this one
                                // from taking it back after Back.
                                focused: widget.isActive && !_claimSpent,
                                visible: widget.isActive,
                                // Hold the renderer still while the keyboard
                                // slides. Separate from `visible` because this
                                // must NOT release focus — the animation being
                                // waited on is the one that focus started.
                                settling: _keyboardSettling,
                                showHeader: false,
                                // No composer, and so no grip above it: the
                                // page hands the pane its full height and the
                                // software keyboard drives the terminal
                                // directly — `TerminalPanel` autofocuses the
                                // view precisely when no box is covering it.
                                // What goes with the box is the batched send,
                                // and the Esc/Tab/Ctrl an on-screen keyboard
                                // never had anyway.
                              ),
                      ),
                      // The bottom of this page IS just above the keyboard:
                      // `PhoneShell`'s Scaffold has already resized for it —
                      // the same resize that empties this page's MediaQuery
                      // insets (see [didChangeMetrics]).
                      if (_keyboardUp && session != null)
                        ListenableBuilder(
                          listenable: session,
                          builder: (context, _) => TerminalKeyBar(
                            terminal: session.terminal,
                            enabled: session.acceptsInput,
                            controlArmed: session.controlArmed,
                            onControlToggle: session.armControl,
                            onDismissKeyboard: _dismissKeyboard,
                            // Only where the far side can actually take one: an
                            // older CLI never advertises the binary kind, so the
                            // upload would go nowhere silently. Null leaves the
                            // buttons undrawn rather than drawn dead.
                            onPickImage:
                                machine?.terminalImagePasteAvailable == true
                                ? () => unawaited(
                                    _sendImage(session, ImageSource.gallery),
                                  )
                                : null,
                            onTakePhoto:
                                machine?.terminalImagePasteAvailable == true
                                ? () => unawaited(
                                    _sendImage(session, ImageSource.camera),
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Pops after the frame: this runs from inside a build, where popping a route synchronously is
  /// not allowed.
  void _leave() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    });
  }

  void _showActions({required String machineName, required String agentName}) {
    showPhoneSheet(
      context,
      title: '$agentName · $machineName',
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.pencil300,
          label: 'Rename agent…',
          onTap: () => showAgentRenameDialog(
            context,
            widget.notifier,
            widget.machineId,
            widget.agentId,
            agentName,
          ),
        ),
        PhoneSheetAction(
          icon: LucideIcons.refreshCw300,
          label: 'Restart agent',
          onTap: () => unawaited(_restart()),
        ),
        // Last, and alone in red: the two above are recoverable and this one is
        // not, so it does not sit where a thumb lands on the way to them.
        //
        // ⚠️ Nothing here pops this page. Deleting detaches the pane, and the
        // `_hadPane` branch above leaves on its own when that happens — the same
        // path a delete from the list, or from the desktop, already takes. A pop
        // here would be a second one, and the parked pages in this pager share
        // the route.
        PhoneSheetAction(
          icon: LucideIcons.trash2300,
          label: 'Delete agent…',
          destructive: true,
          onTap: () => unawaited(
            confirmDeleteAgent(
              context,
              widget.notifier,
              widget.machineId,
              widget.agentId,
              agentName,
            ),
          ),
        ),
      ],
    );
  }

  /// Restarting is a round trip that can fail, and the phone has no status rail to fail into — so
  /// the answer lands as a snackbar, which is the one surface a pushed page here always has.
  Future<void> _restart() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final result = await widget.notifier.restartAgent(
      widget.machineId,
      widget.agentId,
    );
    final error = result.error;
    if (error == null || messenger == null || !mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }
}

/// The header's way back into a session this device is not driving.
///
/// Re-selecting the agent is what reclaims it — the same call the desktop tile's
/// status chip makes, so one gesture means one thing on both.
class _ReclaimButton extends StatelessWidget {
  const _ReclaimButton({required this.action, required this.onPressed});

  final PhoneSummary action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    final color = phoneToneColor(action.tone);
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        action.tone == PhoneTone.attention
            ? LucideIcons.lock300
            : LucideIcons.refreshCw300,
        size: 15,
      ),
      label: Text(
        action.label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      ),
    );
  }
}

class _Attaching extends StatelessWidget {
  const _Attaching();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppPalette.accent,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Attaching to the agent…',
          style: TextStyle(color: AppPalette.textSecondary, fontSize: 14),
        ),
      ],
    ),
  );
}
