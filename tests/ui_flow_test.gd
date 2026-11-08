extends Node
## Drives a real battle through simulated mouse and keyboard input to verify the
## interactive flows: dragging a defender, choosing a formation, starting a wave,
## selecting and casting cards, pausing, and the dugout shop.
## Run: godot --path . -- --ui-test --profile=uitest --fresh-profile

var battle: Battle
var results: Array[String] = []
var failures := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


func _check(cond: bool, what: String) -> void:
	results.append(("PASS  " if cond else "FAIL  ") + what)
	if not cond:
		failures += 1
	print(("[UITEST] PASS " if cond else "[UITEST] FAIL ") + what)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout


func _mouse_move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)
	Input.warp_mouse(p)


func _mouse_button(p: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.global_position = p
	e.button_index = button
	e.pressed = pressed
	Input.parse_input_event(e)


func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	_mouse_move(p)
	await _wait(0.05)
	_mouse_button(p, true, button)
	await _wait(0.05)
	_mouse_button(p, false, button)
	await _wait(0.1)


func _key(action: String) -> void:
	var events := InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			var k := (ev as InputEventKey).duplicate() as InputEventKey
			k.pressed = true
			Input.parse_input_event(k)
			await _wait(0.05)
			var k2 := k.duplicate() as InputEventKey
			k2.pressed = false
			Input.parse_input_event(k2)
			await _wait(0.1)
			return


## Converts a viewport-space point (where events are delivered) from a 3D position.
func _screen_of(p: Vector3) -> Vector2:
	var cam := battle.cam.camera
	var vp_pos := cam.unproject_position(p)
	# Input events use window coordinates; the root viewport is stretched (canvas_items).
	var xf := get_viewport().get_final_transform()
	return xf * vp_pos


func _find_button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text.strip_edges() == text and (root as Button).is_visible_in_tree():
		return root
	for c in root.get_children():
		var r := _find_button(c, text)
		if r:
			return r
	return null


func _button_center(b: Button) -> Vector2:
	var xf := get_viewport().get_final_transform()
	return xf * b.get_global_rect().get_center()


func _run() -> void:
	if "--ui-test-section=hub" in OS.get_cmdline_user_args():
		await _test_u9_hub_play_results()
		await _test_u10_hub()
		_finish()
		return
	if "--ui-test-section=tutorial" in OS.get_cmdline_user_args():
		await _test_tutorial()
		_finish()
		return
	if "--ui-test-section=deck" in OS.get_cmdline_user_args():
		await _test_deck_menus()
		_finish()
		return
	if "--ui-test-section=autobuild" in OS.get_cmdline_user_args():
		await _test_auto_build()
		_finish()
		return
	if "--ui-test-section=cards" in OS.get_cmdline_user_args():
		await _test_card_clicks()
		_finish()
		return
	if "--ui-test-section=newcards" in OS.get_cmdline_user_args():
		await _test_new_card_clicks()
		_finish()
		return
	if "--ui-test-section=daily" in OS.get_cmdline_user_args():
		await _test_daily()
		_finish()
		return
	if "--ui-test-section=missions" in OS.get_cmdline_user_args():
		await _test_missions()
		_finish()
		return
	if "--ui-test-section=title" in OS.get_cmdline_user_args():
		await _test_title()
		_finish()
		return
	if "--ui-test-section=nav" in OS.get_cmdline_user_args():
		await _test_navigation()
		_finish()
		return
	if "--ui-test-section=scouting" in OS.get_cmdline_user_args():
		await _test_scouting()
		_finish()
		return
	if "--ui-test-section=u9e2" in OS.get_cmdline_user_args():
		await _test_u9_e2()
		_finish()
		return
	if "--ui-test-section=packs" in OS.get_cmdline_user_args():
		await _test_packs()
		await _test_multi_packs()
		_finish()
		return
	if "--ui-test-section=draft" in OS.get_cmdline_user_args():
		await _test_draft()
		_finish()
		return
	if "--ui-test-section=u10team" in OS.get_cmdline_user_args():
		await _test_u10_team()
		_finish()
		return
	if "--ui-test-section=u11cards" in OS.get_cmdline_user_args():
		await _test_u11_prestige()
		_finish()
		return
	if "--ui-test-section=u11def" in OS.get_cmdline_user_args():
		await _test_u11_defenders()
		_finish()
		return
	if "--ui-test-section=u9screens" in OS.get_cmdline_user_args():
		await _test_u9_hub_play_results()
		_finish()
		return
	Profile.data.flags["battle_help"] = true
	Profile.data.flags["battle_tutorial_done"] = true
	var cfg := Session.new_run_config("quick")
	cfg.difficulty = "rookie"
	Session.start(cfg)
	# Wait for the battle to load and reach setup.
	for i in 200:
		await _wait(0.1)
		var scene := get_tree().current_scene
		if scene is Battle and (scene as Battle).state == "setup":
			battle = scene
			break
	_check(battle != null, "battle loaded and reached setup")
	if battle == null:
		_finish()
		return
	await _wait(1.0)

	# 1. Drag Maya to a new spot.
	var maya: Defender = null
	for df in battle.defenders:
		if df.id == "maya":
			maya = df
	var start := maya.post
	var from := _screen_of(maya.global_position + Vector3(0, 1.0, 0))
	var target := start + Vector3(-2.5, 0, 3.5)
	var to := _screen_of(target)
	_mouse_move(from)
	await _wait(0.2)
	_mouse_button(from, true)
	await _wait(0.1)
	for k in 10:
		_mouse_move(from.lerp(to, (k + 1) / 10.0))
		await _wait(0.05)
	_mouse_button(to, false)
	await _wait(0.3)
	_check(maya.post.distance_to(start) > 1.0, "drag-and-drop moved Maya (%.1fm)" % maya.post.distance_to(start))
	_check(battle.placement_error(maya.post, maya) == "", "Maya's new spot is a valid placement")

	# 2. Formation button.
	var wide := _find_button(battle.hud.root, "Wide")
	if wide == null:   # formation buttons are drawn cards (no text): find it by its formation id
		for b in _all_buttons(battle.hud.root):
			if b.has_meta("fid") and str(b.get_meta("fid")) == "wide" and b.is_visible_in_tree():
				wide = b
	_check(wide != null, "formation button 'Wide' exists")
	if wide:
		var before := maya.post
		await _click(_button_center(wide))
		await _wait(0.3)
		_check(maya.post.distance_to(before) > 1.0, "formation 'Wide' repositioned the team")
		_check(battle.run.formation == "wide", "run formation set to wide")

	# 3. Select a defender with Tab and check the unit panel.
	await _key("cycle_defender")
	_check(battle.selected != null, "Tab selects a defender")

	# 4. Start the wave with Space.
	await _key("start_wave")
	await _wait(0.3)
	_check(battle.state == "wave", "Space starts the wave")
	battle.cam.default_view(true)

	# 5. Wait for runners, then select card 1 with the keyboard and cast it with a click.
	for i in 100:
		await _wait(0.1)
		if battle.enemies.size() > 0 and battle.cards.energy >= 3.0:
			break
	await _wait(1.5)
	var cast_ok := false
	for idx in battle.cards.hand.size():
		if battle.cards.check(idx) == "":
			var id: String = battle.cards.hand[idx]
			var hand_before := battle.cards.hand_count()
			var energy_before := battle.cards.energy
			await _key("card_%d" % (idx + 1))
			_check(battle.targeting_index == idx, "key %d selects card '%s'" % [idx + 1, id])
			var tpos := Field.MOUND
			var lead := battle.lead_runners(1)
			if not lead.is_empty():
				tpos = lead[0].global_position
			if DB.card(id).target == "defender":
				tpos = battle.defenders[0].global_position
			var sp := _screen_of(tpos + Vector3(0, 1.0, 0))
			_mouse_move(sp)
			await _wait(0.2)
			if not lead.is_empty() and is_instance_valid(lead[0]) and DB.card(id).target == "enemy":
				sp = _screen_of(lead[0].center())   # the runner kept running meanwhile
			await _click(sp)
			await _wait(0.4)
			cast_ok = battle.cards.hand_count() < hand_before or battle.cards.energy < energy_before - 0.5
			var hc := get_viewport().gui_get_hovered_control()
			_check(cast_ok, "clicking the field casts '%s' (energy %.1f -> %.1f)%s" % [id, energy_before, battle.cards.energy,
				"" if cast_ok else " at %s over %s %s, targeting %d" % [sp, hc.get_path() if hc else "field", hc.get_global_rect() if hc else "", battle.targeting_index]])
			break
	if not cast_ok:
		_check(false, "no castable card found in hand %s" % [battle.cards.hand])

	# 6. Right-click cancels targeting.
	for idx in battle.cards.hand.size():
		if battle.cards.check(idx) == "":
			await _key("card_%d" % (idx + 1))
			_check(battle.targeting_index >= 0, "card selected again for cancel test")
			await _click(Vector2(800, 400), MOUSE_BUTTON_RIGHT)
			_check(battle.targeting_index == -1, "right-click cancels targeting")
			break

	# 7. Pause and resume with Escape.
	await _key("pause")
	await _wait(0.2)
	_check(get_tree().paused, "Escape pauses the game")
	await _key("pause")
	await _wait(0.2)
	_check(not get_tree().paused, "Escape resumes the game")

	# 8. Fast-forward cycles speed.
	await _key("fast_forward")
	_check(Engine.time_scale == 2.0, "Shift sets 2x speed")
	await _key("fast_forward")
	await _key("fast_forward")
	_check(Engine.time_scale == 1.0, "Shift cycles back to 1x")

	# 9. Camera controls.
	var focus_before := battle.cam._t_focus
	Input.action_press("pan_left")
	await _wait(0.4)
	Input.action_release("pan_left")
	_check(battle.cam._t_focus.distance_to(focus_before) > 0.5, "A pans the camera")
	await _key("tactical_map")
	_check(battle.cam.tactical, "M toggles the tactical map")
	await _key("tactical_map")

	# 10. Let the inning play out (time-boosted) and test the dugout shop.
	Engine.time_scale = 4.0
	for i in 600:
		await _wait(0.1)
		if battle.state == "dugout" and battle.hud.get("_dugout") != null:
			break
		if battle.state == "break":
			battle.begin_wave()
	Engine.time_scale = 1.0
	_check(battle.state == "dugout", "reached the dugout after inning 1 (state=%s)" % battle.state)
	await _wait(1.0)
	var dug: Node = battle.hud.get("_dugout")
	if dug:
		var coins_before := battle.run.coins
		var buy: Button = null
		for b in _all_buttons(dug):
			if not b.disabled and b.text.is_valid_int():
				buy = b
				break
		if buy:
			await _click(_button_center(buy))
			await _wait(0.3)
			_check(battle.run.coins < coins_before, "buying an upgrade spends run coins (%d -> %d)" % [coins_before, battle.run.coins])
		var next := _find_button(dug, "NEXT INNING  ▶")
		_check(next != null, "dugout has a NEXT INNING button")
		if next:
			await _click(_button_center(next))
			for i in 100:
				await _wait(0.1)
				if battle.run.inning == 2 and battle.state == "setup":
					break
			_check(battle.run.inning == 2 and battle.state == "setup", "NEXT INNING starts inning 2 setup (inning=%d state=%s)" % [battle.run.inning, battle.state])
	_check(Profile.has_saved_run(), "run autosaved at the inning boundary")
	var saved_post: Vector3 = Vector3.ZERO
	for df in battle.defenders:
		if df.id == "maya":
			saved_post = df.post

	# 11. Quit to the main menu, then CONTINUE RUN.
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(1.0)
	var cont := _find_button(get_tree().current_scene, "CONTINUE RUN")
	_check(cont != null and not cont.disabled, "main menu offers CONTINUE RUN")
	if cont:
		await _click(_button_center(cont))
		battle = null
		for i in 300:
			await _wait(0.1)
			var sc := get_tree().current_scene
			if sc is Battle and (sc as Battle).state == "setup":
				battle = sc
				break
		_check(battle != null and battle.run.inning == 2, "continued run resumes at inning 2")
		if battle:
			var maya2: Defender = null
			for df in battle.defenders:
				if df.id == "maya":
					maya2 = df
			_check(maya2 != null and maya2.post.distance_to(saved_post) < 0.1, "defender positions restored on continue")
			_check(battle.run.formation == "wide", "formation restored on continue")
	Router.goto("main_menu")
	await _wait_scene("main_menu")

	# 12. Every main-menu destination opens and BACK returns.
	for pair in [["PLAY", "play_menu"], ["CARD PACKS", "packs"], ["CARDS & DECK", "deck_builder"], ["TEAM", "roster"],
			["PROGRESSION", "progression"], ["SETTINGS", "settings"]]:
		await _wait(0.6)
		if pair[0] == "SETTINGS":   # Update 10: Settings lives in the top bar's gear menu
			var gear: Button = get_tree().current_scene.find_child("GearButton", true, false)
			_check(gear != null, "main menu has the settings gear")
			if gear:
				await _click(_button_center(gear))
				await _wait(0.4)
		var b := _find_button_prefix(get_tree().current_scene, pair[0])
		_check(b != null, "main menu has %s" % pair[0])
		if b == null:
			continue
		await _click(_button_center(b))
		var ok := await _wait_scene(pair[1])
		_check(ok, "%s opens %s" % [pair[0], pair[1]])
		await _wait(0.8)
		var back := _find_button(get_tree().current_scene, "◀  BACK")
		_check(back != null, "%s has a BACK button" % pair[1])
		if back:
			await _click(_button_center(back))
			_check(await _wait_scene("main_menu"), "BACK returns to the main menu from %s" % pair[1])
	await _test_packs()
	await _test_multi_packs()
	await _test_deck_menus()
	await _test_auto_build()
	await _test_daily()
	await _test_missions()
	await _test_navigation()
	await _test_scouting()
	await _test_u9_e2()
	await _test_u10_team()
	await _test_u11_defenders()
	await _test_title()
	await _test_u9_hub_play_results()
	await _test_u10_hub()
	await _test_tutorial()
	await _test_draft()
	await _test_u11_prestige()
	_finish()


## Update 9 screens (stream E1): the hub's new elements (quick mode switch, Season tier bar, win
## streak flame, login calendar, Shop tile), keyboard focus on the hub and Play, the Play screen's
## mode cards (Boss Rush included) with records and payouts, the stadium carousel, and the Results
## sections for the new reward keys.
func _test_u9_hub_play_results() -> void:
	Profile.data.flags["tutorial_done"] = true
	if (Profile.data.history as Array).is_empty():   # the hub waits for a finished game for some tiles
		Profile.add_history({"won": true, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "inning": 3, "score": 100, "outs": 30, "runs": 0, "date": Time.get_datetime_string_from_system()})
	var saved_run: Variant = Profile.data.current_run
	Profile.data.current_run = null
	var last_mode := str(Profile.data.flags.get("last_mode", "standard"))
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(1.2)
	var hub: Node = get_tree().current_scene
	for n in ["PlayButton", "ModeSwitch", "SeasonBar", "StreakFlame", "LoginPanel", "DailyPanel", "MissionsWidget", "ShopTile", "ScoutingBookTile"]:
		var c: Control = hub.find_child(n, true, false)
		_check(c != null and c.is_visible_in_tree(), "hub shows %s" % n)
	# Badges are corner bubbles that never cover a tile's label.
	var covered: Array = []
	for bd in hub.find_children("CornerBadge", "PanelContainer", true, false):
		var host: Button = bd.get_parent() as Button
		if host and host.text != "":
			var label_y := host.get_global_rect().position.y + (host.size.y - host.get_theme_font_size("font_size")) * 0.5
			if (bd as Control).get_global_rect().end.y > label_y + 2.0:
				covered.append(host.text)
	_check(covered.is_empty(), "hub badges sit above the tile labels %s" % [covered])
	# Login calendar: seven days, and CLAIM takes today's reward.
	var days: Control = hub.find_child("LoginDays", true, false)
	_check(days != null and days.get_child_count() == 7, "the login calendar shows seven days")
	var claim: Button = hub.find_child("LoginClaim", true, false)
	if DailyRewards.can_claim():
		_check(claim != null, "the login calendar offers CLAIM")
		if claim:
			await _click(_button_center(claim))
			await _wait(0.6)
			_check(not DailyRewards.can_claim() and hub.find_child("LoginClaim", true, false) == null, "CLAIM takes today's login reward")
	if Shop.gift_available():
		_check(_find_label(hub.find_child("ShopTile", true, false), "FREE GIFT"), "the free gift shows on the Shop tile")
	# Quick mode switch: Boss Rush changes what PLAY opens with.
	var chip: Button = hub.find_child("Mode_boss_rush", true, false)
	_check(chip != null, "the quick mode switch offers Boss Rush")
	if chip and not chip.disabled:
		await _click(_button_center(chip))
		await _wait(0.3)
		_check(str(Profile.data.flags.get("last_mode", "")) == "boss_rush" and chip.button_pressed, "picking Boss Rush on the switch selects it")
		var hero: Button = hub.find_child("PlayButton", true, false)
		var t_top: Label = hub.find_child("HeroTitleTop", true, false)
		var t_main: Label = hub.find_child("HeroTitleMain", true, false)
		_check(t_top != null and t_main != null and t_top.text == "BOSS" and t_main.text == "RUSH", "the hero title shows the picked mode")
		# Keyboard: the first arrow press focuses PLAY, Enter opens the Play screen on Boss Rush.
		_mouse_move(Vector2(960, 1000))
		await _wait(0.2)
		get_viewport().gui_release_focus()
		await _key_event(KEY_DOWN)
		_check(get_viewport().gui_get_focus_owner() == hero, "an arrow key focuses PLAY on the hub (%s)" % get_viewport().gui_get_focus_owner())
		await _key_event(KEY_ENTER)
		_check(await _wait_scene("play_menu"), "Enter on PLAY opens the Play screen")
		await _wait(0.8)
		var pm0: Node = get_tree().current_scene
		_check(str(pm0.get("mode_id")) == "boss_rush", "Play opens on the mode picked on the hub (%s)" % pm0.get("mode_id"))
		Router.goto("main_menu")
		await _wait_scene("main_menu")
		await _wait(1.0)
		hub = get_tree().current_scene
	# Season tier bar opens the Season screen; the Shop tile opens the Shop.
	for pair in [["SeasonBar", "season"], ["ShopTile", "shop"]]:
		var b: Button = hub.find_child(pair[0], true, false)
		if b == null:
			continue
		await _click(_button_center(b))
		_check(await _wait_scene(pair[1]), "%s opens %s" % [pair[0], pair[1]])
		Router.goto("main_menu")
		await _wait_scene("main_menu")
		await _wait(1.0)
		hub = get_tree().current_scene
	# Play: every mode has a big card; Boss Rush can be picked; records and payouts are shown.
	Router.goto("play_menu")
	await _wait_scene("play_menu")
	await _wait(0.8)
	var pm: Node = get_tree().current_scene
	var cards: Dictionary = pm.get("_mode_buttons")
	_check(cards.has("boss_rush") and cards.has("daily") and cards.has("endless") and cards.has("ranked") and cards.has("practice")
		and cards.has("standard") and cards.has("quick"), "Play has a card for every mode %s" % [cards.keys()])
	var br: Button = cards.get("boss_rush")
	if br:
		var texts: Array = []
		for l in br.find_children("*", "Label", true, false):
			texts.append((l as Label).text)
		_check("BOSS RUSH" in texts and texts.any(func(t: String) -> bool: return t.contains("Pro Pack")), "the Boss Rush card names the mode and what a win pays %s" % [texts])
		_check(texts.any(func(t: String) -> bool: return t.begins_with("Best") or t == "No record yet"), "the Boss Rush card shows your record")
		await _click(_button_center(br))
		await _wait(0.4)
		_check(str(pm.get("mode_id")) == "boss_rush" and br.button_pressed, "clicking the Boss Rush card selects it")
	var practice: Button = cards.get("practice")
	if practice:
		await _click(_button_center(practice))
		await _wait(0.4)
		var veteran: Button = pm.find_child("Diff_veteran", true, false)
		_check(veteran != null and veteran.disabled, "Practice locks the difficulty")
		await _click(_button_center(cards["standard"]))
		await _wait(0.4)
	var vet: Button = pm.find_child("Diff_veteran", true, false)
	var diff_before := str(Profile.data.difficulty)
	if vet:
		await _click(_button_center(vet))
		await _wait(0.3)
		_check(str(Profile.data.difficulty) == "veteran" and vet.button_pressed, "a difficulty button selects it")
		var std_texts: Array = []
		for l in (cards["standard"] as Button).find_children("*", "Label", true, false):
			std_texts.append((l as Label).text)
		_check(std_texts.any(func(t: String) -> bool: return t.contains("Champion Pack")), "the Standard card's payout follows the difficulty (Veteran: Champion Pack)")
		var d0: Button = pm.find_child("Diff_" + diff_before, true, false)
		if d0:
			await _click(_button_center(d0))
			await _wait(0.3)
	# Stadium carousel: one big preview, thumbnails for unlocked stadiums, text rows for locked ones.
	var unlocked: Array = Profile.data.arenas_unlocked
	_check(pm.find_children("ArenaPreview", "", true, false).size() == 1, "the stadium panel shows one big preview")
	var locked_tiles := 0
	for b in _all_buttons(pm):
		if b.name.begins_with("Arena_") and not b.name.trim_prefix("Arena_") in unlocked:
			locked_tiles += 1
	_check(locked_tiles == 0, "locked stadiums are not shown as tiles")
	if unlocked.size() < DB.arena_order.size():
		_check(pm.find_child("LockedArenas", true, false) != null, "locked stadiums are listed with their unlock text")
	if unlocked.size() >= 2:
		var before := str(Profile.data.arena)
		var nxt: Button = pm.find_child("ArenaNext", true, false)
		await _click(_button_center(nxt))
		await _wait(0.3)
		_check(str(Profile.data.arena) != before and str(Profile.data.arena) in unlocked, "the carousel's ▶ picks the next stadium")
		Profile.data.arena = before
	var streak_box: Control = pm.find_child("StreakBonus", true, false)
	_check(streak_box != null and streak_box.find_child("StreakFlame", true, false) != null, "Play shows the win streak bonus")
	# Keyboard: the first arrow press focuses START; arrows then move between buttons.
	_mouse_move(Vector2(960, 1060))
	get_viewport().gui_release_focus()
	await _key_event(KEY_DOWN)
	var start: Button = pm.get("_start")
	_check(get_viewport().gui_get_focus_owner() == start, "an arrow key focuses START on the Play screen")
	await _key_event(KEY_UP)
	var f := get_viewport().gui_get_focus_owner()
	_check(f != null and f != start, "arrow keys move the focus on from START (%s)" % (f.name if f else "none"))
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	# Results: the new reward sections.
	var res: Control = load("res://src/ui/results_screen.gd").new()
	res.result = {"won": true, "mode": "standard", "difficulty": "standard", "arena": "steel_yard", "coins": 600, "xp": 300, "rp": 60,
		"levels": 0, "innings_cleared": 9, "outs": 120, "runs": 1, "run_limit": 3, "score": 9000, "mvp": "ace",
		"defender_xp": {"ace": {"xp": 40, "levels": 0, "level": 2, "level_before": 2, "xp_before": 10, "xp_after": 50, "rewards": [], "outs": 9}},
		"packs": [{"type": "pro", "source": "test"}], "stats": {"cards_played": 10, "timeline": []},
		"streak": 3, "streak_bonus_coins": 90, "first_win_today_coins": 200, "season_xp": 160, "season_tiers": [],
		"boons": Boons.all().slice(0, 2).map(func(b: Dictionary) -> String: return str(b.get("id", ""))),
		"milestones": [5, 10], "milestone_coins": 450, "overflow_coins": 80, "promoted": true, "promotion_reward": {"coins": 300, "stars": 10, "pack": "pro"}}
	get_tree().current_scene.add_child(res)
	await _wait(5.0)
	var chips: Control = res.find_child("CoinBonuses", true, false)
	_check(chips != null and chips.get_child_count() == 4, "Results list the streak, first-win, milestone and extra-copy coins")
	_check(res.find_child("SeasonXP", true, false) != null, "Results show the season XP bar")
	_check(res.find_child("Milestones", true, false) != null, "Results show the Endless milestones")
	_check(res.find_child("PromotionReward", true, false) != null, "Results show the promotion reward")
	if not Boons.all().is_empty():
		_check(res.find_child("BoonsTaken", true, false) != null, "Results list the boons drafted")
	var counter: Control = res.find_child("Counter_COINS", true, false)
	var coin_l: Label = counter.find_child("Value", true, false) if counter else null
	for i in 50:   # a loaded machine renders slowly: give the count-up time to finish
		if coin_l == null or coin_l.text == "+600":
			break
		await _wait(0.2)
	_check(coin_l != null and coin_l.text == "+600", "the coin counter finishes on the coins earned (%s, alpha %.2f, in tree %s, paused %s)" % [
		coin_l.text if coin_l else "none", counter.modulate.a if counter else -1.0, counter.is_inside_tree() if counter else false, get_tree().paused])
	# Nothing is cut off at 1080p: the panels' content fits without scrolling.
	var cut: Array = []
	for sc in res.find_children("*", "ScrollContainer", true, false):
		var inner: Control = (sc as ScrollContainer).get_child(0)
		if inner and inner.get_combined_minimum_size().y > (sc as Control).size.y + 1.0:
			cut.append("%s %d>%d" % [(sc as Control).get_parent().name, inner.get_combined_minimum_size().y, (sc as Control).size.y])
	_check(cut.is_empty(), "every Results column fits on screen %s" % [cut])
	res.queue_free()
	await _wait(0.3)
	Profile.data.current_run = saved_run
	Profile.data.flags["last_mode"] = last_mode
	Router.goto("main_menu")
	await _wait_scene("main_menu")


## Update 10 broadcast hub: the top bar's values, CONTINUE RUN only with a saved run, the hero
## title and mode chips, the three TODAY cards, the bottom bar, the gear menu (Settings, Practice,
## Exit; Esc opens and closes it) and a layout where nothing overlaps or leaves the screen.
func _test_u10_hub() -> void:
	Profile.data.flags["tutorial_done"] = true
	if (Profile.data.history as Array).is_empty():
		Profile.add_history({"won": true, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "inning": 3, "score": 100, "outs": 30, "runs": 0, "date": Time.get_datetime_string_from_system()})
	var saved_run: Variant = Profile.data.current_run
	var last_mode := str(Profile.data.flags.get("last_mode", "standard"))
	# No saved run: no CONTINUE RUN card.
	Profile.data.current_run = null
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(1.2)
	var hub: Node = get_tree().current_scene
	_check(hub.find_child("ContinueRun", true, false) == null and _find_button(hub, "CONTINUE RUN") == null, "no CONTINUE RUN card without a saved run")
	# Top bar values.
	var d: Dictionary = Profile.data
	var owned := 0
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned += 1
	var want := {"CoinsValue": UITheme.format_int(int(d.coins)), "StarsValue": UITheme.format_int(int(d.stars)),
		"CardsValue": "%d/%d" % [owned, DB.card_order.size()], "LevelText": "LEVEL %d" % int(d.level), "ManagerName": str(d.name).to_upper()}
	for k in want.keys():
		var l: Label = hub.find_child(k, true, false)
		_check(l != null and l.is_visible_in_tree() and l.text == want[k], "the top bar shows %s = %s (%s)" % [k, want[k], l.text if l else "missing"])
	var div_l: Label = hub.find_child("DivisionText", true, false)
	_check(div_l != null and div_l.text.contains("DIVISION") and div_l.text.ends_with("RP"), "the top bar shows the division and RP")
	var xp_l: Label = hub.find_child("XPText", true, false)
	_check(xp_l != null and (xp_l.text.ends_with(" XP") or xp_l.text == "MAX LEVEL"), "the top bar shows the XP numbers")
	_check(hub.find_child("LevelBar", true, false) != null and _find_button(hub, "?") != null and hub.find_child("GearButton", true, false) != null,
		"the top bar has the level bar, ? and the settings gear")
	# Hero: ribbon, title, venue, chips.
	_check(hub.find_child("BroadcastRibbon", true, false) != null, "the hero block has the BROADCAST MATCHDAY ribbon")
	var venue: Label = hub.find_child("HeroVenue", true, false)
	_check(venue != null and venue.text.contains(str(DB.difficulty(str(Profile.data.difficulty)).get("name", "")).to_upper()), "the hero shows the stadium and difficulty")
	var sw: Control = hub.find_child("ModeSwitch", true, false)
	var chip_names: Array = []
	var pressed := 0
	if sw:
		for c in sw.get_children():
			chip_names.append(str(c.name))
			if (c as Button).button_pressed:
				pressed += 1
	_check(chip_names == ["Mode_quick", "Mode_standard", "Mode_boss_rush", "Mode_endless"], "the mode chips are QUICK, SIEGE, BOSS RUSH, ENDLESS %s" % [chip_names])
	_check(pressed == 1, "exactly one mode chip is highlighted")
	_check(hub.find_child("SeasonBar", true, false) != null and hub.find_child("StreakFlame", true, false) != null, "the Season and win streak chips are on the hub")
	# TODAY cards.
	var daily: Control = hub.find_child("DailyPanel", true, false)
	_check(daily != null and daily.find_child("DailyRewards", true, false) != null and daily.find_child("DailyButton", true, false) != null,
		"the Daily Challenge card has PLAY DAILY and a REWARDS strip")
	var mis: Control = hub.find_child("MissionsWidget", true, false)
	var rows := 0
	var mrows: Node = mis.find_child("MissionRows", true, false) if mis else null
	if mrows:
		for c in mrows.get_children():
			if c is HBoxContainer:
				rows += 1
	_check(mis != null and rows == 3 and mis.find_child("MissionRewards", true, false) != null and mis.find_child("MissionsButton", true, false) != null,
		"the Missions card has three rows, OPEN and a REWARDS strip (%d rows)" % rows)
	var login: Control = hub.find_child("LoginPanel", true, false)
	var days: Control = hub.find_child("LoginDays", true, false)
	var nxt: Label = hub.find_child("LoginNext", true, false)
	_check(login != null and days != null and days.get_child_count() == 7 and nxt != null and nxt.text != ""
		and (hub.find_child("LoginClaim", true, false) != null or hub.find_child("LoginClaimed", true, false) != null),
		"the Daily Login card has CLAIM/CLAIMED, the next reward line and seven days")
	# Bottom bar.
	var bottom: Control = hub.find_child("HubBottom", true, false)
	var names: Array = []
	if bottom:
		for c in bottom.get_children():
			if c is Button:
				names.append((c as Button).text)
	_check(names == ["CARDS & DECK", "CARD PACKS", "UPGRADE CARDS", "TEAM", "SHOP", "SCOUTING BOOK", "PROGRESSION"], "the bottom bar lists the destinations %s" % [names])
	# Layout: nothing overlaps or leaves the screen, and no button is squeezed below its text.
	var vp := (hub.get_viewport() as Viewport).get_visible_rect()
	var left_r := (hub.find_child("HubLeft", true, false) as Control).get_global_rect()
	var today_r := (hub.find_child("TodayBackdrop", true, false) as Control).get_global_rect()
	var bottom_r := (hub.find_child("BottomBar", true, false) as Control).get_global_rect()
	var top_r := (hub.find_child("TopBar", true, false) as Control).get_global_rect()
	_check(not left_r.intersects(today_r) and left_r.end.y <= bottom_r.position.y and left_r.position.y >= top_r.end.y
		and today_r.end.y <= bottom_r.position.y + 1.0, "the hero block, TODAY and the bars do not overlap (%s %s)" % [left_r, today_r])
	var outside: Array = []
	var squeezed: Array = []
	for b in _all_buttons(hub):
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		if r.position.x < vp.position.x - 1 or r.end.x > vp.end.x + 1 or r.end.y > vp.end.y + 1:
			outside.append(b.name)
		if b.text != "" and b.size.x + 1.0 < b.get_combined_minimum_size().x:
			squeezed.append(b.name)
	_check(outside.is_empty(), "every hub button is on screen %s" % [outside])
	_check(squeezed.is_empty(), "no hub button is squeezed below its text %s" % [squeezed])
	var today_inner: Control = hub.find_child("HubRight", true, false)
	_check(today_inner != null and today_inner.get_combined_minimum_size().y <= today_r.size.y - 20.0, "the TODAY cards fit the panel (%d of %d)" % [
		today_inner.get_combined_minimum_size().y if today_inner else -1, today_r.size.y])
	# Gear menu: Settings, Practice and Exit; Esc opens and closes it.
	var gear: Button = hub.find_child("GearButton", true, false)
	if gear:
		await _click(_button_center(gear))
		await _wait(0.4)
		var ok := true
		for n in ["SettingsButton", "PracticeButton", "ExitButton"]:
			var gb: Button = hub.find_child(n, true, false)
			ok = ok and gb != null and gb.is_visible_in_tree()
		_check(ok, "the gear opens Settings, Practice and Exit")
		_check(get_viewport().gui_get_focus_owner() == hub.find_child("SettingsButton", true, false), "the gear menu focuses SETTINGS")
		await _key("pause")
		await _wait(0.3)
		var gm: Node = hub.find_child("GearMenu", true, false)
		_check(gm == null or gm.is_queued_for_deletion(), "Esc closes the gear menu")
		get_viewport().gui_release_focus()
		await _wait(0.2)
		await _key("pause")
		await _wait(0.3)
		var pr: Button = hub.find_child("PracticeButton", true, false)
		_check(pr != null and pr.is_visible_in_tree() and Router.current == "main_menu", "Esc on the hub opens the gear menu")
		await _key("pause")
		await _wait(0.3)
	# A saved run: the CONTINUE RUN card with the mode, inning and stadium.
	Profile.data.current_run = {"arena_id": "steel_yard", "config": {"mode": "endless"}, "inning": 7, "mode_id": "endless", "saved_at": "test"}
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(1.0)
	hub = get_tree().current_scene
	var cont := _find_button(hub, "CONTINUE RUN")
	var det: Label = hub.find_child("ContinueDetail", true, false)
	_check(cont != null and det != null and det.text.contains("Inning 7") and det.text.contains(str(DB.mode("endless").name)), "CONTINUE RUN shows the saved run (%s)" % (det.text if det else "none"))
	if cont:
		var hero_r := (hub.find_child("PlayButton", true, false) as Control).get_global_rect()
		_check(cont.get_global_rect().end.y <= hero_r.position.y, "CONTINUE RUN sits above PLAY")
	_check((hub.find_child("HubLeft", true, false) as Control).get_global_rect().end.y <= (hub.find_child("BottomBar", true, false) as Control).get_global_rect().position.y,
		"the hero block with CONTINUE RUN still clears the bottom bar")
	Profile.data.current_run = saved_run
	Profile.data.flags["last_mode"] = last_mode
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(0.5)


## Presses and releases a key (for the built-in ui_* focus actions).
func _key_event(code: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = code
	k.physical_keycode = code
	k.pressed = true
	Input.parse_input_event(k)
	await _wait(0.05)
	var k2 := k.duplicate() as InputEventKey
	k2.pressed = false
	Input.parse_input_event(k2)
	await _wait(0.15)


func _find_button_prefix(root: Node, text: String) -> Button:
	for b in _all_buttons(root):
		if b.text.strip_edges().begins_with(text) and b.is_visible_in_tree():
			return b
	return null


## 13. Card packs: open a pack, flip a card by clicking it, reveal the rest, finish.
func _test_packs() -> void:
	Profile.add_pack("rookie", "UI test")
	Profile.add_pack("rookie", "UI test")
	Router.goto("packs")
	_check(await _wait_scene("packs"), "packs screen opens")
	await _wait(1.2)
	var ps: Node = get_tree().current_scene
	var packs_before := Profile.pack_count()
	var open := _find_button(ps, "OPEN PACK")
	_check(open != null and not open.disabled, "packs screen offers OPEN PACK")
	if open == null:
		return
	await _click(_button_center(open))
	for i in 80:
		await _wait(0.1)
		if ps.state == "reveal":
			break
	_check(ps.state == "reveal", "opening animation reaches the reveal (state %s)" % ps.state)
	_check(Profile.pack_count() == packs_before - 1, "opening consumes one pack")
	_check(ps._cards.size() == int(DB.pack("rookie").cards), "a Rookie Pack reveals %d cards" % int(DB.pack("rookie").cards))
	if ps._cards.is_empty():
		return
	var first: Node3D = ps._cards[0].root
	var sp: Vector2 = get_viewport().get_final_transform() * ps.camera.unproject_position(first.global_position)
	await _click(sp)
	await _wait(1.0)
	_check(bool(ps._cards[0].revealed), "clicking a face-down card flips it")
	var all := _find_button(ps, "REVEAL ALL")
	_check(all != null, "REVEAL ALL button shown")
	if all:
		await _click(_button_center(all))
	for i in 60:
		await _wait(0.1)
		if ps.state == "done":
			break
	_check(ps.state == "done", "every card revealed")
	for c in ps._result.get("cards", []):
		_check(Profile.is_card_owned(c.id), "pack card %s is in the collection" % c.id)
	var next := _find_button_prefix(ps, "OPEN NEXT PACK")
	_check(next != null, "OPEN NEXT PACK offered while packs remain")
	if next:
		await _click(_button_center(next))
		for i in 30:
			await _wait(0.1)
			if ps.state == "idle":
				break
		_check(ps.state == "idle", "pack screen returns to the next pack")
	Router.goto("main_menu")
	await _wait_scene("main_menu")


## 13b. Pack shop bundle and multi-open: BUY 10, OPEN ×10, REVEAL ALL, DONE.
func _test_multi_packs() -> void:
	var n: int = Profile.BUNDLE_SIZE
	var price := int(Profile.pack_price("rookie", n).coins)
	Profile.data.coins = price + 100
	Router.goto("packs")
	_check(await _wait_scene("packs"), "packs screen opens for the bundle test")
	await _wait(1.2)
	var ps: Node = get_tree().current_scene
	var buy: Button = ps._buy_buttons.get("rookie:%d" % n)
	_check(buy != null and not buy.disabled, "Rookie Pack has an enabled BUY 10 button")
	var pro_buy: Button = ps._buy_buttons.get("pro:%d" % n)
	_check(pro_buy != null and pro_buy.disabled, "an unaffordable BUY 10 is disabled")
	if buy == null:
		return
	var rookies := Profile.pack_count("rookie")
	await _click(_button_center(buy))
	await _wait(0.6)
	_check(Profile.pack_count("rookie") == rookies + n, "BUY 10 adds 10 Rookie Packs (%d -> %d)" % [rookies, Profile.pack_count("rookie")])
	_check(int(Profile.data.coins) == 100, "BUY 10 charges the bundle price (%d left)" % int(Profile.data.coins))
	_check(ps.selected.get("type", "") == "rookie", "the bought pack type is shown on the stage")
	var five := _find_button(ps, "OPEN ×5")
	var ten := _find_button(ps, "OPEN ×10")
	_check(five != null and not five.disabled, "OPEN ×5 offered with 10+ packs")
	_check(ten != null and not ten.disabled, "OPEN ×10 offered with 10+ packs")
	if ten == null:
		return
	var before := Profile.pack_count("rookie")
	var opened := int(Profile.data.packs_opened)
	await _click(_button_center(ten))
	for i in 120:
		await _wait(0.1)
		if ps.state == "reveal":
			break
	_check(ps.state == "reveal" and ps._multi != null, "the ×10 opening reaches the summary grid (state %s)" % ps.state)
	_check(Profile.pack_count("rookie") == before - n and int(Profile.data.packs_opened) == opened + n, "OPEN ×10 consumes 10 packs")
	if ps._multi == null:
		return
	var summary: PackSummary = ps._multi
	var pulled := 0
	for e in summary.entries:
		pulled += int(e.count)
	_check(pulled == n * int(DB.pack("rookie").cards), "the grid holds all %d cards (%d)" % [n * int(DB.pack("rookie").cards), pulled])
	var sorted_ok := true
	for i in range(1, summary.entries.size()):
		sorted_ok = sorted_ok and DB.rarity_index(summary.entries[i - 1].rarity) >= DB.rarity_index(summary.entries[i].rarity)
	_check(sorted_ok, "the grid is sorted best rarity first")
	var vp_rect := get_viewport().get_visible_rect()
	var inside := true
	for e in summary.entries:
		inside = inside and vp_rect.encloses((e.view as Control).get_global_rect())
	_check(inside or summary._scroll.get_v_scroll_bar().visible, "every card fits on screen (or the grid scrolls)")
	var all := _find_button(ps, "REVEAL ALL")
	_check(all != null, "REVEAL ALL shown for the multi-open")
	if all:
		await _click(_button_center(all))
	for i in 150:
		await _wait(0.1)
		if ps.state == "done":
			break
	_check(ps.state == "done", "every multi-open card revealed")
	_check(summary.entries.all(func(e: Dictionary) -> bool: return e.revealed and not (e.view as CardView).face_down), "all grid cards face up")
	var done := _find_button(ps, "DONE")
	_check(done != null, "DONE shown after the multi-open")
	if done:
		await _click(_button_center(done))
		for i in 40:
			await _wait(0.1)
			if ps.state == "idle":
				break
		_check(ps.state == "idle" and ps._multi == null, "DONE returns to the pack screen")
		await _wait(0.6)
		_check(not is_instance_valid(summary), "the summary grid is removed")
	Router.goto("main_menu")
	await _wait_scene("main_menu")


## 15. Cards & Deck: clicking removes/adds cards (a full deck saves automatically), then
## UPGRADE CARDS opens the Card Upgrades screen where a card with enough copies levels up.
func _test_deck_menus() -> void:
	for cid in ["splitter", "knuckleball", "changeup"]:
		Profile.grant_card(cid)
	Session.menu_tab = "deck"
	Router.goto("deck_builder")
	_check(await _wait_scene("deck_builder"), "Cards & Deck opens")
	await _wait(1.0)
	var db: Node = get_tree().current_scene
	var saved: Array = Profile.data.deck.duplicate()
	_check(db._slots.size() == Profile.DECK_SIZE and db.deck.size() == Profile.DECK_SIZE, "deck shows 8 filled slots")
	var first: CardView = db._slot_cards[0]
	var removed := first.card_id
	await _click(_ctl_center(first))
	await _wait(0.5)
	_check(db.deck.size() == Profile.DECK_SIZE - 1 and not removed in db.deck, "clicking a deck card removes it")
	_check(Profile.data.deck == saved, "an incomplete deck is not saved")
	_check("1 more" in str(db._need_label.text), "deck asks for one more card ('%s')" % db._need_label.text)
	var scroll: Control = db._owned_grid.get_parent().get_parent()
	var add_id := ""
	for cid in db._col_views.keys():
		var v: CardView = db._col_views[cid]
		if Profile.is_card_owned(cid) and not cid in db.deck and scroll.get_global_rect().encloses(v.get_global_rect()):
			add_id = cid
			break
	_check(add_id != "", "a visible owned card is outside the deck")
	if add_id != "":
		await _click(_ctl_center(db._col_views[add_id]))
		await _wait(0.8)
		_check(db.deck.size() == Profile.DECK_SIZE and add_id in db.deck, "clicking a collection card adds it to the deck")
		_check(Profile.data.deck == db.deck, "the full deck is saved automatically")
		_check(db._pills.has(add_id) and db._pills[add_id].visible, "the added card is marked IN DECK")
	var cid_up: String = Profile.data.deck[0]
	Profile.data.cards[cid_up].copies = 20
	Profile.data.coins = maxi(int(Profile.data.coins), 5000)
	var upb := _find_button(db, "UPGRADE CARDS  ▶")
	_check(upb != null, "Cards & Deck has an UPGRADE CARDS button")
	if upb == null:
		return
	await _click(_button_center(upb))
	_check(await _wait_scene("card_upgrades"), "UPGRADE CARDS opens the card upgrades screen")
	await _wait(1.0)
	var us: Node = get_tree().current_scene
	_check(us.ready_count() >= 1, "upgrade screen counts ready cards (%d)" % us.ready_count())
	us._select(cid_up)
	await _wait(0.3)
	var lvl := Profile.card_level(cid_up)
	var coins := int(Profile.data.coins)
	var big := _find_button(us, "UPGRADE TO LEVEL %d" % (lvl + 1))
	_check(big != null and not big.disabled, "UPGRADE button is enabled for %s" % cid_up)
	if big:
		await _click(_button_center(big))
		await _wait(0.3)
		_check(Profile.card_level(cid_up) == lvl + 1, "UPGRADE raises %s to level %d" % [cid_up, Profile.card_level(cid_up)])
		_check(int(Profile.data.coins) < coins, "the upgrade spends coins (%d -> %d)" % [coins, int(Profile.data.coins)])
		for i in 60:
			await _wait(0.1)
			if not us._busy:
				break
		_check(not us._busy and us.selected == cid_up, "upgrade animation finishes (busy %s, selected %s)" % [us._busy, us.selected])
	# Upgrade All: enough copies and coins for several level-ups, then button -> confirm -> applied.
	var owned_ids: Array = []
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned_ids.append(cid)
	for cid in owned_ids.slice(0, 3):
		Profile.data.cards[cid].copies = 100
	Profile.data.coins = 4000
	us._rebuild()
	await _wait(0.3)
	var plan: Dictionary = Profile.upgrade_all_plan()
	var all_btn: Button = us._all_btn
	_check(all_btn != null and not all_btn.disabled and "(%d)" % plan.levels in all_btn.text, "UPGRADE ALL shows the level-ups available (%s)" % (all_btn.text if all_btn else "missing"))
	if all_btn and not all_btn.disabled:
		await _click(_button_center(all_btn))
		await _wait(0.4)
		var confirm := _find_button(us, "UPGRADE ALL")
		_check(confirm != null, "UPGRADE ALL asks for confirmation")
		if confirm:
			await _click(_button_center(confirm))
			await _wait(0.4)
			var all_up := true
			for e in plan.cards:
				if Profile.card_level(e.id) != int(e.to):
					all_up = false
			_check(all_up and int(Profile.data.coins) == 4000 - int(plan.coins), "UPGRADE ALL levels every planned card and spends %d coins" % int(plan.coins))
			for i in 40:
				await _wait(0.1)
				if not us._busy:
					break
			_check(not us._busy and us._all_btn.disabled, "nothing left to upgrade afterwards (button disabled)")
	var back := _find_button(us, "◀  BACK")
	_check(back != null, "card upgrades has a BACK button")
	if back:
		await _click(_button_center(back))
		_check(await _wait_scene("deck_builder"), "BACK from Card Upgrades returns to Cards & Deck")
	await _wait(0.5)
	Router.goto("main_menu")
	await _wait_scene("main_menu")


func _shift_click(p: Vector2) -> void:
	_mouse_move(p)
	await _wait(0.05)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.position = p
		e.global_position = p
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.shift_pressed = true
		Input.parse_input_event(e)
		await _wait(0.05)
	await _wait(0.1)


## A visible owned collection card that is not `except`.
func _visible_card(db: Node, except: Array) -> String:
	var scroll: Control = db._owned_grid.get_parent().get_parent()
	for cid in DB.card_order:
		if db._col_views.has(cid) and not cid in except and Profile.is_card_owned(cid):
			var v: CardView = db._col_views[cid]
			if scroll.get_global_rect().encloses(v.get_global_rect()):
				return cid
	return ""


## 15b. Auto Build and card comparison: Auto Build changes the deck, saves it and explains it (banner
## and slot chips); UNDO restores the old deck; COMPARE + a click opens two cards side by side, CHANGE
## swaps one side, shift-click starts a comparison too, and Esc closes it without leaving the screen.
func _test_auto_build() -> void:
	var saved_cards: Dictionary = Profile.data.cards.duplicate(true)
	var saved_deck: Array = Profile.data.deck.duplicate()
	for cid in DB.card_order:
		Profile.grant_card(cid)
	Profile.data.deck = Profile.STARTER_DECK.duplicate()
	Session.menu_tab = "deck"
	Router.goto("deck_builder")
	_check(await _wait_scene("deck_builder"), "Cards & Deck opens (auto build)")
	await _wait(1.0)
	var db: Node = get_tree().current_scene
	var old: Array = Profile.data.deck.duplicate()
	_check(db._auto_btn != null and db._undo_btn.disabled, "Auto Build button shown, Undo disabled at first")
	await _click(_button_center(db._auto_btn))
	await _wait(1.0)
	var seen := {}
	for cid in db.deck:
		seen[cid] = true
	_check(db.deck.size() == Profile.DECK_SIZE and seen.size() == Profile.DECK_SIZE and db.deck != old, "Auto Build fills 8 different cards and changes the deck (%s)" % [db.deck])
	_check(Profile.data.deck == db.deck, "the auto-built deck is saved")
	_check(db._banner.visible and "avg cost" in str(db._banner_text.text), "the summary banner explains the deck ('%s')" % db._banner_text.text)
	var chips := 0
	for ch in db._chips:
		if ch.visible and ch.text != "":
			chips += 1
	_check(chips == Profile.DECK_SIZE, "every deck slot shows a reason chip (%d)" % chips)
	db._inspect(db.deck[0])
	await _wait(0.3)
	_check(db._detail.find_child("WhyBlock", true, false) != null, "the inspector says why a deck card was picked")
	_check(not db._undo_btn.disabled, "Undo is available after Auto Build")
	var undo := _find_button(db._banner, "UNDO")
	_check(undo != null, "the banner has an UNDO button")
	if undo:
		await _click(_button_center(undo))
		await _wait(0.6)
		_check(db.deck == old and Profile.data.deck == old, "UNDO restores (and saves) the previous deck")
		_check(not db._banner.visible and db._undo_btn.disabled, "the banner hides after UNDO")
	# Another style gives a deck that fits it.
	db._mode_btn.select(DeckAI.MODES.find("boss"))
	db._mode_btn.item_selected.emit(DeckAI.MODES.find("boss"))
	await _click(_button_center(db._auto_btn))
	await _wait(0.8)
	var bosses := 0
	for cid in db.deck:
		if "boss" in DeckAI.analyze(cid, Profile.card_level(cid)).tags:
			bosses += 1
	_check(bosses >= 2 and "BOSS KILLER" in str(db._banner_title.text), "Boss Killer style picks 2+ boss answers (%d)" % bosses)
	_check(str(Profile.data.flags.get("auto_build_mode", "")) == "boss", "the chosen style is remembered")
	# Compare: COMPARE in the inspector, then click a second card.
	var a: String = db.deck[0]
	db._inspect(a)
	await _wait(0.3)
	_check(db._compare_btn != null and db._compare_btn.is_visible_in_tree(), "the inspector has a COMPARE button")
	await _click(_button_center(db._compare_btn))
	await _wait(0.3)
	_check(db._pick_side == 1 and db._pick_bar != null and db._pick_bar.visible, "COMPARE asks for a second card")
	var b := _visible_card(db, [a])
	_check(b != "", "a second card is visible")
	if b != "":
		await _click(_ctl_center(db._col_views[b]))
		await _wait(0.5)
		var cmp: Node = db._compare
		_check(cmp != null and is_instance_valid(cmp) and cmp.visible and cmp.ids == [a, b], "clicking a card opens the comparison of %s and %s" % [a, b])
		_check(db.deck.size() == Profile.DECK_SIZE and Profile.data.deck == db.deck, "picking a card to compare does not edit the deck")
		if cmp:
			_check(cmp.find_child("Side0", true, false) != null and cmp.find_child("Side1", true, false) != null, "both cards are shown side by side")
			var better := 0
			for row in cmp.find_child("Table", true, false).get_children():
				if row.has_meta("better"):
					better += 1
			_check(better >= 1, "better values are highlighted (%d rows)" % better)
			var chg: Button = cmp.find_child("Change0", true, false)
			await _click(_button_center(chg))
			await _wait(0.3)
			_check(not cmp.visible and db._pick_side == 0, "CHANGE hides the comparison and asks for a card")
			var c := _visible_card(db, [a, b])
			if c != "":
				await _click(_ctl_center(db._col_views[c]))
				await _wait(0.5)
				_check(cmp.visible and cmp.ids == [c, b], "the picked card replaces the left side (%s)" % [cmp.ids])
			await _key("pause")
			await _wait(0.4)
			_check(db._compare == null and Router.current == "deck_builder", "Esc closes the comparison and stays on Cards & Deck")
	# Shift-click starts a comparison as well.
	var s1 := _visible_card(db, [])
	var s2 := _visible_card(db, [s1])
	if s1 != "" and s2 != "":
		await _shift_click(_ctl_center(db._col_views[s1]))
		await _wait(0.3)
		_check(db._pick_side == 1 and db.deck.size() == Profile.DECK_SIZE, "shift-click starts a comparison without editing the deck")
		await _click(_ctl_center(db._col_views[s2]))
		await _wait(0.5)
		_check(db._compare != null and db._compare.ids == [s1, s2], "then a click opens it")
		await _key("pause")
		await _wait(0.4)
		_check(db._compare == null, "Esc closes it")
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	Profile.data.cards = saved_cards   # leave the collection as the other sections expect it
	Profile.data.deck = saved_deck
	Profile.save_soon()


## 16. Daily Challenge: the main-menu tile opens Play with the Daily selected, START plays
## today's fixed rules, the game leaves the saved run alone, and Results records it.
func _test_daily() -> void:
	Profile.data.flags["battle_help"] = true
	Profile.data.flags["battle_tutorial_done"] = true
	var fake_run := not Profile.has_saved_run()
	if fake_run:   # a saved regular run to prove the daily game leaves it alone
		Profile.data.current_run = {"config": {"mode": "standard"}, "mode_id": "standard", "inning": 5, "arena_id": "steel_yard", "saved_at": "test"}
	var saved_before: String = JSON.stringify(Profile.data.current_run)
	var rules := DailyChallenge.today_rules()
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(1.0)
	var tile: Button = get_tree().current_scene.find_child("DailyButton", true, false)
	_check(tile != null and tile.is_visible_in_tree(), "main menu highlights the Daily Challenge")
	if tile == null:
		return
	await _click(_button_center(tile))
	_check(await _wait_scene("play_menu"), "the Daily tile opens the Play screen")
	await _wait(1.0)
	var pm: Node = get_tree().current_scene
	_check(pm.mode_id == "daily", "Play opens with the Daily Challenge selected (%s)" % pm.mode_id)
	# Select another mode, then click the Daily card itself.
	await _click(_button_center(pm._mode_buttons["quick"]))
	await _wait(0.3)
	await _click(_button_center(pm._mode_buttons["daily"]))
	await _wait(0.4)
	_check(pm.mode_id == "daily", "clicking the DAILY CHALLENGE card selects it")
	var texts: Array = []
	for l in pm._mode_info.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var shows_rules := false
	for t in texts:
		if str(t).begins_with("Twist: "):
			shows_rules = true
	var countdown: bool = not pm._countdown_labels.is_empty() and pm._countdown_labels[0].is_visible_in_tree() \
		and str(pm._countdown_labels[0].text).contains("m")
	_check("DAILY CHALLENGE" in texts and shows_rules and countdown, "the Daily card shows today's rules and a countdown")
	_check(pm._start.text.begins_with("PLAY DAILY"), "START becomes PLAY DAILY")
	var plays_before := {}
	for cid in DB.card_order:
		plays_before[cid] = Profile.card_plays(cid)
	await _click(_button_center(pm._start))
	battle = null
	for i in 300:
		await _wait(0.1)
		var sc := get_tree().current_scene
		if sc is Battle and (sc as Battle).state == "setup":
			battle = sc
			break
	_check(battle != null, "the Daily Challenge battle starts")
	if battle == null:
		return
	_check(battle.run.is_daily() and str(battle.run.config.daily) == str(rules.date), "the battle is today's daily (%s)" % str(battle.run.config.get("daily", "")))
	_check(battle.run.deck == rules.deck and battle.run.arena_id == rules.arena and battle.run.difficulty_id == rules.difficulty, "the battle uses the fixed deck, stadium and difficulty")
	_check(rules.modifier in battle.run.modifiers, "the daily modifier is active (%s)" % rules.modifier)
	# A card cast in the daily game counts towards mastery.
	var cid: String = battle.run.deck[0]
	battle.card_cast.emit(cid)
	await _wait(0.2)
	_check(int(battle.run.stats.get("card_casts", {}).get(cid, 0)) == 1, "card casts are counted for mastery")
	_check(JSON.stringify(Profile.data.current_run) == saved_before, "the daily game does not touch the saved run")
	battle.abandon()
	var retry: Button = null
	for i in 80:
		await _wait(0.1)
		retry = _find_button(get_tree().current_scene, "RETRY DAILY")
		if retry:
			break
	_check(retry != null, "Results offer RETRY DAILY")
	var res: Dictionary = Session.last_result
	_check(not res.get("daily", {}).is_empty() and DailyChallenge.played(), "Results record today's daily game (best %d)" % DailyChallenge.best_score())
	_check(DailyChallenge.current_streak() >= 1, "the daily streak counts today (%d)" % DailyChallenge.current_streak())
	_check(Profile.card_plays(cid) == int(plays_before[cid]) + 1, "mastery saved for %s (%d plays)" % [cid, Profile.card_plays(cid)])
	_check(JSON.stringify(Profile.data.current_run) == saved_before, "the saved run survives the daily game")
	await _wait(1.0)
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	if fake_run:
		Profile.data.current_run = null


## 15. Missions (Update 6): the main menu widget opens Progression → Missions, a finished
## mission is claimed with its reward, the free reroll works once, the Results strip claims
## on the spot, and the Overview shows the account level road.
func _test_missions() -> void:
	Missions.refresh()
	var s := Missions.state()
	var inst: Dictionary = s.daily[0]
	inst.progress = int(inst.goal)
	inst.claimed = false
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(1.0)
	var widget: Control = get_tree().current_scene.find_child("MissionsWidget", true, false)
	_check(widget != null and widget.is_visible_in_tree(), "main menu shows the Missions widget")
	var open: Button = get_tree().current_scene.find_child("MissionsButton", true, false)
	_check(open != null, "the Missions widget has an OPEN button")
	if open == null:
		return
	await _click(_button_center(open))
	_check(await _wait_scene("progression"), "the Missions widget opens Progression")
	await _wait(1.0)
	var tabs: TabContainer = null
	for c in get_tree().current_scene.find_children("*", "TabContainer", true, false):
		tabs = c
	_check(tabs != null and tabs.current_tab == 1 and tabs.get_current_tab_control().name == "Missions", "Progression opens on the Missions tab")
	var row: Control = get_tree().current_scene.find_child("Mission_daily_0", true, false)
	var claim: Button = row.find_child("ClaimButton", true, false) if row else null
	_check(claim != null and claim.is_visible_in_tree(), "a finished mission shows CLAIM")
	if claim:
		var coins := int(Profile.data.coins)
		var stars := int(Profile.data.stars)
		var packs := Profile.pack_count()
		var rw := Missions.reward(inst)
		await _click(_button_center(claim))
		for i in 30:   # the panel rebuilds after the claim moment
			await _wait(0.1)
			var r0: Control = get_tree().current_scene.find_child("Mission_daily_0", true, false)
			if r0 and r0.find_child("ClaimButton", true, false) == null:
				break
		await _wait(0.6)
		_check(bool(Missions.state().daily[0].claimed), "clicking CLAIM claims the mission")
		_check(int(Profile.data.coins) == coins + int(rw.get("coins", 0)) and int(Profile.data.stars) == stars + int(rw.get("stars", 0))
			and Profile.pack_count() == packs + (1 if str(rw.get("pack", "")) != "" else 0), "the reward is paid (%s)" % Missions.reward_text(rw))
		var row2: Control = get_tree().current_scene.find_child("Mission_daily_0", true, false)
		_check(row2 != null and row2.find_child("ClaimButton", true, false) == null, "a claimed mission cannot be claimed again")
	var reroll: Button = get_tree().current_scene.find_child("RerollButton", true, false)
	_check(reroll != null, "unfinished daily missions offer a free REROLL")
	if reroll:
		var ids := str(Missions.state().daily.map(func(m: Dictionary) -> String: return m.id))
		_mouse_move(_button_center(reroll))   # hover first: the button grows on hover
		await _wait(0.4)
		await _click(_button_center(reroll))
		await _wait(0.5)
		_check(Missions.rerolls_left() == 0 and str(Missions.state().daily.map(func(m: Dictionary) -> String: return m.id)) != ids, "REROLL swaps a mission once")
		_check(get_tree().current_scene.find_child("RerollButton", true, false) == null, "no more rerolls today")
	# Results strip: a mission finished in the game can be claimed right there.
	var inst2: Dictionary = Missions.state().daily[1]
	if bool(inst2.claimed):
		inst2 = Missions.state().daily[2]
	inst2.progress = int(inst2.goal)
	var strip := MissionsPanel.results_strip({"missions": [{"kind": "daily", "id": inst2.id, "text": Missions.text(inst2), "reward": Missions.reward(inst2)}], "first_win": true, "first_win_coins": 150})
	var holder := PanelContainer.new()
	holder.position = Vector2(200, 200)
	holder.custom_minimum_size = Vector2(900, 0)
	get_tree().current_scene.add_child(holder)
	holder.add_child(strip)
	await _wait(0.4)
	var rc: Button = strip.find_child("ClaimButton", true, false)
	_check(strip.find_child("MissionComplete_" + str(inst2.id), true, false) != null and rc != null, "Results show MISSION COMPLETE! with CLAIM")
	if rc:
		await _click(_button_center(rc))
		await _wait(0.5)
		_check(bool(inst2.claimed), "claiming from the Results strip works")
	holder.queue_free()
	# Overview: the account level road.
	tabs.current_tab = 0
	await _wait(0.8)
	var road: Control = get_tree().current_scene.find_child("LevelRoad", true, false)
	_check(road != null and road.is_visible_in_tree() and road.find_child("Level%d" % Profile.MAX_ACCOUNT_LEVEL, true, false) != null,
		"Overview shows the account level road up to level %d" % Profile.MAX_ACCOUNT_LEVEL)
	Router.goto("main_menu")
	await _wait_scene("main_menu")


func _ctl_center(c: Control) -> Vector2:
	return get_viewport().get_final_transform() * c.get_global_rect().get_center()


## 14. Guided first game: pop-ups advance on NEXT and on the player's actions.
func _test_tutorial() -> void:
	Profile.data.flags["battle_tutorial_done"] = false
	var cfg := Session.new_run_config("quick")
	cfg.difficulty = "rookie"
	Session.start(cfg)
	battle = null
	for i in 200:
		await _wait(0.1)
		var scene := get_tree().current_scene
		if scene is Battle and (scene as Battle).state == "setup":
			battle = scene
			break
	if battle == null:
		_check(false, "tutorial battle loaded")
		return
	await _wait(1.0)
	var tut: Node = battle.hud.get_node_or_null("Tutorial")
	_check(tut != null and tut._bubble.visible, "first game shows the tutorial pop-up")
	if tut == null:
		return
	await _wait(0.5)
	for i in 3:
		var nb := _find_button(tut, "NEXT  ▶")
		if nb:
			await _click(_button_center(nb))
			await _wait(0.6)
	_check(tut._waiting == "moved", "tutorial asks the player to drag a defender")
	var df: Defender = battle.defenders[battle.defenders.size() - 1]
	var dest := df.post
	for off in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5), Vector3(2, 0, 2), Vector3(-2, 0, -2)]:
		if battle.placement_error(df.post + off, df) == "":
			dest = df.post + off
			break
	_check(dest != df.post, "found a valid spot to drag %s to" % df.id)
	var from := _screen_of(df.global_position + Vector3(0, 1.0, 0))
	var to := _screen_of(dest)
	_mouse_move(from)
	await _wait(0.2)
	_mouse_button(from, true)
	await _wait(0.1)
	for k in 10:
		_mouse_move(from.lerp(to, (k + 1) / 10.0))
		await _wait(0.05)
	_mouse_button(to, false)
	await _wait(0.6)
	_check(tut._step == 4, "moving a defender advances the tutorial (step %d)" % tut._step)
	await _wait(0.5)
	var nb2 := _find_button(tut, "NEXT  ▶")
	if nb2:
		await _click(_button_center(nb2))
		await _wait(0.6)
	_check(tut._waiting == "wave", "tutorial asks to start the wave")
	await _key("start_wave")
	for i in 80:
		await _wait(0.1)
		if tut._title.text == "HERE THEY COME!" and tut._bubble.visible:
			break
	_check(get_tree().paused and tut._title.text == "HERE THEY COME!", "wave tip pauses the game (state %s, step %d, waiting %s, paused %s, title %s)" % [
		battle.state, tut._step, tut._waiting, get_tree().paused, tut._title.text])
	await _wait(0.6)
	var nb3 := _find_button(tut, "NEXT  ▶")
	if nb3:
		await _click(_button_center(nb3))
		await _wait(0.6)
	_check(not get_tree().paused and tut._waiting == "card", "card step lets the game run")
	for i in 60:
		await _wait(0.1)
		if battle.cards.energy >= 3.0 and not battle.lead_runners(1).is_empty():
			break
	for idx in battle.cards.hand.size():
		if battle.cards.check(idx) == "":
			await _key("card_%d" % (idx + 1))
			var id: String = battle.cards.hand[idx]
			var tpos: Vector3 = battle.lead_runners(1)[0].global_position if not battle.lead_runners(1).is_empty() else Field.MOUND
			if DB.card(id).target == "defender":
				tpos = battle.defenders[0].global_position
			var sp := _screen_of(tpos + Vector3(0, 1.0, 0))
			_mouse_move(sp)
			await _wait(0.2)
			var lead_now := battle.lead_runners(1)
			if not lead_now.is_empty() and DB.card(id).target == "enemy":
				sp = _screen_of(lead_now[0].center())   # the runner kept running meanwhile
			await _click(sp)
			break
	for i in 30:
		await _wait(0.1)
		if tut._step == 8:
			break
	_check(tut._step == 8 and get_tree().paused, "playing a card advances to the last step (step %d, paused %s, energy %.1f)" % [tut._step, get_tree().paused, battle.cards.energy])
	await _wait(0.6)
	var go := _find_button(tut, "LET'S GO!")
	if go:
		await _click(_button_center(go))
		await _wait(0.6)
	_check(bool(Profile.data.flags.get("battle_tutorial_done", false)) and not get_tree().paused, "tutorial completes and the game resumes")


