class_name Rewards
extends RefCounted
## Converts a finished run into permanent progression: coins, account XP,
## defender XP, card packs, rank points, records, stats and history.

# Tuned with tools/balance/economy.py (Update 5): about 7-9 packs and 2,000-2,500 coins per hour of play,
# the whole collection in ~15-20 hours, the team at level 10 after ~12 hours.
const COIN_SHARE := 0.35           # of the coins earned during the run
const COINS_PER_INNING := 15
const WIN_COINS := 100
const DEFENDER_XP_SHARE := 0.3     # of the account XP, for every defender on the team
const DEFENDER_XP_PER_OUT := 1
# First-hour pacing (Update 6): the first win ever pays a Pro Pack and coins on top.
const FIRST_WIN_COINS := 150
const FIRST_WIN_PACK := "pro"


static func innings_cleared(run: RunState, won: bool) -> int:
	if won:
		return run.inning
	return maxi(0, run.inning - 1) if run.wave < run.waves_per_inning else run.inning


static func apply(run: RunState, won: bool) -> Dictionary:
	var mode := DB.mode(run.mode_id)
	var diff := DB.difficulty(run.difficulty_id)
	var arena_mod: Dictionary = DB.arena(run.arena_id).get("modifier", {})
	var mult := float(mode.get("reward_mult", 1.0)) * float(diff.get("reward", 1.0)) * (1.0 + float(arena_mod.get("reward", 0.0)))
	var cleared := innings_cleared(run, won)
	var unlocked_before: Dictionary = Profile.data.achievements.duplicate()
	var level_before := int(Profile.data.level)
	var division_before := int(Profile.data.division)
	var packs_before := Profile.pack_count()

	var coins := int(round((run.coins_earned * COIN_SHARE + cleared * COINS_PER_INNING + (WIN_COINS if won else 0)) * mult))
	# Daily Challenge bonus (first game of the day: coins + a Rookie Pack; first win: a Pro Pack)
	# is added by DailyChallenge.record_result below and shown separately on the Results screen.
	var xp := maxi(15, int(round((run.outs_total * 2.0 + cleared * 30 + (220 if won else 0)) * mult)))
	Profile.add_coins(coins)
	var levels := Profile.add_xp(xp)

	# Defender XP: everyone on the team gets a share of the account XP, +1 per runner they got out, MVP +50%.
	var mvp := run.mvp()
	var def_xp := {}
	for id in run.team:
		var outs := int(run.stats.get("outs_by", {}).get(id, 0))
		var amount := int(round((xp * DEFENDER_XP_SHARE + outs * DEFENDER_XP_PER_OUT) * (1.5 if id == mvp else 1.0)))
		var d_level_before := Profile.defender_level(id)
		var xp_before := Profile.defender_xp(id)
		var gained := Profile.add_defender_xp(id, amount)
		var rewards: Array = []
		for l in range(d_level_before + 1, Profile.defender_level(id) + 1):
			var t := Profile.level_reward_text(Profile.defender_level_reward(l))
			if t != "":
				rewards.append(t)
		def_xp[id] = {"xp": amount, "levels": gained, "level": Profile.defender_level(id), "level_before": d_level_before,
			"xp_before": xp_before, "xp_after": Profile.defender_xp(id), "rewards": rewards, "outs": outs}

	# Card packs (opened from the Packs screen). Level-up and signature packs are added by Profile.
	var src := "%s %s" % [mode.name, "win" if won else "reward"]
	Profile.add_pack("rookie", src)
	match run.mode_id:
		"standard":
			if won:
				Profile.add_pack("champion" if run.difficulty_id in ["veteran", "legend"] else "pro", src)
		"endless":
			for i in mini(cleared / 5, 2):
				Profile.add_pack("rookie", src)
		"ranked":
			if won:
				Profile.add_pack("pro", src)

	# Rank points.
	var rp := 0
	var rp_mult := float(diff.get("rp", 1.0))
	match run.mode_id:
		"standard": rp = int(round((60 if won else cleared * 4) * rp_mult))
		"quick": rp = int(round((22 if won else cleared * 3) * rp_mult))
		"endless": rp = int(round(cleared * 5 * rp_mult))
		"ranked": rp = int(round((30 if won else 0) * rp_mult))
	Profile.data.rp = int(Profile.data.rp) + rp
	var promoted := false
	if run.mode_id == "ranked" and won:
		Profile.promote()
		promoted = true

	# Stats, achievements and records.
	if won:
		Profile.bump_stat("wins_" + run.mode_id)
		if run.mode_id == "standard":
			Profile.bump_stat("wins_standard_" + run.difficulty_id)
			if run.difficulty_id == "legend":
				Profile.bump_stat("wins_standard_veteran")
			if run.runs == 0:
				Profile.bump_stat("perfect_games")
		if run.mode_id == "quick" and int(run.stats.get("cards_played", 0)) == 0:
			Profile.bump_stat("no_card_wins")
	Profile.bump_stat("runs_played")
	Profile.bump_stat("clean_innings", float(run.stats.get("clean_innings", 0)))
	Profile.bump_stat("caught_stealing", float(run.stats.get("caught_stealing", 0)))
	# First win ever: a one-time bonus so the first session pays well.
	var first_win := false
	if won and not bool(Profile.data.flags.get("first_win_bonus", false)):
		Profile.data.flags["first_win_bonus"] = true
		first_win = true
		Profile.add_coins(FIRST_WIN_COINS)
		Profile.add_pack(FIRST_WIN_PACK, "First win bonus")
	var records: Array = []
	if run.mode_id == "endless":
		var reached := run.inning
		if reached > int(Profile.data.records.get("best_endless_inning", 0)):
			Profile.data.records.best_endless_inning = reached
			records.append("New Endless record: inning %d!" % reached)
		if run.score > int(Profile.data.records.get("best_endless_score", 0)):
			Profile.data.records.best_endless_score = run.score
			records.append("New Endless high score: %s" % UITheme.format_int(run.score))
		Profile.set_stat_max("best_endless_inning", reached)
	var best_key := "best_score_" + run.mode_id
	if run.score > int(Profile.data.records.get(best_key, 0)):
		Profile.data.records[best_key] = run.score
		if run.mode_id != "endless" and not run.is_daily():
			records.append("New best score for %s!" % mode.name)
	Profile.refresh_unlocks()

	# Card mastery (cosmetic) from the cards played, and the Daily Challenge record + bonus.
	var mastery := CardMastery.apply_run(run)
	var daily := {}
	if run.is_daily():
		daily = DailyChallenge.record_result(run, won)
	# Missions: end-of-game events (live ones already counted during the game).
	Missions.on_run(run, won, cleared)
	var level_rewards: Array = []
	for l in range(level_before + 1, int(Profile.data.level) + 1):
		level_rewards.append({"level": l, "text": LevelRoad.reward_text(l)})

	var new_achievements: Array = []
	for id in Profile.data.achievements.keys():
		if not unlocked_before.has(id):
			new_achievements.append(id)

	var result := {
		"won": won, "mode": run.mode_id, "difficulty": run.difficulty_id, "arena": run.arena_id,
		"inning": run.inning, "innings_cleared": cleared, "outs": run.outs_total, "runs": run.runs, "run_limit": run.run_limit,
		"score": run.score, "coins": coins, "xp": xp, "levels": levels, "level_before": level_before,
		"defender_xp": def_xp, "mvp": mvp, "packs": Profile.data.packs.slice(packs_before), "rp": rp, "promoted": promoted,
		"division_before": division_before, "records": records, "achievements": new_achievements,
		"stats": run.stats.duplicate(true), "date": Time.get_datetime_string_from_system(),
		"mastery": mastery, "daily": daily,
		"missions": Missions.take_fresh(), "level_rewards": level_rewards,
		"first_win": first_win, "first_win_coins": FIRST_WIN_COINS if first_win else 0,
	}
	Profile.add_history({"won": won, "mode": run.mode_id, "difficulty": run.difficulty_id, "arena": run.arena_id,
		"inning": run.inning, "score": run.score, "outs": run.outs_total, "runs": run.runs, "date": result.date})
	Profile.save_now()
	return result
