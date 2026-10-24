# Characters — build report

**Status: COMPLETE — all 20 GLBs + 20 portraits are final builds** (ace+runner were delivered first; everything was
rebuilt from the final generator at the end). Every GLB was imported into a scratch Godot 4.7.2 project and
inspected, and re-imported into Blender to measure foot sliding / ground contact / loop seams.

## 1. Rebuild

```
# everything (20 GLBs + 20 portraits), ~2-3 min per character on 4 cores
/opt/tools/bpyenv/bin/python tools/blender/characters/build_characters.py
# selected ids / flags
/opt/tools/bpyenv/bin/python tools/blender/characters/build_characters.py ace runner [--no-portraits] [--no-glb]
# metrics of the exported GLBs (foot slide, lowest mesh point, loop seams) -> characters_verify.json
/opt/tools/bpyenv/bin/python tools/blender/characters/verify_characters.py [ids...]
```

Outputs `assets/models/characters/<id>.glb`, `assets/textures/portraits/<id>.png`, and machine-readable summaries
`docs/asset_reports/characters_build.json` / `characters_verify.json`. Fully procedural and deterministic: bodies,
heads, clothes and gear are numpy SDF sculpts polygonised with surface nets and decimated in Blender to the budgets;
weights are computed procedurally; animations are authored with a custom FK/two-bone-IK pose solver and baked.
Jersey numbers use the repo font `assets/fonts/RussoOne-Regular.ttf`. Materials are flat colours only (no textures,
no UVs needed).

Source `tools/blender/characters/`: `build_characters.py` (entry, assembly, export), `roster.py` (all character
definitions), `rig.py` (shared armature + pose solver), `anim.py` (all clips), `skin.py` (weights), `body.py`,
`heads.py`, `outfit.py`, `enemies.py` (modelling), `sdf.py` (SDF + polygoniser), `meshutil.py`, `materials.py`,
`render.py`, `portrait.py`, `verify_characters.py`.

## 2. GLB contents (verified in Godot 4.7.2, identical for all 20)

```
<id> (Node3D)
├─ Armature (Node3D)
│  └─ Skeleton3D                 path: Armature/Skeleton3D   (22 bones)
│     └─ Body (MeshInstance3D)   path: Armature/Skeleton3D/Body  (single skinned mesh, one surface per material)
└─ AnimationPlayer               path: AnimationPlayer
```

* Bones (names/hierarchy exactly ASSET_SPEC 3.1): `root, hips, spine, chest, neck, head, shoulder.L, upper_arm.L,
  forearm.L, hand.L, shoulder.R, upper_arm.R, forearm.R, hand.R, thigh.L, shin.L, foot.L, toe.L, thigh.R, shin.R,
  foot.R, toe.R`. Body types only change bone lengths/thickness.
* Origin on the ground between the feet, front = +Z in Godot (−Y in Blender), metres, real in-game size for
  enemies/bosses (no scaling needed).
* Tracks: `Armature/Skeleton3D:<bone>` rotations for all bones + `hips` position. Godot's importer drops tracks
  that never change (e.g. `root`, clavicles) — expected.
* Rigid parts use 100 % weight on one bone: cap/helmet/hair/eyes/glasses/horns → `head`, mitt → `hand.L`,
  bats → `hand.R`. `hand.R` of defenders is empty (game spawns the ball).
* Materials (exact spec names): defenders `Skin, Hair, Eyes, Iris, Jersey, JerseyTrim, Number, Pants, Socks, Shoes,
  Belt, Cap, Glove, Undershirt, Metal` (+ `Gear` for Rico). `Undershirt` = accent colour (sleeves, cap emblem, glove
  lacing, shoe swoosh, Maya's hair tie/wristbands, Bruno's headband). Hana's sun visor uses `Cap`.
  Enemies/bosses `Jersey` (gunmetal), `JerseyTrim` (type accent), `Pants, Socks, Shoes, Belt, Glove`,
  `Undershirt` (charcoal long sleeves + head under the helmet), `Gear` (helmet/dark armour), `Metal`
  (steel/iron/gold plates, buckle), `Glow` (emissive eye slit, molten seams, phantom trims), `Bat`, `Cloth` (capes,
  hood, scarf), `Number` (back number). Extra names: `Pupil`, `NumberOutline`, `Visor` (see deviations).

## 3. Animations (names + lengths as imported in Godot; event times as built)

