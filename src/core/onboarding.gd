class_name Onboarding
extends RefCounted
## Update 13 "Rookie Camp": new-player onboarding and early retention (data/onboarding.json).
##
## * Progressive feature unlocks: the hub's features open in groups by account level or Rookie Path step
##   (whichever comes first). Locked ones stay on the hub as teasers ("Unlocks at level 3"); the first hub
##   visit after one opens shows NEW FEATURE UNLOCKED with a spotlight (pending_unlocks / mark_announced).
##   An established manager (level 5+, 5+ games, flags.unlock_all, or a save from before this update with
##   that much play) has everything open, silently.
## * Rookie Path: the ten-step starter track (data/missions.json "starter", run by Missions). Its finale lets
##   the player sign a free agent of their choice.
## * Choices: picks the hub shows as a popup, one at a time: an Epic card after the third game (cards that
##   suit the player's deck), a Legendary on Rookie Week day 7, a free agent at the end of the Rookie Path.
## * Rookie Week: a 7-day bonus calendar for new managers next to the normal login calendar. One claim per
##   calendar day; a missed day pauses it (it never resets); it leaves the hub after day 7.
## * Early pacing: a bonus pack for each of the first three games, a consolation reward and an easier
##   difficulty after a loss in the first five games, Auto Build suggested after two early losses in a row
##   (on_game_end, called by Rewards.apply). Faster account levels 1-5 live in data/account_levels.json.
## * Welcome back: after 3+ days away the hub pays a bonus and shows a short recap (on_hub_open).
## * Badge budget: a new manager sees at most two attention badges on the hub, by priority.
## State: Profile.data.onboarding (default_state); first-session timestamps: Profile.data.onboarding_funnel.

const DATA_PATH := "res://data/onboarding.json"
const VERSION := 13

static var _data: Dictionary = {}
## The hub's blocking onboarding popups (unlock cards, picks, welcome back, coach tips) stay off in
## automated runs (--ui-test, --smoke-test, --no-popups) unless a test turns them on.
static var force_popups := false


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		if _data.is_empty():
			_data = {"features": []}
	return _data


static func default_state() -> Dictionary:
	return {"version": VERSION, "established": false, "rookie": true, "announced": [],
		"week": {"claims": 0, "last_claim": ""}, "losses_row": 0, "epic_offered": false,
		"choices": [], "coach": {}, "last_seen": "", "welcome": {}}


## First-session funnel timestamps (written by the first-session flow; "" until reached).
static func funnel_default() -> Dictionary:
	return {"first_launch": "", "first_game": "", "first_win": "", "first_pack": "", "game_2": "", "day2_return": ""}


static func state() -> Dictionary:
	if typeof(Profile.data.get("onboarding")) != TYPE_DICTIONARY:
		Profile.data["onboarding"] = default_state()
	return Profile.data.onboarding


## Writes a funnel timestamp once (later calls keep the first one).
static func funnel_mark(key: String) -> void:
	if typeof(Profile.data.get("onboarding_funnel")) != TYPE_DICTIONARY:
		Profile.data["onboarding_funnel"] = funnel_default()
	var f: Dictionary = Profile.data.onboarding_funnel
	if str(f.get(key, "")) == "":
		f[key] = Time.get_datetime_string_from_system()


static func popups_enabled() -> bool:
	if force_popups:
		return true
	var args := OS.get_cmdline_user_args()
	return not ("--ui-test" in args or "--smoke-test" in args or "--no-popups" in args)


# ---------------------------------------------------------------- established managers

## True when every feature is open: account level 5+, 5+ games, flags.unlock_all, or marked established
## (a pre-Update 13 save with that much play, or make_established()).
static func established() -> bool:
	if Profile.data.is_empty():
		return true
	if bool(state().get("established", false)) or bool(Profile.data.get("flags", {}).get("unlock_all", false)):
		return true
	var e: Dictionary = data().get("established", {})
	return int(Profile.data.get("level", 1)) >= int(e.get("level", 5)) or Profile.stat("runs_played") >= float(e.get("games", 5))


## A manager the hub still guides: features are locked or the Rookie Path is running.
static func is_new_player() -> bool:
	if Profile.data.is_empty() or bool(state().get("established", false)):
		return false
	return not established() or path_active()


