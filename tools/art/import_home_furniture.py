"""Bake generated furniture, warm wood and worn plum materials at 320x180.

Run from any directory: python tools/art/import_home_furniture.py
The generated source, native sprites and placement/palette record are retained
under game/art_metadata/home_furniture_warm_v16 (excluded from Godot import).
The original background stays intact; only a sibling furnished bitmap is written.
"""
from collections import Counter
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "game/art_metadata/home_furniture_warm_v16"
BASE = ROOT / "game/assets/home_601/home_601_native.png"
OUT = ROOT / "game/assets/home_601/home_601_furnished_native.png"
SOURCE = ART / "furniture_atlas_generated.png"
MATERIAL_SOURCE = ART / "interior_materials_generated.png"
PLACEMENTS = [
    ("bookshelf", [90, 24, 18, 34]),
    ("repair_desk", [94, 64, 25, 20]),
    ("stool", [96, 126, 12, 14]),
    ("storage_box", [219, 132, 16, 14]),
    ("folding_chair", [229, 82, 12, 18]),
    ("bedside_lamp", [231, 48, 10, 12]),
]
WARM = [
    "17141a", "271f22", "39302a", "534136", "70523b", "96643f",
    "b77b43", "d99b53", "f6bf65", "ffdc8a", "491e26", "652d2f",
    "8a4141", "a2564d", "15252a", "263a3c", "a6a09a",
]
FLOOR_REGIONS = [[26, 60, 178, 92], [214, 60, 80, 92], [204, 101, 10, 22]]
OLD_PROP_PROTECTION = [
    [35, 39, 50, 41], [84, 58, 8, 16], [114, 20, 28, 49],
    [163, 39, 38, 32], [122, 100, 66, 28], [139, 81, 34, 18],
    [21, 93, 24, 51], [44, 115, 45, 28], [245, 50, 35, 63],
    [228, 47, 16, 30], [285, 48, 16, 68], [285, 113, 16, 18],
    [248, 122, 30, 20],
]
WALL_REGIONS = [[27, 19, 177, 41], [214, 19, 80, 41]]
WALL_PROTECTION = OLD_PROP_PROTECTION + [[31, 18, 73, 36], [217, 18, 72, 36], [149, 20, 25, 26]]
DECOR = [
    ("worn_rug", 2, [133, 80, 47, 23]),
    ("table_clutter", 3, [145, 80, 15, 9]),
    ("faded_poster", 4, [178, 20, 14, 16]),
    ("sofa_throw", 5, [132, 103, 35, 12]),
]


def rectangle_mask(regions, protected):
    mask = Image.new("L", (320, 180), 0)
    draw = ImageDraw.Draw(mask)
    for values, fill in [(r, 255) for r in regions] + [(r, 0) for r in protected]:
        x, y, w, h = values
        draw.rectangle((x, y, x + w - 1, y + h - 1), fill=fill)
    return mask


def generated_materials():
    source = Image.open(MATERIAL_SOURCE).convert("RGBA")
    assert source.size == (1536, 1024)
    # A shared material palette preserves the warm wood, plum wall, paper and teal.
    small = source.resize((192, 128), Image.Resampling.BOX)
    palette = small.convert("RGB").quantize(colors=48, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    textures = []
    for index, name in enumerate(["wood_floor", "plum_wall"]):
        cell = source.crop((index * 512 + 16, 16, index * 512 + 496, 496))
        texture = cell.convert("RGB").resize((64, 64), Image.Resampling.BOX).quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
        texture.putalpha(255)
        texture.save(ART / (name + "_native.png"))
        textures.append(texture)
    decorations = []
    for name, index, rect in DECOR:
        column, row = index % 3, index // 3
        cell = source.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512))
        bounds = cell.getchannel("A").point(lambda a: 255 if a >= 160 else 0).getbbox()
        assert bounds, name
        resized = cell.crop(bounds).resize(tuple(rect[2:]), Image.Resampling.BOX)
        texture = resized.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
        texture.putalpha(resized.getchannel("A").point(lambda a: 255 if a >= 160 else 0))
        texture.save(ART / (name + "_native.png"))
        decorations.append((name, rect, texture))
    return textures, decorations


def paint_material(canvas, mask, texture):
    for y in range(180):
        for x in range(320):
            if mask.getpixel((x, y)):
                canvas.putpixel((x, y), texture.getpixel((x % texture.width, y % texture.height)))


