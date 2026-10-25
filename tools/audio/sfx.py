"""All sound effects.  Each generator takes a numpy Generator and returns a
mono float signal; `finish()` handles DC, fades, soft limiting and peak level.

SFX registry at the bottom: name -> (generator, peak_dbfs, volume_db, loop).
"""
from __future__ import annotations

import numpy as np

import instruments as ins
from crowd import claps, crowd_burst
from dsp import (SR, TWO_PI, bp, brown, butter, colored, db2lin, fade, fft_shape,
                 filt, fm, hp, limiter, linseg, lp, mix, make_ir, mtof, note, normalize_peak,
                 ns, partials, peak, peq, perc, pink, place, reverb, saturate, saw,
                 sine, smooth, square, tarr, triangle, tvfilt, white)

# shared impulse responses (deterministic)
ROOM = make_ir(0.35, 0.004, 0.5, 1.0, 0.5, seed=11)
HALL = make_ir(1.3, 0.012, 0.45, 1.1, 0.3, seed=12)
STADIUM = make_ir(2.2, 0.035, 0.35, 1.15, 0.25, seed=13)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def buf(seconds):
    return np.zeros(ns(seconds))


def at(b, x, t, gain=1.0):
    """Mix x into b at time t (s); a short fade-out (15 % of the item, <= 60 ms)
    guards against clicks from truncated decays."""
    place(b, fade(x, 0.0, min(0.06, 0.15 * len(x) / SR)), ns(t) if t > 0 else 0, gain)
    return b


def wet(x, ir, amount, tail=None):
    """Mono reverb mix (uses left channel of the IR)."""
    r = reverb(x, ir)[0]
    n = len(x) if tail is None else len(x) + ns(tail)
    out = np.zeros(n)
    out[:len(x)] += x
    out += amount * r[:n] if len(r) >= n else np.pad(amount * r, (0, n - len(r)))
    return out


def bump(n, peak_pos=0.4, power=1.0):
    u = np.linspace(0, 1, n)
    a = np.log(0.5) / np.log(peak_pos)
    return np.sin(np.pi * u ** a) ** power


def whoosh(rng, dur, f_lo, f_hi, peak_pos=0.4, q=1.4, body=0.5, power=1.6, tilt=-2.0):
    n = ns(dur)
    b = bump(n, peak_pos, 1.0)
    fc = f_lo * (f_hi / f_lo) ** b
    nz = colored(n, rng, tilt)
    y = tvfilt(nz, "bp", fc, q) + body * tvfilt(nz, "lp", fc * 0.7, 0.7)
    return y * b ** power


def thump(dur, f0, f1, tau_p, decay, hold=0.0):
    n = ns(dur)
    t = tarr(n)
    f = f1 + (f0 - f1) * np.exp(-t / tau_p)
    a = np.exp(-np.maximum(t - hold, 0) / decay)
    return fade(sine(f, n) * a, 0.0, min(0.03, dur * 0.3))


def noise_hit(rng, dur, f, q, decay, kind="bp"):
    n = ns(dur)
    t = tarr(n)
    x = filt(white(n, rng), kind, f, q)
    return fade(x * np.exp(-t / decay) * (1 - np.exp(-t / 0.0004)), 0.0, min(0.02, dur * 0.3))


def grains(rng, total, times, f_lo, f_hi, d_lo, d_hi, q_lo=1.5, q_hi=4.0, amps=None):
    out = buf(total)
    for i, tt in enumerate(times):
        d = rng.uniform(d_lo, d_hi)
        m = ns(d)
        g = white(m, rng)
        fc = np.exp(rng.uniform(np.log(f_lo), np.log(f_hi)))
        g = bp(g, fc, rng.uniform(q_lo, q_hi)) * perc(m, 0.0005, d / 4)
        a = amps[i] if amps is not None else 1.0
        place(out, g * a, ns(tt))
    return out


def tone(midi_or_f, dur, kind="sine", decay=None, attack=0.003, release=0.02, is_f=False):
    f = midi_or_f if is_f else mtof(midi_or_f)
    n = ns(dur)
    t = tarr(n)
    if kind == "sine":
        x = sine(f, n)
    elif kind == "tri":
        x = triangle(f, n)
    elif kind == "square":
        x = square(f, n)
    else:
        x = saw(f, n)
    env = np.clip(t / attack, 0, 1)
    if decay:
        env *= np.exp(-t / decay)
    return fade(x * env, 0.0, release)


def trim(x, thresh_db=-62.0, margin=0.01):
    p = peak(x)
    if p == 0:
        return x
    idx = np.nonzero(np.abs(x) > p * db2lin(thresh_db))[0]
    end = min(len(x), idx[-1] + ns(margin)) if len(idx) else len(x)
    return x[:end]


def finish(x, peak_db=-3.0, fin=0.001, fout=0.02, shave_db=1.5, hpf=30.0, do_trim=True):
    x = np.asarray(x, float)
    x = filt(x, "hp", hpf, 0.7071, order=2)
    if do_trim:
        x = trim(x)
    x = fade(x, fin, fout)
    if shave_db > 0:
        # soft-knee peak shaving: only the top few dB of the transients are rounded
        x = soft_knee(normalize_peak(x, shave_db), 0.6)
    x = fade(x, fin, fout)
    return normalize_peak(x, peak_db)


def soft_knee(x, k=0.6):
    a = np.abs(x)
    y = np.where(a <= k, a, k + (1 - k) * np.tanh((a - k) / (1 - k)))
    return np.sign(x) * y


# ---------------------------------------------------------------------------
# combat
# ---------------------------------------------------------------------------
def throw(rng, v):
    dur = [0.19, 0.23, 0.27][v]
    lo, hi = [(520, 2400), (450, 2100), (600, 2800)][v]
    x = whoosh(rng, dur, lo, hi, [0.33, 0.38, 0.42][v], q=1.7, body=0.35, power=1.4)
    x += 0.5 * whoosh(rng, dur, lo * 0.45, hi * 0.4, 0.4, q=1.0, body=0.6, power=1.6)
    # faint seam whistle following the doppler sweep
    n = len(x)
    b = bump(n, [0.33, 0.38, 0.42][v])
    whistle = sine(900 * (1.6 ** b), n) * b ** 3 * 0.02
    x = lp(x + whistle * peak(x), 6500)
    return finish(x, -3.0, 0.002, 0.03, shave_db=1.0)


def ball_hit(rng, v):
    """Punchy body thud: short pitched thump (~100-180 Hz), textured mid
    'thwack', leathery smack and a tiny click.  Kept < 0.25 s."""
    pf = [1.0, 0.88, 1.12][v]
    b = buf(0.24)
    at(b, thump(0.2, 185 * pf, 92 * pf, 0.014, [0.045, 0.055, 0.04][v]), 0, 0.9)
    at(b, thump(0.12, 70 * pf, 55 * pf, 0.02, 0.03), 0, 0.35)
    at(b, noise_hit(rng, 0.14, 320 * pf, 1.0, 0.035), 0, 0.9)
    at(b, noise_hit(rng, 0.08, [1800, 1500, 2200][v], 0.9, 0.011), 0, 0.75)
    at(b, noise_hit(rng, 0.03, 3500, 0.7, 0.002, "hp"), 0, 0.3)
    x = saturate(b, 2.5)
    x = wet(x, ROOM, 0.1)
    x = lp(x, 7000)
    return finish(x, -3.0, 0.0003, 0.03, shave_db=2.5)


def crit_hit(rng):
    b = buf(0.9)
    at(b, thump(0.4, 165, 70, 0.02, 0.11), 0, 1.0)
    at(b, thump(0.3, 70, 45, 0.03, 0.12), 0, 0.4)
    at(b, thump(0.3, 400, 160, 0.01, 0.03), 0, 0.4)
    crack = partials(1.0, ns(0.2), [(900, 0.6, 0.03), (1850, 0.5, 0.02), (2600, 0.35, 0.014),
                                     (3400, 0.2, 0.01)], rng)
    at(b, crack, 0.001, 0.8)
    at(b, noise_hit(rng, 0.06, 1500, 0.6, 0.006, "hp"), 0, 0.6)
    at(b, noise_hit(rng, 0.2, 500, 1.2, 0.05), 0, 0.6)
    x = saturate(b, 2.5)
    sp = buf(0.9)
    for i, m in enumerate([76, 80, 83, 88, 92]):
        at(sp, ins.bell(m, 0.6, 0.6, rng, "glock", 0.5), 0.045 + i * 0.032, 0.32 * (1 - 0.08 * i))
    x = x + lp(sp, 7000)
    x = wet(x, ROOM, 0.2)
    return finish(x, -3.0, 0.0005, 0.08, shave_db=2.5)


