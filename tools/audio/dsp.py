"""Small procedural-audio DSP library for Baseball Draw.

Everything is plain numpy + scipy.signal and fully deterministic (callers pass
explicit numpy Generators).  Signals are float64 arrays in [-1, 1]; mono is
shape (n,), stereo is shape (2, n).
"""
from __future__ import annotations

import os
import struct
import subprocess
import zlib

import numpy as np
from scipy import ndimage
from scipy import signal as sps

SR = 44100
TWO_PI = 2.0 * np.pi


# --------------------------------------------------------------------------
# basic helpers
# --------------------------------------------------------------------------
def ns(seconds: float) -> int:
    """Seconds -> sample count."""
    return max(1, int(round(seconds * SR)))


def tarr(n: int) -> np.ndarray:
    return np.arange(n) / SR


def mtof(m) -> np.ndarray | float:
    return 440.0 * 2.0 ** ((np.asarray(m, float) - 69.0) / 12.0)


_NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def note(name: str) -> int:
    """'C4' -> 60, 'F#5' -> 78, 'Bb2' -> 46."""
    name = name.strip()
    pc = _NOTE_PC[name[0].upper()]
    i = 1
    while i < len(name) and name[i] in "#b":
        pc += 1 if name[i] == "#" else -1
        i += 1
    octave = int(name[i:])
    return 12 * (octave + 1) + pc


def db2lin(db) -> float:
    return 10.0 ** (np.asarray(db, float) / 20.0)


def lin2db(x) -> float:
    return 20.0 * np.log10(np.maximum(np.asarray(x, float), 1e-12))


def seed_of(name: str) -> int:
    """Stable per-name seed (independent of build order)."""
    return zlib.crc32(name.encode("utf-8")) & 0x7FFFFFFF


def rng_for(name: str) -> np.random.Generator:
    return np.random.default_rng(seed_of(name))


def peak(x) -> float:
    return float(np.max(np.abs(x))) if np.size(x) else 0.0


def rms(x) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if np.size(x) else 0.0


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if x.shape[-1] >= n:
        return x[..., :n]
    pad = [(0, 0)] * (x.ndim - 1) + [(0, n - x.shape[-1])]
    return np.pad(x, pad)


def place(buf: np.ndarray, x: np.ndarray, start: int, gain: float = 1.0) -> None:
    """Add x into buf at sample offset start (clipped to buffer bounds).
    buf/x may be mono or stereo; mono x into stereo buf is added to both."""
    if start >= buf.shape[-1]:
        return
    s0 = max(0, start)
    off = s0 - start
    n = min(x.shape[-1] - off, buf.shape[-1] - s0)
    if n <= 0:
        return
    seg = x[..., off:off + n] * gain
    if buf.ndim == 2 and seg.ndim == 1:
        buf[:, s0:s0 + n] += seg
    else:
        buf[..., s0:s0 + n] += seg


def mix(*sigs) -> np.ndarray:
    """Sum signals of different lengths (all mono or all stereo)."""
    n = max(s.shape[-1] for s in sigs)
    out = np.zeros(sigs[0].shape[:-1] + (n,))
    for s in sigs:
        out[..., :s.shape[-1]] += s
    return out


def concat(*sigs) -> np.ndarray:
    return np.concatenate(sigs, axis=-1)


# --------------------------------------------------------------------------
# oscillators
# --------------------------------------------------------------------------
def _phase(freq, n: int, phase0: float = 0.0):
    if np.ndim(freq) == 0:
        inc = np.full(n, float(freq) / SR)
    else:
        f = np.asarray(freq, float)
        if f.shape[0] < n:
            f = np.concatenate([f, np.full(n - f.shape[0], f[-1])])
        inc = f[:n] / SR
    ph = phase0 + np.concatenate(([0.0], np.cumsum(inc[:-1])))
    return ph, inc


def sine(freq, n: int, phase0: float = 0.0) -> np.ndarray:
    ph, _ = _phase(freq, n, phase0)
    return np.sin(TWO_PI * ph)


