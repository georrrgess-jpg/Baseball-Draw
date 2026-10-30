extends Node3D
## Title screen, shown once when the game launches.
## Background: a live night stadium. The camera swoops in and then cranes slowly around the field;
## searchlights sweep the sky, fireworks burst, home-run balls arc overhead, the crowd does the wave
## and the team celebrates on the field.
## Foreground: the Baseball Draw logo slams in (flash, light rays, shine sweep, gold sparkles), then
## "PRESS ANY BUTTON TO START" pulses at the bottom. Any key, click or pad button opens the main menu.

const ARENA := "champions_citadel"
const LOGO_PATH := "res://assets/textures/logo/logo_tagline.png"
const INTRO := 1.4          # when the logo lands
const PROMPT_AT := 2.3      # when "press any button" appears and input is accepted

var stadium: StadiumBuilder
var camera: Camera3D
var _t := 0.0
var _started := false
var _ready_for_input := false
var _shake := 0.0
var _models: Array[CharacterModel] = []
var _beams: Array[Node3D] = []
var _balls: Array = []         # [{node, trail: Array[MeshInstance3D], from, to, t, dur, height}]
var _ball_t := 1.2
var _fw_t := 2.2
var _wave_t := 3.0
var _cheer_t := 4.0

# Overlay
var _ui: CanvasLayer
var _logo: TextureRect
var _logo_mat: ShaderMaterial
var _rays: Control
var _flash: ColorRect
var _prompt: Label
var _prompt_box: Control
var _prompt_band: Panel
var _sparkles: CPUParticles2D
var _intro_tw: Tween


func _ready() -> void:
	var arena := DB.arena(ARENA)
	var layout := DB.layout_for_arena(ARENA)
	stadium = StadiumBuilder.new()
	stadium.build(self, arena, layout, false)
	var routes: Array = []
	for r in layout.get("routes", []):
		routes.append(Route.from_points(r.id, r.gate, r.points))
	FieldBuilder.build(self, arena.get("theme", {}), routes)
	stadium.set_excitement(0.9)
	if stadium.scoreboard_ui and stadium.scoreboard_ui.has_method("flash"):
		stadium.scoreboard_ui.flash("BASEBALL DRAW", 9999.0)

	camera = Camera3D.new()
	camera.fov = 52.0
	camera.far = 900.0
	add_child(camera)
	_place_camera(0.0)
	_spawn_team()
	_build_searchlights()
	_build_overlay()

	Audio.play_music("menu_theme")
	Audio.play_ambience(["stadium_crowd", ""])
	_intro()


# ---------------------------------------------------------------- 3D scene

func _spawn_team() -> void:
	var colors: Dictionary = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.home).colors
	var spots := [Vector3(0, 0, 1), Vector3(-5, 0, -2.5), Vector3(5, 0, -2.5), Vector3(0, 0, -8.5), Vector3(-11, 0, -12), Vector3(11, 0, -12)]
	var team: Array = Profile.data.team
	for i in mini(team.size(), spots.size()):
		var id: String = team[i]
		var cm := CharacterModel.new()
		add_child(cm)
		var c := colors.duplicate()
		c["Undershirt"] = DB.defender(id).accent
		cm.setup(id, {"accent": DB.defender_accent(id), "colors": c, "cache_key": id, "base": "victory" if i % 2 == 0 else "celebrate"})
		cm.position = spots[i]
		cm.rotation.y = randf_range(-PI, PI)
		cm.add_child(Enemy._make_blob_shadow(0.5))
		_models.append(cm)


