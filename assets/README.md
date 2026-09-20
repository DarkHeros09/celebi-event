# assets/ — Celebi's descent sprite

This directory holds one file, **`celebi.png`**: the sprite that descends to the
player at the Ilex Forest shrine.

| property | value |
| --- | --- |
| size | **16 × 64** — four 16×16 frames stacked vertically |
| frames | four, one per step of the descent, top to bottom |
| colours | **four shades only**: white, two greys, black |

## Where it comes from

It is a re-cut of the cart's own overworld graphic — `gfx/overworld/celebi.2bpp`,
the sheet `SpecialCelebiGFX` loads in `engine/events/celebi.asm`. The cart copies
it into `vTiles0` for that one animation and never as an ordinary sprite, so it
is **not** a row of the `OverworldSprites` table, and the engine's importer
therefore never writes it: a Gold import yields `battle/front/celebi.png` and
`battle/back/celebi_back.png` but **no overworld sheet**.

That is the whole reason this file is carried in the package. Nothing on the
player's machine can be used to derive it, so the choice was never "ship it or
derive it" — it was "ship it, or ship a descent with no Celebi in it".

`tools/author_celebi_sheet.py` is the recipe: point it at your own cart's 16×64
sheet and it writes this file. It reproduces the shipped sheet byte for byte, so
building it yourself and downloading it come out the same.

## The four shades are load-bearing

`SpriteRenderer:resolveImage` runs the sheet through `getObpImage`, which keys
shade 0 (white) to transparent and maps shades 1–3 onto the sprite's own OBJ
palette — `PAL_OW_GREEN`, the palette the cart draws the shrine sprite with. Its
colours 1–3 are `#FF9C52` (orange), `#3ABD19` (green) and black at every time of
day, so the Celebi that descends is an orange-bodied, green-accented hover, and
it follows the time of day and the COLOR option like every other sprite on the
map.

That is also why **one sheet serves all three carts**: nothing in the file names
a colour. A true-colour PNG will not work — it has no shade levels for the bake
to read, so nothing in it means "palette colour 1". That was the 1.4.0/1.4.1
bug; see README, "Celebi's colours".

## If you delete it

Nothing breaks. The shrine event still runs end to end — the "!", the step back,
the 160-iteration descent, the tear-down and the Lv30 battle all play — the
descent just has no sprite in it, and the mod says so once in the log. The event
is the cutscene and the battle, not the picture.
