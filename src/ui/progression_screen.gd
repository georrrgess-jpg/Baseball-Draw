extends MenuScreen
## Long-term progression: rank emblem with a progress ring and the next reward, account
## level, a stats dashboard and the rank ladder; achievements with progress; stadium
## unlocks; the Pro Shop (permanent gear) and match history.

var _tabs: TabContainer


func _ready() -> void:
	setup_screen("PROGRESSION", "Rank, achievements, stadiums, gear and match history")
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_tabs)
	_tabs.add_child(_overview_tab())
	_tabs.add_child(_achievements_tab())
	_tabs.add_child(_stadiums_tab())
	_tabs.add_child(_shop_tab())
	_tabs.add_child(_history_tab())
	_tabs.tab_changed.connect(func(i: int) -> void:
		Audio.ui("ui_tab")
		var page := _tabs.get_child(i)
		if page is Control:
			UITheme.animate_in(page, 0.0, 0.99))
	var icons := ["progression", "trophy", "map", "upgrade", "inning"]
	for i in icons.size():
		_tabs.set_tab_icon(i, DB.icon(icons[i]))
		_tabs.set_tab_icon_max_width(i, 26)
	for a in OS.get_cmdline_user_args():   # screenshot helper
		if a.begins_with("--tab="):
			_tabs.current_tab = clampi(int(a.split("=")[1]), 0, _tabs.get_tab_count() - 1)


func _scroll(name: String) -> Array:
	var s := ScrollContainer.new()
	s.name = name
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	s.add_child(vb)
	return [s, vb]


# ---------------------------------------------------------------- overview

