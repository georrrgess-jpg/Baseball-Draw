class_name Rewards
extends RefCounted
## Converts a finished run into permanent progression: coins, account XP,
## defender XP, card packs, rank points, records, stats and history.
##
## Update 9 ("Big League") adds on top of the game's own coins:
## * Win streak: consecutive wins in rewarded modes. A win pays the bonus the streak had before it
##   (Profile.streak_bonus: +10 % per win in the streak, at most +50 %), then extends the streak; a loss
##   resets it. The Endless Ninth has no win, so it neither extends nor resets the streak; Practice never
##   reaches Rewards. Result keys: streak, streak_bonus, streak_bonus_coins.
## * First win of the day: the first win of each local calendar day pays the game's coins twice
##   (result key first_win_today_coins: the extra half).
## * Season XP (Season.add_xp): 100 per game, +60 for a win, +100 for the day's first Daily Challenge.
## * Endless milestones: every 5 innings cleared pays 150 coins x (innings / 5) and a Rookie Pack, plus a Pro
##   Pack at 10 and 20 (they replace the old Rookie Pack per 5 innings).
## * Boss Rush: a win pays a Pro Pack; the fastest win is records.best_time_boss_rush (run.stats.time).
## * Promotion rewards (Profile.promote), and coins from extra copies of max-level cards (overflow_coins).
## Update 13 ("Rookie Camp", Onboarding.on_game_end): a bonus pack for each of a new manager's first three
## games, a consolation reward after a loss in the first five (with an easier difficulty / Auto Build tip),
## and the Epic pick after the third game. Result key "rookie".
## `coins` stays the game's own coins; every bonus has its own key and `coins_total` adds them all up.

# Tuned with tools/balance/economy.py (Update 5), then every coin reward raised by 50 % (coin boost):
# about 4,600 coins per hour of play. Prices are unchanged.
const COIN_SHARE := 0.525          # of the coins earned during the run
const COINS_PER_INNING := 22.5
const WIN_COINS := 150
const DEFENDER_XP_SHARE := 0.3     # of the account XP, for every defender on the team
const DEFENDER_XP_PER_OUT := 1
# First-hour pacing (Update 6): the first win ever pays a Pro Pack and coins on top.
const FIRST_WIN_COINS := 225
const FIRST_WIN_PACK := "pro"
# Update 9: daily first win, Endless milestones and Boss Rush.
const FIRST_WIN_TODAY_MULT := 2.0  # the day's first win pays its coins this many times
const MILESTONE_EVERY := 5         # Endless innings per milestone
const MILESTONE_COINS := 150       # x (innings / 5)
const MILESTONE_PACK := "rookie"
const MILESTONE_PRO_AT := [10, 20]
const BOSS_RUSH_WIN_PACK := "pro"


static func innings_cleared(run: RunState, won: bool) -> int:
	if won:
		return run.inning
	return maxi(0, run.inning - 1) if run.wave < run.waves_per_inning else run.inning


## True for modes whose wins and losses move the win streak (Endless cannot be won: it never counts).
static func counts_for_streak(mode_id: String) -> bool:
	return mode_id != "endless" and mode_id != "practice" and bool(DB.mode(mode_id).get("rewards", true))


## Endless milestones reached with `cleared` innings: [5, 10, ...].
static func milestones_for(cleared: int) -> Array:
	var out: Array = []
	var m := MILESTONE_EVERY
	while m <= cleared:
		out.append(m)
		m += MILESTONE_EVERY
	return out


