extends Node3D
## Roster: inspect defenders on a 3D showcase stage (drag to rotate), level-up traits,
## equip gear, choose the team uniform, pick the six-player team and the captain.
## Update 9: the defenders are a portrait grid (12 fit without scrolling) and free agents can be
## signed early for coins (Shop.sign_agent, after a confirmation). `Router.open("roster", id)`
## opens the screen on that defender.
## Update 10: BEST TEAM (TeamAI, four styles) previews the strongest six and captain, who comes in and
## goes out, the score change and why, then applies it; COMPARE opens TeamCompare for the selected
## defender and the most natural rival (same role, in the six or on the bench).

const GRID_COLS := 3
const PORTRAIT := 88.0
const TILE_H := 168.0
const ROAD_ROW := 10   # level road nodes per row (20 levels = two rows)

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
## Update 10: the strip's BEST TEAM and COMPARE buttons, the open Best Team preview and comparison.
var best_button: Button
var compare_button: Button
var best_preview: Control
var compare: TeamCompare
var best_mode := "balanced"
var best_result: Dictionary = {}
var _best_body: VBoxContainer


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
	best_mode = str(Profile.data.get("flags", {}).get("best_team_mode", "balanced"))
	if not best_mode in TeamAI.MODES:
		best_mode = "balanced"
	selected = Profile.data.team[0]
	if DB.defenders.has(Router.open_arg):   # opened on a defender (e.g. from the Shop)
		selected = Router.open_arg
	# Screenshot helper: `--team-levels=ace:20,jax:15` sets defender levels (in memory) first and picks
	# the first option of every trait tier reached.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--team-levels="):
			for spec in a.split("=")[1].split(","):
				var kv := spec.split(":")
				if kv.size() == 2 and Profile.data.defenders.has(kv[0]):
					Profile.data.defenders[kv[0]].level = clampi(int(kv[1]), 1, DB.defender_max_level)
					Profile.data.defenders[kv[0]].xp = 0 if int(kv[1]) >= DB.defender_max_level else Profile.defender_xp_needed(int(kv[1])) / 3
					for tier in DB.traits:
						if Profile.chosen_trait(kv[0], int(tier.level)) == "":
							Profile.choose_trait(kv[0], int(tier.level), str(tier.options[0].id))
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
				elif spec.size() > 1 and spec[1] == "best":
					open_best_team(spec[2] if spec.size() > 2 else best_mode)
				elif spec.size() > 1 and spec[1] == "compare":
					open_compare(selected, spec[2] if spec.size() > 2 else "")
	_screen.set_help("roster", func() -> Dictionary:
		return {"team_intro": _grid, "team_road": _road_box, "team_traits": _traits_head, "team_free_agents": _grid,
			"team_best": best_button, "team_compare": compare_button}, _hint_features)


