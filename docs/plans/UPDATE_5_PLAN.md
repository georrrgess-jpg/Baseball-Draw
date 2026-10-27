# Update 5 plan: "Championship Polish"

Status: **plan only, nothing executed yet.**

Goal: make every screen, animation and system of Baseball Draw feel finished and deliberate. No placeholder-looking
parts, no confusing moments, and a battle that feels great to play. Polish comes first, then a small amount of
well-chosen new content where it makes the game feel richer.

The update runs in five phases:

| Phase | What happens | Output |
|---|---|---|
| 0 | Measuring tools (capture, simulation, profiling) | Scripts that make the review repeatable |
| 1 | Full review | A scored issue list (`docs/plans/update5_review.md`) |
| 2 | Fixes and improvements, in parallel work streams | Commits per stream |
| 3 | New features (chosen list below) | Commits per feature |
| 4 | Verification, before/after comparison, build | Windows build, report, screenshots |

---

## Phase 0 — Tools for an honest review

So that "unappealing" is judged on real evidence and not guesswork:

1. **Screen atlas capture.** A script renders every screen and state at 1920×1080 and at 1280×720:
   * menus and their tabs, and popups;
   * every battle state (setup, wave, break, dugout, results, pause);
   * every arena, every boss, every card cast, every pack type opening;
   * the tutorial steps.

   That is roughly 120 images, combined into contact sheets per area.
2. **Animation strips.** Frame-by-frame captures (10–20 frames) of:
   * every defender clip (idle, run, throw, catch, celebrate, hit);
   * every runner type running, getting hit and getting out;
   * every card effect, card select/hover/deny, pack tear and card flip;
   * menu transitions.

   Problems like popping, foot sliding, clipping, stiff timing and effects that read poorly show up in strips.
3. **Balance simulator.** Headless autopilot runs: about 50 seeds × 4 difficulties × 3 modes, plus deck variants.
   It records:
   * win rate and the inning where runs are lost;
   * coins earned and spent, and energy left unused;
   * how often each card is played and how much it does;
   * defender outs and damage share, boss time-to-kill, and how often runs happen per runner type.

   Output is a CSV plus a summary report.
4. **Economy model.** A small script projects a player's progress over 20 hours from the reward data: packs per hour,
   when cards are complete, upgrade pacing, defender levels and rank pacing.
5. **Performance and stability.**
   * Frame-time capture of the heaviest moments: boss wave at 3x speed, Grand Slam Barrage, Champion ×10 opening.
   * Memory and leak checks: the test runs report leaked objects at exit today.
   * A **Windows smoke test in CI**: launch the exported .exe on GitHub's Windows runner, run a scripted game and
     check the log for errors. The .exe has never been run on Windows. If the runner cannot render 3D, at least
     startup, menus and saves are covered headless.
6. **Fresh-player walkthrough script.** Plays a brand-new profile from the first launch through the tutorial, the
   first pack and the first deck edit to the second game. It logs each moment the player could be confused:
   * a popup with no clear next step;
   * text that is too long;
   * a button whose result is unclear.

## Phase 1 — The review

Every screen and system is scored against the same checklist. Each finding gets **Severity** (1 cosmetic … 4 breaks
the experience), **Reach** (how often a player sees it) and **Effort** (S/M/L). Priority = Severity × Reach ÷ Effort.

**Checklist used for every screen:**
* **Clear purpose:** within two seconds, can a new player tell what this screen is for and what to do next?
* **Visual hierarchy:** one focal point; secondary info quieter; no big empty areas or cramped corners.
* **Consistency:**
  * the same button, panel, header, icon and number styles everywhere;
  * one type scale with a minimum readable size (16 px at 1080p);
  * one set of rarity and category colours.
* **Motion:**
  * everything that appears or changes animates in, quickly (0.12–0.3 s), with matching easing;
  * nothing pops;
  * there is feedback within 100 ms of every click.
* **Sound:** every interaction has a fitting sound, with consistent loudness.
* **Readability in battle:**
  * the player can always see runners, health bars, gates, home plate, energy and the hand;
  * effects never hide them for long.
* **Scaling:** correct at 1280×720, 1920×1080, 2560×1440 and ultrawide, and at UI scale 0.8–1.25.
* **Edge cases:** empty states (no packs, no cards ready), maxed states, very long names, a full collection.

**Areas reviewed:**
* Battle:
  * camera, HUD, hand, targeting, every card effect, hit and KO feedback;
  * defenders, runners and bosses (models and animation);
  * the stadium (crowd, props, lighting, sky), waves and breaks, the dugout, the results screen.
* Menus: main menu, Play, Cards & Deck, Upgrade Cards, Card Packs, Team, Progression (all tabs), Settings, Pause.
* Systems: balance, difficulty curve, economy, progression pacing, tutorial, saves.
* Audio: music, effects, mix.
* Technical: performance, loading, stability, Windows.

### Findings already noted (seed list for the review)

Collected while working on the last updates and from the current screenshots. The review confirms and ranks these
and adds whatever it finds.

