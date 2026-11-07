extends Node
## Automated system tests. Run headless:
##   godot --headless --path . res://tests/test_suite.tscn -- --profile=unittest --fresh-profile
## Exits with code 0 when every check passes.

var checks := 0
var failures := 0
var battle: Battle
const NEW_CARDS := ["called_shot", "line_drive", "tag_at_the_plate", "bullpen_call", "hot_corner", "perfect_game"]
const NEW_CARDS_U7 := ["bean_ball", "around_the_horn", "grand_salami", "rundown", "rain_delay", "intentional_walk", "infield_fly",
	"golden_glove", "the_shift", "momentum", "relief_pitcher", "instant_replay"]
const ROLES := ["damage", "aoe", "control", "defense", "run_stop", "economy", "buff", "boss"]


func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("  FAIL ", what)


func section(name: String) -> void:
	print("== ", name)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _run() -> void:
	test_data()
	test_profile_and_saves()
	test_run_state()
	test_waves()
	test_rewards_and_progression()
	test_packs()
	test_economy()
	test_tools()
	await test_daily_mastery_sets()
	test_missions()
	test_level_road_and_achievements()
	test_update6_waves()
	test_upgrade_all()
	test_deck_ai()
	test_team_ai()
	await test_menus()
	await test_u9_screens()
	test_update5_content()
	test_update7_content()
	test_update9_modes()
	test_update9_models()
	test_update9_cards_content()
	await test_scouting()
	await test_battle_systems()
	await test_u9_e2_screens()
	test_update9_economy()
	print("==== %d checks, %d failed ====" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- data

func test_data() -> void:
	section("data integrity")
	ok(DB.cards.size() == 56, "56 cards defined (%d)" % DB.cards.size())
	for id in NEW_CARDS:
		ok(DB.cards.has(id), "Update 5 card %s defined" % id)
	ok(DB.cards.values().filter(func(c: Dictionary) -> bool: return c.rarity == "legendary").size() >= 3, "at least three Legendary cards")
	for id in DB.card_order:
		var c := DB.card(id)
		ok(c.rarity in DB.RARITY_ORDER, "%s rarity valid" % id)
		ok(c.category in DB.CATEGORY_ORDER, "%s category valid" % id)
		ok(c.target in ["none", "enemy", "area", "path", "defender"], "%s target valid" % id)
		ok(int(c.cost) >= 0 and int(c.cost) <= 10, "%s cost within energy cap" % id)
		ok(DB.card_texture(id) != null, "%s has card art" % id)
		ok(DB.icon(str(c.category)) != null, "%s has a category icon" % id)
		ok(not "{" in DB.card_text(id, 1), "%s text placeholders resolve" % id)
		if c.has("linked"):
			ok(DB.defenders.has(c.linked), "%s linked defender exists" % id)
		for g in c.get("growth", []):
			ok(c.params.has(g), "%s growth param %s exists" % [id, g])
	for id in DB.defender_order:
		var d := DB.defender(id)
		ok(DB.cards.has(d.signature), "%s signature card exists" % id)
		ok(DB.roles.has(d.role), "%s role valid" % id)
		for k in ["damage", "interval", "range", "throw_speed", "accuracy"]:
			ok(float(d.stats[k]) > 0, "%s stat %s positive" % [id, k])
	for fid in DB.formation_order:
		ok(DB.formations[fid].positions.size() == DB.formation_slots.size(), "formation %s has a position per slot" % fid)
	for lid in DB.layouts.keys():
		var lay: Dictionary = DB.layouts[lid]
		for r in lay.routes:
			ok(lay.gates.has(r.gate), "layout %s route %s gate exists" % [lid, r.id])
			var last: Array = r.points[r.points.size() - 1]
			ok(absf(float(last[0]) - Field.HOME.x) < 0.01 and absf(float(last[1]) - Field.HOME.z) < 0.01, "route %s ends at home plate" % r.id)
	for aid in DB.arena_order:
		ok(DB.layouts.has(DB.arena(aid).layout), "arena %s layout exists" % aid)
	for aid in DB.achievement_order:
		ok(int(DB.achievements[aid].goal) > 0, "achievement %s has a goal" % aid)
	for cb in DB.combos:
		for cid in cb.cards:
			ok(DB.cards.has(cid), "combo card %s exists" % cid)
	for uid in DB.upgrade_order:
		ok(not DB.upgrades[uid].effect.is_empty(), "upgrade %s has an effect" % uid)

	# CardView draws icons in _draw(), which only records the texture RID: DB must keep the texture alive.
	var icon_ref := weakref(DB.icon("lock"))
	ok(icon_ref.get_ref() != null, "UI icons stay loaded after the caller drops them")
	var portrait_ref := weakref(DB.portrait("ace"))
	ok(portrait_ref.get_ref() != null, "portraits stay loaded after the caller drops them")


# ---------------------------------------------------------------- saves

func test_profile_and_saves() -> void:
	section("profile & saves")
	Profile.reset_profile()
	ok(Profile.data.deck.size() == Profile.DECK_SIZE, "new profile has an 8-card deck")
	ok(Profile.data.team.size() == Profile.TEAM_SIZE, "new profile has a 6-player team")
	Profile.data.coins = 1234
	Profile.data.cards.splitter.owned = true
	Profile.save_now()
	Profile.data.coins = 1
	Profile.load_profile()
	ok(int(Profile.data.coins) == 1234, "save/load round-trips coins")
	ok(Profile.is_card_owned("splitter"), "save/load round-trips collection")
	ok(Profile.load_status == "ok", "load status ok")
	# Corrupt the main save: the backup must be restored.
	Profile.data.coins = 777
	Profile.save_now()
	Profile.data.coins = 778
	Profile.save_now()  # profile.bak now holds 777
	var f := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	Profile.load_profile()
	ok(Profile.load_status == "restored_backup", "corrupt save restores from backup (%s)" % Profile.load_status)
	ok(int(Profile.data.coins) == 777, "backup contents restored (%d)" % int(Profile.data.coins))
	# Unknown ids and bad sizes are repaired.
	Profile.data.deck = ["not_a_card", "power_throw"]
	Profile.data.team = ["ghost"]
	Profile._sanitize()
	ok(Profile.data.deck.size() == Profile.DECK_SIZE and not "not_a_card" in Profile.data.deck, "sanitize repairs the deck")
	ok(Profile.data.team.size() == Profile.TEAM_SIZE and not "ghost" in Profile.data.team, "sanitize repairs the team")
	# Card upgrades consume copies and coins.
	Profile.data.coins = 1000
	Profile.data.cards.power_throw.copies = 5
	var lvl := Profile.card_level("power_throw")
	ok(Profile.upgrade_card("power_throw"), "card upgrade succeeds with copies + coins")
	ok(Profile.card_level("power_throw") == lvl + 1, "card level increased")
	ok(int(Profile.data.coins) == 1000 - int(DB.COINS_TO_UPGRADE[lvl]), "upgrade charged coins")
	ok(DB.card_param("power_throw", "damage", 2) > DB.card_param("power_throw", "damage", 1), "card level raises card power")
	# Gear and traits feed defender stats.
	var before := float(Profile.defender_mods("jax").damage)
	Profile.data.coins = 5000
	ok(Profile.buy_gear("iron_wristband"), "gear purchase")
	Profile.equip_gear("jax", "iron_wristband")
	ok(float(Profile.defender_mods("jax").damage) > before, "gear increases defender damage")
	Profile.add_defender_xp("jax", 700)
	ok(Profile.defender_level("jax") >= 3, "defender XP levels up (lv %d)" % Profile.defender_level("jax"))
	Profile.choose_trait("jax", 3, "power")
	ok(float(Profile.defender_mods("jax").damage) > before + 0.1, "trait adds damage")
	# Unlocks by account level.
	ok(not Profile.is_defender_unlocked("nova"), "nova locked at start")
	Profile.add_xp(5000)
	ok(Profile.is_defender_unlocked("nova"), "nova unlocks at account level 4 (level %d)" % int(Profile.data.level))
	ok(Profile.data.packs.any(func(pk: Dictionary) -> bool: return pk.type == "signature" and pk.get("card", "") == "thunderbolt"),
		"unlocking nova brings a Signature Pack with her card")
	ok("neon_diamond" in Profile.data.arenas_unlocked, "neon diamond unlocks at level 3")
	# Achievements award stars once.
	var stars := int(Profile.data.stars)
	Profile.bump_stat("total_outs", 1)
	ok(Profile.data.achievements.has("first_out"), "first_out achievement unlocks")
	ok(int(Profile.data.stars) == stars + int(DB.achievements.first_out.stars), "achievement awards stars")
	Profile.bump_stat("total_outs", 1)
	ok(int(Profile.data.stars) == stars + int(DB.achievements.first_out.stars), "achievement not double-awarded")


# ---------------------------------------------------------------- run state

func test_run_state() -> void:
	section("run state")
	var cfg := Session.new_run_config("standard")
	cfg.seed = 4242
	var r := RunState.create(cfg)
	ok(r.max_innings == 9 and r.waves_per_inning == 3, "standard is 9 innings x 3 waves")
	ok(r.run_limit == 3, "standard run limit is 3")
	ok(r.boss_for_inning(3) == "iron_slugger" and r.boss_for_inning(9) == "grand_slammer", "standard bosses scheduled")
	r.inning = 4
	r.wave = 0
	r.coins = 99
	r.upgrades = {"stronger_arm": 2}
	r.deck.append("splitter")
	r.temp_cards.append("splitter")
	r.rng.randi()
	var d := r.to_dict()
	var json := JSON.stringify(d)
	var back := RunState.from_dict(JSON.parse_string(json))
	ok(back.inning == 4 and back.coins == 99, "run state round-trips through JSON")
	ok(back.upgrade_level("stronger_arm") == 2, "upgrades round-trip")
	ok("splitter" in back.deck, "temporary cards round-trip")
	ok(back.rng.state == r.rng.state, "rng state round-trips exactly")
	var per_level := float(DB.upgrades.stronger_arm.effect.damage)
	ok(is_equal_approx(back.modifier_total("damage"), 2.0 * per_level), "upgrade modifiers aggregate (%.2f)" % back.modifier_total("damage"))
	var e := RunState.create(Session.new_run_config("endless"))
	ok(e.is_endless() and e.boss_for_inning(3) != "" and e.boss_for_inning(4) == "", "endless bosses every 3rd inning")
	var p := RunState.create(Session.new_run_config("practice"))
	ok(p.is_practice() and p.run_limit > 100, "practice cannot be lost")


# ---------------------------------------------------------------- waves

func test_waves() -> void:
	section("wave generation")
	var cfg := Session.new_run_config("standard")
	cfg.seed = 7
	var r := RunState.create(cfg)
	var a := WaveGenerator.generate(r, 1, 4)
	var b := WaveGenerator.generate(r, 1, 4)
	ok(str(a) == str(b), "waves are deterministic per seed")
	var totals: Array[float] = []
	for inning in range(1, 10):
		r.inning = inning
		var cost := 0.0
		for w in 3:
			var info := WaveGenerator.generate(r, w, 4)
			ok(int(info.total) > 0, "inning %d wave %d has runners" % [inning, w + 1])
			for g in info.groups:
				ok(DB.enemies.has(g.enemy), "wave enemy %s exists" % g.enemy)
				ok(int(g.route) >= 0, "route index valid")
				cost += float(DB.enemy(g.enemy).get("cost", 0)) * int(g.count)
			if w == 2:
				var boss := r.boss_for_inning(inning)
				ok(info.boss == boss, "inning %d final wave boss = '%s'" % [inning, boss])
		totals.append(cost)
	ok(totals[8] > totals[0] * 2.0, "late innings are much bigger (%.0f vs %.0f)" % [totals[8], totals[0]])
	r.inning = 5
	ok(WaveGenerator.hp_multiplier(r) > 1.3, "enemy health scales with innings")
	var vet_cfg := cfg.duplicate()
	vet_cfg.difficulty = "veteran"
	var v := RunState.create(vet_cfg)
	v.inning = 5
	ok(WaveGenerator.hp_multiplier(v) > WaveGenerator.hp_multiplier(r), "veteran runners are tougher")


# ---------------------------------------------------------------- rewards

func test_rewards_and_progression() -> void:
	section("rewards & ranks")
	var cfg := Session.new_run_config("standard")
	cfg.seed = 99
	var r := RunState.create(cfg)
	r.inning = 9
	r.wave = 3
	r.outs_total = 300
	r.coins_earned = 900
	var coins := int(Profile.data.coins)
	var rp := int(Profile.data.rp)
	var wins := Profile.stat("wins_standard")
	var res := Rewards.apply(r, true)
	ok(int(Profile.data.coins) >= coins + int(res.coins) and int(res.coins) > 0, "victory awards coins (%d, plus level-up bonuses)" % int(res.coins))
	ok(int(res.xp) > 200, "victory awards XP (%d)" % int(res.xp))
	ok(res.packs.size() >= 2, "standard victory awards packs (%d)" % res.packs.size())
	ok(res.packs.any(func(pk: Dictionary) -> bool: return pk.type == "pro"), "standard victory includes a Pro Pack")
	ok(Profile.pack_count() >= res.packs.size(), "earned packs wait unopened in the inventory")
	ok(int(Profile.data.rp) == rp + int(res.rp) and int(res.rp) > 0, "victory awards rank points")
	ok(Profile.stat("wins_standard") == wins + 1, "win recorded")
	ok("iron_fortress" in Profile.data.arenas_unlocked, "standard win unlocks Iron Fortress")
	ok(Profile.data.history.size() > 0 and Profile.data.history[0].won, "history entry recorded")
	Profile.data.rp = 5000
	var div := int(Profile.data.division)
	ok(Profile.promotion_available(), "promotion available with enough RP")
	var rr := RunState.create(Session.new_run_config("ranked"))
	rr.inning = 3
	Rewards.apply(rr, true)
	ok(int(Profile.data.division) == div + 1, "winning the promotion challenge promotes")


# ---------------------------------------------------------------- economy (Update 5)

func test_economy() -> void:
	section("economy tuning")
	# Shop prices (round numbers) and rarer Epic/Legendary pulls.
	ok(int(DB.pack("rookie").price_coins) == 200 and int(DB.pack("pro").price_coins) == 500 and int(DB.pack("champion").price_stars) == 50,
		"pack prices: Rookie 200, Pro 500 coins, Champion 50 stars")
	ok(int(Profile.pack_price("pro", Profile.BUNDLE_SIZE).coins) == 4500 and int(Profile.pack_price("champion", Profile.BUNDLE_SIZE).stars) == 450,
		"bundles: 10 Pro Packs 4,500 coins, 10 Champion Packs 450 stars")
	for t in ["rookie", "pro", "champion"]:
		var w: Dictionary = DB.pack(t).weights
		var total := 0.0
		for r in w.values():
			total += float(r)
		ok(float(w.legendary) / total < 0.015, "%s packs: Legendary is the long tail (%.2f %% per slot)" % [t, 100.0 * float(w.legendary) / total])
	ok(DB.pack("champion").slots[-1].get("min", "") == "epic", "Champion Packs still guarantee an Epic")
	# Defender level road: slower curve, same rewards.
	ok(int(DB.defender_xp_curve[DB.defender_xp_curve.size() - 1]) == 10200, "defender level 10 needs 10,200 XP")
	ok(str(DB.defender_level_rewards["10"].get("pack", "")) == "champion", "defender level 10 still gives a Champion Pack")
	# Rewards for a won Quick Defense game (Standard, Steel Yard): coins, defender XP and one pack.
	var level0 := int(Profile.data.level)
	var cfg := Session.new_run_config("quick")
	cfg.difficulty = "standard"
	cfg.arena = "steel_yard"
	var r := RunState.create(cfg)
	r.inning = 3
	r.wave = 3
	r.coins_earned = 720
	r.outs_total = 160
	r.stats.outs_by = {r.team[0]: 40}
	var res := Rewards.apply(r, true)
	ok(int(res.coins) == 268, "Quick win coins = (720 x 0.525 + 3 x 22.5 + 150) x 0.45 = 268 (%d)" % int(res.coins))
	ok(int(res.xp) == 284, "Quick win XP = (160 x 2 + 3 x 30 + 220) x 0.45 = 284 (%d)" % int(res.xp))
	var game_packs: Array = res.packs.filter(func(pk: Dictionary) -> bool: return str(pk.source).begins_with("Quick Defense"))
	ok(game_packs.size() == 1 and game_packs[0].type == "rookie", "a Quick Defense game gives one Rookie Pack (%d)" % game_packs.size())
	var mvp_xp := int(res.defender_xp[r.team[0]].xp)
	ok(mvp_xp == int(round((284 * Rewards.DEFENDER_XP_SHARE + 40 * Rewards.DEFENDER_XP_PER_OUT) * 1.5)), "MVP defender XP = (XP x 0.3 + outs) x 1.5 (%d)" % mvp_xp)
	ok(int(res.defender_xp[r.team[1]].xp) == int(round(284 * Rewards.DEFENDER_XP_SHARE)), "other defenders get 30 % of the XP")
	# A won Standard Siege: one Rookie Pack plus a Pro Pack; a loss: only the Rookie Pack.
	var cfg2 := Session.new_run_config("standard")
	cfg2.difficulty = "standard"
	cfg2.arena = "steel_yard"
	var s2 := RunState.create(cfg2)
	s2.inning = 9
	s2.wave = 3
	var res2 := Rewards.apply(s2, true)
	var types: Array = res2.packs.filter(func(pk: Dictionary) -> bool: return str(pk.source).begins_with("Standard Siege")).map(func(pk: Dictionary) -> String: return pk.type)
	ok(types.size() == 2 and "rookie" in types and "pro" in types, "a Standard Siege win gives a Rookie and a Pro Pack (%s)" % [types])
	var s3 := RunState.create(cfg2)
	s3.inning = 7
	s3.wave = 1
	var res3 := Rewards.apply(s3, false)
	var types3: Array = res3.packs.filter(func(pk: Dictionary) -> bool: return str(pk.source).begins_with("Standard Siege"))
	ok(types3.size() == 1, "a lost Standard Siege gives one Rookie Pack (%d)" % types3.size())
	ok(int(Profile.data.level) >= level0, "account level never drops")


# ---------------------------------------------------------------- battle

func test_packs() -> void:
	section("card packs")
	Profile.reset_profile()
	ok(Profile.pack_count() == 0, "fresh profile starts with no unopened packs")
	var owned_before := Profile.stat("cards_owned")
	for type in ["rookie", "pro", "champion"]:
		Profile.add_pack(type, "test")
		var idx: int = Profile.data.packs.size() - 1
		var res := Profile.open_pack(idx)
		var pd := DB.pack(type)
		ok(res.cards.size() == int(pd.cards), "%s opens %d cards" % [type, int(pd.cards)])
		var best := 0
		var ids := {}
		for c in res.cards:
			best = maxi(best, DB.rarity_index(c.rarity))
			ids[c.id] = true
			ok(Profile.is_card_owned(c.id), "%s: %s is now owned" % [type, c.id])
		var slots: Array = pd.slots
		var need := DB.rarity_index(str(slots[slots.size() - 1].get("min", "common")))
		ok(best >= need, "%s guarantees %s or better" % [type, str(slots[slots.size() - 1].get("min", "common"))])
		ok(ids.size() == res.cards.size(), "%s has no repeats inside one pack" % type)
	ok(Profile.pack_count() == 0, "opened packs leave the inventory")
	ok(Profile.stat("cards_owned") >= owned_before, "collection grew")
	# Duplicates become upgrade copies.
	var cid: String = Profile.STARTER_CARDS[0]
	var copies := Profile.card_copies(cid)
	Profile.grant_card(cid, 2)
	ok(Profile.card_copies(cid) == copies + 2, "duplicate cards add upgrade copies")
	# Shop.
	Profile.data.coins = 1000
	Profile.data.stars = 0
	ok(Profile.buy_pack("rookie") and Profile.pack_count("rookie") == 1, "buying a Rookie Pack adds it to the inventory")
	ok(int(Profile.data.coins) == 1000 - int(DB.pack("rookie").price_coins), "the shop charges the pack price")
	ok(not Profile.buy_pack("champion"), "Champion Packs need stars")
	ok(not Profile.buy_pack("signature"), "Signature Packs are not for sale")
	test_pack_bundles()
	# Level-ups and new defenders give packs.
	var n := Profile.pack_count()
	var next_lv := int(Profile.data.level) + 1
	Profile.add_xp(Profile.xp_to_next(int(Profile.data.level)))
	ok(Profile.pack_count() >= n + 1 and Profile.pack_count() == n + LevelRoad.reward(next_lv).packs.size(), "levelling up awards the level road packs")
	var sig_def := ""
	for id in DB.defender_order:
		if not Profile.is_defender_unlocked(id) and str(DB.defender(id).get("signature", "")) != "":
			sig_def = id
			break
	if sig_def != "":
		var sig: String = DB.defender(sig_def).signature
		Profile.data.cards[sig].owned = false   # packs opened above may have rolled it already
		Profile.unlock_defender(sig_def)
		var has_sig: bool = Profile.data.packs.any(func(pk: Dictionary) -> bool: return pk.type == "signature" and pk.get("card", "") == sig)
		ok(has_sig and not Profile.is_card_owned(sig), "a new defender brings a Signature Pack")
		for i in Profile.data.packs.size():
			if Profile.data.packs[i].type == "signature":
				var res := Profile.open_pack(i)
				ok(res.cards.size() == 1 and res.cards[0].id == sig and Profile.is_card_owned(sig), "the Signature Pack contains the signature card")
				break
	# Defender level road: coins, packs and trait choices.
	var coins0 := int(Profile.data.coins)
	var packs0 := Profile.pack_count()
	Profile.add_defender_xp("ace", 2100)
	ok(Profile.defender_level("ace") >= 5, "defender XP raises the level (%d)" % Profile.defender_level("ace"))
	ok(int(Profile.data.coins) >= coins0 + 100 + 250, "level road coin rewards are paid")
	ok(Profile.data.packs.any(func(pk: Dictionary) -> bool: return pk.type == "rookie" and str(pk.source).begins_with("Ace reached level 4")), "level 4 gives a Rookie Pack")
	ok(Profile.pack_count() >= packs0 + 1, "level rewards add packs")
	ok(Profile.pending_traits("ace") == 1, "level 3 unlocks a trait to choose")
	Profile.choose_trait("ace", 3, "power")
	ok(Profile.pending_traits("ace") == 0, "choosing the trait clears the reminder")
	# Save round trip keeps unopened packs.
	Profile.add_pack("pro", "test")
	Profile.save_now()
	var count := Profile.pack_count()
	Profile.load_profile()
	ok(Profile.pack_count() == count, "unopened packs survive save and load")
	Profile.reset_profile()


## Shop bundles of 10 and opening 5 / 10 packs at once.
func test_pack_bundles() -> void:
	section("pack bundles and multi-open")
	var n := Profile.BUNDLE_SIZE
	var packs0 := Profile.pack_count()
	for type in ["rookie", "pro", "champion"]:
		var single := Profile.pack_price(type)
		var bundle := Profile.pack_price(type, n)
		var key := "stars" if int(single.stars) > 0 else "coins"
		ok(int(bundle[key]) < int(single[key]) * n, "%s bundle is cheaper than %d singles (%d vs %d)" % [type, n, int(bundle[key]), int(single[key]) * n])
		ok(int(bundle[key]) == RunState.round_price(int(single[key]) * n * Profile.BUNDLE_DISCOUNT), "%s bundle price is the rounded discount" % type)
	ok(int(Profile.pack_price("rookie", n).coins) == 1800, "10 Rookie Packs cost 1,800 coins (%d)" % int(Profile.pack_price("rookie", n).coins))
	ok(int(Profile.pack_price("rookie", 3).coins) == 600, "other counts are not discounted")
	# Refused when short, without touching the wallet or the inventory.
	var price := int(Profile.pack_price("rookie", n).coins)
	Profile.data.coins = price - 1
	ok(not Profile.can_buy_pack("rookie", n), "a bundle needs its full price")
	ok(not Profile.buy_pack("rookie", n), "buying a bundle without enough coins fails")
	ok(int(Profile.data.coins) == price - 1 and Profile.pack_count() == packs0, "a refused bundle charges nothing and adds no packs")
	ok(not Profile.buy_pack("signature", n), "Signature Packs are not sold in bundles")
	Profile.data.stars = 0
	ok(not Profile.buy_pack("champion", n), "a Champion bundle needs stars")
	# Buying a bundle.
	Profile.data.coins = price + 7
	var bought0 := Profile.stat("packs_bought")
	var rookies0 := Profile.pack_count("rookie")
	ok(Profile.buy_pack("rookie", n), "buying 10 Rookie Packs succeeds")
	ok(int(Profile.data.coins) == 7, "the bundle price is deducted (%d left)" % int(Profile.data.coins))
	ok(Profile.pack_count("rookie") == rookies0 + n, "the bundle adds 10 Rookie Packs")
	ok(Profile.stat("packs_bought") == bought0 + n, "the bundle counts 10 packs bought")
	Profile.data.stars = int(Profile.pack_price("champion", n).stars)
	ok(Profile.buy_pack("champion", n) and int(Profile.data.stars) == 0 and Profile.pack_count("champion") >= n, "a Champion bundle is paid in stars")
	# Opening 10 at once.
	var opened0 := int(Profile.data.packs_opened)
	var rookies := Profile.pack_count("rookie")
	Profile._save_queued = false
	var res := Profile.open_packs("rookie", n)
	ok(int(res.get("packs", 0)) == n and res.get("cards", []).size() == n * int(DB.pack("rookie").cards), "opening 10 Rookie Packs gives 30 cards (%d)" % res.get("cards", []).size())
	ok(Profile.pack_count("rookie") == rookies - n, "opening 10 consumes 10 packs")
	ok(int(Profile.data.packs_opened) == opened0 + n, "every pack counts as opened")
	ok(Profile._save_queued, "a multi-open saves the profile")
	var all_owned := true
	var new_seen := {}
	var flags_ok := true
	for c in res.get("cards", []):
		all_owned = all_owned and Profile.is_card_owned(c.id)
		if c.new:
			flags_ok = flags_ok and not new_seen.has(c.id) and int(c.copies) == 0
			new_seen[c.id] = true
		else:
			flags_ok = flags_ok and int(c.copies) > 0
	ok(all_owned, "every multi-open card is in the collection")
	ok(flags_ok, "a card is NEW at most once per multi-open; repeats become copies")
	# Each pack keeps its own guarantees: 10 Champion Packs hold at least 10 Epic+ cards.
	var champs := Profile.pack_count("champion")
	var cres := Profile.open_packs("champion", n)
	var epics := 0
	for c in cres.get("cards", []):
		if DB.rarity_index(c.rarity) >= DB.rarity_index("epic"):
			epics += 1
	ok(cres.get("cards", []).size() == n * int(DB.pack("champion").cards) and epics >= n, "10 Champion Packs keep a guaranteed Epic each (%d)" % epics)
	ok(Profile.pack_count("champion") == champs - n, "10 Champion Packs consumed")
	# Opening more than owned does nothing.
	Profile.add_pack("pro", "test")
	Profile.add_pack("pro", "test")
	var pros := Profile.pack_count("pro")
	ok(Profile.open_packs("pro", 5).is_empty() and Profile.pack_count("pro") == pros, "opening 5 with fewer owned opens nothing")
	var five := Profile.open_packs("pro", 2)
	ok(five.get("cards", []).size() == 2 * int(DB.pack("pro").cards) and Profile.pack_count("pro") == pros - 2, "opening a smaller batch works")
	# Saved like single opens.
	Profile.save_now()
	var opened := int(Profile.data.packs_opened)
	var owned_id: String = res.cards[0].id
	Profile.load_profile()
	ok(int(Profile.data.packs_opened) == opened and Profile.is_card_owned(owned_id), "multi-open results survive save and load")


# ---------------------------------------------------------------- daily, mastery, sets (Update 5)

func test_daily_mastery_sets() -> void:
	section("daily challenge, mastery, collection sets")
	Profile.reset_profile()
	# Seeding: the same date gives the same rules, other dates differ.
	var day0 := "2026-10-27"
	var a := DailyChallenge.rules_for(day0)
	ok(str(a) == str(DailyChallenge.rules_for(day0)), "same date gives the same daily rules")
	var differ := 0
	var arenas := {}
	var mods := {}
	var formats := {}
	var diffs := {}
	for i in range(1, 41):
		var r := DailyChallenge.rules_for(DailyChallenge.shift_date(day0, i))
		if str(r) != str(a):
			differ += 1
		arenas[r.arena] = true
		mods[r.modifier] = true
		formats[r.format] = true
		diffs[r.difficulty] = true
	ok(differ == 40, "every other date gives different rules (%d of 40)" % differ)
	ok(arenas.size() >= 4 and mods.size() >= 8 and formats.size() == 2 and diffs.size() >= 2,
		"daily rules vary (%d stadiums, %d modifiers, %d formats, %d difficulties)" % [arenas.size(), mods.size(), formats.size(), diffs.size()])
	ok(DailyChallenge.shift_date("2026-12-31", 1) == "2027-01-01" and DailyChallenge.days_between("2026-02-28", "2026-03-01") == 1, "date arithmetic crosses months and years")
	var unique := {}
	var deck_ok: bool = a.deck.size() == Profile.DECK_SIZE
	for cid in a.deck:
		unique[cid] = true
		deck_ok = deck_ok and DB.cards.has(cid) and str(DB.card(cid).get("linked", "")) == ""
	ok(deck_ok and unique.size() == Profile.DECK_SIZE, "daily deck has 8 different non-signature cards %s" % [a.deck])
	ok(DB.difficulties.has(a.difficulty) and DB.arenas.has(a.arena) and not DailyChallenge.modifier_def(a.modifier).is_empty(), "daily rules use valid ids")
	ok(DailyChallenge.countdown_text(3725) == "1h 02m" and DailyChallenge.seconds_to_next() <= 86400, "countdown to the next challenge")
	# Config and run state.
	DailyChallenge.date_override = day0
	var cfg := Session.new_run_config("daily")
	ok(cfg.get("daily", "") == day0 and cfg.deck == a.deck and int(cfg.seed) == int(a.seed) and cfg.arena == a.arena, "daily config carries the day's rules")
	var run := RunState.create(cfg)
	ok(run.is_daily() and run.max_innings == int(a.innings) and DailyChallenge.is_daily_mode(run.mode_id), "daily run has %d innings" % run.max_innings)
	ok(run.card_level(a.deck[0]) == int(a.card_level), "daily cards play at level %d" % int(a.card_level))
	var bosses_ok := true
	for k in a.bosses.keys():
		bosses_ok = bosses_ok and run.boss_for_inning(int(k)) == str(a.bosses[k])
	ok(bosses_ok and run.boss_for_inning(1) == "", "daily bosses come from the rules %s" % [a.bosses])
	# Daily-only modifiers work through the shared modifier code.
	var found := {}
	for i in 400:
		var r := DailyChallenge.rules_for(DailyChallenge.shift_date(day0, i))
		if r.modifier in ["power_surge", "bare_plate"] and not found.has(r.modifier):
			found[r.modifier] = r.date
	ok(found.size() == 2, "daily-only modifiers get picked (%s)" % [found])
	if found.has("power_surge"):
		var ps := RunState.create(DailyChallenge.config_for(found.power_surge))
		ok(ps.modifier_total("energy_regen") >= 1.0, "Power Surge doubles energy regeneration")
	if found.has("bare_plate"):
		var bp := RunState.create(DailyChallenge.config_for(found.bare_plate))
		ok(bp.shields == 0 and int(DB.difficulty(bp.difficulty_id).shields) > 0, "Bare Plate removes the base shields")
	DailyChallenge.set_active(true)
	ok(DB.endless_modifiers.has("power_surge"), "daily modifiers are listed while a daily game runs")
	DailyChallenge.set_active(false)
	ok(not DB.endless_modifiers.has("power_surge") and DB.endless_modifiers.has("speed_demons"), "daily modifiers never leak into Endless")
	# The Continue Run slot is untouched.
	Profile.data.current_run = {"config": {"mode": "standard"}, "inning": 4, "mode_id": "standard"}
	Profile.store_run(run.to_dict())
	ok(int(Profile.data.current_run.inning) == 4, "a daily game never replaces the saved run")
	# Streak, best score and the once-per-day bonus.
	var packs0 := Profile.pack_count()
	var coins0 := int(Profile.data.coins)
	run.score = 3000
	var r1 := DailyChallenge.record_result(run, false)
	ok(r1.first_today and int(r1.streak) == 1 and int(r1.best) == 3000, "first daily game starts a streak (%d)" % int(r1.streak))
	ok(Profile.pack_count() == packs0 + 1 and int(Profile.data.coins) == coins0 + int(r1.bonus_coins) and int(r1.bonus_coins) > 0, "first game of the day gives coins and a pack")
	run.score = 2000
	var r2 := DailyChallenge.record_result(run, false)
	ok(not r2.first_today and int(r2.best) == 3000 and not r2.new_best and Profile.pack_count() == packs0 + 1, "a second attempt keeps the best score and gives no bonus")
	run.score = 5000
	var r3 := DailyChallenge.record_result(run, true)
	ok(r3.new_best and int(r3.best) == 5000 and Profile.pack_count() == packs0 + 2 and "pro" in r3.bonus_packs, "first win of the day gives a Pro Pack (%s)" % [r3.bonus_packs])
	DailyChallenge.record_result(run, true)
	ok(Profile.pack_count() == packs0 + 2 and int(DailyChallenge.day_record(day0).attempts) == 4, "the win bonus is given once per day")
	var next := RunState.create(DailyChallenge.config_for(DailyChallenge.shift_date(day0, 1)))
	ok(int(DailyChallenge.record_result(next, false).streak) == 2, "playing the next day extends the streak")
	var gap := RunState.create(DailyChallenge.config_for(DailyChallenge.shift_date(day0, 3)))
	var rg := DailyChallenge.record_result(gap, false)
	ok(int(rg.streak) == 1 and int(rg.best_streak) == 2, "missing a day resets the streak (best stays 2)")
	DailyChallenge.date_override = DailyChallenge.shift_date(day0, 4)
	ok(DailyChallenge.current_streak() == 1, "streak still alive the day after")
	DailyChallenge.date_override = DailyChallenge.shift_date(day0, 6)
	ok(DailyChallenge.current_streak() == 0, "streak shows 0 after a missed day")
	DailyChallenge.date_override = day0
	# Mastery thresholds.
	ok(CardMastery.stars_for(0) == 0 and CardMastery.stars_for(9) == 0 and CardMastery.stars_for(10) == 1 and CardMastery.stars_for(39) == 1
		and CardMastery.stars_for(40) == 2 and CardMastery.stars_for(119) == 2 and CardMastery.stars_for(120) == 3 and CardMastery.stars_for(999) == 3,
		"mastery stars at 10 / 40 / 120 plays")
	ok(CardMastery.next_threshold(10) == 40 and CardMastery.next_threshold(120) == 0 and is_equal_approx(CardMastery.progress(25), 0.5), "mastery progress to the next star")
	# A daily game through Rewards: mastery from card casts, daily record in the result.
	Profile.data.cards.power_throw.plays = 8
	var dr := RunState.create(DailyChallenge.config_for(DailyChallenge.shift_date(day0, 10)))
	dr.score = 4100
	dr.inning = 2
	dr.stats["card_casts"] = {"power_throw": 3, "curveball": 1}
	var res := Rewards.apply(dr, false)
	ok(Profile.card_plays("power_throw") == 11 and CardMastery.stars("power_throw") == 1, "card casts add mastery (%d plays)" % Profile.card_plays("power_throw"))
	var m0: Dictionary = res.mastery[0] if not res.mastery.is_empty() else {}
	ok(res.mastery.size() == 2 and m0.get("id", "") == "power_throw" and int(m0.stars_after) == 1 and int(m0.stars_before) == 0, "the result lists mastery gains, star earners first")
	ok(not res.daily.is_empty() and int(res.daily.score) == 4100 and res.daily.first_today, "the result carries the daily record")
	ok(Profile.data.history[0].mode == dr.mode_id and int(res.rp) == 0, "daily games are in the history and give no rank points")
	var prac := RunState.create(Session.new_run_config("quick"))
	prac.stats["card_casts"] = {}
	ok(Rewards.apply(prac, false).daily.is_empty(), "other modes have no daily record")
	# Collection sets: once-only rewards.
	ok(not CollectionSets.can_claim("offense") and CollectionSets.claim("offense") == "", "an incomplete set cannot be claimed")
	var off := CollectionSets.cards_in("offense")
	ok(off.size() > 0 and int(CollectionSets.progress("offense").total) == off.size(), "offense set lists %d cards" % off.size())
	for cid in off:
		Profile.grant_card(cid)
	ok(CollectionSets.is_complete("offense") and CollectionSets.can_claim("offense"), "owning every offense card completes the set")
	var pk0 := Profile.pack_count("pro")
	ok(CollectionSets.claim("offense") == "pro" and Profile.pack_count("pro") == pk0 + 1, "claiming the set gives a Pro Pack")
	ok(CollectionSets.claim("offense") == "" and Profile.pack_count("pro") == pk0 + 1 and not CollectionSets.can_claim("offense"), "a set reward is given only once")
	Profile.save_now()
	Profile.load_profile()
	ok(CollectionSets.is_claimed("offense") and not CollectionSets.can_claim("offense"), "claimed sets survive save and load")
	for cid in DB.card_order:
		Profile.grant_card(cid)
	ok(CollectionSets.reward_pack("all") == "champion" and CollectionSets.claim("all") == "champion", "the full collection gives a Champion Pack")
	# Save migration: a save written before this update (no daily, sets or plays) loads cleanly.
	var old := Profile.default_profile()
	old.erase("daily")
	old.erase("sets_claimed")
	for cid in old.cards.keys():
		old.cards[cid].erase("plays")
	old.coins = 4321
	var f := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	ok(Profile.load_status == "ok" and int(Profile.data.coins) == 4321, "an old save loads (%s)" % Profile.load_status)
	ok(int(Profile.data.daily.streak) == 0 and typeof(Profile.data.daily.days) == TYPE_DICTIONARY and Profile.data.sets_claimed.is_empty(), "old saves get empty daily records and sets")
	ok(Profile.card_plays("power_throw") == 0 and CardMastery.stars("power_throw") == 0, "old saves start mastery at zero")
	ok(DailyChallenge.current_streak() == 0 and not DailyChallenge.played(), "old saves have no daily games yet")
	# Mangled daily data is repaired.
	Profile.data.daily = {"streak": "3", "days": [1, 2]}
	Profile.data.sets_claimed = {"bogus": "x"}
	Profile._merge(Profile.data, {})
	var d0: Dictionary = Profile.default_profile()
	Profile._merge(d0, {"daily": {"streak": 2.0, "last_date": "2026-10-26", "days": {"2026-10-26": {"best": 10.0}, "bad": 5}}, "sets_claimed": {"bogus": "x"}, "version": 1})
	Profile.data = d0
	Profile._sanitize()
	ok(int(Profile.data.daily.streak) == 2 and Profile.data.daily.days.size() == 1 and not Profile.data.sets_claimed.has("bogus"), "sanitize repairs daily records and set claims")
	# The Results screen shows the daily tile and mastery moments.
	var rs: Control = load("res://src/ui/results_screen.gd").new()
	rs.result = {"won": true, "mode": "daily", "difficulty": "veteran", "arena": "steel_yard", "coins": 80, "xp": 150, "rp": 0,
		"levels": 0, "innings_cleared": 3, "outs": 40, "runs": 1, "run_limit": 3, "score": 5200, "mvp": "ace", "defender_xp": {}, "packs": [],
		"stats": {"cards_played": 6}, "daily": {"date": day0, "score": 5200, "best": 5200, "new_best": true, "streak": 3, "best_streak": 3,
			"first_today": true, "bonus_coins": 150, "bonus_packs": ["rookie", "pro"], "attempts": 1},
		"mastery": [{"id": "power_throw", "plays": 3, "before": 8, "after": 11, "stars_before": 0, "stars_after": 1}]}
	add_child(rs)
	await get_tree().process_frame
	var texts := []
	for l in rs.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	ok("DAILY CHALLENGE" in texts and "DAY STREAK" in texts and "CARD MASTERY" in texts, "results shows the daily record and card mastery")
	ok(_find_text(rs, "RETRY DAILY"), "results offers RETRY DAILY")
	rs.queue_free()
	# Cards & Deck shows the set progress strip; Card Upgrades shows mastery.
	Session.menu_tab = "deck"
	var dbs: Control = load("res://src/ui/deck_builder.gd").new()
	add_child(dbs)
	await get_tree().process_frame
	ok(dbs.find_children("Set_offense", "", true, false).size() == 1 and dbs.find_children("Set_all", "", true, false).size() == 1, "Cards & Deck shows set progress tiles")
	dbs.queue_free()
	DailyChallenge.date_override = ""
	Profile.reset_profile()
	await get_tree().process_frame


# ---------------------------------------------------------------- missions (Update 6)

func _mission(id: String, event: String, goal: int, tier := 1, is_max := false) -> Dictionary:
	return {"id": id, "kind": "daily", "event": event, "goal": goal, "progress": 0, "claimed": false, "max": is_max, "tier": tier}


func test_missions() -> void:
	section("missions")
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-10-28"   # a Wednesday
	Missions.refresh()
	var s := Missions.state()
	ok(s.daily.size() == 3, "three daily missions (%d)" % s.daily.size())
	ok(s.daily.map(func(m: Dictionary) -> int: return int(m.tier)) == [1, 2, 3], "one daily mission per tier")
	ok(s.weekly.size() == 1, "one weekly mission")
	ok(Missions.starter_active() and int(s.starter.get("step", -1)) == 0, "a new profile starts the Learn the ropes chain")
	for m in Missions.active():
		ok(Missions.text(m) != "" and not "{" in Missions.text(m), "mission text resolves: %s" % Missions.text(m))
		ok(not Missions.reward(m).is_empty() and Missions.reward_text(Missions.reward(m)) != "", "mission %s has a reward" % m.id)
	# Deterministic per day.
	var g1 := Missions.generate_daily("2026-10-28")
	ok(str(g1) == str(Missions.generate_daily("2026-10-28")), "the same day rolls the same missions")
	ok(str(g1.map(func(m: Dictionary) -> String: return m.id)) == str(s.daily.map(func(m: Dictionary) -> String: return m.id)), "today's missions are the day's roll")
	var differ := 0
	for i in range(1, 11):
		if str(Missions.generate_daily(DailyChallenge.shift_date("2026-10-28", i))) != str(g1):
			differ += 1
	ok(differ >= 8, "other days roll other missions (%d of 10)" % differ)
	ok(Missions.week_of("2026-10-28") == "2026-10-26" and Missions.week_of("2026-11-01") == "2026-10-26" and Missions.week_of("2026-11-02") == "2026-11-02",
		"weeks start on Monday")
	# Every pool entry resolves (defender, difficulty placeholders).
	for def in Missions.data().daily:
		var inst := Missions._instance(def, RandomNumberGenerator.new(), "daily")
		ok(not "{" in str(inst.event) and int(inst.goal) >= 1, "mission %s resolves (%s, goal %d)" % [def.id, inst.event, int(inst.goal)])
	# Progress from live stats; claim once.
	s.daily[0] = _mission("outs", "total_outs", 5)
	Profile.bump_stat("total_outs", 3)
	ok(int(s.daily[0].progress) == 3 and not Missions.can_claim(s.daily[0]), "outs count towards the mission (3 / 5)")
	Profile.bump_stat("total_outs", 4)
	ok(int(s.daily[0].progress) == 5 and Missions.can_claim(s.daily[0]), "mission completes and caps at its goal")
	ok((s.fresh as Array).any(func(f: Dictionary) -> bool: return f.id == "outs"), "a finished mission is queued for the Results screen")
	var coins := int(Profile.data.coins)
	var rw := Missions.claim("daily", 0)
	ok(int(rw.get("coins", 0)) == 150 and int(Profile.data.coins) == coins + 150, "claiming a tier 1 mission pays 150 coins")
	ok(Missions.claim("daily", 0).is_empty() and int(Profile.data.coins) == coins + 150, "a mission is claimed only once")
	ok(Profile.stat("missions_completed") == 1.0 and int(s.completed) == 1, "claims count as completed missions")
	Profile.bump_stat("total_outs", 10)
	ok(int(s.daily[0].progress) == 5, "a claimed mission stops counting")
	# Max-type missions take the best game.
	s.daily[1] = _mission("combo", "max_combo", 3, 2, true)
	Missions.on_event("max_combo", 2)
	Missions.on_event("max_combo", 2)
	ok(int(s.daily[1].progress) == 2, "combo missions keep the best combo, not the sum")
	Missions.on_event("max_combo", 4)
	ok(Missions.is_done(s.daily[1]), "a combo of 4 completes a combo-of-3 mission")
	# Reroll: once per day, same tier, never a finished mission.
	ok(Missions.rerolls_left() == 1, "one free reroll per day")
	ok(not Missions.can_reroll(1), "a finished mission cannot be rerolled")
	var old_id := str(s.daily[2].id)
	ok(Missions.reroll(2), "reroll succeeds")
	ok(str(s.daily[2].id) != old_id and int(s.daily[2].tier) == 3, "reroll swaps in another tier 3 mission (%s -> %s)" % [old_id, s.daily[2].id])
	ok(Missions.rerolls_left() == 0 and not Missions.reroll(2), "the second reroll of the day is refused")
	# End-of-game events (Rewards.apply): card categories, wins by difficulty.
	s.daily[2] = _mission("win_diff", "win_diff:rookie", 1, 3)
	s.weekly[0] = {"id": "w_cards", "kind": "weekly", "event": "cards_offense", "goal": 4, "progress": 0, "claimed": false, "max": false, "tier": 0}
	var cfg := Session.new_run_config("quick")
	cfg.difficulty = "standard"
	var run := RunState.create(cfg)
	run.inning = 3
	run.wave = 3
	run.stats.card_casts = {"power_throw": 3, "curveball": 2, "line_drive": 1}
	run.stats.outs_by = {run.team[0]: 12}
	var res := Rewards.apply(run, true)
	ok(Missions.is_done(s.daily[2]), "a Standard win counts for a 'win on Rookie or harder' mission")
	ok(Missions.is_done(s.weekly[0]), "Offense cards played in the game count (3 + 1 of 4)")
	ok((res.missions as Array).any(func(f: Dictionary) -> bool: return f.id == "win_diff"), "Results get the missions this game finished")
	ok(bool(res.get("first_win", false)) and (res.packs as Array).any(func(pk: Dictionary) -> bool: return pk.source == "First win bonus"), "the first win pays the first-win bonus")
	var res2 := Rewards.apply(run, true)
	ok(not bool(res2.get("first_win", false)), "the first-win bonus is paid once")
	# Weekly claim: a Pro Pack and stars.
	var stars := int(Profile.data.stars)
	var pros := Profile.pack_count("pro")
	var wr := Missions.claim("weekly", 0)
	ok(str(wr.get("pack", "")) == "pro" and Profile.pack_count("pro") == pros + 1 and int(Profile.data.stars) >= stars + int(wr.get("stars", 0)), "the weekly mission pays a Pro Pack and stars")
	# Starter chain advances step by step.
	var st0 := str(s.starter.id)
	Profile.bump_stat("cards_played", 3)
	ok(Missions.can_claim(s.starter), "starter step 1 (%s) completes after 3 cards" % st0)
	Missions.claim("starter")
	ok(int(s.starter_step) == 1 and str(s.starter.id) == str(Missions.starter_steps()[1].id) and int(s.starter.progress) == 0, "claiming moves the chain to step 2")
	# Day rollover: unclaimed finished missions are paid out, new missions, reroll back.
	coins = int(Profile.data.coins)
	DailyChallenge.date_override = "2026-10-29"
	Missions.refresh()
	ok(int(Profile.data.coins) >= coins + 150 and str(s.day) == "2026-10-29", "finished but unclaimed missions are paid out at the day change")
	ok(s.daily.size() == 3 and s.daily.all(func(m: Dictionary) -> bool: return int(m.progress) == 0 and not bool(m.claimed)), "the new day brings fresh missions")
	ok(Missions.rerolls_left() == 1, "the free reroll comes back each day")
	var week := str(s.week)
	DailyChallenge.date_override = "2026-11-01"
	Missions.refresh()
	ok(str(s.week) == week, "the weekly mission stays until Sunday ends")
	DailyChallenge.date_override = "2026-11-02"
	Missions.refresh()
	ok(str(s.week) == "2026-11-02" and int(s.weekly[0].progress) == 0, "the weekly mission resets on Monday")
	# Saves: round trip, an old save without missions, a broken missions block.
	s.daily[0].progress = 1
	Profile.save_now()
	Profile.load_profile()
	ok(int(Missions.state().daily[0].progress) == 1 and Missions.state().day == "2026-11-02", "missions survive save and load")
	var old: Dictionary = Profile.data.duplicate(true)
	old.erase("missions")
	old.level = 12
	var f := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	ok(Profile.load_status == "ok" and typeof(Profile.data.missions) == TYPE_DICTIONARY, "a pre-Update 6 save loads")
	ok(not Missions.starter_active() and Missions.active().size() == 4, "veterans skip the starter chain but get daily and weekly missions")
	old.level = 1
	old.stats = {}
	f = FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	ok(Missions.starter_active(), "a new manager's old save keeps the starter chain")
	Profile.data.missions = {"day": 5, "daily": [{"id": "nope"}, "junk"], "weekly": "x", "starter": {"id": "nope"}}
	Profile._sanitize()
	Missions.refresh()
	ok(Missions.state().daily.size() == 3 and Missions.state().weekly.size() == 1, "a broken missions block is repaired")
	DailyChallenge.date_override = ""


func test_level_road_and_achievements() -> void:
	section("account level road, new achievements")
	Profile.reset_profile()
	ok(LevelRoad.reward(1).packs.is_empty() and int(LevelRoad.reward(1).coins) == 0, "level 1 is the start (no reward)")
	for l in range(2, Profile.MAX_ACCOUNT_LEVEL + 1):
		var r := LevelRoad.reward(l)
		ok(int(r.coins) > 0 and not (r.packs as Array).is_empty() and LevelRoad.reward_text(l) != "", "level %d pays coins and a pack (%s)" % [l, LevelRoad.reward_text(l)])
	ok(LevelRoad.reward(4).unlocks.any(func(u: Dictionary) -> bool: return u.id == "nova"), "level 4 shows Nova on the road")
	ok(LevelRoad.reward(3).unlocks.any(func(u: Dictionary) -> bool: return u.id == "neon_diamond"), "level 3 shows the Neon Diamond stadium")
	ok("pro" in LevelRoad.reward(10).packs and "pro" in LevelRoad.reward(15).packs, "every fifth level pays a Pro Pack")
	ok(LevelRoad.next_milestone(1) == 3 and LevelRoad.is_milestone(4) and not LevelRoad.is_milestone(8), "milestones: unlocks and Pro Packs")
	var early := 0
	for l in range(2, 7):
		early += LevelRoad.reward(l).packs.size()
	ok(early >= 9, "levels 2-6 pay at least 9 packs for a generous first hour (%d)" % early)
	var coins := int(Profile.data.coins)
	var n := Profile.pack_count()
	Profile.add_xp(Profile.xp_to_next(1))
	ok(int(Profile.data.coins) == coins + int(LevelRoad.reward(2).coins) and Profile.pack_count() == n + 2, "reaching level 2 pays the road reward")
	ok(Profile.stat("account_level") == 2.0, "account level is tracked as a stat")
	# New achievements: data and triggers.
	ok(DB.achievement_order.size() >= 38, "achievements cover the new content (%d)" % DB.achievement_order.size())
	for id in ["new_arrivals", "daily_first", "daily_streak_3", "daily_streak_7", "daily_wins", "mastery_stars", "mastery_card", "set_first",
			"set_all", "missions_10", "missions_50", "caught_stealing", "boss_rush"]:
		ok(DB.achievements.has(id) and int(DB.achievements[id].stars) > 0, "achievement %s defined with stars" % id)
	var names := {}
	for id in DB.achievement_order:
		names[str(DB.achievements[id].name)] = true
	ok(names.size() == DB.achievement_order.size(), "achievement names are unique")
	ok(not names.has("Perfect Game") and not names.has("Mastered"), "no achievement shares a name with a card or the mastery frame")
	for i in 25:
		Profile.bump_stat("boss_iron_slugger")
	ok(Profile.data.achievements.has("boss_rush") and Profile.stat("bosses_defeated") == 25.0, "25 boss kills unlock Boss Rush")
	for cid in Profile.NEW_CARDS_U5:
		Profile.grant_card(cid)
	ok(Profile.data.achievements.has("new_arrivals"), "collecting the six Update 5 cards unlocks New Arrivals")
	Profile.add_card_plays("power_throw", 40)
	ok(Profile.stat("mastery_stars") == 2.0, "mastery stars are counted (%d)" % int(Profile.stat("mastery_stars")))
	Profile.add_card_plays("curveball", 120)
	ok(Profile.data.achievements.has("mastery_card"), "mastering a card unlocks Card Master")
	var cfg := Session.new_run_config("quick")
	var run := RunState.create(cfg)
	run.stats.caught_stealing = 10
	Rewards.apply(run, false)
	ok(Profile.data.achievements.has("caught_stealing"), "catching 10 Base Stealers unlocks Caught Stealing")
	Profile.data.coins = 5000
	Profile.data.cards.power_throw.copies = 10
	var before := Profile.stat("cards_upgraded")
	Profile.upgrade_card("power_throw")
	ok(Profile.stat("cards_upgraded") == before + 1, "card upgrades are counted for missions")


## A run config that does not draw from the global random stream (later battle checks
## depend on it).
func _cfg(mode: String) -> Dictionary:
	return {"mode": mode, "difficulty": "standard", "arena": "steel_yard", "deck": Profile.data.deck.duplicate(),
		"team": Profile.data.team.duplicate(), "captain": Profile.data.captain, "formation": "balanced", "seed": 7, "resume": null}


func test_update6_waves() -> void:
	section("Update 6 waves: Endless pressure, per-mode tuning")
	var cfg := _cfg("endless")
	cfg.difficulty = "standard"
	cfg.seed = 7
	var r := RunState.create(cfg)
	r.inning = 1
	ok(is_equal_approx(WaveGenerator.effective_inning(r), 2.5), "Endless starts further up the curve (%.1f)" % WaveGenerator.effective_inning(r))
	ok(WaveGenerator.mini_boss_for(r, r.waves_per_inning - 1) == "", "no mini-boss in inning 1")
	r.inning = 2
	var w := WaveGenerator.generate(r, r.waves_per_inning - 1, 3)
	var mini: Array = w.groups.filter(func(g: Dictionary) -> bool: return g.enemy == "captain" and g.affix != "")
	ok(w.mini_boss == "captain" and not mini.is_empty(), "inning 2 closes with an elite Captain")
	ok(WaveGenerator.generate(r, 0, 3).mini_boss == "", "only the last wave has the mini-boss")
	r.inning = 3
	ok(WaveGenerator.generate(r, r.waves_per_inning - 1, 3).mini_boss == "", "boss innings have no mini-boss")
	r.inning = 4
	ok(WaveGenerator.generate(r, r.waves_per_inning - 1, 3).mini_boss == "slugger", "from inning 4 the mini-boss is a Slugger")
	var q := _cfg("quick")
	q.difficulty = "standard"
	var qr := RunState.create(q)
	ok(WaveGenerator.mode_tuning(qr, "budget") > 1.0, "Quick Defense Standard has its own tuning")
	var sv := _cfg("standard")
	sv.difficulty = "veteran"
	ok(WaveGenerator.mode_tuning(RunState.create(sv), "enemy_hp") < 1.0, "Standard Siege Veteran is eased")
	sv.difficulty = "standard"
	ok(WaveGenerator.mode_tuning(RunState.create(sv), "enemy_hp") == 1.0, "Standard Siege Standard is unchanged")
	# Update 8: Quick Defense runner health rises at every difficulty step (the per-mode tuning used to
	# give Standard tougher runners than Veteran).
	var prev := 0.0
	var rising := true
	for did in ["rookie", "standard", "veteran", "legend"]:
		q.difficulty = did
		var hp := float(DB.difficulty(did).enemy_hp) * WaveGenerator.mode_tuning(RunState.create(q), "enemy_hp")
		rising = rising and hp > prev
		prev = hp
	ok(rising, "Quick Defense runner health rises with every difficulty step")
	# Update 8: Veteran Standard Siege waves are bigger than Update 7's (the stronger catcher made it too
	# easy) but still smaller than the difficulty's own; boss health is untuned (data/modes.json boss_hp).
	sv.difficulty = "veteran"
	var svr := RunState.create(sv)
	ok(WaveGenerator.mode_tuning(svr, "budget") > 0.78 and WaveGenerator.mode_tuning(svr, "budget") < 1.0, "Veteran Siege wave size is tuned between Update 7 and the difficulty default")
	ok(is_equal_approx(WaveGenerator.boss_hp_tuning(svr, "grand_slammer"), 1.0), "Veteran Siege bosses keep their health")
	# Leave a fresh profile: the battle checks below measure card damage, which defender
	# levels (from the Rewards.apply calls above) would raise.
	Profile.reset_profile()


func _find_text(n: Node, text: String) -> bool:
	if (n is Button and (n as Button).text == text) or (n is Label and (n as Label).text == text):
		return true
	for c in n.get_children():
		if _find_text(c, text):
			return true
	return false


func test_menus() -> void:
	section("menus")
	# Settings search filters rows across every category.
	var sp := SettingsPanel.new()
	add_child(sp)
	await get_tree().process_frame
	sp._search.text = "shadow"
	sp._apply_filter()
	var shown: Array = []
	for r in sp._rows:
		if (r.row as Control).visible:
			shown.append(r.text)
	ok(shown.size() >= 1 and shown.size() < sp._rows.size(), "settings search narrows the rows (%d of %d)" % [shown.size(), sp._rows.size()])
	ok(sp._sections.graphics.visible and not sp._sections.audio.visible, "search shows only categories with matches")
	sp._search.text = "zzzz"
	sp._apply_filter()
	ok(sp._empty.visible, "search with no match shows the empty message")
	sp.queue_free()
	# Results screen builds from a result with timeline + highlights, without a battle.
	var res: Control = load("res://src/ui/results_screen.gd").new()
	res.result = {"won": true, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "coins": 120, "xp": 200, "rp": 10,
		"levels": 0, "innings_cleared": 3, "outs": 40, "runs": 1, "run_limit": 5, "score": 4000, "mvp": "ace",
		"defender_xp": {}, "packs": [{"type": "rookie", "source": "test"}],
		"stats": {"cards_played": 6, "max_combo": 3, "outs_by": {"ace": 9}, "damage_by": {"ace": 1200},
			"timeline": [{"inning": 1, "runs": 0, "energy_avg": 5.0}, {"inning": 2, "runs": 1, "energy_avg": 7.5}],
			"highlights": {"best_combo": {"n": 3, "inning": 2}, "best_play": {"card": DB.card_order[0], "outs": 3, "inning": 1}}}}
	add_child(res)
	await get_tree().process_frame
	var graphs := res.find_children("*", "RunGraph", true, false)
	ok(graphs.size() == 1 and (graphs[0] as RunGraph).timeline.size() == 2, "results shows the game-flow graph")
	var texts := []
	for l in res.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	ok("TRIPLE PLAY" in texts and "BEST CARD PLAY" in texts and "MVP" in texts, "results shows the three highlights")
	res.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- Update 9 (stream E1): hub, Play, Results

func test_u9_screens() -> void:
	section("update 9 screens")
	# Shared helpers.
	var parts := UITheme.reward_parts({"coins": 150})
	ok(parts.size() == 1 and parts[0][0] == "coin" and parts[0][1] == "150", "reward_parts: coins")
	parts = UITheme.reward_parts({"pack": "pro", "stars": 10})
	ok(parts.size() == 2 and parts[0][0] == "gift" and parts[0][1] == "PRO" and parts[1][0] == "star", "reward_parts: pack + stars")
	parts = UITheme.reward_parts({"type": "stars", "amount": 10})
	ok(parts.size() == 1 and parts[0][0] == "star" and parts[0][1] == "10", "reward_parts: {type, amount}")
	ok(UITheme.reward_parts("nonsense").is_empty() and UITheme.reward_parts({}).is_empty(), "reward_parts: empty shapes")
	ok(UITheme.format_duration(3 * 86400 + 4 * 3600) == "3d 4h" and UITheme.format_duration(5 * 3600 + 12 * 60) == "5h 12m"
		and UITheme.format_duration(125) == "2m 05s", "format_duration")
	ok(MenuScreen.mode_locked_reason("standard") == "" and MenuScreen.mode_locked_reason("boss_rush") == "", "Standard and Boss Rush are open")
	var rp_before := int(Profile.data.rp)
	Profile.data.rp = 0
	ok(MenuScreen.mode_locked_reason("ranked").begins_with("Unlocks at"), "the Promotion Challenge says what unlocks it")
	Profile.data.rp = rp_before
	# Hints: every screen's ids exist, including the new features.
	var missing: Array = []
	for sid in Hints.SCREENS.keys():
		for hid in Hints.SCREENS[sid]:
			if not Hints.HINTS.has(hid):
				missing.append(hid)
	for hid in Hints.FEATURE_ONLY:
		if not Hints.HINTS.has(hid):
			missing.append(hid)
	ok(missing.is_empty(), "every listed hint has a text %s" % [missing])
	for hid in ["menu_season", "menu_shop", "menu_login", "menu_streak", "battle_boons", "play_boss_rush", "shop_free_agents", "team_free_agents"]:
		ok(Hints.HINTS.has(hid), "hint for %s" % hid)
	# Flame chip: hot and cold.
	var hot := UITheme.flame_chip(3, 0.3)
	var cold := UITheme.flame_chip(0, 0.0)
	ok(_find_text(hot, "3-WIN STREAK  ·  +30% COINS") and _find_text(cold, "NO WIN STREAK"), "the win streak flame shows the streak and bonus")
	hot.free()
	cold.free()
	# Results: the Update 9 reward sections.
	var res: Control = load("res://src/ui/results_screen.gd").new()
	res.result = {"won": true, "mode": "endless", "difficulty": "standard", "arena": "steel_yard", "coins": 500, "xp": 200, "rp": 30,
		"levels": 0, "innings_cleared": 11, "outs": 90, "runs": 3, "run_limit": 3, "score": 8000, "mvp": "",
		"defender_xp": {}, "packs": [], "stats": {"cards_played": 4, "timeline": []},
		"streak": 2, "streak_bonus_coins": 40, "first_win_today_coins": 0, "season_xp": 160, "season_tiers": [],
		"boons": [], "milestones": [5, 10], "milestone_coins": 450, "overflow_coins": 0}
	add_child(res)
	await get_tree().process_frame
	var chips: Node = res.find_child("CoinBonuses", true, false)
	ok(chips != null and chips.get_child_count() == 2, "results: only the bonuses that paid are listed (streak, milestones)")
	ok(res.find_child("SeasonXP", true, false) != null and res.find_child("Milestones", true, false) != null, "results: season XP and milestones")
	ok(res.find_child("BoonsTaken", true, false) == null and res.find_child("PromotionReward", true, false) == null, "results: no boons or promotion block when there are none")
	# The counter race: counters are bound to their panels; a panel out of the tree stops counting.
	var counter: Control = res.find_child("Counter_COINS", true, false)
	var value: Label = counter.find_child("Value", true, false) if counter else null
	ok(value != null and value.text == "+0", "the coin counter starts at 0")
	await _wait(2.05)   # T_COINS 1.7 + 0.15 fade-in: counting now
	var mid_text := value.text if value else ""
	var parent := counter.get_parent()
	parent.remove_child(counter)
	await _wait(1.0)
	ok(value.text == mid_text, "a counter taken off screen mid-count stops (its tween is killed: %s)" % mid_text)
	counter.free()
	await _wait(0.6)
	ok(is_instance_valid(res), "the results screen survives a counter freed mid-animation")
	res.queue_free()
	await get_tree().process_frame
	# Old-style result (no Update 9 keys): no new sections, nothing breaks.
	var old: Control = load("res://src/ui/results_screen.gd").new()
	old.result = {"won": false, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "coins": 50, "xp": 40, "rp": 3,
		"levels": 0, "innings_cleared": 1, "outs": 10, "runs": 5, "run_limit": 5, "score": 300, "defender_xp": {}, "packs": [], "stats": {}}
	add_child(old)
	await get_tree().process_frame
	ok(old.find_child("CoinBonuses", true, false) == null and old.find_child("SeasonXP", true, false) == null, "results without Update 9 keys stay as before")
	old.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------- Update 8: scouting book, combo hints

func test_scouting() -> void:
	section("scouting book")
	var keys := Scouting.all_keys()
	ok(keys.size() == DB.enemies.size() + DB.elite_affixes.size(), "the book has one entry per runner type, boss and affix (%d)" % keys.size())
	for id in DB.enemies.keys():
		ok(str(id) in keys, "book lists %s" % id)
	for a in DB.elite_affixes:
		ok(Scouting.AFFIX_PREFIX + str(a.id) in keys, "book lists the %s affix" % a.id)
	for b in DB.enemies.keys().filter(func(id: String) -> bool: return bool(DB.enemy(id).get("boss", false))):
		ok(Scouting.group_of(b) == "bosses" and b in Scouting.keys_in_group("bosses"), "%s is listed under bosses" % b)
	for k in keys:
		ok(Scouting.entry_name(k) != "" and not "{" in Scouting.what_it_does(k) and Scouting.what_it_does(k).length() > 20, "%s: plain-language 'what it does'" % k)
		ok(not "{" in Scouting.how_to_stop(k) and Scouting.how_to_stop(k).length() > 20, "%s: 'how to stop it' tips" % k)
		ok(Scouting.ability_name(k) != "", "%s: special ability named" % k)
		var rows := Scouting.stat_rows(k)
		ok(not rows.is_empty() and rows.all(func(r: Array) -> bool: return float(r[3]) >= 0.0 and float(r[3]) <= 1.0), "%s: stat bars within 0..1" % k)
		var counters := Scouting.counters(k)
		ok(not counters.is_empty(), "%s: at least one good card against it" % k)
		var good := Scouting.good_cards(k)
		ok(good.size() >= 1 and good.size() <= Scouting.GOOD_CARDS, "%s: 1-%d good cards shown (%d)" % [k, Scouting.GOOD_CARDS, good.size()])
		var seen_unowned := false
		var order_ok := true
		for cid in good:
			ok(DB.cards.has(cid), "%s: good card %s exists" % [k, cid])
			if not Profile.is_card_owned(cid):
				seen_unowned = true
			elif seen_unowned:
				order_ok = false
		ok(order_ok, "%s: owned good cards are listed first" % k)
		ok(Scouting.reason(good[0], k) != "", "%s: the best card says why" % k)
	# The mapping follows the data: armor calls for armor piercing, speed for slows, bosses for boss cards.
	ok(Scouting.counters("armored").any(func(c: String) -> bool: return "pierce" in Scouting.card_tags(c)), "armored runners are countered by armor-piercing cards")
	ok(Scouting.counters("sprinter").any(func(c: String) -> bool: return "slow" in Scouting.card_tags(c) or "fast_bonus" in Scouting.card_tags(c)), "sprinters are countered by slows or fast-runner cards")
	for b in Scouting.keys_in_group("bosses"):
		ok(Scouting.counters(b).slice(0, 4).all(func(c: String) -> bool: return not "no_boss" in Scouting.card_tags(c)), "%s: no boss-immune card is suggested" % b)
		ok("boss" in Scouting.card_tags(Scouting.counters(b)[0]), "%s: the best counter is a boss card" % b)
	ok("armored" in Scouting.good_against("hot_corner"), "Hot Corner is good against Armored Runners")
	ok(Scouting.good_against("called_shot").any(func(k: String) -> bool: return Scouting.group_of(k) == "bosses"), "Called Shot is good against bosses")
	# Seen tracking.
	var saved: Variant = Profile.data.get("scouting")
	ok(Profile.default_profile().has("scouting"), "new profiles have scouting flags")
	Profile.data.scouting = Scouting.default_state()
	ok(Scouting.met_count() == 0 and not Scouting.is_met("sprinter"), "nothing is scouted on a new profile")
	var fresh := Scouting.mark_enemy("sprinter", "swift")
	ok(fresh.size() == 2 and Scouting.is_met("sprinter") and Scouting.is_met("affix:swift"), "a spawned elite sprinter scouts the sprinter and the Swift affix")
	ok(Scouting.mark_enemy("sprinter", "swift").is_empty(), "a second sighting is not new")
	ok(Scouting.is_new("sprinter") and Scouting.new_count() == 2, "met but not opened: NEW")
	Scouting.mark_viewed("sprinter")
	ok(not Scouting.is_new("sprinter") and Scouting.new_count() == 1, "opening it in the book clears NEW")
	Scouting.mark_viewed("jumper")
	ok(not Scouting.is_viewed("jumper"), "an entry not met yet can't be marked viewed")
	ok(not Scouting.mark_met("not_a_runner"), "unknown runners are ignored")
	Profile.data.scouting.met["bogus"] = "x"
	Scouting.sanitize()
	ok(not Profile.data.scouting.met.has("bogus"), "sanitize drops unknown entries")
	# Migration from saves before Update 8.
	ok(Scouting.migrate({}).met.is_empty(), "a save with no games starts with an empty book")
	var old := {"version": 1, "stats": {"runs_played": 4, "boss_phantom_captain": 1},
		"history": [{"won": true, "mode": "standard", "difficulty": "standard", "inning": 4}]}
	var mig := Scouting.migrate(old)
	ok(mig.met.has("runner") and mig.met.has("jumper") and mig.met.has("iron_slugger"), "migration scouts what the history reached (inning 4)")
	ok(not mig.met.has("captain") and not mig.met.has("grand_slammer"), "migration does not scout what was never reached")
	ok(mig.met.has("phantom_captain") and mig.met.has("decoy"), "a beaten boss (and its decoys) is scouted")
	ok(mig.viewed.has("runner") and not mig.met.has("affix:swift"), "migrated entries are not NEW; no elites without hard games")
	old.history.append({"difficulty": "veteran", "inning": 2})
	ok(Scouting.migrate(old).met.has("affix:plated"), "Veteran games scout the elite affixes")
	var keep := Profile.data
	Profile.data = Profile.default_profile()
	Profile._merge(Profile.data, old.duplicate(true))
	Profile._migrate(old)
	ok(Scouting.is_met("jumper") and not Scouting.is_new("jumper"), "Profile migration fills the book for old saves")
	Profile.data = keep
	Profile.data.scouting = saved if typeof(saved) == TYPE_DICTIONARY else Scouting.default_state()
	# Combo pairs in the hand.
	var hud_script: Script = load("res://src/ui/battle_hud.gd")
	var pairs: Array = hud_script.combo_pairs(["curveball", "heat_wave", "", "power_throw", "lockdown"])
	ok(pairs.size() == 2, "two combo pairs found in the hand (%d)" % pairs.size())
	ok(pairs.size() == 2 and pairs[0][0] == 0 and pairs[0][1] == 1 and pairs[1][0] == 1 and pairs[1][1] == 4, "combo pairs name the right slots")
	ok(pairs.size() > 0 and str(pairs[0][2]) != "", "combo pairs carry the combo text")
	ok((hud_script.combo_pairs(["power_throw", "rally_cry", "", "", ""]) as Array).is_empty(), "no combo, no link")
	var all_found := true
	for c in DB.combos:
		if (hud_script.combo_pairs([c.cards[1], "", c.cards[0]]) as Array).size() != 1:
			all_found = false
	ok(all_found, "every combo in combos.json is detected in either order")
	# Wiring.
	ok(Router.SCENES.has("scouting_book") and ResourceLoader.exists(Router.SCENES.scouting_book), "the Scouting Book scene is registered")
	ok(Hints.HINTS.has("scouting_intro") and Hints.HINTS.has("battle_combo") and "scouting_intro" in Hints.ids_for("scouting_book"), "Scouting Book and combo hints exist")
	var book: Control = load("res://src/ui/scouting_book.gd").new()
	Profile.data.scouting.met["armored"] = "x"
	Scouting.open_on = "armored"
	add_child(book)
	await get_tree().process_frame
	ok(book.get("selected") == "armored", "the book opens on the requested entry")
	var rows: Node = book.find_child("ScoutList", true, false)
	ok(rows != null and rows.get_child_count() >= keys.size(), "the book lists every entry")
	ok(book.find_child("GoodCards", true, false) != null and book.find_child("StatBars", true, false) != null, "the report shows stats and good cards")
	ok(Scouting.is_viewed("armored"), "opening an entry marks it viewed")
	book.queue_free()
	Profile.data.scouting = saved if typeof(saved) == TYPE_DICTIONARY else Scouting.default_state()
	await get_tree().process_frame


func test_battle_systems() -> void:
	section("battle systems")
	var cfg := Session.new_run_config("practice")
	cfg.seed = 5
	Session.run_config = cfg
	var packed: PackedScene = load("res://scenes/battle.tscn")
	battle = packed.instantiate()
	add_child(battle)
	for i in 50:
		await _wait(0.1)
		if battle.state == "setup":
			break
	ok(battle.state == "setup", "battle reaches setup")
	ok(battle.defenders.size() == 6, "six defenders spawned")
	for df in battle.defenders:
		ok(battle.placement_error(df.post, df) == "", "%s starts on a valid spot" % df.id)
	# Position bonus: the pitcher on the mound gets +20% damage.
	var ace: Defender = null
	for df in battle.defenders:
		if df.id == "ace":
			ace = df
	ace.place(Field.MOUND)
	var on_mound := ace.s_damage
	ace.place(Vector3(-6, 0, -14))
	ok(on_mound > ace.s_damage * 1.15, "pitcher position bonus applies on the mound (%.1f vs %.1f)" % [on_mound, ace.s_damage])
	ace.place(Field.MOUND)
	# Placement rules.
	ok(battle.placement_error(Field.FIRST, ace) != "", "can't stand on a base")
	ok(battle.placement_error(Vector3(0, 0, -40), ace) != "", "can't stand outside the park")
	ok(battle.placement_error(battle.routes[0].position_at(5.0), ace) != "", "can't stand on a runner route")
	# Formations change positions and synergies are detected.
	var p0 := ace.post
	battle.apply_formation("wide")
	ok(battle.run.formation == "wide", "formation applied")
	ok(battle.synergy_active("full_squad"), "Full Squad synergy active with every position covered")

	# Targeting & throwing: a runner in range takes damage from defenders.
	var route := battle.routes[0]
	var e := battle.spawn_enemy("runner", route, route.length * 0.6, {"lateral": 0.0, "hp_mult": 1.0})
	var hp0 := e.hp
	for i in 60:
		await _wait(0.1)
		if not e.alive or e.hp < hp0:
			break
	ok(not e.alive or e.hp < hp0, "defenders throw at and damage a runner")
	_clear()

	# Runner reaching home: practice is invulnerable, a shield absorbs it in normal runs.
	battle.run.shields = 1
	var leaker := battle.spawn_enemy("runner", route, route.length - 0.2, {"lateral": 0.0})
	await _wait(0.4)
	ok(battle.run.shields == 0 and battle.run.runs == 0, "base shield turns a scoring runner into an out")
	_clear()

	# Each card: put runners in place, execute, verify the effect.
	battle.cards.infinite_energy = true
	for cid in DB.card_order:
		await _test_card(cid)
	_clear()
	await _test_update5_battle()
	_clear()
	await _test_update7_battle()
	_clear()
	await _test_update8_battle()
	_clear()
	await _test_update9_battle()
	_clear()
	await _test_update9_defenders()
	_clear()
	await _test_update9_cards_battle()
	_clear()
	# Balance statistics: damage and outs are credited to the card that caused them.
	var imp: Dictionary = battle.run.card_impact
	for cid in ["power_throw", "thunderbolt", "sky_hook"]:
		ok(float(imp.get(cid, {}).get("damage", 0.0)) > 0.0, "%s damage is credited to the card (%s)" % [cid, imp.get(cid, {})])
	ok(not imp.has("field_vision"), "buff cards are not credited with damage")
	battle.queue_free()
	await _wait(0.2)


# ---------------------------------------------------------------- tools (Update 5)

func test_tools() -> void:
	section("smoke test and balance tools")
	var all_ok := {"menu": true, "battle": true, "played": true, "results": true, "saved": true, "reloaded": true, "errors": 0}
	ok(SmokeTest.verdict(all_ok) == "PASS", "smoke test passes when every step completes without errors")
	var missing := all_ok.duplicate()
	missing.reloaded = false
	ok(SmokeTest.verdict(missing).begins_with("FAIL") and "reloaded" in SmokeTest.verdict(missing), "a missing step fails the smoke test and names it")
	var errs := all_ok.duplicate()
	errs.errors = 2
	errs.first_error = "boom"
	ok(SmokeTest.verdict(errs).begins_with("FAIL") and "boom" in SmokeTest.verdict(errs), "logged errors fail the smoke test")
	ok(SmokeTest.verdict({}).begins_with("FAIL"), "an empty run fails the smoke test")
	var counter := SmokeTest.ErrorCounter.new()
	OS.add_logger(counter)
	push_warning("smoke-test logger check: this warning is expected and ignored")
	var after_warning := counter.count
	push_error("smoke-test logger check: this error is expected")
	OS.remove_logger(counter)
	ok(after_warning == 0 and counter.count == 1, "the smoke test counts errors but not warnings (%d, %d)" % [after_warning, counter.count])
	var r := RunState.create(Session.new_run_config("quick"))
	r.add_card_impact("power_throw", 120.0, 1)
	r.add_card_impact("power_throw", 30.0)
	r.add_card_impact("", 999.0, 5)
	ok(is_equal_approx(float(r.card_impact.power_throw.damage), 150.0) and int(r.card_impact.power_throw.outs) == 1 and r.card_impact.size() == 1,
		"card impact accumulates per card and ignores uncredited damage")
	ok(not r.to_dict().has("card_impact"), "card impact statistics are not saved with the run")


func _hold_fire(on: bool) -> void:
	for df in battle.defenders:
		df.attack_cd = 1.0e9 if on else 0.5
		df.target = null


## Update 5 cards, the Base Stealer and the Shielded elite in a live battle. Defenders hold
## their throws so each number below comes from the card alone.
func _test_update5_battle() -> void:
	section("update 5 cards, runner and elite (battle)")
	var route := battle.routes[0]
	_hold_fire(true)
	await _wait(0.1)

	# Called Shot: flat + % of max health through armor; capped on regular runners; slows bosses.
	var boss := battle.spawn_enemy("iron_slugger", route, route.length * 0.35, {"lateral": 0.0, "hp_mult": 1.0})
	boss.ability_t = 999.0
	var tank := battle.spawn_enemy("armored", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0})
	await _wait(0.1)
	var b0 := boss.hp
	var t0 := tank.hp
	battle.effects.execute("called_shot", 1, {"enemy": boss, "point": boss.global_position, "valid": true})
	await _wait(1.5)
	battle.effects.execute("called_shot", 1, {"enemy": tank, "point": tank.global_position, "valid": true})
	await _wait(1.5)
	var want_boss := DB.card_param("called_shot", "damage", 1) + boss.max_hp * DB.card_param("called_shot", "percent", 1) / 100.0
	var want_tank := DB.card_param("called_shot", "damage", 1) + DB.card_param("called_shot", "max_bonus", 1)
	ok((b0 - boss.hp) >= want_boss - 3.0 and (b0 - boss.hp) <= want_boss * 1.6, "called shot hits a boss for %d%% of its max health through 75%% armor (%.0f, want %.0f)"
		% [int(DB.card_param("called_shot", "percent", 1)), b0 - boss.hp, want_boss])
	# A crit can multiply the hit, so accept base..crit range; uncapped it would be far larger.
	var dealt_t := t0 - tank.hp
	ok(dealt_t >= want_tank - 3.0 and dealt_t <= want_tank * 1.6, "called shot's bonus is capped on regular runners and ignores armor (%.0f, want %.0f, crit allowed)" % [dealt_t, want_tank])
	ok(boss.slows.has("called_shot"), "called shot slows a boss")
	_clear()
	await _wait(0.2)

	# Line Drive: a small burst - runners in the circle are hit, one outside is not.
	var near := _spawn_pack(3)
	var far := battle.spawn_enemy("runner", battle.routes[battle.routes.size() - 1], 3.0, {"lateral": 0.0, "hp_mult": 40.0})
	await _wait(0.1)
	var near_hp: Array = near.map(func(en: Enemy) -> float: return en.hp)
	var far_hp := far.hp
	battle.effects.execute("line_drive", 1, {"point": near[1].global_position, "valid": true})
	await _wait(1.6)
	var hit_all := true
	for i in near.size():
		hit_all = hit_all and near[i].hp < float(near_hp[i]) - 1.0
	ok(hit_all, "line drive hits every runner in its circle")
	ok(is_equal_approx(far.hp, far_hp), "line drive leaves runners outside the circle alone")
	_clear()
	await _wait(0.2)

	# Tag at the Plate: the next runner home is out (before shields); only one per card.
	battle.run.shields = 1
	var tags := int(battle.run.stats.get("plate_tags", 0))
	battle.effects.execute("tag_at_the_plate", 1, {"valid": true})
	var r1 := battle.spawn_enemy("runner", route, route.length - 0.3, {"lateral": 0.0})
	await _wait(0.5)
	ok(not r1.alive and r1.hp <= 0.0 and battle.run.shields == 1 and int(battle.run.stats.get("plate_tags", 0)) == tags + 1,
		"tag at the plate tags out the next runner home, before the shield")
	ok(not battle.buff_active("plate_tag"), "the plate tag is used up by one runner")
	var r2 := battle.spawn_enemy("runner", route, route.length - 0.3, {"lateral": 0.0})
	await _wait(0.5)
	ok(not r2.alive and battle.run.shields == 0, "the next runner meets the Base Shield instead")
	# A boss is stunned and shoved back instead of tagged.
	battle.effects.execute("tag_at_the_plate", 1, {"valid": true})
	var boss2 := battle.spawn_enemy("iron_slugger", route, route.length - 0.2, {"lateral": 0.0, "hp_mult": 1.0})
	boss2.ability_t = 999.0
	await _wait(0.4)
	ok(boss2.alive and boss2.stun_t > 0.0 and boss2.remaining() > 2.5, "a boss at the plate is stunned and shoved back (%.1f m out)" % boss2.remaining())
	_clear()
	await _wait(0.2)

	# Bullpen Call: draws cards and gives energy.
	battle.cards.infinite_energy = false
	battle.cards.energy = 2.0
	for i in battle.cards.hand.size():
		battle.cards.hand[i] = ""
	var hand0 := battle.cards.hand_count()
	battle.effects.execute("bullpen_call", 1, {"valid": true})
	ok(battle.cards.hand_count() == hand0 + int(DB.card_param("bullpen_call", "draw", 1)), "bullpen call draws %d cards" % int(DB.card_param("bullpen_call", "draw", 1)))
	ok(absf(battle.cards.energy - (2.0 + DB.card_param("bullpen_call", "energy", 1))) < 0.05, "bullpen call gives energy (%.2f)" % battle.cards.energy)
	battle.cards.infinite_energy = true

	# Hot Corner: the chosen defender's throws pierce armor, can't miss and hit harder.
	var hot: Defender = battle.defenders[0]
	var other: Defender = battle.defenders[1]
	var armored := battle.spawn_enemy("armored", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0})
	var dmg0 := hot.effective_damage()
	battle.effects.execute("hot_corner", 1, {"defender": hot, "valid": true})
	await _wait(0.1)
	var pl: Dictionary = hot._build_payload(armored, false)
	ok(float(pl.get("pierce", 0.0)) >= 1.0 and float(pl.get("accuracy", 0.0)) >= 200.0, "hot corner throws pierce armor and can't miss")
	ok(hot.effective_damage() > dmg0 * 1.2, "hot corner raises the defender's damage (%.0f -> %.0f)" % [dmg0, hot.effective_damage()])
	ok(float(other._build_payload(armored, false).get("pierce", 0.0)) < 1.0, "other defenders are not affected")
	var ah := armored.hp
	battle.projectiles.hit(armored, pl, armored.center())
	ok(ah - armored.hp >= float(pl.damage) * 0.99, "a hot-corner throw deals full damage to an armored runner (%.0f of %.0f)" % [ah - armored.hp, float(pl.damage)])
	_clear()
	await _wait(0.2)

	# Perfect Game: every runner stunned and damaged, bosses lose a share of max health, tag window.
	var pack := _spawn_pack(4)
	var boss3 := battle.spawn_enemy("phantom_captain", battle.routes[battle.routes.size() - 1], 6.0, {"lateral": 0.0, "hp_mult": 1.0})
	boss3.ability_t = 999.0
	await _wait(0.1)
	var bhp := boss3.hp
	var php: Array = pack.map(func(en: Enemy) -> float: return en.hp)
	battle.effects.execute("perfect_game", 1, {"valid": true})
	await _wait(1.2)
	var all_hit := true
	for i in pack.size():
		all_hit = all_hit and pack[i].hp < float(php[i]) - 1.0 and pack[i].stun_t > 0.0
	ok(all_hit, "perfect game damages and stuns every runner")
	ok(bhp - boss3.hp >= boss3.max_hp * DB.card_param("perfect_game", "boss_percent", 1) / 100.0, "perfect game takes %d%% of a boss's health (%.0f)"
		% [int(DB.card_param("perfect_game", "boss_percent", 1)), bhp - boss3.hp])
	var r3 := battle.spawn_enemy("runner", route, route.length - 0.3, {"lateral": 0.0})
	var r4 := battle.spawn_enemy("runner", route, route.length - 0.2, {"lateral": 0.6})
	await _wait(0.5)
	ok(not r3.alive and not r4.alive and r3.hp <= 0.0 and r4.hp <= 0.0, "during the Perfect Game window every runner home is tagged out")
	_clear()
	await _wait(0.2)

	# Shielded elite: the bubble blocks the first hit only.
	var sh := battle.spawn_enemy("runner", route, route.length * 0.4, {"lateral": 0.0, "hp_mult": 10.0, "affix": "shielded"})
	await _wait(0.2)
	ok(sh.shield_hits == 1, "a Shielded elite starts with a bubble")
	var s0 := sh.hp
	var d1 := battle.deal_damage(sh, 100.0, {"kind": "throw"})
	ok(d1 == 0.0 and is_equal_approx(sh.hp, s0) and sh.shield_hits == 0, "the bubble blocks the first hit")
	var d2 := battle.deal_damage(sh, 100.0, {"kind": "throw"})
	ok(d2 > 0.0 and sh.hp < s0, "the second hit gets through")
	_clear()
	await _wait(0.2)

	# Base Stealer: steals while unwatched; a slow mid-steal catches it stealing.
	# Nobody can see it at first: shrink every defender's range.
	var ranges: Array = battle.defenders.map(func(df: Defender) -> float: return df.s_range)
	for df in battle.defenders:
		df.s_range = 0.1
	var st := battle.spawn_enemy("base_stealer", route, 2.0, {"lateral": 0.0, "hp_mult": 10.0})
	await _wait(1.2)
	ok(st.is_stealing() or st.steal_cd > 0.0, "an unwatched Base Stealer takes off")
	var spd_steal := st.current_speed() if st.is_stealing() else 0.0
	if not st.is_stealing():
		st.steal_cd = 0.0
		await _wait(0.8)
		spd_steal = st.current_speed()
	ok(st.is_stealing() and spd_steal > st.base_speed * 1.8, "stealing runs at steal speed (%.1f vs %.1f)" % [spd_steal, st.base_speed])
	var caught := int(battle.run.stats.get("caught_stealing", 0))
	st.apply_slow("curveball", 0.4, 2.0)
	await _wait(0.1)
	ok(not st.is_stealing() and st.stun_t > 0.0 and st.vulnerable_t > 0.0 and int(battle.run.stats.get("caught_stealing", 0)) == caught + 1,
		"a slow mid-steal catches it stealing (stunned, vulnerable)")
	# Watched: a defender aiming at it keeps it from stealing.
	st.slows.clear()
	st.stun_t = 0.0
	st.vulnerable_t = 0.0
	var watcher: Defender = battle.defenders[0]
	var rng0 := watcher.s_range
	watcher.s_range = 999.0
	watcher.target = st
	st.steal_cd = 0.0
	await _wait(1.0)
	ok(not st.is_stealing() and watcher.target == st, "a Base Stealer a defender is aiming at doesn't steal")
	watcher.s_range = rng0
	for i in battle.defenders.size():
		battle.defenders[i].s_range = float(ranges[i])
	_hold_fire(false)
	_clear()


