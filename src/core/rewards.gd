class_name Rewards
extends RefCounted
## Converts a finished run into permanent progression: coins, account XP,
## defender XP, card packs, rank points, records, stats and history.

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

	var coins := int(round((run.coins_earned * 0.55 + cleared * 22 + (160 if won else 0)) * mult))
	var xp := maxi(15, int(round((run.outs_total * 2.0 + cleared * 30 + (220 if won else 0)) * mult)))
	Profile.add_coins(coins)
	var levels := Profile.add_xp(xp)

	# Defender XP: everyone on the team, MVP gets +50%.
	var mvp := run.mvp()
	var def_xp := {}
	for id in run.team:
		var amount := int(round(xp * 0.55 * (1.5 if id == mvp else 1.0)))
		var gained := Profile.add_defender_xp(id, amount)
		def_xp[id] = {"xp": amount, "levels": gained, "level": Profile.defender_level(id)}

	# Card packs (opened from the Packs screen). Level-up and signature packs are added by Profile.
	var src := "%s %s" % [mode.name, "win" if won else "reward"]
	Profile.add_pack("rookie", src)
	match run.mode_id:
		"standard":
			for i in cleared / 3:
				Profile.add_pack("rookie", src)
			if won:
				Profile.add_pack("champion" if run.difficulty_id in ["veteran", "legend"] else "pro", src)
		"quick":
			if won:
				Profile.add_pack("rookie", src)
		"endless":
			for i in mini(cleared / 3, 4):
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
		if run.mode_id != "endless":
			records.append("New best score for %s!" % mode.name)
	Profile.refresh_unlocks()

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
	}
	Profile.add_history({"won": won, "mode": run.mode_id, "difficulty": run.difficulty_id, "arena": run.arena_id,
		"inning": run.inning, "score": run.score, "outs": run.outs_total, "runs": run.runs, "date": result.date})
	Profile.save_now()
	return result