## Navigation and hints (Update 6): a screen's first-visit hint shows once, "GOT IT" moves
## through the queue and marks hints seen, the "?" button replays them, Esc closes a hint before
## it leaves the screen, and Esc returns to the main menu from every menu screen.
func _test_navigation() -> void:
	Profile.data.flags["tutorial_done"] = true
	if (Profile.data.history as Array).is_empty():   # the main menu waits for a finished game
		Profile.add_history({"won": true, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "inning": 3, "score": 100, "outs": 30, "runs": 0, "date": Time.get_datetime_string_from_system()})
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	Hints.force_enabled = true
	Hints.reset_seen()
	# 1. First visit of Card Packs: the intro hint shows by itself.
	Router.goto("packs")
	await _wait_scene("packs")
	var shown := ""
	for i in 30:
		await _wait(0.1)
		shown = Hints.current_id()
		if shown != "":
			break
	_check(shown == "packs_intro", "first visit to Card Packs shows its hint (%s)" % shown)
	var card: Node = Hints.current().find_child("HintCard", true, false) if Hints.current() else null
	_check(card != null and (card as Control).get_global_rect().size.x > 300, "hint card is laid out")
	await _wait(0.8)   # let the card settle (it places itself next to its target, then pops in)
	var got := _find_button(Hints.current(), "GOT IT") if Hints.current() else null
	_check(got != null, "hint has a GOT IT button")
	if got:
		await _click(_button_center(got))
		await _wait(0.4)
	_check(Hints.seen("packs_intro"), "GOT IT marks the hint seen")
	_check(Hints.current_id() == "packs_rarity", "the next hint of the screen follows, one at a time (%s)" % Hints.current_id())
	var stacked: Array = []
	for c in get_tree().current_scene.find_children("*", "CanvasLayer", true, false):
		if c.get_node_or_null("HintRoot") != null and not c.is_queued_for_deletion():   # a hint layer
			stacked.append(str(c.get_path()))
	_check(stacked.size() == 1, "exactly one hint on screen %s" % [stacked])
	await _wait(0.8)
	got = _find_button(Hints.current(), "GOT IT") if Hints.current() else null
	if got:
		await _click(_button_center(got))
		await _wait(0.4)
	_check(not Hints.is_showing(), "hints closed after the last GOT IT")
	_check(bool((Profile.data.flags.get("hints_seen", {}) as Dictionary).get("packs_rarity", false)), "seen flags stored in the profile")
	# 2. Second visit: nothing shows.
	await _key("pause")
	_check(await _wait_scene("main_menu"), "Esc leaves Card Packs")
	Router.goto("packs")
	await _wait_scene("packs")
	await _wait(1.6)
	_check(not Hints.is_showing(), "a seen hint does not show again")
	# 3. "?" replays the screen's hints; Esc closes the hint and stays on the screen.
	var help := _find_button(get_tree().current_scene, "?")
	_check(help != null, "Card Packs has a ? button")
	if help:
		await _click(_button_center(help))
		await _wait(0.4)
		_check(Hints.current_id() == "packs_intro", "? replays the screen's hints (%s)" % Hints.current_id())
		await _key("pause")
		await _wait(0.4)
		_check(not Hints.is_showing() and Router.current == "packs", "Esc closes the hint first and stays on the screen")
	Hints.force_enabled = false
	# 4. Esc returns to the main menu from every menu screen.
	for scene in ["play_menu", "packs", "deck_builder", "card_upgrades", "roster", "progression", "settings", "shop", "season"]:
		Router.goto(scene)
		if not await _wait_scene(scene):
			_check(false, "%s opens" % scene)
			continue
		await _wait(0.6)
		_check(_find_button(get_tree().current_scene, "?") != null or scene == "progression", "%s has a ? button" % scene)
		await _key("pause")
		_check(await _wait_scene("main_menu"), "Esc returns to the main menu from %s" % scene)
	# 5. A cross-link (Upgrade Cards -> Card Packs) returns to where it came from.
	Router.goto("card_upgrades")
	await _wait_scene("card_upgrades")
	await _wait(0.5)
	var link := _find_button(get_tree().current_scene, "GET CARD PACKS  ▶")
	_check(link != null, "Upgrade Cards links to Card Packs")
	if link:
		await _click(_button_center(link))
		await _wait_scene("packs")
		await _wait(0.6)
		await _key("pause")
		_check(await _wait_scene("card_upgrades"), "Esc from Card Packs returns to Upgrade Cards (opened from there)")
		await _wait(0.6)
		await _key("pause")
		_check(await _wait_scene("main_menu"), "Esc from Upgrade Cards then returns to the main menu")
	# 6. The Daily shortcut opens the Play screen on the Daily Challenge.
	Session.menu_tab = "daily"
	Router.goto("play_menu")
	await _wait_scene("play_menu")
	await _wait(0.4)
	_check(str(get_tree().current_scene.get("mode_id")) == "daily", "Play opens on the Daily Challenge from a shortcut")
	Router.goto("main_menu")
	await _wait_scene("main_menu")


