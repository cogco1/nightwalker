"""Compose delivery previews from real native enemy animation frames.

Only compositing, nearest-neighbour enlargement and GIF palette encoding happen
here. No character pose or animation frame is drawn or interpolated.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "outputs/enemy_animations_v01"
MANIFEST = ROOT / "game/assets/enemy_animations_v01/manifest.json"
BG = (21, 25, 30)
FG = (236, 224, 197)
MUTED = (154, 166, 168)
ACCENT = (223, 145, 41)
ACTION_NAMES = {"hover": "悬浮巡航", "laser": "激光蓄能 / 发射", "walk": "行走",
                "fire": "开火", "attack": "近战攻击", "prone_down": "卧倒",
                "prone_crawl": "匍匐移动", "prone_fire": "卧姿狙击"}


def local_path(path: str) -> Path:
    return ROOT / "game" / path.removeprefix("res://") if path.startswith("res://") else ROOT / path


def font(size: int) -> ImageFont.FreeTypeFont:
    for candidate in [Path("C:/Windows/Fonts/simhei.ttf"), Path("C:/Windows/Fonts/msyh.ttc")]:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    raise FileNotFoundError("A Chinese-capable font is needed for preview labels")


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def enlarged(image: Image.Image, factor: int) -> Image.Image:
    native = Image.new("RGB", image.size, BG)
    native.paste(image, (0, 0), image.getchannel("A"))
    return native.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST)


def gif(path: Path, frames: list[Image.Image], durations: list[int]) -> None:
    """Keep one palette across frames, avoiding colour pulses from encoding."""
    assert len(frames) == len(durations)
    samples = [im.resize((max(1, im.width // 2), max(1, im.height // 2)), Image.Resampling.NEAREST) for im in frames]
    training = Image.new("RGB", (max(im.width for im in samples), sum(im.height for im in samples)), BG)
    y = 0
    for im in samples:
        training.paste(im, (0, y))
        y += im.height
    palette = training.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    encoded = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in frames]
    path.parent.mkdir(parents=True, exist_ok=True)
    encoded[0].save(path, save_all=True, append_images=encoded[1:], duration=durations,
                    loop=0, disposal=2, optimize=False)


def durations_for(count: int, fps: float) -> list[int]:
    # GIF delays are multiples of 10 ms. Cumulative rounding preserves the rate.
    times = [round(i * 100 / fps) * 10 for i in range(count + 1)]
    return [max(10, times[i + 1] - times[i]) for i in range(count)]


def make_card(unit: dict, image: Image.Image, action_name: str = "选定造型") -> Image.Image:
    card = Image.new("RGB", (384, 328), BG)
    card.paste(enlarged(image, 4), (0, 50))
    draw = ImageDraw.Draw(card)
    variant = unit["unit"].rsplit("_", 1)[-1]
    draw.text((14, 7), f'{unit["code"]}  {unit["callsign"]} / {variant}', font=font(23), fill=FG)
    draw.text((14, 306), action_name, font=font(18), fill=MUTED)
    return card


def make_overview(units: list[dict], images: list[Image.Image], labels: list[str]) -> Image.Image:
    canvas = Image.new("RGB", (1536, 736), BG)
    draw = ImageDraw.Draw(canvas)
    draw.text((24, 15), "夜行者 / 选定敌人与动作素材 v01", font=font(28), fill=FG)
    draw.text((25, 52), "8 个造型 · 18 组独立动作 · 144 帧原生像素 · 最近邻 4×预览", font=font(19), fill=MUTED)
    for index, (unit, im, label) in enumerate(zip(units, images, labels)):
        canvas.paste(make_card(unit, im, label), ((index % 4) * 384, 80 + (index // 4) * 328))
    return canvas


def build(manifest_path: Path = MANIFEST, output: Path = OUT) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    assert manifest["cell_size"] == [96, 64]
    assert manifest["foot_anchor"] == [48, 57]
    assert len(manifest["units"]) == 8
    units = manifest["units"]
    loaded: dict[str, dict[str, list[Image.Image]]] = {}
    records = []
    idles = []
    for unit in units:
        unit_id = unit["unit"]
        loaded[unit_id] = {}
        idle = Image.open(local_path(unit["idle"])).convert("RGBA")
        assert idle.size == (96, 64), unit_id
        idles.append(idle)
        preview_dir = output / "previews" / unit_id
        preview_dir.mkdir(parents=True, exist_ok=True)
        enlarged(idle, 6).save(preview_dir / "selected_6x.png", optimize=True)
        for action in unit["actions"]:
            name = action["name"]
            count, columns = action["frames"], action["columns"]
            assert (count, columns) == (8, 4), (unit_id, name)
            frames = [Image.open(output / "frames" / unit_id / name / f"{index:02d}.png").convert("RGBA") for index in range(count)]
            atlas = Image.open(local_path(action["sheet"])).convert("RGBA")
            assert atlas.size == (384, 128), (unit_id, name)
            for index, im in enumerate(frames):
                assert im.size == (96, 64), (unit_id, name, index)
                assert sum(im.getchannel("A").histogram()[1:255]) == 0, (unit_id, name, index)
                x, y = (index % columns) * 96, (index // columns) * 64
                assert atlas.crop((x, y, x + 96, y + 64)).tobytes() == im.tobytes(), (unit_id, name, index)
            loaded[unit_id][name] = frames
            hashes = [hashlib.sha256(im.tobytes()).hexdigest() for im in frames]
            delays = durations_for(count, float(action["fps"]))
            if not action["loop"]:
                delays[-1] += 400
            gif_frames = [enlarged(im, 6) for im in frames]
            gif_path = preview_dir / f"{name}.gif"
            gif(gif_path, gif_frames, delays)
            with Image.open(gif_path) as encoded:
                assert encoded.n_frames == count, (unit_id, name, "GIF frame count")
                for index, expected in enumerate(gif_frames):
                    encoded.seek(index)
                    assert encoded.convert("RGB").tobytes() == expected.tobytes(), (unit_id, name, index, "GIF pixel fidelity")
                    assert encoded.info["duration"] == delays[index], (unit_id, name, index, "GIF delay")
            sheet_preview = Image.new("RGB", (1152, 434), BG)
            draw = ImageDraw.Draw(sheet_preview)
            draw.text((16, 10), f'{unit["callsign"]} / {ACTION_NAMES[name]} / 8 帧 / {action["fps"]} fps', font=font(24), fill=FG)
            sheet_preview.paste(enlarged(atlas, 3), (0, 50))
            sheet_preview.save(preview_dir / f"{name}_frames_3x.png", optimize=True)
            records.append({"unit": unit_id, "action": name, "frames": count, "unique_frames": len(set(hashes)),
                            "fps": action["fps"], "runtime_loop": action["loop"], "frame_sha256": hashes,
                            "gif": str((preview_dir / f"{name}.gif").relative_to(output)).replace("\\", "/"),
                            "bounds": [list(im.getchannel("A").getbbox() or (0, 0, 0, 0)) for im in frames]})
        all_frames, all_delays = [], []
        for action in unit["actions"]:
            frames = loaded[unit_id][action["name"]]
            all_frames += [make_card(unit, im, ACTION_NAMES[action["name"]]) for im in frames]
            delays = durations_for(len(frames), float(action["fps"]))
            delays[-1] += 400
            all_delays += delays
        gif(preview_dir / "all_actions.gif", all_frames, all_delays)
    make_overview(units, idles, ["选定造型"] * len(units)).save(output / "selected_overview.png", optimize=True)
    overview_frames = []
    # Four groups show every sniper action, while two-action units alternate.
    for group in range(4):
        for index in range(8):
            poses, labels = [], []
            for unit in units:
                action = unit["actions"][group % len(unit["actions"])]
                poses.append(loaded[unit["unit"]][action["name"]][index])
                labels.append(ACTION_NAMES[action["name"]])
            overview_frames.append(make_overview(units, poses, labels))
    gif(output / "action_overview.gif", overview_frames, [90] * 32)
    report = {"passed": True, "units": len(units), "actions": len(records), "frames": sum(r["frames"] for r in records),
              "cell_size": [96, 64], "sampling": "nearest", "new_poses_drawn": False,
              "gif_decoded_pixel_match": True, "gif_delays_match": True,
              "gif_note": "GIFs repeat for inspection; non-looping game actions remain non-looping in manifest.",
              "actions_detail": records}
    assert (report["actions"], report["frames"]) == (18, 144)
    write_json(output / "preview_validation.json", report)
    return {key: report[key] for key in ["passed", "units", "actions", "frames", "cell_size", "sampling"]}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    parser.add_argument("--output", type=Path, default=OUT)
    args = parser.parse_args()
    print(json.dumps(build(args.manifest, args.output), ensure_ascii=False, indent=2))
