class_name StadiumFireworks
extends Node3D
## Fireworks over the stadium: a rocket streaks up from behind the outfield wall and bursts into
## a sphere of additive sparks that droop and fade. A small pool of particle systems is reused,
## and the spark count follows the particle quality setting.

const POOL := 6

var _bursts: Array[GPUParticles3D] = []
var _rockets: Array[GPUParticles3D] = []
var _next := 0
var _queue: Array = []      # [time, origin, apex, color]
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var palette: Array[Color] = [Color(1.0, 0.3, 0.25), Color(1.0, 0.82, 0.3), Color(0.35, 0.8, 1.0),
	Color(0.6, 1.0, 0.45), Color(1.0, 0.45, 0.95), Color(1, 1, 1)]


func _ready() -> void:
	_rng.randomize()
	var scale_amt := Settings.particle_scale()
	var tex := _spark_texture()
	for i in POOL:
		_bursts.append(_make_burst(int(140 * scale_amt) + 30, tex))
		_rockets.append(_make_rocket(tex))
	set_process(true)


func _spark_material(tex: Texture2D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.no_depth_test = false
	m.disable_fog = true
	return m


func _make_burst(amount: int, tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.96
	p.lifetime = 2.1
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 9.5
	pm.gravity = Vector3(0, -3.2, 0)
	pm.damping_min = 2.6
	pm.damping_max = 3.4
	pm.scale_min = 0.8
	pm.scale_max = 1.3
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(0.7, 0.7))
	sc.add_point(Vector2(1, 0.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.85, 0.85)
	q.material = _spark_material(tex)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _make_rocket(tex: Texture2D) -> GPUParticles3D:
	# The rocket is a short-lived trail emitter that we move upwards.
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.45
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, -2, 0)
	pm.color = Color(1.0, 0.8, 0.5)
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1.0))
	sc.add_point(Vector2(1, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	q.material = _spark_material(tex)
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-10, -30, -10), Vector3(20, 40, 20))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


func _spark_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 32
	gt.height = 32
	return gt


## Queues `count` shells over `duration` seconds above the area around `center`.
func launch_show(count: int, duration: float, center := Vector3(0, 0, -30), spread := Vector2(30, 10), height := Vector2(18, 26)) -> void:
	for i in count:
		var at := _t + (duration * i / maxf(count - 1, 1)) + _rng.randf_range(0.0, 0.25)
		var apex := center + Vector3(_rng.randf_range(-spread.x, spread.x), _rng.randf_range(height.x, height.y), _rng.randf_range(-spread.y, spread.y))
		var origin := Vector3(apex.x * 1.1, 2.0, apex.z - 6.0)
		_queue.append([at, origin, apex, palette[_rng.randi() % palette.size()]])


func busy() -> bool:
	return not _queue.is_empty()


func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_t += dt
	var i := 0
	while i < _queue.size():
		if _queue[i][0] <= _t:
			_launch(_queue[i][1], _queue[i][2], _queue[i][3])
			_queue.remove_at(i)
		else:
			i += 1


func _launch(origin: Vector3, apex: Vector3, col: Color) -> void:
	var idx := _next
	_next = (_next + 1) % POOL
	var rocket := _rockets[idx]
	rocket.global_position = origin
	rocket.emitting = true
	var tw := create_tween()
	tw.set_ignore_time_scale(true)
	tw.tween_property(rocket, "global_position", apex, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		rocket.emitting = false
		var b := _bursts[idx]
		b.global_position = apex
		(b.process_material as ParticleProcessMaterial).color = col * 1.25
		b.restart()
		b.emitting = true
		# Silent until an audio pass adds a "firework" effect (unknown names are ignored).
		Audio.play("firework", -8.0, 0.1, 120))
