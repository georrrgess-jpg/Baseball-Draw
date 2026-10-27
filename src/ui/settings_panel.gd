class_name SettingsPanel
extends Control
## Settings UI: display, graphics, audio, gameplay, accessibility and key rebinding.
## Used full-screen from the main menu and as an overlay from the pause menu.
## Layout: a category list with a search box on the left, the category's settings on the
## right as rows (name, one-line explanation, control). Typing in the search box shows the
## matching rows from every category. Graphics has a benchmark that picks a quality preset.

const CATEGORIES := [
	["display", "Display", "display"],
	["graphics", "Graphics", "camera"],
	["audio", "Audio", "volume"],
	["gameplay", "Gameplay", "control"],
	["access", "Accessibility", "info"],
	["controls", "Controls", "keyboard"],
]

var overlay := false
var _waiting_action := ""
var _bind_buttons := {}
var _search: LineEdit
var _nav := {}             # category id -> Button
var _sections := {}        # category id -> VBoxContainer (header + rows)
var _rows: Array = []      # [{"cat", "row", "text"}]
var _current := "display"
var _scroll: ScrollContainer
var _pages: VBoxContainer
var _empty: Label
var _cur_cat := ""         # category the helpers below add rows to


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if overlay:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var dim := ColorRect.new()
		dim.color = Color(0.01, 0.02, 0.05, 0.88)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var m := 70 if overlay else 0
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, m)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)
	if overlay:
		var head := HBoxContainer.new()
		var t := UITheme.title("SETTINGS", 56)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var close := UITheme.button("Close", "secondary", 24, "back")
		close.custom_minimum_size.x = 150
		close.pressed.connect(func() -> void:
			Settings.save_settings()
			Audio.ui("ui_back")
			queue_free())
		head.add_child(close)
		vb.add_child(head)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	vb.add_child(body)

	# Left: search + categories.
	var side := UITheme.card_panel(UITheme.BORDER, 14)
	side.custom_minimum_size = Vector2(300, 0)
	body.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	side.add_child(sv)
	_search = LineEdit.new()
	_search.placeholder_text = "Search settings..."
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 48)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", UITheme.FS_BODY)
	_search.text_changed.connect(func(_t: String) -> void: _apply_filter())
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	var sic := UITheme.icon_rect("search", 26, UITheme.MUTED)
	sic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(sic)
	srow.add_child(_search)
	sv.add_child(srow)
	sv.add_child(UITheme.hsep(0.08))
	for c in CATEGORIES:
		var b := UITheme.button(c[1].to_upper(), "secondary", 26, c[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 54)
		var cid: String = c[0]
		b.pressed.connect(func() -> void: _show_category(cid))
		sv.add_child(b)
		_nav[cid] = b

	# Right: the pages.
	var main := UITheme.card_panel(UITheme.BORDER, 18)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(main)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main.add_child(_scroll)
	_pages = VBoxContainer.new()
	_pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.add_theme_constant_override("separation", 22)
	_scroll.add_child(_pages)
	_build_display()
	_build_graphics()
	_build_audio()
	_build_gameplay()
	_build_access()
	_build_controls()
	_empty = UITheme.label("No settings match your search.", UITheme.FS_LEAD, UITheme.MUTED)
	_pages.add_child(_empty)
	_show_category("display", true)
	for a in OS.get_cmdline_user_args():   # screenshot helpers
		if a.begins_with("--settings-tab="):
			_show_category(a.split("=")[1], true)
		elif a.begins_with("--settings-search="):
			_search.text = a.split("=")[1]
			_apply_filter()


# ---------------------------------------------------------------- layout + search

func _section(cat: String, title: String, icon: String, note := "") -> VBoxContainer:
	_cur_cat = cat
	var s := VBoxContainer.new()
	s.add_theme_constant_override("separation", 8)
	s.add_child(UITheme.section_header(title.to_upper(), icon, UITheme.GOLD, UITheme.FS_H2))
	if note != "":
		var n := UITheme.label(note, UITheme.FS_SMALL, UITheme.MUTED)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.add_child(n)
	_pages.add_child(s)
	_sections[cat] = s
	return s


## One settings row: name and explanation on the left, the control on the right.
func _row(text: String, desc: String, control: Control, keywords := "") -> PanelContainer:
	var p := UITheme.tile_panel(Color(1, 1, 1, 0.07), 12)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 24)
	p.add_child(hb)
	var lv := VBoxContainer.new()
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.add_theme_constant_override("separation", 0)
	lv.add_child(UITheme.label(text, UITheme.FS_LEAD, UITheme.OFFWHITE))
	if desc != "":
		var d := UITheme.label(desc, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_small())
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(d)
	hb.add_child(lv)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(control)
	_sections[_cur_cat].add_child(p)
	_rows.append({"cat": _cur_cat, "row": p, "text": (text + " " + desc + " " + keywords).to_lower()})
	return p


