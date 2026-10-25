extends Control
## End-of-run results: outcome, stats, rewards (coins, XP, defender XP, card packs,
## rank points), records and achievements.

var battle: Battle
var result: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.6, 1.2).set_delay(1.2)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)
	var won: bool = result.get("won", false)
	var practice: bool = result.get("practice", false)
	var title := UITheme.title("VICTORY!" if won else ("PRACTICE OVER" if practice else "DEFEAT"), 120,
		UITheme.GOLD if won else (UITheme.BLUE if practice else UITheme.SCARLET))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	title.pivot_offset = Vector2(900, 60)
	title.scale = Vector2(0.5, 0.5)
	title.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.6)
	tw.tween_property(title, "modulate:a", 1.0, 0.3).set_delay(0.6)

	if practice:
		var b := UITheme.menu_button("MAIN MENU", UITheme.SCARLET)
		b.pressed.connect(func() -> void: Router.goto("main_menu"))
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)
		return

	var mode := DB.mode(result.get("mode", "standard"))
	var sub := UITheme.header("%s · %s · %s" % [mode.name, DB.difficulty(result.get("difficulty", "standard")).name, DB.arena(result.get("arena", "steel_yard")).name], 30, UITheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.modulate.a = 0.0
	vb.add_child(body)
	create_tween().tween_property(body, "modulate:a", 1.0, 0.5).set_delay(1.4)

	# Stats
	var stats := _panel("MATCH STATS")
	stats.custom_minimum_size = Vector2(420, 0)
	body.add_child(stats)
	var sv: VBoxContainer = stats.get_child(0)
	var st: Dictionary = result.get("stats", {})
	sv.add_child(_kv("Innings cleared", str(result.get("innings_cleared", 0))))
	sv.add_child(_kv("Outs", str(result.get("outs", 0))))
	sv.add_child(_kv("Runs allowed", "%d / %d" % [int(result.get("runs", 0)), int(result.get("run_limit", 3))]))
	sv.add_child(_kv("Best combo", str(int(st.get("max_combo", 0)))))
	sv.add_child(_kv("Double / triple plays", "%d / %d" % [int(st.get("double_plays", 0)), int(st.get("triple_plays", 0))]))
	sv.add_child(_kv("Cards played", str(int(st.get("cards_played", 0)))))
	sv.add_child(_kv("Bosses defeated", str(st.get("bosses", []).size())))
	sv.add_child(_kv("Score", UITheme.format_int(int(result.get("score", 0))), UITheme.GOLD))
	var mvp: String = result.get("mvp", "")
	if mvp != "":
		var hb := HBoxContainer.new()
		var pt := TextureRect.new()
		pt.texture = DB.portrait(mvp)
		pt.custom_minimum_size = Vector2(72, 72)
		pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(pt)
		var mv := VBoxContainer.new()
		mv.add_child(UITheme.label("MVP", 18, UITheme.MUTED, UITheme.font_body_bold()))
		mv.add_child(UITheme.label(DB.defender(mvp).name.to_upper(), 40, Color(DB.defender(mvp).accent).lightened(0.3), UITheme.font_display()))
		hb.add_child(mv)
		sv.add_child(hb)

	# Rewards
	var rew := _panel("REWARDS")
	rew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rew)
	var rv: VBoxContainer = rew.get_child(0)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	top.add_child(_reward_chip("coin", "+%s" % UITheme.format_int(int(result.get("coins", 0))), UITheme.GOLD))
	top.add_child(_reward_chip("upgrade", "+%d XP" % int(result.get("xp", 0)), UITheme.GREEN))
	top.add_child(_reward_chip("trophy", "+%d RP" % int(result.get("rp", 0)), UITheme.BLUE))
	rv.add_child(top)
	if int(result.get("levels", 0)) > 0:
		rv.add_child(UITheme.label("ACCOUNT LEVEL UP!  Now level %d" % int(Profile.data.level), 26, UITheme.GREEN, UITheme.font_display()))
	var xpbar := ProgressBar.new()
	xpbar.max_value = Profile.xp_to_next(int(Profile.data.level))
	xpbar.value = int(Profile.data.xp)
	xpbar.custom_minimum_size = Vector2(0, 14)
	xpbar.show_percentage = false
	xpbar.add_theme_stylebox_override("fill", UITheme.panel_style(UITheme.GREEN, Color(0, 0, 0, 0), 0, 4, 0))
	rv.add_child(UITheme.label("Level %d — %d / %d XP" % [int(Profile.data.level), int(Profile.data.xp), Profile.xp_to_next(int(Profile.data.level))], 18, UITheme.MUTED))
	rv.add_child(xpbar)
	if result.get("promoted", false):
		rv.add_child(UITheme.label("PROMOTED TO %s!" % Profile.division().name.to_upper(), 34, UITheme.GOLD, UITheme.font_display()))
	elif Profile.promotion_available():
		rv.add_child(UITheme.label("Promotion Challenge available: %s!" % Profile.next_division().name, 22, UITheme.GOLD, UITheme.font_body_bold()))
	rv.add_child(UITheme.hsep())
	var packs: Array = result.get("packs", [])
	rv.add_child(UITheme.header("PACKS EARNED" if not packs.is_empty() else "NO PACKS THIS TIME", 26, UITheme.GOLD))
	var pack_row := HBoxContainer.new()
	pack_row.add_theme_constant_override("separation", 14)
	rv.add_child(pack_row)
	var i := 0
	for pk in packs:
		var art := PackArt.new(str(pk.type), str(pk.get("card", "")))
		art.custom_minimum_size = Vector2(96, 148)
		art.pivot_offset = Vector2(48, 74)
		art.modulate.a = 0.0
		art.scale = Vector2.ONE * 0.6
		art.tooltip_text = "%s — %s" % [DB.pack(str(pk.type)).name, pk.get("source", "")]
		pack_row.add_child(art)
		var t := create_tween()
		t.tween_interval(1.6 + i * 0.25)
		t.tween_callback(func() -> void: Audio.play("card_draw"))
		t.set_parallel(true)
		t.tween_property(art, "modulate:a", 1.0, 0.25)
		t.tween_property(art, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	if not packs.is_empty():
		var open := UITheme.menu_button("OPEN PACKS", UITheme.GOLD, 30)
		open.custom_minimum_size = Vector2(250, 60)
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void: Router.goto("packs"))
		pack_row.add_child(open)
	rv.add_child(UITheme.hsep())
	rv.add_child(UITheme.header("TEAM PROGRESS", 24, UITheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	rv.add_child(grid)
	var ti := 0
	for id in result.get("defender_xp", {}).keys():
		grid.add_child(_progress_tile(id, result.defender_xp[id], 2.0 + ti * 0.25))
		ti += 1
	for rec in result.get("records", []):
		rv.add_child(UITheme.label("★ " + rec, 22, UITheme.GOLD, UITheme.font_body_bold()))
	for aid in result.get("achievements", []):
		rv.add_child(UITheme.label("Achievement unlocked: %s" % DB.achievements[aid].name, 20, UITheme.GOLD, UITheme.font_body_bold()))

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 18)
	vb.add_child(buttons)
	var again := UITheme.menu_button("PLAY AGAIN", UITheme.GREEN)
	again.pressed.connect(func() -> void:
		var cfg: Dictionary = battle.run.config.duplicate(true)
		cfg.seed = randi()
		cfg.resume = null
		cfg.deck = Profile.data.deck.duplicate()
		cfg.team = Profile.data.team.duplicate()
		Session.start(cfg))
	buttons.add_child(again)
	var deck := UITheme.menu_button("CARDS & DECK", UITheme.BLUE)
	deck.pressed.connect(func() -> void: Router.goto("deck_builder"))
	buttons.add_child(deck)
	var menu := UITheme.menu_button("MAIN MENU", UITheme.SCARLET)
	menu.pressed.connect(func() -> void: Router.goto("main_menu"))
	buttons.add_child(menu)


## One defender's XP gain: the bar fills from before to after; each level gained flashes
## LEVEL UP! and shows the level road reward it unlocked.
func _progress_tile(id: String, d: Dictionary, delay: float) -> Control:
	var accent := Color(DB.defender(id).accent)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.95), Color(accent, 0.45), 1, 10, 8))
	p.custom_minimum_size = Vector2(250, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var pt := DB.portrait(id)
	if pt:
		var tr := TextureRect.new()
		tr.texture = pt
		tr.custom_minimum_size = Vector2(52, 52)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tr)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var nm := UITheme.label(DB.defender(id).name, 20, accent.lightened(0.35), UITheme.font_header())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var lvl_l := UITheme.label("LV %d" % int(d.get("level_before", d.level)), 20, UITheme.GOLD, UITheme.font_display())
	top.add_child(lvl_l)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 12)
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.add_theme_stylebox_override("fill", UITheme.panel_style(accent.lightened(0.15), Color(0, 0, 0, 0), 0, 4, 0))
	var lb := int(d.get("level_before", d.level))
	var need0 := maxi(1, Profile.defender_xp_needed(lb))
	bar.value = clampf(float(d.get("xp_before", 0)) / need0, 0.0, 1.0)
	vb.add_child(bar)
	var info := UITheme.label("+%d XP" % int(d.xp) + ("  ·  %d outs" % int(d.outs) if int(d.get("outs", 0)) > 0 else ""), 15, UITheme.MUTED, UITheme.font_body_bold())
	vb.add_child(info)
	var levels := int(d.get("levels", 0))
	var after := clampf(float(d.get("xp_after", 0)) / maxi(1, Profile.defender_xp_needed(int(d.level))), 0.0, 1.0)
	if int(d.level) >= DB.defender_max_level:
		after = 1.0
	var tw := create_tween()
	tw.tween_interval(delay)
	for k in levels:
		var lv := lb + k + 1
		tw.tween_property(bar, "value", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Audio.play("level_up", -4.0)
			lvl_l.text = "LV %d" % lv
			p.modulate = Color(1.5, 1.4, 1.1)
			p.pivot_offset = p.size * 0.5
			p.scale = Vector2(1.06, 1.06)
			var rewards: Array = d.get("rewards", [])
			info.text = "LEVEL UP!" + ("  +" + str(rewards[k]) if k < rewards.size() else "")
			info.add_theme_color_override("font_color", UITheme.GOLD)
			bar.value = 0.0)
		tw.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(p, "modulate", Color.WHITE, 0.4)
	tw.tween_property(bar, "value", after, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return p


func _panel(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.04, 0.07, 0.12, 0.92), Color(1, 1, 1, 0.12), 1, 12, 18))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	vb.add_child(UITheme.header(title, 30, UITheme.GOLD))
	return p


func _kv(k: String, v: String, vc := UITheme.OFFWHITE) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var kl := UITheme.label(k, 21, UITheme.MUTED)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(kl)
	hb.add_child(UITheme.label(v, 21, vc, UITheme.font_body_bold()))
	return hb


func _reward_chip(icon: String, text: String, col: Color) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_child(UITheme.icon_rect(icon, 38, col))
	hb.add_child(UITheme.label(text, 40, col, UITheme.font_display()))
	return hb
