class_name CardView
extends Control
## Visual ability card: metallic rarity frame, category banner, energy gem, illustration,
## type line, description, level pips, cooldown sweep and playable/selected states.
## Rare and better cards get an animated foil finish; `face_down` draws the card back.
## Update 11: Prestige cards (levels 6-10) get an iridescent holo frame (card_prestige.gdshader), a gold
## Prestige crest with the star count over the rarity gem and gold stars instead of level pips. The crest
## and stars are drawn by a child overlay so the frame shader doesn't tint them.

signal clicked(card: CardView)
signal hovered(card: CardView, on: bool)

const FOIL_SHADER := preload("res://assets/shaders/card_foil.gdshader")
const PRESTIGE_SHADER := preload("res://assets/shaders/card_prestige.gdshader")
const PRESTIGE_GOLD := Color("#FFD66B")
const PRESTIGE_GOLD_DARK := Color("#8A5A0E")
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
## Prestige stars to show (0-5). -1 (the default) = automatic: the owned card's real Prestige, but never
## more than this view's level allows (so a level-5 card raised in a game by a boon doesn't look prestiged,
## and a preview at a lower level shows no crest).
var prestige := -1:
	set(v):
		prestige = v
		if is_inside_tree():
			_update_foil()
		queue_redraw()
## Combo hint in the battle hand (set by the HUD; drawing only): 1 = this card combos with another
## card in hand (a soft green halo and a link badge); `combo_partner` = it combos with the
## selected card (a brighter, pulsing halo).
var combo_glow := 0.0
var combo_partner := false
const COMBO_COLOR := Color("#4DF2A0")
var lift_px := 12.0          # how far the card rises on hover (selected cards rise further)
var _hover := false
var _art: Texture2D
var _lift := 0.0             # eased hover amount 0..1
var _sel := 0.0              # eased selection amount 0..1
var _shake := 0.0            # refusal shake 0..1
var _t := 0.0
## Prestige ceremony: keep the crest off while it drops in from above.
var hide_crest := false:
	set(v):
		hide_crest = v
		if _overlay:
			_overlay.queue_redraw()
var _foil_mat: ShaderMaterial
var _prestige_mat: ShaderMaterial
var _overlay: Control         # crest and stars of a Prestige card (drawn without the frame shader)


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
	draw.connect(func() -> void:
		if _overlay:
			_overlay.queue_redraw())


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


## Prestige stars this view shows (0 = not a Prestige card).
func prestige_stars() -> int:
	if card_id == "" or face_down or not owned:
		return 0
	if prestige >= 0:
		return clampi(prestige, 0, DB.card_max_level - DB.PRESTIGE_LEVEL)
	if not Profile.is_card_owned(card_id):
		return 0
	return mini(Profile.card_prestige(card_id), DB.prestige_stars(level))


