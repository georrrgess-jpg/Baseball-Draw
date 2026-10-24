class_name MenuScreen
extends Control
## Shared layout for the 2D menus: themed background, header bar with title,
## back button and currencies, and a content area.

var content: Control
var _coins_label: Label
var _stars_label: Label


func setup_screen(title: String, subtitle := "") -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UITheme.NAVY_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var img_path := "res://assets/textures/ui/loading_bg.png"
	if ResourceLoader.exists(img_path):
		var img := TextureRect.new()
		img.texture = load(img_path)
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.modulate = Color(1, 1, 1, 0.22)
		add_child(img)
	var pat_path := "res://assets/textures/ui/diamond_pattern.png"
	if ResourceLoader.exists(pat_path):
		var pat := TextureRect.new()
		pat.texture = load(pat_path)
		pat.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pat.stretch_mode = TextureRect.STRETCH_TILE
		pat.modulate = Color(1, 1, 1, 0.5)
		add_child(pat)
	var vig := "res://assets/textures/ui/vignette.png"
	if ResourceLoader.exists(vig):
		var v := TextureRect.new()
		v.texture = load(vig)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		v.stretch_mode = TextureRect.STRETCH_SCALE
		v.modulate = Color(1, 1, 1, 0.6)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(v)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	outer.add_child(header)
	var back := UITheme.menu_button("◀  BACK", UITheme.MUTED, 28)
	back.custom_minimum_size = Vector2(170, 56)
	back.pressed.connect(go_back)
	header.add_child(back)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", -6)
	tb.add_child(UITheme.title(title, 64))
	if subtitle != "":
		tb.add_child(UITheme.label(subtitle, 20, UITheme.MUTED, UITheme.font_body_bold()))
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tb)
	var cur := HBoxContainer.new()
	cur.add_theme_constant_override("separation", 18)
	var cb := HBoxContainer.new()
	cb.add_child(UITheme.icon_rect("coin", 32, UITheme.GOLD))
	_coins_label = UITheme.label("", 32, UITheme.GOLD, UITheme.font_header())
	cb.add_child(_coins_label)
	cur.add_child(cb)
	var sb := HBoxContainer.new()
	sb.add_child(UITheme.icon_rect("star", 32, Color(0.7, 0.85, 1.0)))
	_stars_label = UITheme.label("", 32, Color(0.7, 0.85, 1.0), UITheme.font_header())
	sb.add_child(_stars_label)
	cur.add_child(sb)
	header.add_child(cur)
	var brush_path := "res://assets/textures/logo/brush_stroke.png"
	if ResourceLoader.exists(brush_path):
		var brush := TextureRect.new()
		brush.texture = load(brush_path)
		brush.custom_minimum_size = Vector2(0, 10)
		brush.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		brush.stretch_mode = TextureRect.STRETCH_SCALE
		brush.modulate = Color(1, 1, 1, 0.8)
		outer.add_child(brush)
	content = VBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(content)
	refresh_currency()
	Profile.changed.connect(refresh_currency)
	Audio.play_music("menu_theme")


func refresh_currency() -> void:
	if _coins_label:
		_coins_label.text = UITheme.format_int(int(Profile.data.coins))
		_stars_label.text = UITheme.format_int(int(Profile.data.stars))


func go_back() -> void:
	Audio.ui("ui_back")
	Profile.save_now()
	Router.goto("main_menu")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		go_back()
		get_viewport().set_input_as_handled()


static func panel(bg := Color(0.04, 0.07, 0.12, 0.9), border := Color(1, 1, 1, 0.1), pad := 16) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 1, 12, pad))
	return p


static func portrait_rect(id: String, size := 64.0, accent := Color(1, 1, 1, 0.3)) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(accent.darkened(0.65), accent, 2, 8, 2))
	var r := TextureRect.new()
	r.texture = DB.portrait(id)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	frame.add_child(r)
	if r.texture == null:
		var l := UITheme.label(str(DB.defender(id).get("name", DB.enemy(id).get("name", id))).substr(0, 2).to_upper(), int(size * 0.45), UITheme.OFFWHITE, UITheme.font_display())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2(size, size)
		frame.add_child(l)
	return frame
