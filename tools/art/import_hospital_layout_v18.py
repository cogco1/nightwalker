"""Assemble generated hospital furniture on the existing native floor plan.

This performs image conversion/compositing, not substitute illustration: all
visible prop pixels are from the built-in image_gen atlas and all new floor
pixels are sampled from the built-in image_gen first-floor painting. Existing
walls, doors, stairs, corridors and side-view backgrounds remain registered.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
META = ROOT / "game/art_metadata/hospital_layout_v18"
ASSET = ROOT / "game/assets/underground_hospital"
PROP_OUT = META / "native_props"
GRID = ([0, 345, 655, 945, 1273], [0, 340, 640, 930, 1236])
PROPS = [
    ("bed", (32, 57)), ("bedside", (14, 27)), ("iv", (11, 43)), ("curtain", (16, 47)),
    ("pharmacy", (58, 62)), ("fridge", (32, 58)), ("supplies", (27, 61)), ("bench", (53, 24)),
    ("locker", (16, 36)), ("sink", (27, 30)), ("drawer", (19, 45)), ("monitor_cart", (24, 32)),
    ("small_files", (16, 31)), ("archive", (31, 42)), ("office_locker", (20, 43)), ("plant", (14, 23)),
]
PLACEMENTS = {
    1: [
        ("curtain", (145, 94)), ("bed", (182, 92)), ("bed", (252, 92)), ("bed", (319, 92)),
        ("bedside", (234, 94)), ("bedside", (302, 94)), ("iv", (222, 105)), ("iv", (291, 105)),
        ("pharmacy", (415, 94)), ("fridge", (490, 94)), ("fridge", (526, 94)), ("supplies", (580, 94)),
    ],
    2: [
        ("plant", (24, 43)), ("bench", (43, 43)), ("locker", (175, 43)),
        ("curtain", (203, 43)), ("sink", (222, 43)), ("drawer", (252, 43)),
        ("monitor_cart", (357, 43)), ("small_files", (428, 43)),
        ("archive", (451, 43)), ("office_locker", (600, 88)),
    ],
}
FLOORS = {1: [(140, 94, 252, 96), (404, 94, 216, 96)],
          2: [(20, 43, 171, 92), (203, 43, 207, 92), (422, 43, 198, 92)]}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rect_box(rect: list[int] | tuple[int, ...]) -> tuple[int, int, int, int]:
    x, y, w, h = rect
    return x, y, x + w, y + h


def palette_reduce(image: Image.Image, colors: int) -> Image.Image:
    alpha = image.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    image = image.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                                         dither=Image.Dither.NONE).convert("RGBA")
    image.putalpha(alpha)
    return image


def load_props() -> tuple[dict, list]:
    atlas = Image.open(META / "furniture_atlas_generated.png").convert("RGBA")
    result, records = {}, []
    PROP_OUT.mkdir(exist_ok=True)
    for index, (name, size) in enumerate(PROPS):
        row, col = divmod(index, 4)
        region = (GRID[0][col], GRID[1][row], GRID[0][col + 1], GRID[1][row + 1])
        cell = atlas.crop(region)
        bounds = cell.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()
        sprite = palette_reduce(cell.crop(bounds).resize(size, Image.Resampling.NEAREST), 48)
        sprite.save(PROP_OUT / f"{name}.png")
        result[name] = sprite
        records.append({"name": name, "source_region": region, "source_alpha_bbox": bounds,
                        "native_size": size, "native_sha256": digest(PROP_OUT / f"{name}.png")})
    surfaces = Image.open(META / "work_surfaces_generated.png").convert("RGBA")
    for name, size, region in [
        ("reception_counter", (71, 40), (0, 0, 960, 530)),
        ("surgery_table", (34, 49), (960, 0, 1536, 530)),
        ("office_desk", (68, 49), (0, 530, 960, 1024)),
        ("surgery_lamp", (40, 27), (960, 530, 1536, 1024)),
    ]:
        cell = surfaces.crop(region)
        bounds = cell.getchannel("A").point(lambda v: 255 if v >= 128 else 0).getbbox()
        sprite = palette_reduce(cell.crop(bounds).resize(size, Image.Resampling.NEAREST), 48)
        sprite.save(PROP_OUT / f"{name}.png")
        result[name] = sprite
        records.append({"name": name, "source_sheet": "work_surfaces_generated.png",
                        "source_region": region, "source_alpha_bbox": bounds, "native_size": size,
                        "native_sha256": digest(PROP_OUT / f"{name}.png")})
    return result, records


def tile_floor(image: Image.Image, tile: Image.Image, rect: tuple[int, int, int, int]) -> None:
    # The generated 32x32 floor tile is registered to the same world grid in
    # every room. It is never stretched or blurred to cover the native canvas.
    x, y, w, h = rect
    for ty in range(y, y + h, tile.height):
        for tx in range(x, x + w, tile.width):
            part = tile.crop((0, 0, min(tile.width, x + w - tx), min(tile.height, y + h - ty)))
            image.alpha_composite(part, (tx, ty))


def update_layout() -> dict:
    data = json.loads((META / "layout_before.json").read_text(encoding="utf-8"))
    floors = data["views"]["top_down"]["floors"]
    rects = {
        "1": {"bed_a": [182, 92, 32, 57], "bed_b": [252, 92, 32, 57], "bed_c": [319, 92, 32, 57],
              "ward_cabinet_a": [234, 94, 14, 27], "ward_cabinet_b": [302, 94, 14, 27],
              "ward_iv_a": [222, 141, 11, 7], "ward_iv_b": [291, 141, 11, 7],
              "ward_curtain": [145, 94, 16, 47], "medical_shelves": [415, 94, 58, 40],
              "lab_bench": [415, 134, 58, 22], "refrigerators": [490, 94, 68, 58],
              "east_supplies": [580, 94, 27, 61]},
        "2": {"reception_desk": [103, 43, 71, 40], "waiting_seats": [43, 43, 53, 24],
              "reception_cabinet": [175, 43, 16, 36], "surgery_table": [289, 76, 31, 43],
              "surgery_sink": [222, 43, 27, 30], "medical_cart": [357, 43, 24, 32],
              "office_desk": [543, 43, 68, 49], "files": [451, 43, 31, 42],
              "office_cabinet": [600, 88, 20, 43]},
    }
    for floor, updates in rects.items():
        for item in floors[floor]["colliders"]:
            if item["id"] in updates:
                item["rect"] = updates[item["id"]]
        floors[floor]["furniture_registration"] = "res://art_metadata/hospital_layout_v18/import_record.json"
    floors["2"]["colliders"].extend([
        {"id": "treatment_drawer", "rect": [252, 43, 19, 45]},
        {"id": "treatment_curtain", "rect": [203, 43, 16, 47]},
        {"id": "office_small_files", "rect": [428, 43, 16, 31]},
        {"id": "reception_plant", "rect": [24, 43, 14, 23]},
    ])
    floors["1"]["monitors"] = [{"id": "cold_led_0", "rect": [513, 102, 4, 2]},
                                   {"id": "cold_led_1", "rect": [549, 102, 4, 2]}]
    floors["2"]["monitors"] = [{"id": "upper_screen_0", "rect": [114, 52, 7, 5]},
                                   {"id": "upper_screen_1", "rect": [363, 46, 11, 8]},
                                   {"id": "upper_screen_2", "rect": [554, 54, 8, 7]}]
    for item in data["interactions"]:
        if item["id"] == "stairs_up":
            item["top_down_trigger_rect"] = [32, 112, 58, 76]
        elif item["id"] == "stairs_down":
            item["top_down_trigger_rect"] = [29, 84, 55, 52]
        elif item["id"] == "archive":
            item["anchors"]["top_down"] = [469, 100]
        elif item["id"] == "reception_pc":
            item["anchors"]["top_down"] = [132, 96]
        elif item["id"] == "duty_record":
            item["anchors"]["top_down"] = [574, 106]
    data["interactions"].append({
        "id": "treatment_drawer", "title": "水槽旁抽屉", "floor_id": 2,
        "room_id": "treatment", "kind": "inspect", "anchors": {"top_down": [261, 100]},
        "radius": 18, "drawer_rect": [255, 78, 14, 7], "lines": ["抽屉里的便签写着：1010。"]})
    data["power_sections"]["clinical"]["top_down"]["screen_rects"] = [
        item["rect"] for item in floors["2"]["monitors"]]
    data["design_notes"] += " Native layout v18: short north wall at y43; wall-attached furniture bodies fully block their backs; generated upright props replace floor-like silhouettes. Side view unchanged."
    return data


def main() -> None:
    props, records = load_props()
    generated = Image.open(META / "floor_1_generated.png").convert("RGBA").resize((640, 224), Image.Resampling.NEAREST)
    tile = palette_reduce(generated.crop((170, 154, 202, 178)), 32)
    tile.save(META / "floor_tile_native.png")
    placement_records = []
    for floor in (1, 2):
        image = Image.open(META / f"floor_{floor}_before.png").convert("RGBA")
        for area in FLOORS[floor]:
            tile_floor(image, tile, area)
        if floor == 2:
            for name, point in [("reception_counter", (103, 43)),
                                ("surgery_table", (288, 74)),
                                ("office_desk", (543, 43)),
                                ("surgery_lamp", (286, 36))]:
                sprite = props[name]
                image.alpha_composite(sprite, point)
                placement_records.append({"floor": floor, "name": name, "visual_rect": [*point, *sprite.size],
                                          "source": f"native_props/{name}.png"})
            # The left stair is structural, not a room prop. Restore its exact
            # original pixels after replacing the surrounding floor material.
            before = Image.open(META / "floor_2_before.png").convert("RGBA")
            stair_rect = (27, 90, 45, 45)
            image.alpha_composite(before.crop(rect_box(stair_rect)), (stair_rect[0], stair_rect[1]))
        for name, point in PLACEMENTS[floor]:
            sprite = props[name]
            image.alpha_composite(sprite, point)
            placement_records.append({"floor": floor, "name": name,
                                      "visual_rect": [*point, *sprite.size],
                                      "source": f"native_props/{name}.png"})
        destination = ASSET / f"hospital_floor_{floor}_native.png"
        image.save(destination)
        image.resize((2560, 896), Image.Resampling.NEAREST).save(META / f"floor_{floor}_final_4x.png")
    layout = update_layout()
    (ASSET / "layout.json").write_text(json.dumps(layout, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    manifest = {
        "schema_version": 1, "generator": "built-in image_gen", "native_size": [640, 224],
        "source_files": [{"path": name, "sha256": digest(META / name)} for name in
                         ["floor_1_generated.png", "floor_2_generated.png", "furniture_atlas_generated.png", "work_surfaces_generated.png"]],
        "prompts": ["floor_1_prompt.txt", "floor_2_prompt.txt", "furniture_atlas_prompt.txt", "work_surfaces_prompt.txt"],
        "conversion": {"resampling": "nearest", "palette_colors_per_prop_max": 48,
                       "dithering": "none", "prop_alpha_values": [0, 255]},
        "floor_regions": FLOORS, "floor_tile_source_native_rect": [170, 154, 32, 24],
        "props": records, "placements": placement_records,
        "collision_rects": {key: [{"id": item["id"], "collision_rect": item["rect"]}
                                    for item in floor["colliders"]]
                            for key, floor in layout["views"]["top_down"]["floors"].items()},
        "protected": ["side view", "corridor bounds", "original doorway coordinates", "stairs geometry",
                      "player scale and frames", "Coburn foot 492,82 and rear approach 492,64"],
        "outputs": [{"path": f"hospital_floor_{floor}_native.png",
                     "sha256": digest(ASSET / f"hospital_floor_{floor}_native.png")} for floor in (1, 2)],
    }
    (META / "import_record.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Converted generated props and floor material; registered 2 native hospital floors and layout.")


if __name__ == "__main__":
    main()
