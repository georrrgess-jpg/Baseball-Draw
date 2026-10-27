class_name BattleAudio
extends Node
## Listens to the running Battle (found through SceneTree.node_added, no hooks in battle.gd)
## and drives the adaptive arena music, crowd reactions, stings, ducking and a few missing
## feedback sounds (card drawn into the hand, energy full).
##
## Battle signals used: state_changed, wave_started, score_changed, run_scored, boss_spawned,
## card_cast, banner_requested; optional (connected when present): boss_intro_started,
## boss_defeated.  CardSystem: card_drawn.

const OUT_GAP := 1.2           # min seconds between small out cheers
const BIG_GAP := 4.0
const ROAR_GAP := 20.0
const CHANT_GAP := 11.0
const TENSE_HOLD := 4.0        # tense layer stays at least this long once triggered

var audio: Node                # the Audio autoload
var battle: Node = null
var _cards: Object = null
var _last_outs := 0
var _t := 0.0
var _next_ok := {}             # reaction -> time it may play again
var _boss: Node = null
var _boss_hp := 0.0
var _boss_hit_acc := 0.0
var _boss_hit_t := 0.0
var _boss_wave := false
var _boss_defeat_handled := false
var _tense_until := 0.0
var _tense_on := false
var _energy_full := false
var _chant_alt := 0
var _log_on := false
var _last_roar := -100.0
var _last_layers := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_log_on = "--audio-log" in OS.get_cmdline_user_args()
	get_tree().node_added.connect(_on_node_added)


## With the --audio-log user argument, prints what the battle audio does (for headless runs).
func _log(msg: String) -> void:
	if _log_on:
		print("[audio %.1f] %s" % [_t, msg])


func _on_node_added(n: Node) -> void:
	var sc: Script = n.get_script()
	if sc != null and sc.get_global_name() == &"Battle":
		_attach(n)


func _attach(b: Node) -> void:
	if battle == b:
		return
	battle = b
	_cards = null
	_last_outs = 0
	_boss = null
	_boss_wave = false
	_boss_defeat_handled = false
	_tense_on = false
	_tense_until = 0.0
	_energy_full = false
	_next_ok.clear()
	b.tree_exiting.connect(_on_battle_exiting.bind(b))
	b.state_changed.connect(_on_state_changed)
	b.wave_started.connect(_on_wave_started)
	b.score_changed.connect(_on_score_changed)
	b.boss_spawned.connect(_on_boss_spawned)
	b.banner_requested.connect(_on_banner)
	b.card_cast.connect(_on_card_cast)
	if b.has_signal("boss_intro_started"):
		b.connect("boss_intro_started", _on_boss_intro_signal)
	if b.has_signal("boss_defeated"):
		b.connect("boss_defeated", _on_boss_defeated_signal)


func _on_battle_exiting(b: Node) -> void:
	if battle == b:
		battle = null
		_cards = null
		_boss = null
		audio.set_ambience_swell(0.0)


func is_active() -> bool:
	return battle != null and is_instance_valid(battle)


## Arena of the running battle ("" when none).
func arena_id() -> String:
	if not is_active():
		return ""
	var run: Variant = battle.get("run")
	if run == null:
		return ""
	return str(run.get("arena_id"))


func _ready_to(key: String, gap: float) -> bool:
	if _t < float(_next_ok.get(key, -1.0)):
		return false
	_next_ok[key] = _t + gap
	return true


# ---------------------------------------------------------------- music intensity

## Called by the Audio manager when the battle asks for battle_theme / boss_theme.
func on_music_request(name: String) -> void:
	_boss_wave = name == "boss_theme"
	if _boss_wave:
		_boss_defeat_handled = false


