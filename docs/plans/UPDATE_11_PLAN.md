# Update 11 plan: "Hall of Fame"

Goal: a long-term chase for cards and defenders, and fair bosses at every level.

## 1. Card levels 1–10 and Prestige (stream A)
* Card max level goes from 5 to 10.
* Levels 1–5 work as today.
* **PRESTIGE** unlocks at level 5: a special upgrade step that turns the card into a **Prestige card** and
  opens levels 6–10 (shown as Prestige ★1–★5).
* **Power:**
  * levels 6–10 are gentle, about +5 % effect per level instead of +12 %, so prestiged cards don't break the
    difficulty curve;
  * the prestige step itself gives the same +5 %;
  * the final numbers are tuned with the simulator (Standard Siege on Standard with a prestiged deck must stay
    beatable but not trivial).
* **Cost:**
  * Prestige needs a lot of copies plus coins: a long-term sink for the extra copies and coins of late play.
  * Levels 6–10 have rising copy and coin costs per rarity.
  * The extra-copies-to-coins conversion now applies only to level 10 cards, or to copies beyond what the
    card can still use.
  * The economy model is re-run, with targets: the first Prestige at about 8–12 h, a max-level (10) common at
    about 25–35 h.
* **New look:** a Prestige frame in every place a card is drawn (hand, deck builder, upgrades, packs, compare,
  inspector):
  * an iridescent animated holo frame;
  * a gold Prestige crest with ★1–★5;
  * a subtle shimmer that stays readable in battle.
* **Animation:** the Prestige ceremony in Upgrade Cards (and Upgrade All):
  * the card lifts and spins;
  * the old frame cracks and shatters into shards;
  * light rays and a prismatic burst;
  * the new holo frame forms with the crest slamming in;
  * confetti and sound;
  * skippable with a click or Esc;
  * respects `reduce_flashes`.
* Upgrade All includes prestige-ready cards only if the player opts in (a checkbox), with a summary.
* The automatic deck builder, the card compare and the mastery and collection displays all know about levels
  6–10.

## 2. Defender levels to 20 (stream B)
* Defender max level goes from 10 to 20.
* **Power:** levels 11–20 grow +3 % per level (instead of +6 %).
* **XP:** the XP curve extends smoothly, so level 20 lands at about 40–60 h of play.
* **Rewards for levels 11–20:**
  * coins and packs;
  * a 4th training trait tier at level 12 and a 5th at level 16 (new trait pairs in `gear.json`);
  * at level 15 an **All-Star** badge;
  * at level 20 a **Hall of Famer** gold portrait frame and a nameplate on the Team screen and lineup.
* **UI:**
  * the Team level road shows 20 levels readably (two rows or a scroller);
  * level badges everywhere support 2 digits;
  * the Results XP bars and level-up notices handle levels 11–20.
* Best Team (TeamAI) uses the new levels automatically; check that nothing assumes a max of 10.

## 3. Phantom Captain and boss fairness (stream C)
* **Analyse first, with the simulator and targeted tests:**
  * when the Phantom Captain is unkillable: Endless at high innings, Veteran/Legend, Boss Rush, Siege inning 6;
  * the reason: health scaling, phase uptime, decoys soaking throws and cards, untargetable state blocking
    damage, armor;
  * report the numbers: boss health versus team damage per second, time to kill, % untargetable.
* **Then fix it:**
  * cap or soften boss health growth at high innings;
  * phase uptime with a guaranteed vulnerable window after a phase (e.g. "REVEALED: +25 % damage for 3 s");
  * decoys never shield the boss from cards aimed at it;
  * pending card damage still lands when it phases.
  * The target: the Phantom Captain beaten in about 60–75 % of its encounters with a reasonable deck at every
    stage.
* Check the other bosses at high innings the same way, and fix anything similar.
* **Improvements:**
  * the boss health bar shows the phase/vulnerable state;
  * the Scouting Book text for the Phantom Captain explains the counterplay.

## Ownership
| Stream | Owns |
|---|---|
| A. Cards | `data/cards.json`, `src/autoload/db.gd`, `src/autoload/profile.gd`, `src/ui/card_view.gd`, `src/ui/card_upgrades_screen.gd`, `src/ui/deck_builder.gd`, `src/ui/card_compare.gd`, `src/ui/pack_summary.gd`, `src/core/deck_ai.gd`, `src/core/card_mastery.gd`, `src/core/collection_sets.gd`, new prestige FX files, `tools/balance/economy.py` |
| B. Defenders | `data/defenders.json`, `data/gear.json`, `src/ui/roster_screen.gd`, `src/ui/results_screen.gd`, `src/core/team_ai.gd`, `src/characters/character_model.gd` (frames/badges only), `src/ui/main_menu.gd` (lineup nameplates only) |
| C. Bosses | `src/battle/enemy.gd`, `src/core/wave_generator.gd`, `data/enemies.json`, `data/difficulties.json`, `data/modes.json`, `src/ui/battle_hud.gd`, `src/core/scouting.gd`, `tools/balance/simulate.py` |

* Each stream adds tests in new sections of `tests/test_suite.gd` and `tests/ui_flow_test.gd`.
* Changes needed in another stream's file go to the lead as a request.
* **Lead:** merging, the full verification, screenshots, docs and the build.
