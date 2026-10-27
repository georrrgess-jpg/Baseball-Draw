class_name Battle
extends Node3D
## Orchestrates a run: builds the arena, spawns defenders, runs waves and innings,
## resolves outs/runs/combos, routes input (placement, card targeting, camera)
## and hands off to the dugout and results screens.

signal state_changed(state: String)
signal score_changed
signal selection_changed(defender: Defender)
signal wave_started(info: Dictionary)
signal targeting_changed(card_index: int)
signal banner_requested(text: String, color: Color)
signal card_cast(id: String)
signal card_denied(index: int, reason: String)
signal defender_moved(defender: Defender)
signal run_scored(runs: int)
signal boss_spawned(enemy: Enemy)

const COMBO_WINDOW := 1.35
const BREAK_TIME := 12.0
const SPEEDS := [1.0, 2.0, 3.0]
## Characters are drawn larger than life so they read clearly from the tactical camera.
const UNIT_SCALE := 1.55

var run: RunState
var arena: Dictionary
var layout: Dictionary
var routes: Array[Route] = []
var gate_positions: Dictionary = {}
var defenders: Array[Defender] = []
var enemies: Array[Enemy] = []
var walls: Array = []
var traps: Array = []
var zones: Array = []
var buffs: Array = []
var cards: CardSystem
var effects: CardEffects
var projectiles: ProjectileManager
var vfx: VFX
var cam: CameraRig
var stadium: StadiumBuilder
var hud: Node
var field_mat: ShaderMaterial
var shield_dome: MeshInstance3D

var state := "loading"           # setup | wave | break | dugout | results
var wave_info: Dictionary = {}
var spawn_queue: Array = []
var wave_time := 0.0
var wave_spawned := 0
var wave_total := 0
var break_timer := 0.0
var combo_count := 0
var combo_timer := 0.0
var field_vision_active := false
var speed_index := 0
var selected: Defender = null
var dragging: Defender = null
var drag_valid := false
var hover_defender: Defender = null
var hover_enemy: Enemy = null
var targeting_index := -1
var target_preview: Dictionary = {}
var last_cast_point: Variant = null   # world point of the last cast (HUD flourish target)
var practice := false
var practice_invulnerable := true
var spawn_counter := 0
var excitement := 0.2
var boss_alive: Enemy = null
var cards_played_run := 0
var inning_start_runs := 0
var active_synergies: Array = []
var _hud_timer := 0.0
var _drag_ghost: MeshInstance3D
var _target_ring: MeshInstance3D
var _target_line: MeshInstance3D
var _mouse_pos := Vector2.ZERO
var _uniform_colors: Dictionary = {}
var auto_test := false
var _danger_ring: MeshInstance3D
var _preview_marked: Array = []
var _danger := 0.0
var _danger_warned := 0.0


func _ready() -> void:
	var cfg: Dictionary = Session.run_config
	if cfg.is_empty():
		cfg = Session.new_run_config("quick")
	if cfg.get("resume") != null and typeof(cfg.resume) == TYPE_DICTIONARY:
		run = RunState.from_dict(cfg.resume)
	else:
		run = RunState.create(cfg)
	practice = run.is_practice()
	auto_test = bool(cfg.get("auto_test", false))
	arena = DB.arena(run.arena_id)
	layout = DB.layout_for_arena(run.arena_id)
	_uniform_colors = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.get("home", {})).get("colors", {})

	for r in layout.get("routes", []):
		routes.append(Route.from_points(r.id, r.gate, r.points))
	for gid in layout.get("gates", {}).keys():
		var g: Array = layout.gates[gid]
		gate_positions[gid] = Vector3(float(g[0]), 0, float(g[1]))

	stadium = StadiumBuilder.new()
	stadium.build(self, arena, layout)
	field_mat = FieldBuilder.build(self, arena.get("theme", {}), routes)

	vfx = VFX.new()
	vfx.name = "VFX"
	add_child(vfx)
	projectiles = ProjectileManager.new()
	projectiles.name = "Projectiles"
	projectiles.battle = self
	add_child(projectiles)
	effects = CardEffects.new(self)

	cam = CameraRig.new()
	cam.name = "CameraRig"
	add_child(cam)
	cam.set_view(Vector3(0, 0, -8), 0.0, -30.0, 70.0, true)

	_spawn_team()
	cards = CardSystem.new()
	cards.setup(run.deck, run.energy, run.run_seed + run.inning * 101)
	_apply_card_mods()
	if practice:
		cards.infinite_energy = true

	_target_ring = FieldBuilder.make_ring(3.0, Color(1, 1, 1, 0.9), 0.05, 0.18)
	_target_ring.visible = false
	add_child(_target_ring)
	_drag_ghost = FieldBuilder.make_ring(1.0, Color(0.3, 1.0, 0.5, 0.95), 0.12, 0.25)
	_drag_ghost.visible = false
	add_child(_drag_ghost)
	_target_line = MeshInstance3D.new()
	var tl := PlaneMesh.new()
	tl.size = Vector2(1, 1)
	_target_line.mesh = tl
	var tlm := StandardMaterial3D.new()
	tlm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tlm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tlm.albedo_color = Color(1.0, 0.45, 0.1, 0.35)
	tlm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_target_line.material_override = tlm
	_target_line.visible = false
	add_child(_target_line)

	_danger_ring = FieldBuilder.make_ring(4.2, Color(1.0, 0.15, 0.1, 0.0), 0.06, 0.12)
	_danger_ring.position = Vector3(Field.HOME.x, 0.06, Field.HOME.z)
	(_danger_ring.material_override as ShaderMaterial).set_shader_parameter("pulse", 1.0)
	add_child(_danger_ring)
	shield_dome = vfx.make_shield_dome()
	shield_dome.global_position = Field.HOME
	_update_shield_dome()

	var hud_script: Script = load("res://src/ui/battle_hud.gd")
	hud = hud_script.new()
	hud.battle = self
	add_child(hud)

	Audio.play_ambience(["stadium_crowd", "wind_industrial"])
	if practice:
		Audio.play_music("practice_theme")
	else:
		Audio.play_music("battle_theme")
	_update_scoreboard()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cam-view="):
			var v := a.split("=")[1].split(",")
			cam.set_view(Vector3(float(v[0]), 0, float(v[1])), float(v[2]), float(v[3]), float(v[4]), true)
			cam.cinematic = true
		elif a == "--no-hud":
			hud.visible = false
	if auto_test:
		var ap := Autopilot.new()
		ap.battle = self
		add_child(ap)
	_intro()


