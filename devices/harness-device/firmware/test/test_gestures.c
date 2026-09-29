#include "../main/ui/habitat/gestures.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
static ht_gesture_t g;
static ht_touch_result_t tap(uint32_t t, int x, int y) {
    ht_gesture_begin(&g,x,y,t,0);
    ht_gesture_move(&g,x+2,y-2);
    return ht_gesture_end(&g,x,y,t+75);
}
static void clear(void) { memset(&g,0,sizeof(g)); }
static uint32_t seed=1267;
static unsigned next(void) { seed=seed*1664525u+1013904223u; return seed; }
int main(void) {
    clear(); ht_gesture_begin(&g,233,233,1000,0);
    assert(g.live); // DOWN only starts classification, never an action.
    assert(ht_gesture_end(&g,233,233,1075)==HT_TOUCH_TAP);
    ht_gesture_guard(&g,1075); ht_gesture_cancel(&g);
    assert(tap(1200,233,233)==HT_TOUCH_NONE);
    assert(tap(1400,233,233)==HT_TOUCH_NONE); // old double/triple habit is one voice intent
    assert(tap(1600,233,233)==HT_TOUCH_TAP);
    clear(); ht_gesture_begin(&g,230,230,1000,0);
    assert(ht_gesture_end(&g,230,230,1330)==HT_TOUCH_TAP); // deliberate slower tap
    ht_gesture_begin(&g,230,230,2000,0);
    assert(ht_gesture_end(&g,230,230,2700)==HT_TOUCH_HOLD);
    ht_gesture_begin(&g,230,230,3000,0);
    assert(ht_gesture_end(&g,230,230,10000)==HT_TOUCH_NONE); // resting finger
    ht_gesture_begin(&g,230,230,11000,0);
    assert(ht_gesture_end(&g,230,230,11024)==HT_TOUCH_NONE); // sensor pulse
    clear(); assert(tap(UINT32_MAX-150,233,233)==HT_TOUCH_TAP);
    ht_gesture_guard(&g,UINT32_MAX-75);
    assert(tap(30,233,233)==HT_TOUCH_NONE);
    assert(tap(500,233,233)==HT_TOUCH_TAP);
    for(int i=0;i<20000;i++) {
        clear(); ht_gesture_begin(&g,233,233,1000,0);
        int dx=(int)(next()%401)-200,dy=(int)(next()%401)-200;
        if(dx*dx+dy*dy<144) dx=25;
        ht_gesture_move(&g,233+dx,233+dy);
        if(i%3==0) ht_gesture_cancel(&g);
        assert(ht_gesture_end(&g,233,233,1080)==HT_TOUCH_NONE);
        assert(tap(1200,233,233)==HT_TOUCH_TAP);
    }
    puts("gestures: PASS (single release, slow tap, voice guard, holds, wrap + 20,000 drag/cancel traces)");
}
