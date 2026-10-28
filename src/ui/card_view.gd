class_name CardView
extends Control
## Visual ability card: metallic rarity frame, category banner, energy gem, illustration,
## type line, description, level pips, cooldown sweep and playable/selected states.
## Rare and better cards get an animated foil finish; `face_down` draws the card back.

signal clicked(card: CardView)
signal hovered(card: CardView, on: bool)

const FOIL_SHADER := preload("res://assets/shaders/card_foil.gdshader")
const PANEL_TOP := Color("#1B2740")
const PANEL_BOTTOM := Color("#0A0F1B")

var card_id := ""
var level := 1
var cooldown_frac := 0.0
var cooldown_left := 0.0
var playable := true
var selected := false
var owned := true:
	set(v):
		owned = v
		if is_inside_tree():
			_update_foil()
		queue_redraw()
var show_level := true
## Mastery stars (0-3) drawn on the bottom-right frame edge; 3 adds the gold "mastered" trim.
## -1 (the default, e.g. the battle hand) draws nothing. Cosmetic only.
var mastery := -1
var hotkey := ""
var count_badge := ""
var face_down := false:
	set(v):
		face_down = v
		if is_inside_tree():
			_update_foil()
		queue_redraw()
var foil := true
var lift_px := 12.0          # how far the card rises on hover (selected cards rise further)
var _hover := false
var _art: Texture2D
var _lift := 0.0             # eased hover amount 0..1
var _sel := 0.0              # eased selection amount 0..1
var _shake := 0.0            # refusal shake 0..1
var _t := 0.0
var _foil_mat: ShaderMaterial


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
	resized.connect(_update_foil)


func set_card(id: String, lvl: int = 1) -> void:
	card_id = id
	level = lvl
	_art = DB.card_texture(id) if id != "" else null
	tooltip_text = ""
	_update_foil()
	queue_redraw()


func _ready() -> void:
	if card_id != "" and _art == null:
		_art = DB.card_texture(card_id)
	_update_foil()


## Foil only on owned, face-up Rare+ cards; one material per card so each sweeps on its own phase.
func _update_foil() -> void:
	var r := 0 if card_id == "" else DB.rarity_index(str(DB.card(card_id).get("rarity", "common")))
	if not foil or face_down or not owned or r < 2:
		material = null
		return
	if _foil_mat == null:
		_foil_mat = ShaderMaterial.new()
		_foil_mat.shader = FOIL_SHADER
	var rar := str(DB.card(card_id).rarity)
	_foil_mat.set_shader_parameter("tint", DB.rarity_color(rar))
	_foil_mat.set_shader_parameter("sheen", [0.0, 0.0, 0.32, 0.42, 0.55][r])
	_foil_mat.set_shader_parameter("holo", [0.0, 0.0, 0.0, 0.55, 0.85][r])
	_foil_mat.set_shader_parameter("phase", float(absi(hash(card_id)) % 97) / 27.0)
	var sz := size if size.x > 1.0 else custom_minimum_size
	_foil_mat.set_shader_parameter("card_size", sz)
	# _draw() draws the card around its bottom centre (see draw_set_transform there).
	_foil_mat.set_shader_parameter("rect_origin", Vector2(-sz.x * 0.5, -sz.y))
	material = _foil_mat


func refresh() -> void:
	_update_foil()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()


## The clickable area is exactly what is drawn (the raised, enlarged card) plus the card's
## resting slot, so the card never slips out from under the cursor while it rises.
func _has_point(point: Vector2) -> bool:
	return _hit_rect().has_point(point)


func _hit_rect() -> Rect2:
	var s := size.x / 150.0
	var rise := s * (lift_px * _lift + lift_px * 1.2 * _sel)
	var grow := 1.0 + 0.035 * _lift + 0.06 * _sel
	var vis := Rect2(size.x * 0.5 * (1.0 - grow), size.y - rise - size.y * grow, size.x * grow, size.y * grow)
	return Rect2(Vector2.ZERO, size).merge(vis).grow_individual(3.0, 6.0, 3.0, 6.0)


