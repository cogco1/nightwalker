"""Compose nearest-neighbor previews of the focused, real-GPU V06 capture."""
from __future__ import annotations

import json
from pathlib import Path
from PIL import Image, ImageDraw

PROJECT = Path(__file__).resolve().parents[1]
EVIDENCE = PROJECT / "evidence"
SOURCE = EVIDENCE / "special_motion_v06"


def main() -> None:
    manifest = json.loads((SOURCE / "capture_manifest.json").read_text(encoding="utf-8"))
    states = {state["index"]: state for state in manifest["states"]}
    sections = {section["name"]: list(range(section["first"], section["last"] + 1)) for section in manifest["sections"]}
    selections = {
        "rising_slash": ("rising_slash_v06.gif", sections["side_rising_slash"]),
        "dash_stab": ("dash_stab_v06.gif", sections["side_dash_stab"]),
        "critical_two_frame_stop": ("critical_two_frame_stop_v06.gif", sections["critical_top_y_stop"] + sections["critical_side_x_stop"]),
    }
    previews = {}
    for name, (filename, indices) in selections.items():
        pictures = [Image.open(SOURCE / f"{index:04}.png").convert("RGB").resize((960, 540), Image.Resampling.NEAREST) for index in indices]
        output = EVIDENCE / filename
        pictures[0].save(output, save_all=True, append_images=pictures[1:], duration=20, loop=0, disposal=2, optimize=False)
        previews[name] = str(output)

    # Review unmodified viewport pixels at 2x; labels sit outside the viewport.
    action_rows = []
    for name in ("side_rising_slash", "side_dash_stab"):
        candidates = [states[index] for index in sections[name]]
        first_fx = next(state["index"] for state in candidates if state["air_lines"])
        action_rows.append([first_fx - 3, first_fx, first_fx + 3, first_fx + 10])
    frozen_rows = []
    for name in ("critical_top_y_stop", "critical_side_x_stop"):
        frozen = [index for index in sections[name] if states[index]["stop_active"]]
        frozen_rows.append([frozen[0] - 1, frozen[0], frozen[1], frozen[1] + 1])
    sheet = Image.new("RGB", (2560, 4 * 384), (24, 25, 31))
    pen = ImageDraw.Draw(sheet)
    for row, indices in enumerate(action_rows + frozen_rows):
        for column, index in enumerate(indices):
            state = states[index]
            picture = Image.open(SOURCE / f"{index:04}.png").convert("RGB").resize((640, 360), Image.Resampling.NEAREST)
            x, y = column * 640, row * 384
            sheet.paste(picture, (x, y + 24))
            label = f"{index:04} {state['section']} frame {state['frame']}"
            if state["stop_active"]:
                label += f" FROZEN {state['stop_displayed_before_render'] + 1}/2"
            pen.text((x + 6, y + 6), label, fill=(230, 234, 240))
    sheet.save(EVIDENCE / "specials_storyboard_v06.png")

    # A closer crop makes the dagger, coat afterimages and small airflow readable.
    native_review = Image.new("RGB", (6 * 400, 2 * 420), (24, 25, 31))
    pen = ImageDraw.Draw(native_review)
    for row, name in enumerate(("side_rising_slash", "side_dash_stab")):
        candidates = [states[index] for index in sections[name]]
        first_fx = next(state["index"] for state in candidates if state["air_lines"])
        for column, index in enumerate([first_fx - 6, first_fx - 3, first_fx, first_fx + 2, first_fx + 5, first_fx + 10]):
            state = states[index]
            x, y = map(round, state["render_position"])
            picture = Image.open(SOURCE / f"{index:04}.png").convert("RGB")
            crop = picture.crop((x - 40, y - 72, x + 40, y + 8)).resize((400, 400), Image.Resampling.NEAREST)
            left, top = column * 400, row * 420
            native_review.paste(crop, (left, top + 20))
            pen.text((left + 6, top + 4), f"{index:04} {state['animation']} {state['frame']}", fill=(230, 234, 240))
    native_review.save(EVIDENCE / "specials_native_review_v06.png")
    (EVIDENCE / "special_motion_previews.json").write_text(json.dumps(previews, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"previews": previews, "captured_frames": manifest["captured_frames"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
