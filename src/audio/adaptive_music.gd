class_name AdaptiveMusic
extends Node
## Layered arena music: four stems of one arena (calm, wave, boss, tense) that start on the
## same mix block, loop with identical lengths and are cross-faded by intensity.
## Built by tools/audio/arena_music.py; paths come from the "arenas" section of the manifest.

const LAYERS: Array[String] = ["calm", "wave", "boss", "tense"]
const SILENT_DB := -60.0
## Seconds for a full 0 -> 1 fade per layer (rising / falling). Tense rises fast, falls slowly.
const FADE_UP := {"calm": 1.5, "wave": 1.2, "boss": 0.8, "tense": 0.7}
const FADE_DOWN := {"calm": 2.5, "wave": 2.5, "boss": 2.0, "tense": 3.0}
## Layer trims relative to the stem volume (the full stack is loud; the master limiter is the safety).
const TRIM_DB := {"calm": 0.0, "wave": 0.0, "boss": -1.0, "tense": -1.5}

var arena_id := ""
var base_db := -7.0
var bus := "MusicMix"
var _players: Dictionary = {}     # layer -> AudioStreamPlayer
var _level: Dictionary = {}       # layer -> current linear 0..1
var _target: Dictionary = {}      # layer -> target linear 0..1
var _master := 0.0                # overall fade (0..1) for start/stop
var _master_target := 0.0
var _master_rate := 1.0
var _drift_timer := 0.0
var _last_usec := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for l in LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.volume_db = SILENT_DB
		add_child(p)
		_players[l] = p
		_level[l] = 0.0
		_target[l] = 0.0


func is_playing() -> bool:
	return arena_id != "" and _master_target > 0.0


## Starts the stems of an arena (if not already playing) and fades in over `fade` seconds.
func start(id: String, layer_paths: Dictionary, volume_db: float, fade := 1.2) -> bool:
	if id == arena_id and _master_target > 0.0:
		return true
	var streams := {}
	for l in LAYERS:
		var path := str(layer_paths.get(l, ""))
		if path == "" or not ResourceLoader.exists(path):
			return false
		var s: AudioStream = load(path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		streams[l] = s
	arena_id = id
	base_db = volume_db
	for l in LAYERS:
		var p: AudioStreamPlayer = _players[l]
		p.stop()
		p.stream = streams[l]
		_level[l] = _target[l]
		_apply(l)
	# Same frame -> same mix block: the stems stay sample-aligned (equal lengths, no drift).
	for l in LAYERS:
		(_players[l] as AudioStreamPlayer).play(0.0)
	_master = 0.0
	_master_target = 1.0
	_master_rate = 1.0 / maxf(fade, 0.01)
	return true


func stop(fade := 1.0) -> void:
	_master_target = 0.0
	_master_rate = 1.0 / maxf(fade, 0.01)
	if fade <= 0.0:
		_master = 0.0
		_halt()


## Target mix, each 0..1 (calm is normally 1; wave/boss/tense add on top).
func set_layers(calm: float, wave: float, boss: float, tense: float) -> void:
	_target["calm"] = clampf(calm, 0.0, 1.0)
	_target["wave"] = clampf(wave, 0.0, 1.0)
	_target["boss"] = clampf(boss, 0.0, 1.0)
	_target["tense"] = clampf(tense, 0.0, 1.0)


func get_layer(l: String) -> float:
	return float(_level.get(l, 0.0))


func get_target(l: String) -> float:
	return float(_target.get(l, 0.0))


func _process(_delta: float) -> void:
	# Unscaled time, so fades don't speed up at 3x game speed or stall during hit-stop.
	var now := Time.get_ticks_usec()
	var d := clampf((now - _last_usec) / 1000000.0, 0.0, 0.1) if _last_usec > 0 else 0.0
	_last_usec = now
	if arena_id == "":
		return
	_master = move_toward(_master, _master_target, d * _master_rate)
	for l in LAYERS:
		var cur: float = _level[l]
		var tgt: float = _target[l]
		if cur != tgt:
			var t: float = FADE_UP[l] if tgt > cur else FADE_DOWN[l]
			_level[l] = move_toward(cur, tgt, d / maxf(t, 0.01))
		_apply(l)
	if _master <= 0.0 and _master_target <= 0.0:
		_halt()
		return
	_drift_timer += d
	if _drift_timer > 4.0:
		_drift_timer = 0.0
		_check_drift()


func _apply(l: String) -> void:
	var p: AudioStreamPlayer = _players[l]
	# Equal-power-ish curve: perceived level follows the fade smoothly.
	var g := sin(float(_level[l]) * PI * 0.5) * _master
	p.volume_db = SILENT_DB if g <= 0.001 else base_db + float(TRIM_DB[l]) + linear_to_db(g)


func _halt() -> void:
	for l in LAYERS:
		(_players[l] as AudioStreamPlayer).stop()
	arena_id = ""


## Safety net: if a stem ever slips (it should not), re-align it to the calm stem.
func _check_drift() -> void:
	var ref: AudioStreamPlayer = _players["calm"]
	if not ref.playing:
		return
	var pos := ref.get_playback_position()
	for l in LAYERS:
		var p: AudioStreamPlayer = _players[l]
		if p == ref or not p.playing or p.stream == null:
			continue
		var diff := absf(p.get_playback_position() - pos)
		var length := p.stream.get_length()
		if length > 0.0:
			diff = minf(diff, length - diff)
		if diff > 0.08 and float(_level[l]) <= 0.01:
			p.seek(pos)   # only re-seek silent layers, so no audible jump
