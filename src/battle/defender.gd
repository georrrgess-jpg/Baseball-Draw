class_name Defender
extends Node3D
## A fielder on the diamond. Auto-targets runners in range and throws baseballs whose
## release is synced to the throw animation. Stats come from data, level, gear,
## traits, run upgrades, position zone, synergies and temporary buffs.

const RELEASE := {"throw": 0.30, "pitch": 0.85, "catch": 0.25, "special": 0.70}

var battle: Battle
var id := ""
var data: Dictionary = {}
var role := ""
var trait_id := ""
var model: CharacterModel
var post := Vector3.ZERO           # assigned position on the field
var zone := ""
var in_position := false
var is_captain := false
var targeting := "first"

# Effective stats (static part recomputed on placement/upgrade changes).
var s_damage := 0.0
var s_interval := 1.0
var s_range := 10.0
var s_throw_speed := 25.0
var s_accuracy := 75.0
var s_crit := 0.05
var s_special_power := 1.0
var s_special_cd := 1.0
var s_boss_damage := 0.0
var aura_radius := 0.0              # Rico's home guard
var ricochet := 0.0                 # from synergies

# Dynamic multipliers set by the battle each frame (auras, cards).
var dyn_damage := 0.0
var dyn_speed := 0.0
var dyn_range := 0.0
var dyn_crit := 0.0
var dyn_ricochet := 0.0

var target: Enemy = null
var attack_cd := 0.5
var throw_count := 0
var stun_t := 0.0
var stun_guard := 0
var _retarget_t := 0.0
var _pending_release := -1.0
var _pending_action := ""
var _pending_payload: Dictionary = {}
var _special_cb: Callable
var _special_t := -1.0
var _dash_state := ""            # "", "out", "back"
var _dash_target: Enemy = null
var _dash_cd := 0.0
var _range_ring: MeshInstance3D
var _select_ring: MeshInstance3D
var _zone_ring: MeshInstance3D
var _captain_badge: Label3D
var _shadow: MeshInstance3D
var selected := false
var show_range := false
var outs := 0
var damage_dealt := 0.0


func setup(p_battle: Battle, defender_id: String, uniform_colors: Dictionary) -> void:
	battle = p_battle
	id = defender_id
	data = DB.defender(id)
	role = data.role
	trait_id = data.get("trait", {}).get("id", "")
	targeting = data.get("targeting", "first")
	model = CharacterModel.new()
	add_child(model)
	var colors := uniform_colors.duplicate()
	colors["Undershirt"] = data.accent
	model.setup(id, {"accent": Color(data.accent), "colors": colors, "cache_key": id, "base": "ready", "scale": Battle.UNIT_SCALE})

	_shadow = Enemy._make_blob_shadow(0.5 * Battle.UNIT_SCALE)
	add_child(_shadow)
	_range_ring = FieldBuilder.make_ring(10.0, Color(data.accent).lightened(0.2), 0.012, 0.05, 48.0)
	_range_ring.visible = false
	add_child(_range_ring)
	_select_ring = FieldBuilder.make_ring(0.85, Color(1.0, 0.85, 0.3, 0.95), 0.12, 0.12)
	_select_ring.visible = false
	add_child(_select_ring)
	_zone_ring = FieldBuilder.make_ring(0.7, Color(0.3, 1.0, 0.6, 0.8), 0.1, 0.0, 10.0)
	_zone_ring.visible = false
	add_child(_zone_ring)
	_captain_badge = Label3D.new()
	_captain_badge.text = "C"
	_captain_badge.font = UITheme.font_display()
	_captain_badge.font_size = 64
	_captain_badge.outline_size = 14
	_captain_badge.modulate = UITheme.GOLD
	_captain_badge.outline_modulate = Color(0.1, 0.05, 0.0)
	_captain_badge.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_captain_badge.no_depth_test = true
	_captain_badge.pixel_size = 0.006
	_captain_badge.position = Vector3(0, model.height + 0.45, 0)
	_captain_badge.visible = false
	add_child(_captain_badge)


func set_captain(v: bool) -> void:
	is_captain = v
	_captain_badge.visible = v


