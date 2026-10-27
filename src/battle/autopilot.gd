class_name Autopilot
extends Node
## Plays the game by itself for automated testing and balance simulation:
## starts waves, casts cards at sensible targets, shops in the dugout and logs results.
## Enabled with `-- --test-battle=<mode> --auto` (see boot.gd).
##
## When the game ends it prints one `[AUTO] STATS {json}` line with everything the balance
## tools need (tools/balance/simulate.py): runs per inning and per runner type, energy left
## unused, coins earned and spent, card plays and impact, defender shares, boss kill times
## and the rewards the run paid out. `--speed=<x>` plays at x times game speed.

var battle: Battle
var card_timer := 1.0
var log_prefix := "[AUTO]"
var quit_on_finish := true
var play_cards := true
var _last_state := ""
var _reported := false
var _start_msec := 0

# ---- balance statistics (game time, so the numbers don't depend on how fast the machine is)
var game_time := 0.0
var wave_time := 0.0
var capped_time := 0.0            # seconds of wave time spent at full energy (regen wasted)
var coins_spent := 0
var card_plays: Dictionary = {}   # card id -> times cast
var spawned_by_type: Dictionary = {}
var runs_by_type: Dictionary = {}
var runs_by_inning: Array = []
var bosses: Array = []            # {id, inning, spawn_t, ttk, result}
var _known: Dictionary = {}       # Enemy -> id, the runners alive last frame
var _inning_runs_start := 0
var _boss_watch: Array = []
# `--perf` samples the engine's process and physics time every frame, split by phase (CPU only:
# a headless run has no GPU, so this is the game-logic and scene cost, not the rendering cost).
var perf := false
var perf_samples: Dictionary = {}   # phase -> {"process": [], "frame": [], "enemies": []}
var _last_frame_us := 0


func _ready() -> void:
	_start_msec = Time.get_ticks_msec()
	battle.state_changed.connect(_on_state)
	battle.run_scored.connect(_on_run_scored)
	battle.boss_spawned.connect(_on_boss_spawned)
	play_cards = not ("--no-cards" in OS.get_cmdline_user_args())
	quit_on_finish = bool(Session.run_config.get("auto_quit", true))   # the smoke test keeps going
	perf = "--perf" in OS.get_cmdline_user_args()
	battle.profile_sections = perf   # per-section timing of the battle loop (battle.prof)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			Engine.time_scale = float(a.split("=")[1])
	print("%s start mode=%s difficulty=%s arena=%s seed=%d team=%s deck=%s" % [log_prefix, battle.run.mode_id,
		battle.run.difficulty_id, battle.run.arena_id, battle.run.run_seed, battle.run.team, battle.run.deck])


func _on_state(s: String) -> void:
	if s == _last_state:
		return
	_last_state = s
	var r := battle.run
	print("%s t=%.1fs game=%.0fs state=%s inning=%d wave=%d runs=%d/%d outs=%d coins=%d score=%d shields=%d" % [log_prefix,
		(Time.get_ticks_msec() - _start_msec) / 1000.0, game_time, s, r.inning, r.wave, r.runs, r.run_limit, r.outs_total, r.coins, r.score, r.shields])
	if s == "setup":
		_inning_runs_start = r.runs
	if s == "dugout" or s == "results":
		if runs_by_inning.size() < r.inning:
			runs_by_inning.append(r.runs - _inning_runs_start)
	if s == "dugout":
		get_tree().create_timer(2.5, true, false, true).timeout.connect(_shop)


func _shop() -> void:
	var r := battle.run
	# Buy the cheapest useful upgrades in a fixed priority order.
	for id in ["stronger_arm", "faster_relay", "base_shield", "wider_coverage", "captains_rally"]:
		var u: Dictionary = DB.upgrades[id]
		if r.upgrade_level(id) < int(u.max) and r.coins >= r.upgrade_price(id):
			coins_spent += r.upgrade_price(id)
			r.coins -= r.upgrade_price(id)
			r.upgrades[id] = r.upgrade_level(id) + 1
			if id == "base_shield":
				battle.add_shield(1)
			print("%s bought %s (lvl %d)" % [log_prefix, id, r.upgrade_level(id)])
	battle._refresh_team_stats()
	var hud: Node = battle.hud
	var dug: Node = hud.get("_dugout")
	if dug and is_instance_valid(dug):
		dug.queue_free()
	battle.next_inning()


