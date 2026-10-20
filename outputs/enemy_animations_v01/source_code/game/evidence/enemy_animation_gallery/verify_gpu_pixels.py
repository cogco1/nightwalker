import json
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
manifest = json.loads((REPO / "game/assets/enemy_animations_v01/manifest.json").read_text(encoding="utf-8"))
report = {"passed": True, "right_frames": 0, "left_frames": 0, "opaque_pixels_checked": 0, "mismatched_pixels": 0, "captures": []}


def verify(source: Image.Image, capture: Path) -> None:
    sprite = np.array(source.convert("RGBA"))
    rendered = np.array(Image.open(capture).convert("RGB"))[68:132, 112:208]
    mask = sprite[:, :, 3] == 255
    mismatches = int(np.any(sprite[:, :, :3] != rendered, axis=2)[mask].sum())
    report["mismatched_pixels"] += mismatches
    report["opaque_pixels_checked"] += int(mask.sum())
    report["captures"].append({"path": capture.name, "mismatched_pixels": mismatches})


for unit in manifest["units"]:
    for action in unit["actions"]:
        for frame_index in range(8):
            frame_path = REPO / "outputs/enemy_animations_v01/frames" / unit["unit"] / action["name"] / f"{frame_index:02d}.png"
            verify(Image.open(frame_path), OUT / f"{unit['unit']}_{action['name']}_{frame_index:02d}.png")
            report["right_frames"] += 1
    last_action = unit["actions"][-1]["name"]
    final_pose = Image.open(REPO / "outputs/enemy_animations_v01/frames" / unit["unit"] / last_action / "07.png")
    verify(final_pose.transpose(Image.Transpose.FLIP_LEFT_RIGHT), OUT / f"{unit['unit']}_left.png")
    report["left_frames"] += 1
report["passed"] = report["mismatched_pixels"] == 0 and report["right_frames"] == 144 and report["left_frames"] == 8
(OUT / "gpu_pixel_verification.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({key: value for key, value in report.items() if key != "captures"}))
raise SystemExit(0 if report["passed"] else 1)
