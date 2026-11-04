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
const STAR := Color(0.7, 0.85, 1.0)

# ---- Design system (menus). Sizes are design pixels at 1920x1080; nothing below FS_MIN.
const FS_MIN := 16        ## captions, footnotes
const FS_SMALL := 18      ## secondary text, tile details
const FS_BODY := 20       ## body text
const FS_LEAD := 24       ## emphasised body, list names
const FS_H3 := 26         ## tile titles
const FS_H2 := 30         ## panel / section headers
const FS_H1 := 40         ## big numbers, sub-titles
const FS_TITLE := 64      ## screen titles
## Standard panel colours: a screen's main panels, tiles inside them, and their borders.
const PANEL_BG := Color(0.04, 0.07, 0.12, 0.92)
const TILE_BG := Color(0.06, 0.095, 0.16, 0.95)
const BORDER := Color(1, 1, 1, 0.1)
## Button heights per role.
const BTN_H_HERO := 112
const BTN_H_LARGE := 72
const BTN_H := 56
const BTN_H_SMALL := 44
## Motion: everything that appears uses these (seconds).
const T_FAST := 0.12
const T_MED := 0.22
const T_SLOW := 0.35

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
	# Toggle switches sit on the row's panel; without this they inherit the filled Button styles.
	for st in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		var cs := panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 6, 6)
		if st.begins_with("hover"):
			cs.bg_color = Color(1, 1, 1, 0.05)
		t.set_stylebox(st, "CheckButton", cs)
	t.set_stylebox("focus", "CheckButton", panel_style(Color(0, 0, 0, 0), Color(GOLD, 0.6), 1, 6, 6))
	t.set_color("font_pressed_color", "CheckButton", GREEN)
	t.set_color("font_hover_pressed_color", "CheckButton", GREEN)
	t.set_font("font", "CheckButton", font_body_bold())

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
	t.set_constant("icon_separation", "TabContainer", 8)

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
	add_feedback(b)
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
	add_feedback(b, 1.0)
	return b


## Standard menu button. Variants:
##   "primary"   — the screen's main action (filled scarlet, or `accent` if given)
##   "secondary" — everything else (navy, accent border on hover)
##   "danger"    — destructive actions (deep red outline)
##   "ghost"     — low-emphasis text button
## `icon` is an icon name from assets/textures/icons.
static func button(text: String, variant := "secondary", size := FS_LEAD, icon := "", accent := Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	var acc: Color = accent
	if acc.a == 0.0:
		acc = {"primary": SCARLET, "danger": SCARLET_DEEP, "ghost": MUTED}.get(variant, BLUE)
	var normal_bg := Color(0.07, 0.115, 0.195, 0.95)
	var normal_border := Color(1, 1, 1, 0.14)
	var font := font_header()
	match variant:
		"primary":
			normal_bg = acc.darkened(0.15)
			normal_border = acc.lightened(0.35)
			font = font_display()
		"danger":
			normal_bg = Color(0.16, 0.05, 0.07, 0.92)
			normal_border = Color(SCARLET, 0.55)
		"ghost":
			normal_bg = Color(1, 1, 1, 0.0)
			normal_border = Color(1, 1, 1, 0.0)
	var mk := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		var s := button_style(bg, border, 0.0, bw)
		s.set_corner_radius_all(8)
		s.content_margin_left = 20
		s.content_margin_right = 20
		return s
	b.add_theme_stylebox_override("normal", mk.call(normal_bg, normal_border, 2))
	b.add_theme_stylebox_override("hover", mk.call(acc.lightened(0.08) if variant == "primary" else Color(acc.r * 0.45, acc.g * 0.45, acc.b * 0.45, 0.98), Color.WHITE if variant == "primary" else acc, 2))
	b.add_theme_stylebox_override("pressed", mk.call(acc.darkened(0.3) if variant == "primary" else acc.darkened(0.2), Color.WHITE, 2))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), Color(GOLD, 0.85), 2))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.06, 0.08, 0.11, 0.7), Color(1, 1, 1, 0.05), 1))
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", maxi(size, FS_MIN))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.38))
	if variant == "primary":
		b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
		b.add_theme_constant_override("outline_size", 4)
	b.custom_minimum_size = Vector2(0, BTN_H_SMALL if size < 24 else BTN_H)
	if icon != "":
		b.icon = DB.icon(icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", int(size * 1.05))
		b.add_theme_constant_override("h_separation", 10)
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -7.0))
	if not text.ends_with("BACK"):   # BACK buttons play ui_back from their screen's go_back()
		b.pressed.connect(func() -> void: Audio.ui("ui_click", -2.0))
	add_feedback(b)
	return b


## Square icon-only button with a tooltip.
static func icon_button(icon: String, tooltip: String, accent := BLUE, side := 52) -> Button:
	var b := button("", "secondary", FS_LEAD, icon, accent)
	b.tooltip_text = tooltip
	b.custom_minimum_size = Vector2(side, side)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(st)
		s.content_margin_left = 8
		s.content_margin_right = 8
	return b


