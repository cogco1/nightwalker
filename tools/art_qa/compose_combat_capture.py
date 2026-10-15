"""Turn a recorder capture (frames + sound timeline) into an MP4 with the combat sounds mixed in.

Usage: python -I tools/art_qa/compose_combat_capture.py [capture_dir] [scale]
Default capture_dir: game/evidence/charged_slash (written by tests/recorders/record_charged_slash.gd).
The recorder cannot grab engine audio, so the track is rebuilt from the logged sound events using the same
WAV files and volumes as game/scripts/core/combat_feedback.gd. Needs imageio-ffmpeg for the ffmpeg binary.
"""
import json
import subprocess
import sys
from pathlib import Path

import imageio_ffmpeg
import numpy as np
from scipy.io import wavfile

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "game" / "assets" / "audio" / "sfx"
VOLUME_DB = {"swing_light": -9.0, "swing_heavy": -5.0, "hit_light": -6.0, "hit_critical": -3.0,
             "hit_heavy": 0.0, "charge": -12.0, "charge_ready": -8.0}


def main() -> int:
    capture = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "game" / "evidence" / "charged_slash"
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    report = json.loads((capture / "capture_report.json").read_text(encoding="utf-8"))
    fps = int(report.get("fps", 30))
    frames = int(report["frames"])
    rate = 44100
    track = np.zeros(int(frames / fps * rate) + rate, dtype=np.float64)
    for event in report["sounds"]:
        sample_rate, samples = wavfile.read(SFX / f"{event['sound']}.wav")
        assert sample_rate == rate
        start = int(event["seconds"] * rate)
        clip = samples.astype(np.float64) / 32767 * 10 ** (VOLUME_DB[event["sound"]] / 20)
        end = min(len(track), start + len(clip))
        track[start:end] += clip[: end - start]
    track = np.tanh(track * 1.2) / np.tanh(1.2)
    audio = capture / "combat_sounds.wav"
    wavfile.write(audio, rate, (track * 32767 * 0.9).astype(np.int16))
    out = capture / f"{capture.name}.mp4"
    width, height = 320 * scale, 180 * scale
    subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), "-y", "-loglevel", "error", "-framerate", str(fps), "-start_number", "0",
                    "-i", str(capture / "frames" / "%04d.png"), "-i", str(audio), "-frames:v", str(frames),
                    "-vf", f"scale={width}:{height}:flags=neighbor,format=yuv420p", "-c:v", "libx264", "-crf", "16",
                    "-preset", "slow", "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", str(out)], check=True)
    print(out, f"{frames} frames, {len(report['sounds'])} sounds, {out.stat().st_size / 1e6:.1f} MB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
