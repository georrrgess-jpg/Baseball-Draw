class_name CardCompare
extends Control
## Card comparison overlay (Cards & Deck): two cards side by side. Each side shows the card, its rarity,
## role tags, level, mastery and its combos with the current deck; the middle table lists cost, cooldown,
## target, level, mastery, Auto Build power and every stat at the current level (and the next level), with
## the better value of each row highlighted. CHANGE under a side asks the host to pick a new card for it.
## Esc (via the host's overlay stack), CLOSE or a click on the dim background closes it.

signal change_requested(side: int)
signal closed

const SIDE_W := 300.0
const LABEL_W := 230.0
## Display names for params; anything else is shown as its key in words.
const PARAM_NAMES := {
	"damage": "Damage", "burn_dps": "Burn / second", "burn_time": "Burn time", "width": "Width", "length": "Length",
	"knockback": "Knockback", "balls": "Balls", "stun": "Stun", "per_defender": "Power per defender",
	"targets": "Targets", "armor_break": "Armor break", "chains": "Bounces", "falloff": "Damage kept per bounce",
	"slow": "Slow", "duration": "Duration", "vulnerability": "Extra damage taken", "confuse": "Confuse",
	"pushback": "Push back", "freeze": "Freeze", "boss_freeze": "Boss freeze", "threshold": "Finishes below",
	"root": "Root", "slow_time": "Slow time", "home_bonus": "Root near home", "crit_bonus": "Crit chance bonus",
	"hp": "Wall health", "shields": "Shields", "charges": "Charges", "chain_damage": "Bounce damage",
	"range_bonus": "Range bonus", "radius": "Radius", "damage_bonus": "Damage bonus", "speed_bonus": "Attack speed bonus",
	"pull_time": "Pull time", "pull": "Pull back", "percent": "Max-health damage", "max_bonus": "Max bonus damage",
	"boss_stun": "Boss stun", "draw": "Cards drawn", "energy": "Energy gained", "boss_percent": "Boss max-health damage",
	"tag_time": "Tag time",
}
const FRACTION_KEYS := ["slow", "vulnerability", "crit_bonus", "damage_bonus", "speed_bonus", "range_bonus",
	"per_defender", "chain_damage", "falloff", "threshold"]
const PERCENT_KEYS := ["percent", "boss_percent", "slow"]
const SECOND_KEYS := ["duration", "burn_time", "stun", "root", "slow_time", "freeze", "boss_freeze", "confuse",
	"pull_time", "tag_time", "boss_stun"]
const METRE_KEYS := ["knockback", "pushback", "pull", "width", "length", "radius"]
const TARGET_TEXT := {"enemy": "One runner", "area": "An area", "path": "A basepath", "defender": "A defender", "none": "Instant"}

var ids: Array = ["", ""]
var deck: Array = []
var _panel: PanelContainer
var _body: HBoxContainer
var _closing := false


func _init(a := "", b := "", deck_ids: Array = []) -> void:
	ids = [a, b]
	deck = deck_ids.duplicate()
	name = "CardCompare"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Audio.ui("ui_back")
			close())
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	_panel = UITheme.card_panel(Color(UITheme.GOLD, 0.6), 22, Color(0.04, 0.065, 0.11, 0.98), 2)
	_panel.custom_minimum_size = Vector2(1420, 0)
	cc.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	var sh := UITheme.section_header("COMPARE CARDS", "swap", UITheme.GOLD, UITheme.FS_H2)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	var close_b := UITheme.button("CLOSE", "secondary", UITheme.FS_BODY)
	close_b.tooltip_text = "Close (Esc)"
	close_b.pressed.connect(close)
	head.add_child(close_b)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 20)
	vb.add_child(_body)
	var foot := UITheme.label("CHANGE swaps one side: pick any card in your collection.  ·  Shift-click a card, then click another, to compare from anywhere.  ·  Esc closes.",
		UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(foot)
	_rebuild()
	UITheme.animate_in(_panel, 0.0, 0.94)


## Replaces one side (0 = left, 1 = right) and redraws.
func set_side(side: int, id: String) -> void:
	ids[clampi(side, 0, 1)] = id
	if is_inside_tree():
		_rebuild()


func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, UITheme.T_FAST)
	tw.tween_callback(queue_free)


# ================================================================ layout

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_body.add_child(_side(0))
	_body.add_child(_table())
	_body.add_child(_side(1))