## Scouting Book (Update 8): the main-menu tile opens the book, an entry can be selected, the
## card inspector links to it; in battle a combo pair in hand is linked, the selected card's
## partner glows, the hand tooltip names the combo, and a threat icon opens the scouting card
## (pausing the game) which Esc closes without leaving the battle.
func _test_scouting() -> void:
	Profile.data.flags["tutorial_done"] = true
	if (Profile.data.history as Array).is_empty():
		Profile.add_history({"won": true, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "inning": 3, "score": 100, "outs": 30, "runs": 0, "date": Time.get_datetime_string_from_system()})
	Scouting.mark_met("sprinter")
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(0.8)
	var tile := _find_button(get_tree().current_scene, "SCOUTING BOOK")
	_check(tile != null, "the main menu has a SCOUTING BOOK tile")
	if tile:
		await _click(_button_center(tile))
	_check(await _wait_scene("scouting_book"), "the tile opens the Scouting Book")
	await _wait(0.8)
	var book: Node = get_tree().current_scene
	var list: Node = book.find_child("ScoutList", true, false)
	var row_count := 0
	if list:
		for c in list.get_children():
			if c is Button:
				row_count += 1
	_check(row_count == Scouting.all_keys().size(), "the book lists every runner, boss and affix (%d)" % row_count)
	var row: Button = book.find_child("Row_sprinter", true, false)
	_check(row != null, "the Sprinter has a row")
	if row:
		await _click(_button_center(row))
		await _wait(0.5)
	_check(str(book.get("selected")) == "sprinter", "clicking a row selects it (%s)" % book.get("selected"))
	_check(Scouting.is_viewed("sprinter"), "the selected entry is no longer NEW")
	var report: Node = book.find_child("ScoutReport", true, false)
	_check(report != null and report.find_child("GoodCards", true, false) != null and report.find_child("HowToStop", true, false) != null,
		"the report shows how to stop it and good cards")
	var tt: Node = book.find_child("Turntable", true, false)
	_check(tt is SubViewportContainer and tt.get("_model") != null, "the turntable shows the model")
	var locked_key := ""
	for k in Scouting.all_keys():
		if not Scouting.is_met(k):
			locked_key = k
			break
	if locked_key != "":
		var lrow: Button = book.find_child("Row_" + locked_key.replace(":", "_"), true, false)
		if lrow:
			await _click(_button_center(lrow))
			await _wait(0.4)
		_check(not Scouting.is_met(locked_key) and _find_label(book, "NOT SCOUTED YET"), "an entry not met yet stays locked")
	await _key("pause")
	_check(await _wait_scene("main_menu"), "Esc leaves the Scouting Book")
	# Cards & Deck inspector: "Good against" links to the book, and BACK returns.
	Profile.grant_card("hot_corner")
	Session.menu_tab = "deck"
	Router.goto("deck_builder")
	await _wait_scene("deck_builder")
	await _wait(0.8)
	var db: Node = get_tree().current_scene
	db.set("selected", "hot_corner")
	db.call("_refresh_detail")
	await _wait(0.3)
	var ga: Node = null
	for n in db.find_children("*", "VBoxContainer", true, false):
		if str(n.get_meta("good_against", "")) == "hot_corner" and not n.is_queued_for_deletion():
			ga = n
	var ga_btns: Array = ga.find_children("*", "Button", true, false).map(func(b: Node) -> String: return "%s:%s" % [(b as Button).text, (b as Button).is_visible_in_tree()]) if ga else []
	_check(ga != null and _find_button(ga, "Armored Runner") != null, "the inspector lists what Hot Corner is good against %s" % [ga_btns])
	var link := _find_button(ga, "Armored Runner") if ga else null
	if link:
		var sc: Node = link.get_parent()
		while sc and not sc is ScrollContainer:
			sc = sc.get_parent()
		if sc:
			(sc as ScrollContainer).ensure_control_visible(link)
			await _wait(0.4)
		await _click(_button_center(link))
		_check(await _wait_scene("scouting_book"), "a Good-against link opens the Scouting Book")
		await _wait(0.6)
		_check(str(get_tree().current_scene.get("selected")) == "armored", "the book opens on that runner")
		await _key("pause")
		_check(await _wait_scene("deck_builder"), "Esc returns to Cards & Deck")
	# In battle.
	Profile.data.flags["battle_help"] = true
	Profile.data.flags["battle_tutorial_done"] = true
	var cfg := Session.new_run_config("quick")
	cfg.difficulty = "rookie"
	Session.start(cfg)
	battle = null
	for i in 200:
		await _wait(0.1)
		var scene := get_tree().current_scene
		if scene is Battle and (scene as Battle).state == "setup":
			battle = scene
			break
	_check(battle != null, "battle loaded")
	if battle == null:
		return
	await _wait(0.8)
	var hud: Node = battle.hud
	battle.cards.draw_interval = 999.0
	battle.cards.hand = ["curveball", "power_throw", "heat_wave", "field_vision", "rally_cry"]
	battle.cards.hand_changed.emit()
	await _wait(0.4)
	var pairs: Array = hud.get("_combo_pairs")
	_check(pairs.size() == 1 and pairs[0][0] == 0 and pairs[0][1] == 2, "the combo pair in hand is found (%s)" % [pairs])
	var links: Control = hud.find_child("ComboLinks", true, false)
	_check(links != null and links.visible and links.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the combo link is drawn (and takes no clicks)")
	var views: Array = hud.get("_card_views")
	_check((views[0] as CardView).combo_glow > 0.5 and (views[2] as CardView).combo_glow > 0.5 and (views[1] as CardView).combo_glow == 0.0,
		"both combo cards glow, the others don't")
	var xf := get_viewport().get_final_transform()
	_mouse_move(xf * (views[2] as CardView).get_global_rect().get_center())
	await _wait(0.3)
	var tip: RichTextLabel = hud.get("_card_tip_label")
	_check(tip != null and "COMBO with Curveball" in tip.text, "the hand tooltip names the combo")
	_mouse_move(Vector2(20, 450))
	await _key("start_wave")
	for i in 80:
		await _wait(0.1)
		if battle.state == "wave" and battle.enemies.size() > 0:
			break
	battle.cards.infinite_energy = true
	battle.cards.energy = CardSystem.MAX_ENERGY
	battle.cards.draw_interval = 999.0
	battle.cards.hand = ["curveball", "power_throw", "heat_wave", "field_vision", "rally_cry"]
	battle.cards.hand_changed.emit()
	await _wait(0.5)
	_check(Scouting.is_met("runner"), "runners met in the game are scouted")
	battle.select_card(0)
	await _wait(0.3)
	views = hud.get("_card_views")
	_check(battle.targeting_index == 0 and (views[2] as CardView).combo_partner and not (views[1] as CardView).combo_partner,
		"selecting a combo card highlights its partner")
	await _key("pause")   # cancels targeting
	await _wait(0.3)
	var icon: Control = null
	var icons: Control = hud.get("_threat_icons")
	for i in 30:
		await _wait(0.1)
		if icons:
			for c in icons.find_children("Threat_*", "TextureRect", true, false):
				icon = c
				break
		if icon:
			break
	_check(icon != null, "the threat panel shows runner icons")
	if icon:
		await _click(xf * icon.get_global_rect().get_center())
		await _wait(0.5)
		var pop: Node = hud.find_child("ScoutPopup", true, false)
		_check(pop != null and get_tree().paused, "clicking a threat icon opens the scouting card and pauses")
		_check(pop != null and pop.find_child("GoodCards", true, false) != null, "the scouting card shows good cards")
		await _key("pause")
		await _wait(0.4)
		_check(hud.find_child("ScoutPopup", true, false) == null and not get_tree().paused, "Esc closes the scouting card and resumes")
		_check(Router.current == "battle" and (hud.get("_pause") == null or not is_instance_valid(hud.get("_pause"))), "the game goes on (no pause menu, still in battle)")
	get_tree().paused = false
	Router.goto("main_menu")
	await _wait_scene("main_menu")


func _find_label(root: Node, text: String) -> bool:
	for l in root.find_children("*", "Label", true, false):
		if (l as Label).text == text and (l as Label).is_visible_in_tree():
			return true
	return false


## Title screen: the logo and prompt appear, input during the intro skips it, a key opens the menu.
func _test_title() -> void:
	Router.goto("title")
	_check(await _wait_scene("title"), "the title screen opens")
	await _wait(0.4)
	var ts: Node = get_tree().current_scene
	_mouse_button(Vector2(800, 450), true)   # a press during the intro skips to the prompt
	await _wait(0.1)
	_mouse_button(Vector2(800, 450), false)
	await _wait(0.4)
	_check(ts.get("_ready_for_input") == true and (ts.get("_prompt") as Label).modulate.a > 0.0, "a press during the intro shows the prompt at once")
	_check((ts.get("_prompt") as Label).text == "PRESS ANY BUTTON TO START", "the prompt says PRESS ANY BUTTON TO START")
	var k := InputEventKey.new()
	k.keycode = KEY_SPACE
	k.pressed = true
	Input.parse_input_event(k)
	await _wait(0.1)
	var k2 := k.duplicate() as InputEventKey
	k2.pressed = false
	Input.parse_input_event(k2)
	_check(await _wait_scene("main_menu"), "pressing a key opens the main menu")
	await _wait(0.5)


func _wait_scene(name: String) -> bool:
	for i in 200:
		await _wait(0.1)
		if Router.current == name and not Router.busy:
			return true
	return false


func _all_buttons(n: Node) -> Array[Button]:
	var out: Array[Button] = []
	if n is Button:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_buttons(c))
	return out


