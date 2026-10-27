# Update 5 review: menus and design system (Stream E)

Scope: main menu, Play, Progression (all tabs), Results, Dugout, Settings (all tabs), Pause, Team,
Cards & Deck, Upgrade Cards, Card Packs. Evidence: the captures in `docs/screenshots/` (1600×900) plus
baseline captures of Settings, Progression → Achievements, main menu and Play at 1920×1080 and 1280×720.

Scoring as in the plan: **Severity** 1 cosmetic … 4 breaks the experience; **Reach** 1 rare … 4 every
session; **Effort** S = 1, M = 2, L = 3. **Priority = Severity × Reach ÷ Effort.** Seed findings from the plan
keep their numbers (19–25).

Checklist used per screen: purpose clear in 2 s · one focal point · consistency (buttons, panels, headers,
type scale, colours) · minimum text 16 px at 1080p · motion and click feedback within 100 ms · sound ·
empty and maxed states · scaling 1280×720 – 2560×1440 and UI scale 0.8–1.25.

## Scaling note

The project uses `canvas_items` stretch with `expand` aspect on a 1920×1080 base, so 1280×720 and
2560×1440 are the same layout scaled. What changes the layout is the **UI scale** setting (and Larger text):
at 1.25 the canvas is 1536×864, at 0.8 it is 2400×1350. Fixed minimum widths that add up to more than
~1450 px overflow at UI scale 1.25. 16 px design text renders at 10.7 px physical on a 720p window; that
is the floor, so nothing in menus should be smaller than 16.

## Findings

| # | Screen | Finding | Sev | Reach | Effort | Priority | Status |
|---|---|---|---|---|---|---|---|
| 24 | All menus | No shared design system: four button styles (skewed menu bars, flat small buttons, tab buttons, arena rows), panel paddings/radii differ per screen, headers are plain gold text with different sizes (24–34), no common enter animation, hover feedback only on some buttons. | 3 | 4 | M | 6.0 | Fixed |
| 19 | Main menu | Ten identical bars with no emphasis; PLAY looks like EXIT; disabled CONTINUE RUN always visible; no icons or grouping; badges are text suffixes ("CARD PACKS (3)"). Camera barely moves, lineup is static apart from catch. | 3 | 4 | M | 6.0 | Fixed |
| 22 | Results | Stats panel half empty, rewards read like a spreadsheet, everything appears at once; no story of the game (no graph, no highlights); MVP is a small line. | 3 | 4 | M | 6.0 | Fixed |
| 20 | Play | Three flat columns with large empty areas (mode column bottom, deck panel); stadiums are text rows without pictures; difficulty shown as one line of numbers; locked items only say "LOCKED: …" in 17 px. | 3 | 3 | M | 4.5 | Fixed |
| 21 | Progression | Overview is mostly empty: small level number, plain stats list, ladder cards in a row with no progress shown, next reward hidden in a sentence. Achievement progress bars are 6 px and show no numbers. Stadiums tab uses colour swatches instead of pictures. | 3 | 2 | M | 3.0 | Fixed |
| E1 | Settings | Two-column grid fills a third of the width, two thirds of the screen is empty; CheckButtons inherit the red pressed button style (a red bar 360 px wide); no explanations for options; no search; no help choosing a quality preset. | 2 | 3 | M | 3.0 | Fixed |
| 23 | Dugout | NOW/NEXT captions are 15 px; the BUY button text ("BUY 50") is not a price and the UI test could not find it (its check silently skipped); headers inconsistent with the rest. Icons per upgrade already existed. | 2 | 3 | S | 6.0 | Fixed |
| E2 | Pause | Plain stack of identical bars; no game status; Controls opens an unthemed AcceptDialog with monospace-aligned text in a proportional font. | 2 | 3 | S | 6.0 | Fixed |
| E3 | Results | "Play again" reused the profile deck/team rather than the game's settings and was undefined for Promotion Challenges (it replays the old division's challenge after a promotion). | 3 | 2 | S | 6.0 | Fixed |
| E4 | Router | Every screen change fades 0.28 s out + 0.35 s in with linear easing; feels sluggish. | 1 | 4 | S | 4.0 | Fixed (0.2 s in / 0.28 s out, eased) |
| E5 | All menus | Text below 16 px: dugout NOW/NEXT (15), Cards & Deck detail captions (15), pack shop captions (14), pack summary tags (14). | 2 | 3 | S | 6.0 | Fixed |
| E6 | Team | Headers and action buttons in the old style; otherwise fine after the Update 4 rework. | 1 | 3 | S | 3.0 | Fixed (consistency only) |
| E7 | Progression → History | Empty state is one grey line. | 1 | 2 | S | 2.0 | Fixed (icon, text, PLAY button) |
| E8 | Play / UI scale 1.25 | Fixed widths (560 + 440 + middle) overflow the canvas at UI scale 1.25. | 2 | 1 | S | 2.0 | Fixed (500 + 400, stadium tiles flow) |
| 25 | Card Packs ×10 grid | Card text ~9–10 px at 1600×900 in the ten-pack grid; full text should show on hover. | 2 | 2 | M | 2.0 | Deferred (packs screen was just redesigned; owner of `card_view.gd` is the lead) |
| E9 | Main menu | Welcome panel for new players overlaps the profile panel area at 720p-equivalent heights when Continue is shown. | 1 | 1 | S | 1.0 | Checked, no overlap with the new layout |

