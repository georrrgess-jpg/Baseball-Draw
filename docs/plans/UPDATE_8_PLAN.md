# Update 8 plan: "All-Star Tuning"

Goal: make every game feel fair, readable and exciting.
* Mechanics are tuned against data from the simulator.
* Card and ability effects become more vibrant: saturated colour, glow, punchier timing.
* A few features that make the game richer to play and easier to understand.

## Evidence that sets the priorities

* **Card impact is unmeasured since Update 7.** The pool grew from 32 to 44 cards, and the Auto Build power
  scores are heuristics. The simulator can measure play share, damage and outs per energy for each card.
* **Defenders are lopsided.** Update 5: Kai did 37 % of team damage and Rico about 1 %; only Rico was buffed.
* **Difficulty is still off.** Veteran Standard Siege wins about 1–2 in 6 (target about 40 %), and most losses
  come at the final boss.
* **Effects reviewed in Update 6:** several scored low and were improved; the rest were never touched. Many
  are pale, white or single-colour, and from the battle camera's 50 m distance a lot of effects read small and
  washed out. Hits and defender throws reuse a few generic bursts.
* **No reference for opponents:** runner types, elites and bosses are only explained by tooltips and the boss
  name card.

## Streams (parallel helpers in separate copies of the code; one owner per file)

| Stream | Scope | Main files |
|---|---|---|
| **M. Mechanics** | Simulator pass over all 44 cards (play share, damage/outs per energy, per-card win impact with random decks). Retune outliers: cost, cooldown, params. Defender balance (damage/out share; buff the weakest roles). Veteran and Legend win rates. Dugout upgrade value (which upgrades the autopilot and a human would never buy). Energy pacing (time at full energy). Every change has before/after tables and keeps card text consistent. | `data/*.json`, `wave_generator.gd`, `rewards.gd`, `autopilot.gd`, `tools/balance/` |
| **V. Card effect vibrancy** | Colour and impact pass over every card effect: saturated category palettes, HDR glow that survives tone-mapping, stronger anticipation → impact → linger, ground decals that read from 50 m, screen-space accents for big cards (Legendaries: a brief colour grade or radial streaks). Fix the weakest from the review plus anything still pale. Respects `reduce_flashes` and particle settings. | `src/vfx/card_fx.gd`, card shaders and textures, visual parts of `card_effects.gd` |
| **A. Abilities and hits** | Defender signature throws and class abilities, ball trails per defender colour, crit and out bursts, elite and boss attack telegraphs and impacts, status effects (burn, freeze, stun) more vivid. | `src/vfx/vfx.gd` (shared helpers: additions are coordinated), `projectiles.gd`, `defender.gd`, `enemy.gd` (visuals only) |
| **F. Features** | **Scouting Book:** a screen listing every runner type, elite affix and boss with a 3D turntable model, stats, what it does, and which cards counter it. Seen/unseen tracking, reachable from the main menu, Play and the threat panel. **Combo hints in the hand:** cards that combo with each other glow and link when both are in hand, and the tooltip names the combo. **Card codex link:** the card inspector lists "good against". | new `src/ui/scouting_book.gd`, `main_menu.gd`/`play_menu.gd` (entry points), `battle_hud.gd` (combo hint), `card_view.gd` (draw only), `profile.gd` (seen flags) |

**Lead:** merging, cross-stream fixes, the full verification pass, before/after captures, docs and the build.

## Quality bar
* Every changed effect gets a before/after capture from the battle camera.
* The card hand stays perfectly clickable (hit map: 0 dead points).
* All tests pass; new features get UI tests.
* Balance changes have simulator evidence and nothing gets worse for new players (Rookie stays easy).
