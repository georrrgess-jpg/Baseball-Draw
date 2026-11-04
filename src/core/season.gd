class_name Season
extends RefCounted
## Season Pass (Update 9): 14-day seasons on a fixed calendar, 30 free tiers of rewards earned with
## season XP from games, missions and the Daily Challenge. State: Profile.data.season.
## FOUNDATION STUB: the economy stream (D) implements the rules in docs/plans/UPDATE_9_PLAN.md.

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


## {id, number, name, start, end, seconds_left}
static func current() -> Dictionary:
	return {"id": 1, "number": 1, "name": "Season 1", "start": EPOCH_DATE, "end": "", "seconds_left": SEASON_DAYS * 86400}


static func xp() -> int:
	return int(Profile.data.get("season", {}).get("xp", 0))


static func tier() -> int:
	return mini(TIERS, xp() / XP_PER_TIER)


## {tier, xp_in, xp_need}: progress inside the current tier.
static func tier_progress() -> Dictionary:
	return {"tier": tier(), "xp_in": xp() % XP_PER_TIER, "xp_need": XP_PER_TIER}


## [{tier, reward, claimed, reached}]
static func tiers() -> Array:
	return []


static func claimable() -> Array:
	return []


static func claim(_tier: int) -> Dictionary:
	return {}


static func claim_all() -> Array:
	return []


## Adds season XP; returns the tiers newly reached.
static func add_xp(_n: int, _source := "") -> Array:
	return []


static func reward_text(_reward: Dictionary) -> String:
	return ""
