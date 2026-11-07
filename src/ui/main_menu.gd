extends Node3D
## Main menu (the hub), Update 10 "broadcast matchday" layout: a live 3D stadium with the team
## warming up (throwing and catching) under a slow cinematic camera, framed like a TV broadcast:
## * a top bar across the full width: logo, manager (division, RP), LEVEL bar, coins / stars /
##   cards owned, "?" and a settings gear (Settings, Practice, Exit);
## * the hero block on the left: the BROADCAST MATCHDAY ribbon, the selected mode as a huge title
##   with stadium and difficulty, the win streak / Season / promotion chips, CONTINUE RUN (when a
##   run is saved), the big PLAY and the quick mode chips;
## * the 3D lineup in the middle;
## * the TODAY panel on the right: Daily Challenge, Missions and Daily Login cards;
## * a bottom bar across the full width with the destinations and their badges.

var stadium: StadiumBuilder
var camera: Camera3D
var models: Array[CharacterModel] = []
var ui: Control
var _t := 0.0
var _ball: MeshInstance3D
var _throw_t := 1.5
var _buttons: Array[Button] = []
var _continue_btn: Button
var _hero: Button
var _caption: VBoxContainer
var _right: VBoxContainer
var _daily_countdown: Label
var _login_countdown: Label
var _countdown_t := 0.0
var _welcome_later: Button   # "Look around first" on the welcome panel (Esc presses it)
## Idle showcase: every few seconds one defender shows off and the camera leans toward them.
var _show_t := 5.0
var _focus := Vector3.ZERO
var _focus_t := 0.0
var _focus_w := 0.0


func _ready() -> void:
	var arena := DB.arena(Profile.data.get("arena", "steel_yard"))
	var layout := DB.layout_for_arena(arena.id)
	stadium = StadiumBuilder.new()
	stadium.build(self, arena, layout, false)
	var routes: Array = []
	for r in layout.get("routes", []):
		routes.append(Route.from_points(r.id, r.gate, r.points))
	FieldBuilder.build(self, arena.get("theme", {}), routes)
	stadium.set_excitement(0.35)
	stadium.scoreboard_ui.flash("PLAY BALL!", 9999.0)

	camera = Camera3D.new()
	camera.fov = 38.0
	camera.far = 600.0
	add_child(camera)
	_spawn_team()
	_ball = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	_ball.mesh = sm
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.98, 0.97, 0.93)
	bm.emission_enabled = true
	bm.emission = Color(1, 0.9, 0.7)
	bm.emission_energy_multiplier = 0.6
	_ball.material_override = bm
	_ball.visible = false
	add_child(_ball)

	if "--skip-welcome" in OS.get_cmdline_user_args():   # screenshot helper: a returning player
		Profile.data.flags.tutorial_done = true
	_build_ui()
	UITheme.apply_debug_ui_scale(self)
	Audio.play_music("menu_theme")
	Audio.play_ambience(["stadium_crowd", ""])


func _spawn_team() -> void:
	var colors: Dictionary = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.home).colors
	# A V-shaped hero lineup facing the camera, framed in the open middle of the screen (between
	# the hero block and the TODAY panel).
	var spots := [
		[Vector3(3.7, 0, 9.4), "victory"], [Vector3(2.4, 0, 8.4), "ready"], [Vector3(5.0, 0, 8.5), "idle"],
		[Vector3(1.2, 0, 7.3), "idle"], [Vector3(6.2, 0, 7.4), "ready"], [Vector3(3.7, 0, 6.6), "idle"],
	]
	var team: Array = Profile.data.team
	for i in mini(team.size(), spots.size()):
		var id: String = team[i]
		var cm := CharacterModel.new()
		add_child(cm)
		var c := colors.duplicate()
		c["Undershirt"] = DB.defender(id).accent
		cm.setup(id, {"accent": DB.defender_accent(id), "colors": c, "cache_key": id, "base": spots[i][1]})
		cm.position = spots[i][0]
		var to := Vector3(0.5, 0, 17.0) - cm.position
		cm.rotation.y = atan2(to.x, to.z) + randf_range(-0.2, 0.2)
		models.append(cm)
		var shadow := Enemy._make_blob_shadow(0.5)
		cm.add_child(shadow)


## Camera framing: the lineup sits in the open middle of the screen, a little left of centre
## (the TODAY panel covers the right third).
const CAM_POS := Vector3(-0.4, 1.8, 16.6)
const CAM_LOOK := Vector3(4.35, 2.3, 4.0)


func _process(delta: float) -> void:
	_t += delta
	_update_countdowns(delta)
	# The camera starts on the lineup (no fly-in through the stadium) and only breathes a little.
	# During a showcase it leans toward the defender showing off.
	var pos := CAM_POS + Vector3(sin(_t * 0.07) * 0.22, sin(_t * 0.11) * 0.06, cos(_t * 0.05) * 0.12)
	var look := CAM_LOOK + Vector3(sin(_t * 0.045) * 0.12, sin(_t * 0.08) * 0.03, 0.0)
	_focus_t -= delta
	_focus_w = move_toward(_focus_w, 1.0 if _focus_t > 0.0 else 0.0, delta * 0.7)
	var w := smoothstep(0.0, 1.0, _focus_w) * 0.35
	camera.position = pos.lerp(pos + (_focus - pos) * 0.12, w)
	camera.look_at(look.lerp(_focus, w), Vector3.UP)
	_show_t -= delta
	if _show_t <= 0.0 and models.size() > 0:
		_show_t = randf_range(7.0, 10.0)
		_showcase()
	_throw_t -= delta
	if _throw_t <= 0.0 and models.size() >= 2:
		_throw_t = randf_range(2.4, 3.6)
		_play_catch()


## Two defenders play catch: throw animation, ball arc, catch animation.
func _play_catch() -> void:
	var a: CharacterModel = models[randi() % models.size()]
	var b: CharacterModel = models[randi() % models.size()]
	if a == b:
		return
	var to := b.position - a.position
	a.rotation.y = atan2(to.x, to.z)
	b.rotation.y = atan2(-to.x, -to.z)
	a.play_action("throw", 1.0)
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(func() -> void:
		_ball.visible = true
		var start := a.hand_position()
		var end := b.glove_position()
		var flight := start.distance_to(end) / 16.0
		var t2 := create_tween()
		t2.tween_method(func(k: float) -> void:
			_ball.global_position = start.lerp(end, k) + Vector3(0, sin(k * PI) * 1.4, 0), 0.0, 1.0, flight)
		t2.tween_callback(func() -> void:
			_ball.visible = false
			Audio.play("glove_catch", -14.0))
		get_tree().create_timer(maxf(flight - 0.25, 0.0)).timeout.connect(func() -> void: b.play_action("catch", 1.0)))


# ---------------------------------------------------------------- UI
#
# Layout (design pixels, 1920x1080; the window stretches with "expand", so wider screens only
# widen the middle): a TOP_H top bar and a BOTTOM_H bottom bar across the full width; between
# them the hero block on the left (HERO_W wide) and the TODAY panel on the right (TODAY_W wide).

const TOP_H := 104.0
const BOTTOM_H := 132.0
const HERO_X := 44.0
const HERO_W := 560.0
const TODAY_W := 620.0
## Modes on the hub's quick switch: [id, short name, icon].
const QUICK_MODES := [["quick", "QUICK", "speed"], ["standard", "SIEGE", "trophy"], ["boss_rush", "BOSS RUSH", "boss"], ["endless", "ENDLESS", "wave"]]
const TODAY_ACCENT := Color("#FF8A3D")
const CARD_GOLD := Color("#F5B82E")