**Battle look and feel**
1. **Crowd:** the stands are filled with blocky, cube-like fans, the least polished thing on screen and visible
   in every battle shot. Replace them with low-poly fans (heads, arms, team colours) using instanced meshes,
   animated by a vertex shader (cheer, wave, stand on big plays), with density following the quality preset.
2. **Dugouts and props:** both dugouts are plain grey boxes. They need:
   * benches, a roof and railings;
   * bench players and the team colours;
   * bat racks and a water cooler.
3. **Base Shield dome:** a permanent translucent dome sits over home plate and hides the most important spot on the
   field. Replace it with a low ring and shield-pip icons that flare only when a run is blocked.
4. **Big aura effects:** Rally Cry and Twin Play draw huge translucent domes and rings that wash over the field for
   seconds. Make them a short burst, then a subtle lingering ground ring.
5. **Field surface:** the checker mowing pattern looks flat and tiled. Needed:
   * grass texture variation and mowing stripes;
   * dirt and grass edge blending, chalk lines with wear;
   * footprints or clay scuffs on the base paths.
6. **Health bars of bunched runners overlap.** Stack-offset them slightly, or show only the nearest runner's
   bar with a count.
7. **Hit feedback:** needs short **hit-stop** (2–3 frames) and a camera punch on crits and kills, a better ball
   trail, and a catch flash.
8. **KO/"out" animation:** never caught clearly in captures. Verify it, then tune its timing and readability.
9. **Defender throws:** confirm the hand release lines up with the ball spawn on every throw clip, and add a
   follow-through and a glove pop on catches.
10. **Boss entrances:** bosses should get a short intro: camera move, name card, gate burst, crowd reaction.
    Boss defeats should get slow motion, a confetti burst and the crowd standing.
11. **Fizzle labels are tiny.** Make them readable while keeping them clearly secondary.
12. **Uniform layering:** the jersey/pants and sleeve layering was never fixed, and the sock fix was never
    confirmed on Rico. Check every defender in every clip and fix.

**HUD**
13. Empty hand slots (outline plus "NEXT CARD") are functional but plain. Add a card-back silhouette that fills as
    the draw timer runs, and a deal-in sweep when the card lands.
14. Achievement toasts land on top of the threat panel area. Give toasts their own spot, or queue them during
    waves.
15. Floating combo and play banners ("TWIN PLAY!", "GRAND SLAM COMBO X8!"):
    * cover the outfield at large sizes;
    * should be smaller, placed consistently and shown one at a time.
16. Top-left buttons (II, 1x, MAP, RANGES) look like debug buttons. Restyle them with icons and tooltips.
17. Setup-phase formation panel: small buttons and dense text. Restyle it as cards with formation diagrams.
18. Energy bar: make the cost of the hovered card visible on the bar (a preview of the energy it would spend).

**Menus**
19. **Main menu:** a long stack of identical bars with no emphasis. Make PLAY a hero button with the current
    mode or continue state, group the rest by purpose, and add icons. Give the 3D lineup a slow camera drift and
    an idle "showcase" (a random defender does a signature move).
20. **Play screen:** three flat columns with lots of empty space. Make modes into cards with art and mode details,
    stadium picker thumbnails rendered from each arena, and a difficulty explainer showing exactly what changes.
21. **Progression screen:** mostly empty, with a small rank ladder and a plain stats list. Needed:
    * a large rank emblem with a progress ring and the next reward;
    * a stats dashboard with icons;
    * an achievements grid with progress bars.
22. **Results screen:**
    * the left stats panel has unused space and the rewards look like a spreadsheet;
    * build up the rewards in sequence (coins count up, XP bar fills, rank points tick, packs fly in);
    * add a run-summary graph (runs allowed and energy over the innings).
23. **Dugout:** text is small on several tiles; check the 16 px minimum and add icons per upgrade.
24. A **shared design system pass** across all screens:
    * the same panel style, header style and button sizes;
    * the same back-button placement and the same transitions.
25. **Card text in the ×10 pack grid** is about 9–10 px at 1600×900. Show the full text on hover there.

**Systems and mechanics**
26. **Balance:** cards, defenders, runners and bosses have never been balanced by simulation. Use the Phase 0
    simulator to find dominant or useless cards, dead turns with energy capped, and difficulty spikes.
27. **Economy:** the 10-pack bundle and level-road rewards changed pack inflow. Re-tune pack and coin income so
    the collection completes at a satisfying pace (target set during review, e.g. common cards within 2–3 hours,
    all cards around 15–20 hours).
28. **Single-pack flow:** recheck it after the multi-open work.
29. **Endless mode scaling and modifiers:** check long runs for runaway difficulty or boredom.

**Audio**
30. Only one battle music track is shared by all six arenas. Add arena-flavoured variations and intensity
    layers (wave start, boss, last out), plus crowd reaction layers (cheer on outs, groan on runs, chant on combos).
31. Mix pass: consistent loudness across effects, ducking music during big moments, and no repeated-sound fatigue
    on rapid hits.