def _blep(t, dt):
    out = np.zeros_like(t)
    m = t < dt
    if np.any(m):
        x = t[m] / dt[m]
        out[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    if np.any(m):
        x = (t[m] - 1.0) / dt[m]
        out[m] = x * x + x + x + 1.0
    return out


def saw(freq, n: int, phase0: float = 0.0) -> np.ndarray:
    """Band-limited (polyBLEP) sawtooth."""
    ph, dt = _phase(freq, n, phase0)
    t = ph % 1.0
    dt = np.minimum(np.abs(dt), 0.5) + 1e-12
    return 2.0 * t - 1.0 - _blep(t, dt)


def square(freq, n: int, pw: float = 0.5, phase0: float = 0.0) -> np.ndarray:
    """Band-limited (polyBLEP) pulse wave."""
    ph, dt = _phase(freq, n, phase0)
    t = ph % 1.0
    dt = np.minimum(np.abs(dt), 0.5) + 1e-12
    y = np.where(t < pw, 1.0, -1.0)
    y += _blep(t, dt)
    y -= _blep((t + 1.0 - pw) % 1.0, dt)
    return y


def triangle(freq, n: int, phase0: float = 0.0) -> np.ndarray:
    ph, _ = _phase(freq, n, phase0)
    t = ph % 1.0
    return 2.0 * np.abs(2.0 * t - 1.0) - 1.0


def supersaw(freq, n: int, voices: int = 5, detune_cents: float = 14.0,
             rng: np.random.Generator | None = None) -> np.ndarray:
    rng = rng or np.random.default_rng(0)
    out = np.zeros(n)
    for i in range(voices):
        d = 0.0 if voices == 1 else (i / (voices - 1) - 0.5) * 2.0 * detune_cents
        f = np.asarray(freq, float) * 2.0 ** (d / 1200.0)
        out += saw(f, n, rng.random())
    return out / np.sqrt(voices)


def fm(fc, ratio: float, index, n: int, fb_phase: float = 0.0) -> np.ndarray:
    """Two-operator FM: sin(carrier + index * sin(modulator))."""
    pc, _ = _phase(fc, n)
    pm, _ = _phase(np.asarray(fc, float) * ratio, n, fb_phase)
    return np.sin(TWO_PI * pc + np.asarray(index, float) * np.sin(TWO_PI * pm))


def partials(f0: float, n: int, spec, rng=None) -> np.ndarray:
    """Additive / modal synthesis.  spec = [(ratio, amp, decay_s), ...]."""
    t = tarr(n)
    out = np.zeros(n)
    for k, (ratio, amp, dec) in enumerate(spec):
        f = f0 * ratio
        if f >= SR * 0.45:
            continue
        ph = rng.random() if rng is not None else 0.0
        out += amp * np.exp(-t / dec) * np.sin(TWO_PI * (f * t + ph))
    return out


# --------------------------------------------------------------------------
# noise
# --------------------------------------------------------------------------
def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n)


def colored(n: int, rng: np.random.Generator, slope_db_oct: float = -3.0,
            fmin: float = 20.0) -> np.ndarray:
    """FFT-shaped noise (periodic over n samples), unit RMS.
    slope -3 = pink, -6 = brown."""
    X = np.fft.rfft(rng.standard_normal(n))
    f = np.fft.rfftfreq(n, 1.0 / SR)
    expo = slope_db_oct / (20.0 * np.log10(2.0))
    g = np.maximum(f, fmin) ** expo
    g[0] = 0.0
    y = np.fft.irfft(X * g, n)
    return y / (rms(y) + 1e-12)


def pink(n, rng):
    return colored(n, rng, -3.0)


def brown(n, rng):
    return colored(n, rng, -6.0)


def fft_shape(x: np.ndarray, gain_fn) -> np.ndarray:
    """Circular zero-phase filtering: multiply spectrum by gain_fn(freqs)."""
    n = x.shape[-1]
    X = np.fft.rfft(x, axis=-1)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(X * gain_fn(f), n, axis=-1)


# --------------------------------------------------------------------------
# envelopes
# --------------------------------------------------------------------------
def linseg(points, n: int, curve: str = "lin") -> np.ndarray:
    """Breakpoint envelope. points = [(time_s, value), ...].
    curve 'exp' interpolates in log domain (values must be > 0)."""
    t = tarr(n)
    ts = np.array([p[0] for p in points], float)
    vs = np.array([p[1] for p in points], float)
    if curve == "exp":
        return np.exp(np.interp(t, ts, np.log(np.maximum(vs, 1e-6))))
    return np.interp(t, ts, vs)


