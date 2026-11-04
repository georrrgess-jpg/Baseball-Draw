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
##
## Dugout Draft (Update 9): the autopilot takes a boon a second after the cards appear, by each
## boon's "ai_value" with some randomness (so the simulator covers every boon). `--boon-pick=random`
## picks at random, `--boon-pick=first` takes the first card, and `--boon=<id>` always takes that
## boon when it is offered.
##
## `--card-level=N` / `--defender-level=N` play with the deck's cards and the team at that level
## (the simulator's "mid profile", e.g. cards 3 and defenders 5) instead of a fresh level-1 profile.

var battle: Battle
var card_timer := 1.0
var cast_gap := Vector2(1.0, 2.5)   # seconds between casts; `--cast-gap=3,6` models a slower player
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
var boon_pick := "value"            # value | random | first
var boon_force := ""
var boons_offered: Dictionary = {}  # boon id -> times offered (simulator coverage)
var _boon_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_start_msec = Time.get_ticks_msec()
	battle.state_changed.connect(_on_state)
	battle.run_scored.connect(_on_run_scored)
	battle.boss_spawned.connect(_on_boss_spawned)
	play_cards = not ("--no-cards" in OS.get_cmdline_user_args())
	quit_on_finish = bool(Session.run_config.get("auto_quit", true))   # the smoke test keeps going
	if "--auto-stay" in OS.get_cmdline_user_args():   # screenshots of the Results screen
		quit_on_finish = false
	perf = "--perf" in OS.get_cmdline_user_args()
	battle.profile_sections = perf   # per-section timing of the battle loop (battle.prof)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--speed="):
			Engine.time_scale = float(a.split("=")[1])
		if a.begins_with("--cast-gap="):
			var g := a.split("=")[1].split(",")
			cast_gap = Vector2(float(g[0]), float(g[1] if g.size() > 1 else g[0]))
		if a.begins_with("--shop="):
			var ids := a.split("=")[1]
			shop_order = [] if ids == "none" else Array(ids.split(","))
		if a.begins_with("--boon-pick="):
			boon_pick = a.split("=")[1]
		if a.begins_with("--boon="):
			boon_force = a.split("=")[1]
	_boon_rng.seed = hash([battle.run.run_seed, "autopilot_boons"])
	_apply_profile_levels()
	if battle.has_signal("draft_opened"):
		battle.draft_opened.connect(_on_draft)
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


## `--card-level=N` / `--defender-level=N`: raise this (throwaway simulation) profile's deck cards and
## team before the first wave.
func _apply_profile_levels() -> void:
	var changed := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--card-level="):
			var lvl := clampi(int(a.split("=")[1]), 1, DB.card_max_level)
			for cid in battle.run.deck:
				var c: Dictionary = Profile.data.cards.get(cid, {})
				c["owned"] = true
				c["level"] = lvl
				Profile.data.cards[cid] = c
			changed = true
		elif a.begins_with("--defender-level="):
			var dl := clampi(int(a.split("=")[1]), 1, DB.defender_max_level)
			for did in battle.run.team:
				var d: Dictionary = Profile.data.defenders.get(did, {})
				d["level"] = dl
				Profile.data.defenders[did] = d
			changed = true
	if changed:
		battle._refresh_team_stats()


## Dugout Draft: wait until the cards are up (Battle.DRAFT_DELAY), then pick through the overlay.
func _on_draft(offers: Array) -> void:
	for id in offers:
		boons_offered[id] = int(boons_offered.get(id, 0)) + 1
	var pick := choose_boon(offers)
	get_tree().create_timer(Battle.DRAFT_DELAY + 1.0, false).timeout.connect(func() -> void:
		if battle.state != "draft":
			return
		var draft: Node = battle.hud.get("_draft")
		if draft and is_instance_valid(draft) and draft.has_method("pick"):
			draft.pick(pick)   # like a click on the card
		else:
			battle.choose_boon(pick)
		print("%s boon %s (offered %s)" % [log_prefix, pick, offers]))


