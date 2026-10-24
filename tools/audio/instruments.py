"""Synth instruments used by the music and some SFX.

Every function returns a mono float array (unnormalised but roughly in the
-1..1 range for vel = 1).  Durations are in seconds; the returned buffer
includes the release tail.
"""
from __future__ import annotations

import numpy as np

from dsp import (SR, TWO_PI, adsr, bp, butter, fade, filt, fm, hp, lp, mtof, ns,
                 partials, peq, perc, saturate, saw, sine, square, tarr, tvfilt,
                 white)


# ==========================================================================
# drums (one-shots, rendered once per kit and re-used)
# ==========================================================================
def kick(rng, f0=165.0, f1=47.0, pitch_tau=0.032, decay=0.32, click=0.6,
         drive=1.8, length=0.7, sub=0.0):
    n = ns(length)
    t = tarr(n)
    f = f1 + (f0 - f1) * np.exp(-t / pitch_tau)
    amp = np.where(t < 0.015, 1.0, np.exp(-(t - 0.015) / decay))
    body = sine(f, n) * amp
    if sub:
        body += sub * sine(f1 * 0.999, n) * np.exp(-t / (decay * 1.6)) * (1 - np.exp(-t / 0.01))
    cn = ns(0.006)
    cl = np.zeros(n)
    cl[:cn] = bp(white(cn, rng), 3200, 0.7) * np.linspace(1, 0, cn) ** 2
    cl += 0.5 * sine(1800 * np.exp(-t / 0.004) + 600, n) * np.exp(-t / 0.003)
    x = body + click * cl
    x = np.tanh(drive * x) / np.tanh(drive)
    return fade(x, 0.0005, 0.03)


def snare(rng, tone_f=190.0, decay_tone=0.075, decay_noise=0.17, snappy=0.8,
          length=0.55, bright=1.0):
    n = ns(length)
    t = tarr(n)
    f = tone_f * (1 + 0.25 * np.exp(-t / 0.012))
    tone = (sine(f, n) + 0.55 * sine(f * 1.62, n)) * np.exp(-t / decay_tone)
    nz = white(n, rng)
    nz = filt(nz, "hp", 900, 0.6, order=2)
    nz = lp(nz, 7500 * bright)
    nz = peq(nz, 3800, 3.0, 0.8)
    nz *= np.exp(-t / decay_noise) * (1 - np.exp(-t / 0.0015))
    crack = bp(white(n, rng), 2500, 0.5) * np.exp(-t / 0.006)
    x = 0.9 * tone + snappy * 0.55 * nz + 0.4 * crack
    x = np.tanh(1.5 * x)
    return fade(x, 0.0005, 0.05)


def clap(rng, length=0.45, tail=0.11, f=1250.0):
    n = ns(length)
    t = tarr(n)
    env = np.zeros(n)
    offs = [0.0, 0.009, 0.019, 0.028]
    for i, o in enumerate(offs):
        tt = t - o
        env += np.where(tt >= 0, np.exp(-np.maximum(tt, 0) / 0.0045), 0.0) * (0.8 + 0.2 * i / 3)
    tt = t - offs[-1]
    env += np.where(tt >= 0, 0.7 * np.exp(-np.maximum(tt, 0) / tail), 0.0)
    nz = white(n, rng)
    x = bp(nz, f, 0.9) * 1.6 + 0.4 * hp(nz, 2500)
    x = hp(x, 500) * env
    return fade(x, 0.0003, 0.05)


_METAL = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


def hat(rng, open_=False, decay=None, tone=1.0):
    length = 0.9 if open_ else 0.18
    n = ns(length)
    t = tarr(n)
    metal = sum(square(f * 1.0 * tone, n, 0.5, rng.random()) for f in _METAL)
    metal = filt(metal, "bp", 8500, 0.9)
    metal = filt(metal, "hp", 6200, 0.7, order=2)
    nz = filt(white(n, rng), "hp", 7000, 0.7, order=2)
    x = 0.5 * metal / 3.0 + 0.5 * nz
    x = lp(x, 12000)
    dec = decay or (0.16 if open_ else 0.022)
    env = (1 - np.exp(-t / 0.0007)) * np.exp(-t / dec)
    return fade(x * env, 0.0002, 0.03)


