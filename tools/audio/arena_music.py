"""Adaptive arena music: one 16-bar loop per arena, rendered as four stems that
play in sync and are cross-faded by the game (src/audio/adaptive_music.gd).

    calm   pads, a soft arpeggio, light percussion and a quiet statement of the hook
           (setup, breaks; always playing underneath)
    wave   drums, bass, the rhythm instrument and the lead hook        (wave in progress)
    boss   taiko/toms, brass stabs, choir and crash accents             (a boss is on the field)
    tense  sub pulse, ticking hats, heartbeat kick, tremolo strings     (one run from losing /
                                                                         the final out)

Every arena keeps the game's identity (the battle-theme hook: 1-3-5-4-3-2-3 | 1-3-6-5-3 ...,
the same form and the same layer set) but changes key, tempo, groove and instrumentation to
match the arena's mood (data/arenas.json).

All stems of an arena share one gain, chosen so calm+wave sits at -16 LUFS integrated like the
other music; boss and tense add on top (a bit louder on purpose).  Every stem is a seamless
loop of exactly the same length (wrap-around tail + circular limiter).

Also here: the boss intro / boss defeat stings (one-shots, stereo OGG).
"""
from __future__ import annotations

import numpy as np

import instruments as ins
from dsp import (SR, chorus, compressor, db2lin, delay, hp, limiter, loudness, lp, make_ir, ns,
                 pad_to, process_circular, reverb, tarr, tremolo, width, wrap_tail, fade, dc_block,
                 TWO_PI, white, tvfilt)
from music import FILL_SNARE, FILL_TOMS, arp, bass_line, chain, fill, impact, kit_rock, pad_chords, riser
from sequencer import Song, bass_note, voicing

LAYERS = ("calm", "wave", "boss", "tense")
NAMES = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
MODES = {"minor": [0, 2, 3, 5, 7, 8, 10], "major": [0, 2, 4, 5, 7, 9, 11]}

# The game's hook in scale degrees: (degree, beats[, raise-if-minor]).  16 bars:
# hook (4) + answer (4) + hook (4) + climb (4) that lands on the dominant.
HOOK = [
    [(0, .75), (2, .75), (4, .5), (3, .5), (2, .5), (1, .5), (2, .5)],
    [(0, .75), (2, .75), (5, 1), (4, .5), (2, 1)],
    [(1, .75), (3, .75), (6, 1), (5, .5), (3, .5), (1, .5)],
    [(2, 1.5), (1, .5), (0, 2)],
]
ANSWER = [
    [(0, .75), (2, .75), (4, .5), (3, .5), (2, .5), (1, .5), (2, .5)],
    [(0, .75), (2, .75), (5, .5), (6, .5), (7, 1.5)],
    [(5, .75), (4, .75), (3, .5), (0, .5), (3, .5), (5, 1)],
    [(4, 1.5), (3, .5), (2, .5), (1, .5), (-1, 1, 1)],
]
CLIMB = [
    [(4, .75), (2, .75), (7, .5), (6, .5), (4, .5), (3, .5), (4, .5)],
    [(7, .75), (6, .75), (5, .5), (4, .5), (5, .5), (7, 1)],
    [(5, .75), (6, .75), (7, .5), (8, .5), (9, 1.5)],
    [(8, 1.5), (7, .5), (6, .5, 1), (4, 1.5)],
]
MELODY = HOOK + ANSWER + HOOK + CLIMB


def chart_for(tonic: int, mode: str):
    n = lambda k: NAMES[(tonic + k) % 12]  # noqa: E731
    if mode == "minor":
        i, VI, VII, iv, V = n(0) + "m", n(8), n(10), n(5) + "m", n(7)
        return [i, VI, VII, i, i, VI, iv, V, i, VI, VII, i, i, VI, VII, V]
    I, vi, V, ii, IV = n(0), n(9) + "m", n(7), n(2) + "m", n(5)
    return [I, vi, V, I, I, vi, ii, V, I, vi, V, I, I, vi, IV, V]


