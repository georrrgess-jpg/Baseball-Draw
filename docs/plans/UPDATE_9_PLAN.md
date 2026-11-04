# Update 9 plan: "Big League"

Goal: the biggest update so far. Every game feels different and every session has a reason to come back, with
more to collect and screens that are clearer and more exciting. In short:
* three new team members;
* twelve new cards;
* smarter mode logic and a new mode;
* an economy with short, medium and long goals;
* redesigned hub, Play, Team, Shop and Season screens.

## Why these areas (evidence)

| Area | Evidence |
|---|---|
| Replay value | Runs differ only through the deck. Siege and Endless play the same way every time: no decisions besides cards and dugout upgrades, and nothing changes after a boss. |
| Return loop | The Daily Challenge, three daily missions and a weekly mission are the only daily pulls. There is no login reward, free daily gift, win streak, season track or shop rotation. |
| Medium-term goals | The account level road is the only track. After about level 10, rewards flatten into "Rookie Pack + 150 coins" for every level. |
| Frustration points | Pack luck: legendaries take more than 20 hours (economy model) with no pity protection. Copies of max-level cards are wasted. Coins pile up after the coin boost, and buying random packs is the only sink. |
| Roster | 9 defenders and a single catcher, so there's little lineup choice. The last unlock is at account level 10. |
| Cards | 44 cards. Missing families: critical hits, type-targeted debuffs, cast-twice, in-run economy, signature recharge, comeback ("clutch") plays. |
| Screens | Play menu: three dense columns with tiny difficulty text and a wall of locked stadiums. Team: a long list that won't fit 12 defenders. Level road: unreadable labels under the nodes. Main menu: the daily and mission panels are small, and there is no place for new daily systems. |
| Stability | A one-off Windows smoke failure ("Lambda capture was freed", 6 errors) matched the six Results-screen counter callbacks. |

## Features

### 1. New team members (Stream A)
| Id | Name | Role | Trait (always on) | Signature card | Unlock |
|---|---|---|---|---|---|
| `moose` | Moose Malone, "The Big Scoop" | Infielder (first base) | **Long Stretch**: runners within 5 m of him take +25 % damage from everyone and are slowed 10 %. | `scoop_and_tag` | Account level 13, or sign for 6,000 coins |
| `rosa` | Rosa Vega, "The Strategist" | Catcher | **Pitch Framing**: every 6 s she marks the most dangerous runner. Marked runners take +35 % damage, and an out on a marked runner gives +0.5 energy. | `signal_caller` | Account level 16, or 8,000 coins |
| `sid` | Sid "Submarine" Okafor | Pitcher | **Skipper**: throws skip along the ground and pierce, hitting one runner behind the target for 60 % damage. | `worm_burner` | Account level 19, or 10,000 coins |

Each new defender gets:
* a full hero-style 3D model with all clips, a portrait, stats, a role bonus and two training-trait tiers;
* trait code in `defender.gd`;
* a signature pack on unlock (the existing mechanism);
* Scouting Book and roster data.

### 2. Twelve new cards (Stream B)
| Id | Name | Rarity | Type | Cost | Effect |
|---|---|---|---|---|---|
| `scouting_report` | Scouting Report | Common | Control | 2 | Pick a runner: every runner of its type takes +30 % damage for 8 s. |
| `sprinkler_system` | Sprinkler System | Common | Defense | 2 | Soak a base path for 7 s: runners 30 % slower, with a chance to slip (0.6 s stun). |
| `sweet_spot` | Sweet Spot | Uncommon | Offense | 3 | For 6 s every throw is a critical hit. |
| `rally_monkey` | Rally Monkey | Uncommon | Utility | 2 | +2 energy. If a run scored this inning: +4 energy and draw 1 instead (clutch). |
| `second_wind` | Second Wind | Rare | Utility | 3 | One defender: their signature card comes off cooldown, +50 % attack speed for 6 s. |
| `money_ball` | Money Ball | Rare | Utility | 2 | For 12 s, outs pay double in-game coins (dugout). |
| `scoop_and_tag` | Scoop & Tag | Rare | Defense | 4 | Moose's sweep: knock runners in an arc back and stun them. Non-boss runners under 30 % health are out. |
| `signal_caller` | Signal Caller | Rare | Utility | 3 | Rosa marks the 3 most dangerous runners for 10 s: +40 % damage taken, outs refund 1 energy. |
| `hidden_ball_trick` | Hidden Ball Trick | Epic | Control | 4 | After a 1.2 s reveal, the strongest non-boss runner is out. Bosses take 15 % of max health. |
| `worm_burner` | Worm Burner | Epic | Offense | 5 | Sid's skipping grounder tears down a base path: damage to every runner on it, trips them (1 s stun) and leaves a slick (25 % slow, 4 s). |
| `fireworks_night` | Fireworks Night | Legendary | Offense | 7 | 14 fireworks strike random runners over 4 s, then a finale burst. |
| `ground_rule_double` | Ground Rule Double | Legendary | Utility | 6 | The next 2 cards you play this inning are cast twice. |

