extends CanvasLayer
## Guided first game. Coach pop-ups point at the field and the HUD, wait for the player
## to try each action (move a defender, start the wave, play a card) and pause the game
## while they explain. Contextual tips cover the first run scored, the first break, the
## dugout, the first boss and the results. Shown once per profile; skippable.

var hud: Node
var battle: Battle
var _bubble: PanelContainer
var _title: Label
var _body: RichTextLabel
var _next: Button
var _skip: Button
var _counter: Label
var _pointer: TutorialPointer
var _dim: ColorRect
var _steps: Array = []
var _step := -1
var _waiting := ""
var _paused_by_me := false
var _shown_tips := {}
var _queue: Array = []
var _active := false
var _core_done := false


class TutorialPointer:
	extends Control
	var target_rect := Rect2()
	var target_point := Vector2.ZERO
	var has_rect := false
	var has_point := false
	var from_rect := Rect2()
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		var gold := Color(1.0, 0.8, 0.25)
		var aim := Vector2.ZERO
		if has_rect:
			var r := target_rect.grow(8.0 + pulse * 5.0)
			draw_rect(r, Color(gold, 0.85), false, 4.0)
			draw_rect(r.grow(5.0), Color(gold, 0.25 * pulse), false, 6.0)
			aim = _closest_point(r, from_rect.get_center())
		elif has_point:
			var rad := 46.0 + pulse * 10.0
			draw_arc(target_point, rad, 0, TAU, 48, Color(gold, 0.9), 4.0, true)
			draw_arc(target_point, rad + 9.0, 0, TAU, 48, Color(gold, 0.3 * pulse), 6.0, true)
			aim = target_point + (from_rect.get_center() - target_point).normalized() * (rad + 4.0)
		else:
			return
		var start := _closest_point(from_rect, aim)
		if start.distance_to(aim) < 30.0:
			return
		var dir := (aim - start).normalized()
		var tip := aim - dir * 4.0
		draw_line(start, tip - dir * 18.0, Color(gold, 0.95), 5.0, true)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 26.0 + side * 14.0, tip - dir * 26.0 - side * 14.0]), Color(gold, 0.95))

	func _closest_point(r: Rect2, p: Vector2) -> Vector2:
		return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.02, 0.06, 0.4)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	add_child(_dim)
	_pointer = TutorialPointer.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pointer)
	_build_bubble()
	_define_steps()
	battle.state_changed.connect(_on_state)
	battle.defender_moved.connect(func(_d: Defender) -> void: _event("moved"))
	battle.card_cast.connect(func(_id: String) -> void: _event("card"))
	battle.run_scored.connect(func(_n: int) -> void: _tip("run"))
	battle.boss_spawned.connect(func(e: Enemy) -> void: _tip("boss", e))
	_advance.call_deferred()


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.04, 0.07, 0.13, 0.97), Color(UITheme.GOLD, 0.85), 2, 14, 20))
	_bubble.custom_minimum_size = Vector2(500, 0)
	_bubble.visible = false
	add_child(_bubble)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_bubble.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	_title = UITheme.label("", 34, UITheme.GOLD, UITheme.font_display())
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_counter = UITheme.label("", 16, UITheme.MUTED, UITheme.font_body_bold())
	head.add_child(_counter)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.custom_minimum_size = Vector2(460, 0)
	_body.add_theme_font_size_override("normal_font_size", 21)
	_body.add_theme_font_override("bold_font", UITheme.font_body_bold())
	_body.add_theme_font_size_override("bold_font_size", 22)
	vb.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	_skip = UITheme.small_button("Skip tutorial", UITheme.MUTED, 17)
	_skip.pressed.connect(finish)
	_skip.focus_mode = Control.FOCUS_NONE
	row.add_child(_skip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_next = UITheme.small_button("NEXT  ▶", UITheme.SCARLET, 22)
	_next.custom_minimum_size = Vector2(150, 44)
	_next.pressed.connect(_on_next)
	_next.focus_mode = Control.FOCUS_NONE
	row.add_child(_next)


func _define_steps() -> void:
	_steps = [
		{"title": "DEFEND THE DIAMOND", "wait": "next",
			"text": "Rival runners burst out of the [b]gates[/b] in the outfield and race along the glowing paths to [b]home plate[/b]. Your job is to stop them.",
			"target": func() -> Variant: return _world(battle.routes[0].raw_points[0] + Vector3(0, 1.5, 0))},
		{"title": "OUTS AND RUNS", "wait": "next",
			"text": "Every runner your team stops is an [color=#3DDC84][b]OUT[/b][/color]. A runner who reaches home plate scores a [color=#ff5a50][b]RUN[/b][/color] against you. Fill all three circles and the game is over.",
			"target": func() -> Variant: return _rect(hud._top_runs)},
		{"title": "YOUR TEAM", "wait": "next",
			"text": "Your six defenders throw at runners [b]on their own[/b]. The ring under each one shows how far they can throw — a [color=#3DDC84]green[/color] ring means they stand in their best spot.",
			"target": func() -> Variant: return _world(battle.defenders[0].global_position + Vector3(0, 1.0, 0))},
		{"title": "MOVE A DEFENDER", "wait": "moved",
			"text": "Hold the [b]left mouse button[/b] on a defender and drag them somewhere new. [color=#F5B82E]Try it now![/color]",
			"target": func() -> Variant: return _world(battle.defenders[battle.defenders.size() - 1].global_position + Vector3(0, 1.0, 0))},
		{"title": "FORMATIONS", "wait": "next",
			"text": "Or place the whole team at once with a [b]formation[/b]. Some defenders get bonus [b]synergies[/b] when they play together — active ones are listed here.",
			"target": func() -> Variant: return _rect(hud._setup_panel)},
		{"title": "PLAY BALL!", "wait": "wave",
			"text": "Ready? Press [b]PLAY BALL![/b] (or [b]Space[/b]) to send in the first wave.",
			"target": func() -> Variant: return _rect(hud._start_btn)},
		{"title": "HERE THEY COME!", "wait": "next", "pause": true, "delay": 2.5,
			"text": "Runners are on the field and your defenders are already throwing. Every hit drains the runner's health bar until they're [b]out[/b].",
			"target": func() -> Variant: return _lead_runner()},
		{"title": "PLAY A CARD", "wait": "card",
			"text": "Cards are your special plays. Press [b]1[/b] (or click a card), then [b]click near the runners[/b] to use it. [color=#3FD0FF]Each card costs energy[/color] — the number on its blue gem.",
			"target": func() -> Variant: return _rect(hud._hand_box)},
		{"title": "NICE PLAY!", "wait": "next", "pause": true,
			"text": "[color=#3FD0FF]Energy[/color] refills over time and new cards are drawn automatically. Save your strongest cards for big crowds and bosses.\n\nThat's the basics — good luck, Manager!",
			"target": func() -> Variant: return _rect(hud._energy_bar)},
	]


# ---------------------------------------------------------------- flow

func _advance() -> void:
	_step += 1
	if _step >= _steps.size():
		_core_done = true
		Profile.data.flags["battle_tutorial_done"] = true
		Profile.save_soon()
		_hide()
		_flush_queue()
		return
	var st: Dictionary = _steps[_step]
	var delay := float(st.get("delay", 0.0))
	if delay > 0.0:
		_hide()
		get_tree().create_timer(delay, false).timeout.connect(_show_step.bind(st))
	else:
		_show_step(st)


func _show_step(st: Dictionary) -> void:
	if battle.state in ["results"]:
		return
	_waiting = str(st.get("wait", "next"))
	_present(str(st.title), str(st.text), st.get("target"), bool(st.get("pause", false)) or _waiting == "next" and battle.state == "wave",
		"%d / %d" % [_step + 1, _steps.size()])
	_next.visible = _waiting == "next"
	_next.text = "LET'S GO!" if _step == _steps.size() - 1 else "NEXT  ▶"
	if _waiting == "wave" and battle.state == "wave":
		_event("wave")


func _present(title: String, text: String, target: Variant, pause: bool, counter := "") -> void:
	_active = true
	_title.text = title
	_body.text = text
	_counter.text = counter
	_skip.visible = not _core_done
	# Fade in once the text has been measured, so the bubble doesn't jump on its first frame.
	_bubble.modulate.a = 0.0
	_bubble.visible = true
	var tw := create_tween()
	tw.tween_interval(0.06)
	tw.tween_callback(_update_layout)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.18)
	_set_paused(pause)
	_dim.visible = pause
	_pointer.set_meta("target", target)
	_update_layout()


