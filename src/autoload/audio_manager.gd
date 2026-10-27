extends Node
## Audio buses, pooled sound effects with variation, rate and voice limiting, cross-faded music,
## adaptive per-arena battle music (src/audio/adaptive_music.gd), stings, music ducking and
## ambience. Battle reactions (crowd, intensity) live in src/audio/battle_audio.gd.
##
## Bus layout (Settings sets the volumes of Master/Music/SFX/Ambience/UI):
##   MusicMix -> Music     every music track and the arena stems; ducked for big moments
##   Music                 stings (not ducked, so they cut through the ducked music)
##   Crowd    -> SFX       crowd reactions, with their own small voice pool
##   AmbienceMix -> Ambience   stadium beds; swells with the battle's excitement

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const AMBIENCE_DIR := "res://assets/audio/ambience/"
const MANIFEST := "res://assets/audio/manifest.json"
const POOL_SIZE := 28
const UI_POOL_SIZE := 6
const CROWD_POOL_SIZE := 5
const MAX_VARIANTS := 8
const DEFAULT_VOICES := 5
## Simultaneous voices per sound: rapid hits re-use voices instead of stacking into noise.
const VOICE_LIMITS := {
	"ball_hit": 4, "crit_hit": 3, "throw": 3, "glove_catch": 3, "enemy_out": 3, "coin": 2,
	"swing_whoosh": 2, "footstep_dirt": 2, "card_flip": 4, "card_draw": 2, "barrage_impact": 3,
	"lightning_zap": 3, "shadow_cast": 2, "aura_hum": 2, "shield_block": 2, "boss_slam": 2,
	"crowd_cheer": 2, "crowd_small": 2, "crowd_big": 2, "crowd_roar": 1, "crowd_groan": 2,
	"crowd_ooh": 1, "crowd_chant": 1, "crowd_stomp": 1, "firework": 3,
}
## Frequent sounds get a little level randomisation and back off when they pile up.
const FREQUENT := {
	"ball_hit": 1.5, "crit_hit": 1.0, "throw": 1.5, "glove_catch": 1.5, "enemy_out": 1.0, "coin": 1.0,
	"swing_whoosh": 2.0, "footstep_dirt": 2.0, "card_flip": 1.0, "barrage_impact": 1.5,
	"card_draw": 1.0, "lightning_zap": 1.0, "firework": 2.0,
}
const DENSITY_WINDOW_MS := 450
const DENSITY_DB_PER_HIT := 1.5
const DENSITY_MAX_DB := 6.0
## Extra sample sets mixed into a name's variants (more variety without touching call sites).
const ALIASES := {"crowd_groan": ["crowd_groan_small"]}
const CROWD_PREFIX := "crowd_"
const NON_LOOPING_MUSIC := ["victory", "defeat"]
## Music names the battle asks for that become the arena's adaptive stems.
const ADAPTIVE_NAMES := ["battle_theme", "boss_theme"]

var _pool: Array[AudioStreamPlayer] = []
var _ui_pool: Array[AudioStreamPlayer] = []
var _crowd_pool: Array[AudioStreamPlayer] = []
var _variants: Dictionary = {}       # name -> Array[{s: AudioStream, v: float}]
var _last_played: Dictionary = {}    # name -> msec
var _last_variant: Dictionary = {}   # name -> index
var _recent: Dictionary = {}         # name -> Array[msec]
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current: AudioStreamPlayer
var _music_name := ""
var _sting: AudioStreamPlayer
var _ambience: Array[AudioStreamPlayer] = []
var _ambience_names: Array[String] = ["", ""]
var _rng := RandomNumberGenerator.new()
var _volume_overrides := {}
var _arena_layers := {}              # arena id -> {layer: path}
var _ducks: Array = []               # [{db, until_msec}]
var _duck_db := 0.0
var _ambience_swell_db := 0.0
var _last_usec := 0

