class_name DefenderLevels
extends RefCounted
## Defender levels 1–20 (Update 11): growth per level, the honours a level brings and the level road
## reward texts. The curve, the rewards and the max level live in data/defenders.json (read by DB);
## the late growth rate is read here so DB stays untouched.
##
##   growth(level) = level_growth × (min(level, late_growth_from) − 1) + level_growth_late × max(0, level − late_growth_from)
##                 = +6 % per level up to 10 (+54 %), then +3 % per level (+84 % at 20)
##
## Honours are derived from the level, so old saves need nothing new: All-Star from level 15
## (a badge), Hall of Famer at level 20 (a gold portrait frame and nameplate).

const DATA_PATH := "res://data/defenders.json"
const ALL_STAR := "all_star"
const HALL_OF_FAME := "hall_of_fame"
const BADGE_NAMES := {"all_star": "All-Star", "hall_of_fame": "Hall of Famer"}

static var _late := -1.0
static var _late_from := 10


static func _load() -> void:
	if _late >= 0.0:
		return
	_late = DB.defender_level_growth
	_late_from = DB.defender_max_level
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			_late = float(d.get("level_growth_late", DB.defender_level_growth))
			_late_from = int(d.get("late_growth_from", DB.defender_max_level))


## Total damage / signature power growth at a level (0.0 at level 1).
static func growth(level: int) -> float:
	_load()
	var l := clampi(level, 1, maxi(DB.defender_max_level, 1))
	var early := mini(l, _late_from) - 1
	var late := maxi(0, l - _late_from)
	return DB.defender_level_growth * float(early) + _late * float(late)


## Growth one level adds on reaching `level` (for the level road and the XP bars).
static func growth_step(level: int) -> float:
	return growth(level) - growth(level - 1)


## The first level that gives a badge (reads the level road, falls back to 15 / 20).
static func badge_level(badge: String) -> int:
	for k in DB.defender_level_rewards.keys():
		if str(DB.defender_level_rewards[k].get("badge", "")) == badge:
			return int(k)
	return 20 if badge == HALL_OF_FAME else 15


## "hall_of_fame", "all_star" or "" for a level.
static func honor(level: int) -> String:
	if level >= badge_level(HALL_OF_FAME):
		return HALL_OF_FAME
	if level >= badge_level(ALL_STAR):
		return ALL_STAR
	return ""


static func honor_of(id: String) -> String:
	if not Profile.is_defender_unlocked(id):
		return ""
	return honor(Profile.defender_level(id))


static func is_hall_of_famer(id: String) -> bool:
	return honor_of(id) == HALL_OF_FAME


static func is_all_star(id: String) -> bool:
	return honor_of(id) != ""


## "Champion Pack", "All-Star badge + 1,000 coins", "Hall of Famer frame + Champion Pack", "Choose a trait".
static func reward_text(r: Dictionary) -> String:
	var parts: Array = []
	if r.has("badge"):
		parts.append("%s %s" % [BADGE_NAMES.get(str(r.badge), str(r.badge).capitalize()), "frame" if str(r.badge) == HALL_OF_FAME else "badge"])
	if r.has("coins"):
		parts.append("%s coins" % UITheme.format_int(int(r.coins)))
	if r.has("pack"):
		parts.append(str(DB.pack(str(r.pack)).get("name", str(r.pack).capitalize() + " Pack")))
	if r.has("trait"):
		parts.append("Choose a trait")
	return " + ".join(parts)


## Icon for a reward on the level road.
static func reward_icon(r: Dictionary) -> String:
	if str(r.get("badge", "")) == HALL_OF_FAME:
		return "trophy"
	if str(r.get("badge", "")) == ALL_STAR:
		return "crown"
	if r.has("trait"):
		return "star"
	if r.has("pack"):
		return "deck"
	if r.has("coins"):
		return "coin"
	return "upgrade"

