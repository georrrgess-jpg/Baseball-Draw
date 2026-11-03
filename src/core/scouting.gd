class_name Scouting
extends RefCounted
## The Scouting Book's data: one entry per runner type, boss and elite affix (read from
## data/enemies.json and data/difficulties.json), first sightings ("met"), entries opened in the
## book ("viewed"), plain-language tips, stat bars and the cards that counter each entry.
##
## Entry keys: an enemy id ("sprinter", "iron_slugger") or "affix:<id>" ("affix:swift").
## Profile.data.scouting = {"met": {key: date}, "viewed": {key: true}}.
## Sightings come from a small Tracker node that the battle HUD attaches to every battle.

const AFFIX_PREFIX := "affix:"
const AFFIX_ICONS := {"swift": "speed", "tough": "health", "plated": "armor", "slippery": "shadow", "shielded": "shield"}
const GROUPS := ["runners", "bosses", "elites"]
const GROUP_TITLES := {"runners": "RUNNERS", "bosses": "BOSSES", "elites": "ELITE AFFIXES"}
const THREAT_COLORS := {"low": Color("#5BD75B"), "medium": Color("#F5B82E"), "high": Color("#FF6B3D"), "boss": Color("#E0262F"), "elite": Color("#FF4A3A")}
## Size of the good-cards list.
const GOOD_CARDS := 4

## Plain-language explanation per behaviour: [special ability name, what it does, how to stop it].
## {key} placeholders are filled from the enemy's data (numbers are never written here).
const BEHAVIOR_TEXT := {
	"basic": ["None", "Jogs down the base path at a steady pace. One is easy; a wave of them is not.",
		"Any defender can handle it. Spread your defenders over every route, and use splash damage when they bunch up."],
	"swarm": ["Pack runner", "Arrives in packs of {group}. Each one is fragile and fast, but they flood a route at once.",
		"Splash damage: area cards and bouncing throws clear the whole pack. Single throws can't keep up."],
	"sprinter": ["Burst sprint", "Bursts forward every few seconds and dodges sloppy throws ({evasion} dodge).",
		"Slow or stun it before it bursts. Cards that punish fast runners hit it extra hard."],
	"armored": ["Steel plating", "Armor blocks {armor} of all damage and shrugs off {slow_resist} of every slow.",
		"Break or pierce the armor, or hit it with damage that ignores armor. Weak chip damage barely scratches it."],
	"jumper": ["Leap", "Leaps over walls, traps and frozen turf. While it is in the air, ground effects can't touch it.",
		"Don't count on walls or traps. Throws and cards aimed at the runner itself always connect."],
	"trickster": ["Blink and decoys", "Dodges inaccurate throws ({evasion} dodge), blinks forward and leaves decoys behind.",
		"Reveal it so it can't dodge, or use throws that never miss. Splash damage pops the decoys."],
	"captain": ["Rally aura", "Rallies runners within {aura_radius} m: they run faster and take less damage. Scores {runs} runs.",
		"Take it out first and the rally ends. Big single-target hits and stuns work best."],
	"slugger": ["Wrecking ball", "A walking wrecking ball: smashes walls and stuns defenders it passes. Scores {runs} runs.",
		"Slow it and wear it down from range. Save a big hit or a run-stopper for when it nears home."],
	"stealer": ["Steal", "Sprints for the next base ({steal_speed}x speed) whenever no defender is aiming at it.",
		"Slow, root or stun it while it steals and it is caught stealing: an instant out."],
	"decoy": ["Illusion", "An illusion left by Tricksters and the Phantom Captain. It scores nothing but draws your throws.",
		"Reveal it, or let splash damage pop it on the way to the real runners."],
	"boss_iron": ["Ground slam", "Nearly impervious iron plating ({armor} armor). After each ground slam its armor cracks open and it is VULNERABLE for a few seconds.",
		"Save your big cards for the VULNERABLE window. Armor piercing and damage based on max health work all the time."],
	"boss_phantom": ["Phase and conjure", "Phases out of reality (it can't be hit while phased), conjures decoys and rallies runners within {aura_radius} m.",
		"Hit it while it is solid: boss cards and big single hits. Clear the decoys with splash damage."],
	"boss_slammer": ["Home-run swing", "Home-run swings stun and scatter defenders. Calls in reinforcements as it weakens. Scores {runs} runs.",
		"Keep boss and max-health damage for it, spread your defenders, and shake off stuns with a team buff."],
}

