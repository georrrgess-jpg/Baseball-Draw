class_name DailyChallenge
extends RefCounted
## Daily Challenge: one seeded game per local calendar day, offline. The date fixes the
## format (3 or 5 innings), difficulty, stadium, an 8-card deck from every card in the game,
## one modifier and the bosses (data/daily.json). Cards play at a fixed level so the rules
## are the same for everyone. Daily games never use the Continue Run slot: they are not
## saved mid-game and the player's saved run is kept. The profile keeps the best score per
## day and a streak of consecutive days played (Profile.data.daily).

const DATA_PATH := "res://data/daily.json"

## Tests and screenshots can pin the date (also `-- --daily-date=YYYY-MM-DD`).
static var date_override := ""
static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


# ---------------------------------------------------------------- dates

static func today() -> String:
	if date_override != "":
		return date_override
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--daily-date="):
			return a.split("=")[1]
	return Time.get_date_string_from_system()


## Whole days from `a` to `b` (both "YYYY-MM-DD"); positive when b is later.
static func days_between(a: String, b: String) -> int:
	var ta := Time.get_unix_time_from_datetime_string(a + "T12:00:00")
	var tb := Time.get_unix_time_from_datetime_string(b + "T12:00:00")
	return int(round(float(tb - ta) / 86400.0))


static func shift_date(date: String, days: int) -> String:
	var t := Time.get_unix_time_from_datetime_string(date + "T12:00:00") + days * 86400
	return Time.get_date_string_from_unix_time(t)


## Seconds until the next local midnight (the next challenge).
static func seconds_to_next() -> int:
	var t := Time.get_time_dict_from_system()
	return maxi(0, 86400 - (int(t.hour) * 3600 + int(t.minute) * 60 + int(t.second)))


static func countdown_text(secs := -1) -> String:
	if secs < 0:
		secs = seconds_to_next()
	var h := secs / 3600
	var m := (secs % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, secs % 60]


## "Tue 27 Oct"
static func pretty_date(date: String) -> String:
	var t := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	var d := Time.get_datetime_dict_from_unix_time(t)
	var wd: String = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][int(d.weekday)]
	var mo: String = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][int(d.month) - 1]
	return "%s %d %s" % [wd, int(d.day), mo]


# ---------------------------------------------------------------- rules

static func seed_for(date: String) -> int:
	return absi(("baseball-draw-daily:" + date).hash())


## The day's rules: {date, seed, format, format_name, mode, innings, difficulty, arena, deck,
## modifier, bosses, card_level}. Deterministic: the same date always gives the same rules.
static func rules_for(date: String) -> Dictionary:
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_for(date)
	# Format (weighted).
	var formats: Array = d.get("formats", [])
	var total := 0.0
	for f in formats:
		total += float(f.get("weight", 1.0))
	var x := rng.randf() * total
	var fmt: Dictionary = formats[0] if not formats.is_empty() else {"id": "sprint", "mode": "daily", "name": "Sprint", "difficulties": ["standard"]}
	for f in formats:
		x -= float(f.get("weight", 1.0))
		if x <= 0.0:
			fmt = f
			break
	var mode := DB.mode(str(fmt.mode))
	var diffs: Array = fmt.get("difficulties", ["standard"])
	var difficulty := str(diffs[rng.randi() % diffs.size()])
	if not DB.difficulties.has(difficulty):
		difficulty = "standard"
	# Any stadium, locked ones too: the daily is a chance to play them.
	var arena: String = DB.arena_order[rng.randi() % DB.arena_order.size()]
	# Deck: two cards per category from every non-signature card, filled up if a category runs short.
	var deck: Array = []
	for cat in DB.CATEGORY_ORDER:
		var pool: Array = []
		for cid in DB.card_order:
			var c := DB.card(cid)
			if str(c.category) == cat and str(c.get("linked", "")) == "":
				pool.append(cid)
		for i in 2:
			if pool.is_empty():
				break
			deck.append(pool.pop_at(rng.randi() % pool.size()))
	var rest: Array = DB.card_order.filter(func(cid: String) -> bool: return not cid in deck and str(DB.card(cid).get("linked", "")) == "")
	while deck.size() < Profile.DECK_SIZE and not rest.is_empty():
		deck.append(rest.pop_at(rng.randi() % rest.size()))
	# One modifier ("no shields" only where the difficulty has shields to lose).
	var mods: Array = []
	for mid in d.get("modifier_pool", []):
		var md := modifier_def(str(mid))
		if md.is_empty():
			continue
		if md.has("start_shields") and int(DB.difficulty(difficulty).get("shields", 0)) <= int(md.start_shields):
			continue
		mods.append(str(mid))
	var modifier: String = mods[rng.randi() % mods.size()] if not mods.is_empty() else ""
	# Bosses: one per boss inning of the format, all different.
	var boss_pool: Array = d.get("bosses", ["iron_slugger"]).duplicate()
	var bosses := {}
	var boss_innings: Array = mode.get("bosses", {}).keys()
	boss_innings.sort_custom(func(a, b) -> bool: return int(a) < int(b))
	for k in boss_innings:
		if boss_pool.is_empty():
			boss_pool = d.get("bosses", ["iron_slugger"]).duplicate()
		bosses[str(k)] = boss_pool.pop_at(rng.randi() % boss_pool.size())
	return {
		"date": date, "seed": int(rng.randi()), "format": str(fmt.id), "format_name": str(fmt.name),
		"mode": str(fmt.mode), "innings": int(mode.get("innings", 3)), "difficulty": difficulty, "arena": arena,
		"deck": deck, "modifier": modifier, "bosses": bosses, "card_level": int(d.get("card_level", 3)),
	}