func place(pos: Vector3) -> void:
	post = Vector3(pos.x, 0, pos.z)
	global_position = post
	zone = Field.zone_at(post)
	in_position = zone == DB.roles.get(role, {}).get("zone", "")
	_zone_ring.visible = in_position
	# Face toward the outfield gates by default.
	var to := Vector3(0, 0, -20) - post
	rotation.y = atan2(to.x, to.z)
	recompute()


## Recomputes the static stats from data, permanent progression, run upgrades,
## position zone and synergies.
func recompute() -> void:
	var st: Dictionary = data.stats
	var pm := Profile.defender_mods(id)
	var run: RunState = battle.run
	var dmg_bonus := float(pm.damage) + run.modifier_total("damage") + float(run.defender_bonus.get(id, 0.0))
	var spd_bonus := float(pm.attack_speed) + run.modifier_total("attack_speed")
	var rng_bonus := float(pm.range) + run.modifier_total("range")
	var ts_bonus := float(pm.throw_speed) + run.modifier_total("throw_speed")
	var crit := 0.05 + (float(st.accuracy) + float(pm.accuracy) - 50.0) * 0.002 + float(pm.crit) + run.modifier_total("crit")
	aura_radius = 0.0
	if in_position:
		match role:
			"pitcher":
				dmg_bonus += 0.20
				ts_bonus += 0.15
			"catcher":
				dmg_bonus += 0.15
			"infielder":
				spd_bonus += 0.15
			"outfielder":
				rng_bonus += 0.20
	if trait_id == "home_guard":
		aura_radius = 4.5 * (1.5 if in_position else 1.0)
	var syn: Dictionary = battle.synergy_bonus_for(self)
	spd_bonus += float(syn.get("attack_speed", 0.0))
	rng_bonus += float(syn.get("range", 0.0))
	ricochet = float(syn.get("ricochet", 0.0))
	s_damage = float(st.damage) * (1.0 + dmg_bonus)
	s_interval = float(st.interval) / (1.0 + spd_bonus)
	s_range = float(st.range) * (1.0 + rng_bonus)
	s_throw_speed = float(st.throw_speed) * (1.0 + ts_bonus)
	s_accuracy = clampf(float(st.accuracy) + float(pm.accuracy), 0.0, 100.0)
	s_crit = clampf(crit, 0.0, 0.8)
	s_special_power = float(st.special_power) * (1.0 + float(pm.special_power))
	s_special_cd = float(st.special_cooldown) * (1.0 + float(pm.special_cooldown))
	s_boss_damage = float(pm.boss_damage)
	stun_guard = int(pm.get("stun_guard", 0))
	_range_ring.scale = Vector3(effective_range(), 1, effective_range())


func effective_range() -> float:
	return s_range * (1.0 + dyn_range)


func effective_interval() -> float:
	return s_interval / (1.0 + dyn_speed)


func effective_damage() -> float:
	return s_damage * (1.0 + dyn_damage)


func dps_estimate() -> float:
	return effective_damage() / maxf(effective_interval(), 0.05)


func is_stunned() -> bool:
	return stun_t > 0.0


func stun(time: float) -> void:
	if stun_guard > 0:
		stun_guard -= 1
		battle.vfx.text_popup(global_position + Vector3(0, 2.2, 0), "RESIST!", Color(0.7, 0.9, 1.0), 0.9)
		return
	stun_t = maxf(stun_t, time)
	_pending_release = -1.0
	_dash_state = "back" if _dash_state != "" else ""
	model.stop_action()
	model.play_base("stunned", 0.1)
	battle.vfx.stun_stars(self, time)
	Audio.play("defender_stunned", -4.0)


func cleanse() -> void:
	if stun_t > 0.0:
		stun_t = 0.0
		model.play_base("ready", 0.15)


func set_selected(v: bool) -> void:
	selected = v
	_select_ring.visible = v
	_range_ring.visible = v or show_range


func set_show_range(v: bool) -> void:
	show_range = v
	_range_ring.visible = v or selected


func reset_wave_state() -> void:
	stun_t = 0.0
	stun_guard = int(Profile.defender_mods(id).get("stun_guard", 0))
	_pending_release = -1.0
	_dash_state = ""
	global_position = post
	model.stop_action()
	model.play_base("ready", 0.2)


