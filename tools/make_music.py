"""Generates the games' background music: original, royalty-free, seamless loops.

    pip install numpy          # ffmpeg with libvorbis must be on PATH
    python3 tools/make_music.py

Writes game/assets/music/<name>.ogg. Everything is synthesized here (no samples),
and notes that ring past the end wrap around to the start, so each file loops
without a gap. Change a track's tempo, chords or patterns below and run again.
"""

from __future__ import annotations

import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "music"
ARENA_OUT = Path(__file__).resolve().parent.parent / "arena" / "assets" / "music"
RNG = np.random.default_rng(7)


def hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


# ---------------------------------------------------------------- instruments

def _t(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def pluck(freq: float, dur: float, bright: float = 0.6) -> np.ndarray:
    t = _t(dur)
    sig = sum((bright ** (k - 1)) / k * np.sin(2 * np.pi * freq * k * t) for k in range(1, 8))
    return sig * np.exp(-t * 6.0) * np.minimum(1, t * 400)


def pad(freq: float, dur: float) -> np.ndarray:
    t = _t(dur)
    voices = sum(np.sin(2 * np.pi * freq * d * t) + 0.3 * np.sin(2 * np.pi * freq * 2 * d * t)
                 for d in (0.996, 1.0, 1.004))
    env = np.minimum(1, t / 0.4) * np.minimum(1, (dur - t) / 0.4)
    return voices / 3 * env


def bass(freq: float, dur: float) -> np.ndarray:
    t = _t(dur)
    sig = sum(np.sin(2 * np.pi * freq * k * t) / k for k in (1, 3, 5))
    return sig * np.exp(-t * 3.0) * np.minimum(1, t * 300) * np.minimum(1, (dur - t) * 60)


def brass(freq: float, dur: float) -> np.ndarray:
    t = _t(dur)
    sig = sum(np.sin(2 * np.pi * freq * k * t) / k for k in range(1, 10))
    return sig * np.minimum(1, t / 0.03) * np.exp(-t * 2.5)


def kick(dur: float = 0.35) -> np.ndarray:
    t = _t(dur)
    freq = 45 + 110 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 9)


def noise_hit(dur: float, decay: float, tone: float = 0.0) -> np.ndarray:
    t = _t(dur)
    n = RNG.standard_normal(len(t))
    if tone:
        n = n + 0.6 * np.sin(2 * np.pi * tone * t)
    return n * np.exp(-t * decay)


def hat(dur: float = 0.05) -> np.ndarray:
    return np.diff(noise_hit(dur, 80), prepend=0) * 0.5      # crude high-pass


def snare() -> np.ndarray:
    return noise_hit(0.2, 22, tone=190) * 0.6


def clap() -> np.ndarray:
    hit = noise_hit(0.15, 30)
    out = np.zeros(int(0.17 * SR))
    for k, delay in enumerate((0.0, 0.011, 0.022)):           # a few hands, slightly apart
        i = int(delay * SR)
        out[i:i + len(hit)] += hit[: len(out) - i] * (0.7 if k < 2 else 1.0)
    return np.diff(out, prepend=0) * 0.8


def tom(freq: float) -> np.ndarray:
    t = _t(0.3)
    f = freq * (1 + 0.5 * np.exp(-t * 20))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)


# ---------------------------------------------------------------- arranging

class Track:
    """Two buses: music (ducked by the kick) and drums (dry)."""

    def __init__(self, bpm: float, bars: int):
        self.beat = 60.0 / bpm
        self.length = int(round(bars * 4 * self.beat * SR))
        self.music = np.zeros((2, self.length))
        self.drums = np.zeros((2, self.length))
        self.duck = np.ones(self.length)

    def add(self, bus: str, sig: np.ndarray, beat: float, gain: float = 1.0, pan: float = 0.0) -> None:
        start = int(round(beat * self.beat * SR)) % self.length
        idx = (start + np.arange(len(sig))) % self.length       # wrap around: seamless loop
        target = self.music if bus == "music" else self.drums
        np.add.at(target[0], idx, sig * gain * np.sqrt((1 - pan) / 2))
        np.add.at(target[1], idx, sig * gain * np.sqrt((1 + pan) / 2))

    def pump(self, beat: float, depth: float) -> None:
        start = int(round(beat * self.beat * SR))
        n = int(self.beat * SR)
        curve = 1 - depth * np.exp(-np.arange(n) / (0.12 * SR))
        idx = (start + np.arange(n)) % self.length
        self.duck[idx] = np.minimum(self.duck[idx], curve)

    def render(self) -> np.ndarray:
        out = self.music * self.duck + self.drums
        out = np.tanh(out * 1.2) / np.tanh(1.2)
        return out / (np.abs(out).max() + 1e-9) * 0.85