def glove_catch(rng, v):
    b = buf(0.2)
    f1, f2 = [(1300, 720), (1150, 640)][v]
    at(b, noise_hit(rng, 0.05, f1, 2.5, 0.007), 0, 0.9)
    at(b, noise_hit(rng, 0.06, f2, 2.0, 0.012), 0, 0.7)
    at(b, thump(0.12, 230, 150, 0.01, 0.03), 0, 0.7)
    at(b, noise_hit(rng, 0.01, 4000, 0.7, 0.0015, "hp"), 0, 0.3)
    x = saturate(b, 1.8)
    x = wet(x, ROOM, 0.15)
    return finish(x, -3.0, 0.0003, 0.03, shave_db=2.0)


def bat_crack(rng):
    b = buf(0.6)
    wood = partials(1.0, ns(0.3), [(560, 1.0, 0.06), (1300, 0.8, 0.04), (2150, 0.6, 0.025),
                                    (3050, 0.35, 0.016), (4200, 0.12, 0.01)], rng)
    at(b, wood, 0.0005, 1.0)
    at(b, noise_hit(rng, 0.05, 2000, 0.8, 0.008), 0, 0.9)
    at(b, noise_hit(rng, 0.01, 5000, 0.7, 0.001, "hp"), 0, 0.5)
    at(b, thump(0.2, 180, 95, 0.01, 0.04), 0, 0.5)
    x = saturate(b, 2.0)
    x = wet(x, HALL, 0.12)
    return finish(x, -3.0, 0.0003, 0.05, shave_db=2.0)


def enemy_out(rng, v):
    b = buf(0.75)
    at(b, thump(0.3, 160, 52, 0.02, 0.09), 0, 1.0)
    at(b, noise_hit(rng, 0.1, 1600, 1.0, 0.015), 0, 0.5)
    at(b, noise_hit(rng, 0.2, 420, 1.3, 0.05), 0, 0.6)
    imp = saturate(b, 2.2)
    if v == 0:
        n = ns(0.42)
        t = tarr(n)
        f = 220 + (820 - 220) * np.exp(-t / 0.13)
        f *= 1 + 0.02 * np.sin(TWO_PI * 18 * t)
        tn = (0.6 * square(f, n, 0.5) + 0.4 * triangle(f, n))
        tn = lp(tn, 2200) * np.clip(t / 0.01, 0, 1) * np.exp(-t / 0.2)
        at(imp, fade(tn, 0, 0.05), 0.05, 0.28)
    else:
        for i, (m0, m1) in enumerate([(79, 76), (72, 64)]):
            n = ns(0.16 if i == 0 else 0.32)
            t = tarr(n)
            f = mtof(m1) + (mtof(m0) - mtof(m1)) * np.exp(-t / (0.03 if i == 0 else 0.1))
            tn = lp(0.6 * square(f, n, 0.35) + 0.4 * triangle(f, n), 2400)
            tn *= np.clip(t / 0.006, 0, 1) * np.exp(-t / (0.08 if i == 0 else 0.16))
            at(imp, fade(tn, 0, 0.04), 0.05 + 0.13 * i, 0.26)
    x = wet(imp, ROOM, 0.15)
    return finish(x, -3.0, 0.0005, 0.06, shave_db=2.0)


def defender_stunned(rng):
    b = buf(1.15)
    n = ns(0.3)
    t = tarr(n)
    f = 430 + 220 * np.exp(-t / 0.015)
    bonk = (sine(f, n) + 0.35 * sine(f * 2.43, n) * np.exp(-t / 0.03)) * np.exp(-t / 0.08)
    at(b, bonk, 0, 0.9)
    at(b, noise_hit(rng, 0.03, 1800, 1.0, 0.004), 0, 0.4)
    at(b, thump(0.2, 140, 90, 0.01, 0.05), 0, 0.4)
    # tweety stars
    for k in range(5):
        cn = ns(0.085)
        ct = tarr(cn)
        hi_ = k % 2 == 0
        f0, f1 = (2100, 3000) if hi_ else (1750, 2500)
        fr = f0 + (f1 - f0) * (ct / 0.085) ** 0.6
        ch = sine(fr, cn) * np.sin(np.pi * ct / 0.085) ** 1.5
        ch *= 1 + 0.4 * np.sin(TWO_PI * 45 * ct)
        at(b, ch, 0.17 + k * 0.155, 0.16 * (1 - 0.1 * k))
    x = wet(b, ROOM, 0.25)
    x = lp(x, 5000)
    return finish(x, -3.0, 0.0005, 0.06, shave_db=1.5)


def swing_whoosh(rng):
    x = whoosh(rng, 0.46, 260, 1500, 0.55, q=1.0, body=0.7, power=1.5)
    n = len(x)
    woof = lp(white(n, rng), 260) * bump(n, 0.55, 2.0) * 0.6
    x = lp(x + woof, 6000)
    return finish(x, -3.0, 0.003, 0.05, shave_db=1.0)


def wall_break(rng):
    b = buf(1.3)
    at(b, thump(0.5, 95, 42, 0.03, 0.13), 0, 1.0)
    at(b, noise_hit(rng, 0.3, 700, 0.8, 0.06, "lp"), 0, 0.8)
    times = np.sort(rng.exponential(0.22, 80))
    times = times[times < 1.1] + 0.01
    amps = np.exp(-times / 0.35) * rng.uniform(0.3, 1.0, len(times))
    at(b, grains(rng, 1.3, times, 350, 2800, 0.006, 0.03, 1.5, 4.0, amps), 0, 0.9)
    peb = np.sort(rng.uniform(0.08, 0.9, 16))
    at(b, grains(rng, 1.3, peb, 2200, 4200, 0.003, 0.008, 3, 6, np.exp(-peb / 0.4) * 0.5), 0, 0.6)
    n = ns(1.2)
    t = tarr(n)
    rum = lp(brown(n, rng), 180) * np.exp(-t / 0.35) * (1 - np.exp(-t / 0.02))
    at(b, rum, 0, 0.5)
    x = saturate(b, 1.6)
    x = wet(x, ROOM, 0.2)
    return finish(x, -3.0, 0.0005, 0.1, shave_db=2.0)


def shield_block(rng):
    b = buf(0.85)
    n = ns(0.8)
    t = tarr(n)
    ping = 0.0
    for d in (-7, 0, 7):
        fr = 1046.5 * 2 ** (d / 1200)
        ping = ping + fm(fr, 1.5, 2.2 * np.exp(-t / 0.05) + 0.3, n) * np.exp(-t / 0.22)
    ping += 0.5 * sine(1568 * 1.002, n) * np.exp(-t / 0.15)
    at(b, ping / 3.0, 0, 0.8)
    vw = sine(380 + 520 * (1 - np.exp(-t / 0.04)), n) * np.exp(-t / 0.08)
    at(b, vw, 0, 0.5)
    at(b, noise_hit(rng, 0.03, 2500, 0.7, 0.003, "hp"), 0, 0.35)
    at(b, thump(0.15, 200, 110, 0.01, 0.04), 0, 0.4)
    x = wet(b, HALL, 0.18)
    x = lp(x, 7000)
    return finish(x, -3.0, 0.0005, 0.08, shave_db=1.5)


def run_scored(rng):
    b = buf(2.5)
    for k in range(2):
        n = ns(0.42)
        t = tarr(n)
        bz = square(147, n, 0.5) + square(156, n, 0.4) * 0.8 + 0.5 * saw(294.5, n)
        bz = lp(bz, 2200)
        bz = peq(bz, 900, 6, 1.2)
        bz *= np.clip(t / 0.008, 0, 1)
        at(b, fade(bz, 0, 0.03), k * 0.5, 0.45)
    groan = crowd_burst(rng, 1.9, "groan", voices=40,
                        env_pts=[(0, 0), (0.35, 1.0), (1.0, 0.8), (1.9, 0.0)], bed=0.7)
    at(b, groan, 0.45, 0.8 / max(peak(groan), 1e-9) * 0.6)
    x = wet(b, STADIUM, 0.18)
    return finish(x, -3.0, 0.001, 0.15, shave_db=1.5)