## Shake and flash red: the card was clicked but can't be played right now.
func deny() -> void:
	_shake = 1.0
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# Never stay "hovered" once the mouse is elsewhere (e.g. a card dealt under a resting mouse).
	if _hover and not _hit_rect().has_point(get_local_mouse_position()):
		_hover = false
		hovered.emit(self, false)
	var k := 1.0 - exp(-delta * 16.0)
	var hover_t := 1.0 if (_hover and playable) or (_hover and not selected) else 0.0
	var sel_t := 1.0 if selected else 0.0
	var moving := absf(_lift - hover_t) > 0.002 or absf(_sel - sel_t) > 0.002 or _shake > 0.0 or selected
	if moving:
		_lift = lerpf(_lift, hover_t, k)
		_sel = lerpf(_sel, sel_t, k)
		_shake = maxf(0.0, _shake - delta * 2.6)
		if _foil_mat:
			_foil_mat.set_shader_parameter("hover", maxf(_lift, _sel))
		queue_redraw()


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if face_down:
		_draw_back()
		return
	if card_id == "":
		return
	var c := DB.card(card_id)
	var w := size.x
	var h := size.y
	var s := w / 150.0
	# Hover/selection: rise and grow from the bottom centre; refusal: shake sideways.
	var rise := -s * (lift_px * _lift + lift_px * 1.2 * _sel)
	var grow := 1.0 + 0.035 * _lift + 0.06 * _sel
	var sx := sin(_t * 70.0) * 7.0 * s * _shake * _shake
	draw_set_transform(Vector2(w * 0.5 + sx, h + rise), 0.0, Vector2(grow, grow))
	var rect := Rect2(-w * 0.5, -h, w, h)
	var rarity := str(c.rarity)
	var r_idx := DB.rarity_index(rarity)
	var rar_col := DB.rarity_color(rarity)
	var cat_col := DB.category_color(c.category)
	var dim := 1.0 if (playable and owned) else 0.45
	var dc := Color(dim, dim, dim, 1)

	# Shadow, rarity glow and selection glow
	_rr_fill(Rect2(rect.position + Vector2(3, 6 + 10 * (_lift + _sel)) * s, rect.size), 12 * s, Color(0, 0, 0, 0.45 - 0.15 * (_lift + _sel) * 0.5))
	if r_idx >= 1 and owned:
		var ga: float = [0.0, 0.22, 0.3, 0.38, 0.5][r_idx] * dim
		_rr_fill(rect.grow(4.5 * s), 15 * s, Color(rar_col, ga * 0.5))
		_rr_fill(rect.grow(2.2 * s), 13 * s, Color(rar_col, ga))
	if _sel > 0.01:
		var pulse := 0.75 + 0.25 * sin(_t * 6.0)
		_rr_fill(rect.grow(9 * s), 18 * s, Color(cat_col.lightened(0.2), 0.28 * _sel * pulse))
		_rr_fill(rect.grow(5 * s), 15 * s, Color(cat_col.lightened(0.35), 0.6 * _sel))
	elif _lift > 0.01 and playable:
		_rr_fill(rect.grow(4 * s), 14 * s, Color(rar_col.lightened(0.2), 0.45 * _lift))

	# Metallic rarity frame
	var hi := 0.55 if r_idx >= 4 else 0.42
	_rr_gradient(rect, 12 * s, rar_col.lightened(hi) * dc, rar_col.darkened(0.55) * dc)
	_rr_outline(rect.grow(-1.4 * s), 11 * s, Color(1, 1, 1, 0.35 * dim), 1.2 * s)
	var inner := rect.grow(-5 * s)
	_rr_gradient(inner, 8 * s, PANEL_TOP * dc, PANEL_BOTTOM * dc)
	if r_idx >= 3:
		_draw_corner_ornaments(rect, s, rar_col.lightened(0.5), dim, r_idx >= 4)

	# Category banner with the card name
	var header := Rect2(inner.position, Vector2(inner.size.x, 27 * s))
	_rr_gradient(header, 8 * s, cat_col.darkened(0.1) * dc, cat_col.darkened(0.55) * dc)
	draw_rect(Rect2(header.position.x, header.position.y + 13 * s, header.size.x, 14 * s), cat_col.darkened(0.55) * dc)
	draw_rect(Rect2(header.position.x, header.end.y - 1.5 * s, header.size.x, 1.5 * s), Color(0, 0, 0, 0.45))
	var font := UITheme.font_header()
	var name_size := int(21 * s)
	var name_text: String = c.name
	while font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x > inner.size.x - 42 * s and name_size > 11:
		name_size -= 1
	var name_pos := inner.position + Vector2(34 * s, 20 * s)
	draw_string(font, name_pos + Vector2(1.2, 1.6) * s, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(0, 0, 0, 0.6 * dim))
	draw_string(font, name_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(1, 1, 1, dim))

	# Illustration window
	var art_rect := Rect2(inner.position + Vector2(5, 31) * s, Vector2(inner.size.x - 10 * s, inner.size.y * 0.41))
	if _art:
		draw_texture_rect_region(_art, art_rect, _cover_region(_art, art_rect.size), Color(dim, dim, dim))
	else:
		_draw_v_gradient(art_rect, cat_col.darkened(0.5) * dc, cat_col.darkened(0.1) * dc)
		var ic := DB.icon(c.category)
		if ic:
			var isz := art_rect.size.y * 0.6
			draw_texture_rect(ic, Rect2(art_rect.get_center() - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, 0.85 * dim))
	_draw_v_gradient(Rect2(art_rect.position.x, art_rect.end.y - art_rect.size.y * 0.35, art_rect.size.x, art_rect.size.y * 0.35),
		Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.5))
	draw_rect(art_rect, Color(rar_col.lightened(0.2), 0.95 * dim), false, 1.6 * s)
	draw_rect(art_rect.grow(-1.6 * s), Color(1, 1, 1, 0.12 * dim), false, 1.0)

	# Type line: category on the left, rarity on the right
	var type_rect := Rect2(art_rect.position.x, art_rect.end.y + 3 * s, art_rect.size.x, 15 * s)
	_rr_fill(type_rect, 4 * s, Color(cat_col.darkened(0.62), 0.95) * dc)
	var cic := DB.icon(c.category)
	if cic:
		draw_texture_rect(cic, Rect2(type_rect.position + Vector2(3, 2) * s, Vector2(11, 11) * s), false, Color(cat_col.lightened(0.2), dim))
	var small := UITheme.font_body_bold()
	var tsize := int(11 * s)
	draw_string(small, type_rect.position + Vector2(17 * s, 11.2 * s), str(c.category).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, Color(0.92, 0.94, 1.0, 0.9 * dim))
	var rw := small.get_string_size(rarity.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, tsize).x
	# Rarity tag: a filled pill in the rarity colour so it reads at a glance.
	var tag := Rect2(Vector2(type_rect.end.x - rw - 9 * s, type_rect.position.y + 1.5 * s), Vector2(rw + 7 * s, type_rect.size.y - 3 * s))
	_rr_fill(tag, 3 * s, Color(rar_col.darkened(0.25), 0.95 * dim))
	draw_string(small, Vector2(tag.position.x + 3.5 * s, type_rect.position.y + 11.4 * s), rarity.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, Color(1, 1, 1, dim))

	# Description
	var body := UITheme.font_body()
	var text_top := type_rect.end.y + 4 * s
	draw_multiline_string(body, Vector2(inner.position.x + 6 * s, text_top + 13 * s), DB.card_text(card_id, level), HORIZONTAL_ALIGNMENT_LEFT,
		inner.size.x - 12 * s, int(13.5 * s), 3, Color(0.9, 0.93, 0.98, dim))

	# Energy cost gem
	var gem_c := inner.position + Vector2(15, 14) * s
	_circle_gradient(gem_c, 15.5 * s, Color(0.02, 0.04, 0.09), Color(0.02, 0.04, 0.09))
	_circle_gradient(gem_c, 13.5 * s, UITheme.ENERGY.lightened(0.35) * dc, UITheme.ENERGY.darkened(0.55) * dc)
	draw_arc(gem_c, 13.5 * s, 0, TAU, 28, Color(1, 1, 1, 0.55 * dim), 1.3 * s, true)
	_ellipse(gem_c + Vector2(0, -6) * s, Vector2(8, 3.6) * s, Color(1, 1, 1, 0.28 * dim))
	var cost := str(int(c.cost))
	var df := UITheme.font_display()
	var cs := df.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * s))
	var cpos := gem_c + Vector2(-cs.x * 0.5, 8.5 * s)
	draw_string_outline(df, cpos, cost, HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * s), int(4 * s), Color(0.02, 0.05, 0.12, 0.9))
	draw_string(df, cpos, cost, HORIZONTAL_ALIGNMENT_LEFT, -1, int(23 * s), Color(1, 1, 1, dim))

	# Rarity gem, set into the bottom of the frame
	var gem := Vector2(rect.get_center().x, rect.end.y - 2.5 * s)
	var gr := (6.5 + 1.2 * r_idx) * s
	var diamond := PackedVector2Array([gem + Vector2(0, -gr), gem + Vector2(gr, 0), gem + Vector2(0, gr), gem + Vector2(-gr, 0)])
	draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -gr - 2 * s), gem + Vector2(gr + 2 * s, 0), gem + Vector2(0, gr + 2 * s), gem + Vector2(-gr - 2 * s, 0)]), Color(0, 0, 0, 0.6))
	draw_polygon(diamond, PackedColorArray([rar_col.lightened(0.6) * dc, rar_col * dc, rar_col.darkened(0.4) * dc, rar_col * dc]))
	# Level pips on the bottom frame edge
	if show_level and owned:
		for i in DB.card_max_level:
			var pc := Vector2(rect.position.x + (14 + i * 9) * s, rect.end.y - 2.5 * s)
			draw_circle(pc, 3.6 * s, Color(0.02, 0.03, 0.06, 0.85))
			draw_circle(pc, 2.6 * s, Color(UITheme.GOLD, dim) if i < level else Color(1, 1, 1, 0.18))
	if mastery >= 1:
		_draw_mastery(rect, s, dim)
	# Linked defender badge
	var linked: String = c.get("linked", "")
	if linked != "":
		var pt := DB.portrait(linked)
		var bc := Vector2(art_rect.end.x - 15 * s, art_rect.position.y + 15 * s)
		draw_circle(bc, 15 * s, Color(0.02, 0.04, 0.08, 0.9))
		draw_circle(bc, 13.5 * s, DB.defender_accent(linked) * dc)
		if pt:
			draw_texture_rect(pt, Rect2(bc - Vector2(12.5, 12.5) * s, Vector2(25, 25) * s), false, Color(1, 1, 1, dim))
		else:
			var ini: String = str(DB.defender(linked).name).substr(0, 1)
			draw_string(df, bc + Vector2(-6, 7) * s, ini, HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * s), Color.WHITE)
	# Cooldown sweep
	if cooldown_frac > 0.0:
		var cc := art_rect.get_center()
		var cr := minf(art_rect.size.x, art_rect.size.y) * 0.42
		draw_rect(art_rect, Color(0, 0, 0, 0.55))
		var pts2 := PackedVector2Array([cc])
		var steps := 32
		for i in steps + 1:
			var a := -PI / 2 + TAU * cooldown_frac * float(i) / steps
			pts2.append(cc + Vector2(cos(a), sin(a)) * cr)
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
		_rr_fill(hb, 5 * s, Color(0.03, 0.05, 0.1, 0.95))
		_rr_outline(hb, 5 * s, Color(1, 1, 1, 0.35), 1.0)
		var ks := small.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s))
		draw_string(small, hb.position + Vector2(hb.size.x * 0.5 - ks.x * 0.5, 17 * s), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), Color.WHITE)
	if count_badge != "":
		var cb := Rect2(Vector2(rect.end.x - 34 * s, rect.position.y - 8 * s), Vector2(38, 24) * s)
		_rr_fill(cb, 6 * s, UITheme.SCARLET)
		draw_string(small, cb.position + Vector2(6, 18) * s, count_badge, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * s), Color.WHITE)
	if _shake > 0.0:
		# Refused: a red wash, a hot red rim and the cost gem ringed in red (the usual reason).
		_rr_fill(rect, 12 * s, Color(1.0, 0.15, 0.1, 0.4 * _shake))
		_rr_outline(rect.grow(1.5 * s), 13 * s, Color(1.0, 0.3, 0.22, 0.95 * _shake), 3.0 * s)
		draw_arc(gem_c, 16.5 * s, 0, TAU, 28, Color(1.0, 0.35, 0.25, _shake), 2.6 * s, true)


