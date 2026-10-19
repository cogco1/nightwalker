"""Compose imagegen-painted taller architecture without changing game pixel size.

The user authorized local alignment and compositing of generated paintings.  This
offline builder moves painted sections by whole pixels; it does not stretch old
buildings, redraw architecture, or modify the player's physical ground profile.
"""
from __future__ import annotations

import argparse
from collections import deque
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs/battlefield_tall_v05"
BASELINE = ROOT / "outputs/battlefield_depth_v04/battlefield_near_native.png"
BASELINES = {"near": BASELINE,
             "mid": ROOT / "outputs/battlefield_depth_v04/battlefield_mid_native.png",
             "far": ROOT / "outputs/battlefield_depth_v04/battlefield_far_native.png"}
EVIDENCE = ROOT / "game/evidence/battlefield_run_test"
PART_W, HEIGHT, COUNT = 768, 512, 8
WIDTH, OLD_HEIGHT, ORIGIN_Y = PART_W * COUNT, 256, -256
FLAT_FOOT, FAR_HORIZON = 424, 406
POINTS = [[0, 224], [140, 224], [224, 168], [WIDTH, 168]]
LAYERS = {
    "near": ("main_architecture", "battlefield_layer_01", "battlefield_layer_01_native.png", 1.0, -10),
    "mid": ("middle_buildings_and_factories", "battlefield_mid_background", "battlefield_mid_native.png", 0.58, -15),
    "far": ("distant_city_and_industry", "battlefield_far_background", "battlefield_far_native.png", 0.28, -20),
}


def source_pixels(layer: str, number: int) -> tuple[np.ndarray, dict]:
    path = OUTPUT / f"{layer}_sources" / f"{layer}_{number:02}.png"
    with Image.open(path) as source:
        original_size = source.size
        # Requiring the requested 3:2 canvas prevents accidental anisotropic
        # scaling if the image service returns a different canvas orientation.
        if abs(source.width / source.height - PART_W / HEIGHT) > 0.025:
            raise ValueError(f"{path.name}: expected a 3:2 canvas, got {source.size}")
        pixels = np.array(source.convert("RGBA").resize(
            (PART_W, HEIGHT), Image.Resampling.NEAREST))
    if layer != "far":
        r, g, b = [pixels[:, :, channel].astype(np.int16) for channel in range(3)]
        fringe = ((r > 190) & (g < 85) & (b < 95))
        fringe |= (g > 190) & (r < 110) & (b < 140)
        fringe |= (r > 215) & (g > 205) & (b < 65)
        visible = (pixels[:, :, 3] >= 128) & ~fringe
        if not visible.any() or visible.all():
            raise ValueError(f"{path.name}: visible architecture and real transparency are required")
        pixels[:, :, 3] = np.where(visible, 255, 0)
        pixels[~visible] = 0
    return pixels, {"section": number, "source": str(path.relative_to(ROOT)),
                    "source_size": list(original_size), "normalized_size": [PART_W, HEIGHT]}


def move_pixels(pixels: np.ndarray, offset: int, opaque: bool = False) -> np.ndarray:
    if abs(offset) >= HEIGHT:
        raise ValueError(f"Vertical alignment offset exceeds the canvas: {offset}")
    if opaque:
        result = np.repeat(pixels[:1] if offset >= 0 else pixels[-1:], HEIGHT, axis=0)
    else:
        result = np.zeros_like(pixels)
    if offset > 0:
        result[offset:] = pixels[:-offset]
    elif offset < 0:
        result[:offset] = pixels[-offset:]
    else:
        result[:] = pixels
    return result


