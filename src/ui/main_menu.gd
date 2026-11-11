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
	_rookie_demo_setup()
	# Rookie Camp (Update 13): welcome-back bonus after 3+ days away (paid before the top bar is built).
	Onboarding.on_hub_open()
	UITheme.apply_debug_ui_scale(self)
	_build_ui()
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
		# Update 11: All-Stars and Hall of Famers wear their nameplate over the lineup.
		cm.show_honor_plate(DefenderLevels.honor_of(id), str(DB.defender(id).name), Profile.defender_level(id))
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
		# Bound to the menu: a scene-tree timer would outlive it and call this with a freed defender.
		var t3 := create_tween()
		t3.tween_interval(maxf(flight - 0.25, 0.0))
		t3.tween_callback(func() -> void:
			if is_instance_valid(b):
				b.play_action("catch", 1.0)))


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
	ui.name = "HubUI"
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_fit_ui()
	get_tree().root.size_changed.connect(_fit_ui)
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

	_compute_attention()
	_build_top_bar()
	_build_hero()
	_build_today()
	_build_bottom_bar()
	_build_showcase_caption()
	_build_rookie_path()
	# Staggered entrance.
	var i := 0
	for b in _buttons:
		UITheme.animate_in(b, 0.12 + i * 0.03, 0.96)
		i += 1
	if not bool(Profile.data.flags.get("tutorial_done", false)) and not "--no-help" in OS.get_cmdline_user_args():
		_show_welcome()
	_setup_help()
	# Rookie Camp popups (welcome back, picks, NEW FEATURE UNLOCKED, coach tip), then the PLAY spotlight.
	var pt := create_tween()
	pt.tween_interval(1.1)
	pt.tween_callback(_queue_popups)
	if "--open-gear" in OS.get_cmdline_user_args():   # screenshot helper: the gear menu open
		get_tree().create_timer(1.0).timeout.connect(_toggle_gear_menu)


## The hub is laid out on a canvas of at least DESIGN_SIZE: when the visible area is smaller (a
## UI scale above 100 %), the whole hub is scaled down to fit instead of overflowing.
const DESIGN_SIZE := Vector2(1920, 1080)


func _fit_ui() -> void:
	if ui == null or not is_instance_valid(ui) or get_viewport() == null:
		return
	var vis := get_viewport().get_visible_rect().size
	var f := minf(1.0, minf(vis.x / DESIGN_SIZE.x, vis.y / DESIGN_SIZE.y))
	ui.position = Vector2.ZERO
	ui.scale = Vector2(f, f)
	ui.size = vis / f


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

	_status_row = _build_status_chips()
	hero_box.add_child(_status_row)

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
	_fill_status_chips(row)
	return row


## (Re)fills the chips row: after a claim on the hub the Season chip may unlock or change its badge.
func _fill_status_chips(row: Control) -> void:
	for c in row.get_children():
		row.remove_child(c)
		c.queue_free()
	var flame := UITheme.flame_chip(Profile.win_streak(), Profile.streak_bonus(), UITheme.FS_MIN, false, true)
	flame.custom_minimum_size = Vector2(0, 40)
	row.add_child(flame)
	_season_bar = _build_season_chip() if Onboarding.is_unlocked("season") else _build_season_teaser()
	row.add_child(_season_bar)
	_buttons.append(_season_bar)
	if Profile.promotion_available() and Onboarding.is_unlocked("ranked"):
		var pb := UITheme.button("PROMOTION  ▶", "primary", UITheme.FS_SMALL, "crown", UITheme.GOLD.darkened(0.3))
		pb.name = "PromotionButton"
		pb.custom_minimum_size = Vector2(0, 40)
		pb.tooltip_text = "You have enough rank points for %s: win the Promotion Challenge to move up a division" % str(Profile.next_division().get("name", ""))
		pb.pressed.connect(func() -> void:
			Session.menu_tab = "ranked"
			Router.goto("play_menu"))
		row.add_child(pb)
		_buttons.append(pb)


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
	if n > 0 and _attn("season_claim"):
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
	if not DB.mode(last).has("name") or last in ["practice", "daily", "daily_long"] or Onboarding.mode_lock(last) != "":
		last = "standard" if Onboarding.mode_lock("standard") == "" else "quick"   # a new manager starts on Quick Defense
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
		var lock := Onboarding.mode_lock(id)
		var teaser := not Onboarding.is_unlocked(id)   # Rookie Camp: shown with a lock and its level
		var b := UITheme.button(qm[1], "secondary", 23, "lock" if teaser else qm[2], UITheme.SCARLET)
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
		if teaser:
			_lock_tag(b, id)
			b.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					_locked_pressed(id, b))
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
		if _path_panel and is_instance_valid(_path_panel):
			t["menu_path"] = _path_panel
		var wk: Node = ui.find_child("RookieWeek", true, false) if ui else null
		if wk:
			t["menu_week"] = wk
		return t
	var extra := func() -> Array:
		var e: Array = []
		if Profile.promotion_available() and Onboarding.is_unlocked("ranked"):
			e.append("menu_promotion")
		if Profile.win_streak() > 0:
			e.append("menu_streak")
		if not _free_gift().is_empty() and Onboarding.is_unlocked("shop"):
			e.append("menu_shop")
		if Onboarding.path_active():
			e.append("menu_path")
		if Onboarding.week_active():
			e.append("menu_week")
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
	# A Rookie Camp manager gets the unlock cards and the Rookie Path instead of the first-visit tips.
	if bool(Profile.data.flags.get("tutorial_done", false)) and not _new_player() and not Onboarding.is_new_player():
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
	# Rookie Camp: Rookie Week on top while it runs; the Daily Challenge and Missions only once they are
	# open (until then a COMING UP card lists what unlocks next); the login calendar shrinks to one row
	# while Rookie Week shows its own seven days. An established manager sees Daily, Missions and Login.
	var week := Onboarding.week_active()
	if week:
		blocks.append(_build_week_panel())
	if Onboarding.is_unlocked("daily"):
		blocks.append(_build_daily_panel())
	if Onboarding.is_unlocked("missions"):
		blocks.append(_build_missions_panel(2 if week else 3))
	blocks.append(_build_login_panel(week))
	if not Onboarding.is_unlocked("daily") or not Onboarding.is_unlocked("missions"):
		blocks.append(_build_coming_up())
	var k := 0
	for b in blocks:
		_right.add_child(b)
		if b != head_row and not b.has_meta("compact"):
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
	var hot := not played and _attn("daily_new")   # the badge budget may keep it quiet for a new manager
	var parts := _today_card("DailyPanel", "calendar", "DAILY CHALLENGE", hot)
	var p: PanelContainer = parts[0]
	var vb: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	var bd := UITheme.badge("NEW TODAY" if not played else "BEST %s" % UITheme.format_int(DailyChallenge.best_score()),
		(TODAY_ACCENT.darkened(0.15) if hot else Color(0.2, 0.24, 0.32)) if not played else Color(0.13, 0.4, 0.25), UITheme.FS_SMALL)
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
	if hot:
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
	if _week_status and is_instance_valid(_week_status):
		_week_status.text = Onboarding.week_status_text()


# ---------------------------------------------------------------- missions

