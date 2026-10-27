# Update 5 review: characters (Stream C)

Scope: the nine defenders (`tools/blender/characters/hero*.py`, `anim.py`), their GLBs and portraits.
Runners and bosses were not changed (no defect found that needed a rebuild).

Measured with two new tools:

* `tools/blender/characters/review_frames.py` renders key frames of every clip (idle, ready, run, throw,
  catch, celebrate, hit, pitch, special, victory) from the battle camera angle, close 3/4 front and back
  views, and close-ups (`--focus`), as labelled contact sheets.
* `tools/blender/characters/check_layers.py` measures uniform layering on the exported GLBs: every
  inner-layer vertex that is covered in the rest pose (jersey hem under the waistband, undershirt arm under
  the sleeve, sock under the cuff, neck under the collar) is anchored to the covering triangle, and its
  signed distance to it is tracked through every frame of every clip. A positive value = poke-through.

Priority = Severity (1–4) × Reach (1–4) ÷ Effort (S=1, M=2, L=3).

## Findings

| # | Finding | Sev | Reach | Effort | Prio | Status |
|---|---|---|---|---|---|---|
| 1 | Undershirt arm pokes through the jersey sleeve (hem and armpit) whenever the arm is raised or across the body: 2–4 cm on all nine in throw / pitch / special / catch / ready, 6.4 cm on Bruno; visible as coloured spikes on the sleeve from behind | 3 | 4 | M | 6.0 | fixed |
| 2 | Bruno's tucked jersey is wider than the waistband at the back: the pants poke through the jersey hem as white spikes in every pose; Jax / Rico / Bruno jersey pokes 2–3 cm through the waistband in throw / pitch | 3 | 3 | M | 4.5 | fixed |
| 3 | Bruno / Maya elbow undershirt: the forearm skin pokes through the cuff at the elbow (jagged skin-coloured teeth) | 2 | 3 | S | 6.0 | fixed |
| 4 | Back numbers: the gold outline was broken on "4" and "5" (Jax 34, Bruno 44, Maya 5: missing below the crossbar / top bar, stray slivers beside it) because the outline offset folded over the glyph's open counter; the white fill of the "4" had a hole at the crossbar (scanfill on a concave loop with collinear runs) | 2 | 3 | S | 6.0 | fixed |
| 5 | Throw: little anticipation and a short follow-through (arm stops in front of the body, chest barely bends) | 2 | 4 | S | 8.0 | improved |
| 6 | Catch: the glove just drifts back after the catch, no impact | 2 | 4 | S | 8.0 | improved ("pop") |
| 7 | Celebrate: weak hop; the glove arm sticks straight out to the side (odd silhouette from the battle camera) | 2 | 3 | S | 6.0 | improved |
| 8 | Idle (menus, Team screen) and ready (battle) look static: only breathing | 1 | 4 | S | 4.0 | improved |
| 9 | Rico's socks under the knee pants (Update 3 fix never confirmed) | 3 | 3 | S | — | confirmed OK: close back and side renders of ready / run show no sock through the cuff. The layer check reports ~5.5 cm at the back of the knee in deep crouches; that is the thigh part of the pants folding into the calf inside the knee crease (self-intersection hidden in the fold), not the sock showing |
| 10 | Back of the neck pushes 2.5–5 cm past the collar's top edge when the head tilts back (ready, catch, special) | 1 | 1 | M | 0.5 | open: hidden under the cap / hair from every game camera; not visible in the close renders |

## Layering numbers (worst poke-through over the gameplay clips, cm; before → after)

| | Ace | Rico | Maya | Jax | Kai | Bruno | Nova | Dex | Hana |
|---|---|---|---|---|---|---|---|---|---|
| sleeve | 3.2 → 0.9 | 3.7 → 1.0 | 2.3 → 0.4 | 3.8 → 1.1 | 2.2 → 0.5 | 6.4 → 1.3 | 2.6 → 0.5 | 2.0 → 0.5 | 2.3 → 0.3 |
| waist | 0.1 → 0 | 3.1 → 0 | 0 → 0 | 2.1 → 0 | 0.2 → 0 | 3.0 → 0 | 0 → 0 | 0.2 → 0 | 0 → 0 |
| collar (#10) | 2.9 → 2.7 | 3.3 | 2.5 | 3.3 | 2.7 | 5.3 | 3.0 | 2.9 → 2.6 | 2.8 |
| cuff | 0.1 | 5.6 (crease, see #9) | 0.1 | 0.4 | 0.3 | 0.4 | 0.1 | 0.1 | 0.1 |

The remaining ~1 cm on the sleeves is in the blend band just below the hem (skin stretching over the elbow
of a fully extended throwing arm), not visible in the renders.

## What changed

* **Shared skin weights for layered clothing** (`hero.share_weights`): the undershirt arm under the jersey
  sleeve takes the sleeve's weights and blends back to its own just below the hem; the waistband takes the
  jersey's weights down to the jersey hem; the forearm skin under an elbow cuff takes the cuff's weights;
  the neck base takes the jersey's weights inside the collar.
* **Hidden geometry pulled in**: the tucked jersey is pulled 1.4 cm inside the pant surface below the
  waistband (`tuck_torso`) and its hem is 5.5 cm shorter (still 7 cm under the waistband, clear of the hip
  crease); the forearm skin hidden under an elbow cuff is 16 % thinner.
* **Outline offsets untangled** (`geo.untangle_loop`): offset loops are split at self-intersections and the
  inverted swallowtails dropped, so number outlines (and cap emblem outlines) fill correctly; single-loop
  decals are triangulated by ear clipping (`geo.ear_clip`, scanfill kept for loops with holes), which fixes
  the hole in the "4"; the number fill sits 1.4 mm (× scale) higher above its outline so the outline's
  flatter triangles cannot show through it on round backs (Bruno).
* **Clips** (same names, lengths and event times; release 0.30 / 0.85, catch 0.25, impact 0.70 unchanged):
  * throw / special: deeper sink and coil at the cock (shoulders turn past the hips), glove arm reaches for
    the target and pulls into the chest at release, shoulders rotate through, chest bends over, throwing hand
    finishes toward the left knee, back heel rises higher;
  * catch: small gather, glove reaches the ball at 0.25 and snaps back with the impact (wrist flick, chest and
    head jolt, hips dip), free hand covers the ball;
  * celebrate (defenders): deeper crouch, higher jump, squash on landing, fist punched up at the top and
    yanked down on landing, glove arm thrown up with it;
  * idle (defenders): looks around the field (right, then left) with the chest following, a small nod,
    more weight shift; ready: slow side-to-side scan of the head and chest.

Foot slide and loop seams stay 0.0 on every clip (`verify_characters.py`).
