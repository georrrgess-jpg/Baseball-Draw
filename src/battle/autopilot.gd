class_name Autopilot
extends Node
## Plays the game by itself for automated testing and balance simulation:
## starts waves, casts cards at sensible targets, shops in the dugout and logs results.
## Enabled with `-- --test-battle=<mode> --auto` (see boot.gd).

var battle: Battle
var card_timer := 1.0
var log_prefix := "[AUTO]"
var quit_on_finish := true
var play_cards := true
var _last_state := ""
var _start_msec := 0


func _ready() -> void:
	_start_msec = Time.get_ticks_msec()
	battle.state_changed.connect(_on_state)
	play_cards = not ("--no-cards" in OS.get_cmdline_user_args())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			Engine.time_scale = float(a.split("=")[1])
	print("%s start mode=%s difficulty=%s arena=%s team=%s deck=%s" % [log_prefix, battle.run.mode_id,
		battle.run.difficulty_id, battle.run.arena_id, battle.run.team, battle.run.deck])


func _on_state(s: String) -> void:
	if s == _last_state:
		return
	_last_state = s
	var r := battle.run
	print("%s t=%.1fs state=%s inning=%d wave=%d runs=%d/%d outs=%d coins=%d score=%d shields=%d" % [log_prefix,
		(Time.get_ticks_msec() - _start_msec) / 1000.0, s, r.inning, r.wave, r.runs, r.run_limit, r.outs_total, r.coins, r.score, r.shields])
	if s == "dugout":
		get_tree().create_timer(2.5, true, false, true).timeout.connect(_shop)


func _shop() -> void:
	var r := battle.run
	# Buy the cheapest useful upgrades in a fixed priority order.
	for id in ["stronger_arm", "faster_relay", "base_shield", "wider_coverage", "captains_rally"]:
		var u: Dictionary = DB.upgrades[id]
		if r.upgrade_level(id) < int(u.max) and r.coins >= r.upgrade_price(id):
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


func _process(delta: float) -> void:
	if battle.state == "results":
		if quit_on_finish and battle.run.finished:
			var r := battle.run
			print("%s FINISHED won=%s inning=%d runs=%d outs=%d score=%d cards=%d max_combo=%d bosses=%s" % [log_prefix,
				r.won, r.inning, r.runs, r.outs_total, r.score, int(r.stats.get("cards_played", 0)),
				int(r.stats.get("max_combo", 0)), r.stats.get("bosses", [])])
			print("%s damage_by=%s" % [log_prefix, r.stats.damage_by])
			quit_on_finish = false
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
