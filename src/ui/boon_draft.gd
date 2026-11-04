class_name BoonDraft
extends Control
## Dugout Draft overlay (Update 9): after a boss, three big boon cards to choose from. Pick with
## a click, the 1/2/3 keys, or a controller (left/right + accept). The battle is held in state
## "draft" underneath; Battle.choose_boon applies the pick and continues the game.
##
## Pausing: the overlay processes with the battle, so it ignores input while the pause menu is
## open. Its tweens ignore the game speed (2x / 3x), so the reveal always reads the same.

signal picked(id: String)

const CARD_SIZE := Vector2(360, 470)

var battle: Battle
var offers: Array = []
var cards: Array[Button] = []
var _picked := false
var _input_t := 0.35     # real seconds before keys are accepted (no accidental pick from a held key)
var _dim: ColorRect
var _box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.02, 0.05, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 18)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_box)

	var title := UITheme.title("DUGOUT DRAFT", 76, UITheme.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(title)
	var sub := UITheme.label(_subtitle(), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_body_bold())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_box.add_child(sub)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(row)
	for i in offers.size():
		var c := _make_card(str(offers[i]), i)
		cards.append(c)
		row.add_child(c)
	for i in cards.size():   # controller: left/right moves between the cards
		cards[i].focus_neighbor_left = cards[posmod(i - 1, cards.size())].get_path()
		cards[i].focus_neighbor_right = cards[posmod(i + 1, cards.size())].get_path()

	var foot := UITheme.label("Click a card or press 1 / 2 / 3.  Boons last for the rest of this game.", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_box.add_child(foot)
	_reveal(title, sub, foot)
	Audio.ui("ui_slide")


func _subtitle() -> String:
	var r: RunState = battle.run if battle else null
	if r and r.mode_id == "boss_rush":
		return "Boss beaten! Pick a boon to take into the next round."
	return "Boss beaten! Pick a boon. It lasts for the rest of this game."


func _process(delta: float) -> void:
	_input_t -= delta / maxf(Engine.time_scale, 0.01)


## One big choice card: rarity tag, icon medallion, name, effect, key hint.
func _make_card(id: String, index: int) -> Button:
	var b := Boons.get_boon(id)
	var rarity := str(b.get("rarity", "common"))
	var col := Boons.rarity_color(rarity)
	var card := Button.new()
	card.name = "Boon_" + id
	card.set_meta("boon", id)
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = "%s (%s): %s" % [b.get("name", id), Boons.rarity_name(rarity), b.get("text", "")]
	var glow := 0.0 if rarity == "common" else (14.0 if rarity == "rare" else 24.0)
	card.add_theme_stylebox_override("normal", _card_style(col, 0.0, glow, 3))
	card.add_theme_stylebox_override("hover", _card_style(col, 0.16, glow + 10.0, 4))
	card.add_theme_stylebox_override("pressed", _card_style(col, 0.3, glow + 14.0, 4))
	card.add_theme_stylebox_override("focus", _card_style(col, 0.12, glow + 8.0, 4, UITheme.GOLD))
	card.pressed.connect(func() -> void: pick(id))
	card.mouse_entered.connect(func() -> void:
		Audio.ui("card_hover", -6.0)
		card.grab_focus())
	card.focus_entered.connect(func() -> void: _hover(card, true))
	card.focus_exited.connect(func() -> void: _hover(card, false))

	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 22)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(vb)
	var tag_row := HBoxContainer.new()
	tag_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tag_row.add_child(UITheme.badge(Boons.rarity_name(rarity).to_upper(), col.darkened(0.25), UITheme.FS_SMALL))
	vb.add_child(tag_row)
	# Icon medallion.
	var med_row := CenterContainer.new()
	med_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var med := PanelContainer.new()
	med.custom_minimum_size = Vector2(150, 150)
	var ms := UITheme.panel_style(Color(col.darkened(0.55), 0.95), Color(col.lightened(0.2), 0.9), 3, 75, 0)
	ms.shadow_color = Color(col, 0.35)
	ms.shadow_size = 12
	med.add_theme_stylebox_override("panel", ms)
	med.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UITheme.icon_rect(str(b.get("icon", "star")), 92, col.lightened(0.55))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	med.add_child(ic)
	med_row.add_child(med)
	vb.add_child(med_row)
	var name_l := UITheme.label(str(b.get("name", id)).to_upper(), 36, UITheme.OFFWHITE, UITheme.font_display())
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	vb.add_child(name_l)
	var text_l := UITheme.label(str(b.get("text", "")), UITheme.FS_LEAD, Color(0.86, 0.91, 1.0), UITheme.font_body())
	text_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size = Vector2(CARD_SIZE.x - 60, 0)
	text_l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(text_l)
	var key_row := HBoxContainer.new()
	key_row.alignment = BoxContainer.ALIGNMENT_CENTER
	key_row.add_theme_constant_override("separation", 8)
	var key := PanelContainer.new()
	key.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.45), 2, 6, 4))
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var kl := UITheme.label(" %d " % (index + 1), UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_header())
	key.add_child(kl)
	key_row.add_child(key)
	key_row.add_child(UITheme.label("TAKE", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold()))
	vb.add_child(key_row)
	_ignore_mouse(m)
	return card


