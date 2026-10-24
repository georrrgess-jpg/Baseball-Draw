class_name SettingsPanel
extends Control
## Settings UI: display, graphics, audio, gameplay, accessibility and key rebinding.
## Used full-screen from the main menu and as an overlay from the pause menu.

var overlay := false
var _waiting_action := ""
var _bind_buttons := {}
var _tabs: TabContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if overlay:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0.01, 0.02, 0.05, 0.85)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := 80 if overlay else 0
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	if overlay:
		var head := HBoxContainer.new()
		var t := UITheme.title("SETTINGS", 56)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var close := UITheme.small_button("Close", UITheme.BLUE, 24)
		close.pressed.connect(func() -> void:
			Settings.save_settings()
			queue_free())
		head.add_child(close)
		vb.add_child(head)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_tabs)
	_tabs.add_child(_display_tab())
	_tabs.add_child(_graphics_tab())
	_tabs.add_child(_audio_tab())
	_tabs.add_child(_gameplay_tab())
	_tabs.add_child(_access_tab())
	_tabs.add_child(_controls_tab())


func _page(name: String) -> Array:
	var s := ScrollContainer.new()
	s.name = name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 14)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(grid)
	return [s, grid]


func _row_label(grid: GridContainer, text: String, tip := "") -> void:
	var l := UITheme.label(text, 24, UITheme.OFFWHITE)
	l.custom_minimum_size = Vector2(380, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(l)


func _option(grid: GridContainer, text: String, items: Array, current: int, cb: Callable, tip := "") -> OptionButton:
	_row_label(grid, text, tip)
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(clampi(current, 0, items.size() - 1))
	o.custom_minimum_size = Vector2(360, 44)
	o.item_selected.connect(func(i: int) -> void:
		cb.call(i)
		Settings.save_settings())
	grid.add_child(o)
	return o


func _check(grid: GridContainer, text: String, current: bool, cb: Callable, tip := "") -> CheckButton:
	_row_label(grid, text, tip)
	var c := CheckButton.new()
	c.button_pressed = current
	c.toggled.connect(func(v: bool) -> void:
		cb.call(v)
		Settings.save_settings()
		Audio.ui("ui_toggle"))
	grid.add_child(c)
	return c


func _slider(grid: GridContainer, text: String, current: float, min_v: float, max_v: float, step: float, cb: Callable, fmt := "%d%%", mult := 100.0) -> HSlider:
	_row_label(grid, text)
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(360, 0)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = current
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(280, 30)
	var vl := UITheme.label(fmt % (current * mult), 22, UITheme.GOLD, UITheme.font_body_bold())
	vl.custom_minimum_size = Vector2(70, 0)
	s.value_changed.connect(func(v: float) -> void:
		vl.text = fmt % (v * mult)
		cb.call(v))
	s.drag_ended.connect(func(_c: bool) -> void: Settings.save_settings())
	hb.add_child(s)
	hb.add_child(vl)
	grid.add_child(hb)
	return s


func _display_tab() -> Control:
	var p := _page("Display")
	var g: GridContainer = p[1]
	var modes := ["windowed", "borderless", "fullscreen", "exclusive"]
	_option(g, "Window mode", ["Windowed", "Borderless window", "Fullscreen", "Exclusive fullscreen"],
		modes.find(Settings.get_value("display", "window_mode", "windowed")),
		func(i: int) -> void: Settings.set_value("display", "window_mode", modes[i]))
	var res_names := []
	for r in Settings.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
	_option(g, "Resolution (windowed)", res_names, int(Settings.get_value("display", "resolution", 2)),
		func(i: int) -> void: Settings.set_value("display", "resolution", i))
	_check(g, "V-Sync", bool(Settings.get_value("display", "vsync", true)), func(v: bool) -> void: Settings.set_value("display", "vsync", v))
	var caps := [0, 30, 60, 120, 144, 240]
	_option(g, "Frame rate cap", ["Unlimited", "30", "60", "120", "144", "240"], caps.find(int(Settings.get_value("display", "max_fps", 0))),
		func(i: int) -> void: Settings.set_value("display", "max_fps", caps[i]))
	_slider(g, "UI scale", float(Settings.get_value("display", "ui_scale", 1.0)), 0.75, 1.5, 0.05,
		func(v: float) -> void: Settings.set_value("display", "ui_scale", v))
	return p[0]


func _graphics_tab() -> Control:
	var p := _page("Graphics")
	var g: GridContainer = p[1]
	_option(g, "Quality preset", Settings.QUALITY_NAMES, int(Settings.get_value("graphics", "preset", 2)), func(i: int) -> void:
		Settings.apply_preset(i)
		_rebuild_graphics(), "Sets every option below. Low is for integrated GPUs; Ultra for high-end cards.")
	_option(g, "Shadows", ["Off", "Low", "Medium", "High"], int(Settings.get_value("graphics", "shadows", 2)),
		func(i: int) -> void: Settings.set_value("graphics", "shadows", i))
	_option(g, "Anti-aliasing (MSAA)", ["Off", "2x", "4x", "8x"], int(Settings.get_value("graphics", "msaa", 2)),
		func(i: int) -> void: Settings.set_value("graphics", "msaa", i))
	_check(g, "FXAA", bool(Settings.get_value("graphics", "fxaa", false)), func(v: bool) -> void: Settings.set_value("graphics", "fxaa", v))
	_check(g, "Ambient occlusion (SSAO)", bool(Settings.get_value("graphics", "ssao", true)), func(v: bool) -> void: Settings.set_value("graphics", "ssao", v),
		"Takes effect when the next scene loads.")
	_check(g, "Bloom / glow", bool(Settings.get_value("graphics", "glow", true)), func(v: bool) -> void: Settings.set_value("graphics", "glow", v))
	_check(g, "Volumetric fog", bool(Settings.get_value("graphics", "fog", true)), func(v: bool) -> void: Settings.set_value("graphics", "fog", v))
	_slider(g, "Particle amount", float(Settings.get_value("graphics", "particles", 1.0)), 0.1, 1.0, 0.05,
		func(v: float) -> void: Settings.set_value("graphics", "particles", v))
	_slider(g, "Crowd density", float(Settings.get_value("graphics", "crowd", 1.0)), 0.0, 1.0, 0.05,
		func(v: float) -> void: Settings.set_value("graphics", "crowd", v))
	_slider(g, "3D render scale (FSR below 100%)", float(Settings.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0, 0.05,
		func(v: float) -> void: Settings.set_value("graphics", "render_scale", v))
	_check(g, "Show FPS counter", bool(Settings.get_value("graphics", "show_fps", false)), func(v: bool) -> void: Settings.set_value("graphics", "show_fps", v))
	var note := UITheme.label("Particles, crowd, SSAO and fog apply from the next match.", 18, UITheme.MUTED)
	g.add_child(note)
	return p[0]


func _rebuild_graphics() -> void:
	var old := _tabs.get_child(1)
	var fresh := _graphics_tab()
	_tabs.remove_child(old)
	old.queue_free()
	_tabs.add_child(fresh)
	_tabs.move_child(fresh, 1)
	_tabs.current_tab = 1


func _audio_tab() -> Control:
	var p := _page("Audio")
	var g: GridContainer = p[1]
	for k in [["master", "Master volume"], ["music", "Music"], ["sfx", "Effects"], ["ambience", "Ambience & crowd"], ["ui", "Interface"]]:
		var key: String = k[0]
		_slider(g, k[1], float(Settings.get_value("audio", key, 0.8)), 0.0, 1.0, 0.05, func(v: float) -> void:
			Settings.set_value("audio", key, v)
			if key in ["sfx", "master"]:
				Audio.play("ball_hit", -6.0, 0.0, 150))
	return p[0]


func _gameplay_tab() -> Control:
	var p := _page("Gameplay")
	var g: GridContainer = p[1]
	_check(g, "Auto-start next wave after a short break", bool(Settings.get_value("gameplay", "auto_start_waves", true)),
		func(v: bool) -> void: Settings.set_value("gameplay", "auto_start_waves", v), "When off, press Space to start every wave.")
	_check(g, "Damage numbers", bool(Settings.get_value("gameplay", "damage_numbers", true)), func(v: bool) -> void: Settings.set_value("gameplay", "damage_numbers", v))
	_slider(g, "Screen shake", float(Settings.get_value("gameplay", "screen_shake", 1.0)), 0.0, 1.5, 0.05,
		func(v: float) -> void: Settings.set_value("gameplay", "screen_shake", v))
	_slider(g, "Camera pan speed", float(Settings.get_value("gameplay", "camera_speed", 1.0)), 0.4, 2.0, 0.05,
		func(v: float) -> void: Settings.set_value("gameplay", "camera_speed", v))
	_check(g, "Edge panning (mouse at screen edge)", bool(Settings.get_value("gameplay", "edge_pan", false)),
		func(v: bool) -> void: Settings.set_value("gameplay", "edge_pan", v))
	var reset := UITheme.small_button("Reset profile...", UITheme.SCARLET, 20)
	_row_label(g, "Danger zone")
	reset.pressed.connect(func() -> void:
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Erase ALL progress (levels, cards, unlocks, records)? This cannot be undone."
		dlg.process_mode = Node.PROCESS_MODE_ALWAYS
		dlg.confirmed.connect(func() -> void:
			Profile.reset_profile()
			Router.toast("Profile reset.", "warn"))
		add_child(dlg)
		dlg.popup_centered(Vector2i(560, 180)))
	g.add_child(reset)
	return p[0]


func _access_tab() -> Control:
	var p := _page("Accessibility")
	var g: GridContainer = p[1]
	_check(g, "Larger text", bool(Settings.get_value("accessibility", "large_text", false)), func(v: bool) -> void:
		Settings.set_value("accessibility", "large_text", v, false)
		Settings.apply_display())
	_check(g, "Reduce flashing effects", bool(Settings.get_value("accessibility", "reduce_flashes", false)),
		func(v: bool) -> void: Settings.set_value("accessibility", "reduce_flashes", v))
	_check(g, "Color-blind friendly markers", bool(Settings.get_value("accessibility", "colorblind", false)),
		func(v: bool) -> void: Settings.set_value("accessibility", "colorblind", v), "Runner rings switch from red to a high-contrast yellow/blue scheme.")
	_check(g, "High-contrast HUD", bool(Settings.get_value("accessibility", "high_contrast", false)),
		func(v: bool) -> void: Settings.set_value("accessibility", "high_contrast", v))
	return p[0]


func _controls_tab() -> Control:
	var p := _page("Controls")
	var g: GridContainer = p[1]
	for action in InputConfig.REBINDABLE:
		_row_label(g, InputConfig.display_name(action))
		var b := UITheme.small_button(InputConfig.binding_text(action), UITheme.BLUE, 22)
		b.custom_minimum_size = Vector2(240, 42)
		b.pressed.connect(func() -> void:
			_waiting_action = action
			b.text = "Press a key..."
			Audio.ui("ui_click"))
		g.add_child(b)
		_bind_buttons[action] = b
	_row_label(g, "Mouse: left = select / drag / cast · right = cancel · wheel = zoom")
	var reset := UITheme.small_button("Reset to defaults", UITheme.SCARLET, 22)
	reset.pressed.connect(func() -> void:
		InputConfig.reset_defaults()
		_refresh_bindings())
	g.add_child(reset)
	return p[0]


func _refresh_bindings() -> void:
	for a in _bind_buttons.keys():
		_bind_buttons[a].text = InputConfig.binding_text(a)


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	var code := int(k.physical_keycode)
	if code == KEY_ESCAPE:
		_waiting_action = ""
	else:
		InputConfig.rebind(_waiting_action, code)
		_waiting_action = ""
		Audio.ui("ui_confirm")
	_refresh_bindings()
	get_viewport().set_input_as_handled()