def gate_open(rng):
    b = buf(2.6)
    grind_d = 1.35
    n = ns(grind_d)
    t = tarr(n)
    # stick-slip pulses
    pulses = np.zeros(n)
    tt = 0.02
    while tt < grind_d - 0.05:
        rate = 22 + 18 * tt / grind_d + rng.uniform(-6, 6)
        pulses[ns(tt)] = rng.uniform(0.4, 1.0)
        tt += 1.0 / rate
    modes = [(190, 0.16), (415, 0.12), (733, 0.09), (1120, 0.07), (1610, 0.05), (2230, 0.035)]
    grind = np.zeros(n)
    for f, d in modes:
        k = np.exp(-1.0 / (d * SR))
        # resonator excited by pulses (2-pole)
        r = k
        w = TWO_PI * f / SR
        from scipy.signal import lfilter
        grind += lfilter([1 - r], [1, -2 * r * np.cos(w), r * r], pulses) * (1.0 / (1 + f / 800))
    scrape = bp(pink(n, rng), 900, 0.9) * (0.5 + 0.5 * smooth(np.abs(white(n, rng)), 0.02) * 2)
    env = np.clip(t / 0.15, 0, 1) * (0.7 + 0.3 * np.sin(np.pi * t / grind_d)) * np.clip((grind_d - t) / 0.1, 0, 1)
    squeal = tvfilt(pulses + 0.02 * white(n, rng), "bp", 640 * (1 + 0.35 * np.sin(np.pi * t / grind_d)), 25.0)
    g = grind / (np.max(np.abs(grind)) + 1e-9) + 0.12 * scrape + 1.2 * squeal / (np.max(np.abs(squeal)) + 1e-9)
    at(b, saturate(g * env, 1.5), 0, 0.6)
    # clank
    m = ns(1.4)
    ct = tarr(m)
    clank = partials(1.0, m, [(110, 1.0, 0.5), (283, 0.7, 0.45), (527, 0.5, 0.35), (840, 0.4, 0.28),
                              (1270, 0.3, 0.2), (1790, 0.2, 0.15), (2450, 0.1, 0.1)], rng)
    clank += 0.8 * sine(58, m) * np.exp(-ct / 0.18)
    clank += 0.6 * lp(white(m, rng), 2500) * np.exp(-ct / 0.015)
    at(b, fade(saturate(clank, 1.5), 0.0, 0.4), grind_d - 0.05, 1.0)
    x = wet(b, HALL, 0.35)
    return finish(x, -3.0, 0.01, 0.2, shave_db=2.0)


def footstep(rng, v):
    b = buf(0.16)
    times = np.sort(rng.uniform(0, 0.045, 9))
    at(b, grains(rng, 0.16, times, 500, 2200, 0.004, 0.012, 1.2, 2.5,
                 rng.uniform(0.3, 1.0, 9)), 0, 0.7)
    at(b, thump(0.1, 110, 70, 0.01, 0.02), 0, 0.6)
    at(b, noise_hit(rng, 0.08, 350, 0.8, 0.02, "lp"), 0, 0.5)
    x = lp(b, [3500, 3000][v])
    return finish(x, -12.0, 0.0005, 0.03, shave_db=1.0)


# ---------------------------------------------------------------------------
# cards & abilities
# ---------------------------------------------------------------------------
def card_draw(rng):
    b = buf(0.2)
    n = ns(0.075)
    t = tarr(n)
    sl = tvfilt(white(n, rng), "bp", 1800 + 2600 * t / 0.075, 1.2) * np.sin(np.pi * t / 0.075) ** 1.5
    at(b, sl, 0, 0.5)
    at(b, noise_hit(rng, 0.04, 2900, 1.3, 0.005), 0.07, 0.8)
    at(b, noise_hit(rng, 0.04, 900, 1.0, 0.008), 0.07, 0.3)
    x = lp(b, 7000)
    return finish(x, -6.0, 0.001, 0.02, shave_db=1.0)


def card_hover(rng):
    b = buf(0.04)
    n = ns(0.03)
    t = tarr(n)
    at(b, sine(2350, n) * np.exp(-t / 0.004), 0, 0.8)
    at(b, noise_hit(rng, 0.02, 3000, 1.5, 0.002), 0, 0.3)
    return finish(lp(b, 6000), -15.0, 0.0003, 0.008, shave_db=0.0, do_trim=False)


def card_play(rng):
    b = buf(1.1)
    at(b, whoosh(rng, 0.22, 600, 2500, 0.45, q=1.5, body=0.4), 0, 0.7)
    for i, m in enumerate([84, 88, 91, 96]):
        at(b, ins.bell(m, 0.7, 0.7, rng, "glock", 0.6), 0.08 + i * 0.045, 0.3)
        at(b, ins.fm_bell(m - 12, 0.8, 0.5, rng, 2.0, 1.2, 0.35), 0.08 + i * 0.045, 0.15)
    sh = colored(ns(0.8), rng, -1) * np.exp(-tarr(ns(0.8)) / 0.2)
    at(b, bp(sh, 5000, 2.0), 0.1, 0.06)
    x = wet(b, HALL, 0.25)
    x = lp(x, 7500)
    return finish(x, -3.0, 0.001, 0.1, shave_db=1.5)


def card_denied(rng):
    b = buf(0.42)
    for i, f in enumerate([196.0, 155.6]):
        n = ns(0.13)
        t = tarr(n)
        x = 0.6 * triangle(f, n) + 0.4 * square(f, n, 0.5)
        x = lp(x, 900) * np.clip(t / 0.004, 0, 1) * np.exp(-t / 0.09)
        at(b, fade(x, 0, 0.02), i * 0.14, 0.8)
    at(b, thump(0.12, 120, 80, 0.01, 0.03), 0, 0.3)
    return finish(b, -6.0, 0.0005, 0.03, shave_db=0.5)


def energy_full(rng):
    b = buf(1.3)
    at(b, ins.fm_bell(88, 1.2, 0.8, rng, 3.5, 2.0, 0.55), 0, 0.6)
    at(b, ins.fm_bell(95, 1.2, 0.8, rng, 3.5, 2.0, 0.5), 0.07, 0.5)
    at(b, ins.bell(100, 1.0, 0.6, rng, "glock", 0.6), 0.12, 0.25)
    n = ns(0.6)
    t = tarr(n)
    gl = sine(1200 * 2 ** (t / 0.6 * 1.5), n) * np.sin(np.pi * t / 0.6) * 0.15
    at(b, gl, 0.0, 0.5)
    x = wet(b, HALL, 0.25)
    x = lp(x, 7500)
    return finish(x, -3.0, 0.001, 0.1, shave_db=1.0)


def _crackles(rng, dur, count, env_fn=None, f_lo=1200, f_hi=4200):
    times = np.sort(rng.uniform(0, dur, count))
    amps = np.array([env_fn(tt) if env_fn else 1.0 for tt in times]) * rng.uniform(0.2, 1.0, count)
    return grains(rng, dur + 0.05, times, f_lo, f_hi, 0.002, 0.007, 2, 5, amps)


def fire_cast(rng):
    dur = 1.35
    b = buf(dur)
    n = ns(1.25)
    t = tarr(n)
    nz = white(n, rng)
    cut = 200 + 2800 * (1 - np.exp(-t / 0.06)) * np.exp(-t / 0.5) + 500
    wh = tvfilt(nz, "lp", cut, 0.9) * np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.45)
    at(b, wh, 0, 0.9)
    roar = lp(brown(n, rng), 1100) * np.exp(-t / 0.5) * np.clip(t / 0.05, 0, 1)
    flick = 1 + 0.4 * smooth(white(n, rng), 0.012) * 8
    at(b, roar * flick, 0, 0.6)
    at(b, thump(0.6, 80, 45, 0.04, 0.25), 0, 0.7)
    at(b, _crackles(rng, 1.2, 45, lambda tt: np.exp(-tt / 0.5)), 0.02, 0.5)
    x = saturate(b, 1.5)
    x = wet(x, ROOM, 0.15)
    x = lp(x, 7000)
    return finish(x, -3.0, 0.002, 0.15, shave_db=2.0)


def fire_loop(rng):
    """2.0 s seamless loop: everything is generated circularly."""
    n = ns(2.0)
    t = tarr(n)
    nz = np.fft.irfft(np.fft.rfft(rng.standard_normal(n)), n)
    roar = fft_shape(nz, lambda f: 1.0 / np.maximum(f, 30) * (f < 1400) * (f > 40))
    roar /= np.std(roar)
    hiss = fft_shape(rng.standard_normal(n), lambda f: ((f > 1800) & (f < 4500)).astype(float))
    hiss /= np.std(hiss)
    am = np.zeros(n)
    for k in range(4, 32):  # integer cycles per 2 s -> periodic
        am += rng.uniform(0.3, 1.0) / k ** 0.5 * np.sin(TWO_PI * (k / 2.0) * t + rng.random() * 6)
    am = 1 + 0.35 * am / np.max(np.abs(am))
    x = roar * am * 0.6 + 0.06 * hiss * am
    # crackles placed circularly
    for _ in range(38):
        tt = rng.uniform(0, 2.0)
        m = ns(rng.uniform(0.002, 0.008))
        g = bp(white(m, rng), rng.uniform(1300, 4000), rng.uniform(2, 5)) * perc(m, 0.0004, m / SR / 4)
        s = ns(tt)
        idx = (s + np.arange(m)) % n
        np.add.at(x, idx, g * rng.uniform(0.6, 2.2))
    x = fft_shape(x, lambda f: (f > 45).astype(float))  # periodic DC/sub removal
    x = np.tanh(x / np.max(np.abs(x)) * 1.3)
    return normalize_peak(x - np.mean(x), -6.0)


