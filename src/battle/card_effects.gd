class_name CardEffects
extends RefCounted
## Executes ability cards. Linked cards are cast by their defender (special animation,
## power/cooldown from that defender's stats); without the defender on the field they
## fire from home plate at 75% power.

var battle: Battle

## Cards that resolve instantly (no caster wind-up): they get a cast acknowledgement pop.
const DIRECT_CARDS := ["grand_slam_barrage", "shadow_change", "time_out", "changeup", "frost_field", "wall_of_dirt",
	"base_shield", "bunt_trap", "field_vision", "diamond_aura", "rally_cry", "magnet_glove", "seventh_inning_stretch",
	"tag_at_the_plate", "bullpen_call", "hot_corner", "perfect_game"]
const GOLD := Color(1.0, 0.82, 0.3)
const TAG_TEAL := Color(0.35, 1.0, 0.85)


func _init(p_battle: Battle) -> void:
	battle = p_battle


func p(card_id: String, key: String, level: int) -> float:
	return DB.card_param(card_id, key, level)


func control_mult() -> float:
	return 1.0 + battle.run.modifier_total("control_duration")


## Returns the casting defender for a linked card (or null) and the power multiplier.
func caster_info(card_id: String) -> Dictionary:
	var linked: String = DB.card(card_id).get("linked", "")
	if linked != "":
		for df: Defender in battle.defenders:
			if df.id == linked and not df.is_stunned():
				return {"caster": df, "power": df.s_special_power, "cd": df.s_special_cd, "linked": true}
		return {"caster": null, "power": 0.75, "cd": 1.0, "linked": true}
	return {"caster": null, "power": 1.0, "cd": 1.0, "linked": false}


func nearest_thrower(pos: Vector3) -> Defender:
	var best: Defender = null
	var best_d := INF
	for df: Defender in battle.defenders:
		if df.is_stunned():
			continue
		var dd := Field.v2(df.global_position).distance_to(Field.v2(pos))
		if dd < best_d:
			best_d = dd
			best = df
	return best


func _origin(df: Defender) -> Vector3:
	if df:
		return df.model.hand_position()
	return Field.HOME + Vector3(0, 1.5, 0)


