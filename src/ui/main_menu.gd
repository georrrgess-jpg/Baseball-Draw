extends Node3D
## Main menu (the hub): a live 3D stadium at sunset with the team warming up (throwing and
## catching), a slow cinematic camera, the Baseball Draw logo, PLAY with a quick mode switch and
## the destinations on the left; the profile, win streak, Season tier bar and the TODAY block
## (login calendar, Daily Challenge, missions, the Shop's free gift) on the right.

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
var _profile_box: VBoxContainer
var _caption: VBoxContainer
var _right: VBoxContainer
var _daily_countdown: Label
var _countdown_t := 0.0
var _welcome_later: Button   # "Look around first" on the welcome panel (Esc presses it)
## Idle showcase: every few seconds one defender shows off and the camera leans toward them.
var _show_t := 5.0
var _focus := Vector3.ZERO
var _focus_t := 0.0
var _focus_w := 0.0

const COL_W := 580.0


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
	# A V-shaped hero lineup facing the camera, on the right side of the screen.
	var spots := [
		[Vector3(3.7, 0, 9.4), "victory"], [Vector3(2.1, 0, 8.4), "ready"], [Vector3(5.3, 0, 8.5), "idle"],
		[Vector3(0.6, 0, 7.3), "idle"], [Vector3(6.8, 0, 7.4), "ready"], [Vector3(3.7, 0, 6.6), "idle"],
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


func _process(delta: float) -> void:
	_t += delta
	_update_daily_countdown(delta)
	# The camera starts on the lineup (no fly-in through the stadium) and only breathes a little.
	# During a showcase it leans toward the defender showing off.
	var pos := Vector3(-0.4 + sin(_t * 0.07) * 0.22, 1.8 + sin(_t * 0.11) * 0.06, 16.6 + cos(_t * 0.05) * 0.12)
	var look := Vector3(2.4 + sin(_t * 0.045) * 0.12, 2.3 + sin(_t * 0.08) * 0.03, 4.0)
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
# Layout (design pixels, 1920x1080): the left column is "play and go places" (logo, PLAY with a
# quick mode switch, UP NEXT, the destinations); the right column is "you and today" (profile,
# win streak, Season tier bar, then the TODAY block: login calendar, Daily Challenge, missions and
# the Shop's free gift). The 3D lineup shows through the middle.

## Modes on the hub's quick switch: [id, short name, icon].
const QUICK_MODES := [["quick", "QUICK", "speed"], ["standard", "SIEGE", "trophy"], ["boss_rush", "BOSS RUSH", "boss"], ["endless", "ENDLESS", "wave"]]
const RIGHT_W := 470.0
const TODAY_ACCENT := Color("#FF8A3D")

var _mode_chips := {}
var _hero_sub: Label
var _login_panel: Control
var _season_bar: Button
var _shop_tile: Button
var _gift_button: Button


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	# Gradients on both sides keep the text legible over the stadium.
	for side in [0, 1]:
		var grad := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.03, 0.05, 0.1, 0.94 if side == 0 else 0.0))
		g.set_color(1, Color(0.03, 0.05, 0.1, 0.0 if side == 0 else 0.78))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 256
		gt.height = 4
		grad.texture = gt
		grad.set_anchors_preset(Control.PRESET_LEFT_WIDE if side == 0 else Control.PRESET_RIGHT_WIDE)
		if side == 1:
			grad.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			grad.offset_left = -620
		grad.custom_minimum_size = Vector2(900 if side == 0 else 620, 0)
		grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grad.stretch_mode = TextureRect.STRETCH_SCALE
		grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui.add_child(grad)

	var left := VBoxContainer.new()
	left.name = "HubLeft"
	left.position = Vector2(60, 22)
	left.custom_minimum_size = Vector2(COL_W, 0)
	left.add_theme_constant_override("separation", 10)
	ui.add_child(left)
	var logo_path := "res://assets/textures/logo/logo.png"
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.custom_minimum_size = Vector2(COL_W, 176)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		left.add_child(logo)
	else:
		left.add_child(UITheme.title("BASEBALL DRAW", 96, UITheme.OFFWHITE))
	var tag := UITheme.label("DRAW YOUR HAND. DEFEND THE DIAMOND.", 22, UITheme.OFFWHITE, UITheme.font_brush())
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	left.add_child(spacer)

	# Continue (only when a run is saved) sits right above the hero PLAY button.
	if Profile.has_saved_run():
		var cr: Dictionary = Profile.data.current_run
		_continue_btn = _wide_button("CONTINUE RUN", "save", UITheme.GREEN, 60, 32)
		_continue_btn.tooltip_text = "Saved %s" % str(cr.get("saved_at", "")).replace("T", " ")
		_add_subline(_continue_btn, "%s · Inning %d · %s" % [DB.mode(str(cr.get("mode_id", "standard"))).get("name", "Game"),
			int(cr.get("inning", 1)), DB.arena(str(cr.get("arena_id", "steel_yard"))).get("name", "")], Color(0.75, 1.0, 0.85))
		_continue_btn.pressed.connect(func() -> void: Session.continue_saved_run())
		left.add_child(_continue_btn)
		_buttons.append(_continue_btn)
	var hero := _wide_button("PLAY", "play", UITheme.SCARLET, UITheme.BTN_H_HERO, 76, true)
	hero.name = "PlayButton"
	hero.pressed.connect(func() -> void:
		Session.menu_tab = "mode:" + _selected_mode()
		Router.goto("play_menu"))
	_hero_sub = _add_subline(hero, "", Color(1, 0.88, 0.85))
	left.add_child(hero)
	_buttons.append(hero)
	_hero = hero
	if Profile.promotion_available():
		UITheme.corner_badge(hero, "PROMOTION", UITheme.GOLD.darkened(0.35))
	left.add_child(_build_mode_switch())
	_refresh_hero()
	_add_up_next(left)

	left.add_child(_group_label("COLLECTION"))
	var coll := GridContainer.new()
	coll.columns = 2
	coll.add_theme_constant_override("h_separation", 10)
	coll.add_theme_constant_override("v_separation", 10)
	left.add_child(coll)
	var ready := 0
	for cid in DB.card_order:
		if Profile.can_upgrade_card(cid):
			ready += 1
	var gift := _free_gift()
	var tiles := [
		["CARD PACKS", "gift", UITheme.GOLD, func() -> void: Router.goto("packs"),
			"%d" % Profile.pack_count() if Profile.pack_count() > 0 else "", UITheme.SCARLET, "Open your packs, or buy more"],
		["CARDS & DECK", "deck", UITheme.BLUE, func() -> void:
			Session.menu_tab = "deck"
			Router.goto("deck_builder"),
			"REWARD!" if CollectionSets.claimable_count() > 0 else ("%d NEW" % Profile.fresh_card_count() if Profile.fresh_card_count() > 0 else ""),
			UITheme.GOLD.darkened(0.3) if CollectionSets.claimable_count() > 0 else UITheme.SCARLET, "Your collection and your 8-card deck"],
		["UPGRADE CARDS", "upgrade", UITheme.GREEN, func() -> void: Router.goto("card_upgrades"),
			"%d READY" % ready if ready > 0 else "", Color(0.16, 0.6, 0.35), "Level up cards with copies and coins"],
		["TEAM", "roster", UITheme.BLUE, func() -> void: Router.goto("roster"), "NEW TRAIT" if _trait_ready() else "",
			Color(0.16, 0.45, 0.75), "Defenders, captain, traits, gear and free agents"],
		["SHOP", "coin", UITheme.GOLD, func() -> void: Router.goto("shop"), "FREE GIFT" if not gift.is_empty() else "",
			UITheme.GOLD.darkened(0.35), "Daily deals, the free gift and free agents. New deals in %s" % UITheme.format_duration(Shop.seconds_to_refresh())],
		["SCOUTING BOOK", "enemy", Color("#FF6B3D"), func() -> void: Router.goto("scouting_book"),
			"%d NEW" % Scouting.new_count() if Scouting.new_count() > 0 else "", UITheme.SCARLET,
			"Every runner, boss and elite: what it does and which cards stop it (%d / %d scouted)" % [Scouting.met_count(), Scouting.all_keys().size()]],
	]
	for t in tiles:
		var b := _wide_button(t[0], t[1], t[2], 60, 28)
		b.custom_minimum_size.x = (COL_W - 10) / 2.0
		b.tooltip_text = t[6]
		b.pressed.connect(t[3])
		if t[4] != "":
			UITheme.corner_badge(b, t[4], t[5])
		if (t[0] == "CARD PACKS" and Profile.pack_count() > 0) or (t[0] == "SHOP" and not gift.is_empty()):
			var pulse := b.create_tween().set_loops()
			pulse.tween_property(b, "self_modulate", Color(1.22, 1.12, 0.8), 0.8).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(b, "self_modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
		coll.add_child(b)
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

	left.add_child(_group_label("MORE"))
	var more := HBoxContainer.new()
	more.add_theme_constant_override("separation", 8)
	left.add_child(more)
	var rest := [
		["PRACTICE", "practice", UITheme.PURPLE, func() -> void: Session.start(Session.new_run_config("practice")), "Test cards and runners freely. No rewards.", 1.0],
		["PROGRESSION", "progression", UITheme.GOLD, func() -> void: Router.goto("progression"), "Rank, missions, achievements, stadiums, gear and history", 1.2],
		["SETTINGS", "settings", UITheme.MUTED, func() -> void: Router.goto("settings"), "Display, graphics, audio, controls", 1.0],
		["", "exit", UITheme.SCARLET_DEEP, func() -> void:
			Profile.save_now()
			get_tree().quit(), "Exit: save and quit to desktop", 0.0],
	]
	for t in rest:
		var b := _wide_button(t[0], t[1], t[2], 50, 22)
		b.custom_minimum_size.x = 0
		b.tooltip_text = t[4]
		if float(t[5]) > 0.0:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.size_flags_stretch_ratio = float(t[5])
		else:
			b.name = "ExitButton"
			b.custom_minimum_size.x = 56
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.pressed.connect(t[3])
		more.add_child(b)
		_buttons.append(b)
		if t[0] in ["PRACTICE", "PROGRESSION"] and _new_player():
			_deemphasise(b, str(t[4]))

	# Staggered entrance.
	var i := 0
	for b in _buttons:
		UITheme.animate_in(b, 0.12 + i * 0.04, 0.96)
		i += 1

	_right = VBoxContainer.new()
	_right.name = "HubRight"
	_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right.offset_left = -RIGHT_W - 40.0
	_right.offset_right = -40.0
	_right.offset_top = 24.0
	_right.custom_minimum_size = Vector2(RIGHT_W, 0)
	_right.add_theme_constant_override("separation", 12)
	ui.add_child(_right)
	_build_right(true)
	_build_showcase_caption()
	var ver := UITheme.label("v%s  ·  Made with Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], 16, Color(1, 1, 1, 0.45))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -32
	ver.offset_bottom = -18
	ui.add_child(ver)
	if not bool(Profile.data.flags.get("tutorial_done", false)) and not "--no-help" in OS.get_cmdline_user_args():
		_show_welcome()
	_build_help()


## A left-aligned menu button with an icon (all main-menu entries use this).
func _wide_button(text: String, icon: String, accent: Color, height: float, size: int, hero := false) -> Button:
	var b := UITheme.button(text, "primary" if hero else "secondary", size, icon, accent)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(COL_W, height)
	b.add_theme_font_override("font", UITheme.font_display() if hero or height >= 60 else UITheme.font_header())
	if hero:
		b.add_theme_constant_override("icon_max_width", 64)
		b.add_theme_constant_override("h_separation", 18)
		for st in ["normal", "hover", "pressed", "focus"]:
			var s: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			s.content_margin_left = 30
			s.skew = Vector2(-0.12, 0)
			s.shadow_color = Color(0, 0, 0, 0.45)
			s.shadow_size = 10
			s.shadow_offset = Vector2(0, 4)
			if st == "focus":
				s.set_border_width_all(3)
				s.border_color = UITheme.GOLD
			b.add_theme_stylebox_override(st, s)
	else:
		# Thin coloured stripe on the left edge carries the button's category colour.
		var s: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
		s.border_width_left = 6
		s.border_color = Color(accent, 0.85)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_color_override("icon_normal_color", accent.lightened(0.25))
	return b


## A second, smaller line inside a big button (bottom-right), e.g. the selected mode.
func _add_subline(b: Button, text: String, color: Color) -> Label:
	var l := UITheme.label(text, UITheme.FS_SMALL, color, UITheme.font_body_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -24
	l.offset_bottom = -10
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	return l


func _group_label(text: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l := UITheme.label(text, UITheme.FS_MIN, Color(1, 1, 1, 0.6), UITheme.font_body_bold())
	hb.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.12)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(rule)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 4)
	m.add_child(hb)
	return m


# ---------------------------------------------------------------- PLAY + quick mode switch

## The mode PLAY opens with (the last one played, or the one picked on the quick switch).
func _selected_mode() -> String:
	var last := str(Profile.data.flags.get("last_mode", "standard"))
	if not DB.mode(last).has("name") or last in ["practice", "daily", "daily_long"] or MenuScreen.mode_locked_reason(last) != "":
		last = "standard"
	return last


func _refresh_hero() -> void:
	var m := _selected_mode()
	if _hero_sub:
		_hero_sub.text = "%s  ·  %s  ·  %s" % [DB.mode(m).get("name", "Game"), DB.difficulty(str(Profile.data.difficulty)).get("name", ""),
			DB.arena(str(Profile.data.arena)).get("name", "")]
	for id in _mode_chips.keys():
		(_mode_chips[id] as Button).set_pressed_no_signal(id == m)


## A row of four mode chips under PLAY: picking one changes what PLAY opens with.
func _build_mode_switch() -> Control:
	var row := HBoxContainer.new()
	row.name = "ModeSwitch"
	row.add_theme_constant_override("separation", 8)
	for qm in QUICK_MODES:
		var id: String = qm[0]
		if not DB.mode(id).has("name"):
			continue
		var lock := MenuScreen.mode_locked_reason(id)
		var b := UITheme.button(qm[1], "secondary", UITheme.FS_SMALL + 2, qm[2], UITheme.SCARLET)
		b.name = "Mode_" + id
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 46)
		b.add_theme_constant_override("icon_max_width", 22)
		b.add_theme_constant_override("h_separation", 6)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var s: StyleBoxFlat = b.get_theme_stylebox(st).duplicate()
			s.content_margin_left = 10
			s.content_margin_right = 10
			if st == "pressed":
				s.bg_color = UITheme.SCARLET_DEEP
				s.border_color = UITheme.SCARLET.lightened(0.3)
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
	b.self_modulate = Color(1, 1, 1, 0.5)
	b.tooltip_text = why
	b.mouse_entered.connect(func() -> void: b.self_modulate = Color.WHITE)
	b.mouse_exited.connect(func() -> void: b.self_modulate = Color(1, 1, 1, 0.5))
	b.focus_entered.connect(func() -> void: b.self_modulate = Color.WHITE)
	b.focus_exited.connect(func() -> void: b.self_modulate = Color(1, 1, 1, 0.5))


## "UP NEXT": the single most useful thing to do now (open packs, upgrade a card, a trait...),
## as a slim one-click strip under PLAY. The Daily has its own panel, so it is not repeated here.
func _add_up_next(parent: Control) -> void:
	if _new_player():
		return
	var list: Array = NextSteps.suggestions(true).filter(func(sg: Dictionary) -> bool: return str(sg.id) != "promotion")
	if list.is_empty():
		return
	var sg: Dictionary = list[0]
	var b := NextSteps.button(sg, COL_W)
	b.name = "UpNext"
	b.text = "UP NEXT:  " + str(sg.text)
	b.custom_minimum_size = Vector2(COL_W, 52)
	b.add_theme_font_size_override("font_size", UITheme.FS_LEAD)
	var sub := UITheme.label(str(sg.get("detail", "")), UITheme.FS_MIN, Color(1, 1, 1, 0.6), UITheme.font_body_bold())
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.offset_right = -18
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(sub)
	parent.add_child(b)
	_buttons.append(b)


## Tips: the "?" button (top right, left of the right column) and the first-visit hints, which
## wait until the first game is done (the welcome panel covers the very first launch).
func _build_help() -> void:
	var targets := func() -> Dictionary:
		var t := {"menu_home": _hero}
		var named := {"menu_daily": "DailyPanel", "menu_login": "LoginPanel", "menu_promotion": "PromotionButton", "menu_streak": "StreakFlame"}
		for k in named.keys():
			var n: Node = _right.find_child(named[k], true, false) if _right else null
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
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.offset_right = -RIGHT_W - 40.0 - 14.0
	help.offset_left = help.offset_right - UITheme.BTN_H
	help.offset_top = 24.0
	help.offset_bottom = 24.0 + UITheme.BTN_H
	ui.add_child(help)
	UITheme.animate_in(help, 0.5)
	if bool(Profile.data.flags.get("tutorial_done", false)) and not _new_player():
		Hints.first_visit(self, "main_menu", targets, extra.call(), 1.2)


# ---------------------------------------------------------------- right column: you + today

## Builds (or rebuilds after a claim) the right column.
func _build_right(animate := false) -> void:
	for c in _right.get_children():
		_right.remove_child(c)
		c.queue_free()
	var blocks: Array[Control] = []
	blocks.append(_build_profile_panel())
	blocks.append(_group_label("TODAY"))
	blocks.append(_build_login_panel())
	blocks.append(_build_daily_panel())
	blocks.append(MissionsPanel.compact_widget())   # Update 6 missions (src/ui/missions_panel.gd)
	var gift := _free_gift()
	if not gift.is_empty():
		blocks.append(_build_gift_button(gift))
	var k := 0
	for b in blocks:
		_right.add_child(b)
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


func _build_profile_panel() -> Control:
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.35), 16, Color(0.04, 0.07, 0.12, 0.9))
	p.name = "ProfilePanel"
	_profile_box = VBoxContainer.new()
	_profile_box.add_theme_constant_override("separation", 8)
	p.add_child(_profile_box)
	var d: Dictionary = Profile.data
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var div := Profile.division()
	var emblem_path := "res://assets/textures/ui/rank_%s.png" % div.id
	if ResourceLoader.exists(emblem_path):
		var em := TextureRect.new()
		em.texture = load(emblem_path)
		em.custom_minimum_size = Vector2(76, 76)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.tooltip_text = "%s division" % div.name
		head.add_child(em)
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", -2)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.add_child(UITheme.label(str(d.name).to_upper(), 34, UITheme.OFFWHITE, UITheme.font_display()))
	nb.add_child(UITheme.label("%s DIVISION  ·  %d RP" % [str(div.name).to_upper(), int(d.rp)], UITheme.FS_BODY, Color(div.color).lightened(0.15), UITheme.font_body_bold()))
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 8)
	lvl_row.add_child(UITheme.label("LEVEL %d" % int(d.level), UITheme.FS_BODY, UITheme.GREEN, UITheme.font_body_bold()))
	var xp := UITheme.bar(UITheme.GREEN, 10, Profile.xp_to_next(int(d.level)), int(d.xp))
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp.tooltip_text = "%d / %d XP to level %d" % [int(d.xp), Profile.xp_to_next(int(d.level)), int(d.level) + 1]
	lvl_row.add_child(xp)
	nb.add_child(lvl_row)
	head.add_child(nb)
	_profile_box.add_child(head)
	# Currencies.
	var cur := HBoxContainer.new()
	cur.add_theme_constant_override("separation", 20)
	var owned := 0
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned += 1
	for c in [["coin", UITheme.format_int(int(d.coins)), UITheme.GOLD, "Coins"], ["star", UITheme.format_int(int(d.stars)), UITheme.STAR, "Stars"],
			["collection", "%d/%d" % [owned, DB.card_order.size()], UITheme.OFFWHITE, "Cards collected"]]:
		var cb := HBoxContainer.new()
		cb.add_theme_constant_override("separation", 4)
		cb.tooltip_text = c[3]
		cb.add_child(UITheme.icon_rect(c[0], 26, c[2]))
		cb.add_child(UITheme.label(c[1], 28, c[2], UITheme.font_header()))
		cur.add_child(cb)
	_profile_box.add_child(cur)
	# Win streak flame and the first-win-of-the-day bonus.
	var bonus_row := HFlowContainer.new()
	bonus_row.add_theme_constant_override("h_separation", 8)
	bonus_row.add_theme_constant_override("v_separation", 6)
	var flame := UITheme.flame_chip(Profile.win_streak(), Profile.streak_bonus())
	flame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bonus_row.add_child(flame)
	if Profile.is_first_win_today():
		var fw := UITheme.badge("2× COINS ON TODAY'S FIRST WIN", Color(0.12, 0.45, 0.28, 0.95), UITheme.FS_MIN)
		fw.name = "FirstWinBadge"
		fw.mouse_filter = Control.MOUSE_FILTER_PASS
		fw.tooltip_text = "Your first win each day pays double coins."
		fw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bonus_row.add_child(fw)
	_profile_box.add_child(bonus_row)
	_season_bar = _build_season_bar()
	_profile_box.add_child(_season_bar)
	if Profile.promotion_available():
		var pb := UITheme.button("PROMOTION TO %s  ▶" % str(Profile.next_division().name).to_upper(), "primary", UITheme.FS_BODY, "crown", UITheme.GOLD.darkened(0.3))
		pb.name = "PromotionButton"
		pb.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
		pb.tooltip_text = "You have enough rank points: win the Promotion Challenge to move up a division"
		pb.pressed.connect(func() -> void:
			Session.menu_tab = "ranked"
			Router.goto("play_menu"))
		_profile_box.add_child(pb)
	return p


