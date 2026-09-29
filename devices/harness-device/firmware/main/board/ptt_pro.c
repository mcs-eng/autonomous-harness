/*
 * The Pro's one button, doing the work the dial spreads over two.
 *
 * The dial has a BOOT button and, on one of the two variants, a PMIC power key (ptt.c). This board has a
 * single physical switch, so the same three meanings are told apart by how long it is held — and the
 * shortest one keeps the shortest gesture, because interrupting a running turn is the thing you reach
 * for in a hurry:
 *
 *   tap              → back / stop the turn      (the dial's BOOT press)
 *   hold ≥ 0.8 s     → screen off / on           (the dial's BOOT hold and PWR tap)
 *   hold ≥ 5 s       → power off                 (this board only — the dial has no off)
 *
 * The 5-second one exists because this board CAN switch itself off: PWR_HOLD released cuts the rail.
 * That is also why it is last and longest — it is the only irreversible one, and a UI that has frozen is
 * exactly when a person needs it, so it must not depend on anything above this task still working.
 *
 * The button is read on GPIO2 and the latch is held on GPIO1. They are separate pins by design
 * (HARDWARE.md §7), so reading the button here cannot disturb the latch.
 */
#include "ptt.h"

#include "board.h"
#include "board_pins.h"
#include "ui/display.h"
#include "ui/ui_screens.h"

#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "ptt";

#define POLL_MS            50    /* finer than the dial's 100ms: one button carries three meanings here */
#define HOLD_SCREEN_MS     800
#define HOLD_POWER_OFF_MS  5000

static void screen_toggle(const char *why)
{
    /* Hold the LVGL lock: display_sleep/wake touch LVGL timers and the panel, and normally run on the
     * LVGL task; the recursive mutex serialises this task's call with it. Same rule as ptt.c. */
    display_lock();
    if (display_is_asleep()) { ESP_LOGI(TAG, "%s → screen ON",  why); display_wake(); }
    else                     { ESP_LOGI(TAG, "%s → screen OFF", why); display_sleep(); }
    display_unlock();
}

/*
 * Cut the rail. Everything before the last line is courtesy — the screen going dark so the person sees
 * the press land, and a moment for any log or NVS write to drain. Releasing PWR_HOLD is not a request;
 * the board is off on the next instruction, so nothing may be left to do after it.
 */
static void power_off(void)
{
    ESP_LOGW(TAG, "power button held %ds → powering off", HOLD_POWER_OFF_MS / 1000);
    display_lock();
    display_sleep();
    display_unlock();
    vTaskDelay(pdMS_TO_TICKS(50));
    gpio_set_level(BSP_PWR_HOLD, 0);
    vTaskDelay(portMAX_DELAY);   /* not reached; the rail is gone */
}

static void ptt_task(void *arg)
{
    (void)arg;
    const gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << BSP_PWR_BTN,
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    gpio_config(&cfg);

    int prev = 1;                 /* active low: 1 = up, 0 = pressed */
    int64_t pressed_at = 0;
    bool screen_fired = false;

    for (;;) {
        const int now = gpio_get_level(BSP_PWR_BTN);

        if (prev == 1 && now == 0) {                      /* fresh press */
            /* The press edge acts at once, exactly as the dial's does — waiting to see whether it
             * becomes a hold would put a delay on the one gesture that is used in a hurry. */
            if (display_is_asleep()) { display_lock(); display_wake(); display_unlock(); }
            ESP_LOGI(TAG, "button press → back / stop turn");
            ui_boot_pressed();
            pressed_at = esp_timer_get_time();
            screen_fired = false;
        } else if (now == 0) {                            /* still down */
            const int64_t held_ms = (esp_timer_get_time() - pressed_at) / 1000;
            if (held_ms >= HOLD_POWER_OFF_MS) power_off();
            if (!screen_fired && held_ms >= HOLD_SCREEN_MS) {
                screen_fired = true;                      /* once per press */
                screen_toggle("button hold");
            }
        }
        prev = now;

        vTaskDelay(pdMS_TO_TICKS(POLL_MS));
    }
}

void ptt_start(void)
{
    xTaskCreate(ptt_task, "ptt", 4096, NULL, 5, NULL);
}