def main():
    original = Image.open(BASE).convert("RGBA")
    atlas = Image.open(SOURCE).convert("RGBA")
    assert original.size == (320, 180) and atlas.size == (1536, 1024)
    # Use the room's existing clustered colors plus a small shared warm ramp.
    palette = [rgb for rgb, _ in Counter(original.convert("RGB").get_flattened_data()).most_common(31)]
    palette += [tuple(bytes.fromhex(value)) for value in WARM]
    palette = list(dict.fromkeys(palette))
    swatch = Image.new("P", (1, 1))
    data = [channel for color in palette for channel in color]
    swatch.putpalette(data + list(palette[0]) * (256 - len(palette)))
    composed = original.copy()
    materials, decorations = generated_materials()
    floor_mask = rectangle_mask(FLOOR_REGIONS, OLD_PROP_PROTECTION)
    wall_mask = rectangle_mask(WALL_REGIONS, WALL_PROTECTION)
    floor_mask.save(ART / "floor_mask.png")
    wall_mask.save(ART / "wall_mask.png")
    paint_material(composed, floor_mask, materials[0])
    paint_material(composed, wall_mask, materials[1])
    # The rug sits below the original solid furniture, not over its silhouettes.
    for name, rect, texture in decorations:
        if name != "worn_rug":
            continue
        texture = texture.copy()
        for y in range(texture.height):
            for x in range(texture.width):
                if not floor_mask.getpixel((rect[0] + x, rect[1] + y)):
                    texture.putpixel((x, y), (0, 0, 0, 0))
        composed.alpha_composite(texture, tuple(rect[:2]))
    records = []
    for index, (name, rect) in enumerate(PLACEMENTS):
        column, row = index % 3, index // 3
        tile = atlas.crop((column * 512, row * 512, (column + 1) * 512, (row + 1) * 512))
        # Drop the generator's translucent halo. Runtime light handles glow.
        silhouette = tile.getchannel("A").point(lambda a: 255 if a >= 160 else 0)
        source_bounds = silhouette.getbbox()
        assert source_bounds, name
        raw = tile.crop(source_bounds)
        resized = raw.resize(tuple(rect[2:]), Image.Resampling.BOX)
        colors = resized.convert("RGB").quantize(palette=swatch, dither=Image.Dither.NONE).convert("RGBA")
        colors.putalpha(resized.getchannel("A").point(lambda a: 255 if a >= 160 else 0))
        colors.save(ART / (name + "_native.png"))
        composed.alpha_composite(colors, tuple(rect[:2]))
        records.append({"id": name, "rect": rect, "source_cell": [column, row],
                        "source_crop": source_bounds, "native_sprite": name + "_native.png"})
    for name, rect, texture in decorations:
        if name != "worn_rug":
            composed.alpha_composite(texture, tuple(rect[:2]))
    composed.save(OUT)
    # The user explicitly requested warm flooring and a fuller apartment look.
    # Changes may touch material masks and approved props, never the old screens.
    changed = 0
    allowed = [rect for _, rect in PLACEMENTS] + [rect for _, _, rect in DECOR]
    for y in range(180):
        for x in range(320):
            if composed.getpixel((x, y)) == original.getpixel((x, y)):
                continue
            changed += 1
            assert floor_mask.getpixel((x, y)) or wall_mask.getpixel((x, y)) or any(rx <= x < rx + w and ry <= y < ry + h for rx, ry, w, h in allowed)
    for rect in [[52, 44, 14, 8], [178, 48, 16, 10], [150, 22, 22, 22]]:
        x, y, w, h = rect
        assert composed.crop((x, y, x + w, y + h)).tobytes() == original.crop((x, y, x + w, y + h)).tobytes()
    record = {"schema_version": 2, "generator": "built-in image_gen", "native_size": [320, 180],
              "palette_rgb": palette, "alpha_threshold": 160, "dither": False,
              "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              "materials_source_sha256": hashlib.sha256(MATERIAL_SOURCE.read_bytes()).hexdigest(),
              "material_palette_size": 48,
              "style_reference_input": "blue_floor_furniture_candidate.png",
              "style_reference_input_sha256": hashlib.sha256((ART / "blue_floor_furniture_candidate.png").read_bytes()).hexdigest(),
              "visual_reference": "Katana ZERO apartment atmosphere, translated into the existing top-down layout; all new materials are original generated assets",
              "reference_urls": ["https://www.nintendolife.com/reviews/switch-eshop/katana_zero", "https://www.steamgriddb.com/game/11465/heroes"],
              "base_sha256": hashlib.sha256(BASE.read_bytes()).hexdigest(),
              "output_sha256": hashlib.sha256(OUT.read_bytes()).hexdigest(),
              "output": str(OUT.relative_to(ROOT)).replace("\\", "/"),
              "changed_native_pixels": changed, "placements": records,
              "floor_regions": FLOOR_REGIONS, "floor_protection": OLD_PROP_PROTECTION,
              "wall_regions": WALL_REGIONS, "wall_protection": WALL_PROTECTION,
              "decor": [{"id": name, "rect": rect} for name, _, rect in DECOR],
              "floor_pixels": sum(1 for v in floor_mask.get_flattened_data() if v),
              "wall_pixels": sum(1 for v in wall_mask.get_flattened_data() if v),
              "protected_screens_and_empty_frame": "unchanged"}
    (ART / "import_record.json").write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(OUT), "changed_native_pixels": changed, "sprite_palette": len(palette)}))


if __name__ == "__main__":
    main()