func _intro() -> void:
	var fixed_cam := cam.cinematic
	cam.cinematic = true
	var tw := create_tween()
	tw.tween_interval(0.2)
	tw.tween_callback(func() -> void:
		if not fixed_cam:
			cam.default_view())
	tw.tween_interval(1.4)
	tw.tween_callback(func() -> void:
		if not "--keep-cam" in OS.get_cmdline_user_args():
			cam.cinematic = false
		var resume: Variant = Session.run_config.get("resume")
		var args := OS.get_cmdline_user_args()
		if "--open-dugout" in args:
			run.coins = 260
			_open_dugout()
		elif "--show-results" in args:
			# Screenshot/debug shortcut: a plausible finished three-inning game.
			run.outs_total = 64
			run.coins_earned = 400
			run.score = 6850
			run.runs = 1
			run.stats.cards_played = 14
			run.stats.double_plays = 5
			run.stats.triple_plays = 1
			run.stats.max_combo = 4
			run.stats.bosses = [run.boss_for_inning(run.inning)] if run.boss_for_inning(run.inning) != "" else []
			for i in run.team.size():
				run.stats.damage_by[run.team[i]] = 1800 + 700 * ((i * 5) % 6)
				run.stats.outs_by[run.team[i]] = 6 + (i * 7) % 9
			finish_run(true)
		elif typeof(resume) == TYPE_DICTIONARY and bool(resume.get("in_dugout", false)):
			_open_dugout()
		else:
			_enter_setup())


func _apply_card_mods() -> void:
	cards.regen_mult = float(DB.difficulty(run.difficulty_id).energy_regen) * (1.0 + run.modifier_total("energy_regen") + _synergy_value("energy_regen"))
	cards.draw_interval = CardSystem.BASE_DRAW_INTERVAL / (1.0 + run.modifier_total("draw_speed"))
	cards.cooldown_mult = 1.0 + run.modifier_total("card_cooldown")


# ---------------------------------------------------------------- team

func _spawn_team() -> void:
	var positions := formation_positions(run.formation, run.team)
	for i in run.team.size():
		var id: String = run.team[i]
		var df := Defender.new()
		df.name = "Def_" + id
		add_child(df)
		defenders.append(df)
		df.setup(self, id, _uniform_colors)
		var pos: Vector3 = positions.get(id, Vector3(0, 0, 0))
		if run.positions.has(id):
			var p: Array = run.positions[id]
			pos = Vector3(float(p[0]), 0, float(p[1]))
		df.targeting = run.targeting.get(id, df.targeting)
		df.place(find_valid_spot(pos, df))
		df.set_captain(id == run.captain)
	_refresh_team_stats()


## Positions for a formation: role slots are filled first, remaining defenders take what's left.
func formation_positions(formation_id: String, team: Array) -> Dictionary:
	var f: Dictionary = DB.formations.get(formation_id, {})
	var raw: Array = []
	if f.is_empty() and Profile.data.custom_formations.has(formation_id):
		raw = Profile.data.custom_formations[formation_id].get("positions", [])
		# Custom formations store positions per defender id.
		var by_id: Dictionary = Profile.data.custom_formations[formation_id].get("by_id", {})
		if not by_id.is_empty():
			var out := {}
			for id in team:
				if by_id.has(id):
					out[id] = Vector3(float(by_id[id][0]), 0, float(by_id[id][1]))
			var rest := formation_positions("balanced", team)
			for id in team:
				if not out.has(id):
					out[id] = rest[id]
			return out
	if raw.is_empty():
		raw = DB.formations.get(formation_id, DB.formations.balanced).positions
	var slots: Array = DB.formation_slots
	var assigned := {}
	var used := []
	for pass_i in 2:
		for id in team:
			if assigned.has(id):
				continue
			var role: String = DB.defender(id).role
			for s in slots.size():
				if s in used:
					continue
				if pass_i == 1 or slots[s] == role:
					assigned[id] = Vector3(float(raw[s][0]), 0, float(raw[s][1]))
					used.append(s)
					break
	return assigned


func apply_formation(formation_id: String) -> void:
	run.formation = formation_id
	var pos := formation_positions(formation_id, run.team)
	for df in defenders:
		df.place(find_valid_spot(pos.get(df.id, df.post), df))
		vfx.dust(df.global_position, 0.6)
	run.positions.clear()
	_refresh_team_stats()
	Audio.play("footstep_dirt", -4.0)


func mirror_formation() -> void:
	for df in defenders:
		var p := df.post
		df.place(find_valid_spot(Vector3(-p.x, 0, p.z), df, true))
	_refresh_team_stats()


## Checks whether a defender may stand at p. Returns "" or the reason.
func placement_error(p: Vector3, df: Defender) -> String:
	if not Field.in_playable_area(p):
		return "Out of bounds"
	for r in routes:
		if r.distance_to_point(p) < Field.PATH_CLEARANCE:
			return "Too close to a runner route"
	for b in Field.bases():
		if Field.v2(b).distance_to(Field.v2(p)) < Field.BASE_CLEARANCE:
			return "Can't stand on a base"
	for o in defenders:
		if o != df and Field.v2(o.post).distance_to(Field.v2(p)) < Field.UNIT_SPACING:
			return "Too close to a teammate"
	return ""


## Finds the nearest valid spot (spiral search) — used for presets and drops.
func find_valid_spot(p: Vector3, df: Defender, ignore_others := false) -> Vector3:
	if placement_error(p, df) == "" or (ignore_others and _err_ignoring_units(p) == ""):
		return p
	for ring in range(1, 14):
		var r := ring * 0.5
		for k in 16:
			var a := TAU * k / 16.0
			var q := p + Vector3(cos(a) * r, 0, sin(a) * r)
			if placement_error(q, df) == "":
				return q
	return p


func _err_ignoring_units(p: Vector3) -> String:
	if not Field.in_playable_area(p):
		return "x"
	for r in routes:
		if r.distance_to_point(p) < Field.PATH_CLEARANCE:
			return "x"
	return ""


func _refresh_team_stats() -> void:
	_compute_synergies()
	for df in defenders:
		df.recompute()
	if cards:
		_apply_card_mods()
	score_changed.emit()


# ---------------------------------------------------------------- synergies

func _compute_synergies() -> void:
	active_synergies.clear()
	for syn in DB.synergies:
		var req: Dictionary = syn.requires
		var members: Array = []
		var ok := true
		if req.has("roles"):
			for role in req.roles.keys():
				var have: Array = []
				for df in defenders:
					if df.role == role:
						if syn.get("effect", {}).get("zone", "") != "" and df.zone != syn.effect.zone:
							continue
						have.append(df)
				if have.size() < int(req.roles[role]):
					ok = false
					break
				members.append_array(have)
		if req.has("ids"):
			for id in req.ids:
				var found := false
				for df in defenders:
					if df.id == id:
						members.append(df)
						found = true
				if not found:
					ok = false
		if not ok:
			continue
		var within := float(syn.get("within", 0.0))
		if within > 0.0:
			# Need at least one pair of the required roles within range.
			var close: Array = []
			for a in members:
				for b in members:
					if a != b and a.role != b.role or (a != b and syn.id == "double_play_duo"):
						if Field.v2(a.post).distance_to(Field.v2(b.post)) <= within:
							if not a in close:
								close.append(a)
			if close.size() < 2:
				continue
			members = close
		active_synergies.append({"data": syn, "members": members})


func synergy_bonus_for(df: Defender) -> Dictionary:
	var out := {}
	for s in active_synergies:
		var eff: Dictionary = s.data.effect
		if eff.get("scope", "team") == "members" and not df in s.members:
			continue
		for k in eff.keys():
			if k in ["scope", "zone"]:
				continue
			out[k] = float(out.get(k, 0.0)) + float(eff[k])
	return out