## Traits are explained automatically once a defender has reached a trait level; free agents
## once one can be signed.
func _hint_features() -> Array:
	var out: Array = []
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id) and Profile.pending_traits(id) > 0:
			out.append("team_traits")
			break
	for fa in Shop.free_agents():
		if not bool(fa.get("signed", false)):
			out.append("team_free_agents")
			break
	# Update 10: Best Team and Compare once there is a bench to choose from (hint texts live in hints.gd;
	# ids without a text are skipped).
	if TeamAI.available(TeamAI.profile_context()).size() > Profile.TEAM_SIZE:
		out.append_array(["team_best", "team_compare"])
	return out


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
	# The Best Team preview keeps keyboard focus on its own buttons.
	if best_preview and is_instance_valid(best_preview) and not best_preview.is_queued_for_deletion():
		if TeamCompare.trap_focus(best_preview, event):
			get_viewport().set_input_as_handled()
		return
	if compare and is_instance_valid(compare):
		return
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
	var honor := DefenderLevels.honor_of(id)
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
		tip += "\nLevel %d%s%s%s" % [Profile.defender_level(id), "  ·  captain" if captain else ("  ·  in the starting six" if in_team else ""),
			("\n" + DefenderLevels.BADGE_NAMES[honor]) if honor != "" else "", "\nNew trait to choose!" if traits > 0 else ""]
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
	var pr := DefenderHonors.portrait(id, PORTRAIT - 4, accent if unlocked else Color(0.3, 0.3, 0.36), honor)
	pr.position = Vector2(6, 0)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(pr)
	if not unlocked:
		pr.modulate = Color(0.32, 0.32, 0.4)
		var lk := UITheme.icon_rect("lock", 34, UITheme.OFFWHITE)
		lk.position = Vector2(6 + (PORTRAIT - 4 - 34) * 0.5, (PORTRAIT - 4 - 34) * 0.5)
		ph.add_child(lk)
	else:
		# Level badge: round for one digit, a pill for two (Update 11), in the honour's colours.
		var dl := Profile.defender_level(id)
		var lb := DefenderHonors.level_badge(dl, 30.0, 19, honor)
		lb.position = Vector2(PORTRAIT + 16 - DefenderHonors.badge_width(dl, 30.0), PORTRAIT - 30)
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
		var sub_text := str(DB.roles[d.role].name)
		if traits > 0:
			sub_text = "NEW TRAIT"
		elif honor != "":
			sub_text = "★ " + str(DefenderLevels.BADGE_NAMES[honor]).to_upper()
		var sub := UITheme.label(sub_text, UITheme.FS_MIN,
			UITheme.GREEN if traits > 0 else DefenderHonors.color(honor, UITheme.OFFWHITE.darkened(0.15)), UITheme.font_body_bold())
		sub.name = "SubLine"
		sub.clip_text = true
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
	var honor := DefenderLevels.honor_of(selected)
	if honor == "":
		_info.add_child(UITheme.title(d.name.to_upper(), 72, accent.lightened(0.25)))
	else:
		# All-Star / Hall of Famer: the nameplate sits beside the name (Update 11).
		var tr := HBoxContainer.new()
		tr.name = "NameRow"
		tr.add_theme_constant_override("separation", 16)
		var tl := UITheme.title(d.name.to_upper(), 72, DefenderHonors.HOF_GOLD if honor == DefenderLevels.HALL_OF_FAME else accent.lightened(0.25))
		tr.add_child(tl)
		var plate := DefenderHonors.nameplate(selected, UITheme.FS_BODY, honor)
		plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.add_child(plate)
		_info.add_child(tr)
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
	# Season uniforms are Season Pass rewards (tier 30): only owned ones and this season's (locked) show.
	var season_uniform := str(Season.current().get("uniform", ""))
	for uid in DB.uniform_order:
		var u: Dictionary = DB.uniforms[uid]
		var owned: bool = uid in Profile.data.uniforms_owned
		var for_sale := Profile.uniform_for_sale(uid)
		if not owned and not for_sale and uid != season_uniform:
			continue
		var label: String = u.name
		if not owned:
			label = "%s (%d★)" % [u.name, int(u.get("price_stars", 0))] if for_sale else "%s (Season %d reward)" % [u.name, int(u.get("season", 0))]
		var b := UITheme.small_button(label, Color(u.colors.JerseyTrim), 18)
		b.toggle_mode = true
		b.button_pressed = Profile.data.uniform == uid
		if not owned and not for_sale:
			b.disabled = true
			b.tooltip_text = "Reach tier 30 of the Season Pass this season to earn the %s uniform." % u.name
		b.pressed.connect(func() -> void:
			if not owned:
				if Profile.buy_uniform(uid):
					Audio.play("purchase")
				else:
					Router.toast("Not enough stars. Earn stars from achievements and the Season Pass.", "warn")
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


## Level badge, XP to the next level and the level road (a reward at every level). Update 11: 20 levels
## in two rows of ten (the second row is the Hall of Fame road: trait tiers 4 and 5, All-Star at 15,
## Hall of Famer at 20), a pill badge for two digits and the growth of the next level.
func _level_section(id: String, lvl: int, accent: Color, unlocked: bool) -> Control:
	var box := VBoxContainer.new()
	box.name = "LevelSection"
	box.add_theme_constant_override("separation", 6)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var honor := DefenderLevels.honor(lvl) if unlocked else ""
	var badge := DefenderHonors.level_badge(lvl, 64.0, 38, honor)
	if honor == "":
		badge.add_theme_stylebox_override("panel", UITheme.panel_style(Color(accent, 0.25), UITheme.GOLD, 2, 30, 6))
	badge.name = "LevelBadge"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bl: Label = badge.get_node("LevelText")
	bl.add_theme_font_override("font", UITheme.font_display())
	head.add_child(badge)
	var xv := VBoxContainer.new()
	xv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(xv)
	var need := Profile.defender_xp_needed(lvl)
	var have := Profile.defender_xp(id)
	var maxed := lvl >= DB.defender_max_level
	xv.add_child(UITheme.label("LEVEL %d / %d%s" % [lvl, DB.defender_max_level, "  ·  MAX" if maxed else ""], 22, UITheme.OFFWHITE, UITheme.font_header()))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 16)
	bar.show_percentage = false
	bar.max_value = 1 if maxed else maxi(need, 1)
	bar.value = 1 if maxed else have
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(DefenderHonors.HOF_GOLD if maxed else accent.lightened(0.1), Color(0, 0, 0, 0), 0, 6, 0))
	bar.add_theme_stylebox_override("background", UITheme.panel_style(Color(0, 0, 0, 0.45), Color(1, 1, 1, 0.12), 1, 6, 0))
	xv.add_child(bar)
	var growth := int(round(DefenderLevels.growth(lvl) * 100.0))
	var line := "Hall of Famer — the top of the road" if maxed else "%s XP to level %d (+%d%%)" % [
		UITheme.format_int(need - have), lvl + 1, int(round(DefenderLevels.growth_step(lvl + 1) * 100.0))]
	xv.add_child(UITheme.label(line + "   ·   Power +%d%%" % growth, 16, UITheme.MUTED, UITheme.font_body_bold()))
	# Level road: two rows of ten.
	var road := VBoxContainer.new()
	road.name = "LevelRoad"
	road.add_theme_constant_override("separation", 2)
	box.add_child(road)
	_road_box = road
	var next_text := ""
	var row: HBoxContainer = null
	for l in range(1, DB.defender_max_level + 1):
		if row == null or (l - 1) % ROAD_ROW == 0:
			row = HBoxContainer.new()
			row.name = "RoadRow%d" % ((l - 1) / ROAD_ROW + 1)
			row.add_theme_constant_override("separation", 4)
			road.add_child(row)
		var r := Profile.defender_level_reward(l)
		var reached := l <= lvl
		var milestone := str(r.get("badge", ""))
		var node := VBoxContainer.new()
		node.name = "RoadLevel%d" % l
		node.add_theme_constant_override("separation", 1)
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var circ := PanelContainer.new()
		var fill := Color(accent, 0.85) if reached else Color(0.08, 0.1, 0.16, 0.95)
		var border := UITheme.GOLD if l == lvl + 1 else (Color(accent.lightened(0.3), 0.9) if reached else Color(1, 1, 1, 0.15))
		if milestone == DefenderLevels.HALL_OF_FAME:
			fill = DefenderHonors.HOF_GOLD if reached else Color(DefenderHonors.HOF_DEEP, 0.55)
			border = Color(1.0, 0.97, 0.82) if reached or l == lvl + 1 else Color(DefenderHonors.HOF_GOLD, 0.7)
		elif milestone == DefenderLevels.ALL_STAR:
			fill = DefenderHonors.STAR_BLUE if reached else Color(DefenderHonors.STAR_BLUE, 0.35)
			border = DefenderHonors.STAR_RED if not l == lvl + 1 else UITheme.GOLD
		var cs := UITheme.panel_style(fill, border, 2, 16, 0)
		circ.add_theme_stylebox_override("panel", cs)
		circ.custom_minimum_size = Vector2(34, 32)
		circ.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var ink := Color.WHITE if reached else UITheme.MUTED
		if milestone == DefenderLevels.HALL_OF_FAME and reached:
			ink = DefenderHonors.HOF_INK
		elif milestone != "" and not reached:
			ink = UITheme.OFFWHITE
		var nl := UITheme.label(str(l), 17 if l < 10 else 15, ink, UITheme.font_header())
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		circ.add_child(nl)
		node.add_child(circ)
		if not r.is_empty():
			var tint := Color(1, 1, 1, 0.45) if reached else UITheme.GOLD
			if milestone == DefenderLevels.HALL_OF_FAME:
				tint = DefenderHonors.HOF_GOLD if not reached else Color(DefenderHonors.HOF_GOLD, 0.6)
			elif milestone == DefenderLevels.ALL_STAR:
				tint = Color(0.62, 0.78, 1.0) if not reached else Color(0.62, 0.78, 1.0, 0.55)
			var ic := UITheme.icon_rect(DefenderLevels.reward_icon(r), 18, tint)
			ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			node.add_child(ic)
		node.tooltip_text = "Level %d: %s" % [l, Profile.level_reward_text(r) if not r.is_empty() else "Starting level"]
		if l > 1:
			node.tooltip_text += "\nPower +%d%% (+%d%% this level)" % [int(round(DefenderLevels.growth(l) * 100.0)), int(round(DefenderLevels.growth_step(l) * 100.0))]
		node.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(node)
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
		var honor := DefenderLevels.honor_of(id)
		vb.name = "Strip_" + id
		var pf := DefenderHonors.portrait(id, 58, DB.defender_accent(id), honor)
		if honor == "":
			vb.add_child(pf)
		else:
			# All-Star / Hall of Famer: the level badge on the portrait's corner (Update 11).
			var holder := MarginContainer.new()
			holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			holder.add_child(pf)
			var overlay := Control.new()
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			holder.add_child(overlay)
			var dl := Profile.defender_level(id)
			var lb := DefenderHonors.level_badge(dl, 22.0, 14, honor)
			var bw := DefenderHonors.badge_width(dl, 22.0)
			lb.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			lb.offset_left = -bw + 6
			lb.offset_right = 6
			lb.offset_top = -6
			lb.offset_bottom = 16
			overlay.add_child(lb)
			vb.add_child(holder)
		var l := UITheme.label(DB.defender(id).name + (" (C)" if id == Profile.data.captain else ""), 16,
			DefenderHonors.HOF_GOLD if honor == DefenderLevels.HALL_OF_FAME else DB.defender_accent(id).lightened(0.3), UITheme.font_body_bold())
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
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_team_strip.add_child(rl)
	best_button = UITheme.button("BEST TEAM", "primary", UITheme.FS_BODY, "special", UITheme.GOLD.darkened(0.25))
	best_button.name = "BestTeamButton"
	best_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	best_button.tooltip_text = "Pick the strongest six and captain from your unlocked defenders (%s style), with a preview first." % TeamAI.MODE_NAMES[best_mode]
	best_button.pressed.connect(func() -> void: open_best_team(best_mode))
	_team_strip.add_child(best_button)
	compare_button = UITheme.button("COMPARE", "secondary", UITheme.FS_BODY, "swap")
	compare_button.name = "CompareButton"
	compare_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	compare_button.tooltip_text = "Compare %s side by side with another defender." % DB.defender(selected).name
	compare_button.pressed.connect(func() -> void: open_compare(selected))
	_team_strip.add_child(compare_button)


