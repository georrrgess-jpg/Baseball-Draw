"""Music compositions.  Each function returns (stereo float array, metadata).

All pieces are arranged in a tiny in-code score (chord charts, melody strings,
drum grids) and rendered with instruments.py through sequencer.Song.
"""
from __future__ import annotations

import numpy as np

import instruments as ins
from dsp import (SR, TWO_PI, bp, chorus, compressor, delay, fade, filt, hp, leslie, lp,
                 make_ir, mtof, note, ns, peq, saturate, tarr, tremolo, tvfilt, white, width)
from sequencer import Song, bass_note, master_chain, parse_chord, voicing


# ---------------------------------------------------------------------------
# arrangement helpers
# ---------------------------------------------------------------------------
def split_bar(entry: str, beats: int = 4):
    """'Asus4 A' -> [(0, 2, 'Asus4'), (2, 2, 'A')]"""
    syms = entry.split()
    d = beats / len(syms)
    return [(i * d, d, sym) for i, sym in enumerate(syms)]


def first_chord(entry):
    return entry.split()[0]


def last_chord(entry):
    return entry.split()[-1]


def bass_line(s, bus, fn, chart, bars, pattern, lo=28, vel=0.9, gate=0.9, dur_beats=None,
              approach=True, accent=(1.0, 0.75), gain=1.0, **kw):
    """pattern = semitone offsets per step (None = rest); len(pattern) steps per bar.
    The last step approaches the next bar's root from its fifth below."""
    steps = len(pattern)
    step_b = s.bpb / steps
    for bar in bars:
        parts = split_bar(chart[bar], s.bpb)
        nxt = bass_note(first_chord(chart[(bar + 1) % len(chart)]), lo)
        for i, off in enumerate(pattern):
            if off is None:
                continue
            b = i * step_b
            sym = [p for p in parts if p[0] <= b + 1e-6][-1][2]
            r = bass_note(sym, lo)
            m = r + off
            if approach and i == steps - 1 and nxt != r and off == 0:
                m = nxt - 5 if nxt - 5 >= lo - 3 else nxt + 7
            v = vel * (accent[0] if i % 2 == 0 else accent[1])
            s.note(bus, fn, m, bar * s.bpb + b, dur_beats or step_b * gate, v, gain=gain, **kw)


def pad_chords(s, bus, fn, chart, bars, center=62, notes=4, vel=0.6, legato=1.0, gain=1.0,
               rhythm=None, strum=0.0, **kw):
    """Sustained chords; rhythm = [(beat, dur_beats), ...] per bar to make stabs."""
    for bar in bars:
        for off, d, sym in split_bar(chart[bar], s.bpb):
            v = voicing(sym, center, notes)
            hits = rhythm if rhythm is not None else [(0, d)]
            for hb, hd in hits:
                if rhythm is not None and not (off - 1e-6 <= hb < off + d - 1e-6):
                    continue
                for k, m in enumerate(v):
                    s.note(bus, fn, m, bar * s.bpb + hb + k * strum, hd * legato, vel, gain=gain, **kw)


def arp(s, bus, fn, chart, bars, center=66, order=(0, 1, 2, 3, 4, 3, 2, 1), steps=16, vel=0.7,
        notes=3, gain=1.0, dur=0.9, **kw):
    sb = s.bpb / steps
    for bar in bars:
        parts = split_bar(chart[bar], s.bpb)
        for i in range(steps):
            b = i * sb
            sym = [p for p in parts if p[0] <= b + 1e-6][-1][2]
            v = voicing(sym, center, notes)
            ext = v + [x + 12 for x in v]
            m = ext[order[i % len(order)] % len(ext)]
            acc = 1.0 if i % 4 == 0 else 0.78
            s.note(bus, fn, m, bar * s.bpb + b, sb * dur, vel * acc, gain=gain, **kw)


def riser(seconds, rng, f0=300, f1=6000):
    n = ns(seconds)
    t = tarr(n)
    u = t / seconds
    x = tvfilt(white(n, rng), "bp", f0 * (f1 / f0) ** (u ** 1.5), 2.0)
    x += 0.3 * tvfilt(white(n, rng), "hp", 1000 + 6000 * u, 0.7)
    return fade(x * u ** 2.2 * 0.5, 0.01, 0.02)


def impact(rng, f0=70, decay=0.6):
    n = ns(decay * 4)
    t = tarr(n)
    x = np.sin(TWO_PI * np.cumsum(f0 * 0.5 + f0 * 0.5 * np.exp(-t / 0.08)) / SR) * np.exp(-t / decay)
    x += 0.4 * lp(white(n, rng), 1500) * np.exp(-t / 0.05)
    return fade(np.tanh(1.5 * x), 0.0, 0.1)


def chain(*fns):
    def run(x):
        for f in fns:
            x = f(x)
        return x
    return run


def bars(a, b):
    return list(range(a, b))


# ---------------------------------------------------------------------------
# kits
# ---------------------------------------------------------------------------
def kit_rock(rng, kick_f=(155, 50), kick_decay=0.3, snare_f=200, snare_decay=0.2, hat_gain=0.26,
             bright=1.0):
    return {
        "k": ([ins.kick(rng, kick_f[0], kick_f[1], 0.03, kick_decay, 0.7, 2.0) for _ in range(2)], 0.95, 0.0, "kick"),
        "s": ([ins.snare(rng, snare_f, 0.08, snare_decay, 0.85, bright=bright) for _ in range(3)], 0.8, 0.0, "snare"),
        "c": ([ins.clap(rng) for _ in range(3)], 0.5, 0.05, "snare"),
        "st": ([ins.stomp(rng) for _ in range(3)], 0.85, 0.0, "kick"),
        "h": ([ins.hat(rng) for _ in range(4)], hat_gain, 0.28, "hats"),
        "oh": ([ins.hat(rng, True)], hat_gain * 0.9, 0.28, "hats"),
        "sh": ([ins.shaker(rng) for _ in range(3)], 0.3, -0.35, "hats"),
        "cr": ([ins.crash(rng)], 0.42, -0.35, "hats"),
        "cr2": ([ins.crash(rng, 1.2, 2.2, 1.1)], 0.38, 0.4, "hats"),
        "rd": ([ins.ride(rng)], 0.3, 0.35, "hats"),
        "t1": ([ins.tom(rng, 185)], 0.6, 0.35, "toms"),
        "t2": ([ins.tom(rng, 135)], 0.62, 0.0, "toms"),
        "t3": ([ins.tom(rng, 92, 0.38)], 0.66, -0.35, "toms"),
        "tk": ([ins.taiko(rng, 62)], 0.8, 0.0, "toms"),
        "tk2": ([ins.taiko(rng, 82, 0.5)], 0.7, -0.2, "toms"),
        "rim": ([ins.rim(rng)], 0.4, 0.1, "snare"),
        "sn": ([ins.snap(rng)], 0.4, -0.1, "snare"),
    }


FILL_TOMS = {"t1": "xx......", "t2": "..xx....", "t3": "....xx..", "s": "......xX"}
FILL_SNARE = {"s": "x.x.xxxX", "k": "x...x..."}
FILL_TOMS_LONG = {"t1": "xxxx............", "t2": "....xxxx........", "t3": "........xxxx....",
                  "s": "............xxXX", "k": "x...x...x...x..."}


def fill(s, bar, kit, kind=FILL_TOMS, beats=2):
    s.drums(bar, kind, kit, beats=beats, start=s.bpb - beats)


