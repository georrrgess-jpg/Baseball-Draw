class_name UITheme
extends RefCounted
## Builds the global Theme and exposes palette colours, fonts and style helpers.

const NAVY_DARK := Color("#0E1A2B")
const NAVY := Color("#14233A")
const NAVY_LIGHT := Color("#1E3354")
const CHARCOAL := Color("#1B1F27")
const SCARLET := Color("#E0262F")
const SCARLET_DEEP := Color("#A3141C")
const BLUE := Color("#2F7DE1")
const GOLD := Color("#F5B82E")
const GREEN := Color("#3DDC84")
const PURPLE := Color("#9B5DE5")
const OFFWHITE := Color("#F4F1EA")
const MUTED := Color("#8D9AB0")
const ENERGY := Color("#3FD0FF")

static var _fonts := {}
static var _theme: Theme


static func _font(file: String, weight := 0) -> Font:
	var key := "%s:%d" % [file, weight]
	if _fonts.has(key):
		return _fonts[key]
	var path := "res://assets/fonts/" + file
	var f: Font = null
	if ResourceLoader.exists(path):
		var base: FontFile = load(path)
		if weight > 0:
			var v := FontVariation.new()
			v.base_font = base
			v.variation_opentype = {"wght": weight}
			f = v
		else:
			f = base
	else:
		f = ThemeDB.fallback_font
	_fonts[key] = f
	return f


## Brush/comic display face for titles and big callouts.
static func font_display() -> Font:
	return _font("Bangers-Regular.ttf")


## Hand-lettered marker face for flavour text and the tagline.
static func font_brush() -> Font:
	return _font("PermanentMarker-Regular.ttf")


## Condensed athletic face for headers and numbers.
static func font_header() -> Font:
	return _font("Teko-Variable.ttf", 600)


static func font_body() -> Font:
	return _font("BarlowCondensed-SemiBold.ttf")


static func font_body_bold() -> Font:
	return _font("BarlowCondensed-Bold.ttf")


static func font_small() -> Font:
	return _font("Barlow-Medium.ttf")


