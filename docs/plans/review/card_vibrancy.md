# Review: card effect vibrancy (Update 8, Stream V)

Scope: all 44 ability cards from the **real battle camera** (default view: focus (0, −1.5), pitch −58°,
50 m), at wind-up, peak and linger. Question per card: is the colour saturated and distinct per
category (offense hot reds and oranges, control violets and blues, defense teals and greens,
utility golds), does it glow through the tonemapper, does it read from 50 m, and is there a clear
anticipation → impact → linger?

Evidence: `tools/art/vfx/showcase.sh` on the Practice Field, `--cam-view=0,-1.5,0,-58,50`,
640×360, `--fixed-fps 10`, `--vfx-delay=0.3 --vfx-gap=0.5`, frames at 0.35 / 0.8 / 1.7 s after the
cast (longer cards carry their own times, e.g. Grand Slam Barrage 0.6 / 1.4 / 3.2). Contact sheets
crop to the runner pack (1.4× zoom) or to the whole field for field-wide cards.
Software rendering (llvmpipe) shared with three other streams made one full pass take about
an hour, so these are the only resolution and frame rate that fit the time box.

Scores 1–5: **V** vibrancy (saturated, category-true colour that glows), **I** impact (punch,
anticipation → impact → linger, reads from 50 m).

## Environment check (`src/battle/stadium_builder.gd`)

Filmic tonemapper (white 6.0), glow on with **soft-light** blend, intensity 0.7, HDR threshold 1.35,
levels 1–3; colour adjustment saturation 1.12 (1.2 at night). Consequences:
* Only pixels above 1.35 bloom, and soft-light bloom is gentle: emission must be HDR (2–4×) to
  glow at all, and the bloom adds lightness more than colour.
* Filmic compresses each channel, so a bright colour with strong minor channels (e.g. the old
  gold `(1.0, 0.82, 0.3)` × 2.4) rolls off toward pale yellow-white. Saturated colours with low
  minor channels survive. This is why most effects read white or pastel.
* Additive effects over the bright daytime dirt and grass wash out to pastel; a saturated colour
  has to be *mixed over* the ground (alpha blend with HDR colour), not added, to stay saturated.

The environment itself is not changed (not a Stream V file); the effects were built for it instead.

## Scores

Before = the build at the start of Update 8. After = this pass.

