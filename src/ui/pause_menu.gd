extends Control
## In-battle pause overlay: resume, settings, controls reference, abandon/quit.

signal closed

var battle: Battle
var _settings: Control
var _vb: VBoxContainer
var _controls: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := UITheme.card_panel(Color(UITheme.SCARLET, 0.7), 30, Color(0.05, 0.08, 0.14, 0.97), 2)
	panel.custom_minimum_size = Vector2(540, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	_vb = vb
	var t := UITheme.title("TIME OUT", 72)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var run: RunState = battle.run
	var info := UITheme.label("%s  ·  %s" % [DB.mode(run.mode_id).name, DB.difficulty(run.difficulty_id).name], UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold())
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)
	# Where the game stands, in the same stat-tile style as the menus.
	if not battle.practice:
		var stats := HBoxContainer.new()
		stats.add_theme_constant_override("separation", 8)
		vb.add_child(stats)
		var inn := "%d / %d" % [run.inning, run.max_innings] if run.max_innings > 0 else str(run.inning)
		for st in [["inning", inn, "Inning"], ["runs", "%d / %d" % [run.runs, run.run_limit], "Runs allowed"], ["star", UITheme.format_int(run.score), "Score"]]:
			var tile := UITheme.stat_tile(st[0], st[1], st[2], UITheme.OFFWHITE, 0)
			tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stats.add_child(tile)
	vb.add_child(UITheme.hsep(0.08))
	var resume := _btn("RESUME", "primary", "play", UITheme.GREEN.darkened(0.2))
	resume.pressed.connect(_close)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var settings := _btn("SETTINGS", "secondary", "settings", UITheme.BLUE, row)
	settings.pressed.connect(_open_settings)
	var controls := _btn("CONTROLS", "secondary", "keyboard", UITheme.BLUE, row)
	controls.pressed.connect(_show_controls)
	var howto := _btn("HOW TO PLAY", "secondary", "info", UITheme.BLUE)
	howto.pressed.connect(func() -> void:
		_close()
		battle.hud.show_help())
	vb.add_child(UITheme.hsep(0.08))
	if battle.practice:
		var leave := _btn("LEAVE PRACTICE", "danger", "exit", UITheme.SCARLET)
		leave.pressed.connect(func() -> void:
			get_tree().paused = false
			Router.goto("main_menu"))
	else:
		var daily := battle.run.is_daily()   # Daily Challenge games are never saved mid-game
		var save_quit := _btn("QUIT TO MENU" if daily else "SAVE & QUIT", "secondary", "exit" if daily else "save", UITheme.GOLD)
		save_quit.tooltip_text = "Daily games are not saved: quitting drops this attempt (no score)." if daily else "Your run is saved at the start of each inning. Continue it from the main menu."
		save_quit.pressed.connect(func() -> void:
			get_tree().paused = false
			Router.goto("main_menu"))
		var abandon := _btn("FORFEIT RUN", "danger", "exit", UITheme.SCARLET)
		abandon.tooltip_text = "Ends the game now as a loss. You still get rewards for the innings you cleared."
		abandon.pressed.connect(func() -> void:
			_close()
			battle.abandon())
		var note := UITheme.label("Daily games can't be continued later. Forfeit to record your score." if daily else "Save & Quit resumes from the start of this inning.", UITheme.FS_MIN, UITheme.MUTED)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(note)
	UITheme.animate_in(panel, 0.0, 0.95)
	Audio.ui("ui_slide")


func _close() -> void:
	Audio.ui("ui_back")
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings and is_instance_valid(_settings):
			_settings.queue_free()
			_settings = null
		elif _controls and is_instance_valid(_controls):
			_controls.queue_free()
			_controls = null
		else:
			_close()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	var script: Script = load("res://src/ui/settings_panel.gd")
	_settings = script.new()
	_settings.overlay = true
	add_child(_settings)


## Adds a full-width menu button to `parent` (the panel column by default).
func _btn(text: String, variant: String, icon: String, accent: Color, parent: Control = null) -> Button:
	var b := UITheme.button(text, variant, 30, icon, accent)
	b.custom_minimum_size = Vector2(0, UITheme.BTN_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if parent == null:
		parent = _vb
	parent.add_child(b)
	return b


func _show_controls() -> void:
	if _controls and is_instance_valid(_controls):
		return
	_controls = Control.new()
	_controls.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_controls)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls.add_child(cc)
	var p := UITheme.card_panel(Color(UITheme.BLUE, 0.6), 24, Color(0.05, 0.08, 0.14, 0.98), 2)
	p.custom_minimum_size = Vector2(640, 0)
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("CONTROLS", "keyboard", UITheme.GOLD, 34))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(grid)
	var rows: Array = []
	for a in ["pan_up", "pan_left", "pan_down", "pan_right", "card_1", "card_prev", "card_next", "start_wave", "fast_forward",
			"rotate", "cycle_defender", "info", "tactical_map", "center_camera", "confirm", "pause"]:
		rows.append([InputConfig.display_name(a), InputConfig.binding_text(a)])
	rows.append_array([["Zoom", "Mouse wheel"], ["Select / drag / cast", "Left click"], ["Cancel", "Right click"]])
	for r in rows:
		var k := UITheme.label(str(r[0]), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(k)
		grid.add_child(UITheme.label(str(r[1]), UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold()))
	var tip := UITheme.label("Rebind keys in Settings → Controls.", UITheme.FS_MIN, UITheme.MUTED)
	vb.add_child(tip)
	var close := UITheme.button("Close", "secondary", 24, "back")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void:
		Audio.ui("ui_back")
		_controls.queue_free()
		_controls = null)
	vb.add_child(close)
	UITheme.animate_in(p, 0.0, 0.96)
