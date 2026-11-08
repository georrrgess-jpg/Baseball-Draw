class_name PrestigeCeremony
extends Control
## Update 11: the Prestige ceremony, played in Upgrade Cards when a card is prestiged (level 5 -> 6),
## also after Upgrade All. About five seconds:
##   lift   the card rises from its panel to the centre of the screen and spins (its back shows mid-turn);
##   charge it trembles while cracks of light spread through the old frame, prism rays fade in behind;
##   shatter the old frame bursts into shards, a prismatic ring and a flash, and the holo frame appears;
##   form   a comet of light runs around the new frame twice;
##   slam   the gold Prestige crest drops onto the card with a thud, a dust ring and a small shake;
##   cheer  confetti, "PRESTIGE ★1" and a fanfare, then the card waits for a click.
## A click or Esc skips it at any moment (`close()`). With reduce_flashes there is no white flash,
## no shake, softer rays and rings, and less confetti. The profile is already upgraded when it starts:
## the ceremony is only a show.

signal finished

const CARD_SIZE := Vector2(236, 330)
const T_LIFT := 0.95
const T_SHATTER := 1.85
const T_SLAM := 2.95
const T_END := 5.6
const BIG := 1.8             # the card's scale at the centre of the screen
const PRISM := [Color("#7FE8FF"), Color("#B48CFF"), Color("#FF8AD8"), Color("#FFD66B"), Color("#8CFFB4")]

var card_id := ""
var from_level := 5
var to_level := 6
var start_rect := Rect2()      # global rect the card lifts from (and returns to); empty = from below
var calm := false              # Settings: accessibility/reduce_flashes
var skipped := false
var _t := 0.0
var _closing := -1.0           # time the closing fade started (-1 = not closing)
var _card: CardView
var _top: Control              # above the card: the dropping crest and the confetti
var _title: Label
var _sub: Label
var _hint: Label
var _center := Vector2.ZERO
var _scale := 1.25
var _shake := 0.0
var _jitter := Vector2.ZERO
var _swapped := false
var _slammed := false
var _shards: Array = []        # {pts: PackedVector2Array (local), pos, vel, rot, rv, col, life}
var _cracks: Array = []        # [PackedVector2Array] in card-local pixels
var _confetti: Array = []      # {pos, vel, rot, rv, col, size, life}
var _rng := RandomNumberGenerator.new()
var _sounds := {}


## Starts a ceremony over `host` (usually a MenuScreen; Esc closes it through push_overlay).
static func play(host: Control, id: String, from_lvl: int, from_rect := Rect2()) -> PrestigeCeremony:
	var c := PrestigeCeremony.new()
	c.card_id = id
	c.from_level = from_lvl
	c.to_level = from_lvl + 1
	c.start_rect = from_rect
	c.calm = bool(Settings.get_value("accessibility", "reduce_flashes", false))
	host.add_child(c)
	if host.has_method("push_overlay"):
		host.call("push_overlay", c)
	return c


func _ready() -> void:
	name = "PrestigeCeremony"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 50
	_rng.seed = hash(card_id)
	_card = CardView.new(card_id, from_level)
	_card.set_card(card_id, from_level)
	_card.prestige = 0
	_card.custom_minimum_size = CARD_SIZE
	_card.size = CARD_SIZE
	_card.pivot_offset = CARD_SIZE * 0.5
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.mastery = CardMastery.stars(card_id)
	add_child(_card)
	_top = Control.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.draw.connect(_draw_top)
	add_child(_top)
	_title = UITheme.title("PRESTIGE ★%d" % DB.prestige_stars(to_level), 72, CardView.PRESTIGE_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 14)
	_title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.0, 0.95))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.0
	add_child(_title)
	_sub = UITheme.label("%s is a Prestige card!  Levels 6–10 unlocked: +%d%% per Prestige level." % [str(DB.card(card_id).get("name", "")),
		int(round(DB.card_prestige_growth * 100.0))], 26, UITheme.OFFWHITE, UITheme.font_body_bold())
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.add_theme_constant_override("outline_size", 6)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.modulate.a = 0.0
	add_child(_sub)
	_hint = UITheme.label("Click or press Esc to skip", 20, UITheme.MUTED, UITheme.font_body_bold())
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)
	_make_cracks()
	Audio.play("card_whoosh")
	_layout()