def shaker(rng, length=0.12):
    n = ns(length)
    t = tarr(n)
    nz = filt(white(n, rng), "hp", 5000, 0.7, order=2)
    nz = lp(nz, 11000)
    env = np.sin(np.pi * np.clip(t / length, 0, 1)) ** 2.5
    env = env * np.exp(-t / 0.05)
    return fade(nz * env, 0.0, 0.01)


def crash(rng, decay=1.6, length=2.6, bright=1.0):
    n = ns(length)
    t = tarr(n)
    freqs = rng.uniform(280, 1300, 14)
    metal = sum(square(f, n, rng.uniform(0.3, 0.7), rng.random()) for f in freqs) / 6
    metal = filt(metal, "hp", 3000, 0.7, order=2)
    nz = filt(white(n, rng), "hp", 3500, 0.7, order=2)
    x = 0.5 * metal + 0.6 * nz
    x = lp(x, 11000 * bright)
    x = peq(x, 5500, 3, 0.7)
    body = bp(white(n, rng), 700, 1.2) * np.exp(-t / 0.08)
    env = (1 - np.exp(-t / 0.001)) * (0.45 * np.exp(-t / 0.08) + 0.55 * np.exp(-t / decay))
    return fade(x * env + 0.3 * body, 0.0002, 0.2)


def ride(rng, length=1.4):
    n = ns(length)
    t = tarr(n)
    bell = partials(1.0, n, [(520, 0.6, 0.6), (1270, 0.4, 0.5), (2490, 0.3, 0.4),
                             (3410, 0.25, 0.3), (5120, 0.2, 0.25)], rng)
    nz = filt(white(n, rng), "hp", 4500, 0.7, order=2)
    x = 0.35 * bell + 0.5 * nz * np.exp(-t / 0.35)
    env = (1 - np.exp(-t / 0.0007)) * (0.5 * np.exp(-t / 0.05) + 0.5 * np.exp(-t / 0.7))
    return fade(lp(x * env, 12000), 0.0, 0.1)


def tom(rng, f=110.0, decay=0.32, length=0.8):
    n = ns(length)
    t = tarr(n)
    fr = f * (1 + 0.55 * np.exp(-t / 0.05))
    body = sine(fr, n) + 0.3 * sine(fr * 1.5, n) * np.exp(-t / 0.08)
    body *= np.exp(-t / decay)
    stick = bp(white(n, rng), f * 4, 1.0) * np.exp(-t / 0.012)
    x = np.tanh(1.4 * (body + 0.5 * stick))
    return fade(x, 0.0005, 0.06)


def taiko(rng, f=62.0, decay=0.65, length=1.8):
    n = ns(length)
    t = tarr(n)
    fr = f * (1 + 0.35 * np.exp(-t / 0.04))
    body = (sine(fr, n) + 0.35 * sine(fr * 1.58, n) * np.exp(-t / 0.25)
            + 0.2 * sine(fr * 2.13, n) * np.exp(-t / 0.15))
    body *= np.exp(-t / decay) * (1 - np.exp(-t / 0.002))
    skin = lp(white(n, rng), 1600) * np.exp(-t / 0.03)
    x = np.tanh(1.6 * (body + 0.45 * skin))
    return fade(x, 0.0005, 0.1)


def rim(rng, length=0.12):
    n = ns(length)
    t = tarr(n)
    x = (sine(820, n) * np.exp(-t / 0.012) + 0.8 * bp(white(n, rng), 1700, 3) * np.exp(-t / 0.01)
         + 0.4 * sine(2300, n) * np.exp(-t / 0.004))
    return fade(x, 0.0002, 0.02)


def snap(rng, length=0.15):
    n = ns(length)
    t = tarr(n)
    x = bp(white(n, rng), 2400, 1.5) * np.exp(-t / 0.012) * (1 - np.exp(-t / 0.0006))
    x += 0.3 * bp(white(n, rng), 1100, 2) * np.exp(-t / 0.02)
    return fade(x * 2.0, 0.0, 0.02)


def stomp(rng, length=0.6):
    """Bleacher stomp: low thud with wooden body."""
    n = ns(length)
    t = tarr(n)
    thud = sine(70 * (1 + 0.8 * np.exp(-t / 0.03)), n) * np.exp(-t / 0.13)
    wood = bp(white(n, rng), 230, 1.5) * np.exp(-t / 0.07)
    wood2 = bp(white(n, rng), 600, 2.0) * np.exp(-t / 0.03)
    x = np.tanh(1.8 * (thud + 1.2 * wood + 0.6 * wood2))
    return fade(x, 0.0005, 0.05)