def sand_surface(pixels: np.ndarray) -> np.ndarray:
    """Find the connected sand cap, excluding separate amber window pixels."""
    r, g, b = [pixels[:, :, channel].astype(np.float32) for channel in range(3)]
    sand = ((pixels[:, :, 3] > 0) & (r > 135) & (g > 80)
            & (r > g * 1.12) & (g > b * 1.28) & (b < 150))
    seen = np.zeros(sand.shape, bool)
    candidates: list[tuple[float, np.ndarray]] = []
    for yy, xx in zip(*np.nonzero(sand)):
        if seen[yy, xx]:
            continue
        pending = deque([(int(yy), int(xx))])
        seen[yy, xx] = True
        region = []
        while pending:
            y, x = pending.popleft()
            region.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < HEIGHT and 0 <= nx < PART_W and sand[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    pending.append((ny, nx))
        # New paintings contain a second sand area BELOW the retaining face.
        # Its area is often larger; the walkable cap is the upper continuous
        # band spanning most columns, not the largest yellow component.
        if len(region) >= PART_W * 0.8:
            tops = np.full(PART_W, HEIGHT, np.int32)
            for y, x in region:
                tops[x] = min(tops[x], y)
            covered = tops < HEIGHT
            if int(covered.sum()) >= PART_W * 0.8:
                candidates.append((float(np.median(tops[covered])), tops))
    if not candidates:
        raise ValueError("A connected sand strip must span at least 80% of each near section")
    tops = min(candidates, key=lambda candidate: candidate[0])[1]
    good = np.flatnonzero(tops < HEIGHT)
    return np.rint(np.interp(np.arange(PART_W), good, tops[good])).astype(np.int32)


def world_surface(x: int) -> int:
    for (ax, ay), (bx, by) in zip(POINTS, POINTS[1:]):
        if x <= bx:
            return round(ay + (by - ay) * (x - ax) / (bx - ax))
    return POINTS[-1][1]


def make_palette(colors: np.ndarray) -> Image.Image:
    palette = Image.new("P", (1, 1))
    palette.putpalette(np.tile(colors, (256 // len(colors) + 1, 1))[:256].ravel().tolist())
    return palette


def baseline_palette(layer: str) -> Image.Image:
    with Image.open(BASELINES[layer]) as source:
        pixels = np.array(source.convert("RGBA"))
    colors = np.unique(pixels[:, :, :3][pixels[:, :, 3] > 0], axis=0)
    limit = 48 if layer == "far" else 64
    if len(colors) > limit:
        raise ValueError(f"{layer}: approved baseline exceeds its {limit}-color palette")
    return make_palette(colors)


def quantize_cutout(canvas: np.ndarray, colors: int, fixed_palette: Image.Image | None = None) -> Image.Image:
    visible = canvas[:, :, 3] == 255
    if fixed_palette is None:
        sample = Image.fromarray(canvas[:, :, :3][visible].reshape(1, -1, 3))
        reduced = sample.quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                                  dither=Image.Dither.NONE)
        color_values = np.array(reduced.getpalette(), np.uint8).reshape(-1, 3)
        fixed_palette = make_palette(color_values[[index for _, index in reduced.getcolors()]])
    rgb = Image.fromarray(canvas[:, :, :3]).quantize(
        palette=fixed_palette, dither=Image.Dither.NONE).convert("RGB")
    result = np.dstack([np.array(rgb), canvas[:, :, 3]])
    result[~visible] = 0
    return Image.fromarray(result)


def build_near(baseline: np.ndarray) -> tuple[Image.Image, list[dict], dict]:
    canvas = np.zeros((HEIGHT, WIDTH, 4), np.uint8)
    records = []
    for number in range(1, COUNT + 1):
        pixels, record = source_pixels("near", number)
        tops = sand_surface(pixels)
        # The first source contains the entrance slope; use its flat plateau.
        samples = tops[350:] if number == 1 else tops
        offset = FLAT_FOOT - int(np.median(samples))
        architecture = move_pixels(pixels, offset)
        for local_x in range(PART_W):
            ground = world_surface((number - 1) * PART_W + local_x) - ORIGIN_Y
            architecture[max(0, min(ground, int(tops[local_x]) + offset)):, local_x] = 0
            occupied = np.flatnonzero(architecture[:, local_x, 3])
            if len(occupied):
                last = int(occupied[-1])
                # Close only a small foot gap using existing painted foot pixels.
                if 1 < ground - last <= 9:
                    architecture[last + 1:ground, local_x] = architecture[last, local_x]
        canvas[:, (number - 1) * PART_W:number * PART_W] = architecture
        record.update(source_foot=int(np.median(samples)), vertical_offset=offset,
                      target_flat_foot=FLAT_FOOT)
        records.append(record)
    old_visible = baseline[:, :, 3] == 255
    palette_colors = np.unique(baseline[:, :, :3][old_visible], axis=0)
    if len(palette_colors) > 64:
        raise ValueError("The preserved near baseline must use no more than 64 colors")
    result = np.array(quantize_cutout(canvas, 64, make_palette(palette_colors)))
    # Ground is copied AFTER quantization.  No terrain pixel, world coordinate,
    # slope shape, or original palette value can change during composition.
    surfaces = np.array([world_surface(x) for x in range(WIDTH)])
    old_ground = np.arange(OLD_HEIGHT)[:, None] >= surfaces[None, :]
    result[-ORIGIN_Y:][old_ground] = baseline[old_ground]
    same = np.array_equal(result[-ORIGIN_Y:][old_ground], baseline[old_ground])
    if not same:
        raise AssertionError("Existing ground pixels changed")
    for index, record in enumerate(records):
        start, end = index * PART_W, (index + 1) * PART_W
        section_surface = surfaces[start:end]
        summaries = []
        for artwork, origin_shift in ((baseline, 0), (result, -ORIGIN_Y)):
            mask = artwork[:, start:end, 3] > 0
            mask &= np.arange(artwork.shape[0])[:, None] < (section_surface + origin_shift)[None, :]
            top = np.where(mask.any(axis=0), mask.argmax(axis=0), section_surface + origin_shift)
            column_heights = section_surface + origin_shift - top
            # Ignore isolated feet and tiny source remnants when comparing
            # the building silhouette against the preceding approved artwork.
            structural = column_heights[column_heights > 8]
            summaries.append({"median_column_height": float(np.median(structural)),
                              "p95_column_height": float(np.percentile(column_heights, 95)),
                              "max_height": int(column_heights.max())})
        record["silhouette_height_old"] = summaries[0]
        record["silhouette_height_new"] = summaries[1]
        record["median_height_ratio"] = round(
            summaries[1]["median_column_height"] / summaries[0]["median_column_height"], 4)
    ground_bytes = baseline[old_ground].tobytes()
    report = {"baseline": str(BASELINE.relative_to(ROOT)), "ground_pixels_unchanged": same,
              "preserved_ground_pixel_count": int(old_ground.sum()),
              "ground_rgba_sha256": hashlib.sha256(ground_bytes).hexdigest(),
              "ground_points_world": POINTS, "palette_strategy": "preserve all existing near colors"}
    return Image.fromarray(result), records, report


def build_mid() -> tuple[Image.Image, list[dict], dict]:
    pieces, records = [], []
    for number in range(1, COUNT + 1):
        pixels, record = source_pixels("mid", number)
        visible = pixels[:, :, 3] == 255
        occupied_columns = visible.any(axis=0)
        bottoms = HEIGHT - np.argmax(visible[::-1], axis=0) - 1
        foot = int(np.median(bottoms[occupied_columns]))
        offset = FLAT_FOOT - foot
        pieces.append(move_pixels(pixels, offset))
        record.update(source_foot=foot, vertical_offset=offset, target_foot=FLAT_FOOT)
        records.append(record)
    with Image.open(BASELINES["mid"]) as source:
        old_pixels = np.array(source.convert("RGBA"))
    canvas = np.concatenate(pieces, axis=1)
    visible = canvas[:, :, 3] == 255
    luma_weights = np.array([0.2126, 0.7152, 0.0722])
    old_luma = float((old_pixels[:, :, :3][old_pixels[:, :, 3] > 0] @ luma_weights).mean())
    source_luma = float((canvas[:, :, :3][visible] @ luma_weights).mean())
    # The new paintings retain the approved night palette and brightness.  One
    # shared gain preserves relative shading, materials, and window highlights.
    gain = min(1.0, old_luma / source_luma)
    canvas[visible, :3] = np.rint(canvas[visible, :3].astype(float) * gain).astype(np.uint8)
    calibrated_luma = float((canvas[:, :, :3][visible] @ luma_weights).mean())
    result = quantize_cutout(canvas, 64, baseline_palette("mid"))
    new_pixels = np.array(result)
    output_luma = float((new_pixels[:, :, :3][visible] @ luma_weights).mean())
    brightness = {"method": "one uniform visible-RGB gain, then approved fixed palette",
                  "gain": gain, "baseline_visible_mean_luma": old_luma,
                  "source_visible_mean_luma": source_luma,
                  "calibrated_visible_mean_luma": calibrated_luma,
                  "output_visible_mean_luma": output_luma}
    for index, record in enumerate(records):
        summaries = []
        for pixels in (old_pixels, new_pixels):
            visible = pixels[:, index * PART_W:(index + 1) * PART_W, 3] > 0
            bottom = pixels.shape[0] - 1 - np.argmax(visible[::-1], axis=0)
            heights = bottom - np.argmax(visible, axis=0) + 1
            structural = heights[visible.any(axis=0) & (heights > 8)]
            summaries.append({"median_column_height": float(np.median(structural)),
                              "p95_column_height": float(np.percentile(structural, 95)),
                              "max_height": int(structural.max())})
        record["silhouette_height_old"] = summaries[0]
        record["silhouette_height_new"] = summaries[1]
        record["median_height_ratio"] = round(
            summaries[1]["median_column_height"] / summaries[0]["median_column_height"], 4)
    return result, records, brightness


def build_far(source_horizon: int) -> tuple[Image.Image, list[dict]]:
    pieces, records = [], []
    offset = FAR_HORIZON - source_horizon
    for number in range(1, COUNT + 1):
        pixels, record = source_pixels("far", number)
        pieces.append(move_pixels(pixels[:, :, :3], offset, opaque=True))
        record.update(source_horizon=source_horizon, vertical_offset=offset,
                      target_horizon=FAR_HORIZON)
        records.append(record)
    canvas = np.concatenate(pieces, axis=1)
    seam_width = 16
    for seam in range(PART_W, WIDTH, PART_W):
        left = canvas[:, seam - seam_width // 2 - 1].astype(np.float32)
        right = canvas[:, seam + seam_width // 2].astype(np.float32)
        for offset_x in range(seam_width):
            amount = (offset_x + 1) / (seam_width + 1)
            canvas[:, seam - seam_width // 2 + offset_x] = np.rint(
                left * (1 - amount) + right * amount).astype(np.uint8)
    image = Image.fromarray(canvas).quantize(palette=baseline_palette("far"),
                                            dither=Image.Dither.NONE).convert("RGB")
    return image, records


def save_layer(image: Image.Image, name: str, records: list[dict]) -> dict:
    role, asset_dir, runtime_name, ratio, z_index = LAYERS[name]
    native_path = OUTPUT / f"battlefield_{name}_native.png"
    display_path = OUTPUT / f"battlefield_{name}_12288x1024.png"
    image.save(native_path, optimize=True)
    runtime_path = ROOT / "game/assets" / asset_dir / runtime_name
    runtime_path.parent.mkdir(parents=True, exist_ok=True)
    runtime_path.write_bytes(native_path.read_bytes())
    image.resize((WIDTH * 2, HEIGHT * 2), Image.Resampling.NEAREST).save(display_path, optimize=True)
    contact = Image.new("RGB", (PART_W * 2, HEIGHT * 4), "#22272b")
    for section in range(COUNT):
        piece = image.crop((section * PART_W, 0, (section + 1) * PART_W, HEIGHT))
        contact.paste(piece, ((section % 2) * PART_W, (section // 2) * HEIGHT),
                      piece.getchannel("A") if image.mode == "RGBA" else None)
    contact.save(OUTPUT / f"{name}_contact_sheet.png")
    contact.save(EVIDENCE / f"{name}_contact_sheet.png")
    pixels = np.array(image)
    visible = pixels[:, :, 3] == 255 if image.mode == "RGBA" else np.ones((HEIGHT, WIDTH), bool)
    return {"role": role, "native_size": [WIDTH, HEIGHT], "art_size": [WIDTH, HEIGHT],
            "world_size": [WIDTH, OLD_HEIGHT], "display_size": [WIDTH * 2, HEIGHT * 2],
            "origin": [0, ORIGIN_Y], "scroll_scale_x": ratio, "z_index": z_index,
            "architecture_height_target": "approximately 2x, redrawn by imagegen",
            "pixel_scale": 1, "opaque": image.mode == "RGB",
            "alpha_values": sorted(np.unique(pixels[:, :, 3]).tolist()) if image.mode == "RGBA" else [255],
            "colors": len(np.unique(pixels[:, :, :3][visible], axis=0)),
            "native_sha256": hashlib.sha256(native_path.read_bytes()).hexdigest(),
            "display_sha256": hashlib.sha256(display_path.read_bytes()).hexdigest(),
            "runtime_path": str(runtime_path.relative_to(ROOT)), "source_art": "built-in-imagegen",
            "source_sections": COUNT, "sections": records,
            "palette_strategy": "use the approved v04 layer's fixed visible RGB palette",
            "palette_baseline": str(BASELINES[name].relative_to(ROOT))}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--far-horizon", type=int, default=424,
                        help="Native source skyline foot before vertical alignment (default: 424)")
    args = parser.parse_args()
    with Image.open(BASELINE) as old:
        if old.size != (WIDTH, OLD_HEIGHT):
            raise ValueError(f"Unexpected near baseline size: {old.size}")
        baseline = np.array(old.convert("RGBA"))
    # Read and validate every generated source before replacing runtime assets.
    near, near_records, ground_report = build_near(baseline)
    mid, mid_records, mid_brightness = build_mid()
    far, far_records = build_far(args.far_horizon)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    info = {"date": "2026-10-20", "origin": [0, ORIGIN_Y],
            "world_size": [WIDTH, OLD_HEIGHT], "native_art_size": [WIDTH, HEIGHT],
            "ground": ground_report,
            "near": save_layer(near, "near", near_records),
            "mid": save_layer(mid, "mid", mid_records),
            "far": save_layer(far, "far", far_records)}
    info["mid"]["brightness_calibration"] = mid_brightness
    (OUTPUT / "layer_info.json").write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(info, ensure_ascii=False))


if __name__ == "__main__":
    main()
