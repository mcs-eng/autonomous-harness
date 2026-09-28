/*
 * Which board this is, on a board where the answer is already known.
 *
 * The dial's board.c PROBES: two dials ship from one image and they differ in things the I2C bus can be
 * asked about, so it asks. Here there is nothing to ask. The Pro is a different SoC, so an image built
 * for it cannot be running on anything else — `board_detect()` has no work to do and the table below is
 * a constant.
 *
 * It exists all the same, rather than being #ifdef'd away at the five call sites that read it, because
 * those five are shared code (display.c, touch.c, power.c, ptt.c, cable_client.c) and a constant is
 * cheaper than a branch in each of them. `hello.hw` on the cable carries `name`, so the daemon and its
 * logs can tell a Pro from a dial without a protocol change.
 */
#include "board.h"
#include "board_pins.h"

#include "esp_log.h"

static const board_t s_pro = {
    .name = "harness-pro",
    .lcd_rst = BSP_LCD_RST,
    .touch_rst = BSP_TOUCH_RST,
    .touch = TOUCH_GT911,
    /* The GT911 reports panel-aligned on this board — confirmed on the glass: a touch on the top-left
     * corner mark moves the cursor to the top-left corner. */
    .touch_mirror = false,
    /* An IP5306, not an AXP2101. It answers battery percentage and charge state the same way as far as
     * the UI is concerned, which is what this flag gates. */
    .has_pmic = true,
};

void board_detect(void)
{
    ESP_LOGI("board", "%s", board_describe());
}

const board_t *board(void) { return &s_pro; }

const char *board_describe(void)
{
    return "board=harness-pro touch=gt911 pmic=ip5306 lcd=st7703/720x720";
}

/*
 * Never. There is no button this could read.
 *
 * The Pro's only switch is its power button, and pressing it is how the board got here — at the moment
 * app_main asks this question the button is, by construction, still down. Reading it would factory-reset
 * the device on every single power-on. A reset gesture for this board has to be something else (a touch
 * held through boot, say) and is not invented here.
 */
bool board_factory_reset_requested(void) { return false; }
