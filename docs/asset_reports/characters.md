# Characters — build report

**Status: ace+runner ready** (GLBs built, imported and checked in Godot 4.7.2).
The remaining characters and the portraits follow; this file is updated as they land.

## Rebuild

```
/opt/tools/bpyenv/bin/python tools/blender/characters/build_characters.py [ids...] [--no-portraits] [--no-glb]
```

No ids = all 20. Output: `assets/models/characters/<id>.glb`, `assets/textures/portraits/<id>.png`,
plus a machine-readable summary in `docs/asset_reports/characters_build.json`.
Everything is procedural (numpy SDF sculpting + surface nets + Blender decimation), deterministic, no external assets
(the jersey numbers use `assets/fonts/RussoOne-Regular.ttf` from the repo).

## Verified Godot node structure (ace, runner)

```
<id> (Node3D)
├─ Armature (Node3D)
│  └─ Skeleton3D (Skeleton3D)          path: Armature/Skeleton3D
│     └─ Body (MeshInstance3D, skinned, one surface per material)
└─ AnimationPlayer                       path: AnimationPlayer
```

Bones (22, identical in every file): root, hips, spine, chest, neck, head, shoulder.L/R, upper_arm.L/R,
forearm.L/R, hand.L/R, thigh.L/R, shin.L/R, foot.L/R, toe.L/R (hierarchy exactly as ASSET_SPEC 3.1).
Animation tracks are `Armature/Skeleton3D:<bone>` rotation tracks plus a `hips` position track.

## Animations (names/lengths as imported in Godot)

Defenders: idle 2.0, run 0.70, hit 0.35, stunned 1.2, defeat 1.2, celebrate 1.0, ready 1.6, throw 0.75
(release 0.30), pitch 1.40 (release 0.85), catch 0.60 (catch 0.25), special 1.20 (impact 0.70), victory 2.0, walk 1.0.

Enemies/bosses: idle, run, hit, stunned, defeat, celebrate, sprint 0.55, leap 0.80 (landing 0.80), swing 1.0
(impact 0.50), slam 1.4 (impact 0.90), taunt 1.5, **walk 1.0** (added per lead request).

**Loop flags are not stored in glTF** — set `Animation.loop_mode = LOOP_LINEAR` in code (or in the import
settings) for: idle, run, stunned, celebrate, ready, victory, walk, sprint. Their first and last keys are identical.

In-engine check (Godot 4.7.2, Forward+): ace idle / throw at 0.30 s (release) / run mid-stride, runner idle / run / swing at 0.50 s:

![ace and runner in Godot](img/godot_ace_runner.png)

(Work in progress — full tables, triangle counts, deviations and limitations below once all characters are built.)