## Card hand responsiveness: every point of every card must react to the mouse, and fast
## click sequences (select, cast, select the next card right away) must never be dropped.
func _test_card_clicks() -> void:
	Profile.data.flags["battle_help"] = true
	Profile.data.flags["battle_tutorial_done"] = true
	var cfg := Session.new_run_config("quick")
	cfg.difficulty = "rookie"
	Session.start(cfg)
	for i in 200:
		await _wait(0.1)
		var scene := get_tree().current_scene
		if scene is Battle and (scene as Battle).state == "setup":
			battle = scene
			break
	_check(battle != null, "battle loaded")
	if battle == null:
		return
	await _wait(0.8)
	await _key("start_wave")
	await _wait(0.3)
	battle.cam.default_view(true)
	battle.cards.infinite_energy = true
	battle.cards.energy = CardSystem.MAX_ENERGY
	for i in 80:
		await _wait(0.1)
		if battle.enemies.size() > 0:
			break
	await _wait(0.5)
	var xf := get_viewport().get_final_transform()
	var hud: Node = battle.hud
	# 1. Hit map: a grid of points over every card in the hand (3D off meanwhile: faster).
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(), true)
	var dead := 0
	var total := 0
	var dead_pts: Array[String] = []
	var views: Array = hud.get("_card_views")
	for slot in views.size():
		if not is_instance_valid(views[slot]):
			continue
		var r: Rect2 = (views[slot] as CardView).get_global_rect()
		for gx in 5:
			for gy in 7:
				var p := r.position + Vector2(3 + (r.size.x - 6) * gx / 4.0, 3 + (r.size.y - 6) * gy / 6.0)
				_mouse_move(xf * p)
				await get_tree().process_frame
				await get_tree().process_frame
				var cv: CardView = views[slot] if is_instance_valid(views[slot]) else null
				if cv == null:
					continue   # played or replaced meanwhile
				total += 1
				var h := get_viewport().gui_get_hovered_control()
				if h != cv:
					dead += 1
					if dead_pts.size() < 12:
						dead_pts.append("%s@(%d,%d)->%s" % [cv.card_id, gx, gy, ("%s %s" % [h.get_path(), h.get_global_rect()]) if h else "none"])
	RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(), false)
	_check(dead == 0 and total > 0, "every point of every hand card reacts to the mouse (%d/%d dead) %s" % [dead, total, dead_pts])
	# 2. Fast play: click a card, click a target, then immediately click the next card.
	var reacted := [0]
	var on_sel := func(_i: int) -> void: reacted[0] += 1
	var on_deny := func(_i: int, _r: String) -> void: reacted[0] += 1
	battle.targeting_changed.connect(on_sel)
	battle.card_denied.connect(on_deny)
	var clicks := 0
	var misses: Array[String] = []
	var casts := 0
	for round_i in 12:
		if battle.state != "wave":   # the slow hit map may outlast the first wave
			await _key("start_wave")
			for i in 60:
				await _wait(0.1)
				if battle.state == "wave" and battle.enemies.size() > 0:
					break
		battle.cards.energy = CardSystem.MAX_ENERGY
		battle.cards.cooldowns.clear()
		battle.cards.draw_interval = 0.3   # new cards land in empty slots while we click
		var pick: CardView = null
		for idx in views.size():
			var cv: CardView = views[idx] if is_instance_valid(views[idx]) else null
			if cv and cv.is_visible_in_tree() and battle.cards.check(idx) == "" \
					and str(DB.card(cv.card_id).target) in ["none", "area", "path", "enemy"]:
				pick = cv
				break
		if pick == null:
			await _wait(0.3)
			continue
		var before: int = reacted[0]
		var cp := xf * pick.get_global_rect().get_center()
		_mouse_move(cp)
		await get_tree().process_frame
		_mouse_button(cp, true)
		await get_tree().process_frame
		_mouse_button(cp, false)
		await get_tree().process_frame
		clicks += 1
		if reacted[0] == before:
			misses.append(pick.card_id)
			continue
		if battle.targeting_index < 0:
			continue   # instant cards cast on the first click
		var tpos := Field.MOUND
		var lead := battle.lead_runners(1)
		var aim: Enemy = null
		if not lead.is_empty():
			aim = lead[0]
			tpos = aim.global_position
		var sp := _screen_of(tpos + Vector3(0, 1.0, 0))
		var hand_before := battle.cards.hand.duplicate()
		_mouse_move(sp)
		await get_tree().process_frame
		await get_tree().process_frame
		_mouse_button(sp, true)
		await get_tree().process_frame
		_mouse_button(sp, false)
		await get_tree().process_frame
		if battle.cards.hand != hand_before:
			casts += 1
		else:
			var hc := get_viewport().gui_get_hovered_control()
			# Why: the aimed runner may have been put out (or moved) between aiming and the click.
			var aim_state := "no runner (aimed at the mound)"
			if aim != null:
				if not is_instance_valid(aim) or not aim.alive:
					aim_state = "aimed runner was put out before the click"
				else:
					aim_state = "aimed runner alive, moved %.0f px" % _screen_of(aim.center()).distance_to(sp)
			print("[UITEST] note: no cast of '%s' at %s (targeting %d, over ui %s, preview %s; %s)" % [pick.card_id, sp,
				battle.targeting_index, hc.get_path() if hc else "none", battle.target_preview.get("valid", "?"), aim_state])
	_check(clicks >= 8, "fast play made %d card clicks" % clicks)
	_check(misses.is_empty(), "no fast card click was dropped (%d dropped: %s)" % [misses.size(), misses])
	_check(casts >= 4, "fast play cast %d cards" % casts)


