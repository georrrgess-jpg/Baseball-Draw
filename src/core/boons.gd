class_name Boons
extends RefCounted
## Dugout Draft (Update 9): after a boss the manager picks 1 of 3 boons that last for the rest of
## the game (Standard Siege, Endless, Boss Rush). Data: data/boons.json. Run state: RunState.boons.
## FOUNDATION STUB: the modes stream (C) implements the rules in docs/plans/UPDATE_9_PLAN.md.

const DATA_PATH := "res://data/boons.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
	return _data


static func all() -> Array:
	return data().get("boons", [])


static func get_boon(id: String) -> Dictionary:
	for b in all():
		if str(b.get("id", "")) == id:
			return b
	return {}


## Three boon ids to choose from (none already taken).
static func offer(_run: RunState, _rng: RandomNumberGenerator) -> Array:
	return []


static func apply(_battle: Node, _id: String) -> void:
	pass


## [{id, name, text, rarity, icon}]
static func summary(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var b := get_boon(str(id))
		if not b.is_empty():
			out.append({"id": b.id, "name": b.get("name", ""), "text": b.get("text", ""), "rarity": b.get("rarity", "common"), "icon": b.get("icon", "star")})
	return out
