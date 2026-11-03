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
SCORES_TABLE

## Notes

NOTES

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
