"""Align generated building and wreck cutouts to the game's native pixel grid.

This offline tool only crops, scales uniformly, aligns, and palette-matches
imagegen artwork.  It does not paint structures, draw vehicles, or make physics
geometry; collision placement is chosen from the finished native-pixel images.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs/battlefield_traversal_v06"
SOURCES = OUTPUT / "source_art"
DELIVERED = OUTPUT / "asset_images"
RUNTIME = ROOT / "game/assets/battlefield_traversal"
PALETTE_REFERENCE = ROOT / "outputs/battlefield_tall_v05/battlefield_near_native.png"
ASSETS = {"gatehouse": (256, 256), "tower": (256, 256),
          "wreck_sedan": (96, 48), "wreck_van": (112, 64), "wreck_truck": (128, 64)}


def composite_person_doors(image: Image.Image, palette: Image.Image) -> dict:
    """Insert generated taller door pixels, preserving every deck and alpha edge."""
    path = SOURCES / "gatehouse_door_edit.png"
    with Image.open(path) as source:
        # Coordinates are recorded in the 256px reference coordinate system.
        crop = (57, 156, 78, 187)
        bounds = tuple(round(value * source.width / 256) for value in crop)
        patch = source.convert("RGB").crop(bounds)
    size = (round(patch.width * 34 / patch.height), 34)
    patch = patch.resize(size, Image.Resampling.NEAREST)
    patch = patch.quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
    original = image.copy()
    alpha = image.getchannel("A")
    positions = [(57, 153), (193, 153)]
    for position in positions:
        image.paste(patch, position)
        # Retain the existing foreground handrail in front of the new doorway.
        x, _ = position
        for top, bottom in ((178, 180), (184, 187)):
            image.paste(original.crop((x, top, x + size[0], bottom)), (x, top))
    image.putalpha(alpha)
    return {"source": str(path.relative_to(ROOT)),
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "reference_crop": list(crop), "generated_pixel_crop": list(bounds),
            "native_size": list(size), "placements": positions,
            "alpha_and_decks_preserved": True}


def approved_palette() -> tuple[Image.Image, int]:
    with Image.open(PALETTE_REFERENCE) as source:
        pixels = np.array(source.convert("RGBA"))
    colors = np.unique(pixels[:, :, :3][pixels[:, :, 3] > 0], axis=0)
    if not 1 <= len(colors) <= 64:
        raise ValueError("The approved v05 near layer must contain at most 64 visible RGB colors")
    palette = Image.new("P", (1, 1))
    palette.putpalette(np.tile(colors, (256 // len(colors) + 1, 1))[:256].ravel().tolist())
    return palette, len(colors)


def clean_cutout(path: Path) -> tuple[Image.Image, dict]:
    with Image.open(path) as source:
        pixels = np.array(source.convert("RGBA"))
    visible = pixels[:, :, 3] >= 128
    if not visible.any() or visible.all():
        raise ValueError(f"{path.name} requires visible art and a real transparent background")
    # Remove only saturated matte-colored OUTER edge pixels.  Rust, ochre,
    # yellow-brown paint, and colored details inside the silhouette are retained.
    r, g, b = [pixels[:, :, channel].astype(np.int16) for channel in range(3)]
    matte = ((r >= 240) & (g <= 24) & (b <= 24))
    matte |= (g >= 240) & (r <= 24) & (b <= 24)
    matte |= (r >= 245) & (g >= 245) & (b <= 16) & (np.abs(r - g) <= 10)
    padded = np.pad(visible, 1, constant_values=False)
    interior = (padded[1:-1, :-2] & padded[1:-1, 2:]
                & padded[:-2, 1:-1] & padded[2:, 1:-1])
    fringe = matte & visible & ~interior
    visible &= ~fringe
    pixels[:, :, 3] = np.where(visible, 255, 0)
    pixels[~visible] = 0
    cutout = Image.fromarray(pixels)
    bounds = cutout.getchannel("A").getbbox()
    if bounds is None:
        raise ValueError(f"{path.name}: no artwork remains after matte cleanup")
    return cutout.crop(bounds), {"source": str(path.relative_to(ROOT)),
                                "source_canvas": [pixels.shape[1], pixels.shape[0]],
                                "source_cutout_rect": list(bounds),
                                "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                                "matte_edge_pixels_removed": int(fringe.sum())}


def prepare_asset(name: str, size: tuple[int, int], palette: Image.Image) -> tuple[Image.Image, dict]:
    cutout, info = clean_cutout(SOURCES / f"{name}.png")
    scale = min(size[0] / cutout.width, size[1] / cutout.height)
    # The single scale preserves source proportions.  Rounding merely selects
    # the nearest whole-pixel rectangle; horizontal/vertical stretching is absent.
    fitted_size = (max(1, min(size[0], round(cutout.width * scale))),
                   max(1, min(size[1], round(cutout.height * scale))))
    cutout = cutout.resize(fitted_size, Image.Resampling.NEAREST)
    # A very thin source edge can disappear while downsampling.  Trim any
    # resulting empty native rows/columns before anchoring the visible baseline.
    sampled_bounds = cutout.getchannel("A").getbbox()
    if sampled_bounds is None:
        raise ValueError(f"{name}: no visible pixels survive native-pixel normalization")
    cutout = cutout.crop(sampled_bounds)
    position = ((size[0] - cutout.width) // 2, size[1] - cutout.height)
    canvas = Image.new("RGBA", size)
    canvas.paste(cutout, position)
    alpha = canvas.getchannel("A")
    rgb = canvas.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGB")
    pixels = np.dstack([np.array(rgb), np.array(alpha)])
    pixels[pixels[:, :, 3] == 0] = 0
    result = Image.fromarray(pixels)
    used_rect = result.getchannel("A").getbbox()
    if used_rect is None or used_rect[3] != size[1]:
        raise AssertionError(f"{name}: the visible cutout must reach its canvas bottom baseline")
    info.update({"name": name, "native_canvas": list(size),
                 "source_cutout_size": list((info["source_cutout_rect"][2] - info["source_cutout_rect"][0],
                                               info["source_cutout_rect"][3] - info["source_cutout_rect"][1])),
                 "uniform_scale": scale, "nearest_resized_size": list(fitted_size),
                 "sampled_used_rect": list(sampled_bounds), "resized_cutout": list(cutout.size),
                 "placement": list(position), "used_rect": list(used_rect),
                 "bottom_baseline_exclusive": size[1], "pixel_scale": 1,
                 "alpha_values": sorted(np.unique(pixels[:, :, 3]).tolist()),
                 "visible_colors": len(np.unique(pixels[:, :, :3][pixels[:, :, 3] > 0], axis=0)),
                 "source_art": "built-in-imagegen", "sampling": "nearest", "dithering": False})
    return result, info


def main() -> None:
    palette, palette_count = approved_palette()
    # Validate all five sources before overwriting any delivered/runtime image.
    prepared = {name: prepare_asset(name, size, palette) for name, size in ASSETS.items()}
    gatehouse, gate_info = prepared["gatehouse"]
    gate_info["person_door_composite"] = composite_person_doors(gatehouse, palette)
    gate_pixels = np.array(gatehouse)
    gate_info["visible_colors"] = len(np.unique(gate_pixels[:, :, :3][gate_pixels[:, :, 3] > 0], axis=0))
    DELIVERED.mkdir(parents=True, exist_ok=True)
    RUNTIME.mkdir(parents=True, exist_ok=True)
    report = {"date": "2026-10-20", "palette_reference": str(PALETTE_REFERENCE.relative_to(ROOT)),
              "palette_reference_sha256": hashlib.sha256(PALETTE_REFERENCE.read_bytes()).hexdigest(),
              "palette_colors": palette_count, "assets": {}}
    for name, (image, info) in prepared.items():
        destination = DELIVERED / f"{name}.png"
        image.save(destination, optimize=True)
        runtime_path = RUNTIME / destination.name
        runtime_path.write_bytes(destination.read_bytes())
        info.update({"native_sha256": hashlib.sha256(destination.read_bytes()).hexdigest(),
                     "delivered_path": str(destination.relative_to(ROOT)),
                     "runtime_path": str(runtime_path.relative_to(ROOT))})
        report["assets"][name] = info
    (OUTPUT / "asset_info.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