# ---------------------------------------------------------------- Update 10: Best Team

## Opens the Best Team preview in a style: who comes in and goes out, the score before and after,
## the reasons per pick, the style choice, and APPLY (Profile.set_team) / CANCEL.
func open_best_team(mode := "balanced") -> Control:
	if best_preview and is_instance_valid(best_preview) and not best_preview.is_queued_for_deletion():
		best_preview.queue_free()
	var shade := ColorRect.new()
	shade.name = "BestTeamPreview"
	shade.color = Color(0, 0, 0, 0.66)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.z_index = 40
	_screen.add_child(shade)
	_screen.push_overlay(shade)
	best_preview = shade
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.7), 22, Color(0.04, 0.065, 0.11, 0.98), 2)
	p.custom_minimum_size = Vector2(1380, 0)
	center.add_child(p)
	_best_body = VBoxContainer.new()
	_best_body.add_theme_constant_override("separation", 10)
	p.add_child(_best_body)
	set_best_mode(mode, false)
	shade.modulate.a = 0.0
	shade.create_tween().tween_property(shade, "modulate:a", 1.0, 0.15)
	Audio.ui("ui_tab")
	return shade


## Recomputes the preview for a style (and remembers the style).
func set_best_mode(mode: String, sound := true) -> void:
	if not mode in TeamAI.MODES:
		mode = "balanced"
	best_mode = mode
	if Profile.data.has("flags"):
		Profile.data.flags["best_team_mode"] = mode
	best_result = TeamAI.best_team(mode)
	if sound:
		Audio.ui("ui_tab")
	if _best_body and is_instance_valid(_best_body):
		_fill_best(_best_body, best_result)
	if best_button and is_instance_valid(best_button):
		best_button.tooltip_text = "Pick the strongest six and captain from your unlocked defenders (%s style), with a preview first." % TeamAI.MODE_NAMES[mode]