def frost_cast(rng):
    b = buf(1.5)
    for _ in range(26):
        f = np.exp(rng.uniform(np.log(1700), np.log(4800)))
        d = rng.uniform(0.08, 0.3)
        m = ns(d * 5)
        tt = tarr(m)
        s = sine(f * (1 + 0.04 * tt), m) * np.exp(-tt / d) * (1 - np.exp(-tt / 0.002))
        at(b, s, rng.uniform(0.0, 0.65) ** 1.3, rng.uniform(0.05, 0.15))
    n = ns(0.9)
    t = tarr(n)
    gl = sum(sine(f * 2 ** (t / 0.9 * 1.0), n) for f in (1320, 1980, 2640)) / 3
    at(b, gl * np.sin(np.pi * t / 0.9) ** 2, 0, 0.12)
    crack = buf(0.2)
    ct = np.sort(rng.uniform(0, 0.07, 14))
    at(crack, grains(rng, 0.2, ct, 1800, 5000, 0.002, 0.006, 2, 6, rng.uniform(0.4, 1.0, 14)), 0, 1.0)
    at(crack, noise_hit(rng, 0.15, 1150, 8.0, 0.04), 0, 0.5)
    at(b, crack, 0.14, 0.9)
    at(b, thump(0.3, 120, 70, 0.02, 0.08), 0.14, 0.5)
    air = hp(white(ns(1.2), rng), 3000) * bump(ns(1.2), 0.3, 2) * 0.05
    at(b, air, 0, 1.0)
    x = wet(b, HALL, 0.3)
    x = lp(x, 7500)
    return finish(x, -3.0, 0.002, 0.15, shave_db=1.5)


def shadow_cast(rng):
    n = ns(0.75)
    t = tarr(n)
    tone_ = sum(saw(mtof(m), n, rng.random()) for m in (33, 34, 45, 46)) / 4
    tone_ = lp(tone_, 650) * np.exp(-t / 0.18)
    wh = lp(white(n, rng), 1400) * np.exp(-t / 0.12)
    fwd = tone_ + 0.6 * wh
    fwd = wet(fwd, HALL, 0.8)[:n]
    rev = fwd[::-1] * np.clip(np.linspace(0, 1, n) / 0.15, 0, 1)
    b = buf(1.15)
    at(b, rev, 0, 1.0)
    hit = mix(thump(0.4, 90, 40, 0.02, 0.12), 0.4 * noise_hit(rng, 0.2, 500, 0.8, 0.03, "lp"))
    at(b, hit, 0.74, 0.9)
    tail = lp(white(ns(0.4), rng), 900) * np.exp(-tarr(ns(0.4)) / 0.1)
    at(b, tail, 0.74, 0.3)
    x = wet(b, ROOM, 0.2)
    return finish(x, -3.0, 0.02, 0.12, shave_db=1.5)


def lightning_zap(rng):
    b = buf(1.0)
    n = ns(0.75)
    t = tarr(n)
    # sample & hold pitch jumps
    f = np.zeros(n)
    i = 0
    while i < n:
        seg = ns(rng.uniform(0.006, 0.02))
        f[i:i + seg] = rng.uniform(110, 900)
        i += seg
    z = saw(f, n) * 0.6 + square(f * 1.5, n, 0.3) * 0.3
    gate = np.zeros(n)
    i = 0
    while i < n:
        on = ns(rng.uniform(0.002, 0.012))
        gate[i:i + on] = rng.uniform(0.4, 1.0)
        i += on + ns(rng.uniform(0.001, 0.015))
    gate = smooth(gate, 0.0005)
    crack = bp(white(n, rng), 2200, 0.6) * gate
    env = np.exp(-t / 0.28)
    zap = (0.6 * z * gate + crack) * env
    zap = saturate(bp(zap, 1500, 0.5) + 0.3 * zap, 2.0)
    at(b, zap, 0.0, 0.8)
    at(b, noise_hit(rng, 0.1, 1500, 0.7, 0.015, "hp"), 0, 0.7)
    at(b, thump(0.6, 110, 45, 0.03, 0.18), 0, 0.6)
    rum = lp(brown(ns(0.9), rng), 220) * np.exp(-tarr(ns(0.9)) / 0.3)
    at(b, rum, 0.02, 0.3)
    x = lp(b, 6500)
    x = wet(x, ROOM, 0.15)
    return finish(x, -3.0, 0.0005, 0.1, shave_db=2.5)


def magnet_pull(rng):
    n = ns(1.25)
    t = tarr(n)
    u = t / 1.25
    f = 70 * (160 / 70) ** (u ** 1.3)
    x = saw(f, n) * 0.5 + sine(f, n) * 0.6 + 0.25 * saw(f * 1.5, n)
    cut = 250 + 2300 * u ** 1.5
    x = tvfilt(x, "lp", cut, 2.0)
    rate = 5 + 17 * u ** 1.5
    wob = 1 - 0.45 * (0.5 + 0.5 * np.sin(TWO_PI * np.cumsum(rate) / SR))
    sh = sine(f * 4.0, n) * 0.08 * u
    env = np.clip(t / 0.5, 0, 1) ** 1.5 * np.clip((1.25 - t) / 0.08, 0, 1)
    y = (x * wob + sh) * env
    y = saturate(y, 1.5)
    return finish(y, -3.0, 0.005, 0.05, shave_db=1.0)


def earth_rumble(rng):
    b = buf(1.8)
    at(b, thump(0.8, 75, 34, 0.05, 0.3), 0, 1.0)
    n = ns(1.7)
    t = tarr(n)
    rum = lp(brown(n, rng), 170, order=2) * np.clip(t / 0.08, 0, 1) * np.exp(-t / 0.6)
    rum *= 1 + 0.4 * smooth(white(n, rng), 0.03) * 6
    at(b, rum, 0, 0.9)
    times = np.sort(rng.uniform(0.03, 1.3, 110) ** 1.2)
    amps = np.exp(-times / 0.6) * rng.uniform(0.3, 1.0, len(times))
    at(b, grains(rng, 1.8, times, 250, 1600, 0.008, 0.04, 1.2, 3, amps), 0, 0.8)
    x = saturate(b, 1.6)
    x = wet(x, ROOM, 0.2)
    return finish(x, -3.0, 0.002, 0.2, shave_db=2.5)


def barrage_impact(rng):
    b = buf(1.6)
    at(b, thump(1.0, 80, 30, 0.04, 0.35), 0, 1.0)
    n = ns(1.0)
    t = tarr(n)
    blast = tvfilt(white(n, rng), "lp", 300 + 6500 * np.exp(-t / 0.12), 0.8)
    blast *= np.clip(t / 0.003, 0, 1) * np.exp(-t / 0.3)
    at(b, blast, 0, 0.9)
    times = np.sort(rng.uniform(0.02, 0.9, 40) ** 1.3)
    at(b, grains(rng, 1.6, times, 600, 3500, 0.004, 0.02, 1.5, 4,
                 np.exp(-times / 0.4) * rng.uniform(0.2, 1, 40)), 0, 0.5)
    x = saturate(b, 2.2)
    x = wet(x, HALL, 0.22)
    x = lp(x, 7000)
    return finish(x, -3.0, 0.0005, 0.2, shave_db=3.0)


def time_out_whistle(rng):
    b = buf(1.1)
    for st, d in [(0.0, 0.17), (0.25, 0.62)]:
        n = ns(d)
        t = tarr(n)
        trill = np.sin(TWO_PI * 27 * t)
        f = 2450 * (1 + 0.025 * trill) * (1 + 0.02 * np.clip(t / 0.03, 0, 1))
        w = sine(f, n) + 0.12 * sine(2 * f, n)
        w *= 1 - 0.45 * (0.5 + 0.5 * trill)
        br = bp(white(n, rng), 2450, 4) * 0.25
        env = np.clip(t / 0.015, 0, 1) * np.clip((d - t) / 0.03, 0, 1)
        at(b, (w + br) * env, st, 0.8)
    x = lp(b, 4800)
    x = wet(x, STADIUM, 0.15)
    return finish(x, -3.0, 0.002, 0.08, shave_db=1.0)