## Update 9 cards (Stream B): the hand hit map and fast play with decks made of the twelve new
## cards (two decks, so every new card is dealt into the hand).
func _test_new_card_clicks() -> void:
	var saved: Array = Profile.data.deck.duplicate()
	var decks := [["scouting_report", "sprinkler_system", "sweet_spot", "rally_monkey", "second_wind", "money_ball", "scoop_and_tag", "signal_caller"],
		["hidden_ball_trick", "worm_burner", "fireworks_night", "ground_rule_double", "scouting_report", "sprinkler_system", "sweet_spot", "rally_monkey"]]
	for deck in decks:
		Profile.data.deck = deck.duplicate()
		battle = null
		await _test_card_clicks()
		_check(battle != null and deck.all(func(id: String) -> bool: return id in battle.cards.deck), "the battle plays the new-card deck %s" % [deck])
	Profile.data.deck = saved


func _finish() -> void:
	print("[UITEST] ===== %d checks, %d failed =====" % [results.size(), failures])
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit(1 if failures > 0 else 0)


# ---------------------------------------------------------------- Update 9: NEXT WAVE NOW, Dugout Draft

## Plays waves until the battle reaches `want`: the runners of each wave are sent out at once and
## put out (bosses too), so this checks the UI flow, not the balance, and stays quick on a slow
## software renderer. Returns true when reached.
func _play_until(want: Array, max_steps := 600) -> bool:
	for i in max_steps:
		if battle.state in want:
			return true
		if battle.state == "results":
			return false
		if battle.state == "wave":
			battle.wave_time += 4.0
			for e: Enemy in battle.enemies.duplicate():
				if is_instance_valid(e) and e.alive and e.d > 2.0:
					battle.deal_damage(e, e.hp + 10.0, {"kind": "throw", "true": true, "pierce": 1.0})
		await _wait(0.1)
	return battle.state in want


