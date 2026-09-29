# Top-level ESP-IDF project file. ONE project, TWO boards.
#
#   dial  ESP32-S3R8 · 466x466 round AMOLED (CO5300, QSPI) · CST9217 or CST816S touch
#   pro   ESP32-P4   · 720x720 square LCD  (ST7703I, MIPI-DSI) · GT911 touch
#
# They share the cable protocol, the OTA path, the config store and the screens; they differ in the SoC,
# so the split is made at compile time by CONFIG_IDF_TARGET_* (main/board/board_pins.h) rather than by
# the runtime probe that tells the two DIALS apart (main/board/board.h).
#
# Requires ESP-IDF >= 5.5. Build either board through the Makefile at the repo root:
#
#   make dial-build   make dial-flash     # -B build.dial -D SDKCONFIG=sdkconfig.dial
#   make pro-build    make pro-flash      # -B build.pro  -D SDKCONFIG=sdkconfig.pro
#
# A bare `idf.py build` here still means the dial, so older muscle memory keeps working.
cmake_minimum_required(VERSION 3.16)

# ── Keep sdkconfig honest about sdkconfig.defaults ───────────────────────────────────────────────────
# ESP-IDF reads sdkconfig.defaults ONLY when creating sdkconfig. After that sdkconfig is authoritative and
# defaults are ignored outright — no merge, no warning. That is deliberate (so `idf.py menuconfig` edits
# survive), but it means the file we track states the intent while the file we gitignore decides the build.
#
# On 2026-07-30 that cost two weeks: commit 1f6c5be (2026-07-16) raised ESP_MAIN_TASK_STACK_SIZE to 10240,
# moved BSS to PSRAM and re-shaped the LVGL pool, but every build on a checkout whose sdkconfig predated it
# silently kept the old values. It surfaced as a broken build (a new font was referenced) and, worse, as
# published firmware that overflowed the main stack mid-OTA and could never update itself.
#
# So: stamp the hash of the defaults beside sdkconfig. When they disagree, delete sdkconfig and let IDF
# re-seed it. Day-to-day menuconfig still works; a pull that changes defaults re-applies automatically.
# A deliberate local tweak belongs in sdkconfig.defaults, where it is reviewable and reaches everyone.
#
# TWO BOARDS, TWO SDKCONFIGS. Each build passes its own (`idf.py -D SDKCONFIG=sdkconfig.pro`), so the
# stamp has to follow that file rather than assume the default name — one shared stamp would have each
# board's build delete the other board's config, every time, for ever. And the hash covers EVERY defaults
# file, not just the one this target reads: the alternative is a build that quietly keeps a stale config
# because the change happened to land in the other target's file.
if(DEFINED SDKCONFIG)
    get_filename_component(_sdkcfg "${SDKCONFIG}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_LIST_DIR}")
else()
    set(_sdkcfg "${CMAKE_CURRENT_LIST_DIR}/sdkconfig")
endif()
set(_stamp "${_sdkcfg}.defaults.stamp")
file(GLOB _defaults "${CMAKE_CURRENT_LIST_DIR}/sdkconfig.defaults" "${CMAKE_CURRENT_LIST_DIR}/sdkconfig.defaults.*")
list(REMOVE_ITEM _defaults "${_stamp}")
list(FILTER _defaults EXCLUDE REGEX "\\.stamp$")
list(SORT _defaults)
if(_defaults)
    set(_defaults_hash "")
    foreach(_f IN LISTS _defaults)
        file(SHA256 "${_f}" _one)
        string(APPEND _defaults_hash "${_one}")
    endforeach()
    string(SHA256 _defaults_hash "${_defaults_hash}")
    set(_prev_hash "")
    if(EXISTS "${_stamp}")
        file(READ "${_stamp}" _prev_hash)
        string(STRIP "${_prev_hash}" _prev_hash)
    endif()
    if(EXISTS "${_sdkcfg}" AND NOT _prev_hash STREQUAL _defaults_hash)
        message(WARNING
            "sdkconfig.defaults changed since ${_sdkcfg} was generated -- regenerating it.\n"
            "Any local `idf.py menuconfig` tweak not present in a sdkconfig.defaults file is being "
            "discarded; put it there if it should survive.\n"
            "Previous config saved as ${_sdkcfg}.superseded.")
        file(RENAME "${_sdkcfg}" "${_sdkcfg}.superseded")
    endif()
    file(WRITE "${_stamp}" "${_defaults_hash}")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)


# ── Make LVGL asserts speak ──────────────────────────────────────────────────────────────────────────
# LV_ASSERT_HANDLER is `while(1);` ("Halt by default") and LV_USE_ASSERT_MALLOC / _NULL are on, so any
# failed allocation or NULL inside LVGL spins the LVGL task forever: the screen freezes, the task watchdog
# prints a backtrace every 5s, and the rest of the firmware keeps running so the device looks alive but is
# not. LVGL logging was also off, so it died without a word — which is why several rounds of diagnosis only
# ever saw "stuck somewhere in the draw pipeline".
#
# CONFIG_LV_USE_LOG is now on (see sdkconfig): the assert prints its reason before halting. Overriding the
# handler itself to abort() was tried and abandoned — CMake eats the trailing semicolon of a compile
# definition, expanding the macro without a terminator and breaking lv_assert.h.
project(interns_commander)
