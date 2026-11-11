# Baseball Draw — Development Report

This report describes what was built, how it was verified, and what is known to be limited.
Everything below was produced in a Linux container with no GPU; see *Testing environment* for what
that means for the numbers.

## 1. Engine and architecture

* **Engine:** Godot 4.7.2 (Forward+ renderer). Godot was chosen for its native 3D pipeline, glTF import,
  skeletal animation, GDScript iteration speed and straightforward Windows export.
* **Code:** ~13,000 lines of GDScript in `src/`, organised by responsibility:

| Area | Files |
|---|---|
| Core game state | `src/core/run_state.gd`, `src/autoload/session.gd` |
| Static data / database | `data/*.json`, `src/autoload/db.gd` |
| 3D field and stadium | `src/battle/field.gd`, `field_builder.gd`, `stadium_builder.gd`, `assets/shaders/*.gdshader` |
| Characters | `src/characters/character_model.gd` (GLB wrapper, surface merging, overlays) |
| Defender behaviour | `src/battle/defender.gd` |
| Enemy AI and bosses | `src/battle/enemy.gd`, `route.gd` |
| Projectiles | `src/battle/projectiles.gd` (pooled balls + ribbon trails) |
| Cards | `src/battle/card_system.gd`, `card_effects.gd`, `effect_zone.gd`, `dirt_wall.gd`, `bunt_trap.gd` |
| Waves / innings | `src/core/wave_generator.gd`, `src/battle/battle.gd` |
| Progression | `src/autoload/profile.gd`, `src/core/rewards.gd` |
| User interface | `src/ui/*` (theme, HUD, menus, dugout, results, deck builder, roster, progression, settings) |
| Save management | `src/autoload/profile.gd` (atomic JSON + backup), `settings.gd`, `input_config.gd` |
| Audio | `src/autoload/audio_manager.gd` (buses, pooling, rate limiting, music cross-fades) |
| VFX | `src/vfx/vfx.gd` (shared GPU particle systems driven by `emit_particle`, pooled text) |

* **Data-driven:** cards, defenders, enemies, upgrades, formations, difficulties, modes, arenas/layouts,
  achievements, gear, uniforms, ranks and card combos are JSON in `data/`. Adding a card means a JSON entry,
  art, and (for a new mechanic) a branch in `card_effects.gd`.

## 2. Assets (all procedurally generated, sources in `tools/`)

| Asset set | Generator | Output |
|---|---|---|
| 20 rigged, animated characters (9 stylised defenders, 8 runners, 3 bosses) + portraits | `tools/blender/characters/` (Blender 5.2 `bpy`) | `assets/models/characters/*.glb`, `assets/textures/portraits/*.png` |
| 32 stadium props (walls, gates A–D, light towers, grandstands, scoreboard, dugout, banners, industry, skyline...) | `tools/blender/props/` | `assets/models/props/*.glb` |
| 73 sound effects (incl. pack shake/tear, card flip, rarity reveals), 7 music tracks, 2 ambience loops | `tools/audio/` (NumPy synthesis) | `assets/audio/` |
| 15 effect textures (glow, spark, smoke atlas, flame, scorch, crater, frost, runes, clock, web, chain...) | `tools/art/vfx/` (Pillow + NumPy) | `assets/textures/vfx/` |
| Logo, 26 card illustrations, 65 icons, rank emblems, rarity gems, UI backgrounds, app icon | `tools/art/` (Pillow + cairo) | `assets/textures/` |