## Affix tips: [what it does, how to stop it].
const AFFIX_TEXT := {
	"speed": ["Runs much faster than its normal type.", "Slow or stun it early; it reaches home before your defenders catch up."],
	"hp": ["Much tougher than its normal type.", "Damage based on max health and big single hits cut it down."],
	"armor": ["Extra armor blocks more of every hit.", "Pierce or break the armor."],
	"evasion": ["Dodges inaccurate throws more often.", "Reveal it or use throws that can't be dodged."],
	"shield": ["A bubble blocks the first hit it takes.", "Pop the bubble with any cheap hit, a bounce or splash, then finish it."],
}

## Extra counter needs per behaviour (on top of what its numbers call for).
const BEHAVIOR_NEEDS := {
	"basic": {"aoe": 3, "multi_hit": 1, "block": 3},
	"swarm": {"block": 1},
	"stealer": {"slow": 3, "stun": 2, "fast_bonus": 2},
	"jumper": {"single": 3, "burst": 1, "ground": -4},
	"captain": {"single": 2, "burst": 2},
	"slugger": {"slow": 2, "stun": 1, "ground": -2},
	"decoy": {"aoe": 3, "sure_hit": 3},
	"trickster": {"single": 1, "aoe": 1},
	"boss_iron": {"burst": 1},
	"boss_phantom": {"aoe": 1, "single": 1},
	"boss_slammer": {"cleanse": 3, "stun": 1},
}

## Labels for the counter tags (shown under each good card).
const TAG_LABELS := {
	"pierce": "pierces armor", "percent": "max-health damage", "slow": "slows / stops", "fast_bonus": "extra vs fast runners",
	"aoe": "splash damage", "multi_hit": "many hits", "burst": "big hit", "sure_hit": "can't be dodged", "run_stop": "stops a run",
	"boss": "boss counter", "single": "targets the runner", "cleanse": "shakes off stuns", "stun": "stuns", "block": "blocks the path",
}

static var _tags_cache := {}


# ---------------------------------------------------------------- entries

## Every entry key in book order: runners, then bosses, then elite affixes.
static func all_keys() -> Array[String]:
	var out: Array[String] = []
	for g in GROUPS:
		out.append_array(keys_in_group(g))
	return out


static func keys_in_group(group: String) -> Array[String]:
	var out: Array[String] = []
	match group:
		"runners", "bosses":
			var ids: Array = DB.enemies.keys()
			ids = ids.filter(func(id: String) -> bool: return bool(DB.enemy(id).get("boss", false)) == (group == "bosses"))
			# Earliest first (decoys, which never appear on their own, go last).
			ids.sort_custom(func(a: String, b: String) -> bool:
				var fa := int(DB.enemy(a).get("from_inning", 99))
				var fb := int(DB.enemy(b).get("from_inning", 99))
				return fa < fb if fa != fb else DB.enemies.keys().find(a) < DB.enemies.keys().find(b))
			for id in ids:
				out.append(str(id))
		"elites":
			for a in DB.elite_affixes:
				out.append(AFFIX_PREFIX + str(a.id))
	return out


static func is_affix(key: String) -> bool:
	return key.begins_with(AFFIX_PREFIX)


static func affix(key: String) -> Dictionary:
	var id := key.trim_prefix(AFFIX_PREFIX)
	for a in DB.elite_affixes:
		if str(a.id) == id:
			return a
	return {}


static func group_of(key: String) -> String:
	if is_affix(key):
		return "elites"
	return "bosses" if bool(DB.enemy(key).get("boss", false)) else "runners"


static func exists(key: String) -> bool:
	return not affix(key).is_empty() if is_affix(key) else DB.enemies.has(key)


static func entry_name(key: String) -> String:
	if is_affix(key):
		return "%s Elite" % str(affix(key).get("name", key))
	return str(DB.enemy(key).get("name", key))


## Model shown on the turntable: the enemy's own (or the one it borrows), a plain runner for affixes.
static func model_id(key: String) -> String:
	if is_affix(key):
		return "runner"
	return str(DB.enemy(key).get("model", key))


static func portrait(key: String) -> Texture2D:
	if is_affix(key):
		return null
	return DB.portrait(model_id(key))


