#!/usr/bin/env python3
"""Analyse every file in assets/audio and flag technical problems.

    uv run --with numpy --with scipy python tools/audio/check_audio.py [--plots DIR] [--md OUT.md]

Reports per file: duration, channels, sample peak, 4x true peak, RMS, loudness
(integrated LUFS for music/ambience, max momentary LUFS for SFX), DC offset,
first/last sample (click risk), loop-seam jump (sample + derivative, compared
with the signal's own 99.9th-percentile step), spectral centroid and the share
of energy above 8 kHz.  --plots renders waveform + spectrogram PNGs
(needs matplotlib).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

from dsp import SR, lin2db, loudness, read_audio, true_peak_db  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
AUDIO = os.path.join(ROOT, "assets", "audio")


def analyse(path: str, loop: bool) -> dict:
    x = read_audio(path)
    ch, n = x.shape
    mono = x.mean(axis=0)
    pk = float(np.max(np.abs(x)))
    r = float(np.sqrt(np.mean(x ** 2)))
    lu = loudness(x if ch == 2 else x[0])
    d = {
        "file": os.path.relpath(path, AUDIO), "dur": n / SR, "ch": ch,
        "peak_db": float(lin2db(pk)), "tp_db": true_peak_db(x), "rms_db": float(lin2db(r)),
        "lufs": lu["integrated"], "mom_max": lu["momentary_max"],
        "dc": float(np.max(np.abs(x.mean(axis=1)))),
        "first": float(np.max(np.abs(x[:, 0]))) / max(pk, 1e-9),
        "last": float(np.max(np.abs(x[:, -1]))) / max(pk, 1e-9),
    }
    if loop:
        # Seam test: the step across the loop point (last -> first sample) is
        # compared with the largest steps the signal itself makes within ~93 ms
        # on either side of the seam (ratio <= 1: the seam is no rougher than
        # the surrounding audio, including codec noise).
        w = 4096
        a, b = x[:, -w:], x[:, :w]
        local1 = max(np.max(np.abs(np.diff(a, axis=1))), np.max(np.abs(np.diff(b, axis=1))))
        local2 = max(np.max(np.abs(np.diff(a, 2, axis=1))), np.max(np.abs(np.diff(b, 2, axis=1))))
        jump = float(np.max(np.abs(x[:, 0] - x[:, -1])))
        d2 = np.concatenate([x[:, -2:], x[:, :2]], axis=1)
        djump = float(np.max(np.abs(np.diff(d2, 2, axis=1))))
        d["seam_ratio"] = jump / max(local1, 1e-9)
        d["seam_dratio"] = djump / max(local2, 1e-9)
        wl = int(0.05 * SR)
        e0 = np.sqrt(np.mean(x[:, :wl] ** 2)) + 1e-9
        e1 = np.sqrt(np.mean(x[:, -wl:] ** 2)) + 1e-9
        d["seam_level_db"] = float(20 * np.log10(e0 / e1))
    spec = np.abs(np.fft.rfft(mono * np.hanning(n))) ** 2
    f = np.fft.rfftfreq(n, 1 / SR)
    tot = spec.sum() + 1e-20
    d["centroid"] = float((spec * f).sum() / tot)
    d["hf8k"] = float(spec[f > 8000].sum() / tot)
    return d


def flags(d: dict, cat: str, name: str) -> list:
    out = []
    if d["tp_db"] > -0.5:
        out.append("true-peak>-0.5")
    if d["dc"] > 0.002:
        out.append(f"DC {d['dc']:.4f}")
    if "seam_ratio" in d:
        if d["seam_ratio"] > 1.0 or d["seam_dratio"] > 1.0:
            out.append(f"seam {d['seam_ratio']:.2f}/{d['seam_dratio']:.2f}")
        # Arena stems start on an accented downbeat (crash / heartbeat kick), so a level step at the
        # seam is musical there; the jump/derivative ratios above still catch real discontinuities.
        if abs(d["seam_level_db"]) > 6.0 and cat != "music_layer":
            out.append(f"seam level {d['seam_level_db']:+.1f} dB")
    else:
        if d["first"] > 0.05:
            out.append(f"start {d['first']:.2f}")
        if d["last"] > 0.01:
            out.append(f"end {d['last']:.2f}")
    if cat == "sfx":
        if d["peak_db"] > -2.5:
            out.append("peak>-2.5")
        if any(name.startswith(p) for p in ("throw_", "ball_hit_", "glove_catch_", "footstep")) and d["dur"] > 0.35:
            out.append("too long")
    else:
        if d["peak_db"] > -1.0:
            out.append("peak>-1")
    if d["hf8k"] > 0.08:
        out.append(f"HF {d['hf8k'] * 100:.0f}%")
    return out


def stem_report(man: dict) -> list:
    """Adaptive arena stems: identical lengths, and loudness / peak of the layer combinations
    the game plays (calm; calm+wave; +boss; +tense; all)."""
    arenas = sorted({e["arena"] for e in man.values() if e.get("category") == "music_layer"})
    if not arenas:
        return []
    out = ["", "### Arena stems (in-game level = LUFS + stem volume)", "",
           "| arena | samples equal | calm | calm+wave | +boss | +tense | all | all peak dBFS | flags |",
           "|---|---|---|---|---|---|---|---|---|"]
    combos = [("calm",), ("calm", "wave"), ("calm", "wave", "boss"), ("calm", "wave", "tense"),
              ("calm", "wave", "boss", "tense")]
    for a in arenas:
        st = {}
        for layer in ("calm", "wave", "boss", "tense"):
            e = man.get(f"{a}_{layer}")
            if e:
                st[layer] = read_audio(os.path.join(ROOT, e["path"].replace("res://", "")))
        lens = {x.shape[-1] for x in st.values()}
        n = min(lens)
        vol = float(man[f"{a}_calm"].get("volume_db", 0.0))
        vals = []
        pk = 0.0
        for c in combos:
            x = sum(st[k][:, :n] for k in c)
            vals.append(loudness(x)["integrated"] + vol)
            pk = float(lin2db(np.max(np.abs(x))))
        fl = []
        if len(lens) != 1:
            fl.append(f"lengths {sorted(lens)}")
        if vals[0] < vals[1] - 9:
            fl.append("calm much quieter")
        out.append(f"| {a} | {'yes' if len(lens) == 1 else 'NO'} | " + " | ".join(f"{v:.1f}" for v in vals)
                   + f" | {pk:.1f} | {', '.join(fl) or 'ok'} |")
    return out


def plot(path: str, out_png: str):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    x = read_audio(path)
    mono = x.mean(axis=0)
    t = np.arange(len(mono)) / SR
    fig, ax = plt.subplots(2, 1, figsize=(10, 5.5), sharex=True,
                           gridspec_kw={"height_ratios": [1, 1.6]})
    for c in range(x.shape[0]):
        ax[0].plot(t, x[c], lw=0.4, alpha=0.8)
    ax[0].set_ylim(-1, 1)
    ax[0].set_ylabel("amp")
    ax[0].set_title(os.path.basename(path))
    nfft = 2048 if len(mono) > 20000 else 512
    ax[1].specgram(mono + 1e-9, NFFT=nfft, Fs=SR, noverlap=nfft // 2, cmap="magma",
                   vmin=-130, vmax=-20)
    ax[1].set_ylim(0, 12000)
    ax[1].set_ylabel("Hz")
    ax[1].set_xlabel("s")
    fig.tight_layout()
    fig.savefig(out_png, dpi=80)
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plots", default=None, help="directory for PNG plots")
    ap.add_argument("--plot-only", nargs="*", default=None, help="names to plot (default all)")
    ap.add_argument("--md", default=None, help="write the table as markdown to this file")
    args = ap.parse_args()
    with open(os.path.join(AUDIO, "manifest.json")) as fh:
        man = {e["name"]: e for e in json.load(fh)["files"]}
    files = sorted(glob.glob(os.path.join(AUDIO, "**", "*.wav"), recursive=True)
                   + glob.glob(os.path.join(AUDIO, "**", "*.ogg"), recursive=True))
    rows = []
    hdr = ("| file | dur s | ch | peak dBFS | true pk | RMS dBFS | LUFS | DC | seam (jump/deriv ratio) | "
           "centroid Hz | >8k % | play dB | in game | flags |")
    lines = [hdr, "|" + "---|" * 14]
    nflag = 0
    total_bytes = 0
    for p in files:
        name = os.path.splitext(os.path.basename(p))[0]
        e = man.get(name, {})
        cat = e.get("category", "?")
        d = analyse(p, bool(e.get("loop")))
        fl = flags(d, cat, name)
        nflag += bool(fl)
        total_bytes += os.path.getsize(p)
        lufs = d["lufs"] if cat != "sfx" else d["mom_max"]
        seam = f"{d['seam_ratio']:.2f}/{d['seam_dratio']:.2f}" if "seam_ratio" in d else "-"
        vol = float(e.get("volume_db", 0.0))
        lines.append(f"| {d['file']} | {d['dur']:.2f} | {d['ch']} | {d['peak_db']:.1f} | {d['tp_db']:.1f} | "
                     f"{d['rms_db']:.1f} | {lufs:.1f}{'' if cat != 'sfx' else ' (M)'} | {d['dc']:.4f} | {seam} | "
                     f"{d['centroid']:.0f} | {d['hf8k'] * 100:.1f} | {vol:+.1f} | {lufs + vol:.1f} | "
                     f"{', '.join(fl) or 'ok'} |")
        rows.append(d)
        if args.plots and (args.plot_only is None or name in args.plot_only):
            os.makedirs(args.plots, exist_ok=True)
            plot(p, os.path.join(args.plots, name + ".png"))
    lines.append("")
    lines.append(f"{len(files)} files, {total_bytes / 1e6:.2f} MB total, {nflag} with flags")
    lines += stem_report(man)
    text = "\n".join(lines)
    print(text)
    if args.md:
        with open(args.md, "w") as fh:
            fh.write(text + "\n")


if __name__ == "__main__":
    main()