## Hover and press feedback shared by every menu button: a quick grow on hover, a squish on
## press (scale is safe inside containers). `hover_scale` 1.0 keeps only the press squish.
static func add_feedback(c: Control, hover_scale := 1.03) -> void:
	var to := func(s: float, t: float) -> void:
		if not c.is_inside_tree():
			return
		c.pivot_offset = c.size * 0.5
		var tw := c.create_tween()
		tw.tween_property(c, "scale", Vector2(s, s), t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if hover_scale != 1.0:
		c.mouse_entered.connect(func() -> void:
			if not (c is BaseButton and (c as BaseButton).disabled):
				to.call(hover_scale, T_FAST))
		c.mouse_exited.connect(func() -> void: to.call(1.0, T_FAST))
	if c is BaseButton:
		(c as BaseButton).button_down.connect(func() -> void: to.call(0.96, 0.06))
		(c as BaseButton).button_up.connect(func() -> void:
			to.call(hover_scale if c.get_global_rect().has_point(c.get_global_mouse_position()) else 1.0, T_FAST))


## Screen-enter motion shared by every menu: fade in and rise a little, staggered by `delay`.
## Uses scale + modulate (not position), so it is safe for children of containers.
static func animate_in(c: Control, delay := 0.0, from_scale := 0.97) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		c.pivot_offset = Vector2(c.size.x * 0.5, c.size.y)
		c.scale = Vector2(from_scale, from_scale))
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, T_MED)
	tw.tween_property(c, "scale", Vector2.ONE, T_SLOW).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The standard content panel (a screen's main blocks). `accent` tints the border.
static func card_panel(accent := BORDER, pad := 16, bg := PANEL_BG, border_w := 1) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", panel_style(bg, accent, border_w, 12, pad))
	return p


## A smaller tile inside a panel (stats, list rows, offers).
static func tile_panel(accent := BORDER, pad := 12, highlighted := false) -> PanelContainer:
	var p := PanelContainer.new()
	var bg := TILE_BG if not highlighted else Color(accent.darkened(0.7), 0.95)
	p.add_theme_stylebox_override("panel", panel_style(bg, accent, 2 if highlighted else 1, 10, pad))
	return p


## Section header used inside panels: optional icon, gold caps text and a thin rule.
static func section_header(text: String, icon := "", color := GOLD, size := FS_H2) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	if icon != "":
		var ic := icon_rect(icon, size * 0.9, color)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(ic)
	var l := header(text, size, color)
	hb.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(color, 0.22)
	rule.custom_minimum_size = Vector2(24, 2)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(rule)
	return hb


## A small rounded count/status pill ("3 NEW", "LOCKED").
static func badge(text: String, color := SCARLET, size := FS_MIN) -> PanelContainer:
	var p := PanelContainer.new()
	var s := panel_style(color, Color(1, 1, 1, 0.35), 1, 10, 0)
	s.content_margin_left = 9
	s.content_margin_right = 9
	s.content_margin_top = 1
	s.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(text, size, Color.WHITE, font_body_bold())
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	p.add_child(l)
	return p


## A coloured progress bar in the shared style.
static func bar(color := BLUE, height := 12, max_v := 1.0, value := 0.0) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(0, height)
	pb.show_percentage = false
	pb.max_value = max_v
	pb.value = value
	pb.mouse_filter = Control.MOUSE_FILTER_PASS
	pb.add_theme_stylebox_override("fill", panel_style(color, Color(0, 0, 0, 0), 0, int(height / 2.0), 0))
	pb.add_theme_stylebox_override("background", panel_style(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.08), 1, int(height / 2.0), 0))
	return pb


