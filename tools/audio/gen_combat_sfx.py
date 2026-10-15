"""Synthesise the placeholder combat sound effects (no recorded audio exists in the project yet).

Usage: python -I tools/audio/gen_combat_sfx.py
Writes game/assets/audio/sfx/*.wav (44.1 kHz, mono, 16-bit). Deterministic: fixed seeds.
Replace any file with a recorded/licensed sound of the same name; game/scripts/core/combat_feedback.gd
only refers to the names.
"""
from pathlib import Path

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
OUT = Path(__file__).resolve().parents[2] / "game" / "assets" / "audio" / "sfx"


def t_axis(seconds: float) -> np.ndarray:
    return np.arange(int(RATE * seconds)) / RATE


def noise(seconds: float, seed: int) -> np.ndarray:
    return np.random.default_rng(seed).uniform(-1.0, 1.0, int(RATE * seconds))


def band(signal: np.ndarray, low: float, high: float) -> np.ndarray:
    return sosfilt(butter(4, [low, high], btype="band", fs=RATE, output="sos"), signal)


def lowpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    return sosfilt(butter(4, cutoff, btype="low", fs=RATE, output="sos"), signal)


def highpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    return sosfilt(butter(4, cutoff, btype="high", fs=RATE, output="sos"), signal)


def envelope(seconds: float, attack: float, decay: float) -> np.ndarray:
    t = t_axis(seconds)
    rise = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    return rise * np.exp(-np.maximum(t - attack, 0.0) / decay)


def sweep(seconds: float, start_hz: float, end_hz: float, curve: float = 3.0) -> np.ndarray:
    t = t_axis(seconds)
    frequency = end_hz + (start_hz - end_hz) * np.exp(-curve * t / seconds)
    return np.sin(2.0 * np.pi * np.cumsum(frequency) / RATE)


def fit(signal: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    fade = min(len(signal), int(RATE * 0.01))
    signal = signal.copy()
    signal[-fade:] *= np.linspace(1.0, 0.0, fade)
    return signal / (np.max(np.abs(signal)) + 1e-9) * 10 ** (peak_db / 20.0)


def swing_light() -> np.ndarray:
    s = 0.13
    air = band(noise(s, 1), 700, 5200) * envelope(s, 0.018, 0.035)
    whistle = sweep(s, 1100, 520) * envelope(s, 0.01, 0.03) * 0.12
    return fit(air + whistle)


def swing_heavy() -> np.ndarray:
    s = 0.28
    air = band(noise(s, 2), 240, 2600) * envelope(s, 0.04, 0.07)
    body = sweep(s, 260, 80) * envelope(s, 0.03, 0.08) * 0.35
    return fit(np.tanh(1.6 * (air + body)))


def hit_light() -> np.ndarray:
    s = 0.16
    click = highpass(noise(s, 3), 3500) * envelope(s, 0.0005, 0.004)
    slice_ = band(noise(s, 4), 900, 6000) * envelope(s, 0.001, 0.022)
    thud = sweep(s, 190, 85, 4.0) * envelope(s, 0.002, 0.045)
    return fit(np.tanh(1.4 * (0.6 * click + 0.7 * slice_ + thud)))


def hit_critical() -> np.ndarray:
    s = 0.3
    t = t_axis(s)
    base = np.zeros_like(t)
    light = hit_light()
    base[: len(light)] += light * 0.9
    ring = (np.sin(2 * np.pi * 2210 * t) + 0.6 * np.sin(2 * np.pi * 3330 * t)) * envelope(s, 0.001, 0.07) * 0.35
    low = sweep(s, 150, 60, 4.0) * envelope(s, 0.002, 0.08) * 0.8
    return fit(np.tanh(1.5 * (base + ring + low)))


def hit_heavy() -> np.ndarray:
    s = 0.55
    t = t_axis(s)
    crack = highpass(noise(s, 5), 2500) * envelope(s, 0.0005, 0.006)
    burst = lowpass(noise(s, 6), 2200) * envelope(s, 0.001, 0.06)
    boom = sweep(s, 120, 36, 5.0) * envelope(s, 0.003, 0.2)
    ring = np.sin(2 * np.pi * 1650 * t) * envelope(s, 0.001, 0.11) * 0.18
    return fit(np.tanh(2.2 * (0.5 * crack + 0.6 * burst + 1.1 * boom + ring)))


def charge() -> np.ndarray:
    s = 0.6
    t = t_axis(s)
    frequency = 150 + 330 * (t / s) ** 1.4
    phase = 2 * np.pi * np.cumsum(frequency) / RATE
    tone = np.sin(phase) + 0.35 * np.sin(2 * phase) + 0.15 * np.sin(3 * phase)
    tremolo = 0.75 + 0.25 * np.sin(2 * np.pi * (14 + 16 * t / s) * t)
    hiss = band(noise(s, 7), 2000, 7000) * 0.08
    level = np.clip(t / 0.08, 0, 1) * (0.35 + 0.65 * t / s)
    return fit((tone * tremolo + hiss) * level, -3.0)


def charge_ready() -> np.ndarray:
    s = 0.42
    t = t_axis(s)
    ping = (np.sin(2 * np.pi * 1568 * t) + 0.7 * np.sin(2 * np.pi * 2349 * t) + 0.3 * np.sin(2 * np.pi * 3136 * t))
    shimmer = 1.0 + 0.15 * np.sin(2 * np.pi * 9 * t)
    return fit(ping * shimmer * envelope(s, 0.002, 0.11))


SOUNDS = {
    "swing_light": swing_light, "swing_heavy": swing_heavy, "hit_light": hit_light,
    "hit_critical": hit_critical, "hit_heavy": hit_heavy, "charge": charge, "charge_ready": charge_ready,
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, build in SOUNDS.items():
        samples = build()
        wavfile.write(OUT / f"{name}.wav", RATE, (samples * 32767).astype(np.int16))
        print(f"{name}.wav  {len(samples) / RATE:.2f}s")


if __name__ == "__main__":
    main()
