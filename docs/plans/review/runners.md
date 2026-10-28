# Update 6 review: runners and bosses (Stream R)

Scope: the 8 runner types, the Base Stealer and the 3 bosses (`tools/blender/characters/enemies.py`,
`roster.py`, `anim.py`), their GLBs and portraits.

Measured with `tools/blender/characters/review_frames.py` (now with an enemy clip set: idle, run, sprint,
walk, hit, defeat, leap, swing, slam, taunt, celebrate), rendering every type from the battle camera angle
(52° down) and close 3/4 front views, and with the game's own battle captures.

Priority = Severity (1–4) × Reach (1–4) ÷ Effort (S=1, M=2, L=3).

## Findings (before)

| # | Finding | Sev | Reach | Effort | Prio | Status |
|---|---|---|---|---|---|---|
| 1 | All runners are faceless dark mannequins (a black head with a glowing visor slit) built with the old SDF sculpt pipeline: lumpy, faceted surfaces, small heads, thin limbs. They look like a different game from the Update 2 defenders | 4 | 4 | L | 5.3 | fixed: rebuilt in the hero pipeline |
| 2 | From the battle camera every runner is a dark grey blob; the type colour is only a thin helmet stripe and the socks, so Runner / Swarmer / Sprinter / Jumper / Trickster are hard to tell apart at a glance | 4 | 4 | M | 8.0 | fixed: helmet / cap in the type colour, type silhouettes |
| 3 | Weak per-type silhouettes: Sprinter, Jumper and Runner share one body; the Trickster's hood and scarf read as a generic ninja; the Captain's cape is the only cue | 3 | 4 | M | 6.0 | fixed |
| 4 | Base Stealer is the Runner recoloured (portrait hue-shifted from the Runner's): no "sliding" identity | 2 | 3 | S | 6.0 | fixed: own model (sliding mitts, pink helmet, plum jersey) |
| 5 | Iron Slugger and Siege Slugger look almost the same (grey plates, dark helmet); the Iron Slugger's identity (iron armour) does not come through | 3 | 2 | M | 3.0 | fixed: full iron, face cage, glowing seams, spiked iron bat |
| 6 | All types run with the same cycle | 2 | 4 | S | 8.0 | fixed: per-type gaits |
| 7 | Hit flinch is small (≈10° chest) and hard to see from the battle camera | 2 | 4 | S | 8.0 | improved (×1.4, heavy types ×1.1) |
| 8 | Boss bat swing: the coil lasts 0.2 s, the wind-up is easy to miss | 2 | 2 | S | 4.0 | improved: deeper coil held 0.30–0.40 s, same impact time |
| 9 | Portraits: dark heads on dark backgrounds, faceless, read poorly in the threat panel | 3 | 3 | S | 9.0 | fixed: re-rendered head-and-shoulders portraits with faces and coloured helmets |
| 10 | "Out" fall | 1 | 4 | S | — | kept: the existing backward fall reads well; the game adds the knock-back, burst and shrink |

## What changed

* **Pipeline:** `enemies.EnemyHero` extends the defenders' `hero.Hero` (same head, face, body, uniform,
  shoe and decal code) and adds the opponents' gear: batting helmet with ear flaps, crown stripe and
  ear holes; aero helmet; stocking cap with a floppy tail and pompom; domino mask; face cage; horns;
  pauldrons (rigid blend between shoulder and upper arm), chest / back plates, gauntlets, greaves, knee pads,
  springs, track spikes, sliding mitts, armband, capes and bats (rigid to `hand.R`). The old SDF enemy
  builder was removed from `build_characters.py`.
* **Kit:** shared Wreckers uniform (gunmetal jersey, grey pants, white-outlined numbers) with the type
  colour on the helmet / cap, piping, socks and number, so the gameplay colour cues are unchanged.
* **Types:**
  * Runner (orange): batting helmet, eye black, cocky grin.
  * Sprinter (yellow): lean, long legs, aero helmet, wraparound shades, bare forearms, wristbands,
    neon-yellow track spikes.
  * Armored (steel): bulky, steel helmet with face cage, pauldrons, chest and back plates, gauntlets,
    greaves, scowl.
  * Jumper (lime): long legs, headband and spiky ginger hair, lime sleeves, big knee pads, coil springs.
  * Swarmer (orange): 1.2 m, huge head and helmet, big eyes, gremlin grin.
  * Trickster (purple): lean, long arms, purple stocking cap with a floppy tail, domino mask, sly smirk
    and side glance.
  * Captain (red): red captain's cap, gold epaulettes and armband, cape, beard.
  * Siege Slugger (brown): 2.4 m, beard, spiked pauldrons, chest plate, gauntlets, giant spiked bat.
  * Base Stealer (magenta): lean, magenta helmet, plum jersey, padded sliding mitts.
  * Iron Slugger (boss): iron helmet with cage, glowing orange eyes, three-layer spiked pauldrons, chest
    and back plates with glowing seams, gauntlets, greaves, spiked iron bat.
  * Phantom Captain (boss): pale lavender skin, white hair, glowing violet eyes, dark captain's cap,
    glowing trim and armband, tattered translucent cape.
  * Grand Slammer (boss): 4.2 m, gold horned helmet, gold armour, red cape, huge golden bat, glowing eyes.
* **Animation** (same rig, clip names, lengths and event times): per-type run gaits (`anim.GAITS`:
  sprinter, heavy stomp, bouncy, scurry, sneaky low run with trailing arms, upright captain, low stealer,
  floating phantom), stronger hit flinch, a held coil in the bat swing. Stride lengths follow the leg
  length as for the defenders.
