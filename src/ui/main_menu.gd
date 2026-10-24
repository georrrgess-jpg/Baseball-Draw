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
var _profile_box: VBoxContainer


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
	stadium.scoreboard_ui.flash("BASEBALL DRAW", 9999.0)

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

	_build_ui()
	Audio.play_music("menu_theme")
	Audio.play_ambience(["stadium_crowd", ""])


func _spawn_team() -> void:
	var colors: Dictionary = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.home).colors
	var spots := [
		[Vector3(2.4, 0, 5.4), "ready"], [Vector3(4.4, 0, 3.6), "idle"], [Vector3(6.6, 0, 4.6), "victory"],
		[Vector3(3.0, 0, 1.4), "idle"], [Vector3(5.6, 0, 0.8), "ready"], [Vector3(8.2, 0, 2.2), "idle"],
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
		var to := Vector3(4.0, 0, 13.5) - cm.position
		cm.rotation.y = atan2(to.x, to.z) + randf_range(-0.35, 0.35)
		models.append(cm)
		var shadow := Enemy._make_blob_shadow(0.5)
		cm.add_child(shadow)


func _process(delta: float) -> void:
	_t += delta
	# Slow cinematic orbit in front of home plate.
	camera.position = Vector3(0.2 + sin(_t * 0.06) * 1.4, 2.7 + sin(_t * 0.09) * 0.25, 12.8 + cos(_t * 0.05) * 0.6)
	camera.look_at(Vector3(1.6 + sin(_t * 0.04) * 0.4, 1.9, 1.5), Vector3.UP)
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
	g.set_color(0, Color(0.03, 0.05, 0.1, 0.92))
	g.set_color(1, Color(0.03, 0.05, 0.1, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	grad.texture = gt
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.custom_minimum_size = Vector2(900, 0)
	grad.size = Vector2(900, 1080)
	grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grad)

	var left := VBoxContainer.new()
	left.position = Vector2(70, 40)
	left.add_theme_constant_override("separation", 10)
	ui.add_child(left)
	var logo_path := "res://assets/textures/logo/logo.png"
	if ResourceLoader.exists(logo_path):
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.custom_minimum_size = Vector2(620, 300)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		left.add_child(logo)
	else:
		left.add_child(UITheme.title("BASEBALL", 110, UITheme.OFFWHITE))
		left.add_child(UITheme.title("DRAW", 150, UITheme.SCARLET))
	var tag := UITheme.label("DRAW YOUR HAND. DEFEND THE DIAMOND.", 26, UITheme.OFFWHITE, UITheme.font_brush())
	left.add_child(tag)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	left.add_child(spacer)

	var items := [
		["PLAY", UITheme.SCARLET, func() -> void: Router.goto("play_menu")],
		["CONTINUE RUN", UITheme.GREEN, func() -> void: Session.continue_saved_run()],
		["DECK BUILDER", UITheme.BLUE, func() -> void:
			Session.menu_tab = "deck"
			Router.goto("deck_builder")],
		["ROSTER", UITheme.BLUE, func() -> void: Router.goto("roster")],
		["COLLECTION", UITheme.BLUE, func() -> void:
			Session.menu_tab = "collection"
			Router.goto("deck_builder")],
		["PRACTICE", UITheme.PURPLE, func() -> void: Session.start(Session.new_run_config("practice"))],
		["PROGRESSION", UITheme.GOLD, func() -> void: Router.goto("progression")],
		["SETTINGS", UITheme.MUTED, func() -> void: Router.goto("settings")],
		["EXIT", UITheme.SCARLET_DEEP, func() -> void:
			Profile.save_now()
			get_tree().quit()],
	]
	var i := 0
	for it in items:
		var b := UITheme.menu_button(it[0], it[1], 38)
		b.custom_minimum_size = Vector2(430, 58)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(it[2])
		left.add_child(b)
		_buttons.append(b)
		if it[0] == "CONTINUE RUN":
			_continue_btn = b
			b.disabled = not Profile.has_saved_run()
			if Profile.has_saved_run():
				var cr: Dictionary = Profile.data.current_run
				b.tooltip_text = "%s · Inning %d · %s" % [DB.mode(cr.get("mode_id", "standard")).name, int(cr.get("inning", 1)), cr.get("saved_at", "")]
		# Slide-in animation.
		b.modulate.a = 0.0
		var tw := b.create_tween()
		tw.tween_interval(0.15 + i * 0.05)
		tw.tween_property(b, "modulate:a", 1.0, 0.25)
		i += 1

	_build_profile_panel()
	var ver := UITheme.label("v%s  ·  Made with Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string], 16, Color(1, 1, 1, 0.4))
	ver.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-380, -36)
	ui.add_child(ver)
	if not bool(Profile.data.flags.get("tutorial_done", false)):
		_show_welcome()


func _build_profile_panel() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.04, 0.07, 0.12, 0.88), Color(UITheme.GOLD, 0.35), 1, 12, 18))
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = Vector2(-470, 40)
	p.custom_minimum_size = Vector2(430, 0)
	ui.add_child(p)
	_profile_box = VBoxContainer.new()
	_profile_box.add_theme_constant_override("separation", 8)
	p.add_child(_profile_box)
	var d: Dictionary = Profile.data
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	var div := Profile.division()
	var emblem_path := "res://assets/textures/ui/rank_%s.png" % div.id
	if ResourceLoader.exists(emblem_path):
		var em := TextureRect.new()
		em.texture = load(emblem_path)
		em.custom_minimum_size = Vector2(84, 84)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		head.add_child(em)
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", -2)
	nb.add_child(UITheme.label(str(d.name).to_upper(), 34, UITheme.OFFWHITE, UITheme.font_display()))
	nb.add_child(UITheme.label("%s DIVISION · %d RP" % [str(div.name).to_upper(), int(d.rp)], 20, Color(div.color), UITheme.font_body_bold()))
	nb.add_child(UITheme.label("Account level %d" % int(d.level), 20, UITheme.MUTED, UITheme.font_body_bold()))
	head.add_child(nb)
	_profile_box.add_child(head)
	var xp := ProgressBar.new()
	xp.max_value = Profile.xp_to_next(int(d.level))
	xp.value = int(d.xp)
	xp.custom_minimum_size = Vector2(0, 10)
	xp.show_percentage = false
	xp.add_theme_stylebox_override("fill", UITheme.panel_style(UITheme.GREEN, Color(0, 0, 0, 0), 0, 4, 0))
	xp.tooltip_text = "%d / %d XP" % [int(d.xp), Profile.xp_to_next(int(d.level))]
	_profile_box.add_child(xp)
	var cur := HBoxContainer.new()
	cur.add_theme_constant_override("separation", 20)
	var cb := HBoxContainer.new()
	cb.add_child(UITheme.icon_rect("coin", 30, UITheme.GOLD))
	cb.add_child(UITheme.label(UITheme.format_int(int(d.coins)), 30, UITheme.GOLD, UITheme.font_header()))
	cur.add_child(cb)
	var sb := HBoxContainer.new()
	sb.add_child(UITheme.icon_rect("star", 30, Color(0.7, 0.85, 1.0)))
	sb.add_child(UITheme.label(UITheme.format_int(int(d.stars)), 30, Color(0.7, 0.85, 1.0), UITheme.font_header()))
	cur.add_child(sb)
	var owned := 0
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			owned += 1
	var cards := UITheme.label("Cards %d/%d" % [owned, DB.card_order.size()], 20, UITheme.MUTED, UITheme.font_body_bold())
	cur.add_child(cards)
	_profile_box.add_child(cur)
	_profile_box.add_child(UITheme.hsep())
	_profile_box.add_child(UITheme.header("RECENT PROGRESS", 24, UITheme.GOLD))
	var hist: Array = d.history
	if hist.is_empty():
		_profile_box.add_child(UITheme.label("No games played yet. Hit PLAY to start your first siege!", 18, UITheme.MUTED))
	for h in hist.slice(0, 3):
		var txt := "%s  %s · %s · inning %d · %s pts" % ["W" if h.won else "L", DB.mode(h.mode).name, DB.difficulty(h.difficulty).name, int(h.inning), UITheme.format_int(int(h.score))]
		_profile_box.add_child(UITheme.label(txt, 18, UITheme.GREEN if h.won else Color(1.0, 0.55, 0.5), UITheme.font_body()))
	if Profile.promotion_available():
		_profile_box.add_child(UITheme.label("★ Promotion Challenge to %s available!" % Profile.next_division().name, 19, UITheme.GOLD, UITheme.font_body_bold()))
	var next_unlock := _next_unlock_text()
	if next_unlock != "":
		_profile_box.add_child(UITheme.label(next_unlock, 17, Color(0.75, 0.85, 1.0)))


