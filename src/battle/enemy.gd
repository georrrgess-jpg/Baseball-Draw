class_name Enemy
extends Node3D
## A hostile runner following a route to home plate. Handles movement, status
## effects (slow, root, stun, freeze, confuse, knockback, burn, marks, magnet),
## class behaviours (sprint bursts, leaps, blinks, auras, bat swings) and bosses.

var battle: Battle
var id := ""
var data: Dictionary = {}
var route: Route
var d := 0.0
var lateral := 0.0
var max_hp := 100.0
var hp := 100.0
var armor := 0.0
var base_speed := 3.0
var evasion := 0.0
var runs := 1
var coins := 0
var is_boss := false
var affix := ""
var alive := true
var model: CharacterModel
var height := 1.8
var spawn_order := 0

# Status
var slows: Dictionary = {}          # source -> [amount, time]
var zone_slow := 0.0                # recomputed every frame by zones / auras
var aura_speed := 1.0               # from captains
var aura_dr := 0.0
var home_guard := false             # inside Rico's aura
var root_t := 0.0
var stun_t := 0.0
var freeze_t := 0.0
var confuse_t := 0.0
var mark_t := 0.0
var mark_amt := 0.0
var burn_dps := 0.0
var burn_t := 0.0
var burn_source: Node = null
var chill_t := 0.0
var chill_crit := 0.0
var armor_break_t := 0.0
var untargetable_t := 0.0
var magnet_t := 0.0
var magnet_center := Vector3.ZERO
var knock_from := 0.0
var knock_t := 0.0
var airborne_t := 0.0
var airborne_len := 0.0
var blocked := false
var vulnerable_t := 0.0

# Behaviour timers
var ability_t := 0.0
var ability_cd := 1.0
var dash_t := 0.0
var leap_from := 0.0
var leap_to := 0.0
var decoy_spawned := false
var telegraph_node: Node3D = null
var telegraph_t := 0.0
var telegraph_kind := ""
var telegraph_pos := Vector3.ZERO
var summon_thresholds := [0.66, 0.33]
var _hp_bar: MeshInstance3D
var _shadow: MeshInstance3D
var _marker: MeshInstance3D
var _anim_state := ""
var _death_t := 0.0
var _last_hit_info: Dictionary = {}
var _burn_tick := 0.0
var _rim_dirty := true
# Status visuals (created on first use; see _update_status_fx).
var _fx_ground: MeshInstance3D
var _fx_head: MeshInstance3D
var _fx_ice: MeshInstance3D
var _fx_cage: MeshInstance3D
var _fx_key := 0
var _ice_k := 0.0
var _cage_k := 0.0
# Hit feedback (cosmetic): squash / flinch, health bar chip trail and pulse, death tumble.
var _hit_k := 0.0
var _hit_dir := Vector3.ZERO        # local space, direction the last hit pushed toward
var _impact_gap := 0.0
var _model_scale := Vector3.ONE
var _bar_chip := 1.0
var _bar_hold := 0.0
var _bar_pulse := 0.0
var _bar_anim := false
var _death_vel := Vector3.ZERO

## Health bar styles: world size of the quad, minimum on-screen width, accent trim, ticks.
const BAR_STYLES := {
	"runner": {"size": Vector2(1.3, 0.24), "min_px": 56.0, "trim": Color(0, 0, 0, 0), "ticks": 10.0, "lift": 0.3},
	"elite": {"size": Vector2(1.6, 0.28), "min_px": 74.0, "trim": Color(1.0, 0.8, 0.3, 1.0), "ticks": 10.0, "lift": 0.35},
	"boss": {"size": Vector2(3.4, 0.44), "min_px": 150.0, "trim": Color(1.0, 0.55, 0.15, 1.0), "ticks": 20.0, "lift": 0.5},
}
static var _bar_mats := {}
static var _bar_meshes := {}


