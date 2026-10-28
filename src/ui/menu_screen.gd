class_name MenuScreen
extends Control
## Shared layout for the 2D menus: themed background, header bar with title,
## back button and currencies, and a content area.

var content: Control
var back_button: Button
var _header: Control
var _coins_label: Label
var _stars_label: Label
var _pill: Control
## Open popups on this screen (topmost last): Esc closes the top one before leaving the screen.
var _overlays: Array[Control] = []
## Screen id for the hint system ("" = no "?" button and no first-visit hints).
var help_id := ""
var help_targets := Callable()
var help_extra := Callable()
var help_button: Button
## Optional hook run on Esc before leaving: return true to stay (it handled the key, e.g. Esc
## skips a pack reveal before it leaves the screen). The BACK button always leaves.
var before_back := Callable()


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
	header.add_theme_constant_override("separation", 22)
	outer.add_child(header)
	# Back is always the first thing top-left, the same size on every screen.
	var back := UITheme.button("◀  BACK", "secondary", 26, "", UITheme.MUTED)
	back.custom_minimum_size = Vector2(170, UITheme.BTN_H)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.tooltip_text = "Back to %s (Esc)" % _screen_name(Router.back_target())
	back.pressed.connect(_on_back.bind(false))
	header.add_child(back)
	back_button = back
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", -8)
	tb.add_child(UITheme.title(title, UITheme.FS_TITLE))
	if subtitle != "":
		tb.add_child(UITheme.label(subtitle, UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold()))
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(tb)
	# Currencies sit in one pill on the right of every menu.
	var pill := PanelContainer.new()
	var ps := UITheme.panel_style(Color(0.03, 0.05, 0.09, 0.85), Color(1, 1, 1, 0.12), 1, 26, 0)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 4
	ps.content_margin_bottom = 4
	pill.add_theme_stylebox_override("panel", ps)
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var cur := HBoxContainer.new()
	cur.add_theme_constant_override("separation", 18)
	pill.add_child(cur)
	var cb := HBoxContainer.new()
	cb.tooltip_text = "Coins: buy card packs, card upgrades and gear"
	cb.add_child(UITheme.icon_rect("coin", 30, UITheme.GOLD))
	_coins_label = UITheme.label("", 32, UITheme.GOLD, UITheme.font_header())
	cb.add_child(_coins_label)
	cur.add_child(cb)
	var sb := HBoxContainer.new()
	sb.tooltip_text = "Stars: earned from achievements, spent on uniforms"
	sb.add_child(UITheme.icon_rect("star", 30, UITheme.STAR))
	_stars_label = UITheme.label("", 32, UITheme.STAR, UITheme.font_header())
	sb.add_child(_stars_label)
	cur.add_child(sb)
	header.add_child(pill)
	_pill = pill
	_header = header
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
	_play_enter.call_deferred()
	UITheme.apply_debug_ui_scale(self)


## Shared screen-enter motion: the header, then each top-level block of the content, fade and
## rise in quick succession.
func _play_enter() -> void:
	if _header:
		UITheme.animate_in(_header, 0.0, 0.99)
	var i := 0
	for c in _enter_targets():
		if c is Control and (c as Control).visible:
			UITheme.animate_in(c, 0.06 + i * 0.05)
			i += 1


## The blocks that animate in; screens with one wrapper container animate its children.
func _enter_targets() -> Array:
	var kids := content.get_children()
	if kids.size() == 1 and (kids[0] is BoxContainer):
		return kids[0].get_children()
	return kids


func refresh_currency() -> void:
	if _coins_label:
		_coins_label.text = UITheme.format_int(int(Profile.data.coins))
		_stars_label.text = UITheme.format_int(int(Profile.data.stars))


## BACK and Esc: to the screen that opened this one through a link, else the main menu.
func go_back() -> void:
	Audio.ui("ui_back")
	Profile.save_now()
	Router.back()


static func _screen_name(scene: String) -> String:
	return {"main_menu": "the main menu", "play_menu": "Play", "packs": "Card Packs", "deck_builder": "Cards & Deck",
		"card_upgrades": "Upgrade Cards", "roster": "Team", "progression": "Progression", "settings": "Settings"}.get(scene, "the main menu")


## Turns on the hint system for this screen: a "?" button in the header (left of the currencies)
## that replays the screen's tips, and the first-visit tips themselves. `targets` returns
## {hint_id: Control} for the arrows; `extra` returns feature hint ids to add on this visit.
func set_help(screen_id: String, targets := Callable(), extra := Callable()) -> void:
	help_id = screen_id
	help_targets = targets
	help_extra = extra
	if help_button == null and _header:
		help_button = Hints.help_button(self, screen_id, targets, extra)
		_header.add_child(help_button)
		_header.move_child(help_button, _pill.get_index() if _pill else _header.get_child_count() - 1)
	var ex: Array = extra.call() if extra.is_valid() else []
	Hints.first_visit(self, screen_id, targets, ex)


## Registers a popup so Esc closes it (and BACK still leaves the screen). The popup is dropped
## from the list when it is freed.
func push_overlay(c: Control) -> void:
	_overlays.append(c)
	c.tree_exiting.connect(func() -> void: _overlays.erase(c))


## Closes the topmost open popup; returns false when there is none.
func close_top_overlay() -> bool:
	while not _overlays.is_empty():
		var c: Control = _overlays.pop_back()
		if is_instance_valid(c) and c.is_inside_tree() and not c.is_queued_for_deletion():
			Audio.ui("ui_back")
			if c.has_method("close"):
				c.call("close")
			else:
				c.queue_free()
			return true
	return false


func _on_back(from_key := true) -> void:
	if close_top_overlay():
		return
	if from_key and before_back.is_valid() and bool(before_back.call()):
		return
	go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_on_back()
		get_viewport().set_input_as_handled()


static func panel(bg := UITheme.PANEL_BG, border := UITheme.BORDER, pad := 16) -> PanelContainer:
	return UITheme.card_panel(border, pad, bg)


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