## The boon the autopilot takes: --boon=<id> if offered, else the best "ai_value" with +-35 %
## noise (value), a random one (random) or the first one (first).
func choose_boon(offers: Array) -> String:
	if boon_force != "" and boon_force in offers:
		return boon_force
	match boon_pick:
		"random":
			return str(offers[_boon_rng.randi() % offers.size()])
		"first":
			return str(offers[0])
	var best := str(offers[0])
	var best_v := -1.0
	for id in offers:
		var b := Boons.get_boon(str(id))
		var v := float(b.get("ai_value", 5.0)) * _boon_rng.randf_range(0.65, 1.35)
		if v > best_v:
			best_v = v
			best = str(id)
	return best


## Dugout shopping: one level of each upgrade per visit, in priority order. `--shop=a,b,c` (or
## `--shop=none`) overrides the order so the balance tools can compare purchase orders. Core upgrades
## are always on offer; specials only when this inning's dugout rolls them (the same roll as
## DugoutScreen._roll_offers), at its 20 % discount.
const SHOP_ORDER := ["stronger_arm", "faster_relay", "base_shield", "wider_coverage", "captains_rally"]
var shop_order: Array = SHOP_ORDER.duplicate()
var upgrades_bought: Dictionary = {}   # upgrade id -> levels bought this run


