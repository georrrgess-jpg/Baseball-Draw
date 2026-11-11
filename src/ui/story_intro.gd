class_name StoryIntro
extends CanvasLayer
## Update 13 (Rookie Camp): the story intro a brand-new player sees between the title screen and the
## guided first game. Three animated story cards over the live title stadium (about 4 s each, under
## 15 s in all), then a "PLAY BALL!" slam:
##   1. THE WRECKERS ARE COMING!  (the rival runners and the Iron Slugger burst in)
##   2. YOUR TEAM IS READY        (the six defenders pop in, one by one)
##   3. YOU MAKE THE BIG PLAYS    (three ability cards fan out)
## A click, Space or Enter moves to the next card; SKIP (or Esc) jumps to the game; "I've played
## before" leaves for the hub. The title screen decides what happens next through the signals.

signal finished(skipped: bool)
signal played_before

const CARD_TIME := 4.0           # seconds each story card stays up (auto-advance)
const CARD_SIZE := Vector2(1240, 600)
const WRECKERS := Color("#FF6A2B")
const STORIES := [
	{"kicker": "TONIGHT AT STEEL YARD", "title": "THE WRECKERS ARE COMING!",
		"text": "A rival crew of runners is storming your stadium.", "accent": Color("#FF6A2B"), "bg": Color("#3A0F0C")},
	{"kicker": "YOUR CLUB", "title": "YOUR TEAM IS READY",
		"text": "Your six fielders throw at runners on their own.", "accent": Color("#F5B82E"), "bg": Color("#0C1F3E")},
	{"kicker": "YOUR CALL, MANAGER", "title": "YOU MAKE THE BIG PLAYS",
		"text": "Play cards to stop runners before they reach home plate.", "accent": Color("#3FD0FF"), "bg": Color("#1A1036")},
]

var index := -1
var _root: Control
var _backdrop: ColorRect
var _card: Control
var _pips: Array[ProgressBar] = []
var _skip: Button
var _before: Button
var _t := 0.0
var _done := false
var _slam: Label


func _ready() -> void:
	layer = 20
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_root_input)
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	vec2 d = UV - vec2(0.5);
	float v = smoothstep(0.2, 0.85, length(d * vec2(1.3, 1.0)));
	COLOR = vec4(0.01, 0.015, 0.04, amount * (0.72 + 0.26 * v));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	_backdrop.material = m
	_root.add_child(_backdrop)
	var tw := _backdrop.create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("amount", v), 0.0, 1.0, 0.35)

	# Progress pips (one per card) at the bottom centre.
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 12)
	pips.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pips.position = Vector2(-165, -70)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(pips)
	for i in STORIES.size():
		var pb := UITheme.bar(Color(STORIES[i].accent), 8, 1.0, 0.0)
		pb.custom_minimum_size = Vector2(102, 8)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pb)
		_pips.append(pb)

	_skip = UITheme.button("SKIP", "secondary", 24, "fast_forward")
	_skip.name = "IntroSkip"
	_skip.custom_minimum_size = Vector2(170, 54)
	_skip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip.position = Vector2(-210, 36)
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.tooltip_text = "Skip the intro (Esc) and start your first game."
	_skip.pressed.connect(skip)
	_root.add_child(_skip)

	_before = UITheme.button("I've played before  ▸", "ghost", 22)
	_before.name = "PlayedBefore"
	_before.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	_before.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_before.position = Vector2(36, -96)
	_before.focus_mode = Control.FOCUS_NONE
	_before.tooltip_text = "Skip the guided first game and go to the clubhouse."
	_before.pressed.connect(func() -> void:
		if _done:
			return
		_done = true
		played_before.emit())
	_root.add_child(_before)
	for b in [_skip, _before]:
		b.modulate.a = 0.0
		(b as Node).create_tween().tween_property(b, "modulate:a", 1.0, 0.4).set_delay(0.5)
	Audio.play("swing_whoosh", -8.0)
	next()


func _process(delta: float) -> void:
	if _done or index < 0 or index >= STORIES.size():
		return
	_t += delta
	_pips[index].value = clampf(_t / CARD_TIME, 0.0, 1.0)
	if _t >= CARD_TIME:
		next()


func _on_root_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		_root.accept_event()
		next()


func _unhandled_input(e: InputEvent) -> void:
	if _done:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		get_viewport().set_input_as_handled()
		if e.keycode == KEY_ESCAPE:
			skip()
		elif e.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_RIGHT]:
			next()
	elif e is InputEventJoypadButton and e.pressed:
		get_viewport().set_input_as_handled()
		next()