def rally_horn(rng):
    b = buf(1.9)
    for st, d in [(0.0, 0.2), (0.27, 0.2), (0.54, 0.75)]:
        n = ns(d + 0.05)
        t = tarr(n)
        bend = 2 ** (-60 * np.exp(-t / 0.035) / 1200)
        x = 0.0
        for f in (311.1, 370.0, 466.2):
            x = x + 0.6 * square(f * bend, n, 0.22) + 0.4 * saw(f * bend * 1.003, n)
        x = saturate(x * 0.4, 3.0)
        x = peq(x, 1250, 6, 1.0)
        x = lp(x, 3800)
        env = np.clip(t / 0.02, 0, 1) * np.clip((d - t) / 0.04 + 1, 0, 1)
        at(b, x * env, st, 0.7)
    x = wet(b, STADIUM, 0.3)
    return finish(x, -3.0, 0.002, 0.15, shave_db=2.0)


def aura_hum(rng):
    dur = 1.9
    b = buf(dur + 0.3)
    for m in (60, 64, 67, 71, 72):
        n = ns(dur)
        t = tarr(n)
        x = sum(saw(mtof(m) * 2 ** (d / 1200), n, rng.random()) for d in (-9, 0, 9)) / 3
        cut = 500 + 2200 * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.2
        x = tvfilt(x, "lp", cut, 0.8)
        env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.6
        at(b, x * env, 0, 0.3)
    n = ns(dur)
    t = tarr(n)
    sh = (sine(mtof(84), n) + sine(mtof(91), n)) * (0.5 + 0.5 * np.sin(TWO_PI * 7 * t))
    at(b, sh * np.sin(np.pi * t / dur) ** 2 * 0.06, 0, 1.0)
    x = wet(b, HALL, 0.3)
    return finish(x, -3.0, 0.01, 0.2, shave_db=0.5)


def heal_chime(rng):
    b = buf(1.5)
    for i, m in enumerate([84, 88, 91, 96]):
        at(b, ins.bell(m, 0.8, 0.7, rng, "glock", 0.8), i * 0.065, 0.4)
    n = ns(1.1)
    t = tarr(n)
    pd = (sine(mtof(72), n) + 0.7 * sine(mtof(79), n) + 0.4 * sine(mtof(76), n))
    pd *= np.sin(np.pi * t / 1.1) ** 2 * (1 + 0.1 * np.sin(TWO_PI * 5 * t))
    at(b, pd, 0, 0.12)
    x = wet(b, HALL, 0.3)
    x = lp(x, 7500)
    return finish(x, -3.0, 0.002, 0.15, shave_db=1.0)


def explosion_small(rng):
    b = buf(0.9)
    at(b, thump(0.5, 95, 40, 0.025, 0.15), 0, 1.0)
    n = ns(0.6)
    t = tarr(n)
    bl = tvfilt(white(n, rng), "lp", 350 + 4800 * np.exp(-t / 0.07), 0.8)
    at(b, bl * np.clip(t / 0.002, 0, 1) * np.exp(-t / 0.15), 0, 0.9)
    times = np.sort(rng.uniform(0.01, 0.5, 14))
    at(b, grains(rng, 0.9, times, 700, 3000, 0.003, 0.012, 2, 4,
                 np.exp(-times / 0.2) * rng.uniform(0.3, 1, 14)), 0, 0.4)
    x = saturate(b, 2.0)
    x = wet(x, ROOM, 0.18)
    return finish(x, -3.0, 0.0005, 0.12, shave_db=2.5)


# ---------------------------------------------------------------------------
# game flow
# ---------------------------------------------------------------------------
def _big_hit(rng):
    k = ins.kick(rng, 150, 45, 0.04, 0.4, 0.5, 2.0, 0.9)
    tk = ins.taiko(rng, 60, 0.7, 1.6)
    sn = ins.snare(rng, 180, 0.09, 0.22)
    cr = ins.crash(rng, 1.4, 2.0)
    return mix_at([(k, 0, 0.8), (tk, 0, 0.8), (sn, 0, 0.4), (cr, 0, 0.18)])


def mix_at(items):
    n = max(ns(t) + len(x) for x, t, g in items)
    out = np.zeros(n)
    for x, t, g in items:
        place(out, x, ns(t), g)
    return out


def wave_start(rng):
    b = buf(2.2)
    at(b, _big_hit(rng), 0, 0.8)
    for m in (46, 53, 58):
        at(b, ins.brass(m, 1.1, 1.0, rng, bright=1.0, attack=0.06, rel=0.25, growl=0.15), 0.02, 0.8)
    x = wet(b, STADIUM, 0.3)
    return finish(x, -3.0, 0.0005, 0.2, shave_db=2.5)


def wave_clear(rng):
    b = buf(1.6)
    for i, m in enumerate([67, 72]):
        for mm in (m, m - 12):
            at(b, ins.brass(mm, 0.08, 0.9, rng, bright=1.0, attack=0.015, rel=0.05, scoop=10), i * 0.1, 0.35)
    for m in (64, 67, 72, 76, 84):
        at(b, ins.brass(m, 0.55, 1.0, rng, bright=1.1, attack=0.02, rel=0.2, scoop=15), 0.2, 0.3)
    for i, m in enumerate([84, 88, 91]):
        at(b, ins.bell(m, 0.6, 0.6, rng, "glock"), 0.2 + i * 0.04, 0.2)
    at(b, ins.snare(rng, 200, 0.06, 0.12), 0.2, 0.25)
    at(b, ins.crash(rng, 1.0, 1.4), 0.2, 0.15)
    x = wet(b, HALL, 0.25)
    return finish(x, -3.0, 0.001, 0.15, shave_db=1.5)


def inning_end(rng):
    """Stadium-organ 'Charge!' bugle call (traditional) + crowd answer."""
    b = buf(3.3)
    org = np.zeros(ns(3.3))
    seq = [(0.0, 0.13, 67), (0.15, 0.13, 72), (0.30, 0.13, 76), (0.45, 0.38, 79),
           (0.87, 0.13, 76), (1.02, 1.15, 79)]
    for st, d, m in seq:
        for mm in (m, m - 12):
            place(org, ins.organ(mm, d, 1.0, rng, "888888008", 0.0, 0.3), ns(st))
    for m in (55, 60, 64):
        place(org, ins.organ(m, 1.15, 0.7, rng, "886600000", 0.0, 0.2), ns(1.02))
    # final stabs "da-DA!"
    for st in (2.3, 2.5):
        for m in (60, 64, 67, 72):
            place(org, ins.organ(m, 0.14 if st < 2.4 else 0.4, 0.9, rng, "888888008"), ns(st))
    from dsp import leslie
    org = leslie(saturate(org, 1.6), 6.4)[0]
    at(b, org, 0, 1.0)
    cheer = crowd_burst(rng, 1.3, "cheer", voices=36, env_pts=[(0, 0), (0.1, 1), (0.6, 0.8), (1.3, 0)],
                        clap_rate=0)
    at(b, cheer, 2.0, 0.35 / max(peak(cheer), 1e-9))
    x = wet(b, STADIUM, 0.3)
    return finish(x, -3.0, 0.002, 0.2, shave_db=1.5)


def combo_double(rng):
    b = buf(0.9)
    for i, m in enumerate([84, 91]):
        at(b, ins.bell(m, 0.6, 0.8, rng, "glock", 0.7), i * 0.09, 0.5)
        at(b, ins.fm_bell(m - 12, 0.7, 0.6, rng, 3.5, 1.5, 0.35), i * 0.09, 0.3)
    x = wet(b, HALL, 0.2)
    return finish(lp(x, 7500), -3.0, 0.0005, 0.1, shave_db=1.0)


def combo_triple(rng):
    b = buf(1.2)
    for i, m in enumerate([84, 88, 91]):
        at(b, ins.bell(m, 0.6, 0.8, rng, "glock", 0.8), i * 0.085, 0.45)
        at(b, ins.fm_bell(m - 12, 0.8, 0.6, rng, 3.5, 1.6, 0.4), i * 0.085, 0.3)
    at(b, ins.bell(96, 0.8, 0.8, rng, "glock", 1.0), 0.255, 0.4)
    for m in (60, 64, 67, 72):
        at(b, ins.brass(m, 0.35, 0.8, rng, bright=0.9, attack=0.02, rel=0.15), 0.255, 0.18)
    x = wet(b, HALL, 0.25)
    return finish(lp(x, 7500), -3.0, 0.0005, 0.12, shave_db=1.5)


