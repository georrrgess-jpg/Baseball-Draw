extends Node
## Player preferences (display, graphics, audio, gameplay, accessibility).
## Stored in user://settings.cfg, separate from the profile save.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160)]
const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra"]

## Per-preset graphics values: shadows, ssao, glow, aa(msaa level), particles, crowd, volumetric fog, render scale
const PRESETS := {
	0: {"shadows": 0, "ssao": false, "glow": true, "msaa": 0, "fxaa": true, "particles": 0.35, "crowd": 0.35, "fog": false, "render_scale": 0.8, "ssil": false, "lod_bias": 0.6},
	1: {"shadows": 1, "ssao": false, "glow": true, "msaa": 1, "fxaa": false, "particles": 0.65, "crowd": 0.6, "fog": false, "render_scale": 1.0, "ssil": false, "lod_bias": 1.0},
	2: {"shadows": 2, "ssao": true, "glow": true, "msaa": 2, "fxaa": false, "particles": 1.0, "crowd": 1.0, "fog": true, "render_scale": 1.0, "ssil": false, "lod_bias": 1.0},
	3: {"shadows": 3, "ssao": true, "glow": true, "msaa": 3, "fxaa": false, "particles": 1.0, "crowd": 1.0, "fog": true, "render_scale": 1.0, "ssil": true, "lod_bias": 1.5},
}

var data := {
	"display": {"window_mode": "windowed", "resolution": 2, "vsync": true, "max_fps": 0, "ui_scale": 1.0},
	"graphics": {"preset": 2, "shadows": 2, "ssao": true, "glow": true, "msaa": 2, "fxaa": false, "particles": 1.0,
		"crowd": 1.0, "fog": true, "render_scale": 1.0, "ssil": false, "lod_bias": 1.0, "show_fps": false},
	"audio": {"master": 0.85, "music": 0.65, "sfx": 0.8, "ambience": 0.6, "ui": 0.7},
	"gameplay": {"damage_numbers": true, "screen_shake": 1.0, "auto_start_waves": true, "edge_pan": false,
		"camera_speed": 1.0, "default_difficulty": "standard", "tutorial_hints": true},
	"accessibility": {"colorblind": false, "high_contrast": false, "reduce_flashes": false, "large_text": false},
}


func _ready() -> void:
	load_settings()
	call_deferred("apply_all")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in data.keys():
		for key in data[section].keys():
			if cfg.has_section_key(section, key):
				var v: Variant = cfg.get_value(section, key)
				if typeof(v) == typeof(data[section][key]) or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and typeof(data[section][key]) in [TYPE_INT, TYPE_FLOAT]):
					data[section][key] = v


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in data.keys():
		for key in data[section].keys():
			cfg.set_value(section, key, data[section][key])
	var err := cfg.save(PATH)
	if err != OK:
		push_warning("Settings: could not save (%s)" % error_string(err))


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	return data.get(section, {}).get(key, fallback)


func set_value(section: String, key: String, value: Variant, apply := true) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	if apply:
		match section:
			"display": apply_display()
			"graphics": apply_graphics()
			"audio": apply_audio()
	changed.emit(section, key)


func apply_preset(index: int) -> void:
	index = clampi(index, 0, 3)
	var p: Dictionary = PRESETS[index]
	data.graphics.preset = index
	for k in p.keys():
		data.graphics[k] = p[k]
	apply_graphics()
	changed.emit("graphics", "preset")


func apply_all() -> void:
	apply_display()
	apply_graphics()
	apply_audio()


func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var d: Dictionary = data.display
	match d.window_mode:
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"exclusive":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_size(DisplayServer.screen_get_size())
			DisplayServer.window_set_position(DisplayServer.screen_get_position())
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			var res: Vector2i = RESOLUTIONS[clampi(int(d.resolution), 0, RESOLUTIONS.size() - 1)]
			var screen := DisplayServer.screen_get_size()
			if screen.x > 0:
				res = Vector2i(mini(res.x, screen.x), mini(res.y, screen.y))
			DisplayServer.window_set_size(res)
			var pos := DisplayServer.screen_get_position() + (screen - res) / 2
			DisplayServer.window_set_position(pos)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if d.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(d.max_fps)
	var scale := float(d.ui_scale)
	if bool(data.accessibility.large_text):
		scale *= 1.15
	get_tree().root.content_scale_factor = scale


func apply_graphics() -> void:
	var g: Dictionary = data.graphics
	var vp := get_tree().root
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][clampi(int(g.msaa), 0, 3)]
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if g.fxaa else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if float(g.render_scale) < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(float(g.render_scale), 0.5, 1.0)
	vp.mesh_lod_threshold = 1.0 / maxf(float(g.lod_bias), 0.1)
	var shadow_sizes := [1024, 2048, 4096, 8192]
	RenderingServer.directional_shadow_atlas_set_size(shadow_sizes[clampi(int(g.shadows), 0, 3)], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][clampi(int(g.shadows), 0, 3)])
	changed.emit("graphics", "applied")


## Called by scenes that own a WorldEnvironment so effects follow the quality settings.
func configure_environment(env: Environment) -> void:
	if env == null:
		return
	var g: Dictionary = data.graphics
	env.ssao_enabled = bool(g.ssao)
	env.ssil_enabled = bool(g.ssil)
	env.glow_enabled = bool(g.glow)
	env.volumetric_fog_enabled = bool(g.fog)


func configure_sun(light: DirectionalLight3D) -> void:
	if light == null:
		return
	var g: Dictionary = data.graphics
	light.shadow_enabled = int(g.shadows) > 0
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if int(g.shadows) <= 1 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func particle_scale() -> float:
	return clampf(float(data.graphics.particles), 0.1, 1.0)


func apply_audio() -> void:
	var a: Dictionary = data.audio
	_set_bus("Master", a.master)
	_set_bus("Music", a.music)
	_set_bus("SFX", a.sfx)
	_set_bus("Ambience", a.ambience)
	_set_bus("UI", a.ui)


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


func shake_scale() -> float:
	return float(data.gameplay.screen_shake)
