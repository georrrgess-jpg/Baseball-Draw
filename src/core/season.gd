class_name Season
extends RefCounted
## Season Pass (Update 9): 14-day seasons on a fixed calendar, 30 free tiers of rewards earned with
## season XP from games, missions and the Daily Challenge. State: Profile.data.season
## ({id, xp, claimed: [tiers], bonus_claimed}); rewards and XP sources: data/season.json.
##
## * Calendar: season 1 starts Monday 2026-11-02 (local calendar days); season n starts 14 x (n - 1) days
##   later and ends after its 14th day. Dates come from DailyChallenge.today(), which tests pin with
##   DailyChallenge.date_override. A date before the first season counts as season 1.
## * Season XP: 100 per finished game in a rewarded mode, +60 for a win, +100 for the day's first Daily
##   Challenge (Rewards.apply), +80 per mission claimed (Missions.claim and the day/week payout).
##   500 XP per tier, 30 tiers.
## * Tier rewards (coins, stars, packs, a Champion Pack at 15 and 30, this season's uniform at 30) are
##   claimed on the Season screen with claim(tier) or claim_all().
## * After tier 30 every 1,000 XP pays a Pro Pack at once (no claim needed; bonus_claimed counts them).
##   add_xp reports them as tiers 31, 32, ... after the real tiers it reached.
## * Rollover, the friendly option: when a new season begins, every tier the manager reached but did not
##   claim is paid out automatically (the old season's uniform too), then XP and claims start again.
##   Profile.notice says so and state.last_rollover keeps {season, tiers, to} for screens. A clock that
##   goes back to an earlier season never resets anything.

const DATA_PATH := "res://data/season.json"
const SEASON_DAYS := 14
const TIERS := 30
const XP_PER_TIER := 500
## First season starts Monday 2026-11-02 00:00 (local calendar days).
const EPOCH_DATE := "2026-11-02"

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
	return {"id": 0, "xp": 0, "claimed": [], "bonus_claimed": 0}


## Season XP per source: {game, win, mission, daily}.
static func xp_rules() -> Dictionary:
	return data().get("xp", {"game": 100, "win": 60, "mission": 80, "daily": 100})


static func bonus_xp() -> int:
	return maxi(1, int(data().get("bonus", {}).get("xp", 1000)))


# ---------------------------------------------------------------- calendar

## The season number a date ("YYYY-MM-DD") falls in.
static func number_for(date: String) -> int:
	var days := DailyChallenge.days_between(EPOCH_DATE, date)
	if days < 0:
		return 1
	return days / SEASON_DAYS + 1


static func start_of(number: int) -> String:
	return DailyChallenge.shift_date(EPOCH_DATE, (maxi(1, number) - 1) * SEASON_DAYS)


static func theme(number: int) -> String:
	var themes: Array = data().get("themes", [])
	return str(themes[(maxi(1, number) - 1) % themes.size()]) if not themes.is_empty() else ""


## The uniform id tier 30 of season `number` pays (gear.json uniforms, cycling through the season list).
static func uniform_for(number: int) -> String:
	var list: Array = data().get("uniforms", [])
	if list.is_empty():
		return ""
	var uid := str(list[(maxi(1, number) - 1) % list.size()])
	return uid if DB.uniforms.has(uid) else ""


## {id, number, name, start, end, seconds_left} (+ theme, day, days, uniform). `end` is the last day.
static func current() -> Dictionary:
	var today := DailyChallenge.today()
	var n := number_for(today)
	var start := start_of(n)
	var end := DailyChallenge.shift_date(start, SEASON_DAYS - 1)
	var days_after := maxi(0, DailyChallenge.days_between(today, end))
	return {"id": n, "number": n, "name": "Season %d" % n, "theme": theme(n), "start": start, "end": end,
		"seconds_left": days_after * 86400 + DailyChallenge.seconds_to_next(),
		"day": clampi(DailyChallenge.days_between(start, today) + 1, 1, SEASON_DAYS), "days": SEASON_DAYS,
		"uniform": uniform_for(n)}


## "9d 4h" / "5h 12m"
static func countdown_text(secs := -1) -> String:
	if secs < 0:
		secs = int(current().seconds_left)
	if secs >= 86400:
		return "%dd %dh" % [secs / 86400, (secs % 86400) / 3600]
	return DailyChallenge.countdown_text(secs)


# ---------------------------------------------------------------- state

static func state() -> Dictionary:
	if typeof(Profile.data.get("season")) != TYPE_DICTIONARY:
		Profile.data["season"] = default_state()
	return Profile.data.season


## Starts the current season in the state, paying out the old one's unclaimed tiers. Cheap when nothing changed.
static func refresh() -> void:
	if Profile.data.is_empty():
		return
	var s := state()
	var cur := number_for(DailyChallenge.today())
	var have := int(s.get("id", 0))
	if have == cur or have > cur:
		return
	if have <= 0:
		s.id = cur
		return
	_rollover(s, cur)


static func _rollover(s: Dictionary, cur: int) -> void:
	var old := int(s.id)
	var paid: Array = []
	for t in _claimable_in(s):
		_grant_tier(t, old)
		paid.append(t)
	s.id = cur
	s.xp = 0
	s.claimed = []
	s.bonus_claimed = 0
	s["last_rollover"] = {"season": old, "tiers": paid, "to": cur}
	if not paid.is_empty():
		Profile.notice.emit("Season %d ended: %d unclaimed reward%s added to your account." % [old, paid.size(), "" if paid.size() == 1 else "s"])
	Profile.changed.emit()
	Profile.save_soon()


