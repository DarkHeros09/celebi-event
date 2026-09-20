# assets/ — the one picture this mod does not ship

This directory is where **Celebi's descent sprite** goes. It is empty on purpose:
the file is yours to supply.

## Why it is not here

The sprite is a re-cut of the cart's own overworld graphic — `gfx/overworld/celebi.2bpp`,
the sheet `SpecialCelebiGFX` loads in `engine/events/celebi.asm`. It is Nintendo's
art, so this mod does not redistribute it. Everything else the shrine event needs
is code, and the code ships.

Gold cannot supply it for you either. The engine's importer extracts a
`battle/front/celebi.png` and a `battle/back/celebi_back.png`, but **no overworld
sheet** — Gold has no Celebi overworld sprite of its own, the constant is
Crystal's — so there is nothing in your own imported cache to derive it from.

## What to drop in

Save the sheet as **`assets/celebi.png`** inside the installed mod folder
(`mods/celebi_event/assets/celebi.png`). It has to be:

| property | value |
| --- | --- |
| size | **16 × 64** — four 16×16 frames stacked vertically |
| frames | four, one per step of the descent, top to bottom |
| colours | **four shades only**: white, two greys, black |

The four shades are not a stylistic choice. `SpriteRenderer:resolveImage` runs the
sheet through `getObpImage`, which keys shade 0 (white) to transparent and maps
shades 1–3 onto the sprite's own OBJ palette — `PAL_OW_GREEN`, the palette the
cart draws the shrine sprite with. Its colours 1–3 are `#FF9C52` (orange),
`#3ABD19` (green) and black at every time of day, so the Celebi that descends is
an orange-bodied, green-accented hover, and it follows the time of day and the
COLOR option like every other sprite on the map.

A true-colour PNG will **not** work: it has no shade levels for the bake to read,
so nothing in it means "palette colour 1". That was the 1.4.0/1.4.1 bug — see
README, "Celebi's colours".

## If you would rather not

Nothing breaks. The shrine event still runs end to end — the "!", the step back,
the 160-iteration descent, the tear-down and the Lv30 battle all play — the
descent just has no sprite in it, and the mod says so once in the log. The event
is the cutscene and the battle, not the picture.
