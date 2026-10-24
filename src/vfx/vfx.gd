class_name VFX
extends Node3D
## Battle visual effects. Particles use a handful of shared GPUParticles3D systems
## driven with emit_particle(), so hundreds of hits cost almost nothing.
## Also: floating combat text, ground rings, telegraphs, shockwaves and lightning.

const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY | GPUParticles3D.EMIT_FLAG_COLOR

var systems := {}
var _labels: Array[Label3D] = []
var _label_i := 0
var _soft_tex: Texture2D
var _spark_tex: Texture2D
var _scale := 1.0
var reduce_flashes := false


func _ready() -> void:
	_scale = Settings.particle_scale()
	reduce_flashes = bool(Settings.get_value("accessibility", "reduce_flashes", false))
	_soft_tex = _radial_texture(Color(1, 1, 1, 1), 0.0)
	_spark_tex = _radial_texture(Color(1, 1, 1, 1), 0.55)
	# name: [amount, lifetime, gravity, damping, scale_min, scale_max, texture, additive, drag_up]
	_make_system("spark", 600, 0.55, -9.0, 2.5, 0.06, 0.14, _spark_tex, true)
	_make_system("glow", 300, 0.5, 0.0, 6.0, 0.35, 0.7, _soft_tex, true)
	_make_system("ember", 400, 1.1, 1.6, 1.0, 0.05, 0.11, _spark_tex, true)
	_make_system("smoke", 300, 1.4, 0.6, 2.0, 0.5, 1.1, _soft_tex, false)
	_make_system("dust", 300, 0.9, -1.2, 3.0, 0.35, 0.8, _soft_tex, false)
	_make_system("magic", 400, 0.9, 0.8, 2.0, 0.08, 0.2, _spark_tex, true)
	_make_system("snow", 300, 1.6, -1.5, 1.0, 0.06, 0.14, _soft_tex, true)
	_make_system("confetti", 400, 2.4, -3.0, 1.2, 0.08, 0.16, null, false)
	for i in 40:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font = UITheme.font_display()
		l.font_size = 40
		l.outline_size = 12
		l.outline_modulate = Color(0.05, 0.02, 0.02, 0.9)
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		_labels.append(l)


func _radial_texture(c: Color, hard: float) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, hard, 1.0])
	g.colors = PackedColorArray([c, Color(c, 0.6 if hard > 0.0 else 0.5), Color(c, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	return gt


func _make_system(name: String, amount: int, lifetime: float, gravity: float, damping: float,
		smin: float, smax: float, tex: Texture2D, additive: bool) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(16, int(amount * maxf(_scale, 0.3)))
	p.lifetime = lifetime
	p.emitting = false
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 50, 160))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, gravity, 0)
	pm.damping_min = damping
	pm.damping_max = damping
	pm.scale_min = smin
	pm.scale_max = smax
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var alpha := Gradient.new()
	alpha.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	alpha.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	var at := GradientTexture1D.new()
	at.gradient = alpha
	pm.color_ramp = at
	if name == "confetti":
		pm.angular_velocity_min = -720
		pm.angular_velocity_max = 720
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1) if name != "confetti" else Vector2(1, 0.55)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if name != "confetti" else BaseMaterial3D.BILLBOARD_DISABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	if tex:
		m.albedo_texture = tex
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	p.emitting = true
	p.amount_ratio = 0.0
	systems[name] = p


## Emits n particles from a point with a random spread.
func emit(system: String, pos: Vector3, n: int, color: Color, speed := 4.0, up := 0.5, spread := 1.0) -> void:
	var p: GPUParticles3D = systems.get(system)
	if p == null:
		return
	n = maxi(1, int(round(n * _scale)))
	for i in n:
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0) + up, randf_range(-1, 1)).normalized()
		var v := dir * speed * randf_range(0.5, 1.0) * spread
		var c := color
		c.v = clampf(c.v * randf_range(0.85, 1.15), 0.0, 4.0)
		p.emit_particle(Transform3D(Basis(), pos + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1))), v, c, Color(), FLAGS)


# ---------------------------------------------------------------- hits & bursts