var adaptive: AdaptiveMusic
var battle_audio: BattleAudio


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_create_buses()
	for i in POOL_SIZE:
		_pool.append(_make_player("SFX"))
	for i in UI_POOL_SIZE:
		_ui_pool.append(_make_player("UI"))
	for i in CROWD_POOL_SIZE:
		_crowd_pool.append(_make_player("Crowd"))
	_music_a = _make_player("MusicMix")
	_music_b = _make_player("MusicMix")
	_sting = _make_player("Music")
	for i in 2:
		_ambience.append(_make_player("AmbienceMix"))
	_load_manifest()
	adaptive = AdaptiveMusic.new()
	adaptive.name = "AdaptiveMusic"
	add_child(adaptive)
	battle_audio = BattleAudio.new()
	battle_audio.name = "BattleAudio"
	battle_audio.audio = self
	add_child(battle_audio)


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _add_bus(bus_name: String, send: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(AudioServer.get_bus_index(bus_name), send)


func _create_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambience", "UI"]:
		_add_bus(bus_name, "Master")
	_add_bus("MusicMix", "Music")
	_add_bus("Crowd", "SFX")
	_add_bus("AmbienceMix", "Ambience")
	# Gentle limiter on the master to keep stacked effects from clipping.
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(master, lim)


func _load_manifest() -> void:
	if not FileAccess.file_exists(MANIFEST):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var by_name: Variant = parsed.get("volume_db_by_name", {})
	if typeof(by_name) == TYPE_DICTIONARY:
		for k in by_name.keys():
			_volume_overrides[str(k)] = float(by_name[k])
	var arenas: Variant = parsed.get("arenas", {})
	if typeof(arenas) == TYPE_DICTIONARY:
		for a in arenas.keys():
			var layers: Variant = arenas[a].get("layers", {})
			if typeof(layers) == TYPE_DICTIONARY:
				_arena_layers[str(a)] = layers


## Manifest playback volume (dB) for a sound or music name (0 if unknown).
func volume_of(name: String) -> float:
	return float(_volume_overrides.get(name, 0.0))


func _resolve(name: String) -> Array:
	if _variants.has(name):
		return _variants[name]
	var list: Array = []
	var names: Array = [name]
	names.append_array(ALIASES.get(name, []))
	for base in names:
		var single: String = SFX_DIR + base + ".wav"
		if ResourceLoader.exists(single):
			list.append({"s": load(single), "v": volume_of(base)})
		for i in range(1, MAX_VARIANTS + 1):
			var p := SFX_DIR + "%s_%d.wav" % [base, i]
			if ResourceLoader.exists(p):
				var file := "%s_%d" % [base, i]
				list.append({"s": load(p), "v": float(_volume_overrides.get(file, volume_of(base)))})
	_variants[name] = list
	return list


## Picks a variant, never the same one twice in a row when there is a choice.
func _pick(name: String, streams: Array) -> Dictionary:
	if streams.size() == 1:
		return streams[0]
	var last := int(_last_variant.get(name, -1))
	var i := _rng.randi() % streams.size()
	if i == last:
		i = (i + 1 + _rng.randi() % (streams.size() - 1)) % streams.size()
	_last_variant[name] = i
	return streams[i]


func _voice_limit(name: String) -> int:
	if VOICE_LIMITS.has(name):
		return int(VOICE_LIMITS[name])
	return DEFAULT_VOICES


## Plays a one-shot effect. Rate-limited per name so swarms of hits don't stack into noise;
## frequent sounds also get voice limiting, level randomisation and a pile-up back-off.
func play(name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06, min_gap_ms: int = 45) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -10000)) < min_gap_ms:
		return
	var streams := _resolve(name)
	if streams.is_empty():
		return
	_last_played[name] = now
	var pool := _crowd_pool if name.begins_with(CROWD_PREFIX) else _pool
	var p := _voice_for(pool, name)
	var v := _pick(name, streams)
	var db := volume_db + float(v.v)
	if FREQUENT.has(name):
		var spread := float(FREQUENT[name])
		db += _rng.randf_range(-spread, spread * 0.5)
		db -= _density_db(name, now)
	p.stream = v.s
	p.volume_db = db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter) if pitch_jitter > 0.0 else 1.0
	if Engine.time_scale < 1.0:
		# Slow motion lowers the pitch a little; hit-stop freezes (tiny time scales) don't.
		p.pitch_scale *= clampf(lerpf(1.0, Engine.time_scale, 0.5), 0.75, 1.0)
	p.set_meta("sfx", name)
	p.play()


func _density_db(name: String, now: int) -> float:
	var list: Array = _recent.get(name, [])
	var keep: Array = []
	for t in list:
		if now - int(t) < DENSITY_WINDOW_MS:
			keep.append(t)
	keep.append(now)
	_recent[name] = keep
	return minf(maxf(0.0, keep.size() - 2) * DENSITY_DB_PER_HIT, DENSITY_MAX_DB)


func ui(name: String, volume_db: float = 0.0) -> void:
	var streams := _resolve(name)
	if streams.is_empty():
		return
	var p := _free_player(_ui_pool)
	var v: Dictionary = streams[0]
	p.stream = v.s
	p.volume_db = volume_db + float(v.v)
	p.pitch_scale = 1.0
	p.play()


## A voice for `name`: when the name already uses its voice limit, its oldest voice is re-used.
func _voice_for(pool: Array[AudioStreamPlayer], name: String) -> AudioStreamPlayer:
	var limit := _voice_limit(name)
	var count := 0
	var oldest: AudioStreamPlayer = null
	var oldest_pos := -1.0
	for p in pool:
		if p.playing and p.get_meta("sfx", "") == name:
			count += 1
			var pos := p.get_playback_position()
			if pos > oldest_pos:
				oldest_pos = pos
				oldest = p
	if count >= limit and oldest != null:
		oldest.stop()
		return oldest
	return _free_player(pool)


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


