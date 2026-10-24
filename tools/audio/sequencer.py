"""Tiny arranger: songs, buses, note/chord parsing, drum grids, mixdown."""
from __future__ import annotations

import math
import os
import zlib

import numpy as np

from dsp import (SR, compressor, db2lin, limiter, loudness, make_ir, note, ns,
                 pad_to, pan, place, process_circular, reverb, rng_for,
                 smooth, wrap_tail)

# ---------------------------------------------------------------------------
# harmony helpers
# ---------------------------------------------------------------------------
QUALITIES = {
    "": [0, 4, 7], "maj": [0, 4, 7], "m": [0, 3, 7], "5": [0, 7], "dim": [0, 3, 6],
    "aug": [0, 4, 8], "sus4": [0, 5, 7], "sus2": [0, 2, 7], "7": [0, 4, 7, 10],
    "maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "m7b5": [0, 3, 6, 10], "dim7": [0, 3, 6, 9],
    "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "9": [0, 4, 10, 14], "m9": [0, 3, 10, 14],
    "maj9": [0, 4, 11, 14], "13": [0, 4, 10, 21], "7#9": [0, 4, 10, 15], "add9": [0, 4, 7, 14],
    "madd9": [0, 3, 7, 14], "7sus4": [0, 5, 7, 10], "9sus4": [0, 5, 10, 14], "m11": [0, 3, 10, 17],
    "6/9": [0, 4, 9, 14],
}
_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def parse_chord(sym: str):
    bass = None
    if "/" in sym and not sym.endswith("6/9"):
        sym, b = sym.split("/")
        bass = _pc(b)
    root = _pc(sym[:2] if len(sym) > 1 and sym[1] in "#b" else sym[0])
    qual = sym[2:] if len(sym) > 1 and sym[1] in "#b" else sym[1:]
    return root, QUALITIES[qual], bass


def _pc(s):
    v = _PC[s[0]]
    for c in s[1:]:
        v += 1 if c == "#" else -1
    return v % 12


def voicing(sym: str, center: int = 62, max_notes: int = 4):
    root, ivs, _ = parse_chord(sym)
    ivs = ivs[:max_notes]
    best, best_d = None, 1e9
    for octv in range(2, 7):
        base = 12 * octv + root
        stack = [base + i for i in ivs]
        for inv in range(len(stack)):
            v = sorted(stack[inv:] + [s + 12 for s in stack[:inv]])
            d = abs(np.mean(v) - center) + 0.2 * (v[-1] - v[0])
            if d < best_d:
                best, best_d = v, d
    return best


def bass_note(sym: str, lo: int = 28) -> int:
    root, _, b = parse_chord(sym)
    pc = root if b is None else b
    m = lo + ((pc - lo) % 12)
    return m


def chord_pcs(sym):
    root, ivs, _ = parse_chord(sym)
    return [(root + i) % 12 for i in ivs]


def parse_melody(spec: str):
    """'A4:0.5 D5:0.5 r:1 [D4,F#4]:2 E5:1:0.7' -> [(beat, dur, midi|list|None, vel)]"""
    out, pos = [], 0.0
    for tok in spec.replace("|", " ").split():
        parts = tok.split(":")
        nm, dur = parts[0], float(parts[1])
        vel = float(parts[2]) if len(parts) > 2 else 1.0
        if nm == "r":
            pass
        elif nm.startswith("["):
            out.append((pos, dur, [note(x) for x in nm[1:-1].split(",")], vel))
        else:
            out.append((pos, dur, note(nm), vel))
        pos += dur
    return out, pos


