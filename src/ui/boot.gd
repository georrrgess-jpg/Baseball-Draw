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
	await get_tree().process_frame
	Router.goto("main_menu")