## Boss Rush on Rookie: NEXT WAVE NOW by click and by Space (+1 energy), then the Dugout Draft after
## bosses 1 and 2, picked once with a key and once with a click, with pause and 2x speed in between.
func _test_draft() -> void:
	Profile.data.flags["battle_help"] = true
	Profile.data.flags["battle_tutorial_done"] = true
	Engine.time_scale = 1.0
	var cfg := Session.new_run_config("boss_rush")
	cfg.difficulty = "rookie"
	cfg.seed = 4242
	Session.start(cfg)
	battle = null
	for i in 300:
		await _wait(0.1)
		var sc := get_tree().current_scene
		if sc is Battle and (sc as Battle).state == "setup":
			battle = sc
			break
	_check(battle != null and battle.run.mode_id == "boss_rush", "Boss Rush battle loaded")
	if battle == null:
		return
	await _wait(0.8)
	await _key("start_wave")
	await _wait(0.3)
	_check(battle.state == "wave", "Boss Rush wave 1 started")
	# 1. NEXT WAVE NOW by click.
	Engine.time_scale = 4.0
	var reached := await _play_until(["break"])
	Engine.time_scale = 1.0
	_check(reached, "wave 1 cleared into a break (state=%s)" % battle.state)
	await _wait(0.4)
	var hud: Node = battle.hud
	var btn := _find_button(hud.root, "NEXT WAVE NOW")
	var cap: Label = hud.get("_start_sub")
	_check(btn != null, "the break shows a NEXT WAVE NOW button")
	_check(cap != null and cap.visible and cap.text.contains("+1 ENERGY") and cap.text.contains("SPACE"), "NEXT WAVE NOW says what it pays and its key (%s)" % (cap.text if cap else "-"))
	var calls0 := int(battle.run.stats.get("early_calls", 0))
	battle.cards.energy = 2.0
	if btn:
		await _click(_button_center(btn))
		await _wait(0.2)
	_check(battle.state == "wave", "clicking NEXT WAVE NOW starts the next wave")
	_check(battle.cards.energy >= 4.0 - 0.01, "an early call gives +1 energy on top of the wave's +1 (%.1f from 2.0)" % battle.cards.energy)
	_check(int(battle.run.stats.get("early_calls", 0)) == calls0 + 1, "the early call is counted")
	# 2. NEXT WAVE NOW by key (Space).
	Engine.time_scale = 4.0
	reached = await _play_until(["break"])
	Engine.time_scale = 1.0
	await _wait(0.3)
	battle.cards.energy = 2.0
	await _key("start_wave")
	await _wait(0.2)
	_check(reached and battle.state == "wave" and battle.cards.energy >= 3.99, "Space calls the next wave early with +1 energy (%.1f)" % battle.cards.energy)
	# 3. Boss 1 -> draft; pause and 2x speed while it is up; pick with the 2 key.
	Engine.time_scale = 4.0
	reached = await _play_until(["draft", "dugout"])
	Engine.time_scale = 1.0
	_check(reached and battle.state == "draft", "beating boss 1 opens the Dugout Draft (state=%s)" % battle.state)
	var draft: Node = null
	for i in 40:
		await _wait(0.1)
		var d1: Variant = hud.get("_draft")
		if d1 != null and is_instance_valid(d1):
			draft = d1
			break
	_check(draft != null and is_instance_valid(draft) and (draft.get("cards") as Array).size() == 3, "the draft overlay shows three boon cards")
	if draft == null or not is_instance_valid(draft):
		return
	await _wait(1.0)
	var offers: Array = battle.draft_offers.duplicate()
	var wave0 := battle.run.wave
	await _wait(1.5)
	_check(battle.state == "draft" and battle.run.wave == wave0 and battle.spawn_queue.is_empty(), "the next wave is held while the draft is open")
	await _key("pause")
	await _wait(0.2)
	_check(get_tree().paused, "Escape pauses during the draft")
	await _key("card_1")
	_check(battle.run.boons.is_empty(), "keys don't pick a boon while paused")
	await _key("pause")
	await _wait(0.2)
	_check(not get_tree().paused and battle.state == "draft", "Escape resumes the draft")
	Engine.time_scale = 2.0
	await _key("card_2")
	await _wait(0.3)
	_check(battle.run.boons == [offers[1]], "key 2 takes the second boon at 2x speed (%s of %s)" % [battle.run.boons, offers])
	_check(battle.state != "draft", "the game goes on after the pick (state=%s)" % battle.state)
	Engine.time_scale = 1.0
	# 4. Dugout, then inning 2 to boss 2 -> pick with a click.
	reached = await _play_until(["dugout"], 100)
	var dug: Node = null
	for i in 60:
		await _wait(0.1)
		dug = hud.get("_dugout")
		if dug and is_instance_valid(dug):
			break
	var next := _find_button(dug, "NEXT INNING  ▶") if dug else null
	_check(next != null, "the dugout follows the draft")
	if next == null:
		return
	await _wait(0.8)
	await _click(_button_center(next))
	for i in 100:
		await _wait(0.1)
		if battle.state in ["setup", "wave"]:
			break
	if battle.state == "setup":
		await _key("start_wave")
	Engine.time_scale = 4.0
	reached = await _play_until(["draft"])
	Engine.time_scale = 1.0
	_check(reached and battle.run.inning == 2, "boss 2 opens the second draft (inning %d, state %s)" % [battle.run.inning, battle.state])
	draft = null
	for i in 40:
		await _wait(0.1)
		var d2: Variant = hud.get("_draft")
		if d2 != null and is_instance_valid(d2):
			draft = d2
			break
	await _wait(1.2)
	offers = battle.draft_offers.duplicate()
	_check(offers.size() == 3 and not (battle.run.boons[0] in offers), "the second draft doesn't offer the boon already taken")
	var cards: Array = draft.get("cards") if draft and is_instance_valid(draft) else []
	if cards.size() == 3:
		await _click(_button_center(cards[2]))
		await _wait(0.3)
	_check(battle.run.boons.size() == 2 and battle.run.boons[1] == offers[2], "clicking the third card takes it (%s)" % [battle.run.boons])
	await _wait(1.0)
	hud.refresh()
	var chips: Node = hud.get("_boon_box")
	_check(chips != null and chips.get_child_count() == 2 and (chips as Control).is_visible_in_tree(), "the HUD shows both boons as chips")
	_check(hud.get("_draft") == null or not is_instance_valid(hud.get("_draft")), "the overlay is gone after the pick")
	Engine.time_scale = 1.0
	Router.goto("main_menu")
	await _wait_scene("main_menu")


# ---------------------------------------------------------------- Update 9 (stream E2): Team, Shop, Season, Packs, level road
# Run alone: godot --path . -- --ui-test --profile=uitest --fresh-profile --ui-test-section=u9e2
# Written against the Season / Shop contracts (docs/plans/UPDATE_9_PLAN.md): with the foundation
# stubs (no deals, no tiers) the empty states are checked; with the real data the buy, claim and
# sign paths run too.

func _test_u9_e2() -> void:
	Profile.data.flags["tutorial_done"] = true
	await _test_u9_team()
	await _test_u9_shop()
	await _test_u9_season()
	await _test_u9_packs()
	await _test_u9_level_road()
	Router.goto("main_menu")
	await _wait_scene("main_menu")


## A key press through the GUI (arrow keys, Enter) as a real keyboard sends it.
func _press(keycode: Key) -> void:
	var k := InputEventKey.new()
	k.keycode = keycode
	k.physical_keycode = keycode
	k.pressed = true
	Input.parse_input_event(k)
	await _wait(0.05)
	var k2 := k.duplicate() as InputEventKey
	k2.pressed = false
	Input.parse_input_event(k2)
	await _wait(0.15)


func _closed(n: Variant) -> bool:
	return n == null or not is_instance_valid(n) or (n as Node).is_queued_for_deletion() or not (n as Node).is_inside_tree()


## Team: the portrait grid fits all defenders, works with the keyboard, and a locked free agent
## can be signed after a confirmation that shows the price and whether the player can afford it.
func _test_u9_team() -> void:
	Router.goto("roster")
	_check(await _wait_scene("roster"), "Team screen opens")
	await _wait(1.0)
	var rs: Node = get_tree().current_scene
	var tiles: Dictionary = rs.get("tiles")
	_check(tiles.size() == DB.defender_order.size() and tiles.size() >= 12, "the Team grid has a tile for every defender (%d)" % tiles.size())
	var vp := get_viewport().get_visible_rect()
	var inside := true
	for id in tiles:
		inside = inside and vp.encloses((tiles[id] as Control).get_global_rect())
	_check(inside, "every defender tile fits on screen without scrolling")
	var f := get_viewport().gui_get_focus_owner()
	_check(f != null and f == tiles.get(rs.selected), "the selected defender's tile has keyboard focus")
	await _press(KEY_RIGHT)
	var f2 := get_viewport().gui_get_focus_owner()
	_check(f2 != null and f2 != f and f2 in tiles.values(), "arrow keys move between the tiles")
	if f2 in tiles.values():
		var fid: String = tiles.find_key(f2)
		await _press(KEY_ENTER)
		await _wait(0.3)
		_check(fid == rs.selected, "Enter selects the focused defender (%s)" % rs.selected)
		var f3 := get_viewport().gui_get_focus_owner()
		_check(f3 == rs.tiles.get(rs.selected), "focus stays on the defender after the grid refreshes")
	# A locked free agent: SIGN, the popup, Esc, then sign with enough coins.
	var fa := ""
	for a in Shop.free_agents():
		if not bool(a.signed):
			fa = str(a.id)
			break
	if fa == "":
		_check(true, "every free agent is already signed")
		return
	await _click(_button_center(rs.tiles[fa]))
	await _wait(0.5)
	_check(rs.selected == fa, "clicking a locked free agent selects %s" % fa)
	var sb: Button = rs.get("sign_button")
	_check(sb != null and sb.is_visible_in_tree(), "a locked free agent shows SIGN NOW")
	if sb == null:
		return
	var price := int(ShopScreen.agent_info(fa).price)
	Profile.data.coins = price - 100
	await _click(_button_center(sb))
	await _wait(0.5)
	var pop: Node = rs.find_child("SignConfirm", true, false)
	_check(pop != null, "SIGN NOW opens the signing popup")
	if pop:
		var go: Button = pop.find_child("Sign", true, false)
		_check(go != null and go.disabled, "the popup's SIGN is disabled when coins are short")
		_check(_find_label(pop, "You need 100 more coins."), "the popup says how many coins are missing")
		_check(_find_label(pop, UITheme.format_int(price)), "the popup shows the price")
		await _key("pause")
		await _wait(0.4)
		_check(_closed(pop), "Esc closes the signing popup")
		_check(Router.current == "roster", "Esc on the popup stays on the Team screen")
	Profile.data.coins = price + 250
	sb = rs.get("sign_button")
	await _click(_button_center(sb))
	await _wait(0.5)
	pop = rs.find_child("SignConfirm", true, false)
	var go2: Button = pop.find_child("Sign", true, false) if pop else null
	_check(go2 != null and not go2.disabled, "SIGN is enabled with enough coins")
	_check(pop != null and _find_label(pop, "After signing: 250 coins left."), "the popup shows the coins left after signing")
	if go2 == null:
		return
	_check(get_viewport().gui_get_focus_owner() == go2, "the popup focuses SIGN for keyboard players")
	await _click(_button_center(go2))
	await _wait(0.8)
	_check(_closed(pop), "confirming closes the popup")
	if Profile.is_defender_unlocked(fa):
		_check(int(Profile.data.coins) == 250, "signing charges the price (%d left)" % int(Profile.data.coins))
		var t: Button = rs.tiles.get(fa)
		_check(t != null and not "Locked" in t.tooltip_text, "the signed defender's tile is unlocked")
		_check(rs.get("sign_button") == null, "SIGN NOW is gone once signed")
	else:
		_check(int(Profile.data.coins) == price + 250, "a refused signing charges nothing")


## Shop: countdown, daily deals (or their empty state), the pack shop, free agents, the link to
## Card Packs and back.
func _test_u9_shop() -> void:
	Profile.data.coins = 1000
	Profile.data.stars = 0
	Router.goto("shop")
	_check(await _wait_scene("shop"), "the Shop opens")
	await _wait(1.0)
	var sh: ShopScreen = get_tree().current_scene as ShopScreen
	_check(sh != null, "the Shop scene is a ShopScreen")
	if sh == null:
		return
	var cd: Label = sh.find_child("Countdown", true, false)
	_check(cd != null and cd.text.begins_with("NEW DEALS IN") and cd.text.count(":") == 2, "the Shop shows the refresh countdown (%s)" % (cd.text if cd else "none"))
	var offers := Shop.offers()
	if offers.is_empty():
		var found := false
		for l in sh.find_children("*", "Label", true, false):
			found = found or (l as Label).text.begins_with("Today's deals are being stocked")
		_check(found, "with no deals today the Shop says they are coming")
	else:
		_check(sh.deal_buttons.size() == offers.size(), "one tile per daily deal (%d)" % offers.size())
		for o in offers:
			if str(o.kind) == "gift" and not bool(o.bought):
				var gb: Button = sh.deal_buttons.get(str(o.id))
				_check(gb != null and not gb.disabled, "the free gift can be claimed")
				if gb:
					await _click(_button_center(gb))
					await _wait(0.5)
					var after := sh._offer(str(o.id))
					_check(bool(after.get("bought", false)), "claiming marks the free gift as claimed")
					var gb2: Button = sh.deal_buttons.get(str(o.id))
					_check(gb2 != null and gb2.disabled, "a claimed gift's button is disabled")
				break
		for o in Shop.offers():
			if str(o.kind) == "card" and not bool(o.bought):
				var price := int(o.price.get("coins", 0))
				Profile.data.coins = price + 40
				sh._refresh()
				await _wait(0.2)
				var cb: Button = sh.deal_buttons.get(str(o.id))
				_check(cb != null and not cb.disabled, "an affordable card deal can be bought")
				if cb:
					await _click(_button_center(cb))
					await _wait(0.5)
					_check(bool(sh._offer(str(o.id)).get("bought", false)), "buying a card deal marks it bought")
					_check(int(Profile.data.coins) == 40, "the card deal charged its price (%d left)" % int(Profile.data.coins))
				break
		Profile.data.coins = 0
		sh._refresh()
		await _wait(0.2)
		for o in Shop.offers():
			if not bool(o.bought) and int(o.price.get("coins", 0)) > 0:
				var ub: Button = sh.deal_buttons.get(str(o.id))
				_check(ub != null and ub.disabled, "an unaffordable deal is disabled")
				break
	# Pack shop: same prices as Card Packs.
	Profile.data.coins = 1000
	sh._refresh()
	await _wait(0.2)
	_check(sh.pack_buttons.size() == 6, "the pack shop sells three packs, one or ten at a time")
	var rb: Button = sh.pack_buttons.get("rookie:1")
	var r10: Button = sh.pack_buttons.get("rookie:%d" % Profile.BUNDLE_SIZE)
	var ch: Button = sh.pack_buttons.get("champion:1")
	_check(rb != null and not rb.disabled and r10 != null and r10.disabled and ch != null and ch.disabled, "pack buttons follow the wallet (1,000 coins, 0 stars)")
	if rb:
		var before := Profile.pack_count("rookie")
		await _click(_button_center(rb))
		await _wait(0.4)
		_check(Profile.pack_count("rookie") == before + 1, "BUY adds a Rookie Pack")
		_check(int(Profile.data.coins) == 1000 - int(Profile.pack_price("rookie").coins), "BUY charges the pack price")
	# Free agents: SIGN opens the same popup; Esc closes it.
	_check(sh.agent_buttons.size() == Shop.free_agents().size(), "every free agent is listed (%d)" % sh.agent_buttons.size())
	for a in Shop.free_agents():
		if not bool(a.signed):
			await _click(_button_center(sh.agent_buttons[str(a.id)]))
			await _wait(0.5)
			var pop: Node = sh.find_child("SignConfirm", true, false)
			_check(pop != null, "a free agent's SIGN opens the signing popup")
			await _key("pause")
			await _wait(0.4)
			_check(_closed(pop) and Router.current == "shop", "Esc closes it and stays in the Shop")
			break
	# OPEN PACKS goes to Card Packs; Esc comes back to the Shop.
	var op := _find_button(sh, "OPEN PACKS  ▶")
	_check(op != null, "the pack shop links to Card Packs")
	if op:
		await _click(_button_center(op))
		_check(await _wait_scene("packs"), "OPEN PACKS opens Card Packs")
		await _wait(0.8)
		await _key("pause")
		_check(await _wait_scene("shop"), "Esc from Card Packs returns to the Shop")
		await _wait(0.6)
	await _key("pause")
	_check(await _wait_scene("main_menu"), "Esc leaves the Shop for the main menu")


