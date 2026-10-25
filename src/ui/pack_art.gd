class_name PackArt
extends Control
## Front artwork of a card pack, drawn at any size: pack-colour gradient with light rays,
## the game logo, a fan of card backs (or the defender for Signature packs), the pack
## name and its card count. Used for UI thumbnails and, inside a SubViewport, as the
## texture of the 3D foil pack.

var pack_type := "rookie"
var signature_card := ""


func _init(type := "rookie", card := "") -> void:
	pack_type = type
	signature_card = card
	custom_minimum_size = Vector2(130, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_pack(type: String, card := "") -> void:
	pack_type = type
	signature_card = card
	queue_redraw()


func _draw() -> void:
	# Painted pack fronts (tools/art/packs.py); Signature packs get the defender's portrait
	# in the medallion window (centre 256,370, radius 82 on the 512x788 artwork).
	var tex: Texture2D = DB._texture("res://assets/textures/packs/%s.png" % pack_type)
	if tex:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		if pack_type == "signature":
			var linked := str(DB.card(signature_card).get("linked", "")) if signature_card != "" else ""
			var pt := DB.portrait(linked) if linked != "" else null
			var k := size.x / 512.0
			var r := 80.0 * k
			var mc := Vector2(256, 370) * k
			if pt:
				draw_texture_rect(pt, Rect2(mc - Vector2(r, r), Vector2(r, r) * 2.0), false)
			else:   # no defender attached: a gold star instead of an empty window
				var pts := PackedVector2Array()
				for i in 10:
					var ang := -PI * 0.5 + PI * i / 5.0
					pts.append(mc + Vector2(cos(ang), sin(ang)) * r * (0.75 if i % 2 == 0 else 0.32))
				draw_colored_polygon(pts, Color("#FFD34D"))
		return
	var pd := DB.pack(pack_type)
	var w := size.x
	var h := size.y
	var s := w / 130.0
	var c1 := Color(str(pd.get("color", "#2F7BE0")))
	var c2 := Color(str(pd.get("color2", "#0E2A5C")))
	var acc := Color(str(pd.get("accent", "#9FD3FF")))
	# Background gradient
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([c1.lightened(0.15), c1, c2, c2.darkened(0.2)]))
	# Light rays from behind the centre emblem
	var cc := Vector2(w * 0.5, h * 0.47)
	for i in 18:
		var a0 := TAU * i / 18.0 + 0.08
		var a1 := a0 + TAU / 18.0 * 0.45
		var far := h * 1.2
		draw_colored_polygon(PackedVector2Array([cc, cc + Vector2(cos(a0), sin(a0)) * far, cc + Vector2(cos(a1), sin(a1)) * far]),
			Color(acc, 0.07 if i % 2 == 0 else 0.035))
	# Diagonal foil stripes
	var x := -h
	while x < w:
		draw_line(Vector2(x, h), Vector2(x + h, 0), Color(1, 1, 1, 0.035), 6.0 * s)
		x += 22.0 * s
	# Centre emblem
	_disc(cc, 42 * s, Color(c2.darkened(0.3), 0.85))
	draw_arc(cc, 42 * s, 0, TAU, 48, Color(acc, 0.9), 2.2 * s, true)
	draw_arc(cc, 37 * s, 0, TAU, 48, Color(acc, 0.35), 1.0 * s, true)
	if pack_type == "signature" and signature_card != "":
		var linked := str(DB.card(signature_card).get("linked", ""))
		var pt := DB.portrait(linked) if linked != "" else null
		if pt:
			draw_texture_rect(pt, Rect2(cc - Vector2(36, 36) * s, Vector2(72, 72) * s), false)
	else:
		var n := int(pd.get("cards", 3))
		for i in n:
			var t := (float(i) - (n - 1) * 0.5) / maxf(1.0, n - 1)
			_mini_card(cc + Vector2(t * 22 * s, 4 * s + absf(t) * 4 * s), t * 0.5, s, acc)
	# Logo
	var logo: Texture2D = DB._texture("res://assets/textures/logo/logo_small.png")
	if logo:
		var lw := w * 0.78
		var lh := lw * float(logo.get_height()) / float(logo.get_width())
		draw_texture_rect(logo, Rect2(Vector2((w - lw) * 0.5, h * 0.035), Vector2(lw, lh)), false)
	# Pack name and count
	var df := UITheme.font_display()
	var name_text := str(pd.get("name", "Card Pack")).to_upper()
	var words := name_text.split(" ")
	var line1 := words[0]
	var line2 := " ".join(words.slice(1)) if words.size() > 1 else ""
	_centered_outline(df, line1, h * 0.79, int(30 * s), Color.WHITE, c2.darkened(0.4), s)
	if line2 != "":
		_centered_outline(df, line2, h * 0.865, int(19 * s), acc.lightened(0.3), c2.darkened(0.4), s)
	var tag := "%d CARD%s" % [int(pd.get("cards", 3)), "" if int(pd.get("cards", 3)) == 1 else "S"]
	if pack_type == "signature" and signature_card != "":
		tag = str(DB.card(signature_card).name).to_upper()
	var bf := UITheme.font_body_bold()
	var ts := int(12 * s)
	var tw := bf.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, ts).x + 16 * s
	var tr := Rect2(Vector2((w - tw) * 0.5, h * 0.905), Vector2(tw, 17 * s))
	draw_rect(tr, Color(0, 0, 0, 0.45))
	draw_rect(tr, Color(acc, 0.8), false, 1.0)
	draw_string(bf, tr.position + Vector2(8 * s, 12.6 * s), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, ts, acc.lightened(0.4))
	# Inner border
	draw_rect(Rect2(Vector2(4, 4) * s, Vector2(w - 8 * s, h - 8 * s)), Color(acc, 0.55), false, 1.4 * s)


func _mini_card(c: Vector2, angle: float, s: float, acc: Color) -> void:
	var cw := 26.0 * s
	var ch := 36.0 * s
	draw_set_transform(c, angle, Vector2.ONE)
	draw_rect(Rect2(Vector2(-cw, -ch) * 0.5 + Vector2(2, 3) * s, Vector2(cw, ch)), Color(0, 0, 0, 0.4))
	draw_rect(Rect2(Vector2(-cw, -ch) * 0.5, Vector2(cw, ch)), Color("#E9C46A"))
	draw_rect(Rect2(Vector2(-cw, -ch) * 0.5 + Vector2(2, 2) * s, Vector2(cw - 4 * s, ch - 4 * s)), Color("#13223F"))
	var d := 5.0 * s
	draw_colored_polygon(PackedVector2Array([Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)]), Color(acc, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _disc(c: Vector2, r: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		pts.append(c + Vector2(cos(TAU * i / 40.0), sin(TAU * i / 40.0)) * r)
	draw_colored_polygon(pts, col)


func _centered_outline(font: Font, text: String, y: float, fsize: int, col: Color, outline: Color, s: float) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := Vector2((size.x - tw) * 0.5, y)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, int(5 * s), outline)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
