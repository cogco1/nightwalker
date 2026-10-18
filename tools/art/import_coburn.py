"""Convert the generated Coburn sheet onto the game's fixed native pixel grid.

No character pixels are drawn here. Source art is cropped, uniformly nearest-
neighbour reduced, alpha-thresholded and palette-reduced without dithering.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
META = ROOT / "game/art_metadata/coburn_20261018"
OUT = ROOT / "game/assets/npcs/coburn"
SOURCE = META / "coburn_sheet_generated.png"
CELL = (48, 48)
FOOT = (24, 40)
BODY_HEIGHT = 31
NAMES = ["idle_00", "idle_01", "collapse_00", "dead_00"]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    source = Image.open(SOURCE).convert("RGBA")
    width, height = source.size
    # These are the four model-produced cells, with no hand-drawn corrections.
    cells = [
        source.crop((col * width // 2, row * height // 2,
                     (col + 1) * width // 2, (row + 1) * height // 2))
        for row in range(2) for col in range(2)
    ]
    bounds = [im.getchannel("A").point(lambda x: 255 if x >= 128 else 0).getbbox()
              for im in cells]
    scale = BODY_HEIGHT / (bounds[0][3] - bounds[0][1])
    raw_frames = []
    for im, bbox in zip(cells, bounds):
        crop = im.crop(bbox)
        native = crop.resize((round(crop.width * scale), round(crop.height * scale)),
                             Image.Resampling.NEAREST)
        native.putalpha(native.getchannel("A").point(lambda x: 255 if x >= 128 else 0))
        # An unchanged sole baseline is used for every pose; no pose is rescaled
        # to fill the upright frame, so a bowed head really becomes lower.
        frame = Image.new("RGBA", CELL)
        frame.alpha_composite(native, (FOOT[0] - native.width // 2,
                                       FOOT[1] - native.height))
        raw_frames.append(frame)

    # Build a shared palette solely from opaque generated pixels. Transparent
    # black cannot consume the palette or darken the source's light coat.
    opaque = [rgb[:3] for im in raw_frames for rgb in im.getdata() if rgb[3]]
    swatch = Image.new("RGB", (len(opaque), 1))
    swatch.putdata(opaque)
    palette = swatch.quantize(colors=32, method=Image.Quantize.MEDIANCUT,
                             dither=Image.Dither.NONE)
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for name, frame, bbox in zip(NAMES, raw_frames, bounds):
        converted = frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
        converted.putalpha(frame.getchannel("A"))
        destination = OUT / f"{name}.png"
        converted.save(destination)
        records.append({"name": name, "source_bbox_in_cell": bbox,
                        "native_bbox": converted.getbbox(), "sha256": sha256(destination)})

    preview = Image.new("RGBA", (CELL[0] * 4, CELL[1]), (15, 24, 30, 255))
    for index, name in enumerate(NAMES):
        preview.alpha_composite(Image.open(OUT / f"{name}.png").convert("RGBA"), (index * CELL[0], 0))
    preview.resize((preview.width * 8, preview.height * 8), Image.Resampling.NEAREST).save(META / "native_contact_sheet_8x.png")
    manifest = {
        "schema_version": 1, "character": "科伯恩 / Coburn",
        "source_document": "SK.txt", "canon": {"sex": "male", "age": 27,
            "job": "C区费列罗诊所主治医师", "shift": "8:00—14:30"},
        "visual_design_note": "Appearance is a visual adaptation; the script does not specify his face or clothing.",
        "generator": "built-in image_gen", "source_file": SOURCE.name,
        "source_sha256": sha256(SOURCE), "source_size": list(source.size),
        "prompt_file": "generation_prompt.txt", "native_frame_size": list(CELL),
        "foot_anchor": list(FOOT), "upright_body_height": BODY_HEIGHT,
        "uniform_source_to_native_scale": scale, "texture_filter": "nearest",
        "runtime_scale": [1, 1], "alpha_values": [0, 255], "palette_colors_max": 32,
        "resampling": "nearest", "dithering": "none", "frames": records,
        "protected": "Player frames, hospital background and collision dimensions unchanged."
    }
    (META / "import_record.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False))


if __name__ == "__main__":
    main()
