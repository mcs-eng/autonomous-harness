# Art lifted out of the firmware that came before habitat

`mic.png` and `sparkle.png` are `icon_v_mic` and `icon_sparkle_fill` from `main/ui/icons_voice.c`,
which was deleted with the LVGL renderer on 2026-09-29. They are kept as images rather than redrawn,
because a redraw is a different drawing: the first hand-made microphone here grew a base bar the
original never had.

**Their alpha channel is not the mark.** Both were exported as ARGB8888 in B,G,R,A order and
CIRCULAR-MASKED — alpha 0 outside the coloured disc they sat on, alpha 255 across the whole disc. So
alpha traces the disc and tells you nothing about the shape. The mark is white on that disc, and what
recovers it is the minimum of the three colour channels: the disc floors that minimum at 51, its
antialiased edge reaches about 90, and the mark itself runs to 255. Gate above 90, rescale, crop to
the ink.

Regenerate from git if they are ever needed again:

    git show <rev>:devices/harness-device/firmware/main/ui/icons_voice.c

`scripts/gen_habitat_fonts.py` scales each one into its glyph cell and quantises it to the 2 bits per
pixel every habitat font uses. Nothing here is read at runtime — the device has no image decoder and
no font engine.
