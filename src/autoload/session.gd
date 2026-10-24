extends Node
## Hands run configuration and results between scenes.

## Configuration for the next battle. Keys: mode, difficulty, arena, deck, team, captain,
## formation, seed, resume (RunState dict or null), practice (bool), ranked_division.
var run_config: Dictionary = {}
## Result of the last finished battle (used by menus for "recent progress").
var last_result: Dictionary = {}
## Scene to return to from sub-menus.
var return_scene := "main_menu"
var menu_tab := ""


func new_run_config(mode_id: String) -> Dictionary:
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
	Router.goto("battle")


func continue_saved_run() -> bool:
	if not Profile.has_saved_run():
		return false
	var saved: Dictionary = Profile.data.current_run
	var cfg: Dictionary = saved.get("config", {}).duplicate(true)
	cfg["resume"] = saved
	start(cfg)
	return true