func burst(kind: String, pos: Vector3, color: Color = Color.WHITE) -> void:
	match kind:
		"hit":
			emit("spark", pos, 7, color.lerp(Color.WHITE, 0.5), 5.0)
			emit("glow", pos, 1, Color(color, 0.7), 0.2)
		"crit":
			emit("spark", pos, 16, Color(1.0, 0.9, 0.5), 7.0)
			emit("glow", pos, 2, Color(1.0, 0.8, 0.4, 0.9), 0.3)
			shockwave(pos, 1.2, Color(1.0, 0.85, 0.4), 0.25)
		"explosion":
			emit("spark", pos, 24, Color(1.0, 0.6, 0.2), 9.0, 0.8)
			emit("glow", pos, 4, Color(1.0, 0.5, 0.15, 0.9), 1.2)
			emit("smoke", pos, 6, Color(0.25, 0.22, 0.2, 0.7), 2.0, 1.0)
			emit("ember", pos, 12, Color(1.0, 0.5, 0.1), 5.0, 1.0)
		"fire":
			emit("ember", pos, 6, Color(1.0, 0.55, 0.12), 2.5, 1.2)
			emit("glow", pos, 1, Color(1.0, 0.4, 0.05, 0.8), 1.0, 2.0)
		"frost":
			emit("snow", pos, 8, Color(0.75, 0.95, 1.0), 3.0, 0.6)
			emit("glow", pos, 1, Color(0.5, 0.85, 1.0, 0.7), 0.3)
		"shadow":
			emit("smoke", pos, 6, Color(0.35, 0.15, 0.55, 0.8), 2.5, 0.6)
			emit("magic", pos, 8, Color(0.75, 0.45, 1.0), 3.0)
		"magic":
			emit("magic", pos, 10, color, 3.5, 0.8)
		"gold":
			emit("magic", pos, 14, Color(1.0, 0.85, 0.3), 4.5, 1.0)
			emit("glow", pos, 2, Color(1.0, 0.8, 0.3, 0.8), 0.6)
		"out":
			emit("spark", pos, 10, Color(1.0, 0.95, 0.8), 6.0, 0.8)
			emit("dust", Vector3(pos.x, 0.2, pos.z), 5, Color(0.6, 0.45, 0.32, 0.6), 2.0, 0.2)
		"confetti":
			for i in 3:
				var cols := [UITheme.SCARLET, UITheme.GOLD, UITheme.OFFWHITE, UITheme.BLUE, UITheme.GREEN]
				emit("confetti", pos, 18, cols[randi() % cols.size()], 7.0, 1.5)


func dust(pos: Vector3, amount := 1.0) -> void:
	emit("dust", Vector3(pos.x, 0.25, pos.z), int(6 * amount), Color(0.62, 0.46, 0.33, 0.55), 2.0 * amount, 0.15)


func puff(pos: Vector3, color: Color) -> void:
	emit("smoke", pos, 5, Color(color, 0.7), 1.6, 0.3)
	emit("magic", pos, 8, color, 3.0)


func ember(pos: Vector3) -> void:
	emit("ember", pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.3, 0.3), randf_range(-0.2, 0.2)), 1, Color(1.0, 0.5, 0.1), 1.0, 1.5, 0.6)


func speed_lines(e: Node3D) -> void:
	var back := -e.global_transform.basis.z
	for i in 6:
		var p := e.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 1.6), randf_range(-0.3, 0.3))
		(systems.spark as GPUParticles3D).emit_particle(Transform3D(Basis(), p), back * 6.0, Color(1.0, 0.9, 0.3), Color(), FLAGS)


# ---------------------------------------------------------------- text

func _next_label() -> Label3D:
	var l := _labels[_label_i]
	_label_i = (_label_i + 1) % _labels.size()
	var tw: Tween = l.get_meta("tween") if l.has_meta("tween") else null
	if tw and tw.is_valid():
		tw.kill()
	return l


func damage_number(pos: Vector3, amount: float, crit: bool, color := Color(1.0, 0.95, 0.85)) -> void:
	if not bool(Settings.get_value("gameplay", "damage_numbers", true)):
		return
	if amount < 1.0:
		return
	var l := _next_label()
	l.text = str(int(round(amount))) + ("!" if crit else "")
	l.modulate = Color(1.0, 0.8, 0.2) if crit else color
	l.font_size = 34 if crit else 24
	_animate_label(l, pos + Vector3(randf_range(-0.35, 0.35), 0.3, randf_range(-0.2, 0.2)), 0.75, 1.25 if crit else 1.0)


func text_popup(pos: Vector3, text: String, color: Color, scale := 1.0, duration := 1.0) -> void:
	var l := _next_label()
	l.text = text
	l.modulate = color
	l.font_size = int(32 * scale)
	_animate_label(l, pos, duration, scale)


func _animate_label(l: Label3D, pos: Vector3, duration: float, pop: float) -> void:
	l.global_position = pos
	l.visible = true
	l.scale = Vector3.ONE * 0.4
	var c := l.modulate
	c.a = 1.0
	l.modulate = c
	var oc := l.outline_modulate
	oc.a = 0.9
	l.outline_modulate = oc
	var tw := create_tween()
	l.set_meta("tween", tw)
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE * pop, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.1, 0), duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tw.tween_property(l, "outline_modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tw.chain().tween_callback(func() -> void: l.visible = false)


# ---------------------------------------------------------------- ground rings

func shockwave(pos: Vector3, radius: float, color: Color, time := 0.45) -> void:
	var r := FieldBuilder.make_ring(0.2, color, 0.18, 0.15)
	add_child(r)
	r.global_position = Vector3(pos.x, 0.06, pos.z)
	var mat: ShaderMaterial = r.material_override
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(r, "scale", Vector3(radius, 1, radius), time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(func(a: float) -> void: mat.set_shader_parameter("color", Color(color, a)), 1.0, 0.0, time)
	tw.chain().tween_callback(r.queue_free)


## A danger zone that fills up until the attack lands.
func telegraph(pos: Vector3, radius: float, color: Color, time: float) -> Node3D:
	var r := FieldBuilder.make_ring(radius, color, 0.05, 0.22)
	add_child(r)
	r.global_position = Vector3(pos.x, 0.07, pos.z)
	var mat: ShaderMaterial = r.material_override
	mat.set_shader_parameter("pulse", 1.0)
	mat.set_shader_parameter("progress", 0.0)
	var tw := r.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("progress", v), 0.0, 1.0, time)
	return r


## Persistent ground circle for an ability zone; fades out after `time`.
func zone_ring(pos: Vector3, radius: float, color: Color, time: float, fill := 0.18, spin := 0.0) -> MeshInstance3D:
	var r := FieldBuilder.make_ring(radius, color, 0.04, fill, 24.0 if spin != 0.0 else 0.0)
	add_child(r)
	r.global_position = Vector3(pos.x, 0.065, pos.z)
	var mat: ShaderMaterial = r.material_override
	mat.set_shader_parameter("spin", spin)
	r.scale = Vector3(0.1, 1, 0.1)
	var tw := r.create_tween()
	tw.tween_property(r, "scale", Vector3(radius, 1, radius), 0.2).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(time - 0.6, 0.0))
	tw.tween_method(func(a: float) -> void: mat.set_shader_parameter("color", Color(color, a)), color.a, 0.0, 0.4)
	tw.tween_callback(r.queue_free)
	return r


