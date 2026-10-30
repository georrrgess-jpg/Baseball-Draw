extends Node3D
## Main menu: a live 3D stadium at sunset with the team warming up (throwing and
## catching), a slow cinematic camera, the Baseball Draw logo, navigation and the
## player's profile panel.

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

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	# Left gradient for legibility.
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.05, 0.1, 0.94))
	g.set_color(1, Color(0.03, 0.05, 0.1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.custom_minimum_size = Vector2(980, 0)
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)

	var left := VBoxContainer.new()
	left.position = Vector2(70, 30)
	left.custom_minimum_size = Vector2(COL_W, 0)
	left.add_theme_constant_override("separation", 10)
	ui.add_child(left)
	var logo_path := "res://assets/textures/logo/logo.png"
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.custom_minimum_size = Vector2(COL_W, 236)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		left.add_child(logo)
	else:
		left.add_child(UITheme.title("BASEBALL", 110, UITheme.OFFWHITE))
		left.add_child(UITheme.title("DRAW", 150, UITheme.SCARLET))
	var tag := UITheme.label("DRAW YOUR HAND. DEFEND THE DIAMOND.", 24, UITheme.OFFWHITE, UITheme.font_brush())
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	left.add_child(spacer)

	# Continue (only when a run is saved) sits right above the hero PLAY button.
	if Profile.has_saved_run():
		var cr: Dictionary = Profile.data.current_run
		_continue_btn = _wide_button("CONTINUE RUN", "save", UITheme.GREEN, 64, 34)
		_continue_btn.tooltip_text = "Saved %s" % str(cr.get("saved_at", "")).replace("T", " ")
		_add_subline(_continue_btn, "%s · Inning %d · %s" % [DB.mode(str(cr.get("mode_id", "standard"))).name,
			int(cr.get("inning", 1)), DB.arena(str(cr.get("arena_id", "steel_yard"))).name], Color(0.75, 1.0, 0.85))
		_continue_btn.pressed.connect(func() -> void: Session.continue_saved_run())
		left.add_child(_continue_btn)
		_buttons.append(_continue_btn)
	var hero := _wide_button("PLAY", "play", UITheme.SCARLET, UITheme.BTN_H_HERO, 76, true)
	hero.pressed.connect(func() -> void: Router.goto("play_menu"))
	var last_mode := str(Profile.data.flags.get("last_mode", "standard"))
	if not DB.mode(last_mode).has("name"):
		last_mode = "standard"
	_add_subline(hero, "%s  ·  %s  ·  %s" % [DB.mode(last_mode).name, DB.difficulty(str(Profile.data.difficulty)).name,
		DB.arena(str(Profile.data.arena)).name], Color(1, 0.88, 0.85))
	left.add_child(hero)
	_buttons.append(hero)
	_hero = hero
	if Profile.promotion_available():
		_add_badge(hero, "PROMOTION", UITheme.GOLD.darkened(0.35))
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
	var tiles := [
		["CARD PACKS", "gift", UITheme.GOLD, func() -> void: Router.goto("packs"),
			"%d" % Profile.pack_count() if Profile.pack_count() > 0 else "", UITheme.SCARLET],
		["CARDS & DECK", "deck", UITheme.BLUE, func() -> void:
			Session.menu_tab = "deck"
			Router.goto("deck_builder"),
			"REWARD!" if CollectionSets.claimable_count() > 0 else ("%d NEW" % Profile.fresh_card_count() if Profile.fresh_card_count() > 0 else ""),
			UITheme.GOLD.darkened(0.3) if CollectionSets.claimable_count() > 0 else UITheme.SCARLET],
		["UPGRADE CARDS", "upgrade", UITheme.GREEN, func() -> void: Router.goto("card_upgrades"),
			"%d READY" % ready if ready > 0 else "", Color(0.16, 0.6, 0.35)],
		["TEAM", "roster", UITheme.BLUE, func() -> void: Router.goto("roster"), "NEW TRAIT" if _trait_ready() else "", Color(0.16, 0.45, 0.75)],
	]
	for t in tiles:
		var b := _wide_button(t[0], t[1], t[2], 62, 30)
		b.custom_minimum_size.x = (COL_W - 10) / 2.0
		b.pressed.connect(t[3])
		if t[4] != "":
			_add_badge(b, t[4], t[5])
		if t[0] == "CARD PACKS" and Profile.pack_count() > 0:
			var pulse := b.create_tween().set_loops()
			pulse.tween_property(b, "self_modulate", Color(1.22, 1.12, 0.8), 0.8).set_trans(Tween.TRANS_SINE)
			pulse.tween_property(b, "self_modulate", Color.WHITE, 0.8).set_trans(Tween.TRANS_SINE)
		coll.add_child(b)
		_buttons.append(b)
		if t[0] == "UPGRADE CARDS" and ready == 0 and _new_player():
			_deemphasise(b, "Upgrade cards with copies from packs. Open some packs first.")

	left.add_child(_group_label("MORE"))
	var more := GridContainer.new()
	more.columns = 2
	more.add_theme_constant_override("h_separation", 10)
	more.add_theme_constant_override("v_separation", 10)
	left.add_child(more)
	var rest := [
		["PRACTICE", "practice", UITheme.PURPLE, func() -> void: Session.start(Session.new_run_config("practice")), "Test cards and runners freely. No rewards."],
		["PROGRESSION", "progression", UITheme.GOLD, func() -> void: Router.goto("progression"), "Rank, achievements, stadiums, gear and history"],
		["SETTINGS", "settings", UITheme.MUTED, func() -> void: Router.goto("settings"), "Display, graphics, audio, controls"],
		["EXIT", "exit", UITheme.SCARLET_DEEP, func() -> void:
			Profile.save_now()
			get_tree().quit(), "Save and quit to desktop"],
	]
	for t in rest:
		var b := _wide_button(t[0], t[1], t[2], 52, 26)
		b.custom_minimum_size.x = (COL_W - 10) / 2.0
		b.tooltip_text = t[4]
		b.pressed.connect(t[3])
		more.add_child(b)
		_buttons.append(b)
		if t[0] in ["PRACTICE", "PROGRESSION"] and _new_player():
			_deemphasise(b, str(t[4]))

	# Staggered entrance.
	var i := 0
	for b in _buttons:
		UITheme.animate_in(b, 0.12 + i * 0.045, 0.96)
		i += 1

	_build_profile_panel()
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
func _add_subline(b: Button, text: String, color: Color) -> void:
	var l := UITheme.label(text, UITheme.FS_SMALL, color, UITheme.font_body_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -24
	l.offset_bottom = -10
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)


## Notification-style badge on the button's top-right corner, overlapping the edge, so it never
## covers the button's label (the half-width tiles have no room beside the text).
func _add_badge(b: Button, text: String, color: Color) -> void:
	var bd := UITheme.badge(text, color)
	bd.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	bd.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	bd.grow_vertical = Control.GROW_DIRECTION_END
	bd.offset_right = 8
	bd.offset_top = -12
	bd.z_index = 1
	b.add_child(bd)


func _group_label(text: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var l := UITheme.label(text, UITheme.FS_MIN, Color(1, 1, 1, 0.55), UITheme.font_body_bold())
	hb.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(1, 1, 1, 0.12)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(rule)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_top", 6)
	m.add_child(hb)
	return m


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
	b.custom_minimum_size = Vector2(COL_W, UITheme.BTN_H)
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


## Tips: the "?" button (top right, left of the profile panel) and the first-visit hints, which
## wait until the first game is done (the welcome panel covers the very first launch).
func _build_help() -> void:
	var targets := func() -> Dictionary:
		var t := {"menu_home": _hero}
		var dp := _right.get_node_or_null("DailyPanel") if _right else null
		if dp:
			t["menu_daily"] = dp
		var pb := _profile_box.find_child("PromotionButton", true, false) if _profile_box else null
		if pb:
			t["menu_promotion"] = pb
		return t
	var extra := func() -> Array: return ["menu_promotion"] if Profile.promotion_available() else []
	var help := Hints.help_button(self, "main_menu", targets, extra)
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	help.offset_right = -500.0
	help.offset_left = -500.0 - UITheme.BTN_H
	help.offset_top = 36.0
	help.offset_bottom = 36.0 + UITheme.BTN_H
	ui.add_child(help)
	UITheme.animate_in(help, 0.5)
	if bool(Profile.data.flags.get("tutorial_done", false)) and not _new_player():
		Hints.first_visit(self, "main_menu", targets, extra.call(), 1.2)


func _build_profile_panel() -> void:
	# Right column: the profile panel, then the Daily Challenge highlight.
	_right = VBoxContainer.new()
	_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right.offset_left = -480.0
	_right.offset_right = -40.0
	_right.offset_top = 36.0
	_right.custom_minimum_size = Vector2(440, 0)
	_right.add_theme_constant_override("separation", 14)
	ui.add_child(_right)
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.35), 18, Color(0.04, 0.07, 0.12, 0.88))
	_right.add_child(p)
	UITheme.animate_in(p, 0.25)
	_build_daily_panel()
	_right.add_child(MissionsPanel.compact_widget())   # Update 6 missions (src/ui/missions_panel.gd)
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
		em.custom_minimum_size = Vector2(88, 88)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		em.tooltip_text = "%s division" % div.name
		head.add_child(em)
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", -2)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nb.add_child(UITheme.label(str(d.name).to_upper(), 36, UITheme.OFFWHITE, UITheme.font_display()))
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
	var cur := HBoxContainer.new()
	cur.add_theme_constant_override("separation", 22)
	var cb := HBoxContainer.new()
	cb.add_child(UITheme.icon_rect("coin", 28, UITheme.GOLD))
	cb.add_child(UITheme.label(UITheme.format_int(int(d.coins)), 30, UITheme.GOLD, UITheme.font_header()))
	cur.add_child(cb)
	var sb := HBoxContainer.new()
	sb.add_child(UITheme.icon_rect("star", 28, UITheme.STAR))
	sb.add_child(UITheme.label(UITheme.format_int(int(d.stars)), 30, UITheme.STAR, UITheme.font_header()))
	cur.add_child(sb)
	var owned := 0
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned += 1
	var cards := HBoxContainer.new()
	cards.add_child(UITheme.icon_rect("collection", 28, UITheme.OFFWHITE))
	cards.add_child(UITheme.label("%d/%d" % [owned, DB.card_order.size()], 30, UITheme.OFFWHITE, UITheme.font_header()))
	cards.tooltip_text = "Cards collected"
	cur.add_child(cards)
	_profile_box.add_child(cur)
	_profile_box.add_child(UITheme.hsep())
	_profile_box.add_child(UITheme.section_header("RECENT GAMES", "inning", UITheme.GOLD, 24))
	var hist: Array = d.history
	if hist.is_empty():
		var none := UITheme.label("No games played yet. Hit PLAY to start your first game!", UITheme.FS_SMALL, UITheme.MUTED)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_profile_box.add_child(none)
	for h in hist.slice(0, 3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var pill := UITheme.badge("W" if h.won else "L", Color(0.13, 0.55, 0.3) if h.won else Color(0.6, 0.15, 0.17), UITheme.FS_MIN)
		pill.custom_minimum_size = Vector2(30, 0)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(pill)
		var txt := UITheme.label("%s · %s · inn. %d" % [DB.mode(str(h.mode)).name, DB.difficulty(str(h.difficulty)).name, int(h.inning)], UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body())
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.clip_text = true
		row.add_child(txt)
		row.add_child(UITheme.label(UITheme.format_int(int(h.score)), UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold()))
		_profile_box.add_child(row)
	if Profile.promotion_available():
		var pb := UITheme.button("PROMOTION TO %s  ▶" % str(Profile.next_division().name).to_upper(), "primary", UITheme.FS_BODY, "crown", UITheme.GOLD.darkened(0.3))
		pb.name = "PromotionButton"
		pb.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
		pb.tooltip_text = "You have enough rank points: win the Promotion Challenge to move up a division"
		pb.pressed.connect(func() -> void:
			Session.menu_tab = "ranked"
			Router.goto("play_menu"))
		_profile_box.add_child(pb)
	var next_unlock := _next_unlock_text()
	if next_unlock != "":
		var nu := HBoxContainer.new()
		nu.add_theme_constant_override("separation", 8)
		nu.add_child(UITheme.icon_rect("lock", 20, Color(0.75, 0.85, 1.0)))
		nu.add_child(UITheme.label(next_unlock, UITheme.FS_MIN + 1, Color(0.75, 0.85, 1.0)))
		_profile_box.add_child(nu)


# ---------------------------------------------------------------- daily challenge

## Daily Challenge highlight: today's rules, best score, streak, countdown and a PLAY button
## that opens the Play screen with the Daily Challenge selected.
func _build_daily_panel() -> void:
	const ACCENT := Color("#FF8A3D")
	var rules := DailyChallenge.today_rules()
	var played := DailyChallenge.played()
	var p := UITheme.card_panel(Color(ACCENT, 0.85 if not played else 0.45), 16, Color(0.09, 0.06, 0.05, 0.9), 2)
	p.name = "DailyPanel"
	_right.add_child(p)
	UITheme.animate_in(p, 0.4)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var ic := UITheme.icon_rect("calendar", 34, ACCENT.lightened(0.2))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(ic)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -6)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(UITheme.label("DAILY CHALLENGE", 30, ACCENT.lightened(0.25), UITheme.font_display()))
	var md := DailyChallenge.modifier_def(str(rules.modifier))
	var sub := UITheme.label("%s · %d innings · %s" % [DB.difficulty(str(rules.difficulty)).name, int(rules.innings), str(md.get("name", ""))],
		UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	sub.clip_text = true
	hv.add_child(sub)
	var bd := UITheme.badge("NEW TODAY" if not played else "BEST %s" % UITheme.format_int(DailyChallenge.best_score()),
		ACCENT.darkened(0.2) if not played else Color(0.13, 0.4, 0.25))
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
	st.add_child(UITheme.icon_rect("fire", 20, ACCENT.lightened(0.2)))
	st.add_child(UITheme.label("%d-day streak" % streak if streak > 0 else "Start a streak today", UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold()))
	info.add_child(st)
	_daily_countdown = UITheme.label("New challenge in %s" % DailyChallenge.countdown_text(), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	info.add_child(_daily_countdown)
	var go := UITheme.button("PLAY DAILY", "primary", UITheme.FS_LEAD, "play", ACCENT.darkened(0.15))
	go.name = "DailyButton"
	go.custom_minimum_size = Vector2(190, UITheme.BTN_H)
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


func _update_daily_countdown(delta: float) -> void:
	_countdown_t -= delta
	if _countdown_t > 0.0 or _daily_countdown == null:
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


func _next_unlock_text() -> String:
	for id in DB.defender_order:
		if not Profile.is_defender_unlocked(id):
			return "Next unlock: %s at account level %d" % [DB.defender(id).name, int(DB.defender(id).unlock.value)]
	return ""


## Esc closes the welcome panel (the main menu has nothing to go back to).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and _welcome_later and is_instance_valid(_welcome_later):
		get_viewport().set_input_as_handled()
		Audio.ui("ui_back")
		_welcome_later.pressed.emit()
		_welcome_later = null


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
