class_name PackSummary
extends PanelContainer
## Results of a ×5 / ×10 pack opening: every card pulled, in one grid, best rarity first with
## duplicates stacked (×3) and NEW / UPGRADE READY tags. Cards are dealt face down from the
## torn pack, then flip in a quick cascade from the commons up so the big pulls land last;
## Epic and Legendary cards tremble before turning and keep a turning ray burst behind them.
## Clicking a face-down card flips just that one.

signal revealed(rarity: String, at: Vector2)   # every flip, with the card's global centre
signal all_revealed
signal deal_finished

const GAP := Vector2(16, 10)
const TAG_H := 46.0
const RARITY_DESC := ["legendary", "epic", "rare", "uncommon", "common"]

var entries: Array = []        # {"id", "rarity", "count", "new", "copies", "upgrade", "slot", "holder", "view", "tag", "rays", "revealed" (flip started), "face_up"}
var cascading := false
var dealt := false
var _done := false
var _cascade: Tween
var _type := ""
var _packs := 0
var _total := 0
var _scroll: ScrollContainer
var _grid: GridContainer
var _chips := {}               # rarity -> {"panel", "label", "count"}
var _star_tex: Texture2D
var _card_w := 140.0
var _rng := RandomNumberGenerator.new()


## `result` is Profile.open_packs(): {"type", "packs", "cards": [{"id", "rarity", "new", "copies"}]}.
func setup(result: Dictionary, star_tex: Texture2D) -> void:
	_rng.randomize()
	_star_tex = star_tex
	_type = str(result.get("type", "rookie"))
	_packs = int(result.get("packs", 1))
	var cards: Array = result.get("cards", [])
	_total = cards.size()
	var by_id := {}
	for c in cards:
		if not by_id.has(c.id):
			by_id[c.id] = {"id": c.id, "rarity": str(c.rarity), "count": 0, "new": false, "copies": 0, "revealed": false, "face_up": false}
			entries.append(by_id[c.id])
		var e: Dictionary = by_id[c.id]
		e.count += 1
		e.new = e.new or bool(c.new)
		e.copies += int(c.copies)
	for e in entries:
		e["upgrade"] = Profile.can_upgrade_card(e.id)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := DB.rarity_index(a.rarity)
		var rb := DB.rarity_index(b.rarity)
		if ra != rb:
			return ra > rb
		if a.new != b.new:
			return a.new
		if a.count != b.count:
			return a.count > b.count
		return DB.card_order.find(a.id) < DB.card_order.find(b.id))
	_build()


func _build() -> void:
	var pd := DB.pack(_type)
	var accent := Color(str(pd.get("accent", "#9FD3FF")))
	add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.02, 0.035, 0.08, 0.78), Color(accent, 0.4), 2, 14, 14))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	var title := UITheme.title("%d × %s" % [_packs, str(pd.name).to_upper()], 40, accent.lightened(0.35))
	head.add_child(title)
	var sub := UITheme.label("%d CARDS  ·  %d DIFFERENT" % [_total, entries.size()], 20, UITheme.MUTED, UITheme.font_body_bold())
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	# Rarity tally, filled in as cards turn over.
	for r in RARITY_DESC:
		var col := DB.rarity_color(r)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.panel_style(Color(col.darkened(0.6), 0.92), col, 2, 8, 6))
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.visible = false
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var l := UITheme.label("", 17, col.lightened(0.45), UITheme.font_body_bold())
		chip.add_child(l)
		head.add_child(chip)
		_chips[r] = {"panel": chip, "label": l, "count": 0}
	vb.add_child(UITheme.hsep(0.1))
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(_scroll)
	# Expand flags let the content fill the scroll area, so a short grid sits centred in it.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 4)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(center)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", int(GAP.x))
	_grid.add_theme_constant_override("v_separation", int(GAP.y))
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_grid)
	for i in entries.size():
		entries[i]["index"] = i
		_build_slot(entries[i])
	_scroll.resized.connect(_relayout)


