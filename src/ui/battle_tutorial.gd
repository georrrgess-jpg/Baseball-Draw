extends CanvasLayer
## Guided first game, learning by doing (Update 13 "Rookie Camp"). Every step is an action with one
## short line of text, a spotlight and an arrow on the thing to touch:
##   1. DRAG A FIELDER   - a ghost hand drags a defender to a glowing ring; waits for a drag.
##   2. PLAY BALL!       - points at PLAY BALL; waits for the wave.
##      (the first throw: "Your fielders throw on their own!", no button)
##   3. PLAY A CARD      - once a runner is on the field: slow motion, Power Throw is in the hand, the
##                         arrow goes card -> runner; waits for a card.
##   4. A PACK OF RUNNERS (first game only) - a staged moment: three runners burst out of the centre
##      gate in a tight pack; near the infield the game drops to bullet time, Heat Wave is in the hand
##      with the energy for it, and the arrow goes card -> pack. Every runner of the pack the fire
##      reaches goes out at once: a TRIPLE PLAY, with a celebration.
## Short one-off tips (no pause) cover the first break, the dugout, the first run and the first boss
## (a weakened Iron Slugger closes the first game: the boss tease). Shown once per profile; the
## Skip link ends it at any time. The game is never paused: slow motion gives the player time instead.

const SLOWMO_CARD := 0.3        # time scale while the first card step waits for the player
const SLOWMO_COMBO := 0.1       # bullet time while the staged pack waits for Heat Wave
const PACK_SIZE := 3
const PACK_HP := 110.0          # survives a few throws; one Heat Wave (120) is enough
const PACK_ROUTE := "center_1b"
const PACK_TRIGGER := 17.0      # metres from the Heat Wave caster: inside its 20 m line of fire
const STAGED_TIMEOUT := 14.0    # real seconds the staged moment waits for the card
const TIP_TIME := 4.0           # real seconds a one-off tip stays up

var hud: Node
var battle: Battle
var first_game := false
var _bubble: PanelContainer
var _title: Label
var _body: RichTextLabel
var _next: Button
var _skip: Button
var _counter: Label
var _timer_bar: ProgressBar
var _pointer: TutorialPointer
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _stamp_layer: Control
var _steps: Array = []
var _step := -1
var _waiting := ""
var _cond: Callable = Callable()      # a deferred step starts when this returns true
var _shown_tips := {}
var _active := false
var _core_done := false
var _tip_until := 0                   # _now_ms() when the current tip hides itself
var _clock := 1.0                     # real seconds as the game's frames count them (slow motion excluded)
var _slow := false
var _staged_t0 := 0
var _focus_card := ""                 # the card the current step asks for
var _drag_df: Defender = null
var _drag_spot := Vector3.ZERO
var _throw_seen := false
var _target_fn: Variant = null          # Callable returning the pointer target (Rect2, Vector2 or null)
## The staged pack (first game): the three runners, whether Heat Wave was cast at them, and how many
## of them went out together (tests read `staged_outs`).
var pack: Array = []
var pack_spawned := false
var _pack_cast_ms := 0
var staged_outs := 0
var celebrated := false


