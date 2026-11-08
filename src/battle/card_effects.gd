class_name CardEffects
extends RefCounted
## Executes ability cards. Linked cards are cast by their defender (special animation,
## power/cooldown from that defender's stats); without the defender on the field they
## fire from home plate at 75% power.

var battle: Battle

## Cards that resolve instantly (no caster wind-up): they get a cast acknowledgement pop.
const DIRECT_CARDS := ["grand_slam_barrage", "shadow_change", "time_out", "changeup", "frost_field", "wall_of_dirt",
	"base_shield", "bunt_trap", "field_vision", "diamond_aura", "rally_cry", "magnet_glove", "seventh_inning_stretch",
	"tag_at_the_plate", "bullpen_call", "hot_corner", "perfect_game",
	"around_the_horn", "grand_salami", "rain_delay", "intentional_walk", "infield_fly", "golden_glove", "the_shift", "momentum",
	"relief_pitcher", "instant_replay",
	"scouting_report", "sprinkler_system", "sweet_spot", "rally_monkey", "second_wind", "money_ball", "hidden_ball_trick",
	"fireworks_night", "ground_rule_double"]
const GOLD := Color(1.0, 0.82, 0.3)
const TAG_TEAL := Color(0.35, 1.0, 0.85)
const BEAN := Color(1.0, 0.35, 0.25)
const RELIEF := Color(0.55, 1.0, 0.5)
const SALAMI_SPEED := 13.0
const WORM_SPEED := 30.0
## Ground Rule Double: the echo goes off this long after the card (after a caster's wind-up).
const ECHO_DELAY := 0.9

## Update 7 mechanics that last: Rundown, Infield Fly, Golden Glove, The Shift, Relief Pitcher
## and Grand Salami's rolling ball and fire trail. Each is {kind, t, ...}; Battle ticks them.
var active: Array = []
## Instant Replay: the last card played this game (not a Legendary) and its target.
var last_play: Dictionary = {}
var _replaying := false
## Ground Rule Double: true while an echo (the free second cast) runs.
var _echoing := false
var _depth := 0


func _init(p_battle: Battle) -> void:
	battle = p_battle
	# Signal Caller refunds energy for outs on signalled runners. Battle's runner_out signal
	# (Update 9) is used when it exists; otherwise on_out() does it.
	if battle.has_signal("runner_out"):
		battle.connect("runner_out", _on_runner_out)


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
## While Ground Rule Double has charges left this inning, a played card also echoes: it goes
## off a second time for free ECHO_DELAY seconds later (replays and echoes don't use charges).
func execute(card_id: String, level: int, target: Dictionary) -> void:
	_depth += 1
	_execute_card(card_id, level, target)
	_depth -= 1
	if _depth > 0 or _echoing or _replaying or card_id == "ground_rule_double" or battle.cards == null:
		return
	if battle.cards.take_double_cast(battle.run.inning):
		_echo(card_id, level, target)


