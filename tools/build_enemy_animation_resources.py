"""Build Godot SpriteFrames from the delivered enemy art manifest.

No artwork is resampled here. Left-facing poses use AnimatedSprite2D.flip_h.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "game/assets/enemy_animations_v01/manifest.json"


def godot_path(path: str) -> str:
    return json.dumps(path, ensure_ascii=False)


def build(manifest_path: Path) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    cell_w, cell_h = manifest["cell_size"]
    if (cell_w, cell_h) != (96, 64):
        raise ValueError("This gallery expects the agreed native 96×64 art cells")
    written = []
    for unit in manifest["units"]:
        name = unit["unit"]
        idle = unit.get("idle", f"res://assets/enemy_animations_v01/{name}/idle.png")
        actions = unit["actions"]
        if any(not isinstance(action, dict) for action in actions):
            raise ValueError("Use final manifest action objects, not selection strings")
        textures = [idle] + [action["sheet"] for action in actions]
        texture_ids = {path: f"tex_{index}" for index, path in enumerate(dict.fromkeys(textures))}
        definitions = []
        for path, tex_id in texture_ids.items():
            local = ROOT / "game" / path.removeprefix("res://")
            if not local.is_file():
                raise FileNotFoundError(local)
            definitions += [f'[ext_resource type="Texture2D" path={godot_path(path)} id="{tex_id}"]', ""]
        atlas_defs = []
        anim_defs = []

        def add_atlas(resource_id: str, texture: str, index: int, columns: int) -> None:
            x, y = (index % columns) * cell_w, (index // columns) * cell_h
            atlas_defs.extend([
                f'[sub_resource type="AtlasTexture" id="{resource_id}"]',
                f'atlas = ExtResource("{texture_ids[texture]}")',
                f"region = Rect2({x}, {y}, {cell_w}, {cell_h})", "",
            ])

        def add_animation(action_name: str, ids: list[str], fps: float, loop: bool) -> None:
            frames = ", ".join('{"duration": 1.0, "texture": SubResource("%s")}' % atlas_id for atlas_id in ids)
            anim_defs.append('{"frames": [%s], "loop": %s, "name": &"right_%s", "speed": %s}' % (
                frames, str(loop).lower(), action_name, float(fps)))

        add_atlas("idle_0", idle, 0, 1)
        add_animation("idle", ["idle_0"], 1, True)
        for action in actions:
            count, columns = int(action["frames"]), int(action["columns"])
            if count != 8 or columns != 4:
                raise ValueError(f"{name}/{action['name']} must have eight frames in four columns")
            ids = [f"{action['name']}_{index}" for index in range(count)]
            for index, resource_id in enumerate(ids):
                add_atlas(resource_id, action["sheet"], index, columns)
            add_animation(action["name"], ids, float(action["fps"]), bool(action["loop"]))
            if action["name"] == "prone_down":
                add_animation("prone_idle", [ids[-1]], 1, True)
                add_animation("prone_up", list(reversed(ids)), float(action["fps"]), False)
        output = ROOT / "game/assets/enemy_animations_v01" / name / "animations.tres"
        text = '\n'.join([
            f'[gd_resource type="SpriteFrames" load_steps={len(texture_ids) + 1 + sum(1 for line in atlas_defs if line.startswith("[sub_resource"))} format=3]',
            "", *definitions, *atlas_defs, "[resource]", "animations = [", ",\n".join(anim_defs), "]", "",
        ])
        output.write_text(text, encoding="utf-8", newline="\n")
        written.append(str(output.relative_to(ROOT)).replace("\\", "/"))
    return {"units": len(written), "resources": written, "cell_size": [cell_w, cell_h], "mirroring": "AnimatedSprite2D.flip_h"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    print(json.dumps(build(args.manifest), ensure_ascii=False, indent=2))
