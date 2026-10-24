# Baseball Draw — Asset Specification (shared contract)

This document is the contract between the asset generators (Blender scripts, audio synth,
2D art scripts) and the Godot game code. Everything in the game is generated from source
scripts kept in `tools/`, so every asset can be rebuilt.

Engine: **Godot 4.7.2 (Forward+)**. Blender: **bpy 5.2.3** Python module at
`/opt/tools/bpyenv/bin/python` (run scripts with `/opt/tools/bpyenv/bin/python tools/blender/<script>.py`).

## 1. Units and axes

* 1 unit = 1 metre.
* Blender: Z-up, the character/prop **front faces Blender −Y**. The glTF exporter converts this to
  glTF/Godot **Y-up with the front facing +Z**. The game rotates models with
  `rotation.y = atan2(dir.x, dir.z)`, which points +Z at the target.
* Every model's origin is at **ground level, centred** under the model (between the feet for
  characters, base centre for props).
* Export format: binary glTF (`.glb`), `export_yup=True`, apply modifiers, include materials,
  no cameras/lights unless noted.

## 2. Brand palette

| Token | Hex | Use |
|---|---|---|
| navy_dark | `#0E1A2B` | UI background |
| navy | `#14233A` | UI panels |
| charcoal | `#1B1F27` | UI panels, enemy cloth |
| scarlet | `#E0262F` | primary accent, logo "DRAW" |
| scarlet_deep | `#A3141C` | shadows of scarlet |
| blue | `#2F7DE1` | accent |
| gold | `#F5B82E` | currency, legendary, highlights |
| green | `#3DDC84` | positive, uncommon |
| purple | `#9B5DE5` | epic, shadow effects |
| offwhite | `#F4F1EA` | titles, uniforms |

Home team ("Diamond Defenders") uniform: jersey navy `#1C2E4A`, trim scarlet `#D7262E`,
pants off-white `#EDEBE6`, belt/socks navy, cap navy with scarlet brim piping, gold numbers outline.

Per-defender accent colours (undershirt sleeves, cap logo, glove lacing, ability VFX):

| id | name | role | accent |
|---|---|---|---|
| ace | Ace | Pitcher | `#FF4B2B` fire red-orange |
| rico | Rico | Catcher | `#3A7BD5` steel blue |
| maya | Maya | Infielder | `#2ECC71` green |
| jax | Jax | Infielder | `#F39C12` orange-gold |
| kai | Kai | Outfielder | `#29B6F6` sky cyan |
| bruno | Bruno | Outfielder | `#8E44AD` purple |
| nova | Nova | Pitcher (unlockable) | `#FFE135` electric yellow |
| dex | Dex | Infielder (unlockable) | `#1ABC9C` teal |
| hana | Hana | Outfielder (unlockable) | `#FF6FA8` pink |

Enemy team ("The Wreckers"): gunmetal cloth `#2B2F36`, hazard orange accents `#FF7A1A`,
visor/eye glow emissive `#FF3D00`. Per-type accents are listed in section 4.

Card rarity colours: common `#B8C0CC`, uncommon `#5BD75B`, rare `#3A8DFF`, epic `#B45CFF`,
legendary `#FFAA1D`. Card category colours: offense `#FF5A36`, control `#7B6CFF`,
defense `#2EC4B6`, utility `#FFD23F`.

## 3. Characters (`assets/models/characters/<id>.glb`)

### 3.1 Shared armature (all humanoids, identical bone names and hierarchy)

```
root                      (at origin, on the ground; used for whole-body offsets)
└─ hips
   ├─ spine
   │  └─ chest
   │     ├─ neck
   │     │  └─ head
   │     ├─ shoulder.L ─ upper_arm.L ─ forearm.L ─ hand.L
   │     └─ shoulder.R ─ upper_arm.R ─ forearm.R ─ hand.R
   ├─ thigh.L ─ shin.L ─ foot.L ─ toe.L
   └─ thigh.R ─ shin.R ─ foot.R ─ toe.R
```

* Character's left = `.L` = Blender +X side when the character faces −Y.
* Standard defender height ≈ 1.80 m (stylised heroic proportions, head ≈ 1/6.5 of height).
  Different body types are made by scaling bone lengths/thickness, never by renaming bones.
* All defenders are right-handed: **ball in `hand.R`, glove on `hand.L`**.
* Every mesh is skinned to the armature (rigid accessories like caps, gloves, helmets,
  numbers, bats use 100 % weight to a single bone).
* The armature object must be named `Armature`; glTF export produces a `Skeleton3D`
  node in Godot.

### 3.2 Animations (exact names; all characters contain all animations of their group)

All clips are **in place** (no root translation in X/Z; vertical motion is allowed only where noted).
Frame rate 30 fps. "Event" times are in seconds from clip start; the game uses them to spawn balls/effects.

Common (defenders and enemies):

| name | length | loop | notes / event |
|---|---|---|---|
| `idle` | 2.0 s | yes | breathing, small weight shift |
| `run` | 0.70 s | yes | full run cycle, arms pump, feet plant on ground |
| `hit` | 0.35 s | no | flinch backwards, returns near idle |
| `stunned` | 1.2 s | yes | dazed wobble, hand to head |
| `defeat` | 1.2 s | no | knocked down; ends lying on back on the ground (hips may drop via root/hips) |
| `celebrate` | 1.0 s | yes | fist pump / hop |

