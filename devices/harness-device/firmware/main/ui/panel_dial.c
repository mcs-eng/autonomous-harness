/*
 * The round dial's panel: CO5300 AMOLED, 466x466, over QSPI.
 *
 * Lifted out of display.c when the square board arrived, and deliberately UNCHANGED in the lifting —
 * every register, every offset and every comment below is what shipped, because the dial had to keep
 * behaving identically through the split. What display.c kept is everything that was never about this
 * controller: the LVGL lock, the pool, the tick, the task, the idle blank.
 *
 * The twin is panel_pro.c. See panel.h for the contract they share.
 */
#include "panel.h"

#include "board.h"
#include "board_pins.h"
#include "display.h"
#include "ui_perf.h"

#include "driver/spi_master.h"
#include "esp_heap_caps.h"
#include "esp_lcd_co5300.h"
#include "esp_lcd_panel_io.h"
#include "esp_lcd_panel_ops.h"
#include "esp_log.h"

static const char *TAG = "panel_dial";

static esp_lcd_panel_handle_t    s_panel;
static esp_lcd_panel_io_handle_t s_io;   // kept so brightness (DCS 0x51) can be re-sent at runtime
static lv_display_t             *s_disp;
static uint8_t                  *s_buf1;
static uint8_t                  *s_buf2;

// LVGL draw buffers in internal DMA RAM: each is about 1/16 screen,
// double-buffered for about 1/8 screen total.
// NOTE: in LVGL v9, sizeof(lv_color_t) is NOT the pixel byte size — for RGB565
// each pixel is 2 bytes regardless. Size buffers explicitly by bytes-per-pixel.
#define DRAW_LINES   (BSP_LCD_V_RES / 16)   // smaller so both draw buffers fit in internal DMA RAM
#define BYTES_PER_PX (BSP_LCD_BIT_PER_PIXEL / 8)   // RGB565 -> 2

int panel_draw_lines(void) { return DRAW_LINES; }

// CO5300 power-on / init register sequence, taken verbatim from the panel
// vendor's reference BSP. The leading 0xFE/0x19/0x1C block is what was missing
// before — without it the panel never lights up.
static const co5300_lcd_init_cmd_t s_co5300_init_cmds[] = {
    {0xFE, (uint8_t[]){0x20}, 1, 0},
    {0x19, (uint8_t[]){0x10}, 1, 0},
    {0x1C, (uint8_t[]){0xA0}, 1, 0},
    {0xFE, (uint8_t[]){0x00}, 1, 0},
    {0xC4, (uint8_t[]){0x80}, 1, 0},
    {0x3A, (uint8_t[]){0x55}, 1, 0},   // 16bpp RGB565
    {0x35, (uint8_t[]){0x00}, 1, 0},
    {0x53, (uint8_t[]){0x20}, 1, 0},
    {0x51, (uint8_t[]){0xFF}, 1, 0},   // panel at native max — perceived brightness is dimmed in software (ui_set_brightness overlay)
    {0x63, (uint8_t[]){0xFF}, 1, 0},
    {0x2A, (uint8_t[]){0x00, 0x06, 0x01, 0xD7}, 4, 0},   // col 6..471
    {0x2B, (uint8_t[]){0x00, 0x00, 0x01, 0xD1}, 4, 600}, // row 0..465
    {0x11, NULL, 0, 600},              // sleep out
    {0x29, NULL, 0, 0},                // display on
};

// esp_lcd "color trans done" → tell LVGL the flush finished. Uses the global
// display handle (the callback fires only after s_disp is created and rendering
// has started, so it is always valid by then).
static bool on_color_done(esp_lcd_panel_io_handle_t io, esp_lcd_panel_io_event_data_t *e, void *ctx)
{
    ui_perf_flush_done();
    if (s_disp) lv_display_flush_ready(s_disp);
    return false;
}

// LVGL flush callback → push the rendered area to the CO5300. The SW renderer already emits big-endian
// RGB565 (display color format = RGB565_SWAPPED), so no per-pixel swap here — just DMA the area out.
static void lvgl_flush(lv_display_t *disp, const lv_area_t *area, uint8_t *px)
{
    // Asleep: the panel is off — don't push pixels (events still update the offscreen tree and are
    // shown on wake). Ack immediately so LVGL doesn't block waiting for the (skipped) DMA done.
    if (display_is_asleep()) { lv_display_flush_ready(disp); return; }
    ui_perf_flush((size_t)(area->x2-area->x1+1)*(area->y2-area->y1+1)*2);
    esp_lcd_panel_draw_bitmap(s_panel, area->x1, area->y1, area->x2 + 1, area->y2 + 1, px);
}