func _process(_delta: float) -> void:
	# Real time: reactions keep their spacing at 3x game speed and through hit-stop.
	var now := Time.get_ticks_msec() / 1000.0
	var delta := clampf(now - _t, 0.0, 0.1) if _t > 0.0 else 0.0
	_t = now
	if not is_active():
		return
	var b := battle
	if _cards == null and b.get("cards") != null:
		_cards = b.cards
		if _cards.has_signal("card_drawn"):
			_cards.card_drawn.connect(_on_card_drawn)
	_track_boss(delta)
	_update_energy()
	_update_music()
	# The stadium bed breathes with the crowd's excitement (0.2 calm .. 1.0 big plays).
	var ex := clampf(float(b.get("excitement")), 0.0, 1.0)
	audio.set_ambience_swell(lerpf(-2.0, 3.0, ex) if str(b.get("state")) == "wave" else -1.0)


func _update_music() -> void:
	var am: AdaptiveMusic = audio.adaptive
	if am == null or not am.is_playing():
		return
	var st := str(battle.get("state"))
	var in_wave := st == "wave"
	var boss_on := in_wave and ((_boss != null and is_instance_valid(_boss)) or (_boss_wave and not _boss_defeat_handled))
	var tense := in_wave and _is_tense()
	if tense:
		if not _tense_on:
			_tense_on = true
			_on_tension_start()
		_tense_until = _t + TENSE_HOLD
	elif _tense_on and _t > _tense_until:
		_tense_on = false
	var tense_v := 1.0 if (_tense_on and in_wave) else 0.0
	am.set_layers(1.0, 1.0 if in_wave else 0.0, 1.0 if boss_on else 0.0, tense_v)
	if _log_on:
		var key := "%s wave=%d boss=%d tense=%d" % [am.arena_id, int(in_wave), int(boss_on), int(tense_v)]
		if key != _last_layers:
			_last_layers = key
			_log("music layers " + key)


func _is_tense() -> bool:
	var run: Variant = battle.get("run")
	if run == null or bool(battle.get("practice")):
		return false
	var runs_left := int(run.run_limit) - int(run.runs)
	if runs_left <= 1:
		return true
	var danger: Variant = battle.get("_danger")
	if danger != null and float(danger) > 0.8 and runs_left <= 2:
		return true
	# The last out of the game: final wave of the final inning, almost cleared.
	if run.has_method("is_final_inning") and run.is_final_inning() and int(run.wave) >= int(run.waves_per_inning) - 1:
		var left := 0
		for e in battle.enemies:
			if is_instance_valid(e) and e.alive and e.id != "decoy":
				left += 1
		left += int(battle.spawn_queue.size())
		if left <= 2 and left > 0:
			return true
	return false


func _on_tension_start() -> void:
	if not _ready_to("chant", CHANT_GAP):
		return
	_chant_alt = (_chant_alt + 1) % 2
	_sfx("crowd_chant" if _chant_alt == 0 else "crowd_stomp", -1.0, 0.02, 0)


# ---------------------------------------------------------------- battle events

func _on_state_changed(s: String) -> void:
	if s == "setup" or s == "break":
		_boss_wave = false
	if s == "results":
		audio.duck_music(5.0, 1.0)


func _on_wave_started(info: Dictionary) -> void:
	_boss_defeat_handled = false
	_boss_wave = str(info.get("boss", "")) != ""


func _on_score_changed() -> void:
	var run: Variant = battle.get("run")
	if run == null:
		return
	var outs := int(run.outs_total)
	if outs <= _last_outs:
		_last_outs = outs
		return
	_last_outs = outs
	var combo := int(battle.get("combo_count"))
	# Scaled by the combo. battle.gd already adds its own cheer on every combo, so the extra
	# layers stay sparse: the full roar is kept for long chains, boss defeats and victory.
	if combo >= 8 and _ready_to("roar", ROAR_GAP):
		_sfx("crowd_roar", -3.0, 0.03, 0)
		_last_roar = _t
		audio.duck_music(4.0, 1.4)
	elif combo >= 3:
		if _ready_to("big", BIG_GAP):
			_sfx("crowd_big", -2.0 if combo == 3 else 0.0, 0.04, 0)
			if combo >= 4:
				audio.duck_music(3.0, 1.0)
	elif _ready_to("small", OUT_GAP):
		# Single outs: louder as the game heats up; a double play gets the loud end.
		var ex := clampf(float(battle.get("excitement")), 0.0, 1.0)
		_sfx("crowd_small", 1.0 if combo == 2 else lerpf(-6.0, -1.0, ex), 0.05, 0)