## Searchlight beams: tall additive cones from behind the outfield, sweeping the night sky.
func _build_searchlights() -> void:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);
uniform float strength = 0.22;
void fragment() {
	float along = UV.y;                       // 0 at the lamp, 1 at the far end
	float edge = 1.0 - abs(dot(NORMAL, VIEW));  // brighter towards the silhouette's centre line
	float a = strength * pow(1.0 - along, 1.6) * (0.35 + 0.65 * (1.0 - edge));
	ALBEDO = tint.rgb * a;
}
"""
	var tints := [Color(0.7, 0.85, 1.0), Color(1.0, 0.82, 0.55), Color(0.85, 0.7, 1.0), Color(0.7, 1.0, 0.9)]
	var bases := [Vector3(-34, 0, -30), Vector3(34, 0, -30), Vector3(-20, 0, -44), Vector3(20, 0, -44)]
	for i in bases.size():
		var pivot := Node3D.new()
		pivot.position = bases[i] + Vector3(0, 6, 0)
		add_child(pivot)
		var cone := CylinderMesh.new()
		cone.top_radius = 0.6
		cone.bottom_radius = 7.0
		cone.height = 90.0
		cone.radial_segments = 20
		cone.cap_top = false
		cone.cap_bottom = false
		var mi := MeshInstance3D.new()
		mi.mesh = cone
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tint", tints[i])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(0, 45, 0)   # cone hangs from the pivot, wide end up
		pivot.add_child(mi)
		pivot.set_meta("phase", i * 1.7)
		_beams.append(pivot)


func _place_camera(t: float) -> void:
	# Swoop: from high above centre field down into a slow crane orbit around the diamond.
	var k := 1.0 - pow(1.0 - clampf(t / 2.4, 0.0, 1.0), 3.0)
	var ang := 0.55 + t * 0.06
	var radius := lerpf(70.0, 33.0, k)
	var height := lerpf(46.0, 12.0 + sin(t * 0.21) * 2.5, k)
	var center := Vector3(0, 0, -6)
	var pos := center + Vector3(sin(ang) * radius, height, cos(ang) * radius)
	var look := center + Vector3(0, lerpf(0.0, 4.5, k), 0)
	if _shake > 0.0:
		pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.6
	camera.position = pos
	camera.look_at(look, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta * 2.5)
	_place_camera(_t)
	for n in _beams:
		var ph := float(n.get_meta("phase"))
		n.rotation = Vector3(sin(_t * 0.35 + ph) * 0.45, 0.0, cos(_t * 0.27 + ph * 1.3) * 0.38)
	_update_balls(delta)
	_fw_t -= delta
	if _fw_t <= 0.0 and stadium.fireworks:
		_fw_t = randf_range(3.5, 5.5)
		stadium.fireworks.launch_show(randi_range(3, 5), 1.6, Vector3(0, 0, -36), Vector2(30, 6), Vector2(20, 30))
	_wave_t -= delta
	if _wave_t <= 0.0 and stadium.crowd:
		_wave_t = randf_range(9.0, 12.0)
		stadium.crowd.start_wave()
	_cheer_t -= delta
	if _cheer_t <= 0.0 and stadium.crowd:
		_cheer_t = randf_range(5.0, 7.0)
		stadium.crowd.cheer(0.8, 1.6)
	if _rays:
		_rays.rotation += delta * 0.12
	if _logo_mat:
		_logo_mat.set_shader_parameter("t", _t)


## Home-run balls: launched from home plate, arcing over the outfield wall with a glowing trail.
func _update_balls(delta: float) -> void:
	_ball_t -= delta
	if _ball_t <= 0.0:
		_ball_t = randf_range(1.6, 2.8)
		_launch_ball()
	for b in _balls.duplicate():
		b.t += delta
		var k: float = clampf(b.t / b.dur, 0.0, 1.0)
		var pos: Vector3 = (b.from as Vector3).lerp(b.to, k) + Vector3(0, sin(k * PI) * float(b.height), 0)
		(b.node as Node3D).position = pos
		var hist: Array = b.hist
		hist.push_front(pos)
		if hist.size() > b.trail.size():
			hist.pop_back()
		for i in (b.trail as Array).size():
			var s: MeshInstance3D = b.trail[i]
			s.visible = i < hist.size()
			if s.visible:
				s.position = hist[i]
		if k >= 1.0:
			(b.node as Node3D).queue_free()
			for s in b.trail:
				(s as Node3D).queue_free()
			_balls.erase(b)


func _launch_ball() -> void:
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.35
	sm.height = 0.7
	ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(1, 0.98, 0.92)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.92, 0.7)
	bm.emission_energy_multiplier = 2.5
	ball.material_override = bm
	add_child(ball)
	var trail: Array = []
	var tq := QuadMesh.new()
	tq.size = Vector2(0.9, 0.9)
	for i in 16:
		var s := MeshInstance3D.new()
		s.mesh = tq
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		var f := 1.0 - float(i) / 16.0
		m.albedo_color = Color(1.0, 0.75 + 0.2 * f, 0.4 + 0.5 * f, 0.55 * f)
		s.material_override = m
		s.scale = Vector3.ONE * (0.4 + 0.9 * f)
		s.visible = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(s)
		trail.append(s)
	var from := Vector3(randf_range(-1.0, 1.0), 1.0, 8.0)
	var to := Vector3(randf_range(-30.0, 30.0), 6.0, randf_range(-48.0, -40.0))
	_balls.append({"node": ball, "trail": trail, "hist": [], "from": from, "to": to, "t": 0.0,
		"dur": randf_range(2.2, 2.8), "height": randf_range(22.0, 30.0)})
	Audio.play("bat_crack", -16.0)


# ---------------------------------------------------------------- overlay

func _build_overlay() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 5
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(root)

	# Vignette: darker edges so the logo and prompt pop.
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vs := Shader.new()
	vs.code = """
