"""Build the "lamp off" covers for the floor-2 corridor of the top-down hospital.

The corridor art paints each ceiling lamp's light pool into the floor. When the clinic breaker cuts the power
the stealth light test reads the corridor as dark, so the picture has to agree. For every lamp, a colour is a
pool colour when it is at least five times as common inside the lamp's pool box as on the plain floor midway
between the lamps; each pool colour is mapped, by luminance rank, onto those plain-floor pixels, and the
still-bright lower rows of the tube become the dark colour of the existing off cover. Tile seams, grates and
stains keep their own colours.

Writes one RGBA PNG per lamp (remapped pixels opaque, the rest transparent) to
game/assets/underground_hospital/lamp_off/ and records it as the lamp's "off_cover" in layout.json.
Usage: python -I tools/art/gen_lamp_off_covers.py [--preview out.png]
"""
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / "game"
LAYOUT = ROOT / "assets" / "underground_hospital" / "layout.json"
OUT = ROOT / "assets" / "underground_hospital" / "lamp_off"
FLOOR = "2"
POOL_MARGIN_X = 22
POOL_DEPTH = 32
POOL_RATIO = 5.0
REFERENCE_HALF_WIDTH = 14
TUBE_LUMINANCE = 120
TUBE_OFF = (6, 11, 17, 255)  # interior_lighting.gd off cover Color(0.025, 0.045, 0.065)


def luminance(colour: tuple) -> float:
    return 0.3 * colour[0] + 0.59 * colour[1] + 0.11 * colour[2]


def main() -> None:
    layout = json.loads(LAYOUT.read_text(encoding="utf-8"))
    floor = layout["views"]["top_down"]["floors"][FLOOR]
    picture = Image.open(ROOT / floor["background"].removeprefix("res://")).convert("RGBA")
    lamps = floor["fluorescents"]
    zone = next(item["rect"] for item in floor["light_zones"] if item["id"] == "corridor")
    boxes = []
    for lamp in lamps:
        x, y, w, h = lamp["rect"]
        boxes.append((max(zone[0], x - POOL_MARGIN_X), y + h, min(zone[0] + zone[2], x + w + POOL_MARGIN_X), y + h + POOL_DEPTH))
    top = min(box[1] for box in boxes)
    bottom = max(box[3] for box in boxes)
    # Reference: the same rows on the plain floor midway between neighbouring pool boxes.
    reference = []
    for left, right in zip(boxes, boxes[1:]):
        middle = (left[2] + right[0]) // 2
        for x in range(middle - REFERENCE_HALF_WIDTH, middle + REFERENCE_HALF_WIDTH):
            for y in range(top, bottom):
                reference.append(picture.getpixel((x, y)))
    reference_counts = Counter(reference)
    reference.sort(key=luminance)
    OUT.mkdir(parents=True, exist_ok=True)
    preview = picture.copy()
    for lamp, box in zip(lamps, boxes):
        pixels = [(x, y, picture.getpixel((x, y))) for y in range(box[1], box[3]) for x in range(box[0], box[2])]
        ordered = sorted(luminance(colour) for _, _, colour in pixels)
        pool_counts = Counter(colour for _, _, colour in pixels)
        scale = len(pixels) / len(reference)
        mapping = {}
        for _, _, colour in pixels:
            if colour in mapping or pool_counts[colour] < POOL_RATIO * max(1.0, reference_counts[colour] * scale):
                continue
            if luminance(colour) >= TUBE_LUMINANCE:
                mapping[colour] = TUBE_OFF
                continue
            below = sum(1 for value in ordered if value < luminance(colour))
            same = sum(1 for value in ordered if value == luminance(colour))
            rank = (below + same * 0.5) / len(ordered)
            mapping[colour] = reference[min(len(reference) - 1, int(rank * len(reference)))]
        cover = Image.new("RGBA", (box[2] - box[0], box[3] - box[1]), (0, 0, 0, 0))
        for x, y, colour in pixels:
            if colour in mapping:
                cover.putpixel((x - box[0], y - box[1]), mapping[colour])
                preview.putpixel((x, y), mapping[colour])
        name = f"{lamp['id']}.png"
        cover.save(OUT / name)
        lamp["off_cover"] = {"texture": f"res://assets/underground_hospital/lamp_off/{name}", "position": [box[0], box[1]]}
        print(f"{name}: box {box}, {len(mapping)} colours remapped")
    LAYOUT.write_text(json.dumps(layout, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")
    if "--preview" in sys.argv:
        target = Path(sys.argv[sys.argv.index("--preview") + 1])
        preview.crop((0, top - 20, picture.width, bottom + 10)).resize(((picture.width) * 2, (bottom - top + 30) * 2), Image.NEAREST).save(target)


if __name__ == "__main__":
    main()