## Foil only on owned, face-up Rare+ cards; one material per card so each sweeps on its own phase.
## Prestige cards (any rarity) get the Prestige holo instead.
func _update_foil() -> void:
	var r := 0 if card_id == "" else DB.rarity_index(str(DB.card(card_id).get("rarity", "common")))
	var p := prestige_stars()
	_set_overlay(p > 0)
	if p > 0:
		if _prestige_mat == null:
			_prestige_mat = ShaderMaterial.new()
			_prestige_mat.shader = PRESTIGE_SHADER
		var szp := size if size.x > 1.0 else custom_minimum_size
		_prestige_mat.set_shader_parameter("card_size", szp)
		_prestige_mat.set_shader_parameter("rect_origin", Vector2(-szp.x * 0.5, -szp.y))
		_prestige_mat.set_shader_parameter("phase", float(absi(hash(card_id)) % 97) / 23.0)
		_prestige_mat.set_shader_parameter("stars", float(p))
		_prestige_mat.set_shader_parameter("calm", 1.0 if bool(Settings.get_value("accessibility", "reduce_flashes", false)) else 0.0)
		material = _prestige_mat if foil else null
		return
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
		if _prestige_mat:
			_prestige_mat.set_shader_parameter("hover", maxf(_lift, _sel))
		queue_redraw()
		if _overlay:
			_overlay.queue_redraw()


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
	var pres := prestige_stars()

	# Shadow, rarity glow and selection glow
	_rr_fill(Rect2(rect.position + Vector2(3, 6 + 10 * (_lift + _sel)) * s, rect.size), 12 * s, Color(0, 0, 0, 0.45 - 0.15 * (_lift + _sel) * 0.5))
	if pres > 0:
		# Prestige: a warm gold halo that grows a little with each star.
		var pg := (0.34 + 0.05 * pres) * dim
		_rr_fill(rect.grow(6.5 * s), 17 * s, Color(PRESTIGE_GOLD, pg * 0.35))
		_rr_fill(rect.grow(3.2 * s), 14 * s, Color(PRESTIGE_GOLD.lightened(0.2), pg))
	elif r_idx >= 1 and owned:
		var ga: float = [0.0, 0.22, 0.3, 0.38, 0.5][r_idx] * dim
		_rr_fill(rect.grow(4.5 * s), 15 * s, Color(rar_col, ga * 0.5))
		_rr_fill(rect.grow(2.2 * s), 13 * s, Color(rar_col, ga))
	if _sel > 0.01:
		var pulse := 0.75 + 0.25 * sin(_t * 6.0)
		_rr_fill(rect.grow(9 * s), 18 * s, Color(cat_col.lightened(0.2), 0.28 * _sel * pulse))
		_rr_fill(rect.grow(5 * s), 15 * s, Color(cat_col.lightened(0.35), 0.6 * _sel))
	elif _lift > 0.01 and playable:
		_rr_fill(rect.grow(4 * s), 14 * s, Color(rar_col.lightened(0.2), 0.45 * _lift))
	if combo_glow > 0.01:
		_draw_combo_halo(rect, s, dim)

	# Metallic rarity frame (Prestige: a pearl frame the holo shader turns iridescent, with a gold inner line)
	var hi := 0.55 if r_idx >= 4 else 0.42
	if pres > 0:
		_rr_gradient(rect, 12 * s, Color(0.97, 0.95, 1.0) * dc, Color(0.5, 0.46, 0.62) * dc)
	else:
		_rr_gradient(rect, 12 * s, rar_col.lightened(hi) * dc, rar_col.darkened(0.55) * dc)
	_rr_outline(rect.grow(-1.4 * s), 11 * s, Color(1, 1, 1, 0.35 * dim), 1.2 * s)
	var inner := rect.grow(-5 * s)
	_rr_gradient(inner, 8 * s, PANEL_TOP * dc, PANEL_BOTTOM * dc)
	if pres > 0:
		_rr_outline(inner.grow(-0.6 * s), 8 * s, Color(PRESTIGE_GOLD, 0.85 * dim), 1.3 * s)
	if r_idx >= 3 and pres == 0:
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

	# Rarity gem, set into the bottom of the frame (a Prestige card's overlay draws its crest there instead)
	var gem := Vector2(rect.get_center().x, rect.end.y - 2.5 * s)
	if pres == 0:
		_draw_rarity_gem(gem, s, r_idx, rar_col, dc, rect, dim)
	if mastery >= 1 and pres == 0:
		_draw_mastery(rect, s, dim)
	_draw_card_badges(c, rect, art_rect, s, dim, dc, df, small, gem_c, w)


## Rarity gem and the level pips along the bottom frame edge.
func _draw_rarity_gem(gem: Vector2, s: float, r_idx: int, rar_col: Color, dc: Color, rect: Rect2, dim: float) -> void:
	var gr := (6.5 + 1.2 * r_idx) * s
	var diamond := PackedVector2Array([gem + Vector2(0, -gr), gem + Vector2(gr, 0), gem + Vector2(0, gr), gem + Vector2(-gr, 0)])
	draw_colored_polygon(PackedVector2Array([gem + Vector2(0, -gr - 2 * s), gem + Vector2(gr + 2 * s, 0), gem + Vector2(0, gr + 2 * s), gem + Vector2(-gr - 2 * s, 0)]), Color(0, 0, 0, 0.6))
	draw_polygon(diamond, PackedColorArray([rar_col.lightened(0.6) * dc, rar_col * dc, rar_col.darkened(0.4) * dc, rar_col * dc]))
	# Level pips on the bottom frame edge (five: levels 6-10 are the Prestige stars)
	if show_level and owned:
		for i in DB.PRESTIGE_LEVEL:
			var pc := Vector2(rect.position.x + (14 + i * 9) * s, rect.end.y - 2.5 * s)
			draw_circle(pc, 3.6 * s, Color(0.02, 0.03, 0.06, 0.85))
			draw_circle(pc, 2.6 * s, Color(UITheme.GOLD, dim) if i < level else Color(1, 1, 1, 0.18))


