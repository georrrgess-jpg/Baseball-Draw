extends Node
## Static game database. Loads every JSON definition in res://data once at startup
## and exposes typed lookups. Nothing in here changes at runtime.

const DATA_DIR := "res://data/"

var cards: Dictionary = {}          # id -> card dict
var card_order: Array[String] = []
var defenders: Dictionary = {}
var defender_order: Array[String] = []
var roles: Dictionary = {}
var synergies: Array = []
var enemies: Dictionary = {}
var upgrades: Dictionary = {}
var upgrade_order: Array[String] = []
var formations: Dictionary = {}
var formation_order: Array[String] = []
var formation_slots: Array = []
var difficulties: Dictionary = {}
var difficulty_order: Array[String] = []
var elite_affixes: Array = []
var modes: Dictionary = {}
var endless_modifiers: Dictionary = {}
var arenas: Dictionary = {}
var arena_order: Array[String] = []
var layouts: Dictionary = {}
var achievements: Dictionary = {}
var achievement_order: Array[String] = []
var gear: Dictionary = {}
var gear_order: Array[String] = []
var traits: Array = []
var uniforms: Dictionary = {}
var uniform_order: Array[String] = []
var divisions: Array = []
var challenge_modifiers: Array = []
var combos: Array = []
var packs: Dictionary = {}
var pack_order: Array[String] = []
var _textures: Dictionary = {}   # path -> Texture2D (or null when missing)

var card_growth_rate := 0.12
var card_max_level := 5
var defender_level_growth := 0.06
var defender_max_level := 10
var defender_xp_curve: Array = []
var upgrade_price_growth := 1.5

const RARITY_ORDER := ["common", "uncommon", "rare", "epic", "legendary"]
const RARITY_COLORS := {
	"common": Color("#B8C0CC"), "uncommon": Color("#5BD75B"), "rare": Color("#3A8DFF"),
	"epic": Color("#B45CFF"), "legendary": Color("#FFAA1D"),
}
const CATEGORY_COLORS := {
	"offense": Color("#FF5A36"), "control": Color("#7B6CFF"),
	"defense": Color("#2EC4B6"), "utility": Color("#FFD23F"),
}
const CATEGORY_ORDER := ["offense", "control", "defense", "utility"]
## Card copies needed to go from level N to N+1, indexed by rarity.
const COPIES_TO_UPGRADE := {
	"common": [0, 2, 4, 8, 14], "uncommon": [0, 2, 3, 6, 10], "rare": [0, 1, 3, 5, 8],
	"epic": [0, 1, 2, 4, 6], "legendary": [0, 1, 2, 3, 4],
}
const COINS_TO_UPGRADE := [0, 100, 250, 600, 1200]


func _ready() -> void:
	_load_all()


func _read_json(file_name: String) -> Dictionary:
	var path := DATA_DIR + file_name
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DB: cannot open %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("DB: invalid JSON in %s" % path)
		return {}
	return parsed