| clip | length (s) | loop | event (s) | as built |
|---|---|---|---|---|
| `idle` | 2.0 | yes | | breathing + weight shift, feet IK-locked; Ace/Jax/Dex/Nova rest the right fist on the hip; enemies hunch, bat holders rest the bat on the shoulder |
| `run` | 0.70 | yes | | contact/passing poses, opposite arm/leg, hip bob, counter-rotating shoulders, heel-off toe roll |
| `hit` | 0.35 | no | | flinch back, returns to an idle-like pose |
| `stunned` | 1.2 | yes | | dazed wobble, right hand on the head, feet locked |
| `defeat` | 1.2 | no | | stagger, fall backwards, ends lying on the back (`hips` moves back ≈0.55×scale m and down) |
| `celebrate` | 1.0 | yes | | hop + right fist pump (feet leave the ground mid-hop) |
| `ready` (def.) | 1.6 | yes | | athletic crouch, glove low in front with the pocket open, double bounce |
| `throw` (def.) | 0.75 | no | **release 0.30** | gather → cock (hand behind head, glove arm at target) → release with hand.R high and in front of the head, shoulders open → follow-through across the body → ready pose |
| `pitch` (def.) | 1.40 | no | **release 0.85** | set, 80° turn, leg kick ≈0.50, stride lands 0.72, arm cocks, release 0.85, follow-through with back-leg swing, recovers to a fielding crouch at the origin |
| `catch` (def.) | 0.60 | no | **catch 0.25** | glove up/forward with the pocket toward the ball at 0.25, give, glove to chest, back to ready |
| `special` (def.) | 1.20 | no | **impact 0.70** | coiled power-up crouch 0–0.45, explosive stride-throw, release at 0.70 |
| `victory` (def.) | 2.0 | yes | | glove raised, right fist pumps, knee bounce |
| `walk` | 1.0 | yes | | relaxed heel-toe walk; slugger + bosses: heavy wide rolling stomp with hip drop on each foot strike |
| `sprint` (enemy) | 0.55 | yes | | aggressive forward lean, long stride, hard arm pump |
| `leap` (enemy) | 0.80 | no | **land 0.80** | crouch 0–0.15, push-off, tucked legs in the air (hips stay at standing height — the game moves the node), landing pose on the last frame |
| `swing` (enemy) | 1.0 | no | **impact 0.50** | two-handed swing: stride, hips then shoulders rotate, bat barrel in front of the body at 0.50, follow-through (non-bat enemies swing their fists) |
| `slam` (enemy) | 1.4 | no | **impact 0.90** | both hands/bat overhead, down to the ground in front at 0.90 in a deep squat, recover |
| `taunt` (enemy) | 1.5 | no | | chest out, arms wide with laughing shoulder shakes, then points at the defenders (bat raised for bat holders) |

Defenders (13): idle, run, hit, stunned, defeat, celebrate, ready, throw, pitch, catch, special, victory, walk.
Enemies + bosses (12): idle, run, hit, stunned, defeat, celebrate, sprint, leap, swing, slam, taunt, **walk** (added on
request).

* **Loop flags are not stored in glTF** — set `Animation.LOOP_LINEAR` for idle, run, stunned, celebrate, ready,
  victory, walk, sprint (first and last keys are identical; measured seam 0.0).
* In place: `root` never moves; body motion is on `hips` (bob, weight shift, the `defeat` fall, the stride in
  `pitch`/`throw`); all non-looping clips except `defeat` return near the start pose.
* **Natural ground speed** = speed at which the stance foot does not slide with `speed_scale = 1`; for another move
  speed use `speed_scale = move_speed / natural_speed` (e.g. a boss walking at 1.2 m/s).

## 4. Per-character numbers (triangles after triangulation, height = top of mesh in rest pose)

| id | kind | height (m) | triangles (budget) | clips | natural speed walk / run / sprint (m/s) |
|---|---|---|---|---|---|
| ace | defender | 1.81 | 13675 (14000) | 13 | 0.81 / 2.62 |
| rico | defender | 1.77 | 13555 (14000) | 13 | 0.81 / 2.62 |
| maya | defender | 1.73 | 13754 (14000) | 13 | 0.77 / 2.49 |
| jax | defender | 1.92 | 13558 (14000) | 13 | 0.85 / 2.78 |
| kai | defender | 1.93 | 13577 (14000) | 13 | 0.84 / 2.72 |
| bruno | defender | 1.95 | 13570 (14000) | 13 | 0.87 / 2.83 |
| nova | defender | 1.75 | 13557 (14000) | 13 | 0.77 / 2.51 |
| dex | defender | 1.78 | 13560 (14000) | 13 | 0.79 / 2.57 |
| hana | defender | 1.72 | 13559 (14000) | 13 | 0.76 / 2.46 |
| runner | enemy | 1.76 | 8714 (9000) | 12 | 0.78 / 2.54 / 4.08 |
| sprinter | enemy | 1.78 | 8713 (9000) | 12 | 0.77 / 2.51 / 4.03 |
| armored | enemy | 1.86 | 8707 (9000) | 12 | 0.83 / 2.68 / 4.31 |
| jumper | enemy | 1.79 | 8712 (9000) | 12 | 0.77 / 2.51 / 4.03 |
| swarmer | enemy | 1.19 | 8838 (9000) | 12 | 0.52 / 1.68 / 2.70 |
| trickster | enemy | 1.82 | 8707 (9000) | 12 | 0.80 / 2.61 / 4.19 |
| captain | enemy | 1.92 | 8709 (9000) | 12 | 0.83 / 2.71 / 4.35 |
| slugger | enemy | 2.36 | 8709 (9000) | 12 | 1.19 / 3.45 / 5.54 |
| iron_slugger | boss | 3.54 | 21315 (22000) | 12 | 1.78 / 5.17 / 8.30 |
| phantom_captain | boss | 3.21 | 16961 (22000) | 12 | 1.51 / 4.52 / 7.26 |
| grand_slammer | boss | 4.21 | 21312 (22000) | 12 | 2.08 / 6.03 / 9.69 |