**Technical**
32. Objects and resources are reported as leaked at exit by the test runs.
33. Frame rates have never been measured on a real graphics card; set and check a budget (60 fps at High on a
    mid-range GPU).
34. Windows is still untested: covered by the Phase 0 smoke test, plus a request to the user to play one game.

## Phase 2 — Fix and improve (work streams)

Findings are grouped into streams that can run in parallel with helpers working in separate copies of the code,
like the previous updates. Each stream ends with its own tests and screenshots.

| Stream | Covers | Main files |
|---|---|---|
| A. Battle feel | hit-stop, camera punch, ball trails, catch/KO, aura and dome cleanups, fizzles, banners | `battle.gd`, `enemy.gd`, `projectiles.gd`, `vfx.gd`, `card_fx.gd`, `camera_rig.gd` |
| B. Stadium art | crowd rebuild, dugouts and props, field surface, lighting per arena | `stadium_builder.gd`, `assets/shaders/`, `tools/art/` |
| C. Characters | uniform layering, sock check, throw/catch timing, follow-through, celebrations | `tools/blender/characters/`, `character_model.gd`, `defender.gd` |
| D. HUD | hand slots, top buttons, formation panel, energy preview, toast and banner placement | `battle_hud.gd`, `card_view.gd` |
| E. Menus and design system | shared styles, then main menu, Play, Progression, Results, Dugout | `ui_theme.gd`, `src/ui/*` |
| F. Balance and economy | simulator-driven tuning of cards, runners, bosses, difficulty, rewards | `data/*.json`, `rewards.gd` |
| G. Audio | music variations and layers, crowd reactions, mix | `tools/audio/`, `audio.gd` |
| H. Tech | leaks, performance budget, Windows smoke test in CI | `.github/workflows/build.yml`, tests |

Order: H and F start first because they inform everything else. A, B, C, D and E then run in parallel, and G
fits in anywhere. Files shared between streams (e.g. `battle_hud.gd`) get one owner at a time to avoid conflicts.

## Phase 3 — New features (chosen to add depth without clutter)

1. **Boss entrances and finales:** intro camera, name card, unique music sting, slow-motion final out, crowd standing.
2. **Run-summary and highlights on Results:** a graph of the game plus the three best moments (biggest combo, best
   card play, MVP defender) shown as short captions with icons.
3. **Daily Challenge:** one seeded game per day with a fixed deck, a modifier and a best-score record. Gives a
   reason to come back. Offline, so no server is needed.
4. **Card mastery:** each card earns a small mastery star track from use. It unlocks a foil variant or card frame,
   with no power gain, which rewards playing different cards.
5. **Six new cards** filling gaps found by the balance review, one Legendary among them. Each gets art and a
   distinct effect in the current style. The exact cards are decided after the simulator shows which roles are thin.
6. **One new runner type and one elite modifier**, for more variety in the mid-game.
7. **Stadium life:**
   * a jumbotron replay of the last big play on the scoreboard;
   * a mascot on the field between waves;
   * fireworks on wins.
8. **Card collection book view:** set completion per category with a reward for completing a set.
9. **Quality-of-life:**
   * hold-to-preview a card's full text in battle;
   * a "play again with same settings" button;
   * a settings search;
   * a graphics benchmark button that picks a preset for the player's PC.

Features 3, 4 and 5 are the biggest; if the update needs trimming, they are the ones to cut or move to later.

## Phase 4 — Verification and delivery

* **All existing tests** pass, plus new ones:
  * boss intro;
  * daily challenge seeding;
  * mastery saving;
  * new cards in the system suite;
  * a full UI section for each redesigned screen.
* **The card-click test** (hit map plus fast play) must still pass, with zero dead points.
* **Before/after comparison:** the Phase 0 screen atlas is re-captured and shown side by side for every screen
  changed.
* **The balance simulator** is re-run, with target win rates (e.g. Rookie about 90 %, Standard about 65 %, Veteran
  about 40 %, Legend about 15 % for a sensible deck) and no card with a play share far outside the rest.
* **Performance:** the frame-time capture is re-run with no regressions, and the Windows smoke test passes in CI.
* **Delivery:**
  * one Windows build;
  * an updated README and development report;
  * the new screenshots;
  * a short "what changed" summary for the user.

## Things the user can decide (defaults in brackets)

* Whether to include the Phase 3 features 3–5, or keep this update purely to polish. [include 1, 2, 7, 9; 3–5 if time allows]
* Target difficulty feel. [the win rates above]
* Whether to play the Windows build once after Phase 2 and send feedback; nothing replaces a real PC test.
  [requested, optional]

## Size and pacing

This is the largest update so far, bigger than Updates 3 and 4 together. To keep it efficient:
* the review runs on scripts and captures, not by hand;
* streams run in parallel;
* each stream is checked once against the checklist, not reviewed repeatedly.

If it needs to be shorter, Phase 3 is trimmed first; the review and the polish streams are the core of the update.