func _on_run_scored(n: int) -> void:
	# The runner that scored left battle.enemies this frame while still healthy. Counts the runs
	# that got through (after Base Shields), so the totals match the scoreboard.
	for e in _known.keys():
		if is_instance_valid(e) and not (e in battle.enemies) and (e as Enemy).hp > 0.0 and (e as Enemy).runs > 0:
			var id: String = _known[e]
			runs_by_type[id] = int(runs_by_type.get(id, 0)) + n
			_known.erase(e)
			return


func _on_boss_spawned(e: Enemy) -> void:
	var b := {"id": e.id, "inning": battle.run.inning, "spawn_t": game_time, "ttk": -1.0, "result": "alive"}
	bosses.append(b)
	_boss_watch.append([e, b])


func _track(delta: float) -> void:
	game_time += delta
	var now_us := Time.get_ticks_usec()
	if perf and battle.state == "wave" and _last_frame_us > 0:
		var phase := "boss_wave" if battle.boss_alive != null else "wave"
		if not perf_samples.has(phase):
			perf_samples[phase] = {"process": [], "frame": [], "enemies": []}
		var ps: Dictionary = perf_samples[phase]
		ps.process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		ps.frame.append((now_us - _last_frame_us) / 1000.0)
		ps.enemies.append(battle.enemies.size())
	_last_frame_us = now_us
	if battle.state == "wave":
		wave_time += delta
		if battle.cards.energy >= CardSystem.MAX_ENERGY - 0.01:
			capped_time += delta
	var now: Dictionary = {}
	for e in battle.enemies:
		if not _known.has(e):
			spawned_by_type[e.id] = int(spawned_by_type.get(e.id, 0)) + 1
		now[e] = e.id
	_known = now
	for w in _boss_watch.duplicate():
		var e: Variant = w[0]
		var b: Dictionary = w[1]
		if not is_instance_valid(e) or not (e as Enemy).alive:
			var killed: bool = is_instance_valid(e) and (e as Enemy).hp <= 0.0
			b.result = "out" if killed else "scored"
			b.ttk = game_time - float(b.spawn_t)
			_boss_watch.erase(w)


## Frame-time summary per phase: {phase: {frames, process_ms_avg/p95/max, physics_ms_avg, max_enemies}}.
func perf_summary() -> Dictionary:
	var out := {}
	for phase in perf_samples.keys():
		var ps: Dictionary = perf_samples[phase]
		var pr: Array = ps.process.duplicate()
		pr.sort()
		var n := pr.size()
		if n == 0:
			continue
		var tot := 0.0
		for v in pr:
			tot += v
		var fr: Array = ps.frame.duplicate()
		fr.sort()
		var ft := 0.0
		for v in fr:
			ft += v
		# Performance.TIME_PROCESS is unreliable with --fixed-fps; frame_ms is the wall time between frames.
		out[phase] = {"frames": n, "frame_ms_avg": snappedf(ft / n, 0.01), "frame_ms_p95": snappedf(fr[int(n * 0.95)], 0.01), "frame_ms_max": snappedf(fr[n - 1], 0.01),
			"max_enemies": ps.enemies.max()}
	if battle.profile_sections and battle.prof.has("frames"):
		var frames := float(battle.prof.frames)
		var sec := {}
		for k in battle.prof.keys():
			if k != "frames":
				sec[k] = snappedf(float(battle.prof[k]) / frames / 1000.0, 0.001)
		out["battle_loop_ms_per_frame"] = sec
	return out


