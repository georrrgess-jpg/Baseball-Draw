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
			await _click(sp)
			await _wait(0.4)
			cast_ok = battle.cards.hand_count() < hand_before or battle.cards.energy < energy_before - 0.5
			_check(cast_ok, "clicking the field casts '%s' (energy %.1f -> %.1f)" % [id, energy_before, battle.cards.energy])
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
	await _test_deck_menus()
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
