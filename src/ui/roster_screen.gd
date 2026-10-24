extends Node3D
## Roster: inspect defenders on a 3D showcase stage (drag to rotate), level-up traits,
## equip gear, choose the team uniform, pick the six-player team and the captain.

var selected := "ace"
var model: CharacterModel
var stage: Node3D
var camera: Camera3D
var ui: Control
var _list: VBoxContainer
var _info: VBoxContainer
var _team_strip: HBoxContainer
var _drag := false
var _yaw := 0.0
var _screen: MenuScreen


func _ready() -> void:
	_build_stage()
	var layer := CanvasLayer.new()
	add_child(layer)
	_screen = MenuScreen.new()
	layer.add_child(_screen)
	_screen.setup_screen("ROSTER", "Your defenders, their growth, gear and the starting six")
	# Make the menu background transparent in the middle so the 3D stage shows through.
	for i in 4:
		var c := _screen.get_child(i)
		if c is CanvasItem and not (c is MarginContainer):
			(c as CanvasItem).visible = false
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.content.add_child(body)
	_screen.content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lp := MenuScreen.panel()
	lp.custom_minimum_size = Vector2(330, 0)
	body.add_child(lp)
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(ls)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(300, 0)
	_list.add_theme_constant_override("separation", 6)
	ls.add_child(_list)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)
	var rp := MenuScreen.panel(Color(0.04, 0.07, 0.12, 0.92))
	rp.custom_minimum_size = Vector2(560, 0)
	body.add_child(rp)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rs)
	_info = VBoxContainer.new()
	_info.custom_minimum_size = Vector2(526, 0)
	_info.add_theme_constant_override("separation", 8)
	rs.add_child(_info)
	var bottom := MenuScreen.panel(Color(0.03, 0.05, 0.09, 0.92), Color(UITheme.SCARLET, 0.5), 10)
	_screen.content.add_child(bottom)
	_team_strip = HBoxContainer.new()
	_team_strip.add_theme_constant_override("separation", 12)
	bottom.add_child(_team_strip)
	selected = Profile.data.team[0]
	_refresh()


func _build_stage() -> void:
	stage = Node3D.new()
	add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.08, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.65)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.ssao_enabled = true
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 35, 0)
	key.light_energy = 1.4
	key.light_color = Color(1.0, 0.92, 0.82)
	key.shadow_enabled = true
	stage.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.6, 2.6, -2.0)
	rim.light_color = Color(0.4, 0.6, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 7.0
	stage.add_child(rim)
	var rim2 := OmniLight3D.new()
	rim2.position = Vector3(1.8, 1.4, -1.6)
	rim2.light_color = Color(1.0, 0.35, 0.3)
	rim2.light_energy = 2.0
	rim2.omni_range = 6.0
	stage.add_child(rim2)
	var ped := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.25
	cm.bottom_radius = 1.4
	cm.height = 0.3
	ped.mesh = cm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.12, 0.16, 0.24)
	pm.metallic = 0.6
	pm.roughness = 0.35
	ped.material_override = pm
	ped.position.y = -0.15
	stage.add_child(ped)
	var ring := FieldBuilder.make_ring(1.3, Color(UITheme.SCARLET, 0.9), 0.04, 0.1)
	ring.position.y = 0.01
	stage.add_child(ring)
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(30, 30)
	floor_mi.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.05, 0.07, 0.11)
	fm.roughness = 0.6
	fm.metallic = 0.3
	floor_mi.material_override = fm
	floor_mi.position.y = -0.3
	stage.add_child(floor_mi)
	camera = Camera3D.new()
	camera.fov = 30
	camera.position = Vector3(-0.15, 1.3, 6.8)
	stage.add_child(camera)
	camera.look_at(Vector3(-0.15, 1.12, 0), Vector3.UP)
	# Shift the stage so the model sits between the two side panels.
	stage.position = Vector3(0.35, 0, 0)