| id | look |
|---|---|
| ace | athletic pitcher, medium-brown skin, spiky dark hair under the cap, red-orange accent, flame cap emblem, #21 back + small front (gold outline) |
| rico | stocky catcher, tan skin, steel-blue catcher helmet + steel face cage, chest protector, knee/shin guards (`Gear`), round catcher's mitt, #8 |
| maya | slim infielder, light-medium skin, dark ponytail out of the back of the cap (green tie), green wristbands, #5 |
| jax | tall muscular infielder, dark skin, short beard, cap backwards (snapback opening), eye black, orange-gold accent, #34 |
| kai | lean tall outfielder, stylised East-Asian features, cyan wraparound reflective sunglasses, #11 |
| bruno | huge heavy-set outfielder, pale skin, bald, red beard, purple headband, short sleeves + big bare forearms, #44 |
| nova | female pitcher, platinum pixie cut with side-swept fringe, yellow accent, lightning-bolt emblem, #99 |
| dex | slim infielder, curly hair around the cap, smirk, teal accent, #2 |
| hana | female outfielder, black bob with bangs, sun visor, pink accent, #17 |
| runner | Wrecker base: gunmetal uniform, hazard-orange trim/socks, batting helmet + ear flap, dark visor, glowing V slit, claw chest emblem, #13 |
| sprinter | slim, aerodynamic tail helmet, yellow lightning bolts on torso sides and thighs, #7 |
| armored | bulky, steel chest/back plate, layered pauldrons, greaves + knee caps, two-flap riot helmet, #66 |
| jumper | lime coil-spring shin guards, knee braces, long legs, #3 |
| swarmer | 1.19 m, oversized helmet, big hands/feet, #0 |
| trickster | lean, purple hood + mask with glowing eyes, purple scarf with tails, #9 |
| captain | broad, crested helmet, crimson cape, red pauldrons, gold armband, #1 |
| slugger | 2.36 m brute, spiked iron pauldrons, chest plate, gauntlets, giant iron-banded spiked bat in `hand.R` |
| iron_slugger | 3.54 m boss, full iron plates with glowing molten seams, spiked pauldrons, gauntlets, tassets, greaves, giant spiked bat |
| phantom_captain | 3.21 m boss, ghostly violet, semi-transparent tattered cape (`Cloth`, alpha 0.72), glowing violet eyes/trims |
| grand_slammer | 4.21 m final boss, black-and-gold armour, golden horns + crest, dark-red cape, giant golden bat |

## 5. Portraits

512×512 RGBA, transparent, Cycles CPU (96 samples + OpenImageDenoise), head-and-shoulders 3/4 view of the `idle` pose,
identical key/fill/2-rim/top rig scaled by head size; enemies use a tighter, more frontal crop so helmet colours and
the glowing eyes read at icon size.

![portraits](img/portraits_sheet.png)

## 6. Verification

1. Godot 4.7.2 import of all 20 GLBs: no errors; every file has `Armature/Skeleton3D` (22 bones),
   `Armature/Skeleton3D/Body`, `AnimationPlayer` with the clips/lengths above (lengths exact: hit 0.350, throw 0.750…).
2. GLB re-import metrics (`verify_characters.py`, 60 Hz, every 2nd frame):

