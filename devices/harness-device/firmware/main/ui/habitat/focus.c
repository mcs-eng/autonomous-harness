#include "focus.h"
#include "theme.h"
#include <stdio.h>
#include <string.h>

/*
 * THE FOCUS FACE — the dial's pre-habitat screens, in cells.
 *
 * Reference: mockup/device-screens/png/agent-working.png and agent-recap.png, which are exact 466
 * renders of the firmware that shipped before this one. Those are proportional Geist at eight sizes;
 * this is ht_mono_28 at 17 px a cell, which holds about 27 characters a line where the old face held
 * roughly 35. So the arrangement is kept and the measurements are redone, never copied.
 *
 * ── the rule that decides every width on this file ──────────────────────────────────────────────
 *
 * A run's usable width is set by its LOWEST edge, not its top: the chord at distance d from the
 * centre is 2*sqrt(233^2 - d^2), and a 38 px row starting at y has its box ending at y+38. Getting
 * this backwards is what cut the brackets off the first square face's footer. Every width in ROWS
 * below is the chord at that row's bottom, minus a margin.
 *
 * ── the rule that decides the SHAPE of this file ────────────────────────────────────────────────
 *
 * ht_damage() diffs run index against run index and falls back to repainting the whole 466x466 the
 * moment the count or the order changes (terminal.c). So this face emits the SAME RUNS IN THE SAME
 * ORDER on every frame, with empty text where a row has nothing to say — the same stabiliser
 * ht_wrap() already applies by padding to a fixed line count. Do not make a row conditional.
 */

enum { FOCUS_ROWS = 7 };   // pill, name, status, and four of recap

/*
 * WHERE THE BODY STARTS, and it is measured off the raster rather than derived from the cells.
 *
 * Equal CELL gaps are not equal gaps to look at. The pill is a filled block so its bottom edge is
 * exactly its cell's, 60 + 28 = 88; the name's ink opens 11 px inside its cell and its descenders
 * run almost to the bottom of it. So cell gaps of 30 and 30 render as ink gaps of 41 and 44, and the
 * lower one looks the looser of the two.
 *
 * 183 is 118 + 38 + 27, and it puts both at 41. The asymmetry is not arbitrary: a pane name carries
 * a descender about half the time (p, y, g) while the first line of a summary carries an ascender
 * nearly always (h, d, t, k, l), so the gap below the name is the one that needs the three pixels
 * back. Verified by banding the rendered face — see focus_face() in test/test_character.c.
 */
enum { FOCUS_BODY_Y = 118 + 38 + 27 };

/*
 * y, and the width the chord allows there, against a 230 px working radius rather than the 233 px
 * face — the inset every other screen keeps off the bezel.
 *
 * THE NARROW EDGE IS THE ONE FARTHER FROM THE MIDDLE, which for a row above y=233 is its TOP, not
 * its bottom. An earlier note here said "the lowest edge" and meant it generally; that is only true
 * below the centre. The pill and the name sit entirely above it, and while the name had room to
 * spare nothing showed — then the engine badge made it spend its whole width and its top corners
 * went past the bezel.
 *
 *   pill   mono_20, y  60..88  -> far edge  60, d=173 -> chord 303
 *   name   mono_28, y 118..156 -> far edge 118, d=115 -> chord 398
 *   body   mono_28, rows from 183 -> far edges 183/221/297/335 -> chords 449/457/441/412
 *
 * THE STATUS ROW AND THE FIRST RECAP ROW SHARE A y, AND CANNOT BOTH BE FULL. render_home() builds
 * the recap from `!a->busy` and the activity from `a->busy`; its other two status strings ("Try
 * again", "Text expired") each require the recap to be absent as well. So one of the two is always
 * empty, and the face enforces that below rather than trusting it. An empty run draws nothing, and
 * the alternative — sliding the group to fill whichever half is missing — is what used to leave a
 * 96 px hole under the name whenever a turn had said something short.
 *
 * THE FOUR RECAP ROWS HOLD WHAT THE OCTOPUS'S DO: the same {408,408,391,340} and the same
 * HT_CHARACTER_RECAP_CHARS budget ht_character_layout() gives its roomy reading. They sit 22 px
 * higher than its HT_CHARACTER_READING_TEXT_Y, because that row has to clear a portrait and this one
 * has a line of text over it; the widths are re-measured for the y they actually use.
 */