## Opens everything at once, silently (no unlock cards): the Rookie Path is finished, Rookie Week and the
## Epic pick are skipped. Used for managers who already know the game and by tests that need every screen.
static func make_established() -> void:
	var s := state()
	s.established = true
	s.rookie = false
	s.epic_offered = true
	s.announced = feature_ids()
	s.choices = []
	s.coach = {}
	var m := Missions.state()
	m.starter_step = path_steps().size()
	m.starter = {}


# ---------------------------------------------------------------- features

static func features() -> Array:
	return data().get("features", [])


static func feature_ids() -> Array:
	return features().map(func(f: Dictionary) -> String: return str(f.id))


static func feature(id: String) -> Dictionary:
	for f in features():
		if str(f.id) == id:
			return f
	return {}


static func has_feature(id: String) -> bool:
	return not feature(id).is_empty()


## Ungated ids (not in the list) are always open.
static func is_unlocked(id: String) -> bool:
	var f := feature(id)
	if f.is_empty() or established():
		return true
	if int(Profile.data.get("level", 1)) >= int(f.get("level", 1)):
		return true
	return f.has("path") and path_claimed() >= int(f.path)


static func unlock_level(id: String) -> int:
	return int(feature(id).get("level", 1))


## "Unlocks at level 3 or Rookie Path step 5" ("" when open).
static func lock_text(id: String) -> String:
	if is_unlocked(id):
		return ""
	var f := feature(id)
	var t := "Unlocks at level %d" % int(f.get("level", 1))
	if f.has("path") and path_active():
		t += " or Rookie Path step %d" % int(f.path)
	return t


## "LV 3" for chips and tiles ("" when open).
static func lock_short(id: String) -> String:
	return "" if is_unlocked(id) else "LV %d" % unlock_level(id)


## A mode's lock: the game's own rule (MenuScreen.mode_locked_reason) or the onboarding unlock.
static func mode_lock(mode_id: String) -> String:
	var own := MenuScreen.mode_locked_reason(mode_id)
	if own != "" and mode_id != "ranked":
		return own
	var mine := lock_text(mode_id)
	return mine if mine != "" else own


## Features open now that have not had their NEW FEATURE UNLOCKED card yet (the starting ones never do).
static func pending_unlocks() -> Array:
	var s := state()
	var out: Array = []
	for f in features():
		if int(f.get("level", 1)) <= 1 and not f.has("path"):
			continue
		if not str(f.id) in s.announced and is_unlocked(str(f.id)):
			out.append(f)
	return out


static func mark_announced(id: String) -> void:
	var s := state()
	if not id in s.announced:
		(s.announced as Array).append(id)
	Profile.save_soon()


## The next locked features (the lowest unlock level first), for the hub's COMING UP teaser.
static func next_locked(n := 4) -> Array:
	var out: Array = []
	for f in features():
		if not is_unlocked(str(f.id)):
			out.append(f)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("level", 1)) < int(b.get("level", 1)))
	return out.slice(0, n)


# ---------------------------------------------------------------- Rookie Path

static func path_steps() -> Array:
	return Missions.starter_steps()


## Steps claimed so far (0-10).
static func path_claimed() -> int:
	if Profile.data.is_empty():
		return 0
	return int(Missions.state().get("starter_step", 0))


static func path_active() -> bool:
	return path_claimed() < path_steps().size()


## The running step instance ({} once the path is done).
static func path_current() -> Dictionary:
	if not Missions.starter_active():
		return {}
	return Missions.state().starter


static func path_can_claim() -> bool:
	var inst := path_current()
	return not inst.is_empty() and Missions.can_claim(inst)


## Claims the current step (Missions pays it and moves on). Returns the reward ({} when not ready).
static func claim_path() -> Dictionary:
	if not path_can_claim():
		return {}
	return Missions.claim("starter")


static func path_step_def(i: int) -> Dictionary:
	var steps := path_steps()
	return steps[i] if i >= 0 and i < steps.size() else {}


## The features that open when step `i` (0-based) is claimed.
static func unlocked_by_step(i: int) -> Array:
	var out: Array = []
	for f in features():
		if int(f.get("path", -1)) == i + 1:
			out.append(f)
	return out


# ---------------------------------------------------------------- choices (Epic, Legendary, free agent)