## Update 5 content outside battle: collection, saves, packs, waves, the new runner data.
func test_update5_content() -> void:
	section("update 5 cards, runner and elite (data)")
	# A fresh profile sees the new cards, not owned.
	Profile.reset_profile()
	for id in NEW_CARDS:
		ok(Profile.data.cards.has(id) and not Profile.is_card_owned(id), "fresh profile lists %s, not owned" % id)
		ok(DB.combos_for(id).size() > 0, "%s has a combo" % id)
		var details := str(DB.card(id).get("details", ""))
		for key in DB.card(id).params.keys():
			details = details.replace("{%s}" % key, "1")
		ok(details != "" and not "{" in details, "%s has details text with resolvable values" % id)
	# An old save without the new cards loads them as not owned (and keeps what it had).
	var old: Dictionary = Profile.data.duplicate(true)
	for id in NEW_CARDS:
		old.cards.erase(id)
	old.cards.splitter.owned = true
	var f := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	var all_there := true
	for id in NEW_CARDS:
		all_there = all_there and Profile.data.cards.has(id) and not Profile.is_card_owned(id)
	ok(all_there and Profile.is_card_owned("splitter"), "an existing save gains the new cards as not owned")
	# Packs can roll them: every rarity pool holds its new card.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var seen := {}
	for i in 400:
		for cid in Profile.roll_pack("champion", rng):
			seen[cid] = true
	for id in NEW_CARDS:
		ok(seen.has(id), "packs can contain %s" % id)
	Profile.reset_profile()
	# The new runner and elite affix.
	ok(int(DB.achievements.full_collection.goal) == DB.cards.size(), "the Full Deck achievement asks for every card")
	ok(DB.enemies.has("base_stealer") and DB.portrait("base_stealer") != null, "Base Stealer defined with a portrait")
	ok(DB.elite_affixes.any(func(a: Dictionary) -> bool: return a.id == "shielded"), "Shielded elite affix defined")
	var cfg := Session.new_run_config("standard")
	var early := false
	var later := false
	for s in 30:
		cfg.seed = 100 + s
		var r := RunState.create(cfg)
		for inning in range(1, 10):
			r.inning = inning
			for w in 3:
				var info := WaveGenerator.generate(r, w, 4)
				if info.preview.has("base_stealer"):
					if inning < 4:
						early = true
					else:
						later = true
	ok(later and not early, "Base Stealers appear from inning 4 (later %s, early %s)" % [later, early])