func synergy_active(id: String) -> bool:
	for s in active_synergies:
		if s.data.id == id:
			return true
	return false


func _synergy_value(key: String) -> float:
	var v := 0.0
	for s in active_synergies:
		v += float(s.data.effect.get(key, 0.0))
	return v


# ---------------------------------------------------------------- flow

func set_state(s: String) -> void:
	state = s
	state_changed.emit(s)


func _enter_setup() -> void:
	set_state("setup")
	field_mat.set_shader_parameter("zones_alpha", 0.45 if practice else 1.0)
	for df in defenders:
		df.reset_wave_state()
	excitement = 0.25
	if practice:
		notify("PRACTICE FIELD", Color(0.5, 0.9, 1.0))
	elif run.wave == 0:
		var title := "INNING %d" % run.inning
		if run.is_final_inning():
			title = "FINAL INNING"
		notify(title, Color(1.0, 0.85, 0.35))
		_pick_endless_modifier()
	if auto_test:
		get_tree().create_timer(0.5).timeout.connect(begin_wave)


func _pick_endless_modifier() -> void:
	if not run.is_endless() or run.inning < 2:
		return
	var ids: Array = DB.endless_modifiers.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.run_seed, run.inning, "mod"])
	var keep: Array = run.config.get("modifiers", [])
	run.modifiers = keep.duplicate()
	var pick: String = ids[rng.randi() % ids.size()]
	run.modifiers.append(pick)
	notify("MODIFIER: " + DB.endless_modifiers[pick].name.to_upper(), Color(1.0, 0.6, 0.3))
	_refresh_team_stats()


func can_reposition() -> bool:
	return state in ["setup", "break"] or practice


func begin_wave() -> void:
	if state not in ["setup", "break"] or practice:
		return
	if state == "break" and break_timer > 0.5:
		var bonus := int(break_timer)
		if bonus > 0:
			run.coins += bonus
			run.stats.early_calls = int(run.stats.get("early_calls", 0)) + 1
			vfx.text_popup(Field.HOME + Vector3(0, 3, 0), "+%d EARLY CALL" % bonus, UITheme.GOLD, 1.0)
	_cancel_drag()
	field_mat.set_shader_parameter("zones_alpha", 0.0)
	wave_info = WaveGenerator.generate(run, run.wave, routes.size())
	var hp_mult := WaveGenerator.hp_multiplier(run)
	var spd_mult := WaveGenerator.speed_multiplier(run)
	spawn_queue.clear()
	for g in wave_info.groups:
		var route_i := int(g.route) % routes.size()
		for i in int(g.count):
			spawn_queue.append({"time": float(g.start) + i * float(g.interval), "enemy": g.enemy, "route": route_i,
				"affix": g.affix, "hp_mult": hp_mult, "speed_mult": spd_mult})
	spawn_queue.sort_custom(func(a, b) -> bool: return a.time < b.time)
	wave_total = spawn_queue.size()
	wave_spawned = 0
	wave_time = 0.0
	set_state("wave")
	for df in defenders:
		df.reset_wave_state()
	cards.add_energy(1.0)
	var opened := {}
	for s in spawn_queue:
		opened[routes[s.route].gate] = true
	for gid in opened.keys():
		stadium.set_gate_open(gid, true)
	Audio.play("gate_open", -4.0)
	Audio.play("wave_start")
	if wave_info.boss != "":
		Audio.play_music("boss_theme")
		Audio.play("boss_warning")
		notify("BOSS: " + DB.enemy(wave_info.boss).name.to_upper(), Color(1.0, 0.3, 0.2))
	else:
		notify("WAVE %d — PLAY BALL!" % (run.wave + 1), Color(1.0, 1.0, 1.0))
	wave_started.emit(wave_info)
	_update_scoreboard()


func _on_wave_cleared() -> void:
	for gid in stadium.gates.keys():
		stadium.set_gate_open(gid, false)
	run.wave += 1
	Audio.play("wave_clear")
	cards.add_energy(1.0)
	if boss_alive == null and wave_info.get("boss", "") != "":
		Audio.play_music("battle_theme")
	if run.wave >= run.waves_per_inning:
		_on_inning_complete()
	else:
		set_state("break")
		break_timer = BREAK_TIME
		field_mat.set_shader_parameter("zones_alpha", 0.6)
		notify("WAVE CLEAR!", Color(0.5, 1.0, 0.6))
		if auto_test:
			get_tree().create_timer(0.3).timeout.connect(begin_wave)
	_update_scoreboard()


func _on_inning_complete() -> void:
	var clean := run.runs_inning == 0
	var bonus := 20 + run.inning * 4
	if clean:
		bonus += 15
		run.stats.clean_innings = int(run.stats.get("clean_innings", 0)) + 1
		run.score += 100
	run.coins += bonus
	run.coins_earned += bonus
	run.stats.runs_by_inning.append(run.runs_inning)
	crowd_cheer(1.0)
	Audio.play("inning_end")
	for df in defenders:
		df.celebrate()
	stadium.scoreboard_ui.flash("SIDE RETIRED!" if clean else "INNING OVER", 3.0)
	notify("INNING %d COMPLETE  +%d coins" % [run.inning, bonus], Color(1.0, 0.85, 0.35))
	if run.is_endless() and run.inning % 5 == 0:
		run.coins += 50
		run.score += 1000
		notify("MILESTONE: INNING %d!" % run.inning, UITheme.GOLD)
	if run.max_innings > 0 and run.inning >= run.max_innings:
		get_tree().create_timer(1.6).timeout.connect(func() -> void: finish_run(true))
		set_state("results")
		return
	set_state("dugout")
	get_tree().create_timer(1.8).timeout.connect(_open_dugout)


func _open_dugout() -> void:
	set_state("dugout")
	Audio.play_music("dugout_theme")
	# Save at the inning boundary so the run can be continued later.
	var d := run.to_dict()
	d["in_dugout"] = true
	_store_positions(d)
	if not practice and not auto_test:
		Profile.store_run(d)
	if hud.has_method("open_dugout"):
		hud.open_dugout()


## Called by the dugout screen when the player is ready for the next inning.
func next_inning() -> void:
	run.inning += 1
	run.wave = 0
	run.outs_inning = 0
	run.runs_inning = 0
	cards.refill()
	for id in run.temp_cards:
		if not id in cards.deck:
			cards.add_card(id)
	_refresh_team_stats()
	var d := run.to_dict()
	d["in_dugout"] = false
	_store_positions(d)
	if not practice and not auto_test:
		Profile.store_run(d)
	Audio.play_music("battle_theme")
	cam.default_view()
	_enter_setup()
	_update_scoreboard()


func _store_positions(d: Dictionary) -> void:
	var pos := {}
	var tgt := {}
	for df in defenders:
		pos[df.id] = [df.post.x, df.post.z]
		tgt[df.id] = df.targeting
	d.positions = pos
	d.targeting = tgt
	run.positions = pos
	run.targeting = tgt


