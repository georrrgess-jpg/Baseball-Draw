extends Node
## Stress test: fills the Practice Field with runners and measures frame cost.
## Run with rendering for draw-call numbers, or --headless for pure CPU/script cost:
##   godot --path . -- --perf-test --profile=perf [--perf-count=150]

var battle: Battle
var target_count := 150
var samples: Array[float] = []
var process_samples: Array[float] = []
var _t0 := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-count="):
			target_count = int(a.split("=")[1])
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	Profile.data.flags["battle_help"] = true
	var cfg := Session.new_run_config("practice")
	cfg.seed = 1
	Session.start(cfg)
	for i in 300:
		await _wait(0.1)
		if get_tree().current_scene is Battle:
			battle = get_tree().current_scene
			if battle.state == "setup":
				break
	await _wait(1.0)
	battle.profile_sections = true
	var baseline := await _measure(3.0)
	print("[PERF] baseline (empty field): %s" % baseline)
	# Spawn runners in waves until the target is alive at once. They are tough so they stay on the field.
	var spawned := 0
	while spawned < target_count:
		for k in 10:
			var r := battle.routes[spawned % battle.routes.size()]
			var kinds := ["runner", "sprinter", "armored", "swarmer", "jumper", "captain"]
			battle.spawn_enemy(kinds[spawned % kinds.size()], r, randf_range(0.0, r.length * 0.5), {"hp_mult": 60.0, "lateral": randf_range(-1, 1)})
			spawned += 1
		await _wait(0.25)
	battle.cards.infinite_energy = true
	var loaded := await _measure(6.0)
	print("[PERF] %d runners + 6 defenders + projectiles: %s" % [battle.enemies.size(), loaded])
	# Spam area cards on top of the crowd.
	for cid in ["grand_slam_barrage", "heat_wave", "frost_field", "magnet_glove", "splitter"]:
		var lead := battle.lead_runners(1)
		if lead.is_empty():
			break
		battle.effects.execute(cid, 1, {"point": lead[0].global_position, "enemy": lead[0], "valid": true})
	var burst := await _measure(4.0)
	print("[PERF] with simultaneous abilities: %s" % burst)
	var frames := float(battle.prof.get("frames", 1.0))
	var parts: Array[String] = []
	for k in battle.prof.keys():
		if k != "frames":
			parts.append("%s %.2fms" % [k, battle.prof[k] / frames / 1000.0])
	print("[PERF] battle loop per frame: " + ", ".join(parts))
	print("[PERF] nodes=%d objects=%d static_mem=%.1fMB video_mem=%.1fMB" % [
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	get_tree().quit(0)


## Measures frame time, script process time, draw calls and primitives over `secs` seconds.
func _measure(secs: float) -> String:
	var frames: Array[float] = []
	var procs: Array[float] = []
	var draws: Array[float] = []
	var prims: Array[float] = []
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() < t_end:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		procs.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	frames.sort()
	procs.sort()
	return "frames=%d frame_ms(avg %.2f, p95 %.2f) process_ms(avg %.2f, p95 %.2f) draw_calls(avg %d) primitives(avg %dk)" % [
		frames.size(), _avg(frames), frames[int(frames.size() * 0.95)], _avg(procs), procs[int(procs.size() * 0.95)],
		int(_avg(draws)), int(_avg(prims) / 1000.0)]


func _avg(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(a.size(), 1)
