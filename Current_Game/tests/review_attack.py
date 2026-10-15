"""Build a storyboard from real three-hit gameplay frames."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

source = Path(__file__).resolve().parents[1] / "evidence" / "motion_v05"
manifest = json.loads((source / "capture_manifest.json").read_text(encoding="utf-8"))
states = [state for state in manifest["states"] if state["section"] == "side_three_hit_combo"]
review = Image.new("RGB", (2048, 720), (24, 25, 31))
pen = ImageDraw.Draw(review)
for row, stage in enumerate([1, 2, 3]):
    for column, frame in enumerate([0, 5, 6, 7, 8, 9, 12, 15]):
        state = next((entry for entry in states if entry["stage"] == stage and entry["frame"] == frame), None)
        if state is None:
            continue
        root_x, root_y = map(round, state["render_position"])
        with Image.open(source / f"{state['index']:04}.png") as picture:
            crop = picture.crop((root_x - 36, root_y - 56, root_x + 44, root_y + 16)).resize((240, 216), Image.Resampling.NEAREST)
            review.paste(crop, (column * 256, row * 240 + 20))
            pen.text((column * 256 + 2, row * 240 + 2), f"attack{stage} frame{frame}", fill=(235, 235, 235))
review.save(source.parent / "attack_contact_review.png")
