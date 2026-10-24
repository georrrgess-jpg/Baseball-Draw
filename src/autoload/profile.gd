extends Node
## The player's persistent account: progression, collection, deck, team, records,
## achievements and the resumable run. Saved as JSON with an atomic write + backup.

signal changed
signal achievement_unlocked(id: String)
signal level_up(new_level: int)
signal notice(text: String)

var SAVE_PATH := "user://profile.json"
var BACKUP_PATH := "user://profile.bak"
var TMP_PATH := "user://profile.tmp"
var _file_base := "profile"
const SAVE_VERSION := 1
const MAX_ACCOUNT_LEVEL := 50

const STARTER_CARDS := ["power_throw", "curveball", "wall_of_dirt", "field_vision", "heat_wave", "lockdown",
	"frost_field", "twin_play", "rally_cry", "sky_hook"]
const STARTER_DECK := ["power_throw", "curveball", "heat_wave", "lockdown", "frost_field", "wall_of_dirt", "twin_play", "rally_cry"]
const STARTER_TEAM := ["ace", "rico", "maya", "jax", "kai", "bruno"]
const DECK_SIZE := 8
const TEAM_SIZE := 6

var data: Dictionary = {}
var load_status := "new"   # new | ok | restored_backup | reset_corrupt
var _save_queued := false


func _ready() -> void:
	# `-- --profile=<name>` uses a separate save (automated tests never touch the real profile).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--profile="):
			_file_base = "profile_" + a.split("=")[1]
			SAVE_PATH = "user://%s.json" % _file_base
			BACKUP_PATH = "user://%s.bak" % _file_base
			TMP_PATH = "user://%s.tmp" % _file_base
		if a == "--fresh-profile":
			for path in [SAVE_PATH, BACKUP_PATH]:
				if FileAccess.file_exists(path):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	load_profile()


# ------------------------------------------------------------------ persistence

func default_profile() -> Dictionary:
	var p := {
		"version": SAVE_VERSION,
		"name": "Manager",
		"created": Time.get_datetime_string_from_system(),
		"level": 1, "xp": 0, "coins": 250, "stars": 0,
		"rp": 0, "division": 0,
		"defenders": {}, "cards": {},
		"deck": STARTER_DECK.duplicate(),
		"team": STARTER_TEAM.duplicate(),
		"captain": "ace",
		"formation": "balanced",
		"custom_formations": {},
		"gear_owned": [], "gear_equipped": {},
		"uniforms_owned": ["home"], "uniform": "home",
		"arenas_unlocked": ["steel_yard"], "arena": "steel_yard",
		"difficulty": "standard",
		"stats": {}, "achievements": {}, "records": {"best_endless_inning": 0, "best_endless_score": 0},
		"history": [],
		"current_run": null,
		"flags": {"tutorial_done": false},
	}
	for id in DB.defender_order:
		var unlocked: bool = DB.defender(id).get("unlock", {}).get("type", "") == "default"
		p.defenders[id] = {"unlocked": unlocked, "level": 1, "xp": 0, "traits": {}}
	for id in DB.card_order:
		p.cards[id] = {"owned": id in STARTER_CARDS, "level": 1, "copies": 0}
	return p


func load_profile() -> void:
	var loaded := _try_read(SAVE_PATH)
	if loaded.is_empty():
		if FileAccess.file_exists(SAVE_PATH):
			# Main save is corrupt: keep a copy for inspection, then try the backup.
			DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH),
				ProjectSettings.globalize_path("user://%s.corrupt.json" % _file_base))
			loaded = _try_read(BACKUP_PATH)
			load_status = "restored_backup" if not loaded.is_empty() else "reset_corrupt"
		else:
			load_status = "new"
	else:
		load_status = "ok"
	data = default_profile()
	if not loaded.is_empty():
		_merge(data, loaded)
		_sanitize()
	if load_status in ["new", "reset_corrupt"]:
		save_now()


func _try_read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("version"):
		return {}
	return parsed


## Recursively copies saved values over defaults, keeping new default keys.
func _merge(base: Dictionary, saved: Dictionary) -> void:
	for key in saved.keys():
		if base.has(key) and typeof(base[key]) == TYPE_DICTIONARY and typeof(saved[key]) == TYPE_DICTIONARY:
			_merge(base[key], saved[key])
		elif not base.has(key) or base[key] == null or saved[key] == null or typeof(base[key]) == typeof(saved[key]) \
				or (typeof(base[key]) in [TYPE_INT, TYPE_FLOAT] and typeof(saved[key]) in [TYPE_INT, TYPE_FLOAT]):
			base[key] = saved[key]


