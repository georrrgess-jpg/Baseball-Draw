class_name BuntTrap
extends Node3D
## Bunt Trap: a sticky net on a route that roots and damages the next runners to cross it.

var battle: Battle
var charges := 3
var root_time := 2.0
var damage := 80.0
var _hit: Dictionary = {}
var _disc: MeshInstance3D


func setup(p_battle: Battle, pos: Vector3, p_charges: int, p_root: float, p_damage: float) -> void:
	battle = p_battle
	charges = p_charges
	root_time = p_root
	damage = p_damage
	position = Vector3(pos.x, 0, pos.z)
	_disc = FieldBuilder.make_ring(1.1, Color(0.2, 0.95, 0.8, 0.9), 0.08, 0.35, 12.0)
	add_child(_disc)
	(_disc.material_override as ShaderMaterial).set_shader_parameter("spin", 1.0)


func tick(_delta: float) -> void:
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
			battle.vfx.burst("magic", e.center(), Color(0.2, 0.95, 0.8))
			Audio.play("glove_catch", -6.0)
	if charges <= 0:
		battle.traps.erase(self)
		var tw := create_tween()
		tw.tween_property(_disc, "scale", Vector3(0.01, 1, 0.01), 0.3)
		tw.tween_callback(queue_free)
