#!/usr/bin/env python3
"""Deterministic synthesiser for every sound the game plays.

No samples, no downloads: music and effects are rendered with numpy from
additive and subtractive building blocks (plucked strings as damped harmonic
stacks, a sine/triangle flute, filtered-noise hand drums, a Schroeder
feedback-delay reverb) and written as 16-bit 44.1 kHz WAV. Music is then
encoded to Ogg Vorbis with ffmpeg; effects stay WAV.

    python3 tools/audio/synth.py                  # writes game/assets/audio/**
    python3 tools/audio/synth.py --scratch DIR    # also keeps WAV masters and
                                                  # 10 s previews of each theme
    python3 tools/audio/synth.py --only coin town_theme

The output is identical on every run (fixed seed). The script prints a quality
table (duration, peak, RMS, loop seam, NaN check, Ogg sample count) and exits
non-zero when a check fails. tools/audio/README.md documents the musical
design and the catalogue of effects.
"""
from __future__ import annotations

import argparse
import math
import subprocess
import sys
import tempfile
import wave
import zlib
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from scipy import signal

SR = 44100
SEED = 20261016
TAIL_SECONDS = 4.0  # room after the loop for ringing notes (folded back to the start)
PREROLL_SECONDS = 6.0  # reverb warm-up before the loop is captured
SEAM_SAMPLES = 64  # samples past the loop end compared with the loop start
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = REPO_ROOT / "game" / "assets" / "audio"
FOLDER_BUDGET_BYTES = 4 * 1024 * 1024
MUSIC_RMS_DB = -17.5  # both themes land here so a map change does not jump in level
MUSIC_PEAK_CAP_DB = -1.0

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


# --------------------------------------------------------------------------- basics
def note_midi(name: str) -> int:
    """'D4' -> 62, 'F#3' -> 54, 'Bb2' -> 46."""
    letter, rest = name[0].upper(), name[1:]
    accidental = 0
    while rest and rest[0] in "#b":
        accidental += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NOTE_INDEX[letter] + accidental


def note_hz(name: str) -> float:
    return 440.0 * 2.0 ** ((note_midi(name) - 69) / 12.0)


def db_to_lin(level_db: float) -> float:
    return 10.0 ** (level_db / 20.0)


def lin_to_db(x: float) -> float:
    return 20.0 * math.log10(max(float(x), 1e-12))


def secs(seconds: float) -> int:
    return int(round(seconds * SR))


def time_axis(n: int) -> np.ndarray:
    return np.arange(n) / SR


def attack(t: np.ndarray, seconds: float) -> np.ndarray:
    """Half-cosine ramp from 0 to 1 over `seconds`, then 1."""
    if seconds <= 0:
        return np.ones_like(t)
    x = np.clip(t / seconds, 0.0, 1.0)
    return 0.5 - 0.5 * np.cos(np.pi * x)


def fade_out(y: np.ndarray, seconds: float) -> np.ndarray:
    n = min(len(y), secs(seconds))
    if n <= 0:
        return y
    ramp = 0.5 + 0.5 * np.cos(np.pi * np.arange(n) / n)
    out = y.copy()
    out[-n:] *= ramp
    return out


def fade_in(y: np.ndarray, seconds: float) -> np.ndarray:
    n = min(len(y), secs(seconds))
    if n <= 0:
        return y
    out = y.copy()
    out[:n] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(n) / n)
    return out