func setup(p_battle: Battle, enemy_id: String, p_route: Route, start_d: float, opts: Dictionary) -> void:
	battle = p_battle
	id = enemy_id
	data = DB.enemy(enemy_id)
	route = p_route
	d = start_d
	lateral = float(opts.get("lateral", 0.0))
	affix = str(opts.get("affix", ""))
	is_boss = bool(data.get("boss", false))
	var hp_mult: float = opts.get("hp_mult", 1.0)
	if is_boss:
		# Bosses have hand-tuned health; they only take part of the inning scaling.
		hp_mult = 1.0 + (hp_mult - 1.0) * 0.45
	var speed_mult: float = opts.get("speed_mult", 1.0)
	max_hp = float(data.hp) * hp_mult
	armor = clampf(float(data.armor) + float(opts.get("armor_add", 0.0)), 0.0, 0.9)
	base_speed = float(data.speed) * speed_mult
	evasion = float(data.evasion)
	runs = int(data.runs)
	coins = int(data.coins)
	for a in DB.elite_affixes:
		if a.id == affix:
			max_hp *= 1.0 + float(a.get("hp", 0.0))
			base_speed *= 1.0 + float(a.get("speed", 0.0))
			armor = clampf(armor + float(a.get("armor", 0.0)), 0.0, 0.9)
			evasion = clampf(evasion + float(a.get("evasion", 0.0)), 0.0, 1.0)
			coins = int(coins * 1.5) + 2
	hp = max_hp
	ability_cd = float(DB.difficulty(battle.run.difficulty_id).get("ability_cd", 1.0))
	ability_t = randf_range(1.5, 3.0) * ability_cd

	model = CharacterModel.new()
	add_child(model)
	var model_id: String = data.get("model", enemy_id)
	model.setup(model_id, {"accent": Color("#FF7A1A"), "body": Color("#2B2F36"), "shadows": is_boss,
		"scale": Battle.UNIT_SCALE * (_fallback_scale() if not CharacterModel.has_model(model_id) else 1.0)})
	height = model.height
	if enemy_id == "decoy":
		model.set_ghost(0.55)
	if affix != "":
		model.set_rim(Color(1.0, 0.2, 0.1, 0.6))

	_shadow = _make_blob_shadow(0.45 * height / 1.8 * 1.1)
	add_child(_shadow)
	# Red ground ring so runners read clearly against the field.
	if enemy_id != "decoy":
		var mcol := Color(1.0, 0.22, 0.15, 0.85) if not is_boss else Color(1.0, 0.5, 0.1, 0.95)
		if bool(Settings.get_value("accessibility", "colorblind", false)):
			mcol = Color(1.0, 0.85, 0.1, 0.95) if not is_boss else Color(0.2, 0.65, 1.0, 1.0)
		_marker = FieldBuilder.make_ring(0.62 * height / 1.8 * 1.15, mcol, 0.16, 0.18)
		add_child(_marker)
	_model_scale = model.scale
	# Health bar: shared material per style, drawn on top, screen-size aware (see shader).
	var style := "boss" if is_boss else ("elite" if affix != "" or id in ["captain", "slugger"] else "runner")
	var bs: Dictionary = BAR_STYLES[style]
	_hp_bar = MeshInstance3D.new()
	_hp_bar.mesh = _bar_mesh(style)
	_hp_bar.material_override = _bar_material(style)
	_hp_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hp_bar.extra_cull_margin = 3.0
	_hp_bar.position = Vector3(0, height + float(bs.lift), 0)
	# Plain runners only show a bar once hurt (less clutter); the first hit pops it in.
	_hp_bar.visible = style != "runner"
	add_child(_hp_bar)
	_update_transform(0.0)
	_set_anim(_move_anim())


func _fallback_scale() -> float:
	return {"swarmer": 0.65, "slugger": 1.35, "iron_slugger": 2.0, "phantom_captain": 1.8, "grand_slammer": 2.3, "captain": 1.1, "armored": 1.1}.get(id, 1.0)


static func _bar_mesh(style: String) -> QuadMesh:
	if not _bar_meshes.has(style):
		var q := QuadMesh.new()
		q.size = BAR_STYLES[style].size
		_bar_meshes[style] = q
	return _bar_meshes[style]


static func _bar_material(style: String) -> ShaderMaterial:
	var cb := bool(Settings.get_value("accessibility", "colorblind", false))
	var key := style + ("_cb" if cb else "")
	if not _bar_mats.has(key):
		var bs: Dictionary = BAR_STYLES[style]
		var m := ShaderMaterial.new()
		m.shader = load("res://assets/shaders/billboard_bar.gdshader")
		m.set_shader_parameter("bar_size", bs.size)
		m.set_shader_parameter("min_px", bs.min_px)
		m.set_shader_parameter("trim_color", bs.trim)
		m.set_shader_parameter("ticks", bs.ticks)
		m.set_shader_parameter("colorblind", cb)
		# Above particles (5-7), below floating text (10).
		m.render_priority = 8
		_bar_mats[key] = m
	return _bar_mats[key]


static func _make_blob_shadow(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2, 2)
	mi.mesh = pm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _blob_texture()
	m.albedo_color = Color(0, 0, 0, 0.55)
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1, radius)
	mi.position.y = 0.03
	return mi


