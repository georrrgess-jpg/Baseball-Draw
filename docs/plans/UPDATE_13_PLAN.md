# Update 13 plan: "Rookie Camp" (new-player onboarding and early retention)

Goal: a new player is playing within seconds, feels skilled and rewarded in the first 10 minutes, always knows
the next step, and has strong reasons to come back on days 2–7.

## Problems with today's first session
* The first launch lands on the full hub, with every mode, screen and badge open at once, and a text-heavy
  welcome panel on top. That is a lot to read before the first throw.
* The battle tutorial explains a lot in pop-ups. Learning by doing is more effective.
* After the first game, nothing guides the first pack opening, adding a new card to the deck, or game 2.
* There are no early commitment moments (a choice the player owns), and no new-player-only reward track or
  first-week event.
* A new player who loses early games gets no help and no consolation.

## Stream A: the first-session flow
* **Straight into play.** On the very first launch:
  * the title screen leads to a short skippable intro (3 animated story cards, under 15 s, e.g. "The Wreckers
    are storming your stadium…");
  * then directly into the guided first game, with no stop at the hub;
  * an "I've played before" option skips to the hub.
* **The first game, learning by doing.** Rewrite the battle tutorial so each step is an action with minimal
  text:
  * drag a defender into position;
  * start the wave;
  * play a card on a runner;
  * a staged satisfying moment: a scripted combo/double play with a celebration;
  * a first boss tease.

  Tooltips are short and point at things, with skip available. The first game is tuned to be a comfortable
  win (Rookie with a first-game assist), finishing in about 3–4 minutes.
* **A guided reward sequence after the first win:**
  * the Results screen shows a simplified first-time layout with big reward moments;
  * a guided first pack opening (spotlight, "Tap to open!");
  * a guided "put your new card in your deck" step;
  * back to the hub with PLAY spotlighted for game 2.
* **First-session funnel stats.** Saved locally in the profile (timestamps of first launch, first game, first
  win, first pack, game 2, day-2 return), for tests and tuning.

## Stream B: progressive unlocks, Rookie Path, Rookie Week
* **Progressive feature unlocks.** A new `Onboarding` core. New players start with a simpler hub. Features
  unlock in steps with a celebratory "NEW FEATURE UNLOCKED" card and a spotlight. Locked ones show as
  teasers with "Unlocks at level N", not hidden. Suggested order:
  * Quick Defense, Cards & Deck, Card Packs;
  * then Upgrade Cards and Team;
  * Standard Siege, Missions and Daily Challenge;
  * Shop and Season Pass;
  * Boss Rush, Endless, Scouting Book and Promotion.

  Existing players (by level or games played) have everything unlocked at once.
* **Rookie Path.** It replaces the 5-step starter chain with a visible ~10-step track on the hub. The rewards
  escalate, steps teach one feature each, and the final reward is big (e.g. a Champion Pack plus a defender of
  your choice early). Progress is shown as a strip with the next reward.
* **Commitment moment.** After the 3rd game, **pick 1 of 3 epic cards**, chosen to suit the player's deck.
* **Rookie Week.** A new-player 7-day bonus calendar alongside the normal login calendar:
  * bigger rewards on days 1–7;
  * day 7 is a Champion Pack and a Legendary choice;
  * shown with a countdown;
  * it pauses rather than resets.
* **Early pacing.**
  * Account levels 1–5 come faster (front-loaded XP).
  * The first 3 games always pay a pack.
  * A loss in the first 5 games pays a consolation reward and offers an easier difficulty.
  * Gentle adaptive help: after 2 early losses in a row, suggest Rookie or a better deck via Auto Build.
* **Welcome back.** After 3+ days away, a bonus and a "what's new" recap card.
* **Badge budget.** New players see at most two attention badges on the hub at once.
* Check that the economy model still meets the first-hour and long-term targets.

## Ownership
| Stream | Owns |
|---|---|
| **A. First session** | `src/ui/title_screen.gd`, `src/ui/boot.gd`, new intro scene/script, `src/ui/battle_tutorial.gd`, `src/ui/results_screen.gd`, `src/ui/packs_screen.gd`, `src/ui/pack_summary.gd`, `src/ui/deck_builder.gd` (guided step only), `src/core/session.gd` if present |
| **B. Unlocks and retention** | new `src/core/onboarding.gd`, `src/ui/main_menu.gd`, `src/ui/play_menu.gd`, `src/ui/hints.gd`, `src/ui/ui_theme.gd`, `src/autoload/profile.gd`, `src/core/missions.gd`, `src/core/rewards.gd`, `src/core/daily_rewards.gd`, `data/missions.json`, `data/account_levels.json`, new `data/onboarding.json`, `tools/balance/economy.py` |

* A writes its first-session flags to `Profile.data.flags` and funnel timestamps to
  `Profile.data.onboarding_funnel` (B adds the default).
* A requests any hub spotlight it needs from B (e.g. "spotlight PLAY when `flags.ftue_return_hub`").
* Both streams add tests, plus a **fresh-player UI flow** that plays a brand-new profile through its first
  3 games and the reward steps.

## Verification
* Script check, system suite and the full UI flow test pass, including the new fresh-player flow.
* Measured on the fresh-player run:
  * the time from launch to the first throw;
  * the first-session funnel.
* Screenshots of every new screen and step.
* The economy targets still hold.
* The Windows build passes.