## Missions card: the starter step (while it runs) and today's missions, three rows with progress,
## OPEN (Progression → Missions) and a REWARDS strip with what finishing them pays.
func _build_missions_panel(max_rows := 3) -> Control:
	Missions.refresh()
	# The Rookie Path has its own strip on the hub: this card lists the daily missions only.
	var path_strip := Onboarding.path_active()
	var claimable := Missions.claimable_count() - (1 if path_strip and Onboarding.path_can_claim() else 0)
	var hot := claimable > 0 and _attn("missions_claim")
	var parts := _today_card("MissionsWidget", "target", "MISSIONS", hot)
	var vb: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	if hot:
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
	if Missions.starter_active() and not path_strip:
		list.append(Missions.state().starter)
	list.append_array(Missions.state().daily)
	list = list.slice(0, max_rows)
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
func _build_login_panel(compact := false) -> Control:
	var cal: Array = DailyRewards.calendar()
	var can := DailyRewards.can_claim()
	var hot := can and _attn("login_claim")
	var parts := _today_card("LoginPanel", "calendar", "DAILY LOGIN", hot)
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
	if compact:   # Rookie Week shows its own calendar above: one row here (today's reward on the right)
		p.set_meta("compact", true)
		if not cal.is_empty():
			var e: Dictionary = cal[DailyRewards.day() - 1] if DailyRewards.day() - 1 < cal.size() else cal[0]
			var rr := UITheme.reward_row(e.get("reward", {}), UITheme.FS_SMALL)
			rr.name = "LoginToday"
			_login_countdown.text = _login_sub_text()
			var row0 := HBoxContainer.new()
			row0.add_theme_constant_override("separation", 10)
			vb.remove_child(_login_countdown)
			_login_countdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_login_countdown.clip_text = true
			row0.add_child(_login_countdown)
			row0.add_child(rr)
			vb.add_child(row0)
		if hot:
			var pulse0 := p.create_tween().set_loops()
			pulse0.tween_property(p, "self_modulate", Color(1.14, 1.1, 0.94), 0.9).set_trans(Tween.TRANS_SINE)
			pulse0.tween_property(p, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
		return p
	if cal.is_empty():
		var none := UITheme.label("Log in every day for coins, packs and stars.", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
		vb.add_child(none)
		return p
	var row := HBoxContainer.new()
	row.name = "LoginDays"
	row.add_theme_constant_override("separation", 7)
	vb.add_child(row)
	for e in cal:
		row.add_child(_login_cell(e, can, hot))
	if hot:
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


func _login_cell(e: Dictionary, can: bool, hot := true) -> Control:
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
	if today and can and hot:
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
	_refresh_hub()


## Coins and stars in the top bar after a claim.
func _refresh_top_values() -> void:
	var cl: Label = ui.find_child("CoinsValue", true, false)
	if cl:
		cl.text = UITheme.format_int(int(Profile.data.coins))
	var sl: Label = ui.find_child("StarsValue", true, false)
	if sl:
		sl.text = UITheme.format_int(int(Profile.data.stars))
	var cv: Label = ui.find_child("CardsValue", true, false)
	if cv:
		var owned := 0
		for cid in DB.card_order:
			if Profile.is_card_owned(cid):
				owned += 1
		cv.text = "%d/%d" % [owned, DB.card_order.size()]


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

## The destinations across the bottom: [text, icon, colour, action, badge, badge colour, tooltip, feature,
## attention key]. Rookie Camp: a locked feature is a teaser (lock icon, "LV n" tag, says when it opens);
## badges and pulses follow the badge budget (a new manager sees at most two attention badges at once).
func _build_bottom_bar() -> void:
	if _bottom_bar and is_instance_valid(_bottom_bar):   # rebuilt after a claim on the hub
		_bottom_bar.get_parent().remove_child(_bottom_bar)
		_bottom_bar.queue_free()
	var bar := Panel.new()
	bar.name = "BottomBar"
	_bottom_bar = bar
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
			UITheme.GOLD.darkened(0.3) if CollectionSets.claimable_count() > 0 else UITheme.SCARLET, "Your collection and your 8-card deck", "deck", "deck_new"],
		["CARD PACKS", "gift", UITheme.GOLD, func() -> void: Router.goto("packs"),
			"%d" % Profile.pack_count() if Profile.pack_count() > 0 else "", UITheme.SCARLET, "Open your packs, or buy more", "packs", "packs"],
		["UPGRADE CARDS", "upgrade", UITheme.GREEN, func() -> void: Router.goto("card_upgrades"),
			"%d READY" % ready if ready > 0 else "", Color(0.16, 0.6, 0.35), "Level up cards with copies and coins", "upgrades", "upgrade_ready"],
		["TEAM", "roster", Color("#4FA3FF"), func() -> void: Router.goto("roster"), "NEW TRAIT" if _trait_ready() else "",
			Color(0.16, 0.45, 0.75), "Defenders, captain, traits, gear and free agents", "team", "trait"],
		["SHOP", "coin", UITheme.GOLD, func() -> void: Router.open("shop"), "FREE GIFT" if not gift.is_empty() else "",
			UITheme.GOLD, "Daily deals, the free gift and free agents. New deals in %s" % UITheme.format_duration(Shop.seconds_to_refresh()), "shop", "shop_gift"],
		["SCOUTING BOOK", "search", Color("#FF6B3D"), func() -> void: Router.goto("scouting_book"),
			"%d NEW" % Scouting.new_count() if Scouting.new_count() > 0 else "", UITheme.SCARLET,
			"Every runner, boss and elite: what it does and which cards stop it (%d / %d scouted)" % [Scouting.met_count(), Scouting.all_keys().size()], "scouting", "scouting_new"],
		["PROGRESSION", "progression", UITheme.GOLD, func() -> void: Router.goto("progression"), "",
			UITheme.SCARLET, "Rank, missions, achievements, stadiums, gear and history", "", ""],
	]
	var i := 0
	for t in tiles:
		if i > 0:
			hb.add_child(UITheme.vsep(44, 0.14))
		i += 1
		var fid: String = t[7]
		var locked := fid != "" and not Onboarding.is_unlocked(fid)
		var accent: Color = UITheme.MUTED if locked else t[2]
		var b := UITheme.button(t[0], "secondary", 30, "lock" if locked else t[1], accent)
		b.add_theme_font_override("font", UITheme.font_display())
		b.add_theme_constant_override("icon_max_width", 38)
		b.add_theme_constant_override("h_separation", 12)
		b.add_theme_color_override("icon_normal_color", accent)
		b.add_theme_color_override("icon_focus_color", accent)
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
				bs.bg_color = Color(0.07, 0.12, 0.21, 0.96) if not locked else Color(0.05, 0.07, 0.11, 0.96)
				bs.border_color = Color(1, 1, 1, 0.18) if not locked else Color(1, 1, 1, 0.08)
				bs.border_width_bottom = 4
				bs.shadow_color = Color(0, 0, 0, 0.35)
				bs.shadow_size = 6
				bs.shadow_offset = Vector2(0, 3)
			b.add_theme_stylebox_override(st, bs)
		if locked:
			b.add_theme_color_override("font_color", Color(0.62, 0.67, 0.76))
			b.tooltip_text = "%s: %s.\n%s" % [Onboarding.feature(fid).get("name", t[0]), Onboarding.lock_text(fid), Onboarding.feature(fid).get("text", "")]
			b.pressed.connect(_locked_pressed.bind(fid, b))
			_lock_tag(b, fid)
		else:
			b.tooltip_text = t[6]
			b.pressed.connect(t[3])
			var tag: String = t[4]
			if tag != "" and (str(t[8]) == "" or _attn(str(t[8]))):
				if t[0] == "SHOP":
					UITheme.top_tag(b, tag, t[5])
				else:
					UITheme.corner_badge(b, tag, t[5])
				if t[0] in ["CARD PACKS", "SHOP"]:
					var pulse := b.create_tween().set_loops()
					pulse.tween_property(b, "self_modulate", Color(1.22, 1.12, 0.8), 0.8).set_trans(Tween.TRANS_SINE)
					pulse.tween_property(b, "self_modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
		hb.add_child(b)
		_buttons.append(b)
		if fid in ["deck", "packs", "upgrades", "team"]:
			b.name = "Tile_" + fid
		match t[0]:
			"UPGRADE CARDS":
				if ready == 0 and _new_player() and not locked:
					_deemphasise(b, "Upgrade cards with copies from packs. Open some packs first.")
			"SCOUTING BOOK":
				b.name = "ScoutingBookTile"
				if _new_player() and Scouting.met_count() == 0 and not locked:
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
		if _popup and is_instance_valid(_popup) and _popup_close.is_valid():   # a Rookie Camp popup: its "later" action
			Audio.ui("ui_back")
			_popup_close.call()
			return
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


# ---------------------------------------------------------------- Rookie Camp (Update 13)
#
# A new manager's hub: locked features as teasers, the Rookie Path strip in the open middle, Rookie Week
# on TODAY, the badge budget, and the popups (welcome back, picks, NEW FEATURE UNLOCKED, coach tips, the
# PLAY spotlight). An established manager's hub is unchanged (everything open, no budget, no strip).

const PATH_GREEN := Color("#3DDC84")
const WEEK_ACCENT := Color("#5FD4FF")

var _status_row: Control
var _bottom_bar: Control
var _allowed := {}
## Attention keys whose badge or pulse is on screen (tests check the badge budget with it).
var attention_shown: Array[String] = []
var _path_panel: Control
var _week_status: Label
var _popup: Node
var _popup_close := Callable()
var _choice_later := false


## Which attention badges may show: every candidate, sorted by priority, cut to the badge budget.
func _compute_attention() -> void:
	var c: Array = []
	var ready := false
	for cid in DB.card_order:
		if Profile.can_upgrade_card(cid):
			ready = true
			break
	var cands := {
		"path_claim": Onboarding.path_can_claim(),
		"packs": Profile.pack_count() > 0 and Onboarding.is_unlocked("packs"),
		"week_claim": Onboarding.week_can_claim(),
		"login_claim": DailyRewards.can_claim(),
		"deck_new": (CollectionSets.claimable_count() > 0 or Profile.fresh_card_count() > 0) and Onboarding.is_unlocked("deck"),
		"upgrade_ready": ready and Onboarding.is_unlocked("upgrades"),
		"missions_claim": Missions.claimable_count() - (1 if Onboarding.path_can_claim() else 0) > 0 and Onboarding.is_unlocked("missions"),
		"season_claim": Season.claimable().size() > 0 and Onboarding.is_unlocked("season"),
		"daily_new": not DailyChallenge.played() and Onboarding.is_unlocked("daily"),
		"shop_gift": not _free_gift().is_empty() and Onboarding.is_unlocked("shop"),
		"trait": _trait_ready() and Onboarding.is_unlocked("team"),
		"scouting_new": Scouting.new_count() > 0 and Onboarding.is_unlocked("scouting"),
	}
	for k in cands.keys():
		if bool(cands[k]):
			c.append(k)
	c.sort_custom(func(a: String, b: String) -> bool: return Onboarding.badge_rank(a) < Onboarding.badge_rank(b))
	_allowed = {}
	attention_shown.clear()
	for k in c.slice(0, Onboarding.badge_budget()):
		_allowed[k] = true


## True when `key` may draw attention (and records that it does).
func _attn(key: String) -> bool:
	if not _allowed.has(key):
		return false
	if not key in attention_shown:
		attention_shown.append(key)
	return true


## The muted "LV 3" tag on a locked teaser (not an attention badge).
func _lock_tag(b: Control, fid: String) -> void:
	var t := UITheme.top_tag(b, Onboarding.lock_short(fid), Color(0.2, 0.23, 0.3, 0.97))
	t.name = "LockTag"
	(t.get_child(0) as Label).add_theme_color_override("font_color", Color(0.78, 0.83, 0.92))
	t.tooltip_text = Onboarding.lock_text(fid)


## A locked teaser was pressed: say when it opens, with a little shake.
func _locked_pressed(fid: String, b: Control) -> void:
	var f := Onboarding.feature(fid)
	Audio.ui("ui_error", -6.0)
	Router.toast("%s: %s. %s" % [str(f.get("name", fid)), Onboarding.lock_text(fid), str(f.get("text", ""))], "info", 3.6)
	if b and is_instance_valid(b) and not b.has_meta("shaking"):
		b.set_meta("shaking", true)
		var x := b.position.x
		var tw := b.create_tween()
		for k in 3:
			tw.tween_property(b, "position:x", x + 6.0, 0.04)
			tw.tween_property(b, "position:x", x - 6.0, 0.04)
		tw.tween_property(b, "position:x", x, 0.04)
		tw.tween_callback(func() -> void: b.remove_meta("shaking"))


## The Season chip while the Season Pass is still locked: a muted teaser.
func _build_season_teaser() -> Button:
	var b := UITheme.button("SEASON PASS", "secondary", UITheme.FS_SMALL, "lock", UITheme.MUTED)
	b.name = "SeasonBar"
	b.custom_minimum_size = Vector2(210, 40)
	b.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	b.tooltip_text = "Season Pass: %s.\n%s" % [Onboarding.lock_text("season"), Onboarding.feature("season").get("text", "")]
	b.pressed.connect(_locked_pressed.bind("season", b))
	_lock_tag(b, "season")
	return b


## Drops buttons that were freed by a rebuild.
func _prune_buttons() -> void:
	var keep: Array[Button] = []
	for b in _buttons:
		if is_instance_valid(b) and not (b as Node).is_queued_for_deletion():
			keep.append(b)
	_buttons = keep


## Rebuilds everything a claim can change (TODAY, the bottom bar, the chips, the Rookie Path strip) with
## the badge budget worked out again.
func _refresh_hub() -> void:
	_prune_buttons()
	_compute_attention()
	_build_right(false)
	_build_bottom_bar()
	if _status_row and is_instance_valid(_status_row):
		_fill_status_chips(_status_row)
	_build_rookie_path()
	_refresh_top_values()
	_prune_buttons()


# ---------------------------------------------------------------- Rookie Week (TODAY)

func _build_week_panel() -> Control:
	var can := Onboarding.week_can_claim()
	var hot := can and _attn("week_claim")
	var parts := _today_card("RookieWeek", "gift", "ROOKIE WEEK", hot)
	var p: PanelContainer = parts[0]
	var vb: VBoxContainer = parts[1]
	var head: HBoxContainer = parts[2]
	p.set_meta("compact", true)
	var day_b := UITheme.badge("DAY %d / %d" % [Onboarding.week_day() if can else Onboarding.week_claims(), Onboarding.week_days().size()],
		Color(0.1, 0.36, 0.5, 0.95), UITheme.FS_SMALL)
	day_b.name = "WeekDayBadge"
	day_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(day_b)
	if can:
		var cb := UITheme.button("CLAIM", "primary", UITheme.FS_LEAD, "gift", UITheme.GREEN.darkened(0.35))
		cb.name = "WeekClaim"
		cb.custom_minimum_size = Vector2(140, 42)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.tooltip_text = "Claim today's Rookie Week reward"
		cb.pressed.connect(_claim_week)
		head.add_child(cb)
		_buttons.append(cb)
	_week_status = UITheme.label(Onboarding.week_status_text(), UITheme.FS_SMALL, Color(0.7, 0.9, 1.0), UITheme.font_body_bold())
	_week_status.name = "WeekStatus"
	_week_status.tooltip_text = "A bonus calendar for new managers: one reward a day for seven days. Miss a day and it waits for you: it never resets."
	_week_status.mouse_filter = Control.MOUSE_FILTER_PASS
	vb.add_child(_week_status)
	var row := HBoxContainer.new()
	row.name = "WeekDays"
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	for e in Onboarding.week_calendar():
		row.add_child(_week_cell(e, can, hot))
	if hot:
		var pulse := p.create_tween().set_loops()
		pulse.tween_property(p, "self_modulate", Color(1.1, 1.14, 1.2), 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(p, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return p


func _week_cell(e: Dictionary, can: bool, hot: bool) -> Control:
	var day := int(e.get("day", 0))
	var claimed := bool(e.get("claimed", false))
	var today := bool(e.get("today", false)) and not claimed
	var big := day == Onboarding.week_days().size()
	var bg := Color(0.05, 0.08, 0.14, 0.95)
	var border := Color(1, 1, 1, 0.14)
	if claimed:
		bg = Color(0.05, 0.2, 0.12, 0.92)
		border = Color(UITheme.GREEN, 0.6)
	elif today:
		bg = Color(WEEK_ACCENT.darkened(0.72), 0.95)
		border = WEEK_ACCENT
	elif big:
		bg = Color(0.16, 0.11, 0.02, 0.95)
		border = Color(UITheme.GOLD, 0.75)
	var p := PanelContainer.new()
	p.name = "WeekDay%d" % day
	p.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 3 if (today or big) and not claimed else 2, 8, 3))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.35 if big else 1.0
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.tooltip_text = "Day %d: %s%s" % [day, str(e.get("text", "")), "  (claimed)" if claimed else ("  (today)" if today and can else "")]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var dl := UITheme.label("DAY %d" % day, UITheme.FS_MIN, UITheme.GOLD if big and not claimed else (WEEK_ACCENT if today else Color(0.8, 0.86, 0.95)), UITheme.font_header())
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	var r: Dictionary = e.get("reward", {})
	var parts := UITheme.reward_parts(r)
	var part: Array = parts[0] if not parts.is_empty() else ["gift", "?", UITheme.MUTED]
	if big and str(r.get("choice", "")) != "":
		part = ["crown", "LEGEND", UITheme.GOLD]
	var icon := UITheme.icon_rect("check" if claimed else str(part[0]), 26, UITheme.GREEN if claimed else part[2])
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(icon)
	var amount := str(part[1])
	if amount.length() > 7:
		amount = amount.substr(0, 6)
	var al := UITheme.label(amount, UITheme.FS_MIN, Color(0.75, 0.95, 0.82) if claimed else part[2], UITheme.font_header())
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(al)
	if today and can and hot:
		p.resized.connect(func() -> void: p.pivot_offset = p.size * 0.5)
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "scale", Vector2(1.07, 1.07), 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	return p


## CLAIM on Rookie Week: pays today's day, floats it up, and day 7 opens the Legendary pick.
func _claim_week() -> void:
	var day := Onboarding.week_day()
	var panel: Node = ui.find_child("RookieWeek", true, false)
	var cell: Control = panel.find_child("WeekDay%d" % day, true, false) if panel else null
	var origin := cell.get_global_rect().get_center() if cell else Vector2(1600, 300)
	var r := Onboarding.week_claim()
	if r.is_empty():
		return
	Audio.play("achievement", -3.0)
	Audio.play("coin", -6.0)
	_float_reward(origin, r.get("reward", {}))
	Router.toast("Rookie Week day %d: %s" % [int(r.day), str(r.text)], "achievement")
	_refresh_hub()
	_queue_popups()


# ---------------------------------------------------------------- COMING UP (TODAY)

## What unlocks next, while the Daily Challenge or Missions are still locked.
func _build_coming_up() -> Control:
	var parts := _today_card("ComingUp", "lock", "COMING UP", false)
	var p: PanelContainer = parts[0]
	var vb: VBoxContainer = parts[1]
	var sub := UITheme.label("Level up and follow the Rookie Path to open more of the clubhouse.", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	for f in Onboarding.next_locked(5):
		var row := HBoxContainer.new()
		row.name = "Locked_" + str(f.id)
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = "%s: %s.\n%s" % [str(f.name), Onboarding.lock_text(str(f.id)), str(f.get("text", ""))]
		var ib := PanelContainer.new()
		ib.add_theme_stylebox_override("panel", UITheme.panel_style(Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.15), 1, 8, 4))
		ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ib.add_child(UITheme.icon_rect(str(f.get("icon", "lock")), 24, Color(0.7, 0.76, 0.86)))
		row.add_child(ib)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -4)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(UITheme.label(str(f.name).to_upper(), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header()))
		var ul := UITheme.label(Onboarding.lock_text(str(f.id)), UITheme.FS_MIN, Color(1.0, 0.78, 0.6), UITheme.font_body_bold())
		ul.clip_text = true
		tv.add_child(ul)
		row.add_child(tv)
		var lk := UITheme.icon_rect("lock", 22, UITheme.MUTED)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(lk)
		vb.add_child(row)
	return p