## Season Pass: name, countdown, tier, the track and claiming (one tier, Enter on a focused tier,
## CLAIM ALL), or the empty state while there are no tiers.
func _test_u9_season() -> void:
	var cur := Season.current()
	Profile.data["season"] = {"id": cur.get("id", 1), "xp": 3 * Season.XP_PER_TIER + 120, "claimed": [], "bonus_claimed": 0}
	Router.goto("season")
	_check(await _wait_scene("season"), "the Season Pass opens")
	await _wait(1.2)
	var ss: SeasonScreen = get_tree().current_scene as SeasonScreen
	_check(ss != null, "the Season scene is a SeasonScreen")
	if ss == null:
		return
	var nm: Label = ss.find_child("SeasonName", true, false)
	_check(nm != null and nm.text != "", "the season's name is shown (%s)" % (nm.text if nm else ""))
	var cd: Label = ss.find_child("SeasonCountdown", true, false)
	_check(cd != null and cd.text.begins_with("ENDS IN"), "the season countdown is shown (%s)" % (cd.text if cd else ""))
	var tn: Label = ss.find_child("TierNumber", true, false)
	_check(tn != null and tn.text == str(Season.tier()), "the current tier is shown (%s)" % (tn.text if tn else ""))
	var all: Button = ss.find_child("ClaimAll", true, false)
	var tiers := Season.tiers()
	if tiers.is_empty():
		_check(ss.tier_buttons.is_empty(), "no tiers: the track shows its empty state")
		_check(all != null and all.disabled, "no tiers: CLAIM ALL is disabled")
		await _key("pause")
		_check(await _wait_scene("main_menu"), "Esc leaves the Season Pass")
		return
	_check(ss.tier_buttons.size() == tiers.size() + 1, "the track has every tier plus the bonus (%d)" % ss.tier_buttons.size())
	var claim := SeasonScreen._claimable()
	_check(claim.size() == 3 and all != null and not all.disabled and all.text == "CLAIM ALL (3)", "three tiers are ready and CLAIM ALL counts them (%s)" % [claim])
	_check(get_viewport().gui_get_focus_owner() == ss.tier_buttons.get(1), "focus starts on the first reward to claim")
	var vp := get_viewport().get_visible_rect()
	_check(vp.encloses((ss.tier_buttons[1] as Control).get_global_rect()), "the track is scrolled to the first reward to claim")
	# Click tier 1.
	await _click(_button_center(ss.tier_buttons[1]))
	await _wait(0.6)
	_check(not 1 in SeasonScreen._claimable() and SeasonScreen._claimable().size() == 2, "clicking a ready tier claims it")
	# Enter on a focused tier claims it too.
	(ss.tier_buttons[2] as Control).grab_focus()
	await _press(KEY_ENTER)
	await _wait(0.6)
	_check(not 2 in SeasonScreen._claimable(), "Enter on a focused tier claims it")
	# A locked tier does nothing.
	var locked: int = mini(Season.TIERS, Season.tier() + 3)
	await _click(_button_center(ss.tier_buttons[locked]))
	await _wait(0.4)
	_check(SeasonScreen._claimable().size() == 1, "a locked tier cannot be claimed")
	all = ss.find_child("ClaimAll", true, false)
	await _click(_button_center(all))
	await _wait(0.6)
	_check(SeasonScreen._claimable().is_empty(), "CLAIM ALL claims the rest")
	all = ss.find_child("ClaimAll", true, false)
	_check(all != null and all.disabled, "CLAIM ALL is disabled with nothing left")
	await _key("pause")
	_check(await _wait_scene("main_menu"), "Esc leaves the Season Pass")


## Card Packs: the pity counters, the DAILY SHOP link (and back), extra-copy coins in the summary.
func _test_u9_packs() -> void:
	Router.goto("packs")
	_check(await _wait_scene("packs"), "Card Packs opens")
	await _wait(1.0)
	var ps: Node = get_tree().current_scene
	var e: Label = ps.find_child("Pity_epic", true, false)
	var lg: Label = ps.find_child("Pity_legendary", true, false)
	_check(e != null and e.text == ps.pity_text("Epic or better", Profile.pity_left("epic"), Profile.pity_pack_names("epic")), "Pack Luck shows the Epic counter (%s)" % (e.text if e else ""))
	_check(lg != null and lg.text == ps.pity_text("Legendary", Profile.pity_left("legendary"), Profile.pity_pack_names("legendary")), "Pack Luck shows the Legendary counter (%s)" % (lg.text if lg else ""))
	ps.set("_result", {"cards": [], "overflow_coins": 80, "pity": "epic"})
	var st := str(ps.call("_summary_text"))
	_check("+80 coins from extra copies" in st, "the reveal summary shows coins from extra copies")
	_check("Epic guaranteed by Pack Luck" in st, "the reveal summary names a pity pull")
	ps.set("_result", {})
	var link: Button = ps.get("shop_link")
	_check(link != null and link.is_visible_in_tree(), "Card Packs has a DAILY SHOP link")
	if link:
		await _click(_button_center(link))
		_check(await _wait_scene("shop"), "DAILY SHOP opens the Shop")
		await _wait(0.8)
		await _key("pause")
		_check(await _wait_scene("packs"), "Esc from the Shop returns to Card Packs")
		await _wait(0.5)
	Router.goto("main_menu")
	await _wait_scene("main_menu")


## Level road: every caption is one line inside its own column (no overlaps), with a picture.
func _test_u9_level_road() -> void:
	Router.goto("progression")
	_check(await _wait_scene("progression"), "Progression opens")
	await _wait(1.2)
	var views := get_tree().current_scene.find_children("*", "LevelRoadView", true, false)
	_check(views.size() == 1, "the overview has the account level road")
	if views.is_empty():
		return
	var road: LevelRoadView = views[0]
	var prev := -1.0e9
	var ok_lines := true
	var ok_gap := true
	for l in range(1, Profile.MAX_ACCOUNT_LEVEL + 1):
		var node: Control = road.find_child("Level%d" % l, true, false)
		if node == null:
			ok_lines = false
			continue
		var cap: Control = node.get_child(node.get_child_count() - 1)
		var r := cap.get_global_rect()
		if cap is Label:
			ok_lines = ok_lines and (cap as Label).get_line_count() == 1 and (cap as Label).autowrap_mode == TextServer.AUTOWRAP_OFF
		ok_gap = ok_gap and r.position.x >= prev
		prev = r.end.x
	_check(ok_lines, "every level caption is a single line")
	_check(ok_gap, "level captions never overlap their neighbours")
	Router.goto("main_menu")
	await _wait_scene("main_menu")


# ---------------------------------------------------------------- Update 10: Best Team, Compare Defenders

## Team screen: BEST TEAM opens a preview (who comes in and goes out, the score before and after, reasons,
## the style choice), Esc cancels without changing the team, APPLY sets it, and a second look says the
## team is already the best. COMPARE opens the side-by-side panel: CHANGE picks any defender (a locked
## one shows as locked, with no PUT IN), Esc closes the picker first, PUT X IN FOR Y swaps into the six
## keeping the rules, and Esc closes the panel without leaving the screen.
func _test_u10_team() -> void:
	Profile.data.flags["tutorial_done"] = true
	var seen := {}
	for h in Hints.HINTS:
		seen[h] = true
	Profile.data.flags["hints_seen"] = seen
	Profile.set_team(Profile.STARTER_TEAM.duplicate(), "ace")
	for id in ["nova", "hana", "moose", "rosa"]:
		Profile.data.defenders[id].unlocked = true
		Profile.data.defenders[id].level = 6
	if Profile.is_defender_unlocked("sid"):
		Profile.data.defenders["sid"].unlocked = false
	Router.goto("roster")
	_check(await _wait_scene("roster"), "u10: Team screen opens")
	await _wait(1.0)
	var rs: Node = get_tree().current_scene
	var bb: Button = rs.get("best_button")
	var cb: Button = rs.get("compare_button")
	_check(bb != null and bb.is_visible_in_tree() and cb != null and cb.is_visible_in_tree(), "u10: the team strip has BEST TEAM and COMPARE")
	var vp := get_viewport().get_visible_rect()
	_check(bb != null and vp.encloses(bb.get_global_rect()) and cb != null and vp.encloses(cb.get_global_rect()), "u10: both buttons fit on screen")
	if bb == null or cb == null:
		return
	# BEST TEAM preview, Esc cancels.
	var team_before: Array = Profile.data.team.duplicate()
	await _click(_button_center(bb))
	await _wait(0.6)
	var pv: Node = rs.get("best_preview")
	_check(pv != null and not _closed(pv), "u10: BEST TEAM opens the preview")
	if pv == null:
		return
	var res: Dictionary = rs.get("best_result")
	_check(not bool(res.already_best) and not (res.ins as Array).is_empty() and res.ins.size() == res.outs.size(), "u10: the preview lists who comes in and goes out (%s in, %s out)" % [res.ins, res.outs])
	_check(pv.find_child("InOut", true, false) != null and pv.find_child("ScoreAfter", true, false) != null, "u10: the preview shows the in/out row and the new score")
	_check(_find_label(pv, "%.1f" % float(res.current_score)) and _find_label(pv, "%.1f" % float(res.score)), "u10: the score before (%.1f) and after (%.1f)" % [float(res.current_score), float(res.score)])
	var picks: Node = pv.find_child("Picks", true, false)
	_check(picks != null and picks.get_child_count() == Profile.TEAM_SIZE, "u10: the preview lists the six picks with reasons")
	var apply: Button = pv.find_child("Apply", true, false)
	_check(apply != null and not apply.disabled, "u10: APPLY is enabled")
	var fo := get_viewport().gui_get_focus_owner()
	_check(fo != null and pv.is_ancestor_of(fo), "u10: the preview takes keyboard focus")
	for k in [KEY_UP, KEY_UP, KEY_LEFT, KEY_DOWN]:
		await _press(k)
	fo = get_viewport().gui_get_focus_owner()
	_check(fo != null and pv.is_ancestor_of(fo), "u10: arrow keys stay inside the preview (%s)" % (fo.name if fo else "none"))
	# Style choice.
	var mb: Button = pv.find_child("Mode_boss", true, false)
	_check(mb != null, "u10: the preview offers the Boss Killer style")
	if mb:
		await _click(_button_center(mb))
		await _wait(0.5)
		res = rs.get("best_result")
		_check(str(res.mode) == "boss" and str(Profile.data.flags.get("best_team_mode", "")) == "boss", "u10: choosing Boss Killer recomputes the team (%s)" % [res.team])
		var mbal: Button = pv.find_child("Mode_balanced", true, false)
		if mbal:
			await _click(_button_center(mbal))
			await _wait(0.5)
			res = rs.get("best_result")
	_check(str(res.mode) == "balanced", "u10: back to Balanced")
	await _key("pause")
	await _wait(0.4)
	_check(_closed(pv), "u10: Esc closes the preview")
	_check(Router.current == "roster" and Profile.data.team == team_before, "u10: Esc keeps the screen and the team unchanged")
	# APPLY.
	await _click(_button_center(rs.get("best_button")))
	await _wait(0.6)
	pv = rs.get("best_preview")
	res = rs.get("best_result")
	apply = pv.find_child("Apply", true, false) if pv else null
	if apply:
		await _click(_button_center(apply))
		await _wait(0.6)
	_check(Profile.data.team == res.team and Profile.data.captain == res.captain, "u10: APPLY sets the team %s, captain %s" % [Profile.data.team, Profile.data.captain])
	_check(_closed(pv), "u10: APPLY closes the preview")
	for id in res.ins:
		var t: Button = rs.tiles.get(id)
		_check(t != null and ("starting six" in t.tooltip_text or "captain" in t.tooltip_text), "u10: %s's tile shows them in the six" % id)
	# Already the best.
	await _click(_button_center(rs.get("best_button")))
	await _wait(0.6)
	pv = rs.get("best_preview")
	_check(pv != null and pv.find_child("AlreadyBest", true, false) != null, "u10: a second look says the team is already the best")
	apply = pv.find_child("Apply", true, false) if pv else null
	_check(apply != null and apply.disabled, "u10: APPLY is disabled when nothing would change")
	await _key("pause")
	await _wait(0.4)
	_check(_closed(pv), "u10: Esc closes it again")
	# COMPARE: select a bench defender, open the panel.
	var bench := ""
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id) and not id in Profile.data.team:
			bench = id
			break
	_check(bench != "", "u10: someone is on the bench (%s)" % bench)
	if bench == "":
		return
	await _click(_button_center(rs.tiles[bench]))
	await _wait(0.5)
	await _click(_button_center(rs.get("compare_button")))
	await _wait(0.6)
	var cmp: TeamCompare = rs.get("compare")
	_check(cmp != null and not _closed(cmp), "u10: COMPARE opens the comparison")
	if cmp == null:
		return
	_check(cmp.ids[0] == bench and cmp.ids[1] in Profile.data.team, "u10: %s on the left, a team member on the right (%s)" % [bench, cmp.ids[1]])
	var rows_ok := true
	for rn in ["Row_Level", "Row_Damage", "Row_Throw interval", "Row_Range", "Row_Accuracy", "Row_TeamAI score"]:
		if cmp.find_child(rn, true, false) == null:
			rows_ok = false
	_check(rows_ok, "u10: the table lists level, every stat and the TeamAI score")
	var bars := cmp.find_children("Bar", "ColorRect", true, false)
	var green := false
	var red := false
	for b in bars:
		if (b as ColorRect).color.is_equal_approx(UITheme.GREEN):
			green = true
		if (b as ColorRect).color.r > 0.7 and (b as ColorRect).color.g < 0.3:
			red = true
	_check(green and red, "u10: better values have green bars, worse ones red")
	var vd: Label = cmp.find_child("Verdict", true, false)
	_check(vd != null and vd.text != "", "u10: a one-line verdict (%s)" % (vd.text if vd else ""))
	fo = get_viewport().gui_get_focus_owner()
	_check(fo != null and cmp.is_ancestor_of(fo), "u10: the panel takes keyboard focus")
	var start_fo := fo
	var moved := false
	var inside := true
	for k in [KEY_RIGHT, KEY_DOWN, KEY_LEFT, KEY_LEFT, KEY_UP, KEY_UP, KEY_UP]:
		await _press(k)
		fo = get_viewport().gui_get_focus_owner()
		inside = inside and fo != null and cmp.is_ancestor_of(fo)
		moved = moved or fo != start_fo
	_check(inside and moved, "u10: arrow keys move between the panel's buttons and never leave it")
	# CHANGE the right side to a locked defender.
	var ch1: Button = cmp.buttons.get("Change1")
	await _click(_button_center(ch1))
	await _wait(0.5)
	_check(cmp.picker != null and not _closed(cmp.picker), "u10: CHANGE opens the defender picker")
	var lk: Button = cmp.picker.find_child("Pick_sid", true, false) if cmp.picker else null
	_check(lk != null and not lk.disabled and "locked" in lk.tooltip_text, "u10: a locked defender is listed as locked")
	if lk:
		await _click(_button_center(lk))
		await _wait(0.5)
	_check(cmp.ids[1] == "sid" and cmp.picker == null, "u10: picking sets the side and closes the picker")
	var st1: Node = cmp.find_child("Side1", true, false)
	_check(st1 != null and _find_label(st1, "LOCKED"), "u10: the locked side says LOCKED")
	_check(cmp.buttons.get("PutIn0") == null and cmp.buttons.get("PutIn1") == null, "u10: no PUT IN against a locked defender")
	# Esc closes the picker first, then the panel.
	await _click(_button_center(cmp.buttons.get("Change1")))
	await _wait(0.5)
	var pk: Control = cmp.picker
	await _key("pause")
	await _wait(0.4)
	_check(_closed(pk) and not _closed(cmp), "u10: Esc closes the picker but keeps the panel")
	# PUT X IN FOR Y.
	var member := ""
	for id in Profile.data.team:
		if id != Profile.data.captain:
			member = id
			break
	cmp.open_picker(1)
	await _wait(0.4)
	var mp: Button = cmp.picker.find_child("Pick_" + member, true, false)
	if mp:
		await _click(_button_center(mp))
		await _wait(0.5)
	var put: Button = cmp.buttons.get("PutIn0")
	_check(put != null and put.text == "PUT %s IN FOR %s" % [str(DB.defender(bench).name).to_upper(), str(DB.defender(member).name).to_upper()], "u10: PUT %s IN FOR %s is offered" % [bench, member])
	if put:
		var size_before: int = Profile.data.team.size()
		await _click(_button_center(put))
		await _wait(0.6)
		_check(bench in Profile.data.team and not member in Profile.data.team and Profile.data.team.size() == size_before, "u10: PUT IN swaps them in the starting six %s" % [Profile.data.team])
		_check(Profile.data.captain in Profile.data.team, "u10: the captain is still in the team")
		_check(cmp.buttons.get("PutIn1") != null and cmp.buttons.get("PutIn0") == null, "u10: the panel now offers the swap back")
		var strip_ok := false
		for l in rs.find_children("*", "Label", true, false):
			if (l as Label).text.begins_with(str(DB.defender(bench).name)) and (l as Label).is_visible_in_tree():
				strip_ok = true
		_check(strip_ok, "u10: the starting six strip shows %s" % bench)
	await _key("pause")
	await _wait(0.4)
	_check(_closed(cmp), "u10: Esc closes the comparison")
	_check(Router.current == "roster", "u10: Esc on the panel stays on the Team screen")
	fo = get_viewport().gui_get_focus_owner()
	_check(fo == rs.get("compare_button"), "u10: focus returns to COMPARE")
	Profile.set_team(Profile.STARTER_TEAM.duplicate(), "ace")
	Router.goto("main_menu")
	await _wait_scene("main_menu")


# ---------------------------------------------------------------- Update 11: Prestige (stream A)

func _find_ceremony() -> PrestigeCeremony:
	var scr := get_tree().current_scene
	return scr.find_child("PrestigeCeremony", true, false) as PrestigeCeremony if scr else null


func _cardviews(n: Node, out: Array) -> Array:
	if n is CardView:
		out.append(n)
	for c in n.get_children():
		_cardviews(c, out)
	return out