# ---------------------------------------------------------------------------
# MENU THEME  –  D major, 116 BPM, 44 bars (~91 s)
# ---------------------------------------------------------------------------
def menu_theme():
    s = Song("menu_theme", 116, 44, tail=6.0)
    rng = s.rng
    kit = kit_rock(rng)
    I_ = ["D", "G/D", "D", "A"]
    A = ["D", "G", "Em", "A", "D", "G", "A", "D"]
    B = ["Bm", "G", "D", "A", "Bm", "G", "E7", "A"]
    C = ["G", "A", "F#m", "Bm", "G", "A", "Em7", "Asus4 A"]
    O = ["D", "G", "D", "A", "D", "G", "Em", "A"]
    chart = I_ + A + B + C + A + O
    SEC_A, SEC_B, SEC_C, SEC_A2, SEC_O = 4, 12, 20, 28, 36

    mel_A = ("A4:0.5 D5:0.5 F#5:1.5 E5:0.5 D5:1 | B4:1 D5:0.5 G5:1.5 F#5:0.5 E5:0.5 | "
             "E5:1 G5:1 B5:1.5 A5:0.5 | A5:3 r:0.5 A4:0.5 | D5:0.5 F#5:0.5 A5:1.5 F#5:0.5 A5:0.5 B5:0.5 | "
             "B5:1.5 A5:0.5 G5:1 F#5:0.5 G5:0.5 | A5:1 E5:1 F#5:0.5 G5:0.5 E5:1 | D5:3 r:1")
    riff_B1 = ("B4:0.5 D5:0.5 F#5:0.5 B5:1 A5:0.5 F#5:1 | G5:0.5 F#5:0.5 E5:0.5 D5:0.5 B4:1 r:1 | "
               "A4:0.5 D5:0.5 F#5:0.5 A5:1 G5:0.5 F#5:1 | E5:0.5 F#5:0.5 E5:0.5 C#5:0.5 A4:1 r:1 | ")
    riff_B2 = ("B4:0.5 D5:0.5 F#5:0.5 B5:1 C#6:0.5 D6:1 | D6:0.5 C#6:0.5 B5:0.5 A5:0.5 G5:1 B5:1 | "
               "G#5:1 B5:1 E6:1 D6:1 | C#6:1.5 B5:0.5 A5:1 r:1")
    riff_B = riff_B1 + riff_B2
    mel_C = ("B4:2 A4:1 G4:1 | A4:3 E4:1 | F#4:2 E4:1 C#4:1 | D4:2 F#4:1 B4:1 | "
             "G4:1 B4:1 D5:2 | E5:3 C#5:1 | D5:2 B4:1 G4:1 | D5:2 C#5:2")
    mel_O = ("F#5:1.5 E5:0.5 D5:1 A4:1 | B4:1.5 D5:0.5 G5:2 | F#5:1.5 E5:0.5 D5:1 F#5:1 | E5:3 r:1 | "
             "F#5:1.5 A5:0.5 D6:2 | B5:1.5 A5:0.5 G5:2 | G5:1 F#5:1 E5:1 D5:1 | C#5:2 E5:1 A5:1")

    # ---- drums ----
    P_STOMP = {"st": "x.x.....x.x.....", "c": "....x.......x..."}
    P_A = {"k": "x.....x.x.......", "s": "....x.......x...", "c": "....x.......x...",
           "h": "x.x.x.x.x.x.x.x."}
    P_B = {"k": "x.....x.x.x.....", "s": "....x.......x...", "c": "....x.......x...",
           "oh": "..x...x...x...x.", "h": "x...x...x...x..."}
    P_C = {"k": "x.......x.......", "t3": "x.......x.......", "t2": "......x.......x.", "rd": "x.x.x.x.x.x.x.x."}
    for bar in range(44):
        if bar < 2:
            s.drums(bar, P_STOMP, kit)
        elif bar < 4:
            s.drums(bar, {**P_STOMP, "k": "x.......x.......", "h": "x.x.x.x.x.x.x.x."}, kit)
        elif SEC_A <= bar < SEC_B or SEC_A2 <= bar < SEC_O or bar >= SEC_O:
            pat = dict(P_A)
            if bar >= SEC_A2:
                pat["k"] = "x.....x.x.x....."
                pat["h"] = "x.x.x.x.x.x.x.xx"
            s.drums(bar, pat, kit)
        elif SEC_B <= bar < SEC_C:
            s.drums(bar, P_B, kit)
        else:  # bridge build
            if bar < SEC_C + 6:
                s.drums(bar, {**P_C, "s": "............x..." if bar % 2 else "................"}, kit)
            elif bar == SEC_C + 6:
                s.drums(bar, {"k": "x...x...x...x...", "s": "o.o.o.o.x.x.x.x.", "t3": "x.......x......."}, kit)
            else:
                s.drums(bar, {"k": "x...x...x...x...", "s": "xxxxxxxxxxxxXXXX", "cr": "................"}, kit)
        if bar in (SEC_A, SEC_B, SEC_C, SEC_A2, SEC_O, SEC_A2 + 4, SEC_O + 4, 2):
            s.drums(bar, {"cr": "x"}, kit)
        if bar in (SEC_B - 1, SEC_C - 1, SEC_O - 1, 43):
            fill(s, bar, kit, FILL_TOMS)
        if bar == 3:
            s.drums(bar, {"s": "ooxxxxXX"}, kit, beats=2, start=2)
        if bar in (SEC_A + 3, SEC_A2 + 3, SEC_O + 3):
            fill(s, bar, kit, FILL_SNARE, beats=1)

    # ---- bass ----
    E8 = [0] * 8
    bass_line(s, "bass", ins.bass_finger, chart, [2], [0, None, None, None, None, None, None, None],
              lo=33, vel=0.9, dur_beats=3.8, bright=1.3)
    bass_line(s, "bass", ins.bass_finger, chart, [3], E8, lo=33, vel=0.85, bright=1.3)
    bass_line(s, "bass", ins.bass_finger, chart, bars(SEC_A, SEC_B) + bars(SEC_A2, 44), E8, lo=33,
              vel=0.9, bright=1.3)
    bass_line(s, "bass", ins.bass_finger, chart, bars(SEC_B, SEC_C), [0, 0, 12, 0, 0, 0, 12, 0], lo=33,
              vel=0.9, bright=1.3)
    bass_line(s, "bass", ins.bass_finger, chart, bars(SEC_C, SEC_C + 6), [0, 7, 12, 7], lo=33, vel=0.85,
              bright=1.2, approach=False)
    bass_line(s, "bass", ins.bass_finger, chart, bars(SEC_C + 6, SEC_A2), E8, lo=33, vel=0.9, bright=1.3)

    # ---- organ ----
    org = dict(drawbars="688866448", click=0.2)
    pad_chords(s, "organ", ins.organ, chart, bars(0, 4), center=62, notes=4, vel=0.85, **org)
    pad_chords(s, "organ", ins.organ, chart, bars(SEC_A, SEC_B), center=62, notes=4, vel=0.6,
               rhythm=[(0, 1.4), (1.5, 1.0), (2.5, 1.4)], legato=0.95, **org)
    s.melody("organ", ins.organ, riff_B, SEC_B * 4, vel=1.0, legato=0.9, octave_double=-1, **org)
    pad_chords(s, "organ", ins.organ, chart, bars(SEC_B, SEC_C), center=55, notes=3, vel=0.45, **org)
    pad_chords(s, "organ", ins.organ, chart, bars(SEC_C, SEC_A2), center=60, notes=4, vel=0.6, **org)
    pad_chords(s, "organ", ins.organ, chart, bars(SEC_A2, SEC_O), center=60, notes=4, vel=0.55,
               rhythm=[(0, 1.4), (1.5, 1.0), (2.5, 1.4)], legato=0.95, **org)
    s.melody("organ", ins.organ, mel_A, SEC_A2 * 4, transpose=-12, vel=0.6, legato=0.92, **org)
    pad_chords(s, "organ", ins.organ, chart, bars(SEC_O, 44), center=62, notes=4, vel=0.75,
               rhythm=[(0, 1.2), (1.5, 1.2), (3, 0.9)], legato=0.9, **org)

    # ---- brass ----
    br = dict(bright=1.0, attack=0.035, rel=0.12)
    pad_chords(s, "brass", ins.brass, chart, [3], center=60, notes=4, vel=0.8,
               rhythm=[(0, 3.5)], attack=0.6, rel=0.2)
    s.melody("brass", ins.brass, mel_A, SEC_A * 4, vel=1.0, legato=0.92, octave_double=-1, **br)
    for b_ in (SEC_B + 1, SEC_B + 3):
        pad_chords(s, "brass", ins.brass, chart, [b_], center=64, notes=3, vel=0.9,
                   rhythm=[(3.0, 0.35), (3.5, 0.45)], **br)
    pad_chords(s, "brass", ins.brass, chart, [SEC_B + 7], center=64, notes=3, vel=0.9,
               rhythm=[(3.0, 0.9)], **br)
    s.melody("brass", ins.brass, mel_C, SEC_C * 4, vel=0.9, legato=0.97, attack=0.06, bright=0.85,
             rel=0.2)
    s.melody("brass", ins.brass, mel_A, SEC_A2 * 4, vel=1.0, legato=0.92, octave_double=-1, **br)
    pad_chords(s, "brass", ins.brass, chart, bars(SEC_O, SEC_O + 4), center=62, notes=4, vel=0.85,
               rhythm=[(0, 1.2), (1.5, 1.2), (3, 0.9)], legato=0.9, **br)
    s.melody("brass", ins.brass, mel_O, SEC_O * 4, vel=1.0, legato=0.92, octave_double=-1, **br)

    # ---- strings & bells ----
    pad_chords(s, "strings", ins.strings, chart, bars(SEC_C, SEC_A2), center=72, notes=4, vel=0.6)
    pad_chords(s, "strings", ins.strings, chart, bars(SEC_A2, 44), center=74, notes=3, vel=0.45)
    s.melody("bells", ins.bell, mel_A, SEC_A2 * 4, transpose=12, vel=0.6, legato=1.0)
    s.melody("bells", ins.bell, riff_B2, SEC_B * 4 + 16, vel=0.4, legato=1.0)

    # ---- fx ----
    s.add("fx", riser(s.secs(8), rng), (SEC_A2 - 2) * 4, 0.8)
    s.add("fx", riser(s.secs(4), rng, 400, 5000), (SEC_A - 1) * 4, 0.5)
    for b_ in (SEC_A, SEC_A2):
        s.add("fx", impact(rng, 60, 0.5), b_ * 4, 0.6)

    chains = {
        "kick": lambda x: compressor(x, -10, 3, 0.003, 0.08, 4),
        "snare": chain(lambda x: peq(x, 200, 2, 1), lambda x: compressor(x, -14, 3, 0.002, 0.1, 6, 3)),
        "hats": lambda x: hp(x, 400),
        "bass": chain(lambda x: compressor(x, -16, 4, 0.005, 0.12, 6, 2), lambda x: lp(x, 5000)),
        "organ": chain(lambda x: saturate(x, 1.8), lambda x: leslie(x, 6.3, 0.8), lambda x: hp(x, 110),
                       lambda x: peq(x, 2500, 2, 0.8)),
        "brass": chain(lambda x: hp(x, 120), lambda x: peq(x, 1200, 2.5, 0.9), lambda x: chorus(x, 0.4, 2.0, 9, 0.25),
                       lambda x: compressor(x, -18, 2.5, 0.01, 0.2, 6, 1.5)),
        "strings": chain(lambda x: chorus(x, 0.5, 3.0, 12, 0.4), lambda x: hp(x, 200)),
        "bells": lambda x: width(chorus(x, 0.8, 1.5, 8, 0.3), 1.3),
        "toms": lambda x: compressor(x, -14, 3, 0.003, 0.1, 6),
        "fx": lambda x: width(chorus(x, 0.3, 4, 15, 0.5), 1.4),
    }
    levels = {"kick": -4.3, "snare": -1.8, "hats": 1, "toms": -3, "bass": -1.6, "organ": -12, "brass": 0.3,
              "strings": -2, "bells": -4.5, "fx": -5}
    sends = {"snare": (0.1, 0.32), "brass": (0.1, 0.22), "organ": (0.08, 0.18), "strings": (0, 0.35),
             "bells": (0, 0.35), "toms": (0.1, 0.25), "hats": (0.05, 0.1), "kick": (0.05, 0.05),
             "fx": (0, 0.3)}
    out = s.render(chains, levels, sends, hall=make_ir(2.2, 0.03, 0.4, 1.1, 0.25, seed=31))
    return out, {"bpm": 116, "bars": 44, "beats_per_bar": 4, "key": "D major"}


