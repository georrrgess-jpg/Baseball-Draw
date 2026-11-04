extends Node3D
## Roster: inspect defenders on a 3D showcase stage (drag to rotate), level-up traits,
## equip gear, choose the team uniform, pick the six-player team and the captain.
## Update 9: the defenders are a portrait grid (12 fit without scrolling) and free agents can be
## signed early for coins (Shop.sign_agent, after a confirmation). `Router.open("roster", id)`
## opens the screen on that defender.

const GRID_COLS := 3
const PORTRAIT := 88.0
const TILE_H := 168.0

var selected := "ace"
var model: CharacterModel
var stage: Node3D
var camera: Camera3D
var ui: Control
var _grid: GridContainer
var _count_label: Label
var _info: VBoxContainer
var _team_strip: HBoxContainer
var _drag := false
var _yaw := 0.0
var _screen: MenuScreen
var _road_box: Control      # the level road of the selected defender (hint target)
var _traits_head: Control   # the TRAINING TRAITS header (hint target)
## defender id -> its grid tile (a toggle Button).
var tiles := {}
## SIGN button of the selected free agent (null when the selected defender is not one).
var sign_button: Button


func _ready() -> void:
	_build_stage()
	var layer := CanvasLayer.new()
	add_child(layer)
	_screen = MenuScreen.new()
	layer.add_child(_screen)
	_screen.setup_screen("TEAM", "Your defenders, their growth, gear and the starting six")
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
	var lp := MenuScreen.panel(UITheme.PANEL_BG, UITheme.BORDER, 14)
	lp.custom_minimum_size = Vector2(440, 0)
	body.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lp.add_child(lv)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 8)
	lv.add_child(lh)
	var sh := UITheme.section_header("DEFENDERS", "roster", UITheme.GOLD, UITheme.FS_H3)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(sh)
	_count_label = UITheme.label("", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	_count_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lh.add_child(_count_label)
	var ls := ScrollContainer.new()
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.follow_focus = true
	lv.add_child(ls)
	_grid = GridContainer.new()
	_grid.name = "DefenderGrid"
	_grid.columns = GRID_COLS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	ls.add_child(_grid)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(spacer)
	var rp := MenuScreen.panel(Color(0.04, 0.07, 0.12, 0.92))
	rp.custom_minimum_size = Vector2(560, 0)
	body.add_child(rp)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rs.follow_focus = true
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
	if DB.defenders.has(Router.open_arg):   # opened on a defender (e.g. from the Shop)
		selected = Router.open_arg
	_refresh()
	_focus_tile.call_deferred(selected)
	# Screenshot helper: `--team-demo=<id>` selects a defender, `--team-demo=<id>:sign` also opens
	# the free agent signing popup.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--team-demo="):
			var spec := a.split("=")[1].split(":")
			if DB.defenders.has(spec[0]):
				selected = spec[0]
				_refresh()
				if spec.size() > 1 and spec[1] == "sign":
					ShopScreen.confirm_sign(_screen, selected, func(ok: bool) -> void:
						if ok:
							_refresh())
	_screen.set_help("roster", func() -> Dictionary:
		return {"team_intro": _grid, "team_road": _road_box, "team_traits": _traits_head}, _hint_features)


## Traits are explained automatically once a defender has reached a trait level.
func _hint_features() -> Array:
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id) and Profile.pending_traits(id) > 0:
			return ["team_traits"]
	return []


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
	# The camera looks a little right of the model so it stands between the grid and the
	# detail panel (the grid is wider than the detail panel's share of the screen).
	camera.position = Vector3(0.26, 1.3, 6.8)
	stage.add_child(camera)
	camera.look_at(Vector3(0.26, 1.12, 0), Vector3.UP)


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
		# Only the stage between the defender grid and the detail panel rotates the model.
		_drag = event.pressed and mp.x > vs.x * 0.31 and mp.x < vs.x * 0.62 and mp.y < vs.y * 0.82
	elif event is InputEventMouseMotion and _drag:
		_yaw += event.relative.x * 0.01
		if model:
			model.rotation.y = _yaw


