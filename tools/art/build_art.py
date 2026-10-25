#!/usr/bin/env python3
"""Rebuild every 2D art asset of Baseball Draw.

Usage (from the repo root):
    python3 tools/art/build_art.py                # everything
    python3 tools/art/build_art.py logo cards     # only some groups
    python3 tools/art/build_art.py cards --card heat_wave --card splitter

Groups: logo, cards, packs, icons, ranks, ui, appicon, report
(cards = v2 poster-style illustrations from cards_v2.py; cards_v1 = the previous detailed set)
Requirements: Python 3.10+, numpy, Pillow, and the system libraries librsvg-2 and
cairo (loaded through ctypes; no pip packages beyond numpy/Pillow are needed).
Output paths are listed in docs/asset_reports/art.md.
"""
from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

GROUPS = ["logo", "cards", "packs", "icons", "ranks", "ui", "appicon", "report"]
OPTIONAL = ["cards_v1"]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("groups", nargs="*", choices=GROUPS + OPTIONAL + [[]], help="asset groups to build (default: all)")
    ap.add_argument("--card", action="append", default=None, help="only build these card ids (implies group 'cards')")
    args = ap.parse_args(argv)
    groups = args.groups or GROUPS
    if args.card and "cards" not in groups:
        groups = list(groups) + ["cards"]
    t0 = time.time()
    for g in GROUPS + OPTIONAL:
        if g not in groups:
            continue
        t = time.time()
        print(f"[{g}]")
        if g == "logo":
            import logo
            logo.build()
        elif g == "cards":
            import cards_v2
            cards_v2.build(set(args.card) if args.card else None)
        elif g == "cards_v1":
            import cards
            cards.build(set(args.card) if args.card else None)
        elif g == "packs":
            import packs
            packs.build()
        elif g == "icons":
            import icons
            icons.build()
        elif g == "ranks":
            import ranks
            ranks.build()
        elif g == "ui":
            import ui_textures
            ui_textures.build()
        elif g == "appicon":
            import app_icon
            app_icon.build()
        elif g == "report":
            import report
            report.build()
        print(f"  done in {time.time() - t:.1f}s")
    print(f"all done in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
