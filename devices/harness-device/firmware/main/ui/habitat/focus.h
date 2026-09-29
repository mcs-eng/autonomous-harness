#pragma once
#include "character_layout.h"
#include "character_types.h"

/*
 * The Focus skin: the work, not a companion.
 *
 * Tim and Tux are portraits with words arranged around them, so ht_character_layout() owns the seats
 * and hands the artwork one rectangle. Focus has no artwork — the arrangement IS the skin — so it
 * takes the whole face through the `face` pointer in character.c's registry.
 */
void ht_focus_face(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame, uint16_t ink,
                   const char *recap);

/*
 * The painter half of the registry row. Focus never draws a portrait, but ht_character_portrait()
 * calls `paint` directly and every registry entry must answer it; this draws the name alone, which is
 * the only sensible thing a portrait of "no companion" can be.
 */
void ht_focus_portrait(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame, uint16_t ink,
                       ht_character_size_t size, int y);

/* One frame, no motion. The only thing that animates on this face is the compositor's own shimmer. */
bool ht_focus_motion_tick(ht_character_motion_t *m, uint32_t now, ht_character_mood_t mood,
                          bool quiet, bool visible, bool down, int x, unsigned level,
                          uint32_t activity);