## {coins, packs} one Endless milestone pays.
static func milestone_reward(innings: int) -> Dictionary:
	var packs: Array = [MILESTONE_PACK]
	if innings in MILESTONE_PRO_AT:
		packs.append("pro")
	return {"coins": MILESTONE_COINS * (innings / MILESTONE_EVERY), "packs": packs}


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
	var overflow_before := Profile.stat("overflow_coins")
	var season_xp_before := Season.xp()
	var season_tier_before := Season.tier()

	var coins := int(round((run.coins_earned * COIN_SHARE + cleared * COINS_PER_INNING + (WIN_COINS if won else 0)) * mult))
	# Daily Challenge bonus (first game of the day: coins + a Rookie Pack; first win: a Pro Pack)
	# is added by DailyChallenge.record_result below and shown separately on the Results screen.
	var xp := maxi(15, int(round((run.outs_total * 2.0 + cleared * 30 + (220 if won else 0)) * mult)))
	Profile.add_coins(coins)

	# Win streak (Update 9): a win pays the bonus the streak had before it, then extends it.
	var streak_bonus := 0.0
	var streak_bonus_coins := 0
	if counts_for_streak(run.mode_id):
		if won:
			streak_bonus = Profile.streak_bonus()
			streak_bonus_coins = int(round(coins * streak_bonus))
		Profile.record_streak(won)
	# First win of the day: the game's coins once more.
	var first_win_today_coins := 0
	if won and Profile.is_first_win_today():
		Profile.data.first_win_day = DailyChallenge.today()
		first_win_today_coins = int(round(coins * (FIRST_WIN_TODAY_MULT - 1.0)))
	Profile.add_coins(streak_bonus_coins + first_win_today_coins)
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
		"ranked":
			if won:
				Profile.add_pack("pro", src)
		"boss_rush":
			if won:
				Profile.add_pack(BOSS_RUSH_WIN_PACK, src)
	# Endless milestones: every 5 innings cleared (run.milestones is the same list, filled live for the HUD).
	var milestones: Array = []
	var milestone_coins := 0
	if run.is_endless():
		milestones = milestones_for(cleared)
		for m in milestones:
			var mr := milestone_reward(int(m))
			milestone_coins += int(mr.coins)
			for p in mr.packs:
				Profile.add_pack(str(p), "Endless milestone: inning %d" % int(m))
		Profile.add_coins(milestone_coins)
		if not milestones.is_empty():
			Profile.bump_stat("endless_milestones", float(milestones.size()))

	# Rank points.
	var rp := 0
	var rp_mult := float(diff.get("rp", 1.0))
	match run.mode_id:
		"standard": rp = int(round((60 if won else cleared * 4) * rp_mult))
		"quick": rp = int(round((22 if won else cleared * 3) * rp_mult))
		"endless": rp = int(round(cleared * 5 * rp_mult))
		"ranked": rp = int(round((30 if won else 0) * rp_mult))
		"boss_rush": rp = int(round((30 if won else cleared * 4) * rp_mult))
	Profile.data.rp = int(Profile.data.rp) + rp
	var promoted := false
	var promotion_reward := {}
	if run.mode_id == "ranked" and won:
		promotion_reward = Profile.promote()
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
	# Rookie Camp (Update 13): a bonus pack for each of the first games, a consolation reward and a coach tip
	# after an early loss, and the Epic pick after the third game (result key "rookie").
	var rookie := Onboarding.on_game_end(run, won)
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
	if run.mode_id == "boss_rush" and won and float(run.stats.get("time", 0.0)) > 0.0:
		var t := float(run.stats.time)
		var best := float(Profile.data.records.get("best_time_boss_rush", 0.0))
		if best <= 0.0 or t < best:
			Profile.data.records["best_time_boss_rush"] = snappedf(t, 0.1)
			records.append("New Boss Rush record: %s!" % time_text(t))
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
	if won and counts_for_streak(run.mode_id):
		Missions.on_event("win_streak", float(Profile.win_streak()))
	# Season XP: every game, a win on top, the day's first Daily Challenge.
	var sx := Season.xp_rules()
	var season_xp := int(sx.get("game", 100)) + (int(sx.get("win", 60)) if won else 0)
	if bool(daily.get("first_today", false)):
		season_xp += int(sx.get("daily", 100))
	var season_tiers := Season.add_xp(season_xp, "game")
	var level_rewards: Array = []
	for l in range(level_before + 1, int(Profile.data.level) + 1):
		level_rewards.append({"level": l, "text": LevelRoad.reward_text(l)})

	var new_achievements: Array = []
	for id in Profile.data.achievements.keys():
		if not unlocked_before.has(id):
			new_achievements.append(id)

	var overflow_coins := int(Profile.stat("overflow_coins") - overflow_before)
	var coins_total := coins + streak_bonus_coins + first_win_today_coins + milestone_coins + (FIRST_WIN_COINS if first_win else 0) \
		+ int(daily.get("bonus_coins", 0)) + int(promotion_reward.get("coins", 0)) + overflow_coins \
		+ int(rookie.get("consolation", {}).get("coins", 0))
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
		# Update 9
		"streak": Profile.win_streak(), "streak_best": int(Profile.data.streak.get("best", 0)), "streak_bonus": streak_bonus,
		"streak_bonus_coins": streak_bonus_coins, "first_win_today_coins": first_win_today_coins,
		"season_xp": season_xp, "season_tiers": season_tiers, "season_xp_before": season_xp_before,
		"season_tier_before": season_tier_before, "season_xp_after": Season.xp(),
		"boons": run.boons.duplicate(), "milestones": milestones, "milestone_coins": milestone_coins,
		"promotion_reward": promotion_reward, "overflow_coins": overflow_coins,
		"best_time": float(Profile.data.records.get("best_time_boss_rush", 0.0)) if run.mode_id == "boss_rush" else 0.0,
		"coins_total": coins_total,
		# Update 13: {"bonus_pack", "consolation" (granted bundle), "coach" ({easier, auto_build, ...}), "epic_pick"}
		"rookie": rookie,
	}
	Profile.add_history({"won": won, "mode": run.mode_id, "difficulty": run.difficulty_id, "arena": run.arena_id,
		"inning": run.inning, "score": run.score, "outs": run.outs_total, "runs": run.runs, "date": result.date})
	Profile.save_now()
	return result


