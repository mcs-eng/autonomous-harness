// Harness Pro: 720x720 LCD, 3.95" across, 10.01 px/mm.
//
// RE-DERIVED, NOT SCALED. The dial is 10.48 px/mm and this panel is 10.01 — within 5%, so a pixel means
// the same thing to a thumb on both and the type is shared unchanged. What differs is that the corners
// exist: the usable area goes from 170k pixels to 518k, and every number in metrics_round466.h that was
// a chord, an arc or a clearance from a rim is simply free here.
//
// These are the numbers from devices/harness-pro/mockup/ui-port.html, which was drawn 1:1 against the
// real palette and reviewed before any of this was built.
#pragma once

// ── the face ────────────────────────────────────────────────────────────────────────────────────────
#define UI_FACE_W      720
#define UI_FACE_H      720
#define UI_CX          360
#define UI_CY          360

// ── the readable column ─────────────────────────────────────────────────────────────────────────────
// A real margin this time. The rim used to be the margin; a square has to draw its own.
#define SCREEN_PAD     32
#define SAFE_CONTENT_W 656          // 720 - 2*32
#define SAFE_W         lv_pct(85)   // ~612px

// ── Overview ────────────────────────────────────────────────────────────────────────────────────────
// The dial's shape ports unchanged — one number in the middle, the hand's controls along the bottom —
// and the arc flattens into a row, because the reason it was an arc was the bezel.
#define OV_ROW_Y       124
#define OV_NUM_H       72
#define OV_ROW_GAP     14
#define OV_STATUS_Y    210
#define OV_SIDE_D      88
#define OV_BELL_X      152
#define OV_GEAR_X      480
#define OV_SIDE_Y      548
#define OV_VOICE_D     112
#define OV_VOICE_X     304
#define OV_VOICE_Y     536          // 12px proud of its neighbours, so it still reads as the primary

// ── agent tile ──────────────────────────────────────────────────────────────────────────────────────
// The body runs 191 -> 546, which is 355px against the dial's 136. That is where the room goes: a recap
// card of four lines instead of two, or a verb, a full tool path, three sub-agents and four todos with
// 22px still clear of the buttons.
#define TILE_PAD_TOP   112
#define TILE_NAME_GAP  28
#define TILE_ARC_Y     568
#define TILE_ARC_GAP   22

// ── the action row ──────────────────────────────────────────────────────────────────────────────────
// A straight row, and 96px targets rather than 80 — not for legibility but for the finger: 80px at
// 10.48 px/mm is 7.6mm, 96 at 10.01 is 9.6mm, and this face can afford to be generous. The width the
// square frees is deliberately left empty; three is still the right number of things to press.
#define ACT_BTN_D      96
#define ACT_PREV_X     168
#define ACT_NEXT_X     456
#define ACT_Y          568
#define ACT_VOICE_D    112
#define ACT_VOICE_X    304
#define ACT_VOICE_Y    560

// ── notification drawer ─────────────────────────────────────────────────────────────────────────────
// Four cards rather than two and a bit: a card is 134px, and 104 + 4*134 + 3*14 = 682 fits inside the
// 692 the face allows. Half of NOTIF_MAX at a glance.
#define NOTIF_LIST_W   656
#define NOTIF_LIST_H   496

// ── settings, pairing, pickers ──────────────────────────────────────────────────────────────────────
// Seven rows instead of four. The dial fits exactly four 84px rows between y~64 and y~402 and has to
// scroll to the fifth; here 90 + 7*84 = 678 lands inside the face with the row height unchanged, which
// matters — the row is sized for a fingertip, not for the screen.
#define SET_ROW_W      560
#define SET_ROW_H      84
#define SET_LIST_PAD   90
#define PAIR_W         560
#define PICK_PAD_V     260
#define BRIGHT_BOX_W   620
#define MACHINE_ROW_W  620

// ── pattern lock ────────────────────────────────────────────────────────────────────────────────────
// Spacing follows the face rather than the finger: the dots are targets whose SEPARATION is what stops
// two adjacent ones co-triggering, so a wider face wants a wider grid.
#define LK_GAP         150
#define LK_CX          UI_CX
#define LK_CY          UI_CY

// ── voice waveform ──────────────────────────────────────────────────────────────────────────────────
// Seven bars across a wider face: 346/10 = 34.6px between bars keeps the group the same proportion of
// the glass it is on the dial.
#define WAVE_PITCH_X10 346

// ── gesture edge bands (ui/touch.c) ─────────────────────────────────────────────────────────────────
// An upward swipe must START at or below UI_HOME_EDGE_Y to count as a bottom-edge swipe to Overview.
// The same proportions as the dial, on a taller face: ~14% of the height for the carousel band and the
// bottom ~30px for the reader. Held as proportions rather than pixels because what they describe is how
// far a thumb reaches from the bottom edge, and that has not changed.
#define UI_HOME_EDGE_Y         620
#define UI_READER_HOME_EDGE_Y  690

