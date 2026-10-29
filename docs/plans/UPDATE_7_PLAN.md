# Update 7 plan: "Expansion Pack"

Goal: more cards to build around, a deck builder that builds a strong deck for *your* collection, card
comparison, small model polish, and loose ends from Update 6. Kept tight: three parallel helpers plus the lead.

| Stream | What |
|---|---|
| **N. New cards** | About 12 new cards (32 → about 44), each with a **new mechanic** rather than a re-skin. Data, effects, VFX, art, autopilot use, combos, tests. Also the leftover effects from Update 6: Line Drive (nothing lingers) and Splitter (split balls too small). |
| **D. Deck builder** | A reliable **Auto Build** (`src/core/deck_ai.gd`). It scores every owned card for the player's current team (linked defenders, roles), card levels, mastery, energy curve, category balance, combos and synergies, and picks the best 8 with an explanation of why. It offers **modes** (Balanced, Aggressive, Control, Boss Killer). **Card comparison:** pick two cards and see cost, cooldown, target, every stat side by side at their current levels, with the better values highlighted. Data-driven so the new cards work without special cases. |
| **M. Models** | Marginal polish of the nine defenders: materials and shading (fabric vs skin vs leather), a soft rim and silhouette readability at battle distance, small detail touches. Same rig, clips and events. |
| **Lead** | Dugout shop fix (done: the specials header and pips). The Veteran Siege balance check, the HUD, merging, verification and the build. |

Done means: the script check, system suite, full UI flow test and card hit map all pass; captures of the new
cards and the deck screens; and the Windows smoke test in CI.
