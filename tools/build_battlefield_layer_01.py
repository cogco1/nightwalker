"""Compose imagegen-painted sections into one native-pixel parallax layer.

Local pixel alignment and compositing were explicitly requested by the user.
This script reuses generated pixels; it does not generate replacement artwork.
"""
from __future__ import annotations

import hashlib
import json
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs" / "battlefield_layer_01_v02"
SOURCES = OUTPUT / "source_segments"
GAME_ASSETS = ROOT / "game" / "assets" / "battlefield_layer_01"
PART_WIDTH, HEIGHT, PARTS = 768, 256, 8
WIDTH, HIGH_Y = PART_WIDTH * PARTS, 168
# The entrance follows the painted slope; all later ground remains at HIGH_Y.
POINTS = [[0, 224], [140, 224], [224, HIGH_Y], [WIDTH, HIGH_Y]]


def clean_pixels(path: Path) -> np.ndarray:
    image = Image.open(path).convert("RGBA").resize((PART_WIDTH, HEIGHT), Image.Resampling.NEAREST)
    pixels = np.array(image)
    r, g, b = [pixels[:, :, i].astype(np.int16) for i in range(3)]
    # The generated cutout matte has isolated pure red/green/yellow fringe colors.
    fringe = ((r > 190) & (g < 85) & (b < 95)) | ((g > 190) & (r < 110) & (b < 140))
    fringe |= (r > 215) & (g > 205) & (b < 65)
    opaque = (pixels[:, :, 3] >= 128) & ~fringe
    pixels[:, :, 3] = np.where(opaque, 255, 0)
    pixels[~opaque] = 0
    return pixels


