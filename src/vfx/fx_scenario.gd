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
