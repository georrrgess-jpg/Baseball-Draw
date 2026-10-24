extends MenuScreen
## Long-term progression: account level and rank ladder, achievements, stadium
## unlocks, the Pro Shop (permanent gear) and match history / records.

var _tabs: TabContainer


func _ready() -> void:
	setup_screen("PROGRESSION", "Rank ladder, achievements, stadiums, gear and records")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	_tabs.add_child(_overview_tab())
	_tabs.add_child(_achievements_tab())
	_tabs.add_child(_stadiums_tab())
	_tabs.add_child(_shop_tab())
	_tabs.add_child(_history_tab())
	_tabs.tab_changed.connect(func(_i: int) -> void: Audio.ui("ui_tab"))


func _scroll(name: String) -> Array:
	var s := ScrollContainer.new()
	s.name = name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	s.add_child(vb)
	return [s, vb]


func _overview_tab() -> Control:
	var r := _scroll("Overview")
	var vb: VBoxContainer = r[1]
	var d: Dictionary = Profile.data
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 30)
	vb.add_child(top)
	var lvl := VBoxContainer.new()
	lvl.add_child(UITheme.label("ACCOUNT LEVEL", 20, UITheme.MUTED, UITheme.font_body_bold()))
	lvl.add_child(UITheme.title(str(int(d.level)), 96, UITheme.GREEN))
	var xp := ProgressBar.new()
	xp.custom_minimum_size = Vector2(320, 14)
	xp.max_value = Profile.xp_to_next(int(d.level))
	xp.value = int(d.xp)
	xp.show_percentage = false
	xp.add_theme_stylebox_override("fill", UITheme.panel_style(UITheme.GREEN, Color(0, 0, 0, 0), 0, 4, 0))
	lvl.add_child(xp)
	lvl.add_child(UITheme.label("%d / %d XP to level %d" % [int(d.xp), Profile.xp_to_next(int(d.level)), int(d.level) + 1], 18, UITheme.MUTED))
	top.add_child(lvl)
	var stats := GridContainer.new()
	stats.columns = 2
	stats.add_theme_constant_override("h_separation", 24)
	var rows := [
		["Runs played", int(Profile.stat("runs_played"))], ["Total outs", int(Profile.stat("total_outs"))],
		["Standard Siege wins", int(Profile.stat("wins_standard"))], ["Quick Defense wins", int(Profile.stat("wins_quick"))],
		["Endless best inning", int(d.records.get("best_endless_inning", 0))], ["Endless best score", int(d.records.get("best_endless_score", 0))],
		["Double plays", int(Profile.stat("double_plays"))], ["Cards played", int(Profile.stat("cards_played"))],
	]
	for row in rows:
		stats.add_child(UITheme.label(row[0], 20, UITheme.MUTED))
		stats.add_child(UITheme.label(UITheme.format_int(row[1]), 22, UITheme.OFFWHITE, UITheme.font_body_bold()))
	top.add_child(stats)
	vb.add_child(UITheme.hsep())
	vb.add_child(UITheme.header("RANK LADDER", 34, UITheme.GOLD))
	var ladder := HBoxContainer.new()
	ladder.add_theme_constant_override("separation", 10)
	vb.add_child(ladder)
	for i in DB.divisions.size():
		var div: Dictionary = DB.divisions[i]
		var cur := i == int(d.division)
		var p := MenuScreen.panel(Color(0.05, 0.08, 0.14, 0.95) if not cur else Color(Color(div.color).darkened(0.6), 0.95),
			Color(div.color, 0.9 if cur else 0.25), 10)
		p.custom_minimum_size = Vector2(180, 0)
		var pv := VBoxContainer.new()
		pv.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(pv)
		var path := "res://assets/textures/ui/rank_%s.png" % div.id
		if ResourceLoader.exists(path):
			var em := TextureRect.new()
			em.texture = load(path)
			em.custom_minimum_size = Vector2(120, 120)
			em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if i > int(d.division):
				em.modulate = Color(0.4, 0.4, 0.45)
			pv.add_child(em)
		var nl := UITheme.label(div.name.to_upper(), 26, Color(div.color) if i <= int(d.division) else UITheme.MUTED, UITheme.font_display())
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(nl)
		var rl := UITheme.label("%d RP" % int(div.rp_required), 17, UITheme.MUTED, UITheme.font_body_bold())
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(rl)
		if cur:
			var you := UITheme.label("YOU", 18, UITheme.GOLD, UITheme.font_body_bold())
			you.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pv.add_child(you)
		ladder.add_child(p)
	var nd := Profile.next_division()
	var rp_txt := "Rank points: %d. " % int(d.rp)
	if nd.is_empty():
		rp_txt += "You are at the top of the ladder."
	elif Profile.promotion_available():
		rp_txt += "Promotion Challenge to %s is available from PLAY → Promotion Challenge!" % nd.name
	else:
		rp_txt += "Earn %d more RP (win games, higher difficulties earn more) to unlock the %s Promotion Challenge." % [int(nd.rp_required) - int(d.rp), nd.name]
	var rpl := UITheme.label(rp_txt, 20, UITheme.OFFWHITE)
	rpl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(rpl)
	return r[0]