## Linked defender badge, cooldown sweep, lock, hotkey, count and combo badges and the refusal flash.
func _draw_card_badges(c: Dictionary, rect: Rect2, art_rect: Rect2, s: float, dim: float, dc: Color, df: Font, small: Font, gem_c: Vector2, w: float) -> void:
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
	if combo_glow > 0.01:
		_draw_combo_badge(rect, s, dim)
	if _shake > 0.0:
		# Refused: a red wash, a hot red rim and the cost gem ringed in red (the usual reason).
		_rr_fill(rect, 12 * s, Color(1.0, 0.15, 0.1, 0.4 * _shake))
		_rr_outline(rect.grow(1.5 * s), 13 * s, Color(1.0, 0.3, 0.22, 0.95 * _shake), 3.0 * s)
		draw_arc(gem_c, 16.5 * s, 0, TAU, 28, Color(1.0, 0.35, 0.25, _shake), 2.6 * s, true)


# ---------------------------------------------------------------- Prestige (Update 11)

## Adds or removes the overlay that draws a Prestige card's crest and stars.
func _set_overlay(on: bool) -> void:
	if on and _overlay == null:
		_overlay = Control.new()
		_overlay.name = "PrestigeOverlay"
		_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_overlay.draw.connect(_draw_overlay)
		add_child(_overlay, false, Node.INTERNAL_MODE_FRONT)
	elif not on and _overlay != null:
		_overlay.queue_free()
		_overlay = null
	if _overlay:
		_overlay.queue_redraw()


## The overlay follows the card's hover rise, growth and refusal shake exactly like _draw().
func _draw_overlay() -> void:
	var p := prestige_stars()
	if p <= 0 or _overlay == null:
		return
	var o := _overlay
	var w := size.x
	var h := size.y
	var s := w / 150.0
	var rise := -s * (lift_px * _lift + lift_px * 1.2 * _sel)
	var grow := 1.0 + 0.035 * _lift + 0.06 * _sel
	var sx := sin(_t * 70.0) * 7.0 * s * _shake * _shake
	o.draw_set_transform(Vector2(w * 0.5 + sx, h + rise), 0.0, Vector2(grow, grow))
	var rect := Rect2(-w * 0.5, -h, w, h)
	var dim := 1.0 if (playable and owned) else 0.45
	# Gold trim around the holo frame, with a four-point glint in each corner.
	_rr_outline(rect.grow(-0.6 * s), 11.5 * s, Color(PRESTIGE_GOLD.lightened(0.15), 0.95 * dim), 1.6 * s, o)
	for k: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var corner := Vector2(rect.position.x if k.x > 0 else rect.end.x, rect.position.y if k.y > 0 else rect.end.y)
		var g := corner + k * 4.6 * s
		var r := 4.2 * s
		o.draw_colored_polygon(PackedVector2Array([g + Vector2(0, -r), g + Vector2(r * 0.28, -r * 0.28), g + Vector2(r, 0), g + Vector2(r * 0.28, r * 0.28),
			g + Vector2(0, r), g + Vector2(-r * 0.28, r * 0.28), g + Vector2(-r, 0), g + Vector2(-r * 0.28, -r * 0.28)]), Color(1, 0.97, 0.85, 0.95 * dim))
	# Prestige stars where the level pips go (a Prestige card has all five pips by definition).
	if show_level:
		for i in DB.card_max_level - DB.PRESTIGE_LEVEL:
			var pc := Vector2(rect.position.x + (15 + i * 10.5) * s, rect.end.y - 2.6 * s)
			_star(pc, 5.6 * s, Color(0.05, 0.03, 0.0, 0.9), o)
			_star(pc, 4.3 * s, Color(PRESTIGE_GOLD.lightened(0.25), dim) if i < p else Color(1, 1, 1, 0.22 * dim), o)
	if mastery >= 1:
		_draw_mastery(rect, s, dim, o)
	if not hide_crest:
		var rar := DB.rarity_color(str(DB.card(card_id).get("rarity", "common")))
		if hotkey != "":
			# Battle hand: the HUD's energy bar covers the bottom edge of the cards, so the crest sits as a
			# seal on the art's bottom-right corner instead (always visible, clear of the text).
			var inner := rect.grow(-5 * s)
			var art_rect := Rect2(inner.position + Vector2(5, 31) * s, Vector2(inner.size.x - 10 * s, inner.size.y * 0.41))
			draw_prestige_crest(o, art_rect.end - Vector2(16, 13) * s, s * 1.1, p, rar, dim)
		else:
			draw_prestige_crest(o, Vector2(rect.get_center().x, rect.end.y - 1.0 * s), s * 1.3, p, rar, dim)