## Number of voices currently playing `name` (tests and debugging).
func voices_playing(name: String) -> int:
	var n := 0
	for pool in [_pool, _crowd_pool]:
		for p in pool:
			if p.playing and p.get_meta("sfx", "") == name:
				n += 1
	return n


# ---------------------------------------------------------------- music

func play_music(name: String, fade := 1.2) -> void:
	if battle_audio:
		if name in ADAPTIVE_NAMES:
			battle_audio.on_music_request(name)
		elif name == "victory" and battle_audio.is_active():
			battle_audio.on_victory()
	if name in NON_LOOPING_MUSIC and _sting.playing:
		# The results jingle takes over from a boss sting still ringing out.
		var tw := create_tween()
		tw.tween_property(_sting, "volume_db", _sting.volume_db - 30.0, 0.5)
		tw.tween_callback(_sting.stop)
	if name in ADAPTIVE_NAMES and _start_adaptive(fade):
		_fade_out_track(fade)
		_music_name = name
		return
	if name == _music_name:
		return
	if adaptive and adaptive.is_playing():
		adaptive.stop(fade)
	_music_name = name
	_fade_out_track(fade)
	var path := MUSIC_DIR + name + ".ogg"
	if name == "" or not ResourceLoader.exists(path):
		return
	var next := _music_b if _music_current == _music_a else _music_a
	_music_current = next
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = not name in NON_LOOPING_MUSIC
	next.stream = stream
	next.volume_db = -40.0
	next.play()
	create_tween().tween_property(next, "volume_db", volume_of(name), fade)


func _fade_out_track(fade: float) -> void:
	var prev := _music_current
	_music_current = null
	if prev and prev.playing:
		var tw := create_tween()
		tw.tween_property(prev, "volume_db", -40.0, fade)
		tw.tween_callback(prev.stop)


## Battle music: the arena's stems when a battle is running and the arena has them.
func _start_adaptive(fade: float) -> bool:
	if adaptive == null or battle_audio == null or not battle_audio.is_active():
		return false
	var id := battle_audio.arena_id()
	if not _arena_layers.has(id):
		id = "steel_yard" if _arena_layers.has("steel_yard") else ""
	if id == "":
		return false
	var first_layer := "%s_calm" % id
	return adaptive.start(id, _arena_layers[id], volume_of(first_layer) if _volume_overrides.has(first_layer) else -7.0, fade)


func stop_music(fade := 1.0) -> void:
	play_music("", fade)


## Name of the music currently requested ("battle_theme" while the adaptive stems play).
func current_music() -> String:
	return _music_name


## A short one-shot cue on the Music bus that is not ducked (boss intro, boss defeated).
func play_sting(name: String, volume_db := 0.0) -> void:
	var path := MUSIC_DIR + name + ".ogg"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	_sting.stream = stream
	_sting.volume_db = volume_db + volume_of(name)
	_sting.play()


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


## Temporarily ducks music (e.g. during the boss warning). Overlapping ducks keep the deepest.
func duck_music(amount_db: float, time: float) -> void:
	_ducks.append({"db": absf(amount_db), "until": Time.get_ticks_msec() + int(time * 1000.0)})


## Extra level (dB) on the ambience beds, e.g. a swell with the crowd's excitement.
func set_ambience_swell(db: float) -> void:
	_ambience_swell_db = clampf(db, -12.0, 6.0)


func music_duck_db() -> float:
	return _duck_db


func _process(_delta: float) -> void:
	var usec := Time.get_ticks_usec()
	var delta := clampf((usec - _last_usec) / 1000000.0, 0.0, 0.1) if _last_usec > 0 else 0.0
	_last_usec = usec
	var now := Time.get_ticks_msec()
	var target := 0.0
	var i := _ducks.size() - 1
	while i >= 0:
		if now >= int(_ducks[i].until):
			_ducks.remove_at(i)
		else:
			target = maxf(target, float(_ducks[i].db))
		i -= 1
	# Fast attack (~0.15 s), slow release (~0.7 s).
	var rate := 60.0 if target > _duck_db else 12.0
	_duck_db = move_toward(_duck_db, target, rate * delta)
	var mix := AudioServer.get_bus_index("MusicMix")
	if mix >= 0:
		AudioServer.set_bus_volume_db(mix, -_duck_db)
	var amb := AudioServer.get_bus_index("AmbienceMix")
	if amb >= 0:
		var cur := AudioServer.get_bus_volume_db(amb)
		AudioServer.set_bus_volume_db(amb, move_toward(cur, _ambience_swell_db, 6.0 * delta))
