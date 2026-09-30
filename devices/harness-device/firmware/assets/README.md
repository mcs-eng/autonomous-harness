# Art the glyphs are built from

Nothing here is read at runtime — the device has no image decoder and no font engine.
`scripts/gen_habitat_fonts.py` turns each file into a glyph and quantises it to the 2 bits per pixel
every habitat font uses.

## `mic.png` — lifted from the design, at 1:1

The Focus face's microphone is the mark in `mockup/newdesign.html`, screen "Agent — recap", the
27 x 34 box at (220, 377). That screen is rendered at the device's own 466 x 466, so the mark is
already at the size the glass draws it and is placed into its cell **without scaling** — the only
change between the design and the device is the quantisation to four levels.

It is #00ff2f on black, so the green channel IS the coverage. Red stays near zero on the mark and
only rises in the neutral UI around it; `g > r + 40` keeps that out.

Two earlier microphones were wrong, and both ways are worth remembering. The first was drawn by hand
from strokes and read as a different icon. The second was `icon_v_mic` from the old firmware's
`main/ui/icons_voice.c` — a 24 x 32 white mark inside a 72 px blue disc — enlarged to fill the cell:
40% bigger than the design, and without the design's base bar.

## `sparkle.png`, `sparkle_fill.png` — from the old firmware

`icon_sparkle` and `icon_sparkle_fill` from `main/ui/icons_voice.c`, which was deleted with the LVGL
renderer on 2026-09-29. Scaled into their cell.

**The old icons' alpha channel is not the mark.** They were exported as ARGB8888 in B,G,R,A order.
The disc icons (`icon_v_mic`, `icon_v_rec`, `icon_v_orb`) are CIRCULAR-MASKED — alpha 0 outside the
coloured disc, 255 across it — so alpha traces the disc and says nothing about the shape; the mark
comes out of the colour channels instead. The sparkles are not on a disc, and their alpha is the
shape.

Regenerate from git if they are ever needed again:

    git show <rev>:devices/harness-device/firmware/main/ui/icons_voice.c

## `engines/*.png` — from the old firmware

`main/ui/icons_engine.c`, same export and the same disc caveat. Scaled to cap height.