## Repairs anything that could break the game (unknown ids, bad sizes, float ints from JSON).
func _sanitize() -> void:
	for k in ["level", "xp", "coins", "stars", "rp", "division"]:
		data[k] = int(data[k])
	data.level = clampi(data.level, 1, MAX_ACCOUNT_LEVEL)
	data.division = clampi(data.division, 0, DB.divisions.size() - 1)
	for id in data.defenders.keys():
		if not DB.defenders.has(id):
			data.defenders.erase(id)
			continue
		var d: Dictionary = data.defenders[id]
		d.level = clampi(int(d.get("level", 1)), 1, DB.defender_max_level)
		d.xp = int(d.get("xp", 0))
	for id in data.cards.keys():
		if not DB.cards.has(id):
			data.cards.erase(id)
			continue
		var c: Dictionary = data.cards[id]
		c.level = clampi(int(c.get("level", 1)), 1, DB.card_max_level)
		c.copies = int(c.get("copies", 0))
	var deck: Array = []
	for id in data.deck:
		if DB.cards.has(id) and is_card_owned(id) and not id in deck:
			deck.append(id)
	for id in STARTER_DECK:
		if deck.size() >= DECK_SIZE:
			break
		if not id in deck:
			deck.append(id)
	data.deck = deck.slice(0, DECK_SIZE)
	var team: Array = []
	for id in data.team:
		if DB.defenders.has(id) and is_defender_unlocked(id) and not id in team:
			team.append(id)
	for id in STARTER_TEAM:
		if team.size() >= TEAM_SIZE:
			break
		if not id in team:
			team.append(id)
	data.team = team.slice(0, TEAM_SIZE)
	if not data.captain in data.team:
		data.captain = data.team[0]
	if not DB.formations.has(data.formation) and not data.custom_formations.has(data.formation):
		data.formation = "balanced"
	if not DB.difficulties.has(data.difficulty):
		data.difficulty = "standard"
	if not data.arena in data.arenas_unlocked:
		data.arena = "steel_yard"
	if data.current_run != null and typeof(data.current_run) != TYPE_DICTIONARY:
		data.current_run = null


func save_now() -> void:
	_save_queued = false
	var text := JSON.stringify(data, "\t")
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Profile: cannot write temp save (%s)" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(text)
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	var main_f := _file_base + ".json"
	var bak_f := _file_base + ".bak"
	if dir.file_exists(main_f):
		if dir.file_exists(bak_f):
			dir.remove(bak_f)
		dir.rename(main_f, bak_f)
	dir.rename(_file_base + ".tmp", main_f)


## Coalesces several changes in one frame into a single disk write.
func save_soon() -> void:
	if _save_queued:
		return
	_save_queued = true
	call_deferred("save_now")


func reset_profile() -> void:
	data = default_profile()
	save_now()
	changed.emit()


# ------------------------------------------------------------------ account

func xp_to_next(level: int) -> int:
	return 250 + 125 * (level - 1)


func add_xp(amount: int) -> int:
	var levels := 0
	data.xp += amount
	while data.level < MAX_ACCOUNT_LEVEL and data.xp >= xp_to_next(data.level):
		data.xp -= xp_to_next(data.level)
		data.level += 1
		levels += 1
		data.coins += 100
		level_up.emit(data.level)
		_check_unlocks()
	changed.emit()
	return levels


func add_coins(n: int) -> void:
	data.coins = maxi(0, data.coins + n)
	changed.emit()


func spend_coins(n: int) -> bool:
	if data.coins < n:
		return false
	data.coins -= n
	changed.emit()
	return true


func add_stars(n: int) -> void:
	data.stars = maxi(0, data.stars + n)
	changed.emit()


func spend_stars(n: int) -> bool:
	if data.stars < n:
		return false
	data.stars -= n
	changed.emit()
	return true


# ------------------------------------------------------------------ defenders

func is_defender_unlocked(id: String) -> bool:
	return bool(data.defenders.get(id, {}).get("unlocked", false))


func defender_level(id: String) -> int:
	return int(data.defenders.get(id, {}).get("level", 1))


func defender_xp(id: String) -> int:
	return int(data.defenders.get(id, {}).get("xp", 0))


func defender_xp_needed(level: int) -> int:
	var curve: Array = DB.defender_xp_curve
	if level >= curve.size():
		return 0
	return int(curve[level]) - int(curve[level - 1])


