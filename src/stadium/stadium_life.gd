class_name StadiumLife
extends Node3D
## Makes the ballpark react to the game. Listens to the Battle node's signals (it never calls into
## battle logic) and drives the crowd (cheers, groans, standing ovations, the wave), the jumbotron
## (live feed of big moments), the mascot between waves and fireworks on boss defeats and wins.
## In the main menu (no battle) the crowd idles and starts the occasional wave.

var crowd: StadiumCrowd
var jumbotron: StadiumJumbotron
var mascot: StadiumMascot
var fireworks: StadiumFireworks
var battle: Node = null

var _last_state := ""
var _results_pending := false
var _enemy_pos := {}            # instance id -> last position (to know where an out happened)
var _last_out := Vector3(0, 0, -4)
var _boss: Node3D = null
var _breaks := 0
var _idle_wave_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_crowd: StadiumCrowd, p_jumbo: StadiumJumbotron, p_mascot: StadiumMascot, p_fireworks: StadiumFireworks) -> void:
	crowd = p_crowd
	jumbotron = p_jumbo
	mascot = p_mascot
	fireworks = p_fireworks
	_rng.randomize()
	_idle_wave_t = _rng.randf_range(14.0, 24.0)


## Connects to a Battle node (anything with its signals).
func attach_battle(b: Node) -> void:
	battle = b
	if b.has_signal("state_changed"):
		b.state_changed.connect(_on_state)
	if b.has_signal("banner_requested"):
		b.banner_requested.connect(_on_banner)
	if b.has_signal("run_scored"):
		b.run_scored.connect(_on_run_scored)
	if b.has_signal("boss_spawned"):
		b.boss_spawned.connect(_on_boss_spawned)
	if b.has_signal("score_changed"):
		b.score_changed.connect(_on_score_changed)
	if b.has_signal("card_cast"):
		b.card_cast.connect(_on_card_cast)
	if b.has_signal("wave_started"):
		b.wave_started.connect(_on_wave_started)


func _ready() -> void:
	# Capture/testing hook: --stadium-demo=fireworks|victory|moment|wave|cheer|groan
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stadium-demo="):
			var what := a.split("=")[1]
			get_tree().create_timer(2.0).timeout.connect(func() -> void: _demo(what))
		elif a.begins_with("--stadium-demo-out="):
			# Saves what the scoreboard shows 3.5 s after the demo starts.
			var path := a.split("=")[1]
			get_tree().create_timer(5.5).timeout.connect(func() -> void:
				if jumbotron and jumbotron.display:
					jumbotron.display.get_viewport().get_texture().get_image().save_png(path))


func _demo(what: String) -> void:
	match what:
		"fireworks":
			fireworks.launch_show(8, 3.0, Vector3(0, 0, -34), Vector2(26, 6), Vector2(18, 26))
		"victory":
			_on_game_over(true)
		"moment":
			jumbotron.show_moment("TRIPLE PLAY", "WHAT A PLAY", Vector3(0, 0, -6), 30.0, 2)
		"wave":
			crowd.start_wave()
		"cheer":
			crowd.cheer(1.0, 30.0)
		"groan":
			crowd.groan(1.0, 30.0)


func _process(delta: float) -> void:
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	if battle == null:
		# Menu: an occasional wave around the stadium.
		_idle_wave_t -= dt
		if _idle_wave_t <= 0.0:
			_idle_wave_t = _rng.randf_range(26.0, 40.0)
			crowd.start_wave(1.0 if _rng.randf() < 0.5 else -1.0)
		return
	var state: String = str(battle.get("state"))
	if state == "wave":
		_track_enemies()
	if _results_pending:
		var run: Variant = battle.get("run")
		if run != null and bool(run.finished):
			_results_pending = false
			_on_game_over(bool(run.won))


func _track_enemies() -> void:
	var list: Variant = battle.get("enemies")
	if list == null:
		return
	var seen := {}
	for e in list:
		if is_instance_valid(e) and e is Node3D:
			var id: int = e.get_instance_id()
			_enemy_pos[id] = (e as Node3D).global_position
			seen[id] = true
	for id in _enemy_pos.keys():
		if not seen.has(id):
			_last_out = _enemy_pos[id]
			_enemy_pos.erase(id)