def triad(root: int, minor: bool) -> list[int]:
    return [root, root + (3 if minor else 4), root + 7]


def quiz_think() -> np.ndarray:
    """96 BPM, A minor, soft plucked arpeggios: thinking music."""
    tr = Track(96, 16)
    prog = [(57, True), (53, False), (48, False), (55, False)]      # Am F C G
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = triad(root, minor)
        b0 = bar * 4
        for n in notes:
            tr.add("music", pad(hz(n), 4 * tr.beat), b0, 0.05, pan=-0.3)
        arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[1] + 12]
        for i in range(8):
            tr.add("music", pluck(hz(arp[i % 4]), 0.5, 0.5), b0 + i * 0.5, 0.11, pan=0.35)
        tr.add("music", bass(hz(root - 12), 1.8 * tr.beat), b0, 0.22)
        tr.add("music", bass(hz(root - 12), 0.9 * tr.beat), b0 + 2.5, 0.16)
        tr.add("drums", kick(), b0, 0.45)
        tr.add("drums", kick(), b0 + 2, 0.35)
        for i in range(16):
            tr.add("drums", hat(), b0 + i * 0.25, 0.05 if i % 2 else 0.09, pan=0.25)
        if bar % 4 == 3:
            tr.add("drums", snare(), b0 + 3.5, 0.12)
    return tr.render()


def tug_energy() -> np.ndarray:
    """128 BPM, C major, four-on-the-floor with pumping bass: competitive energy."""
    tr = Track(128, 16)
    prog = [(48, False), (55, False), (57, True), (53, False)]      # C G Am F
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = triad(root, minor)
        b0 = bar * 4
        for beat in range(4):
            tr.add("drums", kick(), b0 + beat, 0.6)
            tr.pump(b0 + beat, 0.55)
            tr.add("drums", hat(0.08), b0 + beat + 0.5, 0.16, pan=0.3)
            tr.add("music", bass(hz(root - 12), 0.45 * tr.beat), b0 + beat + 0.5, 0.3)
        tr.add("drums", clap(), b0 + 1, 0.35)
        tr.add("drums", clap(), b0 + 3, 0.35)
        for n in notes:
            tr.add("music", pad(hz(n + 12), 4 * tr.beat), b0, 0.04, pan=-0.3)
        pattern = [0, 1, 2, 1, 2, 3, 2, 1]
        arp = notes + [notes[0] + 12]
        for i in range(16):
            tr.add("music", pluck(hz(arp[pattern[i % 8]] + 24), 0.25, 0.7), b0 + i * 0.25, 0.07,
                   pan=0.4 if i % 2 else -0.1)
        if bar % 8 == 7:
            for i, f in enumerate((220, 180, 150, 120)):
                tr.add("drums", tom(f), b0 + 2 + i * 0.5, 0.35)
    return tr.render()


def football_stadium() -> np.ndarray:
    """120 BPM, D minor, stomp-and-clap drums with brass stabs: stadium mood."""
    tr = Track(120, 16)
    prog = [(50, True), (46, False), (48, False), (45, False)]      # Dm Bb C A
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = triad(root, minor)
        b0 = bar * 4
        for beat in (0, 0.5, 2, 2.5):                                # stomp stomp
            tr.add("drums", kick(0.3), b0 + beat, 0.55)
            tr.add("drums", tom(90), b0 + beat, 0.25)
            tr.pump(b0 + beat, 0.35)
        tr.add("drums", clap(), b0 + 1, 0.5)
        tr.add("drums", clap(), b0 + 3, 0.5)
        for i in range(8):
            tr.add("drums", hat(0.04), b0 + i * 0.5 + 0.25, 0.07, pan=0.3)
        for n in notes:                                              # brass stabs
            tr.add("music", brass(hz(n), 0.35), b0 + 1.5, 0.05, pan=-0.2)
            tr.add("music", brass(hz(n), 0.6), b0 + 3, 0.06, pan=0.2)
            tr.add("music", pad(hz(n + 12), 4 * tr.beat), b0, 0.045)
        tr.add("music", bass(hz(root - 12), 0.9 * tr.beat), b0, 0.3)
        tr.add("music", bass(hz(root - 12), 0.9 * tr.beat), b0 + 2, 0.3)
        if bar % 4 == 3:
            for i, f in enumerate((240, 200, 170, 140, 110, 90)):
                tr.add("drums", tom(f), b0 + 1 + i * 0.5, 0.4)
    return tr.render()


