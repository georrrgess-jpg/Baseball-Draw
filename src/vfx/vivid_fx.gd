extends RefCounted
## Update 8 "vibrancy" building blocks for card effects, owned by card_fx.gd (no edits to the
## shared vfx.gd): colour-over-life particle systems driven by the category palette's ramps,
## light pooled on the ground that cools over a second or two, and a short screen-space
## accent (radial streaks, coloured screen edges, a glow lift) for Legendary casts.
## Every piece respects the particle-scale setting (counts go through vfx._count) and
## reduce_flashes (dimmer flares, no screen streaks, no glow lift).

const SH := "res://assets/shaders/vfx/"

var vfx: VFX
var rows: Array[String] = []
var ramp_tex: ImageTexture
var _glow_mat: ShaderMaterial
var _plane: PlaneMesh
var _accent: CanvasLayer
var _accent_mat: ShaderMaterial
var _accent_dur := 0.45
var _accent_strength := 0.0
var _glow_base := -1.0
var _glow_lift := 0.0
var _gen := 0


func _init(p_vfx: VFX, palette: Dictionary) -> void:
	vfx = p_vfx
	_build_ramps(palette)
	_build_systems()
	_plane = PlaneMesh.new()
	_plane.size = Vector2(2, 2)
	_glow_mat = ShaderMaterial.new()
	_glow_mat.shader = load(SH + "fx_ground_glow.gdshader")
	_glow_mat.set_shader_parameter("ramp", ramp_tex)
	_glow_mat.set_shader_parameter("noise", vfx.tex.noise)
	_glow_mat.set_shader_parameter("energy", 0.9 if vfx.reduce_flashes else 1.5)
	_glow_mat.render_priority = 1


## One ramp row per palette entry (white-hot core -> tint -> body -> deep edge).
func _build_ramps(palette: Dictionary) -> void:
	var w := 64
	var keys: Array = palette.keys()
	var img := Image.create(w, keys.size(), false, Image.FORMAT_RGBA8)
	for y in keys.size():
		var stops: Array = palette[keys[y]]
		rows.append(String(keys[y]))
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.16, 0.5, 1.0])
		g.colors = PackedColorArray([stops[0], stops[1], stops[2], stops[3]])
		for x in w:
			img.set_pixel(x, y, g.sample(float(x) / (w - 1)))
	ramp_tex = ImageTexture.create_from_image(img)


## The colour to pass to a ramp particle: rgb = tint, a = ramp row.
func row_color(ramp: String, tint := Color.WHITE) -> Color:
	var i := maxi(rows.find(ramp), 0)
	return Color(tint.r, tint.g, tint.b, (i + 0.5) / float(rows.size()))


func row_v(ramp: String) -> float:
	return (maxi(rows.find(ramp), 0) + 0.5) / float(rows.size())


# name: lifetime, texture, gravity, damping, scale, size_mode, streak, extra
func _build_systems() -> void:
	var dim := vfx.reduce_flashes
	_system("v_flare", 64, 0.3, vfx.tex.glow, Vector3.ZERO, 0.0, 2.0, 5, false,
		{"energy": 0.8 if dim else 1.5, "hot": 0.6 if dim else 2.6, "hot_time": 0.35, "fade_pow": 1.6, "core": 0.8})
	_system("v_glow", 300, 0.6, vfx.tex.glow, Vector3.ZERO, 3.0, 0.6, 1, false,
		{"energy": 1.25, "hot": 0.5, "hot_time": 0.2, "fade_pow": 1.2, "core": 0.15})
	_system("v_spark", 600, 0.6, vfx.tex.spark, Vector3(0, -9.0, 0), 1.6, 0.08, 0, true,
		{"energy": 2.2, "hot": 2.0, "hot_time": 0.3, "aspect": 6.0, "core": 0.3, "align": true, "stretch": 0.05})
	_system("v_ember", 400, 1.3, vfx.tex.glow, Vector3(0, 1.4, 0), 1.2, 0.12, 6, false,
		{"energy": 2.6, "hot": 1.2, "hot_time": 0.2, "core": 0.4, "turbulence": 6.0})
	_system("v_mote", 300, 0.9, vfx.tex.star, Vector3(0, 0.6, 0), 2.2, 0.28, 6, false,
		{"energy": 2.0, "hot": 1.5, "hot_time": 0.3, "core": 0.5, "spin": 2.0})


