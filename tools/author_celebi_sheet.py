"""Build `assets/celebi.png` for the GS Ball mod, and check it.

Why this file exists at all: Gold has **no** Celebi overworld sprite.  Its
sprite constants stop short of one, and `gfx/overworld/celebi.png` is
Crystal's -- the 16x64 sheet the shrine descent cycles through, four 16x16
frames, referenced by `engine/events/celebi.asm` (`SpecialCelebiGFX`,
`GetCelebiSpriteTile`).  A mod that draws the descent on Gold therefore needs
the picture -- and since it is Nintendo's, this mod does not ship it.  This
script is the recipe instead: run it on your own copy of the cart's sheet and
drop the result at assets/celebi.png.  assets/README.md has the rest.

The sheet is a **four-shade** image on purpose:

    shade 0 (white)  ->  OBJ colour 0, which the engine keys to alpha
    shade 1 (grey)   ->  palette colour 1
    shade 2 (grey)   ->  palette colour 2
    shade 3 (black)  ->  palette colour 3

`src/render/SpriteRenderer.lua:getObpImage` is the bake that does it, and the
palette is the sprite's own (`PAL_OW_GREEN`, the cart's choice for this
sprite).  Baking the colours into the PNG instead -- which is what 1.4.0/1.4.1
did with a true-colour sheet -- is what made the sprite look wrong: the
palette never applied, so the shrine's own colours never arrived.  In the real
event the sprite is drawn with OBP0 = the green OW palette, whose colours 1-2
are #FF9C52 (orange) and #3ABD19 (green) at every time of day, which is why
the Celebi that descends is an orange-bodied, green-accented little creature.

The four shade levels are the ones the extractor writes (`ImageWriter`'s
columnsToRows -> 255/170/85/0), so a sheet re-encoded from the cart's own
graphic is already in the form the bake wants; this script re-encodes it as
opaque RGBA and refuses to write anything that would not bake.

Vendored into the mod's repo so a player can produce the sheet without
anything from the author's machine.  It needs Pillow, and the cart's own
16x64 `gfx/overworld/celebi.png` as input -- extract that from your own
Crystal ROM.

Usage:  python author_celebi_sheet.py <cart celebi.png> [-o assets/celebi.png]
"""

import argparse
import os
import sys

from PIL import Image


def pixels(image):
    """Every pixel, on either side of Pillow's getdata -> get_flattened_data rename."""
    reader = getattr(image, "get_flattened_data", None) or image.getdata
    return list(reader())

FRAME = 16
FRAMES = 4
SHADES = (255, 170, 85, 0)

# PAL_OW_GREEN's colours 1-3, read out of the real Gold ROM through the
# engine's own resolver (`freebuff/_ref/green_pal.lua` prints this): the same
# four values at MORN, DAY, NITE and DARK, so the sprite looks the same
# whenever the event is played.  Colour 0 is the engine's alpha key and never
# shows, which is why it is not here.
GREEN = ((255, 156, 82), (58, 189, 25), (0, 0, 0))


def load_cart(path):
    """The cart's sheet as a 4-shade grey image, checked before use."""
    try:
        image = Image.open(path).convert("L")
    except Exception:
        raise SystemExit(f"{path}: not an image -- want the cart's 16x64 PNG")
    if image.size != (FRAME, FRAME * FRAMES):
        raise SystemExit(
            f"{path}: expected {FRAME}x{FRAME * FRAMES} (4 frames), "
            f"got {image.width}x{image.height}")
    levels = sorted({p for p in pixels(image)})
    if levels != sorted(SHADES):
        raise SystemExit(
            f"{path}: expected the 4 shade levels {sorted(SHADES)}, got {levels}")
    return image


def build(cart):
    """Opaque RGBA in the four shades, frames stacked the way the engine reads."""
    out = Image.new("RGBA", (FRAME, FRAME * FRAMES))
    pixels = out.load()
    for y in range(FRAME * FRAMES):
        for x in range(FRAME):
            shade = cart.getpixel((x, y))
            pixels[x, y] = (shade, shade, shade, 255)
    return out