func _clear() -> void:
	battle.effects.clear_active()
	for en in battle.enemies.duplicate():
		en.die({})
	for w in battle.walls.duplicate():
		w.crumble()
	battle.buffs.clear()
	for df in battle.defenders:
		df.stun_t = 0.0


func _spawn_pack(n: int, id := "runner") -> Array:
	var out: Array = []
	var route := battle.routes[0]
	for i in n:
		out.append(battle.spawn_enemy(id, route, route.length * 0.45 + i * 0.4, {"lateral": 0.0, "hp_mult": 40.0}))
	return out


func any_blocked(pack: Array) -> bool:
	for en in pack:
		if is_instance_valid(en) and en.blocked:
			return true
	return false


func _test_card(cid: String) -> void:
	_clear()
	await _wait(0.1)
	var pack := _spawn_pack(4)
	var lead: Enemy = pack[pack.size() - 1]
	var center: Vector3 = pack[1].global_position
	var hp_before := 0.0
	for en in pack:
		hp_before += en.hp
	var c := DB.card(cid)
	var tgt := {"point": center, "enemy": lead, "defender": battle.defenders[0], "valid": true}
	var energy_before := battle.cards.energy
	var shields := battle.run.shields
	var hand_before := battle.cards.hand_count()
	battle.effects.execute(cid, 1, tgt)
	if cid == "wall_of_dirt":
		ok(battle.walls.size() > 0, "wall of dirt places a wall")
		await _wait(0.5)
		ok(any_blocked(pack), "the wall blocks runners")
		return
	await _wait(2.6)
	var hp_after := 0.0
	for en in pack:
		if is_instance_valid(en):
			hp_after += maxf(en.hp, 0.0)
	var damaged := hp_after < hp_before - 1.0
	var any := func(pred: Callable) -> bool:
		for en in pack:
			if is_instance_valid(en) and pred.call(en):
				return true
		return false
	match cid:
		"curveball":
			ok(any.call(func(en: Enemy) -> bool: return en.mark_t > 0.0), "curveball marks runners")
		"knuckleball":
			ok(lead.confuse_t > 0.0 or not lead.alive, "knuckleball confuses its target")
		"time_out":
			ok(any.call(func(en: Enemy) -> bool: return en.freeze_t > 0.0), "time out freezes runners")
		"changeup":
			ok(any.call(func(en: Enemy) -> bool: return en.slows.has("changeup")), "changeup slows all runners")
		"lockdown":
			ok(any.call(func(en: Enemy) -> bool: return en.slows.has("lockdown")), "lockdown roots/slows runners")
		"frost_field":
			ok(battle.zones.size() > 0, "frost field creates a zone")
			ok(any.call(func(en: Enemy) -> bool: return en.chill_t > 0.0), "frost field chills runners")
		"base_shield":
			ok(battle.run.shields == mini(shields + 1, 3), "base shield adds a shield")
		"bunt_trap":
			ok(battle.traps.size() > 0 or damaged, "bunt trap placed")
		"twin_play":
			ok(battle.buff_active("twin_play"), "twin play buff active")
		"field_vision":
			ok(battle.field_vision_active, "field vision active")
		"rally_cry":
			ok(battle.buff_active("rally"), "rally cry buff active")
		"diamond_aura":
			ok(battle.buff_active("diamond_aura"), "diamond aura buff active")
		"magnet_glove":
			ok(any.call(func(en: Enemy) -> bool: return en.magnet_t > 0.0) or damaged, "magnet glove pulls runners")
		"seventh_inning_stretch":
			ok(battle.cards.hand_count() >= mini(hand_before + 1, CardSystem.MAX_HAND) or battle.cards.energy >= energy_before, "stretch draws cards / gives energy")
		"shadow_change":
			ok(damaged, "shadow change damages runners")
		"tag_at_the_plate":
			ok(battle.buff_active("plate_tag"), "tag at the plate arms a plate tag")
		"bullpen_call":
			ok(battle.cards.hand_count() >= mini(hand_before + 1, CardSystem.MAX_HAND), "bullpen call draws cards")
		"hot_corner":
			ok(battle.hot_corner_on(battle.defenders[0]), "hot corner heats up the chosen defender")
		"rain_delay":
			ok(battle.spawn_hold > 0.0 or any.call(func(en: Enemy) -> bool: return en.slows.has("rain")), "rain delay holds the gates and slows runners")
		"intentional_walk":
			ok(lead.slows.has("intentional_walk") or not lead.alive, "intentional walk walks its target")
		"rundown":
			ok(lead.rundown_t > 0.0 or damaged, "rundown traps its target")
		"infield_fly":
			ok(any.call(func(en: Enemy) -> bool: return not en.alive) or not battle.effects.active_item("infield_fly").is_empty(), "infield fly catches a runner")
		"golden_glove":
			ok(not battle.effects.active_item("golden_glove").is_empty() or any.call(func(en: Enemy) -> bool: return not en.alive), "golden glove arms a defender")
		"the_shift":
			ok(battle.buff_active("shift"), "the shift is on")
		"momentum":
			ok(battle.buff_active("momentum"), "momentum is on")
		"instant_replay":
			ok(damaged or not battle.effects.active.is_empty(), "instant replay plays the last card again")
		"perfect_game":
			ok(damaged, "perfect game damages every runner")
			ok(battle.buff_active("perfect_tag"), "perfect game opens a tag window at the plate")
		# Update 9 cards (exact numbers in _test_update9_cards_battle)
		"scouting_report":
			ok(lead.scout_t > 0.0 or not lead.alive, "scouting report scouts its target's type")
		"sprinkler_system":
			ok(not battle.effects.active_item("wet").is_empty(), "sprinkler system soaks a base path")
		"sweet_spot":
			ok(battle.buff_active("sweet_spot"), "sweet spot is on")
		"rally_monkey":
			ok(battle.cards.energy >= energy_before, "rally monkey gives energy")
		"second_wind":
			ok(battle.buff_active("second_wind"), "second wind boosts a defender")
		"money_ball":
			ok(battle.buff_active("money_ball"), "money ball is on")
		"signal_caller":
			ok(any.call(func(en: Enemy) -> bool: return en.signal_t > 0.0), "signal caller marks runners")
		"hidden_ball_trick":
			ok(any.call(func(en: Enemy) -> bool: return not en.alive), "hidden ball trick tags a runner out")
		"ground_rule_double":
			ok(battle.cards.double_casts_left(battle.run.inning) == int(DB.card_param(cid, "casts", 1)), "ground rule double arms its casts")
			battle.cards.double_left = 0   # don't double the cards of the later tests
		_:
			ok(damaged, "%s deals damage (%.0f -> %.0f)" % [cid, hp_before, hp_after])


