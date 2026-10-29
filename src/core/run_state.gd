class_name RunState
extends RefCounted
## Everything about the current run that must survive between innings
## (and be saved for "Continue Run"). Pure data: no scene references.

var config: Dictionary = {}
var mode_id := "standard"
var difficulty_id := "standard"
var arena_id := "steel_yard"
var run_seed := 0
var rng := RandomNumberGenerator.new()

var inning := 1
var wave := 0                  # waves completed in the current inning
var waves_per_inning := 3
var max_innings := 9           # 0 = endless
var runs := 0
var run_limit := 3
var shields := 1
var coins := 0                 # run currency for the dugout
var coins_earned := 0
var score := 0
var outs_total := 0
var outs_inning := 0
var runs_inning := 0
var energy := 5.0

var team: Array = []
var captain := ""
var deck: Array = []           # card ids including temporary run cards
var temp_cards: Array = []
var card_level_bonus: Dictionary = {}
var upgrades: Dictionary = {}  # upgrade id -> times bought
var defender_bonus: Dictionary = {}  # defender id -> extra damage fraction
var positions: Dictionary = {}       # defender id -> [x, z]
var targeting: Dictionary = {}       # defender id -> targeting mode
var modifiers: Array = []      # active endless/challenge modifier ids
var formation := "balanced"

var stats := {
	"damage_by": {}, "outs_by": {}, "cards_played": 0, "double_plays": 0, "triple_plays": 0,
	"grand_combos": 0, "max_combo": 0, "clean_innings": 0, "bosses": [], "runs_by_inning": [],
	"curve_heat": 0, "shield_saves": 0, "early_calls": 0,
	# Filled by RunHighlights for the Results screen: per-inning summary and best moments.
	"timeline": [], "highlights": {},
}
var finished := false
var won := false
## Damage and outs credited to the card that caused them (balance statistics, not saved).
var card_impact: Dictionary = {}


static func create(cfg: Dictionary) -> RunState:
	var r := RunState.new()
	r.config = cfg.duplicate(true)
	r.config.erase("resume")
	r.mode_id = cfg.get("mode", "standard")
	r.difficulty_id = cfg.get("difficulty", "standard")
	r.arena_id = cfg.get("arena", "steel_yard")
	r.run_seed = int(cfg.get("seed", randi()))
	r.rng.seed = r.run_seed
	var m := DB.mode(r.mode_id)
	r.waves_per_inning = int(m.get("waves_per_inning", 3))
	r.max_innings = int(m.get("innings", 9))
	var diff := DB.difficulty(r.difficulty_id)
	r.run_limit = int(diff.get("run_limit", 3))
	r.shields = int(diff.get("shields", 1))
	# Per-mode override (e.g. Veteran Standard Siege starts with one shield: over nine innings a single
	# boss reaching home otherwise ends most runs).
	var mt: Dictionary = DB.mode(r.mode_id).get("tuning", {}).get(r.difficulty_id, {})
	if mt.has("shields"):
		r.shields = int(mt.shields)
	r.team = cfg.get("team", []).duplicate()
	r.captain = cfg.get("captain", r.team[0] if r.team.size() > 0 else "")
	r.deck = cfg.get("deck", []).duplicate()
	r.formation = cfg.get("formation", "balanced")
	r.modifiers = cfg.get("modifiers", []).duplicate()
	# Modifiers that change the starting rules (Daily Challenge, e.g. "no base shields").
	for mid in r.modifiers:
		var md := DailyChallenge.modifier_def(str(mid))
		if md.has("start_shields"):
			r.shields = int(md.start_shields)
		if md.has("run_limit_add"):
			r.run_limit = maxi(1, r.run_limit + int(md.run_limit_add))
	if r.mode_id == "practice":
		r.run_limit = 999
		r.waves_per_inning = 0
	# Test/debug entry points (used by the screenshot and simulation tools).
	r.inning = maxi(1, int(cfg.get("start_inning", 1)))
	r.wave = clampi(int(cfg.get("start_wave", 0)), 0, maxi(r.waves_per_inning - 1, 0))
	return r


func is_endless() -> bool:
	return max_innings <= 0 and mode_id != "practice"


func is_practice() -> bool:
	return mode_id == "practice"


func is_daily() -> bool:
	return config.has("daily")


func is_final_inning() -> bool:
	return max_innings > 0 and inning >= max_innings


func boss_for_inning(i: int) -> String:
	var fixed: Variant = config.get("bosses")
	if typeof(fixed) == TYPE_DICTIONARY and not (fixed as Dictionary).is_empty():
		return str(fixed.get(str(i), ""))
	var m := DB.mode(mode_id)
	if m.has("bosses"):
		return str(m.bosses.get(str(i), ""))
	if m.has("boss_every") and i % int(m.boss_every) == 0:
		var cycle := ["iron_slugger", "phantom_captain", "grand_slammer"]
		return cycle[(i / int(m.boss_every) - 1) % cycle.size()]
	return ""


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func upgrade_price(id: String) -> int:
	var u: Dictionary = DB.upgrades[id]
	return round_price(float(u.price) * pow(DB.upgrade_price_growth, upgrade_level(id)))