static func icon_name(key: String) -> String:
	if is_affix(key):
		return str(AFFIX_ICONS.get(key.trim_prefix(AFFIX_PREFIX), "special"))
	return "boss" if group_of(key) == "bosses" else "enemy"


static func threat(key: String) -> String:
	return "elite" if is_affix(key) else str(DB.enemy(key).get("threat", "low"))


static func threat_color(key: String) -> Color:
	return THREAT_COLORS.get(threat(key), UITheme.MUTED)


static func threat_text(key: String) -> String:
	return {"low": "LOW THREAT", "medium": "MEDIUM THREAT", "high": "HIGH THREAT", "boss": "BOSS", "elite": "ELITE"}.get(threat(key), "THREAT")


## Where a player first meets it (one short line).
static func where_text(key: String) -> String:
	if is_affix(key):
		return "Elite runners: Veteran and Legend difficulty, and every Promotion boss wave"
	var e := DB.enemy(key)
	var from := int(e.get("from_inning", 1))
	if str(e.get("behavior", "")) == "decoy":
		return "Conjured by Tricksters and the Phantom Captain"
	if bool(e.get("boss", false)):
		return "Boss of inning %d in Standard Siege" % from
	return "From inning %d in Standard Siege" % from


static func _behavior(key: String) -> String:
	var e := DB.enemy(key)
	var b := str(e.get("behavior", "basic"))
	if b == "basic" and int(e.get("group", 1)) > 1:
		return "swarm"
	return b


static func _fill(text: String, e: Dictionary) -> String:
	for k in e.keys():
		var v: Variant = e[k]
		if typeof(v) in [TYPE_FLOAT, TYPE_INT]:
			var s := str(int(v)) if absf(float(v) - roundf(float(v))) < 0.01 else "%.1f" % float(v)
			if k in ["armor", "evasion", "slow_resist"]:
				s = "%d%%" % int(round(float(v) * 100.0))
			text = text.replace("{%s}" % k, s)
	return text


static func ability_name(key: String) -> String:
	if is_affix(key):
		return str(affix(key).get("text", ""))
	return str(BEHAVIOR_TEXT.get(_behavior(key), ["Special", "", ""])[0])


## "What it does": the plain-language explanation (falls back to the data's own text).
static func what_it_does(key: String) -> String:
	if is_affix(key):
		var a := affix(key)
		var lines: Array[String] = []
		for stat_key in AFFIX_TEXT.keys():
			if a.has(stat_key):
				lines.append(str(AFFIX_TEXT[stat_key][0]))
		return "Any runner type can be an elite: a red glow and a gold health bar. %s (%s.) Elites also drop more coins." % [" ".join(lines), str(a.get("text", ""))]
	var row: Array = BEHAVIOR_TEXT.get(_behavior(key), [])
	return _fill(str(row[1]), DB.enemy(key)) if not row.is_empty() else str(DB.enemy(key).get("text", ""))


static func how_to_stop(key: String) -> String:
	if is_affix(key):
		var a := affix(key)
		var lines: Array[String] = []
		for stat_key in AFFIX_TEXT.keys():
			if a.has(stat_key):
				lines.append(str(AFFIX_TEXT[stat_key][1]))
		return " ".join(lines)
	var row: Array = BEHAVIOR_TEXT.get(_behavior(key), [])
	return _fill(str(row[2]), DB.enemy(key)) if not row.is_empty() else ""