func test_upgrade_all() -> void:
	section("upgrade all")
	Profile.reset_profile()
	var owned: Array = []
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned.append(cid)
	# Give the first three owned cards plenty of copies and enough coins for a few level-ups.
	for cid in owned.slice(0, 3):
		Profile.data.cards[cid].copies = 200
	Profile.data.coins = 5000
	var levels_before := {}
	for cid in owned:
		levels_before[cid] = Profile.card_level(cid)
	var plan := Profile.upgrade_all_plan()
	ok(Profile.data.coins == 5000 and Profile.card_level(owned[0]) == levels_before[owned[0]], "the preview changes nothing")
	ok(plan.levels > 0 and not plan.cards.is_empty(), "the plan finds upgrades (%d level-ups, %d coins)" % [plan.levels, plan.coins])
	ok(plan.coins <= 5000, "the plan never spends more coins than the player has")
	var done := Profile.upgrade_all()
	ok(done.size() == plan.cards.size(), "Upgrade All applies the previewed cards (%d)" % done.size())
	ok(Profile.data.coins == 5000 - int(plan.coins), "Upgrade All spends exactly the previewed coins (%d left)" % Profile.data.coins)
	var all_match := true
	for e in plan.cards:
		if Profile.card_level(e.id) != int(e.to):
			all_match = false
	ok(all_match, "every card reaches its previewed level")
	ok(Profile.upgrade_all_plan().levels == 0, "after Upgrade All nothing affordable is left over")
	Profile.data.coins = 0
	ok(Profile.upgrade_all_plan().levels == 0 and Profile.upgrade_all().is_empty(), "with no coins nothing is upgraded")
	Profile.reset_profile()


# ---------------------------------------------------------------- deck AI (Auto Build)

func _ai_ctx(owned: Array, team: Array = [], captain := "ace", levels := {}) -> Dictionary:
	if team.is_empty():
		team = ["ace", "rico", "maya", "jax", "kai", "bruno"]
	var dl := {}
	for d in team:
		dl[d] = 1
	return {"owned": owned, "levels": levels, "mastery": {}, "team": team, "captain": captain, "defender_levels": dl}


func _unique_owned(deck: Array, owned: Array) -> bool:
	var seen := {}
	for cid in deck:
		if seen.has(cid) or not cid in owned or not DB.cards.has(cid):
			return false
		seen[cid] = true
	return true


func test_deck_ai() -> void:
	section("deck AI (auto build)")
	var all: Array = []
	for cid in DB.card_order:
		all.append(cid)
	# Every card can be analysed from generic data, with or without a "role" field.
	var bad: Array = []
	for cid in all:
		var a := DeckAI.analyze(cid, 1)
		if not str(a.get("role", "")) in DeckAI.ROLES or float(a.get("power", 0.0)) <= 0.0 or (a.tags as Array).is_empty():
			bad.append(cid)
	ok(bad.is_empty(), "every card gets a role, tags and a positive power (%s)" % [bad])
	ok(float(DeckAI.analyze("heat_wave", 5).power) > float(DeckAI.analyze("heat_wave", 1).power), "a higher level means more power")
	ok("aoe" in DeckAI.analyze("heat_wave").tags and "boss" in DeckAI.analyze("time_out").tags and "run_stop" in DeckAI.analyze("wall_of_dirt").tags
		and "control" in DeckAI.analyze("curveball").tags and "economy" in DeckAI.analyze("bullpen_call").tags, "roles are inferred from params and target")
	# Full collection: every mode gives 8 unique owned cards, covers the roles and keeps the curve.
	var full := _ai_ctx(all)
	var decks := {}
	for m in DeckAI.MODES:
		var r := DeckAI.build(m, full)
		decks[m] = r
		var d: Array = r.deck
		ok(d.size() == Profile.DECK_SIZE and _unique_owned(d, all), "%s: 8 unique owned cards (%s)" % [m, d])
		var n: Dictionary = r.counts
		ok(int(n.damage) >= 2 and int(n.aoe) >= 1 and int(n.control) >= 1 and int(n.stop) >= 1 and int(n.boss) >= 1,
			"%s: covers damage/AoE/control/run-stop/boss (%s)" % [m, n])
		var band: Array = DeckAI.MODE_CFG[m].band
		ok(float(r.avg_cost) >= float(band[0]) - 0.01 and float(r.avg_cost) <= float(band[1]) + 0.3 and int(n.heavy) <= 2,
			"%s: average cost %.2f in the band, %d cards cost 6+" % [m, r.avg_cost, n.heavy])
		ok(r.deck == DeckAI.build(m, full).deck, "%s: the same input gives the same deck" % m)
		ok(str(r.summary).contains("avg cost") and (r.reasons as Dictionary).size() == d.size(), "%s: summary and a reason for every card" % m)
	ok(int(decks.aggressive.counts.damage) >= int(decks.balanced.counts.damage), "Aggressive has at least as much damage as Balanced")
	ok(int(decks.control.counts.control) >= int(decks.balanced.counts.control) and int(decks.control.counts.control) >= 3, "Control has 3+ control cards")
	ok(int(decks.boss.counts.boss) >= 2, "Boss Killer has 2+ boss answers (%d)" % int(decks.boss.counts.boss))
	ok(DeckAI.build("nonsense", full).mode == "balanced", "an unknown mode falls back to Balanced")
	# Signatures: preferred when the defender is on the team, penalised when absent.
	var with_ace := _ai_ctx(all, ["ace", "rico", "maya", "jax", "kai", "bruno"], "ace")
	var no_ace := _ai_ctx(all, ["nova", "rico", "maya", "jax", "kai", "bruno"], "rico")
	var hw := DeckAI.analyze("heat_wave", 1)
	ok(DeckAI.card_score(hw, "balanced", with_ace) > DeckAI.card_score(hw, "balanced", no_ace) + 2.0, "a signature scores higher with its defender on the team")
	var r_ace := DeckAI.build("balanced", with_ace)
	ok("heat_wave" in r_ace.deck and "heat_wave" in r_ace.signatures, "Heat Wave is picked as a signature when Ace is on the team")
	var absent := 0
	for cid in DeckAI.build("balanced", no_ace).deck:
		var l := str(DB.card(cid).get("linked", ""))
		if l != "" and not l in no_ace.team:
			absent += 1
	ok(absent <= 1, "linked cards of absent defenders are mostly left out (%d)" % absent)
	ok(str(r_ace.summary).contains("Ace is on your team") or str(r_ace.summary).contains("signatures"), "the summary names the signatures (%s)" % r_ace.summary)
	# Combos count: a deck score with a combo pair beats the same cards without it.
	var info := {}
	for cid in ["curveball", "heat_wave", "power_throw"]:
		info[cid] = DeckAI.analyze(cid, 1)
		info[cid]["score"] = 0.0
	ok(float(DeckAI.deck_score(["curveball", "heat_wave"], info, "balanced", full, {}).combos) > 0.0
		and float(DeckAI.deck_score(["curveball", "power_throw"], info, "balanced", full, {}).combos) == 0.0, "combo pairs add to the deck score")
	# Tiny and odd collections.
	var five: Array = all.slice(0, 5)
	var r5 := DeckAI.build("balanced", _ai_ctx(five))
	ok(r5.deck.size() == 5 and _unique_owned(r5.deck, five) and str(r5.summary).contains("only 5"), "5 owned cards: all of them, and the summary says so")
	var eight: Array = ["power_throw", "curveball", "wall_of_dirt", "field_vision", "heat_wave", "lockdown", "frost_field", "twin_play"]
	var r8 := DeckAI.build("aggressive", _ai_ctx(eight))
	var same: Array = r8.deck.duplicate()
	same.sort()
	eight.sort()
	ok(same == eight, "exactly 8 owned: the deck is those 8")
	ok(DeckAI.build("balanced", _ai_ctx([])).deck.is_empty(), "no cards owned: an empty deck, no crash")
	ok(DeckAI.build("balanced", _ai_ctx(["heat_wave", "heat_wave", "nope", "curveball"])).deck.size() == 2, "duplicates and unknown ids in the owned list are ignored")
	# Random collections of 8..all cards: always 8 unique owned cards, stable.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var all_ok := true
	for i in 12:
		var pool := all.duplicate()
		for k in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var t: Variant = pool[k]
			pool[k] = pool[j]
			pool[j] = t
		var owned: Array = pool.slice(0, rng.randi_range(8, pool.size()))
		var lv := {}
		for cid in owned:
			lv[cid] = rng.randi_range(1, DB.card_max_level)
		var ctx := _ai_ctx(owned, [], "ace", lv)
		var m: String = DeckAI.MODES[i % DeckAI.MODES.size()]
		var d: Array = DeckAI.build(m, ctx).deck
		if d.size() != Profile.DECK_SIZE or not _unique_owned(d, owned) or d != DeckAI.build(m, ctx).deck:
			all_ok = false
	ok(all_ok, "random collections (8 to %d cards, random levels): 8 unique owned cards, deterministic" % all.size())
	# The default context reads the profile.
	Profile.reset_profile()
	var rp := DeckAI.build()
	ok(rp.deck.size() == mini(Profile.DECK_SIZE, DeckAI.profile_context().owned.size()) and _unique_owned(rp.deck, DeckAI.profile_context().owned), "profile context: owned cards only")
	ok(Profile.set_deck(rp.deck) or rp.deck.size() < Profile.DECK_SIZE, "the auto-built deck is a valid saved deck")


# ---------------------------------------------------------------- Update 7 cards

## Update 7 cards in a live battle: each test checks what the card text says. Defenders hold
## their throws so the numbers come from the card alone.
func _test_update7_battle() -> void:
	section("update 7 cards (battle)")
	var route := battle.routes[0]
	var other_route := battle.routes[battle.routes.size() - 1]
	_hold_fire(true)
	await _wait(0.1)
	var lv := 1

	# Bean Ball: damage, stun, knockback; fast runners take double and fly back twice as far.
	var slow_r := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	var fast_r := battle.spawn_enemy("sprinter", other_route, other_route.length * 0.5, {"lateral": 0.0, "hp_mult": 80.0, "speed_mult": 0.01})
	await _wait(0.1)
	var h1 := slow_r.hp
	var h2 := fast_r.hp
	var d1 := slow_r.d
	var d2 := fast_r.d
	battle.effects.execute("bean_ball", lv, {"enemy": slow_r, "point": slow_r.global_position, "valid": true})
	battle.effects.execute("bean_ball", lv, {"enemy": fast_r, "point": fast_r.global_position, "valid": true})
	await _wait(1.2)
	var dmg := DB.card_param("bean_ball", "damage", lv)
	ok(absf((h1 - slow_r.hp) - dmg) < 2.0, "bean ball hits a runner for %d (%.0f)" % [int(dmg), h1 - slow_r.hp])
	ok(absf((h2 - fast_r.hp) - dmg * 2.0) < 3.0, "bean ball hits a fast runner for double (%.0f)" % (h2 - fast_r.hp))
	ok(slow_r.stun_t > 0.0 and fast_r.stun_t > 0.0, "bean ball stuns")
	ok(d1 - slow_r.d > 1.0 and (d2 - fast_r.d) > (d1 - slow_r.d) * 1.6, "bean ball knocks back, fast runners twice as far (%.1f vs %.1f m)" % [d1 - slow_r.d, d2 - fast_r.d])
	_clear()
	await _wait(0.2)

	# Around the Horn: the lead runner on every path first, then the next runners, up to `targets`.
	var on_a: Array = []
	for i in 4:
		on_a.append(battle.spawn_enemy("runner", route, route.length * 0.3 + i * 1.5, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01}))
	var on_b := battle.spawn_enemy("runner", other_route, other_route.length * 0.2, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	await _wait(0.1)
	var hp_a: Array = on_a.map(func(en: Enemy) -> float: return en.hp)
	var hb := on_b.hp
	battle.effects.execute("around_the_horn", lv, {"valid": true})
	await _wait(1.2)
	var hit_n := 0
	for i in on_a.size():
		if on_a[i].hp < float(hp_a[i]) - 1.0:
			hit_n += 1
	ok(on_b.hp < hb - 1.0, "around the horn hits the lead runner on the second path")
	ok(on_a[3].hp < float(hp_a[3]) - 1.0 and hit_n == 3 and on_a[0].hp >= float(hp_a[0]) - 0.01,
		"around the horn hits %d runners in all, leaders first (%d of 4 on the busy path)" % [int(DB.card_param("around_the_horn", "targets", lv)), hit_n])
	_clear()
	await _wait(0.2)

	# Grand Salami: hits every runner on the path behind the landing spot, then they burn.
	var row: Array = []
	for i in 4:
		row.append(battle.spawn_enemy("runner", route, route.length * 0.6 - i * 2.5, {"lateral": 0.0, "hp_mult": 60.0, "speed_mult": 0.01}))
	var aside := battle.spawn_enemy("runner", other_route, 4.0, {"lateral": 0.0, "hp_mult": 60.0, "speed_mult": 0.01})
	await _wait(0.1)
	var hp_row: Array = row.map(func(en: Enemy) -> float: return en.hp)
	var ha := aside.hp
	battle.effects.execute("grand_salami", lv, {"point": row[0].global_position, "valid": true})
	await _wait(1.8)
	var all_hit := true
	var burning := false
	for i in row.size():
		all_hit = all_hit and row[i].hp <= float(hp_row[i]) - DB.card_param("grand_salami", "damage", lv) * 0.9
		burning = burning or row[i].burn_t > 0.0
	ok(all_hit, "grand salami rolls over every runner on the path for its damage")
	ok(burning, "grand salami's fire trail burns runners")
	ok(is_equal_approx(aside.hp, ha), "grand salami leaves other paths alone")
	_clear()
	await _wait(0.2)

	# Rundown: the runner goes back and forth inside its stretch, tagged at each turn.
	var rd := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0})
	await _wait(0.1)
	var rhp := rd.hp
	battle.effects.execute("rundown", lv, {"enemy": rd, "point": rd.global_position, "valid": true})
	await _wait(0.6)
	var lo := rd.rundown_lo
	var hi := rd.rundown_hi
	var stayed := rd.rundown_t > 0.0
	var turned := false
	var last_dir := rd.rundown_dir
	for i in 25:
		await _wait(0.1)
		stayed = stayed and rd.d >= lo - 0.3 and rd.d <= hi + 0.3
		turned = turned or rd.rundown_dir != last_dir
	ok(stayed and hi - lo > 4.0, "rundown keeps the runner inside its stretch (%.1f m)" % (hi - lo))
	ok(turned and rd.hp < rhp - DB.card_param("rundown", "damage", lv) * 0.9, "rundown turns the runner and tags it (%.0f damage)" % (rhp - rd.hp))
	await _wait(2.0)
	ok(rd.rundown_t <= 0.0, "the rundown ends after its duration")
	_clear()
	await _wait(0.2)

	# Rain Delay: the gates stay shut and every runner (a boss too, in full) is slowed.
	var wet := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0})
	var wet_boss := battle.spawn_enemy("iron_slugger", other_route, 5.0, {"lateral": 0.0, "hp_mult": 1.0})
	wet_boss.ability_t = 999.0
	await _wait(0.1)
	battle.effects.execute("rain_delay", lv, {"valid": true})
	var slow := DB.card_param("rain_delay", "slow", lv) / 100.0
	ok(battle.spawn_hold >= DB.card_param("rain_delay", "delay", lv) - 0.01, "rain delay closes the gates for %ds" % int(DB.card_param("rain_delay", "delay", lv)))
	ok(wet.slows.has("rain") and absf(float(wet.slows.rain[0]) - slow) < 0.01, "rain delay slows runners %d%%" % int(slow * 100.0))
	var boss_speed := wet_boss.current_speed()
	ok(absf(boss_speed - wet_boss.base_speed * (1.0 - slow) * wet_boss.aura_speed) < 0.05, "a boss gets the full rain slow (%.2f of %.2f)" % [boss_speed, wet_boss.base_speed])
	var queued := {"time": battle.wave_time + 0.05, "route": 0, "enemy": "runner", "affix": "", "hp_mult": 1.0, "speed_mult": 1.0}
	battle.spawn_queue.append(queued)
	var count0 := battle.enemies.size()
	battle._process_spawns(0.5)
	ok(battle.enemies.size() == count0 and battle.spawn_queue.size() == 1, "no runner leaves the gate during the delay")
	battle.spawn_hold = 0.0
	battle._process_spawns(0.2)
	ok(battle.spawn_queue.is_empty() and battle.enemies.size() == count0 + 1, "runners come out again after the delay")
	_clear()
	await _wait(0.2)

	# Intentional Walk: slowed to a walk, and a walking runner home scores nothing.
	var runs_seen := [0]
	var on_run := func(n: int) -> void: runs_seen[0] = int(runs_seen[0]) + n
	battle.run_scored.connect(on_run)
	var walker := battle.spawn_enemy("runner", route, route.length - 1.0, {"lateral": 0.0, "hp_mult": 40.0})
	await _wait(0.05)
	var sp0 := walker.current_speed()
	battle.effects.execute("intentional_walk", lv, {"enemy": walker, "point": walker.global_position, "valid": true})
	ok(sp0 > 0.0 and walker.current_speed() <= walker.base_speed * walker.aura_speed * (1.0 - DB.card_param("intentional_walk", "slow", lv) / 100.0) + 0.05, "intentional walk slows the runner to a walk")
	await _wait(2.0)
	ok((not is_instance_valid(walker) or (not walker.alive and walker.runs == 0)) and int(runs_seen[0]) == 0, "a walked runner that reaches home scores no run")
	battle.run.shields = 0
	var control := battle.spawn_enemy("runner", route, route.length - 0.4, {"lateral": 0.0, "hp_mult": 40.0})
	await _wait(0.6)
	ok((not is_instance_valid(control) or not control.alive) and int(runs_seen[0]) == 1, "an ordinary runner home still scores (control)")
	battle.run_scored.disconnect(on_run)
	_clear()
	await _wait(0.2)

	# Infield Fly: the first runner into the zone is out once the ball comes down; a boss is stunned.
	var fly_r := battle.spawn_enemy("runner", route, route.length * 0.4, {"lateral": 0.0, "hp_mult": 40.0})
	await _wait(0.05)
	var spot := route.position_at(fly_r.d + 3.0)
	battle.effects.execute("infield_fly", lv, {"point": spot, "valid": true})
	var caught_at := -1.0
	for i in 40:
		await _wait(0.1)
		if not battle.effects.active_item("infield_fly").is_empty() and battle.effects.active_item("infield_fly").victim != null and caught_at < 0.0:
			caught_at = i * 0.1
		if not fly_r.alive:
			break
	ok(caught_at >= 0.0 and not fly_r.alive and fly_r.hp <= 0.0, "infield fly calls out the first runner in the zone")
	var fly_b := battle.spawn_enemy("iron_slugger", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 1.0})
	fly_b.ability_t = 999.0
	await _wait(0.05)
	var fbh := fly_b.hp
	battle.effects.execute("infield_fly", lv, {"point": fly_b.global_position, "valid": true})
	await _wait(DB.card_param("infield_fly", "delay", lv) + 0.4)
	ok(fly_b.alive and fly_b.hp < fbh - 1.0 and fly_b.stun_t > 0.0, "a boss under an infield fly is damaged and stunned, not out")
	_clear()
	await _wait(0.2)

	# Golden Glove: the next runners within reach are put out; a boss uses a catch and is hurt.
	var gg: Defender = battle.defenders[0]
	for df in battle.defenders:
		if df.trait_id != "quick_hands":
			gg = df
			break
	var post0 := gg.post
	var gg_d := route.length * 0.45
	var side := route.direction_at(gg_d).cross(Vector3.UP).normalized()
	gg.place(route.position_at(gg_d) + side * 2.0)
	battle.effects.execute("golden_glove", lv, {"defender": gg, "valid": true})
	var g1 := battle.spawn_enemy("runner", route, gg_d - 6.0, {"lateral": 0.0, "hp_mult": 40.0})
	var g2 := battle.spawn_enemy("runner", route, gg_d - 9.0, {"lateral": 0.0, "hp_mult": 40.0})
	for i in 40:
		await _wait(0.1)
		if not g1.alive and not g2.alive:
			break
	var item := battle.effects.active_item("golden_glove", gg)
	ok(not g1.alive and not g2.alive and g1.hp <= 0.0, "golden glove puts out runners that come within reach")
	ok(not item.is_empty() and int(item.charges) == int(DB.card_param("golden_glove", "charges", lv)) - 2, "each catch uses a charge (%s left)" % str(item.get("charges", "?")))
	var gb := battle.spawn_enemy("iron_slugger", route, gg_d - 2.0, {"lateral": 0.0, "hp_mult": 1.0})
	gb.ability_t = 999.0
	var gbh := gb.hp
	await _wait(0.6)
	ok(gb.alive and gb.hp < gbh - 1.0 and battle.effects.active_item("golden_glove", gg).is_empty(), "a boss can't be caught: it is hurt and uses the last catch")
	gg.place(post0)
	_clear()
	await _wait(0.2)

	# The Shift: every defender slides toward the spot, throws faster, then returns to its post.
	var focus := route.position_at(route.length * 0.5)
	var before: Array = battle.defenders.map(func(df: Defender) -> float: return Field.v2(df.global_position).distance_to(Field.v2(focus)))
	battle.effects.execute("the_shift", lv, {"point": focus, "valid": true})
	await _wait(0.7)
	var closer := 0
	for i in battle.defenders.size():
		if Field.v2(battle.defenders[i].global_position).distance_to(Field.v2(focus)) < float(before[i]) - 1.0:
			closer += 1
	ok(closer >= battle.defenders.size() - 1, "the shift moves the defenders toward the spot (%d of %d)" % [closer, battle.defenders.size()])
	ok(battle.buff_active("shift") and battle.defenders[0].dyn_speed >= DB.card_param("the_shift", "speed_bonus", lv) - 0.01, "shifted defenders throw faster")
	await _wait(DB.card_param("the_shift", "duration", lv))
	var home := true
	for df in battle.defenders:
		home = home and df.global_position.distance_to(df.post) < 0.05
	ok(home and not battle.buff_active("shift"), "after the shift every defender is back on its post")
	_clear()
	await _wait(0.2)

	# Momentum: each out gives energy, up to the cap.
	battle.cards.infinite_energy = false
	battle.cards.energy = 0.0
	battle.effects.execute("momentum", lv, {"valid": true})
	var mom: Array = _spawn_pack(10)
	await _wait(0.1)
	for i in 2:
		mom[i].die({})
	ok(absf(battle.cards.energy - 2.0 * DB.card_param("momentum", "energy", lv)) < 0.2, "momentum: each out gives %.1f energy (%.2f)" % [DB.card_param("momentum", "energy", lv), battle.cards.energy])
	for i in range(2, 10):
		mom[i].die({})
	# (Triple plays and five-out combos pay +1 energy each on their own.)
	var mb: Array = battle.buffs.filter(func(b: Dictionary) -> bool: return b.kind == "momentum")
	ok(not mb.is_empty() and float(mb[0].left) <= 0.01 and battle.cards.energy <= DB.card_param("momentum", "max_energy", lv) + 2.3,
		"momentum stops at %d energy (%.2f with combo bonuses)" % [int(DB.card_param("momentum", "max_energy", lv)), battle.cards.energy])
	battle.cards.infinite_energy = true
	_clear()
	await _wait(0.2)

	# Relief Pitcher: a reliever comes in, throws at runners in range, then leaves.
	var rp_pack := _spawn_pack(3)
	await _wait(0.1)
	var rp_hp := 0.0
	for en in rp_pack:
		rp_hp += en.hp
	var dmg_rp0 := float(battle.run.card_impact.get("relief_pitcher", {}).get("damage", 0.0))
	battle.effects.execute("relief_pitcher", lv, {"point": rp_pack[1].global_position, "valid": true})
	await _wait(0.3)
	ok(not battle.effects.active_item("reliever").is_empty(), "a relief pitcher comes in")
	await _wait(3.0)
	var rp_after := 0.0
	for en in rp_pack:
		rp_after += maxf(en.hp, 0.0)
	ok(rp_after < rp_hp - DB.card_param("relief_pitcher", "damage", lv) * 2.0, "the reliever's throws hit runners (%.0f damage)" % (rp_hp - rp_after))
	ok(float(battle.run.card_impact.get("relief_pitcher", {}).get("damage", 0.0)) > dmg_rp0, "relief pitcher damage is credited to the card")
	await _wait(DB.card_param("relief_pitcher", "duration", lv) + 1.0)
	ok(battle.effects.active_item("reliever").is_empty(), "the reliever leaves when time is up")
	_clear()
	await _wait(0.2)

	# Instant Replay: replays the last non-Legendary card at one level higher; refunds when empty.
	battle.effects.last_play = {}
	battle.cards.infinite_energy = false
	battle.cards.energy = 1.0
	battle.effects.execute("instant_replay", lv, {"valid": true})
	ok(absf(battle.cards.energy - (1.0 + float(DB.card("instant_replay").cost))) < 0.05, "instant replay with nothing to replay refunds its energy")
	battle.cards.infinite_energy = true
	var ir := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 60.0, "speed_mult": 0.01})
	await _wait(0.1)
	battle.effects.execute("power_throw", 1, {"enemy": ir, "point": ir.global_position, "valid": true})
	await _wait(1.0)
	battle.effects.execute("perfect_game", 1, {"valid": true})
	ok(String(battle.effects.last_play.get("id", "")) == "power_throw", "a Legendary isn't recorded for Instant Replay")
	await _wait(1.5)
	var ih := ir.hp
	battle.effects.execute("instant_replay", lv, {"valid": true})
	await _wait(1.4)
	var want := DB.card_param("power_throw", "damage", 2)
	ok(ih - ir.hp >= want - 2.0 and ih - ir.hp <= want * 1.8, "instant replay throws the last card again, one level up (%.0f, want %.0f)" % [ih - ir.hp, want])
	_hold_fire(false)
	_clear()


