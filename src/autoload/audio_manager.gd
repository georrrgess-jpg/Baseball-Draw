extends Node
## Audio buses, pooled sound effects with variation and rate limiting,
## cross-faded music and ambience loops.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const POOL_SIZE := 28
const UI_POOL_SIZE := 6

var _pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _variants: Dictionary = {}       # name -> Array[AudioStream]
var _last_played: Dictionary = {}    # name -> msec
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _music_name := ""
var _ambience: Array[AudioStreamPlayer] = []
var _ambience_names: Array[String] = ["", ""]
var _rng := RandomNumberGenerator.new()
var _volume_overrides := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i in UI_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui_pool.append(p)
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	for i in 2:
		_ambience.append(_make_player("Ambience"))
	_load_manifest()


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _create_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# Gentle limiter on the master to keep stacked effects from clipping.
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)


func _load_manifest() -> void:
	var path := "res://assets/audio/manifest.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var by_name: Variant = parsed.get("volume_db_by_name", {})
	if typeof(by_name) == TYPE_DICTIONARY:
		for k in by_name.keys():
			_volume_overrides[str(k)] = float(by_name[k])


func _resolve(name: String) -> Array:
	if _variants.has(name):
		return _variants[name]
	var list: Array = []
	var single := SFX_DIR + name + ".wav"
	if ResourceLoader.exists(single):
		list.append(load(single))
	for i in range(1, 6):
		var p := SFX_DIR + "%s_%d.wav" % [name, i]
		if ResourceLoader.exists(p):
			list.append(load(p))
	_variants[name] = list
	return list


## Plays a one-shot effect. Rate-limited per name so swarms of hits don't stack into noise.
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06, min_gap_ms: int = 45) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -10000)) < min_gap_ms:
		return
	var streams := _resolve(name)
	if streams.is_empty():
		return
	_last_played[name] = now
	var p := _free_player(_pool)
	p.stream = streams[_rng.randi() % streams.size()]
	p.volume_db = volume_db + float(_volume_overrides.get(name, 0.0))
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	p.pitch_scale *= Engine.time_scale if Engine.time_scale < 1.0 else 1.0
	p.play()


func ui(name: String, volume_db: float = 0.0) -> void:
	var streams := _resolve(name)
	if streams.is_empty():
		return
	var p := _free_player(_ui_pool)
	p.stream = streams[0]
	p.volume_db = volume_db
	p.pitch_scale = 1.0
	p.play()


func _free_player(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for p in pool:
		if not p.playing:
			return p
	# All busy: steal the one closest to finishing.
	var best := pool[0]
	var best_left := INF
	for p in pool:
		var length := p.stream.get_length() if p.stream else 0.0
		var left := length - p.get_playback_position()
		if left < best_left:
			best_left = left
			best = p
	return best


func play_music(name: String, fade := 1.2) -> void:
	if name == _music_name:
		return
	_music_name = name
	var path := MUSIC_DIR + name + ".ogg"
	var next := _music_b if _music_current == _music_a else _music_a
	var prev := _music_current
	_music_current = next
	if prev:
		var tw := create_tween()
		tw.tween_property(prev, "volume_db", -40.0, fade)
		tw.tween_callback(prev.stop)
	if name == "" or not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = not name in ["victory", "defeat"]
	next.stream = stream
	next.volume_db = -40.0
	next.play()
	create_tween().tween_property(next, "volume_db", float(_volume_overrides.get(name, 0.0)), fade)


func stop_music(fade := 1.0) -> void:
	play_music("", fade)


func play_ambience(names: Array) -> void:
	for i in 2:
		var name: String = names[i] if i < names.size() else ""
		if _ambience_names[i] == name:
			continue
		_ambience_names[i] = name
		var p := _ambience[i]
		var path := AMBIENCE_DIR + name + ".ogg"
		if name == "" or not ResourceLoader.exists(path):
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -40.0, 1.0)
			tw.tween_callback(p.stop)
			continue
		var stream: AudioStream = load(path)
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		p.stream = stream
		p.volume_db = -40.0
		p.play()
		create_tween().tween_property(p, "volume_db", -6.0 if i == 1 else 0.0, 1.5)


## Temporarily ducks music (e.g. during the boss warning).
func duck_music(amount_db: float, time: float) -> void:
	if _music_current == null:
		return
	var p := _music_current
	var base := p.volume_db
	var tw := create_tween()
	tw.tween_property(p, "volume_db", base - amount_db, 0.15)
	tw.tween_interval(time)
	tw.tween_property(p, "volume_db", base, 0.6)
