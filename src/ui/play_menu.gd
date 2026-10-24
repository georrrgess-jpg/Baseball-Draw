extends MenuScreen
## Mode, difficulty and stadium selection, with a summary of the team and deck.

var mode_id := "standard"
var _mode_buttons := {}
var _diff_buttons := {}
var _arena_list: VBoxContainer
var _mode_desc: Label
var _start: Button
var _summary: VBoxContainer
var _arena_preview: Label


func _ready() -> void:
	setup_screen("PLAY", "Choose a mode, difficulty and stadium")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	content.add_child(body)

	# Modes
	var modes := panel()
	modes.custom_minimum_size = Vector2(560, 0)
	body.add_child(modes)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 12)
	modes.add_child(mv)
	mv.add_child(UITheme.header("GAME MODE", 32, UITheme.GOLD))
	var mode_list := [
		["standard", UITheme.SCARLET, "9 innings · 3 bosses · full rewards"],
		["quick", UITheme.BLUE, "3 innings · 1 boss · ~10 minutes"],
		["endless", UITheme.PURPLE, "Survive · modifiers · records"],
		["ranked", UITheme.GOLD, ""],
		["practice", UITheme.GREEN, "Sandbox · no rewards, no risk"],
	]
	for m in mode_list:
		var id: String = m[0]
		var b := UITheme.menu_button(DB.mode(id).name.to_upper(), m[1], 34, -0.12)
		b.custom_minimum_size = Vector2(520, 64)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.pressed.connect(func() -> void: _select_mode(id))
		mv.add_child(b)
		var sub: String = m[2]
		if id == "ranked":
			if Profile.promotion_available():
				sub = "Promotion to %s available!" % Profile.next_division().name
			else:
				var nd := Profile.next_division()
				sub = "Reach %d RP to unlock the %s challenge (now %d RP)" % [int(nd.rp_required), nd.name, int(Profile.data.rp)] if not nd.is_empty() else "You are a Legend!"
				b.disabled = true
		var sl := UITheme.label("      " + sub, 18, UITheme.MUTED, UITheme.font_body_bold())
		mv.add_child(sl)
		_mode_buttons[id] = b
	mv.add_child(UITheme.hsep())
	_mode_desc = UITheme.label("", 20, UITheme.OFFWHITE)
	_mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_desc.custom_minimum_size = Vector2(500, 0)
	mv.add_child(_mode_desc)

	# Difficulty + stadium
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 16)
	body.add_child(mid)
	var dp := panel()
	mid.add_child(dp)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dp.add_child(dv)
	dv.add_child(UITheme.header("DIFFICULTY", 32, UITheme.GOLD))
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	dv.add_child(dh)
	var diff_desc := UITheme.label("", 18, UITheme.MUTED)
	diff_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for id in DB.difficulty_order:
		var d := DB.difficulty(id)
		var b := UITheme.small_button(d.name, [UITheme.GREEN, UITheme.BLUE, UITheme.GOLD, UITheme.SCARLET][DB.difficulty_order.find(id)], 24)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 48)
		b.tooltip_text = "%s\nRun limit %d · Starting shields %d · Rewards x%.2f" % [d.text, int(d.run_limit), int(d.shields), float(d.reward)]
		b.pressed.connect(func() -> void:
			Profile.data.difficulty = id
			for k in _diff_buttons.keys():
				_diff_buttons[k].button_pressed = k == id
			diff_desc.text = "%s  Run limit %d, shields %d, rewards x%.2f." % [d.text, int(d.run_limit), int(d.shields), float(d.reward)]
			Profile.save_soon())
		dh.add_child(b)
		_diff_buttons[id] = b
	dv.add_child(diff_desc)
	var cur_diff: String = Profile.data.difficulty
	_diff_buttons[cur_diff].button_pressed = true
	var cd := DB.difficulty(cur_diff)
	diff_desc.text = "%s  Run limit %d, shields %d, rewards x%.2f." % [cd.text, int(cd.run_limit), int(cd.shields), float(cd.reward)]

	var ap := panel()
	ap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(ap)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 8)
	ap.add_child(av)
	av.add_child(UITheme.header("STADIUM", 32, UITheme.GOLD))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	av.add_child(scroll)
	_arena_list = VBoxContainer.new()
	_arena_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arena_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_arena_list)
	_fill_arenas()

	# Summary + start
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(440, 0)
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	var sp := panel()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 8)
	sp.add_child(_summary)
	_fill_summary()
	_start = UITheme.menu_button("START  ▶", UITheme.SCARLET, 46)
	_start.custom_minimum_size = Vector2(440, 86)
	_start.pressed.connect(_on_start)
	right.add_child(_start)

	_select_mode("standard" if not Profile.has_saved_run() else "quick")