## "6:42"
static func time_text(seconds: float) -> String:
	var s := int(round(seconds))
	return "%d:%02d" % [s / 60, s % 60]


# ---------------------------------------------------------------- reward bundles (Update 9)
# One shape for the Season Pass, the login calendar, the shop gift and promotions:
# {"coins": int, "stars": int, "packs": [pack ids], "pack": id (single, also accepted), "uniform": id}.

## Grants a reward bundle; returns what was actually granted (a uniform already owned becomes stars).
static func grant_bundle(r: Dictionary, source: String) -> Dictionary:
	var got := {}
	var coins := int(r.get("coins", 0))
	var stars := int(r.get("stars", 0))
	var uniform := str(r.get("uniform", ""))
	if uniform != "" and DB.uniforms.has(uniform):
		if uniform in Profile.data.uniforms_owned:
			stars += int(Season.data().get("uniform_owned_stars", 50))
		else:
			Profile.data.uniforms_owned.append(uniform)
			got["uniform"] = uniform
			Profile.notice.emit("New team uniform: %s! Equip it on the Team screen." % str(DB.uniforms[uniform].name))
	if coins > 0:
		Profile.add_coins(coins)
		got["coins"] = coins
	if stars > 0:
		Profile.add_stars(stars)
		got["stars"] = stars
	var packs := bundle_packs(r)
	for p in packs:
		Profile.add_pack(str(p), source)
	if not packs.is_empty():
		got["packs"] = packs
	Profile.changed.emit()
	return got


static func bundle_packs(r: Dictionary) -> Array:
	var packs: Array = []
	for p in r.get("packs", []):
		if DB.packs.has(str(p)):
			packs.append(str(p))
	if DB.packs.has(str(r.get("pack", ""))):
		packs.append(str(r.pack))
	return packs


## "2 Rookie Packs + 250 coins + 10 stars + Opening Day uniform"
static func bundle_text(r: Dictionary) -> String:
	var parts: Array = []
	var uniform := str(r.get("uniform", ""))
	if uniform != "" and DB.uniforms.has(uniform):
		parts.append("%s uniform" % str(DB.uniforms[uniform].name))
	var counts := {}
	var order: Array = []
	for p in bundle_packs(r):
		if not counts.has(p):
			order.append(p)
		counts[p] = int(counts.get(p, 0)) + 1
	for p in order:
		var nm := str(DB.pack(str(p)).get("name", p))
		parts.append(nm if int(counts[p]) == 1 else "%d %ss" % [int(counts[p]), nm])
	if int(r.get("coins", 0)) > 0:
		parts.append("%s coins" % UITheme.format_int(int(r.coins)))
	if int(r.get("stars", 0)) > 0:
		parts.append("%d stars" % int(r.stars))
	return " + ".join(parts)


## The main icon for a reward bundle (UITheme icon names): the biggest thing it gives.
static func bundle_icon(r: Dictionary) -> String:
	if str(r.get("uniform", "")) != "":
		return "special"
	var packs := bundle_packs(r)
	if "champion" in packs or "pro" in packs:
		return "gift"
	if not packs.is_empty():
		return "deck"
	if int(r.get("stars", 0)) > 0:
		return "star"
	return "coin"
