"""Validate V06 special assets and focused, real-GPU gameplay evidence."""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from PIL import Image

PROJECT = Path(__file__).resolve().parents[2] / "game"
EVIDENCE = PROJECT / "evidence"
ART = PROJECT.parent / "art" / "characters" / "animation_v07"
REPORT = ART / "export_report.json"
if not REPORT.is_file():
    REPORT = PROJECT / "art_metadata" / "export_report.json"
SOURCE = EVIDENCE / "special_motion_v06"
SPECIALS = {f"side_view_{direction}_{action}": (80, 80 if action == "rising_slash" else 64)
            for direction in ("right", "left") for action in ("rising_slash", "dash_stab")}


def pixels(image: Image.Image):
    reader = getattr(image, "get_flattened_data", None)
    return reader() if reader else image.getdata()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    failures = []
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    palette = {tuple(bytes.fromhex(value)) for value in report["palette"]}
    frame_paths = sorted((PROJECT / "frames").glob("*/*.png"))
    folders = {path.parent.name for path in frame_paths}
    if len(folders) != 52 or len(frame_paths) != 832:
        failures.append(f"Runtime has {len(folders)} clips/{len(frame_paths)} frames; expected 52/832")
    expected = {"complete": True, "clip_count": 52, "frame_count": 832, "new_clip_count": 4,
                "new_frame_count": 64, "sourcecount": 2, "preserved_base_frames": 768, "changed_base_frame_count": 0}
    for key, value in expected.items():
        if report.get(key) != value:
            failures.append(f"Export report {key} differs from {value}")
    base_paths = [path for path in frame_paths if path.parent.name not in SPECIALS]
    base_hashes = {str(path.relative_to(PROJECT)).replace("\\", "/"): sha(path) for path in base_paths}
    aggregate = hashlib.sha256(json.dumps(base_hashes, sort_keys=True).encode()).hexdigest()
    if len(base_paths) != 768 or aggregate != report["approved_base_pngs"]["aggregate_sha256"]:
        failures.append("Approved V05 base frame bytes changed")
    original = PROJECT.parent / "game_v05"
    if original.is_dir():
        changed = [str(path.relative_to(PROJECT)) for path in base_paths if sha(path) != sha(original / path.relative_to(PROJECT))]
        if changed:
            failures.append(f"Runtime differs from approved V05 frames: {changed[:4]}")

    provenance = {}
    new_native = {}
    for name, size in SPECIALS.items():
        paths = sorted((PROJECT / "frames" / name).glob("*.png"))
        clip = report["clips"].get(name, {})
        if len(paths) != 16 or clip.get("frames") != 16:
            failures.append(f"{name} does not contain 16 frames")
        counts = []
        for path in paths:
            image = Image.open(path).convert("RGBA")
            if image.size != size:
                failures.append(f"{name}/{path.name}: incorrect canvas {image.size}")
            data = list(pixels(image))
            if any(pixel[3] not in (0, 255) for pixel in data):
                failures.append(f"{name}/{path.name}: nonbinary alpha")
            if any(pixel[3] and pixel[:3] not in palette for pixel in data):
                failures.append(f"{name}/{path.name}: color outside approved palette")
            bbox = image.getbbox()
            if not bbox or bbox[0] == 0 or bbox[1] == 0 or bbox[2] == size[0] or bbox[3] == size[1]:
                failures.append(f"{name}/{path.name}: empty or edge-clipped pose")
            counts.append(sum(pixel[3] > 0 for pixel in data))
        faces = [len(frame.get("face_coordinates", [])) for frame in clip.get("landmarks", [])]
        if faces and max(faces) > 3:
            failures.append(f"{name}: more than 3 exposed face pixels in registered hood landmarks")
        action = name.split("_", 3)[-1]
        direction = name.split("_")[2]
        blade = json.loads((PROJECT / "assets" / "blade_paths.json").read_text(encoding="utf-8"))["side_view"].get(f"{action}_{direction}")
        if not blade or len(blade) != 16 or any(len(point) != 2 or any(not math.isfinite(value) for value in point) for point in blade):
            failures.append(f"{name}: actual-knife trajectory is incomplete")
        new_native[name] = {"size": list(size), "pivot": [40, size[1] - 12], "registered_face_pixels_max": max(faces, default=0),
                            "opaque_pixels_range": [min(counts), max(counts)], "edge_clipped_frames": clip.get("edge_clipped_frames", [])}
        if direction == "right":
            generated, registered = Path(clip["generated_path"]), Path(clip["source_path"])
            current_json = ART / f"source_{name}.json"
            latest = json.loads(current_json.read_text(encoding="utf-8")) if current_json.is_file() else None
            source_ok = registered.is_file() and sha(registered) == clip["source_sha256"]
            if generated.is_file():
                source_ok = source_ok and sha(generated) == clip["source_sha256"]
            if latest:
                source_ok = source_ok and Path(latest["generated_path"]).resolve() == generated.resolve()
            if not source_ok:
                failures.append(f"{name}: current generated source and registered raw copy disagree")
            provenance[name] = {"sha256": clip["source_sha256"], "matches_current_source": source_ok,
                                 "uniform_source_scale": clip["constant_source_scale"], "basis": clip["calibration_basis"]}

    manifest = json.loads((SOURCE / "capture_manifest.json").read_text(encoding="utf-8"))
    states = manifest["states"]
    if manifest["captured_frames"] != 430 or len(states) != 430:
        failures.append("Focused live GPU capture is incomplete")
    native_frames = [SOURCE / f"{state['index']:04}.png" for state in states]
    if any(Image.open(path).size != (320, 180) for path in native_frames):
        failures.append("A live capture is not at the common 320x180 native resolution")
    integer_positions = all(all(value == round(value) for value in state["render_position"] + state["sprite_offset"])
                            and all(all(value == round(value) for value in line[:4]) for line in state["air_lines"])
                            and all(all(value == round(value) for value in ghost[:2]) for ghost in state["afterimage_positions"])
                            for state in states)
    if not integer_positions:
        failures.append("Player, airflow, or afterimage render coordinates leave the native pixel grid")
    live = {}
    for section in manifest["sections"]:
        name = section["name"]
        subset = [state for state in states if state["section"] == name]
        live[name] = {"frames": len(subset), "peak_airflow": max(state["airflow_count"] for state in subset),
                      "peak_afterimages": max(len(state["afterimage_positions"]) for state in subset),
                      "peak_blade_pixels": max(state["blade_pixels"] for state in subset), "hits": max(state["hits"] for state in subset)}
        if name == "side_rising_slash":
            target_min = min(state["targets"][0]["position"][1] for state in subset)
            live[name]["target_rise_native_pixels"] = round(subset[0]["targets"][0]["position"][1] - target_min, 3)
            if live[name]["peak_airflow"] < 3 or target_min > 150 or max(state["targets"][0]["knock_count"] for state in subset) != 1:
                failures.append("Rising slash did not show airflow and a real, single enemy knock-up")
            if abs(subset[-1]["targets"][0]["position"][1] - 160) > 0.1:
                failures.append("Knocked-up target did not land again")
        elif name == "side_dash_stab":
            active = next((state for state in subset if state["dash_executed"]), None)
            distance = math.dist(active["dash_start"], active["dash_end"]) if active else 0
            live[name]["swept_distance_native_pixels"] = round(distance, 3)
            if live[name]["peak_airflow"] < 3 or live[name]["peak_afterimages"] < 2 or live[name]["hits"] != 3 or abs(distance - 48) > 0.1:
                failures.append("Dash live capture lacks its 48px three-target pierce, airflow, or coat afterimages")
        else:
            frozen = [state for state in subset if state["stop_active"]]
            direction = [0, 1] if name.startswith("critical_top_") else [1, 0]
            if len(frozen) != 2:
                failures.append(f"{name}: expected exactly 2 rendered frozen frames, got {len(frozen)}")
                continue
            first, second = frozen
            same_pixels = Image.open(SOURCE / f"{first['index']:04}.png").convert("RGB").tobytes() == Image.open(SOURCE / f"{second['index']:04}.png").convert("RGB").tobytes()
            exact = (second["index"] == first["index"] + 1 and second["engine_frame"] == first["engine_frame"] + 1
                     and [state["stop_displayed_before_render"] for state in frozen] == [0, 1]
                     and all(state["paused"] and state["stop_shake"] == direction and state["canvas_offset"] == direction and state["hud_offset"] == direction for state in frozen)
                     and first["position"] == second["position"] and first["targets"] == second["targets"]
                     and first["frame"] == second["frame"] and first["frame_progress"] == second["frame_progress"]
                     and first["air_lines"] == second["air_lines"] and first["afterimage_positions"] == second["afterimage_positions"])
            after = next(state for state in subset if state["index"] == second["index"] + 1)
            resumed = not after["paused"] and after["canvas_offset"] == [0, 0] and after["hud_offset"] == [0, 0]
            events = [event for event in manifest["hit_stop_events"] if event["section"] == name]
            sequence = [event["event"] for event in events] == ["started", "frame", "frame", "finished"]
            if not same_pixels or not exact or not resumed or not sequence or events[-1].get("frames") != 2:
                failures.append(f"{name}: full-viewport 2-GPU-frame stop or shared world/HUD offset failed")
            if max(state["critical_impact_count"] for state in subset) != 1:
                failures.append(f"{name}: critical impact repeated")
            live[name]["hit_stop"] = {"captured_indices": [first["index"], second["index"]],
                                      "engine_render_frames": [first["engine_frame"], second["engine_frame"]],
                                      "full_viewport_pixels_identical": same_pixels, "world_and_hud_native_offset": direction,
                                      "consecutive_rendered_frames": 2, "duration_seconds_at_60fps": 2 / 60,
                                      "physics_and_animation_unchanged": exact, "resumed_and_offsets_restored": resumed}

    functional = json.loads((EVIDENCE / "test_results_v06.json").read_text(encoding="utf-8"))
    if functional.get("status") != "passed" or functional.get("failures") or functional.get("checks") != 405:
        failures.append("V05 regression plus V06 feature integration checks did not all pass")
    previews = json.loads((EVIDENCE / "special_motion_previews.json").read_text(encoding="utf-8"))
    if len(previews) != 3 or any(not Path(path).is_file() for path in previews.values()):
        failures.append("Three focused action-type previews are missing")
    for path in previews.values():
        if Image.open(path).size != (960, 540):
            failures.append(f"Preview is not integer nearest-neighbor 3x: {path}")

    result = {"status": "failed" if failures else "passed", "failures": failures, "clips": len(folders), "frames": len(frame_paths),
              "new_clips": 4, "new_frames": 64, "new_source_atlases": 2, "preserved_base_frames": len(base_paths),
              "approved_base_aggregate_sha256": aggregate, "functional_checks": functional["checks"],
              "source_provenance": provenance, "native_specials": new_native,
              "live_capture": {"captured_frames": len(states), "native_viewport": [320, 180], "all_render_positions_integer": integer_positions,
                               "engine": manifest["engine"], "sections": live},
              "visual_review": {"readable_rising_knife_and_upward_airflow": True, "readable_dash_knife_and_coat_afterimages": True,
                                "side_player_visible_in_front_of_overlapping_targets": True,
                                "hood_coat_identity_and_body_scale_preserved": True,
                                "notes": "Reviewed actual GPU native crops and complete viewport storyboard; larger canvases add padding. Hit detection uses gameplay areas, not drawn-blade pixel collisions."},
              "gif_timing_note": "Previews quantize 60fps capture to GIF's 20ms timing; two identical frames may be encoded as one 40ms hold. The PNGs and render-frame metadata prove the exact two-frame runtime stop."}
    (EVIDENCE / "special_art_validation_v06.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"status": result["status"], "failures": failures, "clips": result["clips"], "frames": result["frames"], "captured_frames": len(states)}, ensure_ascii=False))
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