static var _blob_tex: Texture2D
static func _blob_texture() -> Texture2D:
	if _blob_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 1))
		g.set_color(1, Color(0, 0, 0, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_blob_tex = gt
	return _blob_tex


# ---------------------------------------------------------------- queries

func targetable() -> bool:
	return alive and untargetable_t <= 0.0


func is_airborne() -> bool:
	return airborne_t > 0.0


func remaining() -> float:
	return route.length - d


func current_speed() -> float:
	if freeze_t > 0.0 or stun_t > 0.0 or (root_t > 0.0 and not is_airborne()) or magnet_t > 0.0 or blocked or telegraph_t > 0.0:
		return 0.0
	var slow := zone_slow
	for k in slows.keys():
		slow = maxf(slow, float(slows[k][0]))
	slow *= 1.0 - float(data.get("slow_resist", 0.0))
	if is_boss:
		slow *= 0.6
	var s := base_speed * (1.0 - clampf(slow, 0.0, 0.85)) * aura_speed
	if dash_t > 0.0:
		s *= 1.7
	return s


func center() -> Vector3:
	return global_position + Vector3(0, height * 0.55, 0)


func threat_value() -> float:
	return d / maxf(route.length, 1.0)


# ---------------------------------------------------------------- statuses

func apply_slow(source: String, amount: float, time: float) -> void:
	if is_airborne():
		return
	var cur: Array = slows.get(source, [0.0, 0.0])
	slows[source] = [maxf(cur[0], amount), maxf(cur[1], time)]


func apply_stun(time: float) -> void:
	if is_boss:
		time *= 0.35
	stun_t = maxf(stun_t, time)


func apply_root(time: float) -> void:
	if is_airborne():
		return
	if is_boss:
		time *= 0.4
	root_t = maxf(root_t, time)


func apply_freeze(time: float) -> void:
	freeze_t = maxf(freeze_t, time)
	_rim_dirty = true


func apply_confuse(time: float) -> void:
	if is_boss:
		return
	confuse_t = maxf(confuse_t, time)


func apply_mark(time: float, amount: float) -> void:
	mark_t = maxf(mark_t, time)
	mark_amt = maxf(mark_amt, amount)
	_rim_dirty = true


func apply_burn(dps: float, time: float, source: Node) -> void:
	burn_dps = maxf(burn_dps, dps)
	burn_t = maxf(burn_t, time)
	burn_source = source
	_rim_dirty = true


func apply_chill(time: float, crit_bonus: float) -> void:
	chill_t = maxf(chill_t, time)
	chill_crit = maxf(chill_crit, crit_bonus)
	_rim_dirty = true


func apply_armor_break(time: float) -> void:
	armor_break_t = maxf(armor_break_t, time)


func apply_magnet(center_pos: Vector3, time: float) -> void:
	if is_boss:
		time *= 0.3
	magnet_center = center_pos
	magnet_t = maxf(magnet_t, time)


func knockback(amount: float) -> void:
	if is_boss:
		amount *= 0.25
	if amount <= 0.0:
		return
	knock_from = d
	d = maxf(0.0, d - amount)
	knock_t = 0.25


## Crit chance bonus granted to throws against this runner (Frost Field).
func crit_bonus() -> float:
	return chill_crit if chill_t > 0.0 else 0.0


# ---------------------------------------------------------------- damage

## Applies damage after marks, armor and auras. Returns the damage dealt.
func take_damage(amount: float, info: Dictionary = {}) -> float:
	if not alive:
		return 0.0
	if untargetable_t > 0.0 and not info.get("true", false):
		return 0.0
	var mult := 1.0
	var kind: String = info.get("kind", "throw")
	if mark_t > 0.0:
		mult += mark_amt
		if kind == "fire":
			mult += mark_amt
			if battle.run:
				battle.on_curve_heat()
	if home_guard:
		mult += 0.10
	if vulnerable_t > 0.0:
		mult += 0.25
	var arm := armor
	if armor_break_t > 0.0 or vulnerable_t > 0.0:
		arm = 0.0
	arm *= 1.0 - float(info.get("pierce", 0.0))
	var dmg := amount * mult * (1.0 - arm) * (1.0 - aura_dr)
	var before := clampf(hp / max_hp, 0.0, 1.0)
	hp -= dmg
	_last_hit_info = info
	_bar_hit(before, bool(info.get("dot", false)))
	if dmg >= 1.0:
		_hit_feedback(dmg, info)
		if (dmg > max_hp * 0.18 or info.get("crit", false)) and model.action == "" and hp > 0.0 and not is_boss and not is_airborne():
			model.play_action("hit", 1.3)
	if hp <= 0.0:
		die(info)
	elif is_boss:
		_check_summons()
	return dmg


## Cosmetic reaction to a hit: white-hot flash, squash / flinch away from the hit and an
## impact starburst (rate-limited per runner so streams of throws stay readable).
func _hit_feedback(dmg: float, info: Dictionary) -> void:
	var vfx := battle.vfx
	var calm := vfx.reduce_flashes
	if info.get("dot", false):
		model.flash(0.35 * (0.6 if calm else 1.0))
		_hit_k = maxf(_hit_k, 0.25)
		return
	var crit: bool = info.get("crit", false)
	var frac := dmg / maxf(max_hp, 1.0)
	var big: bool = frac >= 0.2 or info.has("card")
	var strength := 1.0 if crit or big else clampf(0.45 + frac * 3.0, 0.45, 1.0)
	model.flash((1.0 if crit or big else 0.85) * (0.55 if calm else 1.0))
	_hit_k = maxf(_hit_k, strength * (0.55 if is_boss else 1.0))
	var dir: Vector3 = info.get("dir", Vector3.ZERO)
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = global_position - vfx.camera_pos()
		dir.y = 0.0
	dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.FORWARD
	_hit_dir = global_transform.basis.inverse() * dir
	if _impact_gap <= 0.0 or crit or big:
		_impact_gap = 0.08
		vfx.hit_impact(info.get("at", center()), dir, info.get("color", Color(1.0, 0.9, 0.7)), strength, crit, big)


func _bar_hit(before: float, dot: bool) -> void:
	if not _hp_bar.visible:
		_hp_bar.visible = true
		_bar_pulse = 1.0
		_bar_chip = before
	_bar_chip = maxf(_bar_chip, before)
	_bar_hold = 0.3
	_bar_pulse = maxf(_bar_pulse, 0.35 if dot else 1.0)
	_hp_bar.set_instance_shader_parameter("fill", clampf(hp / max_hp, 0.0, 1.0))
	_bar_anim = true


## Chip trail drains after a short hold; the pulse decays.
func _tick_bar(delta: float) -> void:
	if not _bar_anim:
		return
	var f := clampf(hp / max_hp, 0.0, 1.0)
	_bar_pulse = maxf(0.0, _bar_pulse - delta * 4.5)
	if _bar_hold > 0.0:
		_bar_hold -= delta
	else:
		_bar_chip = move_toward(_bar_chip, f, delta * (0.5 + 2.0 * (_bar_chip - f)))
	_hp_bar.set_instance_shader_parameter("chip", _bar_chip)
	_hp_bar.set_instance_shader_parameter("pulse", _bar_pulse)
	if _bar_pulse <= 0.0 and _bar_chip <= f:
		_bar_anim = false


## Squash and lean away from the last hit, springing back over ~0.2 s.
func _tick_hit(delta: float) -> void:
	_impact_gap -= delta
	if _hit_k <= 0.0:
		return
	_hit_k = maxf(0.0, _hit_k - delta * 5.0)
	var q := _hit_k * _hit_k
	model.scale = _model_scale * Vector3(1.0 + 0.2 * q, 1.0 - 0.22 * q, 1.0 + 0.2 * q)
	model.position = _hit_dir * 0.28 * q
	model.rotation = Vector3(_hit_dir.z * 0.45 * q, 0.0, -_hit_dir.x * 0.45 * q)


func die(info: Dictionary = {}) -> void:
	if not alive:
		return
	alive = false
	hp = 0.0
	_clear_telegraph()
	_hp_bar.visible = false
	# Knocked back along the last hit, with a small hop (see _tick_death).
	var kd := global_transform.basis * _hit_dir
	if kd.length_squared() < 0.0001:
		kd = global_position - battle.vfx.camera_pos()
		kd.y = 0.0
	_death_vel = kd.normalized() * (1.2 if is_boss else 4.0) if kd.length_squared() > 0.0001 else Vector3.ZERO
	model.flash(0.6 if battle.vfx.reduce_flashes else 1.0)
	if _marker:
		_marker.visible = false
	model.set_rim(Color(0, 0, 0, 0))
	model.freeze_animation(false)
	_clear_status_fx()
	model.play_action("defeat", 1.0)
	_death_t = 0.0
	battle.on_enemy_out(self, info)


# ---------------------------------------------------------------- per-frame

func tick(delta: float) -> void:
	if not alive:
		_death_t += delta
		_tick_hit(delta)
		_tick_death(delta)
		if _death_t > 1.3:
			position.y -= delta * 1.2
			_shadow.visible = false
		if _death_t > 2.3:
			queue_free()
		return
	_tick_status(delta)
	if not alive:
		return
	_tick_behavior(delta)
	_move(delta)
	_update_visuals()
	_update_status_fx(delta)
	_tick_hit(delta)
	_tick_bar(delta)


## Out: the runner is knocked back with a hop, falls (defeat animation), then shrinks away.
func _tick_death(delta: float) -> void:
	if _death_t < 0.45 and _death_vel != Vector3.ZERO:
		global_position += _death_vel * delta
		_death_vel *= maxf(0.0, 1.0 - delta * 6.0)
		var hop := sin(clampf(_death_t / 0.45, 0.0, 1.0) * PI) * (0.15 if is_boss else 0.45)
		model.position.y = hop
	elif _death_t > 1.05 and hp <= 0.0:
		var k := clampf((_death_t - 1.05) / 0.6, 0.0, 1.0)
		model.scale = _model_scale * maxf(0.001, 1.0 - k * k)
		if k >= 1.0:
			model.visible = false


func _tick_status(delta: float) -> void:
	for k in slows.keys():
		slows[k][1] -= delta
		if slows[k][1] <= 0.0:
			slows.erase(k)
	stun_t = maxf(0.0, stun_t - delta)
	root_t = maxf(0.0, root_t - delta)
	var was_frozen := freeze_t > 0.0
	freeze_t = maxf(0.0, freeze_t - delta)
	if was_frozen and freeze_t <= 0.0:
		_rim_dirty = true
	confuse_t = maxf(0.0, confuse_t - delta)
	if mark_t > 0.0:
		mark_t -= delta
		if mark_t <= 0.0:
			mark_amt = 0.0
			_rim_dirty = true
	if chill_t > 0.0:
		chill_t -= delta
		if chill_t <= 0.0:
			_rim_dirty = true
	armor_break_t = maxf(0.0, armor_break_t - delta)
	untargetable_t = maxf(0.0, untargetable_t - delta)
	magnet_t = maxf(0.0, magnet_t - delta)
	dash_t = maxf(0.0, dash_t - delta)
	if vulnerable_t > 0.0:
		vulnerable_t -= delta
		if vulnerable_t <= 0.0:
			_rim_dirty = true
	if burn_t > 0.0:
		burn_t -= delta
		_burn_tick += delta
		if _burn_tick >= 0.5:
			_burn_tick = 0.0
			var dealt := take_damage(burn_dps * 0.5, {"kind": "fire", "source": burn_source, "dot": true})
			if dealt > 0.0:
				# No number for damage over time: the flames flare up on each tick instead.
				battle.vfx.burn_tick(center())
				if burn_source and is_instance_valid(burn_source) and battle.run:
					battle.run.add_damage(burn_source.id, dealt)
		if burn_t <= 0.0:
			burn_dps = 0.0
			_rim_dirty = true


func _move(delta: float) -> void:
	var speed := current_speed()
	if magnet_t > 0.0:
		# Dragged toward the magnet centre along the route.
		var proj: Dictionary = route.project(magnet_center)
		d = move_toward(d, float(proj.d), 6.0 * delta)
		lateral = move_toward(lateral, 0.0, 2.0 * delta)
	elif airborne_t > 0.0:
		airborne_t -= delta
		var k := 1.0 - airborne_t / maxf(airborne_len, 0.01)
		d = lerpf(leap_from, leap_to, k)
		if airborne_t <= 0.0:
			battle.vfx.dust(global_position, 1.0)
	elif knock_t > 0.0:
		knock_t -= delta
	elif confuse_t > 0.0:
		d = maxf(0.0, d - speed * 0.8 * delta)
	else:
		d += speed * delta
	# Walls block runners that are on the ground.
	blocked = false
	if not is_airborne() and freeze_t <= 0.0:
		var ahead := route.position_at(d + 0.7)
		for w in battle.walls:
			if w.active and Field.v2(ahead).distance_to(Field.v2(w.position)) < w.radius:
				blocked = true
				if id in ["slugger", "iron_slugger", "grand_slammer"]:
					w.smash()
					blocked = false
				else:
					w.damage(30.0 * delta * (2.0 if id == "armored" else 1.0))
				break
	if d >= route.length:
		battle.on_enemy_reached_home(self)
		return
	_update_transform(delta)


func _update_transform(delta: float) -> void:
	var pos := route.position_at(d)
	var dir := route.direction_at(d)
	var side := Vector3(-dir.z, 0, dir.x)
	# Runners converge onto the base path as they approach home.
	var lat := lateral * clampf(remaining() / 6.0, 0.0, 1.0)
	pos += side * lat
	if airborne_t > 0.0:
		var k := 1.0 - airborne_t / maxf(airborne_len, 0.01)
		pos.y = sin(k * PI) * 2.0
	global_position = pos
	var face := -dir if confuse_t > 0.0 else dir
	var target_yaw := atan2(face.x, face.z)
	if delta <= 0.0:
		rotation.y = target_yaw
	else:
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 10.0, 0.0, 1.0))
	if _shadow:
		_shadow.global_position = Vector3(pos.x, 0.03, pos.z)
	if _marker:
		_marker.global_position = Vector3(pos.x, 0.05, pos.z)


