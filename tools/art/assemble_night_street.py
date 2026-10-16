"""Assemble the pixelized night-street layers (tools/art/pixelize_layer.py output) into the final assets.

Usage: python -I tools/art/assemble_night_street.py <native_dir>
Reads <native_dir>/{far_towers,petra,district_c,street}{,_emit}.png and writes game/assets/night_street/:
  far_towers  copied (448 wide, parallax 0.15)
  petra       copied (540 wide, parallax 0.34)
  district_c  768 wide: the generated row of blocks, then the blocks again mirrored and reordered (the
              Golden Domain Tower group appears once), with sagging power cables redrawn between roofs
  street      960 wide: the generated street plus its mirror image; the mirror joins seamlessly
  lights.json one entry per self-lit cluster above the pavement wall (lamp heads, kiosk sign, vending
              machine, ID gate): position, colour, energy, radius - read by night_street.gd for PointLight2D
The sky stays procedural: copied from game/assets/night_street_placeholder/ (tools/art/gen_night_street.py).
"""
import colorsys
import json
import math
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageOps

OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "night_street"
HEIGHT = 180
DISTRICT_WIDTH = 768
STREET_WIDTH = 960
CABLE = (11, 8, 22, 255)
# Vertical placement (native px, + = down). The generated pavement sits at y=133; moving the street and
# district down 14 puts it at 147, just behind the y=156 walking line, and uncovers the Petra portico;
# Petra moves 10 so the A-district tower tops clear its cliff edge. Rows pushed past y=180 are uniform road.
SHIFT = {"far_towers": 0, "petra": 10, "district_c": 14, "street": 14}


def shifted(image: Image.Image, name: str) -> Image.Image:
    out = Image.new("RGBA", image.size)
    out.alpha_composite(image, (0, SHIFT[name]))
    return out


def load(native: Path, name: str):
    return Image.open(native / f"{name}.png").convert("RGBA"), Image.open(native / f"{name}_emit.png").convert("RGBA")


def segments(image: Image.Image, min_opaque: int = 5):
    alpha = image.getchannel("A").load()
    found, start = [], None
    for x in range(image.width + 1):
        count = sum(1 for y in range(HEIGHT) if alpha[x, y]) if x < image.width else 0
        if count >= min_opaque and start is None:
            start = x
        if count < min_opaque and start is not None:
            found.append((start, x))
            start = None
    return found


def roof(image: Image.Image, x0: int, x1: int) -> int:
    alpha = image.getchannel("A").load()
    return min(y for x in range(x0, x1) for y in range(HEIGHT) if alpha[x, y])


def district(native: Path) -> None:
    base, emit = load(native, "district_c")
    parts = segments(base)
    tower = min(parts, key=lambda part: roof(base, *part))
    out_base = Image.new("RGBA", (DISTRICT_WIDTH, HEIGHT))
    out_emit = Image.new("RGBA", (DISTRICT_WIDTH, HEIGHT))
    placed = []
    x = 0
    for part in parts:  # the generated order first, untouched
        x = part[0]
        out_base.alpha_composite(base.crop((part[0], 0, part[1], HEIGHT)), (x, 0))
        out_emit.alpha_composite(emit.crop((part[0], 0, part[1], HEIGHT)), (x, 0))
        placed.append((x, x + part[1] - part[0]))
    x = placed[-1][1]
    others = [part for part in parts if part != tower]
    order = others[1::2] + others[0::2]  # reorder so the repeat does not read as a copy
    index = 0
    while x < DISTRICT_WIDTH and order:
        part = order[index % len(order)]
        x += 10
        piece = ImageOps.mirror(base.crop((part[0], 0, part[1], HEIGHT)))
        glow = ImageOps.mirror(emit.crop((part[0], 0, part[1], HEIGHT)))
        out_base.alpha_composite(piece, (x, 0))
        out_emit.alpha_composite(glow, (x, 0))
        placed.append((x, x + piece.width))
        x += piece.width
        index += 1
    # power cables between neighbouring roofs (generated cables were cut where blocks were separated)
    pixels = out_base.load()
    for (a0, a1), (b0, b1) in zip(placed, placed[1:]):
        if b0 >= DISTRICT_WIDTH:
            break
        y_a = roof(out_base, max(a0, a1 - 6), min(a1, DISTRICT_WIDTH)) + 6
        y_b = roof(out_base, b0, min(b0 + 6, DISTRICT_WIDTH)) + 6
        start, end = a1 - 2, min(b0 + 2, DISTRICT_WIDTH - 1)
        span = max(1, end - start)
        for cx in range(start, end + 1):
            t = (cx - start) / span
            cy = round(y_a + (y_b - y_a) * t + 5 * math.sin(math.pi * t))
            if 0 <= cx < DISTRICT_WIDTH and pixels[cx, cy][3] == 0:
                pixels[cx, cy] = CABLE
    shifted(out_base, "district_c").save(OUT / "district_c.png")
    shifted(out_emit, "district_c").save(OUT / "district_c_emit.png")
    print("district_c", out_base.size, "blocks", len(placed), "tower once at", tower)