func finish_run(won: bool) -> void:
	if run.finished:
		return
	run.finished = true
	run.won = won
	set_state("results")
	Engine.time_scale = 1.0
	_cancel_targeting()
	for e in enemies:
		if e.alive:
			e.freeze_t = 999.0
	if won:
		Audio.play_music("victory")
		Audio.play("victory_fanfare")
		crowd_cheer(1.0)
		for df in defenders:
			df.victory()
		vfx.burst("confetti", Field.HOME + Vector3(0, 6, -6))
		vfx.burst("confetti", Field.MOUND + Vector3(0, 6, 0))
	else:
		Audio.play_music("defeat")
		Audio.play("defeat_sting")
		Audio.play("crowd_groan")
	cam.set_view(Field.MOUND, 0.0, -24.0, 26.0)
	cam.orbit(8.0)
	var result := {}
	if not practice:
		result = Rewards.apply(run, won)
		Profile.clear_run()
	else:
		result = {"practice": true}
	Session.last_result = result
	if hud.has_method("show_results"):
		hud.show_results(result)


func abandon() -> void:
	if practice:
		Router.goto("main_menu")
		return
	finish_run(false)


# ---------------------------------------------------------------- spawning

func spawn_enemy(id: String, route: Route, start_d := 0.0, opts: Dictionary = {}) -> Enemy:
	var e := Enemy.new()
	spawn_counter += 1
	e.spawn_order = spawn_counter
	e.name = "Enemy_%d" % spawn_counter
	add_child(e)
	if not opts.has("hp_mult"):
		opts.hp_mult = WaveGenerator.hp_multiplier(run)
	if not opts.has("speed_mult"):
		opts.speed_mult = WaveGenerator.speed_multiplier(run)
	if not opts.has("lateral"):
		opts.lateral = randf_range(-0.9, 0.9)
	opts.armor_add = run.modifier_total("enemy_armor")
	e.setup(self, id, route, start_d, opts)
	enemies.append(e)
	if e.is_boss:
		boss_alive = e
		cam.shake(0.3)
		Audio.play("boss_roar")
		Audio.duck_music(8.0, 2.0)
		if hud.has_method("show_boss"):
			hud.show_boss(e)
		boss_spawned.emit(e)
		_boss_intro(route)
	return e


## Brief camera move to the boss's gate, then back to where the player was looking.
func _boss_intro(route: Route) -> void:
	if auto_test or cam.cinematic:
		return
	var saved := [cam._t_focus, cam._t_yaw, cam._t_pitch, cam._t_distance]
	var gate := route.points[0]
	cam.cinematic = true
	cam.set_view(gate.lerp(Field.HOME, 0.18), cam._t_yaw, -30.0, 24.0)
	get_tree().create_timer(2.4).timeout.connect(func() -> void:
		cam.set_view(saved[0], saved[1], saved[2], saved[3])
		cam.cinematic = false)


func _process_spawns(delta: float) -> void:
	wave_time += delta
	while not spawn_queue.is_empty() and spawn_queue[0].time <= wave_time:
		var s: Dictionary = spawn_queue.pop_front()
		var route := routes[int(s.route)]
		spawn_enemy(s.enemy, route, 0.0, {"affix": s.affix, "hp_mult": s.hp_mult, "speed_mult": s.speed_mult})
		wave_spawned += 1
		vfx.dust(route.points[0] + Vector3(0, 0, 0), 0.6)


# ---------------------------------------------------------------- outs & runs

func on_enemy_out(e: Enemy, info: Dictionary) -> void:
	enemies.erase(e)
	if e == boss_alive:
		boss_alive = null
		_on_boss_defeated(e)
	if e.id == "decoy":
		vfx.puff(e.center(), Color(0.6, 0.35, 1.0))
		e.queue_free()
		return
	var src: Defender = info.get("source") if info.get("source") is Defender else null
	var src_id := src.id if src and is_instance_valid(src) else ""
	run.add_out(src_id)
	run.add_card_impact(str(info.get("card", "")), 0.0, 1)
	if src and is_instance_valid(src):
		src.outs += 1
	var coin := int(round(e.coins * (1.0 + run.modifier_total("coin_mult"))))
	run.coins += coin
	run.coins_earned += coin
	run.score += 10 + e.coins * 2
	vfx.burst("out", e.center())
	if coin >= 12:
		vfx.text_popup(e.center() + Vector3(0.7, 0.4, 0), "+%d" % coin, UITheme.GOLD, 0.75, 0.9)
	Audio.play("enemy_out", -6.0, 0.06, 60)
	Audio.play("coin", -14.0, 0.05, 90)
	# Combos
	if combo_timer > 0.0:
		combo_count += 1
	else:
		combo_count = 1
	combo_timer = COMBO_WINDOW
	if combo_count >= 2:
		_on_combo(combo_count)
	run.stats.max_combo = maxi(int(run.stats.get("max_combo", 0)), combo_count)
	excitement = minf(1.0, excitement + 0.08)
	if not practice:
		Profile.bump_stat("total_outs")
	score_changed.emit()
	_update_scoreboard()


func _on_combo(n: int) -> void:
	var text := ""
	var coins_bonus := 0
	match n:
		2:
			text = "DOUBLE PLAY!"
			coins_bonus = 2
			run.stats.double_plays = int(run.stats.get("double_plays", 0)) + 1
			Audio.play("combo_double")
			if not practice:
				Profile.bump_stat("double_plays")
		3:
			text = "TRIPLE PLAY!"
			coins_bonus = 5
			run.stats.triple_plays = int(run.stats.get("triple_plays", 0)) + 1
			Audio.play("combo_triple")
			if not practice:
				Profile.bump_stat("triple_plays")
		_:
			text = "GRAND SLAM COMBO x%d!" % n
			coins_bonus = 2
			if n == 4:
				run.stats.grand_combos = int(run.stats.get("grand_combos", 0)) + 1
				if not practice:
					Profile.bump_stat("grand_combos")
			Audio.play("combo_grand")
	run.coins += coins_bonus
	run.coins_earned += coins_bonus
	run.score += 25 * n
	if n == 3 or n == 5:
		cards.add_energy(1.0)
	notify(text, Color(1.0, 0.8, 0.25) if n < 4 else Color(1.0, 0.45, 0.2))
	stadium.scoreboard_ui.flash(text.replace("!", ""), 1.8)
	crowd_cheer(0.8)