func _offered_specials() -> Array:
	var r := battle.run
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([r.run_seed, r.inning, "dugout"])
	var specials: Array = []
	for id in DB.upgrade_order:
		var u: Dictionary = DB.upgrades[id]
		if r.upgrade_level(id) < int(u.max) and u.kind != "core":
			specials.append(id)
	for i in range(specials.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = specials[i]
		specials[i] = specials[j]
		specials[j] = t
	var out: Array = []
	for i in mini(2, specials.size()):
		var o := {"id": specials[i]}
		if DB.upgrades[specials[i]].kind == "random_defender":
			o.defender = r.team[rng.randi() % r.team.size()]
		out.append(o)
	return out


func _shop() -> void:
	var r := battle.run
	var specials := _offered_specials()
	for id in shop_order:
		if not DB.upgrades.has(id):
			continue
		var u: Dictionary = DB.upgrades[id]
		var offer: Dictionary = {}
		if u.kind != "core":
			for o: Dictionary in specials:
				if o.id == id:
					offer = o
			if offer.is_empty():
				continue
		var price := r.upgrade_price(id) if u.kind == "core" else RunState.round_price(r.upgrade_price(id) * 0.8)
		if r.upgrade_level(id) >= int(u.max) or r.coins < price:
			continue
		coins_spent += price
		r.coins -= price
		r.upgrades[id] = r.upgrade_level(id) + 1
		upgrades_bought[id] = int(upgrades_bought.get(id, 0)) + 1
		_apply_upgrade(id, offer)
		print("%s bought %s (lvl %d) for %d" % [log_prefix, id, r.upgrade_level(id), price])
	battle._refresh_team_stats()
	var hud: Node = battle.hud
	var dug: Node = hud.get("_dugout")
	if dug and is_instance_valid(dug):
		dug.queue_free()
	battle.next_inning()


## The one-off effects DugoutScreen._buy applies on purchase (the rest are read from run.upgrades).
func _apply_upgrade(id: String, offer: Dictionary) -> void:
	var r := battle.run
	match id:
		"base_shield":
			battle.add_shield(1)
		"card_mastery":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([r.run_seed, r.inning, "mastery", r.upgrade_level(id)])
			var cid: String = r.deck[rng.randi() % r.deck.size()]
			r.card_level_bonus[cid] = int(r.card_level_bonus.get(cid, 0)) + 1
		"hot_streak":
			var did: String = offer.get("defender", r.team[0])
			r.defender_bonus[did] = float(r.defender_bonus.get(did, 0.0)) + float(DB.upgrades[id].effect.defender_damage)
		"new_pitch_card":
			# The autopilot takes the first of the three offered cards.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([r.run_seed, r.inning, "pick", r.upgrade_level(id) - 1])
			var pool: Array = DB.card_order.filter(func(c: String) -> bool: return not c in r.deck)
			if not pool.is_empty():
				var cid: String = pool[rng.randi() % pool.size()]
				r.deck.append(cid)
				r.temp_cards.append(cid)
				battle.cards.add_card(cid)


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
		"bosses": bosses, "upgrades_bought": upgrades_bought, "team": r.team, "assist_by": r.stats.get("assist_by", {}),
		"max_combo": int(r.stats.get("max_combo", 0)), "shield_saves": int(r.stats.get("shield_saves", 0)),
		"reward_coins": int(res.get("coins", 0)), "reward_xp": int(res.get("xp", 0)), "reward_rp": int(res.get("rp", 0)),
		"reward_packs": res.get("packs", []).map(func(pk: Dictionary) -> String: return str(pk.type)),
		"perf": perf_summary(),
		# Update 9: Dugout Draft boons, Endless milestones, early calls, game time (setup + waves + breaks).
		"boons": r.boons, "boons_offered": boons_offered, "milestones": r.milestones,
		"early_calls": int(r.stats.get("early_calls", 0)), "time": float(r.stats.get("time", 0.0)),
		"run_limit_final": r.run_limit,
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
	card_timer = randf_range(cast_gap.x, cast_gap.y)
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
		if battle.has_method("on_card_played"):
			battle.on_card_played(id)
		print("%s cast %s" % [log_prefix, id])
		return


func _live() -> int:
	var n := 0
	for e: Enemy in battle.enemies:
		if e.alive and e.id != "decoy":
			n += 1
	return n


func _target_for(id: String) -> Dictionary:
	var c := DB.card(id)
	var lead := battle.lead_runners(1)
	if lead.is_empty() and id != "base_shield" and id != "seventh_inning_stretch":
		return {}
	match id:
		"called_shot":
			# Save it for the biggest target: the boss, else the toughest runner.
			if battle.boss_alive and is_instance_valid(battle.boss_alive) and battle.boss_alive.targetable():
				return {"enemy": battle.boss_alive, "point": battle.boss_alive.global_position, "valid": true}
			var big: Enemy = null
			for e: Enemy in battle.enemies:
				if e.targetable() and e.id != "decoy" and (big == null or e.max_hp > big.max_hp):
					big = e
			if big == null or big.max_hp < 300.0:
				return {}
			return {"enemy": big, "point": big.global_position, "valid": true}
		"tag_at_the_plate":
			# Only when a runner is about to score and no tag is waiting.
			if (lead[0] as Enemy).remaining() > 8.0 or battle.buff_active("plate_tag"):
				return {}
			return {"valid": true, "point": Field.HOME}
		"bullpen_call":
			if battle.cards.hand_count() > 3:
				return {}
			return {"valid": true, "point": Field.HOME}
		"hot_corner":
			# The defender throwing at the toughest runner (armor / bosses), else the hardest hitter.
			var pick: Defender = null
			var best := -1.0
			for df: Defender in battle.defenders:
				var score := df.s_damage
				if df.target and is_instance_valid(df.target):
					score += 100.0 + df.target.armor * 200.0 + (300.0 if df.target.is_boss else 0.0)
				if score > best:
					best = score
					pick = df
			if pick == null or battle.hot_corner_on(pick):
				return {}
			return {"defender": pick, "point": pick.global_position, "valid": true}
		"perfect_game":
			var live := 0
			for e: Enemy in battle.enemies:
				if e.alive and e.id != "decoy":
					live += 1
			if live < 6 and battle.boss_alive == null and (lead[0] as Enemy).remaining() > 10.0:
				return {}
			return {"valid": true, "point": Field.HOME}
		"bean_ball":
			# Fast runners take double: the fastest threat first, else the lead runner.
			for e: Enemy in battle.lead_runners(6):
				if battle.effects.is_fast(e):
					return {"enemy": e, "point": e.global_position, "valid": true}
			return {"enemy": lead[0], "point": lead[0].global_position, "valid": true}
		"rundown", "intentional_walk":
			# The non-boss runner closest to scoring that isn't already held up.
			for e: Enemy in battle.lead_runners(6):
				if e.is_boss or e.rundown_t > 0.0 or e.slows.has("intentional_walk"):
					continue
				if id == "intentional_walk" and e.remaining() > 14.0:
					return {}
				return {"enemy": e, "point": e.global_position, "valid": true}
			return {}
		"rain_delay":
			if _live() < 5 and battle.boss_alive == null:
				return {}
			return {"valid": true, "point": Field.HOME}
		"momentum":
			if _live() < 4:
				return {}
			return {"valid": true, "point": Field.HOME}
		"around_the_horn":
			if battle.effects.horn_targets(4).size() < 2:
				return {}
			return {"valid": true, "point": Field.HOME}
		"infield_fly":
			# A pop-up just ahead of the lead runner: it runs right into it.
			var e: Enemy = lead[0]
			if not battle.effects.active_item("infield_fly").is_empty():
				return {}
			return {"point": e.route.position_at(minf(e.d + 2.5, e.route.length - 1.0)), "valid": true}
		"golden_glove":
			# The defender with the most runners close by.
			var pick: Defender = null
			var best_n := 0
			for df: Defender in battle.defenders:
				var n := 0
				for e: Enemy in battle.enemies:
					if e.targetable() and not e.is_boss and Field.v2(e.global_position).distance_to(Field.v2(df.global_position)) < 6.0:
						n += 1
				if n > best_n and battle.effects.active_item("golden_glove", df).is_empty():
					best_n = n
					pick = df
			if pick == null:
				return {}
			return {"defender": pick, "point": pick.global_position, "valid": true}
		"diamond_aura":
			# The defender whose aura covers the most throwing power (was a random defender).
			var pick: Defender = null
			var best := -1.0
			var rad := DB.card_param(id, "radius", battle.run.card_level(id))
			for df: Defender in battle.defenders:
				var sum := 0.0
				for o: Defender in battle.defenders:
					if Field.v2(o.global_position).distance_to(Field.v2(df.global_position)) <= rad:
						sum += o.s_damage / maxf(o.s_interval, 0.1)
				if sum > best:
					best = sum
					pick = df
			if pick == null:
				return {}
			return {"defender": pick, "point": pick.global_position, "valid": true}
		"the_shift":
			if _live() < 3:
				return {}
			var sum := Vector3.ZERO
			var leads := battle.lead_runners(4)
			for e: Enemy in leads:
				sum += e.global_position
			return {"point": sum / float(leads.size()), "valid": true}
		"grand_salami":
			# The busiest base path: land on its lead runner, the ball rolls back over the rest.
			var count := {}
			var front := {}
			for e: Enemy in battle.lead_runners(30):
				count[e.route] = int(count.get(e.route, 0)) + 1
				if not front.has(e.route):
					front[e.route] = e
			var best_route: Variant = null
			for rt in count.keys():
				if best_route == null or int(count[rt]) > int(count[best_route]):
					best_route = rt
			if best_route == null or (int(count[best_route]) < 3 and battle.boss_alive == null):
				return {}
			var fe: Enemy = front[best_route]
			return {"point": fe.route.position_at(minf(fe.d + 1.0, fe.route.length - 1.5)), "valid": true}
		"instant_replay":
			var last: Dictionary = battle.effects.last_play
			if last.is_empty() or int(DB.card(String(last.id)).cost) < 3:
				return {}
			return {"valid": true, "point": Field.HOME}
		# Update 9 cards (stream B's targeting rules).
		"second_wind":
			# The hardest thrower, much preferred when its signature card is cooling down.
			var pick: Defender = null
			var best := -1.0
			for df: Defender in battle.defenders:
				var score := df.s_damage / maxf(df.s_interval, 0.1)
				if battle.effects.has_method("signature_cards"):
					for sig in battle.effects.signature_cards(df):
						if sig in battle.cards.deck and battle.cards.cooldown_left(str(sig)) > 3.0:
							score += 1000.0
							break
				if score > best:
					best = score
					pick = df
			if pick == null:
				return {}
			return {"defender": pick, "point": pick.global_position, "valid": true}
		"ground_rule_double":
			if (battle.cards.has_method("double_casts_left") and battle.cards.double_casts_left(battle.run.inning) > 0) or _live() < 3:
				return {}
			return {"valid": true, "point": Field.HOME}
		"rally_monkey":
			if battle.run.runs_inning == 0 and battle.cards.energy > 6.0:
				return {}
			return {"valid": true, "point": Field.HOME}
		"fireworks_night":
			if _live() < 5 and battle.boss_alive == null:
				return {}
			return {"valid": true, "point": Field.HOME}
		"hidden_ball_trick":
			if battle.effects.strongest_runner() == null and battle.boss_alive == null:
				return {}
			return {"valid": true, "point": Field.HOME}
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