| Card | Cat. | Rarity | V before | I before | V after | I after | Notes (before → after) |
|---|---|---|---|---|---|---|---|
| Heat Wave | off | R | 5 | 5 | 5 | 5 | Fire wall; already the best. + cooling ember light along the strip. |
| Power Throw | off | C | 3 | 3 | 4 | 4 | Gold POW, then only the smoke trail → red-orange comet, white-hot core, halo, ground light, scorch. |
| Splitter | off | U | 2 | 2 | 4 | 4 | Pale white ring, nothing lingers → scarlet burst, fan of rays, red ground light, scarlet pops. |
| Grand Slam Barrage | off | L | 5 | 5 | 5 | 5 | + Legendary screen accent, fire light under every impact. |
| Grand Relay | off | E | 2 | 3 | 4 | 4 | Thin pale gold threads → thicker solar-orange links with a glow sheath, punch + ground light per strike. |
| Power Catch | off | R | 3 | 4 | 4 | 4 | Violet (off-category) → crimson-magenta meteor slam; still distinct from fire. |
| Thunderbolt | off | E | 2 | 3 | 4 | 4 | Thin white bolts, tiny impact → volt-yellow core, halo and pooled light; chain jumps glow. |
| Called Shot | off | R | 3 | 3 | 4 | 4 | Pale beam + thin ring → solar beam, landing light during the fall, bigger hot impact. |
| Line Drive | off | C | 1 | 2 | 3 | 3 | Almost invisible → blaze-orange crack, impact punch and ground light. Still a small, fast card. |
| Bean Ball | off | C | 2 | 2 | 3 | 3 | BEANED! text carried it → scarlet POW, halo and ground light. |
| Around the Horn | off | R | 4 | 4 | 4 | 4 | Gold arcs base to base already read; + light at each base and a punch at each strike. |
| Grand Salami | off | L | 3 | 3 | 4 | 4 | Giant ball small at 50 m → ball 1.6 m (was 1.25, visual only), Legendary accent, glowing trail. |
| Curveball | ctl | C | 3 | 3 | 4 | 4 | Lavender ring → deep violet vortex, punch and pooled violet light. |
| Knuckleball | ctl | U | 3 | 3 | 4 | 3 | + violet punch and ground light under the swirl. |
| Shadow Change | ctl | E | 5 | 4 | 5 | 5 | Violet vortex already strong; + hot core punch, pooled light, glow on each victim. |
| Time Out | ctl | L | 3 | 5 | 3 | 5 | Giant white clock: huge impact, colour drained by design. + ice flare and Legendary accent. |
| Changeup | ctl | C | 2 | 3 | 4 | 3 | Pale lavender waves wash the field white → saturated indigo waves (kept translucent) and motes, indigo light at the plate. |
| Pickoff | ctl | R | 2 | 2 | 3 | 3 | Teal (off-category), tiny → electric ice-blue snap, reticle and punch. |
| Rundown | ctl | R | 2 | 2 | 3 | 3 | Pale white bases → indigo bases with pooled light, punch on each tag. |
| Rain Delay | ctl | E | 2 | 3 | 3 | 3 | Grey and pale → cold ice flare over the field, blue light on each shut gate. |
| Intentional Walk | ctl | C | 2 | 2 | 3 | 3 | Mint (off-category) → indigo; punch and ring. |
| Lockdown | def | R | 4 | 4 | 4 | 4 | Rune seal + cage read; + aqua punch and pooled light under the cage. |
| Frost Field | def | U | 3 | 4 | 4 | 4 | Pale disc → aqua cast punch, cold light over the disc, sparks thrown out. |
| Wall of Dirt | def | C | 2 | 2 | 3 | 3 | Only a dashed ring at the cast → emerald slam, ring, dirt thrown sideways. |
| Base Shield | def | R | 3 | 3 | 4 | 3 | + aqua punch at the plate. |
| Bunt Trap | def | C | 2 | 2 | 3 | 3 | Net hidden by the runners → teal punch and ground light that lasts ~1.8 s. |
| Diving Catch | def | R | 2 | 2 | 3 | 3 | Thin pink line → pink dash with a teal landing punch and light. |
| Tag at the Plate | def | C | 3 | 3 | 4 | 4 | + teal light pooled on the plate, punch on the tag. |
| Perfect Game | def | L | 5 | 5 | 5 | 5 | Gold diamond; + Legendary accent, light at each base, punch per strike. |
| Infield Fly | def | U | 2 | 3 | 3 | 3 | White ring → teal-white ring, teal cast and catch punches. |
| Golden Glove | def | R | 3 | 3 | 4 | 4 | Thin gold ring → gold punch at the glove, pooled gold light, big snag punch. |
| The Shift | def | U | 3 | 3 | 4 | 3 | + teal punch at the spot, light under each shifted defender. |
| Twin Play | utl | R | 3 | 3 | 4 | 3 | Thin green lines → lime links, flare and pooled light under each defender. |
| Field Vision | utl | C | 3 | 3 | 3 | 3 | Cyan radar rings per defender read; + sky flare and light under each defender. Rings are large but fast. |
| Diamond Aura | utl | E | 2 | 3 | 4 | 4 | Pale white-blue diamond → gold gem, gold beam and pooled gold light (utility gold; Rally Cry moved to amber). |
| Rally Cry | utl | U | 3 | 3 | 4 | 3 | Gold wave → warm amber wave, flare over each defender, light under each. |
| Magnet Glove | utl | U | 4 | 4 | 4 | 4 | Red field with tethers already read; + amber punch and a light pool for the pull. |
| Sky Hook | utl | R | 2 | 2 | 3 | 3 | Thin arc → sky-blue punch and ground light at the hook. |
| Bullpen Call | utl | U | 3 | 3 | 4 | 3 | + lime punch and light at the mound where the cards pop out. |
| Hot Corner | utl | U | 4 | 4 | 4 | 4 | + fire punch at the eruption and on every hot throw. |
| Seventh-Inning Stretch | utl | E | 3 | 3 | 4 | 3 | + gold punch and light at the mound; fireworks unchanged. |
| Momentum | utl | U | 2 | 2 | 3 | 3 | Small cyan ring → sky punch and light at the plate, a flare on each energy gain. |
| Relief Pitcher | utl | E | 3 | 3 | 4 | 3 | + lime punch where the reliever arrives and in his pitching circle. |
| Instant Replay | utl | L | 3 | 3 | 4 | 4 | REPLAY text carried it → legend-ramp punch (gold into magenta), sky light pool, Legendary accent. |

**Summary.** Before: 36 of 44 cards scored under 4 on vibrancy (mean V 2.9, I 3.1); the weakest were
Line Drive, Splitter, Thunderbolt, Grand Relay, Pickoff, Rundown, Bunt Trap, Wall of Dirt, Diving Catch,
Sky Hook and Momentum, all small and white or pale at 50 m. The 12 Update 7 cards averaged V 2.6.
After: no card under 3; mean V 3.8, I 3.6; Update 7 cards V 3.5. Still at 3 (14): Line Drive, Bean
Ball, Pickoff, Rundown, Rain Delay, Intentional Walk, Wall of Dirt, Bunt Trap, Diving Catch, Infield
Fly, Field Vision, Sky Hook, Momentum and Time Out (V; its white clock is the design). These are
small, single-target or long-lasting cards where more size would cover the runners; their remaining
weakness is scale at 50 m, not colour.