func _layout() -> void:
	var vs := size if size.x > 1.0 else get_viewport_rect().size
	_center = Vector2(vs.x * 0.5, vs.y * 0.47)
	_title.size = Vector2(vs.x, 90)
	_title.position = Vector2(0, _center.y - CARD_SIZE.y * 0.5 * BIG - 112)
	_sub.size = Vector2(vs.x, 40)
	_sub.position = Vector2(0, _center.y + CARD_SIZE.y * 0.5 * BIG + 40)
	_hint.size = Vector2(vs.x, 30)
	_hint.position = Vector2(0, vs.y - 54)


## Skips (or, once it has played, ends) the ceremony. Esc reaches this through MenuScreen.push_overlay.
func close() -> void:
	if _closing >= 0.0:
		return
	skipped = _t < T_END
	_closing = _t
	if not _slammed:   # make sure the end state is right even when skipped early
		_card.set_card(card_id, to_level)
		_card.prestige = -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		accept_event()
		close()


func _input(event: InputEvent) -> void:
	if _closing < 0.0 and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


static func _ease_in_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5


static func _seg(t: float, a: float, b: float) -> float:
	return clampf((t - a) / (b - a), 0.0, 1.0)


func _once(key: String, at: float, sound: String, db := 0.0) -> void:
	if _t >= at and not _sounds.has(key):
		_sounds[key] = true
		if sound != "":
			Audio.play(sound, db)


func _process(delta: float) -> void:
	_t += delta
	_layout()
	if _closing >= 0.0:
		var k := _seg(_t, _closing, _closing + 0.35)
		modulate.a = 1.0 - k
		if k >= 1.0:
			finished.emit()
			queue_free()
		queue_redraw()
		return
	if _t >= T_END + 0.6:
		_hint.text = "Click to continue"
	_update_card(delta)
	_update_particles(delta)
	_once("tremble", T_LIFT + 0.05, "pack_shake", -2.0)
	_once("shatter", T_SHATTER, "wall_break")
	_once("burst", T_SHATTER + 0.02, "reveal_legendary")
	_once("slam", T_SLAM, "boss_slam", -4.0)
	_once("cheer", T_SLAM + 0.08, "achievement")
	_once("pop", T_SLAM + 0.25, "firework_1", -6.0)
	if _t >= T_SHATTER and not _swapped:
		_swapped = true
		_shatter()
	if _t >= T_SLAM and not _slammed:
		_slammed = true
		_slam()
	queue_redraw()
	_top.queue_redraw()


func _update_card(_delta: float) -> void:
	var lift := _ease_out(_seg(_t, 0.0, T_LIFT * 0.8))
	var from_c := start_rect.get_center() if start_rect.size.x > 1.0 else Vector2(_center.x, size.y + CARD_SIZE.y)
	var from_s := (start_rect.size.x / CARD_SIZE.x) if start_rect.size.x > 1.0 else 0.8
	var pos := from_c.lerp(_center, lift)
	_scale = lerpf(from_s, BIG, lift)
	# A pulse when the new frame forms and when the crest lands.
	_scale *= 1.0 + 0.06 * sin(PI * _seg(_t, T_SHATTER, T_SHATTER + 0.45)) + 0.035 * sin(PI * _seg(_t, T_SLAM, T_SLAM + 0.3))
	# Tremble while charging, growing towards the shatter.
	var charge := _seg(_t, T_LIFT, T_SHATTER)
	var amp := (1.5 + 7.0 * charge * charge) * (0.35 if calm else 1.0) if _t < T_SHATTER and _t > T_LIFT else 0.0
	_jitter = Vector2(_rng.randf_range(-amp, amp), _rng.randf_range(-amp, amp))
	_shake = maxf(0.0, _shake - _delta * 3.2)
	var shake_v := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * 16.0 * _shake * _shake
	# Spin once around the vertical axis during the lift (the back shows mid-turn).
	var phi := TAU * _ease_in_out(_seg(_t, 0.12, T_LIFT))
	var sx := cos(phi)
	_card.face_down = sx < 0.0
	_card.scale = Vector2(maxf(absf(sx), 0.02) * _scale, _scale)
	_card.position = pos - CARD_SIZE * 0.5 + _jitter + shake_v
	# Crest: drops from above, slams onto the bottom of the card.
	var land := _card_point(Vector2(CARD_SIZE.x * 0.5, CARD_SIZE.y - 1.6))
	_top.position = Vector2.ZERO
	_top.size = size
	_top.set_meta("land", land)
	# Texts.
	var ti := _seg(_t, T_SLAM, T_SLAM + 0.3)
	_title.modulate.a = ti
	_title.scale = Vector2.ONE * lerpf(1.8, 1.0, _ease_out(ti))
	_title.pivot_offset = _title.size * 0.5
	_sub.modulate.a = _seg(_t, T_SLAM + 0.35, T_SLAM + 0.8)