func lightning(a: Vector3, b: Vector3, color: Color, width := 0.08) -> void:
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam else Vector3(0, 30, 30)
	var pts: Array[Vector3] = [a]
	var segs := 8
	for i in range(1, segs):
		var k := float(i) / segs
		pts.append(a.lerp(b, k) + Vector3(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35), randf_range(-0.35, 0.35)))
	pts.append(b)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in pts.size():
		var p := pts[i]
		var dir := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(cam_pos - p).normalized() * width
		im.surface_add_vertex(p + side)
		im.surface_add_vertex(p - side)
	im.surface_end()
	emit("spark", b, 6, color, 4.0)
	var tw := create_tween()
	tw.tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)


func stun_stars(target: Node3D, time: float) -> void:
	var holder := Node3D.new()
	target.add_child(holder)
	var h: float = target.model.height if "model" in target and target.model else 1.8
	holder.position = Vector3(0, h + 0.15, 0)
	for i in 3:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		s.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.9, 0.3)
		s.material_override = m
		var a := TAU * i / 3.0
		s.position = Vector3(cos(a) * 0.35, 0, sin(a) * 0.35)
		holder.add_child(s)
	var tw := holder.create_tween()
	tw.tween_property(holder, "rotation:y", TAU * time * 1.2, time)
	tw.tween_callback(holder.queue_free)


## A burning strip of ground (Heat Wave). Emits fire for `time` seconds.
func fire_line(from: Vector3, to: Vector3, width: float, time: float) -> void:
	var n := Node3D.new()
	add_child(n)
	var flat_from := Vector3(from.x, 0.1, from.z)
	var flat_to := Vector3(to.x, 0.1, to.z)
	var scorch := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(width, flat_from.distance_to(flat_to))
	scorch.mesh = pm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft_tex
	m.albedo_color = Color(1.0, 0.35, 0.05, 0.55)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	scorch.material_override = m
	scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(scorch)
	scorch.global_position = (flat_from + flat_to) * 0.5 + Vector3(0, 0.02, 0)
	var dir := flat_to - flat_from
	scorch.rotation.y = atan2(dir.x, dir.z)
	var elapsed := [0.0]
	var timer := Timer.new()
	timer.wait_time = 0.06
	timer.autostart = true
	n.add_child(timer)
	timer.timeout.connect(func() -> void:
		elapsed[0] += 0.06
		for i in 3:
			var k := randf()
			var side := Vector3(-dir.z, 0, dir.x).normalized() * randf_range(-width * 0.45, width * 0.45)
			var p := flat_from.lerp(flat_to, k) + side
			emit("ember", p, 1, Color(1.0, 0.5, 0.1), 2.5, 1.5, 0.8)
			if randf() < 0.5:
				emit("glow", p + Vector3(0, 0.3, 0), 1, Color(1.0, 0.35, 0.05, 0.6), 1.2, 2.0, 0.6)
		if elapsed[0] >= time:
			timer.stop()
			var tw := n.create_tween()
			tw.tween_property(m, "albedo_color:a", 0.0, 0.5)
			tw.tween_callback(n.queue_free))


## Glowing hexagonal dome over home plate while Base Shields are up.
func make_shield_dome() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.2
	sm.height = 2.2
	sm.is_hemisphere = true
	sm.radial_segments = 24
	sm.rings = 8
	mi.mesh = sm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 col : source_color = vec4(0.3, 0.8, 1.0, 1.0);
uniform float strength = 1.0;
void fragment() {
	float fres = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	vec2 h = UV * vec2(24.0, 8.0);
	float hex = step(0.9, fract(h.x + 0.5 * floor(h.y))) + step(0.9, fract(h.y));
	float scan = 0.5 + 0.5 * sin(UV.y * 40.0 - TIME * 3.0);
	ALBEDO = col.rgb * (fres * 1.2 + hex * 0.35 + scan * 0.05) * strength;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi
