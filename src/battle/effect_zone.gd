class_name EffectZone
extends Node3D
## Lingering ground effects created by cards (Frost Field) and the shared
## base for walls and traps placed on runner routes.

var battle: Battle
var radius := 3.0
var time_left := 5.0
var kind := ""
var slow := 0.0
var crit := 0.0
var _ring: MeshInstance3D
var _shards: Array[MeshInstance3D] = []
var _snow_t := 0.0


static func frost(p_battle: Battle, pos: Vector3, r: float, dur: float, p_slow: float, p_crit: float) -> EffectZone:
	var z := EffectZone.new()
	z.battle = p_battle
	z.kind = "frost"
	z.radius = r
	z.time_left = dur
	z.slow = p_slow
	z.crit = p_crit
	z.position = Vector3(pos.x, 0, pos.z)
	return z


func _ready() -> void:
	if kind == "frost":
		_ring = battle.vfx.zone_ring(global_position, radius, Color(0.55, 0.9, 1.0, 0.9), time_left, 0.32, 0.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.75, 0.92, 1.0, 0.85)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.08
		mat.metallic_specular = 1.0
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.75, 1.0)
		mat.emission_energy_multiplier = 0.6
		for i in 9:
			var shard := MeshInstance3D.new()
			var pm := PrismMesh.new()
			pm.size = Vector3(randf_range(0.2, 0.45), randf_range(0.5, 1.2), randf_range(0.2, 0.4))
			shard.mesh = pm
			shard.material_override = mat
			var a := randf() * TAU
			var d := sqrt(randf()) * radius * 0.85
			shard.position = Vector3(cos(a) * d, 0.0, sin(a) * d)
			shard.rotation = Vector3(randf_range(-0.4, 0.4), randf() * TAU, randf_range(-0.4, 0.4))
			shard.scale = Vector3(1, 0.01, 1)
			add_child(shard)
			_shards.append(shard)
			var tw := shard.create_tween()
			tw.tween_property(shard, "scale", Vector3.ONE, 0.25).set_delay(i * 0.03).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func tick(delta: float) -> void:
	time_left -= delta
	if kind == "frost":
		for e: Enemy in battle.enemies:
			if e.alive and not e.is_airborne() and Field.v2(e.global_position).distance_to(Field.v2(global_position)) <= radius:
				e.zone_slow = maxf(e.zone_slow, slow)
				e.apply_chill(0.6, crit)
		_snow_t += delta
		if _snow_t > 0.08:
			_snow_t = 0.0
			var a := randf() * TAU
			var d := sqrt(randf()) * radius
			battle.vfx.emit("snow", global_position + Vector3(cos(a) * d, 0.2, sin(a) * d), 1, Color(0.8, 0.95, 1.0), 1.0, 1.2, 0.5)
	if time_left <= 0.0:
		for s in _shards:
			var tw := s.create_tween()
			tw.tween_property(s, "scale", Vector3(1, 0.01, 1), 0.3)
		battle.remove_zone(self)
		var t := create_tween()
		t.tween_interval(0.35)
		t.tween_callback(queue_free)
