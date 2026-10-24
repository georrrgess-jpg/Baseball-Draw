extends Control
## Startup: shows a brief splash while autoloads settle, then opens the main menu.
## Command-line flags (after `--`) support automated testing:
##   --test-battle=<mode>   jump straight into a battle
##   --auto                 let the battle play itself (auto-start waves, autoplay cards)

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = UITheme.NAVY_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var args := OS.get_cmdline_user_args()
	var shots := ""
	var shot_times: Array[float] = []
	for a in args:
		if a.begins_with("--shots="):
			shots = a.split("=")[1]
		elif a.begins_with("--shot-times="):
			for t in a.split("=")[1].split(","):
				shot_times.append(float(t))
	if shots != "":
		var s := Screenshotter.new()
		s.out_dir = shots
		s.times = shot_times
		get_tree().root.add_child.call_deferred(s)
	if "--perf-test" in args:
		var pt: Node = load("res://tests/perf_test.gd").new()
		get_tree().root.add_child.call_deferred(pt)
		return
	if "--ui-test" in args:
		var t: Node = load("res://tests/ui_flow_test.gd").new()
		get_tree().root.add_child.call_deferred(t)
		return
	for a in args:
		if a.begins_with("--test-battle="):
			var cfg := Session.new_run_config(a.split("=")[1])
			cfg.auto_test = "--auto" in args
			for b in args:
				if b.begins_with("--arena="):
					cfg.arena = b.split("=")[1]
				if b.begins_with("--difficulty="):
					cfg.difficulty = b.split("=")[1]
				if b.begins_with("--start-inning="):
					cfg.start_inning = int(b.split("=")[1])
				if b.begins_with("--start-wave="):
					cfg.start_wave = int(b.split("=")[1])
			Session.start(cfg)
			return
		if a.begins_with("--scene="):
			await get_tree().process_frame
			Router.goto(a.split("=")[1])
			return
	if Profile.load_status == "restored_backup":
		Router.toast("Your save was damaged and has been restored from a backup.", "warn", 6.0)
	elif Profile.load_status == "reset_corrupt":
		Router.toast("Your save could not be read and a new profile was created. The old file was kept as profile.corrupt.json.", "warn", 8.0)
	await _splash()
	Router.goto("main_menu")


## Animated logo splash (click or any key skips).
func _splash() -> void:
	var path := "res://assets/textures/logo/logo_tagline.png"
	if not ResourceLoader.exists(path):
		return
	var logo := TextureRect.new()
	logo.texture = load(path)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	logo.offset_left = 360
	logo.offset_right = -360
	logo.offset_top = 200
	logo.offset_bottom = -200
	logo.pivot_offset = Vector2(600, 340)
	logo.modulate.a = 0.0
	logo.scale = Vector2(0.92, 0.92)
	add_child(logo)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(logo, "modulate:a", 1.0, 0.5)
	tw.tween_property(logo, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	Audio.play("bat_crack", -6.0, 0.0)
	var t := 0.0
	while t < 1.7 and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()


var _skip := false


func _input(event: InputEvent) -> void:
	if (event is InputEventMouseButton or event is InputEventKey) and event.is_pressed():
		_skip = true
