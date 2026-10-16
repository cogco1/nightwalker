"""Turn generated night-street source art into native pixel layers for game/assets/night_street/.

Usage:
  python -I tools/art/pixelize_layer.py palette <out_palette.png> <source.png> [<source.png> ...]
  python -I tools/art/pixelize_layer.py layer <source.png> <layer_name> <width|0 = keep aspect> <palette.png> [--opaque] [--key 00ff00] [--out <dir>] [--emit-hues cmo]

`palette` builds one shared palette (max 40 colours, the three neon colours always included) from all
source images, so every parallax layer reads as one piece. `layer`:
  1. maps the full-resolution source to the palette and downsamples by block mode to <width> x 180,
  2. derives hard alpha from the source's transparency, else from the chroma key (skipped with --opaque),
  3. (no dithering anywhere; neon accents covering a third of a block win that pixel),
  4. removes lone pixels that differ from all four neighbours (generator noise),
  5. splits saturated bright pixels whose hue is in --emit-hues (c cyan, m magenta, o sodium orange; default
     all three) into <layer_name>_emit.png and darkens them in the
     base layer to their housing colour, matching how night_street.gd draws base (shaded) + emit (unshaded).
Writes game/assets/night_street/<layer_name>.png and <layer_name>_emit.png.
"""
import colorsys
import sys
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "night_street"
HEIGHT = 180
NEON = [(79, 240, 255), (255, 61, 154), (255, 154, 60)]
MAX_COLOURS = 40