func _hide() -> void:
	_active = false
	_bubble.visible = false
	_dim.visible = false
	_pointer.has_rect = false
	_pointer.has_point = false
	_pointer.set_meta("target", null)
	_set_paused(false)


func _on_next() -> void:
	Audio.ui("ui_click")
	if _step < _steps.size() and not _core_done:
		_advance()
	else:
		_hide()
		_flush_queue()


func _event(name: String) -> void:
	if _core_done or _step < 0 or _step >= _steps.size():
		return
	if _waiting == name:
		Audio.ui("ui_confirm")
		_advance()


func _on_state(s: String) -> void:
	match s:
		"wave":
			# Started the wave before trying everything in setup: jump to the wave steps.
			if not _core_done and _waiting != "wave" and _step < 5:
				_step = 5
				_waiting = "wave"
			_event("wave")
		"break":
			_tip("break")
		"dugout":
			_tip("dugout")
		"results":
			_tip("results")


## One-off contextual tips; queued while a core step is on screen.
func _tip(id: String, data: Variant = null) -> void:
	if _shown_tips.has(id):
		return
	_shown_tips[id] = true
	var tip := {}
	match id:
		"run":
			tip = {"title": "RUN SCORED!", "text": "A runner reached home plate. The blue dome over the plate is a [b]Base Shield[/b] — each one blocks a run. Keep runners away from home!",
				"target": func() -> Variant: return _rect(hud._top_runs)}
		"break":
			tip = {"title": "WAVE CLEARED!", "text": "Take a breath. Move defenders if you like, then start the next wave. Starting early earns [color=#F5B82E]bonus coins[/color].",
				"target": func() -> Variant: return _rect(hud._start_btn)}
		"dugout":
			tip = {"title": "THE DUGOUT", "text": "After every inning, spend the coins you earned on [b]upgrades[/b] for the rest of this game. Then press [b]NEXT INNING[/b].",
				"target": null}
		"boss":
			var e: Enemy = data
			tip = {"title": "BOSS INCOMING!", "text": "Bosses are tough and have special attacks — [color=#ff5a50]red circles[/color] on the ground warn you where they'll strike. Hit them with your strongest cards!",
				"target": func() -> Variant: return _world(e.global_position + Vector3(0, 2.5, 0)) if is_instance_valid(e) else null}
		"results":
			tip = {"title": "GAME OVER — WELL PLAYED!", "text": "You earned [color=#F5B82E][b]card packs[/b][/color]! Open them to collect new cards — every new card can go straight into your deck.",
				"target": null}
	if tip.is_empty():
		return
	if _active:
		_queue.append(tip)
	else:
		_show_tip(tip)