## Queues a pick the hub shows as a popup. kind: "epic" | "legendary" (cards) or "free_agent".
static func queue_choice(kind: String, source: String) -> void:
	var opts := options_for(kind)
	var s := state()
	if opts.is_empty():
		if kind == "free_agent":   # every free agent already signed: coins instead
			Profile.add_coins(5000)
			Profile.notice.emit("Every free agent is already on your team: 5,000 coins instead!")
		return
	(s.choices as Array).append({"kind": kind, "options": opts, "source": source})
	Profile.save_soon()


static func pending_choice() -> Dictionary:
	var list: Array = state().choices
	return list[0] if not list.is_empty() and typeof(list[0]) == TYPE_DICTIONARY else {}


static func options_for(kind: String) -> Array:
	match kind:
		"epic", "legendary":
			return card_options(kind, 3)
		"free_agent":
			var out: Array = []
			for fa in Shop.free_agents():
				if not bool(fa.signed):
					out.append(str(fa.id))
			return out
	return []


## Takes option `id` of the first pending choice. Returns {"kind", "id", "name"} ({} when not offered).
static func choose(id: String) -> Dictionary:
	var c := pending_choice()
	if c.is_empty() or not id in (c.get("options", []) as Array):
		return {}
	var kind := str(c.kind)
	var nm := ""
	match kind:
		"epic", "legendary":
			Profile.grant_card(id)
			nm = str(DB.card(id).get("name", id))
			Profile.bump_stat("rookie_picks")
		"free_agent":
			Profile.unlock_defender(id)
			nm = str(DB.defender(id).get("name", id))
			Profile.bump_stat("rookie_picks")
	(state().choices as Array).pop_front()
	Profile.changed.emit()
	Profile.save_soon()
	return {"kind": kind, "id": id, "name": nm}


## `n` cards of `rarity` that suit the player's deck and team: unowned first, each scored by DeckAI for the
## team, with a bonus for a role the deck is missing; different roles where possible. Signature cards only
## for defenders on the team. Deterministic.
static func card_options(rarity: String, n := 3) -> Array:
	var ctx := DeckAI.profile_context()
	var roles := deck_roles()
	var cands: Array = []
	for cid in DB.card_order:
		var c := DB.card(cid)
		if str(c.get("rarity", "")) != rarity:
			continue
		var linked := str(c.get("linked", ""))
		if linked != "" and not linked in Profile.data.team:
			continue
		var a := DeckAI.analyze(cid, 1)
		var s := DeckAI.card_score(a, "balanced", ctx)
		s += 2.5 * maxi(0, 2 - int(roles.get(str(a.role), 0)))
		if Profile.is_card_owned(cid):
			s -= 100.0
		cands.append({"id": cid, "score": s, "role": str(a.role)})
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		return float(x.score) > float(y.score) or (float(x.score) == float(y.score) and str(x.id) < str(y.id)))
	var out: Array = []
	var used := {}
	for pass_i in 2:   # first one per role, then fill up
		for cd in cands:
			if out.size() >= n:
				break
			if str(cd.id) in out or (pass_i == 0 and used.has(cd.role)):
				continue
			out.append(str(cd.id))
			used[cd.role] = true
	return out


## Role -> number of deck cards with it (DeckAI roles).
static func deck_roles() -> Dictionary:
	var out := {}
	for cid in Profile.data.get("deck", []):
		var r := str(DeckAI.analyze(str(cid), 1).get("role", ""))
		out[r] = int(out.get(r, 0)) + 1
	return out


## Why a picked card suits the deck: "Fills a gap: no Control card in your deck" / "Strong with Jax on your team".
static func card_reason(cid: String) -> String:
	var c := DB.card(cid)
	var role := str(DeckAI.analyze(cid, 1).get("role", ""))
	var role_name := str(DeckAI.ROLE_NAMES.get(role, role.capitalize()))
	var have := int(deck_roles().get(role, 0))
	var linked := str(c.get("linked", ""))
	if linked != "" and linked in Profile.data.team:
		return "%s's signature card, and %s is on your team" % [DB.defender(linked).name, DB.defender(linked).name]
	if have == 0:
		return "Fills a gap: no %s card in your deck yet" % role_name
	if have == 1:
		return "Backs up your only %s card" % role_name
	return "A stronger %s card for your deck" % role_name


# ---------------------------------------------------------------- Rookie Week

static func week_days() -> Array:
	return data().get("rookie_week", {}).get("days", [])


