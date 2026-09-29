"""Exercise production brightness loading, controls, and persistence conversions."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

here = Path(__file__).resolve().parent
source = Path(os.environ.get('UI_SOURCE', here / '../main/ui/habitat/ui_habitat.c')).read_text()

def function(name, text=source):
    match = re.search(r'^[^\n]*\b' + name + r'\([^;]*?\)\n\{.*?^\}', text, re.M | re.S)
    assert match, name
    return match.group(0)

def brightness_case(name):
    match = re.search(r'    case A_BRIGHT:.*?\bbreak;', function(name), re.S)
    assert match, name
    return match.group(0)

load = re.search(r'    s\.brightness = [^;]*config_load_brightness\(\)[^;]*;', function('ui_init')).group(0)
code = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include "theme.h"
static struct { int brightness; } s;
typedef struct { int kind, value; } action_t;
enum { A_BRIGHT };
static action_t pending;
static uint8_t saved;
static uint8_t config_load_brightness(void) { return saved; }
static void config_save_brightness(uint8_t value) { saved=value; }
static void display_lock(void) {}
static void display_unlock(void) {}
static void change(void) {}
static bool queue(action_t a) { pending=a; return true; }
'''
code += function('ui_set_brightness') + '\n'
code += function('ht_rgb', (here / '../main/ui/habitat/terminal.c').read_text()) + '\n'
code += function('color') + '\n'
code += 'static void load_saved(void) {\n' + load + '\n}\n'
code += 'static void tap_brightness(void) { action_t a={.kind=A_BRIGHT}; switch(a.kind) {\n' + brightness_case('dispatch') + '\n} }\n'
code += 'static void persist(void) { action_t a=pending; switch(a.kind) {\n' + brightness_case('worker') + '\n} }\n'
code += r'''
int main(void) {
    // The factory byte 0x99 is 60%. Two presses used to produce 85%, then
    // 110%, whose persisted byte wrapped back to a nearly dark display.
    saved=0x99; load_saved(); assert(s.brightness==60);
    tap_brightness(); tap_brightness();
    if (s.brightness>100) {
        fprintf(stderr,"Brightness escaped its range: %d%%\n",s.brightness);
        return 1;
    }
    int previous=-1;
    for(int level=0;level<=255;level++) {
        saved=(uint8_t)level; load_saved();
        int loaded=s.brightness;
        ui_set_brightness((uint8_t)level);
        assert(s.brightness==loaded && loaded>=previous && loaded<=100);
        previous=loaded;
        for(int step=0;step<8;step++) {
            int before=s.brightness;
            tap_brightness();
            int chosen=s.brightness;
            assert(chosen>=25 && chosen<=100 && chosen%25==0);
            assert(before==100 ? chosen==25 : chosen>before);
            assert(pending.value==chosen);
            persist(); load_saved();
            assert(s.brightness==chosen); // Reboot cannot change the selected step.
            ui_set_brightness(saved); assert(s.brightness==chosen);
        }
    }
    for(int percent=0;percent<=100;percent++) {
        s.brightness=percent;
        uint16_t canvas=color(HT_THEME_CANVAS);
        unsigned r=canvas>>11, g=(canvas>>5)&63, b=canvas&31;
        r=(r<<3)|(r>>2); g=(g<<2)|(g>>4); b=(b<<3)|(b>>2);
        assert(r==g && g==b && r<=24);
        if(percent==25)assert(r==8);
        if(percent==60)assert(r==16);
        if(percent==100)assert(r==24 && color(HT_THEME_TEXT)==ht_rgb(HT_THEME_TEXT));
    }
    puts("Brightness: 256 stored levels, 2048 control/save/reload cycles; bounded, monotonic, exact presets and neutral canvas at all 101 percentages PASS");
}
'''
with tempfile.TemporaryDirectory(prefix='harness-brightness-') as directory:
    out=Path(directory)
    (out/'test.c').write_text(code)
    subprocess.run(['cc','-std=c11','-Wall','-Wextra','-Werror','-O1','-g',
        '-fsanitize='+os.environ.get('SANITIZERS','undefined,bounds'),
        '-I',str(here / '../main/ui/habitat'),str(out/'test.c'),'-o',str(out/'test')],check=True)
    subprocess.run([str(out/'test')],check=True)
