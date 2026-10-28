extends Node
## Scene transitions (fade + threaded loading), the global UI theme and toast notifications.

signal scene_changed(name: String)

const SCENES := {
	"boot": "res://scenes/boot.tscn",
	"main_menu": "res://scenes/main_menu.tscn",
	"battle": "res://scenes/battle.tscn",
	"deck_builder": "res://scenes/deck_builder.tscn",
	"roster": "res://scenes/roster.tscn",
	"progression": "res://scenes/progression.tscn",
	"settings": "res://scenes/settings.tscn",
	"play_menu": "res://scenes/play_menu.tscn",
	"packs": "res://scenes/packs.tscn",
	"card_upgrades": "res://scenes/card_upgrades.tscn",
}

var current := ""
var busy := false
## Screens that opened the current one through a cross-link (e.g. Upgrade Cards -> Card Packs):
## BACK returns along this path. Going to the main menu or a battle clears it.
var _back_stack: Array[String] = []
var _layer: CanvasLayer
var _fade: ColorRect
var _loading_label: Label
var _loading_bar: ProgressBar
var _toast_box: VBoxContainer
var _loading_bg: TextureRect
var _fps: Label
var _fps_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.theme = UITheme.build()
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_fade = ColorRect.new()
	_fade.color = Color(0.03, 0.05, 0.09, 1.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	_layer.add_child(_fade)

	_loading_bg = TextureRect.new()
	_loading_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_loading_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_loading_bg.modulate = Color(1, 1, 1, 0.55)
	_loading_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.add_child(_loading_bg)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	box.position = Vector2(-300, -170)
	box.custom_minimum_size = Vector2(600, 80)
	box.add_theme_constant_override("separation", 10)
	# The fade layer sits above every screen: nothing on it may ever take mouse input
	# (this box used to block clicks on the bottom-centre of every screen, e.g. the card hand).
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.add_child(box)
	_loading_label = Label.new()
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_override("font", UITheme.font_display())
	_loading_label.add_theme_font_size_override("font_size", 34)
	box.add_child(_loading_label)
	_loading_bar = ProgressBar.new()
	_loading_bar.show_percentage = false
	_loading_bar.custom_minimum_size = Vector2(600, 10)
	_loading_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_loading_bar)
	_set_loading_visible(false)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toast_box.position = Vector2(-440, 90)
	_toast_box.custom_minimum_size = Vector2(420, 0)
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.add_theme_constant_override("separation", 8)
	_layer.add_child(_toast_box)

	_fps = Label.new()
	_fps.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_fps.position = Vector2(8, -30)
	_fps.add_theme_font_size_override("font_size", 18)
	_fps.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps.add_theme_constant_override("outline_size", 4)
	_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_fps)
	Profile.achievement_unlocked.connect(_on_achievement)
	Profile.notice.connect(func(t: String) -> void: toast(t, "info"))
	Profile.level_up.connect(func(l: int) -> void:
		toast("Account level %d!  +100 coins" % l, "level")
		Audio.play("level_up"))


func _process(delta: float) -> void:
	_fps_t -= delta
	if _fps_t > 0.0:
		return
	_fps_t = 0.25
	var show := bool(Settings.get_value("graphics", "show_fps", false))
	_fps.visible = show
	if show:
		_fps.text = "%d FPS  %.1f ms" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)]


func _set_loading_visible(v: bool) -> void:
	_loading_label.visible = v
	_loading_bar.visible = v
	_loading_bg.visible = v