func _build_slot(e: Dictionary) -> void:
	var r := DB.rarity_index(e.rarity)
	var col := DB.rarity_color(e.rarity)
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_grid.add_child(slot)
	var rays := Rays.new()
	rays.color = col.lightened(0.15)
	rays.rays = 16 if r >= 4 else 12
	rays.visible = false
	slot.add_child(rays)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.modulate.a = 0.0
	slot.add_child(holder)
	var view := CardView.new()
	view.set_card(e.id, Profile.card_level(e.id))
	view.face_down = true
	view.mouse_filter = Control.MOUSE_FILTER_PASS   # wheel events still reach the scroll
	view.count_badge = "×%d" % e.count if e.count > 1 else ""
	holder.add_child(view)
	view.clicked.connect(func(_c: CardView) -> void:
		if dealt and not e.revealed:
			flip(e, false))
	var tag := VBoxContainer.new()
	tag.add_theme_constant_override("separation", -2)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.visible = false
	var main_text := ""
	var main_col := Color(0.75, 0.9, 1.0)
	var sub_text := ""
	var sub_col := UITheme.MUTED
	var copies_text := "+%d cop%s" % [int(e.copies), "y" if int(e.copies) == 1 else "ies"]
	if e.new:
		main_text = "NEW!"
		main_col = UITheme.GOLD
		if e.upgrade:
			sub_text = "UPGRADE READY"
			sub_col = UITheme.GREEN
		elif int(e.copies) > 0:
			sub_text = copies_text
	elif e.upgrade:
		main_text = "UPGRADE READY"
		main_col = UITheme.GREEN
		sub_text = copies_text
	else:
		main_text = copies_text.to_upper()
	for pair in [[main_text, main_col, true], [sub_text, sub_col, false]]:
		if pair[0] == "":
			continue
		var l := UITheme.label(pair[0], 18 if pair[2] else UITheme.FS_MIN, pair[1], UITheme.font_display() if pair[2] else UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		l.add_theme_constant_override("outline_size", 5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_child(l)
	slot.add_child(tag)
	e["slot"] = slot
	e["holder"] = holder
	e["view"] = view
	e["tag"] = tag
	e["rays"] = rays


## Picks the largest card size that fits every card without scrolling (down to a floor,
## below which the grid scrolls instead).
func _relayout() -> void:
	var avail := _scroll.size - Vector2(16, 26)
	if avail.x < 100.0 or entries.is_empty():
		return
	var n := entries.size()
	var w := 104.0
	var cols := 1
	var cw := 176.0
	while cw >= 104.0:
		cols = clampi(int((avail.x + GAP.x) / (cw + GAP.x)), 1, n)
		var rows := ceili(float(n) / cols)
		w = cw
		if rows * (cw * 1.4 + TAG_H + GAP.y) - GAP.y <= avail.y:
			break
		cw -= 4.0
	# Balance the rows (e.g. 7 + 7 rather than 9 + 5).
	var row_n := ceili(float(n) / cols)
	cols = ceili(float(n) / row_n)
	_card_w = w
	_grid.columns = cols
	var ch := w * 1.4
	for e in entries:
		var slot: Control = e.slot
		slot.custom_minimum_size = Vector2(w, ch + TAG_H)
		var holder: Control = e.holder
		holder.size = Vector2(w, ch)
		holder.pivot_offset = Vector2(w, ch) * 0.5
		var view: CardView = e.view
		view.custom_minimum_size = Vector2(w, ch)
		view.size = Vector2(w, ch)
		var rays: Control = e.rays
		rays.size = Vector2.ONE * ch * 1.55
		rays.position = Vector2(w, ch) * 0.5 - rays.size * 0.5
		rays.pivot_offset = rays.size * 0.5
		var tag: Control = e.tag
		tag.position = Vector2(-10, ch + 6)
		tag.size = Vector2(w + 20, TAG_H - 6)


## Deals the face-down cards out of `from` (global position, e.g. the torn pack) into the
## grid; emits deal_finished when they have landed.
func deal(from: Vector2) -> void:
	_relayout()
	# Let the grid settle at its final card size before measuring where each card lands.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	Audio.play("card_whoosh", -2.0, 0.0, 0)
	var step := clampf(0.7 / maxf(1.0, entries.size()), 0.02, 0.06)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var h: Control = e.holder
		var slot: Control = e.slot
		h.position = from - slot.global_position - h.size * 0.5
		h.scale = Vector2.ONE * 0.3
		h.rotation = _rng.randf_range(-0.9, 0.9)
		var d := step * i
		var tw := create_tween().set_parallel(true)
		tw.tween_property(h, "modulate:a", 1.0, 0.12).set_delay(d)
		tw.tween_property(h, "position", Vector2.ZERO, 0.5).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(h, "scale", Vector2.ONE, 0.5).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(h, "rotation", 0.0, 0.5).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i % 3 == 0:
			tw.tween_callback(Audio.play.bind("card_flip", -12.0, 0.15, 30)).set_delay(d)
	var total := step * entries.size() + 0.5
	var dt := create_tween()
	dt.tween_interval(total)
	dt.tween_callback(func() -> void:
		dealt = true
		deal_finished.emit())


## Flips every face-down card in a cascade, worst to best.
func reveal_all() -> void:
	if cascading or _done:
		return
	cascading = true
	var order: Array = entries.filter(func(e: Dictionary) -> bool: return not e.revealed)
	# Worst first; within a rarity, sweep back from the end of the grid towards its start.
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := DB.rarity_index(a.rarity)
		var rb := DB.rarity_index(b.rarity)
		return ra < rb or (ra == rb and int(a.index) > int(b.index)))
	# A tween owned by this node, so leaving the screen mid-cascade simply stops it.
	_cascade = create_tween()
	for e in order:
		_cascade.tween_callback(flip.bind(e, false))
		_cascade.tween_interval([0.06, 0.08, 0.16, 0.7, 1.05][DB.rarity_index(e.rarity)])
	_cascade.tween_callback(func() -> void: cascading = false)


## Turns everything still face down at once (the SKIP button).
func skip() -> void:
	cascading = false
	if _cascade:
		_cascade.kill()
	for e in entries:
		if not e.revealed:
			flip(e, true)


func flip(e: Dictionary, fast: bool) -> void:
	if e.revealed:
		return
	e.revealed = true
	var r := DB.rarity_index(e.rarity)
	var h: Control = e.holder
	var rays: Rays = e.rays
	var tw := create_tween()
	if r >= 3 and not fast:
		# Anticipation: the card shakes while its rays fade in behind it.
		rays.visible = true
		rays.modulate.a = 0.0
		tw.tween_method(func(v: float) -> void:
			h.position = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 5.0 * v
			h.scale = Vector2.ONE * (1.0 + 0.07 * v)
			rays.modulate.a = 0.8 * v, 0.0, 1.0, 0.32 if r == 3 else 0.55)
		tw.tween_callback(func() -> void: h.position = Vector2.ZERO)
	tw.tween_callback(Audio.play.bind("card_flip", -7.0 if r < 2 else 0.0, 0.08, 35))
	tw.tween_property(h, "scale:x", 0.0, 0.07 if fast else 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_show_face.bind(e))
	tw.tween_property(h, "scale", Vector2.ONE * (1.06 + 0.04 * r), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(h, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_check_done)


func _show_face(e: Dictionary) -> void:
	var r := DB.rarity_index(e.rarity)
	e.face_up = true
	var view: CardView = e.view
	view.face_down = false
	var tag: Control = e.tag
	tag.visible = true
	tag.pivot_offset = tag.size * 0.5
	tag.scale = Vector2.ONE * 0.4
	create_tween().tween_property(tag, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var chip: Dictionary = _chips[e.rarity]
	chip.count += int(e.count)
	(chip.label as Label).text = "%d %s" % [chip.count, str(e.rarity).to_upper()]
	(chip.panel as Control).visible = true
	var rays: Rays = e.rays
	if r >= 3:
		# Best pulls keep a slowly turning burst of light behind them.
		rays.visible = true
		var rt := create_tween()
		rt.tween_property(rays, "modulate:a", 1.0, 0.08)
		rt.tween_property(rays, "modulate:a", 0.8 if r == 3 else 1.0, 0.9)
	elif r == 2:
		rays.visible = true
		rays.modulate.a = 0.7
		var rt2 := create_tween()
		rt2.tween_property(rays, "modulate:a", 0.0, 0.7)
		rt2.tween_callback(func() -> void: rays.visible = false)
	_sparkle(e, r)
	var h: Control = e.holder
	revealed.emit(e.rarity, h.get_global_rect().get_center())


func _sparkle(e: Dictionary, r: int) -> void:
	var p := CPUParticles2D.new()
	p.amount = maxi(3, int([6, 10, 20, 36, 60][r] * Settings.particle_scale()))
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.75 + 0.12 * r
	p.texture = _star_tex
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(_card_w * 0.45, _card_w * 0.62)
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 240)
	p.initial_velocity_min = 60.0 + 25.0 * r
	p.initial_velocity_max = 150.0 + 80.0 * r
	p.damping_min = 50.0
	p.damping_max = 110.0
	p.scale_amount_min = 0.2 + 0.03 * r
	p.scale_amount_max = 0.45 + 0.07 * r
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = g
	p.color = DB.rarity_color(e.rarity).lightened(0.4)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = m
	var h: Control = e.holder
	p.position = h.size * 0.5
	(e.slot as Control).add_child(p)
	p.emitting = true
	var lt := p.create_tween()
	lt.tween_interval(p.lifetime + 0.3)
	lt.tween_callback(p.queue_free)


func _check_done() -> void:
	if _done:
		return
	for e in entries:
		if not e.face_up:
			return
	_done = true
	cascading = false
	all_revealed.emit()


func all_done() -> bool:
	return _done


func summary_text() -> String:
	var new_n := 0
	var copies := 0
	var ups := 0
	for e in entries:
		if e.new:
			new_n += 1
		copies += int(e.copies)
		if e.upgrade:
			ups += 1
	var parts: Array[String] = []
	if new_n > 0:
		parts.append("%d new card%s" % [new_n, "" if new_n == 1 else "s"])
	if copies > 0:
		parts.append("%d upgrade cop%s" % [copies, "y" if copies == 1 else "ies"])
	if ups > 0:
		parts.append("%d card%s ready to upgrade" % [ups, "" if ups == 1 else "s"])
	return " · ".join(parts)


## Fades away, then frees itself.
func outro() -> void:
	cascading = false
	if _cascade:
		_cascade.kill()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween().set_parallel(true)
	for i in entries.size():
		var h: Control = entries[i].holder
		tw.tween_property(h, "position:y", 160.0, 0.35).set_delay(0.012 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "modulate:a", 0.0, 0.35).set_delay(0.12)
	tw.chain().tween_callback(queue_free)


## A soft glow with light rays, turning slowly (drawn additively behind a card).
class Rays extends Control:
	var color := Color.WHITE
	var rays := 12
	var spin := 0.35

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m

	func _process(delta: float) -> void:
		if visible:
			rotation += delta * spin

	func _draw() -> void:
		var c := size * 0.5
		var rad := minf(size.x, size.y) * 0.5
		for i in rays:
			var a := TAU * float(i) / rays
			var long := i % 2 == 0
			var hw := 0.085 if long else 0.05
			var ln := rad if long else rad * 0.72
			draw_polygon(PackedVector2Array([c, c + Vector2.from_angle(a - hw) * ln, c + Vector2.from_angle(a + hw) * ln]),
				PackedColorArray([Color(color, 0.5), Color(color, 0.0), Color(color, 0.0)]))
		for k in 6:
			draw_circle(c, rad * (0.62 - 0.09 * k), Color(color, 0.06))
