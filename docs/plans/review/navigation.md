# Update 6 review: navigation and clarity (Stream U)

Scope: every menu path a new player takes, then the same paths as a mid-game profile. Route walked
with `--fresh-profile`: first launch → tutorial game → Results → Card Packs → Cards & Deck → Upgrade
Cards → Team → Play (Standard, Quick, Daily, Promotion Challenge, Endless, Practice) → Settings → main
menu; then with `--grant-demo-cards` (cards with copies, upgrades ready, packs, coins). Evidence: the code
of every screen in `src/ui/`, the before captures listed at the end and the UI flow test.

Questions per screen: is the purpose and the next step clear within 2 s, are labels clear, does Esc/BACK
always work and go where expected, are there dead ends, is any feature never explained (Daily Challenge,
mastery stars, collection sets, Upgrade Cards copies, defender level road and traits, gear/uniforms,
formations, promotion challenges, energy, card rarity).

Scoring as in the Update 5 reviews: **Severity** 1 cosmetic … 4 breaks the experience; **Reach** 1 rare … 4
every session; **Effort** S = 1, M = 2, L = 3. **Priority = Severity × Reach ÷ Effort.**

## Findings

| # | Screen | Finding | Sev | Reach | Effort | Priority | Status |
|---|---|---|---|---|---|---|---|
| N1 | All menus | Daily Challenge, mastery stars, collection sets, upgrade copies, the defender level road, traits, gear, uniforms, promotion and Endless are never explained. A player meets them as unlabelled stars, badges and locked buttons. | 3 | 4 | M | 6.0 | Fixed: first-visit hint cards |
| N2 | Results | After a game there is no guidance: unopened packs, a card ready to upgrade, an unplayed Daily or an available promotion are not pointed out. The only choices are PLAY AGAIN, CARDS & DECK, MAIN MENU. | 3 | 4 | M | 6.0 | Fixed: "WHAT'S NEXT" row |
| N3 | Results | Esc does nothing on the Results screen (the battle ignores input there, the pause menu is blocked). | 2 | 4 | S | 8.0 | Fixed: Esc → main menu |
| N4 | Dugout | Esc does nothing between innings, so there is no way to Save & Quit without starting the next inning. Esc also does not close the card picker. | 3 | 3 | S | 9.0 | Fixed: Esc closes the picker, else opens the pause menu |
| N5 | Card Packs | Esc during a pack reveal leaves the screen at once, skipping the reveal of cards already granted. | 2 | 3 | S | 6.0 | Fixed: Esc reveals all, then finishes, then leaves |
| N6 | Cards & Deck | The "SET COMPLETE" celebration ignores Esc; Esc leaves the screen behind the popup. | 2 | 1 | S | 2.0 | Fixed: popups register with the screen; Esc closes the top one first |
| N7 | Cross-links | BACK always goes to the main menu, so Upgrade Cards → GET CARD PACKS → BACK lands on the main menu instead of Upgrade Cards (same for Deck → Packs, Play → EDIT TEAM / EDIT DECK). Only Deck → Upgrades had a special case. | 2 | 3 | S | 6.0 | Fixed: Router back path (`Router.open` / `Router.back`); BACK's tooltip names the target |
| N8 | Team | "Buy gear in Progression → Pro Shop." is a dead end: no link, and Progression opens on Overview. | 2 | 2 | S | 4.0 | Fixed: PRO SHOP ▶ opens Progression on the Pro Shop tab |
| N9 | Team | Trait buttons for levels not reached are disabled without saying why (tooltip shows only the trait text). | 2 | 3 | S | 6.0 | Fixed: "Unlocks when X reaches level N." |
| N10 | Main menu | A new trait to choose is only visible inside Team; the TEAM tile has no badge (packs, cards, upgrades do). | 2 | 3 | S | 6.0 | Fixed: NEW TRAIT badge |
| N11 | Main menu | Promotion is a passive gold line at the bottom of the profile panel; nothing on PLAY. | 3 | 2 | S | 6.0 | Fixed: PROMOTION badge on PLAY and a PROMOTION TO … button that opens Play on the challenge |
| N12 | Main menu | Badges show that something is waiting but not which thing matters most. | 2 | 4 | S | 8.0 | Fixed: an "UP NEXT" strip under PLAY with the best next action (one click) |
| N13 | Main menu | A brand-new player sees 8 equal tiles; Practice, Progression and Upgrade Cards are not useful before the first game. | 2 | 2 | S | 4.0 | Fixed: toned down (50 %, full on hover, tooltip says when they matter) until the first game is finished |
| N14 | Play | Difficulty buttons are disabled for Practice and Promotion without a reason. | 1 | 2 | S | 2.0 | Fixed: tooltips |
| N15 | All menus | No way to see an explanation again. | 2 | 2 | S | 4.0 | Fixed: "?" on every screen; Settings → Gameplay → Show tips / Show all tips again |
| N16 | Main menu | First launch: the welcome panel is anchored by its top edge and runs off the bottom of the screen, so PLAY THE FIRST GAME is half cut off (1080p and 720p). | 3 | 4 | S | 12.0 | Fixed: grows up from the bottom-right corner |
| N16b | Main menu | Esc on the welcome panel does nothing. | 1 | 1 | S | 1.0 | Fixed: Esc = "Look around first" |
| N17 | Battle | Energy and formations are explained only by the battle tutorial and the HUD tooltips; nothing replays them outside HOW TO PLAY. | 1 | 2 | M | 1.0 | Open (HUD is the lead's file; HOW TO PLAY covers both) |
| N18 | Play | Changing EDIT TEAM / EDIT DECK and returning resets the chosen mode to the last played one. | 1 | 2 | S | 2.0 | Open |

Checked and fine: every MenuScreen already had BACK top-left and Esc (Play, Card Packs, Cards & Deck,
Upgrade Cards, Team, Progression, Settings); the pause menu closes its sub-panels with Esc before
resuming; Settings' key rebinding takes Esc as "cancel"; Upgrade Cards already explains a disabled
UPGRADE button (missing copies/coins plus a Card Packs link); the Play screen already explains locked
stadiums and the locked Promotion Challenge ("Unlocks at N RP").

## What changed

**Hint cards** (`src/ui/hints.gd`)
* One small card at a time: icon, title, one or two sentences, GOT IT (and SKIP TIPS when more are
  queued, with a "2 / 3" counter). A pulsing outline and an arrow point at the element it explains;
  the card places itself below, above, right or left of it, whichever fits.
* Shown the first time a screen is opened (after its enter animation); a screen's hints queue and show
  one after another. Feature hints (mastery, sets, traits, Daily, Promotion, Endless, Practice) wait until
  the player meets the feature: e.g. mastery after a card has been played in a real game, the Daily hint
  when the Daily mode is selected.
* Never during the battle tutorial or the first game (dugout), never in automated runs (`--ui-test`,
  `--smoke-test`, `--no-help`, `--no-hints`) and not when Settings → Gameplay → Show tips is off.
* "Seen" flags in `Profile.data.flags.hints_seen`. Esc closes the hint (counts as seen) without leaving the
  screen. The "?" button replays all of a screen's hints.
* Hints: main menu (clubhouse, Daily, Promotion), Card Packs (packs, rarity), Cards & Deck (deck,
  mastery, sets), Upgrade Cards, Team (team, level road, traits/gear/uniforms), Play (modes, Daily,
  Promotion, Endless, Practice), Dugout, Settings.

**What's next** (`src/ui/next_steps.gd`): ranked suggestions — promotion challenge, missions ready
(when the progression stream's API exists: `Profile.claimable_mission_count()` or a `Missions` class with
`claimable_count()`), unopened packs, cards ready to upgrade, a trait to choose, a set reward, today's
Daily, new cards for the deck. Results shows the top three as one-click buttons above PLAY AGAIN; the
main menu shows the top one as "UP NEXT".

**Navigation**: `Router.open()` (cross-links push the current screen), `Router.back()` (BACK/Esc pop it),
`Router.goto(scene, loading, tab)` selects a tab by name; `MenuScreen.push_overlay()` makes Esc close
popups first; `MenuScreen.before_back` lets a screen use Esc first (pack reveal); `MenuScreen.set_help()`
adds the "?" button and first-visit hints.