# ---------------------------------------------------------------- Rookie Path strip

## The Rookie Path in the open middle above the bottom bar: ten steps (done, current, to come, the
## finale), the current step with its tip and progress or CLAIM, and the next reward.
func _build_rookie_path() -> void:
	if _path_panel and is_instance_valid(_path_panel):
		_path_panel.get_parent().remove_child(_path_panel)
		_path_panel.queue_free()
	_path_panel = null
	if not Onboarding.path_active():
		if _caption:
			_caption.offset_bottom = -BOTTOM_H - 16
		return
	var steps := Onboarding.path_steps()
	var cur := Onboarding.path_claimed()
	var inst := Onboarding.path_current()
	var ready := Onboarding.path_can_claim()
	var def := Onboarding.path_step_def(cur)
	var p := PanelContainer.new()
	p.name = "RookiePath"
	var s := UITheme.panel_style(Color(0.025, 0.06, 0.1, 0.95), Color(PATH_GREEN, 0.7), 2, 14, 0)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 12
	s.content_margin_bottom = 14
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 14
	p.add_theme_stylebox_override("panel", s)
	p.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	p.offset_left = HERO_X + HERO_W + 40
	p.offset_right = -TODAY_W - 28
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_top = -BOTTOM_H - 18
	p.offset_bottom = -BOTTOM_H - 18
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(p)
	ui.move_child(p, ui.get_child_count() - 1)
	_path_panel = p
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	# Head: ROOKIE PATH and STEP n / 10.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	head.add_child(UITheme.icon_rect("trophy", 30, PATH_GREEN))
	var tl := UITheme.label("ROOKIE PATH", 34, PATH_GREEN, UITheme.font_display())
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	tl.add_theme_constant_override("shadow_offset_x", 2)
	tl.add_theme_constant_override("shadow_offset_y", 2)
	head.add_child(tl)
	var sl := UITheme.label("STEP %d / %d" % [cur + 1, steps.size()], UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header())
	sl.name = "PathStepCount"
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sl)
	# The track.
	var track := HBoxContainer.new()
	track.name = "PathTrack"
	track.add_theme_constant_override("separation", 0)
	track.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(track)
	for i in steps.size():
		if i > 0:
			var line := ColorRect.new()
			line.color = Color(PATH_GREEN, 0.85) if i <= cur else Color(1, 1, 1, 0.14)
			line.custom_minimum_size = Vector2(6, 4)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			line.mouse_filter = Control.MOUSE_FILTER_IGNORE
			track.add_child(line)
		track.add_child(_path_node(i, cur, ready, steps[i]))
	# The current step: icon, text and tip, progress or CLAIM.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var ib := PanelContainer.new()
	ib.add_theme_stylebox_override("panel", UITheme.panel_style(Color(PATH_GREEN, 0.14), Color(PATH_GREEN, 0.6), 2, 10, 6))
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ib.add_child(UITheme.icon_rect(str(def.get("icon", "target")), 32, PATH_GREEN))
	row.add_child(ib)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tv)
	var st := UITheme.label(Missions.text(inst).to_upper() if not inst.is_empty() else "", 28, UITheme.OFFWHITE, UITheme.font_header())
	st.name = "PathStepText"
	st.clip_text = true
	tv.add_child(st)
	var hint := UITheme.label("Done! Claim your reward." if ready else Missions.hint(inst), UITheme.FS_SMALL, Color(0.75, 0.95, 0.82) if ready else UITheme.MUTED, UITheme.font_body_bold())
	hint.name = "PathHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 2
	tv.add_child(hint)
	if ready:
		var cb := UITheme.button("CLAIM", "primary", UITheme.FS_LEAD, "gift", UITheme.GREEN.darkened(0.3))
		cb.name = "PathClaim"
		cb.custom_minimum_size = Vector2(150, 54)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.tooltip_text = "Claim the Rookie Path reward: " + Missions.reward_text(Missions.reward(inst))
		cb.pressed.connect(_claim_path.bind(cb))
		row.add_child(cb)
		_buttons.append(cb)
		if _attn("path_claim"):
			cb.resized.connect(func() -> void: cb.pivot_offset = cb.size * 0.5)
			var tw := cb.create_tween().set_loops()
			tw.tween_property(cb, "scale", Vector2(1.06, 1.06), 0.55).set_trans(Tween.TRANS_SINE)
			tw.tween_property(cb, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_SINE)
	else:
		var pl := UITheme.label("%d / %d" % [int(inst.get("progress", 0)), int(inst.get("goal", 1))], 30, UITheme.OFFWHITE, UITheme.font_header())
		pl.name = "PathProgress"
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pl)
	# The reward for this step, and what the finale pays.
	var rw := HBoxContainer.new()
	rw.name = "PathReward"
	rw.add_theme_constant_override("separation", 12)
	vb.add_child(rw)
	rw.add_child(UITheme.label("REWARD", UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_header()))
	var chips := UITheme.reward_row(Missions.reward(inst), UITheme.FS_SMALL)
	chips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rw.add_child(chips)
	var fin: Dictionary = steps[steps.size() - 1].get("reward", {})
	var fl := UITheme.label("FINALE: %s" % ("CHAMPION PACK + A FREE AGENT" if str(fin.get("choice", "")) == "free_agent" else Missions.reward_text(fin).to_upper()),
		UITheme.FS_MIN, Color(UITheme.GOLD, 0.85), UITheme.font_body_bold())
	fl.name = "PathFinale"
	fl.tooltip_text = "Finish the Rookie Path: %s" % Missions.reward_text(fin)
	fl.mouse_filter = Control.MOUSE_FILTER_PASS
	fl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rw.add_child(fl)
	UITheme.animate_in(p, 0.35, 0.97)
	# Keep the showcase caption clear of the strip.
	var lift := func() -> void:
		if _caption and is_instance_valid(p):
			_caption.offset_bottom = -BOTTOM_H - 18 - p.get_combined_minimum_size().y - 10
	lift.call_deferred()