def timpani(rng, midi, vel=1.0, length=2.2):
    f = mtof(midi)
    n = ns(length)
    t = tarr(n)
    spec = [(1.0, 1.0, 1.4), (1.504, 0.55, 0.9), (1.742, 0.3, 0.7), (2.0, 0.32, 0.6),
            (2.245, 0.18, 0.5), (2.494, 0.14, 0.42), (2.8, 0.08, 0.35)]
    x = np.zeros(n)
    bend = 1 + 0.015 * np.exp(-t / 0.05)
    for r, a, d in spec:
        x += a * np.exp(-t / d) * sine(f * r * bend, n, rng.random())
    x += 0.5 * lp(white(n, rng), 500) * np.exp(-t / 0.025)
    x *= (1 - np.exp(-t / 0.002))
    return fade(np.tanh(1.2 * x * vel), 0.0, 0.15)


# ==========================================================================
# pitched instruments
# ==========================================================================
def _gate_n(dur, rel):
    return ns(dur + rel)


def bass_synth(midi, dur, vel=1.0, rng=None, cutoff=5.0, decay_f=0.14, q=1.1,
               drive=2.0, sub=0.6, detune=0.004, rel=0.05, base=1.4):
    """Gritty analog-style synth bass."""
    f = mtof(midi)
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    osc = 0.5 * saw(f * (1 + detune), n, 0.1) + 0.5 * saw(f * (1 - detune), n, 0.6)
    osc += sub * sine(f, n)
    cut = f * base + f * cutoff * vel * np.exp(-t / decay_f) + 60
    y = tvfilt(osc, "lp", np.minimum(cut, 9000), q)
    env = adsr(n, 0.003, 0.25, 0.75, rel, dur)
    y = saturate(y * env * vel, drive)
    return fade(y, 0.001, 0.01)


def bass_finger(midi, dur, vel=1.0, rng=None, bright=1.0, pluck_pos=0.18, rel=0.06,
                tau=1.4):
    """Additive plucked electric bass (fingerstyle)."""
    f = mtof(midi)
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    K = int(min(28, 4500 / f))
    y = np.zeros(n)
    B = 0.00012
    for k in range(1, K + 1):
        fk = f * k * np.sqrt(1 + B * k * k)
        a = abs(np.sin(np.pi * k * pluck_pos)) / k ** 1.05
        dk = 1.0 / (1.0 / tau + 0.9 * (k - 1) * (1.4 - 0.5 * bright))
        y += a * np.exp(-t / dk) * np.sin(TWO_PI * fk * t + 0.3 * k)
    y *= (1 - np.exp(-t / 0.0025))
    gate = np.where(t < dur, 1.0, np.exp(-(t - dur) / rel))
    y *= gate
    thump = lp(white(n, rng or np.random.default_rng(1)), 900) * np.exp(-t / 0.01) * 0.25
    y = saturate((y + thump) * vel * 0.8, 1.5)
    return fade(y, 0.0005, 0.01)


def bass_sub(midi, dur, vel=1.0, rng=None, rel=0.12):
    f = mtof(midi)
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    y = sine(f, n) + 0.18 * sine(2 * f, n) + 0.05 * sine(3 * f, n)
    env = adsr(n, 0.012, 0.6, 0.85, rel, dur)
    return fade(saturate(y * env * vel, 1.2), 0.001, 0.01)


DRAWBARS = [0.5, 1.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0]


def organ(midi, dur, vel=1.0, rng=None, drawbars="888600004", perc_amt=0.0,
          click=0.25, rel=0.03):
    """Tonewheel-style additive organ (apply leslie on the bus)."""
    rng = rng or np.random.default_rng(int(midi))
    f = mtof(midi)
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    y = np.zeros(n)
    for r, lvl in zip(DRAWBARS, drawbars):
        v = int(lvl)
        if v == 0:
            continue
        fr = f * r
        while fr > 6500:
            fr *= 0.5  # foldback like a real tonewheel generator
        amp = 10 ** (-(8 - v) * 3.0 / 20.0)
        y += amp * np.sin(TWO_PI * fr * t + TWO_PI * rng.random())
    if perc_amt:
        y += perc_amt * np.sin(TWO_PI * f * 3 * t) * np.exp(-t / 0.22)
    env = np.clip(t / 0.004, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / rel))
    y *= env
    if click:
        cn = ns(0.004)
        y[:cn] += click * bp(white(cn, rng), 2500, 0.8) * np.linspace(1, 0, cn)
    return fade(y * vel * 0.33, 0.0005, 0.01)


