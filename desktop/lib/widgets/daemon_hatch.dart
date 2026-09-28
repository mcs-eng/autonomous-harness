import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart' show TerminalTheme;

import '../daemons/daemon_lines.dart';
import '../daemons/daemon_plate_client.dart';
import '../daemons/individuals.dart';
import '../daemons/plates.dart';
import '../daemons/render.dart';
import '../daemons/roster.dart';
import '../daemons/zoo.dart';
import '../shared/theme/app_theme.dart';
import '../terminal/terminal_text.dart';
import '../terminal/terminal_theme_store.dart';
import 'box_chrome.dart';
import 'daemon_consent.dart';
import 'daemon_portrait.dart';
import 'daemon_slot.dart';

/// Where the reveal is. Exposed so render checks can draw any moment of it.
enum HatchStage {
  /// The ready egg (`p4`), its eyes peeking, while harnessd answers: nothing
  /// is known yet.
  egg,

  /// Two big rocks (`rock`).
  rock,

  /// The top lifts and light pours out, in the rarity's light (`burst`). A
  /// secret's stage goes black and its shell dims: only the violet light.
  burst,

  /// The top breaks in two, the halves land either side (`tumble`).
  tumble,

  /// The bottom half (`open`).
  open,

  /// The hatchling rises out of the bottom half a row at a time, as `#` in
  /// the faint colour.
  rise,

  /// A secret: "It is pitch black."
  pitch,

  /// Risen, still as `#`: it holds a moment.
  silhouette,

  /// It fills with its colour (an individual's own colour family) and
  /// blinks.
  colour,
  banner,
  card,

  /// The card, and the question: what to call it (optional; `zoo.nickname`).
  name,

  /// A server from before individuals drew a species you own: no reveal of
  /// a new name. It merged into yours: `+150 xp`.
  merged,

  /// ... and yours grew a level: its portrait morphs to the new version in
  /// three frames, then holds, with the version's changelog line.
  grew,
  failed,

  /// After the first hatch, before anything is watched: what the daemon sees,
  /// "Let it watch" or "Not now" (`zoo.consent`).
  consent,

  /// Only after a yes, its own step: "Let it suggest answers?"
  suggest,
}

/// The status slot's egg line for a moment of the reveal (`rules.eggLine`).
String? hatchSlotStage(HatchStage stage) => switch (stage) {
  HatchStage.egg => 'p4',
  HatchStage.rock => 'rock',
  HatchStage.burst || HatchStage.pitch => 'burst',
  HatchStage.tumble => 'tumble',
  HatchStage.open => 'open',
  HatchStage.rise ||
  HatchStage.silhouette ||
  HatchStage.colour ||
  HatchStage.banner => 'hatchling',
  _ => null,
};

/// How wide the reveal floats, in terminal cells: a plate at the reveal size
/// (56 columns) and the stage's padding either side.
const daemonRevealCells = 60;

/// Ordered dithering (Bayer 4x4): which cells of a morph have turned by each
/// quarter. Crisp in a terminal, the same every time.
const _bayer = [
  [0, 8, 2, 10],
  [12, 4, 14, 6],
  [3, 11, 1, 9],
  [15, 7, 13, 5],
];

/// Frame [step] of [steps] of a portrait turning from [from] into [to]: both
/// bottom-aligned and centred on one canvas. Of the cells that differ, a
/// share turns at each step, in ordered-dither order (so every frame shows
/// progress, spread evenly). Step 0 is [from], step [steps] is [to], on the
/// same canvas, so the held frame never jumps.
List<String> morphPortrait(
  List<String> from,
  List<String> to,
  int step, {
  int steps = 4,
}) {
  final rows = max(from.length, to.length);
  final cols = [...from, ...to].fold<int>(0, (w, r) => max(w, r.length));
  List<List<int>> fit(List<String> art) {
    final top = rows - art.length;
    final width = art.fold<int>(0, (w, r) => max(w, r.length));
    final left = (cols - width) ~/ 2;
    return [
      for (var r = 0; r < rows; r++)
        (r < top ? ' ' * cols : (' ' * left + art[r - top]).padRight(cols))
            .codeUnits
            .toList(),
    ];
  }

  final a = fit(from), b = fit(to);
  final differ =
      [
        for (var r = 0; r < rows; r++)
          for (var c = 0; c < cols; c++)
            if (a[r][c] != b[r][c]) (r, c),
      ]..sort((x, y) {
        final bx = _bayer[x.$1 % 4][x.$2 % 4], by = _bayer[y.$1 % 4][y.$2 % 4];
        return bx != by ? bx - by : (x.$1 * cols + x.$2) - (y.$1 * cols + y.$2);
      });
  final turned = (differ.length * step.clamp(0, steps) / steps).round();
  for (final (r, c) in differ.take(turned)) {
    a[r][c] = b[r][c];
  }
  return [for (final row in a) String.fromCharCodes(row).trimRight()];
}

/// A still of the reveal, for review captures and Reduce Motion.
@immutable
class HatchFrame {
  const HatchFrame({
    required this.stage,
    this.frame = 0,
    this.risen,
    this.bannerRows = 0,
    this.morph,
  });
  final HatchStage stage;

  /// The egg stage's frame (`p4`, `rock`, `burst`, `tumble`).
  final int frame;

  /// On `rise`: how many rows of the hatchling are out (null: all of them).
  final int? risen;
  final int bannerRows;

  /// On `grew`: the morph's frame (1–3), or null for the new version held.
  final int? morph;
}