def combo_grand(rng):
    b = buf(2.0)
    for m in (48, 55, 60, 64, 67, 72, 76):
        at(b, ins.brass(m, 0.55, 1.0, rng, bright=1.2, attack=0.015, rel=0.3, scoop=20), 0, 0.28)
    at(b, ins.timpani(rng, 36, 1.0), 0, 0.6)
    at(b, ins.crash(rng, 1.4, 2.0), 0, 0.35)
    at(b, ins.kick(rng, 140, 45, 0.04, 0.35), 0, 0.5)
    for i, m in enumerate([84, 88, 91, 96, 100]):
        at(b, ins.bell(m, 0.7, 0.7, rng, "glock", 0.7), 0.05 + i * 0.05, 0.22)
    x = wet(b, STADIUM, 0.28)
    return finish(lp(x, 8000), -3.0, 0.0005, 0.2, shave_db=2.0)


def boss_warning(rng):
    b = buf(3.3)
    for k, base in enumerate([36, 35]):
        st = k * 1.3
        for m, g in ((base, 0.45), (base + 7, 0.35), (base + 12, 0.35), (base + 13, 0.2), (base + 19, 0.15)):
            at(b, ins.brass(m, 0.7, 1.0, rng, bright=1.1, attack=0.1, rel=0.15, growl=0.8, vib=0.3), st, g)
        at(b, ins.bass_sub(base, 0.7, 1.0, rng, 0.15), st, 0.18)
        at(b, ins.taiko(rng, 55, 0.6, 1.2), st, 0.4)
    x = wet(b, STADIUM, 0.35)
    return finish(x, -3.0, 0.005, 0.25, shave_db=2.0)


def boss_slam(rng):
    b = buf(2.6)
    at(b, thump(1.6, 60, 26, 0.06, 0.5), 0, 1.0)
    at(b, ins.taiko(rng, 48, 0.9, 1.8), 0, 0.6)
    n = ns(1.5)
    t = tarr(n)
    bl = tvfilt(white(n, rng), "lp", 150 + 3500 * np.exp(-t / 0.08), 0.8)
    at(b, bl * np.clip(t / 0.002, 0, 1) * np.exp(-t / 0.35), 0, 0.7)
    times = np.sort(rng.uniform(0.03, 1.4, 60) ** 1.4)
    at(b, grains(rng, 2.6, times, 300, 2500, 0.006, 0.03, 1.5, 4,
                 np.exp(-times / 0.6) * rng.uniform(0.2, 1, 60)), 0, 0.5)
    x = saturate(b, 2.2)
    x = wet(x, STADIUM, 0.25)
    return finish(x, -3.0, 0.0005, 0.3, shave_db=3.0)


def boss_roar(rng):
    dur = 2.0
    n = ns(dur)
    t = tarr(n)
    u = t / dur
    f0 = 92 * (1 + 0.3 * np.sin(np.pi * np.clip(u * 1.6, 0, 1))) * (1 - 0.25 * u ** 2)
    jit = 1 + 0.06 * smooth(white(n, rng), 0.004) * 12
    f = f0 * jit
    src = saw(f, n) + 0.6 * square(f * 0.5, n, 0.4) + 0.4 * saw(f * 1.01, n)
    src = src * (1 + 0.6 * np.sin(TWO_PI * 33 * t + 2 * smooth(white(n, rng), 0.01)))
    a_ = ins.formant_filter(src, "ah", 0.8)
    o_ = ins.formant_filter(src, "o", 0.8)
    mixv = np.clip(u * 1.4 - 0.2, 0, 1)
    v = a_ * (1 - mixv) + o_ * mixv
    br = bp(white(n, rng), 900, 0.8) * 0.4
    env = np.clip(t / 0.12, 0, 1) * np.clip((dur - t) / 0.6, 0, 1) ** 1.3
    x = saturate((v * 2.5 + br) * env, 3.0)
    x = lp(x, 4500)
    x = x + 0.4 * lp(x, 200)
    x = wet(x, STADIUM, 0.25)
    return finish(x, -3.0, 0.005, 0.25, shave_db=2.0)


def victory_fanfare(rng):
    b = buf(4.6)
    bt = 0.15
    seq = [(0, 1, 67), (1, 1, 67), (2, 1, 67), (3, 3, 72), (6, 2, 76), (8, 2, 74), (10, 1, 72),
           (11, 1, 76), (12, 12, 79)]
    for st, d, m in seq:
        for mm, g in ((m, 0.4), (m - 12, 0.28)):
            at(b, ins.brass(mm, d * bt * 0.95, 1.0, rng, bright=1.1, attack=0.02, rel=0.25,
                            scoop=15), st * bt, g)
    for m in (48, 55, 60, 64, 67):
        at(b, ins.brass(m, 12 * bt, 0.9, rng, bright=0.9, attack=0.04, rel=0.4), 12 * bt, 0.2)
    for i in range(10):
        at(b, ins.timpani(rng, 43, 0.4 + 0.06 * i, 0.8), i * 0.045, 0.25)
    at(b, ins.timpani(rng, 36, 1.0), 12 * bt, 0.7)
    at(b, ins.crash(rng, 1.8, 2.6), 12 * bt, 0.35)
    for i, m in enumerate([84, 88, 91, 96]):
        at(b, ins.bell(m, 0.8, 0.6, rng, "glock"), 12 * bt + i * 0.06, 0.18)
    x = wet(b, STADIUM, 0.3)
    return finish(lp(x, 8000), -3.0, 0.002, 0.4, shave_db=1.5)


def defeat_sting(rng):
    b = buf(3.4)
    seq = [(0.0, 0.45, 67), (0.5, 0.45, 66), (1.0, 0.45, 65), (1.5, 1.4, 64)]
    for st, d, m in seq:
        vib = 0.4 if d < 1 else 2.4
        at(b, ins.brass(m, d, 0.8, rng, bright=0.45, attack=0.05, rel=0.25, vib=vib, scoop=40), st, 0.6)
        at(b, ins.brass(m - 12, d, 0.6, rng, bright=0.35, attack=0.05, rel=0.25, vib=vib * 0.5,
                        scoop=40), st, 0.35)
    for m in (45, 52, 57, 60):
        at(b, ins.strings(m, 1.5, 0.6, rng, attack=0.3, rel=0.6), 1.5, 0.35)
    at(b, ins.timpani(rng, 33, 0.5), 1.5, 0.3)
    x = wet(b, HALL, 0.3)
    return finish(x, -3.0, 0.005, 0.4, shave_db=1.0)


def level_up(rng):
    b = buf(1.5)
    for i, m in enumerate([72, 76, 79, 84, 88, 91]):
        at(b, ins.lead(m, 0.06, 0.8, rng, cutoff=2500, vib=0, rel=0.03), i * 0.045, 0.35)
    for m in (84, 88, 91, 96):
        at(b, ins.bell(m, 0.8, 0.7, rng, "glock", 0.9), 0.28, 0.25)
        at(b, ins.fm_bell(m - 12, 1.0, 0.6, rng, 2.0, 1.0, 0.4), 0.28, 0.12)
    x = wet(b, HALL, 0.25)
    return finish(lp(x, 7500), -3.0, 0.0005, 0.15, shave_db=1.5)


def achievement(rng):
    b = buf(2.3)
    for i, m in enumerate([79, 83, 86, 91]):
        at(b, ins.fm_bell(m, 1.6, 0.7, rng, 3.5, 2.0, 0.7), i * 0.07, 0.3)
    pent = [79, 81, 83, 86, 88, 91, 93, 95, 98]
    for i in range(14):
        m = pent[min(len(pent) - 1, int(i * len(pent) / 14))]
        at(b, ins.bell(m, 0.5, 0.5, rng, "glock", 0.5), 0.3 + i * 0.04 + rng.uniform(0, 0.01), 0.16)
    n = ns(1.6)
    t = tarr(n)
    sh = sum(sine(mtof(m), n) for m in (67, 71, 74)) * np.sin(np.pi * t / 1.6) ** 2
    at(b, sh, 0.1, 0.05)
    x = wet(b, HALL, 0.35)
    return finish(lp(x, 7500), -3.0, 0.0005, 0.2, shave_db=1.5)


