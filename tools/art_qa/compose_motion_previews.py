"""Make review previews from captured gameplay, preserving native pixel edges."""
from __future__ import annotations

import json
from pathlib import Path
from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[2] / "game"
EVIDENCE = PROJECT / "evidence"
SOURCE = EVIDENCE / "motion_v05"


def main() -> None:
    manifest = json.loads((SOURCE / "capture_manifest.json").read_text(encoding="utf-8"))
    states = {entry["index"]: entry for entry in manifest["states"]}
    previews = {}
    for section in manifest["sections"]:
        indices = list(range(section["first"], section["last"] + 1))
        images = [Image.open(SOURCE / f"{index:04}.png").convert("RGB").resize((960, 540), Image.Resampling.NEAREST) for index in indices]
        path = EVIDENCE / f"{section['name']}.gif"
        images[0].save(path, save_all=True, append_images=images[1:], duration=[max(20, states[index]["duration_ms"]) for index in indices], loop=0, disposal=2, optimize=False)
        previews[section["name"]] = str(path)
    review_indices = []
    for label in ["top_down_walk_run_brake_turn", "side_walk_run_turn"]:
        section = next(item for item in manifest["sections"] if item["name"] == label)
        for index in range(section["first"], section["last"] + 1):
            if states[index]["animation"].startswith(("walk_", "run_")):
                review_indices.append(index)
    columns = 10
    sample_indices = review_indices[:40] + review_indices[-40:]
    cells = Image.new("RGB", (columns * 160, ((len(sample_indices) + columns - 1) // columns) * 172), (24, 25, 31))
    pen = ImageDraw.Draw(cells)
    for cell, index in enumerate(sample_indices):
        state = states[index]
        anchor_x, anchor_y = map(round, state["render_position"])
        with Image.open(SOURCE / f"{index:04}.png") as picture:
            crop = picture.crop((anchor_x - 24, anchor_y - 42, anchor_x + 24, anchor_y + 6)).resize((144, 144), Image.Resampling.NEAREST)
            x, y = (cell % columns) * 160, (cell // columns) * 172
            cells.paste(crop, (x + 8, y + 20))
            pen.text((x + 4, y + 3), f"{state['animation']} {state['frame']}", fill=(230, 230, 235))
    cells.save(EVIDENCE / "movement_contact_review.png")
    landings = [state["index"] for state in manifest["states"] if state["animation"].startswith("jump_") and state["frame"] == 13 and abs(state["velocity"][1]) < 0.01]
    contacts = Image.new("RGB", (1200, max(1, len(landings)) * 224), (24, 25, 31))
    pen = ImageDraw.Draw(contacts)
    for row, landing in enumerate(landings):
        for column, index in enumerate(range(landing - 1, landing + 5)):
            if index not in states:
                continue
            state = states[index]
            anchor_x, anchor_y = map(round, state["render_position"])
            with Image.open(SOURCE / f"{index:04}.png") as picture:
                crop = picture.crop((anchor_x - 24, anchor_y - 42, anchor_x + 24, anchor_y + 10)).resize((192, 208), Image.Resampling.NEAREST)
                contacts.paste(crop, (column * 200, row * 224 + 16))
                pen.text((column * 200 + 2, row * 224 + 2), f"{index} {state['animation']} {state['frame']}", fill=(230, 230, 235))
    contacts.save(EVIDENCE / "ground_contacts_review.png")
    (EVIDENCE / "motion_previews.json").write_text(json.dumps(previews, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"previews":previews, "contact_sheet":str(EVIDENCE / "movement_contact_review.png")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
