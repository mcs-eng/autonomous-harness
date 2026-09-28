// Filled daemons (daemons/README.md, "Plates", "Plate colour", "Drops"): the
// baked plates as the desktop reads them, the colour rule against
// frames.json plateColors cell by cell, the card's portrait plate, drops on
// hold hidden everywhere, and the portrait widget's loop.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harness/core/local_key_value_store.dart';
import 'package:harness/daemons/daemon_face.dart';
import 'package:harness/daemons/plates.dart';
import 'package:harness/daemons/render.dart';
import 'package:harness/daemons/individuals.dart';
import 'package:harness/daemons/roster.dart';
import 'package:harness/daemons/zoo.dart';
import 'package:harness/daemons/zoo_controller.dart';
import 'package:harness/terminal/terminal_text.dart';
import 'package:harness/terminal/terminal_theme.dart';
import 'package:harness/widgets/daemon_panel.dart';
import 'package:harness/widgets/daemon_portrait.dart';
import 'package:harness/widgets/daemon_slot.dart';

class _Memory implements LocalKeyValueStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  final roster = daemonRoster;
  final frames =
      jsonDecode(File('../daemons/frames.json').readAsStringSync()) as Map;
  final plated = [
    for (final d in roster.daemons)
      if (d.plate) d,
  ];

  test('drop init is ten plate daemons; tim is its octopus', () {
    expect(plated.map((d) => d.id), [
      'tim',
      'gnu',
      'lynx',
      'mutt',
      'yak',
      'gopher',
      'bug',
      'tux',
      'auk',
      'beastie',
    ]);
    for (final d in plated) {
      expect(d.drop, 'init', reason: d.id);
      expect(d.portraits, isEmpty, reason: '${d.id} has no line portrait');
      expect(d.gradient, isNotNull, reason: d.id);
      expect(d.shinyGradient, isNotNull, reason: d.id);
      // The status line is unchanged: a one-line sprite per version.
      for (final v in roster.rules.versions) {
        expect(d.sprites[v], isNotNull, reason: '${d.id} $v');
      }
    }
    final tim = roster.byId('tim')!;
    expect(tim.gradient!.top, const Color(0xffff87ff));
    expect(tim.gradient!.bottom, const Color(0xffaf5fd7));
    // Every shiny in drop init is gold.
    expect(tim.shinyGradient!.bottom, const Color(0xffd7af00));
    // The old line-art tim is kept, on hold, as tmux.
    final tmux = roster.byId('tmux')!;
    expect(tmux.plate, isFalse);
    expect(tmux.drop, 'unix');
    expect(tmux.portraits, isNotEmpty);
  });

  test('every plate: each size, version and mood, idle 8 frames and the '
      'rest 4, one size for all, within its box', () {
    final rules = roster.rules.plate!;
    expect(daemonPlates.frameMs, 170);
    expect(rules.frameMs, 170);
    for (final d in plated) {
      expect(daemonPlates.has(d.id), isTrue, reason: d.id);
      for (final (size, cols, maxRows) in [
        (PlateSize.portrait, rules.portraitCols, rules.portraitRows),
        (PlateSize.reveal, rules.revealCols, rules.revealRows),
      ]) {
        for (final v in roster.rules.versions) {
          String? box;
          for (final mood in DaemonMood.values) {
            final loop = daemonPlates.loop(d.id, size, v, mood);
            expect(
              loop,
              hasLength(mood == DaemonMood.idle ? 8 : 4),
              reason: '${d.id} ${size.name} $v ${mood.name}',
            );
            for (final frame in loop) {
              final dims = '${frame.length}x${frame.first.length}';
              box ??= dims;
              expect(dims, box, reason: '${d.id} ${size.name} $v: one crop');
              expect(frame.length, lessThanOrEqualTo(maxRows));
              for (final row in frame) {
                expect(row.length, frame.first.length);
                expect(row.length, lessThanOrEqualTo(cols));
                for (final ch in row.split('')) {
                  expect(
                    ch == ' ' || rules.ink.containsKey(ch),
                    isTrue,
                    reason: '${d.id}: "$ch" has an ink level',
                  );
                }
              }
            }
          }
        }
      }
    }
    // Parsed once: a loop is split into rows once and kept.
    expect(
      identical(
        daemonPlates.loop('tim', PlateSize.reveal, '2.0', DaemonMood.work),
        daemonPlates.loop('tim', PlateSize.reveal, '2.0', DaemonMood.work),
      ),
      isTrue,
    );
    // Frames wrap; a daemon without plates has none.
    expect(
      daemonPlates.frame('tim', PlateSize.portrait, '2.0', DaemonMood.idle, 8),
      daemonPlates.frame('tim', PlateSize.portrait, '2.0', DaemonMood.idle),
    );
    expect(
      daemonPlates.frame('tmux', PlateSize.portrait, '2.0', DaemonMood.idle),
      isEmpty,
    );
    // The baked source matches daemons/plates.json.
    final baked =
        jsonDecode(File('../daemons/plates.json').readAsStringSync()) as Map;
    expect(
      daemonPlates.loop('gnu', PlateSize.portrait, '1.0', DaemonMood.need),
      [
        for (final f
            in ((baked['daemons'] as Map)['gnu']
                    as Map)['portrait']['1.0']['need']
                as List)
          (f as String).split('\n'),
      ],
    );
  });

  test('every plate colour matches frames.json plateColors', () {
    final cases = frames['plateColors'] as List;
    expect(cases, hasLength(plated.length * 2));
    var checked = 0;
    for (final raw in cases) {
      final f = raw as Map;
      final d = roster.byId(f['id'] as String)!;
      final shiny = f['shiny'] == true;
      final background = Color(
        0xff000000 | int.parse((f['bg'] as String).substring(1), radix: 16),
      );
      expect(background, plateReferenceBackground);
      final rows = daemonPlates.frame(
        d.id,
        PlateSize.values.byName(f['size'] as String),
        f['v'] as String,
        daemonMoodNamed(f['mood'] as String)!,
        f['frame'] as int,
      );
      expect(rows, hasLength(f['rows']), reason: d.id);
      for (final cell in f['cells'] as List) {
        final c = cell as Map;
        final r = c['r'] as int, col = c['c'] as int;
        final ch = c['ch'] as String;
        expect(rows[r][col], ch, reason: '${d.id} ($r, $col)');
        final colour = plateColor(
          roster,
          d,
          rows.length,
          r,
          ch,
          background: background,
          shiny: shiny,
        );
        expect(
          plateHex(colour!),
          c['hex'],
          reason: '${d.id} shiny=$shiny ($r, $col) "$ch"',
        );
        checked++;
      }
    }
    expect(checked, greaterThan(1000));
    // Spaces are not drawn; line-art daemons have no plate colour.
    final tim = roster.byId('tim')!;
    expect(plateColor(roster, tim, 10, 0, ' '), isNull);
    expect(plateColor(roster, roster.byId('tmux')!, 10, 0, '#'), isNull);
    // The rule, spelled out: `#` is the row colour, `@` burns toward white,
    // the top row is the top stop and the bottom row the bottom stop.
    expect(plateColor(roster, tim, 10, 0, '#'), tim.gradient!.top);
    expect(plateColor(roster, tim, 10, 9, '%'), tim.gradient!.bottom);
    expect(
      plateColor(roster, tim, 10, 0, '@'),
      plateMix(tim.gradient!.top, const Color(0xffffffff), 1.35 - 1),
    );
    expect(
      plateColor(roster, tim, 1, 0, '#', shiny: true),
      tim.shinyGradient!.top,
    );
  });

  test(
    'a plate card shows its portrait plate, idle, frame 0, byte for byte',
    () {
      final cards = frames['cards'] as List;
      for (final raw in cards) {
        final f = raw as Map;
        final d = roster.byId(f['id'] as String)!;
        if (!d.plate) continue;
        final version = f['version'] as String;
        final plate = daemonPlates.frame(
          d.id,
          PlateSize.portrait,
          version,
          DaemonMood.idle,
        );
        expect(cardPortrait(roster, d, version), plate);
        final out = cardLines(
          roster,
          d,
          version: version,
          shiny: f['shiny'] == true,
          serial: f['serial'] as int?,
          nickname: f['nickname'] as String?,
          name: f['name'] as String?,
          traits: f['seed'] is int
              ? rollTraits(roster, d.id, f['seed'] as int)
              : null,
          hatched: f['hatched'] as String?,
          egg: f['egg'] as String?,
        );
        expect(out, [
          for (final l in f['out'] as List) l as String,
        ], reason: '${d.id} $version shiny=${f['shiny']}');
        // The plate sits in rows 3 onward, centred, every glyph where it was.
        final inner = cardWidth - 4;
        final width = plate.fold(0, (w, l) => max(w, l.length));
        final pad = (inner - width) ~/ 2;
        for (final (r, row) in plate.indexed) {
          expect(out[3 + r].substring(2 + pad, 2 + pad + row.length), row);
        }
        // Passing the plate explicitly is the same card.
        expect(
          cardLines(roster, d, version: version, plate: plate).first,
          out.first,
        );
      }
      // A line-art daemon's card is its line portrait, as before.
      final tmux = roster.byId('tmux')!;
      expect(
        cardPortrait(roster, tmux, '2.0'),
        renderPortrait(roster, tmux, '2.0', DaemonMood.idle, motion: false),
      );
      // A plate daemon has no line portrait; its plate stands in.
      final tim = roster.byId('tim')!;
      expect(portraitFor(roster, tim, '1.0'), cardPortrait(roster, tim, '1.0'));
    },
  );

  group('drops on hold', () {
    final at = DateTime.utc(2026, 9, 27, 12);

    test('dropState: hold is hidden before any date is looked at', () {
      expect(roster.drops.map((d) => d.id), ['init', 'unix', 'tty']);
      expect(roster.drop('init')!.state(at), 'released');
      expect(
        roster.drop('init')!.state(DateTime.utc(2026, 9, 26)),
        'announced',
      );
      expect(roster.drop('init')!.state(DateTime.utc(2026, 9, 12)), 'hidden');
      for (final id in ['unix', 'tty']) {
        final drop = roster.drop(id)!;
        expect(drop.hold, isTrue);
        expect(drop.announce, isNull);
        expect(drop.release, isNull);
        expect(drop.state(at), 'hidden', reason: id);
        expect(drop.state(DateTime.utc(2099)), 'hidden', reason: id);
      }
      // Dates never win over hold (card.mjs checks hold first).
      const dated = DaemonDrop(
        'x',
        9,
        'x',
        announce: '2026-01-01',
        release: '2026-01-15',
        hold: true,
      );
      expect(dated.state(at), 'hidden');
      // A drop without dates and without hold is always out.
      expect(const DaemonDrop('y', 9, 'y').state(at), 'released');
      expect(roster.shownDrops(at).map((d) => d.id), ['init']);
      expect(roster.shownDrops(DateTime.utc(2026, 9, 12)), isEmpty);
    });

    test('never drawn or seeded: only init daemons come out of an egg', () {
      final released = roster.released(at).map((d) => d.id).toSet();
      expect(released, plated.map((d) => d.id).toSet());
      for (final kind in roster.rules.eggs.keys) {
        for (final (d, _) in drawWeights(roster, Zoo.empty, kind, now: at)) {
          expect(d.drop, 'init', reason: '$kind egg drew ${d.id}');
        }
      }
      // Before init's release nothing is out at all.
      expect(roster.released(DateTime.utc(2026, 9, 26)), isEmpty);
      // The night egg leans toward bug now (it was the bat).
      expect(roster.rules.eggs['night']!.boost, {'bug': 4});
      // A guest's seed keeps only what could have hatched.
      final seeded = applyZooOps(
        roster,
        Zoo.empty,
        [
          {
            'op': 'zoo.seed',
            'zoo': Zoo(
              daemons: [
                ZooDaemon(id: 'fish', hatched: '', egg: 'first'),
                ZooDaemon(id: 'gnu', hatched: '', egg: 'turn'),
              ],
              pair: 'fish',
              habits: ['turn'],
            ).toJson(),
          },
        ],
        random: Random(1),
        now: at,
      ).zoo;
      expect(seeded.daemons.map((d) => d.id), ['gnu']);
      expect(seeded.pair, legacyZooUid('gnu'));
      // History dates: 08-25 tux, 09-09 bug, 09-27 gnu.
      expect(roster.rules.historyDates['08-25'], 'tux');
      expect(roster.rules.historyDates['09-09'], 'bug');
      expect(roster.rules.historyDates['09-27'], 'gnu');
    });
  });

  group('the zoo tab', () {
    Future<DaemonFace> panel(WidgetTester tester, DateTime at) async {
      final storage = _Memory()
        ..values[ZooController.localZooKey] = jsonEncode({
          'zoo': Zoo(
            daemons: [
              ZooDaemon(
                id: 'tim',
                hatched: '2026-09-27T09:00:00Z',
                egg: 'first',
                version: '2.0',
                xp: 600,
              ),
              // Owned before its drop went on hold: never on a shelf.
              ZooDaemon(id: 'fish', hatched: '', egg: 'turn'),
            ],
            pair: 'tim',
            habits: ['turn', 'split', 'find'],
            firstEgg: true,
          ).toJson(),
          'seeded': true,
        });
      final zoo = ZooController(storage: storage, now: () => at);
      final face = DaemonFace(zoo, now: () => at);
      addTearDown(() {
        face.dispose();
        zoo.dispose();
      });
      zoo.bind('guest');
      await tester.pump();
      face.settings.tab = 'zoo';
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: Builder(
                builder: (context) => SizedBox(
                  width: terminalCellSizeOf(context).width * 46,
                  child: DaemonPanel(
                    face: face,
                    onClose: () {},
                    onHatch: (_) {},
                    onCommand: (_) {},
                    shortcut: (_) => null,
                    now: () => at,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return face;
    }

    testWidgets('released: drop init only; unix and tty on hold show '
        'nowhere, not even what you own of them', (tester) async {
      await panel(tester, DateTime.utc(2026, 9, 28, 12));
      expect(find.text('zoo · drop 1 init  1/9'), findsOneWidget);
      expect(find.textContaining('unix'), findsNothing);
      expect(find.textContaining('tty'), findsNothing);
      expect(find.byKey(const ValueKey('daemon-zoo-fish')), findsNothing);
      expect(find.byKey(const ValueKey('daemon-zoo-tmux')), findsNothing);
      expect(find.text('[ ? ]'), findsNWidgets(8));
      expect(find.text('[ ! ]'), findsOneWidget);
      // The portrait is tim 2.0's plate, frame 0 under Reduce Motion.
      final portrait = tester.widget<Text>(
        find.byKey(const ValueKey('daemon-portrait')),
      );
      expect(
        portrait.textSpan!.toPlainText(),
        daemonPlates
            .frame('tim', PlateSize.portrait, '2.0', DaemonMood.idle)
            .join('\n'),
      );
      // The card shows the same plate, as card.mjs draws it.
      await tester.tap(find.byKey(const ValueKey('daemon-card')));
      await tester.pump();
      final card = tester.widget<SelectableText>(
        find.descendant(
          of: find.byKey(const ValueKey('daemon-card-text')),
          matching: find.byType(SelectableText),
        ),
      );
      expect(
        card.textSpan!.toPlainText().split('\n'),
        zooCardLines(
          roster,
          roster.byId('tim')!,
          version: '2.0',
          hatched: '2026-09-27T09:00:00Z',
          egg: 'first',
        ),
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 3));
    });

    testWidgets('announced, not out: silhouettes and the day it comes out', (
      tester,
    ) async {
      await panel(tester, DateTime.utc(2026, 9, 20, 12));
      expect(find.text('zoo · drop 1 init  out 2026-09-27'), findsOneWidget);
      final tim = roster.byId('tim')!;
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('daemon-zoo-tim'))).data,
        silhouette(renderSprite(roster, tim, 0, DaemonMood.idle)),
      );
      expect(find.text('[ ! ]'), findsOneWidget, reason: 'the secret');
      expect(find.text('[ ? ]'), findsNothing);
      expect(find.textContaining('unix'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(minutes: 3));
    });
  });

  group('the portrait widget', () {
    const dark = darkTerminalTheme;
    const style = TextStyle(fontSize: 13, height: 1.15);

    Widget host(Widget child, {bool reduceMotion = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: child),
      ),
    );

    String shown(WidgetTester tester, String key) {
      final text = tester.widget<Text>(find.byKey(ValueKey(key)));
      return text.textSpan?.toPlainText() ?? text.data!;
    }

    DaemonPortrait portrait(
      String id, {
      String version = '2.0',
      DaemonMood mood = DaemonMood.idle,
      PlateSize size = PlateSize.portrait,
      bool animate = true,
      bool shiny = false,
    }) => DaemonPortrait(
      roster: roster,
      def: roster.byId(id)!,
      version: version,
      style: style,
      theme: dark,
      mood: mood,
      size: size,
      animate: animate,
      shiny: shiny,
      textKey: const ValueKey('p'),
    );

    List<String> loop(String id, DaemonMood mood, [String v = '2.0']) => [
      for (final f in daemonPlates.loop(id, PlateSize.portrait, v, mood))
        f.join('\n'),
    ];

    testWidgets('loops the mood, a frame every frameMs, and starts a new '
        "mood's loop at its beginning", (tester) async {
      await tester.pumpWidget(host(portrait('tim')));
      final idle = loop('tim', DaemonMood.idle);
      expect(shown(tester, 'p'), idle[0]);
      await tester.pump(const Duration(milliseconds: 170));
      expect(shown(tester, 'p'), idle[1]);
      await tester.pump(const Duration(milliseconds: 170 * 7));
      expect(shown(tester, 'p'), idle[0], reason: 'eight frames, then again');
      await tester.pumpWidget(host(portrait('tim', mood: DaemonMood.work)));
      final work = loop('tim', DaemonMood.work);
      expect(shown(tester, 'p'), work[0]);
      await tester.pump(const Duration(milliseconds: 170 * 5));
      expect(shown(tester, 'p'), work[1], reason: 'four frames');
      // Taken away mid-loop: no timer is left behind.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Reduce Motion, or no animation, shows frame 0 and never '
        'ticks', (tester) async {
      await tester.pumpWidget(host(portrait('gnu'), reduceMotion: true));
      final idle = loop('gnu', DaemonMood.idle);
      await tester.pump(const Duration(seconds: 2));
      expect(shown(tester, 'p'), idle[0]);
      await tester.pumpWidget(host(portrait('gnu', animate: false)));
      await tester.pump(const Duration(seconds: 2));
      expect(shown(tester, 'p'), idle[0]);
      // Moving again, then Reduce Motion: back to frame 0 at once.
      await tester.pumpWidget(host(portrait('gnu')));
      await tester.pump(const Duration(milliseconds: 340));
      expect(shown(tester, 'p'), idle[2]);
      await tester.pumpWidget(host(portrait('gnu'), reduceMotion: true));
      expect(shown(tester, 'p'), idle[0]);
    });

    testWidgets('every glyph in the plate colour, on the terminal background, '
        'with a glow in the bottom colour', (tester) async {
      for (final shiny in [false, true]) {
        await tester.pumpWidget(
          host(
            portrait(
              'tim',
              size: PlateSize.reveal,
              animate: false,
              shiny: shiny,
            ),
          ),
        );
        final text = tester.widget<Text>(find.byKey(const ValueKey('p')));
        final rows = daemonPlates.frame(
          'tim',
          PlateSize.reveal,
          '2.0',
          DaemonMood.idle,
        );
        final tim = roster.byId('tim')!;
        final gradient = plateGradient(tim, shiny: shiny)!;
        var r = 0, c = 0, glyphs = 0;
        for (final span in (text.textSpan! as TextSpan).children!) {
          final run = span as TextSpan;
          expect(
            run.style!.shadows!.single.color.withValues(alpha: 1),
            gradient.bottom,
          );
          for (final ch in run.text!.split('')) {
            if (ch == '\n') {
              r++;
              c = 0;
              continue;
            }
            expect(ch, rows[r][c]);
            if (ch != ' ') {
              expect(
                run.style!.color,
                plateColor(
                  roster,
                  tim,
                  rows.length,
                  r,
                  ch,
                  background: dark.background,
                  shiny: shiny,
                ),
                reason: 'shiny=$shiny ($r, $c) "$ch"',
              );
              glyphs++;
            }
            c++;
          }
        }
        expect(r, rows.length - 1);
        expect(glyphs, greaterThan(200));
      }
    });

    testWidgets('a line-art daemon draws its line portrait in its colour', (
      tester,
    ) async {
      await tester.pumpWidget(host(portrait('tmux')));
      final tmux = roster.byId('tmux')!;
      expect(
        shown(tester, 'p'),
        renderPortrait(roster, tmux, '2.0', DaemonMood.idle).join('\n'),
      );
      final text = tester.widget<Text>(find.byKey(const ValueKey('p')));
      expect(text.style!.color, daemonColor(tmux, dark));
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
