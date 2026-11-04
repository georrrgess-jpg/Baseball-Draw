class_name LevelRoadView
extends VBoxContainer
## The account level road (Update 6), drawn like the defenders' level road: a horizontal
## track of levels 1–50 with each level's reward (unlocks, packs, coins), the current
## position and the next reward. Scrolls to the current level. Data: LevelRoad.
## Update 9: each level shows its reward as pictures (the defender's portrait, the stadium,
## the pack art) with the coins as a number, and a one-line caption that never wraps.

const NODE_W := 152
const CARD_W := 132
const CARD_H := 118
const ACCENT := Color("#3DDC84")

var _scroll: ScrollContainer
var _level := 1


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	_level = int(Profile.data.level)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	var sh := UITheme.section_header("ACCOUNT LEVEL ROAD", "upgrade", ACCENT, UITheme.FS_H3)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	var maxed := _level >= Profile.MAX_ACCOUNT_LEVEL
	head.add_child(UITheme.label("LEVEL %d" % _level + ("  ·  MAX" if maxed else "  ·  %s / %s XP" % [UITheme.format_int(int(Profile.data.xp)),
		UITheme.format_int(Profile.xp_to_next(_level))]), UITheme.FS_SMALL, ACCENT, UITheme.font_body_bold()))
	# Next reward and next milestone.
	if not maxed:
		var nx := HBoxContainer.new()
		nx.add_theme_constant_override("separation", 12)
		add_child(nx)
		nx.add_child(_next_tile("NEXT REWARD  ·  LEVEL %d" % (_level + 1), LevelRoad.reward_text(_level + 1), LevelRoad.icon_for(_level + 1), UITheme.GOLD))
		var ms := LevelRoad.next_milestone(_level + 1)
		if ms > 0:
			nx.add_child(_next_tile("NEXT MILESTONE  ·  LEVEL %d" % ms, LevelRoad.reward_text(ms), LevelRoad.icon_for(ms), UITheme.PURPLE.lightened(0.3)))
	_scroll = ScrollContainer.new()
	_scroll.name = "LevelRoad"
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, CARD_H + 104)
	add_child(_scroll)
	var track := HBoxContainer.new()
	track.add_theme_constant_override("separation", 0)
	_scroll.add_child(track)
	for l in range(1, Profile.MAX_ACCOUNT_LEVEL + 1):
		track.add_child(_node(l))
	_scroll_to_current.call_deferred()


func _scroll_to_current() -> void:
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_horizontal = maxi(0, (_level - 3) * NODE_W)


