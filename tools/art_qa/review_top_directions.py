"""Storyboard the actual up/down combo capture, including its stage joins."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

source = Path(__file__).resolve().parents[2] / "game" / "evidence" / "top_directions_v05"
manifest = json.loads((source / "capture_manifest.json").read_text(encoding="utf-8"))
for direction in ["up","down"]:
    states = [state for state in manifest["states"] if state["section"].endswith("_" + direction)]
    review = Image.new("RGB", (2048,816), (24,25,31))
    pen = ImageDraw.Draw(review)
    for row, stage in enumerate([1,2,3]):
        for column, frame in enumerate([0,5,6,7,8,9,14,15]):
            state = next((entry for entry in states if entry["stage"] == stage and entry["frame"] == frame), None)
            if state is None:
                continue
            root_x, root_y = map(round,state["render_position"])
            top = 64 if direction == "up" else 44
            bottom = 16 if direction == "up" else 36
            with Image.open(source / f"{state['index']:04}.png") as picture:
                crop = picture.crop((root_x - 40,root_y - top,root_x + 40,root_y + bottom)).resize((240,240),Image.Resampling.NEAREST)
                review.paste(crop,(column * 256,row * 272 + 20))
                pen.text((column * 256 + 2,row * 272 + 2),f"{direction} attack{stage} frame{frame}",fill=(235,235,235))
    review.save(source.parent / f"top_{direction}_attack_review.png")
