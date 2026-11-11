class_name FirstWinResults
extends Control
## Update 13 (Rookie Camp): the Results screen of a new player's first win. Instead of three columns
## of numbers it plays three big reward moments one after another (coins count up, the level-up,
## the packs fly in), then a single pulsing OPEN YOUR PACK! button that starts the guided first
## pack opening. "See full results" switches to the classic layout (`on_full`). Esc leaves for the hub.

const T_TITLE := 0.5
const T_COINS := 1.3
const T_LEVEL := 2.1
const T_PACKS := 2.9
const T_BUTTON := 3.7

var result: Dictionary = {}
var on_full: Callable
var open_btn: Button
var _rays: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "FirstWin"
	var vs := get_viewport().get_visible_rect().size

	_rays = Rays.new()
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays.position = Vector2(vs.x * 0.5, 190)
	_rays.modulate.a = 0.0
	add_child(_rays)
	UITheme.bound_tween(_rays).tween_property(_rays, "modulate:a", 1.0, 0.6).set_delay(T_TITLE)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_top = 60
	col.offset_bottom = -40
	col.add_theme_constant_override("separation", 18)
	add_child(col)

	var title := UITheme.title("VICTORY!", 150, UITheme.GOLD)
	title.name = "ResultTitle"
	title.add_theme_constant_override("outline_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	_slam(title, T_TITLE, 2.2)
	var rib_row := HBoxContainer.new()
	rib_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rib_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(rib_row)
	var rib := UITheme.slant_ribbon("YOUR FIRST WIN, MANAGER!", "trophy", 30, UITheme.SCARLET, false, 2)
	rib_row.add_child(rib)
	_fade(rib_row, T_TITLE + 0.4)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(spacer)

	var row := HBoxContainer.new()
	row.name = "Moments"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 36)
	col.add_child(row)
	row.add_child(_coins_moment())
	row.add_child(_level_moment())
	row.add_child(_packs_moment())

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fill)

	var packs: Array = result.get("packs", [])
	var bwrap := CenterContainer.new()
	bwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(bwrap)
	var has_pack := not packs.is_empty() or Profile.pack_count() > 0
	open_btn = UITheme.menu_button("OPEN YOUR PACK!" if has_pack else "CONTINUE", UITheme.GOLD, 48)
	open_btn.name = "OpenFirstPack"
	open_btn.icon = DB.icon("gift" if has_pack else "play")
	open_btn.add_theme_constant_override("icon_max_width", 52)
	open_btn.add_theme_constant_override("h_separation", 16)
	open_btn.add_theme_stylebox_override("normal", UITheme.button_style(UITheme.GOLD.darkened(0.35), UITheme.GOLD.lightened(0.3), -0.18, 3))
	open_btn.add_theme_color_override("font_color", Color.WHITE)
	open_btn.custom_minimum_size = Vector2(560, 104)
	open_btn.pressed.connect(func() -> void:
		if has_pack:
			Session.guide = "pack"
			Router.goto("packs")
		else:
			Session.finish_ftue_rewards())
	bwrap.add_child(open_btn)
	_slam(open_btn, T_BUTTON, 1.6)
	var pulse := UITheme.bound_tween(open_btn)
	pulse.tween_interval(T_BUTTON + 0.5)
	pulse.tween_callback(func() -> void:
		open_btn.pivot_offset = open_btn.size * 0.5
		var lp := open_btn.create_tween().set_loops()
		lp.tween_property(open_btn, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
		lp.tween_property(open_btn, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE))
	var ring := Halo.new()
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.target = open_btn
	ring.modulate.a = 0.0
	add_child(ring)
	UITheme.bound_tween(ring).tween_property(ring, "modulate:a", 1.0, 0.4).set_delay(T_BUTTON + 0.3)

	var links := CenterContainer.new()
	links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(links)
	var full := UITheme.button("See full results  ▸", "ghost", 22)
	full.name = "FullResults"
	full.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	full.tooltip_text = "The game's numbers, highlights and every reward in detail."
	full.pressed.connect(func() -> void:
		if on_full.is_valid():
			on_full.call())
	links.add_child(full)
	_fade(links, T_BUTTON + 0.6)


func _process(delta: float) -> void:
	if _rays:
		_rays.rotation += delta * 0.1


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Audio.ui("ui_back")
		Session.finish_ftue_rewards()
	elif event.is_action_pressed("confirm") or event.is_action_pressed("start_wave"):
		get_viewport().set_input_as_handled()
		if open_btn and not open_btn.disabled:
			open_btn.pressed.emit()


# ---------------------------------------------------------------- moments

func _moment(name_id: String, accent: Color, delay: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.name = name_id
	var st := UITheme.panel_style(Color(0.035, 0.06, 0.12, 0.95), Color(accent, 0.75), 3, 22, 18)
	st.shadow_color = Color(accent, 0.25)
	st.shadow_size = 22
	p.add_theme_stylebox_override("panel", st)
	p.custom_minimum_size = Vector2(400, 330)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	_slam(p, delay, 1.5)
	p.set_meta("vb", vb)
	return vb


func _coins_moment() -> Control:
	var vb := _moment("CoinsMoment", UITheme.GOLD, T_COINS)
	var coins := int(result.get("coins_total", result.get("coins", 0)))
	var ic := UITheme.icon_rect("coin", 110, UITheme.GOLD)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ic)
	var l := UITheme.title("+0", 92, UITheme.GOLD)
	l.name = "Value"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	vb.add_child(_caption("COINS"))
	var tw := UITheme.bound_tween(l)
	tw.tween_interval(T_COINS + 0.25)
	var last := [-1]
	tw.tween_method(func(v: float) -> void:
		l.text = "+%s" % UITheme.format_int(int(round(v)))
		var step := int(v * 10.0 / maxf(coins, 1))
		if step != last[0]:
			last[0] = step
			Audio.play("coin", -12.0, 0.08, 40), 0.0, float(coins), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return vb.get_parent()


func _level_moment() -> Control:
	var vb := _moment("LevelMoment", UITheme.GREEN, T_LEVEL)
	var levels := int(result.get("levels", 0))
	var level := int(Profile.data.level)
	var ic := UITheme.icon_rect("upgrade", 100, UITheme.GREEN)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(ic)
	var big := UITheme.title("LEVEL %d" % level if levels > 0 else "+%s XP" % UITheme.format_int(int(result.get("xp", 0))), 80, UITheme.GREEN)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(big)
	vb.add_child(_caption("LEVEL UP!" if levels > 0 else "ACCOUNT XP"))
	var bar := UITheme.bar(UITheme.GREEN, 12, 1.0, 0.0)
	bar.custom_minimum_size = Vector2(300, 12)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(bar)
	var tw := UITheme.bound_tween(bar)
	tw.tween_interval(T_LEVEL + 0.3)
	if levels > 0:
		tw.tween_property(bar, "value", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Audio.play("level_up", -3.0)
			bar.value = 0.0)
	tw.tween_property(bar, "value", clampf(float(Profile.data.xp) / maxi(1, Profile.xp_to_next(level)), 0.0, 1.0), 0.5)
	return vb.get_parent()


func _packs_moment() -> Control:
	var vb := _moment("PacksMoment", UITheme.SCARLET, T_PACKS)
	var packs: Array = result.get("packs", [])
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(300, 200)
	stack.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(stack)
	var shown := mini(packs.size(), 3)
	for i in shown:
		var pk: Dictionary = packs[shown - 1 - i]
		var art := PackArt.new(str(pk.type), str(pk.get("card", "")))
		art.custom_minimum_size = Vector2(124, 190)
		art.size = Vector2(124, 190)
		art.pivot_offset = Vector2(62, 95)
		var off := float(i) - float(shown - 1) * 0.5
		art.position = Vector2(150 - 62 + off * 92.0, 5 + absf(off) * 8.0)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(art)
		art.modulate.a = 0.0
		art.scale = Vector2.ONE * 1.8
		var rot := deg_to_rad(off * 11.0)
		art.rotation = rot - 0.4
		var t := UITheme.bound_tween(art)
		t.tween_interval(T_PACKS + 0.2 + i * 0.16)
		t.tween_callback(func() -> void: Audio.play("card_draw", -2.0))
		t.set_parallel(true)
		t.tween_property(art, "modulate:a", 1.0, 0.15)
		t.tween_property(art, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(art, "rotation", rot, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var n := packs.size()
	var big := UITheme.title("%d NEW PACK%s!" % [n, "" if n == 1 else "S"] if n > 0 else "NO PACKS", 56, UITheme.OFFWHITE)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(big)
	vb.add_child(_caption("FULL OF NEW CARDS"))
	return vb.get_parent()


func _caption(t: String) -> Label:
	var l := UITheme.label(t, 22, UITheme.MUTED, UITheme.font_body_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


# ---------------------------------------------------------------- animation helpers

func _slam(c: Control, delay: float, from_scale: float) -> void:
	c.modulate.a = 0.0
	c.resized.connect(func() -> void: c.pivot_offset = c.size * 0.5)
	var tw := UITheme.bound_tween(c)
	tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		c.pivot_offset = c.size * 0.5
		c.scale = Vector2.ONE * from_scale)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.12)
	tw.tween_property(c, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _fade(c: Control, delay: float) -> void:
	c.modulate.a = 0.0
	UITheme.bound_tween(c).tween_property(c, "modulate:a", 1.0, 0.3).set_delay(delay)


## Rotating gold light rays behind the title.
class Rays:
	extends Control

	func _draw() -> void:
		var n := 24
		for i in n:
			var a0 := TAU * i / n
			var a1 := a0 + TAU / n * 0.45
			var col := Color(1.0, 0.82, 0.4, 0.07) if i % 2 == 0 else Color(1.0, 0.95, 0.8, 0.03)
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * 1400.0, Vector2(cos(a1), sin(a1)) * 1400.0]), col)
		for k in 7:
			draw_circle(Vector2.ZERO, 320.0 - k * 42.0, Color(1.0, 0.85, 0.5, 0.045))


## A pulsing spotlight ring around a target control (the OPEN YOUR PACK! button).
class Halo:
	extends Control
	var target: Control
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		if target == null or not is_instance_valid(target) or not target.is_visible_in_tree():
			return
		var r := target.get_global_rect()
		r.position -= get_global_rect().position
		var p := 0.5 + 0.5 * sin(t * 4.0)
		var g := r.grow(14.0 + p * 10.0)
		draw_rect(g, Color(UITheme.GOLD, 0.5 * (1.0 - p) + 0.2), false, 4.0)
		draw_rect(g.grow(10.0), Color(UITheme.GOLD, 0.18 * p), false, 8.0)