var _mode_chips := {}
var _title_top: Label
var _title_main: Label
var _title_swoosh: Panel
var _venue: Label
var _login_panel: Control
var _season_bar: Button
var _shop_tile: Button
var _gear_menu: Control
var _gear_btn: Button


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	# A dark gradient behind the hero block keeps the big title legible over the stadium.
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.04, 0.09, 0.9))
	g.set_color(1, Color(0.02, 0.04, 0.09, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.custom_minimum_size = Vector2(860, 0)
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)

	_build_top_bar()
	_build_hero()
	_build_today()
	_build_bottom_bar()
	_build_showcase_caption()
	# Staggered entrance.
	var i := 0
	for b in _buttons:
		UITheme.animate_in(b, 0.12 + i * 0.03, 0.96)
		i += 1
	if not bool(Profile.data.flags.get("tutorial_done", false)) and not "--no-help" in OS.get_cmdline_user_args():
		_show_welcome()
	_setup_help()
	if "--open-gear" in OS.get_cmdline_user_args():   # screenshot helper: the gear menu open
		get_tree().create_timer(1.0).timeout.connect(_toggle_gear_menu)


# ---------------------------------------------------------------- top bar

func _build_top_bar() -> void:
	var bar := Panel.new()
	bar.name = "TopBar"
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = TOP_H
	var s := UITheme.panel_style(UITheme.BAR_BG, Color(1, 1, 1, 0.1), 0, 0, 0)
	s.border_width_bottom = 2
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 12
	bar.add_theme_stylebox_override("panel", s)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(bar)
	# Red broadcast slashes behind the logo.
	for k in 3:
		var sl := Panel.new()
		var ss := StyleBoxFlat.new()
		ss.bg_color = UITheme.SCARLET if k != 1 else UITheme.SCARLET_DEEP
		ss.skew = Vector2(-0.42, 0)
		sl.add_theme_stylebox_override("panel", ss)
		sl.position = Vector2(-28 + k * 26, 0)
		sl.size = Vector2(16 if k != 0 else 30, TOP_H)
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(sl)
	var hb := HBoxContainer.new()
	hb.name = "TopRow"
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 64
	hb.offset_right = -22
	hb.add_theme_constant_override("separation", 26)
	bar.add_child(hb)

	# Logo.
	var logo_path := "res://assets/textures/logo/logo.png"
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.name = "Logo"
		logo.texture = load(logo_path)
		logo.custom_minimum_size = Vector2(190, TOP_H - 6)
		logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(logo)
	else:
		var lt := UITheme.title("BASEBALL DRAW", 40, UITheme.OFFWHITE)
		lt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(lt)
	hb.add_child(UITheme.vsep(56))

	# Manager: division emblem, name, division and RP.
	var d: Dictionary = Profile.data
	var div := Profile.division()
	var mgr := HBoxContainer.new()
	mgr.name = "ProfilePanel"
	mgr.add_theme_constant_override("separation", 12)
	mgr.mouse_filter = Control.MOUSE_FILTER_PASS
	mgr.tooltip_text = "%s division  ·  %d rank points" % [div.name, int(d.rp)]
	var emblem_path := "res://assets/textures/ui/rank_%s.png" % div.id
	if ResourceLoader.exists(emblem_path):
		var em := TextureRect.new()
		em.texture = load(emblem_path)
		em.custom_minimum_size = Vector2(62, 62)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		em.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mgr.add_child(em)
	var nb := VBoxContainer.new()
	nb.alignment = BoxContainer.ALIGNMENT_CENTER
	nb.add_theme_constant_override("separation", -4)
	nb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := UITheme.label(str(d.name).to_upper(), 34, UITheme.OFFWHITE, UITheme.font_display())
	nl.name = "ManagerName"
	nb.add_child(nl)
	var dl := UITheme.label("%s DIVISION  ·  %s RP" % [str(div.name).to_upper(), UITheme.format_int(int(d.rp))], UITheme.FS_BODY, Color(div.color).lightened(0.3), UITheme.font_body_bold())
	dl.name = "DivisionText"
	nb.add_child(dl)
	mgr.add_child(nb)
	hb.add_child(mgr)
	hb.add_child(UITheme.vsep(56))

	# LEVEL n, XP numbers and the bar.
	var lv := VBoxContainer.new()
	lv.name = "LevelBlock"
	lv.alignment = BoxContainer.ALIGNMENT_CENTER
	lv.add_theme_constant_override("separation", 4)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv.custom_minimum_size = Vector2(300, 0)
	var need := Profile.xp_to_next(int(d.level))
	var maxed := int(d.level) >= Profile.MAX_ACCOUNT_LEVEL
	lv.tooltip_text = "Account level: unlocks defenders, stadiums and card slots" if maxed \
		else "%s / %s XP to level %d" % [UITheme.format_int(int(d.xp)), UITheme.format_int(need), int(d.level) + 1]
	lv.mouse_filter = Control.MOUSE_FILTER_PASS
	var lrow := HBoxContainer.new()
	lrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ll := UITheme.label("LEVEL %d" % int(d.level), 32, UITheme.GREEN, UITheme.font_display())
	ll.name = "LevelText"
	ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lrow.add_child(ll)
	var xl := UITheme.label("MAX LEVEL" if maxed else "%s / %s XP" % [UITheme.format_int(int(d.xp)), UITheme.format_int(need)], 28, UITheme.OFFWHITE, UITheme.font_header())
	xl.name = "XPText"
	xl.size_flags_vertical = Control.SIZE_SHRINK_END
	lrow.add_child(xl)
	lv.add_child(lrow)
	var xp := UITheme.bar(UITheme.GREEN, 14, float(need), float(need) if maxed else float(int(d.xp)))
	xp.name = "LevelBar"
	xp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv.add_child(xp)
	hb.add_child(lv)
	hb.add_child(UITheme.vsep(56))

	# Coins, stars, cards owned.
	var owned := 0
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned += 1
	var cur := HBoxContainer.new()
	cur.name = "Currencies"
	cur.add_theme_constant_override("separation", 26)
	for c in [["coin", UITheme.format_int(int(d.coins)), UITheme.GOLD, "Coins", "CoinsValue"],
			["star", UITheme.format_int(int(d.stars)), UITheme.STAR, "Stars", "StarsValue"],
			["collection", "%d/%d" % [owned, DB.card_order.size()], UITheme.OFFWHITE, "Cards collected", "CardsValue"]]:
		var cb := HBoxContainer.new()
		cb.add_theme_constant_override("separation", 8)
		cb.tooltip_text = c[3]
		cb.mouse_filter = Control.MOUSE_FILTER_PASS
		var ic := UITheme.icon_rect(c[0], 34, c[2])
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.add_child(ic)
		var vl := UITheme.label(c[1], 38, c[2], UITheme.font_header())
		vl.name = c[4]
		vl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.add_child(vl)
		cur.add_child(cb)
	hb.add_child(cur)
	hb.add_child(UITheme.vsep(56))

	# "?" and the settings gear (its menu holds Settings, Practice and Exit).
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 12)
	icons.name = "TopIcons"
	hb.add_child(icons)
	icons.add_child(Control.new())   # placeholder for the "?" (added by _setup_help)
	_gear_btn = UITheme.icon_button("settings", "Settings, Practice and Exit (Esc)", UITheme.GOLD, 62)
	_gear_btn.name = "GearButton"
	_gear_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_gear_btn.add_theme_constant_override("icon_max_width", 34)
	_gear_btn.pressed.connect(_toggle_gear_menu)
	icons.add_child(_gear_btn)


