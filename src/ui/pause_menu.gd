extends Control
## In-battle pause overlay: resume, settings, controls reference, abandon/quit.

signal closed

var battle: Battle
var _settings: Control


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
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.08, 0.14, 0.97), Color(UITheme.SCARLET, 0.7), 2, 14, 30))
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	var t := UITheme.title("TIME OUT", 72)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var run: RunState = battle.run
	var info := UITheme.label("%s · %s · Inning %d" % [DB.mode(run.mode_id).name, DB.difficulty(run.difficulty_id).name, run.inning], 22, UITheme.MUTED)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(info)
	var resume := UITheme.menu_button("RESUME", UITheme.GREEN)
	resume.pressed.connect(_close)
	vb.add_child(resume)
	var settings := UITheme.menu_button("SETTINGS", UITheme.BLUE)
	settings.pressed.connect(_open_settings)
	vb.add_child(settings)
	var controls := UITheme.menu_button("CONTROLS", UITheme.BLUE)
	controls.pressed.connect(_show_controls)
	vb.add_child(controls)
	if battle.practice:
		var leave := UITheme.menu_button("LEAVE PRACTICE", UITheme.SCARLET)
		leave.pressed.connect(func() -> void:
			get_tree().paused = false
			Router.goto("main_menu"))
		vb.add_child(leave)
	else:
		var save_quit := UITheme.menu_button("SAVE & QUIT", UITheme.GOLD)
		save_quit.tooltip_text = "Your run is saved at the start of each inning. Continue it from the main menu."
		save_quit.pressed.connect(func() -> void:
			get_tree().paused = false
			Router.goto("main_menu"))
		vb.add_child(save_quit)
		var abandon := UITheme.menu_button("FORFEIT RUN", UITheme.SCARLET)
		abandon.pressed.connect(func() -> void:
			_close()
			battle.abandon())
		vb.add_child(abandon)
		var note := UITheme.label("Save & Quit resumes from the start of this inning.", 17, UITheme.MUTED)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(note)
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
		else:
			_close()
		get_viewport().set_input_as_handled()


func _open_settings() -> void:
	var script: Script = load("res://src/ui/settings_panel.gd")
	_settings = script.new()
	_settings.overlay = true
	add_child(_settings)


func _show_controls() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Controls"
	var text := ""
	for a in ["pan_up", "pan_left", "pan_down", "pan_right", "card_1", "card_prev", "card_next", "start_wave", "fast_forward",
			"rotate", "cycle_defender", "info", "tactical_map", "center_camera", "confirm", "pause"]:
		text += "%-28s %s\n" % [InputConfig.display_name(a), InputConfig.binding_text(a)]
	text += "%-28s %s\n" % ["Zoom", "Mouse wheel"]
	text += "%-28s %s\n" % ["Select / drag / cast", "Left click"]
	text += "%-28s %s\n" % ["Cancel", "Right click"]
	dlg.dialog_text = text
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dlg)
	dlg.popup_centered(Vector2i(560, 640))
