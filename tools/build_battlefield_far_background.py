"""Compose imagegen distant-city paintings into the authorized long parallax layer."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "outputs/battlefield_far_v03"
ASSETS = ROOT / "game/assets/battlefield_far_background"
W, H, COUNT = 768, 256, 8


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    pieces = []
    for number in range(1, COUNT + 1):
        source = OUTPUT / "source_segments" / f"far_{number:02}.png"
        pixels = np.array(Image.open(source).convert("RGB").resize((W, H), Image.Resampling.NEAREST))
        # Lift distant rooflines into the visible sky above the main layer's y168 terrace.
        pixels = np.concatenate([pixels[22:], np.repeat(pixels[-1:], 22, axis=0)], axis=0)
        pieces.append(pixels)
    canvas = np.concatenate(pieces, axis=1)
    # Blend only quiet edge strips, never rescale or tile the architecture to fake length.
    seam_width = 32
    for seam in range(W, W * COUNT, W):
        left = canvas[:, seam - seam_width // 2 - 1].astype(np.float32)
        right = canvas[:, seam + seam_width // 2].astype(np.float32)
        for offset in range(seam_width):
            t = (offset + 1) / (seam_width + 1)
            canvas[:, seam - seam_width // 2 + offset] = np.rint(left * (1 - t) + right * t).astype(np.uint8)
    native = Image.fromarray(canvas).quantize(colors=48, method=Image.Quantize.MEDIANCUT,
                                             dither=Image.Dither.NONE).convert("RGB")
    native_name = "battlefield_far_native.png"
    native.save(OUTPUT / native_name, optimize=True)
    native.save(ASSETS / native_name, optimize=True)
    native.resize((W * COUNT * 2, H * 2), Image.Resampling.NEAREST).save(
        OUTPUT / "battlefield_far_12288x512.png", optimize=True)
    info = {"native_size": [W * COUNT, H], "display_size": [W * COUNT * 2, H * 2],
            "origin": [0, 0], "role": "distant_city_and_industry", "scroll_scale_x": 0.28,
            "colors": len(native.getcolors(W * COUNT * H)), "opaque": True,
            "native_sha256": hashlib.sha256((OUTPUT / native_name).read_bytes()).hexdigest(),
            "source_sections": COUNT, "source_art": "built-in-imagegen", "integer_scale": 2}
    (OUTPUT / "layer_info.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8")
    contact = Image.new("RGB", (W * 2, H * 4))
    for number in range(COUNT):
        contact.paste(native.crop((number * W, 0, (number + 1) * W, H)),
                      ((number % 2) * W, (number // 2) * H))
    evidence = ROOT / "game/evidence/battlefield_run_test"
    evidence.mkdir(parents=True, exist_ok=True)
    contact.save(evidence / "far_contact_sheet.png")
    print(json.dumps(info))


if __name__ == "__main__":
    main()