func _move_anim() -> String:
	if stun_t > 0.0:
		return "stunned"
	var spd := current_speed()
	if spd <= 0.05:
		return "idle"
	if base_speed < 1.9 and model.has_anim("walk"):
		return "walk"
	if id == "sprinter" and model.has_anim("sprint"):
		return "sprint"
	return "run"


func _update_visuals() -> void:
	var frozen := freeze_t > 0.0
	model.freeze_animation(frozen)
	if not frozen and model.action == "":
		var a := _move_anim()
		if a != _anim_state:
			_anim_state = a
			model.play_base(a, 0.15)
		var spd := current_speed()
		var stride := 3.4 * height / 1.8
		if a == "walk":
			stride = 1.6 * height / 1.8
		model.set_base_speed(clampf(spd / maxf(stride, 0.1) * (0.7 if a != "walk" else 1.0), 0.35, 2.4) if a in ["run", "sprint", "walk"] else 1.0)
	if _rim_dirty:
		_rim_dirty = false
		var rim := Color(0, 0, 0, 0)
		if affix != "":
			rim = Color(1.0, 0.2, 0.1, 0.5)
		if mark_t > 0.0:
			rim = Color(0.65, 0.4, 1.0, 0.9)
		if chill_t > 0.0:
			rim = Color(0.45, 0.85, 1.0, 0.9)
		if burn_t > 0.0:
			rim = Color(1.0, 0.45, 0.1, 0.95)
		if vulnerable_t > 0.0:
			rim = Color(1.0, 0.8, 0.2, 1.0)
		if frozen:
			rim = Color(0.6, 0.9, 1.0, 1.0)
		if id != "decoy" and untargetable_t <= 0.0:
			model.set_rim(rim)