## The gear's drop-down: SETTINGS, PRACTICE, EXIT (and the version line). Esc toggles it too.
func _toggle_gear_menu() -> void:
	if _gear_menu and is_instance_valid(_gear_menu):
		_close_gear_menu()
		return
	var catcher := Control.new()   # a click anywhere else closes the menu
	catcher.name = "GearMenu"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_gear_menu())
	ui.add_child(catcher)
	_gear_menu = catcher
	var p := UITheme.card_panel(Color(CARD_GOLD, 0.7), 12, Color(0.04, 0.07, 0.13, 0.98), 2)
	p.name = "GearPanel"
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -20
	p.offset_left = -20 - 300
	p.offset_top = TOP_H + 8
	p.offset_bottom = TOP_H + 8
	p.custom_minimum_size = Vector2(300, 0)
	catcher.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var first: Button = null
	for t in [["SETTINGS", "settings", UITheme.BLUE, "Display, graphics, audio, controls", func() -> void: Router.goto("settings")],
			["PRACTICE", "practice", UITheme.PURPLE, "Test cards and runners freely. No rewards.", func() -> void: Session.start(Session.new_run_config("practice"))],
			["EXIT GAME", "exit", UITheme.SCARLET, "Save and quit to desktop", func() -> void:
				Profile.save_now()
				get_tree().quit()]]:
		var b := UITheme.button(t[0], "danger" if t[0] == "EXIT GAME" else "secondary", UITheme.FS_LEAD, t[1], t[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 52)
		b.tooltip_text = t[3]
		b.name = {"SETTINGS": "SettingsButton", "PRACTICE": "PracticeButton", "EXIT GAME": "ExitButton"}[t[0]]
		b.pressed.connect(t[4])
		vb.add_child(b)
		if first == null:
			first = b
	var ver := UITheme.label("v%s  ·  Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], UITheme.FS_MIN, Color(1, 1, 1, 0.45), UITheme.font_body_bold())
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(ver)
	UITheme.animate_in(p, 0.0, 0.94)
	Audio.ui("ui_toggle")
	first.grab_focus()


func _close_gear_menu() -> void:
	if _gear_menu and is_instance_valid(_gear_menu):
		_gear_menu.queue_free()
	_gear_menu = null
	if _gear_btn and is_instance_valid(_gear_btn):
		_gear_btn.grab_focus()


# ---------------------------------------------------------------- hero block

func _build_hero() -> void:
	var hero_box := VBoxContainer.new()
	hero_box.name = "HubLeft"
	hero_box.position = Vector2(HERO_X, TOP_H + 30)
	hero_box.custom_minimum_size = Vector2(HERO_W, 0)
	hero_box.add_theme_constant_override("separation", 20)
	ui.add_child(hero_box)
	var rib := UITheme.slant_ribbon("BROADCAST MATCHDAY", "", 34, UITheme.SCARLET, true)
	rib.name = "BroadcastRibbon"
	rib.custom_minimum_size = Vector2(0, 54)
	rib.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hero_box.add_child(rib)

	# The selected mode as a huge two-line title, a gold swoosh, then "STADIUM · DIFFICULTY".
	var title := VBoxContainer.new()
	title.name = "HeroTitle"
	title.add_theme_constant_override("separation", -26)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_box.add_child(title)
	_title_top = _title_label(66)
	_title_top.name = "HeroTitleTop"
	title.add_child(_title_top)
	_title_main = _title_label(124)
	_title_main.name = "HeroTitleMain"
	title.add_child(_title_main)
	var sw_box := Control.new()
	sw_box.custom_minimum_size = Vector2(HERO_W, 14)
	sw_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_box.add_child(sw_box)
	_title_swoosh = Panel.new()
	var sws := StyleBoxFlat.new()
	sws.bg_color = UITheme.GOLD
	sws.skew = Vector2(-0.8, 0)
	sws.set_corner_radius_all(6)
	sws.corner_radius_top_left = 2
	_title_swoosh.add_theme_stylebox_override("panel", sws)
	_title_swoosh.position = Vector2(18, -6)
	_title_swoosh.size = Vector2(HERO_W * 0.7, 9)
	_title_swoosh.rotation = deg_to_rad(-1.6)
	_title_swoosh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw_box.add_child(_title_swoosh)
	_venue = UITheme.label("", 28, UITheme.OFFWHITE, UITheme.font_spaced(UITheme.font_body_bold(), 7))
	_venue.name = "HeroVenue"
	_venue.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_venue.add_theme_constant_override("shadow_offset_x", 2)
	_venue.add_theme_constant_override("shadow_offset_y", 2)
	var vm := MarginContainer.new()
	vm.add_theme_constant_override("margin_left", 30)
	vm.add_child(_venue)
	hero_box.add_child(vm)

	hero_box.add_child(_build_status_chips())

	# CONTINUE RUN (only when a run is saved).
	if Profile.has_saved_run():
		hero_box.add_child(_build_continue())
	# PLAY.
	var hero := UITheme.button("PLAY", "primary", 104, "play", UITheme.SCARLET)
	hero.name = "PlayButton"
	hero.alignment = HORIZONTAL_ALIGNMENT_LEFT
	hero.custom_minimum_size = Vector2(HERO_W, 140)
	hero.add_theme_constant_override("icon_max_width", 76)
	hero.add_theme_constant_override("h_separation", 26)
	hero.add_theme_constant_override("outline_size", 8)
	hero.add_theme_color_override("font_outline_color", Color(0.25, 0.0, 0.02, 0.55))
	for st in ["normal", "hover", "pressed", "focus"]:
		var s: StyleBoxFlat = hero.get_theme_stylebox(st).duplicate()
		s.content_margin_left = 64
		s.skew = Vector2(-0.16, 0)
		s.set_corner_radius_all(6)
		if st != "focus":
			s.bg_color = UITheme.SCARLET.darkened(0.06) if st == "normal" else s.bg_color
			s.border_width_right = 16
			s.border_width_bottom = 5
			s.border_color = UITheme.GOLD if st != "pressed" else UITheme.GOLD.lightened(0.3)
			s.shadow_color = Color(0, 0, 0, 0.5)
			s.shadow_size = 12
			s.shadow_offset = Vector2(0, 5)
		else:
			s.set_border_width_all(4)
			s.border_color = Color.WHITE
		hero.add_theme_stylebox_override(st, s)
	hero.pressed.connect(func() -> void:
		Session.menu_tab = "mode:" + _selected_mode()
		Router.goto("play_menu"))
	if Profile.is_first_win_today():
		var fw := UITheme.label("2× COINS ON TODAY'S FIRST WIN", UITheme.FS_MIN, Color(1, 0.9, 0.7), UITheme.font_body_bold())
		fw.name = "FirstWinBadge"
		fw.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		fw.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		fw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fw.offset_right = -44
		fw.offset_bottom = -12
		fw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hero.add_child(fw)
	hero_box.add_child(hero)
	_buttons.append(hero)
	_hero = hero
	hero_box.add_child(_build_mode_switch())
	_refresh_hero()


func _title_label(size: int) -> Label:
	var l := UITheme.label("", size, UITheme.OFFWHITE, UITheme.font_display())
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.07, 0.95))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 4)
	l.add_theme_constant_override("shadow_offset_y", 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Splits a mode name into the title's small top line and big main line:
## "The Endless Ninth" -> ["THE", "ENDLESS NINTH"], "Standard Siege" -> ["STANDARD", "SIEGE"].
static func title_lines(mode_name: String) -> Array:
	var words := mode_name.to_upper().split(" ", false)
	if words.size() <= 1:
		return ["", mode_name.to_upper()]
	return [words[0], " ".join(words.slice(1))]


## Win streak flame, the Season tier chip and (when it is open) the promotion chip.
func _build_status_chips() -> Control:
	var row := HFlowContainer.new()
	row.name = "StatusChips"
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 8)
	var flame := UITheme.flame_chip(Profile.win_streak(), Profile.streak_bonus(), UITheme.FS_MIN, false, true)
	flame.custom_minimum_size = Vector2(0, 40)
	row.add_child(flame)
	_season_bar = _build_season_chip()
	row.add_child(_season_bar)
	_buttons.append(_season_bar)
	if Profile.promotion_available():
		var pb := UITheme.button("PROMOTION  ▶", "primary", UITheme.FS_SMALL, "crown", UITheme.GOLD.darkened(0.3))
		pb.name = "PromotionButton"
		pb.custom_minimum_size = Vector2(0, 40)
		pb.tooltip_text = "You have enough rank points for %s: win the Promotion Challenge to move up a division" % str(Profile.next_division().get("name", ""))
		pb.pressed.connect(func() -> void:
			Session.menu_tab = "ranked"
			Router.goto("play_menu"))
		row.add_child(pb)
		_buttons.append(pb)
	return row


