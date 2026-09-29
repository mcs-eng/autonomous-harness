#include "../main/ui/habitat/workspace.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void)
{
    ht_workspace_t w={0};
    ht_workspace_touch(&w,1,4,233,410,100);
    assert(w.touching && w.choice==1);
    assert(ht_workspace_release(&w,233,410,0,175)==-1 && !w.touching);
    ht_workspace_touch(&w,1,4,233,410,200);
    assert(ht_workspace_move(&w,176,410,2,250) && w.choice==2);
    assert(ht_workspace_move(&w,110,410,2,275) && w.choice==3);
    assert(ht_workspace_release(&w,110,410,2,300)==3);
    assert(ht_workspace_release(&w,110,410,2,301)==-1); // one navigation per contact
    ht_workspace_touch(&w,1,4,233,410,400);
    ht_workspace_move(&w,160,410,2,450);
    assert(ht_workspace_release(&w,233,410,2,500)==-1); // slide back to stay
    ht_workspace_touch(&w,0,4,233,410,600);
    assert(ht_workspace_release(&w,450,410,2,700)==-1); // edge clamps; never wraps
    ht_workspace_touch(&w,1,4,233,410,800);
    assert(ht_workspace_release(&w,233,390,1,900)==-1 && !w.touching);
    ht_workspace_touch(&w,1,4,233,410,1000);
    ht_workspace_move(&w,220,380,1,1050);
    assert(ht_workspace_release(&w,100,400,2,1100)==-1); // vertical first stays cancelled
    ht_workspace_touch(&w,1,4,233,410,1200);
    ht_workspace_move(&w,160,410,2,1250);
    assert(ht_workspace_release(&w,160,340,2,1300)==-1); // lifting out of the strip cancels
    ht_workspace_touch(&w,1,4,233,410,1400);
    assert(ht_workspace_release(&w,160,410,2,1420)==-1); // sample glitch
    ht_workspace_touch(&w,1,4,233,410,1500);
    assert(ht_workspace_release(&w,160,410,2,6500)==-1); // missing release cannot navigate
    ht_workspace_touch(&w,1,4,233,410,UINT32_MAX-50);
    assert(ht_workspace_release(&w,160,410,2,50)==2); // timestamp wrap
    for (int count=1;count<=24;count++) for(int index=0;index<count;index++) {
        ht_workspace_touch(&w,index,count,233,410,100);
        ht_workspace_move(&w,0,410,2,150);
        assert(w.choice>=0 && w.choice<count);
        ht_workspace_cancel_touch(&w);
        assert(ht_workspace_release(&w,0,410,2,175)==-1);
    }
    ht_workspace_touch(&w,0,25,233,410,100); assert(!w.touching);
    ht_workspace_touch(&w,-1,4,233,410,100); assert(!w.touching);

    assert(!ht_workspace_request(&w,"",100));
    assert(ht_workspace_request(&w,"workspace-a",100));
    uint32_t serial=w.serial;
    assert(!ht_workspace_request(&w,"workspace-b",101));
    ht_workspace_touch(&w,1,4,233,410,150); assert(!w.touching);
    assert(!ht_workspace_selected(&w,"workspace-b"));
    assert(!ht_workspace_applied(&w,"workspace-a",99));
    assert(ht_workspace_selected(&w,"workspace-a"));
    assert(!ht_workspace_selected(&w,"workspace-a"));
    assert(!ht_workspace_refresh(&w,serial+1,12));
    assert(ht_workspace_refresh(&w,serial,12));
    assert(!ht_workspace_applied(&w,"workspace-b",13));
    assert(!ht_workspace_applied(&w,"workspace-a",12));
    assert(ht_workspace_applied(&w,"workspace-a",13));
    assert(w.phase==HT_WORKSPACE_READY);
    ht_workspace_cancel_request(&w);
    assert(!w.pending[0] && w.phase==HT_WORKSPACE_IDLE && w.serial==serial);
    assert(ht_workspace_request(&w,"workspace-b",UINT32_MAX-2000));
    assert(w.serial!=serial && !ht_workspace_tick(&w,5998));
    assert(ht_workspace_tick(&w,5999) && w.phase==HT_WORKSPACE_IDLE);
    assert(!ht_workspace_selected(&w,"workspace-b"));
    assert(!ht_workspace_applied(&w,"workspace-b",14));
    assert(ht_workspace_request(&w,"workspace-c",100));
    assert(ht_workspace_selected(&w,"workspace-c"));
    assert(ht_workspace_refresh(&w,w.serial,UINT32_MAX));
    assert(ht_workspace_applied(&w,"workspace-c",0));
    ht_workspace_cancel_request(&w);
    char long_id[65]; memset(long_id,'x',sizeof long_id); long_id[64]=0;
    assert(!ht_workspace_request(&w,long_id,100));
    long_id[63]=0; assert(ht_workspace_request(&w,long_id,100));
    puts("workspace: bounded preview, cancellation, single commit, exact tab/snapshot, deadlines and wraparound PASS");
}