func _load_all() -> void:
	var c := _read_json("cards.json")
	card_growth_rate = float(c.get("growth_rate", 0.12))
	card_max_level = int(c.get("max_level", 5))
	for card in c.get("cards", []):
		cards[card.id] = card
		card_order.append(card.id)

	var d := _read_json("defenders.json")
	defender_level_growth = float(d.get("level_growth", 0.06))
	defender_max_level = int(d.get("max_level", 10))
	defender_xp_curve = d.get("xp_curve", [])
	roles = d.get("roles", {})
	synergies = d.get("synergies", [])
	for def in d.get("defenders", []):
		defenders[def.id] = def
		defender_order.append(def.id)

	for e in _read_json("enemies.json").get("enemies", []):
		enemies[e.id] = e

	var u := _read_json("upgrades.json")
	upgrade_price_growth = float(u.get("price_growth", 1.5))
	for up in u.get("upgrades", []):
		upgrades[up.id] = up
		upgrade_order.append(up.id)

	var f := _read_json("formations.json")
	formation_slots = f.get("slots", [])
	for fm in f.get("formations", []):
		formations[fm.id] = fm
		formation_order.append(fm.id)

	var df := _read_json("difficulties.json")
	for x in df.get("difficulties", []):
		difficulties[x.id] = x
		difficulty_order.append(x.id)
	elite_affixes = df.get("elite_affixes", [])

	var m := _read_json("modes.json")
	for x in m.get("modes", []):
		modes[x.id] = x
	for x in m.get("endless_modifiers", []):
		endless_modifiers[x.id] = x

	var a := _read_json("arenas.json")
	layouts = a.get("layouts", {})
	for x in a.get("arenas", []):
		arenas[x.id] = x
		arena_order.append(x.id)

	for x in _read_json("achievements.json").get("achievements", []):
		achievements[x.id] = x
		achievement_order.append(x.id)

	var g := _read_json("gear.json")
	for x in g.get("gear", []):
		gear[x.id] = x
		gear_order.append(x.id)
	traits = g.get("traits", [])
	for x in g.get("uniforms", []):
		uniforms[x.id] = x
		uniform_order.append(x.id)

	combos = _read_json("combos.json").get("combos", [])

	for x in _read_json("packs.json").get("packs", []):
		packs[x.id] = x
		pack_order.append(x.id)

	var r := _read_json("ranks.json")
	divisions = r.get("divisions", [])
	challenge_modifiers = r.get("challenge_modifiers", [])


# ---------------------------------------------------------------- lookups

func card(id: String) -> Dictionary:
	return cards.get(id, {})


func defender(id: String) -> Dictionary:
	return defenders.get(id, {})


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


func arena(id: String) -> Dictionary:
	return arenas.get(id, arenas.get("steel_yard", {}))


func layout_for_arena(id: String) -> Dictionary:
	return layouts.get(arena(id).get("layout", "classic"), layouts.get("classic", {}))


func difficulty(id: String) -> Dictionary:
	return difficulties.get(id, difficulties.get("standard", {}))


func mode(id: String) -> Dictionary:
	return modes.get(id, modes.get("standard", {}))


## Returns a card parameter scaled for the given card level (1-based).
func card_param(card_id: String, param: String, level: int = 1) -> float:
	var c := card(card_id)
	var base := float(c.get("params", {}).get(param, 0.0))
	if param in c.get("growth", []):
		return base * (1.0 + card_growth_rate * float(max(level, 1) - 1))
	return base


func card_text(card_id: String, level: int = 1) -> String:
	var c := card(card_id)
	var text: String = c.get("text", "")
	for key in c.get("params", {}).keys():
		var v := card_param(card_id, key, level)
		var s := str(int(round(v))) if absf(v - roundf(v)) < 0.05 or v >= 10.0 else "%.1f" % v
		text = text.replace("{%s}" % key, s)
	return text


## Combo partners for a card: [{card, text}].
func combos_for(card_id: String) -> Array:
	var out: Array = []
	for c in combos:
		if card_id in c.cards:
			for other in c.cards:
				if other != card_id:
					out.append({"card": other, "text": c.text})
	return out


func division_index(id: String) -> int:
	for i in divisions.size():
		if divisions[i].id == id:
			return i
	return 0


func pack(id: String) -> Dictionary:
	return packs.get(id, packs.get("rookie", {}))


func rarity_index(r: String) -> int:
	return maxi(0, RARITY_ORDER.find(r))


func rarity_color(r: String) -> Color:
	return RARITY_COLORS.get(r, Color.WHITE)


func category_color(c: String) -> Color:
	return CATEGORY_COLORS.get(c, Color.WHITE)


func defender_accent(id: String) -> Color:
	return Color(defender(id).get("accent", "#FFFFFF"))


func card_texture(id: String) -> Texture2D:
	return _texture("res://assets/textures/cards/%s.png" % id)


func portrait(id: String) -> Texture2D:
	return _texture("res://assets/textures/portraits/%s.png" % id)


func icon(name: String) -> Texture2D:
	return _texture("res://assets/textures/icons/%s.svg" % name)


## Loads and keeps a reference to UI textures. Custom _draw() code only records the
## texture's RID, so an uncached texture would be freed before the frame renders.
func _texture(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_textures[path] = tex
	return tex