def bake(sheet, colours):
    """`SpriteRenderer.getObpImage`'s own mapping, so a preview is the real draw.

    (src/render/SpriteRenderer.lua:44 -- r > 0.83 keys OBJ colour 0 to alpha,
    r > 0.5 is palette colour 1, r > 0.17 is colour 2, everything darker is
    colour 3.  That is why the four levels have to be these four: a sheet with
    other tones would bake to the wrong colours rather than fail.)
    """
    out = Image.new("RGBA", sheet.size, (0, 0, 0, 0))
    pixels = out.load()
    for y in range(sheet.height):
        for x in range(sheet.width):
            v = sheet.getpixel((x, y))[0] / 255.0
            if v > 0.83:
                pixels[x, y] = (0, 0, 0, 0)
            elif v > 0.5:
                pixels[x, y] = colours[0] + (255,)
            elif v > 0.17:
                pixels[x, y] = colours[1] + (255,)
            else:
                pixels[x, y] = colours[2] + (255,)
    return out


def preview(path, sheet, scale=6, gap=4):
    """The four baked frames blown up, so the colours can be eyeballed."""
    baked = bake(sheet, GREEN)
    cell = FRAME * scale
    width = FRAMES * cell + (FRAMES - 1) * gap
    out = Image.new("RGBA", (width, cell), (208, 208, 208, 255))
    for f in range(FRAMES):
        frame = baked.crop((0, f * FRAME, FRAME, (f + 1) * FRAME))
        frame = frame.resize((cell, cell), Image.NEAREST)
        out.alpha_composite(frame, (f * (cell + gap), 0))
    out.save(path)
    return out


def check(path):
    """Everything the bake in getObpImage needs of the file, verified."""
    image = Image.open(path)
    problems = []
    if image.size != (FRAME, FRAME * FRAMES):
        problems.append(f"size is {image.size}, want ({FRAME}, {FRAME * FRAMES})")
    rgba = image.convert("RGBA")
    all_pixels = pixels(rgba)
    levels = sorted({p[0] for p in all_pixels})
    if levels != sorted(SHADES):
        problems.append(f"shades are {levels}, want {sorted(SHADES)}")
    alphas = {p[3] for p in all_pixels}
    if alphas != {255}:
        problems.append(f"alphas are {sorted(alphas)}, want fully opaque")
    for f in range(FRAMES):
        frame = rgba.crop((0, f * FRAME, FRAME, f * FRAME + FRAME))
        ink = [p[0] for p in pixels(frame) if p[0] != 255]
        if not ink:
            problems.append(f"frame {f + 1} is empty")
        elif max(ink) not in SHADES[:3]:
            problems.append(f"frame {f + 1} has no mid-tone pixels")
    if not all(p[0] == 255 or p[0] in SHADES[1:]
               for p in pixels(rgba.crop((0, 0, 1, 1)))):
        problems.append("the sheet's first pixel is not a background shade")
    return problems


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cart", nargs="?",
                        help="the cart's own 16x64 gfx/overworld/celebi.png")
    parser.add_argument("-o", "--output",
                        default=os.path.join(os.path.dirname(__file__),
                                             os.pardir, "assets", "celebi.png"))
    parser.add_argument("-p", "--preview",
                        help="also write the baked frames here, 6x, for review")
    args = parser.parse_args(argv)

    if not args.cart:
        parser.error("give me the cart's celebi.png (16x64, four shades) -- "
                     "see assets/README.md")
    cart = load_cart(args.cart)
    out = build(cart)
    out.save(args.output)
    if args.preview:
        preview(args.preview, out)
        print(f"wrote {args.preview} (baked through {GREEN[0]} and 2 more)")

    problems = check(args.output)
    if problems:
        for p in problems:
            print("  FAIL", p)
        return 1
    print(f"wrote {args.output} ({out.width}x{out.height}, {FRAMES} frames, "
          f"shades {SHADES[0]}/{SHADES[1]}/{SHADES[2]}/{SHADES[3]})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