func _next_tile(caption: String, text: String, icon: String, col: Color) -> PanelContainer:
	var p := UITheme.tile_panel(Color(col, 0.5), 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var ic := UITheme.icon_rect(icon, 34, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	v.add_child(UITheme.label(caption, UITheme.FS_MIN, col, UITheme.font_body_bold()))
	var t := UITheme.label(text if text != "" else "—", UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_header())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(t)
	return p


## One level: the reward card (pictures and coins), the track with the level number, and a
## one-line caption naming the main reward.
func _node(l: int) -> Control:
	var reached := l <= _level
	var cur := l == _level
	var nxt := l == _level + 1
	var mile := LevelRoad.is_milestone(l)
	var r := LevelRoad.reward(l)
	var node := VBoxContainer.new()
	node.name = "Level%d" % l
	node.custom_minimum_size = Vector2(NODE_W, 0)
	node.add_theme_constant_override("separation", 4)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	var text := LevelRoad.reward_text(l)
	node.tooltip_text = "Level %d: %s" % [l, text if text != "" else "Starting level"]
	# Reward card.
	var box := PanelContainer.new()
	var border := Color(1, 1, 1, 0.14)
	var bg := Color(0.05, 0.08, 0.13, 0.95)
	if mile and not reached:
		border = Color(UITheme.GOLD, 0.75)
	if nxt:
		border = UITheme.GOLD
		bg = Color(0.18, 0.14, 0.04, 0.95)
	box.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 2 if (mile or nxt) else 1, 10, 6))
	box.custom_minimum_size = Vector2(CARD_W, CARD_H)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(box)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.add_theme_constant_override("separation", 2)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(bv)
	var pic := _picture(l, r)
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if reached:
		pic.modulate = Color(0.55, 0.55, 0.6)
	bv.add_child(pic)
	if int(r.coins) > 0:
		var cr := HBoxContainer.new()
		cr.alignment = BoxContainer.ALIGNMENT_CENTER
		cr.add_theme_constant_override("separation", 4)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cr.add_child(UITheme.icon_rect("coin", 20, UITheme.GOLD if not reached else Color(UITheme.GOLD, 0.45)))
		cr.add_child(UITheme.label(UITheme.format_int(int(r.coins)), UITheme.FS_LEAD, UITheme.GOLD if not reached else UITheme.MUTED, UITheme.font_header()))
		bv.add_child(cr)
	# Track: line, level circle, line.
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 0)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(tr)
	var left := ColorRect.new()
	left.color = Color(ACCENT, 0.85) if reached else Color(1, 1, 1, 0.12)
	left.custom_minimum_size = Vector2(0, 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if l == 1:
		left.color = Color(0, 0, 0, 0)
	tr.add_child(left)
	var circ := PanelContainer.new()
	var fill := Color(ACCENT, 0.9) if reached else Color(0.08, 0.1, 0.16, 0.95)
	var cb := UITheme.GOLD if (cur or nxt) else (Color(ACCENT.lightened(0.3), 0.9) if reached else Color(1, 1, 1, 0.18))
	circ.add_theme_stylebox_override("panel", UITheme.panel_style(fill, cb, 3 if cur else 2, 22, 2))
	circ.custom_minimum_size = Vector2(46 if cur else 40, 46 if cur else 40)
	circ.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UITheme.label(str(l), 22 if cur else 20, Color.WHITE if reached else UITheme.OFFWHITE.darkened(0.25), UITheme.font_header())
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circ.add_child(nl)
	tr.add_child(circ)
	var right := ColorRect.new()
	right.color = Color(ACCENT, 0.85) if l < _level else Color(1, 1, 1, 0.12)
	right.custom_minimum_size = Vector2(0, 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if l == Profile.MAX_ACCOUNT_LEVEL:
		right.color = Color(0, 0, 0, 0)
	tr.add_child(right)
	# Caption: one line, never wrapping into the neighbours.
	var cap: Control
	if cur:
		cap = UITheme.badge("YOU ARE HERE", UITheme.GOLD.darkened(0.3), UITheme.FS_SMALL)
		cap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		var cl := UITheme.label(caption(l), UITheme.FS_BODY + 1, UITheme.GOLD if nxt else (UITheme.MUTED if reached else UITheme.OFFWHITE),
			UITheme.font_header())
		cl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cl.custom_minimum_size = Vector2(NODE_W - 12, 0)
		cl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cap = cl
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(cap)
	return node


## The main reward of a level in a few words: "Dex joins", "Neon Diamond", "Pro Pack",
## "2 Rookie Packs", "Pro Pack +1", "Coins".
static func caption(level: int) -> String:
	var r := LevelRoad.reward(level)
	for u in r.unlocks:
		return ("%s joins" % u.name) if u.type == "defender" else str(u.name)
	var packs: Array = r.packs
	if packs.is_empty():
		return "Coins" if int(r.coins) > 0 else "Start"
	var best := _best_pack(packs)
	var same := packs.count(best)
	var nm := str(DB.pack(best).get("name", best))
	if same == packs.size():
		return nm if same == 1 else "%d %ss" % [same, nm]
	return "%s +%d" % [nm, packs.size() - same]


static func _best_pack(packs: Array) -> String:
	for p in ["champion", "pro", "signature", "rookie"]:
		if p in packs:
			return p
	return str(packs[0])


## The reward's picture: the new defender's portrait, the stadium, the pack art (up to three,
## fanned), or a big coin.
func _picture(l: int, r: Dictionary) -> Control:
	var h := CARD_H - (34 if int(r.coins) > 0 else 12)
	for u in r.unlocks:
		if u.type == "defender":
			var pr := MenuScreen.portrait_rect(str(u.id), h - 6, DB.defender_accent(str(u.id)))
			pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return pr
		var tex := UITheme.arena_thumbnail(str(u.id))
		if tex:
			var frame := PanelContainer.new()
			frame.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0, 0, 0, 0.5), Color(UITheme.GOLD, 0.6), 2, 6, 2))
			frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(CARD_W - 18, h - 6)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame.add_child(tr)
			return frame
		return UITheme.icon_rect("map", h * 0.7, UITheme.GOLD)
	var packs: Array = r.packs
	if not packs.is_empty():
		var shown: Array = packs.slice(0, 3)
		shown.sort_custom(func(a: String, b: String) -> bool: return a != b and _best_pack([a, b]) == b)   # best pack in front
		var pw := h * 0.65
		var fan := Control.new()
		fan.custom_minimum_size = Vector2(pw + (shown.size() - 1) * pw * 0.42, h)
		fan.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for i in shown.size():
			var pa := PackArt.new(str(shown[i]))
			pa.custom_minimum_size = Vector2(pw, h)
			pa.size = Vector2(pw, h)
			pa.position = Vector2(i * pw * 0.42, 0)
			pa.rotation = deg_to_rad((i - (shown.size() - 1) * 0.5) * 6.0)
			pa.pivot_offset = Vector2(pw * 0.5, h)
			fan.add_child(pa)
		return fan
	if l <= 1:
		return UITheme.icon_rect("play", h * 0.6, UITheme.OFFWHITE)
	return UITheme.icon_rect("coin", h * 0.6, UITheme.GOLD)