## The gold Prestige crest: a crowned shield between two laurel sprigs, the rarity colour as its inner rim,
## and a star with the Prestige level (1-5). Centred on `c` (its widest point); `s` = scale (1 at 150 px).
## Static so the Prestige ceremony can draw the same crest on its own canvas.
static func draw_prestige_crest(ci: CanvasItem, c: Vector2, s: float, stars: int, rarity_col: Color, dim := 1.0) -> void:
	var gold := Color(PRESTIGE_GOLD, dim)
	var gold_dark := Color(PRESTIGE_GOLD_DARK, dim)
	# Laurel sprigs: leaves fanning up and out from under the shield.
	for side: float in [-1.0, 1.0]:
		for k in 4:
			var t := float(k) / 3.0
			var base := c + Vector2(side * (9.0 + 6.0 * t), 6.0 - 9.0 * t) * s
			var ang := side * (0.35 + 0.42 * t) - PI * 0.5 * (1.0 - t) * 0.4
			var dir := Vector2(side * cos(ang), -absf(sin(ang)) - 0.35).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			var ln := (6.2 - 0.9 * t) * s
			var wd := 2.0 * s
			var leaf := PackedVector2Array([base, base + dir * ln * 0.5 + nrm * wd, base + dir * ln, base + dir * ln * 0.5 - nrm * wd])
			var outline := PackedVector2Array()
			for v in leaf:
				outline.append(base + (v - base) * 1.25 + dir * -0.6 * s)
			ci.draw_colored_polygon(outline, Color(0.06, 0.03, 0.0, 0.85 * dim))
			ci.draw_polygon(leaf, PackedColorArray([gold_dark, gold.lightened(0.15), gold.lightened(0.35), gold]))
	# Shield with a three-point crown on top.
	var shape := [Vector2(-11, -11), Vector2(-7.5, -11), Vector2(-5.5, -15.5), Vector2(-3, -11.5), Vector2(0, -17.5),
		Vector2(3, -11.5), Vector2(5.5, -15.5), Vector2(7.5, -11), Vector2(11, -11), Vector2(11, 0), Vector2(7.5, 6.5),
		Vector2(0, 11.5), Vector2(-7.5, 6.5), Vector2(-11, 0)]
	var back := PackedVector2Array()
	var face := PackedVector2Array()
	var cols := PackedColorArray()
	var inset := PackedVector2Array()
	for v: Vector2 in shape:
		back.append(c + v * 1.18 * s + Vector2(0, 0.6) * s)
		face.append(c + v * s)
		cols.append(gold.lightened(0.45).lerp(gold_dark, clampf((v.y + 17.5) / 29.0, 0.0, 1.0)))
	for i: int in [0, 8, 9, 10, 11, 12, 13]:
		inset.append(c + (shape[i] as Vector2) * 0.72 * s + Vector2(0, 0.8) * s)
	ci.draw_colored_polygon(back, Color(0.05, 0.03, 0.0, 0.92 * dim))
	ci.draw_polygon(face, cols)
	ci.draw_colored_polygon(inset, Color(0.08, 0.06, 0.16, dim))
	var rim := inset.duplicate()
	rim.append(inset[0])
	ci.draw_polyline(rim, Color(rarity_col.lightened(0.25), dim), maxf(1.0, 1.3 * s), true)
	# Crown jewels.
	for j: Vector2 in [Vector2(-5.5, -15.5), Vector2(0, -17.5), Vector2(5.5, -15.5)]:
		ci.draw_circle(c + j * s, 1.3 * s, Color(1, 1, 0.92, dim))
	# Star with the Prestige level.
	var sc := c + Vector2(0, -1.2) * s
	var star := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + PI * k / 5.0
		star.append(sc + Vector2(cos(a), sin(a)) * (8.3 if k % 2 == 0 else 4.1) * s)
	ci.draw_colored_polygon(star, Color(1.0, 0.9, 0.5, dim))
	var df := UITheme.font_display()
	var fs := maxi(9, int(10.5 * s))
	var txt := str(clampi(stars, 1, 5))
	var ts := df.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var tp := sc + Vector2(-ts.x * 0.5 - 0.3 * s, fs * 0.38)
	ci.draw_string_outline(df, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(2, int(2.2 * s)), Color(1.0, 0.97, 0.85, dim))
	ci.draw_string(df, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.32, 0.12, 0.0, dim))