func _show_category(cat: String, quiet := false) -> void:
	_current = cat
	if _search.text != "":
		_search.text = ""
	_apply_filter()
	_scroll.scroll_vertical = 0
	if not quiet:
		Audio.ui("ui_tab")
		var s: Control = _sections[cat]
		UITheme.animate_in(s, 0.0, 0.99)


func _apply_filter() -> void:
	var q := _search.text.strip_edges().to_lower()
	var any := false
	for cat in _sections.keys():
		var shown := 0
		for r in _rows:
			if r.cat != cat:
				continue
			var ok: bool = q == "" or _matches(r.text, q)
			(r.row as Control).visible = ok
			if ok:
				shown += 1
		var sec: Control = _sections[cat]
		sec.visible = (cat == _current and q == "") or (q != "" and shown > 0)
		# Notes and extra widgets inside a section only show on its own page.
		for c in sec.get_children():
			if not (c is PanelContainer) and c != sec.get_child(0):
				(c as Control).visible = q == ""
		any = any or sec.visible
	_empty.visible = not any
	for k in _nav.keys():
		_nav[k].button_pressed = q == "" and k == _current


static func _matches(text: String, q: String) -> bool:
	for word in q.split(" ", false):
		if not word in text:
			return false
	return true


# ---------------------------------------------------------------- controls

func _option(text: String, desc: String, items: Array, current: int, cb: Callable, keywords := "") -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(clampi(current, 0, items.size() - 1))
	o.custom_minimum_size = Vector2(320, 46)
	o.item_selected.connect(func(i: int) -> void:
		cb.call(i)
		Settings.save_settings()
		Audio.ui("ui_toggle"))
	_row(text, desc, o, keywords + " " + " ".join(items))
	return o


func _check(text: String, desc: String, current: bool, cb: Callable, keywords := "") -> CheckButton:
	var c := CheckButton.new()
	c.button_pressed = current
	c.custom_minimum_size = Vector2(320, 46)
	c.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	c.text = "On" if current else "Off"
	c.toggled.connect(func(v: bool) -> void:
		c.text = "On" if v else "Off"
		cb.call(v)
		Settings.save_settings()
		Audio.ui("ui_toggle"))
	_row(text, desc, c, keywords)
	return c


func _slider(text: String, desc: String, current: float, min_v: float, max_v: float, step: float, cb: Callable, fmt := "%d%%", mult := 100.0, keywords := "") -> HSlider:
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(320, 0)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = current
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(230, 30)
	var vl := UITheme.label(fmt % (current * mult), UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_body_bold())
	vl.custom_minimum_size = Vector2(74, 0)
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	s.value_changed.connect(func(v: float) -> void:
		vl.text = fmt % (v * mult)
		cb.call(v))
	s.drag_ended.connect(func(_c: bool) -> void:
		Settings.save_settings()
		Audio.ui("ui_toggle", -6.0))
	hb.add_child(s)
	hb.add_child(vl)
	_row(text, desc, hb, keywords)
	return s


# ---------------------------------------------------------------- pages

func _build_display() -> void:
	_section("display", "Display", "display")
	var modes := ["windowed", "borderless", "fullscreen", "exclusive"]
	_option("Window mode", "Fullscreen fills your monitor; borderless switches faster between apps.",
		["Windowed", "Borderless window", "Fullscreen", "Exclusive fullscreen"],
		modes.find(Settings.get_value("display", "window_mode", "windowed")),
		func(i: int) -> void: Settings.set_value("display", "window_mode", modes[i]))
	var res_names := []
	for r in Settings.RESOLUTIONS:
		res_names.append("%d x %d" % [r.x, r.y])
	_option("Resolution", "Window size when the game is windowed.", res_names, int(Settings.get_value("display", "resolution", 2)),
		func(i: int) -> void: Settings.set_value("display", "resolution", i), "window size")
	_check("V-Sync", "Removes screen tearing; can add a little input delay.", bool(Settings.get_value("display", "vsync", true)),
		func(v: bool) -> void: Settings.set_value("display", "vsync", v), "vertical sync tearing")
	var caps := [0, 30, 60, 120, 144, 240]
	_option("Frame rate cap", "Limits frames per second to save power and heat.", ["Unlimited", "30", "60", "120", "144", "240"],
		caps.find(int(Settings.get_value("display", "max_fps", 0))),
		func(i: int) -> void: Settings.set_value("display", "max_fps", caps[i]), "fps limit")
	_slider("UI scale", "Makes every menu and the battle HUD bigger or smaller.", float(Settings.get_value("display", "ui_scale", 1.0)), 0.75, 1.5, 0.05,
		func(v: float) -> void: Settings.set_value("display", "ui_scale", v), "%d%%", 100.0, "interface size text")


