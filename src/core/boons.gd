class_name Boons
extends RefCounted
## Dugout Draft (Update 9): after a boss the manager picks 1 of 3 boons that last for the rest of
## the game (Standard Siege after innings 3 and 6, Endless after every boss, Boss Rush after bosses
## 1 and 2; modes with "draft": true in data/modes.json). Data: data/boons.json. Run state:
## RunState.boons (saved with the run, so boons survive Save & Quit / Continue).
##
## How the effects work (see the "effect" keys in boons.json):
## * Stat keys (damage, attack_speed, range, crit, energy_regen, draw_speed, card_cooldown,
##   coin_mult) are summed into RunState.modifier_total, which defenders, the card system and the
##   out coins already read.
## * card_level + categories raise RunState.card_level for those card categories.
## * shield and run_limit are applied once, when the boon is taken (the run saves them).
## * first_card_refund, wave_draw, wave_energy, home_slow and boss_damage are read by Battle
##   (total() below) every wave or every frame.

const DATA_PATH := "res://data/boons.json"
const RARITY_ORDER := ["common", "rare", "epic"]

static var _data: Dictionary = {}
static var _by_id: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				_data = parsed
		_by_id.clear()
		for b in _data.get("boons", []):
			_by_id[str(b.get("id", ""))] = b
	return _data


static func all() -> Array:
	return data().get("boons", [])


static func get_boon(id: String) -> Dictionary:
	data()
	return _by_id.get(id, {})


static func rarity_weight(rarity: String) -> float:
	return float(data().get("rarities", {}).get(rarity, {}).get("weight", 1.0))


static func rarity_name(rarity: String) -> String:
	return str(data().get("rarities", {}).get(rarity, {}).get("name", rarity.capitalize()))


static func rarity_color(rarity: String) -> Color:
	return DB.rarity_color(rarity)


## Sum of a numeric effect key over the boons taken (persistent effects).
static func total(ids: Array, key: String) -> float:
	var t := 0.0
	for id in ids:
		var eff: Dictionary = get_boon(str(id)).get("effect", {})
		var v: Variant = eff.get(key)
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			t += float(v)
	return t


## Extra card levels the boons give a card of this category.
static func card_level_bonus(ids: Array, category: String) -> int:
	var n := 0
	for id in ids:
		var eff: Dictionary = get_boon(str(id)).get("effect", {})
		if eff.has("card_level") and category in eff.get("categories", []):
			n += int(eff.card_level)
	return n


## Whether a boon can be offered now: not taken yet and not useless (a shield at 3 shields, a
## card clinic with no card of its categories in the deck).
static func available(run: RunState, id: String) -> bool:
	var b := get_boon(id)
	if b.is_empty() or id in run.boons:
		return false
	var eff: Dictionary = b.get("effect", {})
	if eff.has("shield") and run.shields >= 3:
		return false
	if eff.has("categories"):
		var cats: Array = eff.categories
		for cid in run.deck:
			if str(DB.card(str(cid)).get("category", "")) in cats:
				return true
		return false
	return true


## Three boon ids to choose from (none already taken), weighted by rarity. If the first two are
## both common, the third is rare or better when one is left.
static func offer(run: RunState, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for b in all():
		if available(run, str(b.id)):
			pool.append(str(b.id))
	var out: Array = []
	while out.size() < 3 and not pool.is_empty():
		var candidates := pool
		if out.size() == 2 and get_boon(out[0]).get("rarity", "") == "common" and get_boon(out[1]).get("rarity", "") == "common":
			var better := pool.filter(func(id: String) -> bool: return get_boon(id).get("rarity", "common") != "common")
			if not better.is_empty():
				candidates = better
		var id := _weighted(candidates, rng)
		out.append(id)
		pool.erase(id)
	return out


static func _weighted(ids: Array, rng: RandomNumberGenerator) -> String:
	var tot := 0.0
	for id in ids:
		tot += rarity_weight(str(get_boon(id).get("rarity", "common")))
	var r := rng.randf() * tot
	for id in ids:
		r -= rarity_weight(str(get_boon(id).get("rarity", "common")))
		if r <= 0.0:
			return id
	return ids[ids.size() - 1]


## Takes a boon for the rest of the game: records it in run.boons and applies the one-off parts
## (shields, run limit); the lasting parts are read from run.boons from now on.
static func apply(battle: Node, id: String) -> void:
	var b := get_boon(id)
	var run: RunState = battle.get("run")
	if b.is_empty() or run == null or id in run.boons:
		return
	run.boons.append(id)
	var eff: Dictionary = b.get("effect", {})
	if eff.has("shield"):
		if battle.has_method("add_shield"):
			battle.add_shield(int(eff.shield))
		else:
			run.shields = mini(run.shields + int(eff.shield), 3)
	if eff.has("run_limit"):
		run.run_limit += int(eff.run_limit)
	if battle.has_method("_refresh_team_stats"):
		battle._refresh_team_stats()


## [{id, name, text, rarity, icon}]
static func summary(ids: Array) -> Array:
	var out: Array = []
	for id in ids:
		var b := get_boon(str(id))
		if not b.is_empty():
			out.append({"id": b.id, "name": b.get("name", ""), "text": b.get("text", ""), "rarity": b.get("rarity", "common"), "icon": b.get("icon", "star")})
	return out