func _show_model(id: String) -> void:
	if model:
		model.queue_free()
	model = CharacterModel.new()
	stage.add_child(model)
	var colors: Dictionary = DB.uniforms.get(Profile.data.uniform, DB.uniforms.home).colors.duplicate()
	colors["Undershirt"] = DB.defender(id).accent
	model.setup(id, {"accent": DB.defender_accent(id), "colors": colors, "cache_key": id + Profile.data.uniform, "base": "idle"})
	model.rotation.y = _yaw
	if Profile.is_defender_unlocked(id):
		model.play_action("celebrate" if model.has_anim("celebrate") else "idle")
	else:
		model.set_ghost(0.25, Color(0.4, 0.45, 0.6))


func _process(delta: float) -> void:
	if model and not _drag:
		_yaw += delta * 0.25
		model.rotation.y = _yaw


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = event.position
		var vs := get_viewport().get_visible_rect().size
		_drag = event.pressed and mp.x > vs.x * 0.22 and mp.x < vs.x * 0.66 and mp.y < vs.y * 0.82
	elif event is InputEventMouseMotion and _drag:
		_yaw += event.relative.x * 0.01
		if model:
			model.rotation.y = _yaw


func _refresh() -> void:
	_fill_list()
	_fill_info()
	_fill_team()
	_show_model(selected)


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_list.add_child(UITheme.header("DEFENDERS", 30, UITheme.GOLD))
	for id in DB.defender_order:
		var d := DB.defender(id)
		var unlocked := Profile.is_defender_unlocked(id)
		var accent := Color(d.accent)
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == selected
		b.custom_minimum_size = Vector2(0, 66)
		b.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.9), Color(accent, 0.3), 1, 8, 6))
		b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0.1, 0.14, 0.22, 0.95), accent, 2, 8, 6))
		b.add_theme_stylebox_override("pressed", UITheme.panel_style(accent.darkened(0.55), accent, 2, 8, 6))
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pr := MenuScreen.portrait_rect(id, 52, accent if unlocked else Color(0.3, 0.3, 0.35))
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			pr.modulate = Color(0.35, 0.35, 0.4)
		hb.add_child(pr)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -4)
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tag := ""
		if id in Profile.data.team:
			tag = "  ★" + (" C" if id == Profile.data.captain else "")
		var n := UITheme.label(d.name + tag, 24, accent.lightened(0.3) if unlocked else UITheme.MUTED, UITheme.font_header())
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(n)
		var s := UITheme.label("%s · Lv %d" % [DB.roles[d.role].name, Profile.defender_level(id)] if unlocked else "LOCKED · " + Profile.defender_unlock_text(id), 16, UITheme.MUTED, UITheme.font_body_bold())
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(s)
		hb.add_child(vb)
		b.add_child(hb)
		b.pressed.connect(func() -> void:
			selected = id
			Audio.ui("ui_tab")
			_refresh())
		_list.add_child(b)