def street(native: Path) -> list:
    base, emit = load(native, "street")
    wide_base = Image.new("RGBA", (base.width * 2, HEIGHT))
    wide_emit = Image.new("RGBA", (base.width * 2, HEIGHT))
    wide_base.alpha_composite(base, (0, 0))
    wide_base.alpha_composite(ImageOps.mirror(base), (base.width, 0))
    wide_emit.alpha_composite(emit, (0, 0))
    wide_emit.alpha_composite(ImageOps.mirror(emit), (base.width, 0))
    wide_base = shifted(wide_base.crop((0, 0, STREET_WIDTH, HEIGHT)), "street")
    wide_emit = shifted(wide_emit.crop((0, 0, STREET_WIDTH, HEIGHT)), "street")
    wide_base.save(OUT / "street.png")
    wide_emit.save(OUT / "street_emit.png")
    # lights: clusters of self-lit pixels above the pavement wall
    alpha = wide_base.getchannel("A").load()
    wall_top = next(y for y in range(HEIGHT) if sum(1 for x in range(STREET_WIDTH) if alpha[x, y]) > 0.9 * STREET_WIDTH)
    glow = wide_emit.load()
    seen, lights = set(), []
    for y in range(wall_top):
        for x in range(STREET_WIDTH):
            if glow[x, y][3] == 0 or (x, y) in seen:
                continue
            stack, cluster = [(x, y)], []
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                cluster.append((cx, cy))
                for nx in range(cx - 2, cx + 3):
                    for ny in range(cy - 2, cy + 3):
                        if 0 <= nx < STREET_WIDTH and 0 <= ny < wall_top + 2 and (nx, ny) not in seen and glow[nx, ny][3]:
                            seen.add((nx, ny))
                            stack.append((nx, ny))
            if len(cluster) < 3:
                continue
            colours = [glow[px, py][:3] for px, py in cluster]
            mean = tuple(sum(c[i] for c in colours) / len(colours) for i in range(3))
            h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in mean))
            cx = sum(p[0] for p in cluster) / len(cluster)
            cy = sum(p[1] for p in cluster) / len(cluster)
            orange = 0.03 <= h <= 0.14
            lights.append({"position": [round(cx), round(cy)], "colour": "%02x%02x%02x" % tuple(round(c) for c in mean),
                           "energy": 1.0 if orange else 1.2, "radius": 56 if orange else min(70, 30 + len(cluster) // 2)})
    # one light per fixture: clusters closer than 14 px (a lamp head split by its housing) merge
    merged = []
    for light in sorted(lights, key=lambda item: item["position"][0]):
        near = next((m for m in merged if math.dist(m["position"], light["position"]) < 14), None)
        if near is None:
            merged.append(dict(light, weight=1))
            continue
        w = near["weight"]
        near["position"] = [round((near["position"][i] * w + light["position"][i]) / (w + 1)) for i in range(2)]
        near["radius"] = max(near["radius"], light["radius"])
        near["energy"] = max(near["energy"], light["energy"])
        near["weight"] = w + 1
    for light in merged:
        light.pop("weight")
    print("street", wide_base.size, "wall top", wall_top, "lights", len(merged))
    return merged


def main() -> int:
    native = Path(sys.argv[1])
    OUT.mkdir(parents=True, exist_ok=True)
    placeholder = OUT.parent / "night_street_placeholder"
    for suffix in ("", "_emit"):
        shutil.copy2(placeholder / f"sky{suffix}.png", OUT / f"sky{suffix}.png")
        for name in ("far_towers", "petra"):
            shifted(Image.open(native / f"{name}{suffix}.png").convert("RGBA"), name).save(OUT / f"{name}{suffix}.png")
    district(native)
    lights = street(native)
    (OUT / "lights.json").write_text(json.dumps(lights, indent=1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
