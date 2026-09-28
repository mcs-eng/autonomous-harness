/*
 * Harness Pro panel: ST7703I, 720x720, MIPI-DSI, two lanes at 480 Mbps.
 *
 * The dial's panel and this one differ in kind, not degree, and the difference decides the shape of this
 * file. The dial partial-renders into two small buffers in internal DMA RAM and pushes them over QSPI
 * (ui/display.c). A DPI panel is scanned out continuously by the DSI peripheral from a framebuffer in
 * PSRAM, so LVGL renders a WHOLE screen into a spare buffer and the flush is a pointer swap — no pixels
 * move. That is why this uses LV_DISPLAY_RENDER_MODE_FULL with the panel's own two framebuffers rather
 * than draw buffers of our own: handing LVGL the memory the panel already scans is what makes the swap
 * free, and it is also what makes it tear-free, because the swap happens between refreshes.
 *
 * Everything the vendor BSP would have carried — the ST7703's power-on register sequence and this
 * panel's DSI timings — comes from waveshare/esp_lcd_st7703 instead. The two config macros below are the
 * whole of it: 38 MHz pixel clock, porches 50/20/50 by 20/4/20, and the init commands inside the driver.
 */
#include "panel.h"

#include "board_pins.h"
#include "display.h"

#include "driver/gpio.h"
#include "driver/ledc.h"
#include "esp_check.h"
#include "esp_lcd_mipi_dsi.h"
#include "esp_lcd_panel_ops.h"
#include "esp_lcd_panel_vendor.h"
#include "esp_lcd_st7703.h"
#include "esp_ldo_regulator.h"
#include "esp_heap_caps.h"
#include "esp_log.h"

static const char *TAG = "panel_pro";

#define BL_TIMER   LEDC_TIMER_0
#define BL_CHANNEL LEDC_CHANNEL_0
#define BL_MAX_DUTY ((1 << BSP_LCD_BL_RES_BITS) - 1)

static esp_lcd_panel_handle_t   s_panel;
static esp_lcd_panel_io_handle_t s_io;
static esp_lcd_dsi_bus_handle_t s_bus;
static esp_ldo_channel_handle_t s_phy_pwr;
static lv_display_t            *s_disp;

/*
 * Backlight. An AP3032 boost drives the LED string and its feedback pin is what this PWM moves, so the
 * duty is INVERTED — more duty is dimmer. The invert is done by the LEDC peripheral rather than by
 * arithmetic here, so the number in the register reads the same way the number in the code does.
 *
 * This is real dimming. The dial has no brightness control in hardware and fakes it with a translucent
 * overlay over the whole UI (ui_screens.c), which costs a composited layer on every frame; this board
 * does not need that, and at M2 the overlay should be switched off for it rather than stacked on top.
 */
static void backlight_init(void)
{
    const gpio_config_t en = {
        .pin_bit_mask = 1ULL << BSP_LCD_BL_EN,
        /* INPUT_OUTPUT, not OUTPUT: a plain output pin reads back 0 whatever it is driving, which made
         * the diagnostic line below report BL_EN=0 on a backlight that was on. */
        .mode = GPIO_MODE_INPUT_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&en);
    gpio_set_level(BSP_LCD_BL_EN, 1);

    const ledc_timer_config_t timer = {
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .duty_resolution = BSP_LCD_BL_RES_BITS,
        .timer_num = BL_TIMER,
        .freq_hz = BSP_LCD_BL_FREQ_HZ,
        .clk_cfg = LEDC_AUTO_CLK,
    };
    ledc_timer_config(&timer);

    const ledc_channel_config_t ch = {
        .gpio_num = BSP_LCD_BL_PWM,
        .speed_mode = LEDC_LOW_SPEED_MODE,
        .channel = BL_CHANNEL,
        .timer_sel = BL_TIMER,
        .duty = 0,
        .hpoint = 0,
        .flags.output_invert = true,
    };
    ledc_channel_config(&ch);
}

/* 0..255 to match the dial's DCS register range, so one UI setting drives both boards. */
void panel_set_brightness(uint8_t level)
{
    ledc_set_duty(LEDC_LOW_SPEED_MODE, BL_CHANNEL, (uint32_t)BL_MAX_DUTY * level / 255u);
    ledc_update_duty(LEDC_LOW_SPEED_MODE, BL_CHANNEL);
}

/* The idle blank. This panel is backlit, so "off" is the backlight rather than the pixels — cutting the
 * DSI stream instead would take a full re-init to come back from, and the dial's wake is instant. */
static uint8_t s_level_before_blank = 255;
void panel_power(bool on)
{
    if (!on) {
        s_level_before_blank = (uint8_t)(ledc_get_duty(LEDC_LOW_SPEED_MODE, BL_CHANNEL) * 255u / BL_MAX_DUTY);
        panel_set_brightness(0);
        gpio_set_level(BSP_LCD_BL_EN, 0);
    } else {
        gpio_set_level(BSP_LCD_BL_EN, 1);
        panel_set_brightness(s_level_before_blank);
    }
}