func _side(side: int) -> Control:
	var cid: String = ids[side]
	var c := DB.card(cid)
	var lvl := Profile.card_level(cid)
	var owned := Profile.is_card_owned(cid)
	var vb := VBoxContainer.new()
	vb.name = "Side%d" % side
	vb.custom_minimum_size = Vector2(SIDE_W, 0)
	vb.add_theme_constant_override("separation", 8)
	var cv := CardView.new(cid, lvl)
	cv.set_card(cid, lvl)
	cv.custom_minimum_size = Vector2(220, 308)
	cv.owned = owned
	cv.mastery = CardMastery.stars(cid)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(cv)
	var nm := UITheme.header(str(c.get("name", cid)).to_upper(), UITheme.FS_H3, UITheme.OFFWHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(nm)
	var sub := UITheme.label("%s  ·  %s%s" % [str(c.get("rarity", "")).capitalize(), str(c.get("category", "")).capitalize(),
		"" if owned else "  ·  not owned"], UITheme.FS_SMALL, DB.rarity_color(str(c.get("rarity", ""))), UITheme.font_body_bold())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var tags := HFlowContainer.new()
	tags.alignment = FlowContainer.ALIGNMENT_CENTER
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 6)
	for t in DeckAI.role_tags(cid, lvl):
		tags.add_child(UITheme.badge(str(t).to_upper(), _tag_color(str(t)).darkened(0.35)))
	vb.add_child(tags)
	var linked := str(c.get("linked", ""))
	if linked != "":
		var on_team: bool = linked in Profile.data.get("team", [])
		var ll := UITheme.label("Signature of %s%s" % [DB.defender(linked).name, " (on your team)" if on_team else " (not on your team: 75 % power)"],
			UITheme.FS_MIN, DB.defender_accent(linked).lightened(0.3) if on_team else UITheme.MUTED, UITheme.font_body_bold())
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(ll)
	vb.add_child(UITheme.hsep())
	var ch := UITheme.label("COMBOS WITH YOUR DECK", UITheme.FS_MIN, UITheme.GOLD, UITheme.font_body_bold())
	vb.add_child(ch)
	var any := false
	for cb in DB.combos_for(cid):
		if cb.card in deck and cb.card != cid:
			any = true
			var l := UITheme.label("+ " + str(DB.card(cb.card).name), UITheme.FS_SMALL, UITheme.GREEN, UITheme.font_body_bold())
			l.tooltip_text = str(cb.text)
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			vb.add_child(l)
	if not any:
		vb.add_child(UITheme.label("None", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold()))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	var chg := UITheme.button("CHANGE", "secondary", UITheme.FS_BODY, "swap")
	chg.name = "Change%d" % side
	chg.tooltip_text = "Pick another card for this side"
	chg.pressed.connect(func() -> void: change_requested.emit(side))
	vb.add_child(chg)
	return vb


func _tag_color(t: String) -> Color:
	match t:
		"Damage", "AoE":
			return DB.category_color("offense")
		"Control":
			return DB.category_color("control")
		"Defense", "Run-stop":
			return DB.category_color("defense")
		"Boss":
			return UITheme.SCARLET
		"Economy":
			return UITheme.ENERGY
		"Buff":
			return DB.category_color("utility")
	return UITheme.BLUE