## Card back: navy and gold with a diamond lattice and the game logo.
func _draw_back() -> void:
	var w := size.x
	var h := size.y
	var s := w / 150.0
	var rect := Rect2(0, 0, w, h)
	_rr_fill(Rect2(rect.position + Vector2(3, 6) * s, rect.size), 12 * s, Color(0, 0, 0, 0.45))
	_rr_gradient(rect, 12 * s, Color("#F7D37A"), Color("#8A5A12"))
	_rr_outline(rect.grow(-1.4 * s), 11 * s, Color(1, 1, 1, 0.4), 1.2 * s)
	var inner := rect.grow(-6 * s)
	_rr_gradient(inner, 8 * s, Color("#1C2F55"), Color("#081022"))
	var step := 16.0 * s
	var y := inner.position.y + step * 0.75
	var row := 0
	while y < inner.end.y - step * 0.5:
		var x := inner.position.x + step * (0.75 if row % 2 == 0 else 1.25)
		while x < inner.end.x - step * 0.5:
			var d := step * 0.32
			draw_colored_polygon(PackedVector2Array([Vector2(x, y - d), Vector2(x + d, y), Vector2(x, y + d), Vector2(x - d, y)]), Color(0.96, 0.75, 0.3, 0.13))
			x += step
		y += step * 0.5
		row += 1
	_rr_outline(inner.grow(-5 * s), 6 * s, Color(0.96, 0.75, 0.3, 0.55), 1.2 * s)
	var cc := inner.get_center()
	_circle_gradient(cc, 52 * s, Color(0.2, 0.35, 0.7, 0.9), Color(0.03, 0.06, 0.14, 0.95))
	draw_arc(cc, 52 * s, 0, TAU, 48, Color(0.96, 0.75, 0.3, 0.9), 2.0 * s, true)
	draw_arc(cc, 46 * s, 0, TAU, 48, Color(0.96, 0.75, 0.3, 0.35), 1.0 * s, true)
	var logo: Texture2D = DB._texture("res://assets/textures/logo/logo_small.png")
	if logo:
		var lw := 92.0 * s
		var lh := lw * float(logo.get_height()) / float(logo.get_width())
		draw_texture_rect(logo, Rect2(cc - Vector2(lw, lh) * 0.5, Vector2(lw, lh)), false)


