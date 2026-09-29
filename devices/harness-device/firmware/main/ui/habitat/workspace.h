#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef enum { HT_WORKSPACE_IDLE, HT_WORKSPACE_WAIT_TAB, HT_WORKSPACE_REFRESH,
               HT_WORKSPACE_WAIT_SNAPSHOT, HT_WORKSPACE_READY } ht_workspace_phase_t;
typedef struct {
    bool touching, moved, cancelled;
    int x, y, origin, choice, count;
    uint32_t began;
    char pending[64];
    uint32_t serial, deadline, floor;
    ht_workspace_phase_t phase;
} ht_workspace_t;

void ht_workspace_touch(ht_workspace_t *, int index, int count, int x, int y, uint32_t now);
bool ht_workspace_move(ht_workspace_t *, int x, int y, unsigned axis, uint32_t now);
// -1 means no navigation; the UI handles a stationary tap by opening its list.
int ht_workspace_release(ht_workspace_t *, int x, int y, unsigned axis, uint32_t now);
void ht_workspace_cancel_touch(ht_workspace_t *);
bool ht_workspace_request(ht_workspace_t *, const char *id, uint32_t now);
bool ht_workspace_selected(ht_workspace_t *, const char *id);
bool ht_workspace_refresh(ht_workspace_t *, uint32_t serial, uint32_t generation);
bool ht_workspace_applied(ht_workspace_t *, const char *id, uint32_t generation);
void ht_workspace_cancel_request(ht_workspace_t *);
bool ht_workspace_tick(ht_workspace_t *, uint32_t now);