## Run alone: godot --path . -- --ui-test --profile=uitest_u11 --fresh-profile --ui-test-section=u11cards
## Prestige a card through the ceremony and skip it with a click, skip one with Esc, Upgrade All's
## Include Prestige opt-in, reduce_flashes, the Prestige frame in Cards & Deck, and the battle hand
## with Prestige cards (hit map: no dead points).
func _test_u11_prestige() -> void:
	var saved_deck: Array = Profile.data.deck.duplicate()
	for cid in ["lockdown", "wall_of_dirt", "power_throw", "curveball", "heat_wave"]:
		Profile.data.cards[cid].owned = true
	Profile.data.cards.lockdown.level = 5
	Profile.data.cards.lockdown.copies = DB.upgrade_copies("rare", 5)
	Profile.data.cards.wall_of_dirt.level = 5
	Profile.data.cards.wall_of_dirt.copies = DB.upgrade_copies("common", 5)
	Profile.data.cards.power_throw.level = 8
	Profile.data.cards.heat_wave.level = 4
	Profile.data.cards.heat_wave.copies = DB.upgrade_copies("rare", 4)
	Profile.data.coins = 60000
	Settings.set_value("accessibility", "reduce_flashes", false)
	Router.goto("card_upgrades")
	_check(await _wait_scene("card_upgrades"), "u11: Upgrade Cards opens")
	await _wait(0.6)
	var scr: Node = get_tree().current_scene
	scr.set("selected", "lockdown")
	scr.call("_rebuild")
	await _wait(0.4)
	var pb := _find_button(scr, "PRESTIGE")
	_check(pb != null and not pb.disabled, "u11: a level-5 card with its copies shows PRESTIGE")
	_check(_find_label(scr, "LEVEL 5  ▶  PRESTIGE ★1"), "u11: the detail says LEVEL 5 ▶ PRESTIGE ★1")
	if pb == null:
		return
	await _click(_button_center(pb))
	var cer: PrestigeCeremony = null
	for i in 30:
		await _wait(0.1)
		cer = _find_ceremony()
		if cer:
			break
	_check(cer != null, "u11: PRESTIGE starts the ceremony")
	_check(Profile.card_level("lockdown") == 6, "u11: the card is Prestige ★1 as soon as it is paid (level %d)" % Profile.card_level("lockdown"))
	if cer == null:
		return
	_check(not cer.calm, "u11: full ceremony with reduce_flashes off")
	await _wait(1.0)
	_check(not _closed(cer), "u11: the ceremony is still playing after a second")
	var pre: bool = cer.get("_card").face_down == false
	_check(pre, "u11: the card has finished its spin and faces the player")
	var t_before: float = cer.get("_t")
	await _click(get_viewport().get_final_transform() * get_viewport().get_visible_rect().get_center())
	var skipped: bool = cer.skipped
	await _wait(0.6)
	_check(_closed(cer) and skipped and t_before < PrestigeCeremony.T_END, "u11: a click skips the ceremony (at %.1f s of %.1f)" % [t_before, PrestigeCeremony.T_END])
	await _wait(0.4)
	_check(Router.current == "card_upgrades", "u11: skipping stays on Upgrade Cards")
	var dcard: CardView = scr.get("_d_card")
	_check(dcard != null and is_instance_valid(dcard) and dcard.card_id == "lockdown" and dcard.prestige_stars() == 1 and dcard.modulate.a > 0.9,
		"u11: the detail card shows the Prestige ★1 frame")
	_check(dcard != null and dcard.material != null and (dcard.material as ShaderMaterial).shader == CardView.PRESTIGE_SHADER,
		"u11: the Prestige holo shader is on the card")
	_check(_find_label(scr, "PRESTIGE ★1  ▶  ★2"), "u11: the next step is ★1 ▶ ★2")
	# Esc skips too, without leaving the screen.
	scr.set("selected", "wall_of_dirt")
	scr.call("_rebuild")
	await _wait(0.4)
	pb = _find_button(scr, "PRESTIGE")
	if pb:
		await _click(_button_center(pb))
	cer = null
	for i in 30:
		await _wait(0.1)
		cer = _find_ceremony()
		if cer:
			break
	_check(cer != null, "u11: a second ceremony starts")
	await _wait(0.5)
	await _key("pause")
	await _wait(0.6)
	_check(_closed(cer) and Router.current == "card_upgrades", "u11: Esc skips the ceremony and stays on the screen")
	_check(Profile.card_level("wall_of_dirt") == 6, "u11: the skipped card is still prestiged")
	await _wait(0.3)
	# Upgrade All: Prestige only with the opt-in.
	Profile.data.cards.curveball.level = 5
	Profile.data.cards.curveball.copies = DB.upgrade_copies("common", 5)
	Settings.set_value("accessibility", "reduce_flashes", true)
	scr.call("_rebuild")
	await _wait(0.3)
	scr.call("_confirm_upgrade_all")
	await _wait(0.4)
	var check := scr.find_child("IncludePrestige", true, false) as CheckBox
	var summary := scr.find_child("UpgradeAllSummary", true, false) as Label
	_check(check != null and check.is_visible_in_tree() and not check.button_pressed, "u11: Upgrade All offers Include Prestige, unticked")
	_check(summary != null and not summary.text.contains("PRESTIGE"), "u11: without the opt-in the summary has no Prestige (%s)" % (summary.text if summary else "?"))
	var rows := scr.find_child("UpgradeAllRows", true, false)
	var n_before := rows.get_child_count() if rows else 0
	if check:
		await _click(get_viewport().get_final_transform() * check.get_global_rect().get_center())
		await _wait(0.3)
	_check(check != null and check.button_pressed and summary.text.contains("1 PRESTIGE"), "u11: ticking it adds the Prestige to the summary (%s)" % (summary.text if summary else "?"))
	_check(rows != null and rows.get_child_count() > n_before - 0 and _find_label(rows, "LV 5  ▶  PRESTIGE ★1"), "u11: the list shows LV 5 ▶ PRESTIGE ★1")
	var go := scr.find_child("UpgradeAllGo", true, false) as Button
	_check(go != null and not go.disabled, "u11: UPGRADE ALL is enabled")
	if go:
		await _click(_button_center(go))
	cer = null
	for i in 30:
		await _wait(0.1)
		cer = _find_ceremony()
		if cer:
			break
	_check(cer != null and cer.calm, "u11: Upgrade All plays the ceremony, calm with reduce_flashes")
	_check(Profile.card_level("curveball") == 6 and Profile.card_level("heat_wave") == 5, "u11: Upgrade All prestiged the opted-in card and levelled the other")
	if cer:
		await _wait(0.4)
		await _click(get_viewport().get_final_transform() * get_viewport().get_visible_rect().get_center())
		await _wait(0.6)
		_check(_closed(cer), "u11: the Upgrade All ceremony can be skipped")
	await _wait(1.4)
	Settings.set_value("accessibility", "reduce_flashes", false)
	# Cards & Deck: the Prestige frame on collection cards.
	Profile.data.deck = ["lockdown", "wall_of_dirt", "power_throw", "curveball", "heat_wave", "frost_field", "twin_play", "rally_cry"]
	Router.goto("deck_builder")
	_check(await _wait_scene("deck_builder"), "u11: Cards & Deck opens")
	await _wait(0.8)
	var views := _cardviews(get_tree().current_scene, [])
	var pres_views := views.filter(func(v: CardView) -> bool: return v.prestige_stars() > 0 and v.is_visible_in_tree())
	var ids := {}
	for v: CardView in pres_views:
		ids[v.card_id] = true
	_check(ids.has("lockdown") and ids.has("power_throw") and ids.has("wall_of_dirt"), "u11: Prestige cards show the Prestige frame in Cards & Deck (%s)" % [ids.keys()])
	var plain := views.filter(func(v: CardView) -> bool: return v.card_id == "heat_wave" and v.is_visible_in_tree())
	_check(not plain.is_empty() and plain.all(func(v: CardView) -> bool: return v.prestige_stars() == 0), "u11: a level-5 card has no Prestige frame")
	var pt: CardView = null
	for v: CardView in pres_views:
		if v.card_id == "power_throw":
			pt = v
	_check(pt != null and pt.prestige_stars() == 3 and pt.get("_overlay") != null and pt.get_child_count() == 0,
		"u11: Power Throw shows ★3 with its crest overlay")
	Router.goto("main_menu")
	await _wait_scene("main_menu")
	await _wait(0.5)
	# The battle hand with Prestige cards: every point clickable.
	battle = null
	await _test_card_clicks()
	if battle:
		var hand_pres := 0
		for v in battle.hud.get("_card_views"):
			if is_instance_valid(v) and (v as CardView).prestige_stars() > 0:
				hand_pres += 1
		_check(hand_pres >= 1 or battle.state != "wave", "u11: the battle hand shows Prestige cards (%d)" % hand_pres)
	Profile.data.deck = saved_deck


# ---------------------------------------------------------------- Update 11: defender levels to 20

## Run alone: godot --path . -- --ui-test --profile=uitest_u11 --fresh-profile --ui-test-section=u11def
## A level-20 defender on the Team screen: the gold frame on the tile and in the starting six, the
## two-digit level badge, the HALL OF FAMER nameplate and the 20-level road in two readable rows; an
## All-Star; the lineup nameplate on the main menu; and the Results screen levelling past 10.
func _test_u11_defenders() -> void:
	Profile.data.flags["tutorial_done"] = true
	var seen := {}
	for h in Hints.HINTS:
		seen[h] = true
	Profile.data.flags["hints_seen"] = seen
	Profile.set_team(Profile.STARTER_TEAM.duplicate(), "ace")
	var saved := {}
	for id in ["ace", "jax", "maya"]:
		saved[id] = Profile.data.defenders[id].duplicate(true)
	Profile.data.defenders.ace.level = 20
	Profile.data.defenders.ace.xp = 0
	Profile.data.defenders.jax.level = 15
	Profile.data.defenders.jax.xp = 500
	# Every trait chosen, so the tiles show the honour instead of NEW TRAIT.
	Profile.data.defenders.ace.traits = {"3": "power", "6": "tempo", "9": "clutch", "12": "iron_man", "16": "armor_breaker"}
	Profile.data.defenders.jax.traits = {"3": "power", "6": "eagle", "9": "signature", "12": "quick_release"}
	Router.goto("roster")
	_check(await _wait_scene("roster"), "u11: Team screen opens")
	await _wait(1.0)
	var rs: Node = get_tree().current_scene
	var tiles: Dictionary = rs.get("tiles")
	var ta: Button = tiles.get("ace")
	_check(ta != null and ta.find_child("HallOfFameFrame", true, false) != null, "u11: the level-20 tile has the gold Hall of Famer frame")
	var badge: Control = ta.find_child("LevelBadge", true, false) if ta else null
	var bt: Label = badge.find_child("LevelText", true, false) if badge else null
	_check(bt != null and bt.text == "20", "u11: the tile's level badge shows 20")
	if badge and bt:
		var br := badge.get_global_rect()
		_check(br.size.x >= bt.get_minimum_size().x and ta.get_global_rect().encloses(br), "u11: the two-digit badge fits its pill and the tile (%s)" % br)
	var sub: Label = ta.find_child("SubLine", true, false) if ta else null
	_check(sub != null and "HALL OF FAMER" in sub.text, "u11: the tile says HALL OF FAMER (%s)" % (sub.text if sub else "none"))
	var tj: Button = tiles.get("jax")
	var tjb: Label = tj.find_child("LevelText", true, false) if tj else null
	var tjs: Label = tj.find_child("SubLine", true, false) if tj else null
	_check(tjb != null and tjb.text == "15" and tjs != null and "ALL-STAR" in tjs.text and tj.find_child("HallOfFameFrame", true, false) == null, "u11: the level-15 tile is an All-Star without the gold frame")
	# The info panel: nameplate, badge and the 20-level road.
	var info: Control = rs.get("_info")
	_check(info != null and info.find_child("HallOfFamePlate", true, false) != null, "u11: the info panel shows the HALL OF FAMER nameplate")
	var sec: Control = info.find_child("LevelSection", true, false) if info else null
	var road: Control = sec.find_child("LevelRoad", true, false) if sec else null
	_check(road != null and road.find_child("RoadRow1", false, false) != null and road.find_child("RoadRow2", false, false) != null, "u11: the level road has two rows")
	if road:
		var r1: Control = road.find_child("RoadRow1", false, false)
		var r2: Control = road.find_child("RoadRow2", false, false)
		_check(r1 and r2 and r1.get_child_count() == 10 and r2.get_child_count() == 10, "u11: ten levels per row, 20 in all")
		var panel_rect: Rect2 = info.get_parent().get_global_rect()
		var inside := true
		var readable := true
		var prev_end := -1.0e9
		for l in range(1, 21):
			var node: Control = road.find_child("RoadLevel%d" % l, true, false)
			if node == null:
				inside = false
				continue
			if l == 11:
				prev_end = -1.0e9
			var nr := node.get_global_rect()
			inside = inside and panel_rect.encloses(nr)
			readable = readable and nr.position.x >= prev_end - 0.5 and nr.size.x >= 32.0
			prev_end = nr.end.x
			var lab: Label = node.find_child("*", true, false) as Label
			for c in node.find_children("*", "Label", true, false):
				lab = c
			if lab:
				readable = readable and lab.get_line_count() == 1 and lab.get_minimum_size().x <= nr.size.x
		_check(inside, "u11: every road level is inside the panel (no horizontal overflow)")
		_check(readable, "u11: road levels don't overlap and every number fits")
		var n20: Control = road.find_child("RoadLevel20", true, false)
		_check(n20 != null and "Hall of Famer" in n20.tooltip_text, "u11: level 20 on the road is the Hall of Famer reward (%s)" % (n20.tooltip_text if n20 else ""))
		var n15: Control = road.find_child("RoadLevel15", true, false)
		_check(n15 != null and "All-Star" in n15.tooltip_text, "u11: level 15 on the road is the All-Star badge")
	var lb: Control = sec.find_child("LevelBadge", true, false) if sec else null
	var lbt: Label = lb.find_child("LevelText", true, false) if lb else null
	_check(lbt != null and lbt.text == "20" and lb.get_global_rect().size.x >= lbt.get_minimum_size().x, "u11: the big level badge fits 20")
	_check(_find_label(info, "LEVEL 20 / 20  ·  MAX"), "u11: LEVEL 20 / 20 · MAX")
	# Trait tiers 4 and 5 are offered.
	_check(_find_button(info, "Iron Man") != null and _find_button(info, "Armor Breaker") != null, "u11: trait tiers 4 and 5 can be chosen")
	# The starting six: the gold frame in the strip.
	var strip: Control = rs.get("_team_strip")
	var sa: Control = strip.find_child("Strip_ace", true, false) if strip else null
	_check(sa != null and sa.find_child("HallOfFameFrame", true, false) != null, "u11: the starting six shows the Hall of Famer's gold frame")
	# The All-Star's own page.
	if tj:
		await _click(_button_center(tj))
		await _wait(0.5)
		info = rs.get("_info")
		_check(info.find_child("AllStarPlate", true, false) != null and info.find_child("HallOfFamePlate", true, false) == null, "u11: the All-Star's page shows the ALL-STAR plate")
		_check(_find_label(info, "NEXT REWARD — Level 16: Choose a trait"), "u11: the next reward after 15 is trait tier 5")
	# The main menu lineup.
	Router.goto("main_menu")
	_check(await _wait_scene("main_menu"), "u11: back to the main menu")
	await _wait(1.0)
	var plates := get_tree().current_scene.find_children("HonorPlate", "Label3D", true, false)
	var hof := plates.filter(func(p: Label3D) -> bool: return "HALL OF FAMER" in p.text and "ACE" in p.text)
	var star := plates.filter(func(p: Label3D) -> bool: return "ALL-STAR" in p.text and "LV 15" in p.text and str(p.get_parent().get("model_id")) == "jax")
	_check(hof.size() == 1 and star.size() == 1 and plates.size() == 2, "u11: the lineup shows Ace's Hall of Famer and Jax's All-Star nameplates (%d plates)" % plates.size())
	# The Results screen: levels 11-20 fill, ALL-STAR! and HALL OF FAMER! appear.
	Profile.data.defenders.ace.level = 20
	Profile.data.defenders.maya.level = 11
	var res: Control = load("res://src/ui/results_screen.gd").new()
	res.result = {"won": true, "mode": "quick", "difficulty": "standard", "arena": "steel_yard", "coins": 80, "xp": 150, "rp": 0,
		"levels": 0, "innings_cleared": 3, "outs": 40, "runs": 1, "run_limit": 3, "score": 5200, "mvp": "ace", "packs": [],
		"stats": {"cards_played": 6},
		"defender_xp": {
			"ace": {"xp": 9000, "levels": 1, "level": 20, "level_before": 19, "xp_before": 8000, "xp_after": 0, "outs": 9,
				"rewards": [Profile.level_reward_text(Profile.defender_level_reward(20))]},
			"maya": {"xp": 4000, "levels": 1, "level": 11, "level_before": 10, "xp_before": 2000, "xp_after": 1000, "outs": 4,
				"rewards": [Profile.level_reward_text(Profile.defender_level_reward(11))]},
			"jax": {"xp": 3000, "levels": 1, "level": 15, "level_before": 14, "xp_before": 4000, "xp_after": 500, "outs": 5,
				"rewards": [Profile.level_reward_text(Profile.defender_level_reward(15))]}}}
	get_tree().current_scene.add_child(res)
	await _wait(6.0)
	var pa: Control = res.find_child("Progress_ace", true, false)
	var pm: Control = res.find_child("Progress_maya", true, false)
	var pj: Control = res.find_child("Progress_jax", true, false)
	for i in 150:   # a loaded machine renders slowly: give the XP bars time to fill
		if pa == null or pm == null or pj == null or (_find_label(pa, "LV 20") and _find_label(pj, "LV 15") and _find_label(pm, "LV 11")):
			break
		await _wait(0.2)
	await _wait(0.5)
	_check(pa != null and pa.find_child("HallOfFameFrame", true, false) != null and pa.find_child("HallOfFamePlate", true, false) != null, "u11: Results: Ace gets the gold frame and nameplate at 20")
	_check(pa != null and _find_label(pa, "LV 20") and _find_label(pa, "HALL OF FAMER!") and "Champion Pack" in pa.tooltip_text and _find_label(pa, "ACE"), "u11: Results: HALL OF FAMER!, Ace's name on the gold plate, the Champion Pack in the tooltip")
	_check(pj != null and _find_label(pj, "ALL-STAR!") and "1,000 coins" in pj.tooltip_text and pj.find_child("AllStarPlate", true, false) != null, "u11: Results: ALL-STAR! at 15")
	_check(pm != null and _find_label(pm, "LV 11") and _find_label(pm, "LEVEL UP!  +750 coins"), "u11: Results: a level-up past 10 (10 -> 11)")
	var lv_ok := true
	for p in [pa, pm, pj]:
		if p:
			var ll: Label = p.find_child("LevelLabel", true, false)
			lv_ok = lv_ok and ll != null and p.get_global_rect().encloses(ll.get_global_rect())
	_check(lv_ok, "u11: Results: the two-digit LV labels fit their tiles")
	res.queue_free()
	for id in saved.keys():
		Profile.data.defenders[id] = saved[id]
	Profile.save_now()
	await _wait(0.3)