static func today_rules() -> Dictionary:
	return rules_for(today())


## A battle config for the day's challenge (the player's own team and formation).
static func config_for(date := "") -> Dictionary:
	var r := rules_for(date if date != "" else today())
	var p: Dictionary = Profile.data
	return {
		"mode": r.mode, "difficulty": r.difficulty, "arena": r.arena, "deck": r.deck.duplicate(),
		"team": p.team.duplicate(), "captain": p.captain, "formation": p.formation, "seed": int(r.seed), "resume": null,
		"modifiers": [r.modifier] if str(r.modifier) != "" else [], "bosses": r.bosses.duplicate(),
		"card_level": int(r.card_level), "daily": r.date,
	}


static func is_daily_mode(mode_id: String) -> bool:
	return mode_id in ["daily", "daily_long"]


# ---------------------------------------------------------------- modifiers

## A modifier by id: the shared endless/challenge modifiers first, then the daily-only ones.
static func modifier_def(id: String) -> Dictionary:
	if DB.endless_modifiers.has(id):
		return DB.endless_modifiers[id]
	for m in data().get("modifiers", []):
		if str(m.get("id", "")) == id:
			return m
	return {}


## While a daily game runs its daily-only modifiers are listed with the shared ones, so the
## battle HUD shows them like any other modifier. Session.start switches this per game.
static func set_active(on: bool) -> void:
	for m in data().get("modifiers", []):
		var id := str(m.get("id", ""))
		if on:
			DB.endless_modifiers[id] = m
		elif DB.endless_modifiers.get(id) == m:
			DB.endless_modifiers.erase(id)


# ---------------------------------------------------------------- records

static func day_record(date: String) -> Dictionary:
	return Profile.data.daily.days.get(date, {})


static func best_score(date := "") -> int:
	return int(day_record(date if date != "" else today()).get("best", 0))


static func played(date := "") -> bool:
	return int(day_record(date if date != "" else today()).get("attempts", 0)) > 0


## Consecutive days played, counting today or yesterday as still alive.
static func current_streak() -> int:
	var d: Dictionary = Profile.data.daily
	var last := str(d.get("last_date", ""))
	if last == "":
		return 0
	var gap := days_between(last, today())
	return int(d.get("streak", 0)) if gap <= 1 else 0


static func rewards() -> Dictionary:
	return data().get("rewards", {"first_coins": 150, "first_pack": "rookie", "win_pack": "pro"})


## Records a finished daily game (called by Rewards.apply) and grants the daily bonus:
## coins and a pack the first time each day, another pack for the first win of the day.
## Returns the summary the Results screen shows.
static func record_result(run: RunState, won: bool) -> Dictionary:
	var date := str(run.config.get("daily", today()))
	var d: Dictionary = Profile.data.daily
	var days: Dictionary = d.days
	var day: Dictionary = days.get(date, {})
	var first := not bool(day.get("rewarded", false))
	var prev_best := int(day.get("best", 0))
	day["attempts"] = int(day.get("attempts", 0)) + 1
	day["best"] = maxi(prev_best, run.score)
	day["won"] = bool(day.get("won", false)) or won
	var rw := rewards()
	var bonus_coins := 0
	var bonus_packs: Array = []
	if first:
		day["rewarded"] = true
		bonus_coins = int(rw.get("first_coins", 0))
		Profile.add_coins(bonus_coins)
		Profile.add_pack(str(rw.get("first_pack", "rookie")), "Daily Challenge %s" % pretty_date(date))
		bonus_packs.append(str(rw.get("first_pack", "rookie")))
		# Streak: consecutive calendar days with a finished daily game.
		var last := str(d.get("last_date", ""))
		var gap := 999 if last == "" else days_between(last, date)
		if gap == 1:
			d["streak"] = int(d.get("streak", 0)) + 1
		elif gap > 1:
			d["streak"] = 1
		elif gap == 0 and int(d.get("streak", 0)) == 0:
			d["streak"] = 1
		if gap >= 0:
			d["last_date"] = date
		d["best_streak"] = maxi(int(d.get("best_streak", 0)), int(d.streak))
		d["played"] = int(d.get("played", 0)) + 1
	if won and not bool(day.get("win_rewarded", false)):
		day["win_rewarded"] = true
		Profile.add_pack(str(rw.get("win_pack", "pro")), "Daily Challenge win")
		bonus_packs.append(str(rw.get("win_pack", "pro")))
		d["wins"] = int(d.get("wins", 0)) + 1
	days[date] = day
	_prune(days)
	Profile.set_stat_max("daily_streak", float(d.get("streak", 0)))
	return {
		"date": date, "score": run.score, "best": int(day.best), "prev_best": prev_best,
		"new_best": run.score > prev_best and run.score > 0, "attempts": int(day.attempts), "first_today": first,
		"streak": int(d.get("streak", 0)), "best_streak": int(d.get("best_streak", 0)),
		"bonus_coins": bonus_coins, "bonus_packs": bonus_packs,
	}


## Keeps the last 30 days of records.
static func _prune(days: Dictionary) -> void:
	var keys: Array = days.keys()
	if keys.size() <= 30:
		return
	keys.sort()
	for k in keys.slice(0, keys.size() - 30):
		days.erase(k)
