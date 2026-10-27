class_name GraphicsBenchmark
extends Node3D
## Settings → Graphics → Run Benchmark. Builds the Steel Yard with the team playing catch
## and an orbiting camera, then plays it at each quality preset (warm-up, then measured frames)
## and recommends the highest preset that holds about 60 fps. The player's settings are
## restored afterwards; the result dialog offers to apply the recommendation.

signal finished(result: Dictionary)

const WARMUP := 0.6
const MEASURE := 2.4
const TARGET_MS := 1000.0 / 58.0

var _t := 0.0
var _camera: Camera3D
var _models: Array[CharacterModel] = []
var _stadium: StadiumBuilder
var _label: Label
var _bar: ProgressBar


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var arena := DB.arena("steel_yard")
	var layout := DB.layout_for_arena(arena.id)
	_stadium = StadiumBuilder.new()
	_stadium.build(self, arena, layout, false)
	var routes: Array = []
	for r in layout.get("routes", []):
		routes.append(Route.from_points(r.id, r.gate, r.points))
	FieldBuilder.build(self, arena.get("theme", {}), routes)
	_stadium.set_excitement(0.8)
	_camera = Camera3D.new()
	_camera.fov = 50.0
	_camera.far = 600.0
	add_child(_camera)
	_camera.make_current()
	var colors: Dictionary = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.home).colors
	var spots := [Vector3(0, 0, 0), Vector3(8, 0, -8), Vector3(-8, 0, -8), Vector3(0, 0, -16), Vector3(-14, 0, -20), Vector3(14, 0, -20)]
	var team: Array = Profile.data.team
	for i in mini(team.size(), spots.size()):
		var cm := CharacterModel.new()
		add_child(cm)
		var id: String = team[i]
		cm.setup(id, {"accent": DB.defender_accent(id), "colors": colors, "cache_key": id, "base": "ready"})
		cm.position = Field.HOME + spots[i] + Vector3(0, 0, -4)
		_models.append(cm)
	_build_overlay()
	_run()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.5), 16, Color(0.03, 0.05, 0.09, 0.9))
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.offset_left = -330
	p.offset_right = 330
	p.offset_top = 40
	layer.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("GRAPHICS BENCHMARK", "speed", UITheme.GOLD, 30))
	_label = UITheme.label("Preparing...", UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	vb.add_child(_label)
	_bar = UITheme.bar(UITheme.GOLD, 12, 1.0, 0.0)
	vb.add_child(_bar)


func _process(delta: float) -> void:
	_t += delta
	var a := _t * 0.35
	_camera.position = Field.MOUND + Vector3(sin(a) * 34.0, 13.0 + sin(_t * 0.5) * 2.0, cos(a) * 34.0)
	_camera.look_at(Field.MOUND + Vector3(0, 1.0, 0), Vector3.UP)
	if int(_t * 1.3) % 2 == 0 and _models.size() > 0:
		var m: CharacterModel = _models[randi() % _models.size()]
		if m.action == "":
			m.play_action(["throw", "catch", "special"][randi() % 3], 1.0)


func _run() -> void:
	var saved: Dictionary = Settings.data.graphics.duplicate(true)
	var saved_vsync := DisplayServer.window_get_vsync_mode()
	var saved_fps := Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().process_frame
	await get_tree().process_frame
	var results := {}
	var names: Array = Settings.QUALITY_NAMES
	for i in names.size():
		Settings.apply_preset(i)
		Settings.configure_environment(_stadium.env)
		Settings.configure_sun(_stadium.sun)
		_label.text = "Testing %s quality  (%d of %d)" % [names[i], i + 1, names.size()]
		var t0 := Time.get_ticks_usec()
		while (Time.get_ticks_usec() - t0) / 1e6 < WARMUP:
			await get_tree().process_frame
		var frames := 0
		var worst := 0.0
		var last := Time.get_ticks_usec()
		t0 = last
		while (Time.get_ticks_usec() - t0) / 1e6 < MEASURE:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxf(worst, (now - last) / 1000.0)
			last = now
			frames += 1
			_bar.value = (i + (now - t0) / 1e6 / MEASURE) / float(names.size())
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(frames, 1)
		results[i] = {"ms": ms, "fps": 1000.0 / maxf(ms, 0.01), "worst": worst}
	# Recommend the highest preset that averages ~60 fps; fall back to the fastest.
	var rec := 0
	for i in names.size():
		if float(results[i].ms) <= TARGET_MS:
			rec = i
	var msg := ""
	if float(results[rec].ms) <= TARGET_MS:
		msg = "%s keeps the game above 60 fps on this PC. Lower presets leave headroom for big moments." % names[rec]
	else:
		msg = "Even Low stays under 60 fps here (%.1f fps). Low plus a lower 3D render scale is the smoothest option." % float(results[0].fps)
	# Restore the player's settings before handing back.
	for k in saved.keys():
		Settings.data.graphics[k] = saved[k]
	Settings.apply_graphics()
	DisplayServer.window_set_vsync_mode(saved_vsync)
	Engine.max_fps = saved_fps
	finished.emit({"presets": results, "recommended": rec, "message": msg})
	queue_free()
