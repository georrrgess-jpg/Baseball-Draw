class_name Missions
extends RefCounted
## Missions (Update 6): three daily missions (one per tier), one weekly mission and the
## "Learn the ropes" starter chain for new managers (data/missions.json).
##
## * Generation is deterministic per (local day, profile): the same day always rolls the
##   same three missions; the weekly mission is fixed per week (weeks start on Monday).
## * Progress comes from events: every Profile.bump_stat (live during games: outs, cards,
##   double plays, bosses; and outside games: packs opened, cards upgraded) and the
##   end-of-game events Rewards.apply sends (wins, card categories, outs per defender,
##   best combo, Daily Challenge, Base Stealers caught ...).
## * One free reroll per day replaces one unclaimed daily mission with another of its tier.
## * A finished mission is claimed once for its reward (coins, a pack, stars). Missions
##   finished but not claimed when the day or week rolls over are paid out automatically.
## State lives in Profile.data.missions; older saves get the defaults (Profile._sanitize).

const DATA_PATH := "res://data/missions.json"
const TIERS := [1, 2, 3]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func default_state() -> Dictionary:
	return {"day": "", "daily": [], "rerolls": 0, "week": "", "weekly": [], "starter_step": 0, "starter": {},
		"completed": 0, "fresh": []}


static func state() -> Dictionary:
	if typeof(Profile.data.get("missions")) != TYPE_DICTIONARY:
		Profile.data["missions"] = default_state()
	return Profile.data.missions


# ---------------------------------------------------------------- dates

static func today() -> String:
	return DailyChallenge.today()


## The Monday that starts the week of `date` ("YYYY-MM-DD").
static func week_of(date: String) -> String:
	var t := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	var wd := int(Time.get_datetime_dict_from_unix_time(t).weekday)   # 0 = Sunday
	return DailyChallenge.shift_date(date, -((wd + 6) % 7))


## Seconds until the weekly mission changes (next Monday, local midnight).
static func seconds_to_next_week() -> int:
	var d := today()
	var days_left := 7 - DailyChallenge.days_between(week_of(d), d) - 1
	return DailyChallenge.seconds_to_next() + days_left * 86400


# ---------------------------------------------------------------- generation

## Rolls today's / this week's missions when the day or week changed. Cheap when nothing changed.
static func refresh() -> void:
	var s := state()
	var d := today()
	if str(s.day) != d:
		_payout_unclaimed(s.daily)
		s.day = d
		s.rerolls = 0
		s.fresh = []
		s.daily = generate_daily(d)
	var w := week_of(d)
	if str(s.week) != w:
		_payout_unclaimed(s.weekly)
		s.week = w
		s.weekly = generate_weekly(w)
	if (s.starter as Dictionary).is_empty() and int(s.starter_step) < starter_steps().size():
		s.starter = _starter_instance(int(s.starter_step))


