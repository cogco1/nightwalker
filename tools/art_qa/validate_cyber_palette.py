"""Check that every opaque pixel in game/frames uses a colour listed in the hero lookup (row 0 of
game/assets/fx/cyber_palette.png). New frames with new colours need a new lookup column, or the hero
shader leaves those pixels unconverted.

Usage: python -I tools/art_qa/validate_cyber_palette.py
"""
from collections import Counter
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parents[2] / "game"


def main() -> int:
    lookup = Image.open(PROJECT / "assets" / "fx" / "cyber_palette.png").convert("RGBA")
    known = {lookup.getpixel((index, 0))[:3] for index in range(lookup.width)}
    unknown = Counter()
    frames = sorted((PROJECT / "frames").rglob("*.png"))
    for path in frames:
        for count, (r, g, b, a) in Image.open(path).convert("RGBA").getcolors(1 << 16) or []:
            if a == 255 and (r, g, b) not in known:
                unknown[f"{r:02x}{g:02x}{b:02x}"] += count
    print(f"{len(frames)} frames, {len(known)} lookup colours, {len(unknown)} unlisted colours")
    for colour, count in unknown.most_common(20):
        print("  unlisted", colour, count)
    return 1 if unknown else 0


if __name__ == "__main__":
    raise SystemExit(main())
