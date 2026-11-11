extends Node
## Hands run configuration and results between scenes.

## Configuration for the next battle. Keys: mode, difficulty, arena, deck, team, captain,
## formation, seed, resume (RunState dict or null), practice (bool), ranked_division.
## Daily Challenge games also carry: daily (date), modifiers, bosses, card_level.
## The first game (Update 13) also carries: innings, bosses, tuning, first_game.
var run_config: Dictionary = {}
## Result of the last finished battle (used by menus for "recent progress").
var last_result: Dictionary = {}
## Scene to return to from sub-menus.
var return_scene := "main_menu"
var menu_tab := ""
## Update 13 (Rookie Camp): the guided reward sequence after the first win. "pack" while the
## Card Packs screen walks the player through the first opening, "deck" while Cards & Deck walks
## them through adding the new card (`guide_card`), "" otherwise. Not saved: leaving the sequence
## drops it, and the hub picks up from `flags.ftue_return_hub`.
var guide := ""
var guide_card := ""

## The first game (Update 13): a short Quick Defense on Rookie with a first-game assist. Two innings
## instead of three, a weakened Iron Slugger closing inning 2 as the first boss, a fixed seed so the
## guided moments are the same for everyone, and gentler runners.
const FIRST_GAME_SEED := 1301
const FIRST_GAME_INNINGS := 2
const FIRST_GAME_TUNING := {"enemy_hp": 0.85, "budget": 0.85, "boss_hp": 0.3}
## Detailed funnel steps (Profile.data.onboarding_funnel.ftue), in the order a new player normally
## reaches them. The shared keys of Profile.data.onboarding_funnel (Onboarding.funnel_default:
## first_launch, first_game, first_win, first_pack, game_2, day2_return) are datetime strings: this
## flow writes first_launch and first_pack there, Onboarding writes the rest.
const FUNNEL_STEPS := ["first_launch", "intro_done", "first_game_start", "first_throw", "first_card",
	"first_win", "first_pack_opened", "deck_edited", "game2_start", "day2_return"]
## Detailed steps mirrored into the shared funnel keys.
const FUNNEL_SHARED := {"first_launch": "first_launch", "first_pack_opened": "first_pack"}


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
	note_game_start(cfg)
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


# ---------------------------------------------------------------- first session (Update 13)

## A brand-new player: no tutorial seen, no game played. Only they get the story intro, the guided
## first game and the guided rewards; every existing profile goes straight to the hub.
func is_new_player() -> bool:
	var flags: Dictionary = Profile.data.get("flags", {})
	if bool(flags.get("tutorial_done", false)) or bool(flags.get("battle_tutorial_done", false)):
		return false
	return (Profile.data.get("history", []) as Array).is_empty() and int(Profile.data.get("stats", {}).get("runs_played", 0)) == 0


## The first game's run configuration (see FIRST_GAME_*).
func first_game_config() -> Dictionary:
	var cfg := new_run_config("quick")
	cfg.difficulty = "rookie"
	cfg.arena = "steel_yard"
	cfg.seed = FIRST_GAME_SEED
	cfg["innings"] = FIRST_GAME_INNINGS
	cfg["bosses"] = {str(FIRST_GAME_INNINGS): "iron_slugger"}
	cfg["tuning"] = FIRST_GAME_TUNING.duplicate()
	cfg["first_game"] = true
	return cfg


## Straight from the title/intro into the guided first game (no stop at the hub).
func start_first_game() -> void:
	var flags: Dictionary = Profile.data.flags
	flags["tutorial_done"] = true          # the hub's welcome panel is for players who skipped this
	flags["battle_tutorial_done"] = false
	funnel_mark("first_game_start")
	Profile.save_soon()
	start(first_game_config())


## Funnel: the first new game after the first game (not a continued run, Practice or an autopilot test).
func note_game_start(cfg: Dictionary) -> bool:
	if bool(cfg.get("first_game", false)) or cfg.get("resume") != null or bool(cfg.get("auto_test", false)) \
			or str(cfg.get("mode", "")) == "practice" or not funnel().has("first_game_start"):
		return false
	if Profile.data.flags.has("ftue_return_hub"):
		Profile.data.flags["ftue_return_hub"] = false   # game 2 is under way: the hub's PLAY spotlight is done
	return funnel_mark("game2_start")


