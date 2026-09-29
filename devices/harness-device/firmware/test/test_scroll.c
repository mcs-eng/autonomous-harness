#include "../main/ui/habitat/scroll.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

typedef struct { ht_scroll_phase_t phase; int dy, velocity; } report_t;
static report_t reports[256];
static int count;
static bool stalled;
static bool emit(ht_scroll_phase_t phase, int dy, int velocity, void *ctx)
{
    (void)ctx;
    if (stalled && phase == HT_SCROLL_MOVE) return false;
    assert(count < 256);
    reports[count++] = (report_t){phase, dy, velocity};
    return true;
}
static int travel(void)
{
    int result = 0;
    for (int i = 0; i < count; i++) result += reports[i].dy;
    return result;
}
static void begin(ht_scroll_t *g, bool reversed, uint32_t now)
{
    memset(g, 0, sizeof(*g)); count = 0; stalled = false;
    ht_scroll_begin(g, 200, 200, now, reversed, false, emit, NULL);
    assert(count == 1 && reports[0].phase == HT_SCROLL_DOWN);
}
int main(void)
{
    ht_scroll_t g;
    begin(&g, false, 0);
    ht_scroll_move(&g, 201, 205, 4);
    assert(!ht_scroll_end(&g, 201, 205, 8));
    assert(count == 2 && travel() == 0 && reports[1].velocity == 0);

    // Horizontal navigation can carry vertical jitter, but must not move the terminal.
    begin(&g, false, 0);
    ht_scroll_move(&g, 160, 208, 8);
    ht_scroll_move(&g, 100, 220, 16);
    assert(!ht_scroll_end(&g, 90, 221, 24));
    assert(count == 2 && travel() == 0);

    // Real scrolling leaves the device while the finger is DOWN, not only on release.
    begin(&g, false, 0);
    ht_scroll_move(&g, 202, 216, 8);
    assert(count == 2 && reports[1].phase == HT_SCROLL_MOVE && travel() == 16);
    ht_scroll_move(&g, 203, 238, 16);
    assert(ht_scroll_end(&g, 203, 241, 20));
    assert(reports[count - 1].phase == HT_SCROLL_UP && travel() == 41);
    assert(reports[count - 1].velocity > 0 && reports[count - 1].velocity <= 6000);

    // A slow drag below the 8px batch size still reports within the 16ms window.
    begin(&g, false, 0);
    ht_scroll_move(&g, 200, 214, 8);
    int before = count;
    ht_scroll_move(&g, 200, 217, 24);
    assert(count == before + 1 && reports[count - 1].dy == 3);
    ht_scroll_end(&g, 200, 217, 25);

    // Resting before lift cancels the throw; holding does not keep a stale velocity.
    begin(&g, false, 0);
    ht_scroll_move(&g, 200, 300, 16);
    for (int t = 32; t <= 208; t += 16) ht_scroll_move(&g, 200, 300, t);
    assert(ht_scroll_end(&g, 200, 300, 224));
    assert(reports[count - 1].velocity == 0 && travel() == 100);

    begin(&g, true, 0);
    ht_scroll_move(&g, 200, 250, 16);
    assert(ht_scroll_end(&g, 200, 256, 24));
    assert(travel() == -56 && reports[count - 1].velocity < 0);

    // Returning to the origin is still a scroll, never an accidental tap on Speak.
    begin(&g, false, 0);
    ht_scroll_move(&g, 200, 160, 16);
    assert(ht_scroll_end(&g, 200, 200, 32) && travel() == 0);

    // A full worker queue retains all movement, including the release remainder.
    begin(&g, false, 0);
    stalled = true;
    ht_scroll_move(&g, 200, 230, 16);
    ht_scroll_move(&g, 200, 260, 32);
    assert(count == 1);
    assert(ht_scroll_end(&g, 200, 263, 36));
    assert(count == 2 && travel() == 63 && reports[1].phase == HT_SCROLL_UP);

    begin(&g, false, 0);
    ht_scroll_move(&g, 200, 240, 16);
    ht_scroll_cancel(&g);
    assert(reports[count - 1].phase == HT_SCROLL_UP && reports[count - 1].velocity == 0);
    before = count;
    assert(!ht_scroll_end(&g, 200, 300, 32) && count == before);

    // Timer wrap at ~49 days and two readings at the same timestamp are valid.
    begin(&g, false, UINT32_MAX - 8);
    ht_scroll_move(&g, 200, 220, 8);
    assert(ht_scroll_end(&g, 200, 230, 8) && travel() == 30);
    assert(reports[count - 1].velocity <= 6000);
    // Several complete clockwise/counterclockwise turns cross all octants and the angle seam.
    for(int sign=-1;sign<=1;sign+=2) for(int reversed=0;reversed<2;reversed++) {
        memset(&g,0,sizeof(g)); count=0;
        ht_scroll_begin(&g,433,233,1000,reversed!=0,true,emit,NULL);
        for(int step=1;step<=96;step++) {
            double angle=sign*step*6.283185307179586/32;
            int x=233+(int)lround(200*cos(angle)),y=233+(int)lround(200*sin(angle));
            ht_scroll_move(&g,x,y,1000+step*20);
        }
        assert(ht_scroll_end(&g,433,233,2940));
        int expected=-sign*(reversed?-1:1)*1800;
        assert(abs(travel()-expected)<=2);
        assert(g.axis==3 && reports[count-1].velocity==0);
    }
    memset(&g,0,sizeof(g)); count=0;
    ht_scroll_begin(&g,433,233,1000,false,true,emit,NULL);
    assert(ht_scroll_end(&g,433,233,1080) && travel()==0); // rim tap never speaks
    memset(&g,0,sizeof(g)); count=0;
    ht_scroll_begin(&g,433,233,1000,false,true,emit,NULL);
    ht_scroll_move(&g,233,233,1010);
    assert(!g.live && ht_scroll_end(&g,33,233,1020)); // radial/invalid path cannot become a swipe
    assert(travel()==0 && reports[count-1].velocity==0);
    unsigned seed=1899;
    for(int trial=0;trial<6000;trial++) {
        memset(&g,0,sizeof(g)); count=0;
        ht_scroll_begin(&g,433,233,1000,false,true,emit,NULL);
        for(int step=0;step<12;step++) {
            seed=seed*1664525u+1013904223u; int x=(int)(seed%466);
            seed=seed*1664525u+1013904223u; int y=(int)(seed%466);
            ht_scroll_move(&g,x,y,1004+step*4);
        }
        assert(ht_scroll_end(&g,433,233,1060));
        int downs=0,ups=0;
        for(int j=0;j<count;j++) {
            downs+=reports[j].phase==HT_SCROLL_DOWN;
            ups+=reports[j].phase==HT_SCROLL_UP;
            assert(abs(reports[j].dy)<=2048);
        }
        assert(downs==1 && ups==1 && reports[count-1].velocity==0);
    }
    assert(ht_scroll_coast_ms(0)==0 && ht_scroll_coast_ms(39)==0);
    assert(ht_scroll_coast_ms(6000)>700 && ht_scroll_coast_ms(6000)<900);
    assert(ht_scroll_coast_ms(-6000)==ht_scroll_coast_ms(6000));
    puts("scroll: PASS (10 linear scenarios, full rim turns, reversal, seam, radial cancellation and brake window)");
}
