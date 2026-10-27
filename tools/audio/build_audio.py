#!/usr/bin/env python3
"""Rebuild every Baseball Draw audio asset deterministically.

Usage (from the repo root):
    uv run --with numpy --with scipy python tools/audio/build_audio.py [--only sfx|music|ambience|NAME ...] [--jobs N]

Outputs:
    assets/audio/sfx/*.wav          44.1 kHz 16-bit mono
    assets/audio/music/*.ogg        Vorbis q5, 44.1 kHz stereo, seamless loops
    assets/audio/music/arena/*.ogg  per-arena adaptive stems (calm/wave/boss/tense), Vorbis q3,
                                    all stems of an arena exactly the same length
    assets/audio/ambience/*.ogg     Vorbis q4, stereo, seamless loops
    assets/audio/manifest.json
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402

from dsp import SR, peak, lin2db, loudness, rng_for, seed_of, write_ogg, write_wav  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")


def build_sfx(name: str):
    import sfx
    fn, vol, loop, group = sfx.REGISTRY[name]
    x = fn(rng_for("sfx:" + name))
    path = os.path.join(OUT, "sfx", name + ".wav")
    write_wav(path, x, loop=loop, seed=seed_of(name))
    return {"name": name, "path": f"res://assets/audio/sfx/{name}.wav", "category": "sfx",
            "duration": round(len(x) / SR, 3), "loop": loop, "volume_db": vol,
            "group": group, "peak_dbfs": round(float(lin2db(peak(x))), 2),
            "loudness": round(float(loudness(x)["momentary_max"]), 2)}


def build_music(name: str):
    import music
    spec = music.REGISTRY[name]
    x, meta = spec["fn"]()
    path = os.path.join(OUT, "music", name + ".ogg")
    write_ogg(path, x, quality=spec.get("quality", 5), loop=spec["loop"], title=name)
    d = {"name": name, "path": f"res://assets/audio/music/{name}.ogg", "category": "music",
         "duration": round(x.shape[-1] / SR, 3), "loop": spec["loop"], "volume_db": spec["volume_db"],
         "group": None, "loudness": round(float(loudness(x)["integrated"]), 2)}
    d.update(meta)
    return d


def build_arena(name: str):
    import arena_music
    stems, meta = arena_music.REGISTRY[name]["fn"]()
    out = []
    for layer, x in stems.items():
        nm = f"{name}_{layer}"
        path = os.path.join(OUT, "music", "arena", nm + ".ogg")
        write_ogg(path, x, quality=arena_music.STEM_QUALITY, loop=True, title=nm)
        d = {"name": nm, "path": f"res://assets/audio/music/arena/{nm}.ogg", "category": "music_layer",
             "duration": round(x.shape[-1] / SR, 3), "loop": True, "volume_db": arena_music.STEM_VOLUME_DB,
             "group": None, "layer": layer, "samples": int(x.shape[-1])}
        d.update(meta)
        out.append(d)
    return out


def build_sting(name: str):
    import arena_music
    spec = arena_music.STINGS[name]
    x, meta = spec["fn"]()
    path = os.path.join(OUT, "music", name + ".ogg")
    write_ogg(path, x, quality=spec.get("quality", 5), loop=False, title=name)
    d = {"name": name, "path": f"res://assets/audio/music/{name}.ogg", "category": "music",
         "duration": round(x.shape[-1] / SR, 3), "loop": False, "volume_db": spec["volume_db"], "group": None,
         "loudness": round(float(loudness(x)["integrated"]), 2)}
    d.update(meta)
    return d


def build_ambience(name: str):
    import ambience
    spec = ambience.REGISTRY[name]
    x = spec["fn"]()
    path = os.path.join(OUT, "ambience", name + ".ogg")
    write_ogg(path, x, quality=5, loop=True, title=name)
    return {"name": name, "path": f"res://assets/audio/ambience/{name}.ogg", "category": "ambience",
            "duration": round(x.shape[-1] / SR, 3), "loop": True, "volume_db": spec["volume_db"],
            "group": None}


def _job(kind_name):
    kind, name = kind_name
    t0 = time.time()
    fn = {"sfx": build_sfx, "music": build_music, "ambience": build_ambience, "arena": build_arena,
          "sting": build_sting}[kind]
    d = fn(name)
    for e in (d if isinstance(d, list) else [d]):
        e["_build_s"] = round(time.time() - t0, 1)
    return d


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=None,
                    help="categories (sfx/music/ambience) or individual asset names")
    # Each worker can use >1 GB while rendering music; keep the default modest.
    ap.add_argument("--jobs", type=int, default=min(2, max(1, (os.cpu_count() or 2))))
    args = ap.parse_args()

    import ambience
    import arena_music
    import music
    import sfx
    # slowest jobs first so the pool stays busy
    jobs = ([("arena", n) for n in arena_music.REGISTRY] + [("music", n) for n in music.REGISTRY]
            + [("sting", n) for n in arena_music.STINGS] + [("ambience", n) for n in ambience.REGISTRY]
            + [("sfx", n) for n in sfx.REGISTRY])
    if args.only:
        jobs = [j for j in jobs if j[0] in args.only or j[1] in args.only
                or (j[0] == "sting" and "music" in args.only)]

    manifest_path = os.path.join(OUT, "manifest.json")
    old = {}
    if os.path.exists(manifest_path):
        with open(manifest_path) as fh:
            for e in json.load(fh).get("files", []):
                old[e["name"]] = e

    t0 = time.time()
    results = {}
    with ProcessPoolExecutor(max_workers=args.jobs) as ex:
        for res in ex.map(_job, jobs):
            for d in (res if isinstance(res, list) else [res]):
                print(f"  {d['category']:11s} {d['name']:28s} {d['duration']:7.2f}s  ({d.pop('_build_s')} s)",
                      flush=True)
                results[d["name"]] = d
    old.update(results)

    arena_names = [f"{a}_{layer}" for a in arena_music.REGISTRY for layer in arena_music.LAYERS]
    order = {n: i for i, n in enumerate(list(music.REGISTRY) + list(arena_music.STINGS) + arena_names
                                        + list(ambience.REGISTRY) + list(sfx.REGISTRY))}
    files = sorted((v for k, v in old.items() if k in order), key=lambda e: order[e["name"]])
    groups = {}
    for e in files:
        if e.get("group"):
            groups.setdefault(e["group"], []).append(e["name"])
    import mix
    mix.apply_targets(files)
    by_name = {e["name"]: e["volume_db"] for e in files}
    for g, members in groups.items():
        by_name[g] = by_name[members[0]]
    manifest = {
        "_comment": "Generated by tools/audio/build_audio.py. volume_db is a suggested playback "
                    "volume (AudioStreamPlayer.volume_db). 'groups' maps a play name to its random "
                    "variants; 'volume_db_by_name' covers both file names and group names. Looping "
                    "WAVs carry a RIFF 'smpl' loop (Godot 'Detect From WAV'); for OGG set "
                    "stream.loop = true when loop is true.",
        "sample_rate": SR,
        "groups": groups,
        "volume_db_by_name": by_name,
        "arenas": {a: {"layers": {layer: f"res://assets/audio/music/arena/{a}_{layer}.ogg"
                                  for layer in arena_music.LAYERS},
                       "bpm": arena_music.STYLES[a]["bpm"], "bars": 16}
                   for a in arena_music.REGISTRY},
        "files": [{k: v for k, v in e.items() if v is not None} for e in files],
    }
    with open(manifest_path, "w") as fh:
        json.dump(manifest, fh, indent=1)
    print(f"done: {len(results)} assets in {time.time() - t0:.1f} s -> {manifest_path}")


if __name__ == "__main__":
    main()