## Runs the card. target: {point: Vector3, enemy: Enemy, defender: Defender}.
## Visuals come from battle.vfx.cards (fx); they never change what the card does.
func execute(card_id: String, level: int, target: Dictionary) -> void:
	var fx = battle.vfx.cards
	var info := caster_info(card_id)
	var caster: Defender = info.caster
	var power: float = info.power
	var point: Vector3 = target.get("point", Field.HOME)
	Audio.play("card_play", -4.0)
	if card_id in DIRECT_CARDS:
		fx.cast_ack(card_id, _ack_point(card_id, target, point))
	match card_id:
		"heat_wave":
			var origin := caster.global_position if caster else Field.HOME
			var run_fire := func() -> void:
				var dir := (point - origin)
				dir.y = 0
				dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, -1)
				var length := p(card_id, "length", level)
				var width := p(card_id, "width", level)
				var end := origin + dir * length
				fx.heat_wave(origin, end, width, 1.4)
				Audio.play("fire_cast")
				battle.shake(0.2)
				var hits := 0
				for e: Enemy in battle.enemies.duplicate():
					if not e.targetable():
						continue
					var rel := e.global_position - origin
					var s := rel.dot(dir)
					var lat := absf(rel.dot(Vector3(-dir.z, 0, dir.x)))
					if s >= -0.5 and s <= length and lat <= width * 0.5 + 0.4:
						hits += 1
						battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "fire", "card": card_id})
						if e.alive:
							e.apply_burn(p(card_id, "burn_dps", level) * power, p(card_id, "burn_time", level), caster)
				if hits == 0:
					fx.fizzle(origin.lerp(end, 0.6))
			_cast(caster, run_fire, point, "special", card_id)

		"power_throw":
			var e: Enemy = target.get("enemy")
			if e == null:
				return
			var df := nearest_thrower(e.global_position)
			var last_pos := e.center()
			var go := func() -> void:
				if not is_instance_valid(e) or not e.targetable():
					fx.lost_throw(_origin(df), last_pos, Color(1.0, 0.85, 0.4))
					return
				battle.projectiles.launch(_origin(df), e, 42.0, {"source": df, "card": card_id, "damage": p(card_id, "damage", level),
					"knockback": p(card_id, "knockback", level), "accuracy": 200.0, "big": true, "color": Color(1.0, 0.85, 0.4), "crit": true,
					"fx": "power", "trail": "comet"})
				fx.power_release(_origin(df), e.center())
				Audio.play("bat_crack", -6.0)
			_cast(df, go, e.global_position, "throw", card_id)

		"splitter":
			var df := nearest_thrower(point)
			var go := func() -> void:
				battle.projectiles.launch_at(_origin(df), point + Vector3(0, 3.5, 0), 26.0, {"color": Color(0.9, 0.95, 1.0), "big": true, "trail": "comet"},
					func(at: Vector3) -> void:
						fx.splitter_burst(at, point)
						var victims := battle.enemies_in_radius(point, float(DB.card(card_id).get("radius", 5.0)))
						if victims.is_empty():
							fx.fizzle(point)
						var n := int(p(card_id, "balls", level)) + (1 if battle.buff_active("twin_play") else 0)
						for i in n:
							if victims.is_empty():
								battle.projectiles.launch_at(at, point + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 18.0, {"arc_mult": 0.3, "color": Color(0.7, 0.9, 1.0), "trail": "comet"}, func(x: Vector3) -> void: fx.ball_impact("split", x, Color(0.7, 0.9, 1.0)))
								continue
							var v: Enemy = victims[i % victims.size()]
							battle.projectiles.launch(at, v, 20.0, {"source": df, "card": card_id, "damage": p(card_id, "damage", level), "accuracy": 200.0, "color": Color(0.7, 0.9, 1.0), "arc_mult": 0.3,
								"fx": "split", "trail": "comet"}))
			_cast(df, go, point, "throw", card_id)

		"grand_slam_barrage":
			Audio.play("rally_horn", -6.0)
			battle.notify("GRAND SLAM BARRAGE!", Color(1.0, 0.6, 0.2))
			var r := float(DB.card(card_id).get("radius", 6.0))
			var balls := int(p(card_id, "balls", level))
			fx.barrage_start(point, r, 2.9)
			for i in balls:
				var delay := 0.25 + i * (2.4 / balls)
				battle.get_tree().create_timer(delay, false).timeout.connect(func() -> void:
					if not is_instance_valid(battle):
						return
					var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * r
					var land := point + Vector3(off.x, 0, off.y)
					var from := land + Vector3(randf_range(-6, 6), 26.0, randf_range(4, 10))
					fx.barrage_mark(land, clampf(from.distance_to(land) / 34.0, 0.08, 3.0))
					battle.projectiles.launch_at(from, land, 34.0, {"fire": true, "big": true, "arc_mult": 0.0, "trail": "fire"}, func(at: Vector3) -> void:
						fx.barrage_impact(at)
						Audio.play("barrage_impact", -6.0, 0.1, 60)
						battle.shake(0.12)
						for e: Enemy in battle.enemies_in_radius(at, 2.0):
							battle.deal_damage(e, p(card_id, "damage", level), {"kind": "fire", "card": card_id})
							if e.alive:
								e.apply_stun(p(card_id, "stun", level))))

		"grand_relay":
			var go := func() -> void:
				var chain: Array = battle.defenders.duplicate()
				if caster:
					chain.erase(caster)
					chain.push_front(caster)
				var prev: Vector3 = _origin(caster)
				for i in chain.size():
					var df: Defender = chain[i]
					var pos: Vector3 = df.model.chest_position()
					var dl := i * 0.08
					var ground := df.global_position
					battle.get_tree().create_timer(dl, false).timeout.connect(func() -> void:
						fx.relay_link(prev, pos, ground))
					prev = pos
				var dmg := p(card_id, "damage", level) * power * (1.0 + float(DB.card(card_id).params.per_defender) * chain.size())
				var count := int(p(card_id, "targets", level)) + (1 if battle.buff_active("twin_play") else 0)
				var targets := battle.lead_runners(count)
				var last := prev
				battle.get_tree().create_timer(chain.size() * 0.08 + 0.1, false).timeout.connect(func() -> void:
					Audio.play("lightning_zap", -4.0)
					if targets.is_empty():
						fx.fizzle(last, "NO RUNNERS")
					for e: Enemy in targets:
						if is_instance_valid(e) and e.targetable():
							fx.relay_strike(last, e.center())
							battle.deal_damage(e, dmg, {"source": caster, "kind": "relay", "card": card_id}))
			_cast(caster, go, point, "special", card_id)

		"power_catch":
			var r := float(DB.card(card_id).get("radius", 3.0))
			var go := func() -> void:
				fx.power_catch_throw(point, r, clampf(_origin(caster).distance_to(point) / 20.0, 0.08, 3.0))
				battle.projectiles.launch_at(_origin(caster), point, 20.0, {"big": true, "arc_mult": 2.2, "color": Color(0.7, 0.4, 1.0), "trail": "heavy"}, func(at: Vector3) -> void:
					Audio.play("boss_slam", -6.0)
					battle.shake(0.35)
					fx.power_catch_impact(point, r)
					if battle.enemies_in_radius(point, r).is_empty():
						fx.fizzle(point)
					for e: Enemy in battle.enemies_in_radius(point, r):
						battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "slam", "card": card_id})
						if e.alive:
							e.apply_stun(p(card_id, "stun", level) * control_mult())
							e.apply_armor_break(p(card_id, "armor_break", level)))
			_cast(caster, go, point, "special", card_id)

		"thunderbolt":
			var e: Enemy = target.get("enemy")
			if e == null:
				return
			var last_pos := e.center()
			var go := func() -> void:
				if not is_instance_valid(e) or not e.targetable():
					fx.chain_arc(_origin(caster), last_pos, Color(1.0, 0.92, 0.4))
					fx.fizzle(last_pos, "NO TARGET")
					return
				Audio.play("lightning_zap")
				var from := _origin(caster)
				fx.thunderbolt(from, e.center())
				battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "lightning", "card": card_id})
				var payload := {"source": caster, "card": card_id, "damage": p(card_id, "damage", level) * power, "chain": int(p(card_id, "chains", level)) + (1 if battle.buff_active("twin_play") else 0),
					"chain_mult": p(card_id, "falloff", level), "chained": [e]}
				battle.projectiles.hit_chain_continue(e, payload, e.center())
			_cast(caster, go, e.global_position, "special", card_id)

		"curveball":
			var r := float(DB.card(card_id).get("radius", 3.5))
			var df := nearest_thrower(point)
			var go := func() -> void:
				battle.projectiles.launch_at(_origin(df), point + Vector3(0, 0.5, 0), 24.0, {"color": Color(0.5, 0.6, 1.0), "arc_mult": 1.6, "trail": "spiral"}, func(_at: Vector3) -> void:
					fx.curveball_impact(point, r)
					Audio.play("shadow_cast", -8.0)
					if battle.enemies_in_radius(point, r).is_empty():
						fx.fizzle(point)
					for e: Enemy in battle.enemies_in_radius(point, r):
						var dur := p(card_id, "duration", level) * control_mult()
						e.apply_slow("curveball", p(card_id, "slow", level), dur)
						e.apply_mark(dur, p(card_id, "vulnerability", level))
						battle.vfx.burst("magic", e.center(), Color(0.65, 0.5, 1.0)))
			_cast(df, go, point, "throw", card_id)

		"knuckleball":
			var e: Enemy = target.get("enemy")
			if e == null:
				return
			var df := nearest_thrower(e.global_position)
			var last_pos := e.center()
			var go := func() -> void:
				if not is_instance_valid(e) or not e.targetable():
					fx.lost_throw(_origin(df), last_pos, Color(0.8, 0.6, 1.0), "wobble")
					return
				battle.projectiles.launch_at(_origin(df), e.center(), 18.0, {"color": Color(0.8, 0.6, 1.0), "arc_mult": 1.2, "trail": "wobble"}, func(at: Vector3) -> void:
					fx.ball_impact("knuckle", at, Color(0.8, 0.6, 1.0))
					if is_instance_valid(e) and e.alive:
						battle.deal_damage(e, p(card_id, "damage", level), {"source": df, "kind": "throw", "card": card_id})
						if e.alive and not e.is_boss:
							e.apply_confuse(p(card_id, "confuse", level) * control_mult())
							battle.vfx.text_popup(e.center() + Vector3(0, 1.2, 0), "CONFUSED!", Color(0.85, 0.65, 1.0), 0.9, 1.0)
						elif e.is_boss:
							fx.fizzle(e.center() + Vector3(0, 0.6, 0), "IMMUNE"))
			_cast(df, go, e.global_position, "throw", card_id)

		"shadow_change":
			var r := float(DB.card(card_id).get("radius", 5.0))
			Audio.play("shadow_cast")
			fx.shadow_change(point, r)
			if battle.enemies_in_radius(point, r).is_empty():
				fx.fizzle(point)
			for e: Enemy in battle.enemies_in_radius(point, r):
				fx.shadow_victim(e)
				battle.deal_damage(e, p(card_id, "damage", level), {"kind": "shadow", "card": card_id})
				if e.alive:
					e.knockback(p(card_id, "pushback", level))
					e.apply_slow("shadow", p(card_id, "slow", level), p(card_id, "duration", level) * control_mult())

		"time_out":
			Audio.play("time_out_whistle")
			battle.notify("TIME OUT!", Color(0.6, 0.9, 1.0))
			battle.hud_flash(Color(0.5, 0.85, 1.0, 0.25))
			fx.time_out(p(card_id, "freeze", level) * control_mult())
			for e: Enemy in battle.enemies:
				if e.alive:
					e.apply_freeze((p(card_id, "boss_freeze", level) if e.is_boss else p(card_id, "freeze", level)) * control_mult())
					fx.time_out_victim(e)

		"changeup":
			Audio.play("frost_cast", -6.0)
			battle.notify("CHANGEUP!", Color(0.6, 0.6, 1.0))
			fx.changeup()
			for e: Enemy in battle.enemies:
				if e.alive:
					e.apply_slow("changeup", p(card_id, "slow", level), p(card_id, "duration", level) * control_mult())
					fx.changeup_victim(e)

		"pickoff":
			var e: Enemy = target.get("enemy")
			if e == null:
				return
			var last_pos := e.center()
			var go := func() -> void:
				if not is_instance_valid(e) or not e.targetable():
					fx.pickoff_strike(_origin(caster), last_pos, false)
					fx.fizzle(last_pos, "NO TARGET")
					return
				var picked: bool = not e.is_boss and e.hp <= e.max_hp * p(card_id, "threshold", level) * power
				fx.pickoff_strike(_origin(caster), e.center(), picked)
				if not picked:
					fx.fizzle(e.center() + Vector3(0, 0.6, 0), "IMMUNE" if e.is_boss else "SAFE!")
				if picked:
					battle.vfx.text_popup(e.center() + Vector3(0, 0.8, 0), "PICKED OFF!", Color(0.2, 1.0, 0.8), 0.8, 0.7)
					e.die({"source": caster, "kind": "pickoff", "card": card_id})
				else:
					battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "throw", "card": card_id})
				Audio.play("glove_catch")
			if caster:
				fx.lock_on(e, Defender.RELEASE.special / 1.3, Color(0.2, 1.0, 0.8))
			_cast(caster, go, e.global_position, "special", card_id)

		"lockdown":
			var r := float(DB.card(card_id).get("radius", 3.5))
			var go := func() -> void:
				var root := p(card_id, "root", level) * power * control_mult()
				if Field.v2(point).distance_to(Field.v2(Field.HOME)) < 7.0:
					root += p(card_id, "home_bonus", level)
				Audio.play("magnet_pull", -4.0)
				fx.lockdown(point, r, root)
				if battle.enemies_in_radius(point, r).is_empty():
					fx.fizzle(point)
				for e: Enemy in battle.enemies_in_radius(point, r):
					e.apply_root(root)
					e.apply_slow("lockdown", p(card_id, "slow", level), root + p(card_id, "slow_time", level))
					fx.lockdown_victim(e)
			_cast(caster, go, point, "special", card_id)

		"frost_field":
			var r := float(DB.card(card_id).get("radius", 4.0))
			var dur := p(card_id, "duration", level) * control_mult()
			Audio.play("frost_cast")
			battle.add_zone(EffectZone.frost(battle, point, r, dur, p(card_id, "slow", level), p(card_id, "crit_bonus", level)))

		"wall_of_dirt":
			Audio.play("earth_rumble")
			battle.add_wall(target.get("point", point), p(card_id, "hp", level), p(card_id, "duration", level) * control_mult())

		"base_shield":
			fx.base_shield()
			if battle.run.shields >= 3:
				fx.fizzle(Field.HOME + Vector3(0, 2.0, 0), "SHIELDS FULL")
			battle.add_shield(int(p(card_id, "shields", level)))

		"bunt_trap":
			fx.bunt_trap_cast(battle.snap_to_route(target.get("point", point)).point)
			battle.add_trap(target.get("point", point), int(p(card_id, "charges", level)), p(card_id, "root", level) * control_mult(), p(card_id, "damage", level))

		"diving_catch":
			var r := float(DB.card(card_id).get("radius", 2.5))
			var go := func() -> void:
				var from := caster.global_position if caster else Field.HOME
				fx.diving_catch(from, point, r)
				battle.vfx.shockwave(point, r, Color(1.0, 0.45, 0.7), 0.35)
				Audio.play("glove_catch")
				if battle.enemies_in_radius(point, r).is_empty():
					fx.fizzle(point)
				for e: Enemy in battle.enemies_in_radius(point, r):
					battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "throw", "card": card_id})
					if e.alive:
						e.knockback(p(card_id, "knockback", level))
						e.apply_stun(p(card_id, "stun", level) * control_mult())
			_cast(caster, go, point, "special", card_id)

		"twin_play":
			var go := func() -> void:
				Audio.play("aura_hum", -4.0)
				battle.add_buff("twin_play", p(card_id, "chain_damage", level), p(card_id, "duration", level) * power)
				battle.notify("TWIN PLAY!", Color(0.35, 1.0, 0.55))
				fx.twin_play(caster, p(card_id, "duration", level) * power)
			_cast(caster, go, point, "special", card_id)

		"field_vision":
			Audio.play("aura_hum", -6.0)
			battle.add_buff("field_vision", p(card_id, "range_bonus", level), p(card_id, "duration", level))
			fx.field_vision(p(card_id, "duration", level), p(card_id, "range_bonus", level))

		"diamond_aura":
			var df: Defender = target.get("defender")
			if df == null:
				return
			Audio.play("aura_hum")
			battle.add_buff("diamond_aura", p(card_id, "damage_bonus", level), p(card_id, "duration", level),
				{"defender": df, "radius": p(card_id, "radius", level), "speed": p(card_id, "speed_bonus", level)})
			fx.diamond_aura(df, p(card_id, "radius", level), p(card_id, "duration", level))

		"rally_cry":
			Audio.play("rally_horn")
			battle.notify("RALLY CRY!", Color(1.0, 0.85, 0.3))
			battle.add_buff("rally", p(card_id, "speed_bonus", level), p(card_id, "duration", level))
			fx.rally_cry(p(card_id, "duration", level))
			for df: Defender in battle.defenders:
				df.cleanse()
				df.celebrate()
				battle.get_tree().create_timer(0.8, false).timeout.connect(func() -> void:
					if is_instance_valid(df):
						df.model.play_base("ready", 0.2))
			battle.crowd_cheer(1.0)

		"magnet_glove":
			var r := float(DB.card(card_id).get("radius", 6.0))
			Audio.play("magnet_pull")
			var pulled := battle.enemies_in_radius(point, r)
			fx.magnet(point, r, p(card_id, "pull_time", level) * control_mult() + 0.4, pulled)
			if pulled.is_empty():
				fx.fizzle(point)
			for e: Enemy in pulled:
				e.apply_magnet(point, p(card_id, "pull_time", level) * control_mult() + 0.4)

		"sky_hook":
			var lead := battle.lead_runners(1)
			if lead.is_empty():
				fx.cast_ack(card_id, caster.global_position if caster else Field.HOME)
				fx.hook_whiff(_origin(caster))
				return
			var e: Enemy = lead[0]
			var go := func() -> void:
				if not is_instance_valid(e) or not e.targetable():
					var again := battle.lead_runners(1)
					if again.is_empty():
						fx.hook_whiff(_origin(caster))
						return
					e = again[0]
				battle.projectiles.launch(_origin(caster), e, 30.0, {"source": caster, "card": card_id, "damage": p(card_id, "damage", level) * power,
					"knockback": p(card_id, "pull", level), "accuracy": 200.0, "arc_mult": 3.5, "color": Color(0.3, 0.85, 1.0), "big": true,
					"fx": "hook", "trail": "hook"})
			_cast(caster, go, e.global_position, "special", card_id)

		"seventh_inning_stretch":
			Audio.play("heal_chime")
			battle.cards.add_energy(p(card_id, "energy", level))
			var before: Array = battle.cards.hand.duplicate()
			battle.cards.draw(int(p(card_id, "draw", level)))
			battle.crowd_cheer(0.7)
			battle.notify("SEVENTH-INNING STRETCH!", Color(1.0, 0.9, 0.5))
			fx.stretch(_new_cards(before), p(card_id, "energy", level))

		"called_shot":
			var e: Enemy = target.get("enemy")
			if e == null:
				return
			var df := nearest_thrower(e.global_position)
			var last_pos := e.center()
			Audio.play("crowd_ooh", -8.0)
			fx.lock_on(e, Defender.RELEASE.special / 1.3 + 0.35, GOLD)
			var go := func() -> void:
				if not is_instance_valid(e) or not e.targetable():
					var again := battle.lead_runners(1)
					if again.is_empty():
						fx.called_shot_impact(last_pos, false)
						fx.fizzle(last_pos, "NO TARGET")
						return
					e = again[0]
				# The ball drops out of the sky onto where the runner will be when it lands.
				var flight := 0.38
				var land: Vector3 = e.route.position_at(minf(e.d + e.current_speed() * flight, e.route.length)) if e.route else e.global_position
				var sky := land + Vector3(randf_range(-2.0, 2.0), 22.0, 5.0)
				fx.called_shot_drop(sky, land, flight)
				battle.projectiles.launch_at(sky, land + Vector3(0, e.height * 0.55, 0), sky.distance_to(land) / flight, {"big": true, "arc_mult": 0.0,
					"color": GOLD, "trail": "comet"}, func(_at: Vector3) -> void:
						if not is_instance_valid(e) or not e.alive:
							fx.called_shot_impact(land, false)
							return
						var bonus := e.max_hp * p(card_id, "percent", level) / 100.0
						if not e.is_boss:
							bonus = minf(bonus, p(card_id, "max_bonus", level))
						Audio.play("bat_crack", -2.0)
						Audio.play("boss_slam", -10.0)
						battle.shake(0.3)
						fx.called_shot_impact(e.center(), e.is_boss)
						battle.deal_damage(e, p(card_id, "damage", level) + bonus, {"source": df, "kind": "called", "card": card_id, "pierce": 1.0,
							"dir": e.global_position - battle.vfx.camera_pos(), "at": e.center(), "color": GOLD})
						if e.alive and e.is_boss:
							# Bosses shrug off 40% of a slow (Enemy.current_speed); the stated slow is what they get.
							e.apply_slow("called_shot", minf(p(card_id, "slow", level) / 100.0 / 0.6, 0.85), p(card_id, "slow_time", level) * control_mult()))
			_cast(df, go, e.global_position, "special", card_id)

		"line_drive":
			var r := float(DB.card(card_id).get("radius", 2.4))
			var df := nearest_thrower(point)
			var go := func() -> void:
				var from := _origin(df)
				Audio.play("bat_crack", -3.0)
				fx.line_drive_release(from, point)
				battle.projectiles.launch_at(from, point + Vector3(0, 0.6, 0), 46.0, {"color": Color(1.0, 0.96, 0.85), "big": true, "arc_mult": 0.12, "trail": "comet"},
					func(_at: Vector3) -> void:
						Audio.play("explosion_small", -5.0)
						battle.shake(0.15)
						fx.line_drive_impact(point, r, (point - from).normalized())
						var victims := battle.enemies_in_radius(point, r)
						if victims.is_empty():
							fx.fizzle(point)
						for e: Enemy in victims:
							battle.deal_damage(e, p(card_id, "damage", level), {"source": df, "kind": "throw", "card": card_id,
								"dir": e.global_position - point, "at": e.center(), "color": Color(1.0, 0.9, 0.6)})
							if e.alive:
								e.knockback(p(card_id, "knockback", level)))
			_cast(df, go, point, "throw", card_id)

		"tag_at_the_plate":
			Audio.play("glove_catch")
			Audio.play("crowd_small", -6.0)
			# A fresh tag replaces one that is still waiting (they don't stack).
			for b in battle.buffs.duplicate():
				if b.kind == "plate_tag":
					battle.buffs.erase(b)
			var dur := p(card_id, "duration", level)
			battle.add_buff("plate_tag", 1.0, dur, {"stun": p(card_id, "boss_stun", level), "knockback": p(card_id, "knockback", level)})
			battle.notify("PLATE BLOCKED!", TAG_TEAL)
			fx.tag_plate(dur)
			var catcher := nearest_thrower(Field.HOME)
			if catcher and catcher.model.action == "":
				catcher.model.play_action("catch", 1.0)

		"bullpen_call":
			Audio.play("card_draw")
			Audio.play("heal_chime", -8.0)
			battle.cards.add_energy(p(card_id, "energy", level))
			var before: Array = battle.cards.hand.duplicate()
			battle.cards.draw(int(p(card_id, "draw", level)))
			battle.notify("BULLPEN CALL!", Color(0.55, 1.0, 0.5))
			fx.bullpen_call(_new_cards(before), p(card_id, "energy", level))

		"hot_corner":
			var df: Defender = target.get("defender")
			if df == null:
				return
			Audio.play("fire_cast", -4.0)
			for b in battle.buffs.duplicate():
				if b.kind == "hot_corner" and b.get("defender") == df:
					battle.buffs.erase(b)
			var dur := p(card_id, "duration", level)
			battle.add_buff("hot_corner", p(card_id, "damage_bonus", level) / 100.0, dur, {"defender": df})
			fx.hot_corner(df, dur)

		"perfect_game":
			Audio.play("rally_horn")
			Audio.play("crowd_roar", -4.0)
			battle.notify("PERFECT GAME!", GOLD)
			battle.hud_flash(Color(1.0, 0.85, 0.4, 0.22))
			battle.crowd_cheer(1.0)
			var tag_time := p(card_id, "tag_time", level)
			battle.add_buff("perfect_tag", 1.0, tag_time, {"stun": 2.0, "knockback": 4.0})
			fx.perfect_game(tag_time)
			var victims: Array = []
			for e: Enemy in battle.enemies:
				if e.alive and e.id != "decoy":
					victims.append(e)
			if victims.is_empty():
				fx.fizzle(Field.MOUND + Vector3(0, 1.5, 0), "NO RUNNERS")
			# Bolts of light strike every runner in a quick sweep outward from the mound.
			for e: Enemy in victims:
				var delay := 0.35 + clampf(Field.v2(e.global_position).distance_to(Field.v2(Field.MOUND)) / 40.0, 0.0, 0.5)
				battle.get_tree().create_timer(delay, false).timeout.connect(func() -> void:
					if not is_instance_valid(battle) or not is_instance_valid(e) or not e.alive:
						return
					fx.perfect_strike(e)
					battle.deal_damage(e, p(card_id, "damage", level), {"kind": "lightning", "card": card_id, "true": true,
						"dir": e.global_position - Field.MOUND, "at": e.center(), "color": GOLD})
					if e.alive and e.is_boss:
						battle.deal_damage(e, e.max_hp * p(card_id, "boss_percent", level) / 100.0, {"kind": "lightning", "card": card_id,
							"true": true, "pierce": 1.0, "at": e.center(), "color": GOLD})
					if e.alive:
						e.apply_stun(p(card_id, "stun", level) * control_mult()))
			Audio.play("lightning_zap", -2.0)