func _system(name: String, amount: int, lifetime: float, texture: Texture2D, gravity: Vector3, damping: float,
		base_scale: float, size_mode: int, streak: bool, extra: Dictionary) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(16, int(amount * maxf(vfx._scale, 0.3)))
	p.lifetime = lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-90, -5, -90), Vector3(180, 70, 180))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ShaderMaterial.new()
	pm.shader = load(SH + "fx_particles.gdshader")
	pm.set_shader_parameter("gravity", gravity)
	pm.set_shader_parameter("damping", damping)
	pm.set_shader_parameter("base_scale", base_scale)
	pm.set_shader_parameter("size_mode", size_mode)
	pm.set_shader_parameter("spin", float(extra.get("spin", 0.0)))
	pm.set_shader_parameter("turbulence", float(extra.get("turbulence", 0.0)))
	pm.set_shader_parameter("align_velocity", bool(extra.get("align", false)))
	pm.set_shader_parameter("stretch", float(extra.get("stretch", 0.0)))
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	p.draw_pass_1 = q
	var sm := ShaderMaterial.new()
	sm.shader = load(SH + "fx_particle_ramp.gdshader")
	sm.set_shader_parameter("tex", texture)
	sm.set_shader_parameter("ramp", ramp_tex)
	sm.set_shader_parameter("streak", streak)
	for k in ["energy", "hot", "hot_time", "fade_in", "fade_pow", "core", "aspect"]:
		if extra.has(k):
			sm.set_shader_parameter(k, extra[k])
	sm.render_priority = 5
	p.material_override = sm
	vfx.add_child(p)
	p.emitting = true
	p.amount_ratio = 0.0
	vfx.systems[name] = p


# ---------------------------------------------------------------- ground light

## Light pooled on the ground: lands white-hot, cools along the ramp and fades over `dur`.
func ground_glow(pos: Vector3, radius: float, ramp: String, dur := 1.5, rim := 0.6, delay := 0.0, strength := 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _plane
	mi.material_override = _glow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	vfx.add_child(mi)
	mi.global_position = Vector3(pos.x, 0.075, pos.z)
	mi.scale = Vector3(radius, 1, radius)
	var seed := randf() * 10.0
	mi.set_instance_shader_parameter("row", row_v(ramp))
	mi.set_instance_shader_parameter("anim", Vector4(0, 0, seed, rim))
	var an := vfx.animate(mi, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var grow := 1.0 - pow(1.0 - clampf(tt / 0.14, 0.0, 1.0), 3.0)
		n.scale = Vector3.ONE * radius * (0.55 + 0.45 * grow)
		var vis := grow * (1.0 - smoothstep(0.35, 1.0, k)) * strength
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, seed, rim * (1.0 - k))), delay)
	an.free_node = true
	return mi


# ---------------------------------------------------------------- screen accent (Legendaries)

## A short screen-space accent at `world_pos`: radial streaks racing outward and a coloured
## glow along the screen edges, about 0.45 s, plus a brief lift of the scene's bloom.
## Sits below the HUD (layer 5 < 10) and ignores the mouse, so the hand stays clickable.
func screen_accent(world_pos: Vector3, color: Color, color2: Color, strength := 1.0) -> void:
	var cam := vfx.get_viewport().get_camera_3d()
	if cam == null:
		return
	if _accent == null:
		_accent = CanvasLayer.new()
		_accent.layer = 5
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_accent_mat = ShaderMaterial.new()
		_accent_mat.shader = load(SH + "fx_screen_accent.gdshader")
		rect.material = _accent_mat
		_accent.add_child(rect)
		vfx.add_child(_accent)
	var vp := vfx.get_viewport().get_visible_rect().size
	var sp := cam.unproject_position(world_pos) if not cam.is_position_behind(world_pos) else vp * 0.5
	_accent_mat.set_shader_parameter("center", Vector2(sp.x / maxf(vp.x, 1.0), sp.y / maxf(vp.y, 1.0)))
	_accent_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_accent_mat.set_shader_parameter("color", color)
	_accent_mat.set_shader_parameter("color2", color2)
	_accent_mat.set_shader_parameter("seed", randf() * 10.0)
	_accent_mat.set_shader_parameter("streaks", 0.0 if vfx.reduce_flashes else 1.0)
	_accent_strength = strength * (0.35 if vfx.reduce_flashes else 1.0)
	_accent.visible = true
	_glow_lift = 0.0 if vfx.reduce_flashes else 0.45 * strength
	_gen += 1
	var gen := _gen
	vfx.every_frame(_accent_dur, func(k: float) -> void: _tick_accent(k, gen))


func _tick_accent(k: float, gen: int) -> void:
	if _accent_mat == null or gen != _gen:
		return
	_accent_mat.set_shader_parameter("t", k)
	_accent_mat.set_shader_parameter("strength", _accent_strength * (1.0 - smoothstep(0.8, 1.0, k)))
	var env := _env()
	if env != null and _glow_lift > 0.0:
		if _glow_base < 0.0:
			_glow_base = env.glow_intensity
		env.glow_intensity = _glow_base + _glow_lift * sin(PI * k)
	if k >= 1.0:
		_accent.visible = false
		if env != null and _glow_base >= 0.0:
			env.glow_intensity = _glow_base


func _env() -> Environment:
	var b = vfx.battle
	if b and "stadium" in b and b.stadium and b.stadium.world_env:
		return b.stadium.world_env.environment
	return null