## Moves to the next story card (or, after the last, the PLAY BALL! slam and `finished`).
func next() -> void:
	if _done:
		return
	if index >= 0 and index < _pips.size():
		_pips[index].value = 1.0
	index += 1
	_t = 0.0
	if _card and is_instance_valid(_card):
		_leave(_card)
		_card = null
	if index >= STORIES.size():
		_play_ball(false)
		return
	_card = _build_card(index)
	_root.add_child(_card)
	_root.move_child(_card, 1)
	_enter(_card)


## Jumps to the game (SKIP / Esc).
func skip() -> void:
	if _done:
		return
	if _card and is_instance_valid(_card):
		_leave(_card)
		_card = null
	_play_ball(true)


func _play_ball(skipped: bool) -> void:
	_done = true
	_skip.disabled = true
	_before.disabled = true
	for b in [_skip, _before]:
		(b as Node).create_tween().tween_property(b, "modulate:a", 0.0, 0.2)
	_slam = UITheme.title("PLAY BALL!", 150, UITheme.GOLD)
	_slam.add_theme_constant_override("outline_size", 18)
	_slam.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_slam.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_slam.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_slam)
	_slam.pivot_offset = get_viewport().get_visible_rect().size * 0.5
	_slam.scale = Vector2(2.4, 2.4)
	_slam.modulate.a = 0.0
	Audio.play("bat_crack", -2.0)
	Audio.play("crowd_roar", -6.0)
	var tw := _slam.create_tween()
	tw.tween_property(_slam, "modulate:a", 1.0, 0.1)
	tw.parallel().tween_property(_slam, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.35 if skipped else 0.7)
	tw.tween_callback(func() -> void: finished.emit(skipped))


# ---------------------------------------------------------------- cards