## What the design system defines (`src/ui/ui_theme.gd`)

* **Type scale** (design px at 1080p): `FS_MIN` 16 · `FS_SMALL` 18 · `FS_BODY` 20 · `FS_LEAD` 24 · `FS_H3` 26 ·
  `FS_H2` 30 · `FS_H1` 40 · `FS_TITLE` 64. Nothing in the menus goes below 16.
* **Panels**: `card_panel()` for a screen's main blocks, `tile_panel()` for tiles inside them (with a
  highlighted variant), `section_header()` (icon + caps + fading rule) for every panel title.
* **Buttons**: `button(text, variant, size, icon, accent)` with `primary` (the one main action per screen),
  `secondary`, `danger`, `ghost`; `icon_button()`; heights `BTN_H_HERO` 112, `BTN_H_LARGE` 72, `BTN_H` 56,
  `BTN_H_SMALL` 44. All menu buttons share hover grow (1.03) and press squish (0.96) via `add_feedback()`
  and play `ui_hover`/`ui_click` (BACK plays `ui_back`).
* **Widgets**: `badge()`, `bar()`, `stat_tile()`, `ProgressRing`, `RunGraph`.
* **Motion**: `animate_in()` (fade + rise, 0.22–0.35 s, cubic ease-out) used by `MenuScreen` for the header and
  each content block in a 50 ms stagger, and by overlays (pause, dialogs, results panels).
* **Header**: every `MenuScreen` has the same BACK button top-left (170×56, Esc also works), the title at 64 px,
  a subtitle at 20 px and the currencies in one pill on the right.

## Verification

* `tools/check_scripts.sh`: all scripts compile.
* Test suite: 962 checks, 0 failed (new "menus" section: settings search filters rows and categories, the
  Results screen builds the game-flow graph and the three highlights from a result).
* UI flow test (full run, 1600×900): 110 checks, 0 failed. The dugout purchase check now runs (the price
  button text is the amount, so the test finds it; before it was skipped silently).
* Captures (1920×1080 and 1280×720, plus Play at UI scale 1.25) were reviewed for every redesigned screen.
  Found and fixed from the captures: oversized search icon, two stadium tiles per row, empty lower third
  on Progression (now "Almost there" achievements), START cut off at UI scale 1.25 (columns now scroll).

## Tools added

* `tools/art/arena_thumbs.tscn` renders `assets/textures/arenas/<id>.jpg` (640×360) for every arena;
  re-run it after stadium art changes (`--only=<arena_id>` for one).
* Screenshot helpers: `--tab=N` (Progression), `--settings-tab=<id>`, `--settings-search=<text>`,
  `--run-benchmark` (Settings), `--open-pause` (battle), `--ui-scale=1.25` (menus), and `--show-results`
  now also fills demo game-flow data and highlights.