# ---------------------------------------------------------------------------
# song container
# ---------------------------------------------------------------------------
class Song:
    def __init__(self, name: str, bpm: float, bars: int, beats_per_bar: int = 4,
                 tail: float = 6.0, swing: float = 0.0, loop: bool = True):
        self.name = name
        self.bpm = bpm
        self.bars = bars
        self.bpb = beats_per_bar
        self.spb = 60.0 / bpm
        self.loop = loop
        self.loop_n = int(round(bars * beats_per_bar * self.spb * SR))
        self.N = self.loop_n + ns(tail)
        self.swing = swing
        self.rng = rng_for(name)
        self.buses: dict[str, np.ndarray] = {}
        self._cache: dict = {}

    # time ------------------------------------------------------------------
    def beat_time(self, beat: float) -> float:
        if self.swing:
            step = beat * 4.0
            r = round(step)
            if abs(step - r) < 1e-6 and int(r) % 2 == 1:
                beat += self.swing * 0.25
        return beat * self.spb

    def bar_beat(self, bar: int, beat: float = 0.0) -> float:
        return bar * self.bpb + beat

    def secs(self, beats: float) -> float:
        return beats * self.spb

    # buses -------------------------------------------------------------------
    def bus(self, name: str) -> np.ndarray:
        if name not in self.buses:
            self.buses[name] = np.zeros((2, self.N))
        return self.buses[name]

    def add(self, bus: str, sig: np.ndarray, beat: float, gain: float = 1.0,
            pan_: float = 0.0, jitter: float = 0.0) -> None:
        t = self.beat_time(beat)
        if jitter:
            t += self.rng.uniform(-jitter, jitter)
        start = int(round(t * SR))
        if start < 0 and self.loop:
            start += self.loop_n  # a note pushed before the downbeat belongs to the loop's end
        if sig.ndim == 1:
            sig = pan(sig, pan_) if pan_ else sig
        place(self.bus(bus), sig, start, gain)

    def note(self, bus: str, fn, midi, beat: float, dur_beats: float, vel: float = 1.0,
             pan_: float = 0.0, gain: float = 1.0, jitter: float = 0.004, cache: bool = True,
             variant: int = 0, **kw) -> None:
        """Render (or reuse) one note of instrument fn and place it on a bus.
        Identical (fn, pitch, length, velocity, params, variant) notes share one render."""
        dur = dur_beats * self.spb
        if isinstance(midi, (list, tuple)):
            for m in midi:
                self.note(bus, fn, m, beat, dur_beats, vel, pan_, gain, jitter, cache, variant, **kw)
            return
        vq = round(vel * 20) / 20.0
        key = (fn.__name__, int(midi), round(dur, 3), vq, tuple(sorted(kw.items())), variant)
        if cache and key in self._cache:
            sig = self._cache[key]
        else:
            sig = fn(int(midi), dur, vq, rng=np.random.default_rng(zlib.crc32(repr(key).encode())), **kw)
            if cache:
                self._cache[key] = sig
        self.add(bus, sig, beat, gain, pan_, jitter)

    def melody(self, bus: str, fn, spec: str, start_beat: float, transpose: int = 0,
               vel: float = 1.0, legato: float = 0.95, octave_double: int = 0,
               pan_: float = 0.0, gain: float = 1.0, glide: bool = False, **kw) -> float:
        evs, total = parse_melody(spec)
        prev = None
        for b, d, m, v in evs:
            mm = [x + transpose for x in m] if isinstance(m, list) else m + transpose
            extra = dict(kw)
            if glide and prev is not None and not isinstance(mm, list):
                extra["glide_from"] = prev
            self.note(bus, fn, mm, start_beat + b, d * legato, vel * v, pan_, gain, **extra)
            if octave_double:
                mo = [x + 12 * octave_double for x in mm] if isinstance(mm, list) else mm + 12 * octave_double
                self.note(bus, fn, mo, start_beat + b, d * legato, vel * v * 0.6, pan_, gain, **kw)
            prev = mm if not isinstance(mm, list) else None
        return total

    def drums(self, bar: int, pattern: dict, kit: dict, beats: float | None = None,
              jitter: float = 0.003, gain: float = 1.0, start: float = 0.0) -> None:
        """pattern: {voice: 'x...X...o...'} (any number of steps spread over `beats`);
        kit: {voice: (samples_list, gain, pan, bus)}.
        Velocity chars: X 1.0, x .82, - .6, o .42 (ghost), g .25."""
        beats = beats or self.bpb
        vmap = {"x": 0.82, "X": 1.0, "o": 0.42, "g": 0.25, "-": 0.6}
        for voice, pat in pattern.items():
            pat = pat.replace(" ", "").replace("|", "")
            samples, g, p, bus = kit[voice]
            steps = len(pat)
            for i, c in enumerate(pat):
                if c in vmap:
                    smp = samples[self.rng.integers(len(samples))]
                    v = vmap[c] * self.rng.uniform(0.93, 1.0)
                    self.add(bus, smp, bar * self.bpb + start + i * beats / steps, g * v * gain, p, jitter)

    def duck(self, beats, depth: float = 0.5, attack: float = 0.004, release: float = 0.18) -> np.ndarray:
        """Sidechain-style gain curve (length N) dipping at each beat in `beats`."""
        env = np.zeros(self.N)
        t = np.arange(ns(release * 6)) / SR
        shape = (1 - np.exp(-t / attack)) * np.exp(-t / release)
        shape /= shape.max()
        for b in beats:
            s = int(round(self.beat_time(b) * SR))
            seg = shape[:max(0, self.N - s)]
            env[s:s + len(seg)] = np.maximum(env[s:s + len(seg)], seg)
        # wrap the release of the last beats onto the start for loops
        return 1.0 - depth * env

    # mixdown -------------------------------------------------------------------
    def render(self, chain: dict, levels: dict, sends: dict, room=None, hall=None,
               master=None, target_lufs: float = -16.0, ceiling_db: float = -1.3):
        """chain: bus -> fn(stereo)->stereo; levels: bus -> dB; sends: bus -> (room, hall) linear."""
        room = room if room is not None else make_ir(0.9, 0.008, 0.5, 1.0, 0.35, seed=3)
        hall = hall if hall is not None else make_ir(2.4, 0.025, 0.4, 1.1, 0.25, seed=5)
        L = self.N + max(room.shape[-1], hall.shape[-1])
        total = np.zeros((2, L))
        rin = np.zeros((2, self.N))
        hin = np.zeros((2, self.N))
        for name, buf in self.buses.items():
            fx = chain.get(name)
            y = fx(buf) if fx else buf
            y = pad_to(y, self.N) * db2lin(levels.get(name, 0.0))
            if os.environ.get("AUDIO_DEBUG"):
                a = np.abs(y).max(axis=0)
                act = a > 1e-3
                r = np.sqrt(np.mean(y[:, act] ** 2)) if act.any() else 0.0
                print(f"    [{self.name}] bus {name:10s} active-RMS {20 * np.log10(r + 1e-12):6.1f} dB  "
                      f"peak {20 * np.log10(a.max() + 1e-12):6.1f} dB  active {act.mean() * 100:4.0f}%")
            total[:, :self.N] += y
            r, h = sends.get(name, (0.0, 0.0))
            if r:
                rin += y * r
            if h:
                hin += y * h
        if np.any(rin):
            w = reverb(rin, room)
            total[:, :w.shape[-1]] += w[:, :L]
        if np.any(hin):
            w = reverb(hin, hall)
            total[:, :w.shape[-1]] += w[:, :L]
        if self.loop:
            out = wrap_tail(total, self.loop_n)
        else:
            out = total
        return master_chain(out, loop=self.loop, master=master, target_lufs=target_lufs,
                            ceiling_db=ceiling_db)


def master_chain(x: np.ndarray, loop: bool, master=None, target_lufs=-16.0, ceiling_db=-1.3):
    """Glue compression + loudness normalisation + look-ahead limiting.
    For loops everything runs circularly so the seam sees steady state."""
    from dsp import dc_block

    def proc(sig, gain_lin):
        y = dc_block(sig, 20.0)
        if master:
            y = master(y)
        y = compressor(y, -14.0, 1.8, 0.02, 0.25, 8.0)
        y = y * gain_lin
        y = limiter(y, ceiling_db, 0.005, 0.12)
        return y

    run = (lambda s, g: process_circular(s, lambda z: proc(z, g), 4.0)) if loop else proc
    g = 1.0
    for _ in range(4):
        y = run(x, g)
        lu = loudness(y)["integrated"]
        g *= db2lin(target_lufs - lu)
    y = run(x, g)
    return y