## Season Pass chip: season, tier, a mini XP bar and a claim badge. Opens the Season screen.
func _build_season_chip() -> Button:
	var cur := Season.current()
	var prog := Season.tier_progress()
	var tier := int(prog.get("tier", 0))
	var b := Button.new()
	b.name = "SeasonBar"
	b.custom_minimum_size = Vector2(196, 40)
	var accent := UITheme.PURPLE.lightened(0.2)
	var mk := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		var s := UITheme.panel_style(bg, border, bw, 20, 0)
		s.content_margin_left = 12
		s.content_margin_right = 12
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color(0.1, 0.06, 0.18, 0.92), Color(accent, 0.6), 1))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.16, 0.09, 0.28, 0.96), accent, 2))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0.2, 0.1, 0.34, 0.98), Color.WHITE, 2))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.9), 2))
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -7.0))
	b.pressed.connect(func() -> void:
		Audio.ui("ui_click", -2.0)
		Router.open("season"))
	UITheme.add_feedback(b, 1.03)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14
	hb.offset_right = -14
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var tl := UITheme.label("SEASON", UITheme.FS_MIN, Color(accent, 0.95), UITheme.font_body_bold())
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tl)
	var tn := UITheme.label("TIER %d" % tier, UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header())
	tn.name = "SeasonTier"
	tn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(tn)
	var need := maxi(1, int(prog.get("xp_need", Season.XP_PER_TIER)))
	var bar := UITheme.bar(accent, 8, float(need), float(int(prog.get("xp_in", 0))))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(bar)
	var sname := str(cur.get("name", "Season"))
	if str(cur.get("theme", "")) != "":
		sname += ": " + str(cur.theme)
	var maxed := tier >= Season.TIERS
	b.tooltip_text = "%s  ·  %d / %d XP to %s%s\nSeason Pass: claim a reward at every tier. Games, wins, missions and the Daily Challenge give season XP." % [
		sname, int(prog.get("xp_in", 0)), need, "the next bonus Pro Pack" if maxed else "tier %d" % (tier + 1),
		("  ·  ends in %s" % Season.countdown_text(int(cur.seconds_left))) if int(cur.get("seconds_left", 0)) > 0 else ""]
	var n := Season.claimable().size()
	if n > 0:
		UITheme.corner_badge(b, "%d TO CLAIM" % n, UITheme.GOLD.darkened(0.35))
		var pulse := b.create_tween().set_loops()
		pulse.tween_property(b, "self_modulate", Color(1.2, 1.12, 0.9), 0.8).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(b, "self_modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	return b


## The green CONTINUE RUN card: mode, inning and stadium of the saved run, with a chevron.
func _build_continue() -> Button:
	var cr: Dictionary = Profile.data.current_run
	var b := UITheme.button("CONTINUE RUN", "secondary", 36, "save", UITheme.GREEN)
	b.name = "ContinueRun"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(HERO_W, 86)
	b.add_theme_font_override("font", UITheme.font_display())
	b.add_theme_constant_override("icon_max_width", 40)
	b.add_theme_constant_override("h_separation", 16)
	b.add_theme_color_override("icon_normal_color", UITheme.GREEN)
	b.add_theme_color_override("icon_hover_color", Color.WHITE)
	b.add_theme_color_override("icon_focus_color", UITheme.GREEN)
	for st in ["normal", "hover", "pressed", "focus"]:
		var s: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
		s.content_margin_left = 24
		s.content_margin_top = 10
		s.content_margin_bottom = 36
		s.set_corner_radius_all(10)
		if st == "normal":
			s.bg_color = Color(0.03, 0.12, 0.09, 0.94)
			s.border_color = Color(UITheme.GREEN, 0.9)
			s.set_border_width_all(3)
		elif st == "hover":
			s.bg_color = Color(0.05, 0.24, 0.15, 0.98)
			s.border_color = UITheme.GREEN.lightened(0.3)
			s.set_border_width_all(3)
		b.add_theme_stylebox_override(st, s)
	b.tooltip_text = "Saved %s" % str(cr.get("saved_at", "")).replace("T", " ")
	var sub := UITheme.label("%s  ·  Inning %d  ·  %s" % [DB.mode(str(cr.get("mode_id", "standard"))).get("name", "Game"),
		int(cr.get("inning", 1)), DB.arena(str(cr.get("arena_id", "steel_yard"))).get("name", "")], UITheme.FS_BODY, Color(0.78, 1.0, 0.88), UITheme.font_body_bold())
	sub.name = "ContinueDetail"
	sub.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sub.offset_left = 80
	sub.offset_top = -40
	sub.offset_bottom = -12
	sub.clip_text = true
	sub.offset_right = -60
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub)
	var chev := UITheme.label("›", 64, UITheme.OFFWHITE, UITheme.font_header())
	chev.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	chev.offset_left = -46
	chev.offset_right = -18
	chev.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(chev)
	b.pressed.connect(func() -> void: Session.continue_saved_run())
	_continue_btn = b
	_buttons.append(b)
	return b


# ---------------------------------------------------------------- PLAY + quick mode switch

## The mode PLAY opens with (the last one played, or the one picked on the quick switch).
func _selected_mode() -> String:
	var last := str(Profile.data.flags.get("last_mode", "standard"))
	if not DB.mode(last).has("name") or last in ["practice", "daily", "daily_long"] or MenuScreen.mode_locked_reason(last) != "":
		last = "standard"
	return last