## "I've played before": skips the intro, the guided game and the guided rewards.
func skip_onboarding() -> void:
	var flags: Dictionary = Profile.data.flags
	flags["tutorial_done"] = true
	flags["battle_tutorial_done"] = true
	flags["ftue_skipped"] = true
	flags["ftue_rewards_done"] = true
	if funnel().has("first_launch"):
		funnel()["skipped"] = _now()
		print("[FTUE] skipped %.1f" % (_now() - float(funnel().first_launch)))
	Profile.save_soon()


## True while the guided reward sequence is still owed: the first win of a player who came through
## the guided first game.
func ftue_rewards_pending() -> bool:
	var flags: Dictionary = Profile.data.get("flags", {})
	return not bool(flags.get("ftue_rewards_done", false)) and not bool(flags.get("ftue_skipped", false)) \
		and funnel().has("first_game_start")


## Ends the guided reward sequence: back to the hub, which spotlights PLAY for game 2
## (`flags.ftue_return_hub`). `go` false only records it (the player left another way).
func finish_ftue_rewards(go := true) -> void:
	guide = ""
	guide_card = ""
	Profile.data.flags["ftue_rewards_done"] = true
	Profile.data.flags["ftue_return_hub"] = true
	Profile.save_soon()
	if go:
		Router.goto("main_menu")


## The detailed first-session funnel (Profile.data.onboarding_funnel.ftue): step -> unix time of the
## first time it was reached, plus "day" (the local calendar day index since the first launch, at the
## last launch) and "days" (each day index the game was opened on). Created here when missing.
func funnel() -> Dictionary:
	var root: Variant = Profile.data.get("onboarding_funnel", null)
	if typeof(root) != TYPE_DICTIONARY:
		root = Onboarding.funnel_default()
		Profile.data["onboarding_funnel"] = root
	var f: Variant = (root as Dictionary).get("ftue", null)
	if typeof(f) != TYPE_DICTIONARY:
		f = {}
		(root as Dictionary)["ftue"] = f
	return f


## Records a funnel step once. Only players whose first launch was recorded (new players) are
## tracked, so an existing profile never gets a half funnel. Prints "[FTUE] <step> <seconds>" for tests.
func funnel_mark(step: String) -> bool:
	var f := funnel()
	if step != "first_launch" and not f.has("first_launch"):
		return false
	if f.has(step):
		return false
	f[step] = _now()
	if FUNNEL_SHARED.has(step):
		Onboarding.funnel_mark(str(FUNNEL_SHARED[step]))   # keeps its first value
	print("[FTUE] %s %.1f" % [step, funnel_seconds(step)])
	Profile.save_soon()
	return true


## Seconds from the first launch to `step` (-1 when either is missing).
func funnel_seconds(step: String) -> float:
	var f := funnel()
	if not f.has("first_launch") or not f.has(step):
		return -1.0
	return float(f[step]) - float(f.first_launch)


## Called once per launch (boot): starts the funnel for a new player and keeps the day index (a
## launch on a later calendar day marks day2_return).
func funnel_on_launch() -> void:
	var f := funnel()
	if not f.has("first_launch"):
		if not is_new_player():
			return
		funnel_mark("first_launch")
	var day := day_index()
	f["day"] = day
	var days: Array = f.get("days", []) if typeof(f.get("days")) == TYPE_ARRAY else []
	if not days.has(day):
		days.append(day)
	f["days"] = days
	if day >= 1:
		funnel_mark("day2_return")   # the detailed one (the hub writes the shared day2_return)
	Profile.save_soon()


## Local calendar days since the first launch (0 on the first day).
func day_index(at: float = -1.0) -> int:
	var f := funnel()
	if not f.has("first_launch"):
		return 0
	if at < 0.0:
		at = _now()
	var bias := float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	return int(floor((at + bias) / 86400.0)) - int(floor((float(f.first_launch) + bias) / 86400.0))


func _now() -> float:
	return Time.get_unix_time_from_system()


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