## Mastery: up to three stars on the bottom-right frame edge. A mastered card (three stars) gets
## a gold outer rim, a fine inner gold line and its stars set on a gold plate.
func _draw_mastery(rect: Rect2, s: float, dim: float) -> void:
	var gold := Color(UITheme.GOLD, dim)
	var mastered := mastery >= CardMastery.MAX_STARS
	if mastered:
		_rr_outline(rect.grow(2.2 * s), 14 * s, Color(1.0, 0.86, 0.4, 0.95 * dim), 2.4 * s)
		_rr_outline(rect.grow(-3.4 * s), 9.5 * s, Color(1.0, 0.85, 0.35, 0.75 * dim), 1.1 * s)
		var plate := Rect2(Vector2(rect.end.x - 44 * s, rect.end.y - 9 * s), Vector2(38, 13) * s)
		_rr_fill(plate, 6 * s, Color(0.35, 0.22, 0.02, 0.95 * dim))
		_rr_outline(plate, 6 * s, Color(1.0, 0.86, 0.4, dim), 1.2 * s)
	for i in CardMastery.MAX_STARS:
		var cpos := Vector2(rect.end.x - (13 + i * 11) * s, rect.end.y - 2.5 * s)
		var on := i < mastery
		_star(cpos, 5.6 * s, Color(0.02, 0.03, 0.06, 0.9))
		_star(cpos, 4.3 * s, (Color(1.0, 0.95, 0.7, dim) if mastered else gold) if on else Color(1, 1, 1, 0.2 * dim))