shader_type canvas_item;
void fragment() {
	vec2 d = UV - vec2(0.5, 0.45);
	float v = smoothstep(0.35, 0.95, length(d * vec2(1.25, 1.0)));
	float bottom = smoothstep(0.62, 1.0, UV.y) * 0.75;
	COLOR = vec4(0.01, 0.015, 0.04, clamp(v * 0.85 + bottom, 0.0, 0.92));
}
"""
	var vm := ShaderMaterial.new()
	vm.shader = vs
	vig.material = vm
	root.add_child(vig)

	# Light rays behind the logo.
	_rays = TitleRays.new()
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays.set_anchors_preset(Control.PRESET_CENTER)
	_rays.position = Vector2(0, -60)
	_rays.modulate.a = 0.0
	root.add_child(_rays)

	# Gold sparkles drifting up around the logo.
	_sparkles = CPUParticles2D.new()
	_sparkles.emitting = false
	_sparkles.amount = 70
	_sparkles.lifetime = 2.6
	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.emission_rect_extents = Vector2(520, 170)
	_sparkles.direction = Vector2(0, -1)
	_sparkles.spread = 25.0
	_sparkles.gravity = Vector2(0, -12)
	_sparkles.initial_velocity_min = 14.0
	_sparkles.initial_velocity_max = 46.0
	_sparkles.scale_amount_min = 2.0
	_sparkles.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.5, 0.0))
	ramp.set_color(1, Color(1.0, 0.85, 0.4, 0.0))
	ramp.add_point(0.2, Color(1.0, 0.95, 0.7, 0.95))
	ramp.add_point(0.7, Color(1.0, 0.8, 0.35, 0.6))
	_sparkles.color_ramp = ramp
	root.add_child(_sparkles)

	# Logo with a periodic shine sweep.
	_logo = TextureRect.new()
	if ResourceLoader.exists(LOGO_PATH):
		_logo.texture = load(LOGO_PATH)
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ls := Shader.new()
	ls.code = """