func stats_dict() -> Dictionary:
	var r := battle.run
	var res: Dictionary = Session.last_result
	return {
		"mode": r.mode_id, "difficulty": r.difficulty_id, "arena": r.arena_id, "seed": r.run_seed,
		"deck": r.deck, "won": r.won, "inning": r.inning, "wave": r.wave, "runs": r.runs, "run_limit": r.run_limit,
		"outs": r.outs_total, "score": r.score, "game_time": game_time, "wave_time": wave_time,
		"capped_time": capped_time, "energy_wasted": capped_time * CardSystem.BASE_REGEN * battle.cards.regen_mult,
		"coins_earned": r.coins_earned, "coins_spent": coins_spent, "coins_left": r.coins,
		"card_plays": card_plays, "card_impact": r.card_impact, "damage_by": r.stats.damage_by, "outs_by": r.stats.outs_by,
		"runs_by_inning": runs_by_inning, "runs_by_type": runs_by_type, "spawned_by_type": spawned_by_type,
		"bosses": bosses, "max_combo": int(r.stats.get("max_combo", 0)), "shield_saves": int(r.stats.get("shield_saves", 0)),
		"reward_coins": int(res.get("coins", 0)), "reward_xp": int(res.get("xp", 0)), "reward_rp": int(res.get("rp", 0)),
		"reward_packs": res.get("packs", []).map(func(pk: Dictionary) -> String: return str(pk.type)),
		"perf": perf_summary(),
	}


func _process(delta: float) -> void:
	_track(delta)
	if battle.state == "results":
		if not _reported and battle.run.finished:
			_reported = true
			var r := battle.run
			print("%s FINISHED won=%s inning=%d runs=%d outs=%d score=%d cards=%d max_combo=%d bosses=%s" % [log_prefix,
				r.won, r.inning, r.runs, r.outs_total, r.score, int(r.stats.get("cards_played", 0)),
				int(r.stats.get("max_combo", 0)), r.stats.get("bosses", [])])
			print("%s damage_by=%s" % [log_prefix, r.stats.damage_by])
			print("%s STATS %s" % [log_prefix, JSON.stringify(stats_dict())])
			if quit_on_finish:
				get_tree().create_timer(1.0, true, false, true).timeout.connect(func() -> void: get_tree().quit(0))
		return
	if battle.state != "wave" or not play_cards:
		return
	card_timer -= delta
	if card_timer > 0.0:
		return
	card_timer = randf_range(1.0, 2.5)
	var cs := battle.cards
	for i in cs.hand.size():
		if cs.check(i) != "":
			continue
		var id: String = cs.hand[i]
		var tgt := _target_for(id)
		if tgt.is_empty():
			continue
		battle.targeting_index = i
		battle.target_preview = tgt
		var cd: float = battle.effects.caster_info(id).cd
		cs.commit(i, cd)
		battle.run.stats.cards_played = int(battle.run.stats.get("cards_played", 0)) + 1
		card_plays[id] = int(card_plays.get(id, 0)) + 1
		battle.targeting_index = -1
		battle.effects.execute(id, battle.run.card_level(id), tgt)
		print("%s cast %s" % [log_prefix, id])
		return


func _target_for(id: String) -> Dictionary:
	var c := DB.card(id)
	var lead := battle.lead_runners(1)
	if lead.is_empty() and id != "base_shield" and id != "seventh_inning_stretch":
		return {}
	match c.target:
		"enemy":
			return {"enemy": lead[0], "point": lead[0].global_position, "valid": true}
		"area":
			# Centre on the densest cluster near the lead runner.
			var best: Vector3 = lead[0].global_position
			var best_n := 0
			for e: Enemy in battle.enemies:
				if not e.targetable():
					continue
				var n := battle.enemies_in_radius(e.global_position, float(c.get("radius", 3.0))).size()
				if n > best_n:
					best_n = n
					best = e.global_position
			if best_n < 2 and DB.card(id).rarity in ["epic", "legendary"]:
				return {}
			return {"point": best, "valid": true}
		"path":
			var e: Enemy = lead[0]
			return {"point": e.route.position_at(minf(e.d + 4.0, e.route.length - 2.0)), "valid": true}
		"defender":
			return {"defender": battle.defenders[randi() % battle.defenders.size()], "valid": true}
		_:
			if id == "base_shield" and battle.run.shields >= 2:
				return {}
			return {"valid": true, "point": Field.HOME}
