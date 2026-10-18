"""Side-by-side comparison of the hit-impact prototype: each move recorded by
game/tests/recorders/record_impact_burst.gd with the prototype on (left) and off (right, impact v2 alone).

Usage: python -I tools/art_qa/compose_impact_burst.py [capture_dir]
Writes <capture_dir>/impact_burst_compare.mp4 (60 fps) and impact_burst_compare_half_speed.mp4. Needs Pillow and
imageio-ffmpeg (for the ffmpeg binary). Frames are the recorder's 640x360 PNGs; labels use the game's pixel font.
"""
import json
import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
FONT = ROOT / "game" / "assets" / "fonts" / "fusion-pixel-12px-proportional-zh_hans.otf"
MOVES = [("charged_draw", "蓄力拔刀斩"), ("heavy_cleave", "右键重劈"), ("light_crit", "轻击三连")]
GAP_FRAMES = 18


def frames_of(folder: Path) -> list:
    return sorted(folder.glob("*.png"))


def label(image: Image.Image, text: str, font: ImageFont.FreeTypeFont) -> None:
    draw = ImageDraw.Draw(image)
    width = int(draw.textlength(text, font=font))
    draw.rectangle([0, image.height - 30, width + 16, image.height], fill=(8, 10, 16))
    draw.text((8, image.height - 28), text, font=font, fill=(204, 216, 222))


def compose(capture: Path, out: Path, repeat: int) -> None:
    font = ImageFont.truetype(str(FONT), 24)
    ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    process = subprocess.Popen([ffmpeg, "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                                "-s", "1280x360", "-r", "60", "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                                "-crf", "16", str(out)], stdin=subprocess.PIPE)
    blank = Image.new("RGB", (1280, 360), (0, 0, 0))
    for move, name in MOVES:
        on = frames_of(capture / (move + "_on"))
        off = frames_of(capture / (move + "_off"))
        if not on or not off:
            continue
        for index in range(max(len(on), len(off))):
            sheet = Image.new("RGB", (1280, 360))
            left = Image.open(on[min(index, len(on) - 1)]).convert("RGB")
            right = Image.open(off[min(index, len(off) - 1)]).convert("RGB")
            label(left, name + " · 打击原型 开", font)
            label(right, name + " · 原版（打击感 v2）", font)
            sheet.paste(left, (0, 0))
            sheet.paste(right, (640, 0))
            for _ in range(repeat):
                process.stdin.write(sheet.tobytes())
        for _ in range(GAP_FRAMES * repeat):
            process.stdin.write(blank.tobytes())
    process.stdin.close()
    process.wait()


def main() -> int:
    capture = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "game" / "evidence" / "impact_burst"
    report = json.loads((capture / "report.json").read_text(encoding="utf-8"))
    compose(capture, capture / "impact_burst_compare.mp4", 1)
    compose(capture, capture / "impact_burst_compare_half_speed.mp4", 2)
    print(json.dumps({"takes": len(report["takes"]), "outputs": ["impact_burst_compare.mp4",
                      "impact_burst_compare_half_speed.mp4"]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