## A point in the card's own pixels (0..CARD_SIZE) mapped to this overlay (spin ignored: used when face-on).
func _card_point(p: Vector2) -> Vector2:
	return _card.position + CARD_SIZE * 0.5 + (p - CARD_SIZE * 0.5) * _scale


func _make_cracks() -> void:
	var n := 9
	for i in n:
		var u := (float(i) + _rng.randf_range(0.1, 0.9)) / float(n)
		var p := _perimeter_point(u, 3.0)
		var inward := (CARD_SIZE * 0.5 - p).normalized()
		var line := PackedVector2Array([p])
		var dir := inward.rotated(_rng.randf_range(-0.6, 0.6))
		for k in _rng.randi_range(4, 7):
			p += dir * _rng.randf_range(10.0, 24.0)
			dir = dir.rotated(_rng.randf_range(-0.75, 0.75)).lerp(inward, 0.25).normalized()
			line.append(p)
		_cracks.append(line)
		if _rng.randf() < 0.6:   # a short branch
			var j := _rng.randi_range(1, line.size() - 2)
			var b := PackedVector2Array([line[j]])
			var bd := dir.rotated(_rng.randf_range(0.8, 1.4) * (1.0 if _rng.randf() < 0.5 else -1.0))
			var q := line[j]
			for k in 3:
				q += bd * _rng.randf_range(8.0, 16.0)
				bd = bd.rotated(_rng.randf_range(-0.5, 0.5))
				b.append(q)
			_cracks.append(b)


## Point on the card's outline at fraction u (0..1, clockwise from the top-left), `inset` px inside.
func _perimeter_point(u: float, inset := 0.0) -> Vector2:
	var w := CARD_SIZE.x - inset * 2.0
	var h := CARD_SIZE.y - inset * 2.0
	var d := fposmod(u, 1.0) * 2.0 * (w + h)
	var o := Vector2(inset, inset)
	if d < w:
		return o + Vector2(d, 0)
	d -= w
	if d < h:
		return o + Vector2(w, d)
	d -= h
	if d < w:
		return o + Vector2(w - d, h)
	d -= w
	return o + Vector2(0, h - d)


func _shatter() -> void:
	_card.set_card(card_id, to_level)
	_card.prestige = DB.prestige_stars(to_level)
	_card.hide_crest = true
	var rar := DB.rarity_color(str(DB.card(card_id).get("rarity", "common")))
	var n := 34
	var band := 14.0
	for i in n:
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		var a := _perimeter_point(u0, -2.0)
		var b := _perimeter_point(u1, -2.0)
		var c := _perimeter_point(u1, band)
		var d := _perimeter_point(u0, band)
		var mid := (a + b + c + d) * 0.25
		# Split each frame segment into two jagged triangles.
		var cut := a.lerp(c, _rng.randf_range(0.35, 0.65)) + Vector2(_rng.randf_range(-3, 3), _rng.randf_range(-3, 3))
		for tri in [[a, b, cut], [cut, c, d, a]]:
			var pts := PackedVector2Array()
			var cen := Vector2.ZERO
			for v: Vector2 in tri:
				cen += v
			cen /= float(tri.size())
			for v: Vector2 in tri:
				pts.append((v - cen) * _scale)
			var out := (mid - CARD_SIZE * 0.5).normalized()
			var speed := _rng.randf_range(260.0, 760.0) * (0.6 if calm else 1.0)
			var col := rar.lightened(_rng.randf_range(0.0, 0.5)) if _rng.randf() < 0.7 else rar.darkened(_rng.randf_range(0.1, 0.5))
			_shards.append({"pts": pts, "pos": _card_point(cen), "vel": out * speed + Vector2(0, -_rng.randf_range(80, 260)),
				"rot": 0.0, "rv": _rng.randf_range(-9.0, 9.0), "col": col, "life": _rng.randf_range(1.0, 1.6)})


func _slam() -> void:
	_card.hide_crest = false
	_shake = 0.0 if calm else 1.0
	var count := 90 if calm else 240
	var vs := size
	for i in count:
		# Two confetti cannons in the bottom corners, aimed up across the card.
		var left := i % 2 == 0
		var origin := Vector2(-10.0 if left else vs.x + 10.0, vs.y * 0.92)
		var ang := (-PI * 0.5 + (0.62 if left else -0.62)) + _rng.randf_range(-0.28, 0.28)
		var sp := _rng.randf_range(900.0, 1700.0) * vs.y / 1080.0
		var col: Color = PRISM[i % PRISM.size()] if i % 4 != 0 else Color("#FFF3C4")
		_confetti.append({"pos": origin + Vector2(0, _rng.randf_range(-40, 40)),
			"vel": Vector2(cos(ang), sin(ang)) * sp, "rot": _rng.randf() * TAU, "rv": _rng.randf_range(-10.0, 10.0),
			"col": col, "size": Vector2(_rng.randf_range(10, 18), _rng.randf_range(5, 9)), "life": _rng.randf_range(2.6, 3.8),
			"flip": _rng.randf() * TAU})