func add_defender_xp(id: String, amount: int) -> int:
	if not data.defenders.has(id):
		return 0
	var d: Dictionary = data.defenders[id]
	var gained := 0
	d.xp += amount
	while d.level < DB.defender_max_level and d.xp >= defender_xp_needed(d.level):
		d.xp -= defender_xp_needed(d.level)
		d.level += 1
		gained += 1
	if d.level >= DB.defender_max_level:
		d.xp = 0
	set_stat_max("max_defender_level", d.level)
	changed.emit()
	return gained


func unlock_defender(id: String) -> void:
	if not data.defenders.has(id) or is_defender_unlocked(id):
		return
	data.defenders[id].unlocked = true
	var sig: String = DB.defender(id).get("signature", "")
	if sig != "":
		grant_card(sig, 0)
	notice.emit("New defender unlocked: %s!" % DB.defender(id).name)
	_update_collection_stats()
	changed.emit()


func defender_unlock_text(id: String) -> String:
	var u: Dictionary = DB.defender(id).get("unlock", {})
	match u.get("type", ""):
		"level": return "Reach account level %d" % int(u.value)
	return ""


func chosen_trait(id: String, level: int) -> String:
	return str(data.defenders.get(id, {}).get("traits", {}).get(str(level), ""))


func choose_trait(id: String, level: int, trait_id: String) -> void:
	if defender_level(id) < level:
		return
	data.defenders[id].traits[str(level)] = trait_id
	changed.emit()
	save_soon()


func equipped_gear(defender_id: String) -> String:
	return str(data.gear_equipped.get(defender_id, ""))


func equip_gear(defender_id: String, gear_id: String) -> void:
	for k in data.gear_equipped.keys():
		if data.gear_equipped[k] == gear_id:
			data.gear_equipped.erase(k)
	if gear_id == "":
		data.gear_equipped.erase(defender_id)
	else:
		data.gear_equipped[defender_id] = gear_id
	changed.emit()
	save_soon()


func buy_gear(gear_id: String) -> bool:
	if gear_id in data.gear_owned:
		return false
	if not spend_coins(int(DB.gear[gear_id].price)):
		return false
	data.gear_owned.append(gear_id)
	changed.emit()
	save_soon()
	return true


## Aggregated permanent modifiers for a defender: level, gear and chosen traits.
func defender_mods(id: String) -> Dictionary:
	var mods := {"damage": 0.0, "range": 0.0, "attack_speed": 0.0, "throw_speed": 0.0, "accuracy": 0.0,
		"crit": 0.0, "special_power": 0.0, "special_cooldown": 0.0, "boss_damage": 0.0, "stun_guard": 0}
	var lvl := defender_level(id)
	mods.damage += DB.defender_level_growth * (lvl - 1)
	mods.special_power += DB.defender_level_growth * (lvl - 1)
	var g := equipped_gear(id)
	if g != "" and DB.gear.has(g):
		for k in DB.gear[g].effect.keys():
			mods[k] = mods.get(k, 0) + DB.gear[g].effect[k]
	for tier in DB.traits:
		var chosen := chosen_trait(id, int(tier.level))
		for opt in tier.options:
			if opt.id == chosen and lvl >= int(tier.level):
				for k in opt.effect.keys():
					mods[k] = mods.get(k, 0) + opt.effect[k]
	return mods


# ------------------------------------------------------------------ cards

func is_card_owned(id: String) -> bool:
	return bool(data.cards.get(id, {}).get("owned", false))


func card_level(id: String) -> int:
	return int(data.cards.get(id, {}).get("level", 1))


func card_copies(id: String) -> int:
	return int(data.cards.get(id, {}).get("copies", 0))


## Adds a card to the collection; extra copies feed upgrades. Returns true if newly unlocked.
func grant_card(id: String, copies: int = 1) -> bool:
	if not data.cards.has(id):
		return false
	var c: Dictionary = data.cards[id]
	var is_new: bool = not bool(c.owned)
	if is_new:
		c.owned = true
	else:
		c.copies += copies
	_update_collection_stats()
	changed.emit()
	return is_new


func upgrade_cost(id: String) -> Dictionary:
	var lvl := card_level(id)
	if lvl >= DB.card_max_level:
		return {}
	var rarity: String = DB.card(id).rarity
	return {"copies": int(DB.COPIES_TO_UPGRADE[rarity][lvl]), "coins": int(DB.COINS_TO_UPGRADE[lvl])}


func can_upgrade_card(id: String) -> bool:
	var cost := upgrade_cost(id)
	return is_card_owned(id) and not cost.is_empty() and card_copies(id) >= cost.copies and data.coins >= cost.coins


func upgrade_card(id: String) -> bool:
	if not can_upgrade_card(id):
		return false
	var cost := upgrade_cost(id)
	data.cards[id].copies -= cost.copies
	data.coins -= cost.coins
	data.cards[id].level += 1
	set_stat_max("max_card_level", data.cards[id].level)
	changed.emit()
	save_soon()
	return true


