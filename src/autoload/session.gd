extends Node
## Hands run configuration and results between scenes.

## Configuration for the next battle. Keys: mode, difficulty, arena, deck, team, captain,
## formation, seed, resume (RunState dict or null), practice (bool), ranked_division.
## Daily Challenge games also carry: daily (date), modifiers, bosses, card_level.
var run_config: Dictionary = {}
## Result of the last finished battle (used by menus for "recent progress").
var last_result: Dictionary = {}
## Scene to return to from sub-menus.
var return_scene := "main_menu"
var menu_tab := ""


func _ready() -> void:
	# Card mastery counts every card cast in a real game. Listening for battles here keeps the
	# count out of the battle code: each cast lands in run.stats.card_casts (saved with the run).
	get_tree().node_added.connect(_on_node_added)


func new_run_config(mode_id: String) -> Dictionary:
	if mode_id == "daily":
		return DailyChallenge.config_for()
	var p: Dictionary = Profile.data
	var cfg := {
		"mode": mode_id,
		"difficulty": p.difficulty,
		"arena": p.arena,
		"deck": p.deck.duplicate(),
		"team": p.team.duplicate(),
		"captain": p.captain,
		"formation": p.formation,
		"seed": randi(),
		"resume": null,
	}
	if mode_id == "practice":
		cfg.difficulty = "standard"
	return cfg


func start(cfg: Dictionary) -> void:
	run_config = cfg
	DailyChallenge.set_active(cfg.has("daily"))
	Router.goto("battle")


func continue_saved_run() -> bool:
	if not Profile.has_saved_run():
		return false
	var saved: Dictionary = Profile.data.current_run
	var cfg: Dictionary = saved.get("config", {}).duplicate(true)
	cfg["resume"] = saved
	start(cfg)
	return true


# ---------------------------------------------------------------- card mastery tracking

func _on_node_added(n: Node) -> void:
	if n.has_signal("card_cast") and n.has_signal("boss_spawned") and "run" in n:
		n.connect("card_cast", _on_card_cast.bind(n))
		if "--demo-mastery" in OS.get_cmdline_user_args():
			n.ready.connect(_demo_mastery.bind(n), CONNECT_ONE_SHOT)


func _on_card_cast(id: String, b: Node) -> void:
	var run: RunState = b.get("run")
	if run == null or bool(b.get("practice")):
		return
	var casts: Variant = run.stats.get("card_casts")
	if typeof(casts) != TYPE_DICTIONARY:
		casts = {}
		run.stats["card_casts"] = casts
	casts[id] = int(casts.get(id, 0)) + 1


## Screenshot helper (`--demo-mastery`, with `--show-results`): a few cards are one play short of
## a star and the run played them, so the Results screen shows the mastery moments.
func _demo_mastery(b: Node) -> void:
	var run: RunState = b.get("run")
	if run == null:
		return
	var casts := {}
	var i := 0
	for cid in run.deck.slice(0, 5):
		var target: int = CardMastery.THRESHOLDS[i % 3]
		Profile.data.cards[cid]["plays"] = maxi(0, target - 2) if i < 2 else 3 + i * 4
		casts[cid] = 3 if i < 2 else 2
		i += 1
	run.stats["card_casts"] = casts