def coin(rng):
    b = buf(0.45)
    n1 = ns(0.07)
    at(b, square(mtof(83), n1, 0.5) * 0.6, 0, 0.5)
    n2 = ns(0.35)
    t = tarr(n2)
    at(b, square(mtof(88), n2, 0.5) * np.exp(-t / 0.1) * 0.6, 0.065, 0.5)
    at(b, ins.bell(100, 0.3, 0.4, rng, "glock", 0.3), 0.065, 0.2)
    x = lp(b, 6000)
    return finish(x, -6.0, 0.0005, 0.04, shave_db=0.5)


def purchase(rng):
    b = buf(1.2)
    at(b, noise_hit(rng, 0.06, 800, 1.5, 0.012), 0, 0.6)
    at(b, thump(0.08, 160, 90, 0.008, 0.02), 0, 0.5)
    at(b, noise_hit(rng, 0.02, 3000, 1.0, 0.002), 0.03, 0.4)
    ch = partials(1.0, ns(1.0), [(2093, 1.0, 0.3), (2662, 0.6, 0.25), (3160, 0.45, 0.2),
                                 (4310, 0.3, 0.15), (5280, 0.15, 0.1)], rng)
    ch = fade(ch, 0.0, 0.4)
    at(b, ch, 0.085, 0.5)
    for _ in range(9):
        f = rng.uniform(3000, 5800)
        m = ns(0.2)
        tt = tarr(m)
        at(b, sine(f, m) * np.exp(-tt / rng.uniform(0.03, 0.08)), 0.1 + rng.uniform(0, 0.3), 0.08)
    x = wet(b, ROOM, 0.2)
    return finish(lp(x, 7500), -3.0, 0.0005, 0.12, shave_db=1.5)


# ---------------------------------------------------------------------------
# UI (quieter: about -9 dBFS peak)
# ---------------------------------------------------------------------------
UI_PEAK = -9.0


def ui_hover(rng):
    n = ns(0.045)
    t = tarr(n)
    x = sine(1500 + 250 * np.clip(t / 0.01, 0, 1), n) * np.clip(t / 0.002, 0, 1) * np.exp(-t / 0.01)
    return finish(x, -13.0, 0.001, 0.01, shave_db=0.0, do_trim=False)


def ui_click(rng):
    b = buf(0.07)
    n = ns(0.06)
    t = tarr(n)
    at(b, sine(820 + 300 * np.exp(-t / 0.004), n) * np.exp(-t / 0.009), 0, 0.8)
    at(b, sine(2100, n) * np.exp(-t / 0.003), 0, 0.3)
    at(b, noise_hit(rng, 0.01, 3000, 1.2, 0.0015), 0, 0.25)
    return finish(b, UI_PEAK, 0.0003, 0.01, shave_db=0.5, do_trim=False)


def _blip(m, d, kind="tri", decay=0.05):
    n = ns(d)
    t = tarr(n)
    f = mtof(m)
    x = (0.7 * sine(f, n) + 0.3 * triangle(f, n)) if kind == "tri" else sine(f, n)
    return fade(x * np.clip(t / 0.003, 0, 1) * np.exp(-t / decay), 0, 0.01)


def ui_back(rng):
    b = buf(0.2)
    at(b, _blip(88, 0.06), 0, 0.7)
    at(b, _blip(83, 0.11, decay=0.05), 0.055, 0.7)
    return finish(lp(b, 5000), UI_PEAK, 0.0005, 0.02, shave_db=0.0)


def ui_confirm(rng):
    b = buf(0.32)
    at(b, _blip(84, 0.07), 0, 0.7)
    at(b, _blip(91, 0.22, decay=0.08), 0.06, 0.7)
    at(b, ins.bell(103, 0.2, 0.3, rng, "glock", 0.3), 0.06, 0.15)
    return finish(lp(b, 6000), UI_PEAK, 0.0005, 0.03, shave_db=0.0)


def ui_error(rng):
    b = buf(0.24)
    for i in range(2):
        n = ns(0.075)
        t = tarr(n)
        x = square(220, n, 0.5) + 0.8 * square(233, n, 0.5)
        x = lp(x, 1100) * np.clip(t / 0.004, 0, 1)
        at(b, fade(x, 0, 0.015), i * 0.11, 0.5)
    return finish(b, UI_PEAK, 0.0005, 0.02, shave_db=0.5)


def ui_tab(rng):
    b = buf(0.1)
    n = ns(0.08)
    at(b, partials(1.0, n, [(950, 1.0, 0.018), (2150, 0.4, 0.008), (3300, 0.15, 0.004)], rng), 0, 0.8)
    at(b, noise_hit(rng, 0.01, 2500, 1.5, 0.001), 0, 0.3)
    return finish(b, UI_PEAK, 0.0003, 0.015, shave_db=0.0)


def ui_slide(rng):
    x = whoosh(rng, 0.24, 380, 1700, 0.45, q=1.2, body=0.6)
    return finish(lp(x, 5000), UI_PEAK, 0.003, 0.04, shave_db=0.0)


def ui_toggle(rng):
    b = buf(0.1)
    for i, f in enumerate([1800, 2500]):
        n = ns(0.03)
        t = tarr(n)
        at(b, sine(f, n) * np.exp(-t / 0.004) + 0.3 * bp(white(n, rng), f, 2) * np.exp(-t / 0.002),
           i * 0.038, 0.7)
    return finish(b, UI_PEAK, 0.0003, 0.01, shave_db=0.0, do_trim=False)


# ---------------------------------------------------------------------------
# crowd
# ---------------------------------------------------------------------------
def crowd_cheer(rng, v):
    dur = [2.6, 2.9][v]
    x = crowd_burst(rng, dur, "cheer", voices=[64, 72][v],
                    env_pts=[(0, 0), (0.18, 1.0), (dur * 0.5, 0.85), (dur, 0.0)],
                    clap_rate=[90, 130][v], bed=0.8, whistles=[1, 2][v])
    x = wet(x, STADIUM, 0.3)
    return finish(x, -3.0, 0.02, 0.4, shave_db=1.0)


def crowd_groan(rng):
    x = crowd_burst(rng, 2.0, "groan", voices=56, env_pts=[(0, 0), (0.3, 1.0), (1.1, 0.75), (2.0, 0)],
                    bed=0.7)
    x = wet(x, STADIUM, 0.3)
    return finish(x, -3.0, 0.03, 0.4, shave_db=1.0)


def crowd_ooh(rng):
    x = crowd_burst(rng, 1.9, "ooh", voices=56, env_pts=[(0, 0), (0.45, 1.0), (1.1, 0.8), (1.9, 0)],
                    bed=0.6)
    x = wet(x, STADIUM, 0.3)
    return finish(x, -3.0, 0.03, 0.4, shave_db=1.0)


# ---------------------------------------------------------------------------
# registry: name -> (fn, volume_db, loop, group)
# ---------------------------------------------------------------------------
def _v(fn, v):
    return lambda rng: fn(rng, v)


# ---------------------------------------------------------------- card packs

def pack_shake(rng):
    """Foil pack crinkling harder and harder while a riser builds."""
    total = 1.1
    times = []
    t = 0.0
    while t < 1.0:
        times.append(t)
        t += 0.06 * (1.0 - t * 0.75) + rng.uniform(0, 0.02)
    amps = [0.35 + 0.65 * (x / 1.0) for x in times]
    b = grains(rng, total, times, 2500, 9000, 0.01, 0.04, 2.0, 5.0, amps)
    n = ns(1.0)
    tt = tarr(n)
    riser = tvfilt(colored(n, rng, -1.0), "bp", 600 * (6.0 ** (tt / 1.0)), 2.5) * (tt / 1.0) ** 2
    at(b, riser, 0.0, 0.35)
    at(b, sine(mtof(52) * (1 + tt), n) * (tt / 1.0) ** 3 * 0.25, 0.0, 1.0)
    return finish(lp(b, 9500), -5.0, 0.001, 0.05)


def pack_tear(rng):
    """Foil rips open with a bright burst of sparkle."""
    b = buf(1.6)
    times = sorted(rng.uniform(0, 0.16, 70))
    at(b, grains(rng, 0.3, times, 1800, 9000, 0.004, 0.02, 1.5, 4.0), 0, 0.9)
    at(b, whoosh(rng, 0.3, 900, 6000, 0.2, q=1.2, body=0.3), 0.0, 0.6)
    at(b, thump(0.25, 160, 55, 0.02, 0.08), 0.12, 0.5)
    for i, m in enumerate([84, 88, 91, 96, 100]):
        at(b, ins.bell(m, 0.8, 0.6, rng, "glock", 0.7), 0.14 + i * 0.035, 0.22)
    sh = colored(ns(1.0), rng, -1) * np.exp(-tarr(ns(1.0)) / 0.35)
    at(b, bp(sh, 6500, 2.0), 0.14, 0.08)
    x = wet(b, HALL, 0.3)
    return finish(lp(x, 9000), -3.0, 0.0005, 0.15, shave_db=1.0)