# ---------------------------------------------------------------- per-frame

func tick(delta: float) -> void:
	if _shadow:
		_shadow.global_position = Vector3(global_position.x, 0.03, global_position.z)
	if stun_t > 0.0:
		stun_t -= delta
		if stun_t <= 0.0:
			model.play_base("ready", 0.2)
		return
	if _special_t >= 0.0:
		_special_t -= delta
		if _special_t < 0.0 and _special_cb.is_valid():
			var cb := _special_cb
			_special_cb = Callable()
			cb.call()
		return
	if _dash_state != "":
		_tick_dash(delta)
		return
	attack_cd -= delta
	_dash_cd -= delta
	_retarget_t -= delta
	if _retarget_t <= 0.0 or target == null or not is_instance_valid(target) or not target.targetable() or not _in_range(target):
		_retarget_t = 0.15
		target = _acquire_target()
	if target:
		_face(target.global_position, delta)
	if _pending_release >= 0.0:
		_pending_release -= delta
		if _pending_release < 0.0:
			_release()
		return
	if trait_id == "quick_hands" and _dash_cd <= 0.0:
		var near := _dash_candidate()
		if near:
			_start_dash(near)
			return
	if target and attack_cd <= 0.0:
		_begin_throw()


func _in_range(e: Enemy) -> bool:
	return Field.v2(e.global_position).distance_to(Field.v2(global_position)) <= effective_range()


func _acquire_target() -> Enemy:
	var best: Enemy = null
	var best_score := -INF
	var r := effective_range()
	var my := Field.v2(global_position)
	for e: Enemy in battle.enemies:
		if not e.targetable():
			continue
		var dist := Field.v2(e.global_position).distance_to(my)
		if dist > r:
			continue
		var score := 0.0
		match targeting:
			"first": score = -e.remaining()
			"last": score = e.remaining()
			"strongest": score = e.hp
			"weakest": score = -e.hp
			"fastest": score = e.base_speed * 10.0 - e.remaining() * 0.1
			"closest": score = -dist
		if e.id == "decoy" and battle.field_vision_active:
			score -= 10000.0
		if score > best_score:
			best_score = score
			best = e
	return best


func _face(pos: Vector3, delta: float) -> void:
	var to := pos - global_position
	if to.length_squared() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), clampf(delta * 12.0, 0.0, 1.0))


func _begin_throw() -> void:
	var interval := effective_interval()
	attack_cd = interval
	throw_count += 1
	var action := "throw"
	var fastball := trait_id == "fastball" and throw_count % 4 == 0
	if fastball and model.has_anim("pitch"):
		action = "pitch"
	var natural := model.anim_length(action)
	# Speed the animation up when the defender throws faster than the clip.
	var speed := maxf(1.0, natural / maxf(interval * 0.92, 0.05))
	if action == "pitch":
		speed = maxf(speed, 1.6)
	model.play_action(action, speed)
	_pending_action = action
	_pending_release = RELEASE.get(action, 0.3) / speed
	_pending_payload = {"fastball": fastball}
	Audio.play("throw", -10.0, 0.1, 70)


func _release() -> void:
	if target == null or not is_instance_valid(target) or not target.targetable():
		target = _acquire_target()
		if target == null:
			return
	var payload := _build_payload(target, bool(_pending_payload.get("fastball", false)))
	battle.projectiles.launch(model.hand_position(), target, s_throw_speed * (1.4 if payload.get("fastball", false) else 1.0), payload)
	# Quick Hands: a second throw at a different runner.
	if trait_id == "quick_hands" and randf() < 0.3:
		var other := _second_target(target)
		if other:
			battle.projectiles.launch(model.hand_position(), other, s_throw_speed, _build_payload(other, false))


func _second_target(exclude: Enemy) -> Enemy:
	var r := effective_range()
	for e: Enemy in battle.enemies:
		if e != exclude and e.targetable() and Field.v2(e.global_position).distance_to(Field.v2(global_position)) <= r:
			return e
	return null


