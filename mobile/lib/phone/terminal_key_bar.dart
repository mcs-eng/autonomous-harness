import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:xterm/xterm.dart';

import 'package:harness_mobile/shared/theme/app_theme.dart';
import 'phone_sheet.dart';

/// The keys a phone keyboard does not have, in a strip above the one it does.
///
/// A pane is driven by `esc`, `tab`, the arrows and `ctrl` far more than by
/// anything the alphabet offers — interrupting Claude Code, cycling its modes,
/// walking shell history, `^C`. None of them exist on a software keyboard, so
/// until this strip a phone could type at an agent but could not DRIVE one.
///
/// It appears with the keyboard and goes away with it: the terminal is short
/// enough on a phone that two rows of chrome are worth their height only while
/// someone is actually typing.
///
/// ⚠️ **Two FIXED rows, and nothing scrolls.** A horizontal scroller was tried
/// and reverted: at a comfortable key width only four keys fit a 393pt phone, so
/// the arrows and `ctrl` — the two most-pressed things here — ended up behind a
/// swipe, and a `»` key had to exist to reach the digits. Every key being in the
/// same place every time is worth more than any of them being bigger: this strip
/// is used while looking at the TERMINAL, not at the strip.
///
/// `~ | / -` are deliberately gone from this row. The system keyboard one row
/// below types all four, which is exactly what the row above it should not spend
/// space on — unlike `↵` and `⇧tab`, which it cannot produce at all.
class TerminalKeyBar extends StatelessWidget {
  const TerminalKeyBar({
    super.key,
    required this.terminal,
    required this.enabled,
    required this.controlArmed,
    required this.onControlToggle,
    required this.onDismissKeyboard,
    this.onPickImage,
    this.onTakePhoto,
  });

  final Terminal terminal;

  /// False while the stream is not accepting input — the strip stays visible
  /// (it moves with the keyboard, and a row that vanished would take the
  /// keyboard's place with it) but dims and stops answering.
  final bool enabled;

  /// Whether the next character typed leaves as a control chord. Owned by the
  /// session, which is also what spends it — see `TerminalSession.armControl`.
  final bool controlArmed;
  final ValueChanged<bool> onControlToggle;
  final VoidCallback onDismissKeyboard;

  /// Sending a picture. Null on a pane that cannot take one — an older CLI that
  /// never advertised `terminalImagePasteAvailable` — and the key is then not
  /// drawn at all rather than drawn dead: a key that does nothing is worse than
  /// one that was never offered.
  final VoidCallback? onPickImage;
  final VoidCallback? onTakePhoto;

  bool get _canSendImage => onPickImage != null || onTakePhoto != null;

  /// The width of a key that sits OUTSIDE the grid — see `apart` in [build].
  ///
  /// Square, and stated rather than shared with the grid on purpose: the grid
  /// keys stretch to fill whatever the row leaves them, and these must not move
  /// when a digit is added or the image key is absent.
  static const double _apartKeyWidth = 34;

  void _send(void Function() action) {
    if (!enabled) return;
    HapticFeedback.selectionClick();
    action();
  }