## Changes screen with a fade. `tab` selects a tab of the new screen by name (the name of a
## TabContainer page, e.g. "Pro Shop" on Progression).
func goto(scene_name: String, show_loading := false, tab := "") -> void:
	if busy or not SCENES.has(scene_name):
		return
	if scene_name in ["main_menu", "battle", "boot"]:
		_back_stack.clear()
	busy = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	var path: String = SCENES[scene_name]
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	Audio.ui("ui_slide", -10.0)
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	if show_loading or scene_name == "battle":
		var tex_path := "res://assets/textures/ui/loading_bg.png"
		_loading_bg.texture = load(tex_path) if ResourceLoader.exists(tex_path) else null
		_loading_label.text = _loading_tip()
		_loading_bar.value = 0
		_set_loading_visible(true)
	ResourceLoader.load_threaded_request(path)
	var progress := []
	while true:
		var status := ResourceLoader.load_threaded_get_status(path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			break
		if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			push_error("Router: failed to load %s" % path)
			busy = false
			return
		if progress.size() > 0:
			_loading_bar.value = float(progress[0]) * 100.0
		await get_tree().process_frame
	var packed: PackedScene = ResourceLoader.load_threaded_get(path)
	get_tree().change_scene_to_packed(packed)
	current = scene_name
	await get_tree().process_frame
	if tab != "":
		_select_tab(get_tree().current_scene, tab)
	await get_tree().process_frame
	_set_loading_visible(false)
	var tw2 := create_tween()
	tw2.tween_property(_fade, "modulate:a", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await tw2.finished
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	busy = false
	scene_changed.emit(scene_name)


## Opens a screen from another menu screen, so that its BACK (and Esc) returns to this one.
func open(scene_name: String, tab := "") -> void:
	if busy or not SCENES.has(scene_name):
		return
	if current != "" and current != scene_name and not current in ["main_menu", "battle", "boot"]:
		_back_stack.erase(scene_name)
		_back_stack.append(current)
	goto(scene_name, false, tab)


## Where BACK leads from the current screen: the screen that opened it, else the main menu.
func back_target() -> String:
	return _back_stack.back() if not _back_stack.is_empty() else "main_menu"


## Goes back one screen (to the screen that opened this one, or the main menu).
func back() -> void:
	if busy:
		return
	var target := "main_menu"
	while not _back_stack.is_empty():
		var t: String = _back_stack.pop_back()
		if t != current and SCENES.has(t):
			target = t
			break
	goto(target)


func _select_tab(n: Node, tab: String) -> bool:
	if n == null:
		return false
	if n is TabContainer:
		for i in n.get_tab_count():
			if n.get_tab_control(i).name == tab:
				(n as TabContainer).current_tab = i
				return true
	for c in n.get_children():
		if _select_tab(c, tab):
			return true
	return false


func _loading_tip() -> String:
	var tips := [
		"Curveball marks runners: Heat Wave burns them for +50%.",
		"Defenders in their home zone get a position bonus. Check the placement ring!",
		"Frost Field turns slowed runners into critical-hit targets.",
		"Jax's Cannon Arm cuts through armored runners.",
		"Base Shields turn a scoring runner into an out at the plate.",
		"Two outs in quick succession is a Double Play: bonus coins and energy.",
		"Press Space between waves to call the next wave early for bonus coins.",
		"Magnet Glove + Grand Slam Barrage is a legendary combination.",
		"Tricksters dodge sloppy throws. Field Vision or an accurate arm fixes that.",
		"Your captain boosts nearby teammates. Captain's Rally makes the aura stronger.",
	]
	return tips[randi() % tips.size()]


## Moves the toast stack down (the battle HUD keeps its threat panel in the top-right corner).
func set_toast_top(y: float) -> void:
	_toast_box.position.y = y


func toast(text: String, kind := "info", duration := 3.2) -> void:
	var panel := PanelContainer.new()
	var accent := {"info": UITheme.BLUE, "achievement": UITheme.GOLD, "level": UITheme.GREEN, "warn": UITheme.SCARLET}.get(kind, UITheme.BLUE)
	panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.95), accent, 2, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	panel.add_child(hb)
	var icon_name: String = {"achievement": "trophy", "level": "upgrade", "warn": "info"}.get(kind, "info")
	var tex := DB.icon(icon_name)
	if tex:
		var ic := TextureRect.new()
		ic.texture = tex
		ic.custom_minimum_size = Vector2(36, 36)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = accent
		hb.add_child(ic)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(340, 0)
	l.add_theme_font_size_override("font_size", 20)
	hb.add_child(l)
	_toast_box.add_child(panel)
	panel.modulate.a = 0.0
	panel.position.x += 60
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


func _on_achievement(id: String) -> void:
	var a: Dictionary = DB.achievements.get(id, {})
	toast("Achievement unlocked: %s  (+%d stars)" % [a.get("name", id), int(a.get("stars", 0))], "achievement", 4.0)
	Audio.play("achievement")