func _on_boss_spawned(e: Node) -> void:
	_boss = e
	_boss_hp = float(e.get("hp"))
	_boss_hit_acc = 0.0
	_boss_defeat_handled = false
	if not battle.has_signal("boss_intro_started"):
		_play_boss_intro()


func _on_boss_intro_signal(_a: Variant = null, _b: Variant = null) -> void:
	_play_boss_intro()


func _play_boss_intro() -> void:
	if not _ready_to("boss_intro", 3.0):
		return
	_sting("sting_boss_intro")
	audio.duck_music(9.0, 2.6)
	_sfx("crowd_ooh", -2.0, 0.03, 0)


func _on_boss_defeated_signal(_a: Variant = null, _b: Variant = null) -> void:
	_boss_defeated()


func _boss_defeated() -> void:
	if _boss_defeat_handled:
		return
	_boss_defeat_handled = true
	_boss = null
	_sting("sting_boss_defeat")
	audio.duck_music(8.0, 2.8)
	if _t - _last_roar > 3.0:
		_sfx("crowd_roar", -1.0, 0.0, 0)
		_last_roar = _t
		_next_ok["roar"] = _t + ROAR_GAP


func _track_boss(delta: float) -> void:
	_boss_hit_t -= delta
	if _boss_hit_t <= 0.0:
		_boss_hit_acc = 0.0
	if _boss == null:
		return
	if not is_instance_valid(_boss):
		_boss = null
		return
	var hp := float(_boss.get("hp"))
	var mx := maxf(float(_boss.get("max_hp")), 1.0)
	if hp < _boss_hp:
		_boss_hit_acc += (_boss_hp - hp) / mx
		_boss_hit_t = 0.6
		if _boss_hit_acc >= 0.18 and _ready_to("big", BIG_GAP):
			_sfx("crowd_big", -3.0, 0.04, 0)
			_boss_hit_acc = 0.0
		elif _boss_hit_acc >= 0.07 and _ready_to("boss_hit", 1.8):
			_sfx("crowd_small", -2.0, 0.05, 0)
			_boss_hit_acc = 0.0
	_boss_hp = hp
	if not bool(_boss.get("alive")):
		# Defeated if it went down on the field (an out), not if it reached home.
		if battle.has_signal("boss_defeated"):
			_boss = null
		elif hp <= 0.0:
			_boss_defeated()
		else:
			_boss = null


func _on_banner(text: String, _color: Color) -> void:
	# Fallback for the boss-defeated moment if hp was not observed reaching zero.
	if text.ends_with("DEFEATED!") and not battle.has_signal("boss_defeated"):
		_boss_defeated()


func _on_card_cast(_id: String) -> void:
	pass  # card_effects.gd already plays card_play + the effect sound.


func _on_card_drawn(_id: String) -> void:
	var st := str(battle.get("state"))
	if st in ["wave", "break", "setup"]:
		_sfx("card_draw", -7.0, 0.08, 150)


func _update_energy() -> void:
	if _cards == null:
		return
	var full := float(_cards.energy) >= CardSystem.MAX_ENERGY - 0.001
	if full and not _energy_full and str(battle.get("state")) in ["wave", "break", "setup"]:
		if _ready_to("energy_full", 4.0):
			_sfx("energy_full", -3.0, 0.0, 0)
	_energy_full = full


## Victory: the stands roar.
func on_victory() -> void:
	if _t - _last_roar > 3.0:   # don't restart a roar that is still going (boss defeated on the last out)
		_sfx("crowd_roar", 0.0, 0.0, 0)
		_last_roar = _t


func _sfx(name: String, db := 0.0, jitter := 0.05, gap := 0) -> void:
	_log("sfx %s %+.1f dB" % [name, db])
	audio.play(name, db, jitter, gap)


func _sting(name: String) -> void:
	_log("sting " + name)
	audio.play_sting(name)