Defender-only:

| name | length | loop | notes / event |
|---|---|---|---|
| `ready` | 1.6 s | yes | athletic fielding crouch, glove forward, subtle bounce |
| `throw` | 0.75 s | no | overhand throw; **release at 0.30 s**; ends in `ready`-like pose |
| `pitch` | 1.40 s | no | full wind-up with leg kick; **release at 0.85 s** |
| `catch` | 0.60 s | no | glove reaches up/forward; **catch at 0.25 s** |
| `special` | 1.20 s | no | power-up crouch then explosive throw/slam; **impact at 0.70 s** |
| `victory` | 2.0 s | yes | confident pose / cheering |
| `walk` | 1.0 s | yes | relaxed walk cycle (menus) |

Enemy-only:

| name | length | loop | notes / event |
|---|---|---|---|
| `sprint` | 0.55 s | yes | aggressive leaning sprint |
| `leap` | 0.80 s | no | crouch (0–0.15 s), airborne tuck, landing at 0.80 s (game moves the node vertically) |
| `swing` | 1.0 s | no | two-handed bat swing; **impact at 0.50 s** (bat holders only, but present on all enemies) |
| `slam` | 1.4 s | no | overhead two-handed ground slam; **impact at 0.90 s** |
| `taunt` | 1.5 s | no | after scoring a run |

### 3.3 Material names (used by the game for recolouring cosmetic uniforms)

Use Principled BSDF (base colour, roughness, metallic, emission). Name materials exactly:

`Skin`, `Hair`, `Eyes` (sclera white), `Iris`, `Jersey`, `JerseyTrim`, `Number`, `Pants`,
`Socks`, `Shoes`, `Belt`, `Cap`, `Glove`, `Undershirt` (accent colour), `Gear` (catcher pads,
helmets), `Metal`, `Glow` (emissive visor/eyes), `Bat`, `Cloth` (capes, hoods).

### 3.4 Roster

Defenders: `ace, rico, maya, jax, kai, bruno, nova, dex, hana`.
Enemies: `runner, sprinter, armored, jumper, swarmer, trickster, captain, slugger`.
Bosses: `iron_slugger, phantom_captain, grand_slammer`.

Enemies and bosses are exported at their real in-game size (e.g. swarmer ≈ 1.2 m tall,
slugger ≈ 2.4 m, grand slammer ≈ 4.2 m) so the game does not scale them.

### 3.5 Portraits

`assets/textures/portraits/<id>.png` — 512×512, transparent background, head-and-shoulders,
3/4 view, consistent key + rim light, rendered from the same models.

## 4. Enemy look summary

| id | silhouette | accent |
|---|---|---|
| runner | standard build, batting helmet with dark visor and glowing eye slit | hazard orange |
| sprinter | slim, aerodynamic helmet, lightning stripes | `#FFD400` |
| armored | bulky, steel shoulder/chest plates, riot-style helmet | steel `#8A939E` |
| jumper | springy legs, knee braces, spring-like shin guards | lime `#9BE22D` |
| swarmer | small (≈1.2 m), oversized helmet, scrappy | orange |
| trickster | lean, purple hood/mask, scarf/cape tails | `#9B5DE5` |
| captain | broad, crested helmet, cape, gold armband | crimson `#C0392B` + gold |
| slugger | huge (≈2.4 m), armoured, carries a giant bat | rust `#8B4513` + iron |
| iron_slugger | boss, ≈3.6 m, full iron plates, glowing molten seams | `#FF6A00` glow |
| phantom_captain | boss, ≈3.2 m, ghostly violet, tattered cape, glowing eyes | `#B45CFF` glow |
| grand_slammer | final boss, ≈4.2 m, black and gold armour, giant golden bat | gold `#FFC83D` |

## 5. Props (`assets/models/props/<name>.glb`)

Origins at ground centre, front facing +Z in Godot (−Y in Blender). Sizes are approximate targets.
See the props generator brief for the full list. Special node names the game relies on:

* `gate.glb`: child nodes `DoorL`, `DoorR` (pivot at their outer hinge), `Beacon` (emissive).
* `scoreboard.glb`: a mesh named `Screen` (UV 0..1 covering the display, material `Screen`).
* `banner_pole.glb`: a mesh named `Banner` (subdivided ≥ 12×8, UV 0..1, material `Banner`).
* `light_tower.glb`: emissive material named `LampEmissive`; an empty named `LightAnchor`
  at the centre of the lamp bank.

## 6. Audio (`assets/audio/`)

* SFX: `assets/audio/sfx/<name>.wav`, 44.1 kHz, 16-bit, mono, peak ≈ −3 dBFS, no DC offset,
  no clicks (fade in/out).
* Music: `assets/audio/music/<name>.ogg` (Vorbis), 44.1 kHz stereo, seamless loops.
* Ambience: `assets/audio/ambience/<name>.ogg`, stereo seamless loops.

## 7. 2D art (`assets/textures/`)

* Logo: `assets/textures/logo/logo.png` (transparent, ~2048 px wide) and `logo_small.png`.
* Card art: `assets/textures/cards/<card_id>.png` (512×384 illustration, no frame — the game draws frames).
* Icons: `assets/textures/icons/*.svg` (white glyphs on transparent, the game tints them).
* App icon: `icon.svg` at the project root, plus `assets/textures/logo/icon.ico` for Windows.