// ── how much the tile body holds ────────────────────────────────────────────────────────────────────
// The body is 355px here against the dial's 136, and these are what that buys. Measured, not hoped:
// verb 38 + 12 + tool 27 + 18 + three sub-agents 99 + 18 + four todos 135 = 347 into 355, with the
// action row still 22px clear.
//
// The row counts are what fits when BOTH lists are on screen at once. Either alone goes to seven, which
// is what the widgets scroll to; the pair is the case that has to be right.
// How many lines the recap card is pinned to. Four. The body has 355px and the card takes 205 of it, leaving 132 for whatever the turn also
// produced — a todo list, or simply air.
#define RECAP_LINES         4
#define RECAP_MAX_CHARS     120  // four lines rather than two
#define TODO_VISIBLE_ROWS   4
#define AGENTS_VISIBLE_ROWS 3

// ── the desk grid ───────────────────────────────────────────────────────────────────────────────────
// The tab's agents, laid out the way the Mac lays them out. The canvas below is the same proportion as
// a window's terminal area (1.34:1), so the app's unit rectangles land on it recognisably — which is the
// whole point: you find an agent by WHERE it is, not by reading a list.
#define UI_DESK_GRID   1
#define DESK_GRID_X    SCREEN_PAD
#define DESK_GRID_Y    88           // under the tab strip
#define DESK_GRID_W    656
// ALL THE WAY DOWN, 88 -> 688, with the face's own 32px margin under it.
//
// It was 488, stopping at 576 to leave room for the hand's row of ‹ ◉ › at 600 — a row that is drawn on
// scr_projects and is therefore BEHIND this overlay, invisible, the whole time the grid is up. So the
// bottom 144px was reserved for something nobody can see, and the tiles were a fifth shorter than the
// glass allows for it (owner, 2026-09-27: "phía dưới trong 1 đoạn ko làm gì, cho agent dài ra luôn đi").
//
// There is nothing for the hand to do here anyway: ‹ › walk between agents and there is no one agent on
// this face, and Voice belongs to a tile. The grid IS the control.
#define DESK_GRID_H    600
#define DESK_GRID_GAP  12
// A tile says two things, sized to the room it has. Three steps rather than a formula, because the
// jump from a full-height tile to a quarter one is not linear and a formula reads worse at both ends.
// The tab line: the first thing on the glass, and the one the app's own rule governs — only the tab you
// are on has a fill. Names are clipped rather than wrapped so the line never becomes two.
#define DESK_STRIP_X       24
#define DESK_STRIP_Y       24
#define DESK_STRIP_H       52
#define DESK_TAB_H         52
#define DESK_TAB_NAME_MAX  300
// THE TOP BAND IS THE TABS' AND NOTHING ELSE'S.
//
// The bell had a seat here for one build, and it cost twice. With nothing to report the seat was an
// empty 84px gap that read as a bug; to make the seat at all the strip had to give up the width, which
// pushed the last tab under a fade — and a fade is a gradient, not an affordance, so the screen stopped
// saying there were more tabs at all (owner, 2026-09-28, two photos).
//
// The bell went to the bottom-right corner instead, where this face had room going spare. See
// NOTIF_FAB_* below and the align in ui_screens.c.
#define DESK_STRIP_W       (UI_FACE_W - 2 * DESK_STRIP_X)

// ── the notification button, bottom right ───────────────────────────────────────────────────────────
// A FLOATING control, not a reserved one: it is drawn only when something is waiting, so it can sit
// over whatever is behind it — the desk's corner tile, the empty air under an agent — and cost nothing
// on every screen where the count is zero, which is most of them.
#define NOTIF_FAB_MARGIN   SCREEN_PAD

// 30% SMALLER AND HALF LIT, because it is not news — it is a count that sits there.
//
// At 64px in full blue it was the brightest thing on a face that is on all day, in the corner the eye
// rests in, saying only "two things are waiting" (owner, 2026-09-28: "nó sáng quá gây distract"). A
// notification the size of a button and the brightness of an alert asks to be dealt with now; this one
// does not. So it keeps its corner and stops shouting from it.
//
// Every number below is the old one times 0.7, and the font follows: montserrat_22's line box is ~26,
// so 26 + 2*10 = NOTIF_FAB_H, and the circle is still full rather than a ring around a small mark.
#define NOTIF_FAB_H        46
#define NOTIF_FAB_PAD_H    15
#define NOTIF_FAB_PAD_V    10
#define NOTIF_PILL_FONT    (&lv_font_montserrat_22)
#define NOTIF_PILL_GAP     7
// On the OBJECT, not on the background: the fill, the glyph and the count dim together, so it reads as
// one quiet control rather than as bright text on a faded disc.
#define NOTIF_FAB_OPA      LV_OPA_50
#define NOTIF_FAB_SHADOW   17

#define DESK_MARK_LG   40
#define DESK_MARK_MD   32
#define DESK_MARK_SM   24