def climb_adventure() -> np.ndarray:
    """116 BPM, D minor, rising arpeggios over a driving beat: always going up."""
    tr = Track(116, 16)
    prog = [(50, True), (46, False), (48, False), (45, False)]      # Dm Bb C A
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = triad(root, minor)
        b0 = bar * 4
        for beat in range(4):
            tr.add("drums", kick(), b0 + beat, 0.5 if beat % 2 == 0 else 0.35)
            tr.pump(b0 + beat, 0.4)
            tr.add("drums", hat(0.05), b0 + beat + 0.5, 0.14, pan=-0.3)
            tr.add("drums", hat(0.03), b0 + beat + 0.75, 0.08, pan=0.3)
            tr.add("music", bass(hz(root - 12), 0.3 * tr.beat), b0 + beat, 0.28)
            tr.add("music", bass(hz(root), 0.2 * tr.beat), b0 + beat + 0.5, 0.18)
        tr.add("drums", snare(), b0 + 1, 0.3)
        tr.add("drums", snare(), b0 + 3, 0.3)
        for n in notes:
            tr.add("music", pad(hz(n + 12), 4 * tr.beat), b0, 0.035, pan=0.2)
        arp = notes + [n + 12 for n in notes]                           # climbs two octaves a bar
        for i in range(16):
            tr.add("music", pluck(hz(arp[i % 6] + 12 + 12 * (i // 12)), 0.22, 0.65), b0 + i * 0.25, 0.065,
                   pan=0.35 if i % 2 else -0.35)
        if bar % 4 == 3:
            tr.add("music", brass(hz(notes[2] + 12), 1.5 * tr.beat), b0 + 2, 0.08)
        if bar % 8 == 7:
            for i, f in enumerate((120, 150, 180, 220)):
                tr.add("drums", tom(f), b0 + 2 + i * 0.5, 0.3)
    return tr.render()


def arena_battle() -> np.ndarray:
    """140 BPM, E minor, pounding toms and brass stabs: a fight is on."""
    tr = Track(140, 16)
    prog = [(52, True), (48, False), (50, False), (47, False)]      # Em C D B
    for bar in range(16):
        root, minor = prog[bar % 4]
        notes = triad(root, minor)
        b0 = bar * 4
        for beat in range(4):
            tr.add("drums", kick(), b0 + beat, 0.6)
            tr.pump(b0 + beat, 0.5)
            tr.add("drums", hat(0.04), b0 + beat + 0.5, 0.15, pan=0.25)
            for k in (0.0, 0.5):
                tr.add("music", bass(hz(root - 12), 0.22 * tr.beat), b0 + beat + k, 0.3)
        tr.add("drums", snare(), b0 + 1, 0.35)
        tr.add("drums", snare(), b0 + 3, 0.35)
        tr.add("drums", clap(), b0 + 3.75, 0.18)
        for i, f in enumerate((140, 120)):
            tr.add("drums", tom(f), b0 + 2.5 + i * 0.25, 0.25, pan=-0.3 if i else 0.3)
        for n in notes:
            tr.add("music", pad(hz(n + 12), 4 * tr.beat), b0, 0.03)
        tr.add("music", brass(hz(notes[0] + 12), 0.5 * tr.beat), b0, 0.09)
        tr.add("music", brass(hz(notes[2] + 12), 0.5 * tr.beat), b0 + 1.5, 0.07)
        for i in range(8):
            tr.add("music", pluck(hz(notes[i % 3] + 24), 0.18, 0.7), b0 + i * 0.5, 0.05, pan=0.4 if i % 2 else -0.4)
        if bar % 8 == 7:
            for i, f in enumerate((220, 180, 150, 120, 100, 90)):
                tr.add("drums", tom(f), b0 + 1 + i * 0.5, 0.33)
    return tr.render()


TRACKS = {"quiz_think": quiz_think, "tug_energy": tug_energy, "football_stadium": football_stadium,
          "climb_adventure": climb_adventure}
ARENA_TRACKS = {"arena_battle": arena_battle}


def save_ogg(name: str, stereo: np.ndarray, out_dir: Path = OUT) -> Path:
    out_dir.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(stereo.T, -1, 1) * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / f"{name}.wav"
        with wave.open(str(wav), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        out = out_dir / f"{name}.ogg"
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(wav), "-c:a", "libvorbis",
                        "-q:a", "4", str(out)], check=True)
    return out


if __name__ == "__main__":
    for name, make in TRACKS.items():
        path = save_ogg(name, make())
        print(f"{path.name}  {path.stat().st_size // 1024} KB")
    for name, make in ARENA_TRACKS.items():
        path = save_ogg(name, make(), ARENA_OUT)
        print(f"arena/{path.name}  {path.stat().st_size // 1024} KB")