func _show_tip(tip: Dictionary) -> void:
	_waiting = "tip"
	_present(str(tip.title), str(tip.text), tip.get("target"), battle.state == "wave")
	_next.visible = true
	_next.text = "GOT IT"


func _flush_queue() -> void:
	if not _queue.is_empty() and not _active:
		_show_tip(_queue.pop_front())


func finish() -> void:
	Profile.data.flags["battle_tutorial_done"] = true
	Profile.save_soon()
	_core_done = true
	_queue.clear()
	_hide()
	queue_free()


func _set_paused(on: bool) -> void:
	if on and not get_tree().paused:
		get_tree().paused = true
		_paused_by_me = true
	elif not on and _paused_by_me:
		get_tree().paused = false
		_paused_by_me = false


func _exit_tree() -> void:
	if _paused_by_me:
		get_tree().paused = false


# ---------------------------------------------------------------- targets & layout

func _rect(c: Control) -> Variant:
	if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
		return null
	return c.get_global_rect()


func _world(p: Vector3) -> Variant:
	var cam := battle.get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(p):
		return null
	return cam.unproject_position(p)


func _lead_runner() -> Variant:
	var lead := battle.lead_runners(1)
	if lead.is_empty():
		return null
	return _world(lead[0].global_position + Vector3(0, 1.4, 0))


func _process(_delta: float) -> void:
	if _active:
		_update_layout()


func _update_layout() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var target: Variant = null
	var tf: Variant = _pointer.get_meta("target", null)
	if tf is Callable:
		target = (tf as Callable).call()
	_pointer.has_rect = target is Rect2
	_pointer.has_point = target is Vector2
	if target is Rect2:
		_pointer.target_rect = target
	elif target is Vector2:
		_pointer.target_point = target
	# Place the bubble away from the target, inside the screen.
	var bsize := _bubble.get_combined_minimum_size()
	_bubble.size = bsize
	var center := vs * 0.5
	var pos := center - bsize * 0.5
	if target != null:
		var tc: Vector2 = (target as Rect2).get_center() if target is Rect2 else target
		var away := center - tc
		if away.length() < 80.0:
			away = Vector2(0, 1)
		var want := tc + away.normalized() * (bsize.length() * 0.5 + 170.0)
		pos = want - bsize * 0.5
	pos.x = clampf(pos.x, 20.0, vs.x - bsize.x - 20.0)
	pos.y = clampf(pos.y, 90.0, vs.y - bsize.y - 250.0)
	_bubble.position = pos
	_pointer.from_rect = Rect2(pos, bsize)