## Stat rows for the bars: [icon, label, value text, fill 0..1, colour]. Health and speed are
## relative to the other entries of the same group (runners or bosses); armor and dodge are
## absolute fractions; runs relative to the most any runner scores.
static func stat_rows(key: String) -> Array:
	if is_affix(key):
		var a := affix(key)
		var rows: Array = []
		for k in [["hp", "health", "HEALTH"], ["speed", "speed", "SPEED"], ["armor", "armor", "ARMOR"], ["evasion", "shadow", "DODGE"]]:
			if a.has(k[0]):
				var v := float(a[k[0]])
				rows.append([k[1], k[2], "+%d%%" % int(round(v * 100.0)), clampf(v, 0.0, 1.0), UITheme.SCARLET])
		if a.has("shield"):
			rows.append(["shield", "SHIELD", "%d hit" % int(a.shield), clampf(float(a.shield) / 3.0, 0.0, 1.0), UITheme.BLUE])
		return rows
	var e := DB.enemy(key)
	var group := group_of(key)
	var max_hp := 1.0
	var max_speed := 1.0
	var max_runs := 1.0
	for id in DB.enemies.keys():
		var o := DB.enemy(id)
		if str(o.get("behavior", "")) == "decoy":
			continue
		max_speed = maxf(max_speed, float(o.get("speed", 0)))
		max_runs = maxf(max_runs, float(o.get("runs", 0)))
		if group_of(id) == group:
			max_hp = maxf(max_hp, float(o.get("hp", 0)))
	var hp := float(e.get("hp", 0))
	var rows: Array = [
		["health", "HEALTH", UITheme.format_int(int(hp)), clampf(hp / max_hp, 0.03, 1.0), UITheme.GREEN],
		["speed", "SPEED", "%.1f m/s" % float(e.get("speed", 0)), clampf(float(e.get("speed", 0)) / max_speed, 0.03, 1.0), UITheme.ENERGY],
		["armor", "ARMOR", "%d%%" % int(round(float(e.get("armor", 0)) * 100.0)), clampf(float(e.get("armor", 0)), 0.0, 1.0), UITheme.MUTED.lightened(0.3)],
		["shadow", "DODGE", "%d%%" % int(round(float(e.get("evasion", 0)) * 100.0)), clampf(float(e.get("evasion", 0)), 0.0, 1.0), UITheme.PURPLE],
		["runs", "RUNS SCORED", str(int(e.get("runs", 0))), clampf(float(e.get("runs", 0)) / max_runs, 0.0, 1.0), UITheme.SCARLET],
	]
	return rows


# ---------------------------------------------------------------- counters

## Counter tags of a card, read from its role, target and params (and its rules text for the few
## properties that have no parameter, e.g. "ignores armor" or "can't be dodged").
static func card_tags(card_id: String) -> Array[String]:
	if _tags_cache.has(card_id):
		return _tags_cache[card_id]
	var c := DB.card(card_id)
	var p: Dictionary = c.get("params", {})
	var role := str(c.get("role", ""))
	var text := (str(c.get("text", "")) + " " + str(c.get("details", ""))).to_lower()
	var tags: Array[String] = []
	var dmg := 0.0
	for k in ["damage", "boss_damage"]:
		dmg = maxf(dmg, float(p.get(k, 0)))
	if p.has("armor_break") or "armor" in text and ("pierce" in text or "ignor" in text or "break" in text or "shatter" in text):
		tags.append("pierce")
	if p.has("percent") or p.has("boss_percent"):
		tags.append("percent")
	for k in ["slow", "root", "freeze", "confuse", "pushback", "pull_time", "pull", "delay"]:
		if p.has(k):
			tags.append("slow")
			break
	if not "slow" in tags and role == "control":
		tags.append("slow")
	if p.has("stun") or p.has("boss_stun"):
		tags.append("stun")
	if p.has("fast_mult"):
		tags.append("fast_bonus")
	if role == "aoe" or p.has("balls") or p.has("chains") or p.has("width") or (str(c.get("target", "")) == "area" and p.has("damage")):
		tags.append("aoe")
	if p.has("balls") or p.has("chains") or p.has("targets") or p.has("chain_damage") or p.has("burn_dps") or p.has("interval"):
		tags.append("multi_hit")
	if dmg >= 180.0 or p.has("threshold"):
		tags.append("burst")
	if "dodge" in text or "never miss" in text or "reveal" in text:
		tags.append("sure_hit")
	if role == "run_stop" or "tagged out" in text or "called out" in text or "put out on the spot" in text:
		tags.append("run_stop")
	var boss_immune := "bosses are immune" in text or "bosses ignore" in text
	if not boss_immune and (role == "boss" or p.has("boss_percent") or p.has("boss_damage") or p.has("boss_stun") or p.has("boss_freeze")):
		tags.append("boss")
	if str(c.get("target", "")) == "enemy":
		tags.append("single")
	if "shake off stun" in text:
		tags.append("cleanse")
	if boss_immune:
		tags.append("no_boss")
	if str(c.get("target", "")) == "path" and not p.has("damage"):
		tags.append("ground")
	if p.has("hp") or (p.has("charges") and p.has("root")):
		tags.append("block")
	_tags_cache[card_id] = tags
	return tags