## One node on the track: done (a green check), the current step (gold ring), to come (number), the
## finale (a trophy, bigger).
func _path_node(i: int, cur: int, ready: bool, def: Dictionary) -> Control:
	var finale := bool(def.get("finale", false))
	var side := 46.0 if finale else 34.0
	var done := i < cur
	var now := i == cur
	var bg := Color(0.06, 0.09, 0.15, 0.98)
	var border := Color(1, 1, 1, 0.2)
	if done:
		bg = Color(PATH_GREEN, 0.9)
		border = PATH_GREEN.lightened(0.3)
	elif now:
		bg = Color(PATH_GREEN.darkened(0.55), 0.98) if not ready else Color(UITheme.GOLD.darkened(0.45), 0.98)
		border = UITheme.GOLD
	elif finale:
		bg = Color(0.18, 0.12, 0.02, 0.98)
		border = Color(UITheme.GOLD, 0.8)
	var n := Panel.new()
	n.name = "PathStep%d" % (i + 1)
	n.custom_minimum_size = Vector2(side, side)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	n.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 3 if now else 2, int(side / 2), 0))
	n.mouse_filter = Control.MOUSE_FILTER_PASS
	n.tooltip_text = "Step %d: %s\nTeaches: %s\nReward: %s" % [i + 1, str(def.get("text", "")), str(def.get("teach", "")), Missions.reward_text(def.get("reward", {}))]
	if done:
		var ic := UITheme.icon_rect("check", side * 0.6, Color(0.02, 0.12, 0.06))
		ic.position = Vector2(side * 0.2, side * 0.2)
		n.add_child(ic)
	elif finale:
		var ic2 := UITheme.icon_rect("trophy", side * 0.62, UITheme.GOLD)
		ic2.position = Vector2(side * 0.19, side * 0.19)
		n.add_child(ic2)
	else:
		var l := UITheme.label(str(i + 1), 20, Color.WHITE if now else UITheme.MUTED, UITheme.font_header())
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.add_child(l)
	if now:
		n.pivot_offset = Vector2(side, side) * 0.5
		var tw := n.create_tween().set_loops()
		tw.tween_property(n, "scale", Vector2(1.14, 1.14), 0.7).set_trans(Tween.TRANS_SINE)
		tw.tween_property(n, "scale", Vector2.ONE, 0.7).set_trans(Tween.TRANS_SINE)
	return n