/* A twelfth of the face. Two buffers of it are 169 KiB of the ~525 KiB internal RAM this board starts
 * with, which leaves room for the audio path that joins later. */
#define DRAW_LINES 60
int panel_draw_lines(void) { return DRAW_LINES; }

static esp_err_t pro_panel_self_test(bool on)
{
    if (!s_panel) return ESP_ERR_INVALID_STATE;
    esp_err_t err = esp_lcd_dpi_panel_set_pattern(s_panel, on ? MIPI_DSI_PATTERN_BAR_VERTICAL
                                                              : MIPI_DSI_PATTERN_NONE);
    /* Logged rather than returned quietly: this is the one call whose failure would leave a blank
     * screen looking exactly like a panel that is not there at all. */
    if (err != ESP_OK) ESP_LOGE(TAG, "pattern %s refused: %s", on ? "on" : "off", esp_err_to_name(err));
    return err;
}

/* Read back what the backlight is actually being driven with, so a brightness bug and a video bug can
 * be told apart from the log instead of by eye. */
static void pro_panel_backlight_debug(void)
{
    ESP_LOGI(TAG, "backlight · BL_EN(GPIO%d)=%d · PWM GPIO%d · duty=%lu/%d · inverted",
             BSP_LCD_BL_EN, gpio_get_level(BSP_LCD_BL_EN), BSP_LCD_BL_PWM,
             (unsigned long)ledc_get_duty(LEDC_LOW_SPEED_MODE, BL_CHANNEL), BL_MAX_DUTY);
}

/*
 * The copy into the framebuffer has finished, so LVGL may reuse the draw buffer.
 *
 * ON_COLOR_TRANS_DONE, NOT ON_REFRESH_DONE, and the difference is why the first version of this file
 * drew nothing at all. `on_refresh_done` reports that the panel finished SCANNING a frame, which is
 * what a buffer-switch scheme waits for; `on_color_trans_done` reports that the pixels asked for by
 * draw_bitmap have actually landed, which is what a copying flush waits for. Registering only the
 * former left every flush un-acknowledged: LVGL rendered one frame, called flush, and waited for a
 * release that never came — a blank screen with no error anywhere. (Espressif's own LVGL adapter picks
 * between the two on exactly this distinction; see its v9 bridge.)
 */
static bool on_color_trans_done(esp_lcd_panel_handle_t panel, esp_lcd_dpi_panel_event_data_t *edata, void *ctx)
{
    lv_display_t *disp = (lv_display_t *)ctx;
    lv_display_flush_ready(disp);
    return false;
}

static void flush_cb(lv_display_t *disp, const lv_area_t *area, uint8_t *px_map)
{
    /* Blanked: the backlight is off, so nothing would be seen. Ack at once rather than making LVGL wait
     * on a copy whose result nobody can look at — the same rule panel_dial.c follows. */
    if (display_is_asleep()) { lv_display_flush_ready(disp); return; }
    /* Partial render: LVGL has drawn one band into its own buffer and this copies that band into the
     * framebuffer the panel scans. The copy is DMA2D's, not the CPU's (`use_dma2d` in the DPI config). */
    esp_lcd_panel_draw_bitmap(s_panel, area->x1, area->y1, area->x2 + 1, area->y2 + 1, px_map);
    /* flush_ready comes from on_color_trans_done, not from here. */
}

esp_err_t panel_bringup(void)
{

    backlight_init();   /* enable the boost early; duty stays 0 until there is something to show */

    /* The DSI PHY runs off an internal LDO, and it has to be up before the bus is created. Getting this
     * wrong does not fail loudly — the bus is created and the panel simply never lights. */
    const esp_ldo_channel_config_t ldo = {
        .chan_id = BSP_LCD_DSI_PHY_LDO_CHAN,
        .voltage_mv = BSP_LCD_DSI_PHY_LDO_MV,
    };
    ESP_RETURN_ON_ERROR(esp_ldo_acquire_channel(&ldo, &s_phy_pwr), TAG, "DSI PHY LDO (VO%d) refused",
                        BSP_LCD_DSI_PHY_LDO_CHAN);

    esp_lcd_dsi_bus_config_t bus = ST7703_PANEL_BUS_DSI_2CH_CONFIG();
    ESP_RETURN_ON_ERROR(esp_lcd_new_dsi_bus(&bus, &s_bus), TAG, "dsi bus");

    esp_lcd_dbi_io_config_t dbi = ST7703_PANEL_IO_DBI_CONFIG();
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_io_dbi(s_bus, &dbi, &s_io), TAG, "dbi io");

    esp_lcd_dpi_panel_config_t dpi = ST7703_720_720_PANEL_60HZ_DPI_CONFIG(LCD_COLOR_PIXEL_FORMAT_RGB565);
    /* ONE framebuffer. LVGL renders into small buffers of its own and each flush copies a band into
     * this one — the same partial-render shape the dial uses, which is why display.c can end up owning
     * both boards rather than branching. Handing LVGL the panel's own framebuffers instead would save
     * the copy, but it needs the buffer-switch protocol and its own tear handling; that is an
     * optimisation for later, on a panel that is already known to work. */
    dpi.num_fbs = 1;

    const st7703_vendor_config_t vendor = {
        .mipi_config = { .dsi_bus = s_bus, .dpi_config = &dpi },
    };
    const esp_lcd_panel_dev_config_t dev = {
        .reset_gpio_num = BSP_LCD_RST,
        .rgb_ele_order = LCD_RGB_ELEMENT_ORDER_RGB,
        .bits_per_pixel = BSP_LCD_BIT_PER_PIXEL,
        .vendor_config = (void *)&vendor,
    };
    ESP_RETURN_ON_ERROR(esp_lcd_new_panel_st7703(s_io, &dev, &s_panel), TAG, "st7703");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_reset(s_panel), TAG, "panel reset");
    ESP_RETURN_ON_ERROR(esp_lcd_panel_init(s_panel), TAG, "panel init");
    return ESP_OK;
}