func _overview_tab() -> Control:
	var r := _scroll("Overview")
	var vb: VBoxContainer = r[1]
	var d: Dictionary = Profile.data
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	vb.add_child(top)

	# Rank: emblem inside a ring showing progress towards the next division.
	var div := Profile.division()
	var nd := Profile.next_division()
	var rank := UITheme.card_panel(Color(Color(div.color), 0.5), 20)
	rank.custom_minimum_size = Vector2(560, 0)
	top.add_child(rank)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 22)
	rank.add_child(rh)
	var ring := ProgressRing.new(Color(div.color).lightened(0.1), 230, 14)
	ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var prev_rp := int(div.rp_required)
	var frac := 1.0
	if not nd.is_empty():
		frac = clampf(float(int(d.rp) - prev_rp) / maxf(1.0, float(int(nd.rp_required) - prev_rp)), 0.0, 1.0)
	ring.value = 0.0
	create_tween().tween_property(ring, "value", frac, 0.9).set_delay(0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var em_path := "res://assets/textures/ui/rank_%s.png" % div.id
	if ResourceLoader.exists(em_path):
		var em := TextureRect.new()
		em.texture = load(em_path)
		em.custom_minimum_size = Vector2(170, 170)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ring.add_child(em)
	rh.add_child(ring)
	var ri := VBoxContainer.new()
	ri.alignment = BoxContainer.ALIGNMENT_CENTER
	ri.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ri.add_theme_constant_override("separation", 2)
	rh.add_child(ri)
	ri.add_child(UITheme.label("DIVISION", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	ri.add_child(UITheme.title(str(div.name).to_upper(), 64, Color(div.color).lightened(0.15)))
	ri.add_child(UITheme.label("%s RP" % UITheme.format_int(int(d.rp)) + ("" if nd.is_empty() else "  /  %s RP" % UITheme.format_int(int(nd.rp_required))), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header()))
	var next_p := UITheme.tile_panel(Color(UITheme.GOLD, 0.35), 10)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 0)
	next_p.add_child(nv)
	nv.add_child(UITheme.label("NEXT REWARD", UITheme.FS_MIN, UITheme.GOLD, UITheme.font_body_bold()))
	var next_txt := ""
	if nd.is_empty():
		next_txt = "You are at the top of the ladder. Legend!"
	elif Profile.promotion_available():
		next_txt = "Promotion Challenge to %s is ready! PLAY → Promotion Challenge." % nd.name
	else:
		next_txt = "%s Promotion Challenge: earn %d more RP. Wins on higher difficulties earn more." % [nd.name, int(nd.rp_required) - int(d.rp)]
	var unlock := _rank_unlock_text(int(d.division) + 1)
	if unlock != "":
		next_txt += "\nReaching %s unlocks %s." % [nd.name, unlock]
	var nl := UITheme.label(next_txt, UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.custom_minimum_size = Vector2(230, 0)
	nv.add_child(nl)
	ri.add_child(next_p)

	# Account level.
	var lvl := UITheme.card_panel(Color(UITheme.GREEN, 0.4), 20)
	lvl.custom_minimum_size = Vector2(360, 0)
	top.add_child(lvl)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 6)
	lvl.add_child(lv)
	lv.add_child(UITheme.section_header("ACCOUNT LEVEL", "upgrade", UITheme.GREEN, UITheme.FS_H3))
	var lring := ProgressRing.new(UITheme.GREEN, 150, 10)
	lring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	lring.value = 0.0
	create_tween().tween_property(lring, "value", float(d.xp) / maxi(1, Profile.xp_to_next(int(d.level))), 0.9).set_delay(0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var lnum := UITheme.title(str(int(d.level)), 72, UITheme.GREEN)
	lnum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lring.add_child(lnum)
	lv.add_child(lring)
	var xl := UITheme.label("%s / %s XP to level %d" % [UITheme.format_int(int(d.xp)), UITheme.format_int(Profile.xp_to_next(int(d.level))), int(d.level) + 1], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	xl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(xl)
	var lr := "Next level: +100 coins and a %s pack" % ("Pro" if (int(d.level) + 1) % 5 == 0 else "Rookie")
	var du := _next_defender_unlock()
	if du != "":
		lr += "\n" + du
	var lrl := UITheme.label(lr, UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	lrl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lrl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(lrl)

	# Stats dashboard.
	var sp := UITheme.card_panel(UITheme.BORDER, 18)
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 10)
	sp.add_child(sv)
	sv.add_child(UITheme.section_header("CAREER STATS", "outs", UITheme.GOLD, UITheme.FS_H3))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sv.add_child(grid)
	var wins := int(Profile.stat("wins_standard")) + int(Profile.stat("wins_quick")) + int(Profile.stat("wins_ranked")) \
		+ int(Profile.stat("wins_daily")) + int(Profile.stat("wins_daily_long"))
	var rows := [
		["inning", int(Profile.stat("runs_played")), "Games played", UITheme.OFFWHITE],
		["trophy", wins, "Wins", UITheme.GOLD],
		["outs", int(Profile.stat("total_outs")), "Total outs", UITheme.OFFWHITE],
		["lightning", int(Profile.stat("double_plays")), "Double plays", UITheme.OFFWHITE],
		["deck", int(Profile.stat("cards_played")), "Cards played", UITheme.OFFWHITE],
		["wave", int(d.records.get("best_endless_inning", 0)), "Endless best inning", UITheme.PURPLE.lightened(0.3)],
		["calendar", int(d.daily.get("best_streak", 0)), "Best daily streak", Color("#FF8A3D").lightened(0.2)],
		["star", CardMastery.mastered_count(), "Cards mastered", UITheme.GOLD],
		["collection", d.sets_claimed.size(), "Card sets completed", UITheme.OFFWHITE],
	]
	for row in rows:
		var t := UITheme.stat_tile(row[0], UITheme.format_int(row[1]), row[2], row[3], 0)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(t)

	# Rank ladder strip.
	var lp := UITheme.card_panel(UITheme.BORDER, 16)
	vb.add_child(lp)
	var lpv := VBoxContainer.new()
	lpv.add_theme_constant_override("separation", 10)
	lp.add_child(lpv)
	lpv.add_child(UITheme.section_header("RANK LADDER", "crown", UITheme.GOLD, UITheme.FS_H3))
	var ladder := HBoxContainer.new()
	ladder.add_theme_constant_override("separation", 8)
	lpv.add_child(ladder)
	for i in DB.divisions.size():
		var dv: Dictionary = DB.divisions[i]
		var cur := i == int(d.division)
		var reached := i <= int(d.division)
		var p := UITheme.tile_panel(Color(Color(dv.color), 0.9 if cur else (0.35 if reached else 0.12)), 8, cur)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pv := VBoxContainer.new()
		pv.alignment = BoxContainer.ALIGNMENT_CENTER
		pv.add_theme_constant_override("separation", 0)
		p.add_child(pv)
		var path := "res://assets/textures/ui/rank_%s.png" % dv.id
		if ResourceLoader.exists(path):
			var em := TextureRect.new()
			em.texture = load(path)
			em.custom_minimum_size = Vector2(76, 76)
			em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			if not reached:
				em.modulate = Color(0.4, 0.4, 0.45)
			pv.add_child(em)
		var nlab := UITheme.label(str(dv.name).to_upper(), 24, Color(dv.color) if reached else UITheme.MUTED, UITheme.font_display())
		nlab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(nlab)
		var rl := UITheme.label("YOU ARE HERE" if cur else "%s RP" % UITheme.format_int(int(dv.rp_required)), UITheme.FS_MIN, UITheme.GOLD if cur else UITheme.MUTED, UITheme.font_body_bold())
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pv.add_child(rl)
		var unl := _rank_unlock_text(i)
		p.tooltip_text = "%s: %s RP%s" % [dv.name, UITheme.format_int(int(dv.rp_required)), ("\nUnlocks " + unl) if unl != "" else ""]
		ladder.add_child(p)

	# Closest achievements: what to aim for next.
	var open: Array = []
	for id in DB.achievement_order:
		if not Profile.data.achievements.has(id):
			open.append(id)
	open.sort_custom(func(a: String, b: String) -> bool: return Profile.achievement_progress(a) > Profile.achievement_progress(b))
	if not open.is_empty():
		var ap := UITheme.card_panel(UITheme.BORDER, 16)
		vb.add_child(ap)
		var av := VBoxContainer.new()
		av.add_theme_constant_override("separation", 10)
		ap.add_child(av)
		av.add_child(UITheme.section_header("ALMOST THERE", "target", UITheme.GOLD, UITheme.FS_H3))
		var ag := GridContainer.new()
		ag.columns = 3
		ag.add_theme_constant_override("h_separation", 10)
		ag.add_theme_constant_override("v_separation", 10)
		av.add_child(ag)
		for id in open.slice(0, 3):
			ag.add_child(_achievement_tile(id))
	return r[0]


## Stadiums unlocked by reaching division `index` (e.g. "the Frostpark stadium").
func _rank_unlock_text(index: int) -> String:
	if index < 0 or index >= DB.divisions.size():
		return ""
	var did: String = DB.divisions[index].id
	var names: Array = []
	for id in DB.arena_order:
		var u: Dictionary = DB.arena(id).get("unlock", {})
		if u.get("type", "") == "rank" and str(u.value) == did:
			names.append("the %s stadium" % DB.arena(id).name)
	return " and ".join(names)


func _next_defender_unlock() -> String:
	for id in DB.defender_order:
		if not Profile.is_defender_unlocked(id):
			var u: Dictionary = DB.defender(id).get("unlock", {})
			if u.get("type", "") == "level":
				return "Level %d unlocks %s" % [int(u.value), DB.defender(id).name]
	return ""


# ---------------------------------------------------------------- achievements

func _achievements_tab() -> Control:
	var r := _scroll("Achievements")
	var vb: VBoxContainer = r[1]
	var done := 0
	for id in DB.achievement_order:
		if Profile.data.achievements.has(id):
			done += 1
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	head.add_child(UITheme.icon_rect("trophy", 44, UITheme.GOLD))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 4)
	head.add_child(hv)
	hv.add_child(UITheme.label("%d / %d UNLOCKED" % [done, DB.achievement_order.size()], 30, UITheme.OFFWHITE, UITheme.font_header()))
	hv.add_child(UITheme.bar(UITheme.GOLD, 10, DB.achievement_order.size(), done))
	var note := UITheme.label("Achievements award stars, spent on team uniforms.", UITheme.FS_SMALL, UITheme.MUTED)
	note.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(note)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	for id in DB.achievement_order:
		grid.add_child(_achievement_tile(id))
	return r[0]


func _achievement_tile(id: String) -> Control:
	var a: Dictionary = DB.achievements[id]
	var got: bool = Profile.data.achievements.has(id)
	var prog := Profile.achievement_progress(id)
	var p := UITheme.tile_panel(Color(UITheme.GOLD, 0.65) if got else Color(1, 1, 1, 0.08), 12, got)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var ic := UITheme.icon_rect("trophy" if got else ("lock" if prog <= 0.0 else "target"), 44, UITheme.GOLD if got else Color(1, 1, 1, 0.3 + 0.4 * prog))
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hb.add_child(info)
	var top := HBoxContainer.new()
	var nm := UITheme.label(str(a.name), UITheme.FS_LEAD, UITheme.GOLD if got else UITheme.OFFWHITE, UITheme.font_header())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	top.add_child(nm)
	var star := HBoxContainer.new()
	star.add_child(UITheme.icon_rect("star", 20, UITheme.STAR))
	star.add_child(UITheme.label(str(int(a.stars)), UITheme.FS_BODY, UITheme.STAR, UITheme.font_header()))
	top.add_child(star)
	info.add_child(top)
	var t := UITheme.label(str(a.text), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_small())
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(t)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var pb := UITheme.bar(UITheme.GOLD if got else UITheme.BLUE, 8, 1.0, prog)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pb)
	var goal := float(a.goal)
	var cur := minf(Profile.stat(str(a.stat)), goal)
	row.add_child(UITheme.label("DONE" if got else "%s / %s" % [UITheme.format_int(int(cur)), UITheme.format_int(int(goal))], UITheme.FS_MIN, UITheme.GOLD if got else UITheme.MUTED, UITheme.font_body_bold()))
	info.add_child(row)
	return p


# ---------------------------------------------------------------- stadiums

func _stadiums_tab() -> Control:
	var r := _scroll("Stadiums")
	var vb: VBoxContainer = r[1]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	for id in DB.arena_order:
		var a := DB.arena(id)
		var unlocked: bool = id in Profile.data.arenas_unlocked
		var accent := Color(a.theme.get("accent", "#ffffff"))
		var p := UITheme.tile_panel(Color(accent, 0.6 if unlocked else 0.12), 0)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		p.add_child(v)
		var pic := Control.new()
		pic.custom_minimum_size = Vector2(0, 220)
		pic.clip_contents = true
		v.add_child(pic)
		var tex := UITheme.arena_thumbnail(id)
		var img := TextureRect.new()
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if tex:
			img.texture = tex
		else:
			var g := Gradient.new()
			g.set_color(0, Color(a.theme.sky_top))
			g.set_color(1, Color(a.theme.sky_horizon))
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.fill_to = Vector2(0, 1)
			img.texture = gt
		if not unlocked:
			img.modulate = Color(0.35, 0.35, 0.4)
		pic.add_child(img)
		var status := UITheme.badge("UNLOCKED" if unlocked else "LOCKED", Color(0.13, 0.55, 0.3) if unlocked else Color(0.45, 0.12, 0.14))
		status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		status.offset_right = -10
		status.offset_top = 10
		pic.add_child(status)
		var m := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 12)
		v.add_child(m)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		m.add_child(info)
		info.add_child(UITheme.label(str(a.name).to_upper(), 30, UITheme.OFFWHITE if unlocked else UITheme.MUTED, UITheme.font_display()))
		info.add_child(UITheme.label("%s: %s" % [a.modifier.name, a.modifier.text], UITheme.FS_SMALL, accent.lightened(0.3), UITheme.font_body_bold()))
		var t := UITheme.label(str(a.text), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_small())
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(t)
		if not unlocked:
			var lk := HBoxContainer.new()
			lk.add_theme_constant_override("separation", 6)
			lk.add_child(UITheme.icon_rect("lock", 20, Color(1.0, 0.7, 0.6)))
			lk.add_child(UITheme.label("Unlock: " + Profile.arena_unlock_text(id), UITheme.FS_SMALL, Color(1.0, 0.7, 0.6), UITheme.font_body_bold()))
			info.add_child(lk)
		grid.add_child(p)
	return r[0]


# ---------------------------------------------------------------- pro shop

func _shop_tab() -> Control:
	var r := _scroll("Pro Shop")
	var vb: VBoxContainer = r[1]
	vb.add_child(UITheme.label("Permanent gear bought with coins. Each item is equipped on one defender in the Team screen.", UITheme.FS_BODY, UITheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vb.add_child(grid)
	var icons := {"damage": "damage", "attack_speed": "attack_speed", "range": "range", "accuracy": "accuracy", "throw_speed": "throw_speed",
		"crit": "target", "special_power": "special", "special_cooldown": "cooldown"}
	for gid in DB.gear_order:
		var g: Dictionary = DB.gear[gid]
		var owned: bool = gid in Profile.data.gear_owned
		var afford := int(Profile.data.coins) >= int(g.price)
		var p := UITheme.tile_panel(Color(UITheme.GOLD, 0.55) if owned else Color(1, 1, 1, 0.1), 14, owned)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		p.add_child(hb)
		var ic_name := "upgrade"
		for k in g.get("effect", {}).keys():
			if icons.has(k):
				ic_name = icons[k]
				break
		var icp := PanelContainer.new()
		icp.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.GOLD, 0.14), Color(UITheme.GOLD, 0.5), 1, 10, 8))
		icp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icp.add_child(UITheme.icon_rect(ic_name, 40, UITheme.GOLD))
		hb.add_child(icp)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(UITheme.label(str(g.name), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header()))
		var gt := UITheme.label(str(g.text), UITheme.FS_SMALL, Color(0.85, 0.89, 0.96), UITheme.font_body_bold())
		gt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(gt)
		var holder := ""
		for k in Profile.data.gear_equipped.keys():
			if Profile.data.gear_equipped[k] == gid:
				holder = DB.defender(k).name
		if owned:
			info.add_child(UITheme.label("Equipped on " + holder if holder != "" else "Owned, not equipped", UITheme.FS_MIN, UITheme.GREEN, UITheme.font_body_bold()))
		elif not afford:
			info.add_child(UITheme.label("Need %s more coins" % UITheme.format_int(int(g.price) - int(Profile.data.coins)), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		hb.add_child(info)
		var b := UITheme.button("OWNED" if owned else UITheme.format_int(int(g.price)), "primary" if (afford and not owned) else "secondary", 24, "" if owned else "coin", UITheme.GOLD.darkened(0.3))
		b.disabled = owned or not afford
		b.custom_minimum_size = Vector2(130, 50)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			if Profile.buy_gear(gid):
				Audio.play("purchase")
				Router.toast("%s purchased! Equip it in the Team screen." % g.name, "info")
				_rebuild_tab(3))
		hb.add_child(b)
		grid.add_child(p)
	return r[0]


# ---------------------------------------------------------------- history

func _history_tab() -> Control:
	var r := _scroll("History")
	var vb: VBoxContainer = r[1]
	var hist: Array = Profile.data.history
	if hist.is_empty():
		var cc := CenterContainer.new()
		cc.custom_minimum_size = Vector2(0, 420)
		vb.add_child(cc)
		var ev := VBoxContainer.new()
		ev.alignment = BoxContainer.ALIGNMENT_CENTER
		ev.add_theme_constant_override("separation", 10)
		cc.add_child(ev)
		var ic := UITheme.icon_rect("inning", 72, UITheme.MUTED)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ev.add_child(ic)
		var l := UITheme.label("No games played yet.", UITheme.FS_H3, UITheme.OFFWHITE, UITheme.font_header())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ev.add_child(l)
		var l2 := UITheme.label("Your last games and their scores will show up here.", UITheme.FS_BODY, UITheme.MUTED)
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ev.add_child(l2)
		var play := UITheme.button("PLAY", "primary", 30, "play")
		play.custom_minimum_size = Vector2(220, 60)
		play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		play.pressed.connect(func() -> void: Router.goto("play_menu"))
		ev.add_child(play)
		return r[0]
	var wins := 0
	for h in hist:
		if h.won:
			wins += 1
	vb.add_child(UITheme.label("Last %d games: %d wins, %d losses" % [hist.size(), wins, hist.size() - wins], UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold()))
	for h in hist:
		var p := UITheme.tile_panel(Color(UITheme.GREEN, 0.45) if h.won else Color(UITheme.SCARLET, 0.35), 10)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 18)
		p.add_child(hb)
		var pill := UITheme.badge("WIN" if h.won else "LOSS", Color(0.13, 0.55, 0.3) if h.won else Color(0.6, 0.15, 0.17), UITheme.FS_SMALL)
		pill.custom_minimum_size = Vector2(64, 0)
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(pill)
		var tex := UITheme.arena_thumbnail(str(h.get("arena", "steel_yard")))
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.custom_minimum_size = Vector2(80, 45)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			hb.add_child(tr)
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", -2)
		mv.custom_minimum_size = Vector2(420, 0)
		mv.add_child(UITheme.label(str(DB.mode(h.mode).name), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header()))
		mv.add_child(UITheme.label("%s · %s" % [DB.difficulty(h.difficulty).name, DB.arena(h.get("arena", "steel_yard")).name], UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		hb.add_child(mv)
		var s := UITheme.label("Inning %d  ·  %d outs  ·  %d runs" % [int(h.inning), int(h.outs), int(h.runs)], UITheme.FS_BODY, Color(0.85, 0.89, 0.96), UITheme.font_body_bold())
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(s)
		hb.add_child(UITheme.label("%s pts" % UITheme.format_int(int(h.score)), UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_header()))
		var dl := UITheme.label(str(h.get("date", "")).replace("T", "  "), UITheme.FS_MIN, UITheme.MUTED)
		dl.custom_minimum_size = Vector2(170, 0)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hb.add_child(dl)
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
	_tabs.set_tab_icon(index, DB.icon("upgrade"))
	_tabs.set_tab_icon_max_width(index, 26)