## Stat tile: icon, big value and a caption underneath.
static func stat_tile(icon: String, value: String, caption: String, color := OFFWHITE, min_w := 200.0) -> PanelContainer:
	var p := tile_panel(Color(color, 0.25), 12)
	p.custom_minimum_size = Vector2(min_w, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var ic := icon_rect(icon, 40, color)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.add_child(label(value, 34, color, font_header()))
	var cap := label(caption, FS_MIN, MUTED, font_body_bold())
	vb.add_child(cap)
	hb.add_child(vb)
	return p


static func hsep(alpha := 0.12) -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, alpha)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Screenshot helper: `-- --ui-scale=1.25` overrides the UI scale setting for this session
## (used to check layouts at UI scale 0.8–1.25 without touching the player's settings file).
static func apply_debug_ui_scale(n: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-scale="):
			n.get_tree().root.content_scale_factor = float(a.split("=")[1])


## Picture of a stadium rendered offline (assets/textures/arenas/<id>.jpg), or null.
static func arena_thumbnail(id: String) -> Texture2D:
	for ext in ["jpg", "png"]:
		var path := "res://assets/textures/arenas/%s.%s" % [id, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## Win streak colour (the flame on the hub, the Play screen and Results).
const FLAME := Color("#FF8A3D")


## Notification bubble on a control's top-right corner, overlapping its edge, so it never covers
## the control's label (half-width tiles have no room beside the text).
static func corner_badge(target: Control, text: String, color := SCARLET) -> PanelContainer:
	var bd := badge(text, color)
	bd.name = "CornerBadge"
	bd.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bd.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bd.grow_vertical = Control.GROW_DIRECTION_END
	bd.offset_left = 0
	bd.offset_right = 8
	bd.offset_top = -12
	bd.offset_bottom = -12
	bd.z_index = 1
	target.add_child(bd)
	return bd


## The win streak flame: a pill with a fire icon, the streak and the coin bonus it gives.
## A streak of 0 shows a dim flame with what the next win starts.
static func flame_chip(streak: int, bonus: float, size := FS_SMALL, compact := false) -> PanelContainer:
	var hot := streak > 0
	var col := FLAME if hot else MUTED
	var p := PanelContainer.new()
	p.name = "StreakFlame"
	var s := panel_style(Color(col.darkened(0.72), 0.92), Color(col, 0.75 if hot else 0.3), 1, 16, 0)
	s.content_margin_left = 8
	s.content_margin_right = 12
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", s)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 5)
	p.add_child(hb)
	var ic := icon_rect("fire", size + 6, col.lightened(0.15))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var txt := ""
	if compact:
		txt = "%d" % streak
	elif hot:
		txt = "%d-WIN STREAK  ·  +%d%% COINS" % [streak, int(round(bonus * 100.0))]
	else:
		txt = "NO WIN STREAK"
	var l := label(txt, size, col.lightened(0.3) if hot else MUTED, font_body_bold())
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	p.tooltip_text = ("Win streak: %d wins in a row. Each win in a row adds +10%% coins (up to +50%%); a loss resets it." % streak) if hot \
		else "Win games in a row for a coin bonus: +10% per win in the streak, up to +50%. A loss resets it."
	if hot:
		# A gentle flicker so the streak feels alive.
		var tw := ic.create_tween().set_loops()
		tw.tween_property(ic, "scale", Vector2(1.12, 1.12), 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ic, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		ic.resized.connect(func() -> void: ic.pivot_offset = ic.size * 0.5)
	return p


## A reward dictionary as [icon, short text, colour] parts. Understands the shapes the economy
## code uses: {coins, stars, pack, packs, xp, uniform, card} and {type, amount/id}.
static func reward_parts(r: Variant) -> Array:
	var out: Array = []
	if typeof(r) != TYPE_DICTIONARY:
		return out
	var d: Dictionary = r
	if d.has("type") and not d.has("coins") and not d.has("pack") and not d.has("stars"):
		var t := str(d.type)
		var v: Variant = d.get("amount", d.get("value", d.get("id", "")))
		d = {t: v}
		if t in ["pack", "card", "uniform"]:
			d[t] = str(v)
	if int(d.get("coins", 0)) > 0:
		out.append(["coin", format_int(int(d.coins)), GOLD])
	var packs: Array = []
	if str(d.get("pack", "")) != "":
		packs.append(str(d.pack))
	if typeof(d.get("packs", null)) == TYPE_ARRAY:
		for pk in d.packs:
			packs.append(str(pk.get("type", "")) if typeof(pk) == TYPE_DICTIONARY else str(pk))
	for pk in packs:
		var pd := DB.pack(pk)
		var pc := Color(str(pd.get("color", "#2F7BE0"))).lightened(0.35)
		out.append(["gift", str(pd.get("name", pk.capitalize())).replace(" Pack", "").to_upper(), pc])
	if int(d.get("stars", 0)) > 0:
		out.append(["star", str(int(d.stars)), STAR])
	if int(d.get("xp", 0)) > 0:
		out.append(["upgrade", "%d XP" % int(d.xp), GREEN])
	if str(d.get("uniform", "")) != "":
		out.append(["roster", "UNIFORM", PURPLE.lightened(0.3)])
	if str(d.get("card", "")) != "" and DB.card(str(d.card)).has("name"):
		out.append(["deck", str(DB.card(str(d.card)).name).to_upper(), BLUE.lightened(0.3)])
	return out


## Reward icons with amounts in one row.
static func reward_row(r: Variant, size := FS_SMALL) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for part in reward_parts(r):
		var c := HBoxContainer.new()
		c.add_theme_constant_override("separation", 3)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := icon_rect(part[0], size + 2, part[2])
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.add_child(ic)
		c.add_child(label(part[1], size, part[2], font_header()))
		hb.add_child(c)
	return hb


## "3d 4h", "5h 12m", "12m 05s" for countdowns.
static func format_duration(secs: int) -> String:
	secs = maxi(0, secs)
	var d := secs / 86400
	var h := (secs % 86400) / 3600
	var m := (secs % 3600) / 60
	if d > 0:
		return "%dd %dh" % [d, h]
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm %02ds" % [m, secs % 60]


## A tween bound to `node` that is killed the moment the node leaves the tree, so its callbacks
## never run against freed controls (e.g. when a screen is closed mid-animation).
static func bound_tween(node: Node) -> Tween:
	var tw := node.create_tween()
	node.tree_exiting.connect(func() -> void:
		if tw.is_valid():
			tw.kill(), CONNECT_ONE_SHOT)
	return tw


static func format_int(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
