"""Encode the actual hospital GPU frames as GIFs without drawing new artwork."""

import json
from pathlib import Path

from PIL import Image


OUTPUT = Path(__file__).resolve().parents[1] / "evidence" / "integrated_v14"


def compose() -> None:
    capture = json.loads((OUTPUT / "capture_report.json").read_text(encoding="utf-8"))
    results = []
    for clip in ("air_dash_right", "air_dash_left"):
        states = [state for state in capture["frames"] if state["clip"] == clip]
        paths = [OUTPUT / clip / f"{state['index']:04d}.png" for state in states]
        assert paths and all(path.is_file() for path in paths)
        samples = paths[:: max(1, len(paths) // 8)]
        palette_sample = Image.new("RGB", (1280, 720 * len(samples)))
        for index, path in enumerate(samples):
            with Image.open(path) as frame:
                assert frame.size == (1280, 720)
                palette_sample.paste(frame.convert("RGB"), (0, index * 720))
        palette = palette_sample.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
        frames = []
        for path in paths:
            with Image.open(path) as frame:
                frames.append(frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE))
        # GIF time is stored in10ms units; this pattern preserves average60fps.
        durations = [10 if index % 3 == 0 else 20 for index in range(len(frames))]
        destination = OUTPUT / f"hospital_{clip}.gif"
        frames[0].save(destination, save_all=True, append_images=frames[1:],
                       duration=durations, disposal=1, loop=0, optimize=False)
        with Image.open(destination) as animation:
            assert animation.size == (1280, 720)
            assert animation.n_frames > 50
            gif_frames = animation.n_frames
        results.append({"file": destination.name, "size": [1280, 720],
                        "source_gpu_frames": len(frames), "gif_frames": gif_frames,
                        "duration_ms": sum(durations), "bytes": destination.stat().st_size,
                        "scene": "res://scenes/underground_hospital.tscn", "drawn_art_modified": False})
    (OUTPUT / "gif_report.json").write_text(json.dumps({"status": "passed", "gifs": results}, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    compose()
