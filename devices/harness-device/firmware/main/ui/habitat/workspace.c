#include "workspace.h"
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

void ht_workspace_cancel_touch(ht_workspace_t *w)
{
    w->touching = w->moved = w->cancelled = false;
}
void ht_workspace_touch(ht_workspace_t *w, int index, int count, int x, int y, uint32_t now)
{
    ht_workspace_cancel_touch(w);
    if (w->phase != HT_WORKSPACE_IDLE || index < 0 || index >= count || count > 24) return;
    w->touching = true; w->x = x; w->y = y; w->origin = w->choice = index;
    w->count = count; w->began = now;
}
bool ht_workspace_move(ht_workspace_t *w, int x, int y, unsigned axis, uint32_t now)
{
    if (!w->touching || w->cancelled) return false;
    bool before = w->moved;
    int choice = w->choice;
    if (axis == 1 || abs(y - w->y) > 64 || now - w->began >= 5000) {
        w->cancelled = true; return true;
    }
    if (axis == 2) {
        w->moved = true;
        // Match the pane swipe direction: pulling left reveals the next tab.
        int target = w->origin + (w->x - x) / 56;
        w->choice = target < 0 ? 0 : target >= w->count ? w->count - 1 : target;
    }
    return before != w->moved || choice != w->choice;
}
int ht_workspace_release(ht_workspace_t *w, int x, int y, unsigned axis, uint32_t now)
{
    ht_workspace_move(w,x,y,axis,now);
    int selected = w->touching && w->moved && !w->cancelled && now - w->began >= 25 &&
        w->choice != w->origin ? w->choice : -1;
    ht_workspace_cancel_touch(w);
    return selected;
}
void ht_workspace_cancel_request(ht_workspace_t *w)
{
    w->pending[0] = 0; w->phase = HT_WORKSPACE_IDLE; w->deadline = 0;
}
bool ht_workspace_request(ht_workspace_t *w, const char *id, uint32_t now)
{
    if (w->phase != HT_WORKSPACE_IDLE || !id || !*id || strlen(id) >= sizeof w->pending) return false;
    snprintf(w->pending,sizeof w->pending,"%s",id);
    w->serial++; if (!w->serial) w->serial++;
    w->deadline = now + 8000; w->phase = HT_WORKSPACE_WAIT_TAB;
    return true;
}
bool ht_workspace_selected(ht_workspace_t *w, const char *id)
{
    if (w->phase != HT_WORKSPACE_WAIT_TAB || !id || strcmp(w->pending,id)) return false;
    w->phase = HT_WORKSPACE_REFRESH; return true;
}
bool ht_workspace_refresh(ht_workspace_t *w, uint32_t serial, uint32_t generation)
{
    if (w->phase != HT_WORKSPACE_REFRESH || w->serial != serial) return false;
    w->floor = generation; w->phase = HT_WORKSPACE_WAIT_SNAPSHOT; return true;
}
bool ht_workspace_applied(ht_workspace_t *w, const char *id, uint32_t generation)
{
    if (w->phase != HT_WORKSPACE_WAIT_SNAPSHOT || !id || strcmp(w->pending,id) ||
        (int32_t)(generation - w->floor) <= 0) return false;
    w->phase = HT_WORKSPACE_READY; return true;
}
bool ht_workspace_tick(ht_workspace_t *w, uint32_t now)
{
    if (w->phase == HT_WORKSPACE_IDLE || (int32_t)(now - w->deadline) < 0) return false;
    ht_workspace_cancel_request(w); return true;
}