static const struct { int y, width; const ht_font_t *font; } ROWS[FOCUS_ROWS] = {
    {  50, 240, &ht_mono_20 },   // the pill: 38 tall from 50, 20 cells of name — see pill()
    { 118, 384, &ht_mono_28 },
    { FOCUS_BODY_Y,       442, &ht_mono_28 },
    { FOCUS_BODY_Y,       408, &ht_mono_28 },
    { FOCUS_BODY_Y +  38, 408, &ht_mono_28 },
    { FOCUS_BODY_Y +  76, 391, &ht_mono_28 },
    { FOCUS_BODY_Y + 114, 340, &ht_mono_28 },
};

/*
 * One row, centred on what it actually contains.
 *
 * `rest` is advanced, so consecutive calls walk one string across several rows. A row with nothing
 * left still emits its run — see the shape rule above.
 */
static void row(ht_scene_t *s, int index, uint16_t ink, uint16_t fill, const char **rest)
{
    const ht_font_t *font = ROWS[index].font;
    // A filled row spends two of its cells on the padding that makes the block clear the text, so it
    // has two fewer to write in. Forgetting this is how a full-width pill overran its own chord.
    int cells = ROWS[index].width / font->width - (fill != s->background ? 2 : 0);
    char line[HT_TEXT_BYTES] = "";
    if (rest && *rest && **rest) {
        const char *begin = *rest, *end = ht_take_display_line(rest, cells, font);
        size_t n = (size_t)(end - begin);
        if (n >= sizeof line) n = sizeof line - 1;
        memcpy(line, begin, n);
        line[n] = 0;
    }
    int glyphs = 0;
    for (const char *p = line; *p; glyphs++) ht_utf8_next(&p);
    // A filled row is padded by one cell each side so the block clears the text it sits behind.
    bool filled = fill != s->background && glyphs;
    char padded[HT_TEXT_BYTES];
    snprintf(padded, sizeof padded, filled ? " %s " : "%s", line);
    int width = (glyphs + (filled ? 2 : 0)) * font->width;
    /*
     * ALWAYS ONE RUN, even with nothing to say.
     *
     * ht_text() refuses a run of width <= 0 and returns false, which leaves the next writer pointing
     * at the PREVIOUS run. An empty status row used to blank the engine mark, and three empty recap
     * rows used to blank the status — both from that. A one-cell run draws nothing and holds the
     * index, which is also what keeps ht_damage() on its cheap per-cell path.
     */
    if (width <= 0) width = font->width;
    ht_text(s, (HT_WIDTH - width) / 2, ROWS[index].y, width, font,
            ink, filled ? fill : s->background, padded);
}

/*
 * THE ENGINE'S OWN MARK.
 *
 * Order matches ENGINES in scripts/gen_habitat_fonts.py, which is what assigns the codepoints; the
 * two lists are one list in two files and must be changed together. `engine` is twelve bytes on the
 * wire (cable_client.c) and was stored and drawn nowhere until this face.
 *
 * An unknown engine gets no badge rather than a wrong one — a mark that means "some engine" teaches
 * a person to stop reading it.
 */
static const char *const ENGINES[] = {
    "claude", "codex", "cursor", "opencode", "grok", "copilot", "amp",
    "devin", "kilo", "pi", "hermes", "muse", "agy", "commandcode",
};

/*
 * And the colour it is drawn in — one per engine, in the order above.
 *
 * A badge is a single text cell, and ht_run_t.colors is per CELL, so a mark gets exactly one colour;
 * a two-tone logo (the Codex ring, the Antigravity gradient) is flattened to its dominant hue and
 * that is a real limit, not a choice. What IS a choice is which colour, and the old firmware's answer
 * is the one kept here: it recoloured Claude alone, to 0xcc7c5e, and let every other vendored asset
 * keep its own — which for ten of these fourteen meant white. Measured off those assets, only Codex,
 * Kilo, Muse and Antigravity ever carried a hue at all. Painting all fourteen in the accent, as the
 * first draft of this face did, made every engine look like the same lilac smudge and told a person
 * nothing; 0 here means "no colour of its own", and the mark is drawn in the row's ink.
 */