func _star(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + PI * k / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, col)


func _draw_corner_ornaments(rect: Rect2, s: float, col: Color, dim: float, legendary: bool) -> void:
	var l := 16.0 * s
	var o := 3.0 * s
	var c := Color(col, 0.95 * dim)
	var corners := [[rect.position + Vector2(o, o), Vector2(1, 0), Vector2(0, 1)],
		[Vector2(rect.end.x - o, rect.position.y + o), Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(rect.position.x + o, rect.end.y - o), Vector2(1, 0), Vector2(0, -1)],
		[rect.end - Vector2(o, o), Vector2(-1, 0), Vector2(0, -1)]]
	for k in corners:
		var p: Vector2 = k[0]
		draw_polyline(PackedVector2Array([p + k[1] * l, p, p + k[2] * l]), c, 2.0 * s, true)
		if legendary:
			var q: Vector2 = p + (k[1] + k[2]) * 5.0 * s
			var d := 2.6 * s
			draw_colored_polygon(PackedVector2Array([q + Vector2(0, -d), q + Vector2(d, 0), q + Vector2(0, d), q + Vector2(-d, 0)]), Color(1, 1, 0.9, dim))


## Source rect that fills `dst` without stretching (centred crop, like "cover").
func _cover_region(tex: Texture2D, dst: Vector2) -> Rect2:
	var tw := float(tex.get_width())
	var th := float(tex.get_height())
	var a := dst.x / maxf(dst.y, 1.0)
	if a > tw / th:
		var ch := tw / a
		return Rect2(0, (th - ch) * 0.5, tw, ch)
	var cw := th * a
	return Rect2((tw - cw) * 0.5, 0, cw, th)