func _table() -> Control:
	var a: String = ids[0]
	var b: String = ids[1]
	var ca := DB.card(a)
	var cb := DB.card(b)
	var la := Profile.card_level(a)
	var lb := Profile.card_level(b)
	var vb := VBoxContainer.new()
	vb.name = "Table"
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	var rows: Array = []   # [label, text a, text b, num a, num b, higher_is_better (1, -1, 0), next a, next b]
	rows.append(["Energy cost", str(int(ca.cost)), str(int(cb.cost)), float(ca.cost), float(cb.cost), -1, "", ""])
	rows.append(["Cooldown", _secs(float(ca.cooldown)), _secs(float(cb.cooldown)), float(ca.cooldown), float(cb.cooldown), -1, "", ""])
	rows.append(["Target", str(TARGET_TEXT.get(str(ca.target), ca.target)), str(TARGET_TEXT.get(str(cb.target), cb.target)), 0.0, 0.0, 0, "", ""])
	rows.append(["Rarity", str(ca.rarity).capitalize(), str(cb.rarity).capitalize(), 0.0, 0.0, 0, "", ""])
	rows.append(["Level", "%d / %d" % [la, DB.card_max_level], "%d / %d" % [lb, DB.card_max_level], float(la), float(lb), 1, "", ""])
	var ma := CardMastery.stars(a)
	var mb := CardMastery.stars(b)
	rows.append(["Mastery", "★".repeat(ma) + "☆".repeat(CardMastery.MAX_STARS - ma), "★".repeat(mb) + "☆".repeat(CardMastery.MAX_STARS - mb), float(ma), float(mb), 1, "", ""])
	var pa := float(DeckAI.analyze(a, la).get("power", 0.0))
	var pb := float(DeckAI.analyze(b, lb).get("power", 0.0))
	rows.append(["Auto Build power", "%.1f" % pa, "%.1f" % pb, pa, pb, 1,
		_next_power(a, la), _next_power(b, lb)])
	var keys: Array = []
	for k in ca.get("params", {}).keys():
		keys.append(k)
	for k in cb.get("params", {}).keys():
		if not k in keys:
			keys.append(k)
	if ca.has("radius") or cb.has("radius"):
		if not "radius" in keys:
			keys.append("area_radius")
	for k in keys:
		var key := str(k)
		var va := _param(a, key, la)
		var vb2 := _param(b, key, lb)
		rows.append([str(PARAM_NAMES.get(key, key.replace("_", " ").capitalize())) if key != "area_radius" else "Area radius",
			_fmt(key, va) if va != null else "—", _fmt(key, vb2) if vb2 != null else "—",
			float(va) if va != null else 0.0, float(vb2) if vb2 != null else 0.0,
			1 if va != null and vb2 != null else 0,
			_next_param(a, key, la, va), _next_param(b, key, lb, vb2)])
	for i in rows.size():
		vb.add_child(_row(rows[i], i))
	# The two cards combo with each other.
	for cbo in DB.combos_for(a):
		if cbo.card == b:
			var t := UITheme.label("These two combo: " + str(cbo.text), UITheme.FS_SMALL, UITheme.GREEN, UITheme.font_body_bold())
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vb.add_child(t)
	var legend := UITheme.label("Green = better.  Small numbers = at the next level.", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(legend)
	return vb


func _row(r: Array, i: int) -> Control:
	var p := PanelContainer.new()
	p.name = "Row_" + str(r[0])
	var st := UITheme.panel_style(Color(1, 1, 1, 0.045 if i % 2 == 0 else 0.0), Color(0, 0, 0, 0), 0, 6, 0)
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	st.content_margin_left = 10
	st.content_margin_right = 10
	p.add_theme_stylebox_override("panel", st)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var dir := int(r[5])
	var win := 0   # 1 = left better, 2 = right better
	if dir != 0 and absf(float(r[3]) - float(r[4])) > 0.001:
		win = 1 if (float(r[3]) - float(r[4])) * dir > 0.0 else 2
	var rare := str(r[0]) == "Rarity"
	hb.add_child(_cell(str(r[1]), str(r[6]), win == 1, true, DB.rarity_color(str(r[1]).to_lower()) if rare else UITheme.OFFWHITE))
	var lab := UITheme.label(str(r[0]).to_upper(), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	lab.custom_minimum_size = Vector2(LABEL_W, 0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lab)
	hb.add_child(_cell(str(r[2]), str(r[7]), win == 2, false, DB.rarity_color(str(r[2]).to_lower()) if rare else UITheme.OFFWHITE))
	if win != 0:
		p.set_meta("better", "left" if win == 1 else "right")
	return p


func _cell(text: String, next: String, better: bool, left: bool, col := UITheme.OFFWHITE) -> Control:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.alignment = BoxContainer.ALIGNMENT_END if left else BoxContainer.ALIGNMENT_BEGIN
	hb.add_theme_constant_override("separation", 8)
	var v := UITheme.label(text, UITheme.FS_BODY, UITheme.GREEN if better else col, UITheme.font_body_bold())
	if better:
		var bs := UITheme.panel_style(Color(UITheme.GREEN, 0.16), Color(UITheme.GREEN, 0.55), 1, 8, 0)
		bs.content_margin_left = 8
		bs.content_margin_right = 8
		v.add_theme_stylebox_override("normal", bs)
	var n: Label = null
	if next != "":
		n = UITheme.label("→ " + next, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
		n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		n.tooltip_text = "At the next level"
		n.mouse_filter = Control.MOUSE_FILTER_PASS
	if left and n:
		hb.add_child(n)
	hb.add_child(v)
	if not left and n:
		hb.add_child(n)
	return hb


# ================================================================ values

func _param(cid: String, key: String, lvl: int) -> Variant:
	var c := DB.card(cid)
	if key == "area_radius":
		return float(c.radius) if c.has("radius") else null
	if not c.get("params", {}).has(key):
		return null
	return DB.card_param(cid, key, lvl)


func _next_param(cid: String, key: String, lvl: int, cur: Variant) -> String:
	if cur == null or lvl >= DB.card_max_level or not key in DB.card(cid).get("growth", []):
		return ""
	return _fmt(key, DB.card_param(cid, key, lvl + 1))


func _next_power(cid: String, lvl: int) -> String:
	if lvl >= DB.card_max_level:
		return ""
	return "%.1f" % float(DeckAI.analyze(cid, lvl + 1).get("power", 0.0))


static func _secs(v: float) -> String:
	return ("%ds" % int(v)) if v > 0.0 else "None"


static func _num(v: float) -> String:
	return str(int(round(v))) if absf(v - roundf(v)) < 0.05 or v >= 10.0 else "%.1f" % v


## Formats a param value with its unit (%, s, m) the way card texts do.
static func _fmt(key: String, v: Variant) -> String:
	var x := float(v)
	if key in FRACTION_KEYS and x <= 1.0:
		return "%d%%" % int(round(x * 100.0))
	if key in PERCENT_KEYS:
		return "%s%%" % _num(x)
	if key in SECOND_KEYS:
		return "%.1fs" % x
	if key in METRE_KEYS or key == "area_radius":
		return "%s m" % _num(x)
	return _num(x)
