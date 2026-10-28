class_name LevelRoad
extends RefCounted
## Account level road (Update 6): what every account level pays out. Coins and packs come
## from data/account_levels.json; defender and stadium unlocks from their own data (an
## account level unlock in defenders.json / arenas.json). Profile.add_xp grants the coins
## and packs, Profile._check_unlocks the unlocks; the Progression screen and the Results
## screen show the road (src/ui/level_road_view.gd).

const DATA_PATH := "res://data/account_levels.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		if _data.is_empty():
			_data = {"default": {"coins": 100, "packs": ["rookie"]}}
	return _data


## {"coins": int, "packs": [pack ids], "unlocks": [{"type": "defender"|"arena", "id", "name"}]}
static func reward(level: int) -> Dictionary:
	var d := data()
	var base: Dictionary = d.get("default", {})
	for e in d.get("every", []):
		if level % maxi(1, int(e.get("n", 1))) == 0:
			base = e
	base = d.get("levels", {}).get(str(level), base)
	var out := {"coins": int(base.get("coins", 0)), "packs": (base.get("packs", []) as Array).duplicate(), "unlocks": []}
	if level <= 1:
		out.coins = 0
		out.packs = []
	for id in DB.defender_order:
		var u: Dictionary = DB.defender(id).get("unlock", {})
		if u.get("type", "") == "level" and int(u.value) == level:
			out.unlocks.append({"type": "defender", "id": id, "name": str(DB.defender(id).name)})
	for id in DB.arena_order:
		var u: Dictionary = DB.arena(id).get("unlock", {})
		if u.get("type", "") == "level" and int(u.value) == level:
			out.unlocks.append({"type": "arena", "id": id, "name": str(DB.arena(id).name)})
	return out


## "Nova joins the team · Pro Pack · 150 coins"
static func reward_text(level: int, short := false) -> String:
	var r := reward(level)
	var parts: Array = []
	for u in r.unlocks:
		if u.type == "defender":
			parts.append(("%s joins" if short else "%s joins the team") % u.name)
		else:
			parts.append(("%s stadium" if short else "the %s stadium") % u.name)
	var counts := {}
	for p in r.packs:
		counts[p] = int(counts.get(p, 0)) + 1
	for p in counts.keys():
		var nm := str(DB.pack(str(p)).get("name", p))
		parts.append(nm if int(counts[p]) == 1 else "%d %ss" % [int(counts[p]), nm])
	if int(r.coins) > 0:
		parts.append("%s coins" % UITheme.format_int(int(r.coins)))
	return " · ".join(parts)


## The main icon for a level on the road: the biggest thing it gives.
static func icon_for(level: int) -> String:
	var r := reward(level)
	for u in r.unlocks:
		return "roster" if u.type == "defender" else "map"
	if "champion" in r.packs or "pro" in r.packs:
		return "gift"
	if not (r.packs as Array).is_empty():
		return "deck"
	return "coin"


## True for levels that unlock something or pay a Pro Pack or better (drawn bigger on the road).
static func is_milestone(level: int) -> bool:
	var r := reward(level)
	return not (r.unlocks as Array).is_empty() or "pro" in r.packs or "champion" in r.packs


## Pays out the coins and packs for reaching `level` (unlocks are handled by Profile).
static func grant(level: int) -> void:
	var r := reward(level)
	Profile.data.coins = int(Profile.data.coins) + int(r.coins)
	for p in r.packs:
		Profile.add_pack(str(p), "Level %d reward" % level)


## The next level (above `level`) whose reward is a milestone, or 0.
static func next_milestone(level: int) -> int:
	for l in range(level + 1, Profile.MAX_ACCOUNT_LEVEL + 1):
		if is_milestone(l):
			return l
	return 0