func _update_particles(delta: float) -> void:
	for s in _shards:
		s.vel.y += 1100.0 * delta
		s.pos += s.vel * delta
		s.rot += s.rv * delta
		s.life -= delta
	_shards = _shards.filter(func(s: Dictionary) -> bool: return s.life > 0.0)
	for c in _confetti:
		c.vel.y += 760.0 * delta
		c.vel *= 1.0 - minf(1.0, 1.9 * delta)
		c.vel.x += sin(_t * 3.0 + c.rot) * 30.0 * delta
		c.pos += c.vel * delta
		c.rot += c.rv * delta
		c.flip += 7.0 * delta
		c.life -= delta
	_confetti = _confetti.filter(func(c: Dictionary) -> bool: return c.life > 0.0)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	var vs := size
	var dark := _seg(_t, 0.0, 0.35) * 0.86
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0.01, 0.015, 0.035, dark))
	var c := _card.position + CARD_SIZE * 0.5
	# Prism rays behind the card, from the charge on; brighter after the shatter.
	var rays := _seg(_t, T_LIFT, T_SHATTER) * 0.45 + _seg(_t, T_SHATTER, T_SHATTER + 0.3) * 0.55
	if rays > 0.0:
		var n := 16
		var rot := _t * 0.22
		var reach := vs.length() * 0.55
		var strength := rays * (0.5 if calm else 1.0)
		for i in n:
			var a := rot + TAU * float(i) / n
			var wdt := 0.06 if i % 2 == 0 else 0.032
			var col: Color = PRISM[i % PRISM.size()]
			draw_polygon(PackedVector2Array([c, c + Vector2(cos(a - wdt), sin(a - wdt)) * reach, c + Vector2(cos(a + wdt), sin(a + wdt)) * reach]),
				PackedColorArray([Color(col.lightened(0.3), 0.34 * strength), Color(col, 0.0), Color(col, 0.0)]))
		# Soft core glow, warm gold.
		for k in 7:
			var r := (40.0 + 34.0 * k) * _scale
			draw_circle(c, r, Color(1.0, 0.82, 0.45, 0.045 * strength))
	# Shatter: flash, prismatic rings.
	var burst := _seg(_t, T_SHATTER, T_SHATTER + 0.9)
	if burst > 0.0 and burst < 1.0:
		for ring in 3:
			var e := _ease_out(clampf(burst * 1.25 - ring * 0.14, 0.0, 1.0))
			if e <= 0.0:
				continue
			var rad := 70.0 + e * (vs.x * 0.55)
			var a_ring := (1.0 - e) * (0.45 if calm else 0.9)
			var segs := 60
			for i in segs:
				var a0 := TAU * i / segs + _t
				var col: Color = PRISM[(i + ring) % PRISM.size()]
				draw_arc(c, rad, a0, a0 + TAU / segs + 0.01, 3, Color(col, a_ring), 14.0 * (1.0 - e) + 2.0, true)