## What an entry calls for: {tag: weight}, derived from its numbers and behaviour.
static func needs(key: String) -> Dictionary:
	var w := {}
	if is_affix(key):
		var a := affix(key)
		if a.has("speed"):
			_add(w, {"slow": 3, "fast_bonus": 2, "stun": 1})
		if a.has("hp"):
			_add(w, {"percent": 3, "burst": 3})
		if a.has("armor"):
			_add(w, {"pierce": 3, "percent": 1})
		if a.has("evasion"):
			_add(w, {"sure_hit": 3, "aoe": 1})
		if a.has("shield"):
			_add(w, {"multi_hit": 3, "aoe": 1})
		return w
	var e := DB.enemy(key)
	if float(e.get("armor", 0)) >= 0.25:
		_add(w, {"pierce": 3, "percent": 1})
	if float(e.get("speed", 0)) >= 4.0:
		_add(w, {"slow": 3, "fast_bonus": 3, "stun": 1.5, "block": 1})
	if float(e.get("evasion", 0)) >= 0.5:
		_add(w, {"sure_hit": 3, "aoe": 1})
	if int(e.get("group", 1)) > 1:
		_add(w, {"aoe": 3, "multi_hit": 2})
	if int(e.get("runs", 1)) >= 2:
		_add(w, {"run_stop": 1.5})
	if not bool(e.get("boss", false)) and float(e.get("hp", 0)) >= 250.0:
		_add(w, {"burst": 2, "percent": 1.5, "stun": 1})
	_add(w, BEHAVIOR_NEEDS.get(_behavior(key), {}))
	if bool(e.get("boss", false)):
		_add(w, {"boss": 4, "percent": 3, "burst": 2, "no_boss": -8})
	return w


static func _add(w: Dictionary, add: Dictionary) -> void:
	for t in add.keys():
		w[t] = float(w.get(t, 0.0)) + float(add[t])


## How well a card answers an entry (0 = not at all).
static func score(card_id: String, key: String) -> float:
	var w := needs(key)
	var s := 0.0
	for t in card_tags(card_id):
		s += float(w.get(t, 0.0))
	return s


## The card's best reason against an entry (a TAG_LABELS text), or "".
static func reason(card_id: String, key: String) -> String:
	var w := needs(key)
	var best := ""
	var bv := 0.0
	for t in card_tags(card_id):
		if float(w.get(t, 0.0)) > bv and TAG_LABELS.has(t):
			bv = float(w[t])
			best = str(TAG_LABELS[t])
	return best


## Every card that counters an entry, best first: [card ids].
static func counters(key: String) -> Array[String]:
	var scored: Array = []
	for cid in DB.card_order:
		var s := score(cid, key)
		if s >= 3.0:
			scored.append([cid, s])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[1] > b[1] if a[1] != b[1] else DB.card_order.find(a[0]) < DB.card_order.find(b[0]))
	var out: Array[String] = []
	for x in scored:
		out.append(str(x[0]))
	return out


## The good-cards list for the book: up to GOOD_CARDS, owned cards first (best first within each).
static func good_cards(key: String, owned_first := true) -> Array[String]:
	var all := counters(key)
	var top := all.slice(0, 10)
	if not owned_first:
		return top.slice(0, GOOD_CARDS)
	var out: Array[String] = []
	for cid in top:
		if Profile.is_card_owned(cid) and out.size() < GOOD_CARDS:
			out.append(cid)
	for cid in top:
		if out.size() >= GOOD_CARDS:
			break
		if not cid in out:
			out.append(cid)
	return out


## The entries a card is good against (the inverse of `counters`): the card is among the best
## ten answers to the entry.
static func good_against(card_id: String) -> Array[String]:
	var out: Array[String] = []
	for key in all_keys():
		var list := counters(key)
		var i := list.find(card_id)
		if i >= 0 and i < 10:
			out.append(key)
	return out


# ---------------------------------------------------------------- seen tracking

static func default_state() -> Dictionary:
	return {"met": {}, "viewed": {}}


static func _state() -> Dictionary:
	var s: Variant = Profile.data.get("scouting")
	if typeof(s) != TYPE_DICTIONARY:
		s = default_state()
		Profile.data["scouting"] = s
	for k in ["met", "viewed"]:
		if typeof((s as Dictionary).get(k)) != TYPE_DICTIONARY:
			s[k] = {}
	return s


static func is_met(key: String) -> bool:
	return _state().met.has(key)


