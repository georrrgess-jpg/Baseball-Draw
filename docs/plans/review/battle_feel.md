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

* **A1 Base Shield.** Now a thin dashed ring (2.7 m) around the plate plus a shield pip per shield
  on the ring's left, right and catcher side, 0.8 m up, so nothing stands over the plate or the
  runners' last steps. The hex dome is kept but only flares for ~1 s when a shield is raised or
  blocks a run (with a ripple toward the runner); the spent pip bursts into shards and a broken
  shield icon. `VFX.make_shield_dome()` / `_update_dome()`.
* **A2 Hit-stop and punch.** Hit-stop is per runner and purely visual: on a crit (0.05 s) or an out
  (0.075 s) the drawn model holds its impact pose, trembles along the hit direction and its
  animation pauses; the runner node keeps moving underneath and the model snaps back on release.
  No game clock is touched, so simulation results are unchanged (system suite 957/957, autopilot
  games finish normally). Camera punch is a 5 % zoom kick (50 ms in, ~0.3 s out) on crits (0.35),
  outs (0.3, elites 0.6) and boss defeats (1.3), scaled by the screen-shake setting and not
  restarted by weaker kicks, so streams of outs don't jitter. `Enemy.hit_stop()`, `CameraRig.punch()`.
* **A3 Boss entrance / finale.** `src/vfx/boss_intro.gd`: camera to the gate, gate burst at 0.35 s
  (rays, dust, debris, sparks, light), name card at 0.45 s ("FINAL BOSS / THE GRAND SLAMMER /
  Home-run swings stun your fielders. Calls in backup as it weakens."), camera back at 2.35 s, done
  at 2.7 s. Click or Space skips (the click is not consumed, so a card can be picked at once).
  Not played in auto tests, during the guided first game, while another cinematic holds the
  camera, or in Practice after the first spawn of each boss. Defeat: 0.16 s hit-stop on the boss,
  0.85 s slow motion (game clock eases to 30 % and back; input untouched, restores the chosen
  speed, cancelled by finish_run), a big burst with confetti and rays, camera punch and shake, the
  existing "DEFEATED!" banner. First capture had the card over the boss's head; it now sits in the
  lower middle with the boss framed above it.
* **A4 Health bars.** Ten times a second Battle projects visible bars to the screen and lifts any
  bar that would overlap a nearer runner's bar by one row (up to 4 rows), eased in the bar shader
  (`stack` instance uniform), so the bars of a bunched group form a short ladder. Bosses keep theirs.
* **A5 Auras.** Rally Cry: one thin wave from the mound and a small shout bubble, light shaft and
  shout icon per defender (all under 1 s), no domes over home plate. Twin Play: a 12 m quick sweep
  instead of a 30 m ring. `defender_aura` lands bright for ~0.5 s, then settles to half strength
  with a fainter fill for the rest of the buff (also used by Field Vision and Diamond Aura).
* **A6 Fizzles.** Full popup size, muted grey, held 1.35 s.
* **A7 Trails.** Capped at 3.6 m (5–9 m for card trails) instead of 12 points.
* **A8 Throws.** Release timing checked against the clips (release frame = ball spawn at the hand
  bone). Added a faint swoosh that follows the throwing hand for 0.18 s after release and a glint
  at the release point, so the follow-through reads at gameplay distance. Skipped at very low
  particle settings.
* **A9 Catches.** Glove pop (flash, ring, sparks, leather dust) at the glove on Maya's dash-tag.
* **A10 KO / out.** In the `hits` captures the out reads: white flash, "out" starburst, knock-back
  hop, fall, shrink. With the new hit-stop and punch the moment of the out is clearer. Not changed
  further; the per-runner OUT text stays off (it was removed in Update 2 as clutter).

## Not done / deferred

* Runner-type running strips and per-clip defender throw strips were not re-captured frame by frame
  (render time: 2–4 s per frame under the shared load); release timing was checked from the clip
  data and code instead.
* Crowd standing and the boss music sting belong to the stadium and audio streams; they can hook
  `boss_intro_started`, `boss_intro_finished` and `boss_defeated` on Battle.
* Uniform layering (seed 12) belongs to the character art stream.

## Verification

* `tools/check_scripts.sh`: 57 scripts, 0 failed. System suite: 957 checks, 0 failed.
* Cards UI section (`--ui-test-section=cards`, 1600×900): 0/175 dead points, 0 dropped fast clicks,
  5 checks, 0 failed.
* Headless autopilot, Standard / Rookie from innings 3, 6 and 9 (`--start-wave=2`, speed 4): all
  finished without script errors; Phantom Captain and Grand Slammer were beaten (finale + slow
  motion ran in auto tests; the intro is skipped there by design).

## Evidence

Capture tools: `src/vfx/fx_scenario.gd` (new) and `tools/art/vfx/showcase.sh`. Frame paths are
listed in the stream report.
