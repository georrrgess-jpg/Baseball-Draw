class_name DailyRewards
extends RefCounted
## Daily login calendar (Update 9): a 7-day cycle of rewards (data/login_rewards.json), claimed once per
## local calendar day. State: Profile.data.login = {day, last_claim, streak, best}.
##
## * `day` counts every claim ever made; the next claim pays calendar day (day % 7) + 1.
## * Missing a day pauses the calendar: the next claim simply pays the next day (it never resets).
## * The login streak counts consecutive calendar days with a claim (a missed day starts it again at 1);
##   `best` keeps the longest. Shown for flair; the "Regular" achievement wants 7 in a row.
## * Dates come from DailyChallenge.today() (tests pin it with DailyChallenge.date_override). A clock that
##   goes back never allows a second claim for a day already claimed.

const DATA_PATH := "res://data/login_rewards.json"
const CYCLE := 7

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
	return {"day": 0, "last_claim": "", "streak": 0, "best": 0}


static func state() -> Dictionary:
	if typeof(Profile.data.get("login")) != TYPE_DICTIONARY:
		Profile.data["login"] = default_state()
	return Profile.data.login


## The reward of calendar day `d` (1-7).
static func reward_for(d: int) -> Dictionary:
	var days: Array = data().get("days", [])
	if days.is_empty():
		return {"coins": 100}
	return (days[clampi(d, 1, days.size()) - 1] as Dictionary).duplicate(true)


static func claimed_today() -> bool:
	return str(state().get("last_claim", "")) == DailyChallenge.today()


## [{day (1-7), reward, claimed, today}] (+ text, icon). `today` marks the day claimable now, or the one
## claimed today.
static func calendar() -> Array:
	var s := state()
	var total := int(s.get("day", 0))
	var done_today := claimed_today()
	var pos := total % CYCLE   # days claimed in the current cycle
	if done_today and pos == 0 and total > 0:
		pos = CYCLE              # today's claim finished the cycle: show it complete
	var today_index := pos - 1 if done_today else pos
	var out: Array = []
	for i in CYCLE:
		var r := reward_for(i + 1)
		out.append({"day": i + 1, "reward": r, "claimed": i < pos, "today": i == today_index,
			"text": reward_text(r), "icon": Rewards.bundle_icon(r)})
	return out


static func can_claim() -> bool:
	if Profile.data.is_empty():
		return false
	var last := str(state().get("last_claim", ""))
	return last == "" or DailyChallenge.days_between(last, DailyChallenge.today()) >= 1


## Claims today's reward. Returns {day, reward, granted, text, streak, best}, or {} when already claimed.
static func claim() -> Dictionary:
	if not can_claim():
		return {}
	var s := state()
	var d := day()
	var r := reward_for(d)
	var today := DailyChallenge.today()
	var last := str(s.get("last_claim", ""))
	s.streak = int(s.get("streak", 0)) + 1 if last != "" and DailyChallenge.days_between(last, today) == 1 else 1
	s.best = maxi(int(s.get("best", 0)), int(s.streak))
	s.day = int(s.get("day", 0)) + 1
	s.last_claim = today
	var got := Rewards.grant_bundle(r, "Login reward: day %d" % d)
	Profile.bump_stat("login_claims")
	Profile.set_stat_max("login_streak", float(s.streak))
	Profile.changed.emit()
	Profile.save_soon()
	return {"day": d, "reward": r, "granted": got, "text": reward_text(r), "streak": int(s.streak), "best": int(s.best)}


## Calendar day (1-7) the next claim pays out.
static func day() -> int:
	return int(Profile.data.get("login", {}).get("day", 0)) % CYCLE + 1


## Consecutive calendar days with a claim, counting today or yesterday as still alive.
static func streak() -> int:
	var s: Dictionary = Profile.data.get("login", {})
	var last := str(s.get("last_claim", ""))
	if last == "" or DailyChallenge.days_between(last, DailyChallenge.today()) > 1:
		return 0
	return int(s.get("streak", 0))


static func reward_text(reward: Dictionary) -> String:
	return Rewards.bundle_text(reward)