func _fill_best(vb: VBoxContainer, r: Dictionary) -> void:
	for c in vb.get_children():
		vb.remove_child(c)
		c.queue_free()
	# Header: title and the style buttons.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var sh := UITheme.section_header("BEST TEAM", "special", UITheme.GOLD, UITheme.FS_H2)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	var mode_btns: Array = []
	for m in TeamAI.MODES:
		var mb := UITheme.small_button(str(TeamAI.MODE_NAMES[m]), UITheme.GOLD, UITheme.FS_SMALL)
		mb.name = "Mode_" + m
		mb.toggle_mode = true
		mb.button_pressed = m == r.mode
		mb.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
		mb.tooltip_text = str(TeamAI.MODE_TEXT[m])
		mb.add_theme_stylebox_override("focus", UITheme.panel_style(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.95), 2, 6, 0))
		var mm: String = m
		var focus_name := mb.name
		mb.pressed.connect(func() -> void:
			set_best_mode(mm)
			_focus_named.call_deferred(focus_name))
		head.add_child(mb)
		mode_btns.append(mb)
	var mt := UITheme.label(str(TeamAI.MODE_TEXT[r.mode]), UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	vb.add_child(mt)
	# Score before / after.
	var sr := HBoxContainer.new()
	sr.name = "ScoreRow"
	sr.add_theme_constant_override("separation", 14)
	vb.add_child(sr)
	var stl := UITheme.label("TEAM SCORE", UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold())
	stl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sr.add_child(stl)
	var before := float(r.current_score)
	var after := float(r.score)
	var sl := UITheme.label("%.1f" % before, UITheme.FS_H1, UITheme.OFFWHITE, UITheme.font_display())
	sl.name = "ScoreBefore"
	sr.add_child(sl)
	if not bool(r.already_best):
		sr.add_child(UITheme.label("→", UITheme.FS_H1, UITheme.MUTED, UITheme.font_display()))
		var al := UITheme.label("%.1f" % after, UITheme.FS_H1, UITheme.GREEN, UITheme.font_display())
		al.name = "ScoreAfter"
		sr.add_child(al)
		var gain := UITheme.badge("+%.1f" % (after - before), UITheme.GREEN.darkened(0.35), UITheme.FS_SMALL)
		gain.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sr.add_child(gain)
	var sumr := UITheme.label(str(r.summary), UITheme.FS_SMALL, Color(0.85, 0.9, 1.0), UITheme.font_body_bold())
	sumr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sumr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sumr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sumr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sr.add_child(sumr)
	if bool(r.already_best):
		var ab := UITheme.label("Your team is already the best %s team: no change needed." % str(TeamAI.MODE_NAMES[r.mode]), UITheme.FS_LEAD, UITheme.GREEN, UITheme.font_header())
		ab.name = "AlreadyBest"
		vb.add_child(ab)
	else:
		# Who comes in and goes out.
		var io := HBoxContainer.new()
		io.name = "InOut"
		io.add_theme_constant_override("separation", 12)
		vb.add_child(io)
		if not r.ins.is_empty():
			var ib := UITheme.badge("IN", UITheme.GREEN.darkened(0.35), UITheme.FS_SMALL)
			ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			io.add_child(ib)
			for id in r.ins:
				io.add_child(_mini_player(id, UITheme.GREEN))
		if not r.outs.is_empty():
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(20, 0)
			io.add_child(gap)
			var ob := UITheme.badge("OUT", UITheme.SCARLET, UITheme.FS_SMALL)
			ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			io.add_child(ob)
			for id in r.outs:
				io.add_child(_mini_player(id, Color(1.0, 0.55, 0.5)))
		if bool(r.captain_changed):
			var gap2 := Control.new()
			gap2.custom_minimum_size = Vector2(20, 0)
			io.add_child(gap2)
			var cl := UITheme.label("New captain: %s (was %s)" % [DB.defender(r.captain).name, DB.defender(str(Profile.data.captain)).name],
				UITheme.FS_BODY, UITheme.GOLD, UITheme.font_body_bold())
			cl.name = "CaptainChange"
			cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			io.add_child(cl)
	vb.add_child(UITheme.hsep())
	# The six with their reasons.
	var grid := GridContainer.new()
	grid.name = "Picks"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)
	for id in r.team:
		grid.add_child(_pick_card(id, r))
	# Buttons.
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	var hint := UITheme.label("Esc closes.  The team only changes when you press APPLY.", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btns.add_child(hint)
	var cancel := UITheme.button("CLOSE" if bool(r.already_best) else "CANCEL", "secondary")
	cancel.name = "Cancel"
	cancel.pressed.connect(func() -> void:
		Audio.ui("ui_back")
		if is_instance_valid(best_preview):
			best_preview.queue_free())
	btns.add_child(cancel)
	var apply := UITheme.button("APPLY", "primary", UITheme.FS_LEAD, "check", UITheme.GREEN.darkened(0.3))
	apply.name = "Apply"
	apply.disabled = bool(r.already_best)
	apply.tooltip_text = "Make this your starting six" if not apply.disabled else "Your team is already the best for this style."
	apply.pressed.connect(apply_best_team)
	btns.add_child(apply)
	# Focus: APPLY when there is something to apply, else the current style.
	var fb: Button = apply if not apply.disabled else mode_btns[TeamAI.MODES.find(r.mode)]
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if fo == null or not fo.is_visible_in_tree() or not best_preview.is_ancestor_of(fo):
		fb.grab_focus.call_deferred()


func _focus_named(n: String) -> void:
	if best_preview and is_instance_valid(best_preview):
		var b: Control = best_preview.find_child(n, true, false)
		if b and not b.is_queued_for_deletion():
			b.grab_focus()


func _mini_player(id: String, col: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(DefenderHonors.portrait(id, 44, DB.defender_accent(id)))
	var l := UITheme.label("%s  Lv %d" % [DB.defender(id).name, Profile.defender_level(id)], UITheme.FS_BODY, col, UITheme.font_header())
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(l)
	return hb


func _pick_card(id: String, r: Dictionary) -> Control:
	var d := DB.defender(id)
	var accent := DB.defender_accent(id)
	var p := PanelContainer.new()
	p.name = "Pick_" + id
	p.custom_minimum_size = Vector2(655, 0)
	var is_new: bool = id in r.ins
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.95), Color(UITheme.GREEN, 0.7) if is_new else Color(accent, 0.3), 2 if is_new else 1, 10, 8))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	hb.add_child(DefenderHonors.portrait(id, 64, accent))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	top.add_child(UITheme.label(str(d.name).to_upper(), UITheme.FS_LEAD, accent.lightened(0.3), UITheme.font_header()))
	var lv := UITheme.label("Lv %d · %s" % [Profile.defender_level(id), DB.roles[d.role].name], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	lv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(lv)
	if id == r.captain:
		var cb := UITheme.badge("C", UITheme.GOLD.darkened(0.25), UITheme.FS_MIN)
		cb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(cb)
	if is_new:
		var nb := UITheme.badge("IN", UITheme.GREEN.darkened(0.35), UITheme.FS_MIN)
		nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		top.add_child(nb)
	var rows: Dictionary = r.get("parts", {}).get("rows", {})
	var sc := float(rows[id].score) if rows.has(id) else 0.0
	var scl := UITheme.label("%.1f" % sc, UITheme.FS_BODY, UITheme.GOLD, UITheme.font_display())
	scl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scl.tooltip_text = "TeamAI score in this team"
	scl.mouse_filter = Control.MOUSE_FILTER_PASS
	top.add_child(scl)
	var reasons: Array = r.reasons.get(id, [])
	for i in mini(reasons.size(), 3):
		var rr: Array = reasons[i]
		var rl := HBoxContainer.new()
		rl.add_theme_constant_override("separation", 6)
		var chip := UITheme.badge(str(rr[0]), _reason_color(str(rr[0])), 13)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rl.add_child(chip)
		var t := UITheme.label(str(rr[1]), UITheme.FS_MIN, UITheme.OFFWHITE.darkened(0.08))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.tooltip_text = str(rr[1])
		t.mouse_filter = Control.MOUSE_FILTER_PASS
		rl.add_child(t)
		v.add_child(rl)
	if reasons.size() > 3:
		var more: Array = []
		for i in range(3, reasons.size()):
			more.append(str(reasons[i][1]))
		p.tooltip_text = "\n".join(more)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


func _reason_color(chip: String) -> Color:
	if chip.begins_with("CAPTAIN"):
		return UITheme.GOLD.darkened(0.3)
	if chip.contains("DAMAGE") or chip == "BOSS":
		return DB.category_color("offense").darkened(0.3)
	if chip == "CROWD" or chip == "CONTROL":
		return DB.category_color("control").darkened(0.3)
	if chip == "SYNERGY" or chip == "TEAM BOOST":
		return UITheme.GREEN.darkened(0.45)
	if chip == "SIGNATURE":
		return UITheme.SCARLET.darkened(0.2)
	return Color(0.25, 0.32, 0.45)


## APPLY: sets the previewed six and captain (Profile.set_team) and closes the preview.
func apply_best_team() -> void:
	if best_result.is_empty() or bool(best_result.get("already_best", false)) or (best_result.team as Array).is_empty():
		return
	var ins: Array = best_result.ins
	Profile.set_team(best_result.team, str(best_result.captain))
	Audio.ui("ui_confirm")
	var msg := "Best team applied (%s): score %.1f." % [TeamAI.MODE_NAMES[best_result.mode], float(best_result.score)]
	if not ins.is_empty():
		var names: Array = []
		for id in ins:
			names.append(str(DB.defender(id).name))
		msg = "Best team applied: %s in. Score %.1f → %.1f." % [", ".join(names), float(best_result.current_score), float(best_result.score)]
	Router.toast(msg, "level")
	if is_instance_valid(best_preview):
		best_preview.queue_free()
	_refresh()
	_focus_best_button.call_deferred()


func _focus_best_button() -> void:
	if best_button and is_instance_valid(best_button) and best_button.is_inside_tree():
		best_button.grab_focus()


# ---------------------------------------------------------------- Update 10: Compare

## The natural rival for a defender: when `id` is in the six, the best bench player of the same role
## (else the best bench player); otherwise the weakest team member of the same role (else the weakest).
func compare_partner(id: String) -> String:
	var ctx := TeamAI.profile_context()
	var team: Array = Profile.data.team
	var role: String = DB.defender(id).role
	if id in team:
		for pass_i in 2:
			var best := ""
			var best_s := -INF
			for o in DB.defender_order:
				if o == id or o in team or not Profile.is_defender_unlocked(o):
					continue
				if pass_i == 0 and DB.defender(o).role != role:
					continue
				var s := TeamAI.defender_score(o, ctx, best_mode)
				if s > best_s:
					best_s = s
					best = o
			if best != "":
				return best
		for o in team:   # nobody on the bench: another member of the six
			if o != id and DB.defender(o).role == role:
				return o
		return team[0] if team[0] != id else team[1]
	for pass_i in 2:
		var worst := ""
		var worst_s := INF
		for o in team:
			if pass_i == 0 and DB.defender(o).role != role:
				continue
			var s := TeamAI.defender_score(o, ctx, best_mode)
			if s < worst_s:
				worst_s = s
				worst = o
		if worst != "":
			return worst
	return team[0]


## Opens the side-by-side comparison: `a` on the left, `b` (default: compare_partner(a)) on the right.
func open_compare(a: String, b := "") -> TeamCompare:
	if not DB.defenders.has(a):
		return null
	if b == "" or not DB.defenders.has(b) or b == a:
		b = compare_partner(a)
	if compare and is_instance_valid(compare):
		compare.queue_free()
	var c := TeamCompare.new(a, b, _screen, best_mode)
	compare = c
	c.team_changed.connect(func() -> void:
		_fill_list()
		_fill_info()
		_fill_team())
	c.closed.connect(func() -> void:
		if compare == c:
			compare = null
			_focus_compare_button.call_deferred())
	_screen.add_child(c)
	_screen.push_overlay(c)
	Audio.ui("ui_tab")
	return c


func _focus_compare_button() -> void:
	if compare_button and is_instance_valid(compare_button) and compare_button.is_inside_tree():
		compare_button.grab_focus()