func on_enemy_reached_home(e: Enemy) -> void:
	if not e.alive:
		return
	e.alive = false
	enemies.erase(e)
	if e == boss_alive:
		boss_alive = null
		if hud.has_method("hide_boss"):
			hud.hide_boss()
	if e.id == "decoy" or e.runs <= 0:
		vfx.puff(e.center(), Color(0.6, 0.35, 1.0))
		e.queue_free()
		return
	var runs_scored := e.runs
	var absorbed := mini(run.shields, runs_scored)
	if absorbed > 0 and absorbed < runs_scored:
		# Partial block: shields soak what they can, the rest scores.
		run.shields -= absorbed
		run.stats.shield_saves = int(run.stats.get("shield_saves", 0)) + absorbed
		vfx.shockwave(Field.HOME, 3.0, Color(0.4, 0.85, 1.0), 0.5)
		Audio.play("shield_block")
		_update_shield_dome()
		runs_scored -= absorbed
	elif absorbed > 0:
		run.shields -= absorbed
		run.add_out("")
		run.stats.shield_saves = int(run.stats.get("shield_saves", 0)) + absorbed
		if not practice:
			Profile.bump_stat("shield_saves", absorbed)
		Audio.play("shield_block")
		vfx.shockwave(Field.HOME, 3.0, Color(0.4, 0.85, 1.0), 0.5)
		vfx.text_popup(Field.HOME + Vector3(0, 2.5, 0), "OUT AT THE PLATE!", Color(0.5, 0.9, 1.0), 1.2)
		_update_shield_dome()
		e.model.play_action("defeat")
		e.alive = false
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			if is_instance_valid(e):
				e.queue_free())
		score_changed.emit()
		return
	if not (practice and practice_invulnerable):
		run.runs += runs_scored
		run.runs_inning += runs_scored
	Audio.play("run_scored")
	Audio.play("crowd_groan", -4.0)
	run_scored.emit(runs_scored)
	cam.shake(0.45)
	hud_flash(Color(1.0, 0.1, 0.1, 0.25))
	notify("RUN SCORED! (%d/%d)" % [run.runs, run.run_limit] if not practice else "RUN SCORED", Color(1.0, 0.3, 0.25))
	stadium.scoreboard_ui.flash("RUN SCORED", 2.0)
	e.model.play_action("taunt")
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_callback(func() -> void:
		if is_instance_valid(e):
			e.queue_free())
	score_changed.emit()
	_update_scoreboard()
	if run.runs >= run.run_limit and not practice:
		notify("GAME OVER", Color(1.0, 0.2, 0.2))
		get_tree().create_timer(1.2).timeout.connect(func() -> void: finish_run(false))
		set_state("results")


func _on_boss_defeated(e: Enemy) -> void:
	if hud.has_method("hide_boss"):
		hud.hide_boss()
	run.score += 500
	if not e.id in run.stats.bosses:
		run.stats.bosses.append(e.id)
	if not practice:
		Profile.bump_stat("boss_" + e.id)
	notify("%s DEFEATED!" % e.data.name.to_upper(), UITheme.GOLD)
	vfx.burst("confetti", e.center() + Vector3(0, 3, 0))
	crowd_cheer(1.0)
	cam.shake(0.5)
	Audio.play("crowd_cheer")


func add_shield(n: int) -> void:
	run.shields = mini(run.shields + n, 3)
	Audio.play("shield_block")
	vfx.shockwave(Field.HOME, 2.4, Color(0.4, 0.85, 1.0), 0.4)
	_update_shield_dome()
	score_changed.emit()


func _update_shield_dome() -> void:
	shield_dome.visible = run.shields > 0
	if run.shields > 0:
		(shield_dome.material_override as ShaderMaterial).set_shader_parameter("strength", 0.6 + 0.4 * run.shields)


# ---------------------------------------------------------------- combat helpers

func deal_damage(e: Enemy, amount: float, info: Dictionary) -> float:
	if not is_instance_valid(e) or not e.alive:
		return 0.0
	var dealt := e.take_damage(amount, info)
	var src = info.get("source")
	on_damage_dealt(src if src is Defender else null, e, dealt, info.get("crit", false))
	return dealt


func on_damage_dealt(source: Variant, e: Enemy, dealt: float, crit: bool) -> void:
	if dealt <= 0.0:
		return
	if source is Defender and is_instance_valid(source):
		(source as Defender).damage_dealt += dealt
		run.add_damage((source as Defender).id, dealt)
	# Only crits and big hits get a number, so steady defender throws don't bury the field in text.
	if crit or dealt >= maxf(90.0, e.max_hp * 0.2):
		vfx.damage_number(e.center() + Vector3(0, 0.4, 0), dealt, crit)


func on_curve_heat() -> void:
	if int(run.stats.get("curve_heat", 0)) == 0 and not practice:
		Profile.bump_stat("curve_heat")
	run.stats.curve_heat = int(run.stats.get("curve_heat", 0)) + 1


func enemies_in_radius(p: Vector3, r: float) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in enemies:
		if e.targetable() and Field.v2(e.global_position).distance_to(Field.v2(p)) <= r:
			out.append(e)
	return out


func nearest_enemy(p: Vector3, r: float, exclude: Array = []) -> Enemy:
	var best: Enemy = null
	var best_d := r
	for e in enemies:
		if not e.targetable() or e in exclude:
			continue
		var d := e.global_position.distance_to(p)
		if d < best_d:
			best_d = d
			best = e
	return best


## Runners closest to scoring, most dangerous first.
func lead_runners(n: int) -> Array:
	var list: Array = []
	for e in enemies:
		if e.targetable() and e.id != "decoy":
			list.append(e)
	list.sort_custom(func(a, b) -> bool: return a.remaining() < b.remaining())
	return list.slice(0, n)


func add_zone(z: Node3D) -> void:
	add_child(z)
	zones.append(z)


func remove_zone(z: Node3D) -> void:
	zones.erase(z)


func add_wall(p: Vector3, hp: float, dur: float) -> void:
	var snap := snap_to_route(p)
	var w := DirtWall.new()
	add_child(w)
	w.setup(self, snap.point, snap.dir, hp, dur)
	walls.append(w)


func add_trap(p: Vector3, charges: int, root_t: float, dmg: float) -> void:
	var snap := snap_to_route(p)
	var t := BuntTrap.new()
	add_child(t)
	t.setup(self, snap.point, charges, root_t, dmg)
	traps.append(t)


## Nearest point on any route (used by path-targeted cards).
func snap_to_route(p: Vector3) -> Dictionary:
	var best := {"point": p, "dir": Vector3(0, 0, 1), "dist": INF}
	for r in routes:
		var pr: Dictionary = r.project(p)
		if float(pr.dist) < float(best.dist):
			var d := clampf(float(pr.d), 1.5, r.length - 1.5)
			best = {"point": r.position_at(d), "dir": r.direction_at(d), "dist": pr.dist}
	return best


func add_buff(kind: String, value: float, duration: float, extra: Dictionary = {}) -> void:
	var b := {"kind": kind, "value": value, "t": duration}
	b.merge(extra)
	buffs.append(b)


func buff_active(kind: String) -> bool:
	for b in buffs:
		if b.kind == kind:
			return true
	return false