func _refresh_hero() -> void:
	var m := _selected_mode()
	var lines := title_lines(str(DB.mode(m).get("name", "Game")))
	if _title_top:
		_title_top.text = lines[0]
		_title_top.visible = lines[0] != ""
		_title_main.text = lines[1]
		# Shrink the big line until it fits the hero column.
		var size := 124
		var f := UITheme.font_display()
		while size > 64 and f.get_string_size(lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > HERO_W - 20:
			size -= 4
		_title_main.add_theme_font_size_override("font_size", size)
		_title_swoosh.size.x = clampf(f.get_string_size(lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x - 10, 200, HERO_W - 30)
	if _venue:
		_venue.text = "%s  ·  %s" % [str(DB.arena(str(Profile.data.arena)).get("name", "")).to_upper().trim_prefix("THE "),
			str(DB.difficulty(str(Profile.data.difficulty)).get("name", "")).to_upper()]
	if _hero:
		var rec := _mode_record_text(m)
		_hero.tooltip_text = "Play %s%s" % [DB.mode(m).get("name", "Game"), ("  ·  " + rec) if rec != "" else ""]
	for id in _mode_chips.keys():
		(_mode_chips[id] as Button).set_pressed_no_signal(id == m)


## A row of four mode chips under PLAY: picking one changes what PLAY opens with.
func _build_mode_switch() -> Control:
	var row := HBoxContainer.new()
	row.name = "ModeSwitch"
	row.add_theme_constant_override("separation", 10)
	for qm in QUICK_MODES:
		var id: String = qm[0]
		if not DB.mode(id).has("name"):
			continue
		var lock := MenuScreen.mode_locked_reason(id)
		var b := UITheme.button(qm[1], "secondary", 23, qm[2], UITheme.SCARLET)
		b.name = "Mode_" + id
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1.25 if id == "boss_rush" else 1.0
		b.custom_minimum_size = Vector2(0, 54)
		b.add_theme_font_override("font", UITheme.font_header())
		b.add_theme_constant_override("icon_max_width", 24)
		b.add_theme_constant_override("h_separation", 8)
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var s: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			s.content_margin_left = 12
			s.content_margin_right = 12
			s.skew = Vector2(-0.16, 0)
			s.set_corner_radius_all(4)
			if st == "normal":
				s.bg_color = Color(0.04, 0.07, 0.13, 0.92)
				s.border_color = Color(1, 1, 1, 0.22)
			if st == "pressed":
				s.bg_color = UITheme.SCARLET.darkened(0.12)
				s.border_color = UITheme.SCARLET.lightened(0.45)
			b.add_theme_stylebox_override(st, s)
		b.add_theme_stylebox_override("hover_pressed", b.get_theme_stylebox("pressed"))
		var rec := _mode_record_text(id)
		b.tooltip_text = "%s: %s%s" % [DB.mode(id).name, DB.mode(id).get("text", ""), ("\n" + rec) if rec != "" else ""]
		if lock != "":
			b.disabled = true
			b.tooltip_text = "%s is locked: %s" % [DB.mode(id).name, lock]
		b.pressed.connect(func() -> void:
			Profile.data.flags["last_mode"] = id
			Profile.save_soon()
			Audio.ui("ui_toggle")
			_refresh_hero())
		row.add_child(b)
		_mode_chips[id] = b
		_buttons.append(b)
	return row


## "Best: 6,850" style line for a mode's record (empty when none).
static func _mode_record_text(id: String) -> String:
	var rec: Dictionary = Profile.data.get("records", {})
	match id:
		"endless":
			return "Best: inning %d" % int(rec.best_endless_inning) if int(rec.get("best_endless_inning", 0)) > 0 else ""
		"boss_rush":
			if float(rec.get("best_time_boss_rush", 0.0)) > 0.0:
				return "Best time: %s" % Rewards.time_text(float(rec.best_time_boss_rush))
	var best := int(rec.get("best_score_" + id, 0))
	return "Best score: %s" % UITheme.format_int(best) if best > 0 else ""


# ---------------------------------------------------------------- guidance (Update 6)

## True until the player has finished a game (advanced tiles are toned down until then).
func _new_player() -> bool:
	return (Profile.data.history as Array).is_empty()


func _trait_ready() -> bool:
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id) and Profile.pending_traits(id) > 0:
			return true
	return false


## Tones a tile down (still clickable) and says when it becomes useful.
func _deemphasise(b: Button, why: String) -> void:
	b.self_modulate = Color(1, 1, 1, 0.55)
	b.tooltip_text = why
	b.mouse_entered.connect(func() -> void: b.self_modulate = Color.WHITE)
	b.mouse_exited.connect(func() -> void: b.self_modulate = Color(1, 1, 1, 0.55))
	b.focus_entered.connect(func() -> void: b.self_modulate = Color.WHITE)
	b.focus_exited.connect(func() -> void: b.self_modulate = Color(1, 1, 1, 0.55))


## Tips: the "?" button in the top bar and the first-visit hints, which wait until the first game
## is done (the welcome panel covers the very first launch).
func _setup_help() -> void:
	var targets := func() -> Dictionary:
		var t := {"menu_home": _hero}
		var named := {"menu_daily": "DailyPanel", "menu_login": "LoginPanel", "menu_promotion": "PromotionButton", "menu_streak": "StreakFlame"}
		for k in named.keys():
			var n: Node = ui.find_child(named[k], true, false) if ui else null
			if n:
				t[k] = n
		if _season_bar and is_instance_valid(_season_bar):
			t["menu_season"] = _season_bar
		if _shop_tile and is_instance_valid(_shop_tile):
			t["menu_shop"] = _shop_tile
		return t
	var extra := func() -> Array:
		var e: Array = []
		if Profile.promotion_available():
			e.append("menu_promotion")
		if Profile.win_streak() > 0:
			e.append("menu_streak")
		if not _free_gift().is_empty():
			e.append("menu_shop")
		return e
	var help := Hints.help_button(self, "main_menu", targets, extra)
	help.custom_minimum_size = Vector2(62, 62)
	var icons: Node = ui.find_child("TopIcons", true, false)
	if icons:
		var ph := icons.get_child(0)
		icons.add_child(help)
		icons.move_child(help, 0)
		ph.queue_free()
	UITheme.animate_in(help, 0.5)
	if bool(Profile.data.flags.get("tutorial_done", false)) and not _new_player():
		Hints.first_visit(self, "main_menu", targets, extra.call(), 1.2)


# ---------------------------------------------------------------- TODAY panel

func _build_today() -> void:
	var bg := Panel.new()
	bg.name = "TodayBackdrop"
	bg.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	bg.offset_left = -TODAY_W
	bg.offset_top = TOP_H
	bg.offset_bottom = -BOTTOM_H
	var bs := UITheme.panel_style(UITheme.TODAY_BG, Color(1, 1, 1, 0.08), 0, 0, 0)
	bs.border_width_left = 2
	bg.add_theme_stylebox_override("panel", bs)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(bg)
	_right = VBoxContainer.new()
	_right.name = "HubRight"
	_right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_right.offset_left = 22
	_right.offset_right = -22
	_right.offset_top = 16
	_right.offset_bottom = -14
	_right.add_theme_constant_override("separation", 12)
	bg.add_child(_right)
	_build_right(true)


## Builds (or rebuilds after a claim) the TODAY column.
func _build_right(animate := false) -> void:
	for c in _right.get_children():
		_right.remove_child(c)
		c.queue_free()
	var blocks: Array[Control] = []
	var head := UITheme.slant_ribbon("TODAY", "calendar", 40, UITheme.SCARLET, false, 2)
	head.name = "TodayHeader"
	head.custom_minimum_size = Vector2(0, 58)
	var head_row := HBoxContainer.new()   # the ribbon fills the width, slashes at the right
	head_row.add_child(head)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	(head.get_node("Ribbon") as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blocks.append(head_row)
	blocks.append(_build_daily_panel())
	blocks.append(_build_missions_panel())
	blocks.append(_build_login_panel())
	var k := 0
	for b in blocks:
		_right.add_child(b)
		if b != head_row:
			b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if animate:
			UITheme.animate_in(b, 0.25 + k * 0.08)
		k += 1


## The Shop's free gift offer when it can still be taken today ({} otherwise).
static func _free_gift() -> Dictionary:
	if not Shop.gift_available():
		return {}
	for o in Shop.offers():
		if typeof(o) == TYPE_DICTIONARY and str(o.get("kind", "")) == "gift":
			return o
	return {}


## A TODAY card: navy, a gold border (brighter when something is waiting), and a header row with
## an icon, the gold title and whatever goes on the right (badge, button).
func _today_card(card_name: String, icon: String, title: String, hot: bool) -> Array:
	var p := PanelContainer.new()
	p.name = card_name
	var s := UITheme.panel_style(UITheme.TODAY_CARD_BG, Color(CARD_GOLD, 0.95 if hot else 0.4), 3 if hot else 2, 12, 0)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 10
	s.content_margin_bottom = 12
	if hot:
		s.shadow_color = Color(CARD_GOLD, 0.16)
		s.shadow_size = 10
	p.add_theme_stylebox_override("panel", s)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var ib := PanelContainer.new()   # the icon on a small gold-edged tile
	ib.add_theme_stylebox_override("panel", UITheme.panel_style(Color(CARD_GOLD, 0.14), Color(CARD_GOLD, 0.6), 2, 8, 5))
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(UITheme.icon_rect(icon, 30, CARD_GOLD))
	head.add_child(ib)
	var tl := UITheme.label(title, 36, CARD_GOLD, UITheme.font_display())
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	tl.add_theme_constant_override("shadow_offset_x", 2)
	tl.add_theme_constant_override("shadow_offset_y", 2)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(tl)
	return [p, vb, head]


## REWARDS strip at the foot of a TODAY card: [[icon, text, colour, done], ...].
func _rewards_strip(strip_name: String, parts: Array, tip: String) -> Control:
	var p := PanelContainer.new()
	p.name = strip_name
	var s := UITheme.panel_style(UITheme.STRIP_BG, Color(CARD_GOLD, 0.22), 1, 8, 0)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", s)
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(hb)
	var lead := HBoxContainer.new()
	lead.add_theme_constant_override("separation", 8)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.add_child(UITheme.icon_rect("gift", 26, CARD_GOLD))
	lead.add_child(UITheme.label("REWARDS", 26, CARD_GOLD, UITheme.font_header()))
	hb.add_child(lead)
	for part in parts:
		hb.add_child(UITheme.vsep(30, 0.18))
		var c := HBoxContainer.new()
		c.add_theme_constant_override("separation", 6)
		c.alignment = BoxContainer.ALIGNMENT_CENTER
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var done: bool = part.size() > 3 and bool(part[3])
		var col: Color = part[2] if not done else UITheme.MUTED
		var ic := UITheme.icon_rect("check" if done else str(part[0]), 26, UITheme.GREEN if done else col)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		c.add_child(ic)
		c.add_child(UITheme.label(str(part[1]), 28, col, UITheme.font_header()))
		hb.add_child(c)
	return p


# ---------------------------------------------------------------- daily challenge

## Daily Challenge card: today's rules, streak, countdown, PLAY DAILY and what it pays (coins and
## a pack for the first game of the day, another pack for the first win).
func _build_daily_panel() -> Control:
	var rules := DailyChallenge.today_rules()
	var played := DailyChallenge.played()
	var parts := _today_card("DailyPanel", "calendar", "DAILY CHALLENGE", not played)
	var p: PanelContainer = parts[0]
	var vb: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	var bd := UITheme.badge("NEW TODAY" if not played else "BEST %s" % UITheme.format_int(DailyChallenge.best_score()),
		TODAY_ACCENT.darkened(0.15) if not played else Color(0.13, 0.4, 0.25), UITheme.FS_SMALL)
	bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bd)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var md := DailyChallenge.modifier_def(str(rules.modifier))
	var sub := UITheme.label("%s · %d innings · %s" % [DB.difficulty(str(rules.difficulty)).name, int(rules.innings), str(md.get("name", ""))],
		UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_body_bold())
	sub.name = "DailyRules"
	sub.clip_text = true
	sub.tooltip_text = str(md.get("text", ""))
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(sub)
	var streak := DailyChallenge.current_streak()
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	st.add_child(UITheme.icon_rect("fire", 22, TODAY_ACCENT.lightened(0.2)))
	st.add_child(UITheme.label("%d-day streak" % streak if streak > 0 else "Start a streak today", UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold()))
	info.add_child(st)
	_daily_countdown = UITheme.label("New challenge in %s" % DailyChallenge.countdown_text(), UITheme.FS_SMALL, Color(0.6, 0.78, 1.0), UITheme.font_body_bold())
	info.add_child(_daily_countdown)
	var go := UITheme.button("PLAY DAILY", "primary", 30, "play", TODAY_ACCENT.darkened(0.12))
	go.name = "DailyButton"
	go.custom_minimum_size = Vector2(210, 60)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.tooltip_text = "Open today's Daily Challenge on the Play screen"
	UITheme.skew_button(go, -0.12)
	go.pressed.connect(func() -> void:
		Session.menu_tab = "daily"
		Router.goto("play_menu"))
	row.add_child(go)
	_buttons.append(go)
	# What today's Daily pays (ticked off once taken).
	var rw := DailyChallenge.rewards()
	var rec := DailyChallenge.day_record(DailyChallenge.today())
	var first_done := bool(rec.get("rewarded", false))
	var win_done := bool(rec.get("win_rewarded", false))
	var strip: Array = [["coin", UITheme.format_int(int(rw.get("first_coins", 0))), UITheme.GOLD, first_done]]
	for pk in [[str(rw.get("first_pack", "rookie")), first_done, ""], [str(rw.get("win_pack", "pro")), win_done, " WIN"]]:
		var pd := DB.pack(pk[0])
		strip.append(["gift", str(pd.get("name", pk[0])).replace(" Pack", "").to_upper() + pk[2], Color(str(pd.get("color", "#2F7BE0"))).lightened(0.35), pk[1]])
	vb.add_child(_rewards_strip("DailyRewards", strip, "First game today: %s coins and a %s. First win today: a %s." % [
		UITheme.format_int(int(rw.get("first_coins", 0))), DB.pack(str(rw.get("first_pack", "rookie"))).get("name", "pack"), DB.pack(str(rw.get("win_pack", "pro"))).get("name", "pack")]))
	if not played:
		var pulse := p.create_tween().set_loops()
		pulse.tween_property(p, "self_modulate", Color(1.12, 1.06, 0.95), 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(p, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return p


func _update_countdowns(delta: float) -> void:
	_countdown_t -= delta
	if _countdown_t > 0.0:
		return
	_countdown_t = 1.0
	if _daily_countdown and is_instance_valid(_daily_countdown):
		_daily_countdown.text = "New challenge in %s" % DailyChallenge.countdown_text()
	if _login_countdown and is_instance_valid(_login_countdown):
		_login_countdown.text = _login_sub_text()


# ---------------------------------------------------------------- missions

## Missions card: the starter step (while it runs) and today's missions, three rows with progress,
## OPEN (Progression → Missions) and a REWARDS strip with what finishing them pays.
func _build_missions_panel() -> Control:
	Missions.refresh()
	var claimable := Missions.claimable_count()
	var parts := _today_card("MissionsWidget", "target", "MISSIONS", claimable > 0)
	var vb: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	if claimable > 0:
		var cb := UITheme.badge("%d TO CLAIM" % claimable, UITheme.GOLD.darkened(0.35), UITheme.FS_SMALL)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(cb)
	var b := UITheme.button("OPEN", "secondary", UITheme.FS_BODY, "", UITheme.GOLD)
	b.name = "MissionsButton"
	b.custom_minimum_size = Vector2(96, 40)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.tooltip_text = "Progression → Missions"
	b.pressed.connect(func() -> void:
		Session.menu_tab = "missions"
		Router.goto("progression"))
	head.add_child(b)
	_buttons.append(b)
	var list: Array = []
	if Missions.starter_active():
		list.append(Missions.state().starter)
	list.append_array(Missions.state().daily)
	list = list.slice(0, 3)
	var coins := 0
	var stars := 0
	var packs: Array = []
	var season_xp := 0
	var rows := VBoxContainer.new()
	rows.name = "MissionRows"
	rows.add_theme_constant_override("separation", 2)
	vb.add_child(rows)
	for i in list.size():
		var inst: Dictionary = list[i]
		if i > 0:
			rows.add_child(UITheme.hsep(0.07))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var done := Missions.is_done(inst)
		var claimed := bool(inst.claimed)
		row.add_child(UITheme.icon_rect("check" if claimed else ("gift" if done else "target"), 22,
			UITheme.GREEN if claimed else (UITheme.GOLD if done else UITheme.MUTED)))
		var t := UITheme.label(("NEW MANAGER: " if inst.kind == "starter" else "") + Missions.text(inst), UITheme.FS_BODY,
			UITheme.MUTED if claimed else UITheme.OFFWHITE, UITheme.font_body_bold())
		t.clip_text = true
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(UITheme.label("CLAIM!" if done and not claimed else ("%d/%d" % [int(inst.progress), int(inst.goal)]),
			UITheme.FS_BODY, UITheme.GOLD if done and not claimed else UITheme.OFFWHITE, UITheme.font_body_bold()))
		rows.add_child(row)
		if not claimed:
			var rw := Missions.reward(inst)
			coins += int(rw.get("coins", 0))
			stars += int(rw.get("stars", 0))
			if str(rw.get("pack", "")) != "":
				packs.append(str(rw.pack))
			season_xp += Missions.season_xp()
	var strip: Array = []
	if coins > 0:
		strip.append(["coin", UITheme.format_int(coins), UITheme.GOLD])
	if stars > 0:
		strip.append(["star", str(stars), UITheme.STAR])
	if not packs.is_empty():
		var pd := DB.pack(packs[0])
		strip.append(["gift", ("%d PACKS" % packs.size()) if packs.size() > 1 else str(pd.get("name", packs[0])).replace(" Pack", "").to_upper(),
			Color(str(pd.get("color", "#2F7BE0"))).lightened(0.35)])
	if season_xp > 0 and strip.size() < 3:
		strip.append(["progression", "%d XP" % season_xp, UITheme.PURPLE.lightened(0.3)])
	if strip.is_empty():
		strip.append(["check", "ALL CLAIMED", UITheme.GREEN])
	vb.add_child(_rewards_strip("MissionRewards", strip, "Finishing these missions pays %s%s." % [
		Missions.reward_text({"coins": coins, "stars": stars, "pack": packs[0] if not packs.is_empty() else ""}),
		("  + %d Season XP" % season_xp) if season_xp > 0 else ""]))
	return parts[0]


# ---------------------------------------------------------------- login calendar

## Seven-day login calendar: CLAIM (or CLAIMED), when the next reward comes, the login streak and
## each day's reward, with the days already claimed and today's cell.
func _build_login_panel() -> Control:
	var cal: Array = DailyRewards.calendar()
	var can := DailyRewards.can_claim()
	var parts := _today_card("LoginPanel", "calendar", "DAILY LOGIN", can)
	var p: PanelContainer = parts[0]
	var vb: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	_login_panel = p
	if can:
		var cb := UITheme.button("CLAIM", "primary", UITheme.FS_LEAD, "gift", UITheme.GREEN.darkened(0.35))
		cb.name = "LoginClaim"
		cb.custom_minimum_size = Vector2(140, 42)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.tooltip_text = "Claim today's login reward"
		cb.pressed.connect(_claim_login)
		head.add_child(cb)
		_buttons.append(cb)
	else:
		var done := UITheme.badge("CLAIMED", Color(0.13, 0.5, 0.3), UITheme.FS_SMALL)
		done.name = "LoginClaimed"
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(done)
	_login_countdown = UITheme.label(_login_sub_text(), UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	_login_countdown.name = "LoginNext"
	vb.add_child(_login_countdown)
	if cal.is_empty():
		var none := UITheme.label("Log in every day for coins, packs and stars.", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
		vb.add_child(none)
		return p
	var row := HBoxContainer.new()
	row.name = "LoginDays"
	row.add_theme_constant_override("separation", 7)
	vb.add_child(row)
	for e in cal:
		row.add_child(_login_cell(e, can))
	if can:
		var pulse := p.create_tween().set_loops()
		pulse.tween_property(p, "self_modulate", Color(1.14, 1.1, 0.94), 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(p, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return p


## "Next reward in 12h 00m · 2-day login streak" (or that today's reward is ready).
func _login_sub_text() -> String:
	var sub := "Day %d reward is ready" % DailyRewards.day() if DailyRewards.can_claim() \
		else "Next reward in %s" % UITheme.format_duration(Shop.seconds_to_refresh())
	var streak := DailyRewards.streak()
	if streak > 0:
		sub += "  ·  %d-day login streak" % streak
	return sub


func _login_cell(e: Dictionary, can: bool) -> Control:
	var day := int(e.get("day", 0))
	var claimed := bool(e.get("claimed", false))
	# The cell to claim now, or (once today's is claimed) the one tomorrow pays.
	var today := (bool(e.get("today", false)) and can) or (not can and not claimed and day == DailyRewards.day())
	var big := day == 7
	var accent := UITheme.GOLD
	var bg := Color(0.05, 0.08, 0.14, 0.95)
	var border := Color(1, 1, 1, 0.16)
	if claimed:
		bg = Color(0.05, 0.2, 0.12, 0.92)
		border = Color(UITheme.GREEN, 0.6)
	elif today:
		bg = Color(accent.darkened(0.7), 0.95)
		border = accent
	elif big:
		border = Color(accent, 0.5)
	var p := PanelContainer.new()
	p.name = "LoginDay%d" % day
	p.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 3 if today and not claimed else 2, 8, 4))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var reward: Variant = e.get("reward", {})
	var txt := str(e.get("text", DailyRewards.reward_text(reward) if typeof(reward) == TYPE_DICTIONARY else ""))
	p.tooltip_text = "Day %d: %s%s" % [day, txt if txt != "" else "reward", "  (claimed)" if claimed else (("  (today)" if can else "  (next)") if today else "")]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var dl := UITheme.label("DAY %d" % day, UITheme.FS_SMALL, accent.lightened(0.2) if today and not claimed else Color(0.8, 0.86, 0.95), UITheme.font_header())
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	var parts := UITheme.reward_parts(reward)
	var part: Array = parts[0] if not parts.is_empty() else ["gift", "?", UITheme.MUTED]
	var icon := UITheme.icon_rect("check" if claimed else str(part[0]), 30, UITheme.GREEN if claimed else part[2])
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(icon)
	var amount := str(part[1])
	if amount.length() > 6:
		amount = amount.substr(0, 5)
	var al := UITheme.label(amount, UITheme.FS_SMALL, Color(0.75, 0.95, 0.82) if claimed else part[2], UITheme.font_header())
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(al)
	if today and can:
		p.resized.connect(func() -> void: p.pivot_offset = p.size * 0.5)
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "scale", Vector2(1.06, 1.06), 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	return p


## CLAIM: pays today's login reward, floats the reward up from today's cell and rebuilds TODAY.
func _claim_login() -> void:
	var day := DailyRewards.day()
	var cell: Control = _login_panel.find_child("LoginDay%d" % day, true, false) if _login_panel else null
	var origin := cell.get_global_rect().get_center() if cell else (_login_panel.get_global_rect().get_center() if _login_panel else Vector2(1600, 300))
	var r := DailyRewards.claim()   # {day, reward, granted, text, streak, best}
	if r.is_empty():
		return
	Audio.play("achievement", -3.0)
	Audio.play("coin", -6.0)
	_float_reward(origin, r.get("reward", {}))
	var txt := str(r.get("text", ""))
	Router.toast("Day %d login reward%s" % [int(r.get("day", day)), (": " + txt) if txt != "" else "!"], "achievement")
	Profile.save_soon()
	_buttons = _buttons.filter(func(b: Button) -> bool: return is_instance_valid(b) and not _right.is_ancestor_of(b))
	_build_right(false)
	_refresh_top_values()


## Coins and stars in the top bar after a claim.
func _refresh_top_values() -> void:
	var cl: Label = ui.find_child("CoinsValue", true, false)
	if cl:
		cl.text = UITheme.format_int(int(Profile.data.coins))
	var sl: Label = ui.find_child("StarsValue", true, false)
	if sl:
		sl.text = UITheme.format_int(int(Profile.data.stars))


## Reward icons float up from `origin` (screen position) and fade.
func _float_reward(origin: Vector2, r: Dictionary) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var k := 0
	for part in UITheme.reward_parts(r):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(UITheme.icon_rect(part[0], 34, part[2]))
		var l := UITheme.label("+" + str(part[1]), 34, part[2], UITheme.font_display())
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		hb.add_child(l)
		layer.add_child(hb)
		hb.position = origin + Vector2(-50 + k * 26, -20 - k * 8)
		hb.modulate.a = 0.0
		var ft := hb.create_tween()
		ft.tween_interval(k * 0.12)
		ft.set_parallel(true)
		ft.tween_property(hb, "modulate:a", 1.0, 0.12)
		ft.tween_property(hb, "position:y", hb.position.y - 90.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ft.chain().tween_property(hb, "modulate:a", 0.0, 0.3)
		k += 1
	get_tree().create_timer(1.8).timeout.connect(layer.queue_free)


# ---------------------------------------------------------------- bottom bar

## The destinations across the bottom: [text, icon, colour, action, badge, badge colour, tooltip].
func _build_bottom_bar() -> void:
	var bar := Panel.new()
	bar.name = "BottomBar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BOTTOM_H
	var s := UITheme.panel_style(UITheme.BAR_BG, Color(CARD_GOLD, 0.75), 0, 0, 0)
	s.border_width_top = 3
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 12
	bar.add_theme_stylebox_override("panel", s)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(bar)
	var hb := HBoxContainer.new()
	hb.name = "HubBottom"
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 52
	hb.offset_right = -52
	hb.offset_top = 26
	hb.offset_bottom = -22
	hb.add_theme_constant_override("separation", 14)
	bar.add_child(hb)
	var ready := 0
	for cid in DB.card_order:
		if Profile.can_upgrade_card(cid):
			ready += 1
	var gift := _free_gift()
	var tiles := [
		["CARDS & DECK", "deck", Color("#4FA3FF"), func() -> void:
			Session.menu_tab = "deck"
			Router.goto("deck_builder"),
			"REWARD!" if CollectionSets.claimable_count() > 0 else ("%d NEW" % Profile.fresh_card_count() if Profile.fresh_card_count() > 0 else ""),
			UITheme.GOLD.darkened(0.3) if CollectionSets.claimable_count() > 0 else UITheme.SCARLET, "Your collection and your 8-card deck"],
		["CARD PACKS", "gift", UITheme.GOLD, func() -> void: Router.goto("packs"),
			"%d" % Profile.pack_count() if Profile.pack_count() > 0 else "", UITheme.SCARLET, "Open your packs, or buy more"],
		["UPGRADE CARDS", "upgrade", UITheme.GREEN, func() -> void: Router.goto("card_upgrades"),
			"%d READY" % ready if ready > 0 else "", Color(0.16, 0.6, 0.35), "Level up cards with copies and coins"],
		["TEAM", "roster", Color("#4FA3FF"), func() -> void: Router.goto("roster"), "NEW TRAIT" if _trait_ready() else "",
			Color(0.16, 0.45, 0.75), "Defenders, captain, traits, gear and free agents"],
		["SHOP", "coin", UITheme.GOLD, func() -> void: Router.open("shop"), "FREE GIFT" if not gift.is_empty() else "",
			UITheme.GOLD, "Daily deals, the free gift and free agents. New deals in %s" % UITheme.format_duration(Shop.seconds_to_refresh())],
		["SCOUTING BOOK", "search", Color("#FF6B3D"), func() -> void: Router.goto("scouting_book"),
			"%d NEW" % Scouting.new_count() if Scouting.new_count() > 0 else "", UITheme.SCARLET,
			"Every runner, boss and elite: what it does and which cards stop it (%d / %d scouted)" % [Scouting.met_count(), Scouting.all_keys().size()]],
		["PROGRESSION", "progression", UITheme.GOLD, func() -> void: Router.goto("progression"), "",
			UITheme.SCARLET, "Rank, missions, achievements, stadiums, gear and history"],
	]
	var i := 0
	for t in tiles:
		if i > 0:
			hb.add_child(UITheme.vsep(44, 0.14))
		i += 1
		var b := UITheme.button(t[0], "secondary", 30, t[1], t[2])
		b.add_theme_font_override("font", UITheme.font_display())
		b.add_theme_constant_override("icon_max_width", 38)
		b.add_theme_constant_override("h_separation", 12)
		b.add_theme_color_override("icon_normal_color", t[2])
		b.add_theme_color_override("icon_focus_color", t[2])
		b.add_theme_color_override("icon_hover_color", Color.WHITE)
		b.custom_minimum_size = Vector2(0, 80)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = maxf(1.0, str(t[0]).length() / 9.0)
		b.clip_text = false
		for st in ["normal", "hover", "pressed", "focus"]:
			var bs: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			bs.skew = Vector2(-0.12, 0)
			bs.set_corner_radius_all(6)
			bs.content_margin_left = 14
			bs.content_margin_right = 14
			if st == "normal":
				bs.bg_color = Color(0.07, 0.12, 0.21, 0.96)
				bs.border_color = Color(1, 1, 1, 0.18)
				bs.border_width_bottom = 4
				bs.shadow_color = Color(0, 0, 0, 0.35)
				bs.shadow_size = 6
				bs.shadow_offset = Vector2(0, 3)
			b.add_theme_stylebox_override(st, bs)
		b.tooltip_text = t[6]
		b.pressed.connect(t[3])
		var tag: String = t[4]
		if tag != "":
			if t[0] == "SHOP":
				UITheme.top_tag(b, tag, t[5])
			else:
				UITheme.corner_badge(b, tag, t[5])
		if (t[0] == "CARD PACKS" and Profile.pack_count() > 0) or (t[0] == "SHOP" and not gift.is_empty()):
			var pulse := b.create_tween().set_loops()
			pulse.tween_property(b, "self_modulate", Color(1.22, 1.12, 0.8), 0.8).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(b, "self_modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
		hb.add_child(b)
		_buttons.append(b)
		match t[0]:
			"UPGRADE CARDS":
				if ready == 0 and _new_player():
					_deemphasise(b, "Upgrade cards with copies from packs. Open some packs first.")
			"SCOUTING BOOK":
				b.name = "ScoutingBookTile"
				if _new_player() and Scouting.met_count() == 0:
					_deemphasise(b, "Runners you meet in games are added here, with tips on how to stop them.")
			"SHOP":
				b.name = "ShopTile"
				_shop_tile = b
			"PROGRESSION":
				b.name = "ProgressionTile"
				if _new_player():
					_deemphasise(b, str(t[6]))


# ---------------------------------------------------------------- idle showcase

## Caption naming the defender who is showing off, bottom-right of the open middle.
func _build_showcase_caption() -> void:
	_caption = VBoxContainer.new()
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.offset_right = -TODAY_W - 30
	_caption.offset_bottom = -BOTTOM_H - 16
	_caption.alignment = BoxContainer.ALIGNMENT_END
	_caption.add_theme_constant_override("separation", -6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	ui.add_child(_caption)
	ui.move_child(_caption, 1)   # under the bars and panels


func _showcase() -> void:
	var idle: Array = []
	for i in models.size():
		if models[i].action == "":
			idle.append(i)
	if idle.is_empty():
		return
	var i: int = idle[randi() % idle.size()]
	var m: CharacterModel = models[i]
	var id: String = Profile.data.team[i]
	# Face the camera, then play a signature move (or celebrate for a moment).
	var to := camera.global_position - m.global_position
	var tw := create_tween()
	tw.tween_property(m, "rotation:y", atan2(to.x, to.z), 0.35).set_trans(Tween.TRANS_SINE)
	var moves: Array = ["special", "pitch", "victory"]
	var move: String = moves[randi() % moves.size()]
	tw.tween_callback(func() -> void:
		if move == "victory" or not m.has_anim(move):
			var base := m.base_anim
			m.play_base("celebrate")
			get_tree().create_timer(2.6).timeout.connect(func() -> void:
				if is_instance_valid(m):
					m.play_base(base))
		else:
			m.play_action(move, 1.0))
	_focus = m.global_position + Vector3(0, 1.6, 0)
	_focus_t = 3.4
	# Caption.
	for c in _caption.get_children():
		c.queue_free()
	var d := DB.defender(id)
	var nl := UITheme.label(str(d.name).to_upper(), 44, Color(DB.defender_accent(id)).lightened(0.3), UITheme.font_display())
	nl.add_theme_constant_override("outline_size", 8)
	nl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption.add_child(nl)
	var role: String = str(DB.roles.get(str(d.get("role", "")), {}).get("name", str(d.get("role", "")).capitalize()))
	var sub := UITheme.label("#%d  ·  %s  ·  %s" % [int(d.get("number", 0)), role, str(d.get("title", ""))], UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_caption.add_child(sub)
	var ct := _caption.create_tween()
	ct.tween_property(_caption, "modulate:a", 1.0, UITheme.T_MED)
	ct.tween_interval(2.8)
	ct.tween_property(_caption, "modulate:a", 0.0, 0.5)


## Esc closes the welcome panel first, then toggles the gear menu (Settings, Practice, Exit); a
## first direction key or d-pad press focuses PLAY so the hub can be driven without a mouse.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if _welcome_later and is_instance_valid(_welcome_later):
			Audio.ui("ui_back")
			_welcome_later.pressed.emit()
			_welcome_later = null
			return
		if _gear_menu and is_instance_valid(_gear_menu):
			Audio.ui("ui_back")
			_close_gear_menu()
		elif not Hints.is_showing():
			_toggle_gear_menu()
		return
	# Keyboard / controller: the first direction press focuses PLAY.
	if ui and MenuScreen.focus_on_nav(ui, event, _hero):
		get_viewport().set_input_as_handled()


func _show_welcome() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.08, 0.14, 0.96), Color(UITheme.SCARLET, 0.7), 2, 12, 22))
	# Bottom of the open middle of the screen (between the hero block and TODAY, above the bottom
	# bar), growing up, so it never covers TODAY or the destinations and is never cut off.
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = -330
	p.offset_top = -BOTTOM_H - 20
	p.offset_right = 290
	p.offset_bottom = -BOTTOM_H - 20
	p.custom_minimum_size = Vector2(620, 0)
	ui.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("WELCOME, MANAGER!", "info", UITheme.GOLD, 34))
	var txt := UITheme.label("Rival runners are storming the Steel Yard. Your six defenders throw at them automatically — you position the team and play ability cards to stop runners before they reach home plate.\n\nYour first game is a short Quick Defense with step-by-step tips. Finish it to earn your first card pack!", 19, UITheme.OFFWHITE)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(576, 0)
	vb.add_child(txt)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var go := UITheme.button("PLAY THE FIRST GAME", "primary", 26, "play")
	go.pressed.connect(func() -> void:
		Profile.data.flags.tutorial_done = true
		Profile.save_soon()
		var cfg := Session.new_run_config("quick")
		cfg.difficulty = "rookie"
		Session.start(cfg))
	hb.add_child(go)
	var later := UITheme.button("Look around first", "ghost", 22)
	later.tooltip_text = "Close this (Esc). PLAY starts a game whenever you are ready."
	later.pressed.connect(func() -> void:
		Profile.data.flags.tutorial_done = true
		Profile.save_soon()
		p.queue_free())
	_welcome_later = later
	hb.add_child(later)
	vb.add_child(hb)
	UITheme.animate_in(p, 0.6)
