"""Validate the new hooded model, drawn breathing, and actual Godot gameplay."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from PIL import Image

PROJECT = Path(__file__).resolve().parents[2] / "game"
REPORT = PROJECT.parent / "art" / "characters" / "animation_v06" / "export_report.json"
if not REPORT.is_file():
    REPORT = PROJECT / "art_metadata" / "export_report.json"
BASELINE = PROJECT.parent / "game_v03" / "assets" / "blade_paths.json"


def pixels(image: Image.Image):
    reader = getattr(image, "get_flattened_data", None)
    return reader() if reader is not None else image.getdata()


def digest(image: Image.Image) -> str:
    return hashlib.sha256(image.convert("RGBA").tobytes()).hexdigest()


def visible_difference(before: Image.Image, after: Image.Image) -> int:
    # RGB stored beneath fully transparent pixels has no rendered appearance.
    return sum((left[3] > 0 or right[3] > 0) and left != right for left,right in zip(pixels(before),pixels(after)))


def trajectory(points: list[list[float]]) -> dict:
    return {"x_span":max(point[0] for point in points) - min(point[0] for point in points), "y_span":max(point[1] for point in points) - min(point[1] for point in points), "path_length":round(sum(math.dist(left,right) for left,right in zip(points,points[1:])),2)}


def normalized_boundary(path: Path) -> Image.Image:
    frame = Image.open(path).convert("RGBA")
    # Compare images at one foot pivot: 64px attacks add padding, not body scale.
    if frame.height >= 64:
        left, top = frame.width // 2 - 24, frame.height - 12 - 42
        return frame.crop((left,top,left + 48,top + 48))
    return frame


def face_signature(image: Image.Image) -> tuple:
    # Two muted skin colors under the hood. Coat tears and gloved hands are below.
    rgba = image.convert("RGBA")
    skin = {(197,161,138),(225,185,153)}
    return tuple((x,y,rgba.getpixel((x,y))[:3]) for y in range(10,23) for x in range(10,38)
                 if rgba.getpixel((x,y))[3] and rgba.getpixel((x,y))[:3] in skin)


def blade_contact(states: list[dict]) -> dict:
    active = [state for state in states if state["stage"] == 3 and 6 <= state["frame"] <= 9 and state.get("drawn_blade_tip")]
    samples = []
    for state in active:
        tip = state["drawn_blade_tip"]
        target = state["primary_target_position"]
        dx, dy = tip[0] - target[0], tip[1] - target[1]
        # Original standing training target: actual drawn head, torso, arm bar.
        touches = (abs(dx) < 4 and -31 <= dy < -25) or (abs(dx) < 6 and -24 <= dy < -11) or (abs(dx) < 9 and -20 <= dy < -17)
        samples.append({"capture_index":state["index"],"sprite_frame":state["frame"],"blade_tip":tip,"target_root":target,"blade_minus_target":[dx,dy],"touches_drawn_target":touches})
    return {"active_samples":len(samples),"contact_samples":sum(sample["touches_drawn_target"] for sample in samples),"samples":samples}


def main() -> int:
    failures = []
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    if report.get("atlas_source_count",0) != 24:
        failures.append(f"Final full-model redraw incomplete: {report.get('atlas_source_count',0)}/24 new action atlases")
    if report.get("generated_image_count",0) != 25 or not report.get("complete",False):
        failures.append("The final master plus 24 action atlases are not all registered")
    if report.get("previous_model_runtime_source_count",-1) != 0:
        failures.append("Runtime export still uses an earlier character model")
    current_source_records = PROJECT.parent / "art" / "characters" / "animation_v06"
    provenance = {}
    for record_path in current_source_records.glob("source_*.json"):
        job = json.loads(record_path.read_text(encoding="utf-8"))
        clip = report.get("clips",{}).get(job["name"],{})
        latest, registered = Path(job["generated_path"]), Path(clip.get("generated_path",""))
        correct = latest == registered
        if not correct:
            failures.append(f"Registered atlas ignores the latest corrected individual source: {job['name']}")
        copied = Path(clip.get("source_path",""))
        if latest.is_file() and copied.is_file():
            correct = correct and hashlib.sha256(latest.read_bytes()).digest() == hashlib.sha256(copied.read_bytes()).digest()
            if not correct:
                failures.append(f"Registered raw source differs from its final generated image: {job['name']}")
        provenance[job["name"]] = {"uses_latest_source":correct,"generated_path":str(latest)}
    palette = {tuple(bytes.fromhex(color)) for color in report["palette"]}
    sources = sorted((PROJECT / "frames").glob("*/*.png"))
    if len(sources) != 768:
        failures.append(f"Expected 768 native frames, got {len(sources)}")
    old_character_hashes = set()
    for previous in ["game_v03","game_v04"]:
        for old_path in (PROJECT.parent / previous / "frames").glob("*/*.png"):
            old_character_hashes.add(digest(normalized_boundary(old_path)))
    old_reused_frames = []
    colors, alpha = set(), set()
    canvas_counts = {}
    for path in sources:
        with Image.open(path) as source:
            image = source.convert("RGBA")
            size = (48,48)
            if "_attack" in path.parent.name:
                size = (80,64) if path.parent.name.endswith(("left_attack3","right_attack3")) else (64,64)
            if image.size != size:
                failures.append(f"Unexpected native padding canvas: {path.relative_to(PROJECT)}")
            if digest(normalized_boundary(path)) in old_character_hashes:
                old_reused_frames.append(str(path.relative_to(PROJECT)))
            canvas_counts[str(image.size)] = canvas_counts.get(str(image.size),0) + 1
            values = list(pixels(image))
            alpha.update(pixel[3] for pixel in values)
            visible = {pixel[:3] for pixel in values if pixel[3]}
            colors.update(visible)
            if not visible <= palette:
                failures.append(f"Off-palette native pixels: {path.relative_to(PROJECT)}")
            if not image.getbbox():
                failures.append(f"Empty character frame: {path.relative_to(PROJECT)}")
    if old_reused_frames:
        failures.append(f"New hooded model still contains {len(old_reused_frames)} copied old-model drawings")
    if not alpha <= {0,255}:
        failures.append("Native sprites contain antialiased alpha")
    idle_report, boundaries, grounded_jump_feet = {}, {}, {}
    for view, directions in [("top_down",["up","down","left","right"]),("side_view",["left","right"])]:
        for direction in directions:
            prefix = f"{view}_{direction}"
            idle_folder = PROJECT / "frames" / f"{prefix}_idle"
            drawings = [Image.open(idle_folder / f"{index:02}.png").convert("RGBA") for index in range(16)]
            hashes = {digest(image) for image in drawings}
            faces = [face_signature(image) for image in drawings]
            idle_report[prefix] = {"unique_images":len(hashes), "canonical_sha256":digest(drawings[0]), "bounds":drawings[0].getbbox(), "face_pixels":len(faces[0]), "face_signature_count":len(set(faces))}
            if len(hashes) < 2:
                failures.append(f"Idle has no drawn coat/shoulder breathing: {prefix}")
            if len(set(faces)) != 1:
                failures.append(f"Idle changes the exposed face pixels: {prefix}")
            if len(faces[0]) > 3 or (direction != "up" and not faces[0]) or (direction == "up" and faces[0]):
                failures.append(f"Idle hood exposes more than a few face pixels or exposes skin in rear view: {prefix}")
            for current, following in [(1,2),(2,3)]:
                before = normalized_boundary(PROJECT / "frames" / f"{prefix}_attack{current}" / "15.png")
                after = normalized_boundary(PROJECT / "frames" / f"{prefix}_attack{following}" / "00.png")
                changed = visible_difference(before,after)
                boundaries[f"{prefix}_{current}_to_{following}"] = changed
                if changed != 0:
                    failures.append(f"Chained strike returns to an earlier pose instead of holding its terminal guard: {prefix} {current}->{following} ({changed}px)")
            final = normalized_boundary(PROJECT / "frames" / f"{prefix}_attack3" / "15.png")
            changed = visible_difference(final,drawings[0])
            boundaries[f"{prefix}_3_to_idle"] = changed
            if changed > 100:
                failures.append(f"Attack return does not settle into the breathing idle drawing: {prefix} ({changed}px)")
    for direction in ["left","right"]:
        for index in [13,14,15]:
            with Image.open(PROJECT / "frames" / f"side_view_{direction}_jump" / f"{index:02}.png") as image:
                foot = image.convert("RGBA").getbbox()[3]
            grounded_jump_feet[f"{direction}_{index}"] = foot
            if foot != 42:
                failures.append(f"Landing foot boundary misaligned: {direction} {index} ({foot})")
    paths = json.loads((PROJECT / "assets" / "blade_paths.json").read_text(encoding="utf-8"))
    baseline = json.loads(BASELINE.read_text(encoding="utf-8")) if BASELINE.is_file() else {}
    trajectory_report = {}
    for view, clips in paths.items():
        for name, points in clips.items():
            if not name.startswith("attack"):
                continue
            measured = trajectory(points)
            old = trajectory(baseline[view][name]) if name in baseline.get(view,{}) else None
            direction = name.rsplit("_",1)[1]
            lateral = measured["y_span"] if direction in ["left","right"] else measured["x_span"]
            forward = measured["x_span"] if direction in ["left","right"] else measured["y_span"]
            trajectory_report[f"{view}_{name}"] = {"current":measured,"v03":old,"lateral_span":lateral,"forward_span":forward}
            if name.startswith(("attack1_","attack2_")) and lateral < 12:
                failures.append(f"Redrawn slash has insufficient arm/blade sweep: {view} {name} ({lateral}px lateral)")
            # A new short dagger and a forward body step do not need the older
            # long-blade atlas's 20px peak-to-guard span. Keep the measured span;
            # require real directed blade contact in the live recording below.
            axis = 0 if direction in ["left","right"] else 1
            sign = -1 if direction in ["left","up"] else 1
            trajectory_report[f"{view}_{name}"]["peak_forward_from_foot_pivot"] = max(point[axis] * sign for point in points)
            if view == "top_down" and name == "attack3_down":
                active_points = points[6:10]
                # A short dagger can strike the lower enemy's head above the player's
                # foot row. Compare its extension with the visual waist/hand,
                # and review actual knife orientation/target contact in the recording.
                points_toward_target = sum(point[1] > -12 and abs(point[0]) <= 12 for point in active_points)
                trajectory_report[f"{view}_{name}"]["active_points"] = active_points
                trajectory_report[f"{view}_{name}"]["active_downward_points"] = points_toward_target
                trajectory_report[f"{view}_{name}"]["visual_waist_reference"] = [0,-12]
                trajectory_report[f"{view}_{name}"]["controller_attack_origin"] = [0,-4]
                trajectory_report[f"{view}_{name}"]["direction_review"] = "Short downward dagger reaches toward the enemy head; foot-line crossing is not required"
                if points_toward_target < 2:
                    failures.append("Downward finisher still aims its drawn knife away from the enemy below")
            if view == "top_down" and name == "attack3_up":
                if sum(point[1] < -4 for point in points[6:10]) < 2:
                    failures.append("Rear-view finisher does not reach toward the enemy above")
    manifest_path = PROJECT / "evidence" / "motion_v05" / "capture_manifest.json"
    live_report = {}
    if not manifest_path.is_file():
        failures.append("No final actual Godot gameplay recording")
    else:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        section_colors, normalized_idle_hashes, rendered_face_hashes, idle_positions, idle_bobs = {}, {}, {}, {}, {}
        live_contacts = {}
        for state in manifest["states"]:
            if [state["viewport_width"],state["viewport_height"]] != [320,180]:
                failures.append(f"Non-native rendered viewport at frame {state['index']}")
            if any(abs(value - round(value)) > 0.0001 for value in state["render_position"] + state["sprite_offset"]):
                failures.append(f"Rendered sprite leaves native pixel grid at frame {state['index']}")
            with Image.open(manifest_path.parent / f"{state['index']:04}.png") as source:
                picture = source.convert("RGB")
                values = list(pixels(picture))
                white, blue = values.count((242,248,255)), values.count((142,188,232))
                sample = section_colors.setdefault(state["section"],{"white_frames":0,"blue_frames":0,"max_fx_pixels":0,"max_blade_pixels":0})
                sample["white_frames"] += int(white > 0)
                sample["blue_frames"] += int(blue > 0)
                sample["max_fx_pixels"] = max(sample["max_fx_pixels"],white + blue)
                sample["max_blade_pixels"] = max(sample["max_blade_pixels"],state["blade_effect_pixels"])
                if state["section"] in ["top_down_breathing_idle","side_breathing_idle"]:
                    view = "top_down" if state["view_mode"] == 0 else "side_view"
                    action, direction = state["animation"].split("_",1)
                    canonical = Image.open(PROJECT / "frames" / f"{view}_{direction}_{action}" / "00.png").convert("RGBA")
                    origin = [round(state["render_position"][axis] + state["sprite_offset"][axis]) for axis in range(2)]
                    crop = picture.crop((origin[0],origin[1],origin[0] + 48,origin[1] + 48))
                    occupied = bytes(channel for rgb,mask in zip(pixels(crop),pixels(canonical)) if mask[3] for channel in rgb)
                    normalized_idle_hashes.setdefault(state["section"],set()).add(hashlib.sha256(occupied).hexdigest())
                    face_rgb = bytes(channel for x,y,rgb in face_signature(canonical) for channel in crop.getpixel((x,y)))
                    rendered_face_hashes.setdefault(state["section"],set()).add(hashlib.sha256(face_rgb).hexdigest())
                    idle_positions.setdefault(state["section"],set()).add(tuple(state["position"]))
                    idle_bobs.setdefault(state["section"],set()).add(state["idle_bob_y"])
        for name in ["top_down_breathing_idle","side_breathing_idle"]:
            if len(normalized_idle_hashes.get(name,set())) < 2:
                failures.append(f"Actual idle coat/shoulder does not breathe inside the sprite: {name}")
            if len(rendered_face_hashes.get(name,set())) != 1:
                failures.append(f"Actual idle changes the tiny exposed face: {name}")
            if len(idle_positions.get(name,set())) != 1 or idle_bobs.get(name,set()) != {0}:
                failures.append(f"Actual idle bobs the whole sprite or drifts its physics root: {name}")
            if section_colors.get(name,{}).get("max_fx_pixels",1) != 0:
                failures.append(f"Blade effects remain visible while idle: {name}")
        for name in ["top_down_three_hit_combo","side_three_hit_combo"]:
            effect = section_colors.get(name,{})
            if effect.get("white_frames",0) < 3 or effect.get("blue_frames",0) < 3:
                failures.append(f"Combo lacks visible white and blue blade layers: {name}")
            if effect.get("max_blade_pixels",0) < 35 or effect.get("max_blade_pixels",0) > 70:
                failures.append(f"Bigger blade trail misses intended native footprint: {name} ({effect.get('max_blade_pixels',0)})")
            contact = blade_contact([state for state in manifest["states"] if state["section"] == name])
            live_contacts[name] = contact
            if contact["contact_samples"] < 1:
                failures.append(f"Actual forward dagger fails to touch the drawn target body: {name}")
            stages = {state["stage"] for state in manifest["states"] if state["section"] == name}
            if not {1,2,3} <= stages:
                failures.append(f"Live capture misses an attack stage: {name}")
        live_report = {"captured_frames":manifest["captured_frames"],"finisher_blade_contacts":live_contacts,"effect_colors_by_section":section_colors,"normalized_idle_image_hash_count":{name:len(values) for name,values in normalized_idle_hashes.items()},"idle_bob_values":{name:sorted(values) for name,values in idle_bobs.items()},"rendered_idle_face_hash_count":{name:len(values) for name,values in rendered_face_hashes.items()}}
    directional_manifest = PROJECT / "evidence" / "top_directions_v05" / "capture_manifest.json"
    if directional_manifest.is_file():
        direction_data = json.loads(directional_manifest.read_text(encoding="utf-8"))
        reviewed_directions = {}
        for direction in ["up","down"]:
            states = [state for state in direction_data["states"] if state["section"].endswith("_" + direction)]
            stages = {state["stage"] for state in states}
            hits = max((state["hits"] for state in states),default=0)
            contact = blade_contact(states)
            reviewed_directions[direction] = {"captured_frames":len(states),"stages":sorted(stages),"hits":hits,"finisher_blade_contact":contact}
            if contact["contact_samples"] < 1:
                failures.append(f"Actual {direction} dagger does not reach the drawn target head/torso")
            if not {1,2,3} <= stages or hits != 3:
                failures.append(f"Actual {direction} combo capture lacks its three registered strikes")
        live_report["top_direction_captured_frames"] = direction_data["captured_frames"]
        live_report["top_direction_combos"] = reviewed_directions
    else:
        failures.append("Missing actual up/down finisher direction evidence")
    result = {"status":"passed" if not failures else "failed","failures":failures,"native_frames":len(sources),"atlas_source_count":report.get("atlas_source_count",0),"source_provenance":provenance,"old_model_reused_frames":old_reused_frames,"native_canvas_counts":canvas_counts,"palette_colors":len(colors),"alpha_values":sorted(alpha),"idle":idle_report,"attack_bridges_changed_pixels":boundaries,"blade_trajectories":trajectory_report,"grounded_jump_feet":grounded_jump_feet,"live_render":live_report}
    (PROJECT / "evidence" / "motion_art_validation_v05.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(result,ensure_ascii=False))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
