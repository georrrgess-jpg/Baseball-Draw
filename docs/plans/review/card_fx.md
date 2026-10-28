# Review: card effects (Update 6, Stream V)

Scope: all 32 ability cards from the battle camera, at wind-up, peak and about one second later;
the Shielded elite bubble; the hand's cast flourish; card faces at hand size.

Evidence: frames from the Practice Field showcase (`--vfx-showcase=<card>@t1/t2/t3`, 640×360,
`--fixed-fps 15`, `--vfx-delay=0.5 --vfx-gap=0.8`). Times are per card so the frames land on
wind-up, peak and linger (linked "special" casts land ~0.55 s after the click, throws ~0.25 s).
Runners stand in a tight pack on the first-base path, as in Update 5's captures. In the
showcase the linked defender is often not on the field, so linked cards fire from home plate
at 75 % power (as in a real game without that defender).

Scores 1–5: **R** readability (is it obvious what happened and where), **S** satisfaction
(punch, timing, follow-through), **U** uniqueness (doesn't look like another card).

## Scores (before)

| Card | Cat. | R | S | U | Sum | Notes |
|---|---|---|---|---|---|---|
| Heat Wave | off | 5 | 5 | 5 | 15 | Fire wall races out, scorched strip and embers linger. Best in set. |
| Grand Slam Barrage | off | 5 | 5 | 5 | 15 | Burning zone, falling fireballs, craters. |
| Time Out | ctl | 5 | 5 | 5 | 15 | Giant stopwatch, colour drains. |
| Perfect Game | def | 5 | 5 | 5 | 15 | Gold diamond, pillars, bolts, tag ring. |
| Thunderbolt | off | 5 | 4 | 5 | 14 | Sky bolt + forked chain. |
| Lockdown | def | 5 | 4 | 5 | 14 | Rune seal snaps, light cage stays. |
| Shadow Change | ctl | 5 | 4 | 4 | 13 | Violet vortex, runners hurled back. |
| Base Shield | def | 5 | 4 | 4 | 13 | Hex dome rises, pips stay. |
| Magnet Glove | utl | 4 | 4 | 5 | 13 | Red magnetic field with tethers. |
| Grand Relay | off | 4 | 4 | 4 | 12 | Gold links defender to defender, bolts to the leaders. |
| Frost Field | def | 4 | 4 | 4 | 12 | Ice disc, shards, snow. |
| Diamond Aura | utl | 4 | 4 | 4 | 12 | Beam + diamond plate under the defender. |
| Tag at the Plate | def | 4 | 4 | 4 | 12 | Teal plate, glove icon, TAGGED OUT. |
| Power Throw | off | 4 | 4 | 3 | 11 | Comet + gold ring; gold impact close to Called Shot. |
| Called Shot | off | 4 | 4 | 3 | 11 | Reticle, sky drop, gold burst; gold again. |
| Wall of Dirt | def | 4 | 3 | 4 | 11 | Wall rises; little impact at the moment of the cast. |
| Curveball | ctl | 4 | 3 | 3 | 10 | Lavender vortex; a lighter Shadow Change. |
| Diving Catch | def | 3 | 3 | 4 | 10 | Pink dash; long thin line from home when Hana is absent. |
| Seventh-Inning Stretch | utl | 3 | 3 | 4 | 10 | Fireworks are high and far; the draw itself is not shown. |
| Sky Hook | utl | 3 | 3 | 4 | 10 | Hook arc is thin until the yank. |
| Twin Play | utl | 3 | 3 | 3 | 9 | Green sweep + links; quiet after 0.5 s (by design, Update 5 A5). |
| Field Vision | utl | 3 | 3 | 2 | 8 | Gold rings per defender; reads like Rally Cry. |
| Rally Cry | utl | 3 | 3 | 2 | 8 | Gold wave + rings; reads like Field Vision. |
| Hot Corner | utl | 3 | 2 | 3 | 8 | Burst, then only a thin ring; hot throws look like normal throws. |
| Changeup | ctl | 3 | 3 | 1 | 7 | Reuses Time Out's clock and big rings. |
| Power Catch | off | 2 | 3 | 3 | 8 | Warning circle nearly invisible during the long lob; small impact. |
| Splitter | off | 3 | 2 | 2 | 7 | White mid-air ring; split balls tiny; nothing lingers. |
| Line Drive | off | 2 | 3 | 2 | 7 | Fast, small white pop; nothing left after 1 s. |
| Bullpen Call | utl | 2 | 2 | 3 | 7 | Tiny card/energy icons over the mound from a 50 m camera. |
| Pickoff | ctl | 2 | 2 | 3 | 7 | Reticle and snap throw too thin to see; result only in a small label. |
| Bunt Trap | def | 2 | 2 | 2 | 6 | A small white puff; the trap spot does not read. |
| Knuckleball | ctl | 1 | 2 | 3 | 6 | Impact nearly invisible; "???" tiny and short. |

Also reviewed:
* **Shielded elite bubble:** a hemisphere scaled 0.42 h wide × 0.72 h tall around the feet: a
  tall amber egg. Readability 2.
* **Hand cast flourish:** the card rises, shrinks to the target and pops a white ring. Generic:
  no category colour until the ring, no trail, untargeted cards fly to an arbitrary spot
  above the hand.
* **Card faces (hand size, 146×204 at 1600×900; collection):** names fit (auto-shrink),
  rarity pill and gem read, foil sweep is calm. The refusal state was only a red wash.

## Fix list (ranked by sum, plus the known items)

| # | Item | Status |
|---|---|---|
| 1 | Knuckleball impact | **Fixed** |
| 2 | Bunt Trap cast | **Fixed** |
| 3 | Pickoff reticle and snap | **Fixed** |
| 4 | Bullpen Call (known) | **Fixed** (Seventh-Inning Stretch shares the drawn-card visual) |
| 5 | Changeup uniqueness | **Fixed** |
| 6 | Power Catch telegraph and impact | **Fixed** |
| 7 | Hot Corner linger + hot throws (known) | **Fixed** |
| 8 | Shielded bubble egg (known) | **Fixed** |
| 9 | Hand cast flourish (known) | **Fixed** |
| 10 | Line Drive linger | Open: needs a longer-lived landing mark (skid line + crater). |
| 11 | Splitter | Open: split balls need bigger glints and a fan-shaped ground mark. |
| 12 | Field Vision vs Rally Cry | Open: both gold rings; Field Vision could move to a cooler colour (eye/radar cyan) or Rally Cry to orange. |
| 13 | Gold family (Power Throw / Called Shot / Grand Relay / Perfect Game) | Open, low: fine individually; Called Shot is the most distinct (sky drop). |

## What changed

* **Hot Corner** (`card_fx.hot_corner`, `_hot_release`): anticipation (flame streaks rush into the
  defender, ground ring implodes), impact at 0.16 s (flame ring, fire column, heat haze, scorch,
  pierce icon, "RED HOT!"), then for the whole buff a burning ring with a flame lick every
  ~0.3 s, a torch in the throwing hand, embers, and a fire flare + ring + sparks at the release
  of every throw that defender makes (detected from the defender's release countdown; the throws
  already carry the fire trail and the "hot" punch-through impact).
* **Bullpen Call** (`card_fx.bullpen_call`, `flying_card`): the bullpen stream is thicker; at the
  mound the drawn cards pop out as little cards (category-coloured frame, the card's own art, a
  dark text panel; 2.5 × 3.6 m on screen) that hang for a beat and fly down to the hand; a big
  energy bolt and "+N ENERGY". `card_effects` passes the drawn ids (hand before/after the draw;
  visual only). **Seventh-Inning Stretch** shows its drawn cards and energy the same way.
* **Shielded bubble** (`vfx.make_runner_bubble`, `fx_dome.gdshader` mode 2, `enemy.gd` 2 lines):
  a full sphere, uniformly scaled (0.6 h) and centred on the body; a clear glossy shell (bright
  amber rim, faint hex cells only toward the edge, a white glint, slow sheen).
* **Knuckleball** (`ball_impact "knuckle"`): violet flash, a small spinning swirl on the ground,
  a big spiral icon + question mark that hang 1.3–1.6 s, "CONFUSED!" instead of a tiny "???".
* **Pickoff** (`lock_on`, `pickoff_strike`): a teal ground ring tightens with the reticle; the snap
  throw is thicker with streaks and a ground ring at the hit.
* **Changeup** (`changeup`, `changeup_victim`): no clock (that is Time Out's); three slow lavender
  beats roll out from the plate, a slow sweep at the plate, after-images behind each runner.
* **Power Catch** (`power_catch_throw`, `power_catch_impact`): a filled violet target zone and
  rings tightening in time with the lob; impact adds a dome pulse, the armor-break icon and a
  small shake.
* **Bunt Trap** (`bunt_trap_cast`): a net seal snaps down on the path, dirt puff, chain icon.
* **Cast flourish** (`battle_hud.on_card_played`, `_ring_burst`, `RingBurst`): lift 0.1 s with a
  category-coloured halo, curved 0.28 s flight with an additive light trail, impact at ~0.38 s:
  flash, two rings, rays and sparks in the category colour. Untargeted linked cards fly to their
  caster, other untargeted cards to home plate. A soft `card_whoosh` on the flight. With
  `reduce_flashes` the white core flash is skipped. Play is never delayed (the card is cast on
  click, the flourish is cosmetic).
* **Denied card** (`card_view._draw`, draw only): a red rim and a red ring round the cost gem on
  top of the existing shake and wash.

Tools: `fx_scenario` `cast:<card>` (plays a card's flourish with the HUD on) and `--vfx-gap`.

## Results after the fixes (from the after captures)

* Clear gains: Changeup (now its own lavender beats, no clock), Knuckleball (swirl, spiral icon,
  CONFUSED!), Shielded bubble (round and clear), Bullpen Call (card + "+N ENERGY" now read from
  the 50 m camera), hand flourish (halo, trail, burst at target / caster / plate).
* Moderate gains: Hot Corner (RED HOT!, flames at 0.45 s, a flare on throws; between throws it is
  still mostly the ring), Power Catch (violet zone during the lob), Pickoff (thicker snap).
* Small gain: Bunt Trap (the net seal is mostly hidden when the runners are standing on it, as in
  the showcase pack).
* In Practice the hand is usually full, so Bullpen Call shows a gold-framed card back and
  Seventh-Inning Stretch shows no cards; in a normal game the drawn cards fly with their art.

## Verification

* `tools/check_scripts.sh`: 76 scripts, 0 failed. System suite: 1261 checks, 0 failed.
* Cards UI section (1600×900): 0/175 dead points, 0 dropped fast clicks, 5 checks, 0 failed.
* Before/after sheets for every changed card, the bubble and the flourish (paths in the stream
  report).