static func _week() -> Dictionary:
	var s := state()
	if typeof(s.get("week")) != TYPE_DICTIONARY:
		s["week"] = {"claims": 0, "last_claim": ""}
	return s.week


## Shown on the hub while a new manager still has days to claim.
static func week_active() -> bool:
	if Profile.data.is_empty() or not bool(state().get("rookie", false)):
		return false
	return int(_week().get("claims", 0)) < week_days().size()


static func week_claims() -> int:
	return int(_week().get("claims", 0))


## Day (1-7) the next claim pays.
static func week_day() -> int:
	return mini(week_claims() + 1, maxi(1, week_days().size()))


static func week_claimed_today() -> bool:
	return str(_week().get("last_claim", "")) == DailyChallenge.today()


static func week_can_claim() -> bool:
	if not week_active():
		return false
	var last := str(_week().get("last_claim", ""))
	return last == "" or DailyChallenge.days_between(last, DailyChallenge.today()) >= 1


static func week_reward(d: int) -> Dictionary:
	var days := week_days()
	if days.is_empty():
		return {}
	return (days[clampi(d, 1, days.size()) - 1] as Dictionary).duplicate(true)


## "2 Rookie Packs + 300 coins" (+ "Legendary of your choice").
static func reward_text(r: Dictionary) -> String:
	var t := Rewards.bundle_text(r)
	match str(r.get("choice", "")):
		"legendary":
			t += (" + " if t != "" else "") + "a Legendary of your choice"
		"epic":
			t += (" + " if t != "" else "") + "an Epic of your choice"
		"free_agent":
			t += (" + " if t != "" else "") + "sign a free agent of your choice"
	return t


## [{day, reward, text, claimed, today}] for the hub's Rookie Week card. `today` marks the day to claim now,
## or the one claimed today.
static func week_calendar() -> Array:
	var claims := week_claims()
	var done_today := week_claimed_today()
	var today_i := claims - 1 if done_today else claims
	var out: Array = []
	for i in week_days().size():
		var r := week_reward(i + 1)
		out.append({"day": i + 1, "reward": r, "text": reward_text(r), "claimed": i < claims, "today": i == today_i})
	return out


## Claims today's Rookie Week day. Returns {day, reward, granted, text} or {} when nothing to claim.
static func week_claim() -> Dictionary:
	if not week_can_claim():
		return {}
	var w := _week()
	var d := week_day()
	var r := week_reward(d)
	var got := Rewards.grant_bundle(r, "Rookie Week: day %d" % d)
	w.claims = week_claims() + 1
	w.last_claim = DailyChallenge.today()
	if str(r.get("choice", "")) != "":
		queue_choice(str(r.choice), "Rookie Week day %d" % d)
	Profile.bump_stat("rookie_week_claims")
	Profile.changed.emit()
	Profile.save_soon()
	return {"day": d, "reward": r, "granted": got, "text": reward_text(r)}


## "Next reward in 5h 12m" / "Day 3 is ready" / "Paused at day 3: claim it today".
static func week_status_text() -> String:
	if week_can_claim():
		var last := str(_week().get("last_claim", ""))
		if last != "" and DailyChallenge.days_between(last, DailyChallenge.today()) > 1:
			return "Paused at day %d: claim it today" % week_day()
		return "Day %d is ready to claim" % week_day()
	return "Next reward in %s" % UITheme.format_duration(DailyChallenge.seconds_to_next())


# ---------------------------------------------------------------- early pacing