func _card_style(col: Color, lift: float, glow: float, bw: int, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var bg := Color(0.05, 0.08, 0.14, 0.97).lerp(col.darkened(0.5), 0.28 + lift)
	var s := UITheme.panel_style(bg, border if border.a > 0.0 else col, bw, 18, 0)
	if glow > 0.0:
		s.shadow_color = Color(col, 0.45)
		s.shadow_size = int(glow)
	return s


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _hover(card: Button, on: bool) -> void:
	if _picked or not is_instance_valid(card):
		return
	card.pivot_offset = card.size * 0.5
	var tw := card.create_tween().set_ignore_time_scale(true)
	tw.tween_property(card, "scale", Vector2.ONE * (1.05 if on else 1.0), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Dim in, title drops, the three cards flip in one after another (rare and epic flash).
func _reveal(title: Control, sub: Control, foot: Control) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_dim, "color:a", 0.62, 0.3)
	for c in [title, sub, foot]:
		(c as Control).modulate.a = 0.0
	title.scale = Vector2(1.25, 1.25)
	var tt := create_tween().set_ignore_time_scale(true).set_parallel(true)
	tt.tween_callback(func() -> void: title.pivot_offset = title.size * 0.5)
	tt.tween_property(title, "modulate:a", 1.0, 0.25)
	tt.tween_property(title, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tt.tween_property(sub, "modulate:a", 1.0, 0.3).set_delay(0.15)
	tt.tween_property(foot, "modulate:a", 1.0, 0.3).set_delay(0.9)
	for i in cards.size():
		var c := cards[i]
		c.modulate.a = 0.0
		c.scale = Vector2(0.05, 1.0)
		var rarity := str(Boons.get_boon(str(offers[i])).get("rarity", "common"))
		var ct := c.create_tween().set_ignore_time_scale(true)
		ct.tween_interval(0.25 + 0.16 * i)
		ct.tween_callback(func() -> void:
			c.pivot_offset = c.size * 0.5
			Audio.ui("card_flip" if rarity == "common" else "reveal_" + rarity, -5.0))
		ct.set_parallel(true)
		ct.tween_property(c, "modulate:a", 1.0, 0.18)
		ct.tween_property(c, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if rarity != "common":
			ct.chain().tween_property(c, "modulate", Color(1.5, 1.45, 1.6), 0.08)
			ct.chain().tween_property(c, "modulate", Color.WHITE, 0.3)
	var ft := create_tween().set_ignore_time_scale(true)
	ft.tween_interval(0.3 + 0.16 * cards.size())
	ft.tween_callback(func() -> void:
		if not _picked and cards.size() > 1 and get_viewport().gui_get_focus_owner() == null:
			cards[1].grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if _picked or not event.is_pressed() or event.is_echo():
		return
	for i in cards.size():
		if event.is_action_pressed("card_%d" % (i + 1)):
			get_viewport().set_input_as_handled()
			if _input_t <= 0.0:
				pick(str(offers[i]))
			return


## Takes boon `id`: the battle applies it and the game goes on; the overlay celebrates and fades.
func pick(id: String) -> void:
	if _picked or not id in offers:
		return
	_picked = true
	var chosen: Button = null
	for c in cards:
		if str(c.get_meta("boon")) == id:
			chosen = c
	Audio.ui("ui_confirm")
	picked.emit(id)
	if battle and is_instance_valid(battle):
		battle.choose_boon(id)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ignore_mouse(self)
	var tw := create_tween().set_ignore_time_scale(true).set_parallel(true)
	for c in cards:
		c.pivot_offset = c.size * 0.5
		if c == chosen:
			tw.tween_property(c, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(c, "modulate", Color(1.6, 1.5, 1.2), 0.12)
		else:
			tw.tween_property(c, "modulate:a", 0.0, 0.25)
			tw.tween_property(c, "scale", Vector2(0.9, 0.9), 0.25)
	tw.chain().tween_interval(0.35)
	tw.chain().tween_property(self, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(queue_free)
