#include "character.h"
#include "octopus.h"
#include "tux.h"
#include <string.h>

typedef struct {
    const char *name;
    bool (*tick)(ht_character_motion_t *, uint32_t, ht_character_mood_t,
                 bool, bool, bool, int, unsigned, uint32_t);
    ht_character_painter_t paint;
} character_definition_t;

// Adding artwork changes this registry and its adapter, never the action layer.
static const character_definition_t characters[HT_CHARACTER_COUNT] = {
    [HT_CHARACTER_TIM] = {"Tim", ht_octopus_motion_tick, ht_octopus_draw},
    [HT_CHARACTER_TUX] = {"Tux", ht_tux_motion_tick, ht_tux_draw},
};
static const character_definition_t *definition(ht_character_id_t id)
{
    return &characters[(unsigned)id < HT_CHARACTER_COUNT ? id : HT_CHARACTER_TIM];
}
ht_character_id_t ht_character_default(void)
{
#ifdef DEVICE_DEFAULT_CHARACTER_TUX
    return HT_CHARACTER_TUX;
#else
    return HT_CHARACTER_TIM;
#endif
}
const char *ht_character_name(ht_character_id_t id) { return definition(id)->name; }
bool ht_character_select(ht_character_t *c, ht_character_id_t id)
{
    if (!c || (unsigned)id >= HT_CHARACTER_COUNT) return false;
    if (c->id == id) return true;
    memset(&c->motion, 0, sizeof c->motion);
    c->id = id;
    return true;
}
bool ht_character_tick(ht_character_t *c, uint32_t now, ht_character_mood_t mood,
                       bool quiet, bool visible, bool down, int x, unsigned level, uint32_t activity)
{
    if ((unsigned)mood >= HT_CHARACTER_MOODS) mood = HT_CHARACTER_IDLE;
    return definition(c->id)->tick(&c->motion, now, mood, quiet, visible, down, x, level, activity);
}
bool ht_character_delivery_tick(ht_character_t *c, uint32_t now, bool pending,
                                uint32_t sequence, bool animate)
{
    uint8_t before = c->delivery.lift;
    if (!c->delivery.initialized) {
        c->delivery.initialized = true;
        c->delivery.sequence = sequence;
    }
    if (sequence != c->delivery.sequence) {
        c->delivery.sequence = sequence;
        // Arrivals during a delivery coalesce; they cannot prolong the motion.
        if (!c->delivery.moving && pending && animate) {
            c->delivery.began = now;
            c->delivery.moving = true;
        }
    }
    uint32_t age = now - c->delivery.began;
    if (!pending || !animate || age >= 1280) c->delivery.moving = false;
    c->delivery.lift = c->delivery.moving ? (age / 160) % 2 : 0;
    if (c->delivery.moving) {
        uint32_t next = 160 - age % 160;
        if (next < c->motion.next_ms) c->motion.next_ms = next;
    }
    return before != c->delivery.lift;
}
static ht_character_face_t delivery_face(const ht_character_t *c, const ht_character_face_t *f)
{
    ht_character_face_t face = *f;
    face.pose.mail = f->unread && !f->carrying && f->mood != HT_CHARACTER_LISTENING
        ? 1 + c->delivery.lift : 0;
    return face;
}
void ht_character_face(ht_scene_t *s, const ht_character_t *c,
                       const ht_character_face_t *f, uint16_t ink, const char *recap)
{
    ht_character_face_t face = delivery_face(c, f);
    ht_character_layout(s, &face, c->motion.frame, ink, recap, definition(c->id)->paint);
}
void ht_character_portrait(ht_scene_t *s, const ht_character_t *c,
                           const ht_character_face_t *f, uint16_t ink,
                           ht_character_size_t size, int y)
{
    ht_character_face_t face = delivery_face(c, f);
    definition(c->id)->paint(s, &face, c->motion.frame, ink, size, y);
}
