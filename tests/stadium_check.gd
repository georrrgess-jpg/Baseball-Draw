extends Node
## Gate clearance report for every arena (see StadiumClearance). Run headless:
##   godot --headless --path . res://tests/stadium_check.tscn [-- --arena=<id>]
## Exits with code 1 when any stadium geometry intrudes into a doorway, a door sweep, a spawn
## area or a runner/boss corridor.


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arena="):
			only = a.get_slice("=", 1)
	var env := StadiumClearance.enemy_envelopes()
	print("corridors: runner %.2f m wide x %.2f m high, boss %.2f m wide x %.2f m high" % [env.runner.x, env.runner.y, env.boss.x, env.boss.y])
	var total := 0
	for aid in DB.arena_order:
		if only != "" and aid != only:
			continue
		var t0 := Time.get_ticks_msec()
		var hits := StadiumClearance.check_arena(self, aid, env)
		total += hits.size()
		print(StadiumClearance.format_report(aid, hits), "   (%d ms; %s)" % [Time.get_ticks_msec() - t0, str(StadiumClearance.last_stats)])
	print("==== %d intrusion(s) ====" % total)
	get_tree().quit(1 if total > 0 else 0)