func _fill_info() -> void:
	for c in _info.get_children():
		c.queue_free()
	var d := DB.defender(selected)
	var unlocked := Profile.is_defender_unlocked(selected)
	var accent := Color(d.accent)
	_info.add_child(UITheme.title(d.name.to_upper(), 72, accent.lightened(0.25)))
	_info.add_child(UITheme.label("%s — #%d %s" % [d.title, int(d.number), DB.roles[d.role].name], 24, UITheme.OFFWHITE, UITheme.font_header()))
	var bio := UITheme.label(d.bio, 19, UITheme.MUTED)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(bio)
	if not unlocked:
		_info.add_child(UITheme.label("LOCKED — " + Profile.defender_unlock_text(selected), 24, UITheme.SCARLET, UITheme.font_display()))
	var lvl := Profile.defender_level(selected)
	var xp_row := HBoxContainer.new()
	xp_row.add_child(UITheme.label("Level %d" % lvl, 26, UITheme.GOLD, UITheme.font_display()))
	var xp := ProgressBar.new()
	xp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp.custom_minimum_size = Vector2(0, 12)
	xp.show_percentage = false
	var need := Profile.defender_xp_needed(lvl)
	xp.max_value = maxi(need, 1)
	xp.value = Profile.defender_xp(selected) if need > 0 else need
	xp.add_theme_stylebox_override("fill", UITheme.panel_style(accent, Color(0, 0, 0, 0), 0, 4, 0))
	xp_row.add_child(xp)
	xp_row.add_child(UITheme.label("%d / %d XP" % [Profile.defender_xp(selected), need] if need > 0 else "MAX", 18, UITheme.MUTED))
	_info.add_child(xp_row)
	# Stats with permanent modifiers.
	var st: Dictionary = d.stats
	var pm := Profile.defender_mods(selected)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 18)
	var stats := [
		["damage", "Damage", "%d" % int(float(st.damage) * (1.0 + float(pm.damage)))],
		["attack_speed", "Throw interval", "%.2fs" % (float(st.interval) / (1.0 + float(pm.attack_speed)))],
		["range", "Range", "%.1fm" % (float(st.range) * (1.0 + float(pm.range)))],
		["throw_speed", "Throw speed", "%d m/s" % int(float(st.throw_speed) * (1.0 + float(pm.throw_speed)))],
		["accuracy", "Accuracy", "%d" % int(float(st.accuracy) + float(pm.accuracy))],
		["special", "Signature power", "x%.2f" % (1.0 + float(pm.special_power))],
		["cooldown", "Signature cooldown", "x%.2f" % (1.0 + float(pm.special_cooldown))],
		["star", "Crit bonus", "+%d%%" % int(float(pm.crit) * 100)],
	]
	for s in stats:
		var hb := HBoxContainer.new()
		hb.add_child(UITheme.icon_rect(s[0], 22, accent.lightened(0.2)))
		hb.add_child(UITheme.label(s[1], 17, UITheme.MUTED))
		grid.add_child(hb)
		grid.add_child(UITheme.label(s[2], 20, UITheme.OFFWHITE, UITheme.font_body_bold()))
	_info.add_child(grid)
	var trait_l := UITheme.label("%s: %s" % [d.trait.name, d.trait.text], 19, Color(0.85, 0.9, 1.0))
	trait_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(trait_l)
	_info.add_child(UITheme.label("Position bonus — " + DB.roles[d.role].bonus_text, 18, UITheme.GREEN))
	var sig := DB.card(d.signature)
	_info.add_child(UITheme.label("Signature card: %s (%s)" % [sig.name, "owned" if Profile.is_card_owned(d.signature) else "not collected"], 18, UITheme.GOLD, UITheme.font_body_bold()))
	if not unlocked:
		return
	# Team & captain
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var in_team: bool = selected in Profile.data.team
	var tb := UITheme.small_button("Remove from team" if in_team else "Add to team", UITheme.SCARLET if in_team else UITheme.GREEN, 21)
	tb.pressed.connect(_toggle_team)
	row.add_child(tb)
	if in_team and selected != Profile.data.captain:
		var cap := UITheme.small_button("Make captain", UITheme.GOLD, 21)
		cap.pressed.connect(func() -> void:
			Profile.set_team(Profile.data.team, selected)
			Audio.ui("ui_confirm")
			_refresh())
		row.add_child(cap)
	_info.add_child(row)
	# Traits
	_info.add_child(UITheme.hsep())
	_info.add_child(UITheme.header("TRAINING TRAITS", 26, UITheme.GOLD))
	for tier in DB.traits:
		var tl := int(tier.level)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		hb.add_child(UITheme.label("Lv %d" % tl, 20, UITheme.GOLD if lvl >= tl else UITheme.MUTED, UITheme.font_body_bold()))
		var chosen := Profile.chosen_trait(selected, tl)
		for opt in tier.options:
			var b := UITheme.small_button(opt.name, UITheme.GREEN, 19)
			b.toggle_mode = true
			b.button_pressed = chosen == opt.id
			b.disabled = lvl < tl
			b.tooltip_text = opt.text
			var oid: String = opt.id
			b.pressed.connect(func() -> void:
				Profile.choose_trait(selected, tl, oid)
				Audio.ui("ui_confirm")
				_fill_info())
			hb.add_child(b)
		_info.add_child(hb)
	# Gear
	_info.add_child(UITheme.hsep())
	_info.add_child(UITheme.header("GEAR", 26, UITheme.GOLD))
	var gear_opt := OptionButton.new()
	gear_opt.add_item("— none —")
	var equipped := Profile.equipped_gear(selected)
	var idx := 1
	var sel := 0
	for gid in DB.gear_order:
		if gid in Profile.data.gear_owned:
			var holder := ""
			for k in Profile.data.gear_equipped.keys():
				if Profile.data.gear_equipped[k] == gid and k != selected:
					holder = " (on %s)" % DB.defender(k).name
			gear_opt.add_item("%s — %s%s" % [DB.gear[gid].name, DB.gear[gid].text, holder])
			gear_opt.set_item_metadata(idx, gid)
			if gid == equipped:
				sel = idx
			idx += 1
	gear_opt.select(sel)
	gear_opt.item_selected.connect(func(i: int) -> void:
		var gid: String = gear_opt.get_item_metadata(i) if i > 0 else ""
		Profile.equip_gear(selected, gid)
		Audio.ui("ui_confirm")
		_fill_info())
	_info.add_child(gear_opt)
	_info.add_child(UITheme.label("Buy gear in Progression → Pro Shop.", 16, UITheme.MUTED))
	# Uniform (team-wide)
	_info.add_child(UITheme.hsep())
	_info.add_child(UITheme.header("TEAM UNIFORM", 26, UITheme.GOLD))
	var uf := HFlowContainer.new()
	uf.add_theme_constant_override("h_separation", 6)
	for uid in DB.uniform_order:
		var u: Dictionary = DB.uniforms[uid]
		var owned: bool = uid in Profile.data.uniforms_owned
		var label: String = u.name if owned else "%s (%d★)" % [u.name, int(u.price_stars)]
		var b := UITheme.small_button(label, Color(u.colors.JerseyTrim), 18)
		b.toggle_mode = true
		b.button_pressed = Profile.data.uniform == uid
		b.pressed.connect(func() -> void:
			if not owned:
				if Profile.spend_stars(int(u.price_stars)):
					Profile.data.uniforms_owned.append(uid)
					Audio.play("purchase")
				else:
					Router.toast("Not enough stars. Earn stars from achievements.", "warn")
					_fill_info()
					return
			Profile.data.uniform = uid
			Profile.save_soon()
			_refresh())
		uf.add_child(b)
	_info.add_child(uf)