Detailed asset reports (dimensions, triangle counts, animation timings, loudness) are in `docs/asset_reports/`.
Characters share one 22-bone armature and one animation set (idle, ready, run, sprint, walk, throw, pitch,
catch, special, hit, stunned, defeat, celebrate, victory, leap, swing, slam, taunt). At load time each
character's 13–17 material surfaces are merged into a single vertex-coloured surface (uniform colours baked in,
cached per model) so a character costs one draw call; translucent surfaces (the Phantom Captain's cape) keep their
own material as a second surface. Clips are baked at 60 Hz so the gameplay events tied to them (ball release,
catch, bat impact, slam impact) land on exact frames; looping clips have identical first and last keys.

## 3. Implemented features

* **Battle:** procedural field shader (mowing stripes, infield dirt, chalk, warning track, worn routes with
  animated direction chevrons, placement-zone overlay); route following with rounded corners; defender
  targeting priorities (first/last/strongest/weakest/fastest/closest); throws released on the animation's
  release frame; accuracy vs evasion misses; crits; class traits (Fastball, Home Guard aura, Quick Hands +
  dash-tag, Cannon Arm pierce/knockback, Precision, Heavy Hitter splash/stun, Static Charge chain, Pickoff
  Artist, Gap Shooter); stuns from sluggers/bosses; zone bonuses; synergies; captain aura.
* **Runners:** slow/root/stun/freeze/confuse/knockback/burn/mark/chill/armor-break/magnet statuses;
  sprint bursts, leaps (ignore ground effects), trickster blinks and decoys, captain auras, slugger swings
  that stun defenders and smash walls; elite affixes on higher difficulties.
* **Bosses:** Iron Slugger (armour cracks after telegraphed ground slams), Phantom Captain (phases out,
  conjures decoys, aura), Grand Slammer (telegraphed home-run swings at defenders, summons reinforcements at
  66%/33%), each with a camera intro, boss bar and music change.
* **Cards:** all 26 cards implemented with distinct mechanics, energy costs, cooldowns, levels, linked-defender
  casting and combos. Targeting previews: area circle, Heat Wave line, runner/defender highlight, route snap.
* **Rules:** an out per runner stopped; runs when runners reach home (2–3 for captains, sluggers, bosses);
  run limit per difficulty (3 on Standard); Base Shields stop one run each; Double/Triple Play and Grand Slam
  combos; innings of 3 waves; early-call bonus; inning bonuses and clean-inning bonus.
* **Dugout** between innings with performance, next-inning scouting, team stats, six core upgrades plus two
  randomised specials (incl. defender-specific Hot Streak and the New Pitch Card choice).
* **Modes:** Standard Siege, Quick Defense, The Endless Ninth (random modifiers, boss every 3rd inning,
  milestones), Practice Field (spawn any runner, any card, swap in any defender, infinite energy) and
  Promotion Challenges for the ranked ladder.
* **Progression:** account XP/levels, defender XP/levels with training traits at levels 3/6/9, gear shop,
  uniforms bought with stars, card packs and card upgrades with copies + coins, 28 achievements, six stadiums
  with unlock conditions, records, match history, eight rank divisions.
* **Menus:** live 3D main menu (team lineup, playing catch, cinematic camera, profile panel), Play menu,
  Deck Builder / Collection (search, rarity/category filters, sort, compare, upgrade, synergies, Save / Auto
  Build / Clear / Test Deck), Roster with a 3D showcase stage, Progression, Settings, pause menu, results.
* **Saves:** atomic writes (temp file + rename), rolling backup, automatic restore of a corrupt save (the bad
  file is kept as `profile.corrupt.json`), schema merge for missing keys, sanitising of unknown ids; runs
  autosave at every inning boundary.

## 4. Verification

| Check | How | Result |
|---|---|---|
| Every script parses and compiles with autoloads | `tools/check_scripts.sh` | 49 scripts, 0 failures |
| System tests | `tests/test_suite.tscn` | 922 checks, 0 failures |
| Interactive flows through simulated mouse/keyboard | `tests/ui_flow_test.gd` (incl. pack opening and the guided first game) | 73 checks, 0 failures |
| Full runs, all modes | autopilot (`--auto`), `tools/simulate.sh` | Standard, Quick, Endless, Practice completed; wins and losses both reached |
| Packaged build | Linux export of the same pack as Windows, autopilot game | Quick Defense won from the exported binary (3 innings, 0 runs, Iron Slugger beaten) |
| Windows export | `--export-release "Windows Desktop"` | `BaseballDraw.exe` (109 MB) + `BaseballDraw.pck` (43 MB) produced |
| Clean-machine build | GitHub Actions *Build Baseball Draw*: fresh import, script check, system suite, autopilot game, Windows + Linux export | Passing; builds downloadable as run artifacts |
| Final art in engine | `tools/capture_screenshots.sh` (15 scenes rendered by the game itself) | See section 7 |

The system suite covers data integrity (art for every card, signatures, layouts ending at home plate...),
save/load round trips, corrupt-save recovery, profile repair, card upgrades, gear and traits affecting stats,
level-based unlocks, achievements (awarded once), run-state JSON round trips including RNG state, wave
determinism and scaling, boss scheduling, rewards and promotion, placement rules, zone bonuses, synergies,
defenders damaging runners, Base Shields, and an execution check of every one of the 26 cards.

The UI flow test drags a defender, applies a formation, uses Tab/Space/1-5/right-click/Esc/Shift/A/M, casts a
card by clicking the field, finishes an inning, buys a dugout upgrade, starts the next inning, quits to the
menu, continues the saved run (inning, formation and positions restored) and opens and backs out of every
main-menu destination.

### Balance simulations (autopilot, fresh level-1 profile)

Balance was iterated in several rounds of simulated games. The first build was far too easy (both bots
won Standard Siege without allowing a run), so shields were changed to stop one run each, coin income
was cut, enemy scaling steepened, energy slowed, and bosses tuned individually. Final numbers:

| Mode / difficulty | Card-playing bot | No-cards bot |
|---|---|---|
| Standard Siege / Rookie | Won, 0 runs allowed | Won, 1 run allowed |
| Standard Siege / Standard | 1 win (all three bosses beaten), 1 loss in the 9th | Lost in the 9th |
| Standard Siege / Veteran | Lost in the 9th | — |
| Standard Siege / Legend | Lost in the 8th | — |
| Quick Defense / Standard | Won (easy by design: a three-inning build-testing mode) | Won |
| The Endless Ninth / Standard | Reached inning 13 | — |

The bot plays cards at sensible but unfocused targets (it does not save Time Out or Power Catch for bosses),
so a human player should do better. Permanent progression (defender levels, gear, card levels) makes later
runs easier, as intended.

## 5. Performance

Measured with `tests/perf_test.gd` (Practice Field stress test):

* **CPU (headless, no rendering):** ~7 ms average frame time with ~70 runners, six defenders, projectiles and
  five simultaneous area abilities; the battle logic itself costs ~2 ms of that.
* **Rendering load (1920×1080):** empty stadium ~830 draw calls / 0.5 M triangles; with 150 runners on the field
  ~1,470 draw calls / 1.9 M triangles (down from ~5,460 before character surface merging).
* GPU frame times could not be measured: the container has no GPU and renders with the Mesa lavapipe software
  rasteriser (~1–3 s per frame), which says nothing about real hardware. The draw-call and triangle counts are
  well within what a mid-range desktop GPU renders at 60 FPS at 1080p, and the Low/Medium presets cut
  shadows, SSAO, fog, particles, crowd density and render scale (FSR) further.

## 6. Known limitations

* No GPU was available, so real-hardware frame rates are estimated from draw calls, triangle counts and CPU
  timings rather than measured. The Windows `.exe` was exported but could not be launched here (no Windows);
  the identical game pack was run successfully through the Linux export.
* Characters are procedural sculpts with flat-coloured materials (no texture maps); faces are modelled
  geometry. Animations are keyframed procedurally; they read well at gameplay distance but are not motion-capture
  quality. There are no finger or face bones (fixed hand poses, no blinking) and no corrective shapes, so the crotch
  and shoulders stretch a little in wide stances and with the arm fully raised. Capes, hoods, scarves and the
  ponytail follow the spine rather than simulating cloth; at the end of `defeat` the bosses' capes dip into the
  ground, and shoe tips can dip 2–5 cm below the ground on single frames.
* Music and sound effects are synthesised; instruments and crowd voices are stylised approximations.
* The `.exe` does not embed the custom icon (that needs `rcedit` on the build machine); the window icon is set
  at runtime.
* Balance was tuned with a bot; it should be refined with human playtesting.

## 7. Screenshots

Rendered by the game itself with `tools/capture_screenshots.sh` (Godot under a virtual display, software
Vulkan, 1600×900, High preset). Gameplay shots come from autopilot games.

| | |
|---|---|
| ![Main menu](screenshots/main_menu.jpg) Main menu with the live 3D lineup | ![Battle](screenshots/battle.jpg) Quick Defense, inning 1 |
| ![Action](screenshots/action.jpg) Mid-game, inning 4 | ![Boss](screenshots/boss.jpg) Grand Slammer, inning 9 |
| ![Setup](screenshots/setup.jpg) Setup phase: zones, routes, formation panel | ![Tutorial](screenshots/tutorial.jpg) Guided first game |
| ![Dugout](screenshots/dugout.jpg) Between-innings dugout | ![Results](screenshots/results.jpg) Results screen |
| ![Play menu](screenshots/play_menu.jpg) Play menu | ![Deck builder](screenshots/deck_builder.jpg) Deck builder |
| ![Roster](screenshots/roster.jpg) Roster with 3D showcase | ![Progression](screenshots/progression.jpg) Progression |
| ![Neon Diamond](screenshots/arena_neon_diamond.jpg) Neon Diamond | ![Frostpark](screenshots/arena_frostpark.jpg) Frostpark |
| ![Champion's Citadel](screenshots/arena_champions_citadel.jpg) Champion's Citadel | ![Pack](screenshots/packs.jpg) Opening a Champion Pack |
| ![Pack reveal](screenshots/packs_reveal.jpg) Pack reveal | ![Heat Wave](screenshots/vfx_heat_wave.jpg) Heat Wave |
| ![Grand Slam Barrage](screenshots/vfx_grand_slam_barrage.jpg) Grand Slam Barrage | ![Thunderbolt](screenshots/vfx_thunderbolt.jpg) Thunderbolt |
| ![Frost Field](screenshots/vfx_frost_field.jpg) Frost Field | ![Lockdown](screenshots/vfx_lockdown.jpg) Lockdown |
| ![Base Shield](screenshots/vfx_base_shield.jpg) Base Shield | ![Upgrade Cards](screenshots/card_upgrades.jpg) Upgrade Cards |
| ![Signature pack](screenshots/packs_signature.jpg) Signature pack opening | |

## 8. Update 2: team models, card effects, packs, tutorial, cleaner HUD

* **Defender models rebuilt** (`tools/blender/characters/hero*.py`). The nine team characters no longer use the
  SDF sculpt pipeline (lumpy, faceted surfaces, small heads). They are smooth lofted and subdivided meshes with
  stylised hero proportions (head ≈ 1/5.4 of height, broad shoulders, chunky hands and cleats), large readable
  eyes, eyebrows and mouths per personality, and a distinct silhouette for each defender (flame cap, catcher
  gear, ponytail, backwards cap and beard, wraparound shades, headband and beard, pixie cut, curls, sun visor).
  Uniform details (piping, numbers with outline, cap emblem, belt, striped socks, laced cleats and glove) are
  modelled. Same rig, clips, lengths and event times; foot slide and loop seams stay at 0. In battle the
  defenders get a soft rim light and are drawn 12 % larger than runners. Portraits re-rendered.
* **Card ability effects rebuilt** (`src/vfx/vfx.gd`, `src/vfx/card_fx.gd`, `assets/shaders/vfx/`): every card has
  its own wind-up, impact and lingering effect using pooled meshes, effect shaders (flame sheets, heat haze,
  branching lightning, frost decals, rune seals, hex dome, cages) and generated textures, with at most three
  flash lights at once and particle counts scaled by the quality preset. Runner status effects (rooted,
  slowed, chilled, frozen, burning, stunned, marked...) are now visible on the runner. Gameplay values
  and timings are unchanged.
* **Card packs** (`data/packs.json`, `src/ui/packs_screen.gd`, `src/ui/pack_art.gd`): cards are collected only
  from packs. Rookie (3 cards, Uncommon+ slot), Pro (4, Rare+ slot), Champion (5, Epic+ slot, bought with stars)
  and Signature packs (a new defender's card). Packs come from every finished game (more for wins), every
  account level (a Pro pack every fifth), new defenders and the shop. Unopened packs are saved in the profile.
  The opening is a 3D sequence: the foil pack (its artwork drawn live into a viewport) charges up and shakes,
  the top tears off in a burst coloured by the best card inside, the cards rise and fan out face down
  with rarity auras, and flip on click. Epic and Legendary cards tremble first and land with light rays,
  a ring, camera shake, a banner and, for Legendary, a flash and confetti. Each card shows NEW, +copies or
  UPGRADE READY. Pulled cards carry a NEW badge in Cards & Deck until viewed.
* **Card redesign** (`src/ui/card_view.gd`, `assets/shaders/card_foil.gdshader`): metallic rarity frames,
  category banner, glossy energy gem, type line with category and rarity, corner ornaments on Epic and Legendary,
  rarity gem and level pips on the frame, an animated foil sweep on Rare+ and a holographic edge on
  Epic and Legendary, plus a card back for reveals.
* **Guided first game** (`src/ui/battle_tutorial.gd`): pop-ups with an arrow and highlight walk through the
  gates and paths, outs and runs, the defenders, dragging a defender (waits for the player to do it),
  formations, PLAY BALL (waits), the first runners (pauses), playing a card (waits) and energy, then one-off
  tips for the first run scored, wave break, dugout, boss and results. It can be skipped, and the rules
  are also available from HOW TO PLAY in the pause menu.
* **Less clutter in battle**:
  * Compact top-left buttons and a slimmer scoreboard without the running score.
  * Only active synergies are listed, and the duplicate scouting panel is gone (the threat panel already shows
    the next wave).
  * Hint text appears only in setup or while aiming, and the minimap is smaller.
  * No per-runner OUT! or coin popups; damage numbers only for crits and big hits; no burn-tick numbers.
  * Shorter, smaller banners, and no screen-centre banner on every card cast.

## 9. Update 3: clearer cards, field view, dugout, packs, deck screens, levelling

* **Short card text** (`data/cards.json`): every card has a one-line rule ("Hit one runner for 160 and knock it
  back."). The old long text is kept as `details` and shown in the deck inspector and upgrade screen.
* **Card art redrawn** (`tools/art/cards_v2.py`): 26 new illustrations with one bold subject, a strong
  silhouette and a rarity-tinted backdrop. Cards draw the art with a centred crop instead of stretching it.
* **Rarity is easier to read** (`src/ui/card_view.gd`): Uncommon and better cards have an outer glow in their
  rarity colour, the rarity tag is a filled pill and the rarity gem grows with rarity.
* **Hand feel** (`src/ui/card_view.gd`, `src/ui/battle_hud.gd`, `src/battle/battle.gd`):
  * Hover and selection ease in and out; the selected card rises, grows and pulses.
  * The click area follows the raised card, the hand is larger (146 × 204), and hover survives hand rebuilds,
    so a card under the cursor is always the one that reacts.
  * Clicking a selected card again only casts cards that need no target; aimed cards are deselected instead.
    A hotkey pressed twice casts at the cursor only when the cursor is over the field.
  * A card that cannot be played shakes, flashes red and shows why ("Need 2 more energy", "Ready in 3s",
    "Click a runner").
  * Every cast flies a glow from the card to the target and bursts there, so each card visibly does
    something even when its effect is quiet.
* **Foil fix** (`assets/shaders/card_foil.gdshader`): Epic and Legendary cards were washed in rainbow colours and
  their light sweep jumped around while hovering. The foil now uses the card's own coordinates (the card is
  drawn around its bottom centre since the hover animation was added) and the sweep keeps one speed.
* **Field view** (`src/battle/camera_rig.gd`, `src/ui/battle_hud.gd`): the default camera shows all three gates,
  including the middle one, and home plate above the hand. The scoreboard moved to a compact top-right panel.
* **Hits are easy to see** (`src/battle/enemy.gd`, `src/battle/projectiles.gd`, `src/vfx/vfx.gd`,
  `assets/shaders/rim_overlay.gdshader`): a hit flashes the runner white-hot, squashes and pushes it away from
  the throw, shows a comic starburst with a shock ring and sparks, and the ball deflects off (or whiffs past on
  a miss). Crits and big hits add a gold flare. A runner that is out gets a bigger burst and ground shockwave,
  is knocked back, falls and shrinks away. Defenders hit by sluggers and bosses flinch and flash.
* **Health bars** (`assets/shaders/billboard_bar.gdshader`): thicker, outlined, coloured by health
  (green → yellow → red, or the colour-blind palette), with a white chip that drains after each hit. They draw on
  top of models and the crowd and stay within a fixed on-screen size range, so they are readable from
  far away and don't swamp the runners up close. Elites and the captain
  get a larger gold-trimmed bar; bosses a large bar with ticks.
* **Every card shows something** (`src/battle/card_effects.gd`, `src/vfx/card_fx.gd`): cards cast with no valid
  target still throw or strike and show a small fizzle ("NO TARGET", "NO RUNNERS", "NO EFFECT", "IMMUNE",
  "SHIELDS FULL"), Changeup and Seventh-Inning Stretch got clearer effects, and every cast pops a coloured ring
  at the casting defender's feet.
* **Dugout** (`src/ui/dugout_screen.gd`, `data/upgrades.json`, `src/core/run_state.gd`): upgrades are cards with
  level pips, a NOW → NEXT line in plain words ("Team damage +10 % → +20 %") and one buy button
  ("BUY 80", "NEED 30 MORE", "MAXED"). Effects are round steps (+10 %, +5 %, 0.1 s) and prices are rounded
  (to 10 below 100, 25 below 500, 50 above). Specials are a separate row at 20 % off. Buying pops the card.
* **Packs** (`tools/art/packs.py`, `src/ui/packs_screen.gd`): each pack type has its own painted front and back.
  The opening grows with the pack: Rookie is a short charge and tear; Pro adds a dimmed stage, light rays and a
  ground pulse; Champion adds crackling arcs, a particle spiral, stronger shake and confetti; Signature
  shows the defender in the pack medallion and opens with a gold spiral.
* **Cards & Deck and Upgrade Cards** (`src/ui/deck_builder.gd`, `src/ui/card_upgrades_screen.gd`):
  * The deck screen has the 8 deck slots on top (the next free slot glows, with "Add 2 more cards" or
    "Ready to play!"), the collection below with category tabs, rarity chips, search and sort, and a large
    card inspector on the right.
  * Click a card to fly it into the deck, click a deck card to remove it, or drag cards to place, swap and
    reorder them. The deck saves itself when all 8 slots are full.
  * Cards you don't own yet are in their own "Find these in card packs" section.
  * Upgrading is a separate screen (main menu → UPGRADE CARDS, with the number of cards ready). It lists
    every card with its copies and coin cost, shows what gets better at the next level ("Damage 90 ▶ 101"),
    and upgrades with one button and a level-up animation.
* **Defender levelling** (`data/defenders.json`, `src/autoload/profile.gd`, `src/core/rewards.gd`,
  `src/ui/results_screen.gd`, `src/ui/roster_screen.gd`):
  * Every level from 2 to 10 gives something: coins, a new trait choice (levels 3, 6, 9) or a pack (Rookie at 4,
    Pro at 7, Champion at 10).
  * Defender XP now also counts outs made, and the game's MVP earns 50 % more.
  * The results screen fills each defender's XP bar, with a LEVEL UP! burst and the reward.
  * The Team screen shows a level badge, the XP bar with what is left to the next level, a 10-step level road
    with the reward icons, the next reward, and a ★ NEW TRAIT marker when a trait is waiting.
* **Sock fix** (`tools/blender/characters/hero_body.py`, `hero.py`): the sock top sits lower and narrower under
  the trouser cuff and shares the leg's skin weights, so it no longer pokes through the trousers when the
  defenders run. All nine models were rebuilt.

Verification for this update: `tools/check_scripts.sh` (54 scripts, 0 failed), the system test suite
(928 checks, 0 failed, including the new level-road checks) and the full UI flow test (90 checks, 0 failed),
which plays the guided first game, card selection and casting, the dugout, pack opening and the new deck screen.

Known limitations of this update:
* Frame rates were measured only on the software renderer. The new hit effects use the existing pools and
  add no lights, and the per-frame battle cost stayed close to before.
* The sock fix was checked on renders of the running and fielding poses. On Rico the result was hard to confirm
  from the renders. Jersey/trouser and sleeve layering were not changed.
* When runners bunch tightly, their health bars overlap (the nearest is drawn on top).
* The Windows executable is built by CI but was not run on Windows here.

## 10. Update 4: reliable card clicks, 10-pack bundles, multi-open

* **Dead click zones on the hand fixed.** A new UI test (`--ui-test-section=cards`) moves the mouse over a
  5 × 7 grid on every card in the hand and checks which control would receive a click. It found two culprits:
  * The scene-transition layer (`src/autoload/router.gd`, drawn above every screen) left its 600 × 80
    loading-text box in place, invisible, at the bottom centre of the screen. It took the clicks on the middle
    and lower part of the hand cards, and on anything else in that spot on other screens. About a third of
    each card did not respond. It now ignores the mouse.
  * The energy row under the cards could take clicks on their bottom edge; it now ignores the mouse.
  After the fix, all 175 sampled points respond.
* **Fixed card slots** (`src/battle/card_system.gd`, `src/ui/battle_hud.gd`): the hand used to be rebuilt from scratch
  after every play and every draw, and it re-centred, so all cards slid sideways by half a card under the
  cursor. Now the hand has five fixed slots. A played card leaves an empty slot showing a NEXT CARD timer,
  and the next draw fills it. Cards that stay are never recreated, so their hover and selection state
  survives, and a new card pops into its slot without moving the others. Keys 1–5 always match the slots.
* **Exact click area** (`src/ui/card_view.gd`): the area that reacts is exactly the drawn card (raised and enlarged
  while hovered or selected) plus its resting slot. The card cannot slip out from under the cursor as it rises.
* **Forgiving runner targeting** (`src/battle/battle.gd`): while a card that targets a runner is selected, the
  nearest runner within 95 px of the cursor counts (50 px otherwise). The target is read again at the moment of
  the click, not from the previous frame, so a runner moving past the cursor is still hit.
* The fast-play part of the test clicks a card, clicks the field, then immediately clicks the next card,
  twelve times, with new cards landing in the slots meanwhile. All twelve clicks register and all twelve
  cards are cast.
* **BUY 10** (`src/autoload/profile.gd`, `src/ui/packs_screen.gd`): every pack in the shop has BUY and BUY 10.
  Bundles are 10 % off, rounded like other prices: Rookie 1,350 coins, Pro 3,600 coins, Champion 325 stars.
  The line under the buttons shows the saving or how much is missing. Buying plays a sound, shows a toast and
  highlights the pack in YOUR PACKS.
* **OPEN ×5 / OPEN ×10**: these appear beside OPEN PACK when you own at least 5 or 10 of the selected pack.
  * One opening plays for all of them. The extra packs fan out behind the front pack and fly into it during the
    charge-up, and it tears with a bigger burst.
  * Every pack is rolled with the same odds and guarantees as a single open.
  * The results grid (`src/ui/pack_summary.gd`) deals the cards face down, best rarity first.
    * Duplicates stack with a ×N badge. Each card is tagged NEW!, UPGRADE READY or +N copies, and the
      header counts each rarity.
    * REVEAL ALL flips the cards in a cascade from commons up, so the best land last. Epic and Legendary
      cards get the same celebration as a single open.
    * SKIP, clicking single cards, and DONE work as on a single open.
* Single opens now wait until every card has actually turned (an Epic or Legendary trembles first) before
  offering DONE or the next pack.

| | |
|---|---|
| ![Pack shop](screenshots/packs_shop.jpg) BUY 10 and OPEN ×5 / ×10 | ![Multi-open](screenshots/packs_multi.jpg) Ten Champion packs at once |

## 11. Update 5: "Championship Polish"

Plan: `docs/plans/UPDATE_5_PLAN.md`. Scored review findings for each area are in `docs/plans/review/`
(`battle_feel.md`, `stadium.md`, `menus.md`, `audio.md`, `characters.md`). The work ran as parallel streams
(tech and balance, stadium, battle feel, HUD, menus, audio, characters, new content).

**Measuring tools**
* **Balance simulator** (`tools/balance/simulate.py`): headless autopilot games; reports win rates, where runs
  are lost, card play share and impact, defender share and boss time-to-kill.
* **Economy model** (`tools/balance/economy.py`): projects 20 hours of play.
* **Smoke test** (`--smoke-test`, `src/core/smoke_test.gd`): plays a short game and saves/reloads a profile.
  CI runs it on the Linux export and, in a new job, on the Windows .exe on a Windows runner.
* **Frame-time capture:** `--perf` and `--perf-test`.
* **Card hit-map test:** `--ui-test-section=cards`.
* **Character layer check:** `tools/blender/characters/check_layers.py`.

**Battle feel** (`battle.gd`, `enemy.gd`, `projectiles.gd`, `camera_rig.gd`, `src/vfx/`)
* **Base Shield:** the permanent dome over home plate is replaced by a thin ring and shield icons; the dome
  flashes only when a shield blocks a run.
* **Rally Cry and Twin Play:** a short burst, then a subtle ground ring.
* **Hits:**
  * a model-only hit-stop on crits and outs (the game clock is untouched);
  * a camera punch on crits, outs and boss kills;
  * frame-rate-independent ball trails;
  * a glove pop on tags and an arm swoosh on throws.
* **Health bars:** bars of bunched runners stack into rows.
* **Fizzle labels:** readable size.
* **Bosses:**
  * Entrance: camera to the gate, gate burst, name card with the boss's threat. Under 3 s, skippable,
    never during the tutorial or auto tests.
  * Defeat: a short slow motion, a big burst, then the DEFEATED banner.
  * New Battle signals: `boss_intro_started`, `boss_intro_finished`, `boss_defeated`.

**Battle HUD** (`battle_hud.gd`)
* Icon toolbar with hotkey tooltips.
* Formation presets as mini diamond diagrams.
* Call-out banners are smaller, queued and merged (a growing combo updates in place).
* The energy bar previews the cost of the hovered or selected card, and outlines missing energy in red.
* The next-card slot is a card back that fills with a seconds countdown.
* Card tooltips include the full rules text.
* The card hit map still shows 0 dead points and 0 dropped fast clicks.

**Stadium** (`src/stadium/`, `stadium_builder.gd`, `field_builder.gd`, crowd and field shaders)
* **Crowd:**
  * low-poly fans in one MultiMesh per grandstand, animated in a vertex shader;
  * they clap, cheer, groan, stand and do the wave in reaction to the game;
  * density follows the quality preset.
* **Dugouts and park:** real dugouts with bench players.
* **Field surface:** mowing stripes, worn turf, rake marks and base-path scuffs, worn chalk, grass foul
  territory, sponsor boards and foul poles.
* **Lighting:** night light-tower glow; Frostpark no longer washed out.
* **Stadium life:**
  * a jumbotron with a live picture-in-picture of big moments (an animated graphic on Low);
  * the mascot "Slugger" between waves;
  * fireworks on wins and boss defeats.

**Menus and design system** (`ui_theme.gd`, `src/ui/`)
* **Shared design system:**
  * a type scale with a 16 px minimum;
  * button variants;
  * one panel, tile and section style;
  * one back-button position and currency pill;
  * hover and press feedback;
  * a shared screen-enter animation.
* **Main menu:** a hero PLAY button, a Continue Run strip, grouped icon tiles with badges, and a drifting
  camera with a defender showcase.
* **Play:** mode cards, rendered stadium pictures, and a difficulty explainer listing exactly what changes.
* **Progression:** rank emblem with a progress ring, a stats dashboard, and achievement progress.
* **Results:**
  * staged reward build-up;
  * a game-flow graph;
  * three highlights (biggest combo, best card play, MVP);
  * PLAY AGAIN with the same settings.
* **Settings:** search, one-line explanations, and a graphics benchmark that recommends a preset.
* **Dugout, pause and Team:** restyled to match.

**Audio** (`tools/audio/`, `src/audio/`, `audio_manager.gd`)
* Each arena has its own take on the battle theme, with four synced layers: calm, wave, boss and tense.
* Boss intro and defeat stings.
* Crowd reactions scaled by excitement.
* Mix targets per category, music ducking, and variation and voice limits for frequent sounds.
* New sounds for card draw, full energy and fireworks.

**Characters** (`tools/blender/characters/`)
* Clothing layers share skin weights, so undershirts, jerseys and pants no longer poke through at the sleeves,
  waist or elbows.
* The broken back-number outlines are fixed.
* Throw, catch, celebrate and idle clips are reworked with the same lengths and event frames.
* Rico's socks are confirmed fixed.

**New content**
* **Six cards (32 in total):**
  * Called Shot (Rare): the boss counter;
  * Line Drive (Common): area damage;
  * Tag at the Plate (Common): a cheap run-stopper;
  * Bullpen Call (Uncommon): draw and energy;
  * Hot Corner (Uncommon): a defender buff that pierces armor;
  * Perfect Game (Legendary).
* **Base Stealer runner:** sprints when no defender is aiming at it; a slow, stun or freeze mid-steal
  catches it.
* **Shielded elite:** blocks the first hit.
* **Daily Challenge** (`src/core/daily_challenge.gd`, `data/daily.json`): one seeded game per day, with a best
  score, a day streak and a first-game/first-win bonus. It never touches the Continue Run slot.
* **Card mastery** (cosmetic): stars at 10 / 40 / 120 plays and a gold MASTERED frame.
* **Collection sets:** a Pro Pack per completed category and a Champion Pack for the full collection.

**Balance and economy**
* **Economy:** re-tuned so the collection lasts. The model projects about 10 earned packs per hour and the
  full collection at about 19 hours (it was about 1 hour).
  * Pack prices: Rookie 200, Pro 500, Champion 50 stars; bundles 1,800 / 4,500 / 450.
  * Fewer free packs per game, and rarer Epic and Legendary odds.
  * Defenders reach level 10 at about 7 hours.
* **Waves:** the simulator showed that the defenders alone stopped every regular runner, even with no cards
  played, so only bosses ever scored. Regular runners now scale up faster per inning, and Standard, Veteran
  and Legend have tougher, bigger waves. On Quick Defense, Standard, the autopilot now wins about 1 game in
  4 with no cards and about 3 in 4 with cards, so cards decide games.
* **Other:** Heat Wave and Rico buffed.

**Tech**
* Leaks at exit cut from 84 to about 22 objects; an orphan HUD label is now freed.
* Per-frame battle-loop cost is about 1 ms (CPU) in a boss wave at 3x speed.

**Verification**
* Script check: 76 scripts, 0 failed.
* System test suite: 1,261–1,283 checks (a few battle checks depend on the run), 0 failed.
* Full UI flow test on the merged game: 127 checks, 0 failed. It covers battle, tutorial, dugout, packs, bundles
  and multi-open, Cards & Deck, Upgrade Cards and the Daily Challenge.
* Card hit map: 0 of 175 dead points, 0 dropped fast clicks.
* Autopilot balance after the final tuning (small samples):

  | Mode | Difficulty | Result |
  |---|---|---|
  | Quick Defense | Rookie | 3 of 3 |
  | Quick Defense | Standard | 2–3 of 4 with cards, about 1 of 4 without cards |
  | Quick Defense | Veteran | 2 of 3 |
  | Standard Siege | Standard | 0 of 2 (one reached the final boss in inning 9) |

  The autopilot spams cards and never saves them for bosses, so human results should be better. Standard
  Siege may still be on the hard side; the multipliers are in `data/difficulties.json`.
* Before/after comparison: `docs/screenshots/update5_before_after.jpg`.

**Known limitations**
* Frame rates were not measured on a real GPU. The crowd (about 0.43 M triangles on High) and the live jumbotron
  feed are the new costs; both scale with the quality preset.
* The graphics benchmark could not be checked for real numbers here.
* Audio was checked by measurement, not by listening.
* The Windows smoke test runs in CI on the first `[build]` after this update; it has not run before.

## 12. Update 6: "Clubhouse"

Plan: `docs/plans/UPDATE_6_PLAN.md`. Scored reviews: `docs/plans/review/runners.md`, `card_fx.md`, `navigation.md`.

**Runner and boss models** (`tools/blender/characters/enemies.py`, `roster.py`, `anim.py`)
* **Rebuilt in the defenders' style:** all 9 runner types and the 3 bosses, previously sculpted with the
  original SDF pipeline.
* **Look:** faces with expressions, and one opponent kit (the "Wreckers"). The type colour is on the helmet,
  piping, socks and number, and each type has its own silhouette:
  * Armored: plates and a face cage;
  * Sprinter: lean, with shades and spikes;
  * Jumper: springs on the shins;
  * Swarmer: tiny, with a big head;
  * Trickster: mask and stocking cap;
  * Captain: cape and epaulettes;
  * Siege Slugger: spiked bat;
  * Base Stealer: its own model.
* **Bosses:** Iron Slugger with glowing seams, a translucent Phantom Captain, and a 4.2 m golden
  Grand Slammer.
* **Animation:** a run style per type, a stronger hit flinch and a clearer swing wind-up. Same rig, clips and
  event times; foot slide and loop seams stay 0.
* **Portraits:** re-rendered.
* **Triangle budget:** Swarmer 6.7k, other runners 11–15k, bosses 22–27k.

**Card effects** (`src/vfx/`, `battle_hud.gd` flourish)
* All 32 cards were captured and scored for readability, satisfaction and uniqueness.
* **Reworked:**
  * Hot Corner: eruption, burning ring, a torch in the throwing hand, fire flares on its throws;
  * Bullpen Call and Seventh-Inning Stretch: the drawn cards fly from the mound to the hand;
  * Knuckleball, Pickoff, Power Catch and Bunt Trap;
  * Changeup: slow lavender pulses with after-images, no longer Time Out's clock;
  * Field Vision: a cyan radar look, no longer the same gold ring as Rally Cry;
  * the Shielded elite: a round, glossy bubble.
* **Cast flourish:** the card lifts with a category-colour halo, flies on a curve with a trail and bursts at
  the target in about 0.4 s.
* **Refused card:** a red rim.

**Progression** (`src/core/missions.gd`, `level_road.gd`, `data/missions.json`, `data/account_levels.json`)
* **Missions:** 3 daily missions and 1 weekly from a pool, with one free reroll per day. They are claimed in the
  new Progression → Missions tab, and there is a main-menu widget and a Results strip.
* **Learn the ropes:** a starter chain for new players.
* **Account level road:** visible on Progression; Results shows "LEVEL UP — reward".
* **Achievements:** 13 new ones, 41 in total.
* **First hour:** a first-win Pro Pack and early levels that pay packs. Six games now give about 30 packs
  (was about 21).
* **Economy model:** now includes the Daily Challenge and missions. The whole collection is about 24 h
  (Update 5 measured about 37 h with the corrected model).
* **Endless:** starts at effective inning 2.5, and an elite mini-boss closes every inning without a boss.
* **Difficulty:** per-mode tuning. Autopilot, 8 games per row:
  * Quick Defense Standard: 75 %;
  * Standard Siege Standard: 6 of 8;
  * Standard Siege Veteran: about 30 % (target 40 %).

**Navigation and clarity** (`src/ui/hints.gd`, `next_steps.gd`, `router.gd`, `menu_screen.gd`)
* **First-visit hint cards:**
  * one at a time, with an arrow and a highlight on the element they explain;
  * a "?" button on every screen replays them;
  * Settings has "Show tips" and "Show all tips again";
  * never during the tutorial or the first game.
* **Esc and BACK work everywhere:**
  * Results and Dugout now respond to Esc, with Save & Quit from the dugout;
  * Esc in a pack reveal first reveals the cards;
  * popups close before the screen;
  * BACK returns to the screen you came from.
* **Welcome panel:** its PLAY THE FIRST GAME button is no longer cut off at the bottom of the screen.
* **Main menu:**
  * an UP NEXT strip with the best next action;
  * a promotion button and a new-trait badge;
  * advanced tiles dimmed until the first game is done.
* **Results:** a WHAT'S NEXT row:
  * promotion
  * claim missions
  * open packs
  * upgrade a card
  * choose a trait
  * claim a set reward
  * the Daily
  * try new cards
* **Disabled buttons:** they say why, and Team links straight to the Pro Shop.

**Verification**
* Script check: 82 scripts, 0 failed.
* System suite: 1,431 checks, 0 failed.
* Full UI flow test: 172 checks, 0 failed. It adds the missions and navigation sections.
* Card hit map: 0 of 175 dead points; 12 of 12 fast clicks cast.
* Before/after comparison: `docs/screenshots/update6_before_after.jpg`.

**Known limitations**
* Not finished from the card review:
  * Line Drive: nothing lingers after the hit.
  * Splitter: the split balls are small.
  * Hot Corner between throws: still mostly its ring.
* Veteran Standard Siege sits under its 40 % autopilot target.
* Frame rates are still unmeasured on a real GPU.

**Upgrade All** (after Update 6)
* An UPGRADE ALL (N) button on the Card Upgrades screen spends copies and coins on every level-up the player can
  afford. Cheapest coin cost goes first, then rarer cards, and a card can gain several levels.
* A confirmation lists each card with its level change and shows the total coin cost before anything is spent.
* `Profile.upgrade_all_plan()` previews without changing anything; `Profile.upgrade_all()` applies exactly that
  plan.
* Covered by system tests and the `deck` UI section.

## 13. Update 7: "Expansion Pack"

Plan: `docs/plans/UPDATE_7_PLAN.md`.

**Twelve new cards** (44 in total), each a new mechanic. Every card also has a `role` tag for the deck
builder.

| Card | Rarity | Cost | What it does |
|---|---|---|---|
| Bean Ball | Common | 2 | 140, stun and knock back; fast runners take double. |
| Intentional Walk | Common | 2 | A runner is 55 % slower for 5 s and can't score. |
| Infield Fly | Uncommon | 3 | A pop-up over an area: the first runner in it is called out. |
| The Shift | Uncommon | 3 | Every defender shifts toward the spot for 6 s and throws faster. |
| Momentum | Uncommon | 2 | For 8 s, every out gives 0.5 energy. |
| Around the Horn | Rare | 4 | 130 to the lead runner on each path. |
| Rundown | Rare | 4 | Traps a runner going back and forth for 4 s, tagged at each turn. |
| Golden Glove | Rare | 4 | A defender catches the next 3 runners that come near. |
| Rain Delay | Epic | 5 | No new runners for 5 s; every runner 35 % slower. |
| Relief Pitcher | Epic | 5 | A reliever jogs in and throws for 10 s. |
| Grand Salami | Legendary | 8 | A giant fireball rolls down a base path, then fire. |
| Instant Replay | Legendary | 4 | Replays your last card, free and one level stronger. |

All twelve have effects, art, autopilot use, combos and system tests, and come from packs. Existing saves
gain them as not owned. Line Drive now leaves a scorch and dust, and Splitter's balls are bigger.

**Auto Build** (`src/core/deck_ai.gd`)
* **Scoring:** each owned card gets a power score from its parameters at its current level, per energy and per
  cooldown. Role coverage, energy curve, team signatures, combos, card level and mastery are added on top.
* **Search:** a greedy pick, then swaps until nothing improves the deck. The result is deterministic.
* **Modes:** Balanced, Aggressive, Control and Boss Killer.
* **Explained:** a summary banner and reason chips per card, plus Undo.
* **Curve limits:** with the bigger pool the energy curve is enforced more firmly. Balanced and Control allow
  one card costing 6+, Aggressive and Boss Killer two.
* **Autopilot check** (Quick Defense, 20 games each): the new Balanced deck won 90 % against 70 % for the old one
  on Standard.

**Card comparison** (`src/ui/card_compare.gd`)
* Open it with COMPARE in the inspector, or shift-click a card.
* It shows two cards side by side with cost, cooldown, target, level, mastery and every stat (now and at the
  next level), with the better value highlighted.

**Defenders:** material classes in the merged character shader (cloth sheen, warm skin, glossy leather,
metal) and a faint outline in each defender's accent colour for readability at battle distance (stronger with
High contrast). Portraits re-rendered.

**Fixes and tuning**
* Dugout: the specials header always starts its own row, and the level pips are round again.
* Veteran Standard Siege starts with one base shield and has slightly smaller waves (per-mode tuning; the shield
  shows on the Play screen). Autopilot: 1–2 wins in 6 per sample, with most losses at the final boss in inning 9.
  Still under the 40 % target.

## 14. Title screen

`src/ui/title_screen.gd`, `scenes/title.tscn`. Shown once when the game launches; it replaces the old logo splash.

* **Background:** a live night stadium (Champion's Citadel).
  * The camera swoops down from above centre field into a slow crane orbit.
  * Four coloured searchlights sweep the sky.
  * Fireworks burst every few seconds.
  * Home-run balls arc out of the park with glowing trails and a bat crack.
  * The crowd cheers and does the wave, and the team celebrates on the field.
* **Logo:** it slams in at about 1.4 s with a whoosh, bat crack and crowd roar, a white flash, a small camera
  shake, light rays, gold sparkles and fireworks, then a shine sweep every few seconds. Reduce-flashes and
  screen-shake settings are respected.
* **Prompt:** "PRESS ANY BUTTON TO START" pulses in a gold-rimmed band at the bottom centre.
* **Input:**
  * A key, mouse click or gamepad button during the intro skips to the finished title.
  * The next press starts: a flash, a roar, the logo rushes forward, and the main menu opens.
* **Main menu:** it now opens directly on the lineup. The camera no longer pushes in through the stadium; it
  only breathes slightly.
* **Test:** UI section `title`, also part of the full run.

![Title screen](screenshots/title.jpg)

## 15. Update 8: "All-Star Tuning"

Plan: `docs/plans/UPDATE_8_PLAN.md`. Reviews: `docs/plans/review/card_vibrancy.md`, `abilities_vibrancy.md`.

**Mechanics** (simulator evidence: Quick Defense random decks, 75 games, plus 6–8-game rows; win rates are
±15–20 points)

| Area | Changes |
|---|---|
| Cards | Grand Slam Barrage: tighter radius, more and harder balls; it had the worst damage per energy. Bunt Trap: cost 2 → 3, it was an auto-include. Around the Horn: 130 → 120. Shadow Change: cost 5 → 4. Pickoff: cooldown 12 → 8, damage 150 → 170. Diamond Aura: cooldown 15 → 12. Intentional Walk: cooldown 8 → 6, lasts 7 s. |
| Defenders | Rico: damage 24 → 30, faster throws, range 8.5 → 12 m. Rico went from 1 % to 3 % of team damage and from 1.6 to 4 outs a game; his catcher aura is now measured as an assist. Also Maya +, Nova +, Kai −, Hana −. Damage shares now run from 3 % to 32 % (they were 1 % to 34 %). |
| Difficulty | Quick Defense Veteran and Legend now really are harder than Standard: their runners had less health than Quick Standard's. Veteran Siege waves are back up a step. Autopilot results: Quick Rookie 8/8, Standard 5/8, Veteran 3/8, Legend 1/8; Siege Standard 5/8, Veteran 4/8. |
| Dugout | Scouting Report 30 → 50 coins (best value per coin). Card Mastery 40 → 30. Lucky Bat +5 % → +8 % crit. Hot Streak +25 % → +35 %. Captain's Rally's data and text now match what the game does (+8 % / +1.5 m per level). |
| Auto Build | `ai_weight` in `cards.json` calibrates the power estimate with measured impact: Relief Pitcher, Called Shot, Momentum and Changeup up; Grand Slam Barrage, Instant Replay, Diamond Aura, Time Out and Field Vision down. |

**Card effects, made vivid** (`src/vfx/card_fx.gd`, new `src/vfx/vivid_fx.gd`, three new shaders)
* All 44 cards were reviewed from the battle camera: 36 scored under 4 of 5 for vibrancy before; after the
  pass none is under 3, and the average rose from 2.9 to 3.8.
* **Why effects looked washed out:** the filmic tonemap and a high glow threshold flattened colour, and additive
  light over daytime grass turned pastel.
* **Fix:** HDR cores pass the glow threshold, and ground light is mixed over the ground instead of added on top.
* **Category palette:** 18 colour-over-life ramps in the category families (offense fire/scarlet, control
  violet/ice, defense teal/emerald, utility gold/amber). Off-family cards moved into their family, for example
  Power Throw from gold to comet red and Line Drive from white to blaze orange.
* **Shared impact:** a `punch()` impact (core flare, halo, sparks, flash ring) and a ground glow that lingers
  1–2 s.
* **Legendaries:** a brief screen accent: radial streaks, coloured screen edges and a bloom lift, about 0.45 s.
* **Settings:** particle counts follow the particle setting; reduce-flashes dims the flares and the accent.

**Abilities and hits** (`vfx.gd`, `projectiles.gd`, `defender.gd`, `enemy.gd`, visuals only)
* **Throws:** trails in each defender's accent colour, with a hot core. Each class ability has its own throw
  look (Ace's burning fastball, Nova's crackle, Kai's laser line...).
* **Signature casts:** the defender glows in their colour, with a ring at the feet and a burst at release.
* **Crits and outs:** crits get a layered gold starburst with streaks; outs pop in the colour of the defender
  who made them, with team-colour sparks.
* **Status effects:** flames on burning runners, crisp ice, bigger stun stars, slow streaks.
* **Elites:** a distinct colour, ground ring and particles for each of the five affixes.
* **Bosses:** a warning zone that fills exactly to the moment of impact, and big impacts (shockwave, crater,
  debris, dust, rays). The Phantom Captain's phase now has a violet implosion.

**New features**
* **Scouting Book** (`src/ui/scouting_book.gd`, `src/core/scouting.gd`):
  * 18 entries: runner types including the bosses, and the elite affixes.
  * Each has a 3D turntable, stat bars read from data, "What it does", "How to stop it", and good cards
    against it (yours first).
  * Entries unlock when first met in a game, and existing saves are migrated from history.
  * Reachable from the main menu, the Play screen and the battle threat panel. In battle, clicking a threat
    icon opens a scouting card and pauses the game.
* **Combo hints in the hand:** a green arc with sparks links two cards that combo, both glow, the selected
  card's partner pulses, and the tooltip names the combo.
* **Good against:** the card inspector lists the opponents a card counters, with links into the book.

**Verification**
* Script check: 88 scripts, 0 failed.
* System suite: 2,047 checks, 0 failed.
* Full UI flow test: 232 checks, 0 failed, including the new scouting sections.
* Card hit map: 0 of 175 dead points; 12 of 12 fast clicks cast.

![Scouting Book](screenshots/scouting_book.jpg)

## 16. Fix: Siege Slugger bat clipping

**Problem:** the Siege Slugger's spiked bat went straight up through its right shoulder pad in idle, walk
and hit, which is the pose the Scouting Book shows. The handle also stuck about 30 cm out below the fist,
so the hand didn't seem to hold it. During the swing the bat also passed through the helmet and both pads.

**Fix (in the character generator):**
* The bat now sits in the fist with only a short knob below it.
* New per-character bat poses (`roster.py` → `bat.pose`, read by `anim.py`):
  * In idle, walk, hit, stunned and sprint, the bat is held upright in front of and beside the pad.
  * The taunt and celebrate raise it on a line that clears the pad.
  * The swing uses re-keyed wind-up and follow-through. The follow-through now returns in front of the body
    instead of over the head.
  * The free hand joins the bat during the wind-up and lets go after the follow-through.
* The other two bat characters (Iron Slugger, Grand Slammer) are unchanged and rebuild byte-identical.

**Verification:**
* A geometric check over every frame of all 11 clips tests the bat against both pads, the helmet and the
  head. Before: up to 26 vertices inside in idle, walk, hit and swing. After: 0 in every clip.
* The rig, clip names, lengths and event times are unchanged. Loop seams are 0 and foot slide is 0.
* Script check: 88 scripts, 0 failed. System suite: 2,047 checks, 0 failed.

![Siege Slugger before / after](screenshots/slugger_bat_fix.jpg)

## 17. Coin boost: +50 % coins from every source

Every way the player earns coins now pays 50 % more. Prices are unchanged: packs, bundles, card upgrades and
gear. In-game coins for dugout upgrades are also unchanged, so battle difficulty doesn't move.

| Source | Before | After |
|---|---|---|
| End of game | 35 % of in-game coins + 15 per inning + 100 for a win | 52.5 % + 22.5 per inning + 150 for a win |
| First win ever | 150 | 225 |
| Daily Challenge, first game of the day | 150 | 225 |
| Daily missions (tier 1 / 2 / 3) | 100 / 150 / 100 + pack | 150 / 225 / 150 + pack |
| Starter missions | 150, 100, 150 | 225, 150, 225 |
| Account level road | 100 per level, 150–250 on milestones | 150 per level, 225–375 on milestones |
| Defender levels 2 / 5 / 8 | 100 / 250 / 400 | 150 / 375 / 600 |

The mode, difficulty and arena reward multipliers still apply on top. The account level-up message now shows
the real amount for that level; before, it always said "+100 coins".

**Economy projection** (`tools/balance/economy.py`, 300 players, 20 hours):

| | Before | After |
|---|---|---|
| Coins per hour | 3,079 | 4,638 |
| Coins after the first 10 games | 9,488 | 14,570 |
| Packs bought with coins per hour | 3.0 | 11.7 |
| First rare card at max level | 13.0 h | 10.2 h |
| All commons at max level | 16.3 h | 11.0 h |
| Rookie bundle (1,800 coins) | 0.6 h of income | 0.4 h of income |

## 18. Update 9: "Big League"

Plan: `docs/plans/UPDATE_9_PLAN.md`. The lead wrote the plan and a foundation commit with the shared
contracts as working stubs: Season, DailyRewards, Shop and Boons; profile keys; placeholder free agents; Boss
Rush; the Shop and Season scenes. Six streams then built the update in parallel, each in its own copy of the
code with one owner per file. The lead merged them, wired the streams together and ran the verification.

### New team members (stream A)
| Defender | Role | Trait | Signature card | Unlock |
|---|---|---|---|---|
| **Moose** Malone, #25 "The Big Scoop" | Infielder (first base) | **Long Stretch**: runners within 5 m take +25 % damage from everyone and are 10 % slower (lime ring). | Scoop & Tag | Account level 15, or sign for 5,000 coins |
| **Rosa** Vega, #7 "The Strategist" | Catcher | **Pitch Framing**: every 6 s she frames the most dangerous runner: +35 % damage taken, and its out gives +0.5 energy ("FRAMED!" and a magenta marker). | Signal Caller | Level 20, or 7,500 coins |
| **Sid** "Submarine" Okafor, #51 | Pitcher | **Skipper**: after a hit, the ball skips on into one runner up to 4 m behind for 60 % damage. | Worm Burner | Level 25, or 10,000 coins |

* All three are hero-style models with the same rig, clips and event times as the other defenders:
  * Moose is the tallest and broadest, with a long first-baseman's mitt.
  * Rosa wears catcher's gear, with her mask pushed up.
  * Sid is lanky and wears goggles; he has his own low submarine throw.
* Each has 18–20k triangles. `verify_characters` is clean: no foot slide and loop seams of 0.
* Stats were tuned with the simulator so each one is a real alternative to the defender it replaces, not a
  straight upgrade.

![New defenders](screenshots/u9/team_moose.jpg)

### Twelve new cards (stream B)
| Card | Rarity | What it does |
|---|---|---|
| Scouting Report | Common | Every runner of the chosen type takes +30 % damage for 8 s, including ones that spawn later. |
| Sprinkler System | Common | Soaks a base path: runners are 30 % slower and can slip. |
| Sweet Spot | Uncommon | Every throw is a critical hit for 6 s. |
| Rally Monkey | Uncommon | +3 energy, or +5 energy and a card if a run scored this inning (clutch). |
| Second Wind | Rare | One defender's signature card comes off cooldown, and they get +50 % attack speed. |
| Money Ball | Rare | Outs pay double in-game coins for 12 s. |
| Scoop & Tag | Rare | Moose's sweep: knocks runners back and stuns them. Hurt runners are out. |
| Signal Caller | Rare | Rosa marks the three most dangerous runners: +40 % damage, and outs refund energy. |
| Hidden Ball Trick | Epic | After a reveal, the strongest non-boss runner is out; bosses lose 15 % of max health. |
| Worm Burner | Epic | Sid's skipping grounder tears down a base path, tripping runners and leaving a slick. |
| Fireworks Night | Legendary | 14 fireworks strike runners over 4 s, then a finale. |
| Ground Rule Double | Legendary | The next 2 cards played this inning are cast twice. |

* Every card has painted art in the existing style, FX in the Update 8 vibrancy style, 19 new combos, the
  "Big League" collection set (Champion Pack reward), Scouting Book "good against" entries, and Auto Build
  support with simulator-calibrated `ai_weight`.
* The card pool grows from 44 to 56.
* Hand hit map with new-card decks: 0 of 175 dead points. Fast play: 12 of 12 clicks registered.

![New card art](screenshots/u9/card_art_new_cards.jpg)
![New card effects](screenshots/u9/vfx_new_cards.jpg)

### Modes: Dugout Draft, Boss Rush, Endless milestones, Next Wave Now (stream C)
* **Dugout Draft:** after a boss that doesn't end the game, the game holds and you pick 1 of 3 boons for the
  rest of the game. This happens after innings 3 and 6 in Standard Siege, after every boss in Endless, and
  after bosses 1 and 2 in Boss Rush.
  * There are 18 boons: 8 common, 6 rare and 4 epic. Examples: Heavy Lumber +15 % team damage, Extra Innings
    one more run allowed, Giant Killer bosses take +25 %, Deep Bench, Leadoff Discount, Infield In, the
    Clinics (+1 card level for a category).
  * Offers never repeat a boon you've taken, skip useless ones, and always include a rare or better.
  * Pick with keys 1/2/3, a click or a controller. Boons survive Save & Quit, and the HUD shows them as chips.
* **Boss Rush** (new mode): three innings, each ending with a tougher boss, with drafts in between. About 7
  minutes, and the best time is recorded.
* **Endless:** a reward every 5 innings (shown in the HUD with your best inning), and a gentler ramp.
* **Next Wave Now:** between waves, the button or Space calls the next wave early for +1 energy and bonus
  coins.
* **New battle hooks** other systems build on: `runner_out`, `add_out_coin_bonus` and `add_energy`.

Simulator (autopilot, starter deck unless "mid"; roughly ±14 points at 12 games):

| Mode / difficulty | Before | After | Target |
|---|---|---|---|
| Standard Siege / Rookie | 100 % | 100 % | easy |
| Standard Siege / Standard | 80 % | 67 % (wave budget ×1.12 so boons don't trivialise it) | about 65 % |
| Boss Rush / Standard | 0 % (untuned stub) | 50 % (median 4.5 min of game time) | about 50 % |
| Boss Rush / Rookie | 75 % | 100 % | easy |
| Endless / Standard, mid profile | median inning 6.5 (fresh) | median inning 12.5 | 12–16 |

![Dugout Draft](screenshots/u9/dugout_draft.jpg)
![HUD: boons, milestone, Next Wave Now](screenshots/u9/hud_boons_milestone_next_wave.jpg)

### Economy and the return loop (stream D)
| System | Rules |
|---|---|
| Season Pass | 14-day seasons, 30 free tiers of 500 XP. XP: 100 per game, +60 for a win, +80 per mission, +100 for the Daily Challenge. Coins, packs and stars, a Champion Pack at tiers 15 and 30, a season uniform at tier 30, then a Pro Pack every 1,000 XP. At rollover, reached rewards are paid out automatically. |
| Login calendar | 7 days: 150 coins → Rookie Pack → 250 coins → 10 stars → Pro Pack → 400 coins → Champion Pack. A missed day pauses it. |
| Win streak | +10 % coins per win in the streak, up to +50 %. A loss resets it. |
| First win of the day | The game's coins are paid twice. |
| Daily Shop | A free gift; two deals on copies of cards you're upgrading (more likely if they're in your deck); a Pro Pack at −25 %; a Champion Pack for 40 stars. Refreshes at midnight. |
| Free agents | Sign Moose, Rosa or Sid early for coins. |
| Pack Luck | An Epic or better within 10 packs; a Legendary within 30 Pro or Champion Packs. Natural Legendary odds were lowered to 0.03 / 0.2 / 0.6 so the guarantee sets the pace. |
| Extra copies | Copies of a max-level card become coins: 20 / 40 / 80 / 160 / 400 by rarity. |
| Promotions | 300 coins and 10 stars × division, plus a Pro Pack (a Champion Pack from Gold up). |
| Missions and achievements | 4 new daily and 3 new weekly missions; 11 new achievements (52 in total). |

Economy model (`tools/balance/economy.py`, 200 players, 30 h):

| | Update 8 economy, 44 cards | Update 9, 56 cards |
|---|---|---|
| Whole collection | about 39 h | 30.1 h |
| First Legendary | 3.3 h | 3.1 h |
| After 6 games (first hour) | 30.5 packs, 8,930 coins | 32 packs, 10,091 coins |
| Coins per hour (all sources except extra copies) | 5,871 | 7,881 |
| Packs earned per hour | 12.5 | 15.1 |
| Season tier 30 at 1 h a day | – | 87 % of seasons, median day 13 of 14 |
| Players who sign a free agent early | – | 30 % (80 % of players who save for one) |

* The free-agent unlocks were moved from levels 13/16/19 to 15/20/25 after the model showed that almost
  nobody signed early.
* Extra-copy coins pay back about two thirds of a pack's price once most cards are maxed. There is no coin
  loop, because every pack still costs more than it returns.

### Screens (streams E1 and E2)
* **Hub:**
  * PLAY with a quick mode switch;
  * a TODAY column: login calendar with CLAIM, the Daily Challenge, missions, the free-gift link;
  * the season tier bar, the win streak flame and a first-win badge;
  * a Shop tile;
  * badges as corner bubbles.
* **Play menu:** seven large mode cards with your best record and what a win pays (Boss Rush included),
  two-line difficulty buttons with the reward multiplier, a stadium carousel instead of the wall of locked
  tiles, and the streak box.
* **Results:** three columns that fit at 1600×900, and a COINS total with bonus chips for the win streak,
  first win, Endless milestones and extra copies. Also the season XP bar with tier-ups, boons drafted and
  promotion rewards. The counter animations are bound to their own controls and stop when those controls
  leave the screen. This fixes the six "Lambda capture was freed" errors from the Windows smoke run of the
  coin-boost build.
* **Team:** a 3×4 portrait grid for 12 defenders, free agents with SIGN NOW and a confirm showing the price,
  and season uniforms shown as rewards instead of being for sale.
* **Shop and Season Pass:** two new screens.
* **Card Packs:** a Pack Luck panel, a Daily Shop link, and "+N COINS" / GUARANTEED tags in the results.
* **Level road:** labels that are readable and don't overlap, with reward pictures.

![Before and after: hub, Play, Results, Team, Card Packs, level road](screenshots/update9_before_after.jpg)
![Shop](screenshots/u9/e2_shop.jpg)
![Season Pass](screenshots/u9/e2_season.jpg)

### Verification
* **Script check:** 95 scripts, 0 failed.
* **System suite:** 2,917 checks, 0 failed (2,068 at the foundation commit).
* **Full UI flow test** on the final merge, fresh profile: 369 checks, 0 failed. The stream sections passed too:
  Dugout Draft 23/0, Team/Shop/Season/Packs 71/0, hub/Play/Results 41/0.
* **Card clicks with new-card decks:** the hand hit map has 0 of 175 dead points in both decks. All 12 of 12
  fast clicks registered, with none dropped.
  * One logged target click didn't cast. The note now says why: the aimed runner was put out before the click
    landed. That is a test artifact, not a click problem.
* **Simulator on the final code** (autopilot, starter deck, 9 games each, about ±15 points):

  | Mode | Difficulty | Wins | Runs allowed per game | Median game time |
  |---|---|---|---|---|
  | Standard Siege | Standard | 6/9 (67 %) | 1.22 | 18.6 min |
  | Boss Rush | Standard | 6/9 (67 %) | 2.11 | 4.8 min |
  | Quick Defense | Standard | 9/9 | 0.11 | 5.7 min |

  Quick Defense on Standard also won 9 of 9 on the foundation commit with the same seeds, so Update 9 didn't
  make it easier. It stays the gentle three-inning mode.
* **Windows build:** CI run 41902203216 passed the automated tests, the Linux smoke test and the Windows smoke
  test (`BaseballDraw.exe` plays a short autopilot game, then saves and reloads).
* **Known limits:**
  * Endless still gets hard within 1–2 innings once the ramp catches up; the gentler ramp only moves where that
    happens.
  * The Long Toss and Fresh Arms boons are never picked by the value-based autopilot. Their effects are covered
    by system tests.
  * Sprinkler System and Worm Burner read only moderately well from the far camera.

## 19. Update 10: "Front Office"

Plan: `docs/plans/UPDATE_10_PLAN.md`. Two parallel streams; the lead merged and verified.

### Best Team and Compare Defenders
* **TeamAI** (`src/core/team_ai.gd`) scores each defender from:
  * level-scaled stats, using the battle's own formulas;
  * gear and training traits;
  * a value for each of the 12 traits;
  * zone bonuses in the formation slots;
  * synergies at their real distances;
  * the captain aura;
  * owned signature cards and the deck.

  It tries every possible six (924 teams with 12 unlocked, under 0.3 s) with the best captain for each. It has
  four styles: Balanced, Damage, Control and Boss Killer. Only a strictly better team replaces the current
  one, so results are deterministic. It enforces the game's real team rules: six players, unlocked only, no
  duplicates, captain in the team.
* **BEST TEAM** on the Team screen previews:
  * the score before → after;
  * who comes in and who goes out;
  * a captain change, if any;
  * the top reasons for each pick.

  APPLY sets the team; CANCEL or Esc changes nothing. When the team is already the best for that style, the
  preview says so and APPLY is disabled.
* **COMPARE** puts two defenders side by side:
  * every stat at the current level, plus damage per second, vs bosses, vs crowds, control and team boost, with
    green/red bars;
  * traits, position bonus and signature card;
  * the TeamAI score;
  * a one-line verdict.

  CHANGE picks any defender for either side, locked ones included. PUT X IN FOR Y swaps a bench player into
  the starting six.
* Trait values in TeamAI are hand-set estimates, not simulator-tuned. Captains are usually the pitcher,
  because the aura on the default formations mostly reaches the infielders.

![Best Team](screenshots/u10/team_best_team_preview.jpg)
![Compare Defenders](screenshots/u10/team_compare.jpg)

### Main menu: broadcast matchday
* **Rebuilt to match the concept art:**
  * a full-width top bar: manager, division and RP, level with XP bar, coins, stars, cards owned, "?" and a
    settings gear;
  * a BROADCAST MATCHDAY hero block: the mode title, stadium and difficulty, CONTINUE RUN, PLAY and the mode
    chips;
  * the 3D lineup in the middle;
  * a TODAY panel: the Daily Challenge, Missions and Daily Login, each with a REWARDS strip of what it really
    pays;
  * a full-width bottom bar with the seven destinations.
* The gear menu holds Settings, Practice and Exit.
* The win streak, season tier and promotion are chips in the hero block.
* The hub scales down to fit at UI scales above 100 %.
* It is keyboard/controller navigable: the first arrow focuses PLAY.

![Concept and result](screenshots/u10/menu_concept_vs_after.jpg)

### Verification
* Script check: 97 scripts, 0 failed.
* System suite: 2,979 checks, 0 failed, including 62 new TeamAI checks: valid teams, never locked,
  deterministic, beats the starter team, Balanced covers every role.
* Full UI flow test on the merged update: 448 checks, 0 failed. It includes the Best Team/Compare section
  (47 checks) and the new hub checks: top bar values, CONTINUE RUN, chips, TODAY cards, bottom bar, gear menu,
  no overlaps.
* The hub's warm-up catch timer is now guarded against the menu being left mid-throw. That old script error
  was seen once in a UI run.
* **Smoke-test fix:** the first Update 10 build failed CI's Linux smoke test with six "Lambda capture was
  freed" errors. That is the same intermittent error as the coin-boost build.
  * **Cause:** card effects, Dugout Draft holds, the autopilot and the hub's catch animation used scene-tree
    timers. Those timers outlive their battle or menu. When a game ended right after a cast, the pending
    callbacks ran with their runners already freed.
  * **Fix:** they now use `Battle.later()` (a tween bound to the battle) or a tween bound to the menu, so
    pending callbacks die with their scene.
  * **Re-checked after the fix:** suite 2,979/0; UI sections draft 23/0 and newcards 12/0; three local smoke
    runs pass.

### Fix: runners running through the gate doors
* **Iron Fortress:**
  * **Before:** both routes left their gate 60° off the doorway and ran along the outfield wall, so runners cut
    through the door frames and the wall.
  * **Now:** they go 7 m straight out through the doorway, then make their wide swing well inside the wall
    (still the same winding path: out, wide, back across, past second, then home).
* **Every stadium:**
  * **Before:** gates start opening when a wave starts and take 0.8 s to swing open, but the first runners
    spawned at once and walked through the still-closed doors.
  * **Now:** spawns wait 0.7 s (`Battle.GATE_LEAD`).
* **New test, `test_routes`:**
  * every route in every layout leaves through its doorway (within 25°);
  * stays clear of the wall away from its gate;
  * never passes another gate.

  The other three layouts already passed.

![Iron Fortress gates](screenshots/u10/iron_fortress_gates_fixed.jpg)

## 20. Update 11: "Hall of Fame"

Plan: `docs/plans/UPDATE_11_PLAN.md`. Three parallel streams; the lead merged and verified.

### Card levels 1–10 and Prestige
* **Levels and power:**
  * Cards go to level 10. At level 5, PRESTIGE unlocks levels 6–10 (Prestige ★1–★5).
  * Power after level 5 is +5 % of base per level: ×1.48 at level 5, ×1.73 at level 10.
* **Costs:**
  * Levels 1–5 are unchanged.
  * The Prestige step costs 5–18 copies and 4,000–9,000 coins by rarity; later steps rise from there.
  * Extra copies become coins only when a card can't use them any more.
* **Look:** an iridescent holo frame, a gold crowned crest with stars, and five gold stars instead of level
  pips. It appears everywhere cards are drawn; in the battle hand the crest is a seal on the art.
* **Ceremony** (about 5.6 s, skippable, gentler with reduce_flashes): lift and spin, cracks of light, the frame
  shatters into shards, a comet traces the new frame, the crest slams down, confetti.
* **Upgrade All:** "Include Prestige" (off by default).
* **Also aware of Prestige:** Auto Build, compare, mastery ("Hall of Fame" cards), sets and pack results.
* **Two achievements:** Hall of Fame Material (first Prestige) and Gold Standard (★5).
* **Simulator** (Standard Siege, starter team): a level-10 deck wins 83 % against 75 % at level 5.
* **Economy model:**
  * first Prestige at 9.1 h;
  * first common at level 10 at 29 h;
  * whole collection 30 → 35 h, because extra copies now feed Prestige instead of buying packs.

![Prestige cards](screenshots/u11/card_faces_before_after.jpg)
![Prestige ceremony](screenshots/u11/ceremony_4_crest_slam.jpg)

### Defender levels to 20
* **Growth:** +3 % per level after level 10 (+84 % at level 20).
* **XP:** the XP curve reaches 90,100 at level 20: about 57 h for a regular team member, about 39 h for a
  defender who is always MVP.
* **Rewards for levels 11–20:** coins, Pro and Champion Packs, and new trait tiers at 12 (Iron Man / Quick
  Release) and 16 (Armor Breaker / Big Game).
* **Honours:** an All-Star badge at 15; a Hall of Famer gold frame and nameplate at 20, shown on the Team
  screen, the lineup and Results.
* **Level road:** two rows of ten. Level badges handle two digits.

![Hall of Famer](screenshots/u11/team_level20_hall_of_famer.jpg)

### Phantom Captain and boss fairness
**Causes found with a new per-boss simulator log:**
* Decoys soaked 18–30 % of the boss's health in damage: balls in flight and delayed cards re-aimed at decoys.
* Burns stopped while it was phased.
* It was untargetable 22–31 % of the time, with no reward window afterwards.
* Captains gave it 20 % damage reduction.
* Boss health grew without a limit in Endless: the Phantom reached 24,000 at inning 24.

**Fixes:**
* A phased Phantom still takes damage from balls in flight, burns and cards already aimed at it. Only new aims
  ignore it.
* After every phase it is REVEALED for 3 s and takes +25 % damage, and its decoys shatter.
* Decoys fade after 6 s.
* Captains no longer rally bosses.
* Boss health growth is softened above 2× and capped at 3.6×.
* The boss bar shows PHASED / REVEALED / VULNERABLE with a timer.
* The Scouting Book and the boss intro explain the counterplay.

| Phantom beaten | Before | After |
|---|---|---|
| Boss Rush, Standard (fresh / mid) | 33 / 92 % | 50 / 92 % |
| Boss Rush, Veteran mid | 42 % | 75 % |
| Boss Rush, Legend high | 33 % | 75 % |
| Siege inning 6, Legend high | 64 % | 58 % |
| Endless inning 6, Legend | 50 % | 75 % |

* The Grand Slammer in Boss Rush went from 33–58 % to 44–75 %.
* Deep Endless (innings 18+) relies on the health cap: the autopilot rarely gets that far.

![Boss bar revealed](screenshots/u11/boss_bar_revealed.jpg)

### Verification
* Script check: 100 scripts, 0 failed.
* System suite: 3,196 checks, 0 failed.
* The hand hit map with Prestige cards: 0 of 175 points dead.
* Full UI flow test on the merged update: 514 checks, 0 failed, including the Prestige, level-20 and boss-bar sections.

## 21. Update 12: Gate tunnels and stadium clearance

Player report: on some maps runners spawned in the wrong place, and gates opened into the rest of the stadium.

### Geometry check
The route check from Update 10 (`test_routes`) only compared 2D route lines with the wall arc. A new tool,
`StadiumClearance` (`src/battle/stadium_clearance.gd`), checks the real stadium meshes instead:
* It builds each arena headless and collects every visible stadium triangle in world space. Each crowd fan
  counts as a box.
* It tests them against oriented boxes for each gate:
  * the doorway;
  * the doors, sampled every 10° of their 100° swing;
  * the spawn area behind the gate;
  * runner and boss corridors along every route, from the back of the tunnel to 8 m out;
  * a 1 m gap around each tunnel.
* Corridor sizes come from the real enemy models at battle scale, plus the runners' ±0.9 m lateral offset:
  * runners: 3.44 m wide × 3.79 m high;
  * bosses: 4.66 m wide × 6.81 m high (the Grand Slammer is 6.7 m tall).
* Anything below 10 cm is treated as floor: the ground, paint and the 8.5 cm door threshold.
* Run the report with `godot --headless --path . res://tests/stadium_check.tscn [-- --arena=<id>]`.
  `test_stadium_clearance` in the system suite runs it for all six arenas and fails on any intrusion. It
  also checks that it catches a crate placed in a tunnel and a post placed in a tunnel's gap.

**Before: 75 intrusions** (full list: `screenshots/u12/clearance_report_before.txt`):

| Arena (layout) | Intrusions | What |
|---|---|---|
| Steel Yard, Sunset Grounds, Frostpark (classic) | 11 each | A wall segment ran 0.75 m into gate L's doorway and its right door's swing, ad board included. The grandstands at ±42° sat right behind gates L and R, in the spawn area and the boss corridor. Every gate header was too low for the bosses. |
| Neon Diamond, Champions Citadel (corner gates) | 18 each | The side walls started inside the corner gates: they crossed the doorway, both door swings and the runner corridor. The outfield wall and its ad board ran into gate R's doorway and door swing. Banner poles stood in the doorways. Headers too low for bosses. |
| Iron Fortress | 6 | A wall segment in gate R's doorway and door swing. A banner pole in the west boss corridor. Headers too low. |

**After: 0 intrusions** in all six arenas.

### Fixes
* **Gates:** scaled ×1.12 wide and ×1.42 tall.
  * The doorway is now 6.7 × 7.0 m, so the tallest boss fits.
  * The scale is the same along X and Z, the axes the doors turn in, so the doors still swing true.
* **Outfield wall:** it is laid out between the gates. Each free stretch is filled with whole segments,
  scaled slightly to fit, that butt into steel collars on the gate pillars. No segment reaches a doorway or a
  door swing any more.
* **Side walls:** a side wall starts at the outer collar of a corner gate instead of inside it.
* **Stands:** stands stay 1.5 m clear of every tunnel.
  * Outfield stands are packed between the tunnels and mirrored. Full 12 m stands go where they fit; narrower
    ones (down to 7 m) fill the tighter gaps.
  * A narrowed stand seats fewer fans, each at full width.
  * Side stands slide along their wall until they are clear.
* **Banners, light towers and the scoreboard:** they move until they are clear of the tunnels. The scoreboard
  steps back behind a centre-field tunnel.

### Runner tunnels
* **The tunnel:** every gate has a 9 m walled, roofed tunnel behind it.
  * A full-height front section opens onto the doors; a lower rear section steps down to the concourse.
  * Inside: steel portal frames, ceiling light strips, caged wall lamps, a hazard dado, white lane edges,
    yellow chevrons pointing to the field, and a hazard threshold.
  * The end wall has service doors and a lit VISITORS sign.
  * A warm work light inside is skipped on Low quality.
  * Outside: cladding in the arena's wall colour, pilasters, a trim band, copings and roof railings.
* **Spawning:** runners now appear inside the tunnel (up to `Battle.TUNNEL_SPAWN` = 3.6 m behind the
  doorway) and walk straight out through the doors.
  * Each runner starts walking early enough to reach the doorway exactly at its old slot time
    (`GATE_LEAD` + its start). Wave timing and route lengths are unchanged.
  * The doorway-exit rule from `test_routes` still holds.
  * In the tunnel a runner is out of play: it can't be aimed at or hit, and its health bar stays hidden.
  * Routes now have `entry_dir()` / `entry_position(d)` for the tunnel stretch (negative d).

### Look
* **Gate surrounds:** steel collars with trim caps and entrance lamps where the wall meets each gate.
* **Light bars:** bars on both pillars glow red while a gate is shut and green while it is open
  (`set_gate_open`).
* **Marquee:** a lit "VISITORS · GATE X" marquee stands on the tunnel roof. Centre-field gates don't get
  one, so it never covers the scoreboard.
* **Materials:** the new pieces use the generated prop textures (concrete, steel, roof sheet, hazard,
  galvanised steel), mapped triplanar, so they match the Blender props.
* **Budget, Steel Yard:** 136 → 170 mesh instances and 3 → 6 lights. Fans drop from 1,990 to 1,730 because
  the gates now take more of the outfield.

### Tools
* `--cam=x,y,z --cam-look=x,y,z [--cam-fov=deg]` pins the battle camera for close-ups. The existing
  `--cam-view` only orbits the field.
* `--no-hud` now also hides pop-up toasts.

Screenshots (`docs/screenshots/u12/`, before | after):
![Steel Yard gates](screenshots/u12/steel_yard_gates_before_after.jpg)
![Neon Diamond gates](screenshots/u12/neon_diamond_gates_before_after.jpg)
![Behind a gate](screenshots/u12/steel_yard_behind_gate_before_after.jpg)
![Tunnel](screenshots/u12/iron_fortress_tunnel.jpg)

For all six arenas there are overview pairs (`<arena>_gates_before_after.jpg`), gate close-ups with runners
(`<arena>_gate_closeup_before_after.jpg`) and tunnel views, inside and from behind (`<arena>_tunnel.jpg`).

### Verification
* Script check: 102 scripts, 0 failed.
* System suite: 3,217 checks, 0 failed.
  * 21 of them are new: the clearance check for all six arenas, the checker self-test, the envelope and doorway
    sizes, and the tunnel spawns (timing, out of play, unchanged route).
  * `test_routes` still passes.
* Clearance report: 0 intrusions in all six arenas (`screenshots/u12/clearance_report_after.txt`).
* Full UI flow test: 514 checks, 0 failed.

## 22. Update 13: "Rookie Camp" (new-player onboarding and early retention)

Plan: `docs/plans/UPDATE_13_PLAN.md`. The goal: a new player is playing within seconds, feels skilled and
rewarded in the first ten minutes, always knows the next step, and has reasons to come back on days 2–7.

### First session (stream A)
* **Straight into play.** A brand-new profile goes title → story intro → guided first game, with no hub stop.
  * The intro (`src/ui/story_intro.gd`) is three animated story cards over the live title stadium, 13 s in all:
    the Wreckers, your six defenders (captain first) and three ability cards.
  * A click, Space or → moves on; SKIP or Esc starts the game at once.
  * "I've played before" (title and intro) goes straight to the hub, with nothing locked.
* **First game: learn by doing** (`src/ui/battle_tutorial.gd`, `Session.first_game_config()`).
  * Rookie Quick Defense cut to 2 innings, with a fixed seed and a first-game assist (runners 0.85× health,
    a 0.85× wave budget, an Iron Slugger at 0.3× health closing inning 2 as the boss tease).
  * Every step is an action with one line of text, a spotlight and a pointer; nothing pauses the game:
    drag a fielder to the ring, PLAY BALL, the first throw, play a card on a runner (in slow motion), then a
    staged pack of three runners and Heat Wave in bullet time for a guaranteed **TRIPLE PLAY** with a
    "WHAT A PLAY!" celebration. Short tips follow for the break, the dugout and the boss.
  * Generic hooks: a config `innings` override (`run_state.gd`), a config `tuning` override
    (`wave_generator.gd`), and the boss intro plays once the tutorial's core steps are done (`battle.gd`).
* **Guided rewards.** The first win gets a simple Results layout (`first_win_results.gd`): coins, XP and packs
  as three big moments and one OPEN YOUR PACK! button. Then a guided pack opening ("TAP TO OPEN!", "TAP A
  CARD TO FLIP IT!", "NEW CARD: X!") and a guided deck swap, saved through `Profile.set_deck` so Rookie Path
  step 3 completes. The hub then spotlights PLAY: "READY FOR GAME 2?".
* **Funnel.** `Profile.data.onboarding_funnel` holds the shared timestamps (first launch, first game, first
  win, first pack, game 2, day-2 return) and a detailed `ftue` record (intro done or skipped, first throw,
  first card, deck edited...). Each step prints `[FTUE] <step> <s>`.

### Unlocks and retention (stream B)
* **Progressive unlocks** (`src/core/onboarding.gd`, `data/onboarding.json`). A feature opens at an account
  level or a Rookie Path step, whichever comes first:

  | Opens at | Features |
  |---|---|
  | Start | Quick Defense, Cards & Deck, Card Packs |
  | Level 2 or step 3 | Upgrade Cards, Team |
  | Level 3 or step 5 | Standard Siege, Missions, Daily Challenge |
  | Level 4 or step 7 | Shop, Season Pass |
  | Level 5 or step 9 | Boss Rush, Endless, Scouting Book, Promotion |

  Locked features stay visible with a lock and "LV n"; pressing one explains how to open it. Each group opens
  with a NEW FEATURE UNLOCKED card and a spotlight on the hub. Established players (level 5, 5 games or
  `flags.unlock_all`) see everything, with no celebrations; old saves are migrated.
* **Rookie Path** (`data/missions.json` "starter"): ten steps on a hub strip, each teaching one feature, with
  rising rewards. The finale is a Champion Pack, 1,000 coins and a free agent of your choice.
* **Picks.** After game 3, pick 1 of 3 unowned Epics, scored by DeckAI for your team, each with a reason.
  The same picker serves the Rookie Week Legendary and the free-agent finale (DECIDE LATER keeps it).
* **Rookie Week:** a 7-day calendar beside the daily login, paying more each day; day 7 is a Champion Pack
  and a Legendary pick. A missed day pauses it; it never resets.
* **Early pacing:** levels 1–4 need 150/250/350/450 XP; games 1–3 pay an extra pack; a loss in the first 5
  games pays 150 coins and a Rookie Pack, and a coach card offers an easier difficulty (after 2 losses in a row
  also AUTO BUILD MY DECK).
* **Welcome back:** after 3+ days away, 500 coins and a Pro Pack (7+ days: 800 coins and 2 Pro Packs) with a
  "what's new" card.
* **Badge budget:** a new player sees at most 2 attention badges on the hub at once.

### Economy (`tools/balance/economy.py`, 200 players, 40 h)
| | Update 12 | Update 13 |
|---|---|---|
| Packs after game 1 / game 3 / game 10 | 5 / 14 / 44 | 6 / 17 / 54 |
| Packs earned in hour 1 | 35 | 46 |
| Whole collection (target 30–40 h) | 35.0 h | 31.2 h |
| First Prestige (target 8–12 h) | 9.1 h | 8.2 h |
| Rookie Path finished | — | half by 1.1 h, all by 6.0 h |

Free picks restart their rarity's pity counter, which keeps the collection time in its target.

### Lead fixes
* A growing combo now upgrades one banner in place (DOUBLE PLAY → TRIPLE PLAY) instead of queueing both.
* The title's "I've played before" no longer shows through under the story intro.
* The guided pack opening hides the header subtitle and rule under its big text.
* The missions panel calls the chain "ROOKIE PATH" and shows its 10 steps as numbered nodes; the "what's
  next" suggestions skip features that are still locked.
* The FTUE UI test waits on game state with longer caps (slow software rendering).
