class_name FxScenario
extends Node
## Debug capture scenarios on the Practice Field, for reviewing battle feel frame by frame.
##   -- --test-battle=practice --fx-scenario=<name> [--fx-shots=t1,t2,...] [--fx-out=<dir>]
## Names:
##   boss:<id>   spawns the boss at a gate (intro plays), forces its attack telegraph at
##               --fx-attack=<s> (default 5.5) and lands a lethal crit at --fx-kill=<s> (default 8).
##   hits        a pack of normal runners in front of the infield; crits forced often, so hits,
##               crits and outs all show up.
##   runners     one of each runner type jogging past a close camera (defenders hold their throws).
##   stealer     Base Stealers take off while nobody aims at them, a Shielded elite's bubble
##               pops, and a slow catches a stealer stealing (--fx-hold, --fx-slow).
##   tag         Maya dash-tags a runner next to her post (catch + glove pop).
##   status      a row of standing runners, one per status (burn, freeze, stun, slow, root,
##               mark, confuse, vulnerable); defenders hold their throws.
##   elites      one runner per elite affix (plain, swift, tough, plated, slippery, shielded).
##   throws      every defender throws at a pack of sturdy runners (trails, hits, crits).
##   cast:<card> after --fx-cast=<s> (default 1.0) the card in hand slot 1 is "played" with the
##               HUD visible: the hand's cast flourish flies to the card's target (runners in
##               front of the infield; home plate or the caster for cards without a target).
## Shots are seconds after the scenario starts; frames are saved as <dir>/<name>_<centiseconds>.png
## and the game quits after the last one. Run with --fixed-fps 30 so frames land on game time.

var battle: Battle
var scenario := ""
var _shots: Array[float] = []
var _out := ""
var _t := 0.0
var _shot_i := 0
var _started := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fx-shots="):
			for t in a.split("=")[1].split(","):
				_shots.append(float(t))
		elif a.begins_with("--fx-out="):
			_out = a.split("=")[1]
	if _out != "":
		DirAccess.make_dir_recursive_absolute(_out)


func _process(delta: float) -> void:
	if not is_instance_valid(battle):
		return
	if not _started:
		if battle.state == "setup":
			_started = true
			_start()
		return
	_t += delta / maxf(Engine.time_scale, 0.01)
	if _shot_i < _shots.size() and _t >= _shots[_shot_i]:
		_capture(_shots[_shot_i])
		_shot_i += 1
		if _shot_i >= _shots.size() and _out != "":
			get_tree().create_timer(0.3, true, false, true).timeout.connect(func() -> void: get_tree().quit(0))


func _capture(t: float) -> void:
	if _out == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%03d.png" % [_out, scenario.replace(":", "_"), int(round(t * 100.0))]
	img.save_png(path)
	print("[FX] saved ", path)


