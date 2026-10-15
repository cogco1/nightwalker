"""Turn the night-street recorder frames into a GIF, an MP4 and a contact sheet of the stills.

Usage: python -I tools/art_qa/compose_night_street_gif.py [scale]
Reads game/evidence/night_street_proto/ written by tests/recorders/record_night_street_proto.gd.
The MP4 (H.264, 1280x720 nearest-neighbour, 30 fps) needs ffmpeg: imageio-ffmpeg's bundled binary, or
ffmpeg on PATH; without one only the GIF and the sheet are written.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image

PROJECT = Path(__file__).resolve().parents[2] / "game"
EVIDENCE = PROJECT / "evidence" / "night_street_proto"


def main() -> int:
    scale = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    report = json.loads((EVIDENCE / "capture_report.json").read_text(encoding="utf-8"))
    frames = []
    for index in range(int(report["frames"])):
        image = Image.open(EVIDENCE / "frames" / f"{index:04d}.png").convert("RGB")
        image = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
        frames.append(image.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE))
    gif = EVIDENCE / "night_street_proto.gif"
    frames[0].save(gif, save_all=True, append_images=frames[1:], duration=33, loop=0, optimize=True, disposal=1)
    stills = [Image.open(EVIDENCE / f"{name}.png").convert("RGB") for name in report["stills"]]
    width, height = stills[0].width * scale, stills[0].height * scale
    sheet = Image.new("RGB", (width * 2 + 8, (height + 8) * ((len(stills) + 1) // 2)), (10, 10, 14))
    for index, still in enumerate(stills):
        sheet.paste(still.resize((width, height), Image.NEAREST), ((index % 2) * (width + 8), (index // 2) * (height + 8)))
    sheet.save(EVIDENCE / "night_street_stills.png")
    print(gif, len(frames), "frames,", round(gif.stat().st_size / 1e6, 1), "MB")
    ffmpeg = shutil.which("ffmpeg")
    try:
        import imageio_ffmpeg
        ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        pass
    if ffmpeg:
        mp4 = EVIDENCE / "night_street_proto.mp4"
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", "30", "-start_number", "0",
                        "-i", str(EVIDENCE / "frames" / "%04d.png"), "-frames:v", str(report["frames"]),
                        "-vf", "scale=1280:720:flags=neighbor,format=yuv420p", "-c:v", "libx264", "-crf", "16",
                        "-preset", "slow", "-movflags", "+faststart", str(mp4)], check=True)
        print(mp4, round(mp4.stat().st_size / 1e6, 1), "MB")
    else:
        print("no ffmpeg found: MP4 skipped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