func _update_buffs(delta: float) -> void:
	for i in range(buffs.size() - 1, -1, -1):
		buffs[i].t -= delta
		if buffs[i].t <= 0.0:
			buffs.remove_at(i)
	field_vision_active = buff_active("field_vision")
	var cap: Defender = null
	for df in defenders:
		if df.is_captain:
			cap = df
	var cap_lvl := run.upgrade_level("captains_rally")
	var cap_radius := 6.0 + 1.5 * cap_lvl
	var cap_bonus := 0.08 + 0.08 * cap_lvl
	for df in defenders:
		df.dyn_damage = 0.0
		df.dyn_speed = 0.0
		df.dyn_range = 0.0
		df.dyn_crit = 0.0
		df.dyn_ricochet = 0.0
		if cap and df != cap and Field.v2(df.post).distance_to(Field.v2(cap.post)) <= cap_radius:
			df.dyn_damage += cap_bonus
		for b in buffs:
			match b.kind:
				"twin_play":
					df.dyn_ricochet = maxf(df.dyn_ricochet, float(b.value))
				"field_vision":
					df.dyn_range += float(b.value)
				"rally":
					df.dyn_speed += float(b.value)
				"diamond_aura":
					var src: Defender = b.get("defender")
					if src and is_instance_valid(src) and Field.v2(df.global_position).distance_to(Field.v2(src.global_position)) <= float(b.radius):
						df.dyn_damage += float(b.value)
						df.dyn_speed += float(b.speed)
	# Enemy auras: captains and Rico's home guard.
	for e in enemies:
		e.zone_slow = 0.0
		e.aura_speed = 1.0
		e.aura_dr = 0.0
		e.home_guard = false
	for e in enemies:
		if not e.alive:
			continue
		var ar := float(e.data.get("aura_radius", 0.0))
		if ar > 0.0:
			for o in enemies:
				if o != e and o.alive and Field.v2(o.global_position).distance_to(Field.v2(e.global_position)) <= ar:
					o.aura_speed = 1.2
					o.aura_dr = 0.2
	for df in defenders:
		if df.aura_radius > 0.0 and not df.is_stunned():
			for e in enemies:
				if e.alive and Field.v2(e.global_position).distance_to(Field.v2(df.global_position)) <= df.aura_radius:
					e.zone_slow = maxf(e.zone_slow, 0.25)
					e.home_guard = true


# ---------------------------------------------------------------- main loop

## Optional per-section timing (enabled by the performance test).
var profile_sections := false
var prof: Dictionary = {}
var _prof_t := 0


func _prof_mark(name: String) -> void:
	if not profile_sections:
		return
	var now := Time.get_ticks_usec()
	prof[name] = float(prof.get(name, 0.0)) + (now - _prof_t)
	_prof_t = now


func _process(delta: float) -> void:
	if profile_sections:
		_prof_t = Time.get_ticks_usec()
		prof["frames"] = float(prof.get("frames", 0.0)) + 1.0
	_update_buffs(delta)
	_prof_mark("buffs_auras")
	for z in zones.duplicate():
		z.tick(delta)
	for w in walls.duplicate():
		w.tick(delta)
	for t in traps.duplicate():
		t.tick(delta)
	_prof_mark("zones_walls")
	for e in enemies.duplicate():
		if is_instance_valid(e):
			e.tick(delta)
	# Dead enemies are no longer in the list but still animate their defeat.
	for c in get_children():
		if c is Enemy and not (c as Enemy).alive:
			(c as Enemy).tick(delta)
	_prof_mark("enemies")
	for df in defenders:
		df.tick(delta)
	_prof_mark("defenders")
	projectiles.tick(delta)
	_prof_mark("projectiles")
	cam.handle_input(delta)

	var active := state == "wave" or practice
	cards.tick(delta, active)
	if combo_timer > 0.0:
		combo_timer -= delta
	excitement = move_toward(excitement, 0.2, delta * 0.08)
	_update_danger(delta)
	stadium.set_excitement(excitement)

	match state:
		"wave":
			_process_spawns(delta)
			if spawn_queue.is_empty() and _no_live_enemies():
				_on_wave_cleared()
		"break":
			if bool(Settings.get_value("gameplay", "auto_start_waves", true)) or auto_test:
				break_timer -= delta
				if break_timer <= 0.0:
					begin_wave()
	_prof_mark("cards_state")
	_update_hover()
	_prof_mark("hover")
	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.1
		if hud.has_method("refresh"):
			hud.refresh()
	_prof_mark("hud")


## Pulses a red ring around home plate as runners close in, with an occasional warning.
func _update_danger(delta: float) -> void:
	var closest := INF
	for e in enemies:
		if e.alive and e.runs > 0:
			closest = minf(closest, e.remaining())
	var target := clampf(1.0 - (closest - 3.0) / 9.0, 0.0, 1.0) if closest < INF else 0.0
	_danger = move_toward(_danger, target, delta * 3.0)
	(_danger_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.15, 0.1, _danger * 0.9))
	_danger_warned -= delta
	if target > 0.75 and _danger_warned <= 0.0 and state == "wave":
		_danger_warned = 6.0
		notify("RUNNER CLOSING ON HOME!", Color(1.0, 0.35, 0.3))
		Audio.play("crowd_ooh", -6.0, 0.05, 2000)


func _no_live_enemies() -> bool:
	for e in enemies:
		if e.alive and e.id != "decoy":
			return false
	# Clear leftover decoys once the real runners are gone.
	for e in enemies.duplicate():
		if e.id == "decoy":
			e.die({})
	return true


func notify(text: String, color: Color) -> void:
	banner_requested.emit(text, color)


func hud_flash(color: Color) -> void:
	if hud.has_method("flash"):
		hud.flash(color)


func shake(amount: float) -> void:
	cam.shake(amount)


func crowd_cheer(amount: float) -> void:
	excitement = clampf(maxf(excitement, amount), 0.0, 1.0)
	if amount >= 0.7:
		Audio.play("crowd_cheer", -6.0, 0.05, 900)


func _update_scoreboard() -> void:
	if stadium and stadium.scoreboard_ui:
		stadium.scoreboard_ui.set_state(run.inning, run.max_innings, run.runs, run.run_limit, run.outs_inning,
			mini(run.wave + (1 if state == "wave" else 0), run.waves_per_inning), run.waves_per_inning)


func cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	Engine.time_scale = SPEEDS[speed_index]
	Audio.ui("ui_toggle")


# ---------------------------------------------------------------- cards

## Selects a hand card for targeting. Clicking the selected card again plays it only if it
## needs no target (otherwise it is put back); pressing its hotkey again plays it at the cursor.
func select_card(index: int, from_key := false) -> void:
	if state in ["dugout", "results", "loading"]:
		return
	if index == targeting_index and index >= 0:
		var t := str(DB.card(targeting_card()).get("target", "none"))
		if t == "none" or (from_key and not _mouse_over_ui()):
			if not try_cast_at_cursor() and t != "none":
				card_denied.emit(index, "Pick a target first")
		else:
			Audio.ui("ui_back")
			_cancel_targeting()
		return
	if index < 0 or index >= cards.hand.size() or cards.hand[index] == "":
		return   # empty slot: the next card is on its way
	var reason := cards.check(index)
	if reason == "" and not (state == "wave" or practice):
		reason = "Play cards during waves"
	if reason == "Not enough energy":
		reason = "Need %d more energy" % maxi(1, int(ceil(float(cards.cost_of(cards.hand[index])) - cards.energy)))
	elif reason == "Cooling down":
		reason = "Ready in %ds" % int(ceil(cards.cooldown_left(cards.hand[index])))
	if reason != "":
		Audio.ui("card_denied")
		card_denied.emit(index, reason)
		return
	_cancel_drag()
	targeting_index = index
	Audio.ui("card_hover")
	targeting_changed.emit(index)