func _rr_points(r: Rect2, rad: float, seg := 5) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var centers := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	var pts := PackedVector2Array()
	for i in 4:
		for k in seg + 1:
			var a := -PI / 2 + PI / 2 * i + PI / 2 * float(k) / seg
			pts.append(centers[i] + Vector2(cos(a), sin(a)) * rad)
	return pts


func _rr_fill(r: Rect2, rad: float, col: Color) -> void:
	draw_colored_polygon(_rr_points(r, rad), col)


func _rr_gradient(r: Rect2, rad: float, top: Color, bottom: Color) -> void:
	var pts := _rr_points(r, rad)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	draw_polygon(pts, cols)


func _rr_outline(r: Rect2, rad: float, col: Color, width: float) -> void:
	var pts := _rr_points(r, rad)
	pts.append(pts[0])
	draw_polyline(pts, col, width, true)


func _draw_v_gradient(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, bottom, bottom]))


func _circle_gradient(c: Vector2, rad: float, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 32:
		var a := TAU * i / 32.0
		var p := c + Vector2(cos(a), sin(a)) * rad
		pts.append(p)
		cols.append(top.lerp(bottom, (p.y - (c.y - rad)) / (2.0 * rad)))
	draw_polygon(pts, cols)


func _ellipse(c: Vector2, radii: Vector2, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(c + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(pts, col)
