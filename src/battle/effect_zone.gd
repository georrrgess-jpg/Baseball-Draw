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
var _snow_t := 0.0
var _mist_t := 0.0
var _frost: MeshInstance3D
var _spread := 0.0
var _ending := false
var _shards: Array[MeshInstance3D] = []


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
		_start_frost()


## Frost Field visuals: crystalline frost races outward from the impact point, ice
## spikes burst up, cold mist rolls over the ground until the zone thaws.
func _start_frost() -> void:
	var vfx := battle.vfx
	var c := global_position
	var ice := Color(0.55, 0.88, 1.0)
	_frost = vfx.make_owned("frost")
	add_child(_frost)
	_frost.position = Vector3(0, 0.05, 0)
	_frost.scale = Vector3(radius * 1.08, 1, radius * 1.08)
	_frost.rotation.y = randf() * TAU
	_frost.set_instance_shader_parameter("color", Color(0.72, 0.92, 1.0, 0.95))
	_frost.set_instance_shader_parameter("color2", Color(0.6, 0.95, 1.0, 1.0))
	_frost.set_instance_shader_parameter("anim", Vector4(0, 1, 0, 0))
	vfx.zone_ring(c, radius, Color(0.6, 0.92, 1.0, 0.85), time_left, 0.06, 0.4, 36.0)
	vfx.shockwave(c, radius * 1.25, ice, 0.45, 0.06)
	vfx.emit_one("flash", c + Vector3(0, 0.8, 0), Vector3.ZERO, Color(0.7, 0.92, 1.0, 0.9), 1.6, 1.0)
	vfx.flash_light(c + Vector3(0, 1.5, 0), ice, 5.0, radius * 3.0, 0.5)
	vfx.ring_emit("snow", c + Vector3(0, 0.3, 0), 0.3, 26, Color(0.85, 0.97, 1.0), radius * 2.2, 2.5, 1.2, 0.8)
	vfx.ring_emit("mist", c + Vector3(0, 0.25, 0), 0.4, 10, Color(0.8, 0.93, 1.0, 0.55), radius * 1.4, 0.2, 1.0, 1.0)
	vfx.spray("shard", c + Vector3(0, 0.3, 0), 10, Color.WHITE, 7.0, Vector3.UP, 0.9, 0.7, 0.8)
	vfx.glyph(c + Vector3(0, 2.6, 0), 3, 1.8, Color(0.7, 0.95, 1.0), 1.0, 0.0, 0.5)
	# Ice spikes: a ring near the rim plus a few inside, growing as the frost reaches them.
	var n := 11
	for i in n:
		var a := TAU * i / n + randf_range(-0.2, 0.2)
		var d := radius * (randf_range(0.72, 0.95) if i < 8 else randf_range(0.2, 0.55))
		var pos := c + Vector3(cos(a) * d, 0.0, sin(a) * d)
		var sz := Vector3(randf_range(0.8, 1.15), randf_range(1.4, 2.5), randf_range(0.8, 1.1)) * (1.0 if i < 8 else 0.75)
		var tilt := Vector3(cos(a) * randf_range(0.15, 0.45), randf() * TAU, sin(a) * randf_range(0.15, 0.45))
		var shard := vfx.make_owned("ice_shard")
		add_child(shard)
		shard.global_position = pos
		shard.rotation = Vector3(tilt.z, tilt.y, -tilt.x)
		shard.scale = Vector3(sz.x, 0.01, sz.z)
		shard.set_meta("size", sz)
		shard.set_meta("delay", d / radius * 0.3)
		shard.set_instance_shader_parameter("fade", 1.0)
		shard.set_instance_shader_parameter("tint", Color(0.62, 0.9, 1.0, 1.0))
		_shards.append(shard)


func tick(delta: float) -> void:
	time_left -= delta
	if kind == "frost":
		for e: Enemy in battle.enemies:
			if e.alive and not e.is_airborne() and Field.v2(e.global_position).distance_to(Field.v2(global_position)) <= radius:
				e.zone_slow = maxf(e.zone_slow, slow)
				e.apply_chill(0.6, crit)
		_frost_visuals(delta)
	if time_left <= 0.0:
		_ending = true
		battle.remove_zone(self)
		_thaw()


func _frost_visuals(delta: float) -> void:
	var vfx := battle.vfx
	_spread = minf(1.0, _spread + delta / 0.45)
	if _frost:
		var ease_s := 1.0 - pow(1.0 - _spread, 3.0)
		_frost.set_instance_shader_parameter("anim", Vector4(0, 1, 0, ease_s))
	for s in _shards:
		var age: float = _spread * 0.45 - float(s.get_meta("delay"))
		if age < 0.0:
			continue
		var g := clampf(age / 0.22, 0.0, 1.0)
		var e := 1.0 + 2.70158 * pow(g - 1.0, 3.0) + 1.70158 * pow(g - 1.0, 2.0)
		var sz: Vector3 = s.get_meta("size")
		s.scale = Vector3(sz.x, maxf(sz.y * e, 0.01), sz.z)
		s.position.y = sz.y * e * 0.42
	_snow_t += delta
	if _snow_t > 0.06:
		_snow_t = 0.0
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		vfx.emit("snow", global_position + Vector3(cos(a) * d, randf_range(0.2, 2.2), sin(a) * d), 1, Color(0.85, 0.97, 1.0), 0.6, 0.0, 0.5)
		if randf() < 0.35:
			vfx.emit_one("magic", global_position + Vector3(cos(a) * d * 0.9, 0.15, sin(a) * d * 0.9), Vector3(0, 0.3, 0), Color(0.75, 0.95, 1.0), 0.6, 0.8)
	_mist_t += delta
	if _mist_t > 0.22:
		_mist_t = 0.0
		var a2 := randf() * TAU
		var d2 := sqrt(randf()) * radius * 0.85
		vfx.emit_one("mist", global_position + Vector3(cos(a2) * d2, 0.3, sin(a2) * d2), Vector3(cos(a2), 0.0, sin(a2)) * 0.6, Color(0.82, 0.94, 1.0, 0.35), randf_range(0.8, 1.2), 1.0)


## The zone melts: frost recedes, spikes shatter into shards.
func _thaw() -> void:
	var vfx := battle.vfx
	if kind == "frost":
		for s in _shards:
			if not is_instance_valid(s):
				continue
			var sz: Vector3 = s.get_meta("size")
			vfx.spray("shard", s.global_position + Vector3(0, sz.y * 0.4, 0), 3, Color.WHITE, 4.0, Vector3.UP, 1.0, 0.5, 0.7)
			s.visible = false
		vfx.emit("snow", global_position + Vector3(0, 0.5, 0), 10, Color(0.85, 0.97, 1.0), 3.0, 0.5)
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		if _frost:
			_frost.set_instance_shader_parameter("anim", Vector4(0, v, 0, v)), 1.0, 0.0, 0.35)
	t.tween_callback(queue_free)