# ---------------------------------------------------------------- status visuals

const SLOW_COLORS := {"curveball": Color(0.62, 0.45, 1.0), "changeup": Color(0.5, 0.55, 1.0), "shadow": Color(0.72, 0.3, 1.0),
	"lockdown": Color(0.35, 0.68, 1.0)}


## Readable status markers that outlive the card's impact: a shackle / slow / frost /
## magnet ring at the feet, stars / ? / reticle over the head, an ice block while
## frozen, a cage of light while rooted, flames while burning.
func _update_status_fx(delta: float) -> void:
	var vfx := battle.vfx
	var rooted := root_t > 0.0 and not is_airborne()
	var slowed := not slows.is_empty()
	var chilled := chill_t > 0.0
	var magnet := magnet_t > 0.0
	var stunned := stun_t > 0.0
	var confused := confuse_t > 0.0
	var marked := mark_t > 0.0
	var broken := armor_break_t > 0.0
	var frozen := freeze_t > 0.0
	var key := int(rooted) | int(slowed) << 1 | int(chilled) << 2 | int(magnet) << 3 | int(stunned) << 4 \
		| int(confused) << 5 | int(marked) << 6 | int(broken) << 7 | int(frozen) << 8
	if key != _fx_key:
		_fx_key = key
		var ground := rooted or slowed or chilled or magnet
		if ground and _fx_ground == null:
			_fx_ground = vfx.make_status_ground()
			add_child(_fx_ground)
			var r := 0.62 * height / 1.8 * 1.15 * 1.35
			_fx_ground.scale = Vector3(r, 1, r)
		if _fx_ground:
			_fx_ground.visible = ground
			_fx_ground.set_instance_shader_parameter("st", Vector4(float(rooted), float(slowed), float(chilled), float(magnet)))
			if slowed:
				var sc := Color(0.5, 0.7, 1.0)
				for k in slows.keys():
					sc = SLOW_COLORS.get(k, sc)
				_fx_ground.set_instance_shader_parameter("slow_col", sc)
		var head := stunned or confused or marked or broken
		if head and _fx_head == null:
			_fx_head = vfx.make_status_head()
			add_child(_fx_head)
			var hs := clampf(height / 2.6, 0.8, 2.2)
			# Above the health bar, which grows upward when the camera is far away.
			_fx_head.position = Vector3(0, height + 1.0 * hs + 0.2, 0)
			_fx_head.scale = Vector3(1.5 * hs, 0.75 * hs, 1.0)
		if _fx_head:
			_fx_head.visible = head
			_fx_head.set_instance_shader_parameter("st", Vector4(float(stunned), float(confused), float(marked), float(broken)))
	if _fx_ground and _fx_ground.visible:
		_fx_ground.global_position = Vector3(global_position.x, 0.06, global_position.z)
	# Ice block while frozen.
	var ice_target := 1.0 if frozen else 0.0
	if _ice_k != ice_target:
		_ice_k = move_toward(_ice_k, ice_target, delta * (7.0 if frozen else 3.0))
		if _fx_ice == null and _ice_k > 0.0:
			_fx_ice = vfx.make_ice_shell()
			add_child(_fx_ice)
			_fx_ice.scale = Vector3(height * 0.44, height * 1.02, height * 0.44)
			_fx_ice.rotation.y = randf() * TAU
		if _fx_ice:
			_fx_ice.visible = _ice_k > 0.0
			_fx_ice.set_instance_shader_parameter("fade", _ice_k)
	# Cage of light bars while rooted.
	var cage_target := 1.0 if rooted else 0.0
	if _cage_k != cage_target:
		_cage_k = move_toward(_cage_k, cage_target, delta * (5.0 if rooted else 3.0))
		if _fx_cage == null and _cage_k > 0.0:
			_fx_cage = vfx.make_status_cage()
			add_child(_fx_cage)
			var cr := 0.55 * height / 1.8 * 1.3
			_fx_cage.scale = Vector3(cr, height * 0.8, cr)
			_fx_cage.position = Vector3(0, height * 0.4, 0)
			_fx_cage.set_instance_shader_parameter("color", Color(0.4, 0.75, 1.0, 1.0))
		if _fx_cage:
			_fx_cage.visible = _cage_k > 0.0
			_fx_cage.set_instance_shader_parameter("progress", _cage_k if rooted else 1.0)
			_fx_cage.set_instance_shader_parameter("vis", 1.0 if rooted else _cage_k)
	if burn_t > 0.0:
		vfx.status_burn(global_position, height, delta)
	if chilled and not frozen:
		vfx.status_chill(global_position, height, delta)
	if magnet:
		vfx.status_magnet(global_position, magnet_center - global_position, height, delta)


