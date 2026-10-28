extends Node
## Automated system tests. Run headless:
##   godot --headless --path . res://tests/test_suite.tscn -- --profile=unittest --fresh-profile
## Exits with code 0 when every check passes.

var checks := 0
var failures := 0
var battle: Battle
const NEW_CARDS := ["called_shot", "line_drive", "tag_at_the_plate", "bullpen_call", "hot_corner", "perfect_game"]


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
	await test_menus()
	test_update5_content()
	await test_battle_systems()
	print("==== %d checks, %d failed ====" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- data

func test_data() -> void:
	section("data integrity")
	ok(DB.cards.size() == 32, "32 cards defined (%d)" % DB.cards.size())
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
	ok(int(res.coins) == 179, "Quick win coins = (720 x 0.35 + 3 x 15 + 100) x 0.45 = 179 (%d)" % int(res.coins))
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
	ok(int(rw.get("coins", 0)) == 100 and int(Profile.data.coins) == coins + 100, "claiming a tier 1 mission pays 100 coins")
	ok(Missions.claim("daily", 0).is_empty() and int(Profile.data.coins) == coins + 100, "a mission is claimed only once")
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
	ok(absf((b0 - boss.hp) - want_boss) < 3.0, "called shot hits a boss for %d%% of its max health through 75%% armor (%.0f, want %.0f)"
		% [int(DB.card_param("called_shot", "percent", 1)), b0 - boss.hp, want_boss])
	ok(absf((t0 - tank.hp) - want_tank) < 3.0, "called shot's bonus is capped on regular runners and ignores armor (%.0f, want %.0f)" % [t0 - tank.hp, want_tank])
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
		"perfect_game":
			ok(damaged, "perfect game damages every runner")
			ok(battle.buff_active("perfect_tag"), "perfect game opens a tag window at the plate")
		_:
			ok(damaged, "%s deals damage (%.0f -> %.0f)" % [cid, hp_before, hp_after])
