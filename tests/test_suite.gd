extends Node
## Automated system tests. Run headless:
##   godot --headless --path . res://tests/test_suite.tscn -- --profile=unittest --fresh-profile
## Exits with code 0 when every check passes.

var checks := 0
var failures := 0
var battle: Battle


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
	await test_battle_systems()
	print("==== %d checks, %d failed ====" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- data

func test_data() -> void:
	section("data integrity")
	ok(DB.cards.size() == 26, "26 cards defined (%d)" % DB.cards.size())
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
	Profile.add_defender_xp("jax", 400)
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
	ok(res.packs.size() >= 4, "standard victory awards packs (%d)" % res.packs.size())
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
	# Level-ups and new defenders give packs.
	var n := Profile.pack_count()
	Profile.add_xp(Profile.xp_to_next(int(Profile.data.level)))
	ok(Profile.pack_count() == n + 1, "levelling up awards a pack")
	var sig_def := ""
	for id in DB.defender_order:
		if not Profile.is_defender_unlocked(id) and str(DB.defender(id).get("signature", "")) != "":
			sig_def = id
			break
	if sig_def != "":
		var sig: String = DB.defender(sig_def).signature
		Profile.unlock_defender(sig_def)
		var has_sig: bool = Profile.data.packs.any(func(pk: Dictionary) -> bool: return pk.type == "signature" and pk.get("card", "") == sig)
		ok(has_sig and not Profile.is_card_owned(sig), "a new defender brings a Signature Pack")
		for i in Profile.data.packs.size():
			if Profile.data.packs[i].type == "signature":
				var res := Profile.open_pack(i)
				ok(res.cards.size() == 1 and res.cards[0].id == sig and Profile.is_card_owned(sig), "the Signature Pack contains the signature card")
				break
	# Save round trip keeps unopened packs.
	Profile.add_pack("pro", "test")
	Profile.save_now()
	var count := Profile.pack_count()
	Profile.load_profile()
	ok(Profile.pack_count() == count, "unopened packs survive save and load")
	Profile.reset_profile()


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
	battle.queue_free()
	await _wait(0.2)


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
	var hand_before := battle.cards.hand.size()
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
			ok(battle.cards.hand.size() >= mini(hand_before + 1, CardSystem.MAX_HAND) or battle.cards.energy >= energy_before, "stretch draws cards / gives energy")
		"shadow_change":
			ok(damaged, "shadow change damages runners")
		_:
			ok(damaged, "%s deals damage (%.0f -> %.0f)" % [cid, hp_before, hp_after])