func _arg_f(name: String, def: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return float(a.split("=")[1])
	return def


func _has_cam_arg() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam-view="):
			return true
	return false


func _view(focus: Vector3, yaw: float, pitch: float, dist: float) -> void:
	if _has_cam_arg():
		return
	battle.cam.set_view(focus, yaw, pitch, dist, true)


func _apply_status(e: Enemy, nm: String) -> void:
	if not is_instance_valid(e):
		return
	match nm:
		"burn":
			e.apply_burn(1.0, 60.0, null)
		"freeze":
			e.apply_freeze(60.0)
		"stun":
			e.apply_stun(60.0)
		"slow":
			e.apply_slow("curveball", 0.4, 60.0)
		"root":
			e.apply_root(60.0)
		"mark":
			e.apply_mark(60.0, 0.3)
		"confuse":
			e.apply_confuse(60.0)
		"vulnerable":
			e.vulnerable_t = 60.0
			e._rim_dirty = true


func _start() -> void:
	print("[FX] scenario ", scenario)
	var route: Route = battle.routes[0]
	if scenario.begins_with("boss:"):
		var id := scenario.split(":")[1]
		var boss := battle.spawn_enemy(id, route, 0.0, {"lateral": 0.0, "hp_mult": 1.0})
		var attack_at := _arg_f("--fx-attack", 5.5)
		var kill_at := _arg_f("--fx-kill", 8.0)
		get_tree().create_timer(attack_at, false).timeout.connect(func() -> void:
			if is_instance_valid(boss) and boss.alive:
				battle.cam.set_view(boss.global_position, battle.cam._t_yaw, -40.0, 26.0)
				boss.ability_t = 0.0)
		get_tree().create_timer(kill_at, false).timeout.connect(func() -> void:
			if is_instance_valid(boss) and boss.alive:
				var df: Defender = battle.defenders[0]
				battle.vfx.burst("crit", boss.center())
				battle.deal_damage(boss, boss.hp * 20.0 + 1000.0, {"source": df, "crit": true, "true": true,
					"dir": boss.global_position - df.global_position, "at": boss.center(), "color": Color(1.0, 0.8, 0.3)}))
	elif scenario == "hits":
		var d0 := route.length * 0.62
		var kinds := ["runner", "runner", "swarmer", "runner", "sprinter", "runner", "armored", "runner"]
		for i in kinds.size():
			battle.spawn_enemy(kinds[i], route, d0 - i * 0.9, {"lateral": randf_range(-1.0, 1.0), "speed_mult": 0.35})
		for df in battle.defenders:
			df.s_crit = 0.45
		var p := route.position_at(d0)
		_view(p.lerp(Field.MOUND, 0.3), 25.0, -38.0, 22.0)
	elif scenario == "runners":
		var kinds := ["runner", "sprinter", "armored", "swarmer", "jumper", "trickster", "captain", "slugger"]
		var d0 := route.length * 0.45
		for i in kinds.size():
			battle.spawn_enemy(kinds[i], route, d0 - i * 1.6, {"lateral": 0.0, "speed_mult": 0.6, "hp_mult": 100.0})
		for df in battle.defenders:
			df.attack_cd = 1.0e9
		var p := route.position_at(d0 - 5.0)
		_view(p, 70.0, -22.0, 17.0)
	elif scenario == "stealer":
		# Base Stealers and a Shielded elite in front of the infield; the defenders hold their
		# throws for a moment (so the stealers take off), then a slow catches one stealing.
		var d0 := route.length * 0.42
		for i in 3:
			battle.spawn_enemy("base_stealer", route, d0 - i * 1.4, {"lateral": randf_range(-0.8, 0.8), "speed_mult": 0.5, "hp_mult": 30.0})
		battle.spawn_enemy("runner", route, d0 - 5.0, {"lateral": 0.0, "speed_mult": 0.4, "hp_mult": 30.0, "affix": "shielded"})
		battle.spawn_enemy("armored", route, d0 - 6.5, {"lateral": 0.6, "speed_mult": 0.4, "hp_mult": 30.0, "affix": "shielded"})
		var hold := _arg_f("--fx-hold", 2.0)
		for df in battle.defenders:
			# Nobody is aiming at first, so the stealers take off.
			var rng := df.s_range
			df.s_range = 0.1
			df.target = null
			get_tree().create_timer(hold, false).timeout.connect(func() -> void:
				if is_instance_valid(df):
					df.s_range = rng)
		get_tree().create_timer(_arg_f("--fx-slow", 1.6), false).timeout.connect(func() -> void:
			for e in battle.enemies:
				if e.is_stealing():
					e.apply_slow("curveball", 0.4, 2.0)
					break)
		var p := route.position_at(d0 - 2.0)
		_view(p.lerp(Field.MOUND, 0.25), 30.0, -32.0, 20.0)
	elif scenario.begins_with("cast:"):
		var id := scenario.split(":")[1]
		var d0 := route.length * 0.55
		for i in 6:
			battle.spawn_enemy("runner", route, d0 - i * 0.6, {"lateral": randf_range(-1.0, 1.0), "speed_mult": 0.05, "hp_mult": 60.0})
		battle.cards.hand[0] = id
		battle.cards.hand_changed.emit()
		get_tree().create_timer(_arg_f("--fx-cast", 1.0), false).timeout.connect(func() -> void:
			var hud = battle.hud
			var t := str(DB.card(id).get("target", "none"))
			var point: Vector3 = Field.HOME if t == "none" else route.position_at(d0 - 1.5)
			var lead := battle.lead_runners(1)
			var df: Node3D = battle.defenders[0]
			if "_card_views" in hud and hud._card_views.size() > 0 and is_instance_valid(hud._card_views[0]):
				hud._selected_card_rect = (hud._card_views[0] as Control).get_global_rect()
			battle.last_cast_point = point
			battle.effects.execute(id, 1, {"point": point, "enemy": lead[0] if not lead.is_empty() else null, "defender": df, "valid": true})
			if hud.has_method("on_card_played"):
				hud.on_card_played(id))
	elif scenario == "status":
		# One runner per status, standing still in a row in front of the infield (no throws).
		var d0 := route.length * 0.55
		var names := ["burn", "freeze", "stun", "slow", "root", "mark", "confuse", "vulnerable"]
		for i in names.size():
			var e := battle.spawn_enemy("runner", route, d0 - i * 1.5, {"lateral": 0.0, "speed_mult": 0.02, "hp_mult": 1000.0})
			var nm: String = names[i]
			get_tree().create_timer(0.3, false).timeout.connect(func() -> void: _apply_status(e, nm))
		for df in battle.defenders:
			df.attack_cd = 1.0e9
		_view(route.position_at(d0 - 5.0), 70.0, -30.0, 19.0)
	elif scenario == "elites":
		# One elite per affix (and a plain runner) walking slowly in front of the infield.
		var d0 := route.length * 0.55
		var affs := ["", "swift", "tough", "plated", "slippery", "shielded"]
		for i in affs.size():
			battle.spawn_enemy("runner", route, d0 - i * 1.8, {"lateral": 0.0, "speed_mult": 0.08, "hp_mult": 1000.0, "affix": affs[i]})
		for df in battle.defenders:
			df.attack_cd = 1.0e9
		_view(route.position_at(d0 - 4.5), 70.0, -28.0, 18.0)
	elif scenario == "throws":
		# Every defender throws at a pack of sturdy runners in front of the infield.
		var d0 := route.length * 0.55
		for i in 10:
			battle.spawn_enemy("runner", route, d0 - i * 0.8, {"lateral": randf_range(-1.2, 1.2), "speed_mult": 0.1, "hp_mult": 200.0})
		for df in battle.defenders:
			df.s_range = 60.0
			df.s_crit = 0.3
	elif scenario == "u8":
		# Abilities and hits in one take (for the battle camera): a pack of runners being
		# thrown at (trails, hits, crits, outs) on one path, one elite per affix on another,
		# and two defenders winding up signature casts at --fx-cast (default 1.0 s).
		var r1: Route = battle.routes[mini(1, battle.routes.size() - 1)]
		var d0 := route.length * 0.62
		var kinds := ["runner", "runner", "swarmer", "runner", "sprinter", "runner", "armored", "runner"]
		for i in kinds.size():
			battle.spawn_enemy(kinds[i], route, d0 - i * 0.9, {"lateral": randf_range(-1.0, 1.0), "speed_mult": 0.35})
		var affs := ["swift", "tough", "plated", "slippery", "shielded"]
		var d1 := r1.length * 0.5
		for i in affs.size():
			battle.spawn_enemy("runner", r1, d1 - i * 1.8, {"lateral": 0.0, "speed_mult": 0.08, "hp_mult": 1000.0, "affix": affs[i]})
		for df in battle.defenders:
			df.s_crit = 0.45
		get_tree().create_timer(_arg_f("--fx-cast", 1.0), false).timeout.connect(func() -> void:
			for i in mini(2, battle.defenders.size()):
				# Same calls as CardEffects._cast for a linked card, minus the card's effect.
				var df: Defender = battle.defenders[battle.defenders.size() - 1 - i * 3]
				var card := str(df.data.get("signature", ""))
				battle.vfx.burst("magic", df.model.chest_position(), Color(df.data.accent))
				df.cast_special(func() -> void: pass, Field.MOUND)
				battle.vfx.cards.anticipate(card, df, Field.MOUND, Defender.RELEASE.special / 1.3, "special"))
	elif scenario == "bosses":
		# All three bosses near the infield; their attacks are forced on a stagger so one set of
		# shots catches each telegraph and impact: Iron Slugger and Grand Slammer at
		# --fx-attack (default 1.0 s), Phantom Captain 0.9 s later.
		var ids := ["iron_slugger", "grand_slammer", "phantom_captain"]
		var at := _arg_f("--fx-attack", 1.0)
		for i in ids.size():
			var r: Route = battle.routes[i % battle.routes.size()]
			var b := battle.spawn_enemy(ids[i], r, r.length * 0.62, {"lateral": 0.0, "hp_mult": 50.0, "speed_mult": 0.05})
			b.ability_t = 1.0e9
			var delay := at + (0.9 if ids[i] == "phantom_captain" else 0.0)
			get_tree().create_timer(delay, false).timeout.connect(func() -> void:
				if is_instance_valid(b) and b.alive:
					b.ability_t = 0.0)
		for df in battle.defenders:
			df.attack_cd = 1.0e9
	elif scenario == "tag":
		var maya: Defender = null
		for df in battle.defenders:
			if df.id == "maya":
				maya = df
		if maya == null:
			maya = battle.defenders[1]
			battle.swap_defender(maya, "maya")
			maya = null
			for df in battle.defenders:
				if df.id == "maya":
					maya = df
		var pr: Dictionary = route.project(maya.post)
		battle.spawn_enemy("runner", route, maxf(0.0, float(pr.d) - 4.0), {"lateral": 0.0, "speed_mult": 0.5, "hp_mult": 3.0})
		_view(maya.post, 30.0, -30.0, 14.0)