static func is_viewed(key: String) -> bool:
	return _state().viewed.has(key)


## Met in a game but not opened in the book yet ("NEW").
static func is_new(key: String) -> bool:
	return is_met(key) and not is_viewed(key)


static func met_count() -> int:
	var n := 0
	for k in all_keys():
		if is_met(k):
			n += 1
	return n


static func new_count() -> int:
	var n := 0
	for k in all_keys():
		if is_new(k):
			n += 1
	return n


## Records a first sighting. Returns true when the entry is new.
static func mark_met(key: String) -> bool:
	if not exists(key) or is_met(key):
		return false
	_state().met[key] = Time.get_date_string_from_system()
	Profile.save_soon()
	return true


static func mark_viewed(key: String) -> void:
	if not is_met(key) or is_viewed(key):
		return
	_state().viewed[key] = true
	Profile.save_soon()


## Records everything a spawned runner shows: its type and its elite affix.
static func mark_enemy(enemy_id: String, affix_id := "") -> Array[String]:
	var fresh: Array[String] = []
	if mark_met(enemy_id):
		fresh.append(enemy_id)
	if affix_id != "" and mark_met(AFFIX_PREFIX + affix_id):
		fresh.append(AFFIX_PREFIX + affix_id)
	return fresh


## Saves from before the Scouting Book: the runners a manager has certainly met (up to the
## deepest inning in their history, plus beaten bosses and elites from hard games) start scouted
## and already viewed, so the book does not open with a wall of NEW marks.
static func migrate(loaded: Dictionary) -> Dictionary:
	var st := default_state()
	var history: Array = loaded.get("history", []) if typeof(loaded.get("history")) == TYPE_ARRAY else []
	var stats: Dictionary = loaded.get("stats", {}) if typeof(loaded.get("stats")) == TYPE_DICTIONARY else {}
	var deepest := 0
	var hard := false
	for h in history:
		if typeof(h) != TYPE_DICTIONARY:
			continue
		deepest = maxi(deepest, int(h.get("inning", 0)))
		if str(h.get("difficulty", "")) in ["veteran", "legend"] or str(h.get("mode", "")) == "ranked":
			hard = true
	deepest = maxi(deepest, int(stats.get("best_endless_inning", 0)))
	if float(stats.get("runs_played", 0)) <= 0.0 and history.is_empty():
		return st
	var date := Time.get_date_string_from_system()
	for id in DB.enemies.keys():
		var e := DB.enemy(id)
		var met := int(e.get("from_inning", 99)) <= deepest or float(stats.get("boss_" + str(id), 0)) > 0.0
		if met:
			st.met[id] = date
			st.viewed[id] = true
	if st.met.has("trickster") or st.met.has("phantom_captain"):
		st.met["decoy"] = date
		st.viewed["decoy"] = true
	if hard:
		for a in DB.elite_affixes:
			st.met[AFFIX_PREFIX + str(a.id)] = date
			st.viewed[AFFIX_PREFIX + str(a.id)] = true
	return st


## Drops unknown keys and fixes types (called from Profile._sanitize).
static func sanitize() -> void:
	var st := _state()
	for k in ["met", "viewed"]:
		for key in (st[k] as Dictionary).keys():
			if not exists(str(key)):
				(st[k] as Dictionary).erase(key)


## The entry the book should open on (set before Router.open("scouting_book")).
static var open_on := ""


# ---------------------------------------------------------------- battle tracker

## Attached to every battle by the HUD: watches the spawned runners and records first sightings.
static func attach(b: Node) -> Tracker:
	var t := Tracker.new()
	t.battle = b
	t.name = "ScoutingTracker"
	b.add_child(t)
	return t


class Tracker extends Node:
	signal scouted(keys: Array)
	var battle: Node
	var _known := {}
	var _t := 0.0

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0 or battle == null:
			return
		_t = 0.25
		check()

	## Looks at every live runner once per type/affix (cheap: a dictionary lookup per runner).
	func check() -> void:
		var fresh: Array = []
		for e in battle.get("enemies"):
			if not is_instance_valid(e):
				continue
			var k := "%s|%s" % [e.id, e.affix]
			if _known.has(k):
				continue
			_known[k] = true
			fresh.append_array(Scouting.mark_enemy(str(e.id), str(e.affix)))
		if not fresh.is_empty():
			scouted.emit(fresh)