## Update 8 tuning hooks in a live battle: per-mode boss health, the Home Guard assist statistic and
## Captain's Rally reading its per-level values from data/upgrades.json.
func _test_update8_battle() -> void:
	section("update 8 tuning hooks (battle)")
	_hold_fire(true)
	var route := battle.routes[0]
	# Boss health: a "boss_hp" entry in the mode's tuning scales that boss only.
	var mode: Dictionary = DB.mode(battle.run.mode_id)
	var had_tuning := mode.has("tuning")
	var old_tuning: Variant = mode.get("tuning", {})
	mode["tuning"] = {battle.run.difficulty_id: {"boss_hp": {"iron_slugger": 0.5}}}
	ok(is_equal_approx(WaveGenerator.boss_hp_tuning(battle.run, "iron_slugger"), 0.5) and is_equal_approx(WaveGenerator.boss_hp_tuning(battle.run, "grand_slammer"), 1.0),
		"boss_hp tuning can target one boss")
	var b := battle.spawn_enemy("iron_slugger", route, route.length * 0.3, {"lateral": 0.0, "hp_mult": 1.0, "speed_mult": 0.01})
	ok(absf(b.max_hp - float(DB.enemy("iron_slugger").hp) * 0.5) < 1.0, "a tuned boss spawns with that much health (%.0f)" % b.max_hp)
	mode["tuning"] = {"all": {"boss_hp": 0.8}}
	ok(is_equal_approx(WaveGenerator.boss_hp_tuning(battle.run, "phantom_captain"), 0.8), "a plain boss_hp number scales every boss")
	if had_tuning:
		mode["tuning"] = old_tuning
	else:
		mode.erase("tuning")
	ok(is_equal_approx(WaveGenerator.boss_hp_tuning(battle.run, "iron_slugger"), 1.0), "practice bosses are untuned")
	_clear()
	await _wait(0.1)
	# Home Guard assist: extra damage inside Rico's aura is credited to it in run.stats.assist_by.
	var rico: Defender = null
	for df in battle.defenders:
		if df.id == "rico":
			rico = df
	if rico:
		var e := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
		await _wait(0.1)
		rico.place(e.global_position + Vector3(1.5, 0, 0))
		await _wait(0.2)
		var before := float(battle.run.stats.get("assist_by", {}).get("home_guard", 0.0))
		var dealt := battle.deal_damage(e, 100.0, {"kind": "throw"})
		var after := float(battle.run.stats.get("assist_by", {}).get("home_guard", 0.0))
		ok(e.home_guard and after - before > 0.0 and absf((after - before) - dealt * 0.10 / 1.10) < 0.5,
			"Home Guard's +10 %% is credited as an assist (%.1f of %.1f)" % [after - before, dealt])
		battle.apply_formation(battle.run.formation)
	_clear()
	# Captain's Rally: each level adds the data's captain_damage to allies in the captain's radius.
	var fx: Dictionary = DB.upgrades.captains_rally.effect
	var cap: Defender = null
	for df in battle.defenders:
		if df.is_captain:
			cap = df
	if cap == null:
		cap = battle.defenders[0]
		battle.set_captain(cap)
	var ally: Defender = battle.defenders[1] if battle.defenders[0] == cap else battle.defenders[0]
	var ally_post := ally.post
	# Just outside the level-0 radius (6 m), inside the level-1 radius.
	ally.place(cap.post + Vector3(6.0 + float(fx.captain_radius) * 0.5, 0, 0))
	await _wait(0.15)
	var lvl0 := ally.dyn_damage
	battle.run.upgrades["captains_rally"] = 1
	await _wait(0.15)
	ok(lvl0 < 0.001 and absf(ally.dyn_damage - (0.08 + float(fx.captain_damage))) < 0.001,
		"Captain's Rally level 1 reaches %.1f m and gives +%d %% (%.2f -> %.2f)" % [6.0 + float(fx.captain_radius),
		roundi(100.0 * (0.08 + float(fx.captain_damage))), lvl0, ally.dyn_damage])
	battle.run.upgrades.erase("captains_rally")
	ally.place(ally_post)
	_hold_fire(false)


## Update 7 content outside battle: collection, saves, packs, roles.
func test_update7_content() -> void:
	section("update 7 cards (data)")
	for id in DB.card_order:
		ok(String(DB.card(id).get("role", "")) in ROLES, "%s has a deck-builder role (%s)" % [id, DB.card(id).get("role", "")])
	Profile.reset_profile()
	for id in NEW_CARDS_U7:
		ok(DB.cards.has(id), "Update 7 card %s defined" % id)
		ok(Profile.data.cards.has(id) and not Profile.is_card_owned(id), "fresh profile lists %s, not owned" % id)
		ok(DB.combos_for(id).size() > 0, "%s has a combo" % id)
		var details := str(DB.card(id).get("details", ""))
		for key in DB.card(id).params.keys():
			details = details.replace("{%s}" % key, "1")
		ok(details != "" and not "{" in details, "%s has details text with resolvable values" % id)
	var old: Dictionary = Profile.data.duplicate(true)
	for id in NEW_CARDS_U7:
		old.cards.erase(id)
	old.cards.curveball.owned = true
	var f := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	var all_there := true
	for id in NEW_CARDS_U7:
		all_there = all_there and Profile.data.cards.has(id) and not Profile.is_card_owned(id)
	ok(all_there and Profile.is_card_owned("curveball"), "an existing save gains the Update 7 cards as not owned")
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var seen := {}
	for i in 600:
		for cid in Profile.roll_pack("champion", rng):
			seen[cid] = true
	for id in NEW_CARDS_U7:
		ok(seen.has(id), "packs can contain %s" % id)
	Profile.reset_profile()


# ---------------------------------------------------------------- Update 9 (stream C: modes, boons, hooks)

## Battle hooks for the other streams: runner_out once per out (after it is scored), the out coin
## bonus and add_energy.
func _test_update9_battle() -> void:
	section("update 9 battle hooks (runner_out, coin bonus, energy)")
	_hold_fire(true)
	var route := battle.routes[0]
	var outs_seen: Array = []
	var cb := func(en: Enemy, info: Dictionary) -> void:
		outs_seen.append([en, info, battle.run.outs_total])
	battle.runner_out.connect(cb)
	var pack: Array = []
	for i in 3:
		pack.append(battle.spawn_enemy("runner", route, route.length * 0.4 + i * 0.5, {"lateral": 0.0, "hp_mult": 1.0, "speed_mult": 0.01}))
	await _wait(0.1)
	var outs0 := battle.run.outs_total
	(pack[0] as Enemy).apply_mark(5.0, 0.2)
	battle.deal_damage(pack[0], 99999.0, {"source": battle.defenders[0], "kind": "throw", "card": "power_throw"})
	battle.deal_damage(pack[1], 99999.0, {"kind": "fire"})
	(pack[2] as Enemy).die({})
	await _wait(0.1)
	ok(outs_seen.size() == 3 and battle.run.outs_total == outs0 + 3, "runner_out fires once per out (%d signals, %d outs)" % [outs_seen.size(), battle.run.outs_total - outs0])
	if outs_seen.size() == 3:
		var i0: Dictionary = outs_seen[0][1]
		ok(outs_seen[0][0] == pack[0] and int(outs_seen[0][2]) == outs0 + 1, "runner_out comes after the out is scored")
		ok(i0.get("defender") == battle.defenders[0] and i0.get("source") == battle.defenders[0] and str(i0.get("card")) == "power_throw" and bool(i0.get("marked")),
			"runner_out info names the defender, the card and the mark (%s)" % [i0])
		var i1: Dictionary = outs_seen[1][1]
		ok(i1.get("defender") == null and str(i1.get("card")) == "" and not bool(i1.get("marked")) and i1.has("source"), "runner_out info for a sourceless out")
	# A decoy is not a runner: no signal.
	outs_seen.clear()
	var dec := battle.spawn_enemy("decoy", route, route.length * 0.4, {"lateral": 0.0})
	dec.die({})
	ok(outs_seen.is_empty(), "a vanishing decoy is not an out")
	# Base Shield out at the plate: one signal, kind "plate".
	battle.practice_invulnerable = true
	battle.run.shields = 1
	outs_seen.clear()
	battle.spawn_enemy("runner", route, route.length - 0.2, {"lateral": 0.0})
	await _wait(0.4)
	ok(outs_seen.size() == 1 and str(outs_seen[0][1].get("kind")) == "plate", "a Base Shield out at the plate fires runner_out (%d)" % outs_seen.size())
	battle.runner_out.disconnect(cb)
	# Out coin bonus: (1 + bonuses) per out; fractions carry over; timed bonuses expire.
	var base_mult := battle.out_coin_mult()
	battle.add_out_coin_bonus(1.0, 5.0)
	ok(is_equal_approx(battle.out_coin_mult(), base_mult + 1.0), "add_out_coin_bonus adds to the coin multiplier (%.2f)" % battle.out_coin_mult())
	var coins0 := battle.run.coins
	var r1 := battle.spawn_enemy("runner", route, route.length * 0.4, {"lateral": 0.0, "speed_mult": 0.01})
	var expect := float(r1.coins) * battle.out_coin_mult()
	battle.combo_timer = 0.0   # no combo bonus coins in these checks
	r1.die({})
	ok(absf(float(battle.run.coins - coins0) - expect) <= 1.0, "an out pays coins x the multiplier (%d, expected %.1f)" % [battle.run.coins - coins0, expect])
	battle._update_buffs(5.5)
	ok(is_equal_approx(battle.out_coin_mult(), base_mult), "a timed coin bonus expires")
	battle.add_out_coin_bonus(0.25, 0.0)
	battle._update_buffs(100.0)
	ok(is_equal_approx(battle.out_coin_mult(), base_mult + 0.25), "a coin bonus with no time lasts the game")
	battle._coin_bonuses.clear()
	# +25 % on 2-coin runners pays over several outs (fractions carry).
	battle.add_out_coin_bonus(0.25, 0.0)
	coins0 = battle.run.coins
	var paid_base := 0.0
	for i in 8:
		var rr := battle.spawn_enemy("runner", route, route.length * 0.4, {"lateral": 0.0, "speed_mult": 0.01})
		paid_base += float(rr.coins) * base_mult
		battle.combo_timer = 0.0
		rr.die({})
	ok(float(battle.run.coins - coins0) >= paid_base * 1.2, "a +25 %% coin bonus pays on small runners too (%d vs %.0f base)" % [battle.run.coins - coins0, paid_base])
	battle._coin_bonuses.clear()
	# add_energy: capped at the maximum.
	battle.cards.infinite_energy = false
	battle.cards.energy = 2.0
	battle.add_energy(1.5)
	ok(is_equal_approx(battle.cards.energy, 3.5), "add_energy adds energy")
	battle.add_energy(50.0)
	ok(is_equal_approx(battle.cards.energy, CardSystem.MAX_ENERGY), "add_energy caps at the maximum")
	battle.cards.infinite_energy = true
	_hold_fire(false)
	await _test_update9_boons()
	_clear()
	await _test_update9_draft()


## Dugout Draft data, offers, run state and save/resume; Boss Rush plan; Endless milestones.
func test_update9_modes() -> void:
	section("update 9 modes: boons data, offers, save/resume, Boss Rush, milestones")
	var all := Boons.all()
	ok(all.size() >= 18, "at least 18 boons (%d)" % all.size())
	var rar := {}
	var ids := {}
	var fields_ok := true
	for b: Dictionary in all:
		rar[str(b.rarity)] = int(rar.get(str(b.rarity), 0)) + 1
		ids[str(b.id)] = true
		if str(b.get("name", "")) == "" or str(b.get("text", "")) == "" or DB.icon(str(b.get("icon", ""))) == null \
				or not (b.rarity in Boons.RARITY_ORDER) or (b.get("effect", {}) as Dictionary).is_empty():
			fields_ok = false
			print("  bad boon ", b)
	ok(fields_ok, "every boon has a name, text, an existing icon, a rarity and an effect")
	ok(ids.size() == all.size(), "boon ids are unique")
	ok(rar.get("common", 0) > rar.get("rare", 0) and rar.get("rare", 0) > rar.get("epic", 0) and rar.get("epic", 0) >= 2, "three rarities, commons most (%s)" % rar)
	ok(Boons.rarity_weight("common") > Boons.rarity_weight("rare") and Boons.rarity_weight("rare") > Boons.rarity_weight("epic"), "rarer boons are offered less often")
	var r := RunState.create(_cfg("standard"))
	r.deck = Profile.STARTER_DECK.duplicate()
	var rng := RandomNumberGenerator.new()
	var three_ok := true
	var never_taken := true
	var seen := {}
	var rare_plus := 0
	for i in 200:
		rng.seed = 1000 + i
		r.boons = [all[i % all.size()].id, all[(i * 7) % all.size()].id]
		var o := Boons.offer(r, rng)
		var uniq := {}
		for id in o:
			uniq[id] = true
			seen[id] = true
			if id in r.boons:
				never_taken = false
		if o.size() != 3 or uniq.size() != 3:
			three_ok = false
		if o.any(func(id: String) -> bool: return Boons.get_boon(id).rarity != "common"):
			rare_plus += 1
	ok(three_ok, "an offer is three different boons")
	ok(never_taken, "offers never repeat a boon already taken")
	ok(seen.size() == all.size(), "every boon shows up in offers (%d of %d)" % [seen.size(), all.size()])
	ok(rare_plus == 200, "every offer has at least one rare or epic boon (%d of 200)" % rare_plus)
	rng.seed = 42
	r.boons = []
	var o1 := Boons.offer(r, rng)
	rng.seed = 42
	ok(Boons.offer(r, rng) == o1, "offers are deterministic for a seed (a replayed inning offers the same)")
	var taken: Array = []
	for b: Dictionary in all:
		taken.append(b.id)
	r.boons = taken.slice(0, taken.size() - 2)
	ok(Boons.offer(r, rng).size() == 2, "with two boons left the offer has two")
	r.boons = taken.duplicate()
	ok(Boons.offer(r, rng).is_empty(), "with every boon taken there is no offer")
	# Useless boons are not offered.
	r.boons = []
	r.shields = 3
	ok(not Boons.available(r, "batting_helmet"), "no shield boon at 3 shields")
	r.shields = 1
	ok(Boons.available(r, "batting_helmet"), "the shield boon is offered below 3 shields")
	var deck_before := r.deck.duplicate()
	r.deck = ["power_throw", "heat_wave"]
	ok(not Boons.available(r, "glove_clinic") and Boons.available(r, "slugger_clinic"), "a card clinic needs a card of its categories in the deck")
	r.deck = deck_before
	# Run state: boons feed the run modifiers and card levels, and survive save/resume.
	var dmg0 := r.modifier_total("damage")
	var lvl0 := r.card_level("power_throw")
	var lvl_c0 := r.card_level("curveball")
	r.boons = ["heavy_lumber", "all_star_break", "slugger_clinic", "rally_caps", "fresh_arms"]
	ok(is_equal_approx(r.modifier_total("damage") - dmg0, 0.25), "boons add to the team damage modifier (+%.2f)" % (r.modifier_total("damage") - dmg0))
	ok(r.card_level("power_throw") == lvl0 + 1 and r.card_level("curveball") == lvl_c0, "a card clinic raises its categories only")
	ok(r.modifier_total("card_cooldown") < -0.2 and r.modifier_total("coin_mult") >= 0.3, "cooldown and coin boons feed the modifiers")
	r.milestones = [5, 10]
	var back := RunState.from_dict(JSON.parse_string(JSON.stringify(r.to_dict())))
	ok(back.boons == r.boons and back.milestones == [5, 10], "boons and milestones survive save/resume (%s %s)" % [back.boons, back.milestones])
	ok(is_equal_approx(back.modifier_total("damage"), r.modifier_total("damage")) and back.card_level("power_throw") == r.card_level("power_throw"),
		"boon effects are the same after resume")
	ok(back.stats.has("time"), "run stats keep the game time")
	var summ := Boons.summary(["heavy_lumber", "nope", "extra_innings"])
	ok(summ.size() == 2 and summ[1].rarity == "epic" and summ[0].has("icon") and summ[0].has("text"), "Boons.summary skips unknown ids")
	# Draft modes.
	ok(bool(DB.mode("standard").get("draft", false)) and bool(DB.mode("endless").get("draft", false)) and bool(DB.mode("boss_rush").get("draft", false)),
		"Standard Siege, Endless and Boss Rush hold a draft after bosses")
	ok(not bool(DB.mode("quick").get("draft", false)) and not bool(DB.mode("daily").get("draft", false)) and not bool(DB.mode("ranked").get("draft", false)),
		"Quick, Daily and Promotion games have no draft")
	# Boss Rush: three innings, each ending with a tougher boss.
	var br := RunState.create(_cfg("boss_rush"))
	ok(br.max_innings == 3 and br.waves_per_inning >= 2, "Boss Rush is three innings")
	var bosses := ["iron_slugger", "phantom_captain", "grand_slammer"]
	var plan_ok := true
	var last_hp := 0.0
	var rising := true
	for i in 3:
		br.inning = i + 1
		ok(br.boss_for_inning(i + 1) == bosses[i], "Boss Rush inning %d ends with %s" % [i + 1, bosses[i]])
		for w in br.waves_per_inning:
			var wv := WaveGenerator.generate(br, w, 3)
			var want: String = bosses[i] if w == br.waves_per_inning - 1 else ""
			if str(wv.boss) != want:
				plan_ok = false
		# The boss's real health: data health x its share of the inning scaling x the mode's boss tuning (Enemy.setup).
		var hp := float(DB.enemy(bosses[i]).hp) * (1.0 + (WaveGenerator.hp_multiplier(br) - 1.0) * 0.45) * WaveGenerator.boss_hp_tuning(br, bosses[i])
		rising = rising and hp > last_hp
		last_hp = hp
	ok(plan_ok, "Boss Rush: only each inning's last wave has the boss")
	ok(rising, "Boss Rush bosses get tougher every inning")
	# Endless milestones: every 5th inning cleared.
	var en := RunState.create(_cfg("endless"))
	var got: Array = []
	for i in range(1, 21):
		en.inning = i
		if en.note_milestone():
			got.append(i)
	ok(got == [5, 10, 15, 20] and en.milestones == [5, 10, 15, 20], "Endless milestones every 5 innings (%s)" % [en.milestones])
	en.inning = 10
	en.note_milestone()
	ok(en.milestones.size() == 4, "a milestone is recorded once")
	var st := RunState.create(_cfg("standard"))
	st.inning = 5
	ok(not st.note_milestone() and st.milestones.is_empty(), "no milestones outside Endless")