def brass(midi, dur, vel=1.0, rng=None, bright=1.0, attack=0.045, rel=0.12,
          detune=3.5, vib=1.0, scoop=25.0, growl=0.0, q=0.8):
    """Analog brass section voice (filter swell + scoop + delayed vibrato)."""
    rng = rng or np.random.default_rng(int(midi))
    f = mtof(midi)
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    vdepth = vib * 10.0 * np.clip((t - 0.22) / 0.4, 0, 1)
    cents = -scoop * np.exp(-t / 0.035) + vdepth * np.sin(TWO_PI * 5.3 * t + rng.random() * 6)
    fr = f * 2 ** (cents / 1200.0)
    d1 = detune * rng.uniform(0.8, 1.2)
    d2 = -detune * rng.uniform(0.8, 1.2)
    osc = (saw(fr * 2 ** (d1 / 1200), n, rng.random())
           + saw(fr * 2 ** (d2 / 1200), n, rng.random())
           + 1.0 * saw(fr, n, rng.random()))
    fenv = adsr(n, attack * 1.4, 0.35, 0.62, rel * 0.8, dur)
    cut = f * 1.1 + (f * 6.0 + 700.0) * bright * vel * fenv
    cut = np.minimum(cut, 7500)
    y = tvfilt(osc, "lp", cut, q)
    y = tvfilt(y, "lp", cut * 1.6, 0.6)
    if growl:
        y *= 1 + growl * np.sin(TWO_PI * 32 * t) * np.exp(-t / 0.3)
        y = saturate(y, 1.0 + 3 * growl)
    env = adsr(n, attack, 0.3, 0.85, rel, dur)
    return fade(y * env * vel * 0.4, 0.001, 0.01)


def epiano(midi, dur, vel=0.8, rng=None, rel=0.09, bell=1.0):
    """FM electric piano (tine-style)."""
    f = mtof(midi)
    n = _gate_n(min(dur, 6.0), rel * 6)
    t = tarr(n)
    tau = 1.7 * (261.6 / f) ** 0.35
    idx = (0.6 + 1.5 * vel) * np.exp(-t / 0.35) + 0.2
    body = fm(f, 1.0, idx, n)
    tine = np.zeros(n)
    if f * 14 < 16000:
        tine = fm(f, 14.0, 1.2 * np.exp(-t / 0.018), n) * np.exp(-t / 0.12) * 0.28 * vel * bell
    amp = (1 - np.exp(-t / 0.0015)) * np.exp(-t / tau)
    gate = np.where(t < dur, 1.0, np.exp(-(t - dur) / rel))
    y = (body + tine) * amp * gate
    y = saturate(y * (0.5 + 0.5 * vel), 1.3)
    return fade(y * 0.6, 0.0005, 0.01)


def pad(midi, dur, vel=0.7, rng=None, attack=0.5, rel=1.0, voices=5, detune=12.0,
        cutoff=2400.0, vib=0.0):
    rng = rng or np.random.default_rng(int(midi))
    f = mtof(midi)
    n = _gate_n(dur, rel * 4)
    t = tarr(n)
    y = np.zeros(n)
    fv = f * (1 + vib * 0.003 * np.sin(TWO_PI * 5.0 * t))
    for i in range(voices):
        d = (i / max(1, voices - 1) - 0.5) * 2 * detune
        y += saw(fv * 2 ** (d / 1200), n, rng.random())
    y /= np.sqrt(voices)
    y = filt(y, "lp", min(cutoff, f * 10), 0.6, order=2)
    env = adsr(n, attack, 0.8, 0.8, rel, dur, curve=1.5)
    return fade(y * env * vel * 0.35, 0.002, 0.02)