func _build_graphics() -> void:
	var s := _section("graphics", "Graphics", "camera", "Particles, crowd, ambient occlusion and fog apply from the next match.")
	# Benchmark card.
	var bench := UITheme.tile_panel(Color(UITheme.GOLD, 0.45), 14, true)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 16)
	bench.add_child(bh)
	bh.add_child(UITheme.icon_rect("speed", 46, UITheme.GOLD))
	var bv := VBoxContainer.new()
	bv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bv.add_theme_constant_override("separation", 0)
	bv.add_child(UITheme.label("Not sure what to pick?", UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_body_bold()))
	var bt := UITheme.label("The benchmark plays a short stadium scene at each quality preset (about 12 seconds) and recommends the best one that keeps the game smooth on this PC.", UITheme.FS_MIN, UITheme.OFFWHITE, UITheme.font_small())
	bt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bv.add_child(bt)
	bh.add_child(bv)
	var run := UITheme.button("RUN BENCHMARK", "primary", 24, "play", UITheme.GOLD.darkened(0.25))
	run.custom_minimum_size = Vector2(250, 56)
	run.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if overlay:
		run.disabled = true
		run.tooltip_text = "Run the benchmark from Settings in the main menu."
	run.pressed.connect(_run_benchmark)
	bh.add_child(run)
	s.add_child(bench)
	_option("Quality preset", "Sets every option below. Low is for integrated graphics, Ultra for high-end cards.", Settings.QUALITY_NAMES,
		int(Settings.get_value("graphics", "preset", 2)), func(i: int) -> void:
		Settings.apply_preset(i)
		_rebuild(), "low medium high ultra benchmark performance")
	_option("Shadows", "Shadow sharpness and distance.", ["Off", "Low", "Medium", "High"], int(Settings.get_value("graphics", "shadows", 2)),
		func(i: int) -> void: Settings.set_value("graphics", "shadows", i))
	_option("Anti-aliasing (MSAA)", "Smooths jagged edges on 3D models.", ["Off", "2x", "4x", "8x"], int(Settings.get_value("graphics", "msaa", 2)),
		func(i: int) -> void: Settings.set_value("graphics", "msaa", i), "aa jaggies")
	_check("FXAA", "A cheap edge-smoothing filter; slightly blurs the image.", bool(Settings.get_value("graphics", "fxaa", false)),
		func(v: bool) -> void: Settings.set_value("graphics", "fxaa", v), "anti-aliasing aa")
	_check("Ambient occlusion (SSAO)", "Soft contact shadows in corners and under players.", bool(Settings.get_value("graphics", "ssao", true)),
		func(v: bool) -> void: Settings.set_value("graphics", "ssao", v))
	_check("Bloom / glow", "Bright lights and effects glow softly.", bool(Settings.get_value("graphics", "glow", true)),
		func(v: bool) -> void: Settings.set_value("graphics", "glow", v))
	_check("Volumetric fog", "Light shafts and haze in the stadium air.", bool(Settings.get_value("graphics", "fog", true)),
		func(v: bool) -> void: Settings.set_value("graphics", "fog", v))
	_slider("Particle amount", "Sparks, dust, confetti and card effects.", float(Settings.get_value("graphics", "particles", 1.0)), 0.1, 1.0, 0.05,
		func(v: float) -> void: Settings.set_value("graphics", "particles", v), "%d%%", 100.0, "effects vfx")
	_slider("Crowd density", "How full the stands are.", float(Settings.get_value("graphics", "crowd", 1.0)), 0.0, 1.0, 0.05,
		func(v: float) -> void: Settings.set_value("graphics", "crowd", v), "%d%%", 100.0, "fans stands")
	_slider("3D render scale", "Renders 3D below full resolution and upscales it (FSR) for more speed.", float(Settings.get_value("graphics", "render_scale", 1.0)), 0.5, 1.0, 0.05,
		func(v: float) -> void: Settings.set_value("graphics", "render_scale", v), "%d%%", 100.0, "fsr resolution upscaling performance")
	_check("Show FPS counter", "Frames per second and frame time in the bottom-left corner.", bool(Settings.get_value("graphics", "show_fps", false)),
		func(v: bool) -> void: Settings.set_value("graphics", "show_fps", v), "performance frame rate")


