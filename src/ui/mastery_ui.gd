class_name MasteryUI
extends RefCounted
## Shared widgets for card mastery (Cards & Deck inspector, Card Upgrades, Results).


## A row of three drawn stars, `filled` of them gold.
class Stars extends Control:
	var filled := 0
	var star_size := 22.0
	var color := UITheme.GOLD

	func _init(n := 0, sz := 22.0, col := UITheme.GOLD) -> void:
		filled = n
		star_size = sz
		color = col
		custom_minimum_size = Vector2(sz * CardMastery.MAX_STARS + 4.0 * (CardMastery.MAX_STARS - 1), sz)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_filled(n: int) -> void:
		filled = n
		queue_redraw()

	func _draw() -> void:
		for i in CardMastery.MAX_STARS:
			var c := Vector2(star_size * 0.5 + i * (star_size + 4.0), size.y * 0.5)
			_star(c, star_size * 0.52, Color(0, 0, 0, 0.55))
			_star(c, star_size * 0.42, color if i < filled else Color(1, 1, 1, 0.16))

	func _star(c: Vector2, r: float, col: Color) -> void:
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2 + PI * k / 5.0
			pts.append(c + Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.45))
		draw_colored_polygon(pts, col)


## Mastery block for a card: stars, play count, progress to the next star and what it unlocks.
static func block(card_id: String, compact := false) -> Control:
	var plays := Profile.card_plays(card_id)
	var stars := CardMastery.stars_for(plays)
	var mastered := stars >= CardMastery.MAX_STARS
	var col := UITheme.GOLD
	var p := UITheme.tile_panel(Color(col, 0.55 if mastered else 0.25), 12, mastered)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	var t := UITheme.label("MASTERED" if mastered else "MASTERY", UITheme.FS_LEAD if not compact else UITheme.FS_BODY, col, UITheme.font_header())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var st := Stars.new(stars, 24.0 if not compact else 20.0)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(st)
	var bar := UITheme.bar(col, 10, 1.0, CardMastery.progress(plays))
	vb.add_child(bar)
	var info := UITheme.label(CardMastery.status_text(plays), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	vb.add_child(info)
	if not compact:
		var th: Array = CardMastery.THRESHOLDS
		var hint := UITheme.label("Play the card in games to earn stars (%d / %d / %d plays). Three stars give it a gold mastered frame. Looks only, no power." % [th[0], th[1], th[2]],
			UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body())
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(hint)
	p.tooltip_text = "Card mastery: %d / %d / %d plays for ★ / ★★ / ★★★ (Practice does not count)." % [CardMastery.THRESHOLDS[0], CardMastery.THRESHOLDS[1], CardMastery.THRESHOLDS[2]]
	return p


## One-line mastery strip (Card Upgrades): label, stars, progress bar and status text.
static func strip(card_id: String) -> Control:
	var plays := Profile.card_plays(card_id)
	var stars := CardMastery.stars_for(plays)
	var mastered := stars >= CardMastery.MAX_STARS
	var p := UITheme.tile_panel(Color(UITheme.GOLD, 0.55 if mastered else 0.22), 10, mastered)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var t := UITheme.label("MASTERED" if mastered else "MASTERY", UITheme.FS_BODY, UITheme.GOLD, UITheme.font_header())
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(t)
	var st := Stars.new(stars, 22.0)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(st)
	var bar := UITheme.bar(UITheme.GOLD, 10, 1.0, CardMastery.progress(plays))
	bar.custom_minimum_size.x = 120
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	var info := UITheme.label(CardMastery.status_text(plays), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(info)
	p.tooltip_text = "Card mastery is cosmetic: play the card in games for stars at %d / %d / %d plays; three stars give it a gold mastered frame." % [CardMastery.THRESHOLDS[0], CardMastery.THRESHOLDS[1], CardMastery.THRESHOLDS[2]]
	return p
