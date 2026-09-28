# Harness Pro — display performance review

2026-09-27 · against `build.pro` at `0x320ce0` (3 286 131 B) · ESP32-P4 @ 400 MHz · LVGL 9.5.0 · IDF 5.5.4

Read-only review. No code changed. Everything below is measured off the built ELF, the sdkconfig, or
the source — not estimated.

---

## The short version

The other team's numbers are real and their diagnosis of *what* is slow is correct. 46–74 ms for a
single display update is what a full 720×720 software re-rasterisation costs on this chip, and this
firmware triggers one on almost every model change.

Where I differ is on *why*, and therefore on the fix:

> **The 22–190× is measuring the removal of work we are doing needlessly — not the removal of LVGL.**
> The baseline being compared against is our destroy-and-rebuild pattern, not LVGL used properly.
> Most of that gap is recoverable inside LVGL, and three of the switches that would recover it are
> simply turned off.

There is also a ceiling nobody has mentioned: `LV_DEF_REFR_PERIOD = 33`, so the display refreshes at
30 Hz. **Any update that completes under ~16 ms is invisible.** Going 46 ms → 3 ms removes every
dropped frame a person can perceive. Going 3 ms → 0.4 ms changes nothing they can see. The headline
190× is largely spent past the point where it matters.

---

## What was measured

### The image is mostly fonts

```
glyph_bitmap :  2 037 757 B   (19 symbols)
glyph_dsc    :     79 008 B   (19 symbols)
cmaps        :      3 216 B
─────────────────────────────
font data    :  2 119 981 B
whole image  :  3 286 131 B
                    → fonts are 64.6 % of the firmware
```

`geist_med_38.c` alone is 1.49 MB of source. Nineteen fonts are linked in at full character range.

**This single fact accounts for the team's "3 183 776 → 620 832 bytes, 80.5 % smaller".** Subsetting
the fonts to the glyphs the UI actually draws takes 2.12 MB to roughly 150 KB. That is an 80 %
reduction *without touching the framework at all*.

Worth being precise about what this buys: image size is an **OTA and flash** win, not primarily a
speed win. Only a few dozen glyphs are touched per frame, so the working set already fits in L2 — the
2 MB is mostly cold. Do it for the download time and the flash budget, and do not expect frames from
it.

### Three accelerators are present and switched off

| Switch | Now | Available | What it does |
|---|---|---|---|
| `LV_USE_PPA` | unset | `SOC_PPA_SUPPORTED=1`, and LVGL 9.5 ships `src/draw/espressif/ppa/` | Hardware fill + image blit. Our UI is almost entirely rounded-rect fills. |
| `LV_DRAW_SW_DRAW_UNIT_CNT` | `1` | `SOC_CPU_CORES_NUM=2` | A second rasterising thread. Needs `LV_USE_OS=FREERTOS`, currently unset. |
| `LV_CACHE_DEF_SIZE` | `0` | — | Image cache off. Every engine mark is drawn through `lv_image_set_scale()`, i.e. a bilinear transform, **on every redraw**. |

The PPA unit handles `LV_DRAW_TASK_TYPE_FILL` and `LV_DRAW_TASK_TYPE_IMAGE` — not labels. That is the
right half for this UI: the desk is nine large rounded rects plus nine scaled icons, and the text
covers a tiny fraction of the pixels.

**Note for the rewrite discussion: a custom framework loses this.** The PPA driver ships inside
LVGL 9.5 and would have to be rewritten by hand.

### The framebuffer is single

`panel_pro.c` sets `dpi.num_fbs = 1`. The DSI scans that buffer continuously while DMA2D writes new
bands into it. Two consequences:

- **Tearing** — there is no vsync-aligned swap, by construction.
- **Bus contention** — scan-out is `720 × 720 × 2 B × 59.2 Hz = 61.4 MB/s` read from PSRAM,
  permanently, and DMA2D's writes land in the same memory.

And the CPU is on that same bus: `SPIRAM_FETCH_INSTRUCTIONS=y`, `SPIRAM_RODATA=y`,
`SPIRAM_FLASH_LOAD_TO_PSRAM=y` mean **code and read-only data execute from PSRAM**, behind a
**128 KB L2 cache** serving a 3.3 MB image.

### Everything else already checks out

Worth saying plainly so nobody re-does it:

- **Draw buffers are already double** — `buf1`/`buf2`, 60 lines each, in internal DMA RAM.
  LVGL rasterises into one while DMA2D drains the other.
- **The band copy is already DMA2D**, not the CPU — `use_dma2d` is set by
  `ST7703_720_720_PANEL_60HZ_DPI_CONFIG`.
- **The DSI is correctly clocked** — 38 MHz over 840 × 764 total = 59.2 Hz, matching the panel.
- `COMPILER_OPTIMIZATION_PERF=y` (`-O2`).

---

## The three claims, one at a time

### 1 · "Render only diff, not the entire screen — 439 784 → 840 bytes"

**Right, and it is the single biggest win on the list. But LVGL already does this.**

LVGL keeps an invalid-area list and `LV_DISPLAY_RENDER_MODE_PARTIAL` only rasterises the dirty
rectangles. The reason the Pro re-renders ~440 KB instead of 840 B is our own application code:

```
$ grep -c "lv_obj_clean(" main/ui/ui_screens.c
10
```

Ten destroy-and-rebuild sites — the desk, the tab line, the notification list, the tab picker, the
pickers, the question screen. Every model change tears down the object tree and builds a new one,
which invalidates everything under it. One desk rebuild is:

```
9 tiles × (3 objects + 19 style/layout calls) + background + N tabs
  ≈ 30 lv_obj allocations, ~180 style property writes, one flex layout pass,
    then a full-screen invalidate
```

That is where the 46 ms lives — and it is perhaps a third object churn and two thirds the
full-screen rasterisation it forces.

**This was already proven on this device today.** The tab line used to rebuild every button on every
selection change; replacing that with a repaint that walks the existing children and changes only
the fill is ~30 lines, and it is exactly the 840-byte version of the same fix:

```c
static void tabline_repaint(void)   /* move the fill, keep the buttons and the scroll */
```

The same treatment applied to `desk_rebuild()`, `notif_rebuild()` and the settings tiles is the bulk
of the claimed win, inside LVGL, at a cost of days not months.

### 2 · "Replace the general-purpose LVGL widget framework with a custom-built one"

**The strongest number behind this (80.5 % smaller) is a font problem, not a framework problem.**
2.12 MB of the 3.28 MB image is glyph data that nothing subsets.

Before a rewrite is the right call, the four things above have to be tried, because each is a config
line or a localised change:

1. Subset the fonts → ~2 MB back, most of the image claim.
2. Stop the destroy-and-rebuild → most of the frame claim.
3. `LV_USE_PPA=y` → hardware fills and image blits.
4. `LV_DRAW_SW_DRAW_UNIT_CNT=2` + `LV_USE_OS=FREERTOS` → the second core.

What a custom framework genuinely wins, and I do not want to argue these away:

- **A lower floor.** LVGL's per-refresh overhead — timer handler, style cascade, layout invalidation
  — is a few hundred microseconds even when nothing changed. 0.39 ms is at the edge of what LVGL can
  do; a purpose-built renderer can go under it.
- **Determinism.** You know exactly what invalidates, because you wrote it.
- **No style cascade** on 180 property writes per rebuild.

What it costs: the PPA draw unit, the font engine, the text shaping (including Vietnamese
diacritics), the scroll/flex layout, the gesture plumbing, and every bug already found in all of
them — **and the dial runs the same `ui_screens.c`**. A rewrite is a rewrite of both devices, or a
permanent fork.

### 3 · "Pixel buffering — CPU pre-loads/prepares pixels while waiting on the render"

**Already done at the draw-buffer level** — `lv_display_set_buffers(s_disp, buf1, buf2, …)`. LVGL
renders the next band into `buf2` while DMA2D copies `buf1`; the flush does not block the renderer.

**Not done at the framebuffer level**, and that is the real remaining version of this claim:
`num_fbs = 1`. Two framebuffers with a vsync-aligned swap would remove tearing and stop DMA2D's
writes landing in the buffer the DSI is reading.

One caution: moving to `num_fbs = 2` with `LV_DISPLAY_RENDER_MODE_DIRECT` means LVGL must maintain
dirty areas across **two** buffers, and a naive switch re-renders the whole screen every frame —
which for this UI (small, infrequent invalidations) would be **slower** than today, not faster. It is
a tearing fix first and a speed fix only for full-screen changes.

---

## Ranked, by gain over cost

| # | Change | Cost | Expect |
|---|---|---|---|
| 1 | **Subset the fonts** to the glyphs actually drawn | hours, build-script only | −2 MB image (−64 %); OTA over the cable gets far shorter |
| 2 | **Repaint instead of rebuild** at the 10 `lv_obj_clean` sites | days | the bulk of 46 ms → single-digit ms |
| 3 | `LV_USE_PPA=y` + `LV_USE_PPA_IMG=y` | one config line + measure | hardware fills/blits; biggest on the desk |
| 4 | `LV_CACHE_DEF_SIZE` > 0, **or better: pre-bake icons at 24/32/40 px** and delete `lv_image_set_scale` | hours | removes a bilinear transform per icon per redraw — and the 2× upscale of a 20 px asset looks bad anyway |
| 5 | `LV_USE_OS=FREERTOS` + `LV_DRAW_SW_DRAW_UNIT_CNT=2` | one config line + measure | up to ~1.8× on large redraws; watch core 0's cable/audio work |
| 6 | `COMPILER_OPTIMIZATION_ASSERTION_LEVEL` 2 → 1 | one line | a few percent, everywhere |
| 7 | `num_fbs = 2` + vsync swap | days, risky | fixes tearing; **may cost frames** — see above |
| 8 | Raise `LV_DEF_REFR_PERIOD` 33 → 16 | one line | only meaningful once 1–5 land |

Items 1, 3, 5, 6 and 8 are **five config lines**. They should be measured before anything is
rewritten.

---

## What is missing before any of this is decided

There is no frame instrumentation on the device. The `display: alive` line reports heap, PSRAM and
LVGL fragmentation, and no timing at all. Every number above about *where* the 46 ms goes is
inference from the code, not measurement.

The measurement build is small and should come first:

- `LV_USE_PERF_MONITOR=y` — LVGL's own FPS and CPU-load overlay.
- `LV_USE_SYSMON` / `LV_USE_PROFILER` for per-draw-task timings.
- One `esp_timer_get_time()` bracket around `desk_rebuild()` and around `lv_timer_handler()`, logged
  on change, so object churn and rasterisation can be told apart.

Without that split — **object churn vs. rasterisation** — a rewrite is being chosen on a number that
does not say which of the two it fixes, and the fix for one of them is a config flag.

---

## The one sentence

Our UI re-creates its object tree on every update and therefore re-rasterises the whole screen; that
is the 46 ms, it is our bug rather than LVGL's, and the accelerators that would absorb what remains
are shipped in the version of LVGL we already link and are switched off.