func _clear_status_fx() -> void:
	for n in [_fx_ground, _fx_head, _fx_ice, _fx_cage]:
		if n:
			n.visible = false
	_fx_key = 0
	_ice_k = 0.0
	_cage_k = 0.0


# ---------------------------------------------------------------- behaviours

func _tick_behavior(delta: float) -> void:
	if freeze_t > 0.0 or stun_t > 0.0:
		return
	ability_t -= delta
	if telegraph_t > 0.0:
		telegraph_t -= delta
		if telegraph_t <= 0.0:
			_resolve_telegraph()
		return
	match data.get("behavior", "basic"):
		"sprinter":
			if ability_t <= 0.0:
				ability_t = randf_range(3.5, 4.5) * ability_cd
				dash_t = 0.9
				battle.vfx.speed_lines(self)
		"jumper":
			if ability_t <= 0.0 and remaining() > 3.0 and magnet_t <= 0.0 and root_t <= 0.0 and confuse_t <= 0.0:
				ability_t = randf_range(3.0, 4.0) * ability_cd
				airborne_len = 0.8
				airborne_t = airborne_len
				leap_from = d
				leap_to = minf(d + 5.5, route.length - 0.5)
				model.play_action("leap", 1.0)
				slows.clear()
				blocked = false
		"trickster":
			if ability_t <= 0.0 and remaining() > 5.0 and confuse_t <= 0.0:
				ability_t = randf_range(4.5, 5.5) * ability_cd
				battle.vfx.puff(center(), Color(0.6, 0.35, 1.0))
				d = minf(d + 4.0, route.length - 1.0)
				untargetable_t = 0.3
				_update_transform(0.0)
				battle.vfx.puff(center(), Color(0.6, 0.35, 1.0))
				Audio.play("shadow_cast", -8.0)
			if not decoy_spawned and hp < max_hp * 0.5:
				decoy_spawned = true
				battle.spawn_enemy("decoy", route, d, {"lateral": lateral + 0.8})
		"slugger":
			if ability_t <= 0.0:
				ability_t = 0.5
				var victim = _nearest_defender(3.6)
				if victim:
					ability_t = 3.0 * ability_cd
					_start_telegraph("swing", global_position, 3.6, 0.55)
		"boss_iron":
			if ability_t <= 0.0:
				ability_t = 8.0 * ability_cd
				_start_telegraph("slam", global_position, 5.0, 1.3)
		"boss_phantom":
			if ability_t <= 0.0:
				ability_t = 7.0 * ability_cd
				_start_telegraph("phase", global_position, 3.0, 0.6)
		"boss_slammer":
			if ability_t <= 0.0:
				ability_t = 1.0
				var victim = _nearest_defender(10.0)
				if victim:
					ability_t = 9.0 * ability_cd
					_start_telegraph("homerun", victim.global_position, 3.6, 1.5)


