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
var _mesh: MeshInstance3D


func setup(p_battle: Battle, pos: Vector3, facing: Vector3, p_hp: float, dur: float) -> void:
	battle = p_battle
	hp = p_hp
	max_hp = p_hp
	time_left = dur
	position = Vector3(pos.x, 0, pos.z)
	rotation.y = atan2(facing.x, facing.z)
	_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(3.4, 1.5, 1.0)
	bm.subdivide_width = 6
	bm.subdivide_height = 3
	_mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(battle.arena.theme.get("dirt", "#b06a3e")).darkened(0.15)
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
	_mesh.material_override = mat
	_mesh.position.y = -0.8
	add_child(_mesh)
	for i in 5:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(0.25, 0.45)
		sm.height = sm.radius * 1.6
		rock.mesh = sm
		rock.material_override = mat
		rock.position = Vector3(randf_range(-1.6, 1.6), randf_range(0.6, 1.0), randf_range(-0.4, 0.4))
		_mesh.add_child(rock)
	var tw := create_tween()
	tw.tween_property(_mesh, "position:y", 0.75, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	battle.vfx.dust(global_position, 2.0)
	battle.shake(0.15)


func damage(amount: float) -> void:
	if not active:
		return
	hp -= amount
	if hp <= 0.0:
		crumble()


func smash() -> void:
	if active:
		battle.vfx.text_popup(global_position + Vector3(0, 2.0, 0), "SMASHED!", Color(1.0, 0.5, 0.2), 1.0)
		crumble()


func crumble() -> void:
	if not active:
		return
	active = false
	Audio.play("wall_break")
	battle.vfx.dust(global_position, 2.5)
	battle.vfx.emit("dust", global_position + Vector3(0, 0.8, 0), 10, Color(0.55, 0.4, 0.28, 0.8), 4.0, 0.6)
	var tw := create_tween()
	tw.tween_property(_mesh, "position:y", -1.0, 0.4)
	tw.tween_callback(queue_free)
	battle.walls.erase(self)


func tick(delta: float) -> void:
	if not active:
		return
	time_left -= delta
	if time_left <= 0.0:
		crumble()
