"""Seamless stereo ambience beds (30 s loops)."""
from __future__ import annotations

import numpy as np

from crowd import babble_stream, claps, crowd_burst
from dsp import (SR, TWO_PI, bp, brown, butter, compressor, db2lin, fade, fft_shape, hp, limiter,
                 loop_crossfade, loudness, lp, make_ir, ns, pan, partials, peak, pink,
                 place, reverb, rng_for, sine, smooth, tarr, white)

LOOP_S = 30.0
XFADE_S = 3.0
PRE_S = 3.0  # pre-roll so reverbs/compressors are in steady state


def _finish(x, target_lufs, ceiling_db=-3.0):
    x = x[:, ns(PRE_S):]
    n_loop = ns(LOOP_S)
    y = loop_crossfade(x, n_loop, ns(XFADE_S))
    # circular (FFT) high-pass so the filter has no start-up transient at the seam
    y = fft_shape(y, lambda f: 1.0 / np.sqrt(1.0 + (25.0 / np.maximum(f, 1e-3)) ** 8))
    lu = loudness(y)["integrated"]
    y = y * db2lin(target_lufs - lu)
    if peak(y) > db2lin(ceiling_db):
        # circular limiting so the seam stays continuous
        from dsp import process_circular
        y = process_circular(y, lambda z: limiter(z, ceiling_db, 0.005, 0.2), 3.0)
    return y


def stadium_crowd():
    rng = rng_for("amb:stadium_crowd")
    total = PRE_S + LOOP_S + XFADE_S
    n = ns(total)
    t = tarr(n)
    out = np.zeros((2, n))
    # 1) dense distant murmur: shaped noise with vowel-ish resonances, slow swells
    swell = 1 + 0.25 * np.sin(TWO_PI * t / 11.0) + 0.15 * np.sin(TWO_PI * t / 4.3 + 1)
    for c in range(2):
        nz = pink(n, rng)
        bed = 0.55 * bp(nz, 480, 1.0) + 0.45 * bp(nz, 1050, 1.2) + 0.18 * bp(nz, 2400, 1.4)
        bed *= 1 + 0.3 * smooth(white(n, rng), 0.05) * 8
        out[c] += 0.5 * bed * swell
    # 2) babble: ~30 talkers spread across the stands
    for i in range(30):
        s = babble_stream(rng, total, level=rng.uniform(0.4, 1.0))
        out += pan(s, rng.uniform(-0.95, 0.95)) * 0.18
    # 3) occasional distant cheers / reactions
    events = [(PRE_S + a, m, d) for a, m, d in [(3.5, "cheer", 2.6), (11.0, "ooh", 1.8), (17.5, "cheer", 3.0), (24.5, "cheer", 2.2)]]
    for st, mood, d in events:
        burst = crowd_burst(rng, d, mood, voices=40, clap_rate=60 if mood == "cheer" else 0,
                            bed=0.9, stereo=True)
        burst = lp(burst, 2800)
        place(out, burst * 1.6 / max(peak(burst), 1e-9), ns(st))
    # 4) scattered clapping and a far vendor whistle
    for c in range(2):
        out[c] += 0.25 * lp(claps(rng, total, lambda tt: 3.0 + 25.0 * np.exp(-((tt - PRE_S - 18.5) / 2.0) ** 2)), 3500)
    out = lp(out, 4500)
    hall = make_ir(2.6, 0.05, 0.35, 1.1, 0.2, seed=21)
    w = reverb(out, hall)[:, :n]
    out = 0.65 * out + 0.6 * w
    out = compressor(out, -20, 2.0, 0.05, 0.4, 6)
    return _finish(out, -24.0)


def wind_industrial():
    rng = rng_for("amb:wind_industrial")
    total = PRE_S + LOOP_S + XFADE_S
    n = ns(total)
    t = tarr(n)
    out = np.zeros((2, n))
    # gusty wind: noise through slowly moving band-pass + low rumble
    for c in range(2):
        nz = pink(n, rng)
        g = smooth(white(n, rng), 1.2) * 120
        gust = 0.55 + 0.45 * np.tanh(g + 0.4 * np.sin(TWO_PI * t / 9.0 + c))
        fc = 380 * 2 ** (1.2 * (gust - 0.5))
        from dsp import tvfilt
        w = tvfilt(nz, "bp", fc, 0.8, block=256)
        w += 0.6 * lp(brown(n, rng), 160)
        whistle = tvfilt(white(n, rng), "bp", fc * 3.1, 14.0, block=256) * 0.25
        out[c] += (w + whistle) * gust
    # distant industrial hum (50 Hz family) with slow beating, plus a machine throb
    hum = (sine(50.0, n) + 0.6 * sine(100.3, n) + 0.35 * sine(150.0, n) + 0.2 * sine(199.6, n)
           + 0.12 * sine(250.4, n))
    hum *= 1 + 0.2 * np.sin(TWO_PI * 0.37 * t)
    throb = lp(brown(n, rng), 90) * (0.6 + 0.4 * np.sin(TWO_PI * 0.55 * t) ** 8)
    for c in range(2):
        out[c] += 0.07 * hum + 0.25 * throb
    # distant metal clanks / chain rattles
    hall = make_ir(3.0, 0.06, 0.3, 1.1, 0.2, seed=22)
    dry = np.zeros((2, n))
    times = [PRE_S + a for a in (2.2, 7.9, 12.4, 13.1, 19.6, 24.8, 28.3)]
    for i, st in enumerate(times):
        m = ns(1.6)
        ct = tarr(m)
        f0 = rng.uniform(90, 160)
        cl = partials(f0, m, [(1, 1, 0.5), (2.61, 0.7, 0.4), (4.83, 0.5, 0.3), (7.1, 0.35, 0.22),
                              (9.9, 0.2, 0.15)], rng)
        cl += 0.5 * lp(white(m, rng), 1800) * np.exp(-ct / 0.01)
        cl = lp(cl, 2200)
        if i % 3 == 2:  # chain rattle: a few quick small hits
            for k in range(5):
                place(cl, cl[:ns(0.3)] * 0.4, ns(0.07 * (k + 1)))
        place(dry, pan(cl, rng.uniform(-0.8, 0.8)) * rng.uniform(0.3, 0.6), ns(st))
    wetc = reverb(dry, hall)[:, :n]
    out += 0.15 * dry + 0.7 * wetc
    out = lp(out, 6000)
    return _finish(out, -27.0)


REGISTRY = {
    "stadium_crowd": {"fn": stadium_crowd, "volume_db": -6.0},
    "wind_industrial": {"fn": wind_industrial, "volume_db": -6.0},
}