All cards also get:
* card art (`tools/art/cards_v2.py`), card FX in the Update 8 vibrancy style, and combos;
* an `ai_weight` calibrated with the simulator, Auto Build support, collection sets and "Good against" data.

### 3. Mode logic (Stream C)
* **Dugout Draft (boons):** after each boss, pick 1 of 3 boons that last for the rest of the game. This applies
  in Standard Siege (after innings 3 and 6), Endless (after every boss) and Boss Rush (after bosses 1 and 2).
  * There are 18 boons in three rarities, in `data/boons.json`. Examples: +15 % team damage, the first card of
    each wave costs 1 less, +1 hand size, a base-shield charge, +25 % in-game coins and −25 % signature cooldowns.
  * The autopilot picks boons too.
* **Boss Rush** (new mode, about 7 minutes): three innings, each ending with a boss. The bosses get tougher, and
  you draft after bosses 1 and 2. A Pro Pack on a win, and the best time is recorded.
* **Endless milestones:** every 5 innings cleared pays out at the end (see Economy). The HUD shows the next
  milestone and your best inning.
* **Early call:** during the break between waves, NEXT WAVE NOW starts the next wave immediately for +1 energy.
  This cuts downtime.
* **Pacing and balance pass:** simulator check of every mode with the new cards, defenders and boons.
  * Standard Siege on Standard stays at about 65 % autopilot wins with the starter deck. Boons must not make it
    trivial, so retune the wave budgets if needed.
  * Rookie stays easy.
  * Target Endless median: about 12–16 innings.

### 4. Economy and return loop (Stream D)
| System | Rules |
|---|---|
| **Season Pass** | 14-day seasons (fixed calendar from 2026-11-02, numbered), 30 free tiers, 500 season XP per tier. XP: 100 per game, +60 for a win, +80 per mission claimed, +100 for the Daily Challenge. Rewards mix coins, packs, stars, a Champion Pack at tiers 15 and 30, and a season uniform at tier 30. After tier 30, a Pro Pack every 1,000 XP. |
| **Daily login calendar** | 7-day cycle, claim once per calendar day: 150 coins → Rookie Pack → 250 coins → 10 stars → Pro Pack → 400 coins → Champion Pack. Missing a day pauses the calendar instead of resetting it; a login streak counter is shown for flair. |
| **Win streak** | Each consecutive win in a rewarded mode adds +10 % coins, up to +50 %. A loss resets it. Shown as a flame on the hub, Play menu and Results. |
| **First win of the day** | Double coins on the first win each day. |
| **Daily Shop** | Refreshes at local midnight. Slots: a **free gift**, **two card deals** (copies of cards you own that still need copies, weighted toward your deck), **one pack deal** (Pro Pack at −25 %), and **one star deal**. Each can be bought once per day. Card copy prices: common 60, uncommon 120, rare 250, epic 500, legendary 1,000 coins. |
| **Free agents** | Sign the new defenders early for coins (table above). This is the big coin sink. |
| **Pack pity** | An epic or better is guaranteed within 10 packs, and a legendary within 30. The counters show on the Packs screen. |
| **Extra copies** | Copies of a max-level card turn into coins: common 20, uncommon 40, rare 80, epic 160, legendary 400 (shown in the pack reveal summary). |
| **Promotion rewards** | Reaching a new division pays coins (300 × division), stars (10 × division) and a Pro Pack (a Champion Pack from Gold up). |
| **Endless milestones** | Every 5 innings cleared: 150 coins × (innings / 5) + a Rookie Pack, plus a Pro Pack at 10 and 20. |
| **Boss Rush** | Reward multiplier 0.6; a win pays a Pro Pack. |
| **Missions and achievements** | New missions (draft boons, win a Boss Rush, buy a shop deal, extend a win streak) and new achievements for the new content. |