func _mouse_over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _cancel_targeting() -> void:
	if targeting_index == -1:
		return
	targeting_index = -1
	_target_ring.visible = false
	_target_line.visible = false
	_mark_preview([], Color.WHITE)
	targeting_changed.emit(-1)


func targeting_card() -> String:
	return cards.hand[targeting_index] if targeting_index >= 0 and targeting_index < cards.hand.size() else ""


func _update_target_preview() -> void:
	var id := targeting_card()
	if id == "":
		_cancel_targeting()
		return
	var c := DB.card(id)
	var gp: Variant = cam.ground_point(_mouse_pos) if not _mouse_over_ui() else null
	target_preview = {}
	_target_ring.visible = false
	_target_line.visible = false
	var col := DB.category_color(c.category)
	_mark_preview(_preview_units(id, gp), col)
	match c.target:
		"area":
			if gp == null:
				return
			var p: Vector3 = gp
			var r := float(c.get("radius", 3.0))
			target_preview = {"point": p, "valid": Field.v2(p).distance_to(Field.v2(Field.HOME)) < 40.0}
			if id == "heat_wave":
				var info := effects.caster_info(id)
				var origin: Vector3 = info.caster.global_position if info.caster else Field.HOME
				var dir := p - origin
				dir.y = 0
				var length := DB.card_param(id, "length", run.card_level(id))
				var width := DB.card_param(id, "width", run.card_level(id))
				if dir.length() > 0.1:
					dir = dir.normalized()
					_target_line.visible = true
					_target_line.global_position = origin + dir * length * 0.5 + Vector3(0, 0.08, 0)
					_target_line.rotation = Vector3(0, atan2(dir.x, dir.z), 0)
					_target_line.scale = Vector3(width, 1, length)
			else:
				_target_ring.visible = true
				_target_ring.global_position = Vector3(p.x, 0.07, p.z)
				_target_ring.scale = Vector3(r, 1, r)
				(_target_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(col, 0.95))
		"enemy":
			if hover_enemy:
				target_preview = {"enemy": hover_enemy, "valid": true, "point": hover_enemy.global_position}
				_target_ring.visible = true
				_target_ring.global_position = Vector3(hover_enemy.global_position.x, 0.07, hover_enemy.global_position.z)
				_target_ring.scale = Vector3(1.2, 1, 1.2)
				(_target_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(col, 0.95))
		"path":
			if gp == null:
				return
			var snap := snap_to_route(gp)
			target_preview = {"point": snap.point, "valid": float(snap.dist) < 6.0}
			_target_ring.visible = true
			_target_ring.global_position = Vector3(snap.point.x, 0.07, snap.point.z)
			_target_ring.scale = Vector3(1.7, 1, 1.7)
			(_target_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(col, 0.95) if target_preview.valid else Color(1, 0.2, 0.2, 0.9))
		"defender":
			if hover_defender:
				target_preview = {"defender": hover_defender, "valid": true, "point": hover_defender.global_position}
				_target_ring.visible = true
				_target_ring.global_position = Vector3(hover_defender.global_position.x, 0.07, hover_defender.global_position.z)
				var rr := DB.card_param(id, "radius", run.card_level(id))
				_target_ring.scale = Vector3(rr, 1, rr)
				(_target_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(col, 0.9))
		"none":
			target_preview = {"valid": true, "point": Field.HOME}


## Units the targeted card would affect at the cursor, highlighted before casting.
func _preview_units(id: String, gp: Variant) -> Array:
	var c := DB.card(id)
	match c.target:
		"area":
			if gp == null:
				return []
			if id == "heat_wave":
				var info := effects.caster_info(id)
				var origin: Vector3 = info.caster.global_position if info.caster else Field.HOME
				var dir: Vector3 = (gp as Vector3) - origin
				dir.y = 0
				if dir.length() < 0.1:
					return []
				dir = dir.normalized()
				var length := DB.card_param(id, "length", run.card_level(id))
				var width := DB.card_param(id, "width", run.card_level(id))
				var out: Array = []
				for e in enemies:
					if not e.targetable():
						continue
					var rel := e.global_position - origin
					var s := rel.dot(dir)
					if s >= -0.5 and s <= length and absf(rel.dot(Vector3(-dir.z, 0, dir.x))) <= width * 0.5 + 0.4:
						out.append(e)
				return out
			return enemies_in_radius(gp, float(c.get("radius", 3.0)))
		"enemy":
			return [hover_enemy] if hover_enemy else []
		"defender":
			if hover_defender == null:
				return []
			var r := DB.card_param(id, "radius", run.card_level(id))
			var out2: Array = []
			for df in defenders:
				if Field.v2(df.global_position).distance_to(Field.v2(hover_defender.global_position)) <= r:
					out2.append(df)
			return out2
		"none":
			match id:
				"time_out", "changeup":
					var all: Array = []
					for e in enemies:
						if e.targetable():
							all.append(e)
					return all
				"sky_hook":
					return lead_runners(1)
				"grand_relay":
					return lead_runners(int(DB.card_param(id, "targets", run.card_level(id))))
				"twin_play", "field_vision", "rally_cry":
					return defenders.duplicate()
	return []


func _mark_preview(units: Array, col: Color) -> void:
	for u in _preview_marked:
		if not is_instance_valid(u) or u in units:
			continue
		if u is Enemy:
			(u as Enemy)._rim_dirty = true
		else:
			(u as Defender).model.set_rim(Color(0, 0, 0, 0))
	_preview_marked = units
	for u in units:
		if is_instance_valid(u):
			u.model.set_rim(Color(col.lightened(0.2), 0.95))


func try_cast_at_cursor() -> bool:
	var id := targeting_card()
	if id == "":
		return false
	# Re-read what is under the cursor right now (not last frame): runners move.
	_update_hover()
	if not target_preview.get("valid", false):
		Audio.ui("card_denied")
		var want := {"enemy": "Click a runner", "defender": "Click a defender", "path": "Click on a basepath", "area": "Click on the field"}
		card_denied.emit(targeting_index, str(want.get(str(DB.card(id).get("target", "")), "Pick a target")))
		return false
	var idx := targeting_index
	var reason := cards.check(idx)
	if reason != "":
		notify(reason.to_upper(), Color(1.0, 0.5, 0.4))
		_cancel_targeting()
		return false
	var cd_scale: float = effects.caster_info(id).cd
	cards.commit(idx, cd_scale)
	cards_played_run += 1
	run.stats.cards_played = int(run.stats.get("cards_played", 0)) + 1
	if not practice:
		Profile.bump_stat("cards_played")
	var tgt := target_preview.duplicate()
	last_cast_point = tgt.get("point", null)
	_cancel_targeting()
	effects.execute(id, run.card_level(id), tgt)
	if hud.has_method("on_card_played"):
		hud.on_card_played(id)
	card_cast.emit(id)
	return true


# ---------------------------------------------------------------- input & selection