## End-of-game pacing for a new manager (called by Rewards.apply after the game's stats are counted):
## the first games' bonus packs, the early-loss consolation and coach tip, and the Epic pick after game 3.
## Returns {"bonus_pack", "consolation", "coach", "epic_pick"} (only the keys that happened).
static func on_game_end(run: RunState, won: bool) -> Dictionary:
	var out := {}
	if Profile.data.is_empty():
		return out
	var s := state()
	var games := int(Profile.stat("runs_played"))
	if games == 1:
		funnel_mark("first_game")
	if games == 2:
		funnel_mark("game_2")
	if won:
		funnel_mark("first_win")
	if not bool(s.get("rookie", false)):
		return out
	var eg: Dictionary = data().get("early_games", {})
	var packs: Array = eg.get("packs", [])
	if games >= 1 and games <= packs.size():
		var pk := str(packs[games - 1])
		Profile.add_pack(pk, str(eg.get("source", "Rookie Camp bonus")))
		out["bonus_pack"] = pk
	var streak_mode := Rewards.counts_for_streak(run.mode_id)
	if won:
		s.losses_row = 0
		s.coach = {}
	elif streak_mode:
		s.losses_row = int(s.get("losses_row", 0)) + 1
	var cons: Dictionary = data().get("consolation", {})
	if not won and streak_mode and games <= int(cons.get("games", 5)):
		var r: Dictionary = cons.get("reward", {})
		var got := Rewards.grant_bundle(r, "Consolation: keep going!")
		out["consolation"] = got
		var easier := easier_difficulty(run.difficulty_id)
		var coach := {"easier": easier, "difficulty": run.difficulty_id, "mode": run.mode_id,
			"auto_build": int(s.losses_row) >= int(cons.get("coach_losses", 2)), "losses": int(s.losses_row), "reward": got}
		s.coach = coach
		out["coach"] = coach
	if games >= 3 and not bool(s.get("epic_offered", false)):
		s.epic_offered = true
		queue_choice("epic", "Your third game")
		out["epic_pick"] = true
	return out


## The next easier difficulty ("" on Rookie).
static func easier_difficulty(diff: String) -> String:
	var i := DB.difficulty_order.find(diff)
	return str(DB.difficulty_order[i - 1]) if i > 0 else ""


static func coach_tip() -> Dictionary:
	var c: Variant = state().get("coach", {})
	return c if typeof(c) == TYPE_DICTIONARY else {}


static func dismiss_coach() -> void:
	state().coach = {}
	Profile.save_soon()


## Puts the coach's easier difficulty in place.
static func take_easier() -> String:
	var e := str(coach_tip().get("easier", ""))
	if e != "" and DB.difficulties.has(e):
		Profile.data.difficulty = e
	dismiss_coach()
	return e


## Rebuilds the deck with Auto Build (balanced). Returns the new deck ([] when nothing changed).
static func auto_build_deck() -> Array:
	var r := DeckAI.build("balanced")
	var deck: Array = r.get("deck", [])
	if deck.size() == Profile.DECK_SIZE and deck != Profile.data.deck and Profile.set_deck(deck):
		return deck
	return []


# ---------------------------------------------------------------- welcome back

## Called when the hub opens: after 3+ days away pays the welcome-back bonus (the recap card shows it);
## notes the day-2 return for the funnel; remembers today.
static func on_hub_open() -> void:
	if Profile.data.is_empty():
		return
	var s := state()
	var today := DailyChallenge.today()
	var last := str(s.get("last_seen", ""))
	var wb: Dictionary = data().get("welcome_back", {})
	if last != "" and last != today:
		var away := DailyChallenge.days_between(last, today)
		if away >= 1:
			funnel_mark("day2_return")
		if away >= int(wb.get("days", 3)) and (s.get("welcome", {}) as Dictionary).is_empty():
			var r: Dictionary = wb.get("reward_long", {}) if away >= int(wb.get("long_days", 7)) else wb.get("reward", {})
			var got := Rewards.grant_bundle(r, "Welcome back bonus")
			s.welcome = {"days": away, "reward": r, "granted": got, "since": last, "date": today}
			Profile.bump_stat("welcome_backs")
	s.last_seen = today
	Profile.save_soon()


static func pending_welcome() -> Dictionary:
	var w: Variant = state().get("welcome", {})
	return w if typeof(w) == TYPE_DICTIONARY else {}


static func dismiss_welcome() -> void:
	state().welcome = {}
	Profile.save_soon()


## The recap card's "what's new" lines: [[icon, text], ...] (at most five).
static func welcome_recap() -> Array:
	var out: Array = []
	var news := str(data().get("welcome_back", {}).get("news", ""))
	if news != "":
		out.append(["star", news])
	if week_active() and week_can_claim():
		out.append(["gift", "Rookie Week waited for you: day %d is ready" % week_day()])
	if DailyRewards.can_claim():
		out.append(["calendar", "Daily Login: day %d is ready (the calendar paused, it never resets)" % DailyRewards.day()])
	if is_unlocked("missions"):
		out.append(["target", "New daily missions and a new Daily Challenge are waiting"])
	if is_unlocked("season"):
		var cur := Season.current()
		out.append(["progression", "%s: tier %d%s" % [str(cur.get("name", "Season")), Season.tier(),
			("  ·  ends in %s" % Season.countdown_text(int(cur.seconds_left))) if int(cur.get("seconds_left", 0)) > 0 else ""]])
	if Profile.pack_count() > 0:
		out.append(["deck", "%d unopened card pack%s" % [Profile.pack_count(), "" if Profile.pack_count() == 1 else "s"]])
	return out.slice(0, 5)


