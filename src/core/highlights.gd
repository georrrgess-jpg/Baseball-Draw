class_name RunHighlights
extends Node
## Records the story of a run for the Results screen:
##   run.stats.timeline   — one entry per inning: runs allowed, outs, cards played,
##                          average and peak energy, seconds spent at full energy;
##   run.stats.highlights — the biggest combo, the best card play (most outs within a few
##                          seconds of the cast) and boss kills.
## Everything lives in run.stats, so it is saved with Continue Run and arrives in the
## Rewards result. Attached by Battle with one line: RunHighlights.attach(self).

const PLAY_WINDOW := 4.0     # seconds after a cast that count towards "best card play"
const SAMPLE_EVERY := 0.25

var battle: Battle
var _entry: Dictionary = {}
var _sample_t := 0.0
var _energy_sum := 0.0
var _energy_n := 0
var _pending: Array = []      # casts still inside their window: {id, t, outs, inning}
var _time := 0.0
var _last_combo := 0
var _demo := false


static func attach(b: Battle) -> RunHighlights:
	var h := RunHighlights.new()
	h.battle = b
	h.name = "RunHighlights"
	b.add_child(h)
	return h


func _ready() -> void:
	if battle == null or battle.run == null or battle.practice:
		set_process(false)
		return
	var st: Dictionary = battle.run.stats
	if typeof(st.get("timeline")) != TYPE_ARRAY:
		st["timeline"] = []
	if typeof(st.get("highlights")) != TYPE_DICTIONARY:
		st["highlights"] = {}
	_last_combo = int(st.get("max_combo", 0))
	battle.card_cast.connect(_on_card_cast)
	battle.boss_spawned.connect(_on_boss_spawned)
	var args := OS.get_cmdline_user_args()
	if "--show-results" in args:
		_demo = true
		_fill_demo()
	if "--open-pause" in args:   # screenshot helper
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if battle.hud.has_method("toggle_pause"):
				battle.hud.toggle_pause())


func _process(delta: float) -> void:
	if _demo or battle.run.finished:
		return
	_time += delta
	var run := battle.run
	_sync_entry()
	_entry.runs = run.runs_inning
	_entry.outs = run.outs_inning
	# Energy samples only while runners are on the field (setup and breaks would skew it).
	if battle.state == "wave":
		_sample_t -= delta
		if _sample_t <= 0.0:
			_sample_t = SAMPLE_EVERY
			var e := float(battle.cards.energy)
			_energy_sum += e
			_energy_n += 1
			_entry.energy_avg = snappedf(_energy_sum / _energy_n, 0.01)
			_entry.energy_peak = maxf(float(_entry.get("energy_peak", 0.0)), e)
			if e >= CardSystem.MAX_ENERGY - 0.05:
				_entry.capped = snappedf(float(_entry.get("capped", 0.0)) + SAMPLE_EVERY, 0.01)
	# Biggest combo, with the inning it happened in.
	var mc := int(run.stats.get("max_combo", 0))
	if mc > _last_combo:
		_last_combo = mc
		if mc >= 2:
			run.stats.highlights["best_combo"] = {"n": mc, "inning": run.inning}
	# Close card-play windows.
	while not _pending.is_empty() and _time - float(_pending[0].t) >= PLAY_WINDOW:
		_close_play(_pending.pop_front())


## Makes sure the timeline has an entry for the current inning (continuing a resumed one).
func _sync_entry() -> void:
	var run := battle.run
	var tl: Array = run.stats.timeline
	if not _entry.is_empty() and int(_entry.inning) == run.inning:
		return
	if not tl.is_empty() and int(tl[-1].get("inning", 0)) == run.inning:
		_entry = tl[-1]
	else:
		_entry = {"inning": run.inning, "runs": 0, "outs": 0, "cards": 0, "energy_avg": 0.0, "energy_peak": 0.0, "capped": 0.0}
		tl.append(_entry)
	_energy_sum = float(_entry.get("energy_avg", 0.0))
	_energy_n = 1 if _energy_sum > 0.0 else 0


func _on_card_cast(id: String) -> void:
	if _demo:
		return
	_sync_entry()
	_entry.cards = int(_entry.get("cards", 0)) + 1
	_pending.append({"id": id, "t": _time, "outs": battle.run.outs_total, "inning": battle.run.inning})


func _close_play(p: Dictionary) -> void:
	var outs := battle.run.outs_total - int(p.outs)
	var hl: Dictionary = battle.run.stats.highlights
	var best: Dictionary = hl.get("best_play", {})
	if outs > int(best.get("outs", 0)):
		hl["best_play"] = {"card": p.id, "outs": outs, "inning": p.inning}


func _on_boss_spawned(e: Enemy) -> void:
	if _demo:
		return
	var inning := battle.run.inning
	e.tree_exiting.connect(func() -> void:
		if not is_instance_valid(battle) or battle.run == null:
			return
		if e.id in battle.run.stats.get("bosses", []):
			var kills: Array = battle.run.stats.highlights.get("boss_kills", [])
			kills.append({"id": e.id, "inning": inning})
			battle.run.stats.highlights["boss_kills"] = kills)


## Screenshot/debug data matching battle.gd's --show-results shortcut (three innings).
func _fill_demo() -> void:
	var st: Dictionary = battle.run.stats
	st.timeline = [
		{"inning": 1, "runs": 0, "outs": 18, "cards": 4, "energy_avg": 5.2, "energy_peak": 9.0, "capped": 0.0},
		{"inning": 2, "runs": 1, "outs": 21, "cards": 5, "energy_avg": 6.4, "energy_peak": 10.0, "capped": 3.5},
		{"inning": 3, "runs": 0, "outs": 25, "cards": 5, "energy_avg": 4.1, "energy_peak": 8.5, "capped": 0.0},
	]
	var deck: Array = battle.run.deck
	st.highlights = {
		"best_combo": {"n": 4, "inning": 3},
		"best_play": {"card": deck[0] if not deck.is_empty() else "power_throw", "outs": 5, "inning": 2},
	}
