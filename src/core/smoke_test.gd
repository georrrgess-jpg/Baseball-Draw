class_name SmokeTest
extends Node
## Release-build smoke test (`BaseballDraw.exe --headless -- --smoke-test`, run by CI on Windows).
## Opens the main menu, plays a Quick Defense game on autopilot at high speed (until it ends or
## GAME_SECONDS of game time pass, then concedes so the rewards path runs too), saves the profile,
## reloads it and checks that it round-trips. Prints "SMOKE TEST: PASS" and exits 0, or
## "SMOKE TEST: FAIL - <reason>" and exits 1. Any engine or script error logged meanwhile fails it.
## Uses its own profile ("smoke", reset at start) unless --profile=<name> is given.

const GAME_SECONDS := 60.0
const SPEED := 4.0
const WALL_LIMIT_MS := 300000

var _errors := ErrorCounter.new()
var _start_ms := 0
var _failed := false


## Counts errors logged by the engine and scripts (Godot 4.5+ Logger).
class ErrorCounter extends Logger:
	var count := 0
	var first := ""
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		count += 1
		if first == "":
			first = "%s (%s:%d %s)" % [rationale if rationale != "" else code, file, line, function]
		_mutex.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


## Pure helper (unit-tested): the verdict from what the run observed.
static func verdict(checks: Dictionary) -> String:
	for k in ["menu", "battle", "played", "results", "saved", "reloaded"]:
		if not bool(checks.get(k, false)):
			return "FAIL - step '%s' did not complete" % k
	if int(checks.get("errors", 0)) > 0:
		return "FAIL - %d error(s) logged, first: %s" % [int(checks.errors), str(checks.get("first_error", ""))]
	return "PASS"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(_errors)
	_start_ms = Time.get_ticks_msec()
	_run.call_deferred()


func _log(text: String) -> void:
	print("[SMOKE] %6.1fs %s" % [(Time.get_ticks_msec() - _start_ms) / 1000.0, text])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Changes scene through the Router (which fades and loads in the background) and waits for it.
func _goto(scene_name: String) -> bool:
	while Router.busy and not _over_time():
		await get_tree().process_frame
	Router.goto(scene_name)
	await get_tree().process_frame
	while Router.busy and not _over_time():
		await get_tree().process_frame
	return Router.current == scene_name and get_tree().current_scene != null


func _over_time() -> bool:
	return Time.get_ticks_msec() - _start_ms > WALL_LIMIT_MS


func _run() -> void:
	var checks := {}
	if not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--profile=")):
		_use_smoke_profile()
	_log("profile ready (%s, status %s)" % [Profile.SAVE_PATH, Profile.load_status])

	# 1. Main menu.
	checks.menu = await _goto("main_menu")
	await _frames(30)
	_log("main menu: %s" % checks.menu)

	# 2. A Quick Defense game on autopilot.
	var cfg := Session.new_run_config("quick")
	cfg.auto_test = true
	cfg.auto_quit = false
	cfg.difficulty = "standard"
	while Router.busy and not _over_time():
		await get_tree().process_frame
	Session.start(cfg)
	await get_tree().process_frame
	while Router.busy and not _over_time():
		await get_tree().process_frame
	var battle := get_tree().current_scene as Battle
	checks.battle = battle != null
	_log("battle loaded: %s" % checks.battle)
	if battle == null:
		_finish(checks)
		return
	Engine.time_scale = SPEED
	var game_t := 0.0
	var last := Time.get_ticks_msec()
	while is_instance_valid(battle) and not battle.run.finished and game_t < GAME_SECONDS and not _over_time():
		await get_tree().process_frame
		Engine.time_scale = SPEED   # the battle resets it between innings
		game_t += get_process_delta_time()
	checks.played = is_instance_valid(battle) and (battle.run.outs_total > 0 or battle.run.finished)
	_log("played %.0fs of game time: inning %d, %d outs, %d runs" % [game_t, battle.run.inning, battle.run.outs_total, battle.run.runs])
	if not battle.run.finished:
		battle.abandon()
	Engine.time_scale = 1.0
	await _frames(20)
	checks.results = battle.run.finished and not Session.last_result.is_empty()
	_log("results: %s (won %s, %d coins, %d packs)" % [checks.results, battle.run.won, int(Session.last_result.get("coins", 0)),
		Session.last_result.get("packs", []).size()])

	# 3. Save, reload and compare.
	var before := {"coins": int(Profile.data.coins), "xp": int(Profile.data.xp), "level": int(Profile.data.level),
		"packs": Profile.pack_count(), "history": Profile.data.history.size(), "runs": Profile.stat("runs_played")}
	Profile.save_now()
	checks.saved = FileAccess.file_exists(Profile.SAVE_PATH)
	Profile.data = {}
	Profile.load_profile()
	var after := {"coins": int(Profile.data.coins), "xp": int(Profile.data.xp), "level": int(Profile.data.level),
		"packs": Profile.pack_count(), "history": Profile.data.history.size(), "runs": Profile.stat("runs_played")}
	checks.reloaded = Profile.load_status == "ok" and str(before) == str(after) and int(after.history) > 0
	_log("save/reload: %s %s" % [checks.reloaded, after])
	await _goto("main_menu")
	await _frames(10)
	_finish(checks)


func _use_smoke_profile() -> void:
	Profile._file_base = "profile_smoke"
	Profile.SAVE_PATH = "user://profile_smoke.json"
	Profile.BACKUP_PATH = "user://profile_smoke.bak"
	Profile.TMP_PATH = "user://profile_smoke.tmp"
	for path in [Profile.SAVE_PATH, Profile.BACKUP_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Profile.load_profile()


func _finish(checks: Dictionary) -> void:
	checks.errors = _errors.count
	checks.first_error = _errors.first
	var v := verdict(checks)
	if _over_time() and v == "PASS":
		v = "FAIL - took longer than %d s" % (WALL_LIMIT_MS / 1000)
	print("SMOKE TEST: %s" % v)
	OS.remove_logger(_errors)
	get_tree().quit(0 if v == "PASS" else 1)
