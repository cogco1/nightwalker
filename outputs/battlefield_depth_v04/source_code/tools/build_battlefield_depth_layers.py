"""Join the sixteen imagegen paintings into two pixel-aligned parallax layers."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs/battlefield_depth_v04"
EVIDENCE = ROOT / "game/evidence/battlefield_run_test"
W, H, COUNT = 768, 256, 8


def build_far():
    pieces = []
    for number in range(1, COUNT + 1):
        path = OUTPUT / "far_sources" / f"far_{number:02}.png"
        with Image.open(path) as source:
            pixels = np.array(source.convert("RGB").resize((W, H), Image.Resampling.NEAREST))
        # Use the same roofline alignment as the preceding far-background version.
        pieces.append(np.concatenate([pixels[22:], np.repeat(pixels[-1:], 22, axis=0)]))
    canvas = np.concatenate(pieces, axis=1)
    seam_width = 32
    for seam in range(W, W * COUNT, W):
        left = canvas[:, seam - seam_width // 2 - 1].astype(np.float32)
        right = canvas[:, seam + seam_width // 2].astype(np.float32)
        for offset in range(seam_width):
            amount = (offset + 1) / (seam_width + 1)
            canvas[:, seam - seam_width // 2 + offset] = np.rint(
                left * (1 - amount) + right * amount).astype(np.uint8)
    return Image.fromarray(canvas).quantize(
        colors=48, method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE).convert("RGB")


def build_mid():
    pieces = []
    for number in range(1, COUNT + 1):
        path = OUTPUT / "mid_sources" / f"mid_{number:02}.png"
        with Image.open(path) as source:
            pixels = np.array(source.convert("RGBA").resize((W, H), Image.Resampling.NEAREST))
        if pixels[:, :, 3].min() >= 128 or pixels[:, :, 3].max() < 128:
            raise ValueError(f"{path.name} must contain visible artwork and real transparency")
        pixels[:, :, 3] = np.where(pixels[:, :, 3] >= 128, 255, 0)
        lifted = np.zeros_like(pixels)
        lifted[:-12] = pixels[12:]
        pieces.append(lifted)
    canvas = np.concatenate(pieces, axis=1)
    visible = canvas[:, :, 3] == 255
    # Build one shared palette from visible pixels, excluding the transparent RGB matte.
    sample = Image.fromarray(canvas[:, :, :3][visible].reshape(1, -1, 3))
    quantized = sample.quantize(colors=64, method=Image.Quantize.MEDIANCUT,
                               dither=Image.Dither.NONE)
    palette_values = quantized.getpalette()
    palette_colors = [palette_values[index * 3:index * 3 + 3]
                      for _, index in quantized.getcolors()]
    palette = Image.new("P", (1, 1))
    palette.putpalette([component for index in range(256)
                        for component in palette_colors[index % len(palette_colors)]])
    rgb = Image.fromarray(canvas[:, :, :3]).quantize(
        palette=palette, dither=Image.Dither.NONE).convert("RGB")
    result = np.dstack([np.array(rgb), canvas[:, :, 3]])
    result[~visible, :3] = 0
    return Image.fromarray(result)


def save_layer(image, name, role, ratio, z_index):
    native_name = f"battlefield_{name}_native.png"
    native_path = OUTPUT / native_name
    image.save(native_path, optimize=True)
    assets = ROOT / f"game/assets/battlefield_{name}_background"
    assets.mkdir(parents=True, exist_ok=True)
    # Copy the exact encoded artifact so the runtime and delivered SHA agree.
    (assets / native_name).write_bytes(native_path.read_bytes())
    image.resize((W * COUNT * 2, H * 2), Image.Resampling.NEAREST).save(
        OUTPUT / f"battlefield_{name}_12288x512.png", optimize=True)
    pixels = np.array(image)
    visible = pixels[:, :, 3] == 255 if image.mode == "RGBA" else np.ones((H, W * COUNT), bool)
    colors = len(np.unique(pixels[:, :, :3][visible], axis=0))
    contact = Image.new("RGB", (W * 2, H * 4), "#22272b")
    for section in range(COUNT):
        piece = image.crop((section * W, 0, (section + 1) * W, H))
        contact.paste(piece, ((section % 2) * W, (section // 2) * H),
                      piece.getchannel("A") if image.mode == "RGBA" else None)
    contact.save(EVIDENCE / f"{name}_contact_sheet.png")
    return {"role": role, "native_size": list(image.size),
            "display_size": [W * COUNT * 2, H * 2], "origin": [0, 0],
            "scroll_scale_x": ratio, "z_index": z_index, "colors": colors,
            "opaque": image.mode == "RGB", "source_sections": COUNT,
            "alpha_values": sorted(np.unique(pixels[:, :, 3]).tolist()) if image.mode == "RGBA" else [255],
            "native_sha256": hashlib.sha256(native_path.read_bytes()).hexdigest(),
            "source_art": "built-in-imagegen", "integer_scale": 2}


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    # Read and validate every source before overwriting either runtime texture.
    far, mid = build_far(), build_mid()
    info = {"far": save_layer(far, "far", "distant_city_and_industry", 0.28, -20),
            "mid": save_layer(mid, "mid", "middle_buildings_and_factories", 0.58, -15)}
    near_path = ROOT / "game/assets/battlefield_layer_01/battlefield_layer_01_native.png"
    with Image.open(near_path) as near:
        near_pixels = np.array(near.convert("RGBA"))
        info["near"] = {"role": "main_architecture", "native_size": list(near.size),
                        "scroll_scale_x": 1.0, "z_index": -10,
                        "colors": len(np.unique(near_pixels[:, :, :3][near_pixels[:, :, 3] == 255], axis=0)),
                        "native_sha256": hashlib.sha256(near_path.read_bytes()).hexdigest(),
                        "unchanged": True}
    (OUTPUT / "layer_info.json").write_text(
        json.dumps(info, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(info))


if __name__ == "__main__":
    main()