func _nearest_defender(radius: float) -> Node3D:
	var best: Node3D = null
	var best_d := radius
	for df in battle.defenders:
		var dist := Field.v2(df.global_position).distance_to(Field.v2(global_position))
		if dist < best_d:
			best_d = dist
			best = df
	return best


func _start_telegraph(kind: String, pos: Vector3, radius: float, time: float) -> void:
	telegraph_kind = kind
	telegraph_pos = pos
	telegraph_t = time
	var col := Color(1.0, 0.15, 0.1, 0.9) if kind != "phase" else Color(0.7, 0.4, 1.0, 0.9)
	telegraph_node = battle.vfx.telegraph(pos, radius, col, time)
	match kind:
		"swing", "homerun":
			model.play_action("swing", model.anim_length("swing") / maxf(time + 0.4, 0.1))
			if kind == "homerun":
				Audio.play("boss_warning", -4.0)
				battle.notify("HOME RUN SWING!", Color(1.0, 0.3, 0.2))
				var to := pos - global_position
				rotation.y = atan2(to.x, to.z)
		"slam":
			model.play_action("slam", model.anim_length("slam") / maxf(time + 0.5, 0.1))
			Audio.play("boss_warning", -4.0)
			battle.notify("GROUND SLAM!", Color(1.0, 0.45, 0.1))
		"phase":
			Audio.play("shadow_cast", -2.0)


