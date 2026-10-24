"""Crowd / voice texture generators (cheers, groans, murmur babble, claps)."""
from __future__ import annotations

import numpy as np

from dsp import (SR, TWO_PI, bp, butter, fade, hp, lp, ns, pan, perc, pink, place,
                 smooth, tarr, white)
from instruments import formant_filter, voice_src

CHEER_VOWELS = ["ae", "a", "e", "o", "ah", "ae", "a"]
GROAN_VOWELS = ["o", "u", "o", "a", "ah"]
OOH_VOWELS = ["u", "o", "u"]


def _jitter(rng, n, rate_hz=9.0, depth=0.02):
    k = max(4, int(n / SR * rate_hz) + 2)
    pts = rng.uniform(-1, 1, k)
    return 1.0 + depth * np.interp(np.linspace(0, k - 1, n), np.arange(k), pts)


def voice_gesture(rng, dur, mood, female):
    """One crowd member yelling: pitch contour + vowel + envelope."""
    n = ns(dur)
    t = tarr(n)
    f0 = rng.uniform(175, 290) if female else rng.uniform(100, 175)
    u = t / dur
    if mood == "cheer":
        rise = 2 ** (rng.uniform(4, 10) / 12)
        contour = 1 + (rise - 1) * (1 - np.exp(-t / rng.uniform(0.05, 0.15)))
        contour *= 2 ** (-rng.uniform(1, 4) / 12 * u ** 2)
        vowel = CHEER_VOWELS[rng.integers(len(CHEER_VOWELS))]
        env = np.clip(t / rng.uniform(0.03, 0.1), 0, 1) * np.clip((1 - u) / 0.35, 0, 1) ** 1.5
        env *= 1 + 0.35 * np.sin(TWO_PI * rng.uniform(3, 7) * t + rng.random() * 6) * (rng.random() < 0.4)
    elif mood == "groan":
        contour = 2 ** ((rng.uniform(2, 5) * (1 - u) - rng.uniform(2, 5) * u) / 12)
        vowel = GROAN_VOWELS[rng.integers(len(GROAN_VOWELS))]
        env = np.clip(t / rng.uniform(0.1, 0.25), 0, 1) * np.clip((1 - u) / 0.6, 0, 1) ** 1.2
    else:  # ooh
        contour = 2 ** (rng.uniform(3, 7) * np.sin(np.pi * np.clip(u * 1.2, 0, 1)) / 12)
        vowel = OOH_VOWELS[rng.integers(len(OOH_VOWELS))]
        env = np.sin(np.pi * np.clip(u, 0, 1)) ** 1.2
    freq = f0 * contour * _jitter(rng, n, 9.0, 0.025)
    src = voice_src(freq, n, rng, breath=0.12)
    y = formant_filter(src, vowel, 1.12 if female else 1.0)
    return fade(y * env, 0.005, 0.02)


def claps(rng, dur, rate_fn, seed_gain=1.0):
    """Poisson clapping; rate_fn(t) = claps per second."""
    n = ns(dur)
    out = np.zeros(n)
    t = 0.0
    while t < dur:
        r = max(rate_fn(t), 1e-3)
        t += rng.exponential(1.0 / r)
        if t >= dur:
            break
        m = ns(rng.uniform(0.006, 0.014))
        c = white(m, rng)
        c = bp(c, rng.uniform(900, 2400), rng.uniform(0.8, 1.6)) * perc(m, 0.0004, m / SR / 4)
        place(out, c * rng.uniform(0.3, 1.0) * seed_gain, ns(t))
    return out


def crowd_burst(rng, dur, mood="cheer", voices=48, env_pts=None, clap_rate=0.0,
                bed=0.6, whistles=0, stereo=False):
    """Layered crowd reaction.  Returns mono or stereo (2, n)."""
    n = ns(dur)
    t = tarr(n)
    shape = env_pts or [(0, 0), (0.15, 1.0), (dur * 0.55, 0.8), (dur, 0.0)]
    env = np.interp(t, [p[0] for p in shape], [p[1] for p in shape])
    out = np.zeros((2, n)) if stereo else np.zeros(n)
    for _ in range(voices):
        st = rng.uniform(0, 0.3) if mood != "groan" else rng.uniform(0, 0.25)
        length = rng.uniform(0.55, 0.95) * (dur - st)
        y = voice_gesture(rng, length, mood, rng.random() < 0.4)
        y *= rng.uniform(0.3, 1.0)
        if stereo:
            y = pan(y, rng.uniform(-0.9, 0.9))
        place(out, y, ns(st))
    out /= np.sqrt(voices) * 0.6
    # mass of distant voices: shaped noise with vowel-ish resonances
    chans = 2 if stereo else 1
    beds = []
    for _ in range(chans):
        nz = pink(n, rng)
        b = 0.6 * bp(nz, 520, 1.2) + 0.45 * bp(nz, 1150, 1.4) + 0.2 * bp(nz, 2500, 1.5)
        b *= _jitter(rng, n, 12.0, 0.25)
        beds.append(b)
    bedsig = np.array(beds) if stereo else beds[0]
    out = out + bed * bedsig * env * 0.5
    if clap_rate:
        if stereo:
            for c in range(2):
                out[c] += 0.5 * claps(rng, dur, lambda tt: clap_rate * np.interp(tt, t, env))
        else:
            out += 0.5 * claps(rng, dur, lambda tt: clap_rate * np.interp(tt, t, env))
    for _ in range(whistles):
        st = rng.uniform(0.1, dur * 0.5)
        wl = rng.uniform(0.35, 0.7)
        m = ns(wl)
        tt = tarr(m)
        f = rng.uniform(1700, 2300) * (1 + 0.25 * np.clip(tt / 0.08, 0, 1)) * (1 - 0.1 * tt / wl)
        f *= 1 + 0.01 * np.sin(TWO_PI * 6 * tt)
        w = np.sin(TWO_PI * np.cumsum(f) / SR) * np.sin(np.pi * tt / wl) ** 0.7 * 0.12
        if stereo:
            w = pan(w, rng.uniform(-0.7, 0.7))
        place(out, w, ns(st))
    out = hp(out, 140)
    out = lp(out, 6500)
    return out


def babble_stream(rng, dur, female=None, level=1.0):
    """One distant talker: random syllables with intonation and pauses."""
    n = ns(dur)
    out = np.zeros(n)
    female = rng.random() < 0.45 if female is None else female
    f0 = rng.uniform(180, 250) if female else rng.uniform(100, 150)
    t = rng.uniform(0, 1.0)
    vowels = list("aeiou") + ["ae", "ah"]
    while t < dur:
        if rng.random() < 0.18:
            t += rng.uniform(0.25, 1.4)  # pause between phrases
            continue
        sd = rng.uniform(0.09, 0.26)
        m = ns(sd)
        tt = tarr(m)
        fr = f0 * 2 ** (rng.uniform(-3, 4) / 12) * (1 + rng.uniform(-0.06, 0.06) * tt / sd)
        src = voice_src(fr, m, rng, breath=0.2)
        y = formant_filter(src, vowels[rng.integers(len(vowels))], 1.12 if female else 1.0)
        y *= np.sin(np.pi * tt / sd) ** 1.5 * rng.uniform(0.5, 1.0)
        place(out, y, ns(t))
        t += sd * rng.uniform(0.75, 1.05)
    return out * level
