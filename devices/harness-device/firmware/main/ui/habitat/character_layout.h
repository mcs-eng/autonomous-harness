#pragma once
#include "character_types.h"
typedef enum {
    HT_CHARACTER_FULL, HT_CHARACTER_COMPACT, HT_CHARACTER_BRIEF,
    HT_CHARACTER_READING, HT_CHARACTER_QUICK
} ht_character_size_t;
enum { HT_CHARACTER_BRIEF_Y = 84, HT_CHARACTER_READING_Y = 82,
       HT_CHARACTER_BRIEF_TEXT_Y = 264, HT_CHARACTER_READING_TEXT_Y = 208,
       HT_CHARACTER_RECAP_CHARS = 90, HT_CHARACTER_RECAP_ROWS = 4,
       HT_NOTIFICATION_Y = 414 };
typedef struct {
    char pane[128];
    uint32_t began, next_ms;
    uint8_t opacity;
    bool initialized, working, activity;
} ht_character_caption_t;
bool ht_character_caption_tick(ht_character_caption_t *caption, uint32_t now,
                                const char *pane, bool working);
uint16_t ht_character_caption_ink(uint16_t foreground, uint16_t background, uint8_t opacity);
typedef void (*ht_character_painter_t)(ht_scene_t *, const ht_character_face_t *, uint8_t frame,
                                      uint16_t ink, ht_character_size_t size, int y);
void ht_character_layout(ht_scene_t *s, const ht_character_face_t *f, uint8_t frame,
                         uint16_t ink, const char *recap, ht_character_painter_t paint);
// Text-only inbox, deliberately distinct from the companion's home recap.
void ht_inbox_card(ht_scene_t *scene, const char *mark, const char *name,
                   const char *message, uint16_t foreground, uint16_t status_ink);
void ht_notification_bell(ht_scene_t *scene, unsigned count, uint16_t ink);
// The envelope is painted in the character's own cells, attached to its limb.
void ht_character_letter(ht_scene_t *s, const ht_character_face_t *f,
                         const ht_font_t *font, int x, int y);
