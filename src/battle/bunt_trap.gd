class_name BuntTrap
extends Node3D
## Bunt Trap: a sticky net on a route that roots and damages the next runners to cross it.

const COLOR := Color(0.2, 0.95, 0.8)

var battle: Battle
var charges := 3
var root_time := 2.0
var damage := 80.0
var _hit: Dictionary = {}
var _disc: MeshInstance3D
var _ring: MeshInstance3D
var _age := 0.0
var _max_charges := 3
var _snap := 0.0


func setup(p_battle: Battle, pos: Vector3, p_charges: int, p_root: float, p_damage: float) -> void:
	battle = p_battle
	charges = p_charges
	_max_charges = maxi(p_charges, 1)
	root_time = p_root
	damage = p_damage
	position = Vector3(pos.x, 0, pos.z)
	var vfx := battle.vfx
	# Glowing net drawn onto the ground (web decal) inside a spinning ring.
	_disc = vfx.make_owned("web")
	add_child(_disc)
	_disc.position = Vector3(0, 0.06, 0)
	_disc.scale = Vector3(1.25, 1, 1.25)
	_disc.rotation.y = randf() * TAU
	_disc.set_instance_shader_parameter("color", Color(COLOR, 0.95))
	_disc.set_instance_shader_parameter("color2", Color.WHITE)
	_disc.set_instance_shader_parameter("anim", Vector4(0, 1, 0, 0))
	_ring = vfx.make_owned("ring")
	add_child(_ring)
	_ring.position = Vector3(0, 0.065, 0)
	_ring.scale = Vector3(1.3, 1, 1.3)
	_ring.set_instance_shader_parameter("color", Color(COLOR, 0.9))
	_ring.set_instance_shader_parameter("mode", 1.0)
	_ring.set_instance_shader_parameter("params", Vector4(0.07, 0.12, 1.2, 12.0))
	_ring.set_instance_shader_parameter("progress", 1.0)
	vfx.shockwave(global_position, 2.2, COLOR, 0.35, 0.06)
	vfx.ring_emit("magic", global_position + Vector3(0, 0.2, 0), 1.1, 12, COLOR, 1.0, 1.5, 0.8, 0.8)
	vfx.emit_one("flash", global_position + Vector3(0, 0.4, 0), Vector3.ZERO, Color(COLOR, 0.7), 0.7, 0.8)


func tick(_delta: float) -> void:
	_age += _delta
	if _disc:
		var draw_in := minf(_age / 0.35, 1.0)
		_snap = maxf(0.0, _snap - _delta * 3.0)
		var strength := 0.55 + 0.45 * float(charges) / _max_charges
		_disc.set_instance_shader_parameter("anim", Vector4(0, strength + _snap, 0, draw_in))
		_disc.scale = Vector3.ONE * (1.25 - 0.25 * _snap)
	for e: Enemy in battle.enemies:
		if charges <= 0:
			break
		if not e.alive or e.is_airborne() or _hit.has(e.get_instance_id()):
			continue
		if Field.v2(e.global_position).distance_to(Field.v2(global_position)) < 1.1:
			_hit[e.get_instance_id()] = true
			charges -= 1
			e.apply_root(root_time)
			battle.deal_damage(e, damage, {"kind": "trap", "card": "bunt_trap"})
			_spring(e)
			Audio.play("glove_catch", -6.0)
	if charges <= 0:
		battle.traps.erase(self)
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			if _disc:
				_disc.set_instance_shader_parameter("anim", Vector4(0, v, 0, 1.0))
			if _ring:
				_ring.set_instance_shader_parameter("progress", v), 1.0, 0.0, 0.35)
		tw.tween_callback(queue_free)


## The net springs up around the runner.
func _spring(e: Enemy) -> void:
	var vfx := battle.vfx
	_snap = 1.0
	vfx.burst("magic", e.center(), COLOR)
	vfx.emit_one("flash", e.center(), Vector3.ZERO, Color(COLOR, 0.8), 0.8, 0.8)
	vfx.shockwave(global_position, 1.8, COLOR, 0.3, 0.07, 0.0, true)
	var feet := Vector3(e.global_position.x, 0.2, e.global_position.z)
	for i in 4:
		var a := TAU * i / 4.0 + randf() * 0.5
		var from := feet + Vector3(cos(a), 0, sin(a)) * 1.1
		vfx.ribbon(vfx.arc_points(from, e.center(), 0.5, 8), COLOR, 0.07, 0.4)
