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
	if "--ui-test-section=tutorial" in OS.get_cmdline_user_args():
		await _test_tutorial()
		_finish()
		return
	if "--ui-test-section=deck" in OS.get_cmdline_user_args():
		await _test_deck_menus()
		_finish()
		return
	if "--ui-test-section=cards" in OS.get_cmdline_user_args():
		await _test_card_clicks()
		_finish()
		return
	if "--ui-test-section=daily" in OS.get_cmdline_user_args():
		await _test_daily()
		_finish()
		return
	if "--ui-test-section=nav" in OS.get_cmdline_user_args():
		await _test_navigation()
		_finish()
		return
	if "--ui-test-section=packs" in OS.get_cmdline_user_args():
		await _test_packs()
		await _test_multi_packs()
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
	await _test_daily()
	await _test_navigation()
	await _test_tutorial()
	_finish()


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
	var back := _find_button(us, "◀  BACK")
	_check(back != null, "card upgrades has a BACK button")
	if back:
		await _click(_button_center(back))
		_check(await _wait_scene("deck_builder"), "BACK from Card Upgrades returns to Cards & Deck")
	await _wait(0.5)
	Router.goto("main_menu")
	await _wait_scene("main_menu")


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
	var got := _find_button(Hints.current(), "GOT IT") if Hints.current() else null
	_check(got != null, "hint has a GOT IT button")
	if got:
		await _click(_button_center(got))
		await _wait(0.4)
	_check(Hints.seen("packs_intro"), "GOT IT marks the hint seen")
	_check(Hints.current_id() == "packs_rarity", "the next hint of the screen follows, one at a time (%s)" % Hints.current_id())
	var stacked := 0
	for c in get_tree().current_scene.find_children("*", "CanvasLayer", true, false):
		if c.find_child("HintCard", true, false) != null:
			stacked += 1
	_check(stacked == 1, "exactly one hint on screen (%d)" % stacked)
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
	for scene in ["play_menu", "packs", "deck_builder", "card_upgrades", "roster", "progression", "settings"]:
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
		if not lead.is_empty():
			tpos = lead[0].global_position
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
			print("[UITEST] note: no cast of '%s' at %s (targeting %d, over ui %s, preview %s)" % [pick.card_id, sp,
				battle.targeting_index, hc.get_path() if hc else "none", battle.target_preview.get("valid", "?")])
	_check(clicks >= 8, "fast play made %d card clicks" % clicks)
	_check(misses.is_empty(), "no fast card click was dropped (%d dropped: %s)" % [misses.size(), misses])
	_check(casts >= 4, "fast play cast %d cards" % casts)


func _finish() -> void:
	print("[UITEST] ===== %d checks, %d failed =====" % [results.size(), failures])
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit(1 if failures > 0 else 0)