func _rebuild() -> void:
	# Rebuilds every page in place (after a preset or benchmark changed many values).
	var q := _search.text
	for c in _pages.get_children():
		_pages.remove_child(c)
		c.queue_free()
	_sections.clear()
	_rows.clear()
	_bind_buttons.clear()
	_build_display()
	_build_graphics()
	_build_audio()
	_build_gameplay()
	_build_access()
	_build_controls()
	_empty = UITheme.label("No settings match your search.", UITheme.FS_LEAD, UITheme.MUTED)
	_pages.add_child(_empty)
	_search.text = q
	_apply_filter()


func _build_audio() -> void:
	_section("audio", "Audio", "volume")
	var rows := [["master", "Master volume", "Everything at once."], ["music", "Music", "Menu and stadium music."],
		["sfx", "Effects", "Throws, hits, cards and runners."], ["ambience", "Ambience & crowd", "Crowd noise and stadium atmosphere."],
		["ui", "Interface", "Menu clicks and hovers."]]
	for k in rows:
		var key: String = k[0]
		_slider(k[1], k[2], float(Settings.get_value("audio", key, 0.8)), 0.0, 1.0, 0.05, func(v: float) -> void:
			Settings.set_value("audio", key, v)
			if key in ["sfx", "master"]:
				Audio.play("ball_hit", -6.0, 0.0, 150)
			elif key == "ui":
				Audio.ui("ui_click", -4.0), "%d%%", 100.0, "sound volume")


func _build_gameplay() -> void:
	_section("gameplay", "Gameplay", "control")
	_check("Auto-start next wave", "Starts the next wave after a short break. When off, press Space for every wave.",
		bool(Settings.get_value("gameplay", "auto_start_waves", true)),
		func(v: bool) -> void: Settings.set_value("gameplay", "auto_start_waves", v), "break timer")
	_check("Damage numbers", "Shows big hits and critical hits as numbers on the field.", bool(Settings.get_value("gameplay", "damage_numbers", true)),
		func(v: bool) -> void: Settings.set_value("gameplay", "damage_numbers", v))
	_slider("Screen shake", "Camera shake on big hits, runs and bosses.", float(Settings.get_value("gameplay", "screen_shake", 1.0)), 0.0, 1.5, 0.05,
		func(v: float) -> void: Settings.set_value("gameplay", "screen_shake", v), "%d%%", 100.0, "camera")
	_slider("Camera pan speed", "How fast WASD and the arrow keys move the camera.", float(Settings.get_value("gameplay", "camera_speed", 1.0)), 0.4, 2.0, 0.05,
		func(v: float) -> void: Settings.set_value("gameplay", "camera_speed", v), "%d%%", 100.0, "scroll")
	_check("Edge panning", "Moves the camera when the mouse touches the screen edge.", bool(Settings.get_value("gameplay", "edge_pan", false)),
		func(v: bool) -> void: Settings.set_value("gameplay", "edge_pan", v), "mouse camera scroll")
	var reset := UITheme.button("Reset profile...", "danger", 20, "exit")
	reset.custom_minimum_size = Vector2(320, 46)
	reset.pressed.connect(func() -> void:
		var dlg := ConfirmationDialog.new()
		dlg.dialog_text = "Erase ALL progress (levels, cards, unlocks, records)? This cannot be undone."
		dlg.process_mode = Node.PROCESS_MODE_ALWAYS
		dlg.confirmed.connect(func() -> void:
			Profile.reset_profile()
			Router.toast("Profile reset.", "warn"))
		add_child(dlg)
		dlg.popup_centered(Vector2i(560, 180)))
	_row("Reset profile", "Erases all progress and starts over. Cannot be undone.", reset, "danger delete erase save")