def adsr(n: int, a: float, d: float, s: float, r: float, gate: float,
         curve: float = 1.0) -> np.ndarray:
    """Analog-style ADSR. a = attack time, d = decay time constant,
    s = sustain level, r = release time constant, gate = note-on length (s)."""
    t = tarr(n)
    a = max(a, 1e-4)
    att = np.clip(t / a, 0.0, 1.0) ** curve
    dec = s + (1.0 - s) * np.exp(-np.maximum(t - a, 0.0) / max(d, 1e-4))
    env = np.where(t < a, att, dec)
    # level at gate
    if gate < a:
        lg = (gate / a) ** curve
    else:
        lg = s + (1.0 - s) * np.exp(-(gate - a) / max(d, 1e-4))
    rel = lg * np.exp(-np.maximum(t - gate, 0.0) / max(r, 1e-4))
    env = np.where(t < gate, env, rel)
    return env


def perc(n: int, attack: float, decay: float, hold: float = 0.0) -> np.ndarray:
    t = tarr(n)
    att = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    dec = np.exp(-np.maximum(t - attack - hold, 0.0) / decay)
    return att * dec


def fade(x: np.ndarray, fin: float = 0.002, fout: float = 0.01) -> np.ndarray:
    x = np.array(x, float, copy=True)
    n = x.shape[-1]
    a = min(ns(fin), n // 2) if fin > 0 else 0
    b = min(ns(fout), n // 2) if fout > 0 else 0
    if a > 0:
        x[..., :a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if b > 0:
        x[..., n - b:] *= np.cos(np.linspace(0, np.pi / 2, b)) ** 2
    return x


# --------------------------------------------------------------------------
# filters
# --------------------------------------------------------------------------
def rbj(kind: str, f, q=0.7071, gain_db=0.0):
    """RBJ cookbook biquad coefficients (vectorised over f/q).
    Returns (b, a) each shape (3, ...) normalised so a0 = 1."""
    f = np.clip(np.asarray(f, float), 5.0, SR * 0.46)
    q = np.asarray(q, float)
    w0 = TWO_PI * f / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)
    A = 10.0 ** (np.asarray(gain_db, float) / 40.0)
    one = np.ones_like(cw)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":
        b = [alpha, 0 * cw, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "notch":
        b = [one, -2 * cw, one]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw),
             A * ((A + 1) - (A - 1) * cw - sq)]
        a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw),
             (A + 1) + (A - 1) * cw - sq]
    elif kind == "highshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw),
             A * ((A + 1) + (A - 1) * cw - sq)]
        a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw),
             (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    b = np.array(np.broadcast_arrays(*b), float)
    a = np.array(np.broadcast_arrays(*a), float)
    return b / a[0], a / a[0]


def filt(x, kind: str, f, q=0.7071, gain_db=0.0, order: int = 1) -> np.ndarray:
    """Static biquad, cascaded `order` times."""
    b, a = rbj(kind, f, q, gain_db)
    sos = np.tile(np.concatenate([b, a]), (order, 1))
    return sps.sosfilt(sos, x, axis=-1)


def lp(x, f, q=0.7071, order=1):
    return filt(x, "lp", f, q, order=order)


def hp(x, f, q=0.7071, order=1):
    return filt(x, "hp", f, q, order=order)


def bp(x, f, q=1.0, order=1):
    return filt(x, "bp", f, q, order=order)


def peq(x, f, gain_db, q=1.0):
    return filt(x, "peak", f, q, gain_db)


def shelf(x, kind, f, gain_db, q=0.7071):
    return filt(x, kind, f, q, gain_db)


def butter(x, kind: str, f, order: int = 4) -> np.ndarray:
    btype = {"lp": "lowpass", "hp": "highpass", "bp": "bandpass"}[kind]
    wn = np.asarray(f, float) / (SR / 2.0)
    sos = sps.butter(order, wn, btype=btype, output="sos")
    return sps.sosfilt(sos, x, axis=-1)


def zphase(x, kind: str, f, order: int = 2) -> np.ndarray:
    """Zero-phase Butterworth (filtfilt) – used for DC/sub cleanup."""
    btype = {"lp": "lowpass", "hp": "highpass"}[kind]
    sos = sps.butter(order, f / (SR / 2.0), btype=btype, output="sos")
    return sps.sosfiltfilt(sos, x, axis=-1)


def tvfilt(x, kind: str, f, q=0.7071, gain_db=0.0, block: int = 32) -> np.ndarray:
    """Time-varying biquad: coefficients updated every `block` samples."""
    x = np.asarray(x, float)
    n = x.shape[-1]
    f = np.asarray(f, float)
    f = np.full(n, float(f)) if f.ndim == 0 else pad_edge(f, n)
    qa = np.asarray(q, float)
    nb = (n + block - 1) // block
    centers = np.minimum(np.arange(nb) * block + block // 2, n - 1)
    qb = qa if qa.ndim == 0 else pad_edge(qa, n)[centers]
    b, a = rbj(kind, f[centers], qb, gain_db)
    y = np.empty_like(x)
    zi = np.zeros(x.shape[:-1] + (2,))
    lfilter = sps.lfilter
    for i in range(nb):
        s0 = i * block
        s1 = min(n, s0 + block)
        y[..., s0:s1], zi = lfilter(b[:, i], a[:, i], x[..., s0:s1], axis=-1, zi=zi)
    return y


def pad_edge(a: np.ndarray, n: int) -> np.ndarray:
    if a.shape[-1] >= n:
        return a[..., :n]
    return np.concatenate([a, np.full(n - a.shape[-1], a[-1])])


def onepole_lp(x, f) -> np.ndarray:
    k = np.exp(-TWO_PI * f / SR)
    return sps.lfilter([1 - k], [1, -k], x, axis=-1)


def smooth(x, tau_s: float) -> np.ndarray:
    """One-pole smoother with time constant tau (s), starts at x[0]."""
    k = np.exp(-1.0 / (max(tau_s, 1e-5) * SR))
    zi = sps.lfilter_zi([1 - k], [1, -k]) * x[..., :1]
    y, _ = sps.lfilter([1 - k], [1, -k], x, axis=-1, zi=zi)
    return y


def dc_block(x, f=18.0) -> np.ndarray:
    return filt(x, "hp", f, 0.7071, order=1)


# --------------------------------------------------------------------------
# effects
# --------------------------------------------------------------------------
def saturate(x, drive: float = 2.0, mix_: float = 1.0, asym: float = 0.0) -> np.ndarray:
    """tanh waveshaper normalised so small signals keep ~unity gain."""
    y = np.tanh(drive * (x + asym)) - np.tanh(drive * asym)
    y /= drive
    return mix_ * y + (1 - mix_) * x


def soft_clip(x, ceiling: float = 0.98) -> np.ndarray:
    return ceiling * np.tanh(x / ceiling)


def pan(x: np.ndarray, p: float = 0.0) -> np.ndarray:
    """Constant-power pan of mono x; p in [-1, 1]."""
    th = (p + 1.0) * np.pi / 4.0
    return np.stack([x * np.cos(th), x * np.sin(th)]) * np.sqrt(2.0)


def to_stereo(x: np.ndarray) -> np.ndarray:
    return x if x.ndim == 2 else np.stack([x, x])


def width(x: np.ndarray, w: float) -> np.ndarray:
    m = 0.5 * (x[0] + x[1])
    s = 0.5 * (x[0] - x[1]) * w
    return np.stack([m + s, m - s])


def make_ir(rt60: float = 1.6, predelay: float = 0.012, hf_ratio: float = 0.45,
            lf_ratio: float = 1.1, er: float = 0.35, seed: int = 7,
            density_ms: float = 12.0, lp_hz: float = 9000.0) -> np.ndarray:
    """Synthetic stereo room impulse response (unit energy per channel)."""
    rng = np.random.default_rng(seed)
    nd = ns(rt60 * 1.15)
    t = tarr(nd)
    pre = ns(predelay)
    chans = []
    for _ in range(2):
        nz = rng.standard_normal(nd)
        lo = butter(nz, "lp", 350.0, 2)
        hi = butter(nz, "hp", 3500.0, 2)
        mid = nz - lo - hi
        env = lambda r: np.exp(-6.9078 * t / r)
        d = lo * env(rt60 * lf_ratio) + mid * env(rt60) + hi * env(rt60 * hf_ratio)
        d *= 1.0 - np.exp(-t / (density_ms / 1000.0))
        d = lp(d, lp_hz)
        ir = np.zeros(nd + pre)
        ir[pre:] = d
        # early reflections
        for _k in range(10):
            pos = pre + ns(rng.uniform(0.003, 0.07))
            ir[pos] += er * rng.uniform(-1, 1) * np.exp(-(pos - pre) / SR / 0.05) * 6.0
        ir = fade(ir, 0.0, rt60 * 0.15)
        chans.append(ir)
    ir = np.array(chans)
    ir /= np.sqrt(np.sum(ir ** 2, axis=1, keepdims=True))
    return ir


def reverb(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """Convolve mono or stereo x with a stereo IR; returns stereo wet signal
    of length len(x) + len(ir) - 1."""
    xs = to_stereo(x)
    return np.stack([sps.oaconvolve(xs[c], ir[c]) for c in range(2)])


def delay(x: np.ndarray, time_s: float, feedback: float = 0.4, repeats: int = 6,
          lp_hz: float = 3500.0, pingpong: bool = True) -> np.ndarray:
    """Feedback delay (wet only, stereo) rendered as filtered echo taps."""
    xs = to_stereo(x)
    d = ns(time_s)
    n = xs.shape[-1] + d * repeats
    out = np.zeros((2, n))
    sig = xs.copy()
    for k in range(1, repeats + 1):
        sig = lp(sig, lp_hz) * feedback
        if pingpong:
            src = sig if k % 2 == 0 else sig[::-1]
        else:
            src = sig
        out[:, k * d:k * d + xs.shape[-1]] += src
    return out


def mod_delay(x: np.ndarray, delay_samples: np.ndarray) -> np.ndarray:
    """Fractional, time-varying delay line (linear interpolation)."""
    n = x.shape[-1]
    idx = np.arange(n) - delay_samples
    return np.interp(idx, np.arange(n), x, left=0.0)


def chorus(x: np.ndarray, rate: float = 0.7, depth_ms: float = 2.5,
           base_ms: float = 11.0, mix_: float = 0.5, voices: int = 2) -> np.ndarray:
    xs = to_stereo(x)
    n = xs.shape[-1]
    t = tarr(n)
    out = np.zeros_like(xs)
    for c in range(2):
        wet = np.zeros(n)
        for v in range(voices):
            ph = c * np.pi / 2 + v * 2 * np.pi / voices
            d = (base_ms + depth_ms * np.sin(TWO_PI * rate * (1 + 0.13 * v) * t + ph)) * SR / 1000
            wet += mod_delay(xs[c], d)
        out[c] = xs[c] * (1 - mix_) + wet / voices * mix_
    return out


def leslie(x: np.ndarray, rate: float = 6.2, depth: float = 1.0) -> np.ndarray:
    """Rotary speaker approximation: split at 800 Hz, horn + drum rotors with
    doppler (modulated delay) and amplitude modulation, stereo mics."""
    m = x if x.ndim == 1 else 0.5 * (x[0] + x[1])
    n = m.shape[-1]
    t = tarr(n)
    lo = butter(m, "lp", 800.0, 2)
    hi = m - lo
    out = np.zeros((2, n))
    for c, ph in enumerate((0.0, np.pi * 0.5)):
        hrot = TWO_PI * rate * t + ph
        drot = TWO_PI * rate * 0.86 * t + ph + 1.3
        dh = (1.2 + 0.45 * depth * np.sin(hrot)) * SR / 1000.0
        dd = (1.2 + 0.25 * depth * np.sin(drot)) * SR / 1000.0
        h = mod_delay(hi, dh) * (1.0 + 0.35 * depth * np.cos(hrot))
        d = mod_delay(lo, dd) * (1.0 + 0.15 * depth * np.cos(drot))
        out[c] = h + d
    return out


def tremolo(x: np.ndarray, rate: float, depth: float, stereo_phase: float = np.pi) -> np.ndarray:
    xs = to_stereo(x)
    t = tarr(xs.shape[-1])
    out = np.empty_like(xs)
    for c in range(2):
        out[c] = xs[c] * (1.0 - depth * 0.5 * (1 + np.sin(TWO_PI * rate * t + c * stereo_phase)))
    return out


# --------------------------------------------------------------------------
# dynamics
# --------------------------------------------------------------------------
def _detector(x: np.ndarray) -> np.ndarray:
    return np.max(np.abs(x), axis=0) if x.ndim == 2 else np.abs(x)


def compressor(x: np.ndarray, thresh_db: float = -18.0, ratio: float = 3.0,
               attack: float = 0.008, release: float = 0.12, knee_db: float = 6.0,
               makeup_db: float = 0.0, sidechain: np.ndarray | None = None) -> np.ndarray:
    sc = _detector(x if sidechain is None else sidechain)
    lvl = 10 * np.log10(smooth(sc ** 2, attack * 0.5) + 1e-12)
    over = lvl - thresh_db
    k = knee_db / 2.0
    gr = np.where(over <= -k, 0.0,
                  np.where(over >= k, over * (1.0 / ratio - 1.0),
                           (1.0 / ratio - 1.0) * (over + k) ** 2 / (4 * k + 1e-9)))
    fast = smooth(gr, attack)
    slow = smooth(gr, release)
    g = db2lin(np.minimum(fast, slow) + makeup_db)
    return x * g


def limiter(x: np.ndarray, ceiling_db: float = -1.0, lookahead: float = 0.004,
            release: float = 0.08) -> np.ndarray:
    """Offline look-ahead brick-wall limiter (no overs by construction)."""
    c = db2lin(ceiling_db)
    pk = _detector(x)
    g_req = np.minimum(1.0, c / np.maximum(pk, 1e-12))
    L = max(2, ns(lookahead))
    # min over [n, n+L-1]
    g_la = ndimage.minimum_filter1d(g_req, size=L, origin=-(L // 2), mode="nearest")
    # causal box average over [n-L+1, n]
    ker = np.ones(L) / L
    g_av = np.convolve(g_la, ker)[:len(g_la)]
    g_av[:L] = np.minimum(g_av[:L], g_la[:L])
    g_rel = smooth(g_av, release)
    g = np.minimum(g_av, g_rel)
    return x * g


def normalize_peak(x: np.ndarray, peak_db: float) -> np.ndarray:
    p = peak(x)
    return x * (db2lin(peak_db) / p) if p > 0 else x


# --------------------------------------------------------------------------
# loudness (ITU-R BS.1770-4)
# --------------------------------------------------------------------------
def _k_weight(x: np.ndarray) -> np.ndarray:
    G, Q, fc = 3.999843853973347, 0.7071752369554196, 1681.974450955533
    b1, a1 = rbj("highshelf", fc, Q, G)
    b2, a2 = rbj("hp", 38.13547087602444, 0.5003270373238773)
    y = sps.lfilter(b1, a1, x, axis=-1)
    return sps.lfilter(b2, a2, y, axis=-1)


def loudness(x: np.ndarray) -> dict:
    """Integrated loudness (LUFS), max short-term (3 s) and max momentary."""
    xs = x if x.ndim == 2 else x[None, :]
    y = _k_weight(xs)
    sq = np.sum(y ** 2, axis=0)  # sum over channels (G = 1 for L/R)

    def blocks(win_s, hop_s):
        w, h = ns(win_s), ns(hop_s)
        if len(sq) < w:
            return np.array([np.mean(sq)])
        cs = np.concatenate(([0.0], np.cumsum(sq)))
        starts = np.arange(0, len(sq) - w + 1, h)
        return (cs[starts + w] - cs[starts]) / w

    def to_lufs(p):
        return -0.691 + 10 * np.log10(np.maximum(p, 1e-12))

    mom = blocks(0.4, 0.1)
    lm = to_lufs(mom)
    gated = mom[lm > -70]
    if len(gated) == 0:
        integ = -70.0
    else:
        rel = to_lufs(np.mean(gated)) - 10.0
        g2 = mom[(lm > -70) & (lm > rel)]
        integ = float(to_lufs(np.mean(g2))) if len(g2) else -70.0
    st = blocks(3.0, 0.1)
    return {"integrated": integ, "momentary_max": float(np.max(lm)),
            "short_term_max": float(np.max(to_lufs(st)))}


def true_peak_db(x: np.ndarray) -> float:
    xs = x if x.ndim == 2 else x[None, :]
    up = sps.resample_poly(xs, 4, 1, axis=-1)
    return float(lin2db(np.max(np.abs(up))))


# --------------------------------------------------------------------------
# looping helpers
# --------------------------------------------------------------------------
def wrap_tail(x: np.ndarray, n_loop: int) -> np.ndarray:
    """Fold everything after n_loop samples back onto the start."""
    out = np.array(x[..., :n_loop], copy=True)
    tail = x[..., n_loop:]
    pos = 0
    while tail.shape[-1] > 0:
        k = min(n_loop, tail.shape[-1])
        out[..., :k] += tail[..., :k]
        tail = tail[..., k:]
        pos += k
    return out


def loop_crossfade(x: np.ndarray, n_loop: int, xfade: int) -> np.ndarray:
    """x has n_loop + xfade samples of continuous material; blend the last
    xfade samples into the start with an equal-power fade -> seamless loop."""
    assert x.shape[-1] >= n_loop + xfade
    out = np.array(x[..., :n_loop], copy=True)
    th = np.linspace(0, np.pi / 2, xfade)
    fin, fout = np.sin(th), np.cos(th)
    out[..., :xfade] = x[..., :xfade] * fin + x[..., n_loop:n_loop + xfade] * fout
    return out


def process_circular(x: np.ndarray, fn, pad_s: float = 3.0) -> np.ndarray:
    """Run a stateful processor on a loop so the seam sees steady state."""
    n = x.shape[-1]
    p = min(ns(pad_s), n)
    ext = np.concatenate([x[..., n - p:], x, x[..., :p]], axis=-1)
    y = fn(ext)
    return y[..., p:p + n]


# --------------------------------------------------------------------------
# file I/O
# --------------------------------------------------------------------------
def to_int16(x: np.ndarray, seed: int = 0) -> np.ndarray:
    rng = np.random.default_rng(seed)
    d = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0  # TPDF dither
    y = np.round((np.clip(x, -1.0, 1.0) + d) * 32767.0)
    return np.clip(y, -32768, 32767).astype("<i2")


def write_wav(path: str, x: np.ndarray, loop: bool = False, seed: int = 0) -> None:
    """16-bit PCM WAV (mono or stereo). loop=True adds a 'smpl' chunk with a
    forward loop over the whole file (Godot imports it as a loop)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    xs = x if x.ndim == 2 else x[None, :]
    ch, n = xs.shape
    data = to_int16(xs.T.reshape(-1), seed).tobytes()
    fmt = struct.pack("<HHIIHH", 1, ch, SR, SR * 2 * ch, 2 * ch, 16)
    chunks = [b"fmt " + struct.pack("<I", len(fmt)) + fmt]
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / SR), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n, 0, 0)
        chunks.append(b"smpl" + struct.pack("<I", len(smpl)) + smpl)
    chunks.append(b"data" + struct.pack("<I", len(data)) + data)
    body = b"WAVE" + b"".join(chunks)
    with open(path, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def write_ogg(path: str, x: np.ndarray, quality: float = 5.0, loop: bool = False,
              title: str = "") -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    xs = to_stereo(x)
    raw = np.ascontiguousarray(np.clip(xs, -1, 1).T.astype("<f4")).tobytes()
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
           "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "pipe:0",
           "-c:a", "libvorbis", "-q:a", str(quality),
           "-fflags", "+bitexact", "-flags:a", "+bitexact",  # fixed Ogg serial -> reproducible files
           "-metadata", f"title={title}", "-metadata", "artist=Baseball Draw (procedural)"]
    if loop:
        cmd += ["-metadata", "LOOPSTART=0", "-metadata", f"LOOPLENGTH={xs.shape[-1]}"]
    cmd += [path]
    subprocess.run(cmd, input=raw, check=True)


def read_audio(path: str) -> np.ndarray:
    """Decode any file with ffmpeg -> float array (channels, n)."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=channels", "-of", "csv=p=0", path], capture_output=True, text=True, check=True)
    ch = int(probe.stdout.strip().split(",")[0])
    out = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", path,
                          "-f", "f32le", "-ar", str(SR), "-"], capture_output=True, check=True)
    a = np.frombuffer(out.stdout, dtype="<f4").astype(float)
    return a.reshape(-1, ch).T
