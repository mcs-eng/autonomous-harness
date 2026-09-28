#pragma once
#include "terminal.h"

// Application state, shared by every character. Artwork never owns actions.
typedef enum {
    HT_CHARACTER_IDLE, HT_CHARACTER_WORKING, HT_CHARACTER_ATTENTION, HT_CHARACTER_DONE,
    HT_CHARACTER_OFFLINE, HT_CHARACTER_ASLEEP, HT_CHARACTER_BOOPED, HT_CHARACTER_LISTENING,
    HT_CHARACTER_MOODS
} ht_character_mood_t;
typedef struct {
    int8_t look;
    uint8_t hands, level, mail; // 0: no letter, 1: holding, 2: briefly lifting it.
    bool blink, pressed;
} ht_character_pose_t;
typedef struct {
    ht_character_pose_t pose;
    ht_character_mood_t mood;
    uint32_t next_blink, blink_until, reaction_at, reaction_until, release_until;
    uint32_t activity, sequence, next_ms, level_at;
    bool initialized, was_down;
} ht_character_reaction_t;
typedef struct {
    const char *recipient, *status, *hint, *detail;
    ht_character_mood_t mood;
    ht_character_pose_t pose;
    bool focus, carrying, footer_action, straight_title, unread, primary_title, roomy_reading, single_label;
    uint16_t ink, foreground, dim;
} ht_character_face_t;

typedef struct {
    uint16_t frames, duration;
    const uint16_t *ends;
} ht_character_animation_t;
typedef struct {
    ht_character_reaction_t reaction;
    uint32_t last_ms, next_ms;
    uint16_t phase;
    uint8_t frame, remainder, rate;
    bool initialized, running;
    const ht_character_animation_t *animation;
} ht_character_motion_t;

bool ht_character_reaction_tick(ht_character_reaction_t *m, uint32_t now, ht_character_mood_t mood,
                                bool quiet, bool visible, bool down, int x, unsigned level, uint32_t activity);
// One pause/resume, touch, microphone, quiet-mode and wrap-safe clock for all art.
bool ht_character_motion_step(ht_character_motion_t *m, const ht_character_animation_t *animation,
                              uint32_t now, ht_character_mood_t mood, bool quiet, bool visible,
                              bool down, int x, unsigned level, uint32_t activity, bool animate);