## Cards that entered the hand since `before` (visual only: the draw effects show them).
func _new_cards(before: Array) -> Array:
	var out: Array = []
	var hand: Array = battle.cards.hand
	for i in hand.size():
		var id: String = hand[i]
		if id != "" and (i >= before.size() or before[i] != id):
			out.append(id)
	return out


## Has the caster perform its animation, then runs the effect at the impact frame.
## The wind-up visuals (anticipation) play over the same window.
func _cast(caster: Defender, effect: Callable, face_point: Vector3, anim := "special", card_id := "") -> void:
	if caster and is_instance_valid(caster) and not caster.is_stunned():
		battle.vfx.cards.cast_ack(card_id, caster.global_position)
		if anim == "special":
			battle.vfx.burst("magic", caster.model.chest_position(), Color(caster.data.accent))
			caster.cast_special(effect, face_point)
			battle.vfx.cards.anticipate(card_id, caster, face_point, Defender.RELEASE.special / 1.3, anim)
		else:
			var to := face_point - caster.global_position
			caster.rotation.y = atan2(to.x, to.z)
			var dur := caster.model.play_action("throw", 1.3)
			caster.attack_cd = maxf(caster.attack_cd, dur)
			battle.vfx.cards.anticipate(card_id, caster, face_point, 0.3 / 1.3, anim)
			battle.get_tree().create_timer(0.3 / 1.3, false).timeout.connect(effect)
	else:
		battle.vfx.cards.cast_ack(card_id, Field.HOME)
		effect.call()


## Where the cast acknowledgement of an instant card shows: the target spot for area /
## path cards, the chosen defender for Diamond Aura, home plate otherwise.
func _ack_point(card_id: String, target: Dictionary, point: Vector3) -> Vector3:
	var df = target.get("defender")
	if card_id in ["diamond_aura", "hot_corner"] and df is Node3D and is_instance_valid(df):
		return (df as Node3D).global_position
	if String(DB.card(card_id).get("target", "none")) in ["area", "path"]:
		return point
	return Field.HOME
