/*
 * The round dial's touch controllers: CST9217 or CST816S, whichever answered the bus at boot.
 *
 * Lifted out of ui/touch.c when the square board arrived, and unchanged in the lifting. Two dials ship
 * from one image and differ here, which is why this still branches at RUNTIME on board()->touch — that
 * is a different axis from the compile-time one that chose this file over touch_gt911.c.
 */
#include "touch_ctrl.h"

#include "board.h"
#include "board_pins.h"
#include "board_i2c.h"
#include "ui_metrics.h"

#include "esp_lcd_touch_cst816s.h"
#include "esp_lcd_touch_cst9217.h"
#include "esp_log.h"

static const char *TAG = "touch";

const char *touch_ctrl_name(void)
{
    return board()->touch == TOUCH_CST816S ? "CST816S" : board()->touch == TOUCH_CST9217 ? "CST9217" : "no-touch";
}

bool touch_ctrl_open(esp_lcd_panel_io_handle_t *out_io, esp_lcd_touch_handle_t *out_tp)
{
    esp_lcd_panel_io_handle_t s_tp_io = NULL;
    esp_lcd_touch_handle_t s_tp = NULL;
    i2c_master_bus_handle_t bus = board_i2c_get();
    if (!bus) {
        ESP_LOGW(TAG, "shared i2c bus unavailable — touch disabled");
        return false;
    }
    const board_t *b = board();
    if (b->touch == TOUCH_NONE) {
        ESP_LOGW(TAG, "no touch controller answered on the bus — touch disabled");
        return false;
    }

    esp_lcd_panel_io_i2c_config_t io_cfg = b->touch == TOUCH_CST816S
        ? (esp_lcd_panel_io_i2c_config_t)ESP_LCD_TOUCH_IO_I2C_CST816S_CONFIG()
        : (esp_lcd_panel_io_i2c_config_t)ESP_LCD_TOUCH_IO_I2C_CST9217_CONFIG();
    io_cfg.scl_speed_hz = BSP_I2C_FREQ_HZ;
    if (esp_lcd_new_panel_io_i2c(bus, &io_cfg, &s_tp_io) != ESP_OK) {
        ESP_LOGW(TAG, "touch panel io failed — touch disabled");
        s_tp_io = NULL;
        return false;
    }

    esp_lcd_touch_config_t tp_cfg = {
        .x_max = UI_FACE_W,
        .y_max = UI_FACE_H,
        .rst_gpio_num = b->touch_rst,
        .int_gpio_num = BSP_TOUCH_INT,
        // The CST9217 is mounted 180° relative to the CO5300 on its board, so BOTH axes are reversed vs
        // the display (horizontal swipe and vertical scroll/taps). The CST816S reports panel-aligned
        // coordinates — measured: mirrored, a touch landed 180° from the finger.
        .flags = { .swap_xy = 0, .mirror_x = b->touch_mirror, .mirror_y = b->touch_mirror },
    };
    esp_err_t err = b->touch == TOUCH_CST816S
        ? esp_lcd_touch_new_i2c_cst816s(s_tp_io, &tp_cfg, &s_tp)
        : esp_lcd_touch_new_i2c_cst9217(s_tp_io, &tp_cfg, &s_tp);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "%s init failed (%s) — touch disabled", touch_ctrl_name(), esp_err_to_name(err));
        s_tp = NULL;
        esp_lcd_panel_io_del(s_tp_io);
        s_tp_io = NULL;
        return false;
    }
    *out_io = s_tp_io;
    *out_tp = s_tp;
    return true;
}
