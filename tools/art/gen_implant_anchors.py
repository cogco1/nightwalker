"""Find a forearm anchor in every hero frame for the barcode-scar overlay.

Usage: python -I tools/art/gen_implant_anchors.py
Writes game/assets/fx/implant_anchors.json: {"res://frames/<action>/<NN>.png": [x, y], ...} in frame pixels.
The blade axis gives the tip (end farther from the figure) and the base; walking on past the base finds
the sword hand, and the scar sits one pixel further along the forearm.
Gaps inside an action reuse the nearest anchored frame; actions with fewer than 10 anchored frames get
no entry, and the overlay hides the scar there. Frames are only read.
"""
import json
import math
from pathlib import Path

from PIL import Image

GAME = Path(__file__).resolve().parents[2] / "game"
STEEL = {(0xE5, 0xE8, 0xE0), (0xBB, 0xC2, 0xC3), (0x8E, 0x99, 0x9F)}


def anchor_for(image: Image.Image):
    pixels = image.load()
    width, height = image.size
    steel, opaque = [], set()
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a < 255:
                continue
            opaque.add((x, y))
            if (r, g, b) in STEEL:
                steel.append((x, y))
    if len(steel) < 3:
        return None
    # blade axis by principal component; the end farther from the figure's median pixel is the tip
    mx = sum(p[0] for p in steel) / len(steel)
    my = sum(p[1] for p in steel) / len(steel)
    sxx = sum((p[0] - mx) ** 2 for p in steel)
    syy = sum((p[1] - my) ** 2 for p in steel)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in steel)
    angle = 0.5 * math.atan2(2 * sxy, sxx - syy)
    ax, ay = math.cos(angle), math.sin(angle)
    ends = (min(steel, key=lambda p: (p[0] - mx) * ax + (p[1] - my) * ay),
            max(steel, key=lambda p: (p[0] - mx) * ax + (p[1] - my) * ay))
    figure = sorted(opaque)
    fx = sorted(p[0] for p in figure)[len(figure) // 2]
    fy = sorted(p[1] for p in figure)[len(figure) // 2]
    tip = max(ends, key=lambda p: (p[0] - fx) ** 2 + (p[1] - fy) ** 2)
    base = ends[1] if tip == ends[0] else ends[0]
    dx, dy = base[0] - tip[0], base[1] - tip[1]
    length = math.hypot(dx, dy) or 1.0
    dx, dy = dx / length, dy / length
    steel_set = set(steel)
    hand = None
    for step in range(1, 7):
        candidate = (round(base[0] + dx * step), round(base[1] + dy * step))
        if candidate in opaque and candidate not in steel_set:
            hand = candidate
            break
    if hand is None:
        return None
    forearm = (round(hand[0] + dx), round(hand[1] + dy))
    return list(forearm if forearm in opaque and forearm not in steel_set else hand)


MIN_FRAMES_PER_ACTION = 10


def main() -> None:
    by_action = {}
    for path in sorted((GAME / "frames").rglob("*.png")):
        by_action.setdefault(path.parent.name, []).append(path)
    anchors = {}
    dropped = []
    for action, paths in sorted(by_action.items()):
        found = [anchor_for(Image.open(path).convert("RGBA")) for path in paths]
        hits = [index for index, value in enumerate(found) if value is not None]
        # A scar that blinks on and off reads as a glitch, so sparse actions get none at all.
        if len(hits) < MIN_FRAMES_PER_ACTION:
            dropped.append(action)
            continue
        for index, path in enumerate(paths):
            nearest = min(hits, key=lambda hit: (abs(hit - index), hit))
            anchors["res://" + path.relative_to(GAME).as_posix()] = found[nearest]
    out = GAME / "assets" / "fx" / "implant_anchors.json"
    out.write_text(json.dumps(anchors, indent=0, sort_keys=True), encoding="utf-8")
    print(f"{len(anchors)} frames in {len(by_action) - len(dropped)} actions anchored; no scar in {len(dropped)}: {', '.join(dropped)}")


if __name__ == "__main__":
    main()