func set_deck(deck: Array) -> bool:
	if deck.size() != DECK_SIZE:
		return false
	for id in deck:
		if not is_card_owned(id):
			return false
	data.deck = deck.duplicate()
	changed.emit()
	save_soon()
	return true


func set_team(team: Array, captain: String) -> void:
	data.team = team.slice(0, TEAM_SIZE)
	data.captain = captain if captain in data.team else data.team[0]
	changed.emit()
	save_soon()


# ------------------------------------------------------------------ stats & achievements

func stat(name: String) -> float:
	return float(data.stats.get(name, 0))


func bump_stat(name: String, amount: float = 1.0) -> void:
	data.stats[name] = stat(name) + amount
	_check_achievements(name)


func set_stat_max(name: String, value: float) -> void:
	if value > stat(name):
		data.stats[name] = value
		_check_achievements(name)


func _check_achievements(stat_name: String) -> void:
	for id in DB.achievement_order:
		var a: Dictionary = DB.achievements[id]
		if a.stat != stat_name or data.achievements.has(id):
			continue
		if stat(stat_name) >= float(a.goal):
			data.achievements[id] = Time.get_datetime_string_from_system()
			data.stars += int(a.get("stars", 0))
			achievement_unlocked.emit(id)


func achievement_progress(id: String) -> float:
	var a: Dictionary = DB.achievements[id]
	return clampf(stat(a.stat) / float(a.goal), 0.0, 1.0)


func _update_collection_stats() -> void:
	var owned := 0
	for id in DB.card_order:
		if is_card_owned(id):
			owned += 1
	data.stats["cards_owned"] = owned
	var defs := 0
	for id in DB.defender_order:
		if is_defender_unlocked(id):
			defs += 1
	data.stats["defenders_owned"] = defs
	data.stats["arenas_owned"] = data.arenas_unlocked.size()
	data.stats["division"] = data.division
	for s in ["cards_owned", "defenders_owned", "arenas_owned", "division"]:
		_check_achievements(s)


# ------------------------------------------------------------------ unlocks

func _check_unlocks() -> void:
	for id in DB.defender_order:
		var u: Dictionary = DB.defender(id).get("unlock", {})
		if u.get("type", "") == "level" and data.level >= int(u.value) and not is_defender_unlocked(id):
			unlock_defender(id)
	for id in DB.arena_order:
		if id in data.arenas_unlocked:
			continue
		if arena_unlock_met(id):
			data.arenas_unlocked.append(id)
			notice.emit("New stadium unlocked: %s!" % DB.arena(id).name)
	_update_collection_stats()


func arena_unlock_met(id: String) -> bool:
	var u: Dictionary = DB.arena(id).get("unlock", {})
	match u.get("type", ""):
		"default": return true
		"level": return data.level >= int(u.value)
		"win_mode": return stat("wins_" + str(u.value)) >= 1
		"rank": return data.division >= DB.division_index(str(u.value))
	return false


func arena_unlock_text(id: String) -> String:
	var u: Dictionary = DB.arena(id).get("unlock", {})
	match u.get("type", ""):
		"level": return "Reach account level %d" % int(u.value)
		"win_mode": return "Win %s" % DB.mode(str(u.value)).name
		"rank": return "Reach the %s division" % str(u.value).capitalize()
	return ""


func refresh_unlocks() -> void:
	_check_unlocks()
	changed.emit()


# ------------------------------------------------------------------ ranks

func division() -> Dictionary:
	return DB.divisions[clampi(int(data.division), 0, DB.divisions.size() - 1)]


func next_division() -> Dictionary:
	var i := int(data.division) + 1
	return DB.divisions[i] if i < DB.divisions.size() else {}


func promotion_available() -> bool:
	var nd := next_division()
	return not nd.is_empty() and int(data.rp) >= int(nd.rp_required)


func promote() -> void:
	if int(data.division) < DB.divisions.size() - 1:
		data.division += 1
		notice.emit("Promoted to %s!" % division().name)
		_check_unlocks()
		changed.emit()


# ------------------------------------------------------------------ run + history

func has_saved_run() -> bool:
	return typeof(data.current_run) == TYPE_DICTIONARY and not data.current_run.is_empty()


func store_run(run_dict: Variant) -> void:
	data.current_run = run_dict
	save_now()


func clear_run() -> void:
	data.current_run = null
	save_soon()


func add_history(entry: Dictionary) -> void:
	data.history.push_front(entry)
	if data.history.size() > 25:
		data.history.resize(25)
