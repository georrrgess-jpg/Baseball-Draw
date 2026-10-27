# Review: battle feel (Stream A, Stream C timing, boss entrances)

Scope: hits, crits, outs, card effects at their peak and one second later, runners moving, bosses
(spawn, telegraph, defeat), defender throws and catches. Evidence comes from frame captures on the
Practice Field (software Vulkan, fixed 30 fps game clock):

* card effects: `tools/art/vfx/showcase.sh <card> <dir> 0.3,1.2,3.0`
* hits, outs, runners, bosses, tags: the new debug scenarios
  `-- --test-battle=practice --fx-scenario=<boss:<id>|hits|runners|tag> --fx-shots=t1,t2 --fx-out=<dir>`
  (`src/vfx/fx_scenario.gd`; run with `--fixed-fps 30`).

Scoring: **Severity** 1 (cosmetic) … 4 (breaks the experience), **Reach** 1 (rare) … 4 (every battle,
all the time), **Effort** S = 1, M = 2, L = 3. Priority = Severity × Reach ÷ Effort.

| # | Finding | Sev | Reach | Effort | Priority | Status |
|---|---|---|---|---|---|---|
| A1 | **Base Shield dome** (seed 3): a permanent 2.5 m hex dome sits on home plate whenever a shield is up, so the most important spot on the field is behind a translucent shell for most of a game. | 3 | 4 | M | 6.0 | Fixed |
| A2 | **No hit-stop or camera punch** (seed 7): crits and outs land with particles only; there is no moment of weight, so big hits and ordinary chip hits feel alike. | 2 | 4 | M | 4.0 | Fixed |
| A3 | **Boss entrance is a bare camera pan** (seed 10): the camera drifts to the gate and back (2.4 s) with no name, no burst and no way to skip; a new player does not learn what the boss does. Defeat is a banner and one confetti puff. | 3 | 3 | M | 4.5 | Fixed (Phase 3 feature 1) |
| A4 | **Bunched health bars overlap** (seed 6): runners on the same path stack their bars on one spot; only the nearest is readable. Worst with swarmers and Grand Slammer reinforcements. | 2 | 3 | M | 3.0 | Fixed |
| A5 | **Rally Cry / Twin Play wash over the field** (seed 4): Rally Cry draws three translucent domes up to 11 m wide over home plate plus waves out to 34 m; Twin Play sends a 30 m ring across the whole field; both then keep a bright filled disc under every defender for 7–8 s. | 2 | 3 | S | 6.0 | Fixed |
| A6 | **Fizzle labels too small** (seed 11): "NO TARGET" / "IMMUNE" use 80 % of the popup size and vanish in about a second. | 1 | 2 | S | 2.0 | Fixed |
| A7 | **Ball trails depend on frame rate**: the trail is a fixed 12 points, so it is ~2 m long at 144 fps and ~10 m at 30 fps (long laser lines in captures and on slow PCs). | 1 | 4 | S | 4.0 | Fixed |
| A8 | **Throw follow-through hard to read** (seed 9): release lines up with the ball spawn (release keyed at 0.30 s of `throw`, 0.85 s of `pitch`, the ball spawns at the hand bone on that frame), but at gameplay distance the arm motion is too small to see. | 1 | 4 | S | 4.0 | Improved (swoosh + glint) |
| A9 | **No glove pop on catches** (seed 9): Maya's dash-tag plays the catch clip with only a sound. | 1 | 2 | S | 2.0 | Fixed |
| A10 | **KO / out** (seed 8): see notes below. | 2 | 4 | M | 4.0 | See notes |

## Notes per finding

(Filled in from the captures, see "Evidence" below.)

## Evidence

Before/after frames are listed in the stream report.
