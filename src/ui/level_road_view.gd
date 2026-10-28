class_name LevelRoadView
extends VBoxContainer
## The account level road (Update 6), drawn like the defenders' level road: a horizontal
## track of levels 1–50 with each level's reward (unlocks, packs, coins), the current
## position and the next reward. Scrolls to the current level. Data: LevelRoad.

const NODE_W := 112
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
	_scroll.custom_minimum_size = Vector2(0, 196)
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


## One level: reward icon, the track with the level number, a short caption.
func _node(l: int) -> Control:
	var reached := l <= _level
	var cur := l == _level
	var nxt := l == _level + 1
	var mile := LevelRoad.is_milestone(l)
	var node := VBoxContainer.new()
	node.name = "Level%d" % l
	node.custom_minimum_size = Vector2(NODE_W, 0)
	node.add_theme_constant_override("separation", 4)
	node.mouse_filter = Control.MOUSE_FILTER_PASS
	var text := LevelRoad.reward_text(l)
	node.tooltip_text = "Level %d: %s" % [l, text if text != "" else "Starting level"]
	# Reward box.
	var box := PanelContainer.new()
	var gold := UITheme.GOLD if (mile and not reached) else Color(1, 1, 1, 0.18)
	var bg := Color(0.05, 0.08, 0.13, 0.95)
	if nxt:
		gold = UITheme.GOLD
		bg = Color(0.18, 0.14, 0.04, 0.95)
	box.add_theme_stylebox_override("panel", UITheme.panel_style(bg, gold, 2 if (mile or nxt) else 1, 10, 6))
	box.custom_minimum_size = Vector2(68 if mile else 56, 60 if mile else 52)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if true:
		var ic := UITheme.icon_rect(LevelRoad.icon_for(l) if l > 1 else "play", 36 if mile else 28,
			Color(1, 1, 1, 0.35) if reached else (UITheme.GOLD if mile else UITheme.OFFWHITE))
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
	node.add_child(box)
	# Track: line, level circle, line.
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 0)
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
	var border := UITheme.GOLD if (cur or nxt) else (Color(ACCENT.lightened(0.3), 0.9) if reached else Color(1, 1, 1, 0.18))
	circ.add_theme_stylebox_override("panel", UITheme.panel_style(fill, border, 3 if cur else 2, 20, 2))
	circ.custom_minimum_size = Vector2(44 if cur else 38, 44 if cur else 38)
	var nl := UITheme.label(str(l), 20 if cur else 18, Color.WHITE if reached else UITheme.MUTED, UITheme.font_header())
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
	# Caption.
	var cap_text := "YOU ARE HERE" if cur else LevelRoad.reward_text(l, true)
	var cap := UITheme.label(cap_text, UITheme.FS_MIN, UITheme.GOLD if (cur or nxt) else (UITheme.MUTED if reached else UITheme.OFFWHITE), UITheme.font_body_bold())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.custom_minimum_size = Vector2(NODE_W - 6, 0)
	cap.max_lines_visible = 3
	node.add_child(cap)
	return node
