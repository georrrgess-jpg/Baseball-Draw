extends Node
## Audio checks (adaptive arena music, stings, crowd reactions, voice limiting, ducking).
## Run headless:
##   godot --headless --path . res://tests/audio_test.tscn -- --profile=audiotest --fresh-profile
## Exits with code 0 when every check passes.

var checks := 0
var failures := 0


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL ", what)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	test_assets()
	test_mixing()
	await test_battle_music()
	print("==== audio: %d checks, %d failed ====" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func test_assets() -> void:
	print("== audio assets")
	var man: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/manifest.json"))
	var arenas: Dictionary = man.get("arenas", {})
	for a in DB.arenas.keys():
		var id := str(a)
		ok(arenas.has(id), "arena %s has adaptive stems" % id)
		if not arenas.has(id):
			continue
		var length := -1.0
		for layer in AdaptiveMusic.LAYERS:
			var path := str(arenas[id].layers.get(layer, ""))
			ok(ResourceLoader.exists(path), "%s %s stem exists" % [id, layer])
			if not ResourceLoader.exists(path):
				continue
			var s: AudioStream = load(path)
			if length < 0.0:
				length = s.get_length()
			ok(absf(s.get_length() - length) < 0.001, "%s %s stem has the shared loop length" % [id, layer])
	for n in ["sting_boss_intro", "sting_boss_defeat"]:
		ok(ResourceLoader.exists("res://assets/audio/music/%s.ogg" % n), "%s exists" % n)
	for n in ["crowd_small", "crowd_big", "crowd_roar", "crowd_groan_small", "crowd_chant", "crowd_stomp"]:
		ok(not Audio._resolve(n).is_empty(), "crowd reaction %s loads" % n)
	ok(Audio._resolve("ball_hit").size() >= 5, "ball hit has 5+ variants")
	ok(Audio._resolve("crowd_groan").size() >= 3, "crowd groan mixes in the alternate groans")


func test_mixing() -> void:
	print("== mixing")
	for b in ["MusicMix", "Crowd", "AmbienceMix"]:
		ok(AudioServer.get_bus_index(b) >= 0, "bus %s exists" % b)
	ok(AudioServer.get_bus_send(AudioServer.get_bus_index("MusicMix")) == &"Music", "MusicMix feeds the Music bus")
	ok(AudioServer.get_bus_send(AudioServer.get_bus_index("Crowd")) == &"SFX", "Crowd feeds the SFX bus")
	# Voice limiting: ten rapid hits never use more than four voices.
	for i in 10:
		Audio.play("ball_hit", -30.0, 0.05, 0)
	ok(Audio.voices_playing("ball_hit") <= 4, "rapid hits are voice limited (%d)" % Audio.voices_playing("ball_hit"))
	ok(Audio.voices_playing("ball_hit") >= 1, "hits still play")
	# Variants never repeat back to back.
	var same := 0
	var prev: Variant = null
	for i in 30:
		var v: Dictionary = Audio._pick("ball_hit", Audio._resolve("ball_hit"))
		if v.s == prev:
			same += 1
		prev = v.s
	ok(same == 0, "no back-to-back repeats of a variant")
	# Manifest volumes apply to UI sounds too.
	ok(absf(Audio.volume_of("ui_click")) > 0.01, "ui_click has a mix volume")


func test_battle_music() -> void:
	print("== adaptive battle music")
	var cfg := Session.new_run_config("quick")
	cfg.seed = 7
	cfg.arena = "neon_diamond"
	cfg.auto_test = false
	Session.run_config = cfg
	var packed: PackedScene = load("res://scenes/battle.tscn")
	var battle: Battle = packed.instantiate()
	add_child(battle)
	for i in 50:
		await _wait(0.1)
		if battle.state == "setup":
			break
	var am: AdaptiveMusic = Audio.adaptive
	ok(Audio.battle_audio.is_active(), "battle audio attached to the battle")
	ok(am.is_playing(), "adaptive music plays in battle")
	ok(am.arena_id == battle.run.arena_id, "stems of the battle's arena (%s / %s)" % [am.arena_id, battle.run.arena_id])
	await _wait(0.3)
	ok(am.get_target("calm") > 0.9 and am.get_target("wave") < 0.1, "setup: calm layer only")
	battle.begin_wave()
	await _wait(0.3)
	ok(am.get_target("wave") > 0.9, "wave layer in during a wave")
	ok(am.get_layer("wave") > 0.0, "wave layer fading in")
	# Boss: boss layer, intro sting, music ducked.
	var boss := battle.spawn_enemy(_any_boss(), battle.routes[0], 2.0)
	await _wait(0.4)
	ok(am.get_target("boss") > 0.9, "boss layer in while a boss is on the field")
	ok(Audio._sting.playing or Audio._sting.stream != null, "boss intro sting started")
	ok(Audio.music_duck_db() > 1.0, "music ducked for the boss intro (%.1f dB)" % Audio.music_duck_db())
	# Tension: one run from losing.
	battle.run.runs = battle.run.run_limit - 1
	await _wait(0.2)
	ok(am.get_target("tense") > 0.9, "tense layer when one run from losing")
	battle.run.runs = 0
	# Boss defeated: defeat sting + roar.
	boss.die({})
	await _wait(0.3)
	ok(Audio._sting.stream != null and str(Audio._sting.stream.resource_path).ends_with("sting_boss_defeat.ogg"),
		"boss defeat sting")
	# Outs cheer (crowd pool).
	var outs0 := battle.run.outs_total
	var e := battle.spawn_enemy("runner", battle.routes[0], 3.0)
	e.die({})
	await _wait(0.1)
	ok(battle.run.outs_total > outs0, "out recorded")
	# Leaving the battle hands back to normal music.
	Audio.play_music("menu_theme")
	await _wait(0.1)
	ok(not am.is_playing(), "adaptive music stops for menu music")
	battle.queue_free()
	await _wait(0.2)
	ok(not Audio.battle_audio.is_active(), "battle audio detaches")


func _any_boss() -> String:
	for id in DB.enemies.keys():
		if bool(DB.enemies[id].get("boss", false)):
			return str(id)
	return "runner"