static func panel_style(bg: Color = Color(0.055, 0.09, 0.15, 0.92), border: Color = Color(1, 1, 1, 0.08),
		border_w := 1, radius := 8, pad := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


static func button_style(bg: Color, border: Color, skew := 0.0, border_w := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(4)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	s.skew = Vector2(skew, 0)
	s.anti_aliasing = true
	return s


static func build() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = font_body()
	t.default_font_size = 22

	# Labels
	t.set_color("font_color", "Label", OFFWHITE)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 2)

	# Buttons
	t.set_stylebox("normal", "Button", button_style(Color(0.08, 0.13, 0.22, 0.95), Color(1, 1, 1, 0.12), 0.0))
	t.set_stylebox("hover", "Button", button_style(Color(0.13, 0.2, 0.33, 1.0), SCARLET, 0.0))
	t.set_stylebox("pressed", "Button", button_style(SCARLET_DEEP, SCARLET, 0.0))
	t.set_stylebox("disabled", "Button", button_style(Color(0.08, 0.1, 0.14, 0.7), Color(1, 1, 1, 0.05), 0.0))
	t.set_stylebox("focus", "Button", button_style(Color(0, 0, 0, 0), Color(GOLD, 0.8), 0.0))
	t.set_color("font_color", "Button", OFFWHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.35))
	t.set_font("font", "Button", font_header())
	t.set_font_size("font_size", "Button", 28)

	# Panels
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_stylebox("panel", "TooltipPanel", panel_style(Color(0.04, 0.06, 0.1, 0.97), Color(GOLD, 0.6), 1, 6, 10))
	t.set_color("font_color", "TooltipLabel", OFFWHITE)
	t.set_font_size("font_size", "TooltipLabel", 18)

	# Progress bars
	var pb_bg := panel_style(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.08), 1, 4, 0)
	var pb_fill := panel_style(BLUE, Color(0, 0, 0, 0), 0, 4, 0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", OFFWHITE)
	t.set_font_size("font_size", "ProgressBar", 16)

	# Sliders
	var slider := panel_style(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.1), 1, 4, 0)
	slider.content_margin_top = 4
	slider.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", slider)
	var grab := panel_style(SCARLET, Color(0, 0, 0, 0), 0, 4, 0)
	t.set_stylebox("grabber_area", "HSlider", grab)
	t.set_stylebox("grabber_area_highlight", "HSlider", panel_style(Color("#ff4a52"), Color(0, 0, 0, 0), 0, 4, 0))

	# Line edits
	t.set_stylebox("normal", "LineEdit", panel_style(Color(0.03, 0.05, 0.09, 0.95), Color(1, 1, 1, 0.12), 1, 6, 8))
	t.set_stylebox("focus", "LineEdit", panel_style(Color(0.03, 0.05, 0.09, 0.95), GOLD, 1, 6, 8))
	t.set_color("font_color", "LineEdit", OFFWHITE)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)

	# Option buttons / popups
	t.set_stylebox("normal", "OptionButton", button_style(Color(0.08, 0.13, 0.22, 0.95), Color(1, 1, 1, 0.12)))
	t.set_stylebox("hover", "OptionButton", button_style(Color(0.13, 0.2, 0.33, 1), SCARLET))
	t.set_stylebox("pressed", "OptionButton", button_style(SCARLET_DEEP, SCARLET))
	t.set_stylebox("focus", "OptionButton", button_style(Color(0, 0, 0, 0), Color(GOLD, 0.8)))
	t.set_font("font", "OptionButton", font_body_bold())
	t.set_font_size("font_size", "OptionButton", 22)
	t.set_stylebox("panel", "PopupMenu", panel_style(Color(0.05, 0.08, 0.13, 0.98), Color(1, 1, 1, 0.12), 1, 6, 6))
	t.set_stylebox("hover", "PopupMenu", panel_style(Color(SCARLET, 0.7), Color(0, 0, 0, 0), 0, 4, 4))
	t.set_font_size("font_size", "PopupMenu", 22)

	# Check boxes
	t.set_font_size("font_size", "CheckBox", 22)
	t.set_font_size("font_size", "CheckButton", 22)

	# Scrollbars
	var sb := panel_style(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 4, 0)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", sb)
	t.set_stylebox("grabber", "VScrollBar", panel_style(Color(1, 1, 1, 0.22), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("grabber_highlight", "VScrollBar", panel_style(Color(1, 1, 1, 0.4), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", panel_style(SCARLET, Color(0, 0, 0, 0), 0, 4, 0))

	# Tabs
	t.set_stylebox("tab_selected", "TabBar", button_style(SCARLET_DEEP, SCARLET))
	t.set_stylebox("tab_unselected", "TabBar", button_style(Color(0.08, 0.13, 0.22, 0.9), Color(1, 1, 1, 0.08)))
	t.set_stylebox("tab_hovered", "TabBar", button_style(Color(0.13, 0.2, 0.33, 1), SCARLET))
	t.set_font("font", "TabBar", font_header())
	t.set_font_size("font_size", "TabBar", 26)
	t.set_stylebox("panel", "TabContainer", panel_style(Color(0.05, 0.08, 0.13, 0.9), Color(1, 1, 1, 0.08)))
	t.set_stylebox("tab_selected", "TabContainer", button_style(SCARLET_DEEP, SCARLET))
	t.set_stylebox("tab_unselected", "TabContainer", button_style(Color(0.08, 0.13, 0.22, 0.9), Color(1, 1, 1, 0.08)))
	t.set_stylebox("tab_hovered", "TabContainer", button_style(Color(0.13, 0.2, 0.33, 1), SCARLET))
	t.set_font("font", "TabContainer", font_header())
	t.set_font_size("font_size", "TabContainer", 26)

	_theme = t
	return t


# ---------------------------------------------------------------- widget helpers

static func label(text: String, size := 22, color := OFFWHITE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 64, color := OFFWHITE) -> Label:
	var l := label(text, size, color, font_display())
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.06, 0.9))
	return l


static func header(text: String, size := 34, color := OFFWHITE) -> Label:
	return label(text, size, color, font_header())


static func icon_rect(name: String, size := 28.0, tint := OFFWHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = DB.icon(name)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.modulate = tint
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## A big angled menu button with an accent stripe, used across the menus.
static func menu_button(text: String, accent := SCARLET, size := 34, skew := -0.18) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_display())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", button_style(Color(0.06, 0.1, 0.17, 0.88), Color(1, 1, 1, 0.1), skew))
	var hover := button_style(Color(accent.r * 0.55, accent.g * 0.55, accent.b * 0.55, 0.95), accent, skew, 3)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", button_style(accent, Color.WHITE, skew, 3))
	b.add_theme_stylebox_override("focus", button_style(Color(0, 0, 0, 0), Color(accent, 0.9), skew, 2))
	b.add_theme_stylebox_override("disabled", button_style(Color(0.05, 0.07, 0.1, 0.6), Color(1, 1, 1, 0.04), skew))
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	b.add_theme_constant_override("outline_size", 4)
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -6.0))
	b.pressed.connect(func() -> void: Audio.ui("ui_click"))
	return b


static func small_button(text: String, accent := BLUE, size := 22) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_override("font", font_body_bold())
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", button_style(Color(0.08, 0.13, 0.22, 0.95), Color(1, 1, 1, 0.12), 0.0, 1))
	b.add_theme_stylebox_override("hover", button_style(Color(accent.r * 0.5, accent.g * 0.5, accent.b * 0.5, 1.0), accent, 0.0, 2))
	b.add_theme_stylebox_override("pressed", button_style(accent, Color.WHITE, 0.0, 2))
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -8.0))
	b.pressed.connect(func() -> void: Audio.ui("ui_click", -3.0))
	return b


static func hsep(alpha := 0.12) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, alpha)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
