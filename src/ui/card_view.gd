class_name CardView
extends Control
## Visual ability card: illustration, rarity frame, energy cost, name, category,
## level pips, cooldown sweep and playable/selected states.

signal clicked(card: CardView)
signal hovered(card: CardView, on: bool)

var card_id := ""
var level := 1
var cooldown_frac := 0.0
var cooldown_left := 0.0
var playable := true
var selected := false
var owned := true
var show_level := true
var hotkey := ""
var count_badge := ""
var _hover := false
var _art: Texture2D
var _lift := 0.0


func _init(id: String = "", lvl: int = 1) -> void:
	card_id = id
	level = lvl
	custom_minimum_size = Vector2(150, 210)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(self, true)
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		hovered.emit(self, false)
		queue_redraw())


func set_card(id: String, lvl: int = 1) -> void:
	card_id = id
	level = lvl
	_art = DB.card_texture(id) if id != "" else null
	tooltip_text = ""
	queue_redraw()


func _ready() -> void:
	if card_id != "" and _art == null:
		_art = DB.card_texture(card_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()


func _process(delta: float) -> void:
	var target := 1.0 if (_hover or selected) else 0.0
	if absf(_lift - target) > 0.01:
		_lift = move_toward(_lift, target, delta * 8.0)
		queue_redraw()


func _draw() -> void:
	if card_id == "":
		return
	var c := DB.card(card_id)
	var w := size.x
	var h := size.y
	var s := w / 150.0
	var lift := -10.0 * _lift * s if selected or _hover else 0.0
	var rect := Rect2(0, lift, w, h)
	var rar_col := DB.rarity_color(c.rarity)
	var cat_col := DB.category_color(c.category)
	var dim := 1.0 if (playable and owned) else 0.45

	# Shadow and glow
	draw_rect(Rect2(rect.position + Vector2(4, 6) * s, rect.size), Color(0, 0, 0, 0.45))
	if selected:
		_draw_round_rect(rect.grow(6 * s), Color(cat_col, 0.55), 12 * s)
	elif _hover and playable:
		_draw_round_rect(rect.grow(4 * s), Color(rar_col, 0.35), 12 * s)
	# Frame
	_draw_round_rect(rect, rar_col.darkened(0.35) * Color(dim, dim, dim, 1), 10 * s)
	var inner := rect.grow(-4 * s)
	_draw_round_rect(inner, Color(0.05, 0.07, 0.12) * Color(dim, dim, dim, 1), 8 * s)
	# Art window
	var art_rect := Rect2(inner.position + Vector2(4, 30) * s, Vector2(inner.size.x - 8 * s, inner.size.y * 0.5))
	if _art:
		draw_texture_rect(_art, art_rect, false, Color(dim, dim, dim))
	else:
		_draw_gradient_rect(art_rect, cat_col.darkened(0.5), cat_col.darkened(0.1), dim)
		var ic := DB.icon(c.category)
		if ic:
			var isz := art_rect.size.y * 0.6
			draw_texture_rect(ic, Rect2(art_rect.get_center() - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, 0.85 * dim))
	draw_rect(art_rect, Color(rar_col, 0.6), false, 1.5 * s)
	# Category stripe
	draw_rect(Rect2(inner.position.x, art_rect.end.y + 2 * s, inner.size.x, 4 * s), Color(cat_col, dim))
	# Name
	var font := UITheme.font_header()
	var name_size := int(22 * s)
	var name_text: String = c.name
	while font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > inner.size.x - 46 * s and name_size > 12:
		name_size -= 1
	draw_string(font, inner.position + Vector2(36 * s, 24 * s), name_text, HORIZONTAL_ALIGNMENT_LEFT, inner.size.x - 40 * s, name_size, Color(1, 1, 1, dim))
	# Cost gem
	var gem_c := inner.position + Vector2(16, 15) * s
	draw_circle(gem_c, 15 * s, Color(0.02, 0.05, 0.1))
	draw_circle(gem_c, 13 * s, UITheme.ENERGY.darkened(0.25) * Color(dim, dim, dim, 1))
	draw_arc(gem_c, 13 * s, 0, TAU, 24, Color(1, 1, 1, 0.5 * dim), 1.5 * s)
	var cost := str(int(c.cost))
	var df := UITheme.font_display()
	var cs := df.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * s))
	draw_string(df, gem_c + Vector2(-cs.x * 0.5, 8 * s), cost, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * s), Color(1, 1, 1, dim))
	# Description snippet
	var body := UITheme.font_body()
	var text_top := art_rect.end.y + 10 * s
	var desc := DB.card_text(card_id, level)
	draw_multiline_string(body, Vector2(inner.position.x + 6 * s, text_top + 13 * s), desc, HORIZONTAL_ALIGNMENT_LEFT,
		inner.size.x - 12 * s, int(13 * s), 4, Color(0.85, 0.88, 0.95, dim))
	# Category icon + rarity gem
	var cic := DB.icon(c.category)
	if cic:
		draw_texture_rect(cic, Rect2(inner.end - Vector2(24, 24) * s, Vector2(18, 18) * s), false, Color(cat_col, dim))
	var gem := inner.position + Vector2(inner.size.x * 0.5, inner.size.y - 9 * s)
	var pts := PackedVector2Array([gem + Vector2(0, -6) * s, gem + Vector2(6, 0) * s, gem + Vector2(0, 6) * s, gem + Vector2(-6, 0) * s])
	draw_colored_polygon(pts, Color(rar_col, dim))
	# Level pips
	if show_level and owned:
		for i in DB.card_max_level:
			var pc := inner.position + Vector2(8 + i * 9, inner.size.y - 9) * s
			draw_circle(pc, 3 * s, Color(UITheme.GOLD, dim) if i < level else Color(1, 1, 1, 0.15))
	# Linked defender badge
	var linked: String = c.get("linked", "")
	if linked != "":
		var pt := DB.portrait(linked)
		var bc := Vector2(art_rect.end.x - 16 * s, art_rect.position.y + 16 * s)
		draw_circle(bc, 15 * s, DB.defender_accent(linked))
		if pt:
			draw_texture_rect(pt, Rect2(bc - Vector2(13, 13) * s, Vector2(26, 26) * s), false, Color(1, 1, 1, dim))
		else:
			var ini: String = str(DB.defender(linked).name).substr(0, 1)
			draw_string(df, bc + Vector2(-6, 7) * s, ini, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), Color.WHITE)
	# Cooldown sweep
	if cooldown_frac > 0.0:
		var cc := art_rect.get_center()
		var r := art_rect.size.y * 0.42
		draw_rect(art_rect, Color(0, 0, 0, 0.55))
		var pts2 := PackedVector2Array([cc])
		var steps := 32
		for i in steps + 1:
			var a := -PI / 2 + TAU * cooldown_frac * float(i) / steps
			pts2.append(cc + Vector2(cos(a), sin(a)) * r)
		if pts2.size() >= 3:
			draw_colored_polygon(pts2, Color(0.2, 0.25, 0.35, 0.75))
		var t := "%.0f" % ceil(cooldown_left)
		var ts := df.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * s))
		draw_string(df, cc + Vector2(-ts.x * 0.5, 12 * s), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * s), Color.WHITE)
	if not owned:
		draw_circle(art_rect.get_center(), 26 * s, Color(0.02, 0.03, 0.06, 0.75))
		var lic := DB.icon("lock")
		if lic:
			draw_texture_rect(lic, Rect2(art_rect.get_center() - Vector2(15, 15) * s, Vector2(30, 30) * s), false, Color(0.85, 0.88, 0.95, 0.85))
	# Hotkey badge
	if hotkey != "":
		var hb := Rect2(rect.position + Vector2(w * 0.5 - 13 * s, -14 * s), Vector2(26, 22) * s)
		_draw_round_rect(hb, Color(0.03, 0.05, 0.1, 0.95), 5 * s)
		draw_rect(hb, Color(1, 1, 1, 0.3), false, 1.0)
		var ks := body.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s))
		draw_string(UITheme.font_body_bold(), hb.position + Vector2(hb.size.x * 0.5 - ks.x * 0.5, 17 * s), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), Color.WHITE)
	if count_badge != "":
		var cb := Rect2(Vector2(rect.end.x - 34 * s, rect.position.y - 8 * s), Vector2(38, 24) * s)
		_draw_round_rect(cb, UITheme.SCARLET, 6 * s)
		draw_string(UITheme.font_body_bold(), cb.position + Vector2(6, 18) * s, count_badge, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), Color.WHITE)


func _draw_round_rect(r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	draw_style_box(sb, r)


func _draw_gradient_rect(r: Rect2, a: Color, b: Color, dim: float) -> void:
	var steps := 12
	for i in steps:
		var t := float(i) / steps
		var c := a.lerp(b, t) * Color(dim, dim, dim, 1)
		draw_rect(Rect2(r.position.x, r.position.y + r.size.y * t, r.size.x, r.size.y / steps + 1), c)