def painted_surface(pixels: np.ndarray) -> np.ndarray:
    """Find the connected sand strip, excluding separate amber windows."""
    r, g, b = [pixels[:, :, i].astype(np.float32) for i in range(3)]
    sand = (pixels[:, :, 3] > 0) & (r > 135) & (g > 80) & (r > g * 1.12) & (g > b * 1.28) & (b < 150)
    seen = np.zeros(sand.shape, dtype=bool)
    best: list[tuple[int, int]] = []
    for yy, xx in zip(*np.nonzero(sand)):
        if seen[yy, xx]:
            continue
        pending = deque([(int(yy), int(xx))])
        seen[yy, xx] = True
        region: list[tuple[int, int]] = []
        while pending:
            y, x = pending.popleft()
            region.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < HEIGHT and 0 <= nx < PART_WIDTH and sand[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    pending.append((ny, nx))
        if len(region) > len(best):
            best = region
    if not best:
        raise ValueError("No connected yellow sand was found in a generated section")
    tops = np.full(PART_WIDTH, HEIGHT, dtype=np.int32)
    for y, x in best:
        tops[x] = min(tops[x], y)
    good = np.flatnonzero(tops < HEIGHT)
    if len(good) < PART_WIDTH * 0.8:
        raise ValueError("Sand strip does not span the section")
    tops = np.rint(np.interp(np.arange(PART_WIDTH), good, tops[good])).astype(np.int32)
    return tops


def surface_y(x: int) -> int:
    for (ax, ay), (bx, by) in zip(POINTS, POINTS[1:]):
        if x <= bx:
            return round(ay + (by - ay) * (x - ax) / (bx - ax))
    return HIGH_Y


def move_pixels(pixels: np.ndarray, offset: int) -> np.ndarray:
    result = np.zeros_like(pixels)
    if offset >= 0:
        result[offset:] = pixels[:HEIGHT - offset]
    else:
        result[:offset] = pixels[-offset:]
    return result


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    GAME_ASSETS.mkdir(parents=True, exist_ok=True)
    prepared: list[np.ndarray] = []
    surfaces: list[np.ndarray] = []
    offsets: list[int] = []
    for index in range(1, PARTS + 1):
        pixels = clean_pixels(SOURCES / f"segment_{index:02}.png")
        tops = painted_surface(pixels)
        samples = tops[350:] if index == 1 else tops
        offset = HIGH_Y - int(np.median(samples))
        prepared.append(move_pixels(pixels, offset))
        surfaces.append(tops + offset)
        offsets.append(offset)

    # A shared generated retaining-face sample and sand cap cross every join.
    # Sampling one phase of the same texture avoids a separate wall at each seam.
    master = prepared[1]
    texture = master[HIGH_Y:, 20:276].copy()
    for x in range(texture.shape[1]):
        opaque = np.flatnonzero(texture[:, x, 3])
        if not len(opaque):
            raise ValueError("Retaining-face texture has a transparent column")
        texture[:opaque[0], x] = texture[opaque[0], x]
        last = int(opaque[0])
        for y in range(texture.shape[0]):
            if texture[y, x, 3]:
                last = y
            else:
                texture[y, x] = texture[last, x]
    canvas = np.zeros((HEIGHT, WIDTH, 4), dtype=np.uint8)
    # Compose the foreground terrace using generated material pixels only.
    for x in range(WIDTH):
        y0 = surface_y(x)
        for y in range(y0, HEIGHT):
            canvas[y, x] = texture[min(y - y0, len(texture) - 1), x % texture.shape[1]]

    segment_records = []
    for index, (pixels, tops) in enumerate(zip(prepared, surfaces)):
        architecture = pixels.copy()
        x0 = index * PART_WIDTH
        for x in range(PART_WIDTH):
            # Remove the old painted floor; preserve architectural silhouettes.
            architecture[max(0, int(tops[x])):, x] = 0
            ground = surface_y(x0 + x)
            architecture[ground:, x] = 0
            occupied = np.flatnonzero(architecture[:, x, 3])
            if len(occupied):
                last = int(occupied[-1])
                # Join a short architectural foot to the exact ground, preserving its pixel colors.
                if 0 < ground - last <= 9:
                    architecture[last + 1:ground, x] = architecture[last, x]
        target = canvas[:, x0:x0 + PART_WIDTH]
        mask = architecture[:, :, 3] > 0
        target[mask] = architecture[mask]
        segment_records.append({"segment": index + 1, "x": x0, "width": PART_WIDTH,
                                "source_vertical_offset": offsets[index]})

    # One palette over the whole image and binary alpha keep every game pixel crisp.
    rgba = Image.fromarray(canvas)
    alpha = rgba.getchannel("A")
    native = rgba.convert("RGB").quantize(colors=64, method=Image.Quantize.MEDIANCUT,
                                         dither=Image.Dither.NONE).convert("RGBA")
    native.putalpha(alpha)
    native_path = OUTPUT / "battlefield_layer_01_native.png"
    display_path = OUTPUT / "battlefield_layer_01_12288x512.png"
    native.save(native_path, optimize=True)
    native.save(GAME_ASSETS / native_path.name, optimize=True)
    native.resize((WIDTH * 2, HEIGHT * 2), Image.Resampling.NEAREST).save(display_path, optimize=True)

    profile = {"width": WIDTH, "height": HEIGHT, "points": POINTS,
               "layer": "main_architecture", "origin": [0, 0], "reference_scroll_scale": 1.0}
    for directory in (OUTPUT, GAME_ASSETS):
        (directory / "ground_profile.json").write_text(json.dumps(profile, indent=2) + "\n", encoding="utf-8")
    report = {"date": "2026-10-20", "native_size": [WIDTH, HEIGHT], "display_size": [WIDTH * 2, HEIGHT * 2],
              "alpha_values": np.unique(np.asarray(alpha)).tolist(), "palette_colors": len(native.getcolors(WIDTH * HEIGHT) or []),
              "segments": segment_records, "ground_points": POINTS,
              "native_sha256": hashlib.sha256(native_path.read_bytes()).hexdigest(),
              "display_sha256": hashlib.sha256(display_path.read_bytes()).hexdigest(),
              "art_source": "built-in imagegen", "compositing": "user-authorized local pixel alignment and composition"}
    (OUTPUT / "composition_report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report))


if __name__ == "__main__":
    main()