func _enter(c: Control) -> void:
	c.modulate.a = 0.0
	c.scale = Vector2(0.86, 0.86)
	c.rotation = deg_to_rad(-4.0)
	c.position.x += 160.0
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "modulate:a", 1.0, 0.22)
	tw.tween_property(c, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "rotation", deg_to_rad(-1.2), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "position:x", c.position.x - 160.0, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Slow drift while it is up (a little life on the hold).
	var drift := c.create_tween()
	drift.tween_interval(0.45)
	drift.tween_property(c, "scale", Vector2(1.025, 1.025), CARD_TIME).set_trans(Tween.TRANS_SINE)
	Audio.play("card_whoosh", -4.0)


func _leave(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "modulate:a", 0.0, 0.3)
	tw.tween_property(c, "position:x", c.position.x - 260.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "rotation", deg_to_rad(-6.0), 0.32)
	tw.chain().tween_callback(c.queue_free)


func _build_card(i: int) -> Control:
	var st: Dictionary = STORIES[i]
	var accent: Color = st.accent
	var vs := get_viewport().get_visible_rect().size
	var c := Control.new()
	c.name = "StoryCard%d" % (i + 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.size = CARD_SIZE
	c.position = (vs - CARD_SIZE) * 0.5 + Vector2(0, -26)
	c.pivot_offset = CARD_SIZE * 0.5
	# Panel: a deep tinted gradient with halftone dots, speed lines and a gold-trimmed frame.
	var bg := ColorRect.new()
	bg.size = CARD_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 base : source_color;
uniform vec4 accent : source_color;
uniform float t = 0.0;
float rect_mask(vec2 uv, vec2 size, float r) {
	vec2 q = abs(uv - 0.5) * size - (size * 0.5 - vec2(r));
	return 1.0 - smoothstep(-1.0, 1.0, length(max(q, 0.0)) - r);
}
void fragment() {
	vec2 size = vec2(1240.0, 600.0);
	vec2 uv = UV;
	vec3 col = mix(base.rgb * 1.35, base.rgb * 0.55, uv.y);
	// light burst from the art side
	vec2 c = (uv - vec2(0.3, 0.42)) * vec2(2.0, 1.0);
	float ang = atan(c.y, c.x);
	float rays = smoothstep(0.55, 1.0, sin(ang * 18.0 + t * 0.6)) * (1.0 - smoothstep(0.0, 1.1, length(c)));
	col += accent.rgb * rays * 0.22;
	col += accent.rgb * (1.0 - smoothstep(0.0, 0.9, length(c))) * 0.28;
	// halftone dots, denser to the lower right
	vec2 g = fract(uv * size / 14.0) - 0.5;
	float dot_r = 0.12 + 0.3 * smoothstep(0.2, 1.2, uv.x + uv.y * 0.6);
	col += accent.rgb * (1.0 - smoothstep(dot_r - 0.05, dot_r, length(g))) * 0.10;
	// speed streaks
	float s = fract(uv.y * 23.0 + floor(uv.x * 3.0) * 0.37 - t * 0.0);
	float streak = smoothstep(0.97, 1.0, s) * smoothstep(0.35, 0.95, uv.x) * 0.18;
	col += vec3(streak);
	float m = rect_mask(uv, size, 26.0);
	float inner = rect_mask((uv - 0.5) * (size / (size - 12.0)) + 0.5, size - 12.0, 22.0);
	vec3 frame = mix(accent.rgb, vec3(1.0, 0.95, 0.8), 0.25);
	col = mix(frame, col, inner);
	COLOR = vec4(col, m * 0.98);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("base", st.bg)
	mat.set_shader_parameter("accent", accent)
	bg.material = mat
	c.add_child(bg)
	var bt := bg.create_tween()
	bt.tween_method(func(v: float) -> void: mat.set_shader_parameter("t", v), 0.0, 6.0, CARD_TIME + 1.0)
	# Drop shadow under the panel.
	var shadow := Panel.new()
	var ss := StyleBoxFlat.new()
	ss.bg_color = Color(0, 0, 0, 0)
	ss.set_corner_radius_all(26)
	ss.shadow_color = Color(0, 0, 0, 0.55)
	ss.shadow_size = 40
	ss.shadow_offset = Vector2(0, 18)
	shadow.add_theme_stylebox_override("panel", ss)
	shadow.size = CARD_SIZE
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(shadow)
	c.move_child(shadow, 0)

	var art := Control.new()
	art.name = "Art"
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(28, 28)
	art.size = Vector2(700, CARD_SIZE.y - 56)
	art.clip_contents = true
	c.add_child(art)
	match i:
		0:
			_art_wreckers(art)
		1:
			_art_team(art)
		2:
			_art_cards(art)

	# Text column on the right.
	var tx := VBoxContainer.new()
	tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tx.position = Vector2(740, 70)
	tx.size = Vector2(CARD_SIZE.x - 740 - 50, CARD_SIZE.y - 140)
	tx.alignment = BoxContainer.ALIGNMENT_CENTER
	tx.add_theme_constant_override("separation", 14)
	c.add_child(tx)
	var kicker := UITheme.slant_ribbon(str(st.kicker), "", 22, accent.darkened(0.15), false, 2)
	kicker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tx.add_child(kicker)
	var head := UITheme.title(str(st.title), 66, Color.WHITE)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.custom_minimum_size = Vector2(tx.size.x, 0)
	head.add_theme_constant_override("line_spacing", -10)
	head.add_theme_color_override("font_shadow_color", Color(accent, 0.55))
	head.add_theme_constant_override("shadow_offset_x", 4)
	head.add_theme_constant_override("shadow_offset_y", 4)
	tx.add_child(head)
	var line := ColorRect.new()
	line.color = accent
	line.custom_minimum_size = Vector2(120, 6)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tx.add_child(line)
	var body := UITheme.label(str(st.text), 30, UITheme.OFFWHITE, UITheme.font_body_bold())
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(tx.size.x, 0)
	tx.add_child(body)
	var k := 0
	for n in [kicker, head, line, body]:
		n.modulate.a = 0.0
		var nt: Tween = (n as Node).create_tween()
		nt.tween_interval(0.25 + k * 0.12)
		nt.tween_property(n, "modulate:a", 1.0, 0.25)
		k += 1
	var step := UITheme.label("%d / %d" % [i + 1, STORIES.size()], 20, Color(1, 1, 1, 0.45), UITheme.font_body_bold())
	step.position = Vector2(CARD_SIZE.x - 90, CARD_SIZE.y - 54)
	c.add_child(step)
	return c


## A portrait in a rounded, rimmed frame (the "trading card" look of the roster).
func _portrait(id: String, side: float, rim: Color, bg_col: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s := UITheme.panel_style(bg_col, rim, 4, int(side * 0.16), 0)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 6)
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(side, side)
	p.size = Vector2(side, side)
	p.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var tr := TextureRect.new()
	tr.texture = DB.portrait(id)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	p.pivot_offset = Vector2(side, side) * 0.5
	return p


## Pops a control in at `delay` (scale overshoot, with a whoosh).
func _pop_in(n: Control, delay: float, rot: float, sound := "") -> void:
	n.modulate.a = 0.0
	n.scale = Vector2(0.3, 0.3)
	n.rotation = deg_to_rad(rot * 2.5)
	var tw := n.create_tween()
	tw.tween_interval(delay)
	if sound != "":
		tw.tween_callback(func() -> void: Audio.play(sound, -10.0, 0.08))
	tw.set_parallel()
	tw.tween_property(n, "modulate:a", 1.0, 0.12)
	tw.tween_property(n, "scale", Vector2.ONE, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "rotation", deg_to_rad(rot), 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Card 1: the Iron Slugger looms; three Wreckers burst in front of him.
func _art_wreckers(art: Control) -> void:
	var boss := _portrait("iron_slugger", 380, WRECKERS, Color("#2A0E0A"))
	boss.position = Vector2(170, 0)
	art.add_child(boss)
	_pop_in(boss, 0.15, 3.0, "boss_warning")
	var tag := UITheme.badge("WRECKERS", WRECKERS, 22)
	tag.position = Vector2(410, 26)
	art.add_child(tag)
	_pop_in(tag, 0.5, 6.0)
	var ids := ["sprinter", "runner", "armored"]
	var xs := [20.0, 245.0, 470.0]
	for k in ids.size():
		var p := _portrait(ids[k], 200, WRECKERS.lightened(0.15), Color("#3A140D"))
		p.position = Vector2(xs[k], 330 - (24.0 if k == 1 else 0.0))
		art.add_child(p)
		_pop_in(p, 0.55 + k * 0.16, [-7.0, 2.0, 8.0][k], "card_draw")


## Card 2: the player's six defenders, captain first and biggest.
func _art_team(art: Control) -> void:
	var team: Array = Profile.data.get("team", []).duplicate()
	var cap := str(Profile.data.get("captain", team[0] if not team.is_empty() else "ace"))
	team.erase(cap)
	team.push_front(cap)
	var slots := [[Vector2(225, 40), 250.0, 0.0], [Vector2(20, 60), 190.0, -6.0], [Vector2(490, 60), 190.0, 6.0],
		[Vector2(0, 300), 170.0, -4.0], [Vector2(255, 320), 180.0, 2.0], [Vector2(505, 300), 170.0, 5.0]]
	var order := [1, 2, 3, 5, 4, 0]   # the captain lands last, on top
	for k in order:
		if k >= team.size():
			continue
		var sl: Array = slots[k]
		var p := _portrait(str(team[k]), float(sl[1]), UITheme.GOLD if k == 0 else Color("#7FB2FF"), Color("#10284D"))
		p.position = sl[0]
		art.add_child(p)
		_pop_in(p, 0.2 + order.find(k) * 0.14, float(sl[2]), "card_draw")
	if not team.is_empty():
		var cb := UITheme.badge("CAPTAIN", UITheme.GOLD, 20)
		cb.position = Vector2(300, 18)
		art.add_child(cb)
		_pop_in(cb, 1.15, -3.0)


## Card 3: three ability cards fan out, the middle one glowing.
func _art_cards(art: Control) -> void:
	var ids := ["power_throw", "heat_wave", "curveball"]
	var sz := Vector2(196, 274)
	var spots := [[Vector2(70, 150), -12.0], [Vector2(252, 92), 0.0], [Vector2(434, 150), 12.0]]
	var glow := TitleGlow.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.position = Vector2(350, 230)
	glow.modulate = Color(UITheme.ENERGY, 0.0)
	art.add_child(glow)
	glow.create_tween().tween_property(glow, "modulate:a", 1.0, 0.6).set_delay(0.6)
	for k in [0, 2, 1]:
		var cv := CardView.new(ids[k], 1)
		cv.set_card(ids[k], 1)
		cv.show_level = false
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.custom_minimum_size = sz
		cv.size = sz
		cv.position = spots[k][0]
		art.add_child(cv)
		cv.pivot_offset = sz * 0.5
		_pop_in(cv, 0.2 + [0, 2, 1].find(k) * 0.18, float(spots[k][1]), "card_whoosh")


## A soft radial glow behind the cards.
class TitleGlow:
	extends Control

	func _draw() -> void:
		for k in 8:
			draw_circle(Vector2.ZERO, 260.0 - k * 30.0, Color(1, 1, 1, 0.05))