## CLAIM on the Rookie Path: pays the step, then any feature it opened gets its unlock card (and the
## finale its free agent pick).
func _claim_path(btn: Control = null) -> void:
	var origin := btn.get_global_rect().get_center() if btn and is_instance_valid(btn) else Vector2(960, 800)
	var step := Onboarding.path_claimed() + 1
	var r := Onboarding.claim_path()
	if r.is_empty():
		return
	Audio.play("achievement", -3.0)
	Audio.play("coin", -6.0)
	_float_reward(origin, r)
	Router.toast("Rookie Path step %d done: %s" % [step, Missions.reward_text(r)], "achievement")
	if not Onboarding.path_active():
		UITheme.confetti_burst(ui, origin, 90)
	Profile.save_soon()
	_refresh_hub()
	_queue_popups()


# ---------------------------------------------------------------- popups

## Shows the next Rookie Camp popup, one at a time: welcome back, a pick, NEW FEATURE UNLOCKED, the
## coach's tip; then the PLAY spotlight. Popups stay off in automated runs (Onboarding.popups_enabled).
func _queue_popups() -> void:
	if not is_inside_tree():
		return
	if _popup and is_instance_valid(_popup):
		return   # the running popup moves on to the next one when it closes
	_next_popup()


func _next_popup() -> void:
	_popup = null
	_popup_close = Callable()
	if not is_inside_tree() or is_queued_for_deletion():
		return
	if Router.busy or get_tree().current_scene != self:
		# A screen change is running: this hub is leaving (it never shows anything again) or the new
		# hub is still fading in (try again in a moment).
		if get_tree().current_scene == self:
			var again := create_tween()
			again.tween_interval(0.4)
			again.tween_callback(_next_popup)
		return
	if Onboarding.popups_enabled():
		var w := Onboarding.pending_welcome()
		if not w.is_empty():
			_show_welcome_back(w)
			return
		var c := Onboarding.pending_choice()
		if not c.is_empty() and not _choice_later:
			_show_choice(c)
			return
		var u := Onboarding.pending_unlocks()
		if not u.is_empty():
			_show_unlock(u.slice(0, 4))
			return
		var tip := Onboarding.coach_tip()
		if not tip.is_empty():
			_show_coach(tip)
			return
	_maybe_ftue()