## Prices are shown as round numbers: 10s under 100, 25s up to 500, 50s above.
static func round_price(v: float) -> int:
	if v < 100.0:
		return maxi(10, int(round(v / 10.0)) * 10)
	if v < 500.0:
		return int(round(v / 25.0)) * 25
	return int(round(v / 50.0)) * 50


## Sum of a numeric key across bought upgrades, the arena modifier and active modifiers.
func modifier_total(key: String) -> float:
	var total := 0.0
	for id in upgrades.keys():
		var eff: Dictionary = DB.upgrades.get(id, {}).get("effect", {})
		if eff.has(key):
			total += float(eff[key]) * int(upgrades[id])
	var am: Dictionary = DB.arena(arena_id).get("modifier", {})
	if am.has(key):
		total += float(am[key])
	for mid in modifiers:
		var md := DailyChallenge.modifier_def(str(mid))
		if md.has(key):
			total += float(md[key])
	return total


func card_level(card_id: String) -> int:
	var base := Profile.card_level(card_id) if Profile.is_card_owned(card_id) else 1
	if config.has("card_level"):   # Daily Challenge: every card at the same level for everyone
		base = int(config.card_level)
	return clampi(base + int(card_level_bonus.get(card_id, 0)), 1, DB.card_max_level + 2)


func add_stat(key: String, amount: float = 1.0) -> void:
	stats[key] = float(stats.get(key, 0)) + amount


func add_damage(defender_id: String, amount: float) -> void:
	if defender_id == "":
		return
	stats.damage_by[defender_id] = float(stats.damage_by.get(defender_id, 0.0)) + amount


func add_card_impact(card_id: String, damage: float, outs := 0) -> void:
	if card_id == "":
		return
	var c: Dictionary = card_impact.get(card_id, {"damage": 0.0, "outs": 0})
	c.damage = float(c.damage) + damage
	c.outs = int(c.outs) + outs
	card_impact[card_id] = c


func add_out(defender_id: String) -> void:
	outs_total += 1
	outs_inning += 1
	if defender_id != "":
		stats.outs_by[defender_id] = int(stats.outs_by.get(defender_id, 0)) + 1


func mvp() -> String:
	var best := ""
	var best_v := -1.0
	for id in team:
		var v := float(stats.damage_by.get(id, 0.0)) + 60.0 * float(stats.outs_by.get(id, 0))
		if v > best_v:
			best_v = v
			best = id
	return best


func to_dict() -> Dictionary:
	return {
		"config": config, "mode_id": mode_id, "difficulty_id": difficulty_id, "arena_id": arena_id,
		"seed": run_seed, "rng_state": str(rng.state), "inning": inning, "wave": wave, "runs": runs, "run_limit": run_limit,
		"shields": shields, "coins": coins, "coins_earned": coins_earned, "score": score,
		"outs_total": outs_total, "energy": energy, "team": team, "captain": captain, "deck": deck,
		"temp_cards": temp_cards, "card_level_bonus": card_level_bonus, "upgrades": upgrades,
		"defender_bonus": defender_bonus, "positions": positions, "targeting": targeting,
		"modifiers": modifiers, "formation": formation, "stats": stats,
		"saved_at": Time.get_datetime_string_from_system(),
	}


static func from_dict(d: Dictionary) -> RunState:
	var r := RunState.create(d.get("config", {}))
	for k in ["mode_id", "difficulty_id", "arena_id", "captain", "formation"]:
		if d.has(k):
			r.set(k, str(d[k]))
	for k in ["inning", "wave", "runs", "run_limit", "shields", "coins", "coins_earned", "score", "outs_total"]:
		if d.has(k):
			r.set(k, int(d[k]))
	r.run_seed = int(d.get("seed", r.run_seed))
	r.energy = float(d.get("energy", 5.0))
	for k in ["team", "deck", "temp_cards", "modifiers"]:
		if d.has(k) and typeof(d[k]) == TYPE_ARRAY:
			r.set(k, d[k].duplicate())
	for k in ["card_level_bonus", "upgrades", "defender_bonus", "positions", "targeting"]:
		if d.has(k) and typeof(d[k]) == TYPE_DICTIONARY:
			r.set(k, d[k].duplicate(true))
	if d.has("stats") and typeof(d.stats) == TYPE_DICTIONARY:
		for k in d.stats.keys():
			r.stats[k] = d.stats[k]
	r.rng.seed = r.run_seed
	if d.has("rng_state"):
		r.rng.state = int(str(d.rng_state))
	return r