| id | max foot slide in planted clips (m) | lowest mesh point over all clips (m) | worst loop seam (m) |
|---|---|---|---|
| ace | 0.0000 | -0.017 (defeat: -0.033) | 0.0000 |
| rico | 0.0000 | -0.014 (defeat: -0.034) | 0.0000 |
| maya | 0.0000 | -0.017 (defeat: -0.031) | 0.0000 |
| jax | 0.0000 | -0.018 (defeat: -0.035) | 0.0000 |
| kai | 0.0000 | -0.021 (defeat: -0.033) | 0.0000 |
| bruno | 0.0000 | -0.018 (defeat: -0.036) | 0.0000 |
| nova | 0.0000 | -0.017 (defeat: -0.032) | 0.0000 |
| dex | 0.0000 | -0.018 (defeat: -0.033) | 0.0000 |
| hana | 0.0000 | -0.016 (defeat: -0.030) | 0.0000 |
| runner | 0.0000 | -0.022 (defeat: -0.032) | 0.0000 |
| sprinter | 0.0000 | -0.019 (defeat: -0.032) | 0.0000 |
| armored | 0.0000 | -0.024 (defeat: -0.034) | 0.0000 |
| jumper | 0.0000 | -0.019 (defeat: -0.032) | 0.0000 |
| swarmer | 0.0000 | -0.021 (defeat: -0.028) | 0.0000 |
| trickster | 0.0000 | -0.021 (defeat: -0.070) | 0.0000 |
| captain | 0.0000 | -0.023 (defeat: -0.160) | 0.0000 |
| slugger | 0.0000 | -0.039 (defeat: -0.041) | 0.0000 |
| iron_slugger | 0.0000 | -0.045 (defeat: -0.066) | 0.0000 |
| phantom_captain | 0.0000 | -0.040 (defeat: -0.378) | 0.0000 |
| grand_slammer | 0.0000 | -0.052 (defeat: -0.424) | 0.0000 |

   Foot slide is measured on grounded feet in idle/ready/stunned/hit/victory/taunt/slam/catch (IK-locked → 0).
   The lowest non-`defeat` points are single frames of shoe tips at the `leap` landing / `pitch` pivot (≈1–2 % of
   height). In `defeat` the cape wearers' capes sink into the ground while lying on the back.
3. In-engine (Godot Forward+, directional light):

![ace and runner](img/godot_ace_runner.png)

ace idle / throw at 0.30 (release) / run mid-stride; runner idle / run / swing at 0.50.

![poses](img/godot_poses.png)

nova pitch at 0.85 (release), maya catch at 0.25, jax special at 0.70, slugger swing at 0.50, armored slam at 0.90,
jumper leap at 0.45 (node not moved, so it hangs in the air).

![defenders](img/godot_lineup_defenders.png)

![enemies and bosses](img/godot_lineup_enemies.png)

4. Blender close-ups (Cycles): face/cap, mitt pocket in `ready`, right hand on hip, cleats.

![close-ups](img/closeups.png)

## 7. Deviations from ASSET_SPEC

* **Baked at 60 Hz instead of 30 fps**: 0.35 s (`hit`) and 0.75 s (`throw`) are not whole frames at 30 fps
  (they imported as 0.333 / 0.733 s). At 60 Hz all lengths and event times are exact. Times in seconds unchanged.
* **Three extra material names**: `Pupil` (black pupils, mouth line, eye black, Kai's glasses frame),
  `NumberOutline` (gold number outline asked for by the palette section), `Visor` (glossy dark enemy visors, Kai's
  cyan lenses). No spec name was renamed or repurposed.
* `walk` added to enemies/bosses (lead request).
* Heights within 2 % of targets (runner 1.76, slugger 2.36, iron_slugger 3.54, phantom 3.21, grand_slammer 4.21,
  swarmer 1.19 m).
* `Metal` metallic 0.55–0.7 (not 1.0) so plates stay readable without a sky/reflection probe.

## 8. Known limitations

* No finger/face bones (per spec): hands are fixed sculpted poses (relaxed right hand, fists for enemies); no blinking.
* Linear-blend skinning, no corrective shapes: some stretch at the crotch/inner thigh in wide stances and at the
  shoulder with the arm fully raised.
* Capes, hood, scarf, ponytail are skinned to spine/neck/hips (no secondary motion): capes can touch the thighs in long
  strides and sink into the ground in `defeat`.
* Shoe tips dip ≤ 2 cm (≤ 5 cm on 3.5–4.2 m bosses) below ground in single frames (leap landing, pitch pivot);
  bodies ≤ 3–4 cm into the ground at the end of `defeat`.
* Arms are IK-clamped (fully extended) in a few frames where the target is out of reach (throw/pitch follow-through,
  slam on big bodies).
* Phantom's `Cloth` is alpha-blended (sorting may need care in Godot; it also matters if the game merges surfaces).
* Hair and thin shells are decimated SDF meshes: light hair (Nova) shows some faceting in close-ups.
* Loop mode must be set by the game (glTF has no loop flag).