## The top layer (above the card): the crest dropping in, then the confetti.
func _draw_top() -> void:
	var vs := size
	var c := _card.position + CARD_SIZE * 0.5
	# Light leaking from the cracks while charging.
	if _t > T_LIFT and _t < T_SHATTER:
		var p := _seg(_t, T_LIFT + 0.1, T_SHATTER - 0.1)
		for line: PackedVector2Array in _cracks:
			var shown := int(ceil(p * float(line.size() - 1)))
			if shown < 1:
				continue
			var pts := PackedVector2Array()
			for i in shown + 1:
				pts.append(_card_point(line[i]))
			_top.draw_polyline(pts, Color(1.0, 0.8, 0.4, 0.35), 7.0, true)
			_top.draw_polyline(pts, Color(1.0, 0.98, 0.85, 0.95), 2.4, true)
		# The frame glows hotter towards the break.
		_rr_outline_on(_top, Rect2(_card_point(Vector2.ZERO), CARD_SIZE * _scale).grow(2.0), 18.0 * _scale, Color(1.0, 0.85, 0.45, 0.6 * p * p), 3.0 + 5.0 * p)
	# Frame forming: a comet of light runs around the new frame twice.
	var form := _seg(_t, T_SHATTER + 0.05, T_SLAM - 0.1)
	if form > 0.0 and form < 1.0:
		for k in 2:
			for j in 14:
				var u := _ease_in_out(form) * 2.0 + k * 0.5 - j * 0.012
				var p := _card_point(_perimeter_point(u, 3.5))
				var a := (1.0 - float(j) / 14.0)
				_top.draw_circle(p, (7.0 - j * 0.35) * _scale, Color(1.0, 0.95, 0.75, 0.75 * a))
				_top.draw_circle(p, (14.0 - j * 0.6) * _scale, Color(PRISM[(j + k) % PRISM.size()], 0.22 * a))
	# Shards of the old frame.
	for s in _shards:
		var a := clampf(s.life / 0.45, 0.0, 1.0)
		_top.draw_set_transform(s.pos, s.rot, Vector2.ONE)
		var col: Color = s.col
		_top.draw_colored_polygon(s.pts, Color(col, a))
		var edge: PackedVector2Array = s.pts.duplicate()
		edge.append(s.pts[0])
		_top.draw_polyline(edge, Color(1, 1, 1, 0.55 * a), 1.2, true)
	_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Slam: dust ring and a gold shockwave at the crest.
	var sl := _seg(_t, T_SLAM, T_SLAM + 0.55)
	if sl > 0.0 and sl < 1.0:
		var land: Vector2 = _top.get_meta("land", c)
		var e := _ease_out(sl)
		_top.draw_arc(land, 20.0 + 150.0 * e, 0, TAU, 48, Color(1.0, 0.85, 0.45, 0.85 * (1.0 - e)), 6.0 * (1.0 - e) + 1.0, true)
		_top.draw_arc(land, 12.0 + 90.0 * e, 0, TAU, 40, Color(1, 1, 1, 0.6 * (1.0 - e)), 3.0, true)
	# The shatter flash covers everything (not with reduce_flashes).
	if not calm and _t >= T_SHATTER and _t < T_SHATTER + 0.3:
		_top.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 0.97, 0.9, 0.75 * pow(1.0 - _seg(_t, T_SHATTER, T_SHATTER + 0.28), 2.0)))
	if _t >= T_SLAM - 0.35 and _t < T_SLAM:
		var land: Vector2 = _top.get_meta("land", Vector2.ZERO)
		var k := _seg(_t, T_SLAM - 0.35, T_SLAM)
		var e := k * k
		var sc := lerpf(2.2, 1.0, e) * 1.3 * (CARD_SIZE.x / 150.0) * _scale
		var pos := land + Vector2(0, -(CARD_SIZE.y * _scale + 160.0) * (1.0 - e))
		# Motion streaks behind the falling crest.
		for k2 in 5:
			var off := float(k2 + 1) * 34.0 * (1.0 - e) + 10.0
			_top.draw_line(pos + Vector2(-14 + k2 * 7, -off - 30), pos + Vector2(-14 + k2 * 7, -off - 30 - 60.0 * (1.0 - e)),
				Color(1.0, 0.9, 0.6, 0.5 * k), 3.0, true)
		var rar := DB.rarity_color(str(DB.card(card_id).get("rarity", "common")))
		CardView.draw_prestige_crest(_top, pos, sc, DB.prestige_stars(to_level), rar, clampf(k * 3.0, 0.0, 1.0))
	for cf in _confetti:
		var a := clampf(cf.life / 0.6, 0.0, 1.0)
		var sz: Vector2 = cf.size
		_top.draw_set_transform(cf.pos, cf.rot, Vector2(1.0, absf(cos(cf.flip)) * 0.9 + 0.1))
		var col: Color = cf.col
		_top.draw_rect(Rect2(-sz * 0.5, sz), Color(col.lightened(0.15 * cos(cf.flip)), a))
	_top.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _rr_outline_on(ci: CanvasItem, r: Rect2, rad: float, col: Color, width: float) -> void:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var pts := PackedVector2Array()
	var centers := [Vector2(r.end.x - rad, r.position.y + rad), Vector2(r.end.x - rad, r.end.y - rad),
		Vector2(r.position.x + rad, r.end.y - rad), Vector2(r.position.x + rad, r.position.y + rad)]
	for i in 4:
		for k in 7:
			var a := -PI / 2 + PI / 2 * i + PI / 2 * float(k) / 6.0
			pts.append((centers[i] as Vector2) + Vector2(cos(a), sin(a)) * rad)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, width, true)
