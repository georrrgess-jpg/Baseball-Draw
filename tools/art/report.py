"""Asset report: contact sheets + docs/asset_reports/art.md (file list generated from disk)."""
from __future__ import annotations

import io
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

from artlib.core import CATEGORY, FONT_DIR, RARITY, ROOT, TEX_DIR, rasterize, to_image

DOC_DIR = ROOT / "docs" / "asset_reports"
IMG_DIR = DOC_DIR / "img"


def _font(name, size):
    return ImageFont.truetype(str(FONT_DIR / name), size)


def _save_jpg(img: Image.Image, path: Path, max_kb: int = 590):
    path.parent.mkdir(parents=True, exist_ok=True)
    for q in (90, 86, 82, 78, 74, 70, 64, 58):
        buf = io.BytesIO()
        img.convert("RGB").save(buf, "JPEG", quality=q, optimize=True, progressive=True)
        if buf.tell() <= max_kb * 1024:
            break
    path.write_bytes(buf.getvalue())
    return path


def cards_sheet():
    cards = json.loads((ROOT / "data" / "cards.json").read_text())["cards"]
    tw, th = 256, 192
    pad, lab = 14, 46
    cols = 5
    rows = (len(cards) + cols - 1) // cols
    W = cols * (tw + pad) + pad
    H = rows * (th + lab + pad) + pad + 70
    sheet = Image.new("RGB", (W, H), "#0E1A2B")
    dr = ImageDraw.Draw(sheet)
    dr.text((pad, 18), "BASEBALL DRAW  -  CARD ILLUSTRATIONS (512x384)", fill="#F4F1EA", font=_font("Teko-Variable.ttf", 40))
    f1 = _font("BarlowCondensed-Bold.ttf", 21)
    f2 = _font("BarlowCondensed-Medium.ttf", 16)
    for i, c in enumerate(cards):
        x = pad + (i % cols) * (tw + pad)
        y = 70 + pad + (i // cols) * (th + lab + pad)
        im = Image.open(TEX_DIR / "cards" / f"{c['id']}.png").convert("RGB").resize((tw, th), Image.LANCZOS)
        dr.rectangle((x - 3, y - 3, x + tw + 2, y + th + 2), fill=RARITY[c["rarity"]])
        sheet.paste(im, (x, y))
        dr.rectangle((x, y + th + 4, x + 6, y + th + 38), fill=CATEGORY[c["category"]])
        dr.text((x + 12, y + th + 3), c["name"].upper(), fill="#F4F1EA", font=f1)
        dr.text((x + 12, y + th + 25), f"{c['category']}  /  {c['rarity']}  /  {c['id']}", fill="#9AA6B8", font=f2)
    return _save_jpg(sheet, IMG_DIR / "cards_contact_sheet.jpg")


def _cover(img: Image.Image, w: int, h: int) -> Image.Image:
    k = max(w / img.width, h / img.height)
    r = img.resize((int(img.width * k + 0.5), int(img.height * k + 0.5)), Image.LANCZOS)
    x0, y0 = (r.width - w) // 2, (r.height - h) // 2
    return r.crop((x0, y0, x0 + w, y0 + h))


def _fit(img: Image.Image, w: int) -> Image.Image:
    return img.resize((w, int(img.height * w / img.width)), Image.LANCZOS)


def logo_preview():
    L = lambda n: Image.open(TEX_DIR / "logo" / n).convert("RGBA")
    W, H1, H2 = 1600, 600, 300
    sheet = Image.new("RGBA", (W, H1 + H2), "#0E1A2B")
    # row 1: logo on the navy UI | tagline lock-up on the sunset loading screen
    sun = _cover(Image.open(TEX_DIR / "ui" / "loading_bg.png").convert("RGBA"), W // 2, H1)
    sheet.paste(sun, (W // 2, 0))
    l1 = _fit(L("logo.png"), 720)
    sheet.alpha_composite(l1, ((W // 2 - l1.width) // 2, (H1 - l1.height) // 2))
    t1 = _fit(L("logo_tagline.png"), 700)
    sheet.alpha_composite(t1, (W // 2 + (W // 2 - t1.width) // 2, (H1 - t1.height) // 2))
    # row 2: small logo, brush stroke behind a heading, app icon sizes
    y2 = H1
    dr = ImageDraw.Draw(sheet)
    dr.rectangle((0, y2, W, y2 + H2), fill="#14233A")
    sm = _fit(L("logo_small.png"), 380)
    sheet.alpha_composite(sm, (40, y2 + (H2 - sm.height) // 2))
    br = L("brush_stroke.png").resize((560, 88), Image.LANCZOS)
    bx, by = 470, y2 + (H2 - 88) // 2
    sheet.alpha_composite(br, (bx, by))
    f = _font("Teko-Variable.ttf", 58)
    tw = dr.textlength("UPGRADE THE ROSTER", font=f)
    dr.text((bx + 280, by + 44), "UPGRADE THE ROSTER", fill="#FFFFFF", font=f, anchor="mm")
    icon = L("icon_256.png")
    x = 1090
    for sz in (192, 64, 32, 16):
        sheet.alpha_composite(icon.resize((sz, sz), Image.LANCZOS), (x, y2 + (H2 - sz) // 2))
        x += sz + 22
    return _save_jpg(sheet, IMG_DIR / "logo_preview.jpg", 700)


def ui_sheet():
    import icons
    cols, cell = 13, 96
    names = icons.NAMES
    rows = (len(names) + cols - 1) // cols
    W = cols * cell
    ranks_h = 300
    H = rows * cell + ranks_h + 40
    sheet = Image.new("RGBA", (W, H), "#14233A")
    dr = ImageDraw.Draw(sheet)
    f = _font("BarlowCondensed-Medium.ttf", 13)
    for i, n in enumerate(names):
        a = rasterize((TEX_DIR / "icons" / f"{n}.svg").read_text(), 64, 64)
        im = to_image(a, dither=False)
        x, y = (i % cols) * cell, (i // cols) * cell
        sheet.alpha_composite(im, (x + 16, y + 6))
        dr.text((x + 6, y + 74), n, fill="#B8C0CC", font=f)
    y0 = rows * cell + 20
    for i, d in enumerate(["rookie", "bronze", "silver", "gold", "platinum", "diamond", "champion", "legend"]):
        im = Image.open(TEX_DIR / "ui" / f"rank_{d}.png").convert("RGBA").resize((150, 150), Image.LANCZOS)
        sheet.alpha_composite(im, (10 + i * 155, y0))
        dr.text((40 + i * 155, y0 + 152), d, fill="#B8C0CC", font=_font("BarlowCondensed-Medium.ttf", 18))
    for i, r in enumerate(RARITY):
        im = Image.open(TEX_DIR / "ui" / f"gem_{r}.png").convert("RGBA")
        sheet.alpha_composite(im, (300 + i * 140, y0 + 190))
        dr.text((300 + i * 140, y0 + 256), r, fill="#B8C0CC", font=_font("BarlowCondensed-Medium.ttf", 16))
    return _save_jpg(sheet, IMG_DIR / "icons_ranks_sheet.jpg")


def backgrounds_sheet():
    names = ["dugout_bg", "loading_bg"]
    ims = [Image.open(TEX_DIR / "ui" / f"{n}.png").convert("RGB").resize((800, 450), Image.LANCZOS) for n in names]
    sheet = Image.new("RGB", (1620, 470), "#0E1A2B")
    for i, im in enumerate(ims):
        sheet.paste(im, (10 + i * 805, 10))
    return _save_jpg(sheet, IMG_DIR / "backgrounds_sheet.jpg")


STYLE_NOTES = """\
## Style notes

* **Palette** (ASSET_SPEC section 2): navy `#0E1A2B`/`#14233A` and charcoal `#1B1F27` are the base of every
  card and UI image; scarlet `#E0262F` (+ `#A3141C` shadow) is the brand accent (logo "DRAW", brush stroke,
  app icon); gold `#F5B82E` for currency/legendary trims; rarity and category colours are used exactly as specified.
* **Logo**: "BASEBALL" is Permanent Marker with roughened (noise-displaced) outlines, a 10 deg slant, per-letter
  jitter and dry-brush streak holes, sitting on a procedurally painted scarlet dry-brush swoosh that doubles as
  the ball's motion trail. "DRAW" is Bangers, widened 18 %, rough-edged, with an 18-step extrusion in
  scarlet_deep, bevel highlight, white outline and dark navy outer outline. The ball is a 3D-shaded render with
  projected seams/stitches, a comet glow, white light slashes, speed lines, sparks and a starburst. A global
  dark contour + drop shadow keeps it readable on the navy UI and on the bright sunset stadium.
* **Cards**: painted at 1024x768 and Lanczos-downsampled to 512x384. Shared language: dark navy backdrop,
  key light and glow in the category colour (offense `#FF5A36`, control `#7B6CFF`, defense `#2EC4B6`,
  utility `#FFD23F`; linked-defender cards also use that defender's accent), stadium light towers / bokeh for
  depth, comic ink outlines, cel-shaded props, vector comic flames, halftone corners, bloom, vignette, a shadow
  grade toward brand navy and fine grain. Rarity raises intensity: more particles, stronger bloom; epic and
  legendary add sparkle passes and the most elaborate compositions (meteor storm, frozen stopwatch). Key
  content stays inside the centre ~85 % so frames/text overlays do not cover it.
* **Icons**: 64x64 viewBox, pure white, solid silhouettes with even-odd cut-outs and 5 px round strokes,
  4 px safe margin. Only path/circle/rect/polygon + strokes are used (no filters, masks or text) so Godot's
  ThorVG importer renders them exactly; they stay legible down to 16-24 px.
* **Rank emblems**: metal shading via banded gradients and a bevelled trim; ornament escalates
  (leather stitched badge -> bronze -> silver + star -> gold + wings + stars -> platinum + laurels ->
  diamond + ice gem + rays -> champion crimson/gold + crown + crossed bats + banner -> legend purple/gold +
  crown + large wings + prismatic rays). All glows fade to zero before the canvas edge.
* **UI textures**: grain is greyscale (mean 128) for overlay/soft-light use; halftone, diamond pattern and
  grain tile seamlessly; the vignette is black with radial alpha; `card_frame_glow.png` is a white ring
  (strongest on a 256x352 rounded card outline) meant to be tinted with the rarity colour.
* **Backdrops**: the dugout keeps its centre calm (defocused sunset field seen through the opening) with
  detail on the sides (chalkboard play diagram, helmet shelf, bat rack, cooler, bench with glove/helmet);
  the loading screen keeps the upper centre clear for the logo.
"""


def write_md(extra_imgs):
    groups = [
        ("Logo", sorted(p for p in (TEX_DIR / "logo").glob("*.*") if p.suffix in (".png", ".ico"))),
        ("Card illustrations", sorted((TEX_DIR / "cards").glob("*.png"))),
        ("Icons", sorted((TEX_DIR / "icons").glob("*.svg"))),
        ("UI (ranks, gems, textures, backdrops)", sorted((TEX_DIR / "ui").glob("*.png"))),
        ("App icon", [ROOT / "icon.svg"]),
    ]
    lines = ["# Baseball Draw - 2D art report", "",
             "All 2D art is generated procedurally by the scripts in `tools/art/` (no external images).", "",
             "## Rebuild", "",
             "```bash",
             "python3 tools/art/build_art.py            # everything (~2-3 min on 4 cores)",
             "python3 tools/art/build_art.py cards --card heat_wave   # a single card",
             "python3 tools/art/build_art.py logo icons ranks ui appicon report",
             "```", "",
             "Requirements: Python 3.10+ with `numpy` and `Pillow`, plus the system libraries **librsvg-2** and",
             "**cairo** (loaded with `ctypes` for SVG rasterisation and font outlines - no extra pip packages).",
             "Fonts come from `assets/fonts/` (a temporary fontconfig file points cairo/librsvg at them; it is written",
             "to `$ART_TMP`, default `<system temp>/baseball_draw_art`). Output is deterministic (all randomness is seeded).", "",
             "| Module | Produces |", "|---|---|",
             "| `artlib/core.py` | palette, SVG rasteriser, font outlines, compositing, blur, noise |",
             "| `artlib/fx.py` | dry-brush strokes, speed lines, halftone, lightning, vector comic flames, smoke, rays |",
             "| `artlib/baseball.py` | 3D-shaded baseball with projected seams/stitches |",
             "| `artlib/scene.py`, `artlib/props.py` | skies, perspective ground, stadium/crowd silhouettes; glove, stopwatch, padlock, chains... |",
             "| `logo.py` | logo, logo_small, logo_tagline, brush_stroke |",
             "| `cards.py` | 26 card illustrations, card_back, card_frame_glow |",
             "| `icons.py` | 65 SVG icons |", "| `ranks.py` | rank emblems, rarity gems |",
             "| `ui_textures.py` | noise_grain, halftone, diamond_pattern, vignette, dugout_bg, loading_bg |",
             "| `app_icon.py` | icon.svg, icon_256.png, icon.ico |", "| `report.py` | this file + preview sheets |", "",
             "## Previews", ""]
    for title, p in extra_imgs:
        lines.append(f"**{title}**  ")
        lines.append(f"![{title}](img/{p.name})")
        lines.append("")
    lines.append(STYLE_NOTES)
    lines.append("## Files")
    lines.append("")
    for title, files in groups:
        lines.append(f"### {title} ({len(files)})")
        lines.append("")
        for f in files:
            rel = f.relative_to(ROOT)
            if f.suffix == ".png":
                with Image.open(f) as im:
                    dims = f"{im.width}x{im.height}"
            elif f.suffix == ".svg":
                dims = "64x64 viewBox" if "icons" in str(rel) else "256x256 viewBox"
            elif f.suffix == ".ico":
                dims = "16-256 multi-size"
            else:
                dims = ""
            lines.append(f"- `{rel}` {dims}")
        lines.append("")
    lines.append("## Limitations")
    lines.append("")
    lines.append("- Illustrations are stylised vector/procedural paintings (no figure drawing): characters appear as")
    lines.append("  silhouettes, hands, gloves and props rather than full posed players.")
    lines.append("- `noise_grain.png` is an 8-bit greyscale texture; use it with an overlay/soft-light blend or as an alpha source.")
    lines.append("")
    (DOC_DIR / "art.md").write_text("\n".join(lines))
    return DOC_DIR / "art.md"


def build():
    IMG_DIR.mkdir(parents=True, exist_ok=True)
    imgs = [("Card illustrations contact sheet", cards_sheet()),
            ("Logo on navy UI and on the sunset loading screen (+ small logo, brush stroke, app icon)", logo_preview()),
            ("Icons, rank emblems and rarity gems", ui_sheet()),
            ("Dugout and loading backdrops", backgrounds_sheet())]
    md = write_md(imgs)
    for _, p in imgs:
        print(f"  {p.relative_to(ROOT)} ({p.stat().st_size // 1024} KB)")
    print(f"  {md.relative_to(ROOT)}")
    return [md] + [p for _, p in imgs]


if __name__ == "__main__":
    build()
