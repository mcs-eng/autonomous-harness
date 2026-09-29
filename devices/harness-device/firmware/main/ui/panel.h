// The panel, as the rest of the firmware needs to know it.
//
// ONE INTERFACE, TWO IMPLEMENTATIONS, CHOSEN BY THE BUILD — panel_dial.c for the round CO5300 over QSPI,
// panel_pro.c for the square ST7703 over MIPI-DSI (main/CMakeLists.txt picks by IDF_TARGET). Everything
// above this line is the same on both boards and lives in display.c: the LVGL lock, its memory pool, the
// tick, the handler task, the idle blank, the heartbeat.
//
// The two calls are separate rather than one `panel_open()` because the order matters and differs from
// what a single call could express: the bus and the controller come up BEFORE lv_init(), and the LVGL
// display is attached after it. That is the order the dial has always used and there was no reason to
// change it for the sake of a tidier signature.
#pragma once

#include <stdint.h>

#include "esp_err.h"
#include "lvgl.h"

// Bus + controller. No LVGL involved; safe to call before lv_init().
esp_err_t panel_bringup(void);

// Allocate draw buffers `draw_lines` tall, create the LVGL display and register the flush for it.
// Call after lv_init() and after the LVGL memory pool exists.
esp_err_t panel_attach(int draw_lines, lv_display_t **out_display);

// 0 = dimmest, 255 = brightest. Applied live; a no-op before panel_bringup().
// The dial re-sends a DCS register; the Pro moves a real PWM. Same range either way.
void panel_set_brightness(uint8_t level);

// The panel's own power, for the idle blank. Not the backlight: on the dial there is no backlight.
void panel_power(bool on);

// How tall one draw buffer should be on this board — a board decides this, because it follows from the
// resolution and from how much internal DMA RAM the rest of that board's firmware needs.
int panel_draw_lines(void);
