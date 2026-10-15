"""Build the 18-colour hero palette lookup used by game/shaders/character_cyber.gdshader.

Usage: python -I tools/art/gen_cyber_palette.py
Writes game/assets/fx/cyber_palette.png (18 x 4):
  row 0  original colour found in game/frames (all 1024 frames use exactly these 18)
  row 1  cyber colour it is swapped to
  row 2  emission: rgb = halo colour, alpha = strength (0 = not emissive)
  row 3  reflective tape: alpha = how much the colour turns into retro-reflective strip when lit
"""
from pathlib import Path

from PIL import Image

GAME = Path(__file__).resolve().parents[2] / "game"
CYAN_GLOW = "4ff0ff"
EYE_GLOW = "ff3d7a"

# original, cyber, glow colour, glow strength (0-255)
PALETTE = [
    ("11141a", "0a0812", None, 0),       # outline
    ("20242b", "15142a", None, 0),       # darkest cloth
    ("303842", "262c4c", None, 0),       # dark cloth
    ("414b58", "36406e", None, 0),       # cloth
    ("5a6268", "4a5888", None, 0),       # cloth light, blade spine
    ("566170", "47557f", None, 0),       # air-dash cloth (v14 frames only)
    ("6b7480", "55638f", None, 0),       # cloth highlight
    ("8a8a85", "7a86a8", None, 0),       # grey trim
    ("75695a", "4a3a6a", None, 0),       # khaki
    ("33251f", "2a1420", None, 0),       # dark leather
    ("533729", "5a1a36", None, 0),       # leather
    ("76513a", "a0285a", None, 0),       # tan -> black-market magenta
    ("a07a5b", "e0407a", None, 0),       # light tan -> magenta accent
    ("e1b999", "ff8fb4", EYE_GLOW, 255),  # face skin -> eyepiece
    ("c5a18a", "d0306a", EYE_GLOW, 140),  # face shadow -> eyepiece rim
    ("8e999f", "2ab8e0", CYAN_GLOW, 120),  # blade steel dark
    ("bbc2c3", "7ff6ff", CYAN_GLOW, 200),  # blade steel
    ("e5e8e0", "e8ffff", CYAN_GLOW, 255),  # blade edge
]


# Cross-body strap, belt and shoulder straps (#533729) become reflective tape: dull in the dark,
# flaring in the light that hits them - light = being watched.
REFLECTIVE = {"533729": 255}


def rgb(hex_colour: str) -> tuple[int, int, int]:
    return tuple(int(hex_colour[i:i + 2], 16) for i in (0, 2, 4))


def main() -> None:
    image = Image.new("RGBA", (len(PALETTE), 4), (0, 0, 0, 0))
    for index, (original, cyber, glow, strength) in enumerate(PALETTE):
        image.putpixel((index, 0), rgb(original) + (255,))
        image.putpixel((index, 1), rgb(cyber) + (255,))
        image.putpixel((index, 2), (rgb(glow) if glow else (0, 0, 0)) + (strength,))
        image.putpixel((index, 3), (255, 255, 255, REFLECTIVE.get(original, 0)))
    out = GAME / "assets" / "fx" / "cyber_palette.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    image.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