# ---------------------------------------------------------------- badge budget

## Attention badges the hub may show at once (a new manager: data "badge_budget"; otherwise no limit).
static func badge_budget() -> int:
	return int(data().get("badge_budget", 2)) if is_new_player() else 1000


## Lower is more important; unknown keys come last.
static func badge_rank(key: String) -> int:
	var order: Array = data().get("badge_priority", [])
	var i := order.find(key)
	return i if i >= 0 else 100 + order.size()


# ---------------------------------------------------------------- saves

## Saves from before Update 13 (no "onboarding" block): established managers get everything open silently;
## newer ones keep the guided hub, with the features they can already use counted as announced. The old
## 5-step starter chain maps onto the Rookie Path (steps whose lesson was already learnt are skipped).
static func migrate(loaded: Dictionary) -> void:
	if loaded.has("onboarding"):
		return
	var stats: Dictionary = loaded.get("stats", {}) if typeof(loaded.get("stats")) == TYPE_DICTIONARY else {}
	var flags: Dictionary = loaded.get("flags", {}) if typeof(loaded.get("flags")) == TYPE_DICTIONARY else {}
	var e: Dictionary = data().get("established", {})
	var est := int(loaded.get("level", 1)) >= int(e.get("level", 5)) or float(stats.get("runs_played", 0)) >= float(e.get("games", 5)) \
		or bool(flags.get("unlock_all", false))
	var s := state()
	if est:
		make_established()
	else:
		s.rookie = true
		s.epic_offered = float(stats.get("runs_played", 0)) >= 3.0
		var lm: Variant = loaded.get("missions")
		if typeof(lm) == TYPE_DICTIONARY and not (lm as Dictionary).has("path_version"):
			Missions.state().starter_step = migrate_starter_step(int(lm.get("starter_step", 0)), lm.get("starter", {}))
			Missions.state().starter = {}
		var ann: Array = []
		for id in feature_ids():
			if is_unlocked(id):
				ann.append(id)
		s.announced = ann
	s.last_seen = DailyChallenge.today()


## Old "Learn the ropes" step (0-5: cards, win, pack, upgrade, daily) -> Rookie Path steps already done
## (win, pack, then the new deck step). A finished but unclaimed old step counts as done.
static func migrate_starter_step(old_step: int, old_inst: Variant) -> int:
	var done := old_step
	if typeof(old_inst) == TYPE_DICTIONARY and int((old_inst as Dictionary).get("progress", 0)) >= int((old_inst as Dictionary).get("goal", 1)) \
			and not bool((old_inst as Dictionary).get("claimed", false)) and (old_inst as Dictionary).has("id"):
		done += 1
	if done >= 3:
		return 2
	if done == 2:
		return 1
	return 0


## Repairs wrong types (Profile._sanitize).
static func sanitize() -> void:
	var s := state()
	var def := default_state()
	for k in def.keys():
		if not s.has(k) or typeof(s[k]) != typeof(def[k]):
			if not (typeof(def[k]) == TYPE_INT and typeof(s.get(k)) == TYPE_FLOAT):
				s[k] = def[k]
	s.losses_row = maxi(0, int(s.losses_row))
	s.version = VERSION
	s.announced = (s.announced as Array).filter(func(x: Variant) -> bool: return typeof(x) == TYPE_STRING)
	var w: Dictionary = s.week
	w["claims"] = clampi(int(w.get("claims", 0)), 0, week_days().size())
	w["last_claim"] = str(w.get("last_claim", ""))
	s.choices = (s.choices as Array).filter(func(c: Variant) -> bool:
		return typeof(c) == TYPE_DICTIONARY and str(c.get("kind", "")) in ["epic", "legendary", "free_agent"] and typeof(c.get("options")) == TYPE_ARRAY)
	if typeof(Profile.data.get("onboarding_funnel")) != TYPE_DICTIONARY:
		Profile.data["onboarding_funnel"] = funnel_default()