func _toggle_team() -> void:
	var team: Array = Profile.data.team.duplicate()
	if selected in team:
		if team.size() <= 1:
			return
		team.erase(selected)
	else:
		if team.size() >= Profile.TEAM_SIZE:
			Router.toast("The team is full (6). Remove someone first.", "warn")
			Audio.ui("ui_error")
			return
		team.append(selected)
	Profile.set_team(team, Profile.data.captain)
	Audio.ui("ui_confirm")
	_refresh()


func _fill_team() -> void:
	for c in _team_strip.get_children():
		c.queue_free()
	_team_strip.add_child(UITheme.header("STARTING SIX", 28, UITheme.GOLD))
	for id in Profile.data.team:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.add_child(MenuScreen.portrait_rect(id, 58, DB.defender_accent(id)))
		var l := UITheme.label(DB.defender(id).name + (" (C)" if id == Profile.data.captain else ""), 16, DB.defender_accent(id).lightened(0.3), UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		_team_strip.add_child(vb)
	if Profile.data.team.size() < Profile.TEAM_SIZE:
		_team_strip.add_child(UITheme.label("%d open slot(s) — add defenders from the list." % (Profile.TEAM_SIZE - Profile.data.team.size()), 18, UITheme.SCARLET))
	var roles := {}
	for id in Profile.data.team:
		roles[DB.defender(id).role] = int(roles.get(DB.defender(id).role, 0)) + 1
	var txt := "Roles: "
	for r in ["pitcher", "catcher", "infielder", "outfielder"]:
		txt += "%s %d  " % [DB.roles[r].name, int(roles.get(r, 0))]
	var rl := UITheme.label(txt, 17, UITheme.MUTED)
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_team_strip.add_child(rl)
