"""Check long-blade exports and whole-viewport contact-pause GPU evidence."""
from __future__ import annotations

import hashlib
import json
import math
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image, ImageOps

PROJECT = Path(__file__).resolve().parents[1]
EVIDENCE = PROJECT / "evidence"
ART = PROJECT.parent / "art" / "characters" / "animation_v08"
REPORT = ART / "export_report.json"
SOURCE = EVIDENCE / "sword_motion_v07"
BASE = PROJECT.parent / "game_v06"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels(image: Image.Image):
    reader = getattr(image, "get_flattened_data", None)
    return reader() if reader else image.getdata()


def pause_groups(states: list[dict]) -> list[list[dict]]:
    groups = []
    for state in states:
        if state["stop_active"]:
            if not groups or state["index"] != groups[-1][-1]["index"] + 1:
                groups.append([])
            groups[-1].append(state)
    return groups


def root_mirror(image: Image.Image) -> Image.Image:
    flipped = ImageOps.mirror(image)
    result = Image.new(image.mode, image.size)
    result.paste(flipped, (1,0))
    return result


def physical_contact(state: dict, report: dict) -> dict:
    """Measure drawn steel against the native target rectangles, not hitboxes."""
    action, direction = state["animation"].rsplit("_", 1)
    name = f"side_view_{direction}_{action}"
    frame = state["frame"]
    record = report["clips"][name]["body_preservation"]["frames"][frame]
    image = Image.open(PROJECT / "frames" / name / f"{frame:02}.png").convert("RGBA")
    mask = Image.open(record["new_weapon_mask_path"]).convert("L")
    steel_colors = {tuple(bytes.fromhex(value)) for value in report["palette"][13:17]}
    # AnimatedSprite2D is not centered; its explicit offset is minus the pivot.
    origin = [state["render_position"][axis] + state["sprite_offset"][axis] for axis in (0, 1)]
    steel = [(index % 112 + origin[0], index // 112 + origin[1])
             for index, (color, selected) in enumerate(zip(pixels(image), pixels(mask)))
             if selected and color[3] and color[:3] in steel_colors]
    target = next(target for target in state["targets"] if target["slash_flash_left"] > 0)
    tx, ty = map(round, target["position"])
    # These inclusive/exclusive rectangles match training_target.gd::_draw.
    rectangles = {"lower_stem": (tx-2, ty-11, tx+2, ty), "base": (tx-6, ty-1, tx+6, ty),
                  "torso": (tx-6, ty-24, tx+6, ty-11), "head": (tx-4, ty-31, tx+4, ty-25)}
    overlap = {part: [[int(x), int(y)] for x, y in steel if left <= x < right and top <= y < bottom]
               for part, (left, top, right, bottom) in rectangles.items()}
    left, top, right, bottom = rectangles["head"]
    head_distance = min(math.hypot(max(left-x, 0, x-(right-1)), max(top-y, 0, y-(bottom-1))) for x, y in steel)
    return {"captured_index": state["index"], "animation": state["animation"], "pose_frame": frame,
            "blade_tip_native": state["drawn_blade_tip"], "player_native": state["render_position"],
            "target_native": [tx, ty], "visible_steel_overlap_pixels": overlap,
            "steel_distance_to_visible_head_pixels": round(head_distance, 3),
            "blade_tip_in_front_of_player": state["drawn_blade_tip"][0] > state["render_position"][0],
            "initial_slash_flash_seconds": target["slash_flash_left"]}


def main() -> int:
    failures = []
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    palette = {tuple(bytes.fromhex(color)) for color in report["palette"]}
    frame_paths = sorted((PROJECT / "frames").glob("*/*.png"))
    sides = [path for path in frame_paths if path.parent.name.startswith("side_view_")]
    tops = [path for path in frame_paths if path.parent.name.startswith("top_down_")]
    clips = {path.parent.name for path in frame_paths}
    if len(clips) != 52 or len(frame_paths) != 832 or len(sides) != 384 or len(tops) != 448:
        failures.append("Expected 52/832 total, 24/384 SIDE and 28/448 TOP actions/frames")
    if not report.get("complete"):
        failures.append("Long-blade export is incomplete")
    top_changed = [str(path.relative_to(PROJECT)) for path in tops if sha(path) != sha(BASE / path.relative_to(PROJECT))]
    if top_changed:
        failures.append(f"TOP PNG bytes changed: {top_changed[:3]}")
    if sha(PROJECT / "assets/top_down.tres") != sha(BASE / "assets/top_down.tres"):
        failures.append("TOP SpriteFrames resource changed")
    blade = json.loads((PROJECT / "assets/blade_paths.json").read_text(encoding="utf-8"))
    old_blade = json.loads((BASE / "assets/blade_paths.json").read_text(encoding="utf-8"))
    if blade["top_down"] != old_blade["top_down"]:
        failures.append("TOP blade path data changed")
    native = {}
    for name in sorted({path.parent.name for path in sides}):
        paths = sorted((PROJECT / "frames" / name).glob("*.png"))
        if len(paths) != 16:
            failures.append(f"{name}: missing 16-frame sequence")
        unique = set()
        for path in paths:
            image = Image.open(path).convert("RGBA")
            unique.add(hashlib.sha256(image.tobytes()).hexdigest())
            if image.size != (112,96):
                failures.append(f"{name}/{path.name}: wrong padded canvas")
            data = list(pixels(image))
            if any(pixel[3] not in (0,255) for pixel in data):
                failures.append(f"{name}/{path.name}: antialiased alpha")
            if any(pixel[3] and pixel[:3] not in palette for pixel in data):
                failures.append(f"{name}/{path.name}: color outside approved palette")
            bbox = image.getbbox()
            if not bbox or bbox[0] == 0 or bbox[1] == 0 or bbox[2] == 112 or bbox[3] == 96:
                failures.append(f"{name}/{path.name}: empty or edge-clipped pose")
        native[name] = {"frames":len(paths),"size":[112,96],"pivot":[56,84],"unique_poses":len(unique)}

    protected_body = report.get("body_preservation", {})
    if not protected_body or protected_body.get("changed_body_pixels", -1) != 0:
        failures.append("Protected original body-pixel preservation metadata is missing or reports changes")
    checked_body_frames = 0
    protected_pixels_checked = 0
    changed_body_pixels = 0
    changes_outside_weapon_masks = 0
    blade_lengths = {}
    independently_measured_blades = {}
    steel_colors = {tuple(bytes.fromhex(value)) for value in report["palette"][13:17]}
    for name in sorted({path.parent.name for path in sides if "_right_" in path.parent.name}):
        clip = report.get("clips",{}).get(name,{})
        records = clip.get("body_preservation",{}).get("frames",[])
        if len(records) != 16:
            failures.append(f"{name}: explicit 16-frame body/weapon masks missing")
            continue
        blade_lengths[name] = [frame["steel_length"] for frame in records]
        for record in records:
            index = record["frame"]
            original = Image.open(Path(record["base_path"])).convert("RGBA")
            old = Image.new("RGBA",(112,96))
            old.alpha_composite(original,tuple(record["root_padding"]))
            old_mask = Image.open(Path(record["old_weapon_mask_path"])).convert("L")
            new_mask = Image.open(Path(record["new_weapon_mask_path"])).convert("L")
            protection = Image.open(Path(record["protected_body_mask_path"])).convert("L")
            for direction in ("right","left"):
                current_name = name.replace("_right_", f"_{direction}_")
                current = Image.open(PROJECT / "frames" / current_name / f"{index:02}.png").convert("RGBA")
                reference = old
                if direction == "left":
                    original_left = Image.open(BASE / "frames" / current_name / f"{index:02}.png").convert("RGBA")
                    reference = Image.new("RGBA",(112,96))
                    reference.alpha_composite(original_left,tuple(record["root_padding"]))
                masks = [old_mask,new_mask,protection] if direction == "right" else [root_mirror(mask) for mask in (old_mask,new_mask,protection)]
                if any(mask.size != (112,96) or any(value not in (0,255) for value in pixels(mask)) for mask in masks):
                    failures.append(f"{current_name}/{index}: nonbinary or mis-sized weapon/body masks")
                    continue
                before,after = list(pixels(reference)),list(pixels(current))
                erased,added,protected = [list(pixels(mask)) for mask in masks]
                steel_points = [(offset%112,offset//112) for offset,(color,mask) in enumerate(zip(after,added))
                                if mask and color[3] and color[:3] in steel_colors]
                visible_chord = max((math.dist(left,right) for index,left in enumerate(steel_points) for right in steel_points[index+1:]),default=0)
                independently_measured_blades.setdefault(current_name,[]).append(round(visible_chord,3))
                if visible_chord < 10:
                    failures.append(f"{current_name}/{index}: visible long steel blade collapsed to {visible_chord:.2f}px")
                expected_protected = [bool(pixel[3]) and not removed and not overlaid for pixel,removed,overlaid in zip(before,erased,added)]
                if any(bool(value) != expected for value,expected in zip(protected,expected_protected)):
                    failures.append(f"{current_name}/{index}: body protection mask omits original nonweapon pixels")
                body_changes = sum(bool(mask) and left != right for mask,left,right in zip(protected,before,after))
                other_changes = sum((left[3] or right[3]) and left != right and not remove and not add
                                    for left,right,remove,add in zip(before,after,erased,added))
                changed_body_pixels += body_changes
                changes_outside_weapon_masks += other_changes
                protected_pixels_checked += sum(bool(value) for value in protected)
                checked_body_frames += 1
                if body_changes or other_changes:
                    failures.append(f"{current_name}/{index}: changed {body_changes} protected body / {other_changes} nonweapon pixels")
    if checked_body_frames != 384:
        failures.append(f"Independently verified only {checked_body_frames}/384 side body frames")

    provenance = {}
    source_records = sorted(ART.glob("source_*.json"))
    if len(source_records) != 12:
        failures.append(f"Expected 12 current RIGHT edited atlases, found {len(source_records)}")
    for path in source_records:
        job = json.loads(path.read_text(encoding="utf-8"))
        current = Path(job["generated_path"])
        registered = report.get("clips",{}).get(job["name"],{})
        final = Path(registered.get("generated_path", ""))
        raw = Path(registered.get("source_path", ""))
        same = current.resolve() == final.resolve() and current.is_file() and raw.is_file() and sha(current) == sha(raw)
        if not same:
            failures.append(f"Latest edited source not registered: {job['name']}")
        provenance[job["name"]] = {"uses_latest_generated_source":same,"sha256":sha(current) if current.is_file() else None}

    manifest = json.loads((SOURCE / "capture_manifest.json").read_text(encoding="utf-8"))
    states = manifest["states"]
    captured_at = (SOURCE / "0000.png").stat().st_mtime
    capture_inputs = [PROJECT / "scripts" / name for name in ("player.gd", "arena.gd", "training_target.gd", "controls.gd")]
    capture_inputs += [PROJECT / "project.godot", PROJECT / "scenes/main.tscn", PROJECT / "scenes/player.tscn",
                       PROJECT / "assets/side_view.tres", PROJECT / "assets/top_down.tres", PROJECT / "assets/blade_paths.json",
                       PROJECT / "tests/record_sword_motion_v07.gd", REPORT]
    capture_current = all(path.stat().st_mtime <= captured_at for path in capture_inputs + frame_paths)
    if not capture_current:
        failures.append("A runtime input was written after the first focused GPU capture frame")
    capture_provenance = {"all_inputs_last_written_before_first_capture": capture_current,
                          "first_png_saved_utc": datetime.fromtimestamp(captured_at, timezone.utc).isoformat(),
                          "current_input_sha256": {str(path.relative_to(PROJECT.parent)): sha(path) for path in capture_inputs},
                          "note": "Hashes recorded during final validation; file write times and captured poses confirm capture freshness."}
    if len(states) != 500 or manifest["captured_frames"] != 500:
        failures.append("Focused 500-frame GPU contact capture is incomplete")
    grid = all(all(value == round(value) for value in state["render_position"]+state["sprite_offset"])
               and all(all(value == round(value) for value in line[:4]) for line in state["air_lines"])
               and all(all(value == round(value) for value in ghost[:2]) for ghost in state["afterimage_positions"])
               and all(all(all(value == round(value) for value in point) for point in target["slash_pixels"]) for target in state["targets"])
               for state in states)
    if not grid:
        failures.append("An actor/airflow/afterimage/enemy slashlight leaves the native pixel grid")
    if any(Image.open(SOURCE / f"{state['index']:04}.png").size != (320,180) for state in states):
        failures.append("Native viewport resolution changed")
    live = {}
    expected_pauses = {"side_longblade_combo":[4,4,4],"side_longblade_crouch":[4],"side_rising_slash":[4],"side_dash_stab":[4],"critical_side_x_stop":[4,4,6]}
    for section in manifest["sections"]:
        name = section["name"]
        subset = [state for state in states if state["section"] == name]
        groups = pause_groups(subset)
        if [len(group) for group in groups] != expected_pauses[name]:
            failures.append(f"{name}: wrong displayed pause lengths {[len(group) for group in groups]}")
        proofs = []
        for group in groups:
            first, last = group[0], group[-1]
            requested = first["stop_requested_frames"]
            frame_data = [Image.open(SOURCE / f"{state['index']:04}.png").convert("RGB").tobytes() for state in group]
            identical = all(data == frame_data[0] for data in frame_data)
            sequence = ([state["index"] for state in group] == list(range(first["index"],last["index"]+1))
                        and [state["engine_frame"] for state in group] == list(range(first["engine_frame"],last["engine_frame"]+1))
                        and [state["stop_displayed_before_render"] for state in group] == list(range(requested)))
            stable = all(state["paused"] and state["canvas_offset"] == [1,0] and state["hud_offset"] == [1,0]
                         and all(state[key] == first[key] for key in ("position","targets","frame","frame_progress","air_lines","afterimage_positions"))
                         for state in group)
            after = states[last["index"]+1]
            resumed = not after["paused"] and after["canvas_offset"] == [0,0] and after["hud_offset"] == [0,0]
            finished = next((event for event in manifest["hit_stop_events"] if event["event"] == "finished" and event["engine_frame"] == last["engine_frame"] and event["section"] == name),{})
            duration = finished.get("elapsed_seconds",0)
            if not identical or not sequence or not stable or not resumed or duration+0.00001 < requested/60:
                failures.append(f"{name}/{first['index']}: incomplete whole-viewport freeze, shared HUD shift or visible duration")
            proofs.append({"captured_indices":[state["index"] for state in group],"rendered_frames":len(group),"nominal_min_frames":requested,
                           "elapsed_seconds":duration,"full_viewport_png_pixels_identical":identical,"world_and_hud_native_offset":[1,0],"scene_physics_and_effects_fixed":stable,"restored_after_pause":resumed})
        peak_light = max(max((len(target["slash_pixels"]) for target in state["targets"]),default=0) for state in subset)
        if peak_light == 0:
            failures.append(f"{name}: confirmed contacts did not show enemy slashlight")
        if any(target["slash_pixels"] for target in subset[-1]["targets"]):
            failures.append(f"{name}: enemy slashlight did not expire")
        live[name] = {"frames":len(subset),"hits":max(state["hits"] for state in subset),"enemy_slashlight_peak_pixels":peak_light,"contact_pauses":proofs,
                      "airflow_peak":max(state["airflow_count"] for state in subset),"afterimages_peak":max(len(state["afterimage_positions"]) for state in subset)}
    physical = {}
    for name, expected in (("side_longblade_combo", 7), ("side_rising_slash", 3)):
        section_states = [state for state in states if state["section"] == name]
        first = pause_groups(section_states)[0][0]
        contact = physical_contact(first, report)
        before = [state for state in section_states if state["index"] < first["index"]]
        contact["no_hits_before_first_pause"] = all(state["hits"] == 0 and not state["stop_active"] for state in before)
        if first["frame"] != expected or not contact["blade_tip_in_front_of_player"] or not contact["no_hits_before_first_pause"]:
            failures.append(f"{name}: contact started on a backward or mistimed pose")
        overlap = contact["visible_steel_overlap_pixels"]
        if name == "side_longblade_combo":
            contact["review"] = "Frame 7 steel intersects the enemy lower stem and base; contact is below the torso slash flash."
            if not overlap["lower_stem"] or not overlap["base"]:
                failures.append("First standing strike's forward steel does not intersect the victim lower stem/base")
        else:
            contact["review"] = "Frame 3 steel intersects the upper left torso edge, within 7 native pixels of the head; the blade has not passed overhead."
            if not overlap["torso"] or contact["steel_distance_to_visible_head_pixels"] > 7:
                failures.append("Rising contact blade misses the victim upper body")
        physical[name] = contact
    functional = json.loads((EVIDENCE / "test_results_v07.json").read_text(encoding="utf-8"))
    if functional.get("status") != "passed" or functional.get("failures") or functional.get("checks",0) < 405:
        failures.append("Base controls and contact-response functional checks did not all pass")
    previews = json.loads((EVIDENCE / "sword_motion_previews.json").read_text(encoding="utf-8"))
    if len(previews) != 5 or any(not Path(path).is_file() for path in previews.values()):
        failures.append("Five focused gameplay previews are missing")
    result = {"edition":"v07","status":"failed" if failures else "passed","failures":failures,"clips":len(clips),"frames":len(frame_paths),
              "side_clips":24,"side_frames":len(sides),"unchanged_top_frames":len(tops)-len(top_changed),"edited_source_atlases":len(source_records),
              "native_side_clips":native,"body_preservation":{**protected_body,"independent_frames_checked":checked_body_frames,
                   "protected_pixels_checked":protected_pixels_checked,"independent_changed_body_pixels":changed_body_pixels,
                   "changes_outside_weapon_masks":changes_outside_weapon_masks},"visible_blade_lengths_native_pixels":blade_lengths,
              "independently_measured_blade_chords":independently_measured_blades,"source_provenance":provenance,
              "functional_checks":functional.get("checks"),"capture_provenance":capture_provenance,"physical_contact_review":physical,
              "live_capture":{"captured_frames":len(states),"native_viewport":[320,180],"pixel_grid_preserved":grid,"sections":live},
              "gif_timing_note":"Nearest-neighbor 3x previews use 20ms GIF timing. Exact runtime 4/6 frames and >=67/100ms durations are verified from actual GPU PNGs and render metadata.",
              "collision_note":"Sword light is visual; damage uses forward/swept gameplay areas with wall checks."}
    (EVIDENCE / "sword_art_validation_v07.json").write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"status":result["status"],"failures":failures,"clips":len(clips),"frames":len(frame_paths),"captured_frames":len(states)},ensure_ascii=False))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