def strings(midi, dur, vel=0.7, rng=None, attack=0.18, rel=0.5, cutoff=3800.0):
    rng = rng or np.random.default_rng(int(midi) + 3)
    f = mtof(midi)
    n = _gate_n(dur, rel * 4)
    t = tarr(n)
    y = np.zeros(n)
    for i in range(7):
        d = (i / 6 - 0.5) * 16 + rng.uniform(-2.5, 2.5)
        vib = 1 + 0.0035 * np.sin(TWO_PI * (5.2 + 0.3 * i) * t + rng.random() * 6)
        y += saw(f * 2 ** (d / 1200) * vib, n, rng.random())
    y /= np.sqrt(7)
    y = filt(y, "lp", min(cutoff, f * 12), 0.6, order=2)
    y = peq(y, 1600, 3, 1.0)
    y = hp(y, 180)
    env = adsr(n, attack, 0.6, 0.85, rel, dur, curve=1.3)
    return fade(y * env * vel * 0.33, 0.002, 0.02)


def lead(midi, dur, vel=0.9, rng=None, glide_from=None, glide=0.05, cutoff=3200.0,
         pw=0.42, vib=1.0, rel=0.07, saw_mix=0.55):
    rng = rng or np.random.default_rng(int(midi) + 11)
    f = mtof(midi)
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    if glide_from is not None:
        f0 = mtof(glide_from)
        fr = f + (f0 - f) * np.exp(-t / glide)
    else:
        fr = np.full(n, f)
    vd = vib * 14 * np.clip((t - 0.18) / 0.3, 0, 1)
    fr = fr * 2 ** (vd * np.sin(TWO_PI * 5.6 * t) / 1200)
    osc = (1 - saw_mix) * square(fr, n, pw, rng.random()) + saw_mix * saw(fr * 1.0018, n, rng.random())
    cut = cutoff * (1 + 1.2 * np.exp(-t / 0.09))
    y = tvfilt(osc, "lp", np.minimum(cut, 9000), 0.9)
    env = adsr(n, 0.006, 0.18, 0.8, rel, dur)
    return fade(y * env * vel * 0.4, 0.001, 0.01)


def pluck(midi, dur, vel=0.8, rng=None, bright=1.0, decay=0.22, rel=0.05):
    rng = rng or np.random.default_rng(int(midi) + 21)
    f = mtof(midi)
    n = _gate_n(dur, rel * 5 + decay)
    t = tarr(n)
    osc = saw(f, n, rng.random()) + 0.45 * square(f * 1.003, n, 0.3, rng.random())
    cut = f * 1.2 + 4500 * bright * vel * np.exp(-t / 0.07)
    y = tvfilt(osc, "lp", np.minimum(cut, 9000), 1.1)
    env = (1 - np.exp(-t / 0.0015)) * np.exp(-t / decay)
    env *= np.where(t < dur, 1.0, np.exp(-(t - dur) / rel))
    return fade(y * env * vel * 0.4, 0.0005, 0.01)


def power_chord(midi, dur, vel=1.0, rng=None, mute=False, drive=9.0, fifth=True,
                octave=True, rel=0.05):
    """Synthesised distorted electric guitar power chord."""
    rng = rng or np.random.default_rng(int(midi) + 31)
    notes = [midi] + ([midi + 7] if fifth else []) + ([midi + 12] if octave else [])
    n = _gate_n(dur, rel * 5)
    t = tarr(n)
    x = np.zeros(n)
    for m in notes:
        f = mtof(m)
        for d in (-0.0025, 0.0028):
            x += saw(f * (1 + d + rng.uniform(-0.0006, 0.0006)), n, rng.random())
    x = hp(x, 90)
    if mute:
        x = tvfilt(x, "lp", 350 + 1800 * np.exp(-t / 0.05), 0.8)
    else:
        x = lp(x, 3200)
    x = np.tanh(drive * x * 0.35)
    # cabinet
    x = filt(x, "lp", 4200, 0.7, order=2)
    x = peq(x, 1900, 4.0, 1.2)
    x = peq(x, 420, -4.0, 1.0)
    x = peq(x, 110, 2.5, 0.9)
    x = hp(x, 75)
    sus = np.exp(-t / (0.11 if mute else 2.2))
    env = (1 - np.exp(-t / 0.002)) * sus * np.where(t < dur, 1.0, np.exp(-(t - dur) / rel))
    return fade(x * env * vel * 0.5, 0.0005, 0.01)