func _select_mode(id: String) -> void:
	mode_id = id
	for k in _mode_buttons.keys():
		_mode_buttons[k].button_pressed = k == id
	var m := DB.mode(id)
	var txt: String = m.text
	if id == "ranked":
		var nd := Profile.next_division()
		if not nd.is_empty():
			txt += "\nDivision challenge: %s difficulty, 3 innings with special modifiers. Win to be promoted to %s." % [DB.difficulty(nd.challenge_difficulty).name, nd.name]
	if id == "endless":
		txt += "\nBest so far: inning %d · %s points." % [int(Profile.data.records.get("best_endless_inning", 0)), UITheme.format_int(int(Profile.data.records.get("best_endless_score", 0)))]
	if Profile.has_saved_run() and id != "practice":
		txt += "\n\nNote: starting a new run replaces your saved run in progress."
	_mode_desc.text = txt
	for k in _diff_buttons.keys():
		_diff_buttons[k].disabled = id in ["practice", "ranked"]
	Audio.ui("ui_tab")


func _fill_arenas() -> void:
	for c in _arena_list.get_children():
		c.queue_free()
	for id in DB.arena_order:
		var a := DB.arena(id)
		var unlocked: bool = id in Profile.data.arenas_unlocked
		var row := Button.new()
		row.toggle_mode = true
		row.button_pressed = Profile.data.arena == id
		row.disabled = not unlocked
		row.custom_minimum_size = Vector2(0, 76)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var accent := Color(a.theme.get("accent", "#ffffff"))
		row.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.9), Color(accent, 0.25), 1, 8, 10))
		row.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0.1, 0.14, 0.22, 0.95), Color(accent, 0.8), 2, 8, 10))
		row.add_theme_stylebox_override("pressed", UITheme.panel_style(Color(accent.darkened(0.6), 0.95), accent, 2, 8, 10))
		row.add_theme_stylebox_override("disabled", UITheme.panel_style(Color(0.04, 0.05, 0.08, 0.8), Color(1, 1, 1, 0.05), 1, 8, 10))
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 14
		hb.offset_right = -14
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 14)
		row.add_child(hb)
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(10, 0)
		swatch.color = accent
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(swatch)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -2)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		var name_l := UITheme.label(a.name.to_upper(), 28, UITheme.OFFWHITE if unlocked else UITheme.MUTED, UITheme.font_header())
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(name_l)
		var sub := "%s — %s" % [a.modifier.name, a.modifier.text] if unlocked else "LOCKED: " + Profile.arena_unlock_text(id)
		var sub_l := UITheme.label(sub, 17, UITheme.MUTED, UITheme.font_body_bold())
		sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(sub_l)
		hb.add_child(vb)
		row.tooltip_text = a.text
		row.pressed.connect(func() -> void:
			Profile.data.arena = id
			Profile.save_soon()
			Audio.ui("ui_toggle")
			_fill_arenas())
		_arena_list.add_child(row)


func _fill_summary() -> void:
	for c in _summary.get_children():
		c.queue_free()
	_summary.add_child(UITheme.header("YOUR TEAM", 30, UITheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	for id in Profile.data.team:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.add_child(portrait_rect(id, 96, DB.defender_accent(id)))
		var n: String = DB.defender(id).name + (" (C)" if id == Profile.data.captain else "")
		var l := UITheme.label(n, 18, DB.defender_accent(id).lightened(0.3), UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		grid.add_child(vb)
	_summary.add_child(grid)
	var edit_team := UITheme.small_button("Edit team (Roster)", UITheme.BLUE, 20)
	edit_team.pressed.connect(func() -> void: Router.goto("roster"))
	_summary.add_child(edit_team)
	_summary.add_child(UITheme.hsep())
	_summary.add_child(UITheme.header("DECK", 30, UITheme.GOLD))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 4)
	for cid in Profile.data.deck:
		var c := DB.card(cid)
		var chip := PanelContainer.new()
		chip.add_theme_stylebox_override("panel", UITheme.panel_style(DB.category_color(c.category).darkened(0.6), DB.rarity_color(c.rarity), 1, 6, 6))
		chip.add_child(UITheme.label("%s  %d" % [c.name, int(c.cost)], 17, UITheme.OFFWHITE, UITheme.font_body_bold()))
		flow.add_child(chip)
	_summary.add_child(flow)
	var edit_deck := UITheme.small_button("Edit deck", UITheme.BLUE, 20)
	edit_deck.pressed.connect(func() -> void:
		Session.menu_tab = "deck"
		Router.goto("deck_builder"))
	_summary.add_child(edit_deck)
	var fname: String = DB.formations.get(Profile.data.formation, {}).get("name", "Custom")
	_summary.add_child(UITheme.label("Formation: %s (change it on the field before the first pitch)" % fname, 17, UITheme.MUTED))


func _on_start() -> void:
	Audio.ui("ui_confirm")
	var cfg := Session.new_run_config(mode_id)
	if mode_id == "ranked":
		var nd := Profile.next_division()
		cfg.difficulty = nd.get("challenge_difficulty", "standard")
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["ranked", int(Profile.data.division)])
		var mods: Array = DB.challenge_modifiers.duplicate()
		var picked: Array = []
		for i in 2:
			var k := rng.randi() % mods.size()
			picked.append(mods[k])
			mods.remove_at(k)
		cfg.modifiers = picked
		cfg.seed = hash(["ranked_seed", int(Profile.data.division)])
	if mode_id != "practice":
		Profile.clear_run()
	Profile.save_now()
	Session.start(cfg)