func _clear_telegraph() -> void:
	telegraph_t = 0.0
	if telegraph_node and is_instance_valid(telegraph_node):
		telegraph_node.queue_free()
	telegraph_node = null


func _resolve_telegraph() -> void:
	var kind := telegraph_kind
	telegraph_kind = ""
	if telegraph_node and is_instance_valid(telegraph_node):
		telegraph_node.queue_free()
	telegraph_node = null
	match kind:
		"swing":
			Audio.play("swing_whoosh")
			_stun_defenders(telegraph_pos, 3.6, 2.0)
			battle.vfx.shockwave(telegraph_pos, 3.6, Color(1.0, 0.4, 0.2))
		"slam":
			Audio.play("boss_slam")
			battle.shake(0.6)
			_stun_defenders(telegraph_pos, 5.0, 2.5)
			battle.vfx.shockwave(telegraph_pos, 5.0, Color(1.0, 0.5, 0.1))
			battle.vfx.dust(telegraph_pos, 3.0)
			vulnerable_t = 4.0
			_rim_dirty = true
			battle.notify("ARMOR CRACKED — ATTACK NOW!", Color(1.0, 0.8, 0.2))
		"phase":
			untargetable_t = 1.6
			model.set_ghost(0.3)
			for i in 3:
				battle.spawn_enemy("decoy", route, minf(d + randf_range(-2.0, 2.0), route.length - 2.0),
					{"lateral": randf_range(-1.6, 1.6), "hp_mult": 1.0})
			get_tree().create_timer(1.6, false).timeout.connect(func() -> void:
				if is_instance_valid(self) and alive:
					model.set_ghost(1.0)
					_rim_dirty = true)
		"homerun":
			Audio.play("bat_crack")
			Audio.play("boss_slam", -3.0)
			battle.shake(0.8)
			_stun_defenders(telegraph_pos, 3.6, 3.0)
			battle.vfx.shockwave(telegraph_pos, 3.6, Color(1.0, 0.75, 0.2))
			battle.vfx.burst("explosion", telegraph_pos + Vector3(0, 0.5, 0), Color(1.0, 0.7, 0.2))


func _stun_defenders(pos: Vector3, radius: float, time: float) -> void:
	for df in battle.defenders:
		if Field.v2(df.global_position).distance_to(Field.v2(pos)) <= radius:
			df.stun(time, global_position)


func _check_summons() -> void:
	if id != "grand_slammer" or summon_thresholds.is_empty():
		return
	if hp / max_hp <= float(summon_thresholds[0]):
		summon_thresholds.pop_front()
		battle.notify("THE GRAND SLAMMER CALLS FOR BACKUP!", Color(1.0, 0.6, 0.2))
		Audio.play("boss_roar")
		for i in 6:
			battle.spawn_enemy("swarmer", route, maxf(0.0, d - 1.5 - i * 0.6), {"lateral": randf_range(-1.5, 1.5)})
		for i in 2:
			battle.spawn_enemy("runner", route, maxf(0.0, d - 2.0 - i), {"lateral": randf_range(-1.2, 1.2)})


func _set_anim(a: String) -> void:
	_anim_state = a
	model.play_base(a, 0.0)