esp_err_t panel_attach(int draw_lines, lv_display_t **out_display)
{
    esp_err_t err;

    /* Draw buffers in INTERNAL DMA RAM, for the reason display.c gives on the dial: the flush reads
     * these while the CPU writes the next band, and putting both in the same external memory makes the
     * two contend. See panel_draw_lines() for how tall they are and why. */
    /* 64-BYTE ALIGNED, AND THE SIZE ROUNDED UP TO MATCH. That is the L2 cache line, and the PPA reaches
     * these buffers through the cache: a buffer that starts mid-line, or ends mid-line, cannot be
     * invalidated without dragging a neighbour's bytes in or out with it. LVGL is told the same number
     * through CONFIG_LV_DRAW_BUF_ALIGN, and its PPA unit refuses to compile if the two disagree. */
    const size_t line = 64;
    size_t buf_bytes = BSP_LCD_H_RES * draw_lines * (BSP_LCD_BIT_PER_PIXEL / 8);
    buf_bytes = (buf_bytes + line - 1) / line * line;
    uint8_t *buf1 = heap_caps_aligned_alloc(line, buf_bytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    uint8_t *buf2 = heap_caps_aligned_alloc(line, buf_bytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA);
    if (!buf1 || !buf2) {
        ESP_LOGE(TAG, "draw buffers (%u B x2) would not fit in internal DMA RAM", (unsigned)buf_bytes);
        return ESP_ERR_NO_MEM;
    }

    s_disp = lv_display_create(BSP_LCD_H_RES, BSP_LCD_V_RES);
    if (!s_disp) return ESP_ERR_NO_MEM;
    /* Plain RGB565, NOT the dial's RGB565_SWAPPED: that swap exists because the CO5300 is fed over QSPI
     * in the panel's byte order, and DSI is not. Getting it wrong here is not subtle — the whole screen
     * comes out in the wrong hue. */
    lv_display_set_color_format(s_disp, LV_COLOR_FORMAT_RGB565);
    lv_display_set_buffers(s_disp, buf1, buf2, buf_bytes, LV_DISPLAY_RENDER_MODE_PARTIAL);
    lv_display_set_flush_cb(s_disp, flush_cb);

    const esp_lcd_dpi_panel_event_callbacks_t cbs = { .on_color_trans_done = on_color_trans_done };
    err = esp_lcd_dpi_panel_register_event_callbacks(s_panel, &cbs, s_disp);
    /* Without this LVGL never gets its buffer back and the screen stays on frame one. Loud, not a warning. */
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "flush-done callback refused (%s) — LVGL would stall after one frame",
                 esp_err_to_name(err));
        return err;
    }

    /*
     * FULL BRIGHTNESS, HERE, BECAUSE NOTHING ELSE WILL DO IT.
     *
     * The dial comes up lit without anyone asking: the last entries of its CO5300 power-on sequence are
     * {0x51, 0xFF} — panel at native maximum — and ui_set_brightness() then dims in SOFTWARE, with a
     * translucent layer over the whole UI. So app_main never calls display_set_brightness() on either
     * board, and a Pro whose backlight was left at the duty backlight_init() set (zero) drew a perfect,
     * invisible screen: the daemon paired, the log said `ui: face: overview`, and the glass was black.
     *
     * Matching the dial means coming up at maximum and letting the UI's own overlay do the dimming.
     * Using this PWM for the user's brightness setting instead — which is what the hardware is for — is
     * a change to ui_screens.c, not to this line.
     */
    panel_set_brightness(255);

    ESP_LOGI(TAG, "panel up · %dx%d · %d lanes @ %d Mbps · framebuffer %u KiB in PSRAM · draw buffers %u KiB x2",
             BSP_LCD_H_RES, BSP_LCD_V_RES, BSP_LCD_DSI_LANES, BSP_LCD_DSI_LANE_MBPS,
             (unsigned)(BSP_LCD_H_RES * BSP_LCD_V_RES * 2 / 1024), (unsigned)(buf_bytes / 1024));

    if (out_display) *out_display = s_disp;
    return ESP_OK;
}
