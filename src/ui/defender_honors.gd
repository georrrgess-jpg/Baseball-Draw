class_name DefenderHonors
extends RefCounted
## Defender honours in the UI (Update 11): the level badge (a pill that fits two digits), the All-Star
## badge (level 15) and the Hall of Famer gold portrait frame and nameplate (level 20). Used by the Team
## screen, the Results screen and the main menu lineup; the honours come from DefenderLevels.

const HOF_GOLD := Color("#FFD35A")
const HOF_DEEP := Color("#8A5A0B")
const HOF_INK := Color("#2A1C04")
const STAR_RED := Color("#E0262F")
const STAR_BLUE := Color("#1D4FC4")


## The level in a round badge that widens into a pill for two digits. All-Stars get red, white and
## blue; Hall of Famers solid gold.
static func level_badge(level: int, height := 30.0, font_size := 19, honor := "") -> PanelContainer:
	if honor == "":
		honor = DefenderLevels.honor(level)
	var p := PanelContainer.new()
	p.name = "LevelBadge"
	var bg := Color(0.05, 0.07, 0.12, 0.96)
	var border := UITheme.GOLD
	var ink := UITheme.GOLD
	if honor == DefenderLevels.HALL_OF_FAME:
		bg = HOF_GOLD
		border = Color(1.0, 0.97, 0.82)
		ink = HOF_INK
	elif honor == DefenderLevels.ALL_STAR:
		bg = STAR_BLUE
		border = STAR_RED
		ink = Color.WHITE
	var s := UITheme.panel_style(bg, border, 2, int(height * 0.5), 0)
	var digits := str(level).length()
	s.content_margin_left = 3.0 + 2.0 * float(digits - 1)
	s.content_margin_right = s.content_margin_left
	if honor == DefenderLevels.HALL_OF_FAME:
		s.shadow_color = Color(HOF_GOLD, 0.55)
		s.shadow_size = 5
	p.add_theme_stylebox_override("panel", s)
	p.custom_minimum_size = Vector2(badge_width(level, height), height)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UITheme.label(str(level), font_size if digits < 2 else int(round(font_size * 0.88)), ink, UITheme.font_header())
	l.name = "LevelText"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	p.add_child(l)
	return p


## Width of a level badge: round for one digit, a pill for two.
static func badge_width(level: int, height := 30.0) -> float:
	return height * (1.0 + 0.32 * float(str(level).length() - 1))


## A defender's portrait in its frame: the accent frame, or a thick gold frame with a glow for a
## Hall of Famer (`honor` overrides the defender's own, e.g. for a level reached on Results).
static func portrait(id: String, size := 64.0, accent := Color(1, 1, 1, 0.3), honor := "-") -> PanelContainer:
	var frame := MenuScreen.portrait_rect(id, size, accent)
	if honor == "-":
		honor = DefenderLevels.honor_of(id)
	if honor == DefenderLevels.HALL_OF_FAME:
		gild(frame, size)
	return frame


## Turns a portrait frame gold (Hall of Famer).
static func gild(frame: PanelContainer, size := 64.0) -> void:
	var w := 3 if size < 56.0 else 4
	var s := UITheme.panel_style(HOF_DEEP.darkened(0.35), HOF_GOLD, w, 8, 2)
	s.shadow_color = Color(HOF_GOLD, 0.5)
	s.shadow_size = 6 if size < 56.0 else 9
	frame.add_theme_stylebox_override("panel", s)
	frame.name = "HallOfFameFrame"
	frame.set_meta("hall_of_fame", true)


## "HALL OF FAMER" (gold plate) or "ALL-STAR" (red, white and blue) beside a defender's name, or the
## name itself on the plate (`text`, the Results tiles); null when the defender has no honour yet.
static func nameplate(id: String, font_size := UITheme.FS_MIN, honor := "-", text := "") -> PanelContainer:
	if honor == "-":
		honor = DefenderLevels.honor_of(id)
	if honor == "":
		return null
	var hof := honor == DefenderLevels.HALL_OF_FAME
	var p := PanelContainer.new()
	p.name = "HallOfFamePlate" if hof else "AllStarPlate"
	var s := UITheme.panel_style(HOF_GOLD if hof else STAR_BLUE, Color(1.0, 0.97, 0.82) if hof else STAR_RED, 2, 6, 0)
	s.content_margin_left = 10
	s.content_margin_right = 12
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	if hof:
		s.shadow_color = Color(HOF_GOLD, 0.45)
		s.shadow_size = 6
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = ("Hall of Famer: %s reached level %d, the top of the level road." if hof
		else "All-Star: %s reached level %d.") % [DB.defender(id).get("name", id),
		DefenderLevels.badge_level(DefenderLevels.HALL_OF_FAME if hof else DefenderLevels.ALL_STAR)]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	var ink := HOF_INK if hof else Color.WHITE
	var ic := UITheme.icon_rect("trophy" if hof else "star", font_size + 2, ink)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)
	if text == "":
		text = "HALL OF FAMER" if hof else "ALL-STAR"
	var l := UITheme.label(text, font_size, ink, UITheme.font_header())
	l.name = "PlateText"
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(l)
	return p


## Short caption colour for an honour (tile sub-lines, the team strip).
static func color(honor: String, fallback := UITheme.OFFWHITE) -> Color:
	if honor == DefenderLevels.HALL_OF_FAME:
		return HOF_GOLD
	if honor == DefenderLevels.ALL_STAR:
		return Color(0.62, 0.78, 1.0)
	return fallback