def card_whoosh(rng):
    b = buf(0.5)
    at(b, whoosh(rng, 0.38, 500, 3200, 0.45, q=1.4, body=0.45), 0, 0.9)
    return finish(lp(b, 8000), -8.0, 0.001, 0.05)


def card_flip(rng):
    b = buf(0.35)
    at(b, whoosh(rng, 0.14, 1200, 5000, 0.5, q=1.6, body=0.2), 0, 0.6)
    at(b, noise_hit(rng, 0.05, 3200, 1.4, 0.006), 0.11, 0.9)
    at(b, thump(0.08, 300, 140, 0.01, 0.02), 0.11, 0.25)
    return finish(lp(b, 9000), -6.0, 0.0005, 0.03, shave_db=0.5)


def reveal_common(rng):
    b = buf(0.9)
    at(b, ins.bell(84, 0.7, 0.6, rng, "glock", 0.6), 0, 0.35)
    at(b, ins.fm_bell(72, 0.8, 0.4, rng, 2.0, 1.2, 0.4), 0, 0.12)
    return finish(wet(b, HALL, 0.2), -8.0, 0.0005, 0.1)


def reveal_rare(rng):
    b = buf(1.5)
    for i, m in enumerate([79, 84, 88, 91]):
        at(b, ins.bell(m, 0.9, 0.65, rng, "glock", 0.7), i * 0.05, 0.3)
    at(b, ins.fm_bell(67, 1.2, 0.5, rng, 3.5, 2.0, 0.6), 0, 0.2)
    sh = colored(ns(0.9), rng, -1) * np.exp(-tarr(ns(0.9)) / 0.3)
    at(b, bp(sh, 6000, 2.0), 0.05, 0.05)
    return finish(lp(wet(b, HALL, 0.3), 8500), -5.0, 0.0005, 0.15)


def reveal_epic(rng):
    b = buf(2.2)
    at(b, thump(0.5, 110, 45, 0.03, 0.18), 0, 0.7)
    at(b, whoosh(rng, 0.25, 400, 4000, 0.2, q=1.0, body=0.5), 0, 0.4)
    for i, m in enumerate([74, 79, 83, 86, 91, 95]):
        at(b, ins.fm_bell(m, 1.4, 0.7, rng, 3.5, 2.0, 0.8), 0.05 + i * 0.06, 0.24)
    n = ns(1.6)
    t = tarr(n)
    pad = sum(sine(mtof(m), n) for m in (62, 66, 69, 74)) * np.sin(np.pi * t / 1.6) ** 2
    at(b, pad, 0.1, 0.06)
    return finish(lp(wet(b, HALL, 0.4), 8500), -3.0, 0.0005, 0.25, shave_db=1.5)


def reveal_legendary(rng):
    b = buf(3.4)
    at(b, thump(0.9, 90, 32, 0.04, 0.35), 0, 0.9)
    at(b, noise_hit(rng, 0.5, 400, 0.8, 0.12, "lp"), 0, 0.5)
    at(b, whoosh(rng, 0.4, 300, 6000, 0.15, q=0.9, body=0.6), 0, 0.5)
    chord = [72, 76, 79, 84, 88, 91, 96]
    for i, m in enumerate(chord):
        at(b, ins.fm_bell(m, 2.2, 0.75, rng, 3.5, 2.2, 1.0), 0.08 + i * 0.07, 0.22)
        at(b, ins.bell(m + 12, 1.0, 0.5, rng, "glock", 0.8), 0.6 + i * 0.05, 0.12)
    n = ns(2.8)
    t = tarr(n)
    pad = sum(sine(mtof(m), n) * (1 + 0.003 * np.sin(2 * np.pi * 5 * t)) for m in (60, 64, 67, 72, 76)) \
        * np.sin(np.pi * np.minimum(t / 2.8, 1.0)) ** 1.5
    at(b, pad, 0.15, 0.07)
    sh = colored(ns(2.4), rng, -1) * np.exp(-tarr(ns(2.4)) / 0.9)
    at(b, bp(sh, 7000, 1.5), 0.1, 0.07)
    return finish(lp(wet(b, HALL, 0.45), 9000), -2.0, 0.0005, 0.4, shave_db=1.5)


REGISTRY: dict = {}


def _reg(name, fn, vol_db, loop=False, group=None):
    REGISTRY[name] = (fn, vol_db, loop, group)


for _i in range(3):
    _reg(f"throw_{_i + 1}", _v(throw, _i), -8.0, group="throw")
for _i in range(3):
    _reg(f"ball_hit_{_i + 1}", _v(ball_hit, _i), -5.0, group="ball_hit")
_reg("crit_hit", crit_hit, -3.0)
for _i in range(2):
    _reg(f"glove_catch_{_i + 1}", _v(glove_catch, _i), -6.0, group="glove_catch")
_reg("bat_crack", bat_crack, -3.0)
for _i in range(2):
    _reg(f"enemy_out_{_i + 1}", _v(enemy_out, _i), -5.0, group="enemy_out")
_reg("defender_stunned", defender_stunned, -5.0)
_reg("swing_whoosh", swing_whoosh, -5.0)
_reg("wall_break", wall_break, -4.0)
_reg("shield_block", shield_block, -5.0)
_reg("run_scored", run_scored, -3.0)
_reg("gate_open", gate_open, -4.0)
for _i in range(2):
    _reg(f"footstep_dirt_{_i + 1}", _v(footstep, _i), -10.0, group="footstep_dirt")

_reg("card_draw", card_draw, -6.0)
_reg("card_hover", card_hover, -6.0)
_reg("card_play", card_play, -4.0)
_reg("card_denied", card_denied, -4.0)
_reg("energy_full", energy_full, -5.0)
_reg("fire_cast", fire_cast, -3.0)
_reg("fire_loop", fire_loop, -10.0, loop=True)
_reg("frost_cast", frost_cast, -3.0)
_reg("shadow_cast", shadow_cast, -3.0)
_reg("lightning_zap", lightning_zap, -4.0)
_reg("magnet_pull", magnet_pull, -5.0)
_reg("earth_rumble", earth_rumble, -3.0)
_reg("barrage_impact", barrage_impact, -3.0)
_reg("time_out_whistle", time_out_whistle, -6.0)
_reg("rally_horn", rally_horn, -5.0)
_reg("aura_hum", aura_hum, -6.0)
_reg("heal_chime", heal_chime, -5.0)
_reg("explosion_small", explosion_small, -4.0)

_reg("wave_start", wave_start, -2.0)
_reg("wave_clear", wave_clear, -3.0)
_reg("inning_end", inning_end, -3.0)
_reg("combo_double", combo_double, -4.0)
_reg("combo_triple", combo_triple, -3.0)
_reg("combo_grand", combo_grand, -2.0)
_reg("boss_warning", boss_warning, -2.0)
_reg("boss_slam", boss_slam, -2.0)
_reg("boss_roar", boss_roar, -3.0)
_reg("victory_fanfare", victory_fanfare, -3.0)
_reg("defeat_sting", defeat_sting, -3.0)
_reg("level_up", level_up, -4.0)
_reg("achievement", achievement, -4.0)
_reg("coin", coin, -6.0)
_reg("purchase", purchase, -4.0)

_reg("ui_hover", ui_hover, -6.0)
_reg("ui_click", ui_click, -4.0)
_reg("ui_back", ui_back, -4.0)
_reg("ui_confirm", ui_confirm, -4.0)
_reg("ui_error", ui_error, -4.0)
_reg("ui_tab", ui_tab, -4.0)
_reg("ui_slide", ui_slide, -5.0)
_reg("ui_toggle", ui_toggle, -4.0)

for _i in range(2):
    _reg(f"crowd_cheer_{_i + 1}", _v(crowd_cheer, _i), -6.0, group="crowd_cheer")
_reg("crowd_groan", crowd_groan, -6.0)
_reg("crowd_ooh", crowd_ooh, -6.0)

_reg("pack_shake", pack_shake, -4.0)
_reg("pack_tear", pack_tear, -3.0)
_reg("card_whoosh", card_whoosh, -5.0)
_reg("card_flip", card_flip, -4.0)
_reg("reveal_common", reveal_common, -6.0)
_reg("reveal_rare", reveal_rare, -4.0)
_reg("reveal_epic", reveal_epic, -3.0)
_reg("reveal_legendary", reveal_legendary, -2.0)