Targets (`tools/balance/economy.py`, extended with every new source):
* The first hour stays generous.
* The whole collection, including legendaries, in about 25–30 hours; the first legendary in under about 6 hours.
* Season 30 reached with about 1 hour of play a day.
* Coins have purposes all the way through: upgrades, shop deals, free agents and packs.

### 5. Screens (Streams E1 and E2)
* **E1 — Hub (main menu):**
  * a clear hierarchy: PLAY with a quick mode switch;
  * a "today" column: login calendar claim, free gift badge, missions, the Daily Challenge;
  * a season tier bar, win streak flame, and buttons for Shop and Season.
* **E1 — Play menu:** big mode cards with your best record, what a win pays, and the Boss Rush card. Readable
  difficulty, and a compact stadium carousel instead of the wall of locked tiles.
* **E1 — Results:**
  * win streak, first win of the day, season XP bar with tier-ups, boons taken, Endless milestones;
  * fix the counter callback race (tweens bound to and killed with their panels).
* **E2 — Team:** a portrait grid that fits 12 defenders, and free agent signing.
* **E2 — Shop (new screen):** the daily deals, free gift, refresh countdown, pack shop and free agents.
* **E2 — Season (new screen):** the tier track, claimable rewards and the season countdown.
* **E2 — Level road:** readable labels and reward icons.
* **E2 — Packs screen:** pity counters and a link to the Shop.

## Contracts (written by the lead before the streams start; stubs exist from the start)

Profile keys (defaults in `profile.gd`):
* `season` = `{id, xp, claimed: [tiers], bonus_claimed}`
* `login` = `{day, last_claim, streak, best}`
* `shop` = `{date, offers: [], bought: []}`
* `streak` = `{wins, best}`
* `pity` = `{epic, legendary}` (packs since the last one)
* `first_win_day` = `""`

APIs (`class_name`, static):
* `Season`:
  * `current() -> {id, number, name, start, end, seconds_left}`
  * `xp() -> int`, `tier() -> int`, `tier_progress() -> {tier, xp_in, xp_need}`
  * `tiers() -> Array[{tier, reward, claimed, reached}]`
  * `claimable() -> Array[int]`, `claim(tier) -> Dictionary`, `claim_all() -> Array`
  * `add_xp(n, source) -> Array[int]` (tiers reached)
  * `reward_text(reward) -> String`
* `DailyRewards`:
  * `calendar() -> Array[{day, reward, claimed, today}]`, `can_claim() -> bool`, `claim() -> Dictionary`
  * `day() -> int`, `streak() -> int`, `reward_text(reward) -> String`
* `Shop`:
  * `offers() -> Array[{id, kind, card, pack, copies, price: {coins, stars}, bought, title, text}]`
  * `can_buy(id) -> bool`, `buy(id) -> Dictionary`, `seconds_to_refresh() -> int`
  * `free_agents() -> Array[{id, price, level, signed}]`, `sign_agent(id) -> bool`
* `Boons`:
  * `all() -> Array`, `get_boon(id) -> Dictionary`
  * `offer(run, rng) -> Array[String]` (three ids), `apply(battle, id)`
  * `summary(ids) -> Array[{id, name, text, rarity, icon}]`
* `Profile`:
  * `win_streak() -> int`, `streak_bonus() -> float`
  * `pity_left(rarity) -> int`, `is_first_win_today() -> bool`