static const uint32_t ENGINE_INK[] = {
    0xcc7c5e, 0x7090f0, 0, 0, 0, 0, 0,
    0, 0xf0f070, 0, 0, 0x2d9bf0, 0x3080f0, 0,
};
_Static_assert(sizeof ENGINE_INK / sizeof ENGINE_INK[0] == sizeof ENGINES / sizeof ENGINES[0],
               "one ink per engine");

bool ht_focus_engine_mark(const char *engine, char out[4], uint32_t *ink)
{
    if (!engine || !*engine) return false;
    for (unsigned i = 0; i < sizeof ENGINES / sizeof ENGINES[0]; i++) {
        if (strcmp(engine, ENGINES[i])) continue;
        uint32_t cp = HT_ENGINE_FIRST + i;
        *ink = ENGINE_INK[i];
        out[0] = (char)(0xe0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
        out[2] = (char)(0x80 | (cp & 0x3f));
        out[3] = 0;
        return true;
    }
    return false;
}

/*
 * THE VOICE SCREEN: the waveform, or the three sparkles, and nothing else.
 *
 * The device drew it this way before habitat — a green meter on black while it listens, then three
 * marks while the words are on their way — and there is nothing else worth saying on a screen whose
 * whole job is to show that it is hearing you. So this branch emits the face's eight runs with the
 * other six empty, which is what keeps ht_damage() on its cheap path; see the note at the top.
 *
 * Nine bars from six heights, indexed by the 0..4 level that already reaches every skin through
 * pose.level. The shape is a hill: loud makes it taller, not wider.
 */
/*
 * THE RECORDING METER, as the old firmware drew it.
 *
 * Seven bars, six pixels wide, on a 22.4 px pitch about the screen's middle, resting at heights
 * 16/52/79/121/79/52/16 — the Figma measurements the deleted ui_screens.c carried — with a crest
 * travelling left to right. There it was seven LVGL rectangles whose heights an animation timer
 * drove every 40 ms; here each bar is one run of ht_wave, whose cell IS one bar in sixteen heights,
 * so the same picture costs seven runs and no allocation.
 *
 * The travelling wave is a table rather than a sine at runtime. The old tick advanced a phase 12°
 * every 40 ms and offset each bar by 40°, scaling its rest height between 0.35x and 1.0x; that is a
 * closed form over fifteen frames and seven bars, so it is evaluated once, by
 * scripts/gen_habitat_fonts.py's sibling arithmetic, and lives here as 105 bytes of level indices.
 * No trigonometry, no floating point, and the cycle is the old 1.2 s exactly — see
 * ht_focus_motion_tick for why fifteen frames at this duration land there.
 */
enum { WAVE_BARS = 7, WAVE_FRAMES = 15, WAVE_PITCH_X10 = 224 };
static const uint8_t WAVE[WAVE_FRAMES][WAVE_BARS] = {
    {  1,  6, 10, 14,  8,  3,  1 },
    {  1,  6, 10, 13,  6,  3,  0 },
    {  2,  6,  9, 11,  5,  2,  0 },
    {  2,  6,  8,  9,  4,  2,  1 },
    {  2,  6,  7,  7,  3,  2,  1 },
    {  2,  5,  5,  6,  3,  3,  1 },
    {  1,  4,  4,  5,  4,  4,  1 },
    {  1,  3,  3,  5,  5,  4,  2 },
    {  1,  2,  3,  6,  6,  5,  2 },
    {  1,  2,  4,  8,  7,  6,  2 },
    {  1,  2,  4, 10,  9,  6,  2 },
    {  0,  2,  6, 12,  9,  6,  1 },
    {  0,  3,  7, 14, 10,  6,  1 },
    {  1,  4,  8, 15,  9,  5,  1 },
    {  1,  5,  9, 15,  9,  4,  1 },
};

// One ht_wave codepoint as UTF-8. Sixteen levels, so this is never a multi-branch encoder.
static void wave_glyph(unsigned level, char out[4])
{
    uint32_t cp = HT_WAVE_FIRST + (level >= HT_WAVE_LEVELS ? HT_WAVE_LEVELS - 1 : level);
    out[0] = (char)(0xe0 | (cp >> 12));
    out[1] = (char)(0x80 | ((cp >> 6) & 0x3f));
    out[2] = (char)(0x80 | (cp & 0x3f));
    out[3] = 0;
}

static void voice_face(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame)
{
    bool listening = f->mood == HT_CHARACTER_LISTENING;

    /*
     * TEN RUNS, ALWAYS, IN THIS ORDER — seven bars then three sparkles — whichever half is showing.
     *
     * ht_damage() diffs run index against run index and repaints all 466x466 the moment the count or
     * the order moves, so the half that is idle is emitted empty rather than skipped. Recording and
     * sending are then a change of text and colour, not a reshape, and the damage is the cells that
     * actually moved.
     */
    int mid_y = (HT_HEIGHT - ht_wave.height) / 2;
    uint16_t voice = ht_rgb(HT_THEME_VOICE);
    for (int k = 0; k < WAVE_BARS; k++) {
        char bar[4] = {0};
        if (listening) wave_glyph(WAVE[frame % WAVE_FRAMES][k], bar);
        int x = HT_WIDTH / 2 + (k - WAVE_BARS / 2) * WAVE_PITCH_X10 / 10 - ht_wave.width / 2;
        ht_text(s, x, mid_y, ht_wave.width, &ht_wave, voice, s->background, bar);
    }

    /*
     * And the sending sweep: three filled sparkles on a 66 px pitch, the lit one travelling across
     * them. That pitch and that artwork are the old screen's; what is gone is its 1.3x pop on the
     * lit mark, because a glyph has one size and scaling it would mean a second atlas for a state
     * that already reads from the colour alone. White idle, the meter's own green lit.
     */
    int spark_y = (HT_HEIGHT - ht_spark.height) / 2;
    int lit = (frame % WAVE_FRAMES) / 5;      // three steps, 200 ms each, per the old busy sweep
    for (int i = 0; i < 3; i++)
        ht_text(s, HT_WIDTH / 2 + (i - 1) * 66 - ht_spark.width / 2, spark_y,
                ht_spark.width, &ht_spark,
                listening ? s->background : i == lit ? voice : f->foreground, s->background,
                listening ? "" : HT_SPARK);

    // And the rows the home face owns, emitted empty for the same reason.
    for (int i = 0; i < FOCUS_ROWS; i++)
        ht_text(s, 0, ROWS[i].y, ROWS[i].font->width, ROWS[i].font, f->dim, s->background, "");
}

/*
 * The microphone level, in one run.
 *
 * Nine cells, indexed by the 0..4 level that already reaches every skin through pose.level (fed from
 * audio_client_input_level()). Deliberately NOT a background-filled bar whose width tracks the
 * level: a run whose `w` changes every frame trips the reshape path in ht_damage() and forfeits
 * banded damage for the entire scene. A fixed-width string changes only its cells.
 */
static const char *meter(unsigned level)
{
    // Nine cells that grow outward from the middle. A mono cell has one height, so this is a shape
    // that widens rather than a waveform that rises — the honest version of the old face's bars.
    static const char *const bars[5] = {
        "    -    ", "   -|-   ", "  -|I|-  ", " -|III|- ", "-|IIIII|-"
    };
    return bars[level > 4 ? 4 : level];
}

/*
 * THE TAB PILL, as the design draws it: a rounded box with a thin lighter rim.
 *
 * Habitat fills rectangles and nothing else, so the outline is a run of ht_pill glyphs — two cells of
 * left cap, one body cell per letter, two of right cap — whose coverage levels 1 and 2 are the fill
 * and the rim (see HT_THEME_PILL). The name is a second run laid over the body cells with exactly
 * level 1 as its background, from ht_blend(), so the two meet without a seam. The caps are the
 * padding: the name starts where the left cap's curve ends.
 *
 * TWO RUNS, ALWAYS — with no tab both are one empty cell — so the face's run count never moves.
 * The name's cell sits 4 px into the pill, which centres its cap height (rows 8..22 of ht_mono_20)
 * on the pill's middle rather than centring the cell and leaving the letters high.
 */
static void pill(ht_scene_t *s, const ht_character_face_t *f, const char *tab)
{
    const ht_font_t *font = ROWS[0].font;
    int cells = ROWS[0].width / font->width;
    char line[HT_TEXT_BYTES] = "";
    if (*tab) {
        const char *rest = tab, *end = ht_take_display_line(&rest, cells, font);
        size_t n = (size_t)(end - tab);
        if (n >= sizeof line) n = sizeof line - 1;
        memcpy(line, tab, n);
        line[n] = 0;
    }
    int glyphs = 0;
    for (const char *p = line; *p; glyphs++) ht_utf8_next(&p);
    if (!glyphs) {
        ht_text(s, 0, ROWS[0].y, ht_pill.width, &ht_pill, s->background, s->background, "");
        ht_text(s, 0, ROWS[0].y, font->width, font, f->foreground, s->background, "");
        return;
    }
    char outline[HT_TEXT_BYTES];
    int used = snprintf(outline, sizeof outline, "%s", HT_PILL_LEFT);
    for (int i = 0; i < glyphs && used + 4 < (int)sizeof outline - 7; i++)
        used += snprintf(outline + used, sizeof outline - (size_t)used, "%s", HT_PILL_BODY);
    snprintf(outline + used, sizeof outline - (size_t)used, "%s", HT_PILL_RIGHT);
    int width = (glyphs + 4) * ht_pill.width, x = (HT_WIDTH - width) / 2;
    uint16_t ink = ht_rgb(HT_THEME_PILL);
    ht_text(s, x, ROWS[0].y, width, &ht_pill, ink, s->background, outline);
    ht_text(s, x + 2 * ht_pill.width, ROWS[0].y + 4, glyphs * font->width, font, f->foreground,
            ht_blend(ink, s->background, 1), line);
}

void ht_focus_face(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame, uint16_t ink,
                   const char *recap)
{
    (void)ink;
    if (f->voice) { voice_face(s, f, frame); return; }
    // The pane this agent belongs to. It stands where the old face drew the repository name, which
    // does not exist anywhere in the cable vocabulary — see ht_character_face_t.
    pill(s, f, f->tab && *f->tab ? f->tab : "");

    /*
     * The name, and the engine's badge beside it.
     *
     * The badge is its own run because a run carries one colour, and the badge's is not the name's:
     * this is what lets each engine keep its own ink (ENGINE_INK). ht_run_t.colors would colour
     * cells individually, but that array has to outlive both scene buffers and a face rebuilt every
     * frame has nowhere to keep one — and a one-cell badge would get one colour out of it anyway.
     * The cell is wider than a letter's, so the pair is measured and centred together rather than
     * the badge being squeezed into the name's first character.
     */
    char mark[4];
    uint32_t mark_ink = 0;
    bool badged = ht_focus_engine_mark(f->engine, mark, &mark_ink);
    const char *who = f->recipient ? f->recipient : "";
    int cells = 0;
    for (const char *p = who; *p; cells++) ht_utf8_next(&p);
    // The badge spends part of the row's chord, so the name gets what is left of it — not the whole
    // width it would have had alone. Getting this wrong puts the pair's ends outside the bezel.
    int room = ROWS[1].width - (badged ? ht_engine.width + 8 : 0);
    if (cells * ht_mono_28.width > room) cells = room / ht_mono_28.width;
    int name_w = cells * ht_mono_28.width;
    int total = name_w + (badged ? ht_engine.width + 8 : 0);
    if (total > ROWS[1].width) total = ROWS[1].width;
    int x = (HT_WIDTH - total) / 2;
    // Always emitted, badge or not, so the run count and order never move — see the note at the top.
    ht_text(s, badged ? x : 0, ROWS[1].y, badged ? ht_engine.width : 1, &ht_engine,
            mark_ink ? ht_rgb(mark_ink) : f->foreground, s->background, badged ? mark : "");
    ht_text(s, x + (badged ? ht_engine.width + 8 : 0), ROWS[1].y, name_w ? name_w : 1, &ht_mono_28,
            f->foreground, s->background, who);

    /*
     * The live line.
     *
     * While listening this is the meter; while working it is the activity the daemon scraped off the
     * engine's spinner plus the seconds this dial has been counting. Neither is a tool call and the
     * seconds are the dial's own — see ht_character_face_t.elapsed.
     */
    char status[HT_TEXT_BYTES];
    uint16_t status_ink = f->ink;
    if (f->mood == HT_CHARACTER_LISTENING) {
        snprintf(status, sizeof status, "%s", meter(f->pose.level));
        status_ink = ht_rgb(HT_THEME_DONE);
    } else if (f->activity && *f->activity) {
        if (f->elapsed) snprintf(status, sizeof status, "%s... %us", f->activity, f->elapsed);
        else snprintf(status, sizeof status, "%s", f->activity);
        status_ink = ht_rgb(HT_THEME_DONE);
    } else if (f->status && *f->status) {
        snprintf(status, sizeof status, "%s", f->status);
    } else {
        status[0] = 0;
    }
    // Whatever the turn left behind, in the octopus's own four rows and under its own character
    // budget, so the same summary reads the same on either skin.
    char prose[HT_CHARACTER_RECAP_CHARS * 4 + 8];
    ht_display_text(prose, sizeof prose, recap && *recap ? recap : "", &ht_mono_28);
    int budget = 0;
    for (const char *p = prose; *p; budget++) ht_utf8_next(&p);

    /*
     * The two cannot share the glass — see the ROWS comment. Stated here as code rather than left as
     * an assumption about render_home(), so a future caller that breaks it loses the status line
     * instead of printing it through the summary.
     */
    if (prose[0]) status[0] = 0;
    const char *live = status;
    row(s, 2, status_ink, s->background, &live);

    const char *body = prose;
    for (int i = 3; i < FOCUS_ROWS; i++) row(s, i, f->foreground, s->background, &body);

    // More than the rows or the budget hold. The octopus marks this too (recap_lines); without it a
    // summary that was cut simply reads as a sentence that stops.
    if (*body || budget > HT_CHARACTER_RECAP_CHARS) {
        for (int i = s->count - 1; i >= 3; i--) {
            char *line = s->runs[i].text;
            size_t n = strlen(line);
            if (!n || (n == 1 && line[0] == ' ')) continue;
            while (n && line[n - 1] == ' ') n--;
            size_t cells = (size_t)(s->runs[i].w / s->runs[i].font->width);
            if (n + 3 > cells) n = cells > 3 ? cells - 3 : 0;
            // Finish at the last whole word the row supplies, the way lines() does — a cut through
            // the middle of one reads as a typo rather than as more text waiting.
            size_t word = n;
            while (word && line[word - 1] != ' ') word--;
            if (word > 1) n = word;
            while (n && line[n - 1] == ' ') n--;
            strcpy(line + n, "...");
            break;
        }
    }
}

void ht_focus_portrait(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame, uint16_t ink,
                       ht_character_size_t size, int y)
{
    (void)frame;
    (void)size;
    const char *name = f->recipient ? f->recipient : "";
    ht_center(s, y, &ht_mono_28, ink, name);
}

bool ht_focus_motion_tick(ht_character_motion_t *m, uint32_t now, ht_character_mood_t mood,
                          bool quiet, bool visible, bool down, int x, unsigned level,
                          uint32_t activity)
{
    /*
     * Fifteen frames, and only the voice screen spends them.
     *
     * Nothing on the home face moves — a skin whose subject is the work should not fidget. These are
     * the recording meter and the sending sweep, both of which the old firmware animated, and the
     * duration is picked so each lands on the cadence it had there.
     *
     * ht_character_motion_step halves the rate while the mood is LISTENING or IDLE, which is exactly
     * the mood ui_habitat.c reports while the microphone is open. So 600 ms of phase over fifteen
     * frames is 40 ms a frame recording — the old wave_tick's timer period, 1.2 s for a full
     * travelling cycle — and 20 ms a frame sending, where the sweep steps every fifth frame and so
     * holds each sparkle for the same 200 ms the old busy sweep did.
     *
     * `ends` are cumulative marks in that phase, not frame numbers. An earlier version listed
     * 1..6 against a 900 ms duration, which put every frame boundary inside the first six
     * milliseconds and left the animation parked on its last frame for the rest of the cycle —
     * a screen that looked as dead as the `frames = 1` it replaced.
     */
    static const uint16_t ends[] = { 40, 80, 120, 160, 200, 240, 280, 320,
                                     360, 400, 440, 480, 520, 560, 600 };
    static const ht_character_animation_t sweep = { 15, 600, ends };
    return ht_character_motion_step(m, &sweep, now, mood, quiet, visible, down, x, level,
                                    activity, true);
}