# ---------------------------------------------------------------------------
# BATTLE THEME  –  E minor, 134 BPM, 60 bars (~107 s)
# ---------------------------------------------------------------------------
def battle_theme():
    s = Song("battle_theme", 134, 60, tail=6.0)
    rng = s.rng
    kit = kit_rock(rng, kick_f=(170, 52), kick_decay=0.24, snare_f=215, snare_decay=0.17, hat_gain=0.24)
    I_ = ["Em", "C", "D", "Bsus4 B"]
    A = ["Em", "C", "D", "Em", "Em", "C", "Am", "B"]
    Bc = ["Am", "Em", "C", "D", "Am", "Em", "C", "B7"]
    BRK = ["C", "D", "Em", "Em", "C", "D", "B", "B"]
    O = ["Em", "C", "D", "Em", "C", "D", "B", "B"]
    chart = I_ + A + A + Bc + Bc + BRK + A + O
    S_A1, S_A2, S_B1, S_B2, S_BRK, S_A3, S_O = 4, 12, 20, 28, 36, 44, 52

    hook = ("E5:0.75 G5:0.75 B5:0.5 A5:0.5 G5:0.5 F#5:0.5 G5:0.5 | E5:0.75 G5:0.75 C6:1 B5:0.5 G5:1 | "
            "F#5:0.75 A5:0.75 D6:1 C6:0.5 A5:0.5 F#5:0.5 | G5:1.5 F#5:0.5 E5:2 | ")
    hook_a = hook + ("E5:0.75 G5:0.75 B5:0.5 A5:0.5 G5:0.5 F#5:0.5 G5:0.5 | E5:0.75 G5:0.75 C6:0.5 D6:0.5 E6:1.5 | "
                     "C6:0.75 B5:0.75 A5:0.5 E5:0.5 A5:0.5 C6:1 | B5:1.5 A5:0.5 G5:0.5 F#5:0.5 D#5:1")
    hook_b = hook + ("B5:0.75 G5:0.75 E6:0.5 D6:0.5 B5:0.5 A5:0.5 G5:0.5 | E6:0.75 D6:0.75 C6:0.5 B5:0.5 C6:0.5 E6:1 | "
                     "A5:0.75 B5:0.75 C6:0.5 D6:0.5 E6:1.5 | D#6:1 F#6:1 B5:2")
    mel_B = ("A5:1.5 C6:0.5 B5:1 A5:1 | G5:1.5 B5:0.5 E5:2 | E5:1 G5:1 C6:1 E6:1 | D6:2 C6:0.5 B5:0.5 A5:1 | "
             "A5:1.5 C6:0.5 E6:1 D6:1 | B5:1.5 G5:0.5 E5:2 | C6:1 B5:1 A5:1 G5:1 | F#5:2 D#5:2")
    mel_brk = ("E5:1.5 G5:0.5 B5:2 | A5:1.5 F#5:0.5 D5:2 | E5:1.5 G5:0.5 B5:1.5 C6:0.5 | B5:4 | "
               "E6:1.5 D6:0.5 B5:2 | A5:1.5 B5:0.5 F#5:2 | D#5:1 F#5:1 A5:1 B5:1 | D#6:4")
    mel_O = hook + ("E6:0.75 D6:0.75 C6:0.5 B5:0.5 C6:0.5 E6:1 | D6:0.75 C6:0.75 A5:0.5 F#5:0.5 A5:0.5 D6:1 | "
                    "B5:1.5 A5:0.5 G5:0.5 F#5:0.5 D#5:1 | F#5:4")

    kicks = []

    def dr(bar, pat, **kw):
        s.drums(bar, pat, kit, **kw)
        if "k" in pat and not kw:
            p = pat["k"].replace(" ", "")
            kicks.extend(bar * 4 + i * 4 / len(p) for i, c in enumerate(p) if c in "xX")

    P_ROCK = {"k": "x.....x.x.....x.", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."}
    P_ROCK16 = {"k": "x.....x.x.x...x.", "s": "....x.......x...", "h": "xxxxxxxxxxxxxxxx".replace("x", "x"),
                "c": "....x.......x..."}
    P_FOUR = {"k": "x...x...x...x...", "c": "....x.......x...", "oh": "..x...x...x...x.",
              "h": "x.xxx.xxx.xxx.xx", "s": "....o.......o..."}
    P_HALF = {"k": "x.........x.....", "t3": "x.......x.......", "rd": "x...x...x...x..."}
    for bar in range(60):
        if bar < S_A1:
            # intro: filtered four-on-the-floor builds in
            s.drums(bar, {"k": "x...x...x...x..." if bar >= 1 else "x.......x.......",
                          "h": "..x...x...x...x." if bar >= 2 else "................"}, kit_intro(kit))
            if bar == 3:
                s.drums(bar, {"s": "ooooxxxxxxxxXXXX"}, kit_intro(kit), beats=4)
        elif bar < S_A2:
            dr(bar, P_ROCK)
        elif bar < S_B1:
            dr(bar, P_ROCK16)
        elif bar < S_B2:
            dr(bar, P_FOUR)
        elif bar < S_BRK:
            pat = dict(P_FOUR)
            if bar >= S_BRK - 2:
                pat["s"] = "xxxxxxxxxxxxXXXX" if bar == S_BRK - 1 else "x.x.x.x.x.x.x.x."
            dr(bar, pat)
        elif bar < S_A3:
            if bar < S_BRK + 4:
                dr(bar, P_HALF)
            elif bar < S_BRK + 6:
                dr(bar, {"k": "x...x...x...x...", "t3": "x.......x.......", "h": "..x...x...x...x."})
            else:
                dr(bar, {"k": "x...x...x...x...", "s": "x.x.x.x.x.x.x.x." if bar == S_A3 - 2 else "xxxxxxxxxxxxXXXX",
                         "h": "x.x.x.x.x.x.x.x."})
        elif bar < S_O:
            dr(bar, P_ROCK16)
        else:
            dr(bar, P_ROCK if bar < S_O + 4 else P_ROCK16)
        if bar in (S_A1, S_A2, S_B1, S_B2, S_A3, S_O, S_A1 + 4, S_A2 + 4, S_A3 + 4, S_B1 + 4, S_B2 + 4):
            s.drums(bar, {"cr": "x"}, kit)
        if bar in (S_A2 - 1, S_B1 - 1, S_B2 - 1, S_O - 1, 59):
            fill(s, bar, kit, FILL_TOMS)
        if bar in (S_A1 + 3, S_A2 + 3, S_A3 + 3, S_O + 3):
            fill(s, bar, kit, FILL_SNARE, beats=1)

    # ---- bass ----
    bs = dict(cutoff=4.5, decay_f=0.12, drive=2.2)
    bass_line(s, "bass", ins.bass_synth, chart, bars(2, 4), [0, None, 0, None, 0, None, 0, None], lo=28, vel=0.8, **bs)
    rock8 = [0, 0, 0, 0, 0, 0, 12, 0]
    bass_line(s, "bass", ins.bass_synth, chart, bars(S_A1, S_B1) + bars(S_A3, 60), rock8, lo=28, vel=0.95, **bs)
    bass_line(s, "bass", ins.bass_synth, chart, bars(S_B1, S_BRK), [None, 12, None, 12, None, 12, None, 12],
              lo=28, vel=0.95, approach=False, **bs)
    bass_line(s, "bass", ins.bass_sub, chart, bars(S_BRK, S_BRK + 6), [0, None, None, None], lo=28, vel=0.9,
              dur_beats=3.6, approach=False)
    bass_line(s, "bass", ins.bass_synth, chart, bars(S_BRK + 6, S_A3), [0] * 8, lo=28, vel=0.9, **bs)

    # ---- guitars (double-tracked: two independent renders panned hard L/R) ----
    for var, gname in ((1, "gtrL"), (2, "gtrR")):
        gk = dict(jitter=0.007, variant=var, pan_=-0.8 if var == 1 else 0.8)
        for bar in bars(S_A1, S_B1) + bars(S_A3, 60):
            r = bass_note(first_chord(chart[bar]), 40)
            if bar < S_A2:  # A1: tight palm-muted eighths
                for i in range(8):
                    s.note(gname, ins.power_chord, r, bar * 4 + i * 0.5, 0.45, 0.85 if i % 2 == 0 else 0.7,
                           mute=True, octave=False, **gk)
            elif bar == 59:  # last bar: let it ring into the loop point
                s.note(gname, ins.power_chord, r, bar * 4, 3.6, 0.9, **gk)
            else:  # open hit + chugs
                s.note(gname, ins.power_chord, r, bar * 4, 1.4, 0.95, **gk)
                for i in (3, 4, 5, 7):
                    s.note(gname, ins.power_chord, r, bar * 4 + i * 0.5, 0.4, 0.75, mute=True, octave=False, **gk)
                s.note(gname, ins.power_chord, r, bar * 4 + 3.0, 0.45, 0.9, **gk)
        for bar in bars(S_B2, S_BRK):
            for off, d, sym in split_bar(chart[bar]):
                r = bass_note(sym, 40)
                s.note(gname, ins.power_chord, r, bar * 4 + off, 1.4, 0.85, **gk)
                s.note(gname, ins.power_chord, r, bar * 4 + off + 1.5, 2.3, 0.8, **gk)

    # ---- arp / pads / lead ----
    arp(s, "arp", ins.pluck, chart, bars(0, S_A2) + bars(S_B1, S_A3), center=64, vel=0.7, bright=0.9)
    arp(s, "arp", ins.pluck, chart, bars(S_A3, 60), center=71, vel=0.5, bright=0.8, order=(0, 2, 1, 3, 2, 4, 3, 5))
    pad_chords(s, "pad", ins.pad, chart, bars(S_A2, 60), center=67, notes=4, vel=0.55, attack=0.25, rel=0.6)
    pad_chords(s, "pad", ins.strings, chart, bars(S_BRK, S_A3), center=72, notes=3, vel=0.55)
    ld = dict(cutoff=3400, vib=0.8)
    s.melody("lead", ins.lead, hook_a, S_A1 * 4, vel=0.95, legato=0.9, **ld)
    s.melody("lead", ins.lead, hook_b, S_A2 * 4, vel=0.95, legato=0.9, **ld)
    s.melody("lead", ins.lead, hook_b, S_A2 * 4, transpose=-12, vel=0.45, legato=0.9, **ld)
    s.melody("lead2", ins.lead, mel_B, S_B1 * 4, vel=0.9, legato=0.96, saw_mix=0.85, cutoff=4200, glide=True)
    s.melody("lead2", ins.lead, mel_B, S_B2 * 4, vel=0.95, legato=0.96, saw_mix=0.85, cutoff=4200, glide=True)
    s.melody("lead2", ins.lead, mel_B, S_B2 * 4, transpose=-12, vel=0.5, legato=0.96, saw_mix=0.85, cutoff=3000)
    s.melody("bells", ins.bell, mel_brk, S_BRK * 4, vel=0.8, legato=1.0)
    s.melody("bells", ins.pluck, mel_brk, S_BRK * 4, transpose=-12, vel=0.45, legato=0.9, decay=0.5)
    s.melody("lead", ins.lead, hook_a, S_A3 * 4, vel=1.0, legato=0.9, **ld)
    s.melody("lead", ins.lead, hook_a, S_A3 * 4, transpose=-12, vel=0.5, legato=0.9, **ld)
    s.melody("lead", ins.lead, mel_O, S_O * 4, vel=0.95, legato=0.9, **ld)

    # ---- fx ----
    s.add("fx", riser(s.secs(8), rng), (S_A3 - 2) * 4, 0.9)
    s.add("fx", riser(s.secs(4), rng, 300, 5000), (S_A1 - 1) * 4, 0.7)
    s.add("fx", riser(s.secs(4), rng, 300, 5000), (S_B1 - 1) * 4, 0.5)
    for b_ in (S_A1, S_B1, S_A3):
        s.add("fx", impact(rng, 55, 0.5), b_ * 4, 0.7)

    duck = s.duck(kicks, depth=0.45, release=0.16)
    intro_cut = np.interp(np.arange(s.N), [0, s.loop_n * 3.6 / 60, s.loop_n * 4 / 60, s.N], [500, 3000, 16000, 16000])
    chains = {
        "kick": lambda x: compressor(x, -10, 3, 0.003, 0.08, 4),
        "snare": chain(lambda x: peq(x, 220, 2, 1), lambda x: compressor(x, -14, 3, 0.002, 0.1, 6, 3)),
        "hats": lambda x: hp(x, 500),
        "intro": lambda x: tvfilt(x, "lp", intro_cut, 0.9, block=256),
        "bass": chain(lambda x: x * duck ** 0.5, lambda x: compressor(x, -16, 4, 0.004, 0.1, 6, 2)),
        "gtrL": lambda x: hp(x, 100), "gtrR": lambda x: hp(x, 100),
        "arp": chain(lambda x: x * duck, lambda x: x + 0.35 * delay(x, s.secs(0.75), 0.4, 5, 3000)[:, :x.shape[-1]],
                     lambda x: hp(x, 250)),
        "pad": chain(lambda x: x * duck, lambda x: chorus(x, 0.4, 3, 12, 0.5), lambda x: hp(x, 200)),
        "lead": chain(lambda x: x + 0.3 * delay(x, s.secs(0.75), 0.35, 4, 2800)[:, :x.shape[-1]],
                      lambda x: compressor(x, -18, 3, 0.005, 0.1, 6, 2), lambda x: hp(x, 200)),
        "lead2": chain(lambda x: chorus(x, 0.6, 2.5, 10, 0.35),
                       lambda x: x + 0.3 * delay(x, s.secs(0.5), 0.35, 4, 2800)[:, :x.shape[-1]],
                       lambda x: hp(x, 200)),
        "bells": lambda x: x + 0.4 * delay(x, s.secs(0.75), 0.45, 6, 3500)[:, :x.shape[-1]],
        "toms": lambda x: compressor(x, -14, 3, 0.003, 0.1, 6),
        "fx": lambda x: width(chorus(x, 0.3, 4, 15, 0.5), 1.4),
    }
    levels = {"kick": -4, "snare": -1.6, "hats": 2, "toms": -3, "intro": -6.5, "bass": -1.2, "gtrL": -7,
              "gtrR": -7, "arp": -4, "pad": -3, "lead": 1.5, "lead2": 3, "bells": -3.4, "fx": -5}
    sends = {"snare": (0.1, 0.25), "toms": (0.1, 0.2), "lead": (0.05, 0.15), "lead2": (0.05, 0.2),
             "pad": (0, 0.3), "arp": (0, 0.2), "bells": (0, 0.35), "gtrL": (0.08, 0), "gtrR": (0.08, 0),
             "fx": (0, 0.3), "intro": (0.05, 0.1)}
    out = s.render(chains, levels, sends, hall=make_ir(1.9, 0.02, 0.4, 1.1, 0.25, seed=32))
    return out, {"bpm": 134, "bars": 60, "beats_per_bar": 4, "key": "E minor",
                 "sections": {"intro": 0, "A1": 4, "A2": 12, "B1": 20, "B2": 28, "breakdown": 36, "A3": 44,
                              "outro": 52}}


def kit_intro(kit):
    return {k: (v[0], v[1], v[2], "intro") for k, v in kit.items()}


# ---------------------------------------------------------------------------
# BOSS THEME  –  C minor, 146 BPM, 48 bars (~79 s)
# ---------------------------------------------------------------------------
def boss_theme():
    s = Song("boss_theme", 146, 48, tail=6.0)
    rng = s.rng
    kit = kit_rock(rng, kick_f=(160, 48), kick_decay=0.2, snare_f=175, snare_decay=0.22, hat_gain=0.2)
    I_ = ["Cm", "Db", "Cm", "G"]
    A = ["Cm", "Cm", "Ab", "Ab", "Fm", "Fm", "G", "G"]
    B = ["Ab", "Fm", "Db", "G", "Ab", "Fm", "Db", "G7"]
    BRK = ["Cm", "Db", "Cm", "Db", "Ab", "Ab", "G", "G"]
    C = ["Fm", "Cm", "Ab", "G", "Fm", "Cm", "Db", "G"]
    T = ["Cm", "Ab", "G", "G"]
    chart = I_ + A + B + A + BRK + C + T
    S_A, S_B, S_A2, S_BRK, S_C, S_T = 4, 12, 20, 28, 36, 44

    low_A = ("C3:2 Eb3:1 D3:1 | C3:1.5 G2:0.5 Ab2:1 G2:1 | Ab2:2 C3:1 Eb3:1 | D3:2 Eb3:1 C3:1 | "
             "F3:2 Ab3:1 G3:1 | F3:1.5 Eb3:0.5 D3:1 C3:1 | B2:2 D3:1 F3:1 | G3:3 r:1")
    mel_B = ("C5:2 Eb5:1 C5:1 | Ab4:2 F4:1 Ab4:1 | Db5:2 Ab4:1 F4:1 | B4:3 G4:1 | "
             "C5:2 Eb5:1 F5:1 | Ab5:2 F5:1 Eb5:1 | F5:2 Eb5:1 Db5:1 | D5:2 B4:2")
    mel_brk = ("C5:3 D5:0.5 Eb5:0.5 | F5:3 Eb5:0.5 Db5:0.5 | C5:2 G4:2 | Ab4:4 | C5:2 Eb5:2 | F5:2 Eb5:2 | "
               "B4:4 | D5:2 F5:2")
    mel_C = ("F5:2 Ab5:1 G5:1 | Eb5:2 G5:1 F5:1 | Eb5:1.5 D5:0.5 C5:2 | B4:2 D5:2 | "
             "F5:2 Ab5:1 C6:1 | C6:2 G5:2 | Ab5:2 F5:1 Db5:1 | D5:2 B4:1 G4:1")

    MIN = [0, 0, 3, 0, 2, 0, 3, 5, 0, 0, 3, 0, 7, 5, 3, 2]
    MAJ = [0, 0, 4, 0, 2, 0, 4, 5, 0, 0, 4, 0, 7, 5, 4, 2]
    DOM = [0, 0, 4, 0, 1, 0, 4, 5, 0, 0, 4, 0, 7, 5, 4, 1]

    def ostinato(bar_list, vel=0.75, lo=53, bus="ost"):
        for bar in bar_list:
            sym = first_chord(chart[bar])
            root, ivs, _ = parse_chord(sym)
            pat = MIN if 3 in ivs else (DOM if sym.startswith("G") else MAJ)
            r = lo + ((root - lo) % 12)
            for i, off in enumerate(pat):
                s.note(bus, ins.strings, r + off, bar * 4 + i * 0.25, 0.2, vel * (1 if i % 4 == 0 else 0.8),
                       attack=0.008, rel=0.06, cutoff=5000)

    P_A = {"k": "x.x.x.x.x.x.x.x.", "s": "....X.......X...", "h": "x.x.x.x.x.x.x.x."}
    P_A2 = {"k": "x.xxx.xxx.xxx.xx", "s": "....X.......X...", "rd": "x.x.x.x.x.x.x.x."}
    P_B = {"k": "x..x..x.x..x..x.", "s": "....X.......X...", "h": "x.x.x.x.x.x.x.x.", "tk": "x..............."}
    P_BRK = {"tk": "x..x..x.x...x.x.", "tk2": "......x.......x.", "k": "x.......x......."}
    for bar in range(48):
        if bar < S_A:
            s.drums(bar, {"tk": "x.....x.x.......", "k": "x.....x.x......."}, kit)
            if bar == 3:
                s.drums(bar, {"s": "oooooxxxxxxxXXXX", "t3": "x...x...x...x..."}, kit)
        elif bar < S_B or S_C <= bar < S_T:
            s.drums(bar, P_A2 if bar >= S_C else P_A, kit)
        elif bar < S_A2:
            s.drums(bar, P_B, kit)
        elif bar < S_BRK:
            s.drums(bar, P_A2, kit)
        elif bar < S_C:
            s.drums(bar, P_BRK, kit)
            if bar >= S_C - 2:
                s.drums(bar, {"s": "x.x.x.x.xxxxxxxx" if bar == S_C - 2 else "xxxxxxxxxxxxXXXX"}, kit)
        else:
            s.drums(bar, {"k": "x.x.x.x.x.x.x.x.", "s": "....X.......X...", "tk": "x.......x.......",
                          "h": "x.x.x.x.x.x.x.x."}, kit)
        if bar in (S_A, S_B, S_A2, S_C, S_T, S_A + 4, S_A2 + 4, S_C + 4, S_B + 4):
            s.drums(bar, {"cr": "x", "tk": "x"}, kit)
        if bar in (S_B - 1, S_A2 - 1, S_BRK - 1, 47):
            fill(s, bar, kit, FILL_TOMS_LONG, beats=4) if bar == 47 else fill(s, bar, kit, FILL_TOMS)

    # intro hits + bell tolls
    for bar in range(S_A):
        sym = chart[bar]
        v = voicing(sym, 45, 4)
        for m in v:
            s.note("brass_lo", ins.brass, m, bar * 4, 2.5, 1.0, bright=0.7, attack=0.05, rel=0.3, growl=0.6)
        s.note("bass", ins.bass_sub, bass_note(sym, 24), bar * 4, 3.0, 1.0)
    for b_ in (0, 2):
        s.add("bells", ins.fm_bell(48, 4.0, 0.9, rng, 1.4, 3.0, 1.6), b_ * 4)
    for i in range(16):
        s.add("toms", ins.timpani(rng, 31, 0.3 + 0.04 * i, 0.6), 12 + i * 0.25, 0.6)

    ostinato(bars(S_A, S_B) + bars(S_A2, S_BRK) + bars(S_C, 48), vel=0.8)
    ostinato(bars(S_B, S_A2), vel=0.6, lo=60)
    # low brass melody (octave doubled) in A sections
    bl = dict(bright=0.75, attack=0.05, rel=0.2, growl=0.5)
    s.melody("brass_lo", ins.brass, low_A, S_A * 4, vel=1.0, legato=0.95, octave_double=-1, **bl)
    s.melody("brass_lo", ins.brass, low_A, S_A2 * 4, vel=1.0, legato=0.95, octave_double=-1, **bl)
    s.melody("lead", ins.lead, low_A, S_A2 * 4, transpose=24, vel=0.75, legato=0.95, cutoff=3000, saw_mix=0.8)
    # B: high brass + choir
    s.melody("brass_hi", ins.brass, mel_B, S_B * 4, vel=0.95, legato=0.95, bright=1.0, attack=0.04)
    s.melody("brass_hi", ins.brass, mel_B, S_B * 4, transpose=-12, vel=0.7, legato=0.95, bright=0.8)
    pad_chords(s, "choir", ins.choir, chart, bars(S_B, S_A2), center=62, notes=3, vel=0.8, vowel="a")
    pad_chords(s, "choir", ins.choir, chart, bars(S_BRK, S_C), center=60, notes=3, vel=0.8, vowel="o")
    pad_chords(s, "choir", ins.choir, chart, bars(S_C, S_T), center=64, notes=3, vel=0.8, vowel="a")
    s.melody("strings", ins.strings, mel_brk, S_BRK * 4, vel=0.85, legato=1.0, attack=0.25)
    s.melody("strings", ins.strings, mel_brk, S_BRK * 4, transpose=-12, vel=0.6, legato=1.0, attack=0.25)
    s.melody("brass_hi", ins.brass, mel_C, S_C * 4, vel=1.0, legato=0.95, bright=1.1, attack=0.03)
    s.melody("brass_hi", ins.brass, mel_C, S_C * 4, transpose=-12, vel=0.8, legato=0.95, bright=0.9)
    s.melody("lead", ins.lead, mel_C, S_C * 4, transpose=12, vel=0.55, legato=0.95, cutoff=3200, saw_mix=0.8)
    # turnaround: brass hits
    for bar in range(S_T, 48):
        for off, d, sym in split_bar(chart[bar]):
            for m in voicing(sym, 50, 4):
                for hb, hd in ((0, 1.2), (1.5, 1.2), (3, 0.8)):
                    s.note("brass_lo", ins.brass, m, bar * 4 + hb, hd, 0.95, bright=0.9, attack=0.02, rel=0.15,
                           growl=0.4)
    # bass + guitars
    bsy = dict(cutoff=3.5, decay_f=0.1, drive=2.5)
    for bar in bars(S_A, 48):
        r = bass_note(first_chord(chart[bar]), 24)
        if S_BRK <= bar < S_C:
            s.note("bass", ins.bass_sub, r, bar * 4, 3.8, 1.0)
            continue
        for i in range(8):
            s.note("bass", ins.bass_synth, r if i != 7 else r + 12, bar * 4 + i * 0.5, 0.45,
                   0.95 if i % 2 == 0 else 0.8, **bsy)
    for var, g in ((1, "gtrL"), (2, "gtrR")):
        for bar in bars(S_A, S_BRK) + bars(S_C, 48):
            r = bass_note(first_chord(chart[bar]), 36)
            if S_B <= bar < S_A2:
                s.note(g, ins.power_chord, r, bar * 4, 3.6, 0.9, jitter=0.008, variant=var, pan_=-0.8 if var == 1 else 0.8)
                continue
            for i, c in enumerate("x.xxx.xxx.xxx.xx"):
                if c == "x":
                    s.note(g, ins.power_chord, r, bar * 4 + i * 0.25, 0.22, 0.85, mute=True, octave=False,
                           jitter=0.006, variant=var, pan_=-0.8 if var == 1 else 0.8)
    s.add("fx", riser(s.secs(8), rng, 200, 5000), (S_C - 2) * 4, 0.9)
    s.add("fx", impact(rng, 45, 0.8), S_C * 4, 1.0)
    s.add("fx", impact(rng, 45, 0.8), 0, 1.0)

    chains = {
        "kick": lambda x: compressor(x, -10, 3, 0.002, 0.06, 4),
        "snare": chain(lambda x: peq(x, 180, 3, 1), lambda x: compressor(x, -14, 3, 0.002, 0.1, 6, 3)),
        "hats": lambda x: hp(x, 500),
        "toms": lambda x: compressor(x, -14, 3, 0.003, 0.1, 6, 2),
        "bass": lambda x: compressor(x, -16, 4, 0.004, 0.1, 6, 2),
        "brass_lo": chain(lambda x: hp(x, 50), lambda x: peq(x, 800, 3, 0.8), lambda x: compressor(x, -18, 3, 0.01, 0.2, 6, 2)),
        "brass_hi": chain(lambda x: hp(x, 150), lambda x: chorus(x, 0.4, 2, 9, 0.3), lambda x: peq(x, 1300, 2, 0.9)),
        "ost": chain(lambda x: hp(x, 150), lambda x: width(chorus(x, 0.5, 2, 10, 0.3), 1.3)),
        "strings": chain(lambda x: chorus(x, 0.5, 3, 12, 0.4), lambda x: hp(x, 150)),
        "choir": chain(lambda x: chorus(x, 0.4, 4, 14, 0.5), lambda x: hp(x, 150)),
        "gtrL": lambda x: hp(x, 80), "gtrR": lambda x: hp(x, 80),
        "lead": lambda x: x + 0.3 * delay(x, s.secs(0.75), 0.35, 4, 3000)[:, :x.shape[-1]],
        "bells": lambda x: x,
        "fx": lambda x: width(chorus(x, 0.3, 4, 15, 0.5), 1.4),
    }
    levels = {"kick": -6, "snare": -3, "hats": -1, "toms": -5.5, "bass": -2.7, "brass_lo": 2, "brass_hi": -3.7,
              "ost": 1, "strings": 1, "choir": -1, "gtrL": -6.5, "gtrR": -6.5, "lead": -1, "bells": -3, "fx": -10}
    sends = {"snare": (0.1, 0.3), "toms": (0.1, 0.3), "brass_lo": (0.05, 0.25), "brass_hi": (0.05, 0.25),
             "ost": (0.05, 0.15), "strings": (0, 0.35), "choir": (0, 0.4), "lead": (0, 0.2), "bells": (0, 0.5),
             "fx": (0, 0.3)}
    out = s.render(chains, levels, sends, hall=make_ir(2.6, 0.03, 0.35, 1.2, 0.25, seed=33))
    return out, {"bpm": 146, "bars": 48, "beats_per_bar": 4, "key": "C minor"}


# ---------------------------------------------------------------------------
# DUGOUT THEME  –  A dorian funk, 98 BPM, 24 bars (~59 s)
# ---------------------------------------------------------------------------
def dugout_theme():
    s = Song("dugout_theme", 98, 24, tail=5.0, swing=0.12)
    rng = s.rng
    kit = {
        "k": ([ins.kick(rng, 120, 48, 0.03, 0.28, 0.4, 1.6) for _ in range(2)], 0.9, 0.0, "kick"),
        "s": ([ins.snare(rng, 225, 0.07, 0.14, 0.75, bright=0.85) for _ in range(4)], 0.7, 0.05, "snare"),
        "h": ([ins.hat(rng, decay=0.03) for _ in range(4)], 0.22, 0.3, "hats"),
        "oh": ([ins.hat(rng, True, 0.1)], 0.2, 0.3, "hats"),
        "sh": ([ins.shaker(rng) for _ in range(3)], 0.22, -0.4, "hats"),
        "rim": ([ins.rim(rng)], 0.35, 0.1, "snare"),
    }
    A1 = ["Am7", "D9", "Am7", "D9", "Am7", "D9", "Fmaj7", "E7#9"]
    B = ["Dm9", "G13", "Cmaj9", "Am9", "Dm9", "G13", "Bm7b5", "E7#9"]
    A2 = ["Am7", "D9", "Am7", "D9", "Fmaj7", "G6", "Fmaj7", "E7#9"]
    chart = A1 + B + A2
    mel_A1 = ("r:2 E5:0.5 G5:0.5 A5:1 | r:4 | r:2 G5:0.5 A5:0.5 C6:1 | B5:1 A5:1 r:2 | "
              "r:2 E5:0.5 G5:0.5 A5:1 | r:4 | r:1 A5:0.5 G5:0.5 F5:0.5 E5:0.5 C5:1 | B4:2 r:2")
    mel_A2 = ("r:0.5 A4:0.5 C5:0.5 D5:0.5 E5:1 G5:0.5 E5:0.5 | F#5:1 E5:0.5 D5:0.5 E5:2 | "
              "r:0.5 A4:0.5 C5:0.5 D5:0.5 E5:0.5 G5:0.5 A5:1 | B5:0.5 A5:0.5 F#5:1 E5:2 | "
              "r:0.5 C5:0.5 E5:0.5 F5:0.5 A5:1.5 G5:0.5 | B5:1 A5:0.5 G5:0.5 E5:2 | "
              "C5:0.5 E5:0.5 G5:0.5 A5:0.5 C6:1 B5:1 | G#5:1 G5:1 E5:2")
    P = {"k": "X..x..x...x.....", "s": "....X..o.o..X..o", "h": "xgxgxgxgxgxgxg.g", "oh": "..............x."}
    PB = {"k": "X..x......x..x..", "s": "....X..o.o..X...", "h": "xgxgxgxgxgxgxgxg", "sh": "x.x.x.x.x.x.x.x."}
    for bar in range(24):
        s.drums(bar, PB if 8 <= bar < 16 else P, kit)
        if bar in (7, 15, 23):
            s.drums(bar, {"s": "..o.x.ox", "k": "x......."}, kit, beats=2, start=2)

    # bass (fingered funk)
    P1 = [(0, 0, 3, 1.0), (3, 12, 1, 0.7), (4, 0, 1, 0.45), (6, 10, 1, 0.8), (7, 12, 2, 0.9), (10, 7, 1, 0.85),
          (11, 0, 1, 0.5), (12, 0, 2, 0.9), (14, 3, 1, 0.7), (15, "A", 1, 0.75)]
    P2 = [(0, 0, 2, 1.0), (2, 0, 1, 0.45), (3, 12, 1, 0.75), (6, 7, 1, 0.8), (7, 10, 1, 0.8), (8, 12, 2, 0.9),
          (10, 0, 1, 0.6), (11, 7, 1, 0.7), (13, 5, 1, 0.7), (14, 7, 1, 0.75), (15, "A", 1, 0.75)]
    for bar in range(24):
        r = bass_note(chart[bar], 28)
        nxt = bass_note(chart[(bar + 1) % 24], 28)
        pat = P1 if bar % 2 == 0 else P2
        for st, off, ln, v in pat:
            if off == "A":
                m = nxt - 1 if nxt != r else r + 7
            else:
                m = r + off
            s.note("bass", ins.bass_finger, m, bar * 4 + st * 0.25, ln * 0.25 * 0.85, v, bright=1.1)

    # e-piano comping
    R1 = [(0, 0.4), (0.75, 0.25), (1.5, 0.5), (2.5, 0.25), (2.75, 0.5), (3.5, 0.4)]
    R2 = [(0.5, 0.4), (1.25, 0.25), (2.0, 0.6), (2.75, 0.25), (3.5, 0.4)]
    for bar in range(24):
        pad_chords(s, "ep", ins.epiano, chart, [bar], center=63, notes=4, vel=0.6,
                   rhythm=R1 if bar % 2 == 0 else R2, legato=1.0, strum=0.012)
    # organ pad in B, organ melody in A2
    pad_chords(s, "organ", ins.organ, chart, bars(8, 16), center=60, notes=4, vel=0.55, drawbars="808000000",
               click=0.05)
    s.melody("ep_lead", ins.epiano, mel_A1, 0, transpose=0, vel=0.85, legato=1.0)
    s.melody("organ", ins.organ, mel_A2, 16 * 4, vel=0.9, legato=0.92, drawbars="888600000", perc_amt=0.5,
             click=0.15)
    # B: e-piano fills (simple pentatonic answers)
    fills = "r:2 A5:0.5 C6:0.5 D6:1 | r:4 | r:2 E6:0.5 D6:0.5 B5:1 | r:4 | r:2 A5:0.5 C6:0.5 F6:1 | r:4 | r:2 D6:0.5 C6:0.5 A5:1 | G#5:2 r:2"
    s.melody("ep_lead", ins.epiano, fills, 8 * 4, vel=0.7, legato=1.0)

    chains = {
        "kick": lambda x: compressor(x, -12, 3, 0.004, 0.08, 4),
        "snare": lambda x: compressor(x, -16, 3, 0.002, 0.1, 6, 2),
        "hats": lambda x: hp(x, 500),
        "bass": chain(lambda x: compressor(x, -18, 4, 0.004, 0.12, 6, 3), lambda x: lp(x, 3500)),
        "ep": chain(lambda x: tremolo(x, 4.2, 0.3), lambda x: chorus(x, 0.6, 2, 8, 0.3), lambda x: hp(x, 140)),
        "ep_lead": chain(lambda x: tremolo(x, 4.2, 0.2), lambda x: hp(x, 160)),
        "organ": chain(lambda x: saturate(x, 1.3), lambda x: leslie(x, 0.9, 1.0), lambda x: hp(x, 120)),
    }
    levels = {"kick": -3.5, "snare": 0.5, "hats": 5, "bass": -1.4, "ep": -5, "ep_lead": -2, "organ": -9.7}
    sends = {"snare": (0.25, 0.05), "ep": (0.1, 0.15), "ep_lead": (0.1, 0.2), "organ": (0.1, 0.15),
             "hats": (0.15, 0), "kick": (0.1, 0)}
    out = s.render(chains, levels, sends, target_lufs=-17.0)
    return out, {"bpm": 98, "bars": 24, "beats_per_bar": 4, "key": "A dorian"}


# ---------------------------------------------------------------------------
# PRACTICE THEME  –  F major chill, 80 BPM, 20 bars (60 s)
# ---------------------------------------------------------------------------
def practice_theme():
    s = Song("practice_theme", 80, 20, tail=6.0, swing=0.1)
    rng = s.rng
    kit = {
        "k": ([ins.kick(rng, 105, 50, 0.04, 0.3, 0.1, 1.2) for _ in range(2)], 0.85, 0.0, "drums"),
        "rim": ([ins.rim(rng) for _ in range(2)], 0.4, 0.1, "drums"),
        "sn": ([ins.snap(rng) for _ in range(2)], 0.35, -0.15, "drums"),
        "sh": ([ins.shaker(rng, 0.1) for _ in range(3)], 0.2, -0.4, "drums"),
        "h": ([ins.hat(rng, decay=0.025) for _ in range(3)], 0.13, 0.35, "drums"),
    }
    A = ["Fmaj7", "Em7", "Dm9", "Cmaj9", "Bbmaj7", "Am7", "Gm9", "C9sus4"]
    C = ["Bbmaj7", "Am7", "Gm9", "C9sus4"]
    chart = A + A + C
    mel = ("A5:1.5 G5:0.5 E5:1 C5:1 | D5:1 E5:1 G5:2 | F5:1.5 E5:0.5 D5:1 A4:1 | E5:2 D5:1 B4:1 | "
           "D5:1.5 F5:0.5 A5:2 | G5:1 E5:1 C5:2 | Bb4:1 D5:1 F5:1 A5:1 | G5:2 F5:2")
    mel_C = "r:2 C6:1 A5:1 | G5:4 | r:2 F5:1 D5:1 | G5:2 C6:2"
    for bar in range(20):
        if bar == 0:
            continue
        pat = {"k": "x......x..x.....", "rim": "....x.......x...", "sh": "x.x.x.x.x.x.x.x.", "h": "..x...x...x...x."}
        if bar >= 16:
            pat["sn"] = "....x.......x..."
            pat.pop("rim")
        s.drums(bar, pat, kit)
    for bar in range(20):
        sym = chart[bar]
        s.note("bass", ins.bass_sub, bass_note(sym, 29), bar * 4, 2.6, 0.9)
        s.note("bass", ins.bass_sub, bass_note(sym, 29) + (7 if bar % 2 else 12), bar * 4 + 3, 0.8, 0.6)
    pad_chords(s, "ep", ins.epiano, chart, range(20), center=62, notes=4, vel=0.45, strum=0.03,
               rhythm=[(0, 2.5), (2.5, 1.5)])
    s.melody("mar", ins.bell, mel, 8 * 4, vel=0.9, legato=1.0, kind="marimba")
    s.melody("mar", ins.bell, mel_C, 16 * 4, vel=0.6, legato=1.0, kind="glock")
    # vinyl-ish soft noise bed (very quiet)
    n = s.N
    crackle = np.zeros(n)
    idx = rng.integers(0, n, 900)
    crackle[idx] = rng.uniform(-1, 1, 900) * rng.uniform(0.1, 1, 900) ** 2
    crackle = bp(crackle, 2500, 0.8) + 0.02 * lp(white(n, rng), 3000)
    s.add("vinyl", np.stack([crackle, np.roll(crackle, 777)]), 0)

    chains = {
        "drums": chain(lambda x: lp(x, 10000), lambda x: compressor(x, -18, 3, 0.005, 0.12, 6, 2)),
        "bass": lambda x: lp(x, 900),
        "ep": chain(lambda x: tremolo(x, 3.0, 0.25), lambda x: chorus(x, 0.5, 2.5, 9, 0.35), lambda x: lp(x, 7500),
                    lambda x: hp(x, 140)),
        "mar": lambda x: x + 0.3 * delay(x, s.secs(0.75), 0.4, 5, 2500)[:, :x.shape[-1]],
        "vinyl": lambda x: x,
    }
    levels = {"drums": -3.2, "bass": -11, "ep": -4, "mar": -0.3, "vinyl": -26}
    sends = {"ep": (0.1, 0.25), "mar": (0.05, 0.3), "drums": (0.15, 0.05)}
    out = s.render(chains, levels, sends, target_lufs=-18.0)
    return out, {"bpm": 80, "bars": 20, "beats_per_bar": 4, "key": "F major"}


# ---------------------------------------------------------------------------
# VICTORY (~12 s, one-shot)  –  C major fanfare with bVI-bVII-I cadence
# ---------------------------------------------------------------------------
def victory():
    s = Song("victory", 120, 6, tail=3.0, loop=False)
    rng = s.rng
    kit = kit_rock(rng, snare_f=210, snare_decay=0.15)
    # bar 0: timpani + snare roll crescendo, strings swell, brass pickup triplets
    for i in range(16):
        s.add("perc", ins.timpani(rng, 43, 0.3 + 0.045 * i, 0.7), i * 0.25, 0.5)
    s.drums(0, {"s": "gggooooxxxxxxXXX"}, kit, beats=4)
    pad_chords(s, "strings", ins.strings, ["G"], [0], center=59, notes=3, vel=0.7, attack=1.5)
    br = dict(bright=1.1, attack=0.02, rel=0.25, scoop=15)
    s.melody("brass", ins.brass, "G4:0.333 G4:0.333 G4:0.334", 3, vel=0.95, legato=0.85, octave_double=-1, **br)
    s.melody("brass", ins.brass, "C5:1.5 G4:0.5 C5:0.5 E5:0.5 G5:1 | A5:1 C6:1 B5:1 G5:1 | C6:1 Ab5:1 D6:1 Bb5:1 | "
             "C6:4", 4, vel=1.0, legato=0.92, octave_double=-1, **br)
    chart = ["G", "C", "F G", "Ab Bb", "C", "C"]
    pad_chords(s, "brass_pad", ins.brass, chart, [1, 2, 3], center=60, notes=4, vel=0.75, bright=0.8, attack=0.05)
    pad_chords(s, "brass_pad", ins.brass, chart, [4], center=60, notes=4, vel=0.9, bright=1.0, attack=0.03, rel=0.6)
    for bar in (1, 2, 3):
        s.drums(bar, {"k": "x.......x.......", "s": "....x..x.x..x.xx", "h": "x.x.x.x.x.x.x.x."}, kit)
    s.drums(1, {"cr": "x"}, kit)
    s.drums(4, {"cr": "x", "cr2": "x", "k": "x", "s": "X"}, kit)
    for bar in (1, 2, 3):
        for off, d, sym in split_bar(chart[bar]):
            s.note("bass", ins.bass_finger, bass_note(sym, 28), bar * 4 + off, d * 0.9, 0.9)
    s.note("bass", ins.bass_finger, bass_note("C", 28), 16, 6, 1.0)
    s.add("perc", ins.timpani(rng, 36, 1.0, 2.5), 16, 0.9)
    s.add("perc", ins.timpani(rng, 43, 0.8, 1.5), 18.5, 0.6)
    s.add("perc", ins.timpani(rng, 36, 1.0, 2.5), 19, 0.8)
    for i, m in enumerate([84, 88, 91, 96, 100]):
        s.note("bells", ins.bell, m, 16 + i * 0.12, 1.5, 0.7)
    from crowd import crowd_burst
    cheer = crowd_burst(rng, 5.5, "cheer", voices=60, clap_rate=100, bed=0.8, whistles=2, stereo=True,
                        env_pts=[(0, 0), (0.3, 1.0), (3.0, 0.8), (5.5, 0)])
    s.add("crowd", cheer / np.max(np.abs(cheer)), 16)

    chains = {
        "brass": chain(lambda x: hp(x, 120), lambda x: chorus(x, 0.4, 2, 9, 0.3), lambda x: peq(x, 1200, 2, 0.9)),
        "brass_pad": chain(lambda x: hp(x, 100), lambda x: chorus(x, 0.4, 2, 9, 0.4)),
        "strings": lambda x: chorus(x, 0.5, 3, 12, 0.4),
        "snare": lambda x: compressor(x, -14, 3, 0.002, 0.1, 6, 2),
        "hats": lambda x: hp(x, 400),
        "crowd": lambda x: hp(x, 200),
    }
    levels = {"brass": -3, "brass_pad": -6, "strings": 1, "perc": -9.6, "snare": -4.4, "kick": -7.7, "hats": -2,
              "bass": -3.4, "bells": -6, "crowd": -7}
    sends = {"brass": (0.05, 0.25), "brass_pad": (0, 0.3), "strings": (0, 0.3), "perc": (0.05, 0.25),
             "snare": (0.1, 0.25), "bells": (0, 0.4), "crowd": (0, 0.2)}
    out = s.render(chains, levels, sends, target_lufs=-15.0)
    out = out[:, :ns(12.5)]
    out = fade(out, 0.0, 1.5)
    return out, {"bpm": 120, "key": "C major"}


# ---------------------------------------------------------------------------
# DEFEAT (~8 s, one-shot)  –  A minor, descending, soft
# ---------------------------------------------------------------------------
def defeat():
    s = Song("defeat", 72, 3, tail=3.0, loop=False)
    rng = s.rng
    chart = [("Am", 0, 2), ("F", 2, 1), ("Dm6", 3, 1), ("E7", 4, 2), ("Am", 6, 5)]
    for sym, b, d in chart:
        for m in voicing(sym, 57, 4):
            s.note("strings", ins.strings, m, b, d * 0.98, 0.6, attack=0.4, rel=0.9)
        s.note("bass", ins.bass_sub, bass_note(sym, 33), b, d * 0.95, 0.7)
    s.melody("ep", ins.epiano, "E5:1 D5:0.5 C5:0.5 | C5:1 | A4:1 | G#4:1 B4:1 | A4:4", 0, vel=0.7, legato=1.0)
    s.melody("horn", ins.brass, "E4:1 D4:0.5 C4:0.5 | C4:1 | A3:1 | G#3:1 B3:1 | A3:3", 0, vel=0.6, legato=0.98,
             bright=0.35, attack=0.12, rel=0.5, vib=0.6)
    s.add("perc", ins.timpani(rng, 33, 0.45, 2.5), 6, 0.6)
    s.note("ep", ins.epiano, note("A2"), 6, 4, 0.5)
    chains = {"strings": lambda x: chorus(x, 0.4, 3, 12, 0.4),
              "ep": chain(lambda x: tremolo(x, 3.5, 0.2), lambda x: hp(x, 80)),
              "horn": lambda x: hp(x, 100)}
    levels = {"strings": 0.4, "bass": -11.7, "ep": -2, "horn": -4, "perc": -6.2}
    sends = {"strings": (0, 0.35), "ep": (0, 0.35), "horn": (0, 0.3), "perc": (0, 0.3)}
    out = s.render(chains, levels, sends, target_lufs=-18.0)
    out = out[:, :ns(8.4)]
    out = fade(out, 0.0, 1.8)
    return out, {"bpm": 72, "key": "A minor"}


REGISTRY = {
    "menu_theme": {"fn": menu_theme, "loop": True, "volume_db": -6.0, "quality": 5},
    "battle_theme": {"fn": battle_theme, "loop": True, "volume_db": -7.0, "quality": 5},
    "boss_theme": {"fn": boss_theme, "loop": True, "volume_db": -7.0, "quality": 5},
    "dugout_theme": {"fn": dugout_theme, "loop": True, "volume_db": -6.0, "quality": 5},
    "practice_theme": {"fn": practice_theme, "loop": True, "volume_db": -6.0, "quality": 5},
    "victory": {"fn": victory, "loop": False, "volume_db": -4.0, "quality": 5},
    "defeat": {"fn": defeat, "loop": False, "volume_db": -4.0, "quality": 5},
}