## Season tier bar: season name, tier, XP in the tier and time left. Opens the Season screen.
func _build_season_bar() -> Button:
	var cur := Season.current()
	var prog := Season.tier_progress()
	var tier := int(prog.get("tier", 0))
	var b := Button.new()
	b.name = "SeasonBar"
	b.custom_minimum_size = Vector2(0, 70)
	var accent := UITheme.PURPLE.lightened(0.15)
	var mk := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		var s := UITheme.panel_style(bg, border, bw, 10, 0)
		s.content_margin_left = 12
		s.content_margin_right = 12
		return s
	b.add_theme_stylebox_override("normal", mk.call(Color(0.1, 0.06, 0.18, 0.92), Color(accent, 0.55), 1))
	b.add_theme_stylebox_override("hover", mk.call(Color(0.16, 0.09, 0.28, 0.96), accent, 2))
	b.add_theme_stylebox_override("pressed", mk.call(Color(0.2, 0.1, 0.34, 0.98), Color.WHITE, 2))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.9), 2))
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -7.0))
	b.pressed.connect(func() -> void:
		Audio.ui("ui_click", -2.0)
		Router.goto("season"))
	UITheme.add_feedback(b, 1.02)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 12
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var tv := VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.add_theme_constant_override("separation", -8)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.custom_minimum_size = Vector2(62, 0)
	var tl := UITheme.label("TIER", UITheme.FS_MIN, Color(accent, 0.9), UITheme.font_body_bold())
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(tl)
	var tn := UITheme.label(str(tier), 36, UITheme.OFFWHITE, UITheme.font_display())
	tn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(tn)
	hb.add_child(tv)
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 3)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(mid)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sname := str(cur.get("name", "Season"))
	if str(cur.get("theme", "")) != "":
		sname += ": " + str(cur.theme)
	var name_l := UITheme.label(sname.to_upper(), UITheme.FS_LEAD, accent.lightened(0.2), UITheme.font_header())
	name_l.clip_text = true
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_l)
	var left_s := int(cur.get("seconds_left", 0))
	if left_s > 0:
		top.add_child(UITheme.label("ends in %s" % Season.countdown_text(left_s), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	mid.add_child(top)
	var need := maxi(1, int(prog.get("xp_need", Season.XP_PER_TIER)))
	var maxed := tier >= Season.TIERS
	var bar := UITheme.bar(accent, 10, float(need), float(int(prog.get("xp_in", 0))))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.add_child(bar)
	mid.add_child(UITheme.label("%d / %d XP to %s" % [int(prog.get("xp_in", 0)), need, "the next bonus Pro Pack" if maxed else "tier %d" % (tier + 1)],
		UITheme.FS_MIN, UITheme.OFFWHITE, UITheme.font_body_bold()))
	hb.add_child(UITheme.icon_rect("play", 18, Color(accent, 0.9)))
	b.tooltip_text = "Season Pass: claim a reward at every tier. Games, wins, missions and the Daily Challenge give season XP."
	var n := Season.claimable().size()
	if n > 0:
		UITheme.corner_badge(b, "%d TO CLAIM" % n, UITheme.GOLD.darkened(0.35))
		var pulse := b.create_tween().set_loops()
		pulse.tween_property(b, "self_modulate", Color(1.2, 1.12, 0.9), 0.8).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(b, "self_modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
	return b


# ---------------------------------------------------------------- login calendar

## Seven-day login calendar: each day's reward, the days already claimed, today's cell and the
## CLAIM button (or when the next reward comes).
func _build_login_panel() -> Control:
	var cal: Array = DailyRewards.calendar()
	var can := DailyRewards.can_claim()
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.85 if can else 0.35), 14, Color(0.06, 0.06, 0.04, 0.9), 2 if can else 1)
	p.name = "LoginPanel"
	_login_panel = p
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var ic := UITheme.icon_rect("gift", 30, UITheme.GOLD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UITheme.label("DAILY LOGIN", 28, UITheme.GOLD, UITheme.font_display()))
	var streak := DailyRewards.streak()
	var sub := "Day %d of 7" % DailyRewards.day() if can else "Next reward in %s" % UITheme.format_duration(Shop.seconds_to_refresh())
	if streak > 1:
		sub += "  ·  %d-day login streak" % streak
	hv.add_child(UITheme.label(sub, UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold()))
	if can:
		var cb := UITheme.button("CLAIM", "primary", UITheme.FS_LEAD, "gift", UITheme.GOLD.darkened(0.3))
		cb.name = "LoginClaim"
		cb.custom_minimum_size = Vector2(150, UITheme.BTN_H_SMALL)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cb.tooltip_text = "Claim today's login reward"
		cb.pressed.connect(_claim_login)
		head.add_child(cb)
	else:
		var done := UITheme.badge("CLAIMED", Color(0.13, 0.45, 0.28), UITheme.FS_MIN)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(done)
	if cal.is_empty():
		var none := UITheme.label("Log in every day for coins, packs and stars.", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
		vb.add_child(none)
		return p
	var row := HBoxContainer.new()
	row.name = "LoginDays"
	row.add_theme_constant_override("separation", 6)
	vb.add_child(row)
	for e in cal:
		row.add_child(_login_cell(e, can))
	if can:
		var pulse := p.create_tween().set_loops()
		pulse.tween_property(p, "self_modulate", Color(1.16, 1.1, 0.92), 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(p, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return p


func _login_cell(e: Dictionary, can: bool) -> Control:
	var day := int(e.get("day", 0))
	var claimed := bool(e.get("claimed", false))
	var today := bool(e.get("today", false))
	var big := day == 7
	var accent := UITheme.PURPLE.lightened(0.2) if big else UITheme.GOLD
	var bg := Color(0.05, 0.08, 0.13, 0.95)
	var border := Color(1, 1, 1, 0.1)
	if claimed:
		bg = Color(0.06, 0.2, 0.12, 0.9)
		border = Color(UITheme.GREEN, 0.4)
	elif today:
		bg = Color(accent.darkened(0.6), 0.95)
		border = accent
	elif big:
		border = Color(accent, 0.5)
	var p := PanelContainer.new()
	p.name = "LoginDay%d" % day
	p.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 2 if today and not claimed else 1, 8, 4))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var reward: Variant = e.get("reward", {})
	var txt := str(e.get("text", DailyRewards.reward_text(reward) if typeof(reward) == TYPE_DICTIONARY else ""))
	p.tooltip_text = "Day %d: %s%s" % [day, txt if txt != "" else "reward", "  (claimed)" if claimed else ("  (today)" if today else "")]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(vb)
	var dl := UITheme.label("DAY %d" % day, UITheme.FS_MIN, accent.lightened(0.2) if today and not claimed else UITheme.MUTED, UITheme.font_body_bold())
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(dl)
	var parts := UITheme.reward_parts(reward)
	var part: Array = parts[0] if not parts.is_empty() else ["gift", "?", UITheme.MUTED]
	var icon := UITheme.icon_rect("check" if claimed else str(part[0]), 26, UITheme.GREEN if claimed else part[2])
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(icon)
	var amount := str(part[1])
	if amount.length() > 6:
		amount = amount.substr(0, 5)
	var al := UITheme.label(amount, UITheme.FS_MIN, UITheme.MUTED if claimed else part[2], UITheme.font_header())
	al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(al)
	if today and can:
		p.resized.connect(func() -> void: p.pivot_offset = p.size * 0.5)
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "scale", Vector2(1.06, 1.06), 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	return p


## CLAIM: pays today's login reward, floats the reward up from today's cell and rebuilds the column.
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
	_build_right(false)


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


## Free gift waiting in the Shop: a slim gold button at the bottom of TODAY.
func _build_gift_button(gift: Dictionary) -> Control:
	var b := UITheme.button("FREE GIFT IN THE SHOP  ▶", "secondary", UITheme.FS_LEAD, "gift", UITheme.GOLD)
	b.name = "FreeGiftButton"
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 50)
	var s: StyleBoxFlat = b.get_theme_stylebox("normal").duplicate()
	s.border_color = Color(UITheme.GOLD, 0.7)
	s.bg_color = Color(0.14, 0.11, 0.03, 0.92)
	b.add_theme_stylebox_override("normal", s)
	b.add_theme_color_override("font_color", UITheme.GOLD.lightened(0.2))
	b.add_theme_color_override("icon_normal_color", UITheme.GOLD)
	var what := str(gift.get("title", ""))
	b.tooltip_text = "Today's free gift%s. Open the Shop to take it." % ((": " + what) if what != "" else "")
	b.pressed.connect(func() -> void: Router.goto("shop"))
	_gift_button = b
	return b


# ---------------------------------------------------------------- daily challenge

## Daily Challenge highlight: today's rules, best score, streak, countdown and a PLAY button
## that opens the Play screen with the Daily Challenge selected.
func _build_daily_panel() -> Control:
	var rules := DailyChallenge.today_rules()
	var played := DailyChallenge.played()
	var p := UITheme.card_panel(Color(TODAY_ACCENT, 0.85 if not played else 0.45), 14, Color(0.09, 0.06, 0.05, 0.9), 2)
	p.name = "DailyPanel"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var ic := UITheme.icon_rect("calendar", 30, TODAY_ACCENT.lightened(0.2))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UITheme.label("DAILY CHALLENGE", 28, TODAY_ACCENT.lightened(0.25), UITheme.font_display()))
	var md := DailyChallenge.modifier_def(str(rules.modifier))
	var sub := UITheme.label("%s · %d innings · %s" % [DB.difficulty(str(rules.difficulty)).name, int(rules.innings), str(md.get("name", ""))],
		UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	sub.clip_text = true
	hv.add_child(sub)
	var bd := UITheme.badge("NEW TODAY" if not played else "BEST %s" % UITheme.format_int(DailyChallenge.best_score()),
		TODAY_ACCENT.darkened(0.2) if not played else Color(0.13, 0.4, 0.25))
	bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bd)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var streak := DailyChallenge.current_streak()
	var st := HBoxContainer.new()
	st.add_theme_constant_override("separation", 6)
	st.add_child(UITheme.icon_rect("fire", 20, TODAY_ACCENT.lightened(0.2)))
	st.add_child(UITheme.label("%d-day streak" % streak if streak > 0 else "Start a streak today", UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold()))
	info.add_child(st)
	_daily_countdown = UITheme.label("New challenge in %s" % DailyChallenge.countdown_text(), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	info.add_child(_daily_countdown)
	var go := UITheme.button("PLAY DAILY", "primary", UITheme.FS_LEAD, "play", TODAY_ACCENT.darkened(0.15))
	go.name = "DailyButton"
	go.custom_minimum_size = Vector2(180, UITheme.BTN_H_SMALL)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.tooltip_text = "Open today's Daily Challenge on the Play screen"
	go.pressed.connect(func() -> void:
		Session.menu_tab = "daily"
		Router.goto("play_menu"))
	row.add_child(go)
	if not played:
		var pulse := p.create_tween().set_loops()
		pulse.tween_property(p, "self_modulate", Color(1.18, 1.08, 0.95), 0.9).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(p, "self_modulate", Color.WHITE, 0.9).set_trans(Tween.TRANS_SINE)
	return p


func _update_daily_countdown(delta: float) -> void:
	_countdown_t -= delta
	if _countdown_t > 0.0 or _daily_countdown == null or not is_instance_valid(_daily_countdown):
		return
	_countdown_t = 1.0
	_daily_countdown.text = "New challenge in %s" % DailyChallenge.countdown_text()


# ---------------------------------------------------------------- idle showcase

## Bottom-right caption naming the defender who is showing off.
func _build_showcase_caption() -> void:
	_caption = VBoxContainer.new()
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_caption.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_caption.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_caption.offset_right = -40
	_caption.offset_bottom = -56
	_caption.alignment = BoxContainer.ALIGNMENT_END
	_caption.add_theme_constant_override("separation", -6)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.modulate.a = 0.0
	ui.add_child(_caption)


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


## Esc closes the welcome panel (the main menu has nothing to go back to); a first direction key
## or d-pad press focuses PLAY so the hub can be driven without a mouse.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _welcome_later and is_instance_valid(_welcome_later):
		get_viewport().set_input_as_handled()
		Audio.ui("ui_back")
		_welcome_later.pressed.emit()
		_welcome_later = null
		return
	# Keyboard / controller: the first direction press focuses PLAY.
	if ui and MenuScreen.focus_on_nav(ui, event, _hero):
		get_viewport().set_input_as_handled()


func _show_welcome() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.08, 0.14, 0.96), Color(UITheme.SCARLET, 0.7), 2, 12, 22))
	# Grows up and left from the bottom-right corner, so its buttons are never cut off.
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = -600
	p.offset_top = -40
	p.offset_right = -40
	p.offset_bottom = -40
	p.custom_minimum_size = Vector2(560, 0)
	ui.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("WELCOME, MANAGER!", "info", UITheme.GOLD, 34))
	var txt := UITheme.label("Rival runners are storming the Steel Yard. Your six defenders throw at them automatically — you position the team and play ability cards to stop runners before they reach home plate.\n\nYour first game is a short Quick Defense with step-by-step tips. Finish it to earn your first card pack!", 19, UITheme.OFFWHITE)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(520, 0)
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