  /// The image key: asks WHICH picture, then hands off.
  ///
  /// The sheet only appears where there is a choice to make. A build with just
  /// one of the two wired goes straight there instead — a sheet with a single
  /// row is a tap spent on nothing.
  void _sendImage(BuildContext context) {
    final pick = onPickImage;
    final photo = onTakePhoto;
    if (pick == null) {
      photo?.call();
      return;
    }
    if (photo == null) {
      pick();
      return;
    }
    showPhoneSheet(
      context,
      title: 'Send a picture to this agent',
      actions: [
        PhoneSheetAction(
          icon: LucideIcons.image300,
          label: 'Choose from library',
          onTap: pick,
        ),
        PhoneSheetAction(
          icon: LucideIcons.camera300,
          label: 'Take a photo',
          onTap: photo,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    // Row one is what drives an engine: leave a mode, complete a path, send,
    // cycle Claude Code's modes, walk history. The image key ends it because
    // sending a picture is a deliberate act, not something done mid-sentence —
    // but it is still HERE, on screen, not behind anything.
    final top = <Widget>[
      _key(label: 'esc', onTap: () => terminal.keyInput(TerminalKey.escape)),
      _key(label: 'tab', onTap: () => terminal.keyInput(TerminalKey.tab)),
      _key(
        icon: LucideIcons.cornerDownLeft300,
        semanticLabel: 'Enter',
        onTap: () => terminal.keyInput(TerminalKey.enter),
      ),
      // Shift+Tab is CSI Z, and xterm builds it from the modifier rather than
      // from a key of its own — which is why this passes `shift` instead of
      // looking for a `TerminalKey.shiftTab` that does not exist.
      _key(
        label: '⇧tab',
        onTap: () => terminal.keyInput(TerminalKey.tab, shift: true),
      ),
      _key(
        icon: LucideIcons.arrowLeft300,
        semanticLabel: 'Left',
        onTap: () => terminal.keyInput(TerminalKey.arrowLeft),
      ),
      _key(
        icon: LucideIcons.arrowUp300,
        semanticLabel: 'Up',
        onTap: () => terminal.keyInput(TerminalKey.arrowUp),
      ),
      _key(
        icon: LucideIcons.arrowDown300,
        semanticLabel: 'Down',
        onTap: () => terminal.keyInput(TerminalKey.arrowDown),
      ),
      _key(
        icon: LucideIcons.arrowRight300,
        semanticLabel: 'Right',
        onTap: () => terminal.keyInput(TerminalKey.arrowRight),
      ),
    ];
    final bottom = <Widget>[
      _key(
        label: 'ctrl',
        held: controlArmed,
        onTap: () => onControlToggle(!controlArmed),
      ),
      for (final digit in const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'])
        _key(label: digit, onTap: () => terminal.textInput(digit)),
    ];
    // ⚠️ **Neither of these sends a byte anywhere**, and that is why they sit
    // apart from the grid rather than in it. Every key to the left of the rule
    // is a keystroke the pty receives; these two act on the PHONE — one opens an
    // OS picker, the other drops the keyboard. Sharing a row taught the eye they
    // were the same kind of thing, and an image button that looks like `esc`
    // reads as something that will be typed at the agent.
    final apart = <Widget>[
      if (_canSendImage)
        _key(
          icon: LucideIcons.image300,
          semanticLabel: 'Send image',
          onTap: () => _sendImage(context),
        ),
      // The way back to a full screen of output, which on a phone is the only
      // way to read one.
      _key(
        icon: LucideIcons.chevronDown300,
        semanticLabel: 'Hide keyboard',
        alwaysEnabled: true,
        onTap: onDismissKeyboard,
      ),
    ];

    return ExcludeFocus(
      // ⚠️ Load-bearing. Every key here is a tap target inside a focus scope the
      // TERMINAL owns: a focusable one would take the focus on tap, the input
      // connection would close, and the keyboard this strip is attached to
      // would leave with it on the first `esc`.
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppPalette.panelBg,
          border: Border(top: BorderSide(color: AppGlass.hair)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          // Held out of the app-wide text scale like the composer's own type:
          // at a large scale twelve keys across a phone stop fitting the row.
          child: MediaQuery.withNoTextScaling(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The pair sits beside the SHORTER row, and the arithmetic is
                // the whole reason: row one carries eight keys and row two
                // eleven, so taking ~85pt out of row two would squeeze the
                // digits to 23pt — narrower than the system keyboard's own keys
                // right below them. Beside row one they cost it 44pt → 33pt,
                // which is where the old bar's keys already were.
                Row(
                  children: [
                    Expanded(child: _row(top)),
                    const SizedBox(width: 8),
                    // The rule earns its place only when there are two kinds of
                    // thing to separate. Against an older CLI the image key is
                    // absent and `⌄` is all that is left — it lived inside the
                    // grid before this, so a rule drawn for it alone would be
                    // marking a distinction that is no longer being made.
                    if (_canSendImage) ...[
                      Container(width: 1, height: 22, color: AppGlass.hair),
                      const SizedBox(width: 8),
                    ],
                    for (var index = 0; index < apart.length; index++) ...[
                      if (index > 0) const SizedBox(width: 4),
                      SizedBox(width: _apartKeyWidth, child: apart[index]),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                _row(bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One row, every key sharing the width equally.
  ///
  /// `Expanded` rather than a fixed width: the keys then land on the same grid
  /// the system keyboard below uses, which is what lets a thumb find one without
  /// looking. It also means a row of nine and a row of twelve both fill the
  /// phone rather than ending in a ragged gap.
  Widget _row(List<Widget> keys) => Row(
    children: [
      for (var index = 0; index < keys.length; index++) ...[
        if (index > 0) const SizedBox(width: 4),
        Expanded(child: keys[index]),
      ],
    ],
  );

  Widget _key({
    String? label,
    IconData? icon,
    String? semanticLabel,
    bool held = false,
    bool alwaysEnabled = false,
    required VoidCallback onTap,
  }) {
    assert((label == null) != (icon == null), 'a key carries one of the two');
    final live = enabled || alwaysEnabled;
    final foreground = held
        ? AppPalette.accentOnSurface
        : live
        ? AppPalette.textPrimary
        : AppPalette.textFaint;
    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      // Named so a test can reach the icon keys, which carry no text.
      key: ValueKey('terminal-key-${semanticLabel ?? label}'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: alwaysEnabled ? onTap : () => _send(onTap),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: held ? AppSurface.accentWash : AppGlass.surfaceFill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: held ? AppPalette.accentOnSurface : AppGlass.lift,
            ),
          ),
          child: icon != null
              ? Icon(icon, size: 16, color: foreground)
              : Text(
                  label!,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1,
                    color: foreground,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}