/// The hatch reveal (`daemons/README.md`, "Eggs": "Opening", and
/// "Hatching"): the ready egg's eyes peek (and keep peeking while harnessd
/// answers), it rocks twice, bursts in its rarity's light (a secret's stage
/// goes black and its shell dims, only the violet light showing), the top
/// tumbles off, and the hatchling rises out of the bottom half a row at a
/// time as `#` in the faint colour, holds 850 ms, fills with its colour (an
/// individual's own colour family, or its own plate once harnessd has drawn
/// it) and blinks; its name types in as a banner; the rarity stamp, its
/// flags and `1 in N`, its first words and the card follow, and then it asks
/// for a name (optional). The card copies as a fenced code block. Reduce
/// Motion goes straight to the card. From the fourth hatch on, any key
/// skips to the card.
///
/// It floats beside the status slot, takes keyboard focus while it is open,
/// and Escape dismisses it at any point. [onRevealed] runs once, when the
/// daemon may be named elsewhere (the card is up, or the reveal was closed).
/// [onStage] hears each moment, for the status slot's egg line.
class DaemonHatchReveal extends StatefulWidget {
  const DaemonHatchReveal({
    super.key,
    required this.roster,
    required this.egg,
    required this.result,
    required this.zoo,
    required this.onClose,
    this.onRevealed,
    this.reduceMotion = false,
    this.skippable = false,
    this.still,
    this.before,
    this.needsConsent = false,
    this.onConsent,
    this.onSuggest,
    this.plates,
    this.onName,
    this.onStage,
  });

  final DaemonRoster roster;
  final ZooEgg egg;
  final Future<ZooHatch?> result;

  /// The zoo as it is now; the hatchling's date comes from it.
  final Zoo Function() zoo;
  final VoidCallback onClose;
  final VoidCallback? onRevealed;
  final bool reduceMotion;

  /// After the person's third hatch, any key skips to the card.
  final bool skippable;

  /// Draw one fixed moment instead of running (render checks only).
  final HatchFrame? still;

  /// The zoo before this hatch: a merged duplicate's level-up is told
  /// against it.
  final Zoo? before;

  /// Nobody has answered the first-day consent: after the card, `[ next ]`
  /// shows what the daemon sees and asks. [onConsent] hears the answer;
  /// [onSuggest], a yes to the second step.
  final bool needsConsent;
  final ValueChanged<bool>? onConsent;
  final VoidCallback? onSuggest;

  /// The individual's own plates, from the harness process.
  final DaemonPlateClient? plates;

  /// Name the new individual (`zoo.nickname { uid, name }`): false for a
  /// name the rules refuse. Without it, nothing asks for a name.
  final bool Function(String uid, String name)? onName;

  /// Each moment of the reveal, as the status slot shows it: an egg line's
  /// stage, and at `hatchling` the hatchling's 0.1 sprite.
  final void Function(String stage, {String? sprite})? onStage;

  @override
  State<DaemonHatchReveal> createState() => _DaemonHatchRevealState();
}

class _DaemonHatchRevealState extends State<DaemonHatchReveal> {
  /// How long the risen silhouette holds before it fills with colour.
  static const silhouetteFor = 850;

  /// Each row of the rise.
  static const riseRow = 55;

  /// How deep the hatchling stands in the bottom half once it is out.
  static const sunk = 2;

  /// Each of the morph's three frames.
  static const morphFrame = 160;

  final _focus = FocusNode(debugLabel: 'Hatch reveal');
  final _copyFocus = FocusNode(debugLabel: 'Copy card');
  final _nextFocus = FocusNode(debugLabel: 'Hatch next');
  final _nameFocus = FocusNode(debugLabel: 'Hatchling name');
  final _name = TextEditingController();
  String? _nameError;
  HatchStage _stage = HatchStage.egg;
  int _frame = 0;
  int? _risen;
  int _loopTick = 0;
  Timer? _loopTimer;
  String? _lid;
  int _bannerRows = 0;
  int? _morph;
  ZooHatch? _hatch;
  bool _closed = false, _revealed = false, _skip = false;
  Timer? _waitTimer;
  Completer<void>? _waitDone;
  String? _copyNote;

  /// The hatchling's reveal plate, chosen once as it starts to rise (its own
  /// when harnessd has drawn it by then), so nothing jumps.
  _Hatchling? _hatchling;

  DaemonRoster get roster => widget.roster;
  DaemonDef? get _def => roster.byId(_hatch?.daemonId);
  bool get _alive => !_closed && mounted;
  String get _kind => widget.egg.kind;

  /// The light the egg opens in: its hatchling's rarity, from the burst on.
  String get _light {
    final rarity = _def?.rarity;
    final opened = switch (_stage) {
      HatchStage.egg || HatchStage.rock || HatchStage.failed => false,
      _ => true,
    };
    if (!opened || rarity == null) return 'plain';
    return roster.rules.plate?.light.containsKey(rarity) == true
        ? rarity
        : 'common';
  }

  /// A secret's stage is black from the burst on, its shell dimmed; the
  /// grue's is black too.
  bool get _pitch =>
      (_def?.secret == true || _def?.darkOnly == true) &&
      _stage != HatchStage.failed &&
      _stage != HatchStage.egg &&
      _stage != HatchStage.rock;

  bool get _dim => _pitch && _def?.secret == true;