shader_type canvas_item;
uniform float t = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float period = 4.2;
	float p = mod(t, period) / 1.1 - 0.25;          // sweep for ~1.1 s, then rest
	float d = (UV.x * 0.8 + UV.y * 0.45) - p * 1.6;
	float band = exp(-d * d * 260.0) * 0.85 + exp(-d * d * 40.0) * 0.18;
	c.rgb += vec3(1.0, 0.96, 0.85) * band * c.a;
	COLOR = c;
}
"""
	_logo_mat = ShaderMaterial.new()
	_logo_mat.shader = ls
	_logo.material = _logo_mat
	root.add_child(_logo)

	# PRESS ANY BUTTON TO START
	_prompt_box = Control.new()
	_prompt_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	root.add_child(_prompt_box)
	# A soft dark band behind the prompt keeps it readable over the busy stadium.
	var band := Panel.new()
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.02, 0.02, 0.06, 0.62)
	bs.border_color = Color(UITheme.GOLD, 0.55)
	bs.set_border_width_all(2)
	bs.set_corner_radius_all(40)
	bs.shadow_color = Color(1.0, 0.75, 0.3, 0.25)
	bs.shadow_size = 18
	band.add_theme_stylebox_override("panel", bs)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.size = Vector2(860, 86)
	band.position = Vector2(-430, -184)
	band.modulate.a = 0.0
	_prompt_box.add_child(band)
	_prompt_band = band
	_prompt = UITheme.title("PRESS ANY BUTTON TO START", 54, Color(1.0, 0.95, 0.82))
	_prompt.add_theme_constant_override("outline_size", 12)
	_prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.08, 0.9))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size = Vector2(1200, 0)
	_prompt.position = Vector2(-600, -178)
	_prompt.pivot_offset = Vector2(600, 36)
	_prompt.modulate.a = 0.0
	_prompt_box.add_child(_prompt)

	var ver := UITheme.label("v%s" % ProjectSettings.get_setting("application/config/version", "1.0"), 16, Color(1, 1, 1, 0.35))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-90, -36)
	root.add_child(ver)

	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	root.add_child(_flash)

	# Start from black.
	var black := ColorRect.new()
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.color = Color(0, 0, 0, 1)
	root.add_child(black)
	var bt := black.create_tween()
	bt.tween_property(black, "color:a", 0.0, 0.9).set_trans(Tween.TRANS_SINE)
	bt.tween_callback(black.queue_free)
	root.resized.connect(_layout_logo)
	_layout_logo.call_deferred()


func _layout_logo() -> void:
	var vp := get_viewport().get_visible_rect().size
	var w := minf(vp.x * 0.62, 1180.0)
	var h := w * 1398.0 / 2048.0
	_logo.size = Vector2(w, h)
	_logo.position = Vector2((vp.x - w) * 0.5, vp.y * 0.43 - h * 0.5)
	_logo.pivot_offset = _logo.size * 0.5
	_rays.position = Vector2(vp.x * 0.5, vp.y * 0.43)
	_sparkles.position = Vector2(vp.x * 0.5, vp.y * 0.45)


func _intro() -> void:
	_logo.modulate.a = 0.0
	_logo.scale = Vector2(2.6, 2.6)
	var tw := create_tween()
	_intro_tw = tw
	tw.tween_interval(INTRO - 0.35)
	tw.tween_callback(func() -> void: Audio.play("swing_whoosh", -4.0))
	tw.tween_property(_logo, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(_logo, "scale", Vector2(0.94, 0.94), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_logo_impact)
	tw.tween_property(_logo, "scale", Vector2(1.04, 1.04), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_logo, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(PROMPT_AT - INTRO - 0.55)
	tw.tween_callback(_show_prompt)


func _logo_impact() -> void:
	Audio.play("bat_crack", 0.0, 0.0)
	Audio.play("crowd_roar", -4.0)
	var reduce := bool(Settings.get_value("accessibility", "reduce_flashes", false))
	_flash.color = Color(1.0, 0.95, 0.85, 0.35 if reduce else 0.8)
	create_tween().tween_property(_flash, "color:a", 0.0, 0.6)
	if bool(Settings.get_value("gameplay", "screen_shake", true)):
		_shake = 1.0
	_rays.modulate.a = 0.0
	create_tween().tween_property(_rays, "modulate:a", 1.0, 0.5)
	_sparkles.emitting = true
	if stadium.fireworks:
		stadium.fireworks.launch_show(6, 1.0, Vector3(0, 0, -36), Vector2(28, 6), Vector2(20, 30))
	if stadium.crowd:
		stadium.crowd.stand_up(4.0)


func _show_prompt() -> void:
	_ready_for_input = true
	_prompt.modulate.a = 0.0
	var tw := _prompt.create_tween().set_parallel()
	tw.tween_property(_prompt, "modulate:a", 1.0, 0.4)
	tw.tween_property(_prompt_band, "modulate:a", 1.0, 0.4)
	var pulse := _prompt.create_tween().set_loops()
	pulse.tween_property(_prompt, "scale", Vector2(1.05, 1.05), 0.75).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(_prompt, "self_modulate", Color(1.15, 1.05, 0.75), 0.75).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_prompt, "scale", Vector2.ONE, 0.75).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(_prompt, "self_modulate", Color(1, 1, 1, 0.8), 0.75).set_trans(Tween.TRANS_SINE)


# ---------------------------------------------------------------- start

func _unhandled_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventKey and event.pressed and not event.echo:
		pressed = true
	elif event is InputEventMouseButton and event.pressed:
		pressed = true
	elif event is InputEventJoypadButton and event.pressed:
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if _started:
		return
	if not _ready_for_input:
		# Pressing during the intro skips straight to the finished title.
		_skip_intro()
		return
	start()


func _skip_intro() -> void:
	if _ready_for_input:
		return
	if _intro_tw and _intro_tw.is_valid():
		_intro_tw.kill()
	_logo.modulate.a = 1.0
	_logo.scale = Vector2.ONE
	_rays.modulate.a = 1.0
	_sparkles.emitting = true
	_show_prompt()


## Leaves for the main menu: a burst, the crowd roars, the logo rushes toward the camera.
func start() -> void:
	if _started:
		return
	_started = true
	Audio.ui("ui_confirm")
	Audio.play("crowd_roar", -2.0)
	_flash.color = Color(1.0, 0.95, 0.85, 0.5)
	var tw := create_tween().set_parallel()
	tw.tween_property(_flash, "color:a", 0.0, 0.4)
	tw.tween_property(_logo, "scale", Vector2(1.25, 1.25), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(_logo, "modulate:a", 0.0, 0.45)
	tw.tween_property(_prompt, "modulate:a", 0.0, 0.2)
	tw.tween_property(_prompt_band, "modulate:a", 0.0, 0.2)
	tw.tween_property(_rays, "modulate:a", 0.0, 0.3)
	if stadium.fireworks:
		stadium.fireworks.launch_show(5, 0.6, Vector3(0, 0, -36), Vector2(28, 6), Vector2(20, 30))
	tw.chain().tween_callback(func() -> void: Router.goto("main_menu"))


## Rotating light rays drawn behind the logo.
class TitleRays:
	extends Control

	func _draw() -> void:
		var n := 22
		for i in n:
			var a0 := TAU * i / n
			var a1 := a0 + TAU / n * 0.42
			var r := 1300.0
			var col := Color(1.0, 0.85, 0.45, 0.13) if i % 2 == 0 else Color(0.6, 0.75, 1.0, 0.08)
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a1), sin(a1)) * r]), col)
		# Soft glow core.
		for k in 6:
			draw_circle(Vector2.ZERO, 380.0 - k * 55.0, Color(1.0, 0.85, 0.5, 0.04))