# ---------------------------------------------------------------- reactions

func _on_state(s: String) -> void:
	var prev := _last_state
	_last_state = s
	match s:
		"wave":
			crowd.sit_down()
			if mascot:
				mascot.begin_exit(true)
		"break":
			_breaks += 1
			crowd.cheer(0.6, 0.8)
			# The mascot comes out on most breaks; the crowd starts the wave now and then.
			if mascot and _breaks % 2 == 1:
				mascot.appear()
			elif _rng.randf() < 0.7:
				crowd.start_wave(1.0 if _rng.randf() < 0.5 else -1.0)
		"setup":
			# The mascot greets the start of the game and every new inning after the dugout.
			if mascot and (prev == "dugout" or prev == ""):
				mascot.appear("wave" if prev == "" else "")
		"results":
			_results_pending = true
			if mascot:
				mascot.begin_exit(true)


func _on_wave_started(_info: Dictionary) -> void:
	crowd.cheer(0.5, 0.6)
	if mascot:
		mascot.begin_exit(true)


func _on_banner(text: String, _color: Color) -> void:
	var t := text.to_upper()
	if t.contains("DEFEATED"):
		_on_boss_defeated(text)
	elif t.contains("GRAND SLAM") or t.contains("TRIPLE PLAY"):
		crowd.cheer(1.0, 2.2)
		crowd.stand_up(2.6)
		jumbotron.show_moment(text.replace("!", ""), "WHAT A PLAY", _last_out, 4.0, 2)
	elif t.contains("DOUBLE PLAY") or t.contains("TWIN PLAY"):
		crowd.cheer(0.85, 1.3)
		jumbotron.show_moment(text.replace("!", ""), "", _last_out, 3.2, 1)
	elif t.contains("COMPLETE"):
		crowd.cheer(1.0, 2.0)
	elif t.contains("WAVE CLEAR"):
		crowd.cheer(0.7, 1.0)
	elif t.contains("GAME OVER"):
		crowd.groan(1.0, 3.0)


func _on_boss_defeated(text: String) -> void:
	crowd.cheer(1.0, 3.0)
	crowd.stand_up(6.0)
	var where := _last_out
	if _boss and is_instance_valid(_boss):
		where = _boss.global_position
	_boss = null
	jumbotron.show_moment(text.replace("!", ""), "BOSS DOWN", where, 5.0, 3, 11.0)
	if fireworks:
		# Low over the side stands so they show at the edges of the battle camera, not over the field.
		fireworks.launch_show(3, 2.0, Vector3(-31, 0, 0), Vector2(3, 9), Vector2(9, 13))
		fireworks.launch_show(3, 2.0, Vector3(31, 0, 0), Vector2(3, 9), Vector2(9, 13))


func _on_run_scored(_runs: int) -> void:
	crowd.groan(1.0, 1.6)


func _on_boss_spawned(e: Node) -> void:
	_boss = e as Node3D
	crowd.stand_up(1.8)
	crowd.groan(0.5, 0.8)
	var nm := ""
	var data: Variant = e.get("data")
	if data is Dictionary:
		nm = str(data.get("name", "")).to_upper()
	jumbotron.show_moment(nm if nm != "" else "BOSS INCOMING", "BOSS AT THE GATE", _boss, 5.0, 3, 12.0)


func _on_score_changed() -> void:
	if battle and str(battle.get("state")) == "wave":
		crowd.cheer(0.3, 0.35)


func _on_card_cast(_id: String) -> void:
	crowd.cheer(0.4, 0.5)


func _on_game_over(won: bool) -> void:
	if won:
		crowd.stand_up(999.0)
		crowd.cheer(1.0, 6.0)
		if fireworks:
			fireworks.launch_show(14, 9.0, Vector3(0, 0, -34), Vector2(34, 8), Vector2(16, 26))
			fireworks.launch_show(4, 8.0, Vector3(-31, 0, 0), Vector2(3, 9), Vector2(9, 14))
			fireworks.launch_show(4, 8.0, Vector3(31, 0, 0), Vector2(3, 9), Vector2(9, 14))
		jumbotron.show_moment("VICTORY!", "THE DIAMOND IS SAFE", Vector3(0, 0, 1), 9.0, 4, 14.0)
	else:
		crowd.groan(1.0, 4.0)
