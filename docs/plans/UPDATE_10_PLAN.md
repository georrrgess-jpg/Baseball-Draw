# Update 10 plan: "Front Office"

Goal: help managers field their best team, and give the main menu the broadcast-style look of the concept art
(`docs/plans/update10_menu_concept.jpg`).

## 1. Auto Equip Best Team (stream A)
* A **BEST TEAM** button on the Team screen. It picks the strongest starting six from the unlocked defenders and
  a captain, then explains why (for example "Kai: highest damage at Lv 6", "Rosa + Ace: The Battery").
* The new `src/core/team_ai.gd` (class `TeamAI`, static, in the style of `deck_ai.gd`) scores each defender from:
  * their level-scaled stats (damage per second, range, accuracy);
  * their trait value;
  * equipped gear and chosen training traits;
  * role zone bonuses;
  * team synergies (`defenders.json` synergies);
  * signature cards the player owns and has in the deck.
  It then searches for the best valid six (the six are few enough to check every combination).
* Rules: the result must keep the game's team rules, which are whatever the Team screen and battle setup
  require today: six players, role coverage, the captain in the team. The captain is chosen by the team's aura
  benefit.
* Optional modes, like Auto Build: Balanced, Damage, Control, Boss Killer.
* A preview with a confirm shows who comes in and goes out, and the score change, before the team is applied.
  Then `Profile.set_team(team, captain)` applies it.
* The result is deterministic, and it never picks a locked defender.

## 2. Compare Defenders (stream A)
* **COMPARE** on the Team screen opens a side-by-side panel for two defenders, like the card compare in
  Cards & Deck:
  * portraits;
  * level;
  * every stat at the current level, with green/red bars for the better or worse value;
  * trait, role and position bonus;
  * signature card;
  * the TeamAI score;
  * a short verdict, e.g. "Rosa: better vs bosses, Rico: better vs crowds".
* Either side can be swapped to any defender, including locked ones (shown as "locked"). From the panel you can
  "Put X in for Y" in the starting six, keeping the team rules.
* Keyboard and controller navigable; Esc closes the panel.

## 3. Main menu redesign (stream B)
Match the concept art at 1600×900 and 1920×1080:
* **Top bar across the full width:**
  * the logo;
  * manager name, division and RP;
  * a LEVEL n bar with XP numbers;
  * coins, stars and cards owned (n/56);
  * "?" and a settings gear.
* **Left: the hero block:**
  * a red "BROADCAST MATCHDAY" ribbon with a live icon;
  * the selected mode's name as a huge title (e.g. THE ENDLESS NINTH), with "STADIUM · DIFFICULTY" spaced
    under it;
  * a green CONTINUE RUN card when a run is saved (mode, inning, stadium), opening the saved run;
  * the big red PLAY button;
  * the quick mode chips: QUICK, SIEGE, BOSS RUSH, ENDLESS.
* **Middle:** the 3D lineup in the stadium, as now.
* **Right: the TODAY panel** with three cards:
  * the **Daily Challenge** (rules, streak, countdown, PLAY DAILY, and a REWARDS strip with coins, stars and
    pack);
  * **Missions** (three rows with progress, OPEN, and a REWARDS strip);
  * the **Daily Login** (claim state, next-reward countdown, login streak and 7 day tiles).
* **Bottom bar across the full width:** Cards & Deck, Card Packs, Upgrade Cards, Team, Shop (FREE GIFT tag),
  Scouting Book and Progression, with corner badges. Practice and Exit stay reachable: Practice through the
  Play menu's mode cards and the bottom-bar overflow, Exit through the settings gear menu or Esc.
* The season tier bar and win-streak flame stay visible in a compact form (e.g. under the level bar, or as a
  chip in the hero block).
* Everything stays keyboard/controller navigable, the UI flow test keeps passing, and the screen works at
  1280×720.

## Ownership
| Stream | Owns |
|---|---|
| **A. Team** | new `src/core/team_ai.gd`, new `src/ui/team_compare.gd`, `src/ui/roster_screen.gd` |
| **B. Main menu** | `src/ui/main_menu.gd`, `src/ui/ui_theme.gd`, `src/ui/hints.gd` |

Both streams add tests in new sections of `tests/test_suite.gd` and `tests/ui_flow_test.gd`.

**Lead:** merging, the full verification, screenshots, docs and the build.

## Verification
* Script check, system suite and full UI flow test pass.
* TeamAI is checked against hand-made rosters (role rules, locked defenders, deterministic, beats the starter
  team).
* Before/after screenshots of the main menu next to the concept art. Screenshots of the BEST TEAM preview and
  the compare panel.
* The Windows smoke test passes on the `[build]` push.