def bandpass(x: np.ndarray, lo: float, hi: float, order: int = 2) -> np.ndarray:
    lo = max(lo, 10.0)
    hi = min(hi, 0.47 * SR)
    sos = signal.butter(order, [lo, hi], btype="bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lowpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, min(fc, 0.47 * SR), btype="lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x: np.ndarray, fc: float, order: int = 2) -> np.ndarray:
    sos = signal.butter(order, max(fc, 10.0), btype="highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def peak_boost(x: np.ndarray, fc: float, q: float, gain: float) -> np.ndarray:
    """Adds `gain` times a resonant band around `fc` (a wooden body, a bell mode)."""
    b, a = signal.iirpeak(fc, q, fs=SR)
    return x + gain * signal.lfilter(b, a, x)


def damped_sine(t: np.ndarray, hz: float, tau: float, amp: float = 1.0, t0: float = 0.0) -> np.ndarray:
    """A single decaying partial starting at `t0` (zero before it)."""
    tt = t - t0
    live = tt >= 0
    tt = np.where(live, tt, 0.0)
    return amp * np.exp(-tt / tau) * np.sin(2 * np.pi * hz * tt) * live


def swept_tone(hz: np.ndarray, harmonics: list[float]) -> np.ndarray:
    """Harmonic stack following an instantaneous-frequency curve (per sample)."""
    phase = 2 * np.pi * np.cumsum(hz) / SR
    out = np.zeros_like(phase)
    for k, amp in enumerate(harmonics, start=1):
        if amp:
            out += amp * np.sin(k * phase)
    return out


def soft_clip(y: np.ndarray, drive: float = 1.0) -> np.ndarray:
    return np.tanh(drive * y) / math.tanh(drive)


def normalize(y: np.ndarray, peak_db: float) -> np.ndarray:
    peak = float(np.max(np.abs(y)))
    if peak <= 0:
        return y
    return y * (db_to_lin(peak_db) / peak)


def rms_db(y: np.ndarray) -> float:
    return lin_to_db(math.sqrt(float(np.mean(np.square(y)))) if len(y) else 0.0)


def place(buf: np.ndarray, start_seconds: float, y: np.ndarray, gain: float = 1.0) -> None:
    """Adds `y` into `buf` at `start_seconds`, clipping whatever runs past the end."""
    start = max(0, secs(start_seconds))
    end = min(len(buf), start + len(y))
    if end > start:
        buf[start:end] += gain * y[: end - start]


# --------------------------------------------------------------------------- instruments
def pluck(
    rng: np.random.Generator,
    hz: float,
    dur: float,
    vel: float = 0.8,
    *,
    bright: float = 1.0,
    ring: float = 1.0,
    pick: float = 0.14,
    body: bool = True,
    tone_hz: float = 7500.0,
) -> np.ndarray:
    """Plucked gut string (lute, psaltery, bass): a damped harmonic stack.

    Each partial k has amplitude |sin(pi k pick)| / k^alpha (the comb of the pluck
    position), a slight inharmonicity and a decay that shortens with k, so the
    note starts bright and mellows as it rings. A pick-noise burst, a wooden body
    resonance and a gentle damping after the written duration finish it.
    """
    tau1 = ring * float(np.clip(1.1 * (220.0 / hz) ** 0.45, 0.3, 2.8))
    length = min(dur + 0.35, TAIL_SECONDS - 0.1)
    n = secs(length)
    t = time_axis(n)
    kmax = int(max(1, min(28, 0.45 * SR / hz)))
    k = np.arange(1, kmax + 1, dtype=float)[:, None]
    partial_hz = hz * k * np.sqrt(1.0 + 1.2e-4 * k * k)
    alpha = 1.3 - 0.5 * bright * vel
    amps = np.abs(np.sin(np.pi * k * pick)) / k**alpha
    taus = tau1 / (1.0 + 0.3 * (k - 1) ** 1.15)
    y = (amps * np.exp(-t / taus) * np.sin(2 * np.pi * partial_hz * t)).sum(axis=0)
    burst_n = min(n, secs(0.008))
    burst = rng.standard_normal(burst_n) * np.exp(-np.arange(burst_n) / (0.0012 * SR))
    y[:burst_n] += 0.12 * float(amps.sum()) * bandpass(burst, 1500, 8000)
    y *= attack(t, 0.0015)
    y = fade_out(y, 0.25)
    if body:
        y = peak_boost(y, 215.0, 1.2, 0.18)
        y = peak_boost(y, 470.0, 1.6, 0.10)
    y = lowpass(y, tone_hz)
    return normalize(y, 0.0) * vel


def lute(rng: np.random.Generator, hz: float, dur: float, vel: float) -> np.ndarray:
    return pluck(rng, hz, dur, vel)


def bass_lute(rng: np.random.Generator, hz: float, dur: float, vel: float) -> np.ndarray:
    return pluck(rng, hz, dur, vel, bright=0.6, ring=1.3, pick=0.22, tone_hz=3500.0)


def harp(rng: np.random.Generator, hz: float, dur: float, vel: float) -> np.ndarray:
    return pluck(rng, hz, dur, vel, bright=1.2, ring=1.2, pick=0.3, body=False)


def flute(
    rng: np.random.Generator,
    hz: float,
    dur: float,
    vel: float = 0.7,
    *,
    breath: float = 0.035,
    vib_rate: float = 5.0,
    vib_depth: float = 0.004,
) -> np.ndarray:
    """Soft wooden flute: sine with a little 2nd/3rd harmonic (more when blown
    harder), a short upward onset glide, late vibrato and a touch of breath noise."""
    release = 0.10
    n = secs(dur + release)
    t = time_axis(n)
    env = attack(t, 0.045)
    r0 = secs(dur)
    if n > r0:
        env[r0:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(n - r0) / (n - r0))
    env *= 0.9 + 0.1 * (1.0 - np.exp(-t / 0.3))
    glide = -0.012 * np.exp(-t / 0.025)
    vib = vib_depth * np.clip((t - 0.12) / 0.3, 0.0, 1.0)
    vib = vib * np.sin(2 * np.pi * vib_rate * t + rng.uniform(0, 2 * np.pi))
    tone = swept_tone(hz * (1.0 + glide + vib), [1.0, 0.2 + 0.25 * vel, 0.05 + 0.07 * vel, 0.03])
    hiss = bandpass(rng.standard_normal(n), max(1200.0, hz * 1.5), 6000.0)
    hiss *= 1.0 + 1.5 * np.exp(-t / 0.08)
    y = lowpass((tone + breath * hiss) * env, 6500.0)
    return normalize(y, 0.0) * vel


def drum_dum(rng: np.random.Generator, vel: float = 0.8) -> np.ndarray:
    """Open hand-drum stroke: a pitch-dropping sine plus a low-passed skin slap."""
    n = secs(0.32)
    t = time_axis(n)
    body = swept_tone(62.0 + 95.0 * np.exp(-t / 0.045), [1.0]) * np.exp(-t / 0.11)
    skin = lowpass(rng.standard_normal(n), 900.0) * np.exp(-t / 0.018) * 0.7
    y = fade_out((body + skin) * attack(t, 0.001), 0.04)
    return normalize(y, 0.0) * vel


def drum_tek(rng: np.random.Generator, vel: float = 0.6) -> np.ndarray:
    """Rim tap: a short band-passed click with two faint ringing partials."""
    n = secs(0.14)
    t = time_axis(n)
    click = bandpass(rng.standard_normal(n), 1800.0, 6500.0) * np.exp(-t / 0.012)
    ring = damped_sine(t, 720.0, 0.03, 0.4) + damped_sine(t, 1430.0, 0.02, 0.2)
    y = fade_out((click + ring) * attack(t, 0.0005), 0.02)
    return normalize(y, 0.0) * vel


def _loop_coherent(hz: float, loop_seconds: float) -> float:
    """Nearest frequency with an integer number of cycles per loop."""
    return max(1.0, round(hz * loop_seconds)) / loop_seconds


def drone(rng: np.random.Generator, notes: list[str], loop_n: int, *, partials: int = 7) -> np.ndarray:
    """Sustained bourdon for the whole loop: detuned pairs of harmonic stacks with
    slow amplitude shimmer. Every frequency and modulation rate is quantised to a
    whole number of cycles per loop, so the drone is exactly periodic and the
    loop point needs no fade."""
    loop_seconds = loop_n / SR
    t = time_axis(loop_n)
    y = np.zeros(loop_n)
    for name in notes:
        for k in range(1, partials + 1):
            amp = 1.0 / k**1.7
            for detune in (-0.0008, 0.0008):
                hz = _loop_coherent(note_hz(name) * k * (1.0 + detune), loop_seconds)
                am_hz = _loop_coherent(rng.uniform(0.07, 0.3), loop_seconds)
                shimmer = 1.0 + 0.12 * np.sin(2 * np.pi * am_hz * t + rng.uniform(0, 2 * np.pi))
                y += amp * shimmer * np.sin(2 * np.pi * hz * t + rng.uniform(0, 2 * np.pi))
    return normalize(y, 0.0)


# --------------------------------------------------------------------------- reverb
COMB_DELAYS = (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
ALLPASS_DELAYS = (556, 441, 341, 225)


def _blocks(x: np.ndarray, delay: int) -> np.ndarray:
    count = -(-len(x) // delay)
    padded = np.zeros(count * delay)
    padded[: len(x)] = x
    return padded


def _comb(x: np.ndarray, delay: int, gain: float, damp: float) -> np.ndarray:
    """Feedback comb with a one-pole low-pass in the loop, processed one delay
    length at a time so numpy does the work instead of a per-sample loop."""
    xp = _blocks(x, delay)
    y = np.zeros_like(xp)
    prev = np.zeros(delay)
    state = np.zeros(1)
    b, a = np.array([1.0 - damp]), np.array([1.0, -damp])
    for i in range(len(xp) // delay):
        block = slice(i * delay, (i + 1) * delay)
        fb, state = signal.lfilter(b, a, prev, zi=state)
        y[block] = xp[block] + gain * fb
        prev = y[block]
    return y[: len(x)]


def _allpass(x: np.ndarray, delay: int, gain: float = 0.5) -> np.ndarray:
    xp = _blocks(x, delay)
    y = np.zeros_like(xp)
    x_prev = np.zeros(delay)
    y_prev = np.zeros(delay)
    for i in range(len(xp) // delay):
        block = slice(i * delay, (i + 1) * delay)
        y[block] = -gain * xp[block] + x_prev + gain * y_prev
        x_prev, y_prev = xp[block], y[block]
    return y[: len(x)]


def reverb(
    x: np.ndarray, *, rt60: float = 1.8, wet: float = 0.3, damp: float = 0.3, predelay: float = 0.02
) -> np.ndarray:
    """Schroeder/Moorer feedback-delay reverb. `wet` is the RMS of the reverb
    relative to the dry signal (0.3 = reverb 10 dB under the music)."""
    pre = secs(predelay)
    fed = np.concatenate([np.zeros(pre), x[: len(x) - pre]])
    acc = np.zeros_like(x)
    for delay in COMB_DELAYS:
        acc += _comb(fed, delay, 10.0 ** (-3.0 * delay / (rt60 * SR)), damp)
    for delay in ALLPASS_DELAYS:
        acc = _allpass(acc, delay)
    acc = lowpass(acc, 5000.0)
    dry_rms = math.sqrt(float(np.mean(np.square(x)))) or 1.0
    wet_rms = math.sqrt(float(np.mean(np.square(acc)))) or 1.0
    return x + acc * (wet * dry_rms / wet_rms)


# --------------------------------------------------------------------------- sequencing
@dataclass
class Score:
    """Mixes rendered notes into named tracks on a sample grid.

    `unit` is the written duration unit in samples (a quarter note for the town
    theme, an eighth for the outskirts theme); the loop is `total_units` long.
    Notes may ring past the loop end into a tail that `mix()` folds back onto the
    start, which is what makes the end of the loop lead seamlessly into its start.
    """

    unit: int
    total_units: int
    rng: np.random.Generator
    tracks: dict[str, np.ndarray] = field(default_factory=dict)

    @property
    def loop_n(self) -> int:
        return self.unit * self.total_units

    def seconds(self, units: float) -> float:
        return units * self.unit / SR

    def buffer(self, track: str) -> np.ndarray:
        if track not in self.tracks:
            self.tracks[track] = np.zeros(self.loop_n + secs(TAIL_SECONDS))
        return self.tracks[track]

    def place(self, track: str, units: float, y: np.ndarray, gain: float = 1.0, jitter: float = 0.006) -> None:
        """Adds a rendered note at `units`, with a little human timing jitter."""
        start = int(round(units * self.unit + self.rng.normal(0.0, jitter) * SR))
        start = max(0, start)
        buf = self.buffer(track)
        end = min(len(buf), start + len(y))
        buf[start:end] += gain * y[: end - start]

    def mix(self, gains: dict[str, float]) -> np.ndarray:
        out = np.zeros(self.loop_n)
        tail = secs(TAIL_SECONDS)
        for track, gain in gains.items():
            buf = self.buffer(track)
            out += gain * buf[: self.loop_n]
            out[:tail] += gain * buf[self.loop_n : self.loop_n + tail]
        return out


def parse_melody(text: str) -> tuple[list[tuple[float, float, str | None, str]], float]:
    """'D4:1 E4:.5! r:2 | ...' -> [(start, dur, note or None, mark)], total.

    `|` is decoration (bar lines), `r` is a rest, a trailing `!` accents the note
    and `~` softens it.
    """
    events = []
    pos = 0.0
    for token in text.replace("|", " ").split():
        mark = ""
        if token[-1] in "!~":
            mark, token = token[-1], token[:-1]
        name, dur = token.split(":")
        events.append((pos, float(dur), None if name == "r" else name, mark))
        pos += float(dur)
    return events, pos


def play_melody(
    score: Score,
    track: str,
    text: str,
    start_units: float,
    instrument,
    *,
    vel: float = 0.7,
    units_per_bar: int = 4,
    contour: float = 0.08,
    accent: float = 0.12,
    gain: float = 1.0,
    expected_units: float | None = None,
) -> float:
    """Renders a melody string onto a track. Downbeats, `!` marks and higher
    notes play a little louder; every note gets a small velocity wobble."""
    events, total = parse_melody(text)
    if expected_units is not None and abs(total - expected_units) > 1e-9:
        raise ValueError(f"melody is {total} units long, expected {expected_units}: {text[:40]}...")
    for pos, dur, note, mark in events:
        if note is None:
            continue
        level = vel
        if pos % units_per_bar == 0:
            level += 0.6 * accent
        level += {"!": accent, "~": -accent, "": 0.0}[mark]
        level += contour * (note_midi(note) - 64) / 12.0
        level *= 1.0 + score.rng.normal(0.0, 0.04)
        level = float(np.clip(level, 0.15, 1.0))
        y = instrument(score.rng, note_hz(note), score.seconds(dur), level)
        score.place(track, start_units + pos, y, gain)
    return total


def scale_step(note: str, mode: list[int], steps: int) -> str:
    """Moves `note` by `steps` scale degrees inside `mode` (pitch classes)."""
    midi = note_midi(note)
    index = mode.index(midi % 12)
    target_pc = mode[(index + steps) % len(mode)]
    octaves, _ = divmod(index + steps, len(mode))
    midi = midi - (midi % 12) + target_pc + 12 * octaves
    names = {v: k for k, v in NOTE_INDEX.items()}
    pc = midi % 12
    return (names[pc] if pc in names else names[pc - 1] + "#") + str(midi // 12 - 1)


def play_drums(score: Score, pattern: list[tuple[float, str, float]], bar_units: int, bars: range) -> None:
    for bar in bars:
        for pos, kind, vel in pattern:
            hit = drum_dum(score.rng, vel) if kind == "dum" else drum_tek(score.rng, vel)
            score.place("drum", bar * bar_units + pos, hit, jitter=0.003)


def finish_music(dry: np.ndarray, *, rt60: float, wet: float) -> tuple[np.ndarray, float]:
    """Runs the periodic dry loop through the reverb in steady state and
    sets its level (MUSIC_RMS_DB, peaks capped at MUSIC_PEAK_CAP_DB). Returns
    the loop and the seam error: how far the first
    SEAM_SAMPLES of the loop are from what the reverb would have produced had
    the music simply continued (should be around 1e-9)."""
    pre = secs(PREROLL_SECONDS)
    loop_n = len(dry)
    x = np.concatenate([dry[-pre:], dry, dry[:SEAM_SAMPLES]])
    y = reverb(x, rt60=rt60, wet=wet)
    out = y[pre : pre + loop_n]
    beyond = y[pre + loop_n : pre + loop_n + SEAM_SAMPLES]
    gain = db_to_lin(MUSIC_RMS_DB) / math.sqrt(float(np.mean(np.square(out))))
    gain = min(gain, db_to_lin(MUSIC_PEAK_CAP_DB) / float(np.max(np.abs(out))))
    out = out * gain
    seam = float(np.max(np.abs(beyond * gain - out[:SEAM_SAMPLES])))
    return out, seam


# --------------------------------------------------------------------------- town theme
# D Dorian, 4/4, ~92 bpm, 24 bars: A (8) B (8) A' (8). Durations in quarter notes.
D_DORIAN = [2, 4, 5, 7, 9, 11, 0]

TOWN_A = """
D4:1 E4:1 F4:1.5 E4:.5 | D4:2 r:2 | A4:1 G4:1 F4:1 G4:1 | A4:3 r:1 |
F4:.5 G4:.5 A4:1 B4:1! A4:1 | G4:1 F4:1 E4:2 | F4:1 E4:1 D4:1 C4:1 | D4:3 r:1
"""
TOWN_B = """
A4:1 C5:1 D5:1.5 C5:.5 | A4:2 G4:1 A4:1 | B4:1 A4:1 G4:1 F4:1 | E4:2 r:2 |
C5:1 D5:1 E5:1.5! D5:.5 | C5:1 A4:1 B4:1 C5:1 | A4:1 G4:1 F4:1 G4:1 | E4:3 r:1
"""
TOWN_A2 = """
D4:1 E4:1 F4:1 G4:.5 E4:.5 | D4:2 r:1 A3:1~ | A4:1 G4:.5 F4:.5 E4:1 G4:1 | A4:2.5 r:.5 G4:.5 A4:.5 |
F4:.5 G4:.5 A4:1 B4:.5! C5:.5 A4:1 | G4:1 F4:.5 E4:.5 D4:.5 E4:1.5 | F4:1 E4:1 D4:1 C4:1 | D4:4!
"""
TOWN_BASS_A = """
D3:2 A3:2 | D3:2 A3:2 | F3:2 C3:2 | A3:4 | D3:2 G3:2 | C3:4 | D3:2 C3:2 | D3:4
"""
TOWN_BASS_B = """
D3:2 A3:2 | F3:2 C3:2 | G3:2 D3:2 | E3:2 A3:2 | A3:2 E3:2 | F3:2 A3:2 | D3:2 C3:2 | E3:2 A3:2
"""
TOWN_BASS_A2 = """
D3:2 A3:2 | D3:1 r:1 A3:1 r:1 | F3:2 C3:2 | A3:2 A3:2 | D3:2 G3:2 | C3:2 E3:2 | D3:2 C3:2 | D3:4
"""
TOWN_DRUM_A = [(0, "dum", 0.8), (2, "tek", 0.45)]
TOWN_DRUM_B = [(0, "dum", 0.9), (1.5, "tek", 0.5), (2, "dum", 0.55), (3, "tek", 0.5)]
TOWN_DRUM_A2 = [(0, "dum", 0.85), (2, "tek", 0.45), (3.5, "tek", 0.35)]


def town_theme() -> tuple[np.ndarray, float]:
    rng = np.random.default_rng([SEED, 1])
    quarter = 28761  # samples: 91.9996 bpm, so the loop is a whole number of samples
    upb = 4
    phrase = 8 * upb
    score = Score(quarter, 3 * phrase, rng)

    for index, (text, vel) in enumerate([(TOWN_A, 0.70), (TOWN_B, 0.82), (TOWN_A2, 0.76)]):
        play_melody(score, "lute", text, index * phrase, lute, vel=vel, expected_units=phrase)
    # B: a soft flute shadows the lute, a colour change rather than a new voice.
    play_melody(score, "flute", TOWN_B, phrase + 0.02, flute, vel=0.45, contour=0.0, expected_units=phrase)
    # A': a second lute answers long notes a third below, slightly late, like an arpeggio.
    for pos, dur, note, _ in parse_melody(TOWN_A2)[0]:
        if note is not None and dur >= 1.5 and note_midi(note) >= note_midi("D4"):
            final = pos + dur >= phrase
            low = scale_step(note, D_DORIAN, -4 if final else -2)  # open fifth on the final
            y = lute(rng, note_hz(low), score.seconds(dur), 0.42)
            score.place("counter", 2 * phrase + pos + 0.08, y)
    for index, text in enumerate([TOWN_BASS_A, TOWN_BASS_B, TOWN_BASS_A2]):
        play_melody(
            score, "bass", text, index * phrase, bass_lute, vel=0.72, contour=0.0, accent=0.05, expected_units=phrase
        )
    play_drums(score, TOWN_DRUM_A, upb, range(0, 8))
    play_drums(score, TOWN_DRUM_B, upb, range(8, 16))
    play_drums(score, TOWN_DRUM_A2, upb, range(16, 23))
    play_drums(score, [(0, "dum", 0.9), (3.5, "tek", 0.4)], upb, range(23, 24))  # tap leads into the repeat

    dry = score.mix({"lute": 1.0, "flute": 0.5, "counter": 0.6, "bass": 0.62, "drum": 0.45})
    dry += 0.17 * drone(rng, ["D3", "A3"], score.loop_n)
    return finish_music(dry, rt60=1.9, wet=0.33)


# --------------------------------------------------------------------------- outskirts theme
# G Mixolydian, 6/8, ~96 bpm (dotted quarter), 48 bars: A A B B' A' A''. Durations in eighths.
OUT_A = """
G4:2 A4:1 B4:2 C5:1 | D5:3 B4:3 | C5:2 B4:1 A4:2 G4:1 | A4:4 r:2 |
G4:2 A4:1 B4:2 D5:1 | E5:3! D5:3 | C5:2 D5:1 B4:2 A4:1 | G4:4 r:2
"""
OUT_B = """
D5:2 E5:1 F5:3! | E5:2 D5:1 C5:3 | D5:2 E5:1 D5:2 C5:1 | B4:4 r:2 |
C5:2 D5:1 E5:3 | F5:2 E5:1 D5:3 | C5:2 B4:1 A4:2 B4:1 | D5:4 r:2
"""
OUT_B2 = """
D5:2 E5:1 F5:3! | E5:2 D5:1 C5:3 | D5:1 E5:1 F5:1 G5:3! | G5:2 F5:1 E5:3 |
C5:2 D5:1 E5:3 | F5:2 E5:1 D5:3 | C5:2 B4:1 A4:2 B4:1 | D5:4 r:2
"""
OUT_A2 = """
G4:1 A4:1 B4:1 C5:1 B4:1 C5:1 | D5:3 B4:2 A4:1 | C5:1 D5:1 B4:1 A4:2 G4:1 | A4:3 B4:1 A4:2 |
G4:2 A4:1 B4:1 C5:1 D5:1 | E5:2! F5:1 D5:3 | C5:2 D5:1 B4:2 A4:1 | G4:4 r:2
"""
OUT_A3 = """
G4:2 A4:1 B4:2 C5:1 | D5:3 B4:3 | C5:2 B4:1 A4:2 G4:1 | A4:4 r:2 |
G4:2 A4:1 B4:2 D5:1 | E5:3 D5:3 | C5:2 D5:1 B4:2 A4:1~ | G4:5 r:1
"""
OUT_CHORDS = {"G": ("G3", "D4", "G4"), "C": ("C3", "G3", "C4"), "D": ("D3", "A3", "D4"), "F": ("F3", "C4", "F4")}
OUT_A_CHORDS = "G G C D G C D G".split()
OUT_B_CHORDS = "D C D G C F C D".split()
# (eighth, chord tone index, velocity, written length in eighths)
OUT_ARPEGGIO = [(0, 0, 0.75, 2), (2, 1, 0.5, 1), (3, 2, 0.6, 2), (5, 1, 0.45, 1)]
OUT_BASS_ONLY = [(0, 0, 0.7, 6)]
OUT_DRUM_A = [(0, "dum", 0.8), (3, "tek", 0.5)]
OUT_DRUM_B = [(0, "dum", 0.9), (3, "tek", 0.55), (5, "tek", 0.3)]


def play_arpeggio(score: Score, chords: list[str], first_bar: int, pattern, vel_scale: float = 1.0) -> None:
    for bar_offset, chord in enumerate(chords):
        bar = first_bar + bar_offset
        for pos, tone, vel, length in pattern:
            note = OUT_CHORDS[chord][tone]
            level = float(np.clip(vel * vel_scale * (1.0 + score.rng.normal(0.0, 0.04)), 0.15, 1.0))
            y = lute(score.rng, note_hz(note), score.seconds(length), level)
            score.place("lute", bar * 6 + pos, y)


def outskirts_theme() -> tuple[np.ndarray, float]:
    rng = np.random.default_rng([SEED, 2])
    eighth = 9188  # samples: 95.97 bpm for the dotted quarter, 60.003 s loop
    upb = 6
    phrase = 8 * upb
    score = Score(eighth, 6 * phrase, rng)

    phrases = [(OUT_A, 0.62), (OUT_A, 0.70), (OUT_B, 0.80), (OUT_B2, 0.86), (OUT_A2, 0.76), (OUT_A3, 0.64)]
    for index, (text, vel) in enumerate(phrases):
        play_melody(score, "flute", text, index * phrase, flute, vel=vel, units_per_bar=upb, expected_units=phrase)
    # Phrase 4: the lute shadows the flute at the peak of the piece (heterophony).
    play_melody(
        score, "echo", OUT_B2, 3 * phrase + 0.1, lute, vel=0.42, units_per_bar=upb, contour=0.0, expected_units=phrase
    )
    play_arpeggio(score, OUT_A_CHORDS, 0, OUT_BASS_ONLY)
    play_arpeggio(score, OUT_A_CHORDS, 8, OUT_ARPEGGIO)
    play_arpeggio(score, OUT_B_CHORDS, 16, OUT_ARPEGGIO)
    play_arpeggio(score, OUT_B_CHORDS, 24, OUT_ARPEGGIO, 1.08)
    play_arpeggio(score, OUT_A_CHORDS, 32, OUT_ARPEGGIO)
    play_arpeggio(score, OUT_A_CHORDS, 40, OUT_ARPEGGIO, 0.8)
    play_drums(score, OUT_DRUM_A, upb, range(8, 16))
    play_drums(score, OUT_DRUM_B, upb, range(16, 32))
    play_drums(score, OUT_DRUM_A, upb, range(32, 40))

    dry = score.mix({"flute": 0.9, "lute": 0.58, "echo": 0.5, "drum": 0.36})
    dry += 0.15 * drone(rng, ["G3", "D4"], score.loop_n)
    return finish_music(dry, rt60=2.1, wet=0.36)


# --------------------------------------------------------------------------- sound effects
def sfx_jump(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.21)
    t = time_axis(n)
    hz = 300.0 * 2.0 ** (np.minimum(t, 0.16) / 0.16 * 1.4)
    tone = swept_tone(hz, [1.0, 0.35, 0.12]) * np.exp(-t / 0.08) * attack(t, 0.004)
    puff = bandpass(rng.standard_normal(n), 900.0, 3500.0) * np.exp(-t / 0.025) * 0.35
    return tone + puff


def sfx_land(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.2)
    t = time_axis(n)
    thud = swept_tone(45.0 + 70.0 * np.exp(-t / 0.03), [1.0, 0.3]) * np.exp(-t / 0.06)
    noise = rng.standard_normal(n)
    dust = lowpass(noise, 700.0) * np.exp(-t / 0.03) * 0.9
    dust += bandpass(noise, 1500.0, 5000.0) * np.exp(-t / 0.05) * 0.15
    return thud * 0.9 + dust


def sfx_footstep(rng: np.random.Generator, variant: int) -> np.ndarray:
    n = secs(0.1)
    t = time_axis(n)
    lo, hi, scuff_hz = (650.0, 2600.0, 150.0) if variant == 1 else (850.0, 3200.0, 175.0)
    heel = bandpass(rng.standard_normal(n), lo, hi) * np.exp(-t / 0.016) * attack(t, 0.003)
    toe = bandpass(rng.standard_normal(n), lo * 1.3, hi * 1.2) * np.exp(-np.maximum(t - 0.03, 0) / 0.012)
    toe *= 0.6 * (t >= 0.03) * attack(t - 0.03, 0.002)
    scuff = damped_sine(t, scuff_hz, 0.02, 0.35)
    return heel + toe + scuff


def sfx_sword_swing(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.3)
    t = time_axis(n)
    noise = rng.standard_normal(n)

    def bump(centre: float, width: float) -> np.ndarray:
        return np.exp(-(((t - centre) / width) ** 2))

    low = bandpass(noise, 250.0, 900.0) * bump(0.08, 0.05)
    mid = bandpass(noise, 900.0, 2600.0) * bump(0.12, 0.045)
    high = bandpass(noise, 2600.0, 7000.0) * bump(0.16, 0.04) * 0.8
    ring = damped_sine(t, 3100.0, 0.07, 0.25, t0=0.14)
    return (low + mid + high) * attack(t, 0.005) + ring


def sfx_hit_enemy(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.24)
    t = time_axis(n)
    thud = swept_tone(70.0 + 130.0 * np.exp(-t / 0.03), [1.0]) * np.exp(-t / 0.07)
    noise = rng.standard_normal(n)
    crunch = bandpass(noise, 350.0, 1800.0) * np.exp(-t / 0.045)
    snap = bandpass(noise, 1800.0, 6000.0) * np.exp(-t / 0.012) * 0.8
    return soft_clip(1.6 * (thud * 0.9 + crunch * 0.8 + snap), 1.0)


def sfx_hit_shell(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.15)
    t = time_axis(n)
    click = highpass(rng.standard_normal(n), 1500.0) * np.exp(-t / 0.0015) * 1.2
    rings = damped_sine(t, 2350.0, 0.02) + damped_sine(t, 3620.0, 0.013, 0.7)
    rings += damped_sine(t, 5180.0, 0.008, 0.45) + damped_sine(t, 640.0, 0.035, 0.35)
    rings += damped_sine(t, 1180.0, 0.025, 0.3)
    return click + rings


def sfx_hurt_player(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.38)
    t = time_axis(n)
    tone = swept_tone(330.0 + 110.0 * np.exp(-t / 0.12), [1.0, 0.0, 0.45, 0.0, 0.2])
    tone = soft_clip(1.4 * tone * np.exp(-t / 0.14) * attack(t, 0.003), 1.0)
    thud = swept_tone(60.0 + 80.0 * np.exp(-t / 0.03), [1.0]) * np.exp(-t / 0.05) * 0.6
    return tone + thud + lowpass(rng.standard_normal(n), 800.0) * np.exp(-t / 0.02) * 0.3


def sfx_enemy_die(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.65)
    t = time_axis(n)
    hz = 560.0 * 2.0 ** (-t / 0.65 * 2.3) * (1.0 + 0.05 * np.sin(2 * np.pi * 8.0 * t))
    tone = swept_tone(hz, [1.0, 0.5, 0.25, 0.12]) * np.exp(-t / 0.35) * attack(t, 0.005)
    poof = lowpass(rng.standard_normal(n), 1400.0) * np.exp(-np.maximum(t - 0.28, 0) / 0.09)
    poof *= 0.7 * (t >= 0.28) * attack(t - 0.28, 0.01)
    return tone * 0.9 + poof


def bell(t: np.ndarray, hz: float, t0: float, amp: float, stretch: float = 1.0) -> np.ndarray:
    ratios, amps, taus = (1.0, 2.0, 3.0, 4.2), (1.0, 0.55, 0.3, 0.15), (0.22, 0.13, 0.08, 0.05)
    out = np.zeros_like(t)
    for ratio, a, tau in zip(ratios, amps, taus):
        out += damped_sine(t, hz * ratio, tau * stretch, a, t0=t0)
    return amp * out


def sfx_coin(_rng: np.random.Generator) -> np.ndarray:
    t = time_axis(secs(0.42))
    return bell(t, note_hz("B5"), 0.0, 1.0) + bell(t, note_hz("E6"), 0.075, 0.9)


def sfx_item_pickup(rng: np.random.Generator) -> np.ndarray:
    buf = np.zeros(secs(0.55))
    for i, note in enumerate(["D5", "A5", "D6"]):
        place(buf, 0.09 * i, harp(rng, note_hz(note), 0.25, 0.7 + 0.1 * i))
    return reverb(buf, rt60=0.6, wet=0.35, predelay=0.01)


def sfx_quest_accept(rng: np.random.Generator) -> np.ndarray:
    buf = np.zeros(secs(0.85))
    for i, note in enumerate(["D4", "A4", "D5", "A5"]):
        place(buf, 0.11 * i, lute(rng, note_hz(note), 0.3, 0.65 + 0.08 * i))
    return reverb(buf, rt60=0.9, wet=0.35, predelay=0.012)


def sfx_quest_complete(rng: np.random.Generator) -> np.ndarray:
    buf = np.zeros(secs(1.15))
    for i, note in enumerate(["D4", "E4", "F4", "A4"]):
        place(buf, 0.08 * i, lute(rng, note_hz(note), 0.2, 0.6 + 0.08 * i))
    t = time_axis(len(buf))
    buf += 0.6 * (bell(t, note_hz("D5"), 0.36, 1.0, 1.8) + bell(t, note_hz("A5"), 0.4, 0.8, 1.8))
    buf += 0.6 * bell(t, note_hz("D6"), 0.44, 0.6, 1.8)
    return reverb(buf, rt60=1.1, wet=0.4, predelay=0.012)


def sfx_dialogue_blip(_rng: np.random.Generator) -> np.ndarray:
    t = time_axis(secs(0.06))
    tone = np.sin(2 * np.pi * note_hz("C6") * t) * (1.0 + 0.25 * np.sin(2 * np.pi * 2 * note_hz("C6") * t))
    return tone * np.exp(-t / 0.012) * attack(t, 0.0015)


def soft_tone(t: np.ndarray, hz: float, t0: float, length: float) -> np.ndarray:
    tt = t - t0
    env = attack(tt, 0.012) * (tt >= 0)
    tail = np.clip((tt - (length - 0.06)) / 0.06, 0.0, 1.0)
    env *= 0.5 + 0.5 * np.cos(np.pi * tail)
    return env * (np.sin(2 * np.pi * hz * np.maximum(tt, 0)) + 0.2 * np.sin(4 * np.pi * hz * np.maximum(tt, 0)))


def sfx_ui_open(_rng: np.random.Generator) -> np.ndarray:
    t = time_axis(secs(0.24))
    return soft_tone(t, note_hz("C5"), 0.0, 0.13) + soft_tone(t, note_hz("G5"), 0.08, 0.16)


def sfx_ui_close(_rng: np.random.Generator) -> np.ndarray:
    t = time_axis(secs(0.24))
    return soft_tone(t, note_hz("G5"), 0.0, 0.13) + soft_tone(t, note_hz("C5"), 0.08, 0.16)


def sfx_ladder_step(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.11)
    t = time_axis(n)
    knock = damped_sine(t, 410.0, 0.028) + damped_sine(t, 980.0, 0.016, 0.5) + damped_sine(t, 1700.0, 0.01, 0.3)
    tap = bandpass(rng.standard_normal(n), 1500.0, 4500.0) * np.exp(-t / 0.006) * 0.8
    return knock + tap


def sfx_respawn(rng: np.random.Generator) -> np.ndarray:
    buf = np.zeros(secs(1.15))
    t = time_axis(len(buf))
    for i, note in enumerate(["D4", "A4", "D5", "F5", "A5", "D6"]):
        place(buf, 0.05 + 0.1 * i, harp(rng, note_hz(note), 0.3, 0.5 + 0.08 * i))
    shimmer = bandpass(rng.standard_normal(len(buf)), 2500.0, 9000.0) * np.exp(-(((t - 0.45) / 0.22) ** 2))
    pad = (np.sin(2 * np.pi * note_hz("D5") * t) + 0.7 * np.sin(2 * np.pi * note_hz("A5") * t)) * attack(t, 0.3)
    pad *= 0.5 + 0.5 * np.cos(np.pi * np.clip((t - 0.6) / 0.5, 0.0, 1.0))
    buf += 0.12 * shimmer + 0.2 * pad
    return reverb(buf, rt60=1.3, wet=0.45, predelay=0.015)


SFX_BUILDERS = {
    "jump": sfx_jump,
    "land": sfx_land,
    "footstep_1": lambda rng: sfx_footstep(rng, 1),
    "footstep_2": lambda rng: sfx_footstep(rng, 2),
    "sword_swing": sfx_sword_swing,
    "hit_enemy": sfx_hit_enemy,
    "hit_shell": sfx_hit_shell,
    "hurt_player": sfx_hurt_player,
    "enemy_die": sfx_enemy_die,
    "coin": sfx_coin,
    "item_pickup": sfx_item_pickup,
    "quest_accept": sfx_quest_accept,
    "quest_complete": sfx_quest_complete,
    "dialogue_blip": sfx_dialogue_blip,
    "ui_open": sfx_ui_open,
    "ui_close": sfx_ui_close,
    "ladder_step": sfx_ladder_step,
    "respawn": sfx_respawn,
}
MUSIC_BUILDERS = {"town_theme": town_theme, "outskirts_theme": outskirts_theme}
SFX_PEAK_DB = -3.0
SFX_MIN_SECONDS, SFX_MAX_SECONDS = 0.05, 1.2
MUSIC_MIN_SECONDS, MUSIC_MAX_SECONDS = 48.0, 64.0


def finish_sfx(y: np.ndarray) -> np.ndarray:
    y = fade_in(y, 0.001)
    y = fade_out(y, 0.005)
    return normalize(y, SFX_PEAK_DB)


# --------------------------------------------------------------------------- files and checks
def write_wav(path: Path, y: np.ndarray) -> None:
    pcm = np.clip(np.round(y * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())


def ffmpeg(*args: str) -> bytes:
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args]
    return subprocess.run(cmd, check=True, capture_output=True).stdout


def encode_ogg(wav: Path, ogg: Path, quality: float = 3.0, seconds: float | None = None) -> None:
    """Mono Ogg Vorbis at `quality`. The bit-exact flags and the fixed serial
    number keep the file byte-identical between runs (the Ogg muxer would
    otherwise pick a random stream serial)."""
    trim = ["-t", str(seconds)] if seconds else []
    ffmpeg(
        "-i", str(wav), *trim, "-vn", "-map_metadata", "-1", "-fflags", "+bitexact", "-flags", "+bitexact",
        "-c:a", "libvorbis", "-q:a", str(quality), "-ac", "1", "-serial_offset", "1", str(ogg),
    )


def decode_ogg(ogg: Path) -> np.ndarray:
    raw = ffmpeg("-i", str(ogg), "-f", "s16le", "-ac", "1", "-ar", str(SR), "-")
    return np.frombuffer(raw, dtype="<i2").astype(float) / 32768.0


@dataclass
class Row:
    name: str
    kind: str
    seconds: float
    peak_db: float
    rms_db: float
    has_nan: bool
    size: int
    seam: float | None = None
    edge_rms_db: tuple[float, float] | None = None
    ogg_samples: tuple[int, int] | None = None
    ogg_seam_ratio: float | None = None
    problems: list[str] = field(default_factory=list)


def check_sfx(name: str, y: np.ndarray, path: Path) -> Row:
    peak = lin_to_db(np.max(np.abs(y)))
    row = Row(name, "sfx", len(y) / SR, peak, rms_db(y), bool(np.isnan(y).any()), path.stat().st_size)
    if row.has_nan:
        row.problems.append("NaN")
    if not SFX_MIN_SECONDS <= row.seconds <= SFX_MAX_SECONDS:
        row.problems.append("duration")
    if abs(row.peak_db - SFX_PEAK_DB) > 0.1:
        row.problems.append("peak")
    return row


def check_music(name: str, y: np.ndarray, seam: float, ogg: Path) -> Row:
    edge = secs(0.5)
    peak = lin_to_db(np.max(np.abs(y)))
    row = Row(name, "music", len(y) / SR, peak, rms_db(y), bool(np.isnan(y).any()), ogg.stat().st_size)
    row.seam = seam
    row.edge_rms_db = (rms_db(y[:edge]), rms_db(y[-edge:]))
    decoded = decode_ogg(ogg)
    row.ogg_samples = (len(decoded), len(y))
    # The jump from the last decoded sample back to the first, relative to the
    # 99.9th percentile of ordinary sample-to-sample steps: a clean loop point
    # is no bigger a step than the music takes anyway.
    steps = np.abs(np.diff(decoded))
    row.ogg_seam_ratio = float(abs(decoded[0] - decoded[-1]) / max(np.percentile(steps, 99.9), 1e-9))
    if row.has_nan:
        row.problems.append("NaN")
    if not MUSIC_MIN_SECONDS <= row.seconds <= MUSIC_MAX_SECONDS:
        row.problems.append("duration")
    if seam > 1e-5:
        row.problems.append("loop seam")
    if min(row.edge_rms_db) < -40.0:
        row.problems.append("faded loop edge")
    if row.ogg_samples[0] != row.ogg_samples[1]:
        row.problems.append("ogg length")
    if row.ogg_seam_ratio > 3.0:
        row.problems.append("ogg seam")
    return row


def print_report(rows: list[Row], out_dir: Path) -> None:
    print(f"\n{'file':<30} {'kind':<5} {'dur_s':>7} {'peak_dB':>8} {'rms_dB':>7} {'nan':>4} {'bytes':>8}  notes")
    for row in rows:
        notes = []
        if row.seam is not None:
            notes.append(f"seam {row.seam:.1e}")
        if row.edge_rms_db is not None:
            notes.append(f"edge rms {row.edge_rms_db[0]:.1f}/{row.edge_rms_db[1]:.1f} dB")
        if row.ogg_samples is not None:
            notes.append(f"ogg samples {row.ogg_samples[0]} (loop {row.ogg_samples[1]})")
        if row.ogg_seam_ratio is not None:
            notes.append(f"ogg seam step {row.ogg_seam_ratio:.2f}x typical")
        if row.problems:
            notes.append("FAIL: " + ", ".join(row.problems))
        print(
            f"{row.kind + '/' + row.name:<30} {row.kind:<5} {row.seconds:>7.3f} {row.peak_db:>8.2f} "
            f"{row.rms_db:>7.2f} {'yes' if row.has_nan else 'no':>4} {row.size:>8}  {'; '.join(notes)}"
        )
    total = sum(p.stat().st_size for p in out_dir.rglob("*") if p.is_file())
    print(f"\n{out_dir}: {total / 1024:.0f} KiB in total (budget {FOLDER_BUDGET_BYTES // 1024} KiB)")
    if total > FOLDER_BUDGET_BYTES:
        rows.append(Row("<folder>", "all", 0, 0, 0, False, total, problems=["folder budget"]))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="game/assets/audio by default")
    parser.add_argument("--scratch", type=Path, help="keep WAV masters and 10 s previews here")
    parser.add_argument("--only", nargs="*", default=None, help="render only these names")
    args = parser.parse_args(argv)

    scratch = args.scratch or Path(tempfile.mkdtemp(prefix="scratchpad-audio-"))
    scratch.mkdir(parents=True, exist_ok=True)
    (args.out / "sfx").mkdir(parents=True, exist_ok=True)
    (args.out / "music").mkdir(parents=True, exist_ok=True)
    wanted = set(args.only) if args.only else set(SFX_BUILDERS) | set(MUSIC_BUILDERS)
    unknown = wanted - set(SFX_BUILDERS) - set(MUSIC_BUILDERS)
    if unknown:
        parser.error(f"unknown names: {sorted(unknown)}")

    rows: list[Row] = []
    for name, build in SFX_BUILDERS.items():
        if name not in wanted:
            continue
        rng = np.random.default_rng([SEED, zlib.crc32(name.encode())])
        y = finish_sfx(build(rng))
        path = args.out / "sfx" / f"{name}.wav"
        write_wav(path, y)
        rows.append(check_sfx(name, y, path))
        print(f"sfx    {name:<16} {len(y) / SR:.3f} s")
    previews = []
    for name, build in MUSIC_BUILDERS.items():
        if name not in wanted:
            continue
        y, seam = build()
        master = scratch / f"{name}.wav"
        write_wav(master, y)
        ogg = args.out / "music" / f"{name}.ogg"
        encode_ogg(master, ogg)
        preview = scratch / f"{name}_preview10s.ogg"
        encode_ogg(master, preview, seconds=10.0)
        previews.append(preview)
        rows.append(check_music(name, y, seam, ogg))
        print(f"music  {name:<16} {len(y) / SR:.3f} s  -> {ogg}")

    print_report(rows, args.out)
    for preview in previews:
        print(f"preview: {preview}")
    failed = [row for row in rows if row.problems]
    if failed:
        print(f"\n{len(failed)} check(s) failed", file=sys.stderr)
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