`Rewards.apply` result gains these keys:
* `streak`, `streak_bonus_coins`, `first_win_today_coins`
* `season_xp`, `season_tiers` (tiers reached)
* `boons` (ids), `milestones` (Endless innings), `milestone_coins`
* `promotion_reward`, `overflow_coins`

Run state gains `boons: Array[String]` and `milestones: Array[int]`. Mode `boss_rush` lives in `data/modes.json`.
Router scenes: `shop`, `season`.

Battle hooks (Stream C adds them to `battle.gd`; other streams connect defensively with `has_signal` or
`has_method` until the merge):
* `signal runner_out(enemy: Enemy, info: Dictionary)`: emitted for every runner put out, after the out is
  scored. `info` holds `{source, defender, card, marked}`.
* `func add_out_coin_bonus(mult: float, time: float)`: in-game coins per out are multiplied by
  `(1 + every active bonus)`. Used by Money Ball and the coin boon.
* `func add_energy(n: float)` (if missing): energy gain, capped at the maximum.

Runner statuses go through the existing `Enemy.apply_mark / apply_slow / apply_stun / ...`. Only Stream B edits
`enemy.gd`.

Card cooldowns live in the card system (Stream B). Second Wind takes the chosen defender's signature card off
cooldown in the hand or deck, and gives the defender +50 % attack speed for 6 s.

## Streams (parallel helpers, each in its own copy of the code; one owner per file)

| Stream | Owns |
|---|---|
| **A. New defenders** | `tools/blender/characters/*` (roster, hero, anim), the new GLBs and portraits, `data/defenders.json`, `src/battle/defender.gd`, `src/battle/projectiles.gd`, `src/characters/*` |
| **B. New cards** | `data/cards.json`, `data/combos.json`, `src/battle/card_effects.gd`, `src/battle/card_system.gd`, `src/vfx/card_fx.gd`, `tools/art/*` and card art, `src/core/deck_ai.gd`, `src/core/collection_sets.gd`, `src/core/scouting.gd` (counters only), `src/battle/enemy.gd` |
| **C. Modes and boons** | `src/battle/battle.gd`, `run_state.gd`, `wave_generator.gd`, `autopilot.gd`, `data/modes.json`, `data/difficulties.json`, `data/boons.json`, `src/core/boons.gd`, new `src/ui/boon_draft.gd`, `src/ui/battle_hud.gd`, `tools/balance/simulate.py` |
| **D. Economy and return loop** | `src/autoload/profile.gd`, `src/core/rewards.gd`, `season.gd`, `daily_rewards.gd`, `shop.gd`, `missions.gd`, `level_road.gd`, `data/season.json`, `data/login_rewards.json`, `data/shop.json`, `data/missions.json`, `data/achievements.json`, `data/gear.json`, `data/packs.json`, `data/ranks.json`, `tools/balance/economy.py` |
| **E1. Hub, Play, Results** | `src/ui/main_menu.gd`, `play_menu.gd`, `results_screen.gd`, `ui_theme.gd`, `hints.gd`, `menu_screen.gd` |
| **E2. Team, Shop, Season, Packs** | `src/ui/roster_screen.gd`, new `shop_screen.gd`, new `season_screen.gd`, `progression_screen.gd`, `level_road_view.gd`, `packs_screen.gd`, `src/autoload/router.gd`, `scenes/*.tscn` |

**Lead:**
* Foundation: contracts, stubs, profile keys, placeholder defenders, scenes and this plan.
* Merging; the test files (both sides kept); cross-stream wiring (signature ids, results keys); the full
  verification pass; screenshots; docs; and the build.

## Quality bar and verification
* Script check, system suite and full UI flow test all pass. Every stream adds tests for what it built.
* Card hit map: 0 dead points.
* Simulator tables before and after for every mode (win rates by difficulty). Rookie stays easy.
* Economy projection before and after, against the targets above.
* The new models pass `verify_characters` and clip checks, and look right in the Team screen and in battle.
* Screenshots of every new or changed screen, the new cards' effects and the new defenders, with before/after
  where a screen changed.
* The Windows smoke test passes on the `[build]` push.