static func xp() -> int:
	refresh()
	return int(state().get("xp", 0))


static func _tier_of(x: int) -> int:
	return mini(TIERS, x / XP_PER_TIER)


static func tier() -> int:
	return _tier_of(xp())


## {tier, xp_in, xp_need} inside the current tier. After tier 30: progress to the next bonus Pro Pack
## (bonus: true, bonus_earned).
static func tier_progress() -> Dictionary:
	var x := xp()
	var t := _tier_of(x)
	if t >= TIERS:
		var over := x - TIERS * XP_PER_TIER
		return {"tier": TIERS, "xp_in": over % bonus_xp(), "xp_need": bonus_xp(), "bonus": true, "bonus_earned": over / bonus_xp()}
	return {"tier": t, "xp_in": x - t * XP_PER_TIER, "xp_need": XP_PER_TIER, "bonus": false, "bonus_earned": 0}


## The reward of `t` in season `number` (default: the state's season). The uniform resolves to the season's
## uniform id, or to stars when it is already owned (`check_owned` false skips that: a claimed tier keeps
## showing its uniform). Tiers above 30 are the bonus Pro Packs.
static func tier_reward(t: int, number := 0, check_owned := true) -> Dictionary:
	if t > TIERS:
		return {"packs": (data().get("bonus", {}).get("packs", ["pro"]) as Array).duplicate(), "bonus": true}
	var r: Dictionary = (data().get("tiers", {}).get(str(t), {}) as Dictionary).duplicate(true)
	if r.has("uniform"):
		var uid := uniform_for(number if number > 0 else maxi(1, int(state().get("id", 1))))
		r.erase("uniform")
		if uid != "" and (not check_owned or not uid in Profile.data.get("uniforms_owned", [])):
			r["uniform"] = uid
		else:
			r["stars"] = int(r.get("stars", 0)) + int(data().get("uniform_owned_stars", 50))
	return r


## [{tier, reward, claimed, reached}] (+ xp: the season XP the tier needs, text).
static func tiers() -> Array:
	refresh()
	var s := state()
	var have := _tier_of(int(s.xp))
	var out: Array = []
	for t in range(1, TIERS + 1):
		var claimed: bool = t in s.claimed
		var r := tier_reward(t, 0, not claimed)
		out.append({"tier": t, "reward": r, "claimed": claimed, "reached": t <= have, "xp": t * XP_PER_TIER,
			"text": reward_text(r), "icon": Rewards.bundle_icon(r)})
	return out


static func _claimable_in(s: Dictionary) -> Array:
	var out: Array = []
	for t in range(1, _tier_of(int(s.get("xp", 0))) + 1):
		if not t in s.get("claimed", []):
			out.append(t)
	return out


static func claimable() -> Array:
	refresh()
	return _claimable_in(state())


static func _grant_tier(t: int, number: int) -> Dictionary:
	var r := tier_reward(t, number)
	var got := Rewards.grant_bundle(r, "Season %d: tier %d" % [number, t])
	(state().claimed as Array).append(t)
	Profile.bump_stat("season_tiers_claimed")
	return {"tier": t, "reward": r, "granted": got, "text": reward_text(r)}


## Claims a reached tier once. Returns {tier, reward, granted, text}, or {} when it cannot be claimed.
static func claim(t: int) -> Dictionary:
	if not t in claimable():
		return {}
	var res := _grant_tier(t, int(state().id))
	Profile.changed.emit()
	Profile.save_soon()
	return res


## Claims every reached tier; returns the claim results in tier order.
static func claim_all() -> Array:
	var out: Array = []
	for t in claimable():
		out.append(_grant_tier(int(t), int(state().id)))
	if not out.is_empty():
		Profile.changed.emit()
		Profile.save_soon()
	return out


## Adds season XP; returns the tiers newly reached (bonus Pro Packs after tier 30 as 31, 32, ...: those are
## granted at once).
static func add_xp(n: int, source := "") -> Array:
	if n <= 0 or Profile.data.is_empty():
		return []
	refresh()
	var s := state()
	var before := _tier_of(int(s.xp))
	s.xp = int(s.xp) + n
	var after := _tier_of(int(s.xp))
	var reached: Array = []
	for t in range(before + 1, after + 1):
		reached.append(t)
	var earned := maxi(0, int(s.xp) - TIERS * XP_PER_TIER) / bonus_xp()
	while int(s.bonus_claimed) < earned:
		s.bonus_claimed = int(s.bonus_claimed) + 1
		var t := TIERS + int(s.bonus_claimed)
		Rewards.grant_bundle(tier_reward(t), "Season %d: bonus reward" % int(s.id))
		reached.append(t)
	Profile.bump_stat("season_xp", float(n))
	Profile.set_stat_max("season_best_tier", float(after))
	if source != "game" and after > before:
		Profile.notice.emit("Season Pass: tier %d reached! Claim it on the Season screen." % after)
	Profile.changed.emit()
	return reached


static func reward_text(reward: Dictionary) -> String:
	return Rewards.bundle_text(reward)