func _achievements_tab() -> Control:
	var r := _scroll("Achievements")
	var vb: VBoxContainer = r[1]
	var done := 0
	for id in DB.achievement_order:
		if Profile.data.achievements.has(id):
			done += 1
	vb.add_child(UITheme.label("%d / %d unlocked. Achievements award stars, spent on uniforms." % [done, DB.achievement_order.size()], 20, UITheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	for id in DB.achievement_order:
		var a: Dictionary = DB.achievements[id]
		var got: bool = Profile.data.achievements.has(id)
		var p := MenuScreen.panel(Color(0.05, 0.08, 0.14, 0.92), Color(UITheme.GOLD, 0.6) if got else Color(1, 1, 1, 0.08), 12)
		p.custom_minimum_size = Vector2(780, 0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		p.add_child(hb)
		hb.add_child(UITheme.icon_rect("trophy", 44, UITheme.GOLD if got else Color(1, 1, 1, 0.2)))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(UITheme.label(a.name, 24, UITheme.GOLD if got else UITheme.OFFWHITE, UITheme.font_header()))
		info.add_child(UITheme.label(a.text, 18, UITheme.MUTED))
		var pb := ProgressBar.new()
		pb.custom_minimum_size = Vector2(0, 6)
		pb.max_value = 1.0
		pb.value = Profile.achievement_progress(id)
		pb.show_percentage = false
		pb.add_theme_stylebox_override("fill", UITheme.panel_style(UITheme.GOLD, Color(0, 0, 0, 0), 0, 3, 0))
		info.add_child(pb)
		hb.add_child(info)
		var star := HBoxContainer.new()
		star.add_child(UITheme.icon_rect("star", 24, Color(0.7, 0.85, 1.0)))
		star.add_child(UITheme.label(str(int(a.stars)), 22, Color(0.7, 0.85, 1.0), UITheme.font_header()))
		hb.add_child(star)
		grid.add_child(p)
	return r[0]


func _stadiums_tab() -> Control:
	var r := _scroll("Stadiums")
	var vb: VBoxContainer = r[1]
	for id in DB.arena_order:
		var a := DB.arena(id)
		var unlocked: bool = id in Profile.data.arenas_unlocked
		var accent := Color(a.theme.get("accent", "#ffffff"))
		var p := MenuScreen.panel(Color(0.05, 0.08, 0.14, 0.92), Color(accent, 0.6 if unlocked else 0.12), 14)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 18)
		p.add_child(hb)
		var sky := ColorRect.new()
		sky.custom_minimum_size = Vector2(150, 84)
		sky.color = Color(a.theme.sky_horizon).lerp(Color(a.theme.sky_top), 0.4)
		hb.add_child(sky)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UITheme.label(a.name.to_upper(), 30, UITheme.OFFWHITE if unlocked else UITheme.MUTED, UITheme.font_display()))
		var t := UITheme.label(a.text, 18, UITheme.MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(t)
		info.add_child(UITheme.label("Modifier — %s: %s · Layout: %s" % [a.modifier.name, a.modifier.text, str(a.layout).replace("_", " ")], 18, accent, UITheme.font_body_bold()))
		hb.add_child(info)
		hb.add_child(UITheme.label("UNLOCKED" if unlocked else "LOCKED\n" + Profile.arena_unlock_text(id), 20, UITheme.GREEN if unlocked else UITheme.SCARLET, UITheme.font_body_bold()))
		vb.add_child(p)
	return r[0]


func _shop_tab() -> Control:
	var r := _scroll("Pro Shop")
	var vb: VBoxContainer = r[1]
	vb.add_child(UITheme.label("Permanent gear bought with coins. Each item is equipped on one defender (Roster screen).", 20, UITheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for gid in DB.gear_order:
		var g: Dictionary = DB.gear[gid]
		var owned: bool = gid in Profile.data.gear_owned
		var p := MenuScreen.panel(Color(0.05, 0.08, 0.14, 0.92), Color(UITheme.GOLD, 0.5) if owned else Color(1, 1, 1, 0.1), 14)
		p.custom_minimum_size = Vector2(780, 0)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		p.add_child(hb)
		hb.add_child(UITheme.icon_rect("upgrade", 46, UITheme.GOLD))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UITheme.label(g.name, 26, UITheme.OFFWHITE, UITheme.font_header()))
		info.add_child(UITheme.label(g.text, 18, UITheme.MUTED))
		var holder := ""
		for k in Profile.data.gear_equipped.keys():
			if Profile.data.gear_equipped[k] == gid:
				holder = DB.defender(k).name
		if owned:
			info.add_child(UITheme.label("Equipped on " + holder if holder != "" else "Owned — not equipped", 17, UITheme.GREEN, UITheme.font_body_bold()))
		hb.add_child(info)
		var b := UITheme.small_button("OWNED" if owned else "%s" % UITheme.format_int(int(g.price)), UITheme.GOLD, 22)
		if not owned:
			b.icon = DB.icon("coin")
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 22)
		b.disabled = owned or int(Profile.data.coins) < int(g.price)
		b.custom_minimum_size = Vector2(140, 50)
		b.pressed.connect(func() -> void:
			if Profile.buy_gear(gid):
				Audio.play("purchase")
				Router.toast("%s purchased! Equip it in the Roster." % g.name, "info")
				_rebuild_tab(3))
		hb.add_child(b)
		grid.add_child(p)
	return r[0]


func _history_tab() -> Control:
	var r := _scroll("History")
	var vb: VBoxContainer = r[1]
	var hist: Array = Profile.data.history
	if hist.is_empty():
		vb.add_child(UITheme.label("No games played yet.", 22, UITheme.MUTED))
	for h in hist:
		var p := MenuScreen.panel(Color(0.05, 0.08, 0.14, 0.92), Color(UITheme.GREEN, 0.5) if h.won else Color(UITheme.SCARLET, 0.4), 10)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 20)
		p.add_child(hb)
		hb.add_child(UITheme.label("WIN" if h.won else "LOSS", 28, UITheme.GREEN if h.won else UITheme.SCARLET, UITheme.font_display()))
		hb.add_child(UITheme.label("%s · %s · %s" % [DB.mode(h.mode).name, DB.difficulty(h.difficulty).name, DB.arena(h.get("arena", "steel_yard")).name], 20, UITheme.OFFWHITE, UITheme.font_body_bold()))
		var s := UITheme.label("Inning %d · %d outs · %d runs · %s pts" % [int(h.inning), int(h.outs), int(h.runs), UITheme.format_int(int(h.score))], 19, UITheme.MUTED)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(s)
		hb.add_child(UITheme.label(str(h.get("date", "")).replace("T", " "), 16, UITheme.MUTED))
		vb.add_child(p)
	return r[0]


func _rebuild_tab(index: int) -> void:
	var old := _tabs.get_child(index)
	var fresh: Control
	match index:
		3: fresh = _shop_tab()
		_: return
	_tabs.remove_child(old)
	old.queue_free()
	_tabs.add_child(fresh)
	_tabs.move_child(fresh, index)
	_tabs.current_tab = index
