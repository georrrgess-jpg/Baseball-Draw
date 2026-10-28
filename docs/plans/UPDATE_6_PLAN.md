# Update 6 plan: "Clubhouse"

Goal: finish what still looks or feels behind the rest of the game after Update 5. That means:
* the opponents' models;
* card effects that read weakly;
* a progression path without day-to-day goals and with a stingy first hour;
* new features that nobody explains;
* Standard Siege difficulty that is unverified.

## Why these areas (evidence)

| Area | Evidence |
|---|---|
| Runner and boss models | Only the nine defenders were rebuilt (Update 2). The 8 runners, Base Stealer and 3 bosses still use the original SDF-sculpt pipeline: lumpy surfaces, small heads, weak silhouettes from the battle camera. |
| Card effects | Update 5 notes: Hot Corner is subtle after its burst, Bullpen Call's icons are tiny, and the Shielded bubble reads as an egg. 26 older card effects have not been reviewed since Update 2, and the hand's cast flourish is generic. |
| Progression | The economy was cut hard in Update 5 (first game 5–7 packs instead of 15–17, collection about 19 h). There are no missions or quests to give short-term goals. The account level road is not visible anywhere. Achievements don't cover the new content (new cards, Daily Challenge, mastery, sets). Endless innings 1–5 are slow. |
| Navigation and clarity | Daily Challenge, mastery, collection sets, Upgrade Cards and the level roads are never explained. There are no first-visit hints. The "what next" after a game is not guided. |
| Difficulty | Standard Siege on Standard lost 2 of 2 autopilot games after the Update 5 wave tuning (small sample). |

## Streams (parallel helpers, one owner per file)

**R. Runner and boss models**
* Rebuild the 9 runner types and 3 bosses in the hero style of the defenders: smooth lofted meshes, stylised
  proportions, readable faces.
* Each type gets a distinct silhouette and colour language that says what it does (Armored, Sprinter,
  Jumper, Swarmer, Trickster, Captain, Siege Slugger, Base Stealer).
* Polish run, hit and out animations; same rig, clip names and event times.
* Portraits re-rendered.
* Files: `tools/blender/characters/enemies.py`, runner/boss GLBs, portraits.

**V. Card effects review**
* Capture every one of the 32 cards at wind-up, peak and linger. Score how readable it is, how satisfying
  and how unique, then fix the weakest.
* Known items: Hot Corner, Bullpen Call, the Shielded bubble, and the cast flourish from the hand.
* Files: `src/vfx/*`, VFX shaders/textures, the visual side of `card_effects.gd`, and the draw side of
  `card_view.gd` only.

**P. Progression**
* **Missions:** 3 daily plus 1 weekly, with reroll and clear rewards, using the existing economy.
* **Account level road:** a visible track with rewards.
* **Achievements:** new ones for the new content.
* **First-hour pacing:** the first games feel generous; long-term pacing stays as Update 5 set it.
* **Endless:** early innings get boss pressure or shields carried over.
* **Standard Siege:** re-balanced with larger simulator samples. Target: about 65 % autopilot wins on
  Standard with the starter deck.
* **Economy model:** re-run with missions included.
* Files: `profile.gd`, `rewards.gd`, `data/*`, `progression_screen.gd`, new mission files, and
  `wave_generator.gd`/`difficulties.json`.

**U. Navigation and clarity**
* **Fresh-player walkthrough review** of every menu path (Esc/BACK everywhere, dead ends, confusing labels).
* **First-visit hint cards** for each screen and feature: Daily, mastery, sets, Upgrade Cards, level roads,
  packs, dugout.
* **After-game guidance:** what to do next (open packs, upgrade a card, new mission done, try the Daily).
* **Help:** a "?" button per screen that replays its hint.
* Files: `src/ui/*` except `progression_screen.gd`, the mission UI, `battle_hud.gd` and `card_view.gd`.

**Lead**
* Merging, the HUD (`battle_hud.gd`), the full verification pass and the build.

## Verification
* Script check, system suite, full UI flow test and the card hit map (0 dead points), all passing.
* Simulator tables before and after for Standard Siege and Quick Defense, and an economy projection.
* Before/after captures of every runner, boss and changed card effect.
* Before/after captures of every changed screen.
* A Windows smoke test in CI on the `[build]` push.