Evidence (before/after contact sheets, wind-up / peak / linger per card) and the Legendary accent
frames are listed in the stream report. Grand Relay, Changeup and Grand Salami were re-captured after
a second tweak; Changeup's waves were made a little more translucent after that capture, and the
ground light was made lighter for big radii (Diamond Aura, Rain Delay) after the utility capture.

## What changed (shared)

* **Category palette** (`card_fx.gd`: `PALETTE`, `CATEGORY_RAMP`, `CARD_RAMP`): 18 colour ramps
  [white-hot core, tint, saturated body, deep edge]. Offense: fire, blaze, comet, scarlet, crimson,
  volt, solar. Control: violet, indigo, ice. Defense: teal, emerald, aqua. Utility: gold, amber, lime,
  sky. Legendary accent: legend (gold into magenta into violet). Every card has its own entry;
  the cast pop uses the category's family entry, so the family reads at the moment of the cast.
* **Colour-over-life particles** (`vivid_fx.gd`, `fx_particle_ramp.gdshader`): five pooled systems
  (`v_flare`, `v_glow`, `v_spark`, `v_ember`, `v_mote`) that sample their ramp row by age: born
  white-hot in HDR (2–4×, above the 1.35 glow threshold), then the saturated body, fading into the
  deep edge. The row rides in the particle colour's alpha, so one system serves every card.
* **Light pooled on the ground** (`ground_glow`, `fx_ground_glow.gdshader`): a hot centre, soft
  halo and rayed rim that walk the ramp as they cool, mixed over the ground (not added) so they stay
  saturated on daytime dirt and grass; about 1–2 s, lighter for big radii.
* **`punch()`**: the shared impact: core flare (~0.1 s), saturated halo, ramp sparks and embers, a
  0.24 s flash ring on the ground, and the ground light. Used at the impact of almost every card;
  the old white `impact_flash` sparks were reduced where punch replaces them.
* **Legendary accent** (`legend_accent`, `screen_accent`, `fx_screen_accent.gdshader`): radial light
  streaks from the impact and coloured screen edges, 0.45 s, plus a brief bloom lift; on Grand Slam
  Barrage, Time Out, Perfect Game, Grand Salami and Instant Replay. A CanvasLayer at layer 5 (the HUD
  is 10) with `MOUSE_FILTER_IGNORE`, kept clear of the impact point.
* **Wind-up**: special casts now pool light under the caster and gather a glow in the hand in the
  card's colour; quick throws flare in the hand.
* **Settings**: counts go through the particle-scale setting; `reduce_flashes` dims the flare
  system (energy 0.8 instead of 1.5, birth boost 0.6 instead of 2.6), the ground light (0.9 instead
  of 1.5) and the screen accent (35 %, no streaks, no bloom lift). No new screen shake beyond Wall of
  Dirt's small 0.08.

## What changed (per card, visual only)

* Off-category colours moved into their family: Power Throw gold → comet red; Splitter white →
  scarlet; Power Catch violet → crimson; Line Drive white → blaze; Pickoff teal → ice blue;
  Intentional Walk mint → indigo; Rundown pale lavender → indigo; Infield Fly white → teal-white;
  Diamond Aura pale blue → gold; Rally Cry gold → amber (so it no longer matches Diamond Aura or
  Field Vision). Projectile and reticle colours in `card_effects.gd` follow.
* New cast visuals for Frost Field and Wall of Dirt (`frost_field_cast`, `wall_cast`, called from
  `card_effects.gd`); their zone and wall are unchanged.
* Grand Relay: thicker links with a glow sheath. Grand Salami: the ball is drawn 1.6 m (was 1.25);
  its hit radius is unchanged; the fire trail glows hot every other stretch for under 2 s.
* Every card listed in the table got `punch()` at its impact and pooled light where it lands.

No rules, numbers or timings changed; sounds are the existing ones.

## Known issues

* The showcase does not clear lingering visuals between cards, so some frames show the previous
  card (Salami's fire trail in Curveball/Knuckleball, Time Out's clock in Changeup, Rain Delay's rain
  and grey grade in Intentional Walk). Both passes have the same contamination.
* Time Out and Field Vision still put large pale rings over the field for about a second (design
  from Update 5/6); not changed here.
* The comet trail of Power Throw draws as a dark smoke smear (projectile trail, Stream A's file).
* Captures are 640×360 from software rendering; HDR bloom is weaker there than on a GPU.


## Verification

* `tools/check_scripts.sh`: 86 scripts, 0 failed. System suite: 1768 checks, 0 failed.
* Cards UI section (1600×900, `--ui-test-section=cards`): 0/175 dead points, 0 dropped fast clicks,
  5 checks, 0 failed.
* Before/after contact sheets for all 44 cards (wind-up, peak, linger) from the battle camera, plus
  Legendary accent frames at 0.12 / 0.25 / 0.4 s.
* The showcase logs "Lambda capture at index 0 was freed" after Magnet Glove when the field is
  cleared between cards (its tethers outlive the runners); the same lines appear with the old code.
