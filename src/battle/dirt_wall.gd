class_name DirtWall
extends Node3D
## Wall of Dirt: an earthen barrier across a route that blocks ground runners
## until its time runs out or it takes enough damage. Sluggers smash it instantly.

var battle: Battle
var active := true
var radius := 1.6
var hp := 200.0
var max_hp := 200.0
var time_left := 7.0
var _mesh: Node3D
var _hurt := 0.0
var _hurt_fx := 0.0
var _base_y := 0.0

static var _mat_cache := {}


static func _dirt_material(col: Color) -> StandardMaterial3D:
	var key := col.to_html()
	if _mat_cache.has(key):
		return _mat_cache[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0
	var nt := NoiseTexture2D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 0.08
	nt.noise = fn
	nt.width = 128
	nt.height = 128
	mat.albedo_texture = nt
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.8, 0.8, 0.8)
	_mat_cache[key] = mat
	return mat


func setup(p_battle: Battle, pos: Vector3, facing: Vector3, p_hp: float, dur: float) -> void:
	battle = p_battle
	hp = p_hp
	max_hp = p_hp
	time_left = dur
	position = Vector3(pos.x, 0, pos.z)
	rotation.y = atan2(facing.x, facing.z)
	var dirt := Color(battle.arena.theme.get("dirt", "#b06a3e")).darkened(0.15)
	var mat := _dirt_material(dirt)
	var dark := _dirt_material(dirt.darkened(0.3))
	_mesh = Node3D.new()
	add_child(_mesh)
	# Base berm.
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.6, 0.9, 1.2)
	base.mesh = bm
	base.material_override = mat
	base.position.y = 0.4
	_mesh.add_child(base)
	# Jagged ridge of earth spikes (like the card art).
	var n := 7
	for i in n:
		var spike := MeshInstance3D.new()
		var pm := PrismMesh.new()
		var h := randf_range(1.2, 2.0) * (1.0 - absf(i - (n - 1) * 0.5) / n * 0.6)
		pm.size = Vector3(randf_range(0.7, 1.0), h, randf_range(0.8, 1.05))
		spike.mesh = pm
		spike.material_override = mat if i % 2 == 0 else dark
		spike.position = Vector3(lerpf(-1.45, 1.45, float(i) / (n - 1)) + randf_range(-0.1, 0.1), 0.55 + h * 0.5, randf_range(-0.12, 0.12))
		spike.rotation = Vector3(randf_range(-0.12, 0.12), randf_range(-0.3, 0.3), randf_range(-0.18, 0.18))
		_mesh.add_child(spike)
	for i in 6:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.22, 0.42)
		sm.height = sm.radius * 1.5
		sm.radial_segments = 6
		sm.rings = 3
		rock.mesh = sm
		rock.material_override = dark
		rock.position = Vector3(randf_range(-1.7, 1.7), randf_range(0.2, 0.6), randf_range(-0.7, 0.7))
		rock.rotation = Vector3(randf() * TAU, randf() * TAU, 0)
		_mesh.add_child(rock)
	_mesh.position.y = -2.6
	var tw := create_tween()
	tw.tween_property(_mesh, "position:y", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_base_y = 0.0
	# Eruption: cracked ground, rocks and a ring of dust.
	var vfx := battle.vfx
	var g := global_position
	var across := global_transform.basis.x
	var cr := vfx.decal("crater", g, 2.0, Color(0.12, 0.08, 0.05, 0.75), Color(0.9, 0.55, 0.25), dur + 0.6, func(node: Node3D, k: float) -> void:
		var vis := smoothstep(0.0, 0.03, k) * (1.0 - smoothstep(0.85, 1.0, k))
		(node as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(minf(k * 8.0, 1.0) * 0.7 + 0.3, vis, 0.0, 1.0)))
	cr.rotation.y = rotation.y
	cr.scale = Vector3(2.4, 1, 1.3)
	set_meta("crater", cr)
	vfx.spray("debris", g + Vector3(0, 0.6, 0), 14, dirt.darkened(0.2), 9.0, Vector3.UP, 0.75, 1.0, 1.0)
	for sgn in [-1.0, 1.0]:
		vfx.spray("dust", g + across * sgn * 1.2 + Vector3(0, 0.4, 0), 8, Color(0.6, 0.45, 0.32, 0.75), 4.5, (across * sgn + Vector3.UP * 0.4).normalized(), 0.6, 1.2, 1.0)
	vfx.ring_emit("dust", g + Vector3(0, 0.3, 0), 1.0, 12, Color(0.58, 0.43, 0.3, 0.7), 4.0, 0.5, 1.1, 1.0)
	vfx.shockwave(g, 3.4, Color(0.85, 0.6, 0.35), 0.4, 0.06)
	battle.shake(0.15)


func damage(amount: float) -> void:
	if not active:
		return
	hp -= amount
	_hurt += amount
	if hp <= 0.0:
		crumble()


func smash() -> void:
	if active:
		battle.vfx.text_popup(global_position + Vector3(0, 2.0, 0), "SMASHED!", Color(1.0, 0.5, 0.2), 0.75, 0.7)
		battle.vfx.spray("debris", global_position + Vector3(0, 1.0, 0), 10, Color(0.45, 0.32, 0.22), 12.0, Vector3.UP, 1.0, 1.2, 1.0)
		crumble()


func crumble() -> void:
	if not active:
		return
	active = false
	Audio.play("wall_break")
	var vfx := battle.vfx
	var g := global_position
	vfx.dust(g, 2.5)
	vfx.emit("dust", g + Vector3(0, 0.8, 0), 14, Color(0.55, 0.4, 0.28, 0.8), 4.0, 0.6, 1.0, 1.3)
	vfx.spray("debris", g + Vector3(0, 0.9, 0), 16, Color(0.45, 0.32, 0.22), 7.0, Vector3.UP, 1.1, 1.0, 1.0)
	vfx.ring_emit("dust", g + Vector3(0, 0.3, 0), 1.2, 10, Color(0.58, 0.43, 0.3, 0.6), 3.0, 0.4, 1.0, 1.0)
	var tw := create_tween()
	tw.tween_property(_mesh, "position:y", -2.6, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
	battle.walls.erase(self)


func tick(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	# Runners pushing on the wall: it shudders and sheds dirt.
	if _hurt > 0.0:
		_hurt_fx -= delta
		if _hurt_fx <= 0.0:
			_hurt_fx = 0.25
			var across := global_transform.basis.x
			battle.vfx.emit("dust", global_position + across * randf_range(-1.4, 1.4) + Vector3(0, randf_range(0.4, 1.4), 0), 2, Color(0.58, 0.43, 0.3, 0.6), 1.5, 0.3)
			battle.vfx.emit("debris", global_position + Vector3(0, 1.2, 0), 1, Color(0.45, 0.32, 0.22), 2.5, 0.5, 1.0, 0.6)
		_mesh.position.x = sin(Time.get_ticks_msec() * 0.07) * 0.03 * clampf(_hurt, 0.0, 1.0)
		_hurt = maxf(0.0, _hurt - delta * 40.0)
	if time_left <= 0.0:
		crumble()