def deg_to_midi(tonic_midi: int, mode: str, d: int, raise_lt: int = 0) -> int:
    sc = MODES[mode]
    m = tonic_midi + 12 * (d // 7) + sc[d % 7]
    if raise_lt and mode == "minor":
        m += 1
    return m


def melody_events(tonic_midi, mode, bars_=range(16)):
    out = []
    for bar in bars_:
        b = 0.0
        for ev in MELODY[bar]:
            d, dur = ev[0], ev[1]
            lt = ev[2] if len(ev) > 2 else 0
            out.append((bar * 4 + b, dur, deg_to_midi(tonic_midi, mode, d, lt)))
            b += dur
    return out


def play_melody(s, bus, fn, events, vel=0.9, legato=0.92, transpose=0, gain=1.0, glide=False, **kw):
    prev = None
    for beat, dur, m in events:
        extra = dict(kw)
        if glide and prev is not None:
            extra["glide_from"] = prev + transpose
        s.note(bus, fn, m + transpose, beat, dur * legato, vel, gain=gain, **extra)
        prev = m


def kit_on(kit, layer):
    return {k: (v[0], v[1], v[2], f"{layer}.{v[3]}") for k, v in kit.items()}


# ---------------------------------------------------------------------------
# arena styles
# ---------------------------------------------------------------------------
STYLES = {
    # Industrial rock fortress at sunset: the reference arrangement (same key/tempo as battle_theme).
    "steel_yard": dict(tonic=4, mode="minor", bpm=134, lead_oct=5, genre="rock"),
    # Golden-hour ballpark: major key, ballpark organ, fingered bass, trumpet-ish brass, light swing.
    "sunset_grounds": dict(tonic=2, mode="major", bpm=118, lead_oct=5, genre="ballpark", swing=0.18),
    # Night game under neon: synthwave, gated pads, 16th arps, four-on-the-floor.
    "neon_diamond": dict(tonic=9, mode="minor", bpm=124, lead_oct=4, genre="synthwave"),
    # Storm-lashed iron citadel: fast, heavy 16th chugs, taiko, low brass.
    "iron_fortress": dict(tonic=2, mode="minor", bpm=144, lead_oct=4, genre="metal"),
    # Snowy mountain park: slower, glassy bells, plucked strings, brushed groove.
    "frostpark": dict(tonic=6, mode="minor", bpm=104, lead_oct=5, genre="ice"),
    # The grand stage: orchestral rock, string ostinato, brass hook, timpani.
    "champions_citadel": dict(tonic=0, mode="minor", bpm=128, lead_oct=5, genre="epic"),
}


def compose(arena: str):
    st = STYLES[arena]
    g = st["genre"]
    tonic, mode, bpm = st["tonic"], st["mode"], st["bpm"]
    s = Song("arena_" + arena, bpm, 16, tail=6.0, swing=st.get("swing", 0.0))
    rng = s.rng
    chart = chart_for(tonic, mode)
    lead_tonic = 12 * (st["lead_oct"] + 1) + tonic
    mel = melody_events(lead_tonic, mode)
    root_lo = lambda bar, lo=28: bass_note(chart[bar], lo)  # noqa: E731
    B16 = list(range(16))
    kick_beats = []

    # ---------------------------------------------------------------- CALM
    if g == "ballpark":
        pad_chords(s, "calm.pad", ins.organ, chart, B16, center=64, notes=4, vel=0.45,
                   drawbars="006620000", rel=0.08)
    elif g in ("metal", "epic"):
        pad_chords(s, "calm.pad", ins.strings, chart, B16, center=60, notes=4, vel=0.5, attack=0.5, rel=0.8)
        pad_chords(s, "calm.pad", ins.choir, chart, B16, center=57, notes=3, vel=0.35, vowel="o")
    elif g == "ice":
        pad_chords(s, "calm.pad", ins.pad, chart, B16, center=67, notes=4, vel=0.45, attack=0.8, rel=1.2,
                   cutoff=3200)
    elif g == "synthwave":
        pad_chords(s, "calm.pad", ins.pad, chart, B16, center=64, notes=4, vel=0.5, attack=0.4, rel=1.0,
                   detune=18.0, cutoff=2000)
    else:
        pad_chords(s, "calm.pad", ins.pad, chart, B16, center=64, notes=4, vel=0.45, attack=0.5, rel=1.0)
    for bar in B16:  # sub root, whole bar
        s.note("calm.sub", ins.bass_sub, root_lo(bar), bar * 4, 3.8, 0.55)
    if g == "ice":
        arp(s, "calm.arp", ins.fm_bell, chart, B16, center=74, steps=8, vel=0.5, order=(0, 2, 1, 3, 2, 4, 3, 1),
            dur=1.6, ratio=3.5, index=1.6, decay=0.7)
    elif g == "ballpark":
        arp(s, "calm.arp", ins.epiano, chart, B16, center=67, steps=8, vel=0.5, order=(0, 1, 2, 3, 2, 1, 2, 3))
    elif g == "synthwave":
        arp(s, "calm.arp", ins.pluck, chart, B16, center=69, steps=16, vel=0.45, bright=0.6,
            order=(0, 1, 2, 3, 4, 3, 2, 1))
    else:
        arp(s, "calm.arp", ins.pluck, chart, B16, center=66, steps=8, vel=0.5, bright=0.6,
            order=(0, 2, 1, 3, 2, 4, 3, 1))
    # quiet hook statement in bars 8-11 so the identity is there even between waves
    play_melody(s, "calm.bell", ins.bell, [e for e in mel if 32 <= e[0] < 48], vel=0.45, legato=1.0,
                transpose=12 if st["lead_oct"] == 4 else 0, kind="chime" if g == "ice" else "glock")
    kit = kit_rock(rng, kick_f=(150, 48), kick_decay=0.26, snare_f=205, snare_decay=0.17, hat_gain=0.22)
    ck = kit_on(kit, "calm")
    for bar in B16:
        if g == "ice":
            s.drums(bar, {"sh": "..x...x...x...x.", "rim": "........x......."}, ck)
        elif g == "ballpark":
            s.drums(bar, {"sh": "x.x.x.x.x.x.x.x.", "k": "x.......x......."}, ck, gain=0.7)
        else:
            s.drums(bar, {"k": "x.......x.......", "h": "..x...x...x...x."}, ck, gain=0.6)

    # ---------------------------------------------------------------- WAVE
    wk = kit_on(kit, "wave")
    pats = {
        "rock": [{"k": "x.....x.x.....x.", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
                 {"k": "x.....x.x.x...x.", "s": "....x.......x...", "h": "xxxxxxxxxxxxxxxx", "c": "....x.......x..."}],
        "ballpark": [{"k": "x.......x.x.....", "s": "....x.......x...", "rd": "x.x.x.x.x.x.x.x.", "sh": "xxxxxxxxxxxxxxxx"}],
        "synthwave": [{"k": "x...x...x...x...", "c": "....x.......x...", "oh": "..x...x...x...x.",
                       "h": "x.xxx.xxx.xxx.xx"}],
        "metal": [{"k": "xxxxxxxxxxxxxxxx", "s": "....X.......X...", "h": "x.x.x.x.x.x.x.x."},
                  {"k": "x.xxx.xxx.xxx.xx", "s": "....X.......X...", "rd": "x.x.x.x.x.x.x.x."}],
        "ice": [{"k": "x.......x.x.....", "rim": "....x.......x...", "sh": "x.x.x.x.x.x.x.x.",
                 "h": "..x...x...x...x."}],
        "epic": [{"k": "x.......x.......", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x.",
                  "tk": "x.........x....."},
                 {"k": "x.....x.x.......", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x.",
                  "tk": "x.....x...x....."}],
    }[g]
    for bar in B16:
        pat = dict(pats[0] if bar < 8 else pats[-1])
        s.drums(bar, pat, wk)
        p = pat.get("k", "").replace(" ", "")
        kick_beats.extend(bar * 4 + i * 4 / len(p) for i, c in enumerate(p) if c in "xX")
        if bar in (0, 8):
            s.drums(bar, {"cr": "x"}, wk)
        if bar in (7, 15):
            fill(s, bar, wk, FILL_TOMS if g in ("rock", "metal", "epic") else FILL_SNARE,
                 beats=2 if g != "ice" else 1)
    # bass
    if g == "rock":
        bass_line(s, "wave.bass", ins.bass_synth, chart, B16, [0, 0, 0, 0, 0, 0, 12, 0], lo=28, vel=0.9,
                  cutoff=4.5, decay_f=0.12, drive=2.2)
    elif g == "ballpark":
        bass_line(s, "wave.bass", ins.bass_finger, chart, B16, [0, None, 7, None, 12, None, 7, None], lo=33, vel=0.9)
    elif g == "synthwave":
        bass_line(s, "wave.bass", ins.bass_synth, chart, B16, [0, 12, 0, 12, 0, 12, 0, 12], lo=28, vel=0.85,
                  cutoff=3.5, decay_f=0.1, drive=1.6)
    elif g == "metal":
        bass_line(s, "wave.bass", ins.bass_synth, chart, B16, [0] * 16, lo=26, vel=0.85, gate=0.7,
                  cutoff=3.0, decay_f=0.08, drive=3.0)
    elif g == "ice":
        bass_line(s, "wave.bass", ins.bass_finger, chart, B16, [0, None, None, 0, None, None, 7, None], lo=30,
                  vel=0.85)
    else:
        bass_line(s, "wave.bass", ins.bass_synth, chart, B16, [0, 0, 0, 0, 0, 0, 0, 0], lo=24, vel=0.85,
                  cutoff=3.5, decay_f=0.12, drive=1.8)
    # rhythm
    for var, gname in ((1, "wave.gtrL"), (2, "wave.gtrR")):
        gk = dict(jitter=0.007, variant=var, pan_=-0.75 if var == 1 else 0.75)
        for bar in B16:
            r = bass_note(chart[bar], 40)
            if g == "rock":
                s.note(gname, ins.power_chord, r, bar * 4, 1.4, 0.9, **gk)
                for i in (3, 4, 5, 7):
                    s.note(gname, ins.power_chord, r, bar * 4 + i * 0.5, 0.4, 0.72, mute=True, octave=False, **gk)
                s.note(gname, ins.power_chord, r, bar * 4 + 3.0, 0.45, 0.85, **gk)
            elif g == "metal":
                for i in range(16):
                    acc = i in (0, 3, 6, 10, 12)
                    s.note(gname, ins.power_chord, r, bar * 4 + i * 0.25,
                           0.5 if acc else 0.22, 0.95 if acc else 0.68, mute=not acc, octave=False, **gk)
            elif g == "epic" and var == 1:
                s.note(gname, ins.power_chord, r, bar * 4, 1.8, 0.8, **gk)
                s.note(gname, ins.power_chord, r, bar * 4 + 2.0, 1.8, 0.75, **gk)
    if g == "ballpark":
        pad_chords(s, "wave.comp", ins.organ, chart, B16, center=67, notes=4, vel=0.7, legato=0.5,
                   rhythm=[(0.5, 0.5), (1.5, 0.5), (2.5, 0.5), (3.5, 0.5)], drawbars="888000000", perc_amt=0.6)
    elif g == "synthwave":
        arp(s, "wave.comp", ins.pluck, chart, B16, center=76, steps=16, vel=0.6, bright=1.0,
            order=(0, 2, 1, 3, 2, 4, 3, 5))
        pad_chords(s, "wave.comp", ins.pad, chart, B16, center=64, notes=4, vel=0.5,
                   rhythm=[(i * 0.5, 0.35) for i in range(8)], legato=1.0, attack=0.01, rel=0.05, cutoff=3000)
    elif g == "ice":
        pad_chords(s, "wave.comp", ins.strings, chart, B16, center=64, notes=3, vel=0.6,
                   rhythm=[(i * 0.5, 0.3) for i in range(8)], attack=0.01, rel=0.08, cutoff=4500)
    elif g == "epic":
        for bar in B16:  # string ostinato (16ths)
            root = bass_note(chart[bar], 52)
            minor = chart[bar].endswith("m")
            pat = [0, 0, 3 if minor else 4, 0, 7, 0, 3 if minor else 4, 0] * 2
            for i, off in enumerate(pat):
                s.note("wave.comp", ins.strings, root + off, bar * 4 + i * 0.25, 0.2, 0.8 if i % 4 == 0 else 0.62,
                       attack=0.008, rel=0.06, cutoff=5000)
    # lead hook
    if g == "rock":
        play_melody(s, "wave.lead", ins.lead, mel, vel=0.9, cutoff=3400, vib=0.8)
        play_melody(s, "wave.lead", ins.lead, [e for e in mel if e[0] >= 32], vel=0.42, transpose=-12, cutoff=3000)
    elif g == "ballpark":
        play_melody(s, "wave.lead", ins.brass, mel, vel=0.85, legato=0.88, bright=1.1)
        play_melody(s, "wave.lead", ins.brass, [e for e in mel if e[0] >= 32], vel=0.45, transpose=-5,
                    legato=0.88)
    elif g == "synthwave":
        play_melody(s, "wave.lead", ins.lead, mel, vel=0.85, transpose=12, saw_mix=0.9, cutoff=3800, glide=True)
        play_melody(s, "wave.lead", ins.lead, mel, vel=0.4, transpose=0, saw_mix=0.7, cutoff=2400)
    elif g == "metal":
        play_melody(s, "wave.lead", ins.lead, mel, vel=0.9, transpose=12, saw_mix=0.85, cutoff=3600, vib=1.2)
        play_melody(s, "wave.lead", ins.brass, mel, vel=0.5, transpose=0, legato=0.85, growl=0.4)
    elif g == "ice":
        play_melody(s, "wave.lead", ins.bell, mel, vel=0.75, legato=1.0, kind="glock")
        play_melody(s, "wave.lead", ins.strings, mel, vel=0.4, transpose=-12, legato=0.95, attack=0.05)
    else:
        play_melody(s, "wave.lead", ins.brass, mel, vel=0.9, legato=0.9, bright=1.0)
        play_melody(s, "wave.lead", ins.strings, mel, vel=0.45, transpose=12, legato=0.95, attack=0.04)
    s.add("wave.fx", riser(s.secs(4), rng, 300, 5000), 12 * 4, 0.45)

    # ---------------------------------------------------------------- BOSS
    bk = kit_on(kit, "boss")
    for bar in B16:
        s.drums(bar, {"tk": "x.....x...x.....", "tk2": "......x.......x.", "t3": "............x.x."
                      if bar % 4 == 3 else "................"}, bk)
        s.drums(bar, {"k": "x.x.x.x.x.x.x.x."}, bk, gain=0.55)
        if bar % 4 == 0:
            s.drums(bar, {"cr2": "x"}, bk)
    pad_chords(s, "boss.brass", ins.brass, chart, B16, center=55, notes=3, vel=0.8, legato=1.0,
               rhythm=[(0, 0.75), (1.5, 0.5), (3.0, 0.9)], growl=0.5, bright=1.1)
    pad_chords(s, "boss.choir", ins.choir, chart, B16, center=64, notes=4, vel=0.55, vowel="a")
    for bar in (0, 4, 8, 12):
        s.add("boss.fx", impact(rng, 55, 0.5), bar * 4, 0.55)

    # ---------------------------------------------------------------- TENSE
    tk = kit_on(kit, "tense")
    for bar in B16:
        s.drums(bar, {"k": "X..x............" if bar % 2 == 0 else "X..x....X..x....",
                      "rim": "x.x.x.x.x.x.x.x.", "h": "xxxxxxxxxxxxxxxx"}, tk, gain=0.75)
        r = root_lo(bar, 28)
        for i in range(8):
            s.note("tense.pulse", ins.bass_synth, r, bar * 4 + i * 0.5, 0.35, 0.8 if i % 2 == 0 else 0.6,
                   cutoff=2.2, decay_f=0.07, drive=1.5)
    # rising tremolo strings: degrees 4,5,6,7 over each 4-bar group, sustained
    for bar in B16:
        d = 4 + bar % 4
        m = deg_to_midi(12 * 6 + tonic, mode, d, 1 if d == 6 else 0)
        s.note("tense.str", ins.strings, m, bar * 4, 4.0, 0.55, attack=0.25, rel=0.3, cutoff=5000)
        s.note("tense.str", ins.strings, m - 12, bar * 4, 4.0, 0.45, attack=0.25, rel=0.3, cutoff=4000)

    # ---------------------------------------------------------------- mix
    duck = s.duck(kick_beats, depth=0.35, release=0.16)
    chains = {
        "calm.pad": chain(lambda x: chorus(x, 0.35, 3, 12, 0.5), lambda x: hp(x, 150)),
        "calm.arp": chain(lambda x: x + 0.35 * delay(x, s.secs(0.75), 0.4, 5, 3000)[:, :x.shape[-1]],
                          lambda x: hp(x, 250)),
        "calm.bell": lambda x: x + 0.4 * delay(x, s.secs(0.75), 0.45, 6, 3500)[:, :x.shape[-1]],
        "calm.sub": lambda x: lp(x, 180),
        "wave.bass": chain(lambda x: x * duck ** 0.5, lambda x: compressor(x, -16, 4, 0.004, 0.1, 6, 2)),
        "wave.gtrL": lambda x: hp(x, 100), "wave.gtrR": lambda x: hp(x, 100),
        "wave.comp": chain(lambda x: x * duck, lambda x: hp(x, 180)),
        "wave.lead": chain(lambda x: x + 0.28 * delay(x, s.secs(0.75), 0.35, 4, 2800)[:, :x.shape[-1]],
                           lambda x: compressor(x, -18, 3, 0.005, 0.1, 6, 2), lambda x: hp(x, 180)),
        "wave.kick": lambda x: compressor(x, -10, 3, 0.003, 0.08, 4),
        "wave.snare": lambda x: compressor(x, -14, 3, 0.002, 0.1, 6, 3),
        "wave.hats": lambda x: hp(x, 500),
        "wave.fx": lambda x: width(chorus(x, 0.3, 4, 15, 0.5), 1.4),
        "boss.brass": chain(lambda x: compressor(x, -16, 3, 0.005, 0.12, 6), lambda x: hp(x, 90)),
        "boss.choir": chain(lambda x: chorus(x, 0.3, 3, 14, 0.4), lambda x: hp(x, 200)),
        "boss.toms": lambda x: compressor(x, -14, 3, 0.003, 0.1, 6),
        "tense.str": chain(lambda x: tremolo(x, s.bpm / 60 * 4, 0.7, 0.0), lambda x: hp(x, 200)),
        "tense.pulse": lambda x: lp(x, 900),
        "tense.hats": lambda x: hp(x, 3000),
    }
    if g == "ballpark":
        from dsp import leslie
        chains["calm.pad"] = chain(lambda x: leslie(x, 0.8), lambda x: hp(x, 120))
        chains["wave.comp"] = chain(lambda x: leslie(x, 6.0), lambda x: hp(x, 150))
    levels = {
        "calm.pad": 4, "calm.arp": 0, "calm.bell": -1, "calm.sub": -1, "calm.kick": -4, "calm.hats": 2,
        "calm.snare": -2,
        "wave.kick": -4, "wave.snare": -2, "wave.hats": 1, "wave.toms": -4, "wave.bass": -2,
        "wave.gtrL": -8, "wave.gtrR": -8, "wave.comp": -7, "wave.lead": 0, "wave.fx": -8,
        "boss.toms": -3, "boss.kick": -8, "boss.hats": -6, "boss.brass": -5, "boss.choir": -6, "boss.fx": -6,
        "tense.kick": -5, "tense.snare": -9, "tense.hats": -11, "tense.pulse": -6, "tense.str": -7,
    }
    sends = {"calm.pad": (0, 0.3), "calm.arp": (0, 0.25), "calm.bell": (0, 0.35), "wave.snare": (0.1, 0.2),
             "wave.toms": (0.1, 0.2), "wave.lead": (0.05, 0.18), "wave.comp": (0.05, 0.15),
             "wave.gtrL": (0.08, 0), "wave.gtrR": (0.08, 0), "boss.toms": (0.1, 0.3), "boss.brass": (0.05, 0.25),
             "boss.choir": (0, 0.4), "boss.fx": (0, 0.3), "tense.str": (0, 0.3), "tense.kick": (0.1, 0.1)}
    if g in ("ice", "epic"):
        hall = make_ir(2.8, 0.03, 0.45, 1.1, 0.25, seed=41)
    elif g == "metal":
        hall = make_ir(2.0, 0.02, 0.35, 1.2, 0.3, seed=42)
    else:
        hall = make_ir(1.9, 0.02, 0.4, 1.1, 0.25, seed=43)
    stems = render_layers(s, chains, levels, sends, hall=hall)
    meta = {"bpm": bpm, "bars": 16, "beats_per_bar": 4, "key": NAMES[tonic] + " " + mode, "arena": arena,
            "genre": g}
    return stems, meta


def render_layers(s: Song, chains, levels, sends, hall, target_lufs=-16.0, ceiling_db=-1.5):
    room = make_ir(0.9, 0.008, 0.5, 1.0, 0.35, seed=3)
    L = s.N + max(room.shape[-1], hall.shape[-1])
    stems = {}
    for layer in LAYERS:
        total = np.zeros((2, L))
        rin = np.zeros((2, s.N))
        hin = np.zeros((2, s.N))
        for name, buf in s.buses.items():
            if not name.startswith(layer + "."):
                continue
            fx = chains.get(name)
            y = fx(buf) if fx else buf
            y = pad_to(y, s.N) * db2lin(levels.get(name, -6.0))
            total[:, :s.N] += y
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
        # circular DC block: a plain IIR would start cold at sample 0 and step at the loop seam
        stems[layer] = process_circular(wrap_tail(total, s.loop_n), lambda z: dc_block(z, 20.0), 3.0)
    # one gain for all stems: calm + wave at the target loudness
    base = stems["calm"] + stems["wave"]
    gain = db2lin(target_lufs - loudness(base)["integrated"])
    out = {}
    for layer, x in stems.items():
        out[layer] = process_circular(x * gain, lambda z: limiter(z, ceiling_db, 0.005, 0.12), 3.0)
    return out


# ---------------------------------------------------------------------------
# stings
# ---------------------------------------------------------------------------
def _sting_song(name, bpm, bars_):
    s = Song(name, bpm, bars_, tail=3.0, loop=False)
    return s


def _finish_sting(s, chains, levels, sends, target=-15.0):
    out = s.render(chains, levels, sends, hall=make_ir(2.4, 0.03, 0.4, 1.1, 0.25, seed=51),
                   target_lufs=target, ceiling_db=-1.5)
    # trim trailing silence, short fade
    a = np.abs(out).max(axis=0)
    idx = np.nonzero(a > 10 ** (-60 / 20))[0]
    end = min(out.shape[-1], (idx[-1] if len(idx) else out.shape[-1]) + ns(0.05))
    return fade(out[:, :end], 0.002, 0.3)


def sting_boss_intro():
    """~3 s: two taiko hits, a low brass + choir swell on a minor chord, a riser and a final slam."""
    s = _sting_song("sting_boss_intro", 100, 2)
    rng = s.rng
    kit = kit_rock(rng, kick_f=(150, 45), kick_decay=0.35)
    s.drums(0, {"tk": "x.....x.........", "tk2": "........x.x....."}, kit)
    s.drums(1, {"tk": "x...............", "cr": "x...............", "cr2": "x..............."}, kit)
    for m in (40, 47, 52, 55):  # E minor, low
        s.note("brass", ins.brass, m, 0.0, 3.6, 0.85, growl=0.6, attack=0.4)
    for m in (64, 67, 71):
        s.note("choir", ins.choir, m, 0.5, 3.4, 0.6, vowel="o")
    s.note("brass", ins.brass, 40, 4.0, 2.0, 1.0, growl=0.8)
    s.note("brass", ins.brass, 47, 4.0, 2.0, 0.9, growl=0.8)
    s.note("sub", ins.bass_sub, 28, 4.0, 2.5, 1.0)
    s.add("fx", riser(s.secs(3.6), rng, 200, 4000), 0.3, 0.55)
    s.add("fx", impact(rng, 50, 0.7), 4.0, 0.9)
    chains = {"brass": lambda x: hp(x, 70), "choir": lambda x: chorus(x, 0.3, 3, 14, 0.4),
              "toms": lambda x: compressor(x, -14, 3, 0.003, 0.1, 6)}
    levels = {"toms": 0, "hats": -6, "brass": -3, "choir": -6, "fx": -4, "sub": -6, "kick": -4}
    sends = {"toms": (0.1, 0.35), "brass": (0, 0.3), "choir": (0, 0.45), "fx": (0, 0.3)}
    out = _finish_sting(s, chains, levels, sends)
    return out, {"bpm": 100, "key": "E minor"}


def sting_boss_defeat():
    """~3.5 s: triumphant brass fanfare (major), timpani roll, crash and a bright chord."""
    s = _sting_song("sting_boss_defeat", 132, 2)
    rng = s.rng
    kit = kit_rock(rng)
    fan = [(0.0, 0.5, [64, 67, 71]), (0.5, 0.5, [64, 67, 71]), (1.0, 0.5, [66, 69, 74]),
           (1.5, 2.5, [67, 71, 76])]  # E minor -> G major
    for b, d, ch in fan:
        for m in ch:
            s.note("brass", ins.brass, m, b, d * 0.92, 0.95, bright=1.2)
    for m in (55, 59, 62, 67, 71, 74, 79):  # final G major chord
        s.note("brass", ins.brass, m, 4.0, 3.0, 0.85, bright=1.1)
    for m in (79, 83, 86, 91):
        s.note("bell", ins.bell, m, 4.0, 2.0, 0.55, kind="glock")
    for i in range(12):  # timpani roll into the chord
        s.add("timp", ins.timpani(rng, 43, 0.35 + 0.05 * i, 1.2), 2.5 + i * 0.125, 0.6)
    s.add("timp", ins.timpani(rng, 43, 1.0, 2.0), 4.0, 0.9)
    s.drums(1, {"cr": "x...............", "cr2": "x..............."}, kit)
    s.note("sub", ins.bass_sub, 31, 4.0, 3.0, 0.9)
    chains = {"brass": lambda x: compressor(x, -16, 2.5, 0.005, 0.12, 6),
              "bell": lambda x: x + 0.3 * delay(x, s.secs(0.5), 0.35, 4, 4000)[:, :x.shape[-1]]}
    levels = {"brass": -2, "bell": -9, "timp": -4, "hats": -5, "sub": -8}
    sends = {"brass": (0.05, 0.3), "bell": (0, 0.4), "timp": (0.05, 0.3), "hats": (0, 0.2)}
    out = _finish_sting(s, chains, levels, sends)
    return out, {"bpm": 132, "key": "G major"}


# ---------------------------------------------------------------------------
# registry (used by build_audio.py)
# ---------------------------------------------------------------------------
STEM_QUALITY = 3
STEM_VOLUME_DB = -7.0  # same playback level as battle_theme

REGISTRY = {arena: {"fn": (lambda a=arena: compose(a))} for arena in STYLES}
STINGS = {
    "sting_boss_intro": {"fn": sting_boss_intro, "loop": False, "volume_db": -6.0, "quality": 5},
    "sting_boss_defeat": {"fn": sting_boss_defeat, "loop": False, "volume_db": -6.0, "quality": 5},
}