static func _rng(key: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(("missions:%s:%s" % [key, str(Profile.data.get("created", ""))]).hash())
	return rng


## Three missions for `date`, one per tier. Deterministic for a given date and profile.
static func generate_daily(date: String) -> Array:
	var rng := _rng("day:" + date)
	var out: Array = []
	for tier in TIERS:
		var pool := _pool_for_tier(tier, [])
		if pool.is_empty():
			continue
		out.append(_instance(_pick(pool, rng), rng, "daily"))
	return out


static func generate_weekly(week: String) -> Array:
	var rng := _rng("week:" + week)
	var pool: Array = data().get("weekly", [])
	if pool.is_empty():
		return []
	return [_instance(pool[rng.randi() % pool.size()], rng, "weekly")]


static func _pool_for_tier(tier: int, exclude: Array) -> Array:
	var lvl := int(Profile.data.get("level", 1))
	var out: Array = []
	for def in data().get("daily", []):
		if int(def.get("tier", 1)) != tier or str(def.id) in exclude:
			continue
		if int(def.get("min_level", 1)) > lvl:
			continue
		out.append(def)
	return out


static func _pick(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	return pool[rng.randi() % pool.size()]


static func _instance(def: Dictionary, rng: RandomNumberGenerator, kind: String) -> Dictionary:
	var g: Array = def.get("goal", [1, 1])
	var step := maxi(1, int(def.get("step", 1)))
	var goal := rng.randi_range(int(g[0]) / step, int(g[g.size() - 1]) / step) * step
	var inst := {"id": str(def.id), "kind": kind, "event": str(def.event), "goal": maxi(1, goal), "progress": 0,
		"claimed": false, "max": bool(def.get("max", false)), "tier": int(def.get("tier", 0))}
	if "{who}" in inst.event:
		var team: Array = Profile.data.get("team", Profile.STARTER_TEAM)
		var who: String = team[rng.randi() % team.size()] if not team.is_empty() else "ace"
		inst.event = inst.event.replace("{who}", who)
		inst["who"] = who
	if "{diff}" in inst.event:
		var diff := difficulty_for_level(int(Profile.data.get("level", 1)))
		inst.event = inst.event.replace("{diff}", diff)
		inst["diff"] = diff
	return inst


## The difficulty a "win on X" mission asks for at this account level.
static func difficulty_for_level(level: int) -> String:
	var diff := "rookie"
	for row in data().get("difficulty_by_level", []):
		if level >= int(row[0]):
			diff = str(row[1])
	return diff


# ---------------------------------------------------------------- starter chain

static func starter_steps() -> Array:
	return data().get("starter", [])


static func _starter_instance(step: int) -> Dictionary:
	var def: Dictionary = starter_steps()[step]
	return {"id": str(def.id), "kind": "starter", "event": str(def.event), "goal": int(def.goal), "progress": 0,
		"claimed": false, "max": false, "tier": 0, "step": step}


static func starter_active() -> bool:
	refresh()
	return not (state().starter as Dictionary).is_empty()


# ---------------------------------------------------------------- queries

static func def_for(inst: Dictionary) -> Dictionary:
	var kind := str(inst.get("kind", "daily"))
	var key := "starter" if kind == "starter" else ("weekly" if kind == "weekly" else "daily")
	for def in data().get(key, []):
		if str(def.id) == str(inst.id):
			return def
	return {}


static func text(inst: Dictionary) -> String:
	var t := str(def_for(inst).get("text", inst.id))
	t = t.replace("{n}", UITheme.format_int(int(inst.goal)))
	if inst.has("who"):
		t = t.replace("{who}", str(DB.defender(str(inst.who)).get("name", inst.who)))
	if inst.has("diff"):
		t = t.replace("{diff}", str(DB.difficulty(str(inst.diff)).get("name", inst.diff)))
	return t


static func hint(inst: Dictionary) -> String:
	return str(def_for(inst).get("hint", ""))


static func reward(inst: Dictionary) -> Dictionary:
	if inst.kind == "starter":
		return def_for(inst).get("reward", {})
	var rw: Dictionary = data().get("rewards", {})
	if inst.kind == "weekly":
		return rw.get("weekly", {})
	return rw.get(str(inst.tier), {"coins": 100})


static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if int(r.get("coins", 0)) > 0:
		parts.append("%s coins" % UITheme.format_int(int(r.coins)))
	if str(r.get("pack", "")) != "":
		parts.append(str(DB.pack(str(r.pack)).get("name", r.pack)))
	if int(r.get("stars", 0)) > 0:
		parts.append("%d stars" % int(r.stars))
	return " + ".join(parts)


static func is_done(inst: Dictionary) -> bool:
	return int(inst.progress) >= int(inst.goal)


static func can_claim(inst: Dictionary) -> bool:
	return not inst.is_empty() and is_done(inst) and not bool(inst.claimed)


## Every active mission: the starter step (while the chain runs), the dailies, the weekly.
static func active() -> Array:
	refresh()
	var s := state()
	var out: Array = []
	if starter_active():
		out.append(s.starter)
	out.append_array(s.daily)
	out.append_array(s.weekly)
	return out


static func claimable_count() -> int:
	var n := 0
	for inst in active():
		if can_claim(inst):
			n += 1
	return n


## The active mission of `kind` with `id`, as [index, instance]; [-1, {}] when not active.
static func find(kind: String, id: String) -> Array:
	refresh()
	var s := state()
	match kind:
		"starter":
			if starter_active() and str(s.starter.id) == id:
				return [0, s.starter]
		"daily", "weekly":
			var list: Array = s[kind]
			for i in list.size():
				if str(list[i].id) == id:
					return [i, list[i]]
	return [-1, {}]


## Missions finished since the last call (for the Results screen); clears the list.
static func take_fresh() -> Array:
	var s := state()
	var out: Array = (s.fresh as Array).duplicate()
	s.fresh = []
	return out


# ---------------------------------------------------------------- progress

## Feeds an event into every matching active mission. `amount` is added, or for "max"
## missions taken as the best single value. Returns the missions this event completed.
static func on_event(key: String, amount: float = 1.0) -> Array:
	if Profile.data.is_empty() or amount <= 0.0:
		return []
	refresh()
	var s := state()
	var done: Array = []
	var lists: Array = [s.daily, s.weekly]
	if starter_active():
		lists.append([s.starter])
	for list in lists:
		for inst in list:
			if bool(inst.claimed) or is_done(inst) or not _matches(str(inst.event), key):
				continue
			if bool(inst.get("max", false)):
				inst.progress = maxi(int(inst.progress), int(amount))
			else:
				inst.progress = int(inst.progress) + int(amount)
			if is_done(inst):
				inst.progress = int(inst.goal)
				done.append(inst)
				(s.fresh as Array).append({"kind": inst.kind, "id": inst.id, "text": text(inst), "reward": reward(inst)})
				Profile.notice.emit("Mission complete: %s! Claim it in Progression → Missions." % text(inst))
	return done


static func _matches(event: String, key: String) -> bool:
	if event.ends_with("*"):
		return key.begins_with(event.substr(0, event.length() - 1))
	return event == key


## End-of-game events for a finished run (called by Rewards.apply). Only events that are not
## also Profile stats (those already arrive through Profile.bump_stat).
static func on_run(run: RunState, won: bool, cleared: int) -> void:
	on_event("games_played")
	if won:
		on_event("win")
		var di := maxi(0, DB.difficulty_order.find(run.difficulty_id))
		for i in di + 1:
			on_event("win_diff:" + str(DB.difficulty_order[i]))
	var casts: Variant = run.stats.get("card_casts", {})
	if typeof(casts) == TYPE_DICTIONARY:
		var by_cat := {}
		for cid in (casts as Dictionary).keys():
			if DB.cards.has(str(cid)):
				var cat := str(DB.card(str(cid)).category)
				by_cat[cat] = int(by_cat.get(cat, 0)) + int(casts[cid])
		for cat in by_cat.keys():
			on_event("cards_" + cat, float(by_cat[cat]))
	for did in (run.stats.get("outs_by", {}) as Dictionary).keys():
		on_event("outs_by:" + str(did), float(run.stats.outs_by[did]))
	on_event("max_combo", float(run.stats.get("max_combo", 0)))
	# clean_innings and caught_stealing arrive as Profile stats (Rewards.apply bumps them).
	if run.mode_id == "standard":
		on_event("innings_standard", float(cleared))
	if run.is_daily():
		on_event("daily_played")


# ---------------------------------------------------------------- reroll + claim

static func rerolls_left() -> int:
	refresh()
	return maxi(0, int(data().get("rerolls_per_day", 1)) - int(state().rerolls))


static func can_reroll(index: int) -> bool:
	var s := state()
	return rerolls_left() > 0 and index >= 0 and index < s.daily.size() and not bool(s.daily[index].claimed) \
		and not is_done(s.daily[index])


## Replaces daily mission `index` with another mission of the same tier (once per day).
static func reroll(index: int) -> bool:
	if not can_reroll(index):
		return false
	var s := state()
	var old: Dictionary = s.daily[index]
	var exclude: Array = s.daily.map(func(m: Dictionary) -> String: return str(m.id))
	var pool := _pool_for_tier(int(old.tier), exclude)
	if pool.is_empty():
		return false
	var rng := _rng("reroll:%s:%d:%d" % [s.day, index, int(s.rerolls)])
	s.daily[index] = _instance(_pick(pool, rng), rng, "daily")
	s.rerolls = int(s.rerolls) + 1
	Profile.save_soon()
	Profile.changed.emit()
	return true


## Grants a finished mission's reward once. `kind` is "daily", "weekly" or "starter";
## `index` picks the daily mission. Returns the reward ({} when nothing was claimed).
static func claim(kind: String, index := 0) -> Dictionary:
	refresh()
	var s := state()
	var inst: Dictionary = {}
	match kind:
		"daily":
			if index >= 0 and index < s.daily.size():
				inst = s.daily[index]
		"weekly":
			if index >= 0 and index < s.weekly.size():
				inst = s.weekly[index]
		"starter":
			inst = s.starter
	if not can_claim(inst):
		return {}
	inst.claimed = true
	var r := reward(inst)
	_grant(r, "Mission: " + text(inst))
	s.completed = int(s.completed) + 1
	if kind == "starter":
		s.starter_step = int(inst.get("step", 0)) + 1
		s.starter = _starter_instance(int(s.starter_step)) if int(s.starter_step) < starter_steps().size() else {}
	Profile.bump_stat("missions_completed")
	Profile.changed.emit()
	Profile.save_soon()
	return r


static func _grant(r: Dictionary, source: String) -> void:
	if int(r.get("coins", 0)) > 0:
		Profile.add_coins(int(r.coins))
	if int(r.get("stars", 0)) > 0:
		Profile.add_stars(int(r.stars))
	if str(r.get("pack", "")) != "":
		Profile.add_pack(str(r.pack), source)


## A day or week ended with finished but unclaimed missions: pay them out so nothing is lost.
static func _payout_unclaimed(list: Array) -> void:
	for inst in list:
		if typeof(inst) == TYPE_DICTIONARY and can_claim(inst):
			inst.claimed = true
			_grant(reward(inst), "Mission: " + text(inst))
			state().completed = int(state().completed) + 1
			Profile.bump_stat("missions_completed")


## Repairs saved mission state (unknown ids, wrong types). Called by Profile._sanitize.
static func sanitize() -> void:
	var s := state()
	var def := default_state()
	for k in def.keys():
		if not s.has(k) or typeof(s[k]) != typeof(def[k]):
			s[k] = def[k]
	for k in ["daily", "weekly"]:
		s[k] = (s[k] as Array).filter(func(m: Variant) -> bool:
			if typeof(m) != TYPE_DICTIONARY or not m.has("id") or not m.has("goal"):
				return false
			m["kind"] = k
			return not def_for(m).is_empty())
		for m in s[k]:
			m.progress = int(m.get("progress", 0))
			m.goal = maxi(1, int(m.goal))
			m.claimed = bool(m.get("claimed", false))
			m.tier = int(m.get("tier", 0))
	s.rerolls = maxi(0, int(s.rerolls))
	s.completed = maxi(0, int(s.completed))
	s.starter_step = clampi(int(s.starter_step), 0, starter_steps().size())
	var st: Dictionary = s.starter
	if not st.is_empty():
		st["kind"] = "starter"
	if not st.is_empty() and (not st.has("id") or def_for(st).is_empty()):
		s.starter = {}
	elif not st.is_empty():
		st.progress = int(st.get("progress", 0))
		st.goal = maxi(1, int(st.get("goal", 1)))
		st.claimed = bool(st.get("claimed", false))