func _build_access() -> void:
	_section("access", "Accessibility", "info")
	_check("Larger text", "Scales all text and menus up by 15%.", bool(Settings.get_value("accessibility", "large_text", false)), func(v: bool) -> void:
		Settings.set_value("accessibility", "large_text", v, false)
		Settings.apply_display(), "font size readability")
	_check("Reduce flashing effects", "Tones down screen flashes and bright bursts.", bool(Settings.get_value("accessibility", "reduce_flashes", false)),
		func(v: bool) -> void: Settings.set_value("accessibility", "reduce_flashes", v), "photosensitive epilepsy")
	_check("Color-blind friendly markers", "Runner rings switch from red to a high-contrast yellow/blue scheme.", bool(Settings.get_value("accessibility", "colorblind", false)),
		func(v: bool) -> void: Settings.set_value("accessibility", "colorblind", v), "colour colorblind deuteranopia")
	_check("High-contrast HUD", "Darker panels and brighter text in battle.", bool(Settings.get_value("accessibility", "high_contrast", false)),
		func(v: bool) -> void: Settings.set_value("accessibility", "high_contrast", v), "readability")


func _build_controls() -> void:
	_section("controls", "Controls", "keyboard", "Click a key, then press the new key. Esc cancels. Mouse: left = select / drag / cast · right = cancel · wheel = zoom.")
	for action in InputConfig.REBINDABLE:
		var b := UITheme.button(InputConfig.binding_text(action), "secondary", 22, "", UITheme.BLUE)
		b.custom_minimum_size = Vector2(240, 46)
		b.pressed.connect(func() -> void:
			_waiting_action = action
			b.text = "Press a key..."
			Audio.ui("ui_click"))
		_row(InputConfig.display_name(action), "", b, "key binding hotkey keyboard " + action.replace("_", " "))
		_bind_buttons[action] = b
	var reset := UITheme.button("Reset to defaults", "danger", 20)
	reset.custom_minimum_size = Vector2(240, 46)
	reset.pressed.connect(func() -> void:
		InputConfig.reset_defaults()
		_refresh_bindings())
	_row("Reset key bindings", "Restores every key to its default.", reset, "keyboard controls")


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


# ---------------------------------------------------------------- benchmark

func _run_benchmark() -> void:
	Audio.ui("ui_confirm")
	var bm := GraphicsBenchmark.new()
	var screen := get_parent()
	while screen and not (screen is MenuScreen) and screen.get_parent() != get_tree().root:
		screen = screen.get_parent()
	if screen is CanvasItem:
		(screen as CanvasItem).visible = false
	get_tree().root.add_child(bm)
	var result: Dictionary = await bm.finished
	if screen is CanvasItem and is_instance_valid(screen):
		(screen as CanvasItem).visible = true
	_show_benchmark_result(result)


func _show_benchmark_result(r: Dictionary) -> void:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.6), 26, Color(0.05, 0.08, 0.14, 0.98), 2)
	p.custom_minimum_size = Vector2(640, 0)
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("BENCHMARK RESULT", "speed", UITheme.GOLD, 34))
	var rec := int(r.get("recommended", 0))
	var names: Array = Settings.QUALITY_NAMES
	for i in names.size():
		var res: Dictionary = r.get("presets", {}).get(i, {})
		if res.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nl := UITheme.label(str(names[i]).to_upper(), UITheme.FS_LEAD, UITheme.GOLD if i == rec else UITheme.OFFWHITE, UITheme.font_header())
		nl.custom_minimum_size = Vector2(120, 0)
		row.add_child(nl)
		var fps := float(res.get("fps", 0.0))
		var b := UITheme.bar(UITheme.GREEN if fps >= 58.0 else (UITheme.GOLD if fps >= 40.0 else UITheme.SCARLET), 14, 120.0, minf(fps, 120.0))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(b)
		var vl := UITheme.label("%d fps · %.1f ms" % [int(round(fps)), float(res.get("ms", 0.0))], UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
		vl.custom_minimum_size = Vector2(150, 0)
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(vl)
		vb.add_child(row)
	var msg := UITheme.label(str(r.get("message", "")), UITheme.FS_BODY, UITheme.OFFWHITE)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(msg)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_END
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var keep := UITheme.button("Keep current", "ghost", 22)
	keep.pressed.connect(func() -> void:
		Audio.ui("ui_back")
		layer.queue_free())
	hb.add_child(keep)
	var apply := UITheme.button("APPLY %s" % str(names[rec]).to_upper(), "primary", 26, "check")
	apply.pressed.connect(func() -> void:
		Settings.apply_preset(rec)
		Settings.save_settings()
		Audio.ui("ui_confirm")
		Router.toast("Graphics set to %s." % names[rec], "level")
		layer.queue_free()
		_rebuild())
	hb.add_child(apply)
	UITheme.animate_in(p)
