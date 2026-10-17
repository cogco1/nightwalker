"""Synthesise the placeholder story sounds for chapter 1 (knock code, heartbeat, held breath, surveillance lock).

Usage: python -I tools/audio/gen_story_sfx.py
Writes game/assets/audio/story/*.wav (44.1 kHz, mono, 16-bit). Deterministic: fixed seeds. Shares the helpers
of gen_combat_sfx.py. Replace any file with a recorded/licensed sound of the same name; the game only refers
to the names (scripts/ui/story_overlay.gd).
"""
import sys
from pathlib import Path

import numpy as np
from scipy.io import wavfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_combat_sfx import RATE, band, envelope, fit, lowpass, noise, t_axis  # noqa: E402

OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "audio" / "story"


def place(total: float, parts: list[tuple[float, np.ndarray]]) -> np.ndarray:
    signal = np.zeros(int(RATE * total))
    for start, part in parts:
        begin = int(RATE * start)
        end = min(len(signal), begin + len(part))
        signal[begin:end] += part[: end - begin]
    return signal


def thud(seed: int, pitch: float = 95.0) -> np.ndarray:
    s = 0.16
    t = t_axis(s)
    body = np.sin(2 * np.pi * pitch * t) * envelope(s, 0.002, 0.045)
    wood = band(noise(s, seed), 300, 1800) * envelope(s, 0.001, 0.012) * 0.6
    return body + wood


def knock() -> np.ndarray:
    # 咚咚 咚咚: two quick pairs on an old door.
    return fit(place(1.15, [(0.0, thud(11)), (0.17, thud(12, 90)), (0.62, thud(13)), (0.79, thud(14, 88))]), -2.0)


def beat(seed: int, pitch: float) -> np.ndarray:
    s = 0.22
    t = t_axis(s)
    return lowpass(np.sin(2 * np.pi * pitch * t) * envelope(s, 0.006, 0.05) + noise(s, seed) * 0.05, 180)


def heartbeat() -> np.ndarray:
    parts = []
    for index, start in enumerate([0.0, 0.62, 1.16]):
        parts += [(start, beat(20 + index, 52)), (start + 0.17, beat(30 + index, 46) * 0.7)]
    return fit(place(1.6, parts), -1.5)


def breath() -> np.ndarray:
    # A long held breath: slow inhale, a pause, a shaky exhale.
    s = 3.2
    t = t_axis(s)
    air = band(noise(s, 41), 250, 2600)
    inhale = np.clip(t / 0.9, 0, 1) * np.clip((1.3 - t) / 0.3, 0, 1)
    exhale = np.clip((t - 1.9) / 0.15, 0, 1) * np.exp(-np.maximum(t - 2.05, 0) / 0.5) * (0.85 + 0.15 * np.sin(2 * np.pi * 7 * t))
    return fit(air * (0.55 * inhale + exhale), -6.0)


def lock() -> np.ndarray:
    s = 0.7
    t = t_axis(s)
    tone = np.sign(np.sin(2 * np.pi * 880 * t)) * 0.4 + np.sin(2 * np.pi * 1320 * t) * 0.3
    gate = (np.floor(t / 0.12) % 2 == 0).astype(float) * np.clip((s - t) / 0.2, 0, 1)
    return fit(lowpass(tone * gate, 4000), -4.0)


SOUNDS = {"knock": knock, "heartbeat": heartbeat, "breath": breath, "lock": lock}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in SOUNDS.items():
        samples = build()
        wavfile.write(OUT / f"{name}.wav", RATE, (samples * 32767).astype(np.int16))
        print(f"{name}.wav  {len(samples) / RATE:.2f}s")


if __name__ == "__main__":
    main()