func _execute_card(card_id: String, level: int, target: Dictionary) -> void:
	var fx = battle.vfx.cards
	var info := caster_info(card_id)
	var caster: Defender = info.caster
	var power: float = info.power
	var point: Vector3 = target.get("point", Field.HOME)
	Audio.play("card_play", -4.0)
	if card_id in DIRECT_CARDS:
		fx.cast_ack(card_id, _ack_point(card_id, target, point))
	if not _replaying and card_id != "instant_replay" and String(DB.card(card_id).get("rarity", "")) != "legendary":
		last_play = {"id": card_id, "level": level, "target": target.duplicate()}
	if _execute_u7(card_id, level, target, point):
		return
	if _execute_u9(card_id, level, target, point):
		return
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
				if not is_instance_valid(e) or not e.hittable():
					fx.lost_throw(_origin(df), last_pos, Color(1.0, 0.42, 0.18))
					return
				battle.projectiles.launch(_origin(df), e, 42.0, {"source": df, "card": card_id, "damage": p(card_id, "damage", level),
					"knockback": p(card_id, "knockback", level), "accuracy": 200.0, "big": true, "color": Color(1.0, 0.42, 0.18), "crit": true,
					"fx": "power", "trail": "comet"})
				fx.power_release(_origin(df), e.center())
				Audio.play("bat_crack", -6.0)
			_cast(df, go, e.global_position, "throw", card_id)

		"splitter":
			var df := nearest_thrower(point)
			var go := func() -> void:
				battle.projectiles.launch_at(_origin(df), point + Vector3(0, 3.5, 0), 26.0, {"color": Color(1.0, 0.5, 0.42), "big": true, "trail": "comet"},
					func(at: Vector3) -> void:
						fx.splitter_burst(at, point)
						var victims := battle.enemies_in_radius(point, float(DB.card(card_id).get("radius", 5.0)))
						if victims.is_empty():
							fx.fizzle(point)
						var n := int(p(card_id, "balls", level)) + (1 if battle.buff_active("twin_play") else 0)
						for i in n:
							if victims.is_empty():
								battle.projectiles.launch_at(at, point + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 18.0, {"arc_mult": 0.3, "color": Color(1.0, 0.25, 0.25), "trail": "comet", "big": true}, func(x: Vector3) -> void: fx.ball_impact("split", x, Color(1.0, 0.25, 0.25)))
								continue
							var v: Enemy = victims[i % victims.size()]
							battle.projectiles.launch(at, v, 20.0, {"source": df, "card": card_id, "damage": p(card_id, "damage", level), "accuracy": 200.0, "color": Color(1.0, 0.25, 0.25), "arc_mult": 0.3,
								"fx": "split", "trail": "comet", "big": true}))
			_cast(df, go, point, "throw", card_id)

		"grand_slam_barrage":
			Audio.play("rally_horn", -6.0)
			battle.notify("GRAND SLAM BARRAGE!", Color(1.0, 0.6, 0.2))
			var r := float(DB.card(card_id).get("radius", 6.0))
			var balls := int(p(card_id, "balls", level))
			fx.barrage_start(point, r, 2.9)
			for i in balls:
				var delay := 0.25 + i * (2.4 / balls)
				battle.later(delay, func() -> void:
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
					battle.later(dl, func() -> void:
						fx.relay_link(prev, pos, ground))
					prev = pos
				var dmg := p(card_id, "damage", level) * power * (1.0 + float(DB.card(card_id).params.per_defender) * chain.size())
				var count := int(p(card_id, "targets", level)) + (1 if battle.buff_active("twin_play") else 0)
				var targets := battle.lead_runners(count)
				var last := prev
				battle.later(chain.size() * 0.08 + 0.1, func() -> void:
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
				battle.projectiles.launch_at(_origin(caster), point, 20.0, {"big": true, "arc_mult": 2.2, "color": Color(1.0, 0.25, 0.55), "trail": "heavy"}, func(at: Vector3) -> void:
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
				if not is_instance_valid(e) or not e.hittable():
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
				if not is_instance_valid(e) or not e.hittable():
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
				if not is_instance_valid(e) or not e.hittable():
					fx.pickoff_strike(_origin(caster), last_pos, false)
					fx.fizzle(last_pos, "NO TARGET")
					return
				var picked: bool = not e.is_boss and e.hp <= e.max_hp * p(card_id, "threshold", level) * power
				fx.pickoff_strike(_origin(caster), e.center(), picked)
				if not picked:
					fx.fizzle(e.center() + Vector3(0, 0.6, 0), "IMMUNE" if e.is_boss else "SAFE!")
				if picked:
					battle.vfx.text_popup(e.center() + Vector3(0, 0.8, 0), "PICKED OFF!", Color(0.55, 0.8, 1.0), 0.8, 0.7)
					e.die({"source": caster, "kind": "pickoff", "card": card_id})
				else:
					battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "throw", "card": card_id})
				Audio.play("glove_catch")
			if caster:
				fx.lock_on(e, Defender.RELEASE.special / 1.3, Color(0.3, 0.62, 1.0))
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
			fx.frost_field_cast(point, r)

		"wall_of_dirt":
			Audio.play("earth_rumble")
			battle.add_wall(target.get("point", point), p(card_id, "hp", level), p(card_id, "duration", level) * control_mult())
			fx.wall_cast(target.get("point", point))

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
				battle.later(0.8, func() -> void:
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
				if not is_instance_valid(e) or not e.hittable():
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
				if not is_instance_valid(e) or not e.hittable():
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
				battle.projectiles.launch_at(from, point + Vector3(0, 0.6, 0), 46.0, {"color": Color(1.0, 0.7, 0.3), "big": true, "arc_mult": 0.12, "trail": "comet"},
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
				battle.later(delay, func() -> void:
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
	if card_id in ["diamond_aura", "hot_corner", "golden_glove", "second_wind"] and df is Node3D and is_instance_valid(df):
		return (df as Node3D).global_position
	if String(DB.card(card_id).get("target", "none")) in ["area", "path"]:
		return point
	return Field.HOME


# ---------------------------------------------------------------- Update 7 cards

## Update 7 cards. Returns false for every other card.
func _execute_u7(card_id: String, level: int, target: Dictionary, point: Vector3) -> bool:
	var fx = battle.vfx.cards
	match card_id:
		"bean_ball":
			var e: Enemy = target.get("enemy")
			if e == null:
				return true
			var df := nearest_thrower(e.global_position)
			var last_pos := e.center()
			var go := func() -> void:
				if not is_instance_valid(e) or not e.hittable():
					fx.lost_throw(_origin(df), last_pos, BEAN)
					return
				var mult := p(card_id, "fast_mult", level) if is_fast(e) else 1.0
				fx.bean_release(_origin(df), e.center())
				Audio.play("bat_crack", -6.0)
				battle.projectiles.launch(_origin(df), e, 44.0, {"source": df, "card": card_id, "damage": p(card_id, "damage", level) * mult,
					"knockback": p(card_id, "knockback", level) * mult, "stun": p(card_id, "stun", level) * control_mult(), "accuracy": 999.0,
					"big": true, "color": BEAN, "fx": "bean_fast" if mult > 1.0 else "bean", "trail": "comet", "arc_mult": 0.15})
			_cast(df, go, e.global_position, "throw", card_id)

		"around_the_horn":
			var targets := horn_targets(int(p(card_id, "targets", level)) + (1 if battle.buff_active("twin_play") else 0))
			var path: Array[Vector3] = [Field.HOME, Field.THIRD, Field.SECOND, Field.FIRST]
			Audio.play("throw", -2.0)
			for i in path.size() - 1:
				var a := path[i]
				var b := path[i + 1]
				battle.later(i * 0.13, func() -> void:
					fx.horn_link(a, b)
					Audio.play("glove_catch", -8.0, 0.1))
			var t0 := (path.size() - 1) * 0.13 + 0.05
			if targets.is_empty():
				battle.later(t0, func() -> void: fx.fizzle(Field.FIRST + Vector3(0, 1.5, 0), "NO RUNNERS"))
			for i in targets.size():
				var wr := weakref(targets[i])
				battle.later(t0 + i * 0.1, func() -> void:
					var e := wr.get_ref() as Enemy
					if e == null or not e.targetable():
						return
					var from := _nearest_base(e.global_position) + Vector3(0, 1.2, 0)
					fx.horn_strike(from, e.center())
					Audio.play("ball_hit", -3.0, 0.1)
					battle.deal_damage(e, p(card_id, "damage", level), {"kind": "throw", "card": card_id, "dir": e.global_position - from,
						"at": e.center(), "color": Color(1.0, 0.7, 0.4)})
					if e.alive:
						e.apply_stun(p(card_id, "stun", level) * control_mult()))

		"grand_salami":
			var best_r: Route = null
			var best_d := 0.0
			var best_dist := INF
			for rt: Route in battle.routes:
				var pr: Dictionary = rt.project(point)
				if float(pr.dist) < best_dist:
					best_dist = float(pr.dist)
					best_r = rt
					best_d = clampf(float(pr.d), 1.5, rt.length - 1.0)
			if best_r == null:
				return true
			var land := best_r.position_at(best_d)
			var flight := 0.6
			var length := p(card_id, "length", level)
			var life := p(card_id, "burn_time", level)
			Audio.play("rally_horn", -6.0)
			battle.notify("GRAND SALAMI!", Color(1.0, 0.45, 0.15))
			fx.salami_drop(land, flight)
			battle.later(flight, func() -> void:
				if not is_instance_valid(battle):
					return
				Audio.play("boss_slam", -2.0)
				Audio.play("barrage_impact", -3.0)
				battle.shake(0.5)
				fx.salami_impact(land)
				var hit := {}
				for e: Enemy in battle.enemies_in_radius(land, 2.4):
					hit[e.get_instance_id()] = true   # the rolling ball doesn't hit them a second time
					battle.deal_damage(e, p(card_id, "damage", level), {"kind": "fire", "card": card_id, "dir": e.global_position - land, "at": e.center()})
					if e.alive:
						e.knockback(p(card_id, "knockback", level))
				active.append({"kind": "salami_fire", "pts": [land], "t": life + length / SALAMI_SPEED, "tick": 0.0,
					"dps": p(card_id, "burn_dps", level), "life": life})
				fx.salami_fire(land, life)
				active.append({"kind": "salami", "route": best_r, "d": best_d, "end": maxf(0.0, best_d - length),
					"hit": hit, "node": fx.salami_ball(land), "damage": p(card_id, "damage", level), "knockback": p(card_id, "knockback", level),
					"last": land, "t": 99.0}))

		"rundown":
			var e: Enemy = target.get("enemy")
			if e == null:
				return true
			var df := nearest_thrower(e.global_position)
			var last_pos := e.center()
			var go := func() -> void:
				if not is_instance_valid(e) or not e.hittable():
					fx.lost_throw(_origin(df), last_pos, DB.category_color("control"))
					return
				battle.projectiles.launch_at(_origin(df), e.center(), 30.0, {"color": Color(0.5, 0.45, 1.0), "arc_mult": 0.4, "trail": "comet"}, func(_at: Vector3) -> void:
					if not is_instance_valid(e) or not e.alive:
						return
					var dur := p(card_id, "duration", level) * control_mult() * (p(card_id, "boss_time", level) if e.is_boss else 1.0)
					var span := p(card_id, "span", level)
					e.rundown_lo = maxf(0.0, e.d - span * 0.65)
					e.rundown_hi = minf(e.route.length - 1.0, e.d + span * 0.35)
					e.rundown_dir = -1.0
					e.rundown_t = dur
					for it in active.duplicate():
						if it.kind == "rundown" and it.e == e:
							active.erase(it)
					active.append({"kind": "rundown", "e": e, "t": dur, "damage": p(card_id, "damage", level)})
					Audio.play("glove_catch")
					battle.vfx.text_popup(e.center() + Vector3(0, 1.3, 0), "RUNDOWN!", Color(0.8, 0.75, 1.0), 1.0, 1.0)
					fx.rundown_start(e, e.route.position_at(e.rundown_lo), e.route.position_at(e.rundown_hi), dur))
			_cast(df, go, e.global_position, "throw", card_id)

		"rain_delay":
			var hold := p(card_id, "delay", level) * control_mult()
			battle.spawn_hold = maxf(battle.spawn_hold, hold)
			Audio.play("frost_cast", -4.0)
			Audio.play("crowd_groan", -10.0)
			battle.notify("RAIN DELAY!", Color(0.6, 0.8, 1.0))
			battle.hud_flash(Color(0.35, 0.5, 0.75, 0.22))
			fx.rain_delay(hold)
			var slow := p(card_id, "slow", level) / 100.0
			for e: Enemy in battle.enemies:
				if e.alive:
					# Bosses shrug off 40% of a slow (Enemy.current_speed); the rain gets them in full.
					e.slows["rain"] = [minf(slow / 0.6, 0.85) if e.is_boss else slow, hold]

		"intentional_walk":
			var e: Enemy = target.get("enemy")
			if e == null:
				return true
			Audio.play("crowd_ooh", -8.0)
			if e.is_boss:
				fx.fizzle(e.center() + Vector3(0, 0.6, 0), "IMMUNE")
				return true
			var dur := p(card_id, "duration", level) * control_mult()
			e.slows["intentional_walk"] = [p(card_id, "slow", level) / 100.0, dur]
			fx.intentional_walk(e, dur)

		"infield_fly":
			var r := float(DB.card(card_id).get("radius", 3.0))
			var dur := p(card_id, "duration", level)
			Audio.play("bat_crack", -4.0)
			Audio.play("crowd_ooh", -10.0)
			var item := {"kind": "infield_fly", "point": point, "r": r, "t": dur, "delay": p(card_id, "delay", level),
				"victim": null, "land": 0.0, "boss_damage": p(card_id, "boss_damage", level)}
			active.append(item)
			fx.infield_fly(point, r, dur, item)

		"golden_glove":
			var df: Defender = target.get("defender")
			if df == null:
				return true
			for it in active.duplicate():
				if it.kind == "golden_glove" and it.df == df:
					active.erase(it)
			var item := {"kind": "golden_glove", "df": df, "t": p(card_id, "duration", level), "charges": int(p(card_id, "charges", level)),
				"radius": p(card_id, "radius", level), "boss_damage": p(card_id, "boss_damage", level), "cd": 0.2}
			active.append(item)
			Audio.play("heal_chime", -4.0)
			Audio.play("glove_catch", -6.0)
			fx.golden_glove(df, item)

		"the_shift":
			var dur := p(card_id, "duration", level)
			var reach := p(card_id, "shift", level)
			var moves: Array = []
			for df: Defender in battle.defenders:
				var to := point - df.post
				to.y = 0.0
				var dist := to.length()
				var step := minf(reach, maxf(0.0, dist - 2.0))
				var dest := df.post + (to / maxf(dist, 0.01)) * step
				if Field.v2(dest).distance_to(Field.v2(Field.HOME)) > Field.WALL_RADIUS - 2.5:
					dest = df.post
				moves.append({"df": df, "to": dest, "from": df.post})
			for it in active.duplicate():
				if it.kind == "shift":
					_end_shift(it)
					active.erase(it)
			for b in battle.buffs.duplicate():
				if b.kind == "shift":
					battle.buffs.erase(b)
			active.append({"kind": "shift", "t": dur, "dur": dur, "moves": moves})
			battle.add_buff("shift", p(card_id, "speed_bonus", level), dur)
			Audio.play("swing_whoosh", -2.0)
			Audio.play("crowd_small", -8.0)
			battle.notify("THE SHIFT!", DB.category_color("defense"))
			fx.shift(point, moves, dur)

		"momentum":
			for b in battle.buffs.duplicate():
				if b.kind == "momentum":
					battle.buffs.erase(b)
			var dur := p(card_id, "duration", level)
			battle.add_buff("momentum", p(card_id, "energy", level), dur, {"left": p(card_id, "max_energy", level)})
			Audio.play("aura_hum", -4.0)
			battle.notify("MOMENTUM!", Color(0.45, 0.9, 1.0))
			fx.momentum(dur)

		"relief_pitcher":
			var spot := point
			var snap := battle.snap_to_route(point)
			if float(snap.dist) < 2.0:
				# Step off the base path, on the mound side.
				var dir: Vector3 = snap.dir
				var side := Vector3(-dir.z, 0, dir.x)
				if side.dot(Field.MOUND - (snap.point as Vector3)) < 0.0:
					side = -side
				spot = (snap.point as Vector3) + side * 2.4
			spot.y = 0.0
			var gate := Field.wall_point(-38.0, 29.0)
			var start := spot + (gate - spot).normalized() * 8.0
			start.y = 0.0
			var holder: Node3D = fx.make_reliever(start, spot)
			Audio.play("card_draw", -2.0)
			Audio.play("crowd_cheer", -10.0)
			battle.notify("RELIEF PITCHER!", RELIEF)
			fx.reliever_call(gate, start, spot)
			active.append({"kind": "reliever", "node": holder, "from": start, "spot": spot, "phase": "in", "k": 0.0,
				"t": 99.0, "cd": 0.0, "damage": p(card_id, "damage", level), "interval": p(card_id, "interval", level),
				"range": p(card_id, "range", level), "dur": p(card_id, "duration", level)})

		"instant_replay":
			if last_play.is_empty():
				battle.cards.add_energy(float(DB.card(card_id).cost))
				fx.fizzle(Field.HOME + Vector3(0, 2.0, 0), "NOTHING TO REPLAY")
				return true
			var rid: String = last_play.id
			var tgt: Dictionary = (last_play.target as Dictionary).duplicate()
			var rc := DB.card(rid)
			if rc.target == "enemy":
				var e0: Variant = tgt.get("enemy")
				if e0 == null or not is_instance_valid(e0) or not (e0 as Enemy).hittable():
					var lead := battle.lead_runners(1)
					if lead.is_empty():
						battle.cards.add_energy(float(DB.card(card_id).cost))
						fx.fizzle(Field.HOME + Vector3(0, 2.0, 0), "NO TARGET")
						return true
					tgt.enemy = lead[0]
					tgt.point = (lead[0] as Enemy).global_position
			if rc.target == "defender":
				var d0: Variant = tgt.get("defender")
				if (d0 == null or not is_instance_valid(d0)) and not battle.defenders.is_empty():
					tgt.defender = battle.defenders[0]
			var lv := mini(int(last_play.level) + int(p(card_id, "levels", level)), DB.card_max_level + 1)
			var at: Vector3 = tgt.get("point", Field.HOME)
			var te: Variant = tgt.get("enemy")
			if te != null and is_instance_valid(te):
				at = (te as Enemy).global_position
			Audio.play("card_whoosh", -2.0)
			Audio.play("crowd_ooh", -6.0)
			battle.notify("INSTANT REPLAY: %s!" % String(rc.name).to_upper(), Color(0.5, 0.95, 1.0))
			fx.instant_replay(at, rid)
			battle.later(0.45, func() -> void:
				if not is_instance_valid(battle):
					return
				_replaying = true
				execute(rid, lv, tgt)
				_replaying = false)
		_:
			return false
	return true


## Sprinters, Swarmers and anything stealing: Bean Ball hits them twice as hard.
func is_fast(e: Enemy) -> bool:
	return float(e.data.get("speed", 3.0)) >= 3.8 or e.is_stealing()


## Around the Horn: the lead runner on each base path first, then the next runners.
func horn_targets(n: int) -> Array:
	var by_route := {}
	for e: Enemy in battle.enemies:
		if e.targetable() and e.id != "decoy":
			if not by_route.has(e.route):
				by_route[e.route] = []
			(by_route[e.route] as Array).append(e)
	var lead_first := func(a: Enemy, b: Enemy) -> bool: return a.remaining() < b.remaining()
	for k in by_route.keys():
		(by_route[k] as Array).sort_custom(lead_first)
	var out: Array = []
	var rank := 0
	while out.size() < n:
		var tier: Array = []
		for k in by_route.keys():
			if (by_route[k] as Array).size() > rank:
				tier.append(by_route[k][rank])
		if tier.is_empty():
			break
		tier.sort_custom(lead_first)
		for e in tier:
			if out.size() < n:
				out.append(e)
		rank += 1
	return out


func _nearest_base(pos: Vector3) -> Vector3:
	var best := Field.HOME
	for b in Field.bases():
		if Field.v2(b).distance_to(Field.v2(pos)) < Field.v2(best).distance_to(Field.v2(pos)):
			best = b
	return best


## Intentional Walk: a walking runner that reaches home scores no run.
func walked_home(e: Enemy) -> bool:
	if e.is_boss or e.id == "decoy" or not e.slows.has("intentional_walk"):
		return false
	battle.vfx.cards.walk_no_run(e)
	return true


## A runner was put out (Battle.on_enemy_out): Momentum pays energy. Signal Caller's refund
## and Money Ball's coins run here too when Battle has no runner_out signal / coin-bonus hook.
func on_out(e: Enemy, _info: Dictionary) -> void:
	for b in battle.buffs:
		if b.kind == "momentum" and float(b.get("left", 0.0)) > 0.0:
			var give := minf(float(b.value), float(b.left))
			b.left = float(b.left) - give
			battle.cards.add_energy(give)
			battle.vfx.cards.momentum_gain(e.center(), give)
			break
	if not battle.has_signal("runner_out"):
		_signal_refund(e)
	if not battle.has_method("add_out_coin_bonus"):
		_money_ball_coins(e)


func _on_runner_out(e: Enemy, _info: Dictionary) -> void:
	if is_instance_valid(e):
		_signal_refund(e)


## Rundown: the runner turned around, so it gets tagged.
func on_rundown_turn(e: Enemy) -> void:
	for it in active:
		if it.kind == "rundown" and it.e == e:
			battle.vfx.cards.rundown_tag(e)
			Audio.play("glove_catch", -6.0, 0.1)
			battle.deal_damage(e, float(it.damage), {"kind": "tag", "card": "rundown", "dir": e.route.direction_at(e.d) * e.rundown_dir,
				"at": e.center(), "color": Color(0.8, 0.75, 1.0)})
			return


## The active Update 7 mechanic of `kind` (for a defender or runner `key`), or an empty dictionary.
func active_item(kind: String, key: Variant = null) -> Dictionary:
	for it in active:
		if it.kind == kind and (key == null or it.get("df") == key or it.get("e") == key):
			return it
	return {}


## Ends every lasting mechanic at once (practice showcase, tests).
func clear_active() -> void:
	for it in active:
		if it.kind == "shift":
			_end_shift(it)
		var n: Variant = it.get("node")
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	active.clear()
	battle.spawn_hold = 0.0


## Per-frame update of the lasting mechanics (called by Battle._process, after it has rebuilt
## the defenders' buff bonuses for this frame).
func tick(delta: float) -> void:
	_apply_boosts()
	if active.is_empty():
		return
	for it in active.duplicate():
		it.t = float(it.t) - delta
		var done := float(it.t) <= 0.0
		match String(it.kind):
			"rundown":
				var e: Enemy = it.e if is_instance_valid(it.e) else null
				done = done or e == null or not e.alive or e.rundown_t <= 0.0
			"infield_fly":
				done = _tick_fly(it, delta)
			"golden_glove":
				done = _tick_glove(it, delta) or done
			"shift":
				_tick_shift(it)
				if done:
					_end_shift(it)
			"reliever":
				done = _tick_reliever(it, delta)
			"salami":
				done = _tick_salami(it, delta)
			"salami_fire":
				_tick_fire(it, delta)
			"scouting":
				_tick_scouting(it)
			"wet":
				_tick_wet(it)
			"trick":
				done = _tick_trick(it)
			"worm":
				done = _tick_worm(it, delta)
		if done:
			active.erase(it)


func _tick_fly(it: Dictionary, delta: float) -> bool:
	var fx = battle.vfx.cards
	var v: Variant = it.victim
	if v == null:
		if float(it.t) <= 0.0:
			return true
		for e: Enemy in battle.enemies_in_radius(it.point, float(it.r)):
			if e.id != "decoy":
				it.victim = e
				it.land = float(it.delay)
				fx.infield_fly_drop(it.point, e, float(it.delay))
				break
		return false
	it.land = float(it.land) - delta
	if float(it.land) > 0.0:
		return false
	if not is_instance_valid(v) or not (v as Enemy).alive:
		fx.fizzle(it.point + Vector3(0, 1.0, 0), "SAFE")
		return true
	var e := v as Enemy
	Audio.play("glove_catch")
	if e.is_boss:
		fx.infield_fly_catch(e, false)
		battle.deal_damage(e, float(it.boss_damage), {"kind": "catch", "card": "infield_fly", "at": e.center()})
		if e.alive:
			e.apply_stun(2.0 * control_mult())
	else:
		fx.infield_fly_catch(e, true)
		Audio.play("crowd_cheer", -8.0)
		e.die({"kind": "catch", "card": "infield_fly", "dir": Vector3.UP})
	return true


func _tick_glove(it: Dictionary, delta: float) -> bool:
	var df: Defender = it.df if is_instance_valid(it.df) else null
	if df == null or int(it.charges) <= 0:
		return true
	it.cd = float(it.cd) - delta
	if float(it.cd) > 0.0 or df.is_stunned():
		return false
	for e: Enemy in battle.enemies:
		if not e.targetable() or e.id == "decoy" or e.is_airborne():
			continue
		if Field.v2(e.global_position).distance_to(Field.v2(df.global_position)) > float(it.radius):
			continue
		it.charges = int(it.charges) - 1
		it.cd = 0.35
		var to := e.global_position - df.global_position
		df.rotation.y = atan2(to.x, to.z)
		if df.model.action == "":
			df.model.play_action("catch", 1.4)
		Audio.play("glove_catch")
		battle.vfx.cards.golden_catch(df, e, e.is_boss)
		if e.is_boss:
			battle.deal_damage(e, float(it.boss_damage), {"source": df, "kind": "catch", "card": "golden_glove", "at": e.center()})
			if e.alive:
				e.apply_stun(1.5 * control_mult())
		else:
			Audio.play("crowd_cheer", -10.0)
			e.die({"source": df, "kind": "catch", "card": "golden_glove", "dir": to})
		break
	return int(it.charges) <= 0


func _tick_shift(it: Dictionary) -> void:
	var tt := float(it.dur) - float(it.t)
	var k := 1.0
	if tt < 0.4:
		k = 1.0 - pow(1.0 - tt / 0.4, 3.0)
	elif float(it.t) < 0.5:
		k = smoothstep(0.0, 0.5, maxf(float(it.t), 0.0))
	for m in it.moves:
		var df: Defender = m.df if is_instance_valid(m.df) else null
		if df == null or df == battle.dragging or df._dash_state != "" or df.post != m.from:
			continue
		var pos: Vector3 = (m.from as Vector3).lerp(m.to, k)
		df.global_position = Vector3(pos.x, 0.0, pos.z)


## The shift is over: every defender that still has the same post stands on it again.
func _end_shift(it: Dictionary) -> void:
	for m in it.moves:
		var df: Defender = m.df if is_instance_valid(m.df) else null
		if df and df != battle.dragging and df._dash_state == "":
			df.global_position = df.post


func _tick_reliever(it: Dictionary, delta: float) -> bool:
	var node: Node3D = it.node if is_instance_valid(it.node) else null
	if node == null:
		return true
	var model: CharacterModel = node.get_child(0) as CharacterModel
	match String(it.phase):
		"in":
			it.t = 99.0
			it.k = float(it.k) + delta / 0.9
			node.global_position = (it.from as Vector3).lerp(it.spot, minf(float(it.k), 1.0))
			if float(it.k) >= 1.0:
				it.phase = "pitch"
				it.t = float(it.dur)
				model.play_base("ready", 0.2)
				battle.vfx.cards.reliever_arrive(it.spot, float(it.range), float(it.dur))
		"pitch":
			it.cd = float(it.cd) - delta
			if float(it.t) <= 0.0:
				it.phase = "out"
				it.k = 0.0
				it.t = 99.0
				model.play_base("run", 0.2)
				var back: Vector3 = (it.from as Vector3) - node.global_position
				node.rotation.y = atan2(back.x, back.z)
				battle.vfx.cards.reliever_leave(node.global_position)
				return false
			if float(it.cd) <= 0.0:
				var tgt: Enemy = null
				for e: Enemy in battle.enemies:
					if e.targetable() and Field.v2(e.global_position).distance_to(Field.v2(node.global_position)) <= float(it.range):
						if tgt == null or e.remaining() < tgt.remaining():
							tgt = e
				if tgt:
					it.cd = float(it.interval)
					var to := tgt.global_position - node.global_position
					node.rotation.y = atan2(to.x, to.z)
					model.play_action("throw", 1.6)
					Audio.play("throw", -8.0, 0.1, 70)
					var dmg := float(it.damage)
					var crit := randf() < 0.1 + tgt.crit_bonus() + sweet_spot_crit()
					if crit:
						dmg *= 1.75
					var mw := weakref(model)
					var tw := weakref(tgt)
					battle.later(0.3 / 1.6, func() -> void:
						var m := mw.get_ref() as CharacterModel
						var en := tw.get_ref() as Enemy
						if m == null or en == null or not en.hittable():
							return
						battle.vfx.arm_swoosh(m, RELIEF)
						battle.projectiles.launch(m.hand_position(), en, 30.0, {"card": "relief_pitcher", "damage": dmg, "crit": crit,
							"accuracy": 90.0, "color": RELIEF, "trail": "comet", "fx": "relief"}))
		"out":
			it.t = 99.0
			it.k = float(it.k) + delta / 0.9
			node.global_position = (it.spot as Vector3).lerp(it.from, minf(float(it.k), 1.0))
			if float(it.k) >= 1.0:
				battle.vfx.cards.reliever_gone(node.global_position)
				node.queue_free()
				return true
	return false


func _tick_salami(it: Dictionary, delta: float) -> bool:
	var node: Node3D = it.node if is_instance_valid(it.node) else null
	var route: Route = it.route
	it.d = float(it.d) - SALAMI_SPEED * delta
	var pos := route.position_at(maxf(float(it.d), 0.0))
	var dir := -route.direction_at(maxf(float(it.d), 0.0))
	if node:
		battle.vfx.cards.salami_roll(node, pos, dir, delta)
	if pos.distance_to(it.last) >= 1.2:
		it.last = pos
		var fire := active_item("salami_fire")
		if not fire.is_empty():
			(fire.pts as Array).append(pos)
			battle.vfx.cards.salami_fire(pos, float(fire.t) - 0.3)
	for e: Enemy in battle.enemies:
		if not e.targetable() or it.hit.has(e.get_instance_id()):
			continue
		if Field.v2(e.global_position).distance_to(Field.v2(pos)) < 1.9:
			it.hit[e.get_instance_id()] = true
			battle.vfx.cards.salami_hit(e)
			battle.deal_damage(e, float(it.damage), {"kind": "fire", "card": "grand_salami", "dir": dir, "at": e.center(), "color": Color(1.0, 0.5, 0.15)})
			if e.alive:
				e.knockback(float(it.knockback))
	if float(it.d) <= float(it.end) or float(it.d) <= 0.0:
		battle.vfx.cards.salami_end(pos)
		if node:
			node.queue_free()
		return true
	return false


## Grand Salami's fire trail: runners on it burn (re-applied every half second).
func _tick_fire(it: Dictionary, delta: float) -> void:
	it.tick = float(it.tick) - delta
	if float(it.tick) > 0.0:
		return
	it.tick = 0.5
	for e: Enemy in battle.enemies:
		if not e.targetable():
			continue
		for q in it.pts:
			if Field.v2(e.global_position).distance_to(Field.v2(q)) < 1.5:
				e.apply_burn(float(it.dps), 1.2, null)
				break


# ---------------------------------------------------------------- Update 9 cards

## Update 9 cards. Returns false for every other card.
func _execute_u9(card_id: String, level: int, target: Dictionary, point: Vector3) -> bool:
	var fx = battle.vfx.cards
	match card_id:
		"scouting_report":
			var e: Enemy = target.get("enemy")
			if e == null or not is_instance_valid(e):
				return true
			var type := scout_type(e)
			var dur := p(card_id, "duration", level) * control_mult()
			for it in active.duplicate():
				if it.kind == "scouting" and it.type == type:
					active.erase(it)
			var item := {"kind": "scouting", "type": type, "t": dur, "amt": p(card_id, "vulnerability", level)}
			active.append(item)
			_tick_scouting(item)
			var victims := scouted(type)
			Audio.play("card_whoosh", -6.0)
			Audio.play("crowd_ooh", -10.0)
			battle.notify("SCOUTED: %s!" % type_name(type, victims.size()).to_upper(), Color(0.92, 0.55, 1.0))
			fx.scouting_report(e, victims, dur)

		"sprinkler_system":
			var at := route_at(point)
			if at.is_empty():
				return true
			var rt: Route = at.route
			var half := p(card_id, "length", level) * 0.5
			var d0 := clampf(float(at.d) - half, 0.0, rt.length)
			var d1 := clampf(float(at.d) + half, 0.0, rt.length)
			var dur := p(card_id, "duration", level) * control_mult()
			active.append({"kind": "wet", "key": "sprinkler", "route": rt, "d0": d0, "d1": d1, "t": dur,
				"slow": p(card_id, "slow", level) / 100.0, "chance": p(card_id, "slip_chance", level) / 100.0,
				"stun": p(card_id, "stun", level) * control_mult()})
			Audio.play("frost_cast", -6.0)
			Audio.play("crowd_small", -12.0)
			fx.sprinkler(rt, d0, d1, dur)

		"sweet_spot":
			for b in battle.buffs.duplicate():
				if b.kind == "sweet_spot":
					battle.buffs.erase(b)
			var dur := p(card_id, "duration", level)
			battle.add_buff("sweet_spot", p(card_id, "crit_bonus", level), dur)
			Audio.play("bat_crack", -2.0)
			Audio.play("crowd_ooh", -8.0)
			battle.notify("SWEET SPOT!", Color(1.0, 0.62, 0.22))
			fx.sweet_spot(dur)

		"rally_monkey":
			var clutch: bool = battle.run.runs_inning > 0
			var gain := p(card_id, "clutch_energy" if clutch else "energy", level)
			battle.cards.add_energy(gain)
			var before: Array = battle.cards.hand.duplicate()
			if clutch:
				battle.cards.draw(int(p(card_id, "draw", level)))
			Audio.play("crowd_cheer", -6.0 if clutch else -10.0)
			Audio.play("heal_chime", -8.0)
			battle.crowd_cheer(1.0 if clutch else 0.6)
			battle.notify("CLUTCH RALLY MONKEY!" if clutch else "RALLY MONKEY!", Color(1.0, 0.75, 0.25))
			fx.rally_monkey(clutch, _new_cards(before), gain)

		"second_wind":
			var df: Defender = target.get("defender")
			if df == null or not is_instance_valid(df):
				return true
			var reset: Array = []
			for sid in signature_cards(df):
				if battle.cards.reset_cooldown(sid):
					reset.append(sid)
			for b in battle.buffs.duplicate():
				if b.kind == "second_wind" and b.get("defender") == df:
					battle.buffs.erase(b)
			var dur := p(card_id, "duration", level)
			battle.add_buff("second_wind", p(card_id, "speed_bonus", level), dur, {"defender": df})
			df.cleanse()
			Audio.play("heal_chime", -4.0)
			Audio.play("aura_hum", -6.0)
			battle.notify("SECOND WIND!", Color(0.6, 1.0, 0.45))
			fx.second_wind(df, dur, reset)

		"money_ball":
			# Several Money Balls add up (with Ground Rule Double: triple coins).
			var dur := p(card_id, "duration", level)
			var bonus := p(card_id, "coin_bonus", level)
			battle.add_buff("money_ball", bonus, dur)
			if battle.has_method("add_out_coin_bonus"):
				battle.call("add_out_coin_bonus", bonus, dur)
			Audio.play("coin", -2.0)
			Audio.play("crowd_cheer", -10.0)
			battle.notify("MONEY BALL!", GOLD)
			fx.money_ball(dur)

		"scoop_and_tag":
			var info := caster_info(card_id)
			var caster: Defender = info.caster
			var power: float = info.power
			var r := float(DB.card(card_id).get("radius", 4.0))
			var go := func() -> void:
				var from: Vector3 = caster.global_position if caster and is_instance_valid(caster) else Field.HOME
				var victims := battle.enemies_in_radius(point, r)
				Audio.play("swing_whoosh", -2.0)
				Audio.play("glove_catch", -4.0)
				battle.shake(0.25)
				fx.scoop_sweep(from, point, r)
				if victims.is_empty():
					fx.fizzle(point)
				for e: Enemy in victims:
					battle.deal_damage(e, p(card_id, "damage", level) * power, {"source": caster, "kind": "slam", "card": card_id,
						"dir": e.global_position - from, "at": e.center(), "color": Color(0.75, 1.0, 0.35)})
					if not e.alive:
						continue
					if not e.is_boss and e.id != "decoy" and e.hp <= e.max_hp * p(card_id, "threshold", level):
						fx.scoop_tag(e)
						e.die({"source": caster, "kind": "tag", "card": card_id, "dir": e.global_position - from})
						continue
					e.knockback(p(card_id, "knockback", level))
					e.apply_stun(p(card_id, "stun", level) * control_mult())
			_cast(caster, go, point, "special", card_id)

		"signal_caller":
			var info := caster_info(card_id)
			var caster: Defender = info.caster
			var power: float = info.power
			var lead := battle.lead_runners(1)
			var face: Vector3 = (lead[0] as Enemy).global_position if not lead.is_empty() else Field.MOUND
			var go := func() -> void:
				var marked := battle.lead_runners(int(p(card_id, "targets", level)))
				var dur := p(card_id, "duration", level) * power
				Audio.play("crowd_ooh", -8.0)
				Audio.play("glove_catch", -6.0)
				if marked.is_empty():
					fx.fizzle(Field.HOME + Vector3(0, 2.0, 0), "NO RUNNERS")
				for e: Enemy in marked:
					e.apply_signal(dur, p(card_id, "vulnerability", level), p(card_id, "energy", level))
				battle.notify("SIGNALS CALLED!", Color(1.0, 0.42, 0.72))
				fx.signal_caller(caster, marked, dur)
			_cast(caster, go, face, "special", card_id)

		"hidden_ball_trick":
			var victim := strongest_runner()
			var bosses := live_bosses()
			if victim == null and bosses.is_empty():
				fx.fizzle(Field.HOME + Vector3(0, 2.0, 0), "NO RUNNERS")
				return true
			var reveal := p(card_id, "reveal", level)
			active.append({"kind": "trick", "t": reveal, "victim": victim, "pct": p(card_id, "boss_percent", level)})
			Audio.play("crowd_ooh", -6.0)
			battle.notify("HIDDEN BALL TRICK!", Color(0.75, 0.5, 1.0))
			fx.hidden_ball_start(victim, bosses, reveal)

		"worm_burner":
			var info := caster_info(card_id)
			var caster: Defender = info.caster
			var power: float = info.power
			var at := route_at(point)
			if at.is_empty():
				return true
			var rt: Route = at.route
			var d_start := clampf(float(at.d), 1.5, rt.length - 0.5)
			var land := rt.position_at(d_start)
			var length := p(card_id, "length", level)
			var src := weakref(caster) if caster else null
			var go := func() -> void:
				var from := _origin(caster) if caster and is_instance_valid(caster) else Field.HOME + Vector3(0, 1.5, 0)
				var flight := clampf(from.distance_to(land) / 36.0, 0.12, 0.8)
				Audio.play("bat_crack", -3.0)
				fx.worm_release(from, land, flight)
				battle.later(flight, func() -> void:
					if not is_instance_valid(battle):
						return
					Audio.play("explosion_small", -6.0)
					battle.shake(0.2)
					fx.worm_land(land)
					active.append({"kind": "worm", "route": rt, "d": d_start, "start": d_start, "end": maxf(0.0, d_start - length),
						"hit": {}, "node": fx.worm_ball(land), "damage": p(card_id, "damage", level) * power,
						"stun": p(card_id, "stun", level) * control_mult(), "slow": p(card_id, "slow", level) / 100.0,
						"slow_time": p(card_id, "slow_time", level) * control_mult(), "last": land, "t": 99.0, "src": src}))
			_cast(caster, go, land, "special", card_id)

		"fireworks_night":
			var n := int(p(card_id, "rockets", level))
			var span := p(card_id, "time", level)
			var dmg := p(card_id, "damage", level)
			Audio.play("rally_horn", -6.0)
			Audio.play("crowd_cheer", -6.0)
			battle.notify("FIREWORKS NIGHT!", Color(1.0, 0.55, 0.85))
			battle.crowd_cheer(1.0)
			fx.fireworks_start(span)
			for i in n:
				var delay := 0.35 + span * float(i) / float(maxi(n, 1))
				battle.later(delay, func() -> void:
					if is_instance_valid(battle):
						_firework(dmg, i))
			battle.later(0.35 + span + 0.45, func() -> void:
				if is_instance_valid(battle):
					_fireworks_finale(card_id, level))

		"ground_rule_double":
			var n := int(p(card_id, "casts", level))
			battle.cards.grant_double_casts(n, battle.run.inning)
			Audio.play("bat_crack", -2.0)
			Audio.play("crowd_roar", -6.0)
			battle.notify("GROUND RULE DOUBLE! NEXT %d CARDS CAST TWICE" % n, GOLD)
			battle.crowd_cheer(0.9)
			fx.ground_rule_double(n)
		_:
			return false
	return true


## Ground Rule Double's echo: the same card again, free, ECHO_DELAY seconds later.
func _echo(card_id: String, level: int, target: Dictionary) -> void:
	var fx = battle.vfx.cards
	var at: Vector3 = target.get("point", Field.HOME)
	var te: Variant = target.get("enemy")
	if te != null and is_instance_valid(te):
		at = (te as Enemy).global_position
	fx.double_mark(card_id, at, ECHO_DELAY)
	battle.later(ECHO_DELAY, func() -> void:
		if not is_instance_valid(battle):
			return
		var tgt := echo_target(card_id, target)
		if tgt.is_empty():
			fx.fizzle(at + Vector3(0, 2.0, 0), "NO TARGET")
			return
		fx.double_go(card_id, tgt.get("point", at))
		_echoing = true
		execute(card_id, level, tgt)
		_echoing = false)


## The target for an echo: the same one, or the runner nearest home / the first defender if
## it is gone. Empty when there is nothing left to aim at.
func echo_target(card_id: String, target: Dictionary) -> Dictionary:
	var tgt := target.duplicate()
	match String(DB.card(card_id).get("target", "none")):
		"enemy":
			var e0: Variant = tgt.get("enemy")
			if e0 == null or not is_instance_valid(e0) or not (e0 as Enemy).hittable():
				var lead := battle.lead_runners(1)
				if lead.is_empty():
					return {}
				tgt.enemy = lead[0]
			tgt.point = (tgt.enemy as Enemy).global_position
		"defender":
			var d0: Variant = tgt.get("defender")
			if d0 == null or not is_instance_valid(d0):
				if battle.defenders.is_empty():
					return {}
				tgt.defender = battle.defenders[0]
	return tgt


## Sweet Spot and Second Wind: per-frame bonuses on top of what Battle._update_buffs set.
func _apply_boosts() -> void:
	for b in battle.buffs:
		match String(b.kind):
			"sweet_spot":
				for df: Defender in battle.defenders:
					df.dyn_crit += float(b.value)
			"second_wind":
				var df: Variant = b.get("defender")
				if df != null and is_instance_valid(df):
					(df as Defender).dyn_speed += float(b.value)


## Extra crit chance from Sweet Spot (the Relief Pitcher's throws use it too).
func sweet_spot_crit() -> float:
	var c := 0.0
	for b in battle.buffs:
		if b.kind == "sweet_spot":
			c += float(b.value)
	return c


## Signal Caller: an out on a signalled runner refunds energy (once).
func _signal_refund(e: Enemy) -> void:
	if e.signal_t <= 0.0 or e.signal_refund <= 0.0:
		return
	var give := e.signal_refund
	e.signal_t = 0.0
	e.signal_refund = 0.0
	battle.cards.add_energy(give)
	battle.vfx.cards.signal_refund(e.center(), give)


## Money Ball without Battle's coin-bonus hook: pays the extra coins for an out itself.
func _money_ball_coins(e: Enemy) -> void:
	var bonus := 0.0
	for b in battle.buffs:
		if b.kind == "money_ball":
			bonus += float(b.value)
	if bonus <= 0.0:
		return
	var coin := int(round(e.coins * (1.0 + battle.run.modifier_total("coin_mult")) * bonus))
	if coin <= 0:
		return
	battle.run.coins += coin
	battle.run.coins_earned += coin
	battle.vfx.cards.money_ball_coin(e.center(), coin)


## The scouting type of a runner (decoys count as their Trickster).
static func scout_type(e: Enemy) -> String:
	return "trickster" if e.id == "decoy" else e.id


## Plural display name of a runner type ("Sprinters", or a boss's own name).
static func type_name(type: String, count: int) -> String:
	var d := DB.enemy(type)
	var n := str(d.get("name", type.capitalize()))
	return n if bool(d.get("boss", false)) or count == 1 else n + "s"


## Every live runner of a scouting type.
func scouted(type: String) -> Array:
	var out: Array = []
	for e: Enemy in battle.enemies:
		if e.alive and e.id == type:
			out.append(e)
	return out


## Second Wind: the defender's signature card(s): its data's signature and any card linked to it.
func signature_cards(df: Defender) -> Array:
	var out: Array = []
	var sig := str(df.data.get("signature", ""))
	if sig != "" and DB.cards.has(sig):
		out.append(sig)
	for cid in DB.card_order:
		if str(DB.card(cid).get("linked", "")) == df.id and not cid in out:
			out.append(cid)
	return out


## Hidden Ball Trick: the non-boss runner with the most health left (closest to home on a tie).
func strongest_runner() -> Enemy:
	var best: Enemy = null
	for e: Enemy in battle.enemies:
		if not e.alive or e.is_boss or e.id == "decoy":
			continue
		if best == null or e.hp > best.hp + 0.01 or (absf(e.hp - best.hp) <= 0.01 and e.remaining() < best.remaining()):
			best = e
	return best


func live_bosses() -> Array:
	var out: Array = []
	for e: Enemy in battle.enemies:
		if e.alive and e.is_boss:
			out.append(e)
	return out


## The base path nearest a point: {route, d, dist}, or empty without routes.
func route_at(point: Vector3) -> Dictionary:
	var best := {}
	for rt: Route in battle.routes:
		var pr: Dictionary = rt.project(point)
		if best.is_empty() or float(pr.dist) < float(best.dist):
			best = {"route": rt, "d": float(pr.d), "dist": float(pr.dist)}
	return best


func _tick_scouting(it: Dictionary) -> void:
	for e: Enemy in battle.enemies:
		if e.alive and e.id == it.type:
			e.apply_scouted(maxf(float(it.t), 0.05), float(it.amt))


## Sprinkler System / Worm Burner's slick: runners on the stretch of path are slowed (and,
## on wet grass, may slip).
func _tick_wet(it: Dictionary) -> void:
	var rt: Route = it.route
	for e: Enemy in battle.enemies:
		if not e.alive or e.is_airborne():
			continue
		var pr: Dictionary = rt.project(e.global_position)
		if float(pr.dist) > 1.9 or float(pr.d) < float(it.d0) - 0.5 or float(pr.d) > float(it.d1) + 0.5:
			continue
		e.apply_slow(String(it.key), float(it.slow), 0.3)
		if float(it.chance) > 0.0:
			e.apply_soak(0.6, float(it.chance), float(it.stun))


## Hidden Ball Trick: after the reveal the marked runner (or the strongest one left) is out,
## and every boss loses a share of its max health.
func _tick_trick(it: Dictionary) -> bool:
	if float(it.t) > 0.0:
		return false
	var fx = battle.vfx.cards
	var v: Enemy = it.victim if it.victim != null and is_instance_valid(it.victim) and (it.victim as Enemy).alive else null
	if v == null:
		v = strongest_runner()
	var bosses := live_bosses()
	if v == null and bosses.is_empty():
		fx.fizzle(Field.HOME + Vector3(0, 2.0, 0), "SAFE!")
		return true
	Audio.play("glove_catch")
	if v:
		fx.hidden_ball_out(v)
		Audio.play("crowd_cheer", -6.0)
		v.die({"kind": "tag", "card": "hidden_ball_trick", "dir": -v.route.direction_at(v.d), "color": Color(0.8, 0.55, 1.0)})
		battle.notify("GOTCHA! TAGGED OUT!", Color(0.85, 0.6, 1.0))
	for b: Enemy in bosses:
		fx.hidden_ball_boss(b)
		battle.deal_damage(b, b.max_hp * float(it.pct) / 100.0, {"kind": "tag", "card": "hidden_ball_trick", "true": true, "pierce": 1.0,
			"at": b.center(), "color": Color(0.8, 0.55, 1.0)})
	return true


## Worm Burner: the grounder skips up the base path, hitting each runner it passes once.
func _tick_worm(it: Dictionary, delta: float) -> bool:
	var fx = battle.vfx.cards
	var node: Node3D = it.node if is_instance_valid(it.node) else null
	var rt: Route = it.route
	var prev := rt.position_at(maxf(float(it.d), float(it.end)))
	it.d = float(it.d) - WORM_SPEED * delta
	var dd := maxf(float(it.d), float(it.end))
	var pos := rt.position_at(dd)
	var dir := -rt.direction_at(dd)
	if node:
		fx.worm_roll(node, pos, dir, float(it.start) - dd)
	if pos.distance_to(it.last) >= 1.4:
		it.last = pos
		fx.worm_trail(pos, dir)
	var src: Variant = (it.src as WeakRef).get_ref() if it.src != null else null
	for e: Enemy in battle.enemies:
		if not e.targetable() or e.is_airborne() or it.hit.has(e.get_instance_id()):
			continue
		if seg_dist(e.global_position, prev, pos) < 1.8:
			it.hit[e.get_instance_id()] = true
			fx.worm_hit(e)
			battle.deal_damage(e, float(it.damage), {"source": src, "kind": "throw", "card": "worm_burner", "dir": dir, "at": e.center(),
				"color": Color(1.0, 0.6, 0.25)})
			if e.alive:
				e.apply_stun(float(it.stun))
	if dd <= float(it.end) + 0.001:
		fx.worm_end(pos)
		if node:
			node.queue_free()
		active.append({"kind": "wet", "key": "slick", "route": rt, "d0": float(it.end), "d1": float(it.start), "t": float(it.slow_time),
			"slow": float(it.slow), "chance": 0.0, "stun": 0.0})
		fx.slick(rt, float(it.end), float(it.start), float(it.slow_time))
		return true
	return false


## Ground distance from p to the segment a-b.
static func seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var pa := Field.v2(p) - Field.v2(a)
	var ab := Field.v2(b) - Field.v2(a)
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf(pa.dot(ab) / l2, 0.0, 1.0)
	return (pa - ab * t).length()


## Fireworks Night: one rocket at a random runner (it splashes the runners next to it).
func _firework(dmg: float, i: int) -> void:
	var fx = battle.vfx.cards
	var pool: Array = []
	for e: Enemy in battle.enemies:
		if e.targetable() and e.id != "decoy":
			pool.append(e)
	var ang := randf_range(-60.0, 60.0)
	var from := Field.wall_point(ang, 31.0) + Vector3(0, 6.0, 0)
	var flight := 0.55
	if pool.is_empty():
		var sky := Field.MOUND + Vector3(randf_range(-14, 14), randf_range(12, 18), randf_range(-14, 6))
		fx.firework_rocket(from, sky, flight, i)
		battle.later(flight, func() -> void:
			if is_instance_valid(battle):
				fx.firework_burst(sky, i, false))
		return
	var e: Enemy = pool[randi() % pool.size()]
	var wr := weakref(e)
	fx.firework_rocket(from, e.center() + Vector3(0, 0.5, 0), flight, i)
	battle.later(flight, func() -> void:
		if not is_instance_valid(battle):
			return
		var t := wr.get_ref() as Enemy
		if t == null or not t.alive:
			return
		var at := t.center()
		fx.firework_burst(at, i, true)
		Audio.play("barrage_impact", -8.0, 0.15, 60)
		battle.deal_damage(t, dmg, {"kind": "fire", "card": "fireworks_night", "at": at, "dir": t.global_position - from})
		for o: Enemy in battle.enemies_in_radius(at, 1.6):
			if o != t:
				battle.deal_damage(o, dmg * 0.5, {"kind": "fire", "card": "fireworks_night", "at": o.center(), "dir": o.global_position - at}))


## Fireworks Night finale: a huge burst over the biggest crowd.
func _fireworks_finale(card_id: String, level: int) -> void:
	var fx = battle.vfx.cards
	var r := p(card_id, "radius", level)
	var best: Enemy = null
	var best_n := 0
	for e: Enemy in battle.enemies:
		if not e.targetable() or e.id == "decoy":
			continue
		var n := battle.enemies_in_radius(e.global_position, r).size()
		if n > best_n:
			best_n = n
			best = e
	var center: Vector3 = best.global_position if best else Field.MOUND
	Audio.play("boss_slam", -4.0)
	Audio.play("crowd_roar", -4.0)
	battle.shake(0.45)
	fx.fireworks_finale(center, r)
	for e: Enemy in battle.enemies_in_radius(center, r):
		battle.deal_damage(e, p(card_id, "finale_damage", level), {"kind": "fire", "card": card_id, "at": e.center(), "dir": e.global_position - center})
		if e.alive:
			e.apply_stun(p(card_id, "stun", level) * control_mult())