## Combo hint: a soft halo around the card, brighter and pulsing on the selected card's partner.
func _draw_combo_halo(rect: Rect2, s: float, dim: float) -> void:
	var k := combo_glow * (1.0 if dim >= 1.0 else 0.7)
	var pulse := 0.5 + 0.5 * sin(_t * (6.0 if combo_partner else 2.4))
	if combo_partner:
		_rr_fill(rect.grow(10 * s), 19 * s, Color(COMBO_COLOR, (0.16 + 0.14 * pulse) * k))
		_rr_fill(rect.grow(5.5 * s), 15 * s, Color(COMBO_COLOR.lightened(0.2), (0.45 + 0.3 * pulse) * k))
	else:
		_rr_fill(rect.grow(6.5 * s), 16 * s, Color(COMBO_COLOR, (0.14 + 0.1 * pulse) * k))
		_rr_outline(rect.grow(3 * s), 14 * s, Color(COMBO_COLOR, (0.6 + 0.3 * pulse) * k), 2.0 * s)


## Combo hint: two linked rings on the top-right corner of the frame.
func _draw_combo_badge(rect: Rect2, s: float, dim: float) -> void:
	var c := Vector2(rect.end.x - 6 * s, rect.position.y + 6 * s)
	var r := 11.0 * s
	draw_circle(c, r + 1.5 * s, Color(0.02, 0.05, 0.04, 0.95))
	draw_circle(c, r, Color(COMBO_COLOR.darkened(0.55), dim))
	var col := Color(COMBO_COLOR.lightened(0.35 if combo_partner else 0.15), dim)
	draw_arc(c + Vector2(-2.8, 0) * s, 4.2 * s, 0, TAU, 16, col, 1.8 * s, true)
	draw_arc(c + Vector2(2.8, 0) * s, 4.2 * s, 0, TAU, 16, col, 1.8 * s, true)


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
func _draw_mastery(rect: Rect2, s: float, dim: float, ci: CanvasItem = null) -> void:
	var gold := Color(UITheme.GOLD, dim)
	var mastered := mastery >= CardMastery.MAX_STARS
	if mastered:
		_rr_outline(rect.grow(2.2 * s), 14 * s, Color(1.0, 0.86, 0.4, 0.95 * dim), 2.4 * s, ci)
		_rr_outline(rect.grow(-3.4 * s), 9.5 * s, Color(1.0, 0.85, 0.35, 0.75 * dim), 1.1 * s, ci)
		var plate := Rect2(Vector2(rect.end.x - 44 * s, rect.end.y - 9 * s), Vector2(38, 13) * s)
		_rr_fill(plate, 6 * s, Color(0.35, 0.22, 0.02, 0.95 * dim), ci)
		_rr_outline(plate, 6 * s, Color(1.0, 0.86, 0.4, dim), 1.2 * s, ci)
	for i in CardMastery.MAX_STARS:
		var cpos := Vector2(rect.end.x - (13 + i * 11) * s, rect.end.y - 2.5 * s)
		var on := i < mastery
		_star(cpos, 5.6 * s, Color(0.02, 0.03, 0.06, 0.9), ci)
		_star(cpos, 4.3 * s, (Color(1.0, 0.95, 0.7, dim) if mastered else gold) if on else Color(1, 1, 1, 0.2 * dim), ci)


func _star(c: Vector2, r: float, col: Color, ci: CanvasItem = null) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI / 2 + PI * k / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
	(ci if ci else self).draw_colored_polygon(pts, col)


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


func _rr_fill(r: Rect2, rad: float, col: Color, ci: CanvasItem = null) -> void:
	(ci if ci else self).draw_colored_polygon(_rr_points(r, rad), col)


func _rr_gradient(r: Rect2, rad: float, top: Color, bottom: Color) -> void:
	var pts := _rr_points(r, rad)
	var cols := PackedColorArray()
	for p in pts:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / maxf(r.size.y, 1.0), 0.0, 1.0)))
	draw_polygon(pts, cols)


func _rr_outline(r: Rect2, rad: float, col: Color, width: float, ci: CanvasItem = null) -> void:
	var pts := _rr_points(r, rad)
	pts.append(pts[0])
	(ci if ci else self).draw_polyline(pts, col, width, true)


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