func _next_unlock_text() -> String:
	for id in DB.defender_order:
		if not Profile.is_defender_unlocked(id):
			return "Next unlock: %s at account level %d" % [DB.defender(id).name, int(DB.defender(id).unlock.value)]
	return ""


func _show_welcome() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.08, 0.14, 0.96), Color(UITheme.SCARLET, 0.7), 2, 12, 22))
	p.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	p.position = Vector2(-60, -330)
	p.custom_minimum_size = Vector2(620, 0)
	ui.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	vb.add_child(UITheme.header("WELCOME, MANAGER!", 34, UITheme.GOLD))
	var txt := UITheme.label("Rival runners are storming the Steel Yard. Position your six defenders, draw ability cards and keep runners off home plate. Three runs and the game is over.\n\nStart with QUICK DEFENSE on Rookie or Standard — three innings, about ten minutes.", 19, UITheme.OFFWHITE)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(580, 0)
	vb.add_child(txt)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var go := UITheme.small_button("Play Quick Defense", UITheme.SCARLET, 22)
	go.pressed.connect(func() -> void:
		Profile.data.flags.tutorial_done = true
		Profile.save_soon()
		var cfg := Session.new_run_config("quick")
		Session.start(cfg))
	hb.add_child(go)
	var later := UITheme.small_button("Look around first", UITheme.BLUE, 22)
	later.pressed.connect(func() -> void:
		Profile.data.flags.tutorial_done = true
		Profile.save_soon()
		p.queue_free())
	hb.add_child(later)
	vb.add_child(hb)