func _refresh() -> void:
	_fill_list()
	_fill_info()
	_fill_team()
	_show_model(selected)
	_screen.refresh_currency()


func _fill_list() -> void:
	var had_focus := _focused_tile()
	for c in _grid.get_children():
		c.queue_free()
	tiles.clear()
	var n := 0
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id):
			n += 1
		var t := _tile(id)
		_grid.add_child(t)
		tiles[id] = t
	_count_label.text = "%d / %d" % [n, DB.defender_order.size()]
	if had_focus != "":
		_focus_tile.call_deferred(had_focus)


## One defender in the grid: portrait with level / captain / team badges (a lock when locked),
## the name, and the role, NEW TRAIT, or how to unlock.
func _tile(id: String) -> Button:
	var d := DB.defender(id)
	var unlocked := Profile.is_defender_unlocked(id)
	var accent := Color(d.accent)
	var in_team: bool = id in Profile.data.team
	var captain: bool = id == Profile.data.captain
	var traits := Profile.pending_traits(id) if unlocked else 0
	var b := Button.new()
	b.name = "Tile_" + id
	b.toggle_mode = true
	b.button_pressed = id == selected
	b.custom_minimum_size = Vector2(0, TILE_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nb := Color(0.06, 0.09, 0.15, 0.92) if unlocked else Color(0.035, 0.045, 0.075, 0.92)
	var border := Color(accent, 0.6) if in_team else (Color(accent, 0.22) if unlocked else Color(1, 1, 1, 0.07))
	b.add_theme_stylebox_override("normal", UITheme.panel_style(nb, border, 2 if in_team else 1, 10, 4))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0.1, 0.14, 0.22, 0.96), accent, 2, 10, 4))
	var sel := UITheme.panel_style(accent.darkened(0.6), accent.lightened(0.25), 3, 10, 4)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.add_theme_stylebox_override("focus", UITheme.panel_style(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.95), 2, 10, 4))
	var tip := "%s — %s, %s" % [d.name, d.title, DB.roles[d.role].name]
	if unlocked:
		tip += "\nLevel %d%s%s" % [Profile.defender_level(id), "  ·  captain" if captain else ("  ·  in the starting six" if in_team else ""),
			"\nNew trait to choose!" if traits > 0 else ""]
	else:
		tip += "\nLocked: " + unlock_text(id)
	b.tooltip_text = tip
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 6
	v.offset_bottom = -4
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	# Portrait with its badges.
	var ph := Control.new()
	ph.custom_minimum_size = Vector2(PORTRAIT + 12, PORTRAIT + 4)
	ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ph)
	var pr := MenuScreen.portrait_rect(id, PORTRAIT - 4, accent if unlocked else Color(0.3, 0.3, 0.36))
	pr.position = Vector2(6, 0)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(pr)
	if not unlocked:
		pr.modulate = Color(0.32, 0.32, 0.4)
		var lk := UITheme.icon_rect("lock", 34, UITheme.OFFWHITE)
		lk.position = Vector2(6 + (PORTRAIT - 4 - 34) * 0.5, (PORTRAIT - 4 - 34) * 0.5)
		ph.add_child(lk)
	else:
		var lb := PanelContainer.new()
		lb.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.07, 0.12, 0.96), UITheme.GOLD, 2, 14, 0))
		lb.custom_minimum_size = Vector2(30, 30)
		lb.position = Vector2(PORTRAIT - 14, PORTRAIT - 30)
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ll := UITheme.label(str(Profile.defender_level(id)), 19, UITheme.GOLD, UITheme.font_header())
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.add_child(ll)
		ph.add_child(lb)
	if captain:
		var cb := UITheme.badge("C", UITheme.GOLD.darkened(0.25), UITheme.FS_MIN)
		cb.position = Vector2(0, -4)
		ph.add_child(cb)
	elif in_team:
		var tb := UITheme.badge("★", UITheme.SCARLET, UITheme.FS_MIN)
		tb.position = Vector2(0, -4)
		ph.add_child(tb)
	# Name and the line underneath.
	var nl := UITheme.label(str(d.name), UITheme.FS_LEAD, accent.lightened(0.3) if unlocked else UITheme.MUTED, UITheme.font_header())
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var u: Dictionary = d.get("unlock", {})
	if unlocked:
		var sub := UITheme.label("NEW TRAIT" if traits > 0 else str(DB.roles[d.role].name), UITheme.FS_MIN,
			UITheme.GREEN if traits > 0 else UITheme.OFFWHITE.darkened(0.15), UITheme.font_body_bold())
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sub)
	else:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(row)
		var lvl_txt := "LV %d" % int(u.get("value", 0)) if str(u.get("type", "")) == "level" else "LOCKED"
		row.add_child(UITheme.label(lvl_txt + (" or" if int(u.get("coins", 0)) > 0 else ""), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		if int(u.get("coins", 0)) > 0:
			row.add_child(UITheme.icon_rect("coin", 16, UITheme.GOLD))
			row.add_child(UITheme.label(UITheme.format_int(int(u.coins)), UITheme.FS_MIN, UITheme.GOLD, UITheme.font_body_bold()))
	b.pressed.connect(func() -> void:
		if selected == id:
			b.button_pressed = true
			return
		selected = id
		Audio.ui("ui_tab")
		_refresh())
	return b


## "Account level 13 or sign for 6,000 coins" (free agents) / "Reach account level 7".
static func unlock_text(id: String) -> String:
	var u: Dictionary = DB.defender(id).get("unlock", {})
	var coins := int(u.get("coins", 0))
	if str(u.get("type", "")) == "level":
		if coins > 0:
			return "Account level %d or sign for %s coins" % [int(u.value), UITheme.format_int(coins)]
		return "Reach account level %d" % int(u.value)
	if coins > 0:
		return "Sign for %s coins" % UITheme.format_int(coins)
	return Profile.defender_unlock_text(id)


func _focused_tile() -> String:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for id in tiles:
		if tiles[id] == f:
			return id
	return ""


func _focus_tile(id: String) -> void:
	var t: Button = tiles.get(id)
	if t and is_instance_valid(t) and t.is_inside_tree():
		t.grab_focus()


func _fill_info() -> void:
	for c in _info.get_children():
		c.queue_free()
	var d := DB.defender(selected)
	var unlocked := Profile.is_defender_unlocked(selected)
	var accent := Color(d.accent)
	sign_button = null
	var free_agent := not unlocked and int(d.get("unlock", {}).get("coins", 0)) > 0
	if free_agent:
		var fa := UITheme.badge("FREE AGENT", UITheme.GOLD.darkened(0.3), UITheme.FS_MIN)
		fa.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_info.add_child(fa)
	_info.add_child(UITheme.title(d.name.to_upper(), 72, accent.lightened(0.25)))
	_info.add_child(UITheme.label("%s — #%d %s" % [d.title, int(d.number), DB.roles[d.role].name], 24, UITheme.OFFWHITE, UITheme.font_header()))
	var bio := UITheme.label(d.bio, 19, UITheme.MUTED)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_child(bio)
	if not unlocked:
		var lr := HBoxContainer.new()
		lr.add_theme_constant_override("separation", 8)
		lr.add_child(UITheme.icon_rect("lock", 26, UITheme.SCARLET))
		var ll := UITheme.label("LOCKED — " + unlock_text(selected), 24, UITheme.SCARLET, UITheme.font_display())
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lr.add_child(ll)
		_info.add_child(lr)
		if free_agent:
			_info.add_child(_sign_row(selected))
	var lvl := Profile.defender_level(selected)
	_info.add_child(_level_section(selected, lvl, accent, unlocked))
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
	var tb := UITheme.button("Remove from team" if in_team else "Add to team", "danger" if in_team else "primary", 22, "minus" if in_team else "plus", UITheme.SCARLET if in_team else UITheme.GREEN.darkened(0.25))
	tb.pressed.connect(_toggle_team)
	row.add_child(tb)
	if in_team and selected != Profile.data.captain:
		var cap := UITheme.button("Make captain", "secondary", 22, "captain", UITheme.GOLD)
		cap.pressed.connect(func() -> void:
			Profile.set_team(Profile.data.team, selected)
			Audio.ui("ui_confirm")
			_refresh())
		row.add_child(cap)
	_info.add_child(row)
	# Traits
	_info.add_child(UITheme.hsep())
	_traits_head = UITheme.section_header("TRAINING TRAITS", "upgrade", UITheme.GOLD, UITheme.FS_H3)
	_info.add_child(_traits_head)
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
			b.tooltip_text = opt.text + ("\nUnlocks when %s reaches level %d." % [d.name, tl] if lvl < tl else "")
			var oid: String = opt.id
			b.pressed.connect(func() -> void:
				Profile.choose_trait(selected, tl, oid)
				Audio.ui("ui_confirm")
				_fill_info())
			hb.add_child(b)
		_info.add_child(hb)
	# Gear
	_info.add_child(UITheme.hsep())
	_info.add_child(UITheme.section_header("GEAR", "defense", UITheme.GOLD, UITheme.FS_H3))
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
	var shop_row := HBoxContainer.new()
	shop_row.add_theme_constant_override("separation", 10)
	var shop_l := UITheme.label("One piece of gear per defender. Buy more in the Pro Shop." if not Profile.data.gear_owned.is_empty()
		else "No gear yet. Gear is bought with coins in the Pro Shop.", UITheme.FS_MIN, UITheme.MUTED)
	shop_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shop_row.add_child(shop_l)
	var shop_b := UITheme.button("PRO SHOP  ▶", "ghost", UITheme.FS_SMALL, "", UITheme.GOLD)
	shop_b.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
	shop_b.tooltip_text = "Progression → Pro Shop"
	shop_b.pressed.connect(func() -> void: Router.open("progression", "Pro Shop"))
	shop_row.add_child(shop_b)
	_info.add_child(shop_row)
	# Uniform (team-wide)
	_info.add_child(UITheme.hsep())
	_info.add_child(UITheme.section_header("TEAM UNIFORM", "special", UITheme.GOLD, UITheme.FS_H3))
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


## SIGN for a free agent: the price on the button, the wallet next to it. Opens the Shop's
## confirmation popup; a signed defender joins at once.
func _sign_row(id: String) -> Control:
	var a := ShopScreen.agent_info(id)
	var price := int(a.get("price", DB.defender(id).get("unlock", {}).get("coins", 0)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var b := ShopScreen.price_button("SIGN NOW", {"coins": price}, true, UITheme.GOLD)
	b.name = "SignButton"
	b.custom_minimum_size = Vector2(250, UITheme.BTN_H)
	b.tooltip_text = "Sign %s now instead of waiting for the account level" % DB.defender(id).name
	b.pressed.connect(func() -> void:
		ShopScreen.confirm_sign(_screen, id, func(ok: bool) -> void:
			if ok and is_inside_tree():
				_refresh()
				_focus_tile(id)))
	row.add_child(b)
	sign_button = b
	var short := ShopScreen.shortfall({"coins": price})
	var wl := UITheme.label("You have %s coins" % UITheme.format_int(int(Profile.data.coins)) if short == "" else short,
		UITheme.FS_SMALL, UITheme.MUTED if short == "" else Color(1.0, 0.5, 0.45), UITheme.font_body_bold())
	wl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(wl)
	return row


## Level badge, XP to the next level and the level road (a reward at every level).
func _level_section(id: String, lvl: int, accent: Color, unlocked: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UITheme.panel_style(Color(accent, 0.25), UITheme.GOLD, 2, 30, 6))
	badge.custom_minimum_size = Vector2(64, 64)
	var bl := UITheme.label(str(lvl), 38, UITheme.GOLD, UITheme.font_display())
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(bl)
	head.add_child(badge)
	var xv := VBoxContainer.new()
	xv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(xv)
	var need := Profile.defender_xp_needed(lvl)
	var have := Profile.defender_xp(id)
	var maxed := lvl >= DB.defender_max_level
	xv.add_child(UITheme.label("LEVEL %d%s" % [lvl, "  ·  MAX" if maxed else ""], 22, UITheme.OFFWHITE, UITheme.font_header()))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	bar.max_value = maxi(need, 1)
	bar.value = need if maxed else have
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(accent.lightened(0.1), Color(0, 0, 0, 0), 0, 6, 0))
	bar.add_theme_stylebox_override("background", UITheme.panel_style(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 1, 6, 0))
	xv.add_child(bar)
	var growth := int(round(DB.defender_level_growth * 100.0 * (lvl - 1)))
	xv.add_child(UITheme.label(("Max level reached" if maxed else "%d XP to level %d" % [need - have, lvl + 1]) + "   ·   Power +%d%%" % growth, 16, UITheme.MUTED, UITheme.font_body_bold()))
	# Level road
	var road := HBoxContainer.new()
	road.add_theme_constant_override("separation", 4)
	box.add_child(road)
	_road_box = road
	var next_text := ""
	for l in range(1, DB.defender_max_level + 1):
		var r := Profile.defender_level_reward(l)
		var reached := l <= lvl
		var node := VBoxContainer.new()
		node.add_theme_constant_override("separation", 1)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var circ := PanelContainer.new()
		var fill := Color(accent, 0.85) if reached else Color(0.08, 0.1, 0.16, 0.95)
		var border := UITheme.GOLD if l == lvl + 1 else (Color(accent.lightened(0.3), 0.9) if reached else Color(1, 1, 1, 0.15))
		circ.add_theme_stylebox_override("panel", UITheme.panel_style(fill, border, 2, 16, 2))
		circ.custom_minimum_size = Vector2(32, 32)
		circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var nl := UITheme.label(str(l), 17, Color.WHITE if reached else UITheme.MUTED, UITheme.font_header())
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		circ.add_child(nl)
		node.add_child(circ)
		var icon := "upgrade"
		if r.has("coins"):
			icon = "coin"
		elif r.has("pack"):
			icon = "deck"
		elif r.has("trait"):
			icon = "star"
		if not r.is_empty():
			var ic := UITheme.icon_rect(icon, 18, (UITheme.GOLD if not reached else Color(1, 1, 1, 0.45)))
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			node.add_child(ic)
		node.tooltip_text = "Level %d: %s" % [l, Profile.level_reward_text(r) if not r.is_empty() else "Starting level"]
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		road.add_child(node)
		if l == lvl + 1 and not r.is_empty():
			next_text = "NEXT REWARD — Level %d: %s" % [l, Profile.level_reward_text(r)]
	if next_text != "" and unlocked:
		box.add_child(UITheme.label(next_text, 18, UITheme.GOLD, UITheme.font_body_bold()))
	if Profile.pending_traits(id) > 0 and unlocked:
		box.add_child(UITheme.label("★ New trait unlocked — choose it under TRAINING TRAITS below!", 18, UITheme.GREEN, UITheme.font_body_bold()))
	return box


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
	_team_strip.add_child(UITheme.section_header("STARTING SIX", "formation", UITheme.GOLD, 28))
	for id in Profile.data.team:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 0)
		vb.add_child(MenuScreen.portrait_rect(id, 58, DB.defender_accent(id)))
		var l := UITheme.label(DB.defender(id).name + (" (C)" if id == Profile.data.captain else ""), 16, DB.defender_accent(id).lightened(0.3), UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		_team_strip.add_child(vb)
	if Profile.data.team.size() < Profile.TEAM_SIZE:
		_team_strip.add_child(UITheme.label("%d open slot(s) — pick defenders in the grid." % (Profile.TEAM_SIZE - Profile.data.team.size()), 18, UITheme.SCARLET))
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
