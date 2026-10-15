"""Make pixel-preserving previews from the focused V07 real-GPU recording."""
from __future__ import annotations

import json
from pathlib import Path
from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[2] / "game"
EVIDENCE = PROJECT / "evidence"
SOURCE = EVIDENCE / "sword_motion_v07"


def main() -> None:
    manifest = json.loads((SOURCE / "capture_manifest.json").read_text(encoding="utf-8"))
    states = {state["index"]: state for state in manifest["states"]}
    previews = {}
    rows = []
    for section in manifest["sections"]:
        name = section["name"]
        indices = list(range(section["first"], section["last"] + 1))
        pictures = [Image.open(SOURCE / f"{index:04}.png").convert("RGB").resize((960, 540), Image.Resampling.NEAREST) for index in indices]
        output = EVIDENCE / f"{name}_v07.gif"
        pictures[0].save(output, save_all=True, append_images=pictures[1:], duration=20, loop=0, disposal=2, optimize=False)
        previews[name] = str(output)
        hits = [states[index] for index in indices if states[index]["stop_active"]]
        if name == "side_longblade_combo":
            first = hits[0]["index"]
            rows.append((name, [first - 1, first, first + 1, hits[-1]["index"]]))
        elif name.startswith("critical_"):
            critical = [state["index"] for state in hits if state["stop_requested_frames"] == 6]
            rows.append((name, [critical[0] - 1, critical[0], critical[-1], critical[-1] + 1]))
        else:
            first = hits[0]["index"]
            rows.append((name, [first - 3, first, first + 3, first + 12]))
    sheet = Image.new("RGB", (2560, len(rows) * 384), (24, 25, 31))
    pen = ImageDraw.Draw(sheet)
    for row, (_name, indices) in enumerate(rows):
        for column, index in enumerate(indices):
            state = states[index]
            picture = Image.open(SOURCE / f"{index:04}.png").convert("RGB").resize((640, 360), Image.Resampling.NEAREST)
            x, y = column * 640, row * 384
            sheet.paste(picture, (x, y + 24))
            label = f"{index:04} {state['section']} pose {state['frame']}"
            if state["stop_active"]:
                label += f" FREEZE {state['stop_displayed_before_render']+1}/{state['stop_requested_frames']}"
            pen.text((x + 6, y + 6), label, fill=(230, 234, 240))
    sheet.save(EVIDENCE / "sword_contact_storyboard_v07.png")

    crops = Image.new("RGB", (1600, len(rows) * 420), (24, 25, 31))
    pen = ImageDraw.Draw(crops)
    for row, (_name, indices) in enumerate(rows):
        for column, index in enumerate(indices):
            state = states[index]
            x, y = map(round, state["render_position"])
            picture = Image.open(SOURCE / f"{index:04}.png").convert("RGB")
            cropped = picture.crop((x-30, y-72, x+50, y+8)).resize((400,400), Image.Resampling.NEAREST)
            left, top = column * 400, row * 420
            crops.paste(cropped,(left,top+20))
            pen.text((left+6,top+4),f"{index:04} {state['animation']} {state['frame']}",fill=(230,234,240))
    crops.save(EVIDENCE / "sword_native_review_v07.png")
    (EVIDENCE / "sword_motion_previews.json").write_text(json.dumps(previews, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"previews": previews, "captured_frames": manifest["captured_frames"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
