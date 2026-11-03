# Review: abilities and hits vibrancy (Update 8, Stream A)

Scope: defender throws (all nine) and their signature / class abilities, ball trails, normal hit /
crit / out bursts, runner status effects, elite affix visuals, boss attacks (telegraphs and impacts).
Card effects themselves belong to Stream V (`card_fx.gd`).

Evidence: frame captures from the **battle camera** (default view: 50 m, pitch -58°, `--cam-view=0,-1.5,0,-58,50`)
on the Practice Field, 1600×900, software Vulkan, `--fixed-fps 30`. New debug scenarios in
`src/vfx/fx_scenario.gd`:

* `u8` — a pack of runners being thrown at (trails, hits, crits, outs) on one path, one elite per
  affix on another, and two defenders winding up their signature cast at 1.0 s (same calls as
  `CardEffects._cast` minus the card's effect).
* `bosses` — Iron Slugger, Grand Slammer and Phantom Captain near the infield with their attacks forced on
  a stagger, so one set of shots catches every telegraph and impact.
* `status` — a row of standing runners, one per status (burn, freeze, stun, slow, root, mark,
  confuse, vulnerable). Also `elites` and `throws` for closer looks.

Before frames were rendered from a clean copy of the previous commit (same scenarios), after frames
from this branch.

Scores: **V** = vibrancy (saturated colour, glow, punch), **R** = readability from the battle camera,
both 1 (poor) … 5 (great).

| # | Effect | Before V / R | Finding (before) | After V / R | Change |
|---|---|---|---|---|---|
| A1 | **Defender throw trails** (all 9) | 2 / 2 | Thin, near-white ribbons; the fx_bolt core (70 % white) drowned the accent, so Ace, Kai, Nova and Hana threw the same pale line. | 4 / 3 | Accent-saturated trail on its own material (narrow white core, wide accent glow, 1.5 energy), 1.6× wider, a thin hot inner core, 4.2–6.5 m long; still thin at 50 m by design (it must not hide runners). |
| A2 | **Class abilities on throws** | 2 / 2 | Only Ace's fastball changed colour; Nova's chain, Bruno's splash, Kai's precision etc. used the generic ball. | 4 / 3 | Per-trait trail flavour: Ace's fastball is a burning ball (flames + embers), Nova crackles (yellow sparks), Bruno and Hana sparkle, Dex and Maya leave streak chevrons, Jax a thick spark trail, Kai a long thin laser line, Rico a blue glow. |
| A3 | **Signature (linked-card) cast wind-up** | 3 / 2 | A card-coloured rune circle at the feet; nothing on the defender's body, so it read as "a card happened near that player". | 4 / 4 | The defender glows in their accent (rim ramps up over the wind-up), an accent ring and light column at the feet, energy streaks into the hand, and an accent starburst, ring and streaks burst from the hand at the release frame. Card colours (Stream V) stay on top. |
| A4 | **Normal hit** | 3 / 3 | Thrower-tinted starburst + shock ring + sparks (Update 6). | 3 / 3 | Unchanged (already tinted per thrower). |
| A5 | **Crit** | 2 / 3 | A small gold ring, a few sparks and a glow; under the damage number it read like a normal hit. | 4 / 4 | Layered starburst (orange rim, gold body, white-hot core) 3.3 m wide, 12 gold + 6 accent streaks shooting out in the screen plane, gold ring, sparks and a ground shock. |
| A6 | **Out** | 3 / 3 | White/cream pop and ring, identical for every out. | 4 / 4 | Pop tinted by the defender who got the out over a white core, short sparks in six bright team colours plus a few confetti flecks (gone in < 1 s), streaks, ring, ground shock. `VFX.set_out_tint()` is called from `Enemy.die()`. |
| A7 | **Burn** | 2 / 2 | An orange rim tint and a trickle of small flame particles. | 4 / 4 | A flickering fire sheet clings to the body (camera-facing, just in front of the model, grows in / fades out), on top of the particles and the rim. |
| A8 | **Freeze** | 3 / 4 | Ice block. | 4 / 4 | Crisper cyan ice tint, a frost ring at the feet while frozen, sparkle glints and a little cold mist, and a freeze-crack burst (shards, cyan ring, frost bloom) at the moment of freezing. |
| A9 | **Stun** | 2 / 2 | Three small stars orbit over the head; invisible from 50 m. | 3 / 3 | Four bigger spinning stars with white-hot centres on a faint golden orbit; the head icon quad is 23 % larger (also defenders' stun stars). |
| A10 | **Slow** | 2 / 2 | A dashed ring at the feet. | 3 / 3 | Drag streaks in the slow colour peel off the back of the runner, plus a soft glow behind the feet. |
| A11 | **Root** | 3 / 4 | Shackle ring + cage of light. | 3 / 4 | Unchanged. |
| A12 | **Marked** | 2 / 3 | Pink reticle over the head, purple rim. | 2 / 3 | Bigger with the head icon quad; otherwise unchanged. |
| A13 | **Confused** | 2 / 2 | "?" and spiral over the head. | 2 / 3 | Bigger with the head icon quad. |
| A14 | **Vulnerable** (caught stealing, Iron Slugger after a slam) | 1 / 1 | Gold rim only. | 2 / 3 | Shows the cracked-shield icon over the head as well. |
| A15 | **Elite affixes** | 1 / 1 | Every affix wore the same red rim (and the yellow-trimmed bar); only Shielded had a visual (its bubble). Swift, Tough, Plated and Slippery looked identical. | 4 / 4 | Each affix has its own colour on the rim and a ground aura just outside the red marker with its own pattern: Swift yellow, fast-spinning dashes + wind streaks; Tough crimson-pink, thick pulsing ring + rising embers; Plated steel-silver, six slow "plates" + glints; Slippery green, counter-spinning fine dashes + drips; Shielded amber, three dashes + its bubble. |
| A16 | **Boss telegraphs** (Iron Slugger slam, Grand Slammer home-run swing, Phantom Captain phase; Slugger swing) | 2 / 3 | A red disc whose fill crept outward with a pulsing rim; no sense of when it lands. | 4 / 4 | `VFX.danger_zone()`: hazard band with stripes crawling inward, inward arrows on the rim, a fill whose front reaches the rim exactly on impact (brightening to white at the end), a rim that pulses faster as impact nears, warning sparks rising from the rim at an increasing rate; the boss flashes when it starts winding up. Home-run swing in orange, phase in violet. |
| A17 | **Boss impacts** | 2 / 2 | One shockwave (+ dust for the slam, + explosion for the home run); the phase had no impact at all. | 4 / 4 | `VFX.boss_impact()`: double/triple shockwave, crater decal in the attack colour, flying debris, a dust ring, sparks, radial streaks, starburst, flash (skipped with reduce flashes), light rays and a flash light. Phase: an imploding violet ring, a pulse, mist and a ring of sparkles. Existing shake calls kept. |

## Notes

* **Trails.** The per-trait style is purely cosmetic: `ProjectileManager._prepare()` reads the thrower's
  `trait_id` from the payload's `source`; card trails (`payload.trail`) are untouched. Trail sparkle rates are
  per 30 fps frame and scale with the particle setting.
* **Signature casts.** `Defender.cast_special()` now calls `VFX.defender_windup(df, windup)`. The card's own
  anticipation (`card_fx.anticipate`, Stream V) still plays over it. The accent rim is cleared at the end
  of the wind-up (+0.35 s).
* **Statuses.** All per-frame status particles go through `status_emit()` and its shared budget. The burn
  flame is one owned quad per burning runner (shared material), hidden on death.
* **Elites.** Rim colours come from `VFX.AFFIX_COLORS`; the card target preview still overrides the rim
  (it re-marks `_rim_dirty`).
* **Bosses.** `telegraph()` (used by card effects) is unchanged; bosses and the Slugger use the new
  `danger_zone()` (ring shader mode 5). Gameplay timings, radii and stun times are unchanged.
* **Evidence.** Before/after strips (battle camera, crops scaled 2–3×) are listed in the Stream A report.

## Not done / deferred

* Marked and Confused icons are still small from 50 m; a bigger redesign of the head icons (or a ground
  marker for Marked) would help but competes with the health bars for space.
* Root and Rico's Home Guard aura were left as they were (already readable).
* Throws from cards that use the "throw" animation (Power Throw, Pickoff...) get the accent trail only when
  the card does not set its own trail; their wind-up belongs to Stream V.

## Settings respected

* `reduce_flashes`: every new full-screen-ish flash sprite (crit, out, boss impact) is skipped; the
  danger-zone rim pulse is capped at ~1.4 Hz instead of ~3.5 Hz; flash lights already scale to 35 %;
  starbursts use the `impact` system whose energy is already lowered.
* Particle scale: every new emitter goes through `_count()` / `_scale`, per-frame status and elite
  particles draw from the shared status budget, and trail sparkles scale with the particle setting.
* Screen shake: boss impacts keep the existing `battle.shake()` calls (scaled by the setting); no new shake.
* Input is never paused; hit-stop stays model-only.
* Runners and health bars: the burn flame sits in front of the body but stays below the health bar;
  elite aura rings sit just outside the red runner marker; status icons are drawn above the bar.