class TutorialPointer:
	extends Control
	var target_rect := Rect2()
	var target_point := Vector2.ZERO
	var has_rect := false
	var has_point := false
	var from_rect := Rect2()
	## Drag demo: a ghost hand travels from `drag_from` to `drag_to` (screen points) on a loop.
	var drag := false
	var drag_from := Vector2.ZERO
	var drag_to := Vector2.ZERO
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta / maxf(Engine.time_scale, 0.01)   # animate in real time, also in slow motion
		queue_redraw()

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(t * 5.0)
		var gold := Color(1.0, 0.8, 0.25)
		if drag:
			_draw_drag(gold, pulse)
		var aim := Vector2.ZERO
		if has_rect:
			var r := target_rect.grow(8.0 + pulse * 5.0)
			draw_rect(r, Color(gold, 0.9), false, 4.0)
			draw_rect(r.grow(6.0), Color(gold, 0.28 * pulse), false, 7.0)
			aim = _closest_point(r, from_rect.get_center())
		elif has_point:
			var rad := 46.0 + pulse * 10.0
			draw_arc(target_point, rad, 0, TAU, 48, Color(gold, 0.95), 4.0, true)
			draw_arc(target_point, rad + 10.0, 0, TAU, 48, Color(gold, 0.3 * pulse), 6.0, true)
			aim = target_point + (from_rect.get_center() - target_point).normalized() * (rad + 4.0)
		else:
			return
		var start := _closest_point(from_rect, aim)
		if start.distance_to(aim) < 30.0:
			return
		var dir := (aim - start).normalized()
		var bob := dir * sin(t * 6.0) * 6.0
		var tip := aim - dir * 4.0 - bob
		draw_line(start, tip - dir * 18.0, Color(gold, 0.95), 5.0, true)
		var side := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 28.0 + side * 15.0, tip - dir * 28.0 - side * 15.0]), Color(gold, 0.95))

	func _draw_drag(gold: Color, pulse: float) -> void:
		var green := Color(0.35, 1.0, 0.55)
		# The destination ring.
		draw_arc(drag_to, 40.0 + pulse * 6.0, 0, TAU, 40, Color(green, 0.95), 4.0, true)
		draw_arc(drag_to, 52.0 + pulse * 8.0, 0, TAU, 40, Color(green, 0.3), 6.0, true)
		# Dotted path.
		var n := 14
		for i in n:
			var k := float(i) / n
			var p := drag_from.lerp(drag_to, k) + Vector2(0, -sin(k * PI) * 40.0)
			draw_circle(p, 3.5, Color(gold, 0.55))
		# The ghost hand: press, travel, release, pause.
		var cyc := fmod(t, 2.2) / 2.2
		var k2 := clampf((cyc - 0.15) / 0.6, 0.0, 1.0)
		k2 = k2 * k2 * (3.0 - 2.0 * k2)
		var hp := drag_from.lerp(drag_to, k2) + Vector2(0, -sin(k2 * PI) * 40.0)
		var down := cyc > 0.1 and cyc < 0.8
		var a := 1.0 if cyc < 0.9 else (1.0 - cyc) * 10.0
		draw_circle(hp, 20.0 if down else 26.0, Color(1, 1, 1, 0.25 * a))
		draw_arc(hp, 20.0 if down else 26.0, 0, TAU, 32, Color(1, 1, 1, 0.9 * a), 3.0, true)
		draw_circle(hp, 7.0, Color(gold, a))

	func _closest_point(r: Rect2, p: Vector2) -> Vector2:
		return Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	first_game = bool(battle.run.config.get("first_game", false))
	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.visible = false
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec2 screen = vec2(1920.0, 1080.0);
uniform vec2 hole_pos = vec2(-9999.0);
uniform vec2 hole_half = vec2(0.0);
uniform float hole_round = 40.0;
uniform float alpha = 0.45;
void fragment() {
	vec2 p = UV * screen;
	vec2 q = abs(p - hole_pos) - hole_half;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - hole_round;
	COLOR = vec4(0.0, 0.015, 0.05, alpha * smoothstep(0.0, 36.0, d));
}
"""
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = sh
	_dim.material = _dim_mat
	add_child(_dim)
	_pointer = TutorialPointer.new()
	_pointer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pointer)
	_stamp_layer = Control.new()
	_stamp_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stamp_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stamp_layer)
	_build_bubble()
	_define_steps()
	battle.state_changed.connect(_on_state)
	battle.defender_moved.connect(_on_moved)
	battle.card_cast.connect(_on_card_cast)
	battle.targeting_changed.connect(func(_i: int) -> void: _refresh_aim_text())
	battle.runner_out.connect(_on_runner_out)
	battle.run_scored.connect(func(_n: int) -> void: _tip("run"))
	battle.boss_spawned.connect(_on_boss)
	_advance.call_deferred()


func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	var st := UITheme.panel_style(Color(0.035, 0.06, 0.12, 0.97), Color(UITheme.GOLD, 0.9), 2, 16, 16)
	st.shadow_color = Color(0, 0, 0, 0.55)
	st.shadow_size = 16
	st.shadow_offset = Vector2(0, 6)
	_bubble.add_theme_stylebox_override("panel", st)
	_bubble.custom_minimum_size = Vector2(470, 0)
	_bubble.visible = false
	add_child(_bubble)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_bubble.add_child(outer)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	outer.add_child(hb)
	# The coach: the captain's portrait in a gold frame.
	var face := PanelContainer.new()
	face.add_theme_stylebox_override("panel", UITheme.panel_style(Color("#10284D"), UITheme.GOLD, 3, 14, 0))
	face.custom_minimum_size = Vector2(76, 76)
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var tr := TextureRect.new()
	tr.texture = DB.portrait(str(battle.run.captain if battle.run.captain != "" else "ace"))
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.add_child(tr)
	hb.add_child(face)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
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
	_body.custom_minimum_size = Vector2(350, 0)
	_body.add_theme_font_size_override("normal_font_size", 23)
	_body.add_theme_font_override("bold_font", UITheme.font_body_bold())
	_body.add_theme_font_size_override("bold_font_size", 24)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	outer.add_child(row)
	_skip = UITheme.small_button("Skip tutorial", UITheme.MUTED, 16)
	_skip.name = "SkipTutorial"
	_skip.pressed.connect(finish)
	_skip.focus_mode = Control.FOCUS_NONE
	row.add_child(_skip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_next = UITheme.small_button("GOT IT", UITheme.SCARLET, 20)
	_next.custom_minimum_size = Vector2(130, 40)
	_next.pressed.connect(_on_next)
	_next.focus_mode = Control.FOCUS_NONE
	row.add_child(_next)
	_timer_bar = UITheme.bar(UITheme.GOLD, 4, 1.0, 0.0)
	_timer_bar.custom_minimum_size = Vector2(0, 4)
	_timer_bar.visible = false
	outer.add_child(_timer_bar)


func _define_steps() -> void:
	_steps = [
		{"id": "drag", "title": "DRAG A FIELDER", "wait": "moved", "spot": true,
			"text": "Hold a fielder and drag them onto the [color=#5CFF8A]green ring[/color].",
			"target": func() -> Variant: return _world(_drag_df.global_position + Vector3(0, 1.0, 0)) if _drag_df and is_instance_valid(_drag_df) else null},
		{"id": "wave", "title": "PLAY BALL!", "wait": "wave", "spot": true,
			"text": "Send in the runners!",
			"target": func() -> Variant: return _rect(hud._start_btn)},
		{"id": "card", "title": "PLAY A CARD", "wait": "card", "spot": true, "card": "power_throw", "slowmo": SLOWMO_CARD,
			"text": "Tap [b]{card}[/b]…", "aim": "…then tap a runner!", "cond": _card_ready,
			"target": _card_target},
	]
	# A deck without Power Throw (a guided game outside the first one): the card step asks for the
	# best runner-hitting card the deck has instead.
	var deck: Array = battle.cards.deck if battle.cards else []
	if not "power_throw" in deck and not deck.is_empty():
		var pick := str(deck[0])
		for want in ["enemy", "area", "path"]:
			var found := deck.filter(func(id: Variant) -> bool: return str(DB.card(str(id)).get("target", "")) == want)
			if not found.is_empty():
				pick = str(found[0])
				break
		_steps[2]["card"] = pick
		if str(DB.card(pick).get("target", "")) == "none":
			_steps[2]["aim"] = "…then tap it again!"
	if first_game and "heat_wave" in deck:
		_steps.append({"id": "combo", "title": "A PACK OF RUNNERS!", "wait": "combo", "spot": true, "card": "heat_wave", "slowmo": SLOWMO_COMBO,
			"text": "Tap [b]{card}[/b]…", "aim": "…then tap the pack!", "cond": _pack_ready,
			"target": _card_target})


# ---------------------------------------------------------------- flow

func _advance() -> void:
	_step += 1
	_cond = Callable()
	_set_slowmo(0.0)
	if _step >= _steps.size():
		_core_done = true
		_waiting = ""
		Profile.data.flags["battle_tutorial_done"] = true
		Profile.save_soon()
		_hide()
		return
	var st: Dictionary = _steps[_step]
	_waiting = str(st.wait)
	_focus_card = str(st.get("card", ""))
	if st.id == "drag":
		_pick_drag()
	if st.get("cond") is Callable:
		_hide()
		_cond = st.cond
		return
	_show_step(st)


func _show_step(st: Dictionary) -> void:
	if battle.state == "results":
		return
	_cond = Callable()
	if _focus_card != "":
		_ensure_in_hand(_focus_card)
	_tip_until = 0
	_pointer.drag = st.id == "drag"
	_present(str(st.title), _step_text(st), st.get("target"), bool(st.get("spot", false)), "%d / %d" % [_step + 1, _steps.size()])
	_next.visible = false
	_timer_bar.visible = false
	if float(st.get("slowmo", 0.0)) > 0.0:
		_set_slowmo(float(st.slowmo))
		_staged_t0 = _now_ms()
	if st.id == "combo":
		Audio.play("swing_whoosh", -4.0)
		battle.crowd_cheer(0.6)
		for e in pack:
			if is_instance_valid(e):
				(e as Enemy).untargetable_t = 0.0
	_refresh_aim_text()
	if _waiting == "wave" and battle.state == "wave":
		_event("wave")


func _present(title: String, text: String, target: Variant, spot: bool, counter := "") -> void:
	_active = true
	_title.text = title
	_body.text = text
	_counter.text = counter
	_skip.visible = not _core_done
	# Fade in once the text has been measured, so the bubble doesn't jump on its first frame.
	_bubble.modulate.a = 0.0
	_bubble.visible = true
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.05)
	tw.tween_callback(_update_layout)
	tw.tween_property(_bubble, "modulate:a", 1.0, 0.18)
	_dim.visible = spot
	_target_fn = target
	_update_layout()


func _hide() -> void:
	_active = false
	_bubble.visible = false
	_dim.visible = false
	_pointer.has_rect = false
	_pointer.has_point = false
	_pointer.drag = false
	_target_fn = null
	_tip_until = 0


func _on_next() -> void:
	Audio.ui("ui_click")
	_hide()


func _event(name: String) -> void:
	if _core_done or _step < 0 or _step >= _steps.size():
		return
	if _waiting == name:
		Audio.ui("ui_confirm")
		_advance()


func _on_state(s: String) -> void:
	match s:
		"wave":
			# Started the wave before dragging: skip ahead to the wave step.
			if not _core_done and _waiting == "moved":
				_step = _index_of("wave")
				_waiting = "wave"
			_event("wave")
		"break":
			_end_staged_if_stuck()
			_tip("break")
		"dugout":
			_end_staged_if_stuck()
			_tip("dugout")
		"results":
			_set_slowmo(0.0)
			_hide()


## A wave ended while the staged pack was still on its way (the defence got them first): move on.
func _end_staged_if_stuck() -> void:
	if _waiting == "combo" and pack_spawned and not celebrated:
		_event("combo")


## The drag step is done: the moved fielder's info panel steps aside so the field stays clear.
func _on_moved(_d: Defender) -> void:
	if _waiting == "moved" and not _core_done:
		battle.select_defender.call_deferred(null)
	_event("moved")


func _on_card_cast(id: String) -> void:
	Session.funnel_mark("first_card")
	if _core_done:
		return
	if _waiting == "card":
		_set_slowmo(0.0)
		_praise("NICE THROW!")
		_event("card")
	elif _waiting == "combo" and id == "heat_wave" and _active:
		# Normal speed for the cast itself; the outs follow in _on_runner_out.
		_set_slowmo(0.0)
		_pack_cast_ms = _now_ms()
		_hide()


## The staged moment: once Heat Wave puts out one runner of the pack, every pack runner still up
## near it goes out with it (the fire line is wide; this makes the triple play a sure thing).
func _on_runner_out(e: Enemy, info: Dictionary) -> void:
	if not e in pack or _pack_cast_ms == 0 or celebrated:
		return
	staged_outs += 1
	if str(info.get("card", "")) == "heat_wave":
		for o in pack:
			var other: Enemy = o
			if is_instance_valid(other) and other.alive and other != e and other.global_position.distance_to(e.global_position) < 8.0:
				battle.deal_damage(other, other.hp + 50.0, {"kind": "fire", "card": "heat_wave", "true": true, "pierce": 1.0})
	if staged_outs >= 2 and not celebrated:
		_celebrate.call_deferred(e.global_position)


func _celebrate(at: Vector3) -> void:
	if celebrated:
		return
	celebrated = true
	var n := staged_outs
	battle.vfx.burst("confetti", at + Vector3(0, 3, 0))
	battle.crowd_cheer(1.0)
	battle.shake(0.35)
	battle.slow_motion(0.9, 0.35)   # a beat of slow motion on the big play
	Audio.play("crowd_roar", -4.0)
	# No out count here: the HUD's combo banner counts every out of the moment (it can be more than the pack).
	_stamp("WHAT A PLAY!", "The whole pack, out in one play!" if n >= 3 else "Two outs in one play!", UITheme.GOLD)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_callback(func() -> void: _event("combo"))


## One-off contextual tips; they hide themselves after TIP_TIME (or GOT IT).
func _tip(id: String, data: Variant = null) -> void:
	if _shown_tips.has(id) or battle.state == "results":
		return
	# Never on top of a step the player is acting on.
	if _active and _tip_until == 0:
		return
	_shown_tips[id] = true
	var tip := {}
	match id:
		"watch":
			tip = {"title": "THEY'RE ON IT!", "text": "Your fielders throw on their own.",
				"target": func() -> Variant: return _lead_runner()}
		"run":
			tip = {"title": "RUN SCORED", "text": "Keep runners away from home plate!",
				"target": func() -> Variant: return _rect(hud._top_runs)}
		"break":
			tip = {"title": "WAVE CLEAR!", "text": "Move fielders, or start the next wave early for a bonus.",
				"target": func() -> Variant: return _rect(hud._start_btn)}
		"dugout":
			tip = {"title": "THE DUGOUT", "text": "Spend your coins on upgrades, then press [b]NEXT INNING[/b].",
				"target": null}
		"boss":
			var e: Enemy = data
			tip = {"title": "BOSS: IRON SLUGGER!", "text": "Hit him with your best cards!",
				"target": func() -> Variant: return _world(e.global_position + Vector3(0, 3.0, 0)) if is_instance_valid(e) and e.alive else null}
	if tip.is_empty():
		return
	_present(str(tip.title), str(tip.text), tip.get("target"), false)
	_next.visible = true
	_next.text = "GOT IT"
	_timer_bar.visible = true
	_tip_until = _now_ms() + int(TIP_TIME * 1000.0)


## A short "NICE THROW!" pop near the hand (no bubble).
func _praise(text: String) -> void:
	_hide()
	_stamp(text, "", UITheme.GREEN, 0.7)


func _on_boss(e: Enemy) -> void:
	# The boss tease: a little extra energy and Power Throw in hand, then the tip after the intro.
	if first_game:
		battle.cards.add_energy(3.0)
		_ensure_in_hand("power_throw")
	if battle._boss_intro_node and is_instance_valid(battle._boss_intro_node):
		battle.boss_intro_finished.connect(func(_b: Enemy) -> void: _tip("boss", e), CONNECT_ONE_SHOT)
	else:
		get_tree().create_timer(0.6, false).timeout.connect(func() -> void: _tip("boss", e))


func finish() -> void:
	Profile.data.flags["battle_tutorial_done"] = true
	Profile.save_soon()
	_core_done = true
	_set_slowmo(0.0)
	_hide()
	queue_free()


func _exit_tree() -> void:
	_set_slowmo(0.0)


func _index_of(id: String) -> int:
	for i in _steps.size():
		if _steps[i].id == id:
			return i
	return _step


# ---------------------------------------------------------------- slow motion and the hand

## factor > 0: the game runs at that fraction of the player's chosen speed; 0 restores it.
func _set_slowmo(factor: float) -> void:
	if factor > 0.0:
		_slow = true
		Engine.time_scale = Battle.SPEEDS[battle.speed_index] * factor if is_instance_valid(battle) else factor
	elif _slow:
		_slow = false
		Engine.time_scale = Battle.SPEEDS[battle.speed_index] if is_instance_valid(battle) else 1.0


## Makes sure card `id` is in the hand, playable now (energy, no cooldown). Returns its slot.
func _ensure_in_hand(id: String) -> int:
	var cs := battle.cards
	if cs == null or not id in cs.deck:
		return -1
	var slot := cs.hand.find(id)
	if slot < 0:
		cs.draw_pile.erase(id)
		cs.discard.erase(id)
		slot = cs.hand.find("")
		if slot < 0 and cs.hand.size() < CardSystem.MAX_HAND:
			cs.hand.append("")
			slot = cs.hand.size() - 1
		if slot < 0:
			# Swap out a card that is not being aimed (it goes back on top of the draw pile).
			slot = 0 if battle.targeting_index != 0 else 1
			cs.draw_pile.append(cs.hand[slot])
		cs.hand[slot] = id
		cs.hand_changed.emit()
	cs.cooldowns.erase(id)
	var need := float(cs.cost_of(id)) - cs.energy
	if need > 0.0:
		cs.add_energy(need + 0.2)
	return slot


func _card_view(id: String) -> Control:
	var i: int = battle.cards.hand.find(id)
	if i < 0 or i >= hud._card_views.size() or not is_instance_valid(hud._card_views[i]):
		return null
	return hud._card_views[i]


## The arrow points at the step's card until it is picked, then at its target.
func _card_target() -> Variant:
	var picked := battle.targeting_index >= 0 and battle.targeting_card() == _focus_card
	if not picked:
		return _rect(_card_view(_focus_card))
	if _waiting == "combo":
		return _pack_point()
	return _lead_runner()


## A step's text with the card it asks for named ("Tap [b]Power Throw[/b]…").
func _step_text(st: Dictionary) -> String:
	var card := str(st.get("card", ""))
	return str(st.text).replace("{card}", str(DB.card(card).get("name", card)) if card != "" else "a card")


func _refresh_aim_text() -> void:
	if not _active or _step < 0 or _step >= _steps.size() or _tip_until != 0:
		return
	var st: Dictionary = _steps[_step]
	if not st.has("aim"):
		return
	var picked := battle.targeting_index >= 0 and battle.targeting_card() == _focus_card
	_body.text = str(st.aim) if picked else _step_text(st)


## The first card step waits for a runner out on the field.
func _card_ready() -> bool:
	if battle.state != "wave" or battle.wave_time < 1.5:
		return false
	for e in battle.enemies:
		if is_instance_valid(e) and (e as Enemy).targetable() and (e as Enemy).d > 3.0 and not (e as Enemy).is_boss:
			return true
	return false


# ---------------------------------------------------------------- the staged pack

func _pack_ready() -> bool:
	if battle.state != "wave":
		return false
	if not pack_spawned:
		# At the start of a wave after the first (never mid-wave: the pack is its own moment).
		if battle.wave_time > 1.5 and battle.wave_time < 4.5 and (battle.run.wave >= 1 or battle.run.inning > 1) \
				and str(battle.wave_info.get("boss", "")) == "" and battle.run.inning <= 2:
			_spawn_pack()
		return false
	var alive := pack.filter(func(e: Variant) -> bool: return is_instance_valid(e) and (e as Enemy).alive)
	if alive.size() < 2:
		_event("combo")   # the defence got there first: no staged moment
		return false
	var caster: Defender = battle.effects.caster_info("heat_wave").caster
	var origin := caster.global_position if caster else Field.MOUND
	for e in alive:
		if (e as Enemy).tunnel_left > 0.0:
			return false
	var lead: Enemy = alive[0]
	for e in alive:
		if (e as Enemy).d > lead.d:
			lead = e
	return Field.v2(lead.global_position).distance_to(Field.v2(origin)) < PACK_TRIGGER


## Three runners in a tight pack out of the centre gate (the straight route toward the mound, the
## line Heat Wave fires along). They count toward the wave like any other runner.
func _spawn_pack() -> void:
	pack_spawned = true
	var ri := 0
	for i in battle.routes.size():
		if battle.routes[i].id == PACK_ROUTE:
			ri = i
	var route: Route = battle.routes[ri]
	var hp_mult := PACK_HP / maxf(float(DB.enemy("runner").get("hp", 70)), 1.0)
	var spd := WaveGenerator.speed_multiplier(battle.run)
	var laterals := [0.0, -0.55, 0.55]
	for k in PACK_SIZE:
		var e := battle.spawn_enemy("runner", route, 0.0, {"hp_mult": hp_mult, "speed_mult": spd,
			"lateral": laterals[k % laterals.size()], "tunnel": Battle.TUNNEL_SPAWN * 0.35 + k * 0.85})
		e._tick_tunnel(0.0)
		battle.wave_total += 1
		battle.wave_spawned += 1
		pack.append(e)
	battle.stadium.set_gate_open(route.gate, true)
	Audio.play("gate_open", -6.0)


func _pack_point() -> Variant:
	var sum := Vector3.ZERO
	var n := 0
	for e in pack:
		if is_instance_valid(e) and (e as Enemy).alive:
			sum += (e as Enemy).global_position
			n += 1
	if n == 0:
		return null
	return _world(sum / n + Vector3(0, 1.2, 0))


# ---------------------------------------------------------------- the drag step

## The fielder to drag (not the captain on the mound) and a good spot for them, toward the centre
## gate's route, that passes the placement rules.
func _pick_drag() -> void:
	_drag_df = null
	for df in battle.defenders:
		if df.id != battle.run.captain and Field.v2(df.post).distance_to(Field.v2(Field.MOUND)) > 6.0:
			if _drag_df == null or df.post.z < _drag_df.post.z:
				_drag_df = df
	if _drag_df == null and not battle.defenders.is_empty():
		_drag_df = battle.defenders[battle.defenders.size() - 1]
	if _drag_df == null:
		return
	var aim := Vector3(signf(_drag_df.post.x) * 3.5, 0, -12.0)
	_drag_spot = battle.find_valid_spot(_drag_df.post.lerp(aim, 0.5), _drag_df)
	if _drag_spot.distance_to(_drag_df.post) < 2.0:
		_drag_spot = battle.find_valid_spot(_drag_df.post + Vector3(0, 0, -3.5), _drag_df)


# ---------------------------------------------------------------- celebration stamp

func _stamp(text: String, sub: String, col: Color, hold := 1.4) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -4)
	var vs := get_viewport().get_visible_rect().size
	box.size = Vector2(vs.x, 260)
	box.position = Vector2(0, vs.y * 0.3 - 130)
	box.pivot_offset = box.size * 0.5
	_stamp_layer.add_child(box)
	var big := UITheme.title(text, 104 if sub != "" else 76, col)
	big.add_theme_constant_override("outline_size", 16)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)
	if sub != "":
		var s := UITheme.label(sub, 34, Color.WHITE, UITheme.font_display())
		s.add_theme_constant_override("outline_size", 10)
		s.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(s)
	box.scale = Vector2(2.2, 2.2)
	box.modulate.a = 0.0
	var tw := box.create_tween()   # game time: it stays up as long as the moment does
	tw.tween_property(box, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(box, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(box, "position:y", box.position.y - 40.0, 0.35)
	tw.tween_callback(box.queue_free)


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
	for e in battle.lead_runners(3):
		if (e as Enemy).targetable():
			return _world((e as Enemy).global_position + Vector3(0, 1.4, 0))
	return null


func _now_ms() -> int:
	return int(_clock * 1000.0)


func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.001)
	if not is_instance_valid(battle):
		return
	# Funnel: the first throw of a defender in the first game.
	if not _throw_seen and battle.state == "wave":
		for b in battle.projectiles.balls:
			if b.active:
				_throw_seen = true
				Session.funnel_mark("first_throw")
				if not _core_done and _waiting == "card" and not _active:
					_tip("watch")
				break
	# The staged pack runs in untouched until the moment (the defence would otherwise thin it out first).
	if pack_spawned and _waiting == "combo" and _cond.is_valid():
		for e in pack:
			if is_instance_valid(e) and (e as Enemy).alive:
				(e as Enemy).untargetable_t = maxf((e as Enemy).untargetable_t, 0.25)
	if _cond.is_valid() and not _core_done and (not _active or _tip_until != 0) and _cond.call():
		_hide()
		_show_step(_steps[_step])
	if _tip_until != 0:
		var left := float(_tip_until - _now_ms()) / 1000.0
		_timer_bar.value = clampf(left / TIP_TIME, 0.0, 1.0)
		if left <= 0.0:
			_hide()
	# The staged moment never waits forever: back to normal speed and on with the game.
	if _slow and _staged_t0 > 0 and _now_ms() - _staged_t0 > int(STAGED_TIMEOUT * 1000.0):
		_staged_t0 = 0
		_set_slowmo(0.0)
		if _waiting == "combo":
			_hide()
			_event("combo")
	if _waiting == "combo" and _pack_cast_ms > 0 and not celebrated and _now_ms() - _pack_cast_ms > 3000:
		_event("combo")   # the fire missed the pack
	if _active:
		_update_layout()


func _update_layout() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var target: Variant = null
	var tf: Variant = _target_fn
	if tf is Callable:
		target = (tf as Callable).call()
	_pointer.has_rect = target is Rect2
	_pointer.has_point = target is Vector2
	if target is Rect2:
		_pointer.target_rect = target
	elif target is Vector2:
		_pointer.target_point = target
	if _pointer.drag and _drag_df and is_instance_valid(_drag_df):
		var a: Variant = _world(_drag_df.global_position + Vector3(0, 0.3, 0))
		var b: Variant = _world(_drag_spot + Vector3(0, 0.1, 0))
		if a is Vector2 and b is Vector2:
			_pointer.drag_from = a
			_pointer.drag_to = b
		_pointer.has_point = false   # the ghost hand is the pointer
		target = _pointer.drag_from.lerp(_pointer.drag_to, 0.5)
	# Spotlight: a soft hole around the target.
	_dim_mat.set_shader_parameter("screen", vs)
	if target is Rect2:
		var r: Rect2 = target
		_dim_mat.set_shader_parameter("hole_pos", r.get_center())
		_dim_mat.set_shader_parameter("hole_half", r.size * 0.5 + Vector2(10, 10))
		_dim_mat.set_shader_parameter("hole_round", 16.0)
	elif target is Vector2:
		_dim_mat.set_shader_parameter("hole_pos", target)
		var span := (_pointer.drag_to - _pointer.drag_from).abs() * 0.5 if _pointer.drag else Vector2.ZERO
		_dim_mat.set_shader_parameter("hole_half", span)
		_dim_mat.set_shader_parameter("hole_round", 90.0)
	else:
		_dim_mat.set_shader_parameter("hole_pos", Vector2(-9999, -9999))
	_dim_mat.set_shader_parameter("alpha", 0.5 if _slow else 0.36)
	# Place the bubble away from the target, inside the screen and above the hand.
	var bsize := _bubble.get_combined_minimum_size()
	_bubble.size = bsize
	var center := vs * 0.5
	var pos := Vector2(center.x - bsize.x * 0.5, vs.y * 0.2)
	if target != null:
		var tc: Vector2 = (target as Rect2).get_center() if target is Rect2 else target
		var away := center - tc
		if away.length() < 80.0:
			away = Vector2(0, -1)
		var want := tc + away.normalized() * (bsize.length() * 0.5 + 170.0)
		pos = want - bsize * 0.5
	pos.x = clampf(pos.x, 20.0, vs.x - bsize.x - 20.0)
	pos.y = clampf(pos.y, 90.0, vs.y - bsize.y - 250.0)
	_bubble.position = pos
	_pointer.from_rect = Rect2(pos, bsize)