GLOCK = [(1.0, 1.0, 0.9), (2.76, 0.32, 0.35), (5.40, 0.12, 0.15), (8.93, 0.05, 0.07)]
CHIME = [(1.0, 1.0, 1.4), (2.0, 0.35, 0.8), (3.0, 0.2, 0.5), (4.16, 0.12, 0.35), (5.43, 0.08, 0.2)]
MARIMBA = [(1.0, 1.0, 0.45), (3.93, 0.22, 0.12), (9.2, 0.05, 0.04)]


def bell(midi, dur=1.0, vel=0.8, rng=None, kind="glock", decay_scale=1.0):
    rng = rng or np.random.default_rng(int(midi) + 41)
    f = mtof(midi)
    spec = {"glock": GLOCK, "chime": CHIME, "marimba": MARIMBA}[kind]
    spec = [(r, a, d * decay_scale) for r, a, d in spec]
    n = ns(max(dur, max(d for _, _, d in spec) * 5))
    t = tarr(n)
    y = partials(f, n, spec, rng)
    if kind == "marimba":
        y += 0.15 * lp(white(n, rng), 2000) * np.exp(-t / 0.004)
    else:
        y += 0.05 * hp(white(n, rng), 3000) * np.exp(-t / 0.002)
    y *= 1 - np.exp(-t / 0.0008)
    return fade(y * vel * 0.4, 0.0, 0.05)


def fm_bell(midi, dur=1.5, vel=0.8, rng=None, ratio=3.5, index=2.5, decay=0.9):
    f = mtof(midi)
    n = ns(dur)
    t = tarr(n)
    y = fm(f, ratio, index * np.exp(-t / (decay * 0.4)), n)
    y += 0.4 * fm(f * 2.0, 1.41, 1.0 * np.exp(-t / 0.2), n) * np.exp(-t / (decay * 0.5))
    y *= (1 - np.exp(-t / 0.001)) * np.exp(-t / decay)
    return fade(y * vel * 0.35, 0.0, 0.05)


FORMANTS = {
    "a": [(800, 1.0, 80), (1150, 0.5, 90), (2900, 0.1, 120), (3900, 0.05, 130)],
    "o": [(450, 1.0, 70), (800, 0.35, 80), (2830, 0.05, 100), (3800, 0.02, 120)],
    "u": [(325, 1.0, 50), (700, 0.25, 60), (2530, 0.03, 120), (3500, 0.01, 120)],
    "e": [(400, 1.0, 60), (1700, 0.3, 80), (2600, 0.15, 120), (3600, 0.05, 130)],
    "i": [(290, 1.0, 50), (2100, 0.25, 90), (2900, 0.18, 110), (3700, 0.05, 130)],
    "ae": [(660, 1.0, 80), (1700, 0.4, 90), (2400, 0.15, 120), (3700, 0.05, 130)],
    "ah": [(700, 1.0, 110), (1220, 0.45, 120), (2600, 0.12, 140), (3700, 0.04, 150)],
}


def formant_filter(src, vowel="a", shift=1.0):
    """Parallel formant bank (bandwidths widened for a fuller, less whistly
    vowel) plus a little of the low-passed source for chest/body."""
    y = 0.25 * lp(src, 700)
    for fq, amp, bw in FORMANTS[vowel]:
        fq = fq * shift
        y += amp * bp(src, fq, fq / (bw * 1.8))
    return y


def voice_src(freq, n, rng, breath=0.08):
    s = saw(freq, n, rng.random())
    s = lp(s, 1800)  # glottal roll-off
    s += breath * hp(white(n, rng), 1500)
    return s


def choir(midi, dur, vel=0.7, rng=None, vowel="a", voices=4, attack=0.35, rel=0.6):
    rng = rng or np.random.default_rng(int(midi) + 51)
    f = mtof(midi)
    n = _gate_n(dur, rel * 4)
    t = tarr(n)
    y = np.zeros(n)
    shift = 1.0 if midi < 60 else 1.08
    for _ in range(voices):
        det = 2 ** (rng.uniform(-9, 9) / 1200)
        vib = 1 + 0.004 * np.sin(TWO_PI * rng.uniform(4.6, 5.8) * t + rng.random() * 6)
        src = voice_src(f * det * vib, n, rng)
        y += formant_filter(src, vowel, shift)
    y /= np.sqrt(voices)
    env = adsr(n, attack, 0.8, 0.9, rel, dur, curve=1.5)
    return fade(y * env * vel * 1.1, 0.003, 0.02)
