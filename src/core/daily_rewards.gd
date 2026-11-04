class_name DailyRewards
extends RefCounted
## Daily login calendar (Update 9): a 7-day cycle of rewards, claimed once per calendar day.
## Missing a day pauses the calendar (it never resets). State: Profile.data.login.
## FOUNDATION STUB: the economy stream (D) implements the rules in docs/plans/UPDATE_9_PLAN.md.

const DATA_PATH := "res://data/login_rewards.json"


static func default_state() -> Dictionary:
	return {"day": 0, "last_claim": "", "streak": 0, "best": 0}


## [{day (1-7), reward, claimed, today}]
static func calendar() -> Array:
	return []


static func can_claim() -> bool:
	return false


static func claim() -> Dictionary:
	return {}


## Calendar day (1-7) the next claim pays out.
static func day() -> int:
	return int(Profile.data.get("login", {}).get("day", 0)) % 7 + 1


static func streak() -> int:
	return int(Profile.data.get("login", {}).get("streak", 0))


static func reward_text(_reward: Dictionary) -> String:
	return ""