## A popup card on a spotlight layer: returns [layer, content VBox, card]. `targets` get spotlight holes.
func _popup_card(card_name: String, accent: Color, targets: Array, width := 760.0, center := Vector2(-1, -1)) -> Array:
	var sp := Hints.spotlight(self, targets, true)
	sp.name = card_name
	_popup = sp
	var card := UITheme.card_panel(Color(accent, 0.9), 26, Color(0.035, 0.06, 0.11, 0.98), 3)
	card.name = card_name + "Card"
	card.custom_minimum_size = Vector2(width, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	sp.root.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)
	var vis := get_viewport().get_visible_rect().size
	var f := minf(1.0, minf(vis.x / DESIGN_SIZE.x, vis.y / DESIGN_SIZE.y))
	var place := func() -> void:
		if not is_instance_valid(card):
			return
		var cs := card.get_combined_minimum_size()
		card.size = cs
		card.pivot_offset = cs * 0.5
		var c := center if center.x >= 0.0 else vis * 0.5
		card.position = (c - cs * 0.5).clamp(Vector2(16, 16), vis - cs * f - Vector2(16, 16))
	place.call_deferred()
	card.scale = Vector2(f, f) * 0.9
	card.modulate.a = 0.0
	var tw := card.create_tween().set_parallel()
	tw.tween_property(card, "modulate:a", 1.0, 0.22)
	tw.tween_property(card, "scale", Vector2(f, f), 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return [sp, vb, card]


## Closes the current popup and moves on to the next one.
func _close_popup() -> void:
	var sp: Node = _popup
	_popup = null
	_popup_close = Callable()
	if sp and is_instance_valid(sp):
		if sp.has_method("close"):
			sp.close()
		else:
			sp.queue_free()
	var tw := create_tween()
	tw.tween_interval(0.3)
	tw.tween_callback(_next_popup)


func _popup_buttons(vb: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "PopupButtons"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vb.add_child(row)
	return row


## NEW FEATURE UNLOCKED: one card for the features that just opened, spotlights on their hub elements.
func _show_unlock(feats: Array) -> void:
	var targets: Array = []
	for f in feats:
		var t: Node = ui.find_child(str(f.get("hub", "")), true, false)
		if t is Control:
			targets.append(t)
	# Keep the card clear of the spotlights: above them when they are low on the screen.
	var low := targets.any(func(t: Control) -> bool: return t.get_global_rect().get_center().y > 800.0)
	var vis := get_viewport().get_visible_rect().size
	var parts := _popup_card("UnlockCelebration", UITheme.GOLD, targets, 680.0, Vector2(vis.x * 0.5, vis.y * (0.4 if low else 0.5)))
	var vb: VBoxContainer = parts[1]
	var card: Control = parts[2]
	var rib := UITheme.slant_ribbon("NEW FEATURE%s UNLOCKED" % ("S" if feats.size() > 1 else ""), "star", 34, UITheme.SCARLET, false, 2)
	rib.name = "UnlockRibbon"
	rib.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(rib)
	for f in feats:
		var row := HBoxContainer.new()
		row.name = "Unlocked_" + str(f.id)
		row.add_theme_constant_override("separation", 18)
		vb.add_child(row)
		var art := Control.new()
		art.custom_minimum_size = Vector2(96, 96)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(art)
		var rays := UITheme.rays(150.0, Color(1.0, 0.8, 0.25, 0.2))
		rays.position = Vector2(-27, -27)
		art.add_child(rays)
		var disc := Panel.new()
		disc.add_theme_stylebox_override("panel", UITheme.panel_style(UITheme.GOLD.darkened(0.55), UITheme.GOLD, 3, 48, 0))
		disc.size = Vector2(96, 96)
		disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(disc)
		var ic := UITheme.icon_rect(str(f.get("icon", "star")), 56, Color.WHITE)
		ic.position = Vector2(20, 20)
		disc.add_child(ic)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(tv)
		tv.add_child(UITheme.label(str(f.name).to_upper(), 46 if feats.size() == 1 else 36, UITheme.GOLD, UITheme.font_display()))
		var tx := UITheme.label(str(f.get("text", "")), UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
		tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tx.custom_minimum_size = Vector2(500, 0)
		tv.add_child(tx)
	var where := UITheme.label("Look for the glowing spot%s on your clubhouse." % ("s" if targets.size() > 1 else ""), UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	where.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(where)
	var btns := _popup_buttons(vb)
	var ids: Array = feats.map(func(f: Dictionary) -> String: return str(f.id))
	var done := func() -> void:
		for id in ids:
			Onboarding.mark_announced(id)
		_close_popup()
	if feats.size() == 1 and _try_action(str(feats[0].id)).is_valid():
		var go := UITheme.button("TRY IT  ▶", "primary", UITheme.FS_LEAD, "play", UITheme.GREEN.darkened(0.3))
		go.name = "UnlockTry"
		go.custom_minimum_size = Vector2(220, 58)
		var act := _try_action(str(feats[0].id))
		go.pressed.connect(func() -> void:
			for id in ids:
				Onboarding.mark_announced(id)
			_popup = null
			act.call())
		btns.add_child(go)
	var ok := UITheme.button("GOT IT", "secondary" if feats.size() == 1 else "primary", UITheme.FS_LEAD, "check", UITheme.GOLD)
	ok.name = "UnlockOk"
	ok.custom_minimum_size = Vector2(180, 58)
	ok.pressed.connect(done)
	btns.add_child(ok)
	_popup_close = done
	Audio.play("level_up", -2.0)
	var burst := create_tween()
	burst.tween_interval(0.25)
	burst.tween_callback(func() -> void:
		if is_instance_valid(card) and _popup and is_instance_valid(_popup):
			UITheme.confetti_burst((_popup as Hints.Spotlight).root, card.get_global_rect().get_center() - Vector2(0, card.size.y * 0.4)))
	ok.grab_focus.call_deferred()


## Where TRY IT goes for a feature (an invalid Callable when there is nowhere to go).
func _try_action(id: String) -> Callable:
	match id:
		"deck":
			return func() -> void:
				Session.menu_tab = "deck"
				Router.goto("deck_builder")
		"packs":
			return func() -> void: Router.goto("packs")
		"upgrades":
			return func() -> void: Router.goto("card_upgrades")
		"team":
			return func() -> void: Router.goto("roster")
		"shop":
			return func() -> void: Router.open("shop")
		"season":
			return func() -> void: Router.open("season")
		"scouting":
			return func() -> void: Router.goto("scouting_book")
		"missions":
			return func() -> void:
				Session.menu_tab = "missions"
				Router.goto("progression")
		"daily":
			return func() -> void:
				Session.menu_tab = "daily"
				Router.goto("play_menu")
		"quick", "standard", "boss_rush", "endless":
			return func() -> void:
				Profile.data.flags["last_mode"] = id
				Session.menu_tab = "mode:" + id
				Router.goto("play_menu")
	return Callable()


## A pick: three cards that suit the deck (Epic after game 3, Legendary on Rookie Week day 7) or the free
## agents (Rookie Path finale). DECIDE LATER keeps it for the next visit.
func _show_choice(c: Dictionary) -> void:
	var kind := str(c.get("kind", ""))
	var opts: Array = c.get("options", [])
	var accent := UITheme.PURPLE.lightened(0.15) if kind == "epic" else (UITheme.GOLD if kind == "legendary" else UITheme.BLUE)
	var parts := _popup_card("ChoicePopup", accent, [], 1020.0)
	var vb: VBoxContainer = parts[1]
	var title := {"epic": "PICK YOUR FIRST EPIC", "legendary": "PICK YOUR LEGENDARY", "free_agent": "SIGN A FREE AGENT"}.get(kind, "MAKE YOUR PICK")
	var hh := UITheme.section_header(str(title), "star" if kind != "free_agent" else "roster", accent, 46)
	hh.name = "ChoiceTitle"
	hh.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hh)
	var sub := {"epic": "Three Epic cards that suit your deck and team. Keep one: it is yours for good.",
		"legendary": "Rookie Week day 7! Three Legendary cards for your deck. Keep one.",
		"free_agent": "You finished the Rookie Path! Sign one free agent now, long before their level, for free."}.get(kind, "")
	var sl := UITheme.label(str(sub) + ("  (%s)" % str(c.get("source", "")) if str(c.get("source", "")) != "" and kind == "epic" else ""), UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sl)
	var row := HBoxContainer.new()
	row.name = "ChoiceOptions"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	vb.add_child(row)
	var first: Button = null
	for id in opts:
		var col := VBoxContainer.new()
		col.name = "Option_" + str(id)
		col.add_theme_constant_override("separation", 8)
		col.custom_minimum_size = Vector2(280, 0)
		row.add_child(col)
		if kind == "free_agent":
			_agent_option(col, str(id))
		else:
			var cv := CardView.new(str(id), maxi(1, Profile.card_level(str(id))))
			cv.custom_minimum_size = Vector2(214, 300)
			cv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			cv.tooltip_text = DB.card_text(str(id), 1)
			col.add_child(cv)
			var nl := UITheme.label(str(DB.card(str(id)).get("name", id)).to_upper(), UITheme.FS_LEAD, Color(DB.rarity_color(kind)).lightened(0.3), UITheme.font_header())
			nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(nl)
			var why := UITheme.label(Onboarding.card_reason(str(id)), UITheme.FS_SMALL, Color(0.75, 0.95, 0.82), UITheme.font_body_bold())
			why.name = "Reason"
			why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			why.custom_minimum_size = Vector2(270, 0)
			col.add_child(why)
		var pick := UITheme.button("SIGN" if kind == "free_agent" else "PICK", "primary", UITheme.FS_LEAD, "check", accent.darkened(0.35))
		pick.name = "Pick_" + str(id)
		pick.custom_minimum_size = Vector2(200, 54)
		pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pick.pressed.connect(_pick_option.bind(str(id), kind, col))
		col.add_child(pick)
		if first == null:
			first = pick
	var btns := _popup_buttons(vb)
	var later := UITheme.button("DECIDE LATER", "ghost", UITheme.FS_BODY)
	later.name = "ChoiceLater"
	later.tooltip_text = "Close this (Esc). The pick waits for your next visit."
	var close_fn := func() -> void:
		_choice_later = true
		_close_popup()
	later.pressed.connect(close_fn)
	btns.add_child(later)
	_popup_close = close_fn
	Audio.play("reveal_legendary" if kind == "legendary" else "reveal_epic", -4.0)
	if first:
		first.grab_focus.call_deferred()


func _agent_option(col: VBoxContainer, id: String) -> void:
	var d := DB.defender(id)
	var accent := DB.defender_accent(id)
	var pr := MenuScreen.portrait_rect(id, 190, accent)
	pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(pr)
	var nl := UITheme.label(str(d.name).to_upper(), 34, accent.lightened(0.3), UITheme.font_display())
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(nl)
	var role := str(DB.roles.get(str(d.get("role", "")), {}).get("name", str(d.get("role", "")).capitalize()))
	var sub := UITheme.label("#%d  ·  %s  ·  %s" % [int(d.get("number", 0)), role, str(d.get("title", ""))], UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(sub)
	var u: Dictionary = d.get("unlock", {})
	var info := UITheme.label("Signature card: %s\nNormally level %d or %s coins" % [str(DB.card(str(d.get("signature", ""))).get("name", "")), int(u.get("value", 0)), UITheme.format_int(int(u.get("coins", 0)))],
		UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(info)


func _pick_option(id: String, kind: String, col: Control) -> void:
	var r := Onboarding.choose(id)
	if r.is_empty():
		return
	Audio.play("achievement", -2.0)
	if _popup and is_instance_valid(_popup) and is_instance_valid(col):
		UITheme.confetti_burst((_popup as Hints.Spotlight).root, col.get_global_rect().get_center(), 80)
	if kind == "free_agent":
		Router.toast("%s signed! Put them in your starting six on the Team screen." % str(r.name), "achievement", 4.0)
	else:
		Router.toast("%s joined your collection! Put it in your deck in Cards & Deck." % str(r.name), "achievement", 4.0)
	_refresh_top_values()
	var tw := create_tween()
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void:
		_close_popup()
		_refresh_hub())


## WELCOME BACK after 3+ days away: the bonus (already paid) and a short recap.
func _show_welcome_back(w: Dictionary) -> void:
	var parts := _popup_card("WelcomeBack", UITheme.GOLD, [], 720.0)
	var vb: VBoxContainer = parts[1]
	var hh := UITheme.section_header("WELCOME BACK, MANAGER!", "star", UITheme.GOLD, 46)
	hh.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hh)
	var away := UITheme.label("You were away %d days. The team kept your seat warm: here's a welcome-back bonus." % int(w.get("days", 3)),
		UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	away.name = "WelcomeDays"
	away.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	away.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	away.custom_minimum_size = Vector2(660, 0)
	vb.add_child(away)
	var rp := PanelContainer.new()
	rp.name = "WelcomeReward"
	rp.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.GOLD, 0.1), Color(UITheme.GOLD, 0.5), 2, 10, 12))
	rp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var rr := UITheme.reward_row(w.get("granted", w.get("reward", {})), 30)
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	rr.add_theme_constant_override("separation", 22)
	rp.add_child(rr)
	vb.add_child(rp)
	vb.add_child(UITheme.section_header("WHAT'S NEW", "info", UITheme.GOLD, UITheme.FS_H3))
	var list := VBoxContainer.new()
	list.name = "WelcomeRecap"
	list.add_theme_constant_override("separation", 6)
	vb.add_child(list)
	for line in Onboarding.welcome_recap():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := UITheme.icon_rect(str(line[0]), 24, UITheme.GOLD)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(ic)
		var l := UITheme.label(str(line[1]), UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		list.add_child(row)
	var btns := _popup_buttons(vb)
	var go := UITheme.button("LET'S PLAY", "primary", UITheme.FS_LEAD, "play", UITheme.SCARLET)
	go.name = "WelcomeOk"
	go.custom_minimum_size = Vector2(240, 58)
	var done := func() -> void:
		Onboarding.dismiss_welcome()
		_close_popup()
	go.pressed.connect(done)
	btns.add_child(go)
	_popup_close = done
	Audio.play("achievement", -3.0)
	go.grab_focus.call_deferred()


## After an early loss: the consolation reward, an easier difficulty, and (after two in a row) Auto Build.
func _show_coach(tip: Dictionary) -> void:
	var parts := _popup_card("CoachTip", UITheme.BLUE, [], 700.0)
	var vb: VBoxContainer = parts[1]
	var hh := UITheme.section_header("TOUGH GAME, MANAGER!", "info", UITheme.BLUE.lightened(0.3), 44)
	hh.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hh)
	var t := UITheme.label("Every manager drops a few early games. Here's something to keep you going:", UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.custom_minimum_size = Vector2(640, 0)
	vb.add_child(t)
	var rr := UITheme.reward_row(tip.get("reward", {}), 28)
	rr.alignment = BoxContainer.ALIGNMENT_CENTER
	rr.name = "CoachReward"
	vb.add_child(rr)
	var easier := str(tip.get("easier", ""))
	var auto := bool(tip.get("auto_build", false))
	if easier != "" or auto:
		var adv := UITheme.label(("Try %s: %s" % [DB.difficulty(easier).get("name", easier), DB.difficulty(easier).get("text", "")] if easier != "" else "")
			+ ("\n" if easier != "" and auto else "") + ("Two in a row? Let Auto Build pick the strongest 8 cards from your collection." if auto else ""),
			UITheme.FS_BODY, Color(0.75, 0.88, 1.0), UITheme.font_body_bold())
		adv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		adv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		adv.custom_minimum_size = Vector2(640, 0)
		vb.add_child(adv)
	var btns := _popup_buttons(vb)
	if easier != "":
		var eb := UITheme.button("PLAY ON %s" % str(DB.difficulty(easier).get("name", easier)).to_upper(), "primary", UITheme.FS_BODY, "play", UITheme.GREEN.darkened(0.3))
		eb.name = "CoachEasier"
		eb.custom_minimum_size = Vector2(0, 54)
		eb.pressed.connect(func() -> void:
			var d := Onboarding.take_easier()
			Router.toast("Difficulty set to %s." % str(DB.difficulty(d).get("name", d)), "info")
			_close_popup()
			_refresh_hero())
		btns.add_child(eb)
	if auto:
		var ab := UITheme.button("AUTO BUILD MY DECK", "primary", UITheme.FS_BODY, "deck", UITheme.BLUE.darkened(0.2))
		ab.name = "CoachAutoBuild"
		ab.custom_minimum_size = Vector2(0, 54)
		ab.pressed.connect(func() -> void:
			var deck := Onboarding.auto_build_deck()
			Router.toast("Auto Build: your deck now has %s." % ", ".join(deck.map(func(c: String) -> String: return str(DB.card(c).get("name", c)))) if not deck.is_empty()
				else "Your deck is already the best Auto Build can make.", "info", 4.5)
			if easier == "":
				Onboarding.dismiss_coach()
			ab.disabled = true
			if easier == "":
				_close_popup())
		btns.add_child(ab)
	var keep := UITheme.button("KEEP GOING", "ghost", UITheme.FS_BODY)
	keep.name = "CoachClose"
	var done := func() -> void:
		Onboarding.dismiss_coach()
		_close_popup()
	keep.pressed.connect(done)
	btns.add_child(keep)
	_popup_close = done


## Back from the first-session flow (flags.ftue_return_hub): a spotlight on PLAY for game 2. It never
## blocks: any click or key fades it out. The flag is cleared once shown.
func _maybe_ftue() -> void:
	if not bool(Profile.data.flags.get("ftue_return_hub", false)) or _hero == null or not is_instance_valid(_hero):
		return
	Profile.data.flags["ftue_return_hub"] = false
	Profile.save_soon()
	var sp := Hints.spotlight(self, [_hero], false, 0.5)
	sp.name = "PlaySpotlight"
	var callout := UITheme.card_panel(Color(UITheme.GOLD, 0.9), 16, Color(0.04, 0.07, 0.13, 0.97), 3)
	callout.name = "PlayCallout"
	callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	callout.add_child(cv)
	cv.add_child(UITheme.label("READY FOR GAME 2?", 34, UITheme.GOLD, UITheme.font_display()))
	var tx := UITheme.label("Press PLAY: your new cards are waiting.", UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	cv.add_child(tx)
	sp.root.add_child(callout)
	var hr := _hero.get_global_rect()
	callout.position = Vector2(hr.end.x + 40.0, hr.get_center().y - 48.0)
	callout.modulate.a = 0.0
	var tw := callout.create_tween()
	tw.tween_property(callout, "modulate:a", 1.0, 0.3)
	var bob := callout.create_tween().set_loops()
	bob.tween_property(callout, "position:x", callout.position.x + 10.0, 0.6).set_trans(Tween.TRANS_SINE)
	bob.tween_property(callout, "position:x", callout.position.x, 0.6).set_trans(Tween.TRANS_SINE)
	_hero.grab_focus.call_deferred()


# ---------------------------------------------------------------- screenshot / demo helper

## `--rookie-demo=a,b,...` sets up a Rookie Camp moment for screenshots: fresh, unlock (level 2 just
## reached), path (a step ready to claim), epic, legendary, agent (a pick), week (Rookie Week day 3 ready),
## welcome (5 days away), coach (two early losses), ftue (back from the first game), established.
func _rookie_demo_setup() -> void:
	var demos: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rookie-demo="):
			demos = Array(a.split("=")[1].split(","))
	if demos.is_empty() or Profile.data.flags.get("rookie_demo_done", false):
		return
	Profile.data.flags["rookie_demo_done"] = true
	Profile.data.flags.tutorial_done = true
	var hist := func(won: bool) -> void:
		Profile.add_history({"won": won, "mode": "quick", "difficulty": "rookie", "arena": "steel_yard", "inning": 3, "score": 1200, "outs": 40, "runs": 0, "date": Time.get_datetime_string_from_system()})
	for d in demos:
		match str(d):
			"established":
				Onboarding.make_established()
			"unlock":
				hist.call(true)
				Profile.data.stats["runs_played"] = 1.0
				Profile.add_xp(Profile.xp_to_next(1) + 20)
			"path":
				hist.call(true)
				Profile.data.stats["runs_played"] = 2.0
				Profile.add_xp(Profile.xp_to_next(1) + 60)
				var m := Missions.state()
				m.starter_step = 3
				m.starter = {}
				Missions.refresh()
				m.starter.progress = int(m.starter.goal)
				for f in Onboarding.pending_unlocks():
					Onboarding.mark_announced(str(f.id))
				Profile.add_pack("rookie", "demo")
				Profile.add_pack("rookie", "demo")
			"epic", "legendary", "agent":
				for f in Onboarding.pending_unlocks():
					Onboarding.mark_announced(str(f.id))
				Onboarding.queue_choice({"epic": "epic", "legendary": "legendary", "agent": "free_agent"}[str(d)], "demo")
			"week":
				var w: Dictionary = Onboarding.state().week
				w.claims = 2
				w.last_claim = DailyChallenge.shift_date(DailyChallenge.today(), -1)
			"welcome":
				Onboarding.state().last_seen = DailyChallenge.shift_date(DailyChallenge.today(), -5)
				Onboarding.state().welcome = {}
			"coach":
				hist.call(false)
				hist.call(false)
				Profile.data.stats["runs_played"] = 2.0
				Onboarding.state().losses_row = 2
				var cr := Rewards.grant_bundle(Onboarding.data().consolation.reward, "demo")
				Onboarding.state().coach = {"easier": "rookie", "difficulty": "standard", "mode": "quick", "auto_build": true, "losses": 2, "reward": cr}
			"ftue":
				Profile.data.flags["ftue_return_hub"] = true
	Profile.save_now()
