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
			var hand_before := battle.cards.hand.size()
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
			cast_ok = battle.cards.hand.size() < hand_before or battle.cards.energy < energy_before - 0.5
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


func _finish() -> void:
	print("[UITEST] ===== %d checks, %d failed =====" % [results.size(), failures])
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().quit(1 if failures > 0 else 0)