// CO5300 addresses pixels in 2px units, so partial-update areas must start on an
// even coordinate and end on an odd one (matches the vendor BSP's rounder).
static void rounder_cb(lv_event_t *e)
{
    lv_area_t *area = lv_event_get_param(e);
    area->x1 = (area->x1 >> 1) << 1;
    area->y1 = (area->y1 >> 1) << 1;
    area->x2 = ((area->x2 >> 1) << 1) + 1;
    area->y2 = ((area->y2 >> 1) << 1) + 1;
}

esp_err_t panel_bringup(void)
{
    // QSPI bus + IO using the CO5300 driver's config macros (4 data lines).
    const spi_bus_config_t bus = CO5300_PANEL_BUS_QSPI_CONFIG(
        BSP_LCD_QSPI_SCLK, BSP_LCD_QSPI_D0, BSP_LCD_QSPI_D1, BSP_LCD_QSPI_D2, BSP_LCD_QSPI_D3,
        BSP_LCD_H_RES * BSP_LCD_V_RES * BYTES_PER_PX);
    ESP_ERROR_CHECK(spi_bus_initialize(SPI2_HOST, &bus, SPI_DMA_CH_AUTO));

    esp_lcd_panel_io_handle_t io;
    esp_lcd_panel_io_spi_config_t io_cfg = CO5300_PANEL_IO_QSPI_CONFIG(BSP_LCD_QSPI_CS, on_color_done, NULL);
    io_cfg.trans_queue_depth = 10;
    ESP_ERROR_CHECK(esp_lcd_new_panel_io_spi(SPI2_HOST, &io_cfg, &io));
    s_io = io;   // stash for display_set_brightness()

    co5300_vendor_config_t vendor = {
        .init_cmds = s_co5300_init_cmds,
        .init_cmds_size = sizeof(s_co5300_init_cmds) / sizeof(s_co5300_init_cmds[0]),
        .flags = { .use_qspi_interface = 1 },
    };
    esp_lcd_panel_dev_config_t pcfg = {
        .reset_gpio_num = board()->lcd_rst,   // differs between the two dials — see board.h
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = BSP_LCD_BIT_PER_PIXEL,
        .vendor_config = &vendor,
    };
    ESP_ERROR_CHECK(esp_lcd_new_panel_co5300(io, &pcfg, &s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_set_gap(s_panel, 0x06, 0));  // 6px column offset
    ESP_ERROR_CHECK(esp_lcd_panel_reset(s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_init(s_panel));
    ESP_ERROR_CHECK(esp_lcd_panel_disp_on_off(s_panel, true));
    return ESP_OK;
}

// Re-send the CO5300 "Write Display Brightness" (DCS 0x51). 0x00 = dimmest, 0xFF = max. Safe to call
// any time after display_init(); no-op before the panel IO exists.
void panel_set_brightness(uint8_t level)
{
    if (!s_io) return;
    esp_lcd_panel_io_tx_param(s_io, 0x51, (uint8_t[]){ level }, 1);
}

esp_err_t panel_attach(int draw_lines, lv_display_t **out_display)
{
    // Draw buffers in INTERNAL DMA RAM (not PSRAM): the LCD flush reads these over QSPI DMA, and
    // sharing the octal PSRAM with the CPU-written audio record buffer stalled the flush DMA →
    // LVGL hung in wait_for_flushing → watchdog. Internal DMA RAM has no such contention.
    // `draw_lines` is small in the OTA boot mode so the internal RAM freed goes to the big WiFi RX buffers.
    size_t buf_bytes = BSP_LCD_H_RES * draw_lines * BYTES_PER_PX;
    s_buf1 = heap_caps_malloc(buf_bytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    s_buf2 = heap_caps_malloc(buf_bytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    if (!s_buf1 || !s_buf2) ESP_LOGE(TAG, "draw buffer alloc failed");
    ESP_LOGI(TAG, "draw buffers %u B x2 (internal); free internal: %u",
             (unsigned)buf_bytes, (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));

    s_disp = lv_display_create(BSP_LCD_H_RES, BSP_LCD_V_RES);
    lv_display_set_flush_cb(s_disp, lvgl_flush);
    // Render directly in the panel's byte order (big-endian RGB565). The CO5300 wants byte-swapped
    // RGB565; letting the SW renderer emit it saves a per-pixel CPU swap on every flush (a big win for
    // scroll/pan smoothness — that loop ran over the whole moving region each frame).
    lv_display_set_color_format(s_disp, LV_COLOR_FORMAT_RGB565_SWAPPED);
    lv_display_set_buffers(s_disp, s_buf1, s_buf2, buf_bytes, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_add_event_cb(s_disp, rounder_cb, LV_EVENT_INVALIDATE_AREA, NULL);

    if (out_display) *out_display = s_disp;
    return ESP_OK;
}

// The AMOLED's own power. There is no backlight on this board — the pixels are the light — so the idle
// blank is the panel itself going off.
void panel_power(bool on)
{
    if (s_panel) esp_lcd_panel_disp_on_off(s_panel, on);
}