## Builds the damage payload for one throw, applying traits and crits.
func _build_payload(t: Enemy, fastball: bool) -> Dictionary:
	var dmg := effective_damage()
	var crit_mult := 1.75
	var p := {"source": self, "kind": "throw", "accuracy": s_accuracy, "color": Color(data.accent)}
	match trait_id:
		"fastball":
			if fastball:
				dmg *= 2.0
				p.fastball = true
				p.burn = Vector2(12.0, 2.0)
				p.fire = true
		"cannon_arm":
			p.pierce = 0.6
			p.knockback = 0.8
		"precision":
			if Field.v2(t.global_position).distance_to(Field.v2(global_position)) > 10.0:
				dmg *= 1.5
			crit_mult = 2.5
		"heavy_hitter":
			p.splash = 2.0
			p.stun = 0.4
			p.big = true
		"static_charge":
			p.chain = 1
			p.chain_mult = 0.5
		"pickoff_artist":
			if t.hp < t.max_hp * 0.3:
				dmg *= 2.0
		"gap_shooter":
			if t.id in ["sprinter", "jumper"] or t.is_airborne():
				dmg *= 1.4
	if t.is_boss or t.id == "captain":
		dmg *= 1.0 + s_boss_damage
	var crit_chance := s_crit + dyn_crit + t.crit_bonus()
	var crit := randf() < crit_chance
	if crit:
		dmg *= crit_mult
		if battle.synergy_active("fire_and_ice"):
			p.burn = Vector2(8.0, 2.0)
	p.damage = dmg
	p.crit = crit
	var rico := maxf(ricochet, dyn_ricochet)
	if rico > 0.0:
		p.ricochet = rico
	return p


# ---------------------------------------------------------------- Maya's dash-tag

func _dash_candidate() -> Enemy:
	for e: Enemy in battle.enemies:
		if e.targetable() and not e.is_boss and not e.is_airborne() and e.id != "decoy" \
				and Field.v2(e.global_position).distance_to(Field.v2(post)) < 3.5:
			return e
	return null


func _start_dash(e: Enemy) -> void:
	_dash_target = e
	_dash_state = "out"
	_dash_cd = 2.6
	model.play_base("run", 0.08)


func _tick_dash(delta: float) -> void:
	var speed := 9.0
	if _dash_state == "out":
		if _dash_target == null or not is_instance_valid(_dash_target) or not _dash_target.targetable():
			_dash_state = "back"
			return
		var tp := _dash_target.global_position
		_face(tp, delta * 2.0)
		var to := Field.v2(tp) - Field.v2(global_position)
		if to.length() < 0.9:
			model.play_action("catch", 1.6)
			Audio.play("glove_catch", -4.0)
			var dmg := effective_damage() * 2.0
			var dealt := _dash_target.take_damage(dmg, {"source": self, "kind": "tag"})
			battle.on_damage_dealt(self, _dash_target, dealt, false)
			battle.vfx.text_popup(_dash_target.center() + Vector3(0, 0.6, 0), "TAG!", Color(0.4, 1.0, 0.6), 1.0)
			_dash_state = "back"
			model.play_base("run", 0.1)
			return
		var step := to.normalized() * speed * delta
		global_position += Vector3(step.x, 0, step.y)
	else:
		var to := Field.v2(post) - Field.v2(global_position)
		if to.length() < 0.2:
			global_position = post
			_dash_state = ""
			model.play_base("ready", 0.15)
			return
		_face(post, delta * 2.0)
		var step := to.normalized() * minf(speed * delta, to.length())
		global_position += Vector3(step.x, 0, step.y)


# ---------------------------------------------------------------- signature specials

## Plays the special animation and calls on_impact at the impact frame.
func cast_special(on_impact: Callable, face_point := Vector3.INF) -> void:
	_pending_release = -1.0
	if face_point != Vector3.INF:
		var to := face_point - global_position
		rotation.y = atan2(to.x, to.z)
	var speed := 1.3
	model.play_action("special", speed)
	_special_t = RELEASE.special / speed
	_special_cb = on_impact
	attack_cd = maxf(attack_cd, 0.6)


func celebrate() -> void:
	model.play_base("celebrate", 0.2)


func victory() -> void:
	model.play_base("victory" if model.has_anim("victory") else "celebrate", 0.25)