## Each boon really applies in a battle (practice field, defenders holding their throws).
func _test_update9_boons() -> void:
	section("update 9 boons apply in battle")
	_hold_fire(true)
	var run := battle.run
	var keep_shields := run.shields
	var keep_limit := run.run_limit
	run.boons.clear()
	battle._refresh_team_stats()
	battle.cards.infinite_energy = false
	var df: Defender = battle.defenders[0]
	var route := battle.routes[0]
	var applied := {}
	for b: Dictionary in Boons.all():
		var id := str(b.id)
		run.boons.clear()
		run.shields = 1
		run.run_limit = keep_limit
		battle._refresh_team_stats()
		var before := {"dmg": df.s_damage, "int": df.s_interval, "rng": df.s_range, "crit": df.s_crit, "regen": battle.cards.regen_mult,
			"draw": battle.cards.draw_interval, "cd": battle.cards.cooldown_mult, "coin": battle.out_coin_mult(), "shields": run.shields,
			"limit": run.run_limit, "lvl_pt": run.card_level("power_throw"), "lvl_cb": run.card_level("curveball")}
		Boons.apply(battle, id)
		ok(id in run.boons, "%s is recorded in run.boons" % id)
		var eff: Dictionary = b.effect
		var good := true
		if eff.has("damage"):
			good = good and df.s_damage > before.dmg * 1.05
		if eff.has("attack_speed"):
			good = good and df.s_interval < before.int * 0.95
		if eff.has("range"):
			good = good and df.s_range > before.rng * 1.05
		if eff.has("crit"):
			good = good and df.s_crit > before.crit + 0.05
		if eff.has("energy_regen"):
			good = good and battle.cards.regen_mult > before.regen * 1.1
		if eff.has("draw_speed"):
			good = good and battle.cards.draw_interval < before.draw * 0.9
		if eff.has("card_cooldown"):
			good = good and battle.cards.cooldown_mult < before.cd - 0.2
		if eff.has("coin_mult"):
			good = good and battle.out_coin_mult() > before.coin + 0.2
		if eff.has("shield"):
			good = good and run.shields == before.shields + 1
		if eff.has("run_limit"):
			good = good and run.run_limit == before.limit + 1
		if eff.has("card_level"):
			var cats: Array = eff.categories
			good = good and (run.card_level("power_throw") == before.lvl_pt + 1) == ("offense" in cats) \
				and (run.card_level("curveball") == before.lvl_cb + 1) == ("control" in cats)
		if eff.has("wave_energy") or eff.has("wave_draw") or eff.has("first_card_refund"):
			battle.cards.energy = 2.0
			battle.cards.hand = ["power_throw", "", "", "", ""]
			battle.cards.draw_pile = ["curveball", "heat_wave", "lockdown"]
			battle._wave_start_bonuses(false)
			var e_after := battle.cards.energy
			var h_after := battle.cards.hand_count()
			if eff.has("wave_energy"):
				good = good and is_equal_approx(e_after, 3.0 + float(eff.wave_energy))
			if eff.has("wave_draw"):
				good = good and h_after == 1 + int(eff.wave_draw)
			if eff.has("first_card_refund"):
				var st := battle.state
				battle.state = "wave"
				battle.cards.energy = 2.0
				battle.on_card_played("power_throw")
				var first := battle.cards.energy
				battle.on_card_played("curveball")
				good = good and is_equal_approx(first, 2.0 + float(eff.first_card_refund)) and is_equal_approx(battle.cards.energy, first)
				battle.state = st
		if eff.has("home_slow"):
			# A runner a few metres from home (inside the radius) and one at the gate.
			var nd := route.length - 2.0
			for k in 60:
				if Field.v2(route.position_at(route.length - k * 0.25)).distance_to(Field.v2(Field.HOME)) > float(eff.home_radius) - 2.0:
					nd = route.length - k * 0.25
					break
			var near := battle.spawn_enemy("runner", route, nd, {"lateral": 0.0, "speed_mult": 0.01, "hp_mult": 40.0})
			var far := battle.spawn_enemy("runner", route, 1.0, {"lateral": 0.0, "speed_mult": 0.01, "hp_mult": 40.0})
			await _wait(0.05)
			battle._update_buffs(0.0)
			var with_boon := near.zone_slow
			run.boons.erase(id)
			battle._update_buffs(0.0)
			var without := near.zone_slow
			run.boons.append(id)
			battle._update_buffs(0.0)
			good = good and with_boon >= float(eff.home_slow) - 0.001 and (without < float(eff.home_slow) - 0.001 or near.home_guard) and far.zone_slow < 0.001
			_clear()
		if eff.has("boss_damage"):
			var boss := battle.spawn_enemy("iron_slugger", route, route.length * 0.3, {"lateral": 0.0, "hp_mult": 1.0, "speed_mult": 0.01})
			boss.ability_t = 999.0
			var mook := battle.spawn_enemy("runner", route, route.length * 0.3, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
			await _wait(0.05)
			battle._update_buffs(0.0)
			var bd := battle.deal_damage(boss, 100.0, {"kind": "throw", "pierce": 1.0})
			var md := battle.deal_damage(mook, 100.0, {"kind": "throw", "pierce": 1.0})
			good = good and bd > md * (1.0 + float(eff.boss_damage)) - 1.0 and boss.aura_dr < 0.0
			_clear()
		applied[id] = good
		ok(good, "boon %s has its effect" % id)
	run.boons.clear()
	run.shields = keep_shields
	run.run_limit = keep_limit
	battle._refresh_team_stats()
	battle.cards.infinite_energy = true
	ok(applied.size() == Boons.all().size(), "every boon was applied (%d)" % applied.size())
	# A boon is taken once.
	Boons.apply(battle, "heavy_lumber")
	Boons.apply(battle, "heavy_lumber")
	ok(run.boons.count("heavy_lumber") == 1, "a boon is never stacked twice")
	run.boons.clear()
	battle._refresh_team_stats()
	_hold_fire(false)


## The draft holds the game, offers three boons, takes one (from the overlay too) and goes on.
func _test_update9_draft() -> void:
	section("update 9 Dugout Draft flow (battle)")
	var run := battle.run
	run.boons.clear()
	var st0 := battle.state
	var opened: Array = []
	var cb := func(o: Array) -> void: opened.append(o)
	battle.draft_opened.connect(cb)
	var continued := [0]
	# The first draft ever shows the "battle_boons" tip (hints are on for this check; not on the
	# Practice Field, so the battle plays a normal game until the cards are up).
	Hints.force_enabled = true
	var hs: Dictionary = Profile.data.flags.get_or_add("hints_seen", {})
	hs.erase("battle_boons")
	battle.practice = false
	battle.open_draft(func() -> void: continued[0] += 1)
	ok(battle.state == "draft" and battle.draft_offers.size() == 3 and opened.size() == 1, "open_draft holds the game with three offers")
	ok(not battle.choose_boon("not_a_boon"), "an id that is not on offer is refused")
	var e0 := battle.cards.energy
	battle.select_card(0)
	ok(battle.targeting_index == -1, "no cards can be aimed during the draft")
	# The overlay appears after the boss finale.
	var ov: Node = null
	for i in 60:   # the cards come up DRAFT_DELAY game seconds later
		await _wait(0.1)
		ov = battle.hud.get("_draft")
		if ov and is_instance_valid(ov):
			break
	await _wait(0.4)
	ok(ov != null and is_instance_valid(ov) and (ov.get("cards") as Array).size() == 3, "the draft overlay shows three cards")
	if Hints.HINTS.has("battle_boons"):
		for i in 30:
			if Hints.is_showing():
				break
			await _wait(0.1)
		ok(Hints.current_id() == "battle_boons", "the first draft shows the Dugout Draft tip (%s)" % Hints.current_id())
		if Hints.current():
			Hints.current().queue_free()
	Hints.force_enabled = false
	battle.practice = true
	var pick: String = battle.draft_offers[1]
	var stat0 := Profile.stat("boons_drafted")
	battle.practice = false   # boons_drafted counts outside the Practice Field
	if ov and is_instance_valid(ov):
		ov.pick(pick)
	else:
		battle.choose_boon(pick)
	battle.practice = true
	ok(pick in run.boons and battle.draft_offers.is_empty(), "picking a card takes that boon (%s)" % pick)
	ok(continued[0] == 1, "the game continues once after the pick")
	ok(Profile.stat("boons_drafted") == stat0 + 1, "boons_drafted is counted")
	ok(not battle.choose_boon(pick), "a second pick is ignored")
	await _wait(1.2)
	ok(battle.hud.get("_draft") == null or not is_instance_valid(battle.hud.get("_draft")), "the overlay closes after the pick")
	await _wait(0.1)
	# The HUD lists the boon as a chip with its text as the tooltip.
	battle.hud.refresh()
	var chips: Node = battle.hud.get("_boon_box")
	var chip: Control = chips.get_node_or_null("Boon_" + pick) if chips else null
	ok(chip != null and str(chip.tooltip_text).contains(str(Boons.get_boon(pick).text)), "the HUD shows the boon as a chip with a tooltip")
	battle.draft_opened.disconnect(cb)
	battle.set_state(st0)
	run.boons.clear()
	battle._refresh_team_stats()
	battle.cards.energy = e0
	# Early call: NEXT WAVE NOW during a break pays +1 energy on top of the wave's +1 (and bonus coins).
	battle.practice = false
	battle.cards.infinite_energy = false
	battle.set_state("break")
	battle.break_timer = 9.0
	battle.cards.energy = 2.0
	var calls0 := int(run.stats.get("early_calls", 0))
	var coins0 := run.coins
	battle.begin_wave()
	ok(battle.state == "wave" and is_equal_approx(battle.cards.energy, 3.0 + Battle.EARLY_CALL_ENERGY),
		"an early call gives +%d energy on top of the wave's +1 (%.1f from 2.0)" % [int(Battle.EARLY_CALL_ENERGY), battle.cards.energy])
	ok(int(run.stats.get("early_calls", 0)) == calls0 + 1 and run.coins >= coins0 + 9, "an early call is counted and pays bonus coins")
	battle.spawn_queue.clear()
	battle.set_state("break")
	battle.break_timer = 0.2
	battle.cards.energy = 2.0
	battle.begin_wave()
	ok(is_equal_approx(battle.cards.energy, 3.0) and int(run.stats.get("early_calls", 0)) == calls0 + 1, "a wave started when the break is over is not an early call")
	battle.spawn_queue.clear()
	for gid in battle.stadium.gates.keys():
		battle.stadium.set_gate_open(gid, false)
	battle.practice = true
	battle.cards.infinite_energy = true
	battle.set_state(st0)


# ---------------------------------------------------------------- Update 9: new defenders (Stream A)

const U9_DEFENDERS := ["moose", "rosa", "sid"]
const U9_CLIPS := ["idle", "run", "hit", "stunned", "defeat", "celebrate", "ready", "throw", "pitch", "catch",
	"special", "victory", "walk"]


## Moose, Rosa and Sid: real models (not the placeholders) with every defender clip at the shared
## lengths, portraits and data.
func test_update9_models() -> void:
	section("update 9 defenders: models and data")
	var lengths := {"idle": 2.0, "run": 0.7, "throw": 0.75, "pitch": 1.4, "catch": 0.6, "special": 1.2, "victory": 2.0}
	var heights := {}
	for id in U9_DEFENDERS + ["bruno", "ace"]:
		ok(CharacterModel.has_model(id), "%s has a model" % id)
		var cm := CharacterModel.new()
		add_child(cm)
		cm.setup(id, {"base": "idle"})
		heights[id] = cm.height
		if id in U9_DEFENDERS:
			var missing: Array = U9_CLIPS.filter(func(c: String) -> bool: return not cm.has_anim(c))
			ok(missing.is_empty(), "%s model has every defender clip (missing %s)" % [id, missing])
			var off := []
			for c in lengths:
				if absf(cm.anim_length(c) - float(lengths[c])) > 0.04:
					off.append("%s %.2f" % [c, cm.anim_length(c)])
			ok(off.is_empty(), "%s clip lengths match the other defenders (%s)" % [id, off])
			ok(DB.portrait(id) != null, "%s has a portrait" % id)
		cm.free()
	ok(float(heights.moose) > float(heights.bruno), "Moose is the biggest defender (%.2f vs Bruno %.2f m)" % [heights.moose, heights.bruno])
	for pair in [["moose", "bruno"], ["rosa", "rico"], ["sid", "nova"]]:
		ok(FileAccess.get_md5("res://assets/models/characters/%s.glb" % pair[0]) != FileAccess.get_md5("res://assets/models/characters/%s.glb" % pair[1]),
			"%s has its own model (not the %s placeholder)" % pair)
	var want := {"moose": ["infielder", "long_stretch", 15, 5000, "scoop_and_tag"],
		"rosa": ["catcher", "pitch_framing", 20, 7500, "signal_caller"], "sid": ["pitcher", "skipper", 25, 10000, "worm_burner"]}
	for id in want:
		var d := DB.defender(id)
		var w: Array = want[id]
		ok(d.role == w[0] and d.trait.id == w[1] and int(d.unlock.value) == w[2] and int(d.unlock.get("coins", 0)) == w[3],
			"%s: %s, %s, unlock at level %d or %d coins" % [id, w[0], w[1], w[2], w[3]])
		ok(d.signature == w[4] and DB.cards.has(w[4]) and String(DB.card(w[4]).get("linked", "")) == id,
			"%s's signature card is %s" % [id, w[4]])
		ok(String(d.get("bio", "")).length() > 30 and String(d.get("title", "")) != "" and String(d.trait.get("text", "")).length() > 30,
			"%s has a title, bio and trait text" % id)


func _defender(id: String) -> Defender:
	for df in battle.defenders:
		if df.id == id:
			return df
	return null


## Long Stretch, Pitch Framing and Skipper in a live battle (defenders hold their throws).
func _test_update9_defenders() -> void:
	section("update 9 defenders: Long Stretch, Pitch Framing, Skipper (battle)")
	var route := battle.routes[0]
	_hold_fire(true)
	await _wait(0.1)

	# --- Long Stretch (Moose): runners within 5 m take +25 % damage and are 10 % slower.
	battle.swap_defender(_defender("jax"), "moose")
	var moose := _defender("moose")
	ok(moose != null and moose.trait_id == "long_stretch", "Moose joins the field")
	_hold_fire(true)
	var near := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	var far := battle.spawn_enemy("runner", route, route.length * 0.15, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	await _wait(0.1)
	moose.place(near.global_position + Vector3(3.0, 0, 0))
	await _wait(0.3)
	var far_d := Field.v2(far.global_position).distance_to(Field.v2(moose.global_position))
	ok(near.slows.has("long_stretch") and is_equal_approx(float(near.slows.long_stretch[0]), 0.10)
		and absf(near.current_speed() / near.base_speed - 0.9) < 0.01, "Long Stretch slows a runner 3 m away by 10 %% (speed x%.2f)" % (near.current_speed() / near.base_speed))
	ok(absf(near.aura_vuln - 0.25) < 0.001 and near.aura_vuln_t > 0.0, "Long Stretch gives it +25 %% damage taken (%.2f)" % near.aura_vuln)
	ok(far_d > 5.0 and not far.slows.has("long_stretch") and far.aura_vuln_t <= 0.0, "a runner %.1f m away is not affected" % far_d)
	var dn := battle.deal_damage(near, 100.0, {"kind": "throw"})
	var dfar := battle.deal_damage(far, 100.0, {"kind": "throw"})
	ok(absf(dn / dfar - 1.25) < 0.01, "a runner in Moose's ring takes +25 %% damage from any source (%.0f vs %.0f)" % [dn, dfar])
	ok(moose._aura_ring != null and moose._aura_ring.visible and absf(moose._aura_ring.scale.x - 5.0) < 0.01, "Moose shows a 5 m ring")
	# The ring adds to a card's mark instead of replacing it.
	near.apply_mark(2.0, 0.3)
	var dm := battle.deal_damage(near, 100.0, {"kind": "throw"})
	ok(absf(dm / dfar - 1.55) < 0.01, "Moose's ring stacks with a card mark (%.0f)" % dm)
	moose.stun(1.0)
	await _wait(0.45)
	ok(not moose._aura_ring.visible and not near.slows.has("long_stretch") and near.aura_vuln_t <= 0.0, "a stunned Moose has no ring")
	moose.cleanse()
	moose.place(near.global_position + Vector3(30.0, 0, 0))
	await _wait(0.45)
	ok(not near.slows.has("long_stretch") and near.aura_vuln_t <= 0.0, "leaving the ring ends the slow and the extra damage")
	battle.swap_defender(moose, "jax")
	_clear()
	await _wait(0.1)

	# --- Pitch Framing (Rosa): every 6 s the most dangerous runner is marked for 6 s (+35 % damage).
	battle.swap_defender(_defender("rico"), "rosa")
	var rosa := _defender("rosa")
	ok(rosa != null and rosa.trait_id == "pitch_framing", "Rosa joins the field")
	_hold_fire(true)
	rosa.frame_cd = 100.0
	var back := battle.spawn_enemy("runner", route, route.length * 0.3, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	var lead := battle.spawn_enemy("runner", route, route.length * 0.6, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	var mid := battle.spawn_enemy("runner", route, route.length * 0.45, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	await _wait(0.1)
	ok(rosa.most_dangerous_runner() == lead, "the most dangerous runner is the one closest to scoring")
	rosa.frame_cd = 0.0
	await _wait(0.15)
	ok(rosa.framed.has(lead) and absf(lead.signal_amt - 0.35) < 0.001 and lead.signal_t > 5.5 and absf(lead.signal_refund - 0.5) < 0.001,
		"Pitch Framing signals the lead runner for 6 s at +35 %% with a 0.5 energy refund (%.2f, %.1f s)" % [lead.signal_amt, lead.signal_t])
	ok(not rosa.framed.has(back) and back.signal_t <= 0.0 and rosa.frame_cd > 5.5, "only one runner per call; the next call is 6 s away (%.1f)" % rosa.frame_cd)
	var mk: Node3D = rosa.framed[lead][1] if rosa.framed.has(lead) else null
	ok(mk != null and mk.visible and mk.get_child_count() == 2 and Field.v2(mk.global_position).distance_to(Field.v2(lead.global_position)) < 0.3,
		"a framed runner wears Rosa's marker")
	var dl := battle.deal_damage(lead, 100.0, {"kind": "throw"})
	var db := battle.deal_damage(back, 100.0, {"kind": "throw"})
	ok(absf(dl / db - 1.35) < 0.01, "a framed runner takes +35 %% damage (%.0f vs %.0f)" % [dl, db])
	rosa.frame_cd = 0.0
	await _wait(0.15)
	ok(rosa.framed.has(mid) and not rosa.framed.has(back), "the next call picks the most dangerous runner not yet framed")
	# The refund is paid once by CardEffects (battle.runner_out, or its on_out fallback).
	battle.cards.infinite_energy = false
	battle.cards.energy = 2.0
	var e0: float = battle.cards.energy
	battle.combo_timer = 0.0   # no double/triple-play energy from earlier outs
	battle.deal_damage(lead, 1.0e7, {"kind": "throw"})
	var gain := battle.cards.energy - e0
	ok(gain >= 0.499 and gain < 0.6, "an out on a framed runner refunds 0.5 energy, once (%.2f)" % gain)
	e0 = battle.cards.energy
	battle.combo_timer = 0.0
	battle.deal_damage(back, 1.0e7, {"kind": "throw"})
	ok(battle.cards.energy - e0 < 0.1, "an out on an unframed runner refunds nothing (%.2f)" % (battle.cards.energy - e0))
	battle.cards.infinite_energy = true
	await _wait(0.1)
	ok(not rosa.framed.has(lead) and (not is_instance_valid(mk) or mk.is_queued_for_deletion()), "the marker goes away with the out")
	battle.swap_defender(rosa, "rico")
	_clear()
	await _wait(0.1)

	# --- Skipper (Sid): a hit skips on to one runner behind the target (within 4 m) for 60 %.
	battle.swap_defender(_defender("ace"), "sid")
	var sid := _defender("sid")
	ok(sid != null and sid.trait_id == "skipper", "Sid joins the field")
	_hold_fire(true)
	var tgt := battle.spawn_enemy("runner", route, route.length * 0.5, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	var behind := battle.spawn_enemy("runner", route, route.length * 0.5 - 2.0, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	var beyond := battle.spawn_enemy("runner", route, route.length * 0.5 - 9.0, {"lateral": 0.0, "hp_mult": 40.0, "speed_mult": 0.01})
	await _wait(0.1)
	var p: Dictionary = sid._build_payload(tgt, false)
	ok(is_equal_approx(float(p.get("skip", 0.0)), 0.6), "Sid's throws carry the skip (60 %)")
	var line := behind.global_position - tgt.global_position
	p.damage = 100.0
	p.crit = false
	p.accuracy = 999.0
	p["_dir"] = line
	var ht := tgt.hp
	var hb := behind.hp
	var hy := beyond.hp
	var dmg0 := sid.damage_dealt
	ok(battle.projectiles.hit(tgt, p, tgt.center()), "Sid's throw hits")
	await _wait(0.9)
	ok(absf((ht - tgt.hp) - 100.0) < 0.5, "the target takes the full hit (%.0f)" % (ht - tgt.hp))
	ok(absf((hb - behind.hp) - 60.0) < 0.5, "the ball skips on into the runner 2 m behind for 60 %% (%.0f)" % (hb - behind.hp))
	ok(is_equal_approx(hy, beyond.hp), "a runner %.1f m behind is out of the skip's reach" % Field.v2(beyond.global_position).distance_to(Field.v2(tgt.global_position)))
	ok(sid.damage_dealt - dmg0 > 159.0, "skip damage is credited to Sid (%.0f)" % (sid.damage_dealt - dmg0))
	# Thrown the other way, nothing is behind the target: no skip hit.
	var p2: Dictionary = sid._build_payload(tgt, false)
	p2.damage = 100.0
	p2.crit = false
	p2.accuracy = 999.0
	p2["_dir"] = -line
	hb = behind.hp
	battle.projectiles.hit(tgt, p2, tgt.center())
	await _wait(0.9)
	ok(is_equal_approx(hb, behind.hp), "no skip hit on a runner in front of the target")
	ok(battle.projectiles.skip_target(tgt, line, 4.0) == behind and battle.projectiles.skip_target(tgt, -line, 4.0) == null,
		"skip_target looks behind the target only")
	battle.swap_defender(sid, "ace")
	battle.apply_formation(battle.run.formation)
	_hold_fire(false)


# ---------------------------------------------------------------- Update 9 (stream E2): Team, Shop, Season, Packs, level road

func test_u9_e2_screens() -> void:
	section("Update 9 screens: Team, Shop, Season, Packs, level road")
	# Formatting helpers.
	ok(ShopScreen.format_countdown(3723) == "01:02:03", "shop countdown formats h:m:s (%s)" % ShopScreen.format_countdown(3723))
	ok(ShopScreen.format_countdown(-5) == "00:00:00", "shop countdown never goes negative")
	ok(SeasonScreen.format_left(11 * 86400 + 5 * 3600 + 59) == "11d 05h", "season countdown shows days and hours (%s)" % SeasonScreen.format_left(11 * 86400 + 5 * 3600 + 59))
	ok(SeasonScreen.format_left(3661) == "01:01:01", "season countdown shows h:m:s on the last day")
	# Season reward text and pictures for every reward shape.
	ok(SeasonScreen.reward_label({"coins": 1500}, true) == "1,500 coins", "season reward: coins")
	ok(SeasonScreen.reward_label({"pack": "pro"}, true) == "Pro Pack", "season reward: a pack")
	ok(SeasonScreen.reward_label({"pack": "rookie", "count": 2}, true) == "2 Rookie Packs", "season reward: two packs")
	ok(SeasonScreen.reward_label({"packs": ["champion"], "stars": 10}, true) == "Champion Pack + 10 stars", "season reward: pack list and stars")
	ok(SeasonScreen.reward_label({}, true) == "—", "season reward: empty")
	ok(SeasonScreen.reward_label({"uniform": DB.uniform_order[0]}, true).ends_with("uniform"), "season reward: uniform")
	for r in [{"coins": 100}, {"stars": 5}, {"pack": "champion"}, {"packs": ["rookie", "pro"]}, {"uniform": DB.uniform_order[0]}, {"card": DB.card_order[0], "copies": 2}]:
		var pic := SeasonScreen.reward_picture(r, 100)
		ok(pic != null and pic.get_child_count() == 1, "season reward picture for %s" % [r])
		pic.free()
	ok(SeasonScreen.is_big_reward({"pack": "champion"}) and not SeasonScreen.is_big_reward({"coins": 100}), "champion packs are the big rewards")
	# Shop helpers.
	var full := int(Profile.pack_price("pro", 1).coins)
	ok(ShopScreen._discount_pct({"kind": "pack", "pack": "pro", "price": {"coins": int(full * 0.75), "stars": 0}}) == 25, "pack deal discount is shown as -25%")
	ok(ShopScreen._discount_pct({"kind": "card", "card": DB.card_order[0], "price": {"coins": 60, "stars": 0}}) == 0, "card deals show no pack discount")
	ok(ShopScreen._discount_pct({"kind": "stars", "pack": "champion", "price": {"coins": 0, "stars": 40}, "full_price_stars": 50}) == 20, "star deal discount against its star price")
	ok(ShopScreen.deal_title({"kind": "gift", "title": "FREE GIFT", "reward": {"coins": 100}}) == "100 coins", "the gift tile names what is inside (%s)" % ShopScreen.deal_title({"kind": "gift", "title": "FREE GIFT", "reward": {"coins": 100}}))
	ok(ShopScreen.deal_title({"kind": "card", "card": "heat_wave", "title": ""}) == str(DB.card("heat_wave").name), "a card deal is titled with the card")
	ok(ShopScreen.is_free({"price": {"coins": 0, "stars": 0}}) and not ShopScreen.is_free({"price": {"coins": 10, "stars": 0}}), "free gift detection")
	Profile.data.coins = 100
	ok(ShopScreen.shortfall({"coins": 250}) == "Need 150 more coins", "shortfall names the missing coins")
	ok(ShopScreen.shortfall({"coins": 50}) == "", "no shortfall when affordable")
	var agents := Shop.free_agents()
	ok(agents.size() >= 3, "three free agents to sign (%d)" % agents.size())
	for a in agents:
		ok(ShopScreen.agent_info(str(a.id)).get("price", 0) == a.price, "agent_info finds %s" % a.id)
	# Team: every defender has a readable unlock line; free agents mention the price.
	var roster_script: GDScript = load("res://src/ui/roster_screen.gd")
	# Read from data/defenders.json: the unlock levels and prices are tuned there.
	var mu: Dictionary = DB.defender("moose").get("unlock", {})
	var moose_text := "Account level %d or sign for %s coins" % [int(mu.get("value", 0)), UITheme.format_int(int(mu.get("coins", 0)))]
	ok(str(roster_script.unlock_text("moose")) == moose_text, "Moose's unlock text (%s)" % roster_script.unlock_text("moose"))
	ok(str(roster_script.unlock_text("dex")) == "Reach account level %d" % int(DB.defender("dex").get("unlock", {}).get("value", 0)), "Dex's unlock text")
	# Packs: pity counter wording.
	var packs_script: GDScript = load("res://src/ui/packs_screen.gd")
	ok(str(packs_script.pity_text("Legendary", 12)) == "Legendary within 12 packs", "pity text counts packs")
	ok(str(packs_script.pity_text("Legendary", 1, "Pro or Champion Packs")) == "Legendary guaranteed in your next Pro or Champion Pack", "pity text for the last pack")
	ok(str(packs_script.pity_text("Legendary", 19, "Pro or Champion Packs")) == "Legendary within 19 Pro or Champion Packs", "pity text names the packs that count")
	ok(packs_script.pity_list({"pity": "epic"}) == ["epic"] and packs_script.pity_list({"pity": ["", "legendary"]}) == ["legendary"] and packs_script.pity_list({}).is_empty(), "pity results read as a list")
	# Level road: one short caption per level, no wrapping.
	for l in range(1, Profile.MAX_ACCOUNT_LEVEL + 1):
		var cap := LevelRoadView.caption(l)
		ok(cap != "" and cap.length() <= 18, "level %d caption is short (%s)" % [l, cap])
	var dex_level := int(DB.defender("dex").get("unlock", {}).get("value", 7))
	ok(LevelRoadView.caption(dex_level).ends_with("joins"), "a defender level says who joins (%s)" % LevelRoadView.caption(dex_level))
	# The screens build from the stubs or the real data.
	Profile.data.coins = 1000
	Profile.data.stars = 0
	for scene in ["res://scenes/shop.tscn", "res://scenes/season.tscn"]:
		var sc: Node = load(scene).instantiate()
		add_child(sc)
		await get_tree().process_frame
		await get_tree().process_frame
		if sc is ShopScreen:
			var shop := sc as ShopScreen
			ok(shop.pack_buttons.size() == 6, "Shop has BUY and BUY 10 for three packs (%d)" % shop.pack_buttons.size())
			ok(not (shop.pack_buttons["rookie:1"] as Button).disabled and (shop.pack_buttons["champion:1"] as Button).disabled, "pack buttons follow the wallet")
			ok(shop.agent_buttons.size() == agents.size(), "Shop lists every free agent")
			ok(shop.deal_buttons.size() == Shop.offers().size(), "Shop has one button per daily deal")
		else:
			var season := sc as SeasonScreen
			var tiers := Season.tiers()
			ok(season.tier_buttons.size() == (tiers.size() + 1 if not tiers.is_empty() else 0), "Season track has every tier and the bonus (%d)" % season.tier_buttons.size())
			ok((season.find_child("ClaimAll", true, false) as Button).disabled == Season.claimable().is_empty(), "CLAIM ALL is enabled only with rewards to claim")
		sc.queue_free()
		await get_tree().process_frame
	Profile.reset_profile()


# ---------------------------------------------------------------- Update 9: economy and return loop (stream D)

func test_update9_economy() -> void:
	_test_u9_season()
	_test_u9_login()
	_test_u9_streak_and_results()
	_test_u9_shop()
	_test_u9_free_agents()
	_test_u9_pity_overflow()
	_test_u9_promotion_modes()
	_test_u9_missions_and_saves()
	DailyChallenge.date_override = ""
	Profile.reset_profile()


## A finished game of `mode`.
func _u9_run(mode: String, inning: int, wave: int) -> RunState:
	var r := RunState.create(_cfg(mode))
	r.inning = inning
	r.wave = wave
	r.outs_total = 100
	r.coins_earned = 600
	return r


func _test_u9_season() -> void:
	section("Update 9: Season Pass")
	Profile.reset_profile()
	# Calendar: 14-day seasons from Monday 2026-11-02.
	DailyChallenge.date_override = "2026-11-02"
	var c := Season.current()
	ok(int(c.number) == 1 and int(c.id) == 1 and c.start == "2026-11-02" and c.end == "2026-11-15" and str(c.name) == "Season 1",
		"season 1 runs 2026-11-02 to 2026-11-15 (%s)" % [c])
	ok(int(c.seconds_left) > 13 * 86400 and int(c.seconds_left) <= 14 * 86400, "a new season has 14 days left (%d s)" % int(c.seconds_left))
	DailyChallenge.date_override = "2026-11-15"
	ok(int(Season.current().number) == 1 and int(Season.current().seconds_left) <= 86400, "the last day still belongs to season 1")
	DailyChallenge.date_override = "2026-11-16"
	ok(int(Season.current().number) == 2 and Season.current().start == "2026-11-16" and Season.current().end == "2026-11-29", "season 2 starts 2026-11-16")
	ok(Season.number_for("2027-01-11") == 6 and Season.number_for("2026-10-01") == 1, "season numbers follow the calendar (before the first season: 1)")
	ok(Season.uniform_for(1) == "season_1" and DB.uniforms.has(Season.uniform_for(2)) and Season.theme(1) != "", "every season has a uniform and a theme")
	ok(Season.countdown_text(3 * 86400 + 7200) == "3d 2h", "season countdown text")
	# XP and tiers.
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	ok(Season.xp() == 0 and Season.tier() == 0 and int(Profile.data.season.id) == 1, "a new profile starts season 1 at 0 XP")
	ok(Season.add_xp(499, "test").is_empty() and Season.tier() == 0, "499 XP is not a tier")
	ok(Season.add_xp(1, "test") == [1] and Season.tier() == 1, "500 XP reaches tier 1")
	var tp := Season.tier_progress()
	ok(int(tp.tier) == 1 and int(tp.xp_in) == 0 and int(tp.xp_need) == 500 and not bool(tp.bonus), "tier progress inside tier 1 (%s)" % [tp])
	ok(Season.add_xp(1200, "test") == [2, 3] and int(Season.tier_progress().xp_in) == 200, "1,200 XP more reaches tiers 2 and 3")
	var ts := Season.tiers()
	ok(ts.size() == 30 and bool(ts[2].reached) and not bool(ts[3].reached) and not bool(ts[0].claimed), "tiers() lists 30 tiers with reached flags")
	var all_ok := true
	for t in ts:
		all_ok = all_ok and not (t.reward as Dictionary).is_empty() and str(t.text) != "" and t.has("tier") and t.has("claimed")
	ok(all_ok, "every tier has a reward and a text")
	ok("champion" in Season.tier_reward(15).get("packs", []) and "champion" in Season.tier_reward(30).get("packs", []), "Champion Packs at tiers 15 and 30")
	ok(str(Season.tier_reward(30).get("uniform", "")) == "season_1", "tier 30 pays the season 1 uniform")
	var kinds := {"coins": false, "packs": false, "stars": false}
	for t in ts:
		for k in kinds.keys():
			kinds[k] = bool(kinds[k]) or (t.reward as Dictionary).has(k)
	ok(kinds.values().all(func(v: bool) -> bool: return v), "tier rewards mix coins, packs and stars")
	ok(Season.claimable() == [1, 2, 3], "reached tiers are claimable (%s)" % [Season.claimable()])
	ok(Season.claim(5).is_empty(), "a tier not reached cannot be claimed")
	var coins := int(Profile.data.coins)
	var cl := Season.claim(1)
	ok(int(cl.get("tier", 0)) == 1 and int(Profile.data.coins) == coins + 200, "claiming tier 1 pays 200 coins")
	ok(Season.claim(1).is_empty() and int(Profile.data.coins) == coins + 200, "a tier is claimed once")
	var packs := Profile.pack_count("rookie")
	var all := Season.claim_all()
	ok(all.size() == 2 and Profile.pack_count("rookie") == packs + 1 and int(Profile.data.coins) == coins + 450 and Season.claimable().is_empty(),
		"claim_all pays tiers 2 and 3")
	ok(Season.tiers()[0].claimed and Season.tiers()[2].claimed, "claimed tiers are marked")
	# Tier 30, the season uniform, bonus Pro Packs.
	var reached := Season.add_xp(Season.TIERS * Season.XP_PER_TIER - Season.xp(), "test")
	ok(reached.size() == 27 and int(reached[-1]) == 30 and Season.tier() == 30, "tier 30 at 15,000 XP")
	ok(not Season.claim(30).is_empty() and "season_1" in Profile.data.uniforms_owned, "claiming tier 30 adds the season uniform")
	ok(str(Season.tiers()[29].reward.get("uniform", "")) == "season_1", "a claimed tier 30 still shows its uniform")
	ok(not Profile.uniform_for_sale("season_1") and not Profile.buy_uniform("season_2") and Profile.uniform_for_sale("retro"), "season uniforms are never sold")
	Profile.data.stars = 100
	ok(Profile.buy_uniform("retro") and "retro" in Profile.data.uniforms_owned and int(Profile.data.stars) == 70, "a normal uniform is bought with stars")
	var pros := Profile.pack_count("pro")
	ok(Season.add_xp(999, "test").is_empty() and Season.add_xp(1, "test") == [31] and Profile.pack_count("pro") == pros + 1, "after tier 30, every 1,000 XP pays a Pro Pack")
	ok(bool(Season.tier_progress().bonus) and int(Season.tier_progress().xp_need) == 1000 and int(Profile.data.season.bonus_claimed) == 1, "bonus progress after tier 30")
	ok(Season.add_xp(2500, "test") == [32, 33] and Profile.pack_count("pro") == pros + 3, "several bonus packs at once")
	ok(Profile.data.achievements.has("season_15") and Profile.data.achievements.has("season_30"), "season tier achievements")
	ok(Season.add_xp(0, "test").is_empty() and Season.add_xp(-5, "test").is_empty(), "no XP, no change")
	# Rollover: unclaimed reached tiers are paid out, then a fresh season.
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-10"
	Season.add_xp(2600, "test")   # tiers 1-5
	Season.claim(1)
	coins = int(Profile.data.coins)
	var stars := int(Profile.data.stars)
	var rookies := Profile.pack_count("rookie")
	pros = Profile.pack_count("pro")
	DailyChallenge.date_override = "2026-11-17"
	Season.refresh()
	var se: Dictionary = Profile.data.season
	ok(int(se.id) == 2 and int(se.xp) == 0 and (se.claimed as Array).is_empty() and int(se.bonus_claimed) == 0, "a new season starts from 0")
	ok(se.get("last_rollover", {}).get("tiers", []) == [2, 3, 4, 5] and int(se.last_rollover.season) == 1, "rollover lists the auto-claimed tiers")
	ok(int(Profile.data.coins) == coins + 250 and int(Profile.data.stars) == stars + 10 and Profile.pack_count("rookie") == rookies + 1
		and Profile.pack_count("pro") == pros + 1, "rollover pays every reached tier that was not claimed")
	ok(str(Season.tier_reward(30).get("uniform", "")) == "season_2", "season 2 pays its own uniform")
	DailyChallenge.date_override = "2026-11-10"
	Season.add_xp(100, "test")
	ok(int(Profile.data.season.id) == 2 and Season.xp() == 100, "a clock set back never resets the season")
	DailyChallenge.date_override = "2026-12-01"   # season 3, nothing reached in season 2
	coins = int(Profile.data.coins)
	ok(Season.xp() == 0 and int(Profile.data.season.id) == 3 and int(Profile.data.coins) == coins, "rollover with nothing reached pays nothing")
	# An owned season uniform turns into stars.
	Profile.data.uniforms_owned.append("season_3")
	ok(not Season.tier_reward(30).has("uniform") and int(Season.tier_reward(30).get("stars", 0)) == 50, "an owned season uniform becomes 50 stars")


func _test_u9_login() -> void:
	section("Update 9: login calendar")
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	ok(DailyRewards.can_claim() and DailyRewards.day() == 1 and DailyRewards.streak() == 0, "a new profile can claim day 1")
	var cal := DailyRewards.calendar()
	ok(cal.size() == 7 and bool(cal[0].today) and not bool(cal[0].claimed) and cal.all(func(d: Dictionary) -> bool: return str(d.text) != ""),
		"the calendar shows 7 days, today is day 1")
	var expect := ["150 coins", "Rookie Pack", "250 coins", "10 stars", "Pro Pack", "400 coins", "Champion Pack"]
	var texts := cal.map(func(d: Dictionary) -> String: return DailyRewards.reward_text(d.reward))
	ok(texts == expect, "the 7-day cycle: 150 coins, Rookie, 250 coins, 10 stars, Pro, 400 coins, Champion (%s)" % [texts])
	var coins := int(Profile.data.coins)
	var r := DailyRewards.claim()
	ok(int(r.get("day", 0)) == 1 and int(Profile.data.coins) == coins + 150 and int(r.streak) == 1, "day 1 pays 150 coins")
	ok(not DailyRewards.can_claim() and DailyRewards.claim().is_empty() and int(Profile.data.coins) == coins + 150, "one claim per calendar day")
	cal = DailyRewards.calendar()
	ok(bool(cal[0].claimed) and bool(cal[0].today) and not bool(cal[1].claimed), "today's claimed day stays marked as today")
	DailyChallenge.date_override = "2026-11-05"
	var rookies := Profile.pack_count("rookie")
	r = DailyRewards.claim()
	ok(int(r.day) == 2 and Profile.pack_count("rookie") == rookies + 1 and int(r.streak) == 2, "day 2 the next day: a Rookie Pack, streak 2")
	DailyChallenge.date_override = "2026-11-08"   # two days missed
	ok(DailyRewards.streak() == 0 and DailyRewards.day() == 3, "missing days pauses the calendar on day 3")
	coins = int(Profile.data.coins)
	r = DailyRewards.claim()
	ok(int(r.day) == 3 and int(Profile.data.coins) == coins + 250 and int(r.streak) == 1 and int(r.best) == 2, "the paused calendar continues with day 3; the streak starts again")
	var stars := int(Profile.data.stars)
	for i in range(1, 5):
		DailyChallenge.date_override = DailyChallenge.shift_date("2026-11-08", i)
		r = DailyRewards.claim()
	ok(int(r.day) == 7 and int(r.streak) == 5 and int(Profile.data.stars) == stars + 10, "days 4 to 7 on consecutive days")
	ok(Profile.data.packs.any(func(pk: Dictionary) -> bool: return pk.type == "champion" and str(pk.source).begins_with("Login reward")), "day 7 pays a Champion Pack")
	cal = DailyRewards.calendar()
	ok(cal.all(func(d: Dictionary) -> bool: return bool(d.claimed)) and bool(cal[6].today), "a finished cycle shows all 7 days claimed")
	DailyChallenge.date_override = "2026-11-13"
	ok(DailyRewards.day() == 1 and bool(DailyRewards.calendar()[0].today) and not bool(DailyRewards.calendar()[0].claimed), "after day 7 the cycle starts again")
	DailyChallenge.date_override = "2026-11-11"   # clock set back
	ok(not DailyRewards.can_claim(), "a clock set back cannot claim again")
	ok(int(Profile.data.login.best) == 5 and Profile.stat("login_claims") == 7.0, "best streak and claims are recorded")


func _test_u9_streak_and_results() -> void:
	section("Update 9: win streak, first win of the day, result keys")
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	ok(Profile.win_streak() == 0 and is_zero_approx(Profile.streak_bonus()) and Profile.is_first_win_today(), "a new profile: no streak, first win waiting")
	var c0 := int(Profile.data.coins)
	var res := Rewards.apply(_u9_run("quick", 3, 3), true)
	for k in ["streak", "streak_bonus_coins", "first_win_today_coins", "season_xp", "season_tiers", "boons", "milestones", "milestone_coins",
			"promotion_reward", "overflow_coins"]:
		ok(res.has(k), "result key %s" % k)
	ok(int(res.streak) == 1 and int(res.streak_bonus_coins) == 0, "the first win starts the streak (no bonus yet)")
	ok(int(res.first_win_today_coins) == int(res.coins) and int(res.coins) > 0, "the first win of the day pays its coins twice (%d + %d)" % [int(res.coins), int(res.first_win_today_coins)])
	ok(int(Profile.data.coins) - c0 >= int(res.coins) * 2 and int(res.coins_total) >= int(res.coins) * 2, "doubled coins reach the wallet")
	ok(not Profile.is_first_win_today() and str(Profile.data.first_win_day) == "2026-11-04", "the day's first win is used")
	ok(int(res.season_xp) == 160 and Season.xp() == 160, "a win gives 160 season XP (100 + 60)")
	ok(is_equal_approx(Profile.streak_bonus(), 0.1), "a streak of 1 gives the next win +10 %")
	res = Rewards.apply(_u9_run("quick", 3, 3), true)
	ok(int(res.streak) == 2 and int(res.streak_bonus_coins) == int(round(int(res.coins) * 0.1)) and int(res.first_win_today_coins) == 0,
		"the second win in a row pays +10 % (%d of %d)" % [int(res.streak_bonus_coins), int(res.coins)])
	for i in 6:
		res = Rewards.apply(_u9_run("quick", 3, 3), true)
	ok(int(res.streak) == 8 and is_equal_approx(float(res.streak_bonus), 0.5) and int(res.streak_bonus_coins) == int(round(int(res.coins) * 0.5)),
		"the streak bonus stops at +50 %")
	ok(Profile.data.achievements.has("streak_5") and int(Profile.data.streak.best) == 8, "5 wins in a row: On Fire")
	res = Rewards.apply(_u9_run("endless", 4, 1), false)
	ok(int(res.streak) == 8 and int(res.season_xp) == 100, "Endless never breaks the streak; a game gives 100 season XP")
	res = Rewards.apply(_u9_run("quick", 2, 1), false)
	ok(int(res.streak) == 0 and Profile.win_streak() == 0 and int(Profile.data.streak.best) == 8, "a loss resets the streak, the best stays")
	DailyChallenge.date_override = "2026-11-05"
	res = Rewards.apply(_u9_run("quick", 3, 3), true)
	ok(int(res.first_win_today_coins) == int(res.coins), "a new day brings a new double-coin first win")
	# Daily Challenge: +100 season XP for the day's first finished game.
	var dr := RunState.create(DailyChallenge.config_for("2026-11-05"))
	dr.inning = 2
	res = Rewards.apply(dr, false)
	ok(bool(res.daily.first_today) and int(res.season_xp) == 200, "the Daily Challenge adds 100 season XP (%d)" % int(res.season_xp))
	dr = RunState.create(DailyChallenge.config_for("2026-11-05"))
	res = Rewards.apply(dr, false)
	ok(int(res.season_xp) == 100, "a second daily attempt is a normal game for season XP")
	ok(int(res.season_xp_after) == int(res.season_xp_before) + 100 and res.season_tiers is Array, "results carry the season XP before and after")


func _test_u9_shop() -> void:
	section("Update 9: Daily Shop")
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	var offs := Shop.offers()
	ok(offs.size() == 5 and offs.map(func(o: Dictionary) -> String: return o.kind) == ["gift", "card", "card", "pack", "stars"],
		"today's shop: a gift, two card deals, a pack deal and a star deal")
	var keys_ok := true
	for o in offs:
		for k in ["id", "kind", "card", "pack", "copies", "price", "bought", "title", "text"]:
			keys_ok = keys_ok and o.has(k)
		keys_ok = keys_ok and (o.price as Dictionary).has("coins") and (o.price as Dictionary).has("stars") and str(o.title) != "" and str(o.text) != ""
	ok(keys_ok, "every offer has the contract keys")
	ok(str(Shop.generate("2026-11-04")) == str(Shop.generate("2026-11-04")), "the same day and profile roll the same offers")
	ok(str(Shop.offers()) == str(offs), "offers stay the same through the day")
	var differ := 0
	for i in range(1, 11):
		if str(Shop.generate(DailyChallenge.shift_date("2026-11-04", i))) != str(Shop.generate("2026-11-04")):
			differ += 1
	ok(differ >= 8, "other days roll other offers (%d of 10)" % differ)
	var cards: Array = offs.filter(func(o: Dictionary) -> bool: return o.kind == "card")
	ok(cards[0].card != cards[1].card, "two different cards")
	var deal_ok := true
	for o in cards:
		deal_ok = deal_ok and Profile.is_card_owned(o.card) and Shop.copies_to_max(o.card) > 0 and int(o.copies) >= 1
		deal_ok = deal_ok and int(o.price.coins) == int(o.copies) * Shop.card_price(DB.card(o.card).rarity)
	ok(deal_ok, "card deals: owned cards that need copies, priced per copy")
	ok(Shop.card_price("common") == 60 and Shop.card_price("uncommon") == 120 and Shop.card_price("rare") == 250 and Shop.card_price("epic") == 500
		and Shop.card_price("legendary") == 1000, "copy prices 60 / 120 / 250 / 500 / 1,000")
	var pack: Dictionary = offs[3]
	ok(pack.pack == "pro" and int(pack.price.coins) == 375, "the pack deal: a Pro Pack at -25 % (375 coins)")
	ok(offs[4].pack == "champion" and int(offs[4].price.stars) == 40 and int(offs[4].price.coins) == 0, "the star deal is paid with stars")
	ok(int(offs[0].price.coins) == 0 and int(offs[0].price.stars) == 0, "the gift is free")
	# Weighted toward the deck: with every card owned, deck cards come up far more than their share.
	for id in DB.card_order:
		Profile.data.cards[id].owned = true
	var in_deck := 0
	var total := 0
	for i in 60:
		for o in Shop.generate(DailyChallenge.shift_date("2026-11-04", i)):
			if o.kind == "card":
				total += 1
				in_deck += 1 if o.card in Profile.data.deck else 0
	var share := float(Profile.DECK_SIZE) / DB.card_order.size()
	ok(float(in_deck) / total > share * 1.8, "card deals favour the deck (%.0f %% vs %.0f %% of the cards)" % [100.0 * in_deck / total, 100.0 * share])
	# Copies: what the next level needs, capped per rarity.
	Profile.data.cards.power_throw.copies = 0
	Profile.data.cards.power_throw.level = 1
	ok(Shop.deal_copies("power_throw") == 2, "a level 1 common needs 2 copies for level 2")
	Profile.data.cards.power_throw.level = 4
	ok(Shop.deal_copies("power_throw") == 4, "a level 4 common deal stops at 4 copies")
	Profile.data.cards.power_throw.copies = 13
	ok(Shop.deal_copies("power_throw") == 1 and Shop.copies_to_max("power_throw") == 1, "a deal never exceeds the copies still needed for max level")
	Profile.data.cards.power_throw.level = DB.card_max_level
	ok(Shop.copies_to_max("power_throw") == 0, "a max-level card needs no copies")
	# Buying: once each, affordability, the gift.
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	offs = Shop.offers()
	Profile.data.coins = 0
	Profile.data.stars = 0
	ok(Shop.can_buy("gift") and Shop.gift_available(), "the free gift is always affordable")
	var gift := Shop.buy("gift")
	ok(not gift.is_empty() and not Shop.can_buy("gift") and Shop.buy("gift").is_empty(), "the gift is claimed once a day")
	ok(Shop.offers()[0].bought, "the claimed gift is marked bought")
	ok(not Shop.can_buy("pack") and Shop.buy("pack").is_empty() and not Shop.offers()[3].affordable, "deals need the coins")
	ok(not Shop.can_buy("stars"), "the star deal needs stars")
	ok(not Shop.can_buy("nope") and Shop.buy("nope").is_empty(), "unknown offers are refused")
	Profile.data.coins = 1000
	var pros := Profile.pack_count("pro")
	var b := Shop.buy("pack")
	ok(not b.is_empty() and int(Profile.data.coins) == 625 and Profile.pack_count("pro") == pros + 1, "buying the pack deal: 375 coins for a Pro Pack")
	ok(not Shop.can_buy("pack") and Shop.buy("pack").is_empty() and int(Profile.data.coins) == 625, "each deal is bought once a day")
	Profile.data.stars = 45
	ok(not Shop.buy("stars").is_empty() and int(Profile.data.stars) == 5 and Profile.pack_count("champion") >= 1, "the star deal: a Champion Pack for 40 stars")
	var deal: Dictionary = offs[1]
	Profile.data.coins = int(deal.price.coins)
	var copies := Profile.card_copies(deal.card)
	ok(not Shop.buy("card_1").is_empty() and Profile.card_copies(deal.card) == copies + int(deal.copies) and int(Profile.data.coins) == 0,
		"a card deal adds its copies (%s x%d)" % [deal.card, int(deal.copies)])
	var deal2: Dictionary = offs[2]
	Profile.data.coins = 99999
	Profile.data.cards[deal2.card].level = DB.card_max_level
	ok(not Shop.can_buy("card_2"), "a deal for a card that reached max level is refused")
	ok(Profile.stat("shop_purchases") == 3.0 and Profile.stat("shop_gifts") == 1.0, "purchases and gifts are counted (%d)" % int(Profile.stat("shop_purchases")))
	ok(Shop.seconds_to_refresh() > 0 and Shop.seconds_to_refresh() <= 86400, "refresh countdown to midnight")
	DailyChallenge.date_override = "2026-11-05"
	ok(Shop.can_buy("gift") and Shop.can_buy("pack") and (Profile.data.shop.bought as Array).is_empty() and Profile.data.shop.date == "2026-11-05",
		"the shop refreshes the next day")
	# No card needs copies: the card slots become discounted Rookie Packs.
	for id in DB.card_order:
		Profile.data.cards[id].owned = true
		Profile.data.cards[id].level = DB.card_max_level
	var fallback := Shop.generate("2026-11-06")
	ok(fallback[1].kind == "pack" and fallback[1].pack == "rookie" and int(fallback[1].price.coins) == 150, "with nothing to copy, card slots sell Rookie Packs")


func _test_u9_free_agents() -> void:
	section("Update 9: free agents")
	Profile.reset_profile()
	var fas := Shop.free_agents()
	var by_id := {}
	for fa in fas:
		by_id[fa.id] = fa
	ok(by_id.has("moose") and int(by_id.moose.price) == 5000 and int(by_id.moose.level) == 15, "Moose: 5,000 coins or level 15")
	ok(by_id.has("rosa") and int(by_id.rosa.price) == 7500 and int(by_id.rosa.level) == 20 and by_id.has("sid") and int(by_id.sid.price) == 10000
		and int(by_id.sid.level) == 25, "Rosa 7,500 coins or level 20, Sid 10,000 coins or level 25")
	ok(fas.all(func(f: Dictionary) -> bool: return f.has("signed") and not bool(f.signed)), "nobody is signed on a new profile")
	Profile.data.coins = 4999
	ok(not Shop.sign_agent("moose") and int(Profile.data.coins) == 4999 and not Profile.is_defender_unlocked("moose"), "signing needs the full price")
	Profile.data.coins = 7000
	var sig := str(DB.defender("moose").get("signature", ""))
	if sig != "":
		Profile.data.cards[sig].owned = false
	ok(Shop.sign_agent("moose") and int(Profile.data.coins) == 2000 and Profile.is_defender_unlocked("moose"), "signing Moose: 5,000 coins, on the team now")
	ok(sig == "" or Profile.data.packs.any(func(pk: Dictionary) -> bool: return pk.type == "signature" and pk.get("card", "") == sig), "signing brings the signature pack")
	ok(not Shop.sign_agent("moose") and int(Profile.data.coins) == 2000, "a signed defender cannot be signed again")
	ok(not Shop.sign_agent("ace") and not Shop.sign_agent("nope"), "only free agents can be signed")
	ok(Profile.stat("free_agents_signed") == 1.0 and Profile.data.achievements.has("free_agent"), "signing counts (Front Office)")
	ok(bool(Shop.free_agents().filter(func(f: Dictionary) -> bool: return f.id == "moose")[0].signed), "free_agents() shows Moose as signed")


func _test_u9_pity_overflow() -> void:
	section("Update 9: pack pity, extra copies")
	Profile.reset_profile()
	ok(Profile.pity_left("epic") == 10 and Profile.pity_left("legendary") == 30, "pity: Epic within 10 packs, Legendary within 30")
	Profile.data.pity.epic = 9
	Profile.add_pack("rookie", "test")
	var res := Profile.open_pack(Profile.data.packs.size() - 1)
	ok(res.cards.any(func(c: Dictionary) -> bool: return DB.rarity_index(c.rarity) >= DB.rarity_index("epic")) and int(Profile.data.pity.epic) == 0,
		"the 10th pack without an Epic has one")
	ok(Profile.pity_counts("rookie", "epic") and Profile.pity_counts("pro", "epic") and Profile.pity_counts("champion", "epic")
		and not Profile.pity_counts("signature", "epic"), "every regular pack counts towards the Epic guarantee")
	ok(Profile.pity_counts("pro", "legendary") and Profile.pity_counts("champion", "legendary") and not Profile.pity_counts("rookie", "legendary"),
		"Pro and Champion Packs count towards the Legendary guarantee")
	ok(Profile.pity_pack_names("legendary") == "Pro or Champion Packs" and Profile.pity_pack_names("epic") == "packs", "pity pack names for the Packs screen")
	Profile.data.pity.legendary = 29
	Profile.add_pack("rookie", "test")
	res = Profile.open_pack(Profile.data.packs.size() - 1)
	var natural: bool = res.cards.any(func(c: Dictionary) -> bool: return c.rarity == "legendary")
	ok(str(res.pity) != "legendary" and int(Profile.data.pity.legendary) == (0 if natural else 29), "a Rookie Pack does not trigger the Legendary guarantee")
	Profile.data.pity.legendary = 29
	Profile.add_pack("pro", "test")
	res = Profile.open_pack(Profile.data.packs.size() - 1)
	ok(res.cards.any(func(c: Dictionary) -> bool: return c.rarity == "legendary") and str(res.pity) == "legendary", "the 30th Pro Pack without a Legendary has one")
	ok(int(Profile.data.pity.legendary) == 0 and int(Profile.data.pity.epic) == 0, "a Legendary resets both counters")
	# Over many packs, the gaps never exceed the guarantees.
	var gap_e := 0
	var worst_e := 0
	var leg0 := int(Profile.data.pity.legendary)
	var leg_moved := false
	for i in 90:
		Profile.add_pack("rookie", "test")
		res = Profile.open_pack(Profile.data.packs.size() - 1)
		var best := 0
		for c in res.cards:
			best = maxi(best, DB.rarity_index(c.rarity))
		gap_e = 0 if best >= DB.rarity_index("epic") else gap_e + 1
		worst_e = maxi(worst_e, gap_e)
		leg_moved = leg_moved or int(Profile.data.pity.legendary) > leg0
	ok(worst_e <= 9, "90 Rookie Packs: at most 9 in a row without an Epic (%d)" % worst_e)
	ok(not leg_moved, "Rookie Packs leave the Legendary counter alone")
	ok(Profile.pity_left("epic") == 10 - int(Profile.data.pity.epic), "pity_left counts down")
	var gap_l := 0
	var worst_l := 0
	for i in 70:
		Profile.add_pack("pro", "test")
		res = Profile.open_pack(Profile.data.packs.size() - 1)
		var has_l: bool = res.cards.any(func(c: Dictionary) -> bool: return c.rarity == "legendary")
		gap_l = 0 if has_l else gap_l + 1
		worst_l = maxi(worst_l, gap_l)
	ok(worst_l <= 29 and Profile.pity_left("legendary") == 30 - int(Profile.data.pity.legendary), "70 Pro Packs: at most 29 in a row without a Legendary (%d)" % worst_l)
	var pe := int(Profile.data.pity.epic)
	Profile.add_pack("signature", "test", "heat_wave")
	Profile.open_pack(Profile.data.packs.size() - 1)
	ok(int(Profile.data.pity.epic) == pe, "signature packs do not move the counters")
	# Pity survives save and load.
	Profile.data.pity.epic = 4
	Profile.save_now()
	Profile.load_profile()
	ok(int(Profile.data.pity.epic) == 4, "pity counters persist")
	# Extra copies of a max-level card become coins.
	var cid := "heat_wave"
	var rarity := str(DB.card(cid).rarity)
	Profile.data.cards[cid].owned = true
	Profile.data.cards[cid].level = DB.card_max_level
	var copies := Profile.card_copies(cid)
	var coins := int(Profile.data.coins)
	Profile.add_pack("signature", "test", cid)
	res = Profile.open_pack(Profile.data.packs.size() - 1)
	var per := 2 if rarity == "common" else 1
	ok(int(res.overflow_coins) == per * Profile.overflow_rate(rarity) and int(res.cards[0].overflow) == int(res.overflow_coins) and int(res.cards[0].copies) == 0,
		"a copy of a max-level %s card pays %d coins" % [rarity, int(res.overflow_coins)])
	ok(int(Profile.data.coins) == coins + int(res.overflow_coins) and Profile.card_copies(cid) == copies, "the coins reach the wallet, no copies pile up")
	ok(Profile.overflow_rate("common") == 20 and Profile.overflow_rate("uncommon") == 40 and Profile.overflow_rate("rare") == 80
		and Profile.overflow_rate("epic") == 160 and Profile.overflow_rate("legendary") == 400, "overflow rates 20 / 40 / 80 / 160 / 400")
	Profile.add_pack("signature", "test", cid)
	Profile.add_pack("signature", "test", cid)
	var multi := Profile.open_packs("signature", 2, cid)
	ok(int(multi.get("overflow_coins", 0)) == 2 * per * Profile.overflow_rate(rarity), "a multi-open adds up the overflow coins")
	ok(Profile.stat("overflow_coins") == 3.0 * per * Profile.overflow_rate(rarity), "overflow coins are tracked")
	# A card below max level keeps its copies.
	Profile.data.cards[cid].level = 2
	Profile.add_pack("signature", "test", cid)
	res = Profile.open_pack(Profile.data.packs.size() - 1)
	ok(int(res.overflow_coins) == 0 and Profile.card_copies(cid) == copies + per, "below max level, copies are kept")


func _test_u9_promotion_modes() -> void:
	section("Update 9: promotions, Endless milestones, Boss Rush")
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	var coins := int(Profile.data.coins)
	var stars := int(Profile.data.stars)
	var pros := Profile.pack_count("pro")
	var pr := Profile.promote()
	ok(int(Profile.data.division) == 1 and int(pr.get("coins", 0)) == 300 and int(pr.get("stars", 0)) == 10 and pr.get("packs", []) == ["pro"],
		"Bronze pays 300 coins, 10 stars and a Pro Pack (%s)" % [pr])
	ok(int(Profile.data.coins) == coins + 300 and int(Profile.data.stars) == stars + 10 and Profile.pack_count("pro") == pros + 1, "the promotion reward is granted")
	Profile.promote()
	var champs := Profile.pack_count("champion")
	pr = Profile.promote()
	ok(int(Profile.data.division) == 3 and int(pr.coins) == 900 and int(pr.stars) == 30 and Profile.pack_count("champion") == champs + 1, "Gold pays 900 coins, 30 stars and a Champion Pack")
	for i in range(1, DB.divisions.size()):
		var rw := Profile.promotion_reward(i)
		ok(int(rw.coins) == 300 * i and int(rw.stars) == 10 * i and rw.packs == (["champion"] if i >= 3 else ["pro"]), "division %d reward" % i)
	Profile.data.division = DB.divisions.size() - 1
	ok(Profile.promote().is_empty(), "no promotion past Legend")
	Profile.data.division = 0
	Profile.data.rp = 5000
	var res := Rewards.apply(_u9_run("ranked", 3, 3), true)
	ok(bool(res.promoted) and int(res.promotion_reward.get("coins", 0)) == 300, "a won Promotion Challenge reports its reward")
	res = Rewards.apply(_u9_run("quick", 3, 3), true)
	ok((res.promotion_reward as Dictionary).is_empty(), "other games report no promotion reward")
	# Endless milestones: every 5 innings cleared.
	ok(Rewards.milestones_for(4).is_empty() and Rewards.milestones_for(14) == [5, 10] and Rewards.milestones_for(20) == [5, 10, 15, 20], "milestones every 5 innings")
	ok(int(Rewards.milestone_reward(5).coins) == 150 and Rewards.milestone_reward(5).packs == ["rookie"] and int(Rewards.milestone_reward(15).coins) == 450,
		"milestone 5: 150 coins and a Rookie Pack; 15: 450 coins")
	ok(Rewards.milestone_reward(10).packs == ["rookie", "pro"] and Rewards.milestone_reward(20).packs == ["rookie", "pro"], "Pro Packs at 10 and 20")
	coins = int(Profile.data.coins)
	var er := _u9_run("endless", 11, 0)   # 10 innings cleared
	res = Rewards.apply(er, false)
	var ms: Array = res.packs.filter(func(pk: Dictionary) -> bool: return str(pk.source).begins_with("Endless milestone"))
	ok(res.milestones == [5, 10] and int(res.milestone_coins) == 450, "10 Endless innings: milestones 5 and 10 pay 450 coins")
	ok(ms.size() == 3 and ms.filter(func(pk: Dictionary) -> bool: return pk.type == "pro").size() == 1, "milestone packs: 2 Rookie + 1 Pro")
	ok(int(Profile.data.coins) - coins >= int(res.coins) + 450, "milestone coins reach the wallet")
	var game_rookies: Array = res.packs.filter(func(pk: Dictionary) -> bool: return str(pk.source).begins_with("The Endless Ninth"))
	ok(game_rookies.size() == 1, "Endless still gives its one game Rookie Pack (%d)" % game_rookies.size())
	res = Rewards.apply(_u9_run("endless", 3, 1), false)
	ok((res.milestones as Array).is_empty() and int(res.milestone_coins) == 0, "no milestone before 5 innings")
	# Boss Rush: a Pro Pack on a win and the best time.
	var br := _u9_run("boss_rush", 3, 3)
	br.stats["time"] = 412.4
	br.boons = ["team_damage"]
	res = Rewards.apply(br, true)
	ok((res.packs as Array).any(func(pk: Dictionary) -> bool: return pk.type == "pro" and str(pk.source).begins_with("Boss Rush")), "a Boss Rush win pays a Pro Pack")
	ok(is_equal_approx(float(Profile.data.records.best_time_boss_rush), 412.4) and (res.records as Array).any(func(t: String) -> bool: return "6:52" in t),
		"the best Boss Rush time is recorded (6:52)")
	ok(res.boons == ["team_damage"], "the result lists the boons taken")
	ok(Profile.stat("wins_boss_rush") == 1.0 and Profile.data.achievements.has("rush_win"), "Boss Rush wins are counted (Rush Hour)")
	br = _u9_run("boss_rush", 3, 3)
	br.stats["time"] = 450.0
	Rewards.apply(br, true)
	ok(is_equal_approx(float(Profile.data.records.best_time_boss_rush), 412.4), "a slower win keeps the record")
	br = _u9_run("boss_rush", 3, 3)
	br.stats["time"] = 380.0
	Rewards.apply(br, true)
	ok(is_equal_approx(float(Profile.data.records.best_time_boss_rush), 380.0), "a faster win sets the record")
	br = _u9_run("boss_rush", 2, 1)
	br.stats["time"] = 100.0
	res = Rewards.apply(br, false)
	ok(not (res.packs as Array).any(func(pk: Dictionary) -> bool: return pk.type == "pro" and str(pk.source).begins_with("Boss Rush"))
		and is_equal_approx(float(Profile.data.records.best_time_boss_rush), 380.0),
		"a lost Boss Rush pays no Pro Pack and sets no time")
	ok(is_equal_approx(float(DB.mode("boss_rush").reward_mult), 0.6), "Boss Rush reward multiplier 0.6")


func _test_u9_missions_and_saves() -> void:
	section("Update 9: missions, achievements, old saves")
	Profile.reset_profile()
	DailyChallenge.date_override = "2026-11-04"
	Missions.refresh()
	var s := Missions.state()
	# New events reach missions.
	s.daily[1] = _mission("boons", "boons_drafted", 3, 2)
	Profile.bump_stat("boons_drafted", 2)
	ok(int(s.daily[1].progress) == 2, "drafted boons count towards a mission")
	s.daily[2] = _mission("win_streak", "win_streak", 3, 3, true)
	Rewards.apply(_u9_run("quick", 3, 3), true)
	Rewards.apply(_u9_run("quick", 3, 3), true)
	ok(int(s.daily[2].progress) == 2 and not Missions.is_done(s.daily[2]), "a win streak mission tracks the streak (2 of 3)")
	Rewards.apply(_u9_run("quick", 3, 3), true)
	ok(Missions.is_done(s.daily[2]), "three wins in a row finish it")
	s.daily[0] = _mission("shop_deal", "shop_purchases", 1, 1)
	Profile.data.coins = 1000
	Shop.buy("pack")
	ok(Missions.is_done(s.daily[0]), "buying a shop deal finishes the shop mission")
	var xp0 := Season.xp()
	var r := Missions.claim("daily", 0)
	ok(int(r.get("season_xp", 0)) == 80 and Season.xp() == xp0 + 80 and "80 Season XP" in Missions.reward_text(r), "a claimed mission pays 80 season XP")
	for def in Missions.data().daily + Missions.data().weekly:
		var inst := Missions._instance(def, RandomNumberGenerator.new(), "daily")
		ok(not "{" in Missions.text(inst), "mission %s resolves" % def.id)
	for id in ["boss_rush", "boons", "shop_deal", "win_streak"]:
		ok(Missions.data().daily.any(func(d: Dictionary) -> bool: return d.id == id), "daily mission %s exists" % id)
	for id in ["rush_win", "rush_10", "boons_25", "boons_100", "streak_5", "streak_10", "shop_10", "free_agent", "season_15", "season_30", "login_7"]:
		ok(DB.achievements.has(id) and int(DB.achievements[id].stars) > 0, "achievement %s" % id)
	ok(int(DB.achievements.full_roster.goal) == DB.defenders.size(), "Full Roster asks for every defender (%d)" % DB.defenders.size())
	for i in 25:
		Profile.bump_stat("boons_drafted")
	ok(Profile.data.achievements.has("boons_25"), "25 boons: Draft Day")
	# Old saves: no Update 9 keys, or broken ones.
	var old: Dictionary = Profile.data.duplicate(true)
	for k in ["season", "login", "shop", "streak", "pity", "first_win_day"]:
		old.erase(k)
	old.records.erase("best_time_boss_rush")
	var f := FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	ok(Profile.load_status == "ok" and int(Profile.data.season.xp) == 0 and int(Profile.data.login.day) == 0 and Profile.win_streak() == 0
		and Profile.pity_left("epic") == 10 and Profile.is_first_win_today() and float(Profile.data.records.best_time_boss_rush) == 0.0, "a pre-Update 9 save loads with defaults")
	ok(Season.tier() == 0 and DailyRewards.can_claim() and Shop.offers().size() == 5, "old saves get the season, the calendar and the shop")
	old["season"] = {"id": "x", "xp": -40, "claimed": ["a", 3, 3.0, 99], "bonus_claimed": null}
	old["login"] = "junk"
	old["shop"] = {"date": 5, "offers": ["x", {"id": "gift"}], "bought": [1]}
	old["streak"] = {"wins": 3.0, "best": 7.0}
	old["pity"] = []
	old["first_win_day"] = null
	old["uniforms_owned"] = ["home", "nope"]
	f = FileAccess.open(Profile.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old))
	f.close()
	Profile.load_profile()
	var se: Dictionary = Profile.data.season
	ok(se.claimed == [3] and int(se.xp) == 0 and typeof(se.xp) == TYPE_INT and int(se.bonus_claimed) == 0, "a broken season block is repaired (%s)" % [se])
	ok(typeof(Profile.data.login) == TYPE_DICTIONARY and int(Profile.data.login.day) == 0 and typeof(Profile.data.pity) == TYPE_DICTIONARY, "broken login and pity blocks are reset")
	ok(Profile.win_streak() == 3 and typeof(Profile.data.streak.wins) == TYPE_INT and str(Profile.data.first_win_day) == "", "streak floats become ints, a null day is reset")
	ok(Profile.data.uniforms_owned == ["home"] and (Profile.data.shop.offers as Array).size() == 1, "unknown uniforms and broken offers are dropped")
	ok(Shop.offers().size() == 5 and Season.xp() == 0 and DailyRewards.calendar().size() == 7, "the repaired state works")


# ---------------------------------------------------------------- Update 9 cards (Stream B)

const NEW_CARDS_U9 := ["scouting_report", "sprinkler_system", "sweet_spot", "rally_monkey", "second_wind", "money_ball",
	"scoop_and_tag", "signal_caller", "hidden_ball_trick", "worm_burner", "fireworks_night", "ground_rule_double"]


## Update 9 cards outside battle: data, text that fits the card face, combos, sets, scouting, Auto Build.
func test_update9_cards_content() -> void:
	section("update 9 cards (data)")
	var expect := {"scouting_report": ["common", "control", 2], "sprinkler_system": ["common", "defense", 2],
		"sweet_spot": ["uncommon", "offense", 3], "rally_monkey": ["uncommon", "utility", 2], "second_wind": ["rare", "utility", 2],
		"money_ball": ["rare", "utility", 2], "scoop_and_tag": ["rare", "defense", 4], "signal_caller": ["rare", "utility", 3],
		"hidden_ball_trick": ["epic", "control", 4], "worm_burner": ["epic", "offense", 5], "fireworks_night": ["legendary", "offense", 7],
		"ground_rule_double": ["legendary", "utility", 6]}
	for id in NEW_CARDS_U9:
		var c := DB.card(id)
		ok(not c.is_empty(), "Update 9 card %s defined" % id)
		ok([c.get("rarity"), c.get("category"), int(c.get("cost", -1))] == expect[id], "%s is %s" % [id, expect[id]])
		ok(DB.combos_for(id).size() > 0, "%s has a combo" % id)
		var details := str(c.get("details", ""))
		for key in c.params.keys():
			details = details.replace("{%s}" % key, "1")
		ok(details != "" and not "{" in details, "%s has details text with resolvable values" % id)
		ok(id in CollectionSets.cards_in("big_league") and id in CollectionSets.cards_in(str(c.category)), "%s is in the Big League set and its category set" % id)
		var a := DeckAI.analyze(id, 1)
		ok(float(a.get("power", 0.0)) > 1.5 and str(a.get("role", "")) in ROLES, "Auto Build rates %s (power %.1f, %s)" % [id, float(a.get("power", 0.0)), a.get("role", "")])
	ok(DB.card("scoop_and_tag").get("linked") == "moose" and DB.card("signal_caller").get("linked") == "rosa" and DB.card("worm_burner").get("linked") == "sid",
		"the three signature cards are cast by Moose, Rosa and Sid")
	ok(CollectionSets.cards_in("big_league").size() == NEW_CARDS_U9.size(), "the Big League set holds the %d new cards" % NEW_CARDS_U9.size())
	# Every card's face text fits its three lines (hand card: 128 px wide at font size 13), at levels 1 and 5.
	var font := UITheme.font_body()
	var lh := font.get_height(13)
	var long: Array = []
	for id in DB.card_order:
		for lv in [1, DB.card_max_level]:
			var h := font.get_multiline_string_size(DB.card_text(id, lv), HORIZONTAL_ALIGNMENT_LEFT, 128, 13).y
			if h > lh * 3.0 + 1.0:
				long.append("%s@%d" % [id, lv])
	ok(long.is_empty(), "every card text fits three lines on the card face %s" % [long])
	# Scouting Book: the combat cards counter something.
	for id in ["scouting_report", "sprinkler_system", "scoop_and_tag", "hidden_ball_trick", "worm_burner", "fireworks_night"]:
		ok(Scouting.good_against(id).size() > 0, "%s is good against %s" % [id, Scouting.good_against(id)])
	ok("boss" in Scouting.card_tags("hidden_ball_trick") and "run_stop" in Scouting.card_tags("hidden_ball_trick"), "hidden ball trick counts as a run-stopper and a boss answer")
	# Auto Build with everything owned still builds a valid deck, and the new cards don't move the old cards' power.
	var everything: Array = DB.card_order.duplicate()
	var built := DeckAI.build("balanced", _ai_ctx(everything))
	ok(built.deck.size() == Profile.DECK_SIZE and _unique_owned(built.deck, everything), "Auto Build with all 56 cards builds a valid deck %s" % [built.deck])


## Update 9 cards in a live battle, one exact effect at a time (defenders hold their throws).
func _test_update9_cards_battle() -> void:
	section("update 9 cards (battle)")
	var route := battle.routes[0]
	var other := battle.routes[battle.routes.size() - 1]
	var lv := 1
	var cs := battle.cards
	_hold_fire(true)
	await _gwait(0.1)
	var spawn := func(id: String, rt: Route, d: float, hp := 40.0) -> Enemy:
		return battle.spawn_enemy(id, rt, d, {"lateral": 0.0, "hp_mult": hp, "speed_mult": 0.01})

	# Scouting Report: the target's whole type (and later runners of it) takes +30 %; other types don't.
	var r1: Enemy = spawn.call("runner", route, route.length * 0.5)
	var r2: Enemy = spawn.call("runner", other, other.length * 0.4)
	var sp: Enemy = spawn.call("sprinter", route, route.length * 0.3)
	await _gwait(0.1)
	battle.effects.execute("scouting_report", lv, {"enemy": r1, "point": r1.global_position, "valid": true})
	await _gwait(0.05)
	ok(r1.scout_t > 0.0 and r2.scout_t > 0.0 and sp.scout_t <= 0.0, "scouting report scouts every runner of the type and no other")
	var late: Enemy = spawn.call("runner", other, 3.0)
	await _gwait(0.1)
	ok(late.scout_t > 0.0, "a runner of the scouted type that spawns later is scouted too")
	var dealt := battle.deal_damage(r2, 100.0, {"kind": "throw"})
	var plain := battle.deal_damage(sp, 100.0, {"kind": "throw"})
	ok(absf(dealt - 130.0) < 0.5 and absf(plain - 100.0) < 0.5, "scouted runners take +30%% damage (%.1f vs %.1f)" % [dealt, plain])
	# Enemy.apply_aura_vuln (for defender auras): +25 % while refreshed, gone shortly after.
	sp.apply_aura_vuln(0.25)
	var in_aura := battle.deal_damage(sp, 100.0, {"kind": "throw"})
	await _gwait(0.4)
	var after_aura := battle.deal_damage(sp, 100.0, {"kind": "throw"})
	ok(absf(in_aura - 125.0) < 0.5 and absf(after_aura - 100.0) < 0.5, "an aura vulnerability adds 25%% while refreshed (%.1f, then %.1f)" % [in_aura, after_aura])
	_clear()
	await _gwait(0.2)

	# Sprinkler System: runners on the soaked stretch are 30 % slower and roll to slip.
	var wet: Enemy = spawn.call("runner", route, route.length * 0.5)
	var dry: Enemy = spawn.call("runner", route, route.length * 0.5 - 14.0)
	await _gwait(0.1)
	battle.effects.execute("sprinkler_system", lv, {"point": wet.global_position, "valid": true})
	await _gwait(0.1)
	ok(wet.slows.has("sprinkler") and absf(float(wet.slows.sprinkler[0]) - 0.3) < 0.001 and not dry.slows.has("sprinkler"),
		"sprinkler slows runners on the wet stretch only")
	ok(wet.soak_t > 0.0 and absf(wet.slip_chance - 0.3) < 0.001 and absf(wet.slip_time - 0.6) < 0.001, "wet runners have a 30% chance to slip for 0.6 s")
	var sure: Enemy = spawn.call("runner", other, other.length * 0.5)
	sure.apply_soak(2.0, 1.0, 0.6)
	await _gwait(0.65)
	ok(sure.stun_t > 0.0, "a certain slip stuns the runner")
	_clear()
	await _gwait(0.2)

	# Sweet Spot: every throw is a crit while it lasts.
	var tgt: Enemy = spawn.call("runner", route, route.length * 0.5)
	battle.effects.execute("sweet_spot", lv, {"valid": true})
	await _gwait(0.05)
	var crits := 0
	for df in battle.defenders:
		for i in 5:
			if df._build_payload(tgt, false).crit:
				crits += 1
	ok(crits == battle.defenders.size() * 5, "sweet spot: every throw crits (%d of %d)" % [crits, battle.defenders.size() * 5])
	_clear()
	await _gwait(0.1)

	# Rally Monkey: +3 energy, or +5 and a card after a run scored this inning (clutch).
	cs.infinite_energy = false
	battle.run.runs_inning = 0
	cs.energy = 2.0
	battle.effects.execute("rally_monkey", lv, {"valid": true})
	ok(absf(cs.energy - 5.0) < 0.05, "rally monkey gives 3 energy (%.1f)" % cs.energy)
	battle.run.runs_inning = 1
	cs.energy = 2.0
	var slot := cs.hand.find("")
	if slot < 0:
		cs.discard.append(cs.hand[0])
		cs.hand[0] = ""
	cs.draw_pile.append("power_throw")   # something to draw
	var n0 := cs.hand_count()
	battle.effects.execute("rally_monkey", lv, {"valid": true})
	ok(absf(cs.energy - 7.0) < 0.05 and cs.hand_count() == n0 + 1, "clutch rally monkey gives 5 energy and draws a card (%.1f, %d -> %d)" % [cs.energy, n0, cs.hand_count()])
	battle.run.runs_inning = 0

	# Second Wind: the defender's signature card comes off cooldown, +50 % attack speed for 6 s.
	var df0: Defender = battle.defenders[0]
	var sig := str(df0.data.signature)
	cs.cooldowns[sig] = 10.0
	cs.cooldowns["power_throw"] = 10.0
	var interval0 := df0.effective_interval()
	battle.effects.execute("second_wind", lv, {"defender": df0, "valid": true})
	await _gwait(0.05)
	ok(cs.cooldown_left(sig) <= 0.0 and cs.cooldown_left("power_throw") > 0.0, "second wind recharges %s's signature card (%s) and nothing else" % [df0.id, sig])
	ok(absf(df0.dyn_speed - 0.5) < 0.01 and df0.effective_interval() < interval0 * 0.7, "second wind: +50%% attack speed (%.2f, %.2f -> %.2f s)" % [df0.dyn_speed, interval0, df0.effective_interval()])
	ok(battle.defenders[1].dyn_speed < 0.01, "second wind boosts only the chosen defender")
	cs.cooldowns.clear()
	_clear()
	await _gwait(0.1)

	# Money Ball: outs pay double coins (through Battle's coin-bonus hook when it has one).
	var m1: Enemy = spawn.call("runner", route, route.length * 0.5)
	var m2: Enemy = spawn.call("runner", route, route.length * 0.4)
	await _gwait(0.05)
	battle.combo_timer = 0.0
	var c0 := battle.run.coins
	m1.die({})
	var base := battle.run.coins - c0
	battle.effects.execute("money_ball", lv, {"valid": true})
	battle.combo_timer = 0.0
	c0 = battle.run.coins
	m2.die({})
	var doubled := battle.run.coins - c0
	ok(base > 0 and absi(doubled - base * 2) <= 1, "money ball doubles the coins for an out (%d -> %d)%s" % [base, doubled,
		" via add_out_coin_bonus" if battle.has_method("add_out_coin_bonus") else ""])
	_clear()
	await _gwait(0.1)

	# Scoop & Tag: damage, knockback and stun; non-boss runners under 30 % are out; bosses never.
	var pt := route.position_at(route.length * 0.5)
	var full: Enemy = spawn.call("runner", route, route.length * 0.5)
	var hurt: Enemy = spawn.call("runner", route, route.length * 0.5 + 0.6)
	var boss: Enemy = battle.spawn_enemy("iron_slugger", route, route.length * 0.5 - 0.6, {"lateral": 0.0, "hp_mult": 1.0, "speed_mult": 0.01})
	await _gwait(0.1)
	hurt.hp = hurt.max_hp * 0.25
	boss.hp = boss.max_hp * 0.1
	var h_full := full.hp
	var d_full := full.d
	var power := float(battle.effects.caster_info("scoop_and_tag").power)
	battle.effects.execute("scoop_and_tag", lv, {"point": pt, "valid": true})
	await _gwait(0.9)
	ok(not hurt.alive and boss.alive, "scoop & tag tags out the hurt runner, never the boss")
	ok(absf((h_full - full.hp) - DB.card_param("scoop_and_tag", "damage", lv) * power) < 1.0 and full.d < d_full - 0.5,
		"scoop & tag hits for %.0f and knocks back (%.0f, %.1f m)" % [DB.card_param("scoop_and_tag", "damage", lv) * power, h_full - full.hp, d_full - full.d])
	ok(full.stun_t > 0.0 or full.d < d_full - 0.5, "scoop & tag stuns")
	_clear()
	await _gwait(0.2)

	# Signal Caller: the 3 lead runners take +40 % and refund 1 energy when put out.
	var row: Array = []
	for i in 4:
		row.append(spawn.call("runner", route, route.length * 0.3 + i * 3.0))
	await _gwait(0.1)
	battle.effects.execute("signal_caller", lv, {"valid": true})
	await _gwait(1.0)
	ok(row[3].signal_t > 0.0 and row[2].signal_t > 0.0 and row[1].signal_t > 0.0 and row[0].signal_t <= 0.0, "signal caller marks the 3 lead runners")
	var sd := battle.deal_damage(row[3], 100.0, {"kind": "throw"})
	ok(absf(sd - 140.0) < 0.5, "signalled runners take +40%% damage (%.1f)" % sd)
	cs.energy = 0.0
	battle.combo_timer = 0.0   # no triple-play energy in the way
	row[2].die({})
	await _gwait(0.05)
	ok(cs.energy >= 0.99 and cs.energy < 1.4, "an out on a signalled runner refunds 1 energy (%.2f)" % cs.energy)
	cs.energy = 0.0
	battle.combo_timer = 0.0
	row[0].die({})
	await _gwait(0.05)
	ok(cs.energy < 0.4, "an out on an unmarked runner refunds nothing (%.2f, regen only)" % cs.energy)
	_clear()
	await _gwait(0.2)

	# Hidden Ball Trick: after the reveal the strongest non-boss runner is out; bosses lose 15 %.
	var small: Enemy = spawn.call("runner", route, route.length * 0.6)
	var big: Enemy = spawn.call("armored", route, route.length * 0.3)
	var hb: Enemy = battle.spawn_enemy("iron_slugger", other, other.length * 0.3, {"lateral": 0.0, "hp_mult": 1.0, "speed_mult": 0.01})
	await _gwait(0.1)
	var hb0 := hb.hp
	battle.effects.execute("hidden_ball_trick", lv, {"valid": true})
	await _gwait(0.6)
	ok(big.alive, "the hidden ball trick waits for its reveal")
	await _gwait(DB.card_param("hidden_ball_trick", "reveal", lv))
	ok(not big.alive and small.alive, "the strongest runner (not the lead one) is tagged out")
	ok(absf((hb0 - hb.hp) - hb.max_hp * 0.15) < 1.0, "a boss loses 15%% of its max health (%.0f of %.0f)" % [hb0 - hb.hp, hb.max_hp])
	_clear()
	await _gwait(0.2)

	# Worm Burner: every runner on the stretch behind the landing spot takes damage and trips;
	# a runner ahead of it and one on another path don't; the path stays slick.
	var d_land := route.length * 0.6
	var on_path: Array = []
	for off in [1.0, 5.0, 10.0]:
		on_path.append(spawn.call("runner", route, d_land - off))
	var ahead: Enemy = spawn.call("runner", route, d_land + 6.0)
	var off_path: Enemy = spawn.call("runner", other, 4.0)
	await _gwait(0.1)
	var hp_on: Array = on_path.map(func(en: Enemy) -> float: return en.hp)
	var h_ahead := ahead.hp
	var h_off := off_path.hp
	var wpow := float(battle.effects.caster_info("worm_burner").power)
	battle.effects.execute("worm_burner", lv, {"point": route.position_at(d_land), "valid": true})
	var tripped := 0
	for i in 20:
		await _gwait(0.1)
		for en in on_path:
			if en.stun_t > 0.0:
				tripped = maxi(tripped, 1)
	await _gwait(0.4)
	var hits := 0
	for i in on_path.size():
		if absf((float(hp_on[i]) - on_path[i].hp) - DB.card_param("worm_burner", "damage", lv) * wpow) < 1.0:
			hits += 1
	ok(hits == 3, "worm burner hits every runner on the path behind it for %.0f (%d of 3)" % [DB.card_param("worm_burner", "damage", lv) * wpow, hits])
	ok(ahead.hp >= h_ahead - 0.01 and off_path.hp >= h_off - 0.01, "worm burner misses runners ahead of it and on other paths")
	ok(tripped > 0, "worm burner trips the runners it hits")
	var slick := battle.effects.active_item("wet")
	ok(not slick.is_empty() and slick.key == "slick" and on_path[0].slows.has("slick"), "worm burner leaves a slick that slows runners")
	_clear()
	await _gwait(0.2)

	# Fireworks Night: 14 rockets of 70 (plus splashes) over 4 s, then a finale on the crowd.
	var crowd: Array = []
	for i in 5:
		crowd.append(spawn.call("runner", route, route.length * 0.5 + i * 0.5, 80.0))
	await _gwait(0.1)
	var imp0 := float(battle.run.card_impact.get("fireworks_night", {}).get("damage", 0.0))
	battle.effects.execute("fireworks_night", lv, {"valid": true})
	await _gwait(DB.card_param("fireworks_night", "time", lv) + 1.1)
	var fw := float(battle.run.card_impact.get("fireworks_night", {}).get("damage", 0.0)) - imp0
	var least := DB.card_param("fireworks_night", "rockets", lv) * DB.card_param("fireworks_night", "damage", lv) + 5.0 * DB.card_param("fireworks_night", "finale_damage", lv)
	ok(fw >= least - 1.0, "fireworks night deals at least %.0f (%.0f)" % [least, fw])
	ok(crowd.all(func(en: Enemy) -> bool: return en.stun_t > 0.0), "the finale stuns the crowd")
	_clear()
	await _gwait(0.2)

	# Ground Rule Double: the next 2 cards this inning are cast twice; a third isn't; charges end with the inning.
	var gr: Enemy = spawn.call("runner", route, route.length * 0.5)
	await _gwait(0.1)
	battle.effects.execute("ground_rule_double", lv, {"valid": true})
	ok(cs.double_casts_left(battle.run.inning) == 2, "ground rule double arms 2 casts (and doesn't use one itself)")
	var g0 := gr.hp
	battle.effects.execute("bean_ball", lv, {"enemy": gr, "point": gr.global_position, "valid": true})
	await _gwait(0.6)
	var once := g0 - gr.hp
	await _gwait(CardEffects.ECHO_DELAY + 1.0)
	var twice := g0 - gr.hp
	var bb := DB.card_param("bean_ball", "damage", lv)
	ok(absf(once - bb) < 1.0 and absf(twice - 2.0 * bb) < 1.0, "a doubled card goes off twice (%.0f, then %.0f)" % [once, twice])
	ok(cs.double_casts_left(battle.run.inning) == 1, "one cast-twice charge left")
	battle.effects.execute("bean_ball", lv, {"enemy": gr, "point": gr.global_position, "valid": true})
	ok(cs.double_casts_left(battle.run.inning) == 0, "the second card uses the last charge")
	await _gwait(CardEffects.ECHO_DELAY + 1.6)
	var g1 := gr.hp
	battle.effects.execute("bean_ball", lv, {"enemy": gr, "point": gr.global_position, "valid": true})
	await _gwait(CardEffects.ECHO_DELAY + 1.6)
	ok(absf((g1 - gr.hp) - bb) < 1.0, "the third card is cast once (%.0f)" % (g1 - gr.hp))
	cs.grant_double_casts(2, battle.run.inning)
	ok(cs.double_casts_left(battle.run.inning + 1) == 0, "cast-twice charges run out when the inning ends")
	cs.double_left = 0
	cs.infinite_energy = true
	_clear()
	_hold_fire(false)


## Waits `sec` seconds of game time (the battle's clock): under heavy load the engine advances
## game time slower than the wall clock, so card timings are checked against game time.
func _gwait(sec: float) -> void:
	await get_tree().create_timer(sec, false, false, false).timeout


# ---------------------------------------------------------------- Update 10: team AI (Best Team, compare)

func _team_ctx(unlocked: Array, levels := {}, deck: Array = [], owned: Array = [], team: Array = [], captain := "ace") -> Dictionary:
	if team.is_empty():
		team = Profile.STARTER_TEAM.duplicate()
	if deck.is_empty():
		deck = Profile.STARTER_DECK.duplicate()
	if owned.is_empty():
		owned = deck.duplicate()
	var lv := {}
	for id in DB.defender_order:
		lv[id] = int(levels.get(id, 1))
	return {"unlocked": unlocked, "levels": lv, "owned_cards": owned, "card_levels": {}, "deck": deck,
		"team": team, "captain": captain, "formation": "balanced"}


func _valid_team(r: Dictionary, ctx: Dictionary) -> bool:
	return TeamAI.is_valid(r.team, str(r.captain), ctx)


func test_team_ai() -> void:
	section("update 10: team AI")
	var starter: Array = Profile.STARTER_TEAM
	var all: Array = DB.defender_order.duplicate()
	# Every defender has a trait the AI knows, and a positive rating at every level.
	var unknown: Array = []
	for id in all:
		if not TeamAI.TRAITS.has(str(DB.defender(id).trait.id)):
			unknown.append(id)
	ok(unknown.is_empty(), "TeamAI knows every defender's trait %s" % [unknown])
	var full := _team_ctx(all, {"ace": 6, "rico": 5, "maya": 6, "jax": 3, "kai": 7, "bruno": 4, "nova": 6, "dex": 4, "hana": 6, "moose": 5, "rosa": 5, "sid": 2})
	for id in all:
		var r1 := TeamAI.rate(id, _team_ctx(all))
		ok(float(r1.score) > 0.0 and float(r1.eff) > 0.0, "%s has a positive rating" % id)
	# Level-scaled stats: a higher level means a higher rating; gear and training traits count.
	ok(float(TeamAI.rate("hana", _team_ctx(all, {"hana": 8})).eff) > float(TeamAI.rate("hana", _team_ctx(all, {"hana": 1})).eff) * 1.3, "a higher level means more damage")
	var geared := _team_ctx(all)
	geared["mods"] = {"kai": TeamAI.level_mods(1).merged({"damage": 0.10, "attack_speed": 0.10}, true)}
	ok(float(TeamAI.rate("kai", geared).eff) > float(TeamAI.rate("kai", _team_ctx(all)).eff) * 1.15, "gear and training traits raise the rating")
	# Position bonus and signature cards.
	ok(float(TeamAI.rate("ace", full, "balanced", true).eff) > float(TeamAI.rate("ace", full, "balanced", false).eff), "the position bonus counts")
	var no_sig := _team_ctx(all, {}, ["power_throw", "curveball", "lockdown", "frost_field", "wall_of_dirt", "twin_play", "rally_cry", "bullpen_call"])
	ok(TeamAI.defender_score("ace", _team_ctx(all)) > TeamAI.defender_score("ace", no_sig) + 2.0, "a signature card in the deck adds to the score")
	# Every mode: the rules the game enforces, determinism, and at least the starter team's score.
	for m in TeamAI.MODES:
		var r := TeamAI.best_team(m, full)
		ok(r.team.size() == Profile.TEAM_SIZE and _valid_team(r, full), "%s: six unique unlocked defenders, captain in the team" % m)
		ok(r.team == TeamAI.best_team(m, full).team and r.captain == TeamAI.best_team(m, full).captain, "%s: the same input gives the same team" % m)
		var st := float(TeamAI.team_score(starter, full, m).total)
		ok(float(r.score) >= st - 0.0001, "%s: the best team scores at least the starter team (%.1f >= %.1f)" % [m, float(r.score), st])
		ok(not r.reasons.is_empty() and (r.reasons.keys() as Array).all(func(k: String) -> bool: return not (r.reasons[k] as Array).is_empty()), "%s: every pick has a reason" % m)
		ok(r.mode == m and str(r.summary) != "", "%s: a summary line" % m)
	# Role coverage (scored, the way the battle fills the formation slots): Balanced covers every slot.
	var bal := TeamAI.best_team("balanced", full)
	var roles := {}
	for id in bal.team:
		roles[DB.defender(id).role] = int(roles.get(DB.defender(id).role, 0)) + 1
	var need := {}
	for s in DB.formation_slots:
		need[s] = int(need.get(s, 0)) + 1
	ok(roles == need, "Balanced fills every formation slot with its role %s" % [roles])
	for id in bal.team:
		ok(bool(bal.parts.rows[id].in_position), "Balanced: %s stands in a slot of their role" % id)
	# Never a locked defender: the free agents stay out until they are unlocked, however strong.
	var some := starter + ["nova", "hana"]
	var strong := _team_ctx(some, {"moose": 10, "rosa": 10, "sid": 10, "dex": 10})
	var locked_ok := true
	for m in TeamAI.MODES:
		for id in TeamAI.best_team(m, strong).team:
			if not id in some:
				locked_ok = false
	ok(locked_ok, "never picks a locked defender, even at level 10")
	# Random rosters: always valid, deterministic, never below the current team.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1010
	var rand_ok := true
	for i in 10:
		var pool := all.duplicate()
		for k in range(pool.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var t: Variant = pool[k]
			pool[k] = pool[j]
			pool[j] = t
		var un: Array = pool.slice(0, rng.randi_range(6, pool.size()))
		var lv := {}
		for id in all:
			lv[id] = rng.randi_range(1, DB.defender_max_level)
		var cur: Array = un.slice(0, 6)
		var ctx := _team_ctx(un, lv, [], [], cur, cur[2])
		var m: String = TeamAI.MODES[i % TeamAI.MODES.size()]
		var r := TeamAI.best_team(m, ctx)
		if not _valid_team(r, ctx) or r.team != TeamAI.best_team(m, ctx).team or float(r.score) < float(r.current_score) - 0.0001:
			rand_ok = false
	ok(rand_ok, "random rosters (6 to 12 unlocked, random levels): valid, deterministic, never worse than the current team")
	# Fewer than six unlocked: all of them, captain included; none: an empty result, no crash.
	var four := TeamAI.best_team("balanced", _team_ctx(["ace", "rico", "maya", "kai"], {}, [], [], ["ace", "rico", "maya", "kai"]))
	ok(four.team.size() == 4 and four.captain in four.team, "four unlocked: a team of four with a captain")
	ok(TeamAI.best_team("balanced", _team_ctx([])).team.is_empty(), "nobody unlocked: an empty team, no crash")
	ok(TeamAI.best_team("nonsense", full).mode == "balanced", "an unknown mode falls back to Balanced")
	# Already best: the starter team with only the starters unlocked.
	var only := TeamAI.best_team("balanced", _team_ctx(starter))
	ok(bool(only.already_best) and only.ins.is_empty() and only.outs.is_empty(), "the starters alone: the team is already the best")
	ok(absf(float(only.score) - float(only.current_score)) < 0.001, "already best: the score does not change")
	var changed := TeamAI.best_team("balanced", full)
	ok(not bool(changed.already_best) and changed.ins.size() == changed.outs.size() and changed.ins.size() > 0, "a stronger bench: who comes in and who goes out")
	ok(float(changed.score) > float(changed.current_score), "the new team scores higher (%.1f > %.1f)" % [float(changed.score), float(changed.current_score)])
	# Captain: the battle's aura (+8 % within 6 m), so in Balanced it is the pitcher on the mound.
	ok(DB.defender(bal.captain).role == "pitcher" and bal.captain in bal.team, "the captain is the pitcher whose aura reaches the infield")
	# Compare helpers.
	ok(TeamAI.verdict("rosa", "rico", full).contains("Rosa: better vs bosses"), "verdict: Rosa is better vs bosses (%s)" % TeamAI.verdict("rosa", "rico", full))
	ok(TeamAI.verdict("bruno", "kai", full).contains("Bruno: better vs crowds"), "verdict: Bruno is better vs crowds")
	var sw := TeamAI.swap_in(starter, "ace", "nova", "ace", some)
	ok(sw.team.size() == 6 and "nova" in sw.team and not "ace" in sw.team and sw.captain == "nova", "put in: the incoming player takes the place and the captaincy")
	ok(TeamAI.swap_in(starter, "ace", "moose", "jax", some).is_empty(), "put in: a locked defender cannot come in")
	ok(TeamAI.swap_in(starter, "ace", "rico", "jax", some).is_empty(), "put in: a team member cannot come in twice")
	# The profile context: the result is a team Profile.set_team keeps as it is.
	Profile.reset_profile()
	for id in ["nova", "hana", "moose"]:
		Profile.data.defenders[id].unlocked = true
		Profile.data.defenders[id].level = 6
	var pr := TeamAI.best_team()
	ok(TeamAI.is_valid(pr.team, pr.captain, TeamAI.profile_context()), "profile context: a valid team")
	Profile.set_team(pr.team, pr.captain)
	ok(Profile.data.team == pr.team and Profile.data.captain == pr.captain, "Profile.set_team keeps the best team and captain")
	ok(bool(TeamAI.best_team().already_best), "after applying, the team is already the best")
	Profile.reset_profile()