  @override
  void initState() {
    super.initState();
    if (widget.still case final still?) {
      _stage = still.stage;
      _frame = still.frame;
      _risen = still.risen;
      _bannerRows = still.bannerRows;
      _morph = still.morph;
      unawaited(
        widget.result.then((hatch) {
          if (mounted) {
            setState(() {
              _hatch = hatch;
              _hatchling = _pickHatchling();
            });
          }
        }),
      );
      return;
    }
    unawaited(_run());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _closed = true;
    _waitTimer?.cancel();
    _loopTimer?.cancel();
    if (_waitDone case final done? when !done.isCompleted) done.complete();
    _focus.dispose();
    _copyFocus.dispose();
    _nextFocus.dispose();
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<bool> _wait(int ms) async {
    if (widget.reduceMotion || _skip) return _alive;
    final done = Completer<void>();
    _waitDone = done;
    _waitTimer = Timer(Duration(milliseconds: ms), () {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
    _waitTimer = null;
    _waitDone = null;
    return _alive;
  }

  void _show(VoidCallback change) {
    if (!_alive) return;
    final was = _stage;
    setState(change);
    if (_stage != was) _tellSlot();
  }

  /// The status slot follows the reveal.
  void _tellSlot() {
    final stage = hatchSlotStage(_stage);
    if (stage == null) return;
    final sprite = stage == 'hatchling' ? _hatchlingSprite : null;
    // The first stage is set in initState, while the parent's overlay builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStage?.call(stage, sprite: sprite);
    });
  }

  /// The hatchling's 0.1 sprite, as an individual shows it (its extra).
  String? get _hatchlingSprite {
    final hatch = _hatch;
    if (hatch == null || roster.byId(hatch.daemonId) == null) return null;
    return renderIndividualSprite(
      roster,
      hatch.daemonId,
      rollTraits(roster, hatch.daemonId, hatch.seed),
      0,
      DaemonMood.idle,
      motion: false,
    );
  }

  /// Any key after the third hatch: straight to the card.
  void _skipToCard() {
    if (_skip || !widget.skippable) return;
    _skip = true;
    _waitTimer?.cancel();
    if (_waitDone case final done? when !done.isCompleted) done.complete();
  }

  List<PlateFrame> _eggFrames(String stage) =>
      daemonPlates.egg(_kind, PlateSize.reveal, stage);

  /// Step through an egg stage's frames: [first] ms for the first, [each]
  /// for the rest, [times] through.
  Future<bool> _play(
    HatchStage stage,
    String name, {
    required int each,
    int? first,
    int times = 1,
  }) async {
    final frames = _eggFrames(name).length;
    for (var round = 0; round < times; round++) {
      for (var i = 0; i < max(1, frames); i++) {
        _show(() {
          _stage = stage;
          _frame = i;
        });
        if (!await _wait(i == 0 && round == 0 ? first ?? each : each)) {
          return false;
        }
      }
    }
    return true;
  }

  Future<void> _run() async {
    _tellSlot();
    var answered = false;
    unawaited(
      widget.result.then(
        (_) => answered = true,
        onError: (_) => answered = true,
      ),
    );
    final ms = roster.rules.plate?.eggMs;
    // The ready egg peeks through its loop, and keeps at it while harnessd
    // answers.
    var loops = 0;
    while (!widget.reduceMotion && !_skip && (loops < 1 || !answered)) {
      if (!await _play(HatchStage.egg, 'p4', each: ms?.loop ?? 190)) return;
      loops++;
      if (loops > 40) break;
    }
    ZooHatch? hatch;
    try {
      hatch = await widget.result;
    } catch (_) {
      hatch = null;
    }
    if (!_alive) return;
    if (hatch == null || roster.byId(hatch.daemonId) == null) {
      _show(() => _stage = HatchStage.failed);
      return;
    }
    _hatch = hatch;
    final def = _def!;
    // Its own plates are drawn on this computer as it hatches: ask now.
    final owned = _owned;
    if (owned != null && !hatch.duplicate) widget.plates?.prefetch(owned);
    final grew = hatch.duplicate && _grew != null;
    if (!widget.reduceMotion && !_skip) {
      if (!await _play(
        HatchStage.rock,
        'rock',
        each: ms?.rock ?? 65,
        times: 2,
      )) {
        return;
      }
      if (!await _play(
        HatchStage.burst,
        'burst',
        first: ms?.burstHold ?? 420,
        each: ms?.burst ?? 150,
      )) {
        return;
      }
      if (!await _play(HatchStage.tumble, 'tumble', each: ms?.tumble ?? 75)) {
        return;
      }
      if (!await _play(HatchStage.open, 'open', each: ms?.open ?? 380)) {
        return;
      }
      if (def.darkOnly && !_skip && !hatch.duplicate) {
        _show(() => _stage = HatchStage.pitch);
        if (!await _wait(1600)) return;
      }
    }
    if (hatch.duplicate) {
      // A server from before individuals merged it into yours.
      _show(() => _stage = HatchStage.merged);
      _markRevealed();
      if (grew) {
        if (!await _wait(1400)) return;
        for (
          var step = 1;
          step <= 3 && !widget.reduceMotion && !_skip;
          step++
        ) {
          _show(() {
            _stage = HatchStage.grew;
            _morph = step;
          });
          if (!await _wait(morphFrame)) return;
        }
        _show(() {
          _stage = HatchStage.grew;
          _morph = null;
        });
      }
      _focusNext();
      return;
    }
    _hatchling = _pickHatchling();
    if (!widget.reduceMotion && !_skip) {
      final rows = _hatchling?.rows.length ?? 0;
      for (var risen = 1; risen <= rows && !_skip; risen++) {
        _show(() {
          _stage = HatchStage.rise;
          _risen = risen;
        });
        if (!await _wait(riseRow)) return;
      }
      _show(() {
        _stage = HatchStage.silhouette;
        _risen = null;
      });
      if (!await _wait(silhouetteFor)) return;
      _show(() => _stage = HatchStage.colour);
      _startLoop();
      if (!await _wait(320)) return;
      _show(() => _lid = def.lid ?? '-');
      if (!await _wait(120)) return;
      _show(() => _lid = null);
      if (!await _wait(220)) return;
      final rows2 = bannerRows(def.id).length;
      for (var row = 1; row <= rows2 && !_skip; row++) {
        _show(() {
          _stage = HatchStage.banner;
          _bannerRows = row;
        });
        if (!await _wait(90)) return;
      }
    }
    _loopTimer?.cancel();
    _loopTimer = null;
    final naming = widget.onName != null && _owned != null;
    _show(() {
      _stage = naming ? HatchStage.name : HatchStage.card;
      _lid = null;
      _risen = null;
      _bannerRows = bannerRows(def.id).length;
    });
    _markRevealed();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focus.hasFocus) return;
      if (naming) {
        _nameFocus.requestFocus();
      } else {
        (widget.needsConsent ? _nextFocus : _copyFocus).requestFocus();
      }
    });
  }

  /// The hatchling's idle loop steps while it stands in the shell, before
  /// the card, unless nothing may move.
  void _startLoop() {
    final h = _hatchling;
    if (widget.reduceMotion || h == null || h.frames.length < 2) return;
    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(Duration(milliseconds: h.frameMs), (_) {
      if (!_alive) return;
      setState(() => _loopTick++);
    });
  }

  /// The plate the hatchling rises as: its own reveal plate when harnessd
  /// has drawn it, else its species' painted in its colour family; line art
  /// for a daemon without a plate.
  _Hatchling? _pickHatchling() {
    final hatch = _hatch, def = _def;
    if (hatch == null || def == null) return null;
    final version = roster.rules.versions.first;
    final traits = rollTraits(roster, def.id, hatch.seed);
    if (!def.plate) {
      final rows = renderPortrait(
        roster,
        def,
        version,
        DaemonMood.idle,
        motion: false,
      );
      return _Hatchling(
        [
          PlateFrame(rows, [for (final r in rows) '.' * r.length]),
        ],
        170,
        traits,
      );
    }
    final owned = _owned;
    final art = owned == null
        ? null
        : widget.plates?.art(owned, PlateSize.reveal, version, DaemonMood.idle);
    if (art != null && art.frames.isNotEmpty) {
      return _Hatchling(art.frames, art.frameMs, traits);
    }
    final loop = daemonPlates.loop(
      def.id,
      PlateSize.reveal,
      version,
      DaemonMood.idle,
    );
    if (loop.isEmpty) return null;
    return _Hatchling(
      [
        for (final rows in loop)
          PlateFrame(rows, [for (final r in rows) '.' * r.length]),
      ],
      daemonPlates.frameMs,
      traits,
    );
  }

  /// With consent to ask, `[ next ]` takes the keyboard once it shows.
  void _focusNext() {
    if (!widget.needsConsent) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focus.hasFocus) _nextFocus.requestFocus();
    });
  }

  /// After the card (or a merge): what the daemon sees, and the question.
  void _toConsent() => _show(() => _stage = HatchStage.consent);

  /// The name typed at the hatch: saved when the rules take it; empty skips.
  void _saveName() {
    final uid = _owned?.uid;
    final text = _name.text.trim();
    if (uid != null && text.isNotEmpty) {
      final ok = widget.onName?.call(uid, text) ?? false;
      if (!ok) {
        setState(() => _nameError = '1–24 printable ASCII characters.');
        return;
      }
    }
    _endNaming();
  }

  void _endNaming() {
    _show(() {
      _stage = HatchStage.card;
      _nameError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (widget.needsConsent ? _nextFocus : _copyFocus).requestFocus();
    });
  }

  void _markRevealed() {
    if (_revealed) return;
    _revealed = true;
    widget.onRevealed?.call();
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _markRevealed();
    widget.onClose();
  }

  /// Escape: out of the name prompt (skipping it), else closed.
  void _escape() {
    if (_stage == HatchStage.name) {
      _endNaming();
      return;
    }
    _close();
  }

  /// The hatchling as it stands in your zoo: its name, serial and date.
  ZooDaemon? get _owned {
    final hatch = _hatch;
    if (hatch == null) return null;
    final zoo = widget.zoo();
    return zoo.byUid(hatch.uid) ??
        (hatch.duplicate ? zoo.ofSpecies(hatch.daemonId).firstOrNull : null);
  }

  DaemonTraits? get _traits {
    final hatch = _hatch;
    return hatch == null
        ? null
        : rollTraits(roster, hatch.daemonId, hatch.seed);
  }

  /// Its own portrait plate, once harnessd has drawn it (for the card).
  DaemonIndividualArt? get _portraitArt {
    final owned = _owned;
    if (owned == null) return null;
    return widget.plates?.art(
      owned,
      PlateSize.portrait,
      roster.rules.versions.first,
      DaemonMood.idle,
    );
  }

  /// The hatchling's card (card.mjs): at 0.1, its name when it has one, its
  /// flags and `1 in N`, the day it hatched, the egg it came from and its
  /// serial (`#0042`) when the server minted one; its own portrait once
  /// harnessd has drawn it.
  List<String>? get _card {
    final def = _def, hatch = _hatch;
    if (def == null || hatch == null) return null;
    final owned = _owned;
    return zooCardLines(
      roster,
      def,
      version: roster.rules.versions.first,
      shiny: hatch.shiny,
      name: owned?.name,
      traits: _traits,
      hatched: owned?.hatched ?? DateTime.now().toUtc().toIso8601String(),
      egg: widget.egg.kind,
      serial: owned?.serial ?? hatch.serial,
      plate: _portraitArt?.frames.first.rows,
    );
  }

  /// A merged duplicate's level-up: the level and version yours reached,
  /// when it reached a new one.
  (int, String)? get _grew {
    final now = _owned;
    final was = widget.before?.byUid(now?.uid);
    if (now == null || was == null || now.bond <= was.bond) return null;
    return (now.bond, now.version);
  }

  String? get _grewFrom => widget.before?.byUid(_owned?.uid)?.version;

  Future<void> _copy() async {
    final card = _card;
    if (card == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: cardCodeBlock(card)));
      if (mounted) setState(() => _copyNote = 'Copied as a code block.');
    } catch (_) {
      if (mounted) setState(() => _copyNote = 'Could not copy.');
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.skippable ||
        _stage == HatchStage.card ||
        _stage == HatchStage.name ||
        _stage == HatchStage.failed ||
        _stage == HatchStage.consent ||
        _stage == HatchStage.suggest ||
        _stage == HatchStage.merged ||
        _stage == HatchStage.grew ||
        event.logicalKey == LogicalKeyboardKey.escape ||
        _modifiers.contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    _skipToCard();
    return KeyEventResult.handled;
  }

  static final _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.fn,
  };

  @override
  Widget build(BuildContext context) {
    AppTheme.watch(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        terminalFontStore,
        terminalThemeStore,
        AppTheme.palette,
        ?widget.plates,
      ]),
      builder: (context, _) {
        final theme = currentTerminalTheme();
        final cell = terminalCellSizeOf(context);
        final pitch = _pitch;
        final background = pitch ? daemonPitch : theme.background;
        // On the black stage the ink is light, whatever the theme.
        final fg = pitch ? const Color(0xffd0d0d0) : theme.foreground;
        final ink = terminalContentStyle(color: fg)
            .copyWith(fontFeatures: daemonTextFeatures);
        final muted = fg.withValues(alpha: .6);
        return CallbackShortcuts(
          bindings: {const SingleActivator(LogicalKeyboardKey.escape): _escape},
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: Semantics(
              scopesRoute: true,
              explicitChildNodes: true,
              label: 'Hatching',
              child: Material(
                key: const ValueKey('daemon-hatch'),
                color: background,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kTerminalCornerRadius),
                  side: terminalPaneBorder(focused: true),
                ),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: cell.width * 2,
                    vertical: cell.height,
                  ),
                  // A steady stage: the egg, the hatchling standing in it
                  // and the banner all fit, so the reveal never jumps before
                  // the card.
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: cell.height * _stageRows,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _children(theme, cell, ink, muted, pitch),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The rows every moment of the egg is drawn on: the egg at the reveal
  /// size, with room above its bottom half for the tallest hatchling of the
  /// released drops to stand in it.
  int get _canvasRows {
    final egg = _eggFrames('open').firstOrNull;
    if (egg == null) return 0;
    final rim = _rim(egg);
    var tallest = _hatchling?.rows.length ?? 0;
    for (final d in roster.released(DateTime.now())) {
      if (!d.plate) continue;
      tallest = max(
        tallest,
        daemonPlates
            .frame(
              d.id,
              PlateSize.reveal,
              roster.rules.versions.first,
              DaemonMood.idle,
            )
            .length,
      );
    }
    return egg.rows.length + max(0, tallest - rim - sunk);
  }

  /// The first row of the bottom half the hatchling rises out of.
  static int _rim(PlateFrame open) {
    final at = open.rows.indexWhere((r) => r.trim().isNotEmpty);
    return at < 0 ? 0 : at;
  }

  /// Rows the stage keeps before the card: the egg's canvas at the
  /// portrait's line height, with its banner under it.
  double get _stageRows => max(14, (_canvasRows + 5) * 1.15 + 1);

  /// The egg at this moment, as rows on the stage's canvas and the colour of
  /// each cell: the shell in its kind's gradient, the light inside in the
  /// rarity's colour once it opens (a secret's dimmed), and from the rise on
  /// the hatchling standing in the bottom half, as `#` in the faint colour
  /// until it fills with its own.
  Widget _eggStage(TerminalTheme theme, TextStyle ink) {
    final egg = _eggFrames(switch (_stage) {
      HatchStage.egg => 'p4',
      HatchStage.rock => 'rock',
      HatchStage.burst => 'burst',
      HatchStage.tumble => 'tumble',
      _ => 'open',
    });
    if (egg.isEmpty) return const SizedBox.shrink();
    final frame = egg[_frame % egg.length];
    final background = _pitch ? daemonPitch : theme.background;
    final eggInk = daemonEggInk(
      roster,
      _kind,
      theme,
      light: _light,
      dim: _dim,
      background: background,
    );
    final canvasRows = max(_canvasRows, frame.rows.length);
    final top = canvasRows - frame.rows.length;
    final hatchling = switch (_stage) {
      HatchStage.rise ||
      HatchStage.silhouette ||
      HatchStage.colour ||
      HatchStage.banner => _hatchling,
      _ => null,
    };
    final def = _def;
    final silhouetted =
        _stage == HatchStage.rise || _stage == HatchStage.silhouette;
    final hFrame = hatchling == null
        ? null
        : hatchling.frames[silhouetted
              ? 0
              : _loopTick % hatchling.frames.length];
    final hRows = hFrame?.rows.length ?? 0;
    final risen = min(_risen ?? hRows, hRows);
    final rim = top + _rim(frame);
    // The hatchling's top row: out of sight in the bottom half at first,
    // then a row higher each step, until it stands [sunk] rows deep.
    final hTop = rim + sunk - risen;
    final width = max(
      frame.rows.first.length,
      hFrame?.rows.fold<int>(0, (w, r) => max(w, r.length)) ?? 0,
    );
    final eggLeft = (width - frame.rows.first.length) ~/ 2;
    final hWidth = hFrame?.rows.fold<int>(0, (w, r) => max(w, r.length)) ?? 0;
    final hLeft = (width - hWidth) ~/ 2;
    final faint = ink.color!.withValues(alpha: .35);
    final shiny = _hatch?.shiny == true;
    final PlateCellInk? bodyInk = def == null || hatchling == null
        ? null
        : !def.plate
        ? null
        : daemonIndividualInk(
                roster,
                def,
                hatchling.traits,
                theme,
                shiny: shiny,
                background: background,
              ) ??
              daemonPlateInk(
                roster,
                def,
                theme,
                shiny: shiny,
                background: background,
              );
    final lineColour = def == null
        ? faint
        : daemonColor(def, theme, shiny: shiny);
    final rows = <String>[];
    final colours = <List<Color?>>[];
    for (var r = 0; r < canvasRows; r++) {
      final er = r - top;
      final hr = r - hTop;
      final row = StringBuffer();
      final rowColours = <Color?>[];
      for (var c = 0; c < width; c++) {
        final ec = c - eggLeft;
        final eggCh =
            er >= 0 &&
                er < frame.rows.length &&
                ec >= 0 &&
                ec < frame.rows[er].length
            ? frame.rows[er][ec]
            : ' ';
        final hc = c - hLeft;
        final hCh =
            hFrame != null &&
                hr >= 0 &&
                hr < hRows &&
                r < rim + sunk &&
                hc >= 0 &&
                hc < hFrame.rows[hr].length
            ? hFrame.rows[hr][hc]
            : ' ';
        // Above the rim the hatchling is in front; from the rim down the
        // shell hides what is still inside.
        final shellFirst = r >= rim;
        final useShell = eggCh != ' ' && (shellFirst || hCh == ' ');
        if (useShell) {
          row.write(eggCh);
          rowColours.add(
            eggInk.cell(frame.rows.length, er, eggCh, frame.mat(er, ec)),
          );
        } else if (hCh != ' ') {
          if (silhouetted) {
            row.write('#');
            rowColours.add(faint);
          } else {
            row.write(hCh);
            rowColours.add(
              bodyInk?.cell(hRows, hr, hCh, hFrame!.mat(hr, hc)) ?? lineColour,
            );
          }
        } else {
          row.write(' ');
          rowColours.add(null);
        }
      }
      rows.add(row.toString());
      colours.add(rowColours);
    }
    final size = ink.fontSize ?? 13;
    final style = ink.copyWith(
      height: 1.15,
      shadows: [
        Shadow(
          color: eggInk.glow.withValues(alpha: _dim ? .3 : .4),
          blurRadius: size * .8,
        ),
      ],
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RepaintBoundary(
        child: Text.rich(
          TextSpan(
            children: [
              for (final (r, row) in rows.indexed) ...[
                ...canvasRowSpans(row, colours[r], style),
                if (r < rows.length - 1) TextSpan(text: '\n', style: style),
              ],
            ],
          ),
          key: ValueKey(switch (_stage) {
            HatchStage.egg => 'daemon-hatch-egg',
            HatchStage.rock => 'daemon-hatch-egg-rock',
            HatchStage.burst => 'daemon-hatch-egg-burst-$_light',
            HatchStage.tumble => 'daemon-hatch-egg-tumble',
            HatchStage.open => 'daemon-hatch-egg-open',
            HatchStage.rise => 'daemon-hatch-rise',
            HatchStage.silhouette => 'daemon-hatch-silhouette',
            _ => 'daemon-hatch-portrait',
          }),
          semanticsLabel: switch (_stage) {
            HatchStage.egg || HatchStage.rock => 'An egg, hatching',
            HatchStage.burst ||
            HatchStage.tumble ||
            HatchStage.open => 'The egg opens',
            HatchStage.rise || HatchStage.silhouette => 'A silhouette',
            _ =>
              def == null
                  ? 'A hatchling'
                  : '${def.id} ${roster.rules.versions.first}',
          },
          style: style,
        ),
      ),
    );
  }

  /// A portrait on the stage (a merged duplicate's): a plate at the reveal
  /// size, or its line portrait.
  Widget _portrait(
    DaemonDef def,
    String version,
    TerminalTheme theme,
    TextStyle ink, {
    required Key key,
    required String label,
    DaemonMood mood = DaemonMood.idle,
    bool shiny = false,
    List<String>? rows,
  }) => FittedBox(
    fit: BoxFit.scaleDown,
    child: DaemonPortrait(
      roster: roster,
      def: def,
      version: version,
      style: ink.copyWith(height: 1.15),
      theme: theme,
      size: PlateSize.reveal,
      mood: mood,
      shiny: shiny,
      rows: rows,
      background: daemonBackdrop(def) ?? theme.background,
      animate: !widget.reduceMotion && widget.still == null,
      lid: _lid,
      textKey: key,
      semanticsLabel: label,
    ),
  );

  List<Widget> _children(
    TerminalTheme theme,
    Size cell,
    TextStyle ink,
    Color muted,
    bool pitch,
  ) {
    final def = _def;
    if (_stage == HatchStage.consent || _stage == HatchStage.suggest) {
      final name = _owned?.name ?? def?.id ?? 'it';
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: DaemonConsent(
            name: name,
            ink: ink.color,
            step: _stage == HatchStage.consent
                ? DaemonConsentStep.watch
                : DaemonConsentStep.suggest,
            onWatch: () {
              widget.onConsent?.call(true);
              _show(() => _stage = HatchStage.suggest);
            },
            onNotNow: () {
              widget.onConsent?.call(false);
              _close();
            },
            onSuggest: () {
              widget.onSuggest?.call();
              _close();
            },
            onKeepWatch: _close,
          ),
        ),
      ];
    }
    if (_stage == HatchStage.failed) {
      return [
        Text(
          'The egg did not open.',
          key: const ValueKey('daemon-hatch-failed'),
          style: ink,
        ),
        Text(
          'harnessd could not be reached. It is still in your zoo.',
          textAlign: TextAlign.center,
          style: ink.copyWith(color: muted),
        ),
        SizedBox(height: cell.height),
        _button('[ close ]', _close, theme, ink),
      ];
    }
    if (def == null ||
        _stage == HatchStage.egg ||
        _stage == HatchStage.rock ||
        _stage == HatchStage.burst ||
        _stage == HatchStage.tumble ||
        _stage == HatchStage.open) {
      return [_eggStage(theme, ink)];
    }
    if (_stage == HatchStage.merged || _stage == HatchStage.grew) {
      return _merged(def, theme, cell, ink, muted);
    }
    final shiny = _hatch?.shiny == true;
    final traits = _traits;
    final version = roster.rules.versions.first;
    final rarity = switch (def.rarity) {
      'rare' => theme.cyan,
      'legendary' => theme.yellow,
      'secret' => theme.magenta,
      _ => ink.color ?? theme.foreground,
    };
    final rows = bannerRows(def.id);
    final carded = _stage == HatchStage.card || _stage == HatchStage.name;
    final card = carded ? _card : null;
    // The shared banner face (daemons/banner.json), monospace, at a line
    // height that keeps its rows from touching.
    final banner = ink.copyWith(height: 1.15);
    final cardGround = pitch
        ? const Color(0xff0c0c0c)
        : Color.lerp(theme.background, theme.foreground, .04)!;
    final art = _portraitArt;
    final flags = traits != null && traits.seed != 0 && def.traits != null
        ? '${individualFlags(roster, def.id, traits)}  ·  '
              '${oneInText(oneIn(roster, def.id, traits))}'
        : null;
    return [
      if (_stage == HatchStage.pitch)
        Padding(
          padding: EdgeInsets.only(bottom: cell.height),
          child: Text(
            'It is pitch black. You are likely to be eaten by a grue.',
            key: const ValueKey('daemon-hatch-pitch'),
            textAlign: TextAlign.center,
            style: ink.copyWith(color: const Color(0xff949494)),
          ),
        ),
      if (_stage != HatchStage.pitch && card == null) _eggStage(theme, ink),
      if (_bannerRows > 0) ...[
        SizedBox(height: cell.height / 2),
        Text(
          rows.take(_bannerRows).join('\n'),
          key: const ValueKey('daemon-hatch-banner'),
          semanticsLabel: def.id,
          style: banner,
        ),
      ],
      if (carded) ...[
        SizedBox(height: cell.height / 2),
        Text(
          rarityStamp(roster, def, shiny: shiny),
          key: const ValueKey('daemon-hatch-stamp'),
          style: ink.copyWith(color: rarity, letterSpacing: 1),
        ),
        if (flags != null) ...[
          SizedBox(height: cell.height / 2),
          Text(
            flags,
            key: const ValueKey('daemon-hatch-flags'),
            textAlign: TextAlign.center,
            style: ink,
          ),
        ],
        SizedBox(height: cell.height / 2),
        Text(
          "fork() returned 0. it's a ${def.id}.",
          key: const ValueKey('daemon-hatch-words'),
          textAlign: TextAlign.center,
          style: ink.copyWith(color: muted),
        ),
        if (card != null) ...[
          SizedBox(height: cell.height),
          Container(
            padding: EdgeInsets.all(cell.width),
            decoration: BoxDecoration(
              color: cardGround,
              border: Border.all(color: ink.color!.withValues(alpha: .2)),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DaemonCardText(
                key: const ValueKey('daemon-hatch-card'),
                lines: card,
                portraitRows:
                    art?.frames.first.rows.length ??
                    cardPortrait(roster, def, version).length,
                style: ink.copyWith(fontSize: (ink.fontSize ?? 13) * .92),
                colour: daemonColor(def, theme, shiny: shiny),
                backdrop: daemonBackdrop(def),
                mats: art?.frames.first.mats,
                plate:
                    daemonIndividualInk(
                      roster,
                      def,
                      traits,
                      theme,
                      shiny: shiny,
                      background: cardGround,
                    ) ??
                    daemonPlateInk(
                      roster,
                      def,
                      theme,
                      shiny: shiny,
                      background: cardGround,
                    ),
              ),
            ),
          ),
          SizedBox(height: cell.height / 2),
          if (_stage == HatchStage.name)
            ..._namePrompt(def, theme, cell, ink, muted)
          else
            Row(
              children: [
                _button(
                  '[ copy ]',
                  _copy,
                  theme,
                  ink,
                  focusNode: _copyFocus,
                  key: const ValueKey('daemon-hatch-copy'),
                ),
                SizedBox(width: cell.width),
                if (widget.needsConsent)
                  _button(
                    '[ next ]',
                    _toConsent,
                    theme,
                    ink,
                    focusNode: _nextFocus,
                    key: const ValueKey('daemon-hatch-next'),
                  )
                else
                  _button('[ close ]', _close, theme, ink),
                SizedBox(width: cell.width * 2),
                Expanded(
                  child: Text(
                    _copyNote ?? 'esc closes',
                    style: ink.copyWith(color: muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ],
    ];
  }

  /// `name > _`: what to call it. Enter names it (empty skips), Escape or
  /// `[ skip ]` goes on without a name; it can be named later in the zoo.
  List<Widget> _namePrompt(
    DaemonDef def,
    TerminalTheme theme,
    Size cell,
    TextStyle ink,
    Color muted,
  ) => [
    Text(
      'what will you call it?',
      key: const ValueKey('daemon-hatch-name-question'),
      style: ink,
    ),
    TextField(
      key: const ValueKey('daemon-hatch-name'),
      controller: _name,
      focusNode: _nameFocus,
      maxLength: 24,
      style: ink,
      cursorWidth: cell.width,
      cursorHeight: cell.height,
      cursorColor: theme.cursor,
      decoration: InputDecoration(
        prefixText: 'name > ',
        prefixStyle: ink.copyWith(color: muted),
        hintText: individualName(
          def.id,
          serial: _owned?.serial ?? _hatch?.serial,
        ),
        hintStyle: ink.copyWith(color: muted.withValues(alpha: .35)),
        counterText: '',
        errorText: _nameError,
        errorStyle: ink.copyWith(color: theme.red),
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onSubmitted: (_) => _saveName(),
    ),
    Row(
      children: [
        _button(
          '[ name it ]',
          _saveName,
          theme,
          ink,
          key: const ValueKey('daemon-hatch-name-save'),
        ),
        SizedBox(width: cell.width),
        _button(
          '[ skip ]',
          _endNaming,
          theme,
          ink,
          key: const ValueKey('daemon-hatch-name-skip'),
        ),
        SizedBox(width: cell.width * 2),
        Expanded(
          child: Text(
            'enter names it · esc skips',
            style: ink.copyWith(color: muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  ];

  /// A merged duplicate (a server from before individuals): yours, at its
  /// version and in its colour (shiny now, if the duplicate was), `tim ·
  /// +150 xp`, then how it grew.
  List<Widget> _merged(
    DaemonDef def,
    TerminalTheme theme,
    Size cell,
    TextStyle ink,
    Color muted,
  ) {
    final hatch = _hatch!;
    final owned = _owned;
    final grew = _stage == HatchStage.grew ? _grew : null;
    final version = grew?.$2 ?? owned?.version ?? roster.rules.versions.first;
    final shiny = owned?.shiny ?? hatch.shiny;
    final name = owned?.name ?? def.id;
    final from = _grewFrom;
    // A level-up: the old version turns into the new in three frames, then
    // the new one holds, on one canvas so nothing jumps. A plate turns at the
    // reveal size, from its old idle to its new done.
    List<String> still(String v, DaemonMood mood) => def.plate
        ? daemonPlates.frame(def.id, PlateSize.reveal, v, mood)
        : renderPortrait(roster, def, v, mood, motion: false);
    final morphing = grew != null && from != null && from != version;
    final mood = grew == null ? DaemonMood.idle : DaemonMood.done;
    return [
      Container(
        color: daemonBackdrop(def),
        child: _portrait(
          def,
          version,
          theme,
          ink,
          key: ValueKey(
            _morph == null || grew == null
                ? 'daemon-hatch-portrait'
                : 'daemon-hatch-morph-$_morph',
          ),
          label: '${def.id} $version',
          mood: mood,
          shiny: shiny,
          rows: morphing
              ? morphPortrait(
                  still(from, DaemonMood.idle),
                  still(version, DaemonMood.done),
                  _morph ?? 4,
                )
              : def.plate
              ? null
              : still(version, mood),
        ),
      ),
      SizedBox(height: cell.height / 2),
      Text(
        '$name · +${hatch.xp} xp',
        key: const ValueKey('daemon-hatch-merged'),
        style: ink.copyWith(color: theme.yellow, letterSpacing: 1),
      ),
      SizedBox(height: cell.height / 2),
      Text(
        [
          'another ${def.id}. +${hatch.xp} xp.',
          if (hatch.shiny) 'yours is shiny now.',
        ].join(' '),
        key: const ValueKey('daemon-hatch-words'),
        textAlign: TextAlign.center,
        style: ink.copyWith(color: muted),
      ),
      if (grew != null) ...[
        SizedBox(height: cell.height / 2),
        Text(
          '$name grew: bond ${grew.$1} · ${grew.$2}',
          key: const ValueKey('daemon-hatch-grew'),
          style: ink.copyWith(color: theme.green),
        ),
        // Its room is kept while the portrait morphs, so nothing moves when
        // the changelog line appears.
        Opacity(
          opacity: _morph == null ? 1 : 0,
          child: Text(
            daemonChangelog(def, grew.$2, bond: grew.$1, xp: owned?.xp ?? 0),
            key: _morph == null
                ? const ValueKey('daemon-hatch-changelog')
                : null,
            textAlign: TextAlign.center,
            style: ink.copyWith(color: muted),
          ),
        ),
      ],
      SizedBox(height: cell.height),
      if (widget.needsConsent)
        _button(
          '[ next ]',
          _toConsent,
          theme,
          ink,
          focusNode: _nextFocus,
          key: const ValueKey('daemon-hatch-next'),
        )
      else
        _button('[ close ]', _close, theme, ink),
    ];
  }

  Widget _button(
    String label,
    VoidCallback onPressed,
    TerminalTheme theme,
    TextStyle ink, {
    FocusNode? focusNode,
    Key? key,
  }) => TextButton(
    key: key,
    focusNode: focusNode,
    onPressed: onPressed,
    style:
        TextButton.styleFrom(
          minimumSize: Size.zero,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: ink.color,
          shape: const RoundedRectangleBorder(),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.any(
                  {
                    WidgetState.hovered,
                    WidgetState.focused,
                    WidgetState.pressed,
                  }.contains,
                )
                ? theme.selection.withValues(alpha: .5)
                : Colors.transparent,
          ),
        ),
    child: Text(
      label,
      style: ink.copyWith(color: _pitch ? ink.color : theme.cursor),
    ),
  );
}

/// The plate a hatchling rises as: its idle loop's frames (material rows
/// with them), how long each shows, and its traits.
class _Hatchling {
  const _Hatchling(this.frames, this.frameMs, this.traits);
  final List<PlateFrame> frames;
  final int frameMs;
  final DaemonTraits? traits;
  List<String> get rows => frames.first.rows;
}

/// One row of a drawn canvas as spans, each cell in its own colour (null:
/// nothing is drawn there, so a space rides along in the run it falls in).
List<InlineSpan> canvasRowSpans(
  String row,
  List<Color?> colours,
  TextStyle style,
) {
  final spans = <InlineSpan>[];
  final text = StringBuffer();
  Color? colour;
  void flush() {
    if (text.isEmpty) return;
    spans.add(
      TextSpan(
        text: text.toString(),
        style: colour == null ? style : style.copyWith(color: colour),
      ),
    );
    text.clear();
  }

  for (var c = 0; c < row.length; c++) {
    final glyph = c < colours.length ? colours[c] : null;
    if (glyph != null && colour != null && glyph != colour) flush();
    if (glyph != null) colour = glyph;
    text.write(row[c]);
  }
  flush();
  return spans;
}