func _update_hover() -> void:
	_mouse_pos = get_viewport().get_mouse_position()
	# Nothing in the world is "under the cursor" while it is over a HUD panel or the hand.
	var over_ui := _mouse_over_ui() and dragging == null
	hover_defender = null if over_ui else _pick_defender(_mouse_pos)
	# Aiming a runner card: forgiving pick radius (runners are small and moving).
	var aiming_runner := targeting_index >= 0 and str(DB.card(targeting_card()).get("target", "")) == "enemy"
	hover_enemy = null if over_ui else _pick_enemy(_mouse_pos, 95.0 if aiming_runner else 50.0)
	if targeting_index >= 0:
		_update_target_preview()
	if dragging:
		var gp: Variant = cam.ground_point(_mouse_pos)
		if gp != null:
			var p: Vector3 = gp
			dragging.global_position = p
			var err := placement_error(p, dragging)
			drag_valid = err == ""
			_drag_ghost.visible = true
			_drag_ghost.global_position = Vector3(p.x, 0.08, p.z)
			(_drag_ghost.material_override as ShaderMaterial).set_shader_parameter("color", Color(0.3, 1.0, 0.5, 0.95) if drag_valid else Color(1.0, 0.25, 0.2, 0.95))
			dragging._range_ring.visible = true
			if hud.has_method("drag_info"):
				hud.drag_info(dragging, p, err)


func _pick_defender(mp: Vector2) -> Defender:
	var best: Defender = null
	var best_d := 46.0
	for df in defenders:
		if df == dragging:
			continue
		if cam.camera.is_position_behind(df.global_position):
			continue
		var sp := cam.camera.unproject_position(df.global_position + Vector3(0, 1.0, 0))
		var d := sp.distance_to(mp)
		if d < best_d:
			best_d = d
			best = df
	return best


func _pick_enemy(mp: Vector2, radius := 50.0) -> Enemy:
	var best: Enemy = null
	var best_d := radius
	for e in enemies:
		if not e.targetable():
			continue
		if cam.camera.is_position_behind(e.global_position):
			continue
		var sp := cam.camera.unproject_position(e.center())
		var d := sp.distance_to(mp)
		if d < best_d:
			best_d = d
			best = e
	return best


func select_defender(df: Defender) -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	selected = df
	if df:
		df.set_selected(true)
		Audio.ui("ui_click", -6.0)
	selection_changed.emit(df)


func cycle_defender() -> void:
	if defenders.is_empty():
		return
	var i := defenders.find(selected)
	var nxt := defenders[(i + 1) % defenders.size()]
	select_defender(nxt)
	cam.set_view(nxt.global_position, cam._t_yaw, cam._t_pitch, minf(cam._t_distance, 30.0))


## Replaces a defender on the field with another one at the same spot (Practice Field tool).
func swap_defender(old: Defender, new_id: String) -> void:
	if old == null or new_id == old.id:
		return
	for df in defenders:
		if df.id == new_id:
			return
	var idx := defenders.find(old)
	var post := old.post
	var df := Defender.new()
	df.name = "Def_" + new_id
	add_child(df)
	df.setup(self, new_id, _uniform_colors)
	defenders[idx] = df
	run.team[run.team.find(old.id)] = new_id
	if old.is_captain:
		run.captain = new_id
	if selected == old:
		selected = null
	old.queue_free()
	df.place(post)
	df.set_captain(new_id == run.captain)
	vfx.burst("magic", df.model.chest_position(), DB.defender_accent(new_id))
	_refresh_team_stats()
	select_defender(df)


func set_captain(df: Defender) -> void:
	run.captain = df.id
	for d in defenders:
		d.set_captain(d == df)
	Audio.ui("ui_confirm")
	score_changed.emit()


func _start_drag(df: Defender) -> void:
	dragging = df
	df.model.play_base("run", 0.1)
	Audio.ui("ui_click", -4.0)


func _end_drag() -> void:
	if dragging == null:
		return
	var df := dragging
	dragging = null
	_drag_ghost.visible = false
	if drag_valid:
		df.place(df.global_position)
		vfx.dust(df.global_position, 0.6)
		Audio.play("footstep_dirt", -2.0)
		run.positions[df.id] = [df.post.x, df.post.z]
		defender_moved.emit(df)
	else:
		df.global_position = df.post
		Audio.ui("ui_error")
	df.model.play_base("ready", 0.15)
	df.set_show_range(false)
	_refresh_team_stats()
	if hud.has_method("drag_info"):
		hud.drag_info(null, Vector3.ZERO, "")


func _cancel_drag() -> void:
	if dragging:
		dragging.global_position = dragging.post
		dragging.model.play_base("ready", 0.15)
		dragging.set_show_range(false)
		dragging = null
		_drag_ghost.visible = false
		if hud.has_method("drag_info"):
			hud.drag_info(null, Vector3.ZERO, "")


func _unhandled_input(event: InputEvent) -> void:
	if state in ["results", "loading"]:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam.zoom(-0.1)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam.zoom(0.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_press()
			else:
				_end_drag()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if targeting_index >= 0:
				_cancel_targeting()
			elif dragging:
				_cancel_drag()
			else:
				select_defender(null)
		return
	if state == "dugout":
		return
	for i in 5:
		if event.is_action_pressed("card_%d" % (i + 1)):
			select_card(i, true)
			return
	if event.is_action_pressed("card_next"):
		_cycle_card(1)
	elif event.is_action_pressed("card_prev"):
		_cycle_card(-1)
	elif event.is_action_pressed("start_wave"):
		begin_wave()
	elif event.is_action_pressed("fast_forward"):
		cycle_speed()
	elif event.is_action_pressed("rotate"):
		cam.rotate_step(1)
	elif event.is_action_pressed("cycle_defender"):
		cycle_defender()
	elif event.is_action_pressed("info"):
		var show := not defenders[0].show_range if defenders.size() > 0 else false
		for df in defenders:
			df.set_show_range(show)
	elif event.is_action_pressed("tactical_map"):
		cam.toggle_tactical()
	elif event.is_action_pressed("center_camera"):
		cam.center()
	elif event.is_action_pressed("confirm"):
		if targeting_index >= 0:
			try_cast_at_cursor()
		elif state in ["setup", "break"]:
			begin_wave()
	elif event.is_action_pressed("pause"):
		if targeting_index >= 0:
			_cancel_targeting()
		elif dragging:
			_cancel_drag()
		elif hud.has_method("toggle_pause"):
			hud.toggle_pause()


func _cycle_card(dir: int) -> void:
	if cards.hand.is_empty():
		return
	var n := cards.hand.size()
	var start := targeting_index if targeting_index >= 0 else (-1 if dir > 0 else n)
	for k in n:
		var i := posmod(start + dir * (k + 1), n)
		if cards.check(i) == "":
			_cancel_targeting()
			select_card(i)
			return
	Audio.ui("card_denied")


func _on_left_press() -> void:
	if targeting_index >= 0:
		try_cast_at_cursor()
		return
	var df := hover_defender
	if df and can_reposition():
		select_defender(df)
		_start_drag(df)
		return
	select_defender(df)