def hx(value: str) -> tuple[int, int, int]:
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def build_palette(out_path: str, sources: list[str]) -> None:
    strips = []
    for source in sources:
        image = Image.open(source).convert("RGB")
        image.thumbnail((640, 640))
        strips.append(image)
    width = max(image.width for image in strips)
    combined = Image.new("RGB", (width, sum(image.height for image in strips)))
    y = 0
    for image in strips:
        combined.paste(image, (0, y))
        y += image.height
    reduced = combined.quantize(colors=MAX_COLOURS - len(NEON), method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    colours = [tuple(reduced.getpalette()[i * 3:i * 3 + 3]) for i in range(MAX_COLOURS - len(NEON))]
    colours += NEON
    swatch = Image.new("RGB", (len(colours), 1))
    for index, colour in enumerate(colours):
        swatch.putpixel((index, 0), colour)
    swatch.save(out_path)
    print("palette", len(colours), "colours ->", out_path)


def nearest(colour, palette):
    return min(palette, key=lambda p: (p[0] - colour[0]) ** 2 * 3 + (p[1] - colour[1]) ** 2 * 4 + (p[2] - colour[2]) ** 2 * 2)


EMIT_HUES = {"c": (0.45, 0.58), "m": (0.86, 0.98), "o": (0.04, 0.12)}
emit_hues = "cmo"


def is_neon(colour) -> bool:
    h, s, v = colorsys.rgb_to_hsv(*(c / 255.0 for c in colour))
    if not (s > 0.55 and v > 0.78):
        return False
    return any(low <= h <= high for key, (low, high) in EMIT_HUES.items() if key in emit_hues)


def make_layer(source: str, name: str, width: int, palette_path: str, opaque: bool, key: str) -> None:
    palette_image = Image.open(palette_path).convert("RGB")
    palette = [palette_image.getpixel((i, 0)) for i in range(palette_image.width)]
    raw = Image.open(source)
    high = raw.convert("RGB")
    if width <= 0:
        width = round(high.width * HEIGHT / high.height)  # keep the source aspect
    # alpha: the source's own transparency when it has some (Codex image_gen returns keyed PNGs),
    # otherwise the chroma key; box-averaged and thresholded after downsampling
    own_alpha = raw.convert("RGBA").getchannel("A") if raw.mode in ("RGBA", "LA", "P") else None
    if opaque:
        alpha = Image.new("L", high.size, 255)
    elif own_alpha is not None and own_alpha.getextrema()[0] < 128:
        # keep the source's transparency, but drop chroma-key leftovers (stray near-pure-green specks)
        alpha = own_alpha.copy()
        src = high.load()
        dst = alpha.load()
        for y in range(high.height):
            for x in range(high.width):
                r, g, b = src[x, y]
                if g > 140 and r < 110 and b < 110:
                    dst[x, y] = 0
    else:
        key_rgb = hx(key)
        alpha = Image.new("L", high.size)
        src = high.load()
        dst = alpha.load()
        for y in range(high.height):
            for x in range(high.width):
                r, g, b = src[x, y]
                distance = abs(r - key_rgb[0]) + abs(g - key_rgb[1]) + abs(b - key_rgb[2])
                dst[x, y] = 0 if distance < 120 else 255
    native_alpha = alpha.resize((width, HEIGHT), Image.BOX).point(lambda v: 255 if v >= 128 else 0)
    mask = native_alpha.load()
    # map the full-resolution art to the palette first, then let each native pixel take the most common
    # palette colour of its source block: single-design-pixel windows and neon survive instead of being
    # averaged into the wall around them
    palette_image = Image.new("P", (1, 1))
    flat = [channel for colour in palette for channel in colour]
    palette_image.putpalette(flat + flat[:3] * (256 - len(palette)))
    indexed = high.quantize(palette=palette_image, dither=Image.Dither.NONE)
    index_pixels = indexed.load()
    brightness = high.convert("HSV").getchannel("V").load()
    plain = [colour for colour in palette if not is_neon(colour)]
    sx, sy = high.width / width, high.height / HEIGHT
    mapped = {}
    for y in range(HEIGHT):
        y0, y1 = int(y * sy), max(int(y * sy) + 1, int((y + 1) * sy))
        for x in range(width):
            if mask[x, y] == 0:
                continue
            x0, x1 = int(x * sx), max(int(x * sx) + 1, int((x + 1) * sx))
            counts = {}
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    value = index_pixels[xx, yy]
                    counts[value] = counts.get(value, 0) + 1
            best = max(counts, key=counts.get)
            # a neon accent that fills a fair part of the block wins over the wall behind it
            neon_votes = [(n, v) for v, n in counts.items() if is_neon(palette[v])]
            if neon_votes:
                votes, value = max(neon_votes)
                if votes * 3 >= (x1 - x0) * (y1 - y0):
                    best = value
            colour = palette[best]
            # warm rock highlights can land on the sodium neon swatch; only truly bright source blocks
            # (an actual lamp or tube, V >= 0.85) may stay neon and be split into the emit layer
            if is_neon(colour):
                peak = max(brightness[xx, yy] for yy in range(y0, y1) for xx in range(x0, x1))
                if peak < 217:
                    colour = nearest(colour, plain)
            mapped[(x, y)] = colour
    # lone-pixel cleanup: a pixel unlike all four neighbours takes the most common neighbour colour
    cleaned = dict(mapped)
    for (x, y), colour in mapped.items():
        around = [mapped.get((x + dx, y + dy)) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        around = [c for c in around if c is not None]
        if len(around) == 4 and all(c != colour for c in around) and not is_neon(colour):
            cleaned[(x, y)] = max(set(around), key=around.count)
    base = Image.new("RGBA", (width, HEIGHT), (0, 0, 0, 0))
    emit = Image.new("RGBA", (width, HEIGHT), (0, 0, 0, 0))
    for (x, y), colour in cleaned.items():
        if is_neon(colour):
            emit.putpixel((x, y), colour + (255,))
            housing = nearest(tuple(int(c * 0.28) for c in colour), palette)
            base.putpixel((x, y), housing + (255,))
        else:
            base.putpixel((x, y), colour + (255,))
    OUT.mkdir(parents=True, exist_ok=True)
    base.save(OUT / f"{name}.png")
    emit.save(OUT / f"{name}_emit.png")
    used = len({c for c in cleaned.values()})
    print(f"{name}: {width}x{HEIGHT}, {len(cleaned)} opaque px, {used} colours, "
          f"{sum(1 for c in cleaned.values() if is_neon(c))} emissive px")


def main() -> int:
    if len(sys.argv) >= 4 and sys.argv[1] == "palette":
        build_palette(sys.argv[2], sys.argv[3:])
        return 0
    if len(sys.argv) >= 6 and sys.argv[1] == "layer":
        key = sys.argv[sys.argv.index("--key") + 1] if "--key" in sys.argv else "00ff00"
        global OUT, emit_hues
        if "--out" in sys.argv:
            OUT = Path(sys.argv[sys.argv.index("--out") + 1])
        if "--emit-hues" in sys.argv:
            emit_hues = sys.argv[sys.argv.index("--emit-hues") + 1]
        make_layer(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5], "--opaque" in sys.argv, key)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
