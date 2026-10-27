extends Control
## End-of-run results: outcome, match summary with a game-flow graph, three highlights
## (biggest combo, best card play, MVP), and the rewards built up in sequence: coins count
## up, the XP bar fills, rank points tick, packs fly in, then each defender's XP tile fills.

var battle: Battle
var result: Dictionary = {}

## Reward build-up timeline (seconds after the screen opens).
const T_BODY := 1.2
const T_COINS := 1.7
const T_XP := 2.3
const T_RP := 3.0
const T_PACKS := 3.4
const T_TEAM := 4.0

var _rv: VBoxContainer
const DAILY_ACCENT := Color("#FF8A3D")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.66, 1.0).set_delay(1.0)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	margin.add_child(vb)
	var won: bool = result.get("won", false)
	var practice: bool = result.get("practice", false)
	var title := UITheme.title("VICTORY!" if won else ("PRACTICE OVER" if practice else "DEFEAT"), 104,
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
		var b := UITheme.button("MAIN MENU", "primary", 34, "back")
		b.custom_minimum_size = Vector2(320, UITheme.BTN_H_LARGE)
		b.pressed.connect(func() -> void: Router.goto("main_menu"))
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)
		return

	var mode := DB.mode(result.get("mode", "standard"))
	var daily: Dictionary = result.get("daily", {})
	var mode_name: String = mode.name
	if not daily.is_empty():
		mode_name = "DAILY CHALLENGE  ·  %s" % DailyChallenge.pretty_date(str(daily.get("date", "")))
	var sub := UITheme.header("%s  ·  %s  ·  %s" % [mode_name, DB.difficulty(result.get("difficulty", "standard")).name, DB.arena(result.get("arena", "steel_yard")).name], 30,
		DAILY_ACCENT.lightened(0.2) if not daily.is_empty() else UITheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var left := _build_summary()
	body.add_child(left)
	var mid := _scrollify(_build_rewards())
	body.add_child(mid)
	var right := _scrollify(_build_highlights())
	body.add_child(right)
	var k := 0
	for c in [left, mid, right]:
		UITheme.animate_in(c, T_BODY + k * 0.12)
		k += 1
	vb.add_child(_build_buttons())


# ---------------------------------------------------------------- summary + graph

func _build_summary() -> Control:
	var p := _panel("MATCH SUMMARY", "outs")
	p.custom_minimum_size = Vector2(470, 0)
	var sv: VBoxContainer = p.get_child(0)
	var st: Dictionary = result.get("stats", {})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	sv.add_child(grid)
	var runs_col := UITheme.GREEN if int(result.get("runs", 0)) == 0 else Color(1.0, 0.55, 0.5)
	var tiles := [
		["inning", str(result.get("innings_cleared", 0)), "Innings cleared", UITheme.OFFWHITE],
		["outs", UITheme.format_int(int(result.get("outs", 0))), "Outs", UITheme.OFFWHITE],
		["runs", "%d / %d" % [int(result.get("runs", 0)), int(result.get("run_limit", 3))], "Runs allowed", runs_col],
		["deck", str(int(st.get("cards_played", 0))), "Cards played", UITheme.OFFWHITE],
		["lightning", "%d / %d" % [int(st.get("double_plays", 0)), int(st.get("triple_plays", 0))], "Double / triple plays", UITheme.OFFWHITE],
		["star", UITheme.format_int(int(result.get("score", 0))), "Score", UITheme.GOLD],
	]
	for t in tiles:
		var tile := UITheme.stat_tile(t[0], t[1], t[2], t[3], 0)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(tile)
	sv.add_child(UITheme.section_header("GAME FLOW", "wave", UITheme.GOLD, UITheme.FS_H3))
	var tl: Array = st.get("timeline", [])
	var graph := RunGraph.new(tl)
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.progress = 0.0
	graph.tooltip_text = _graph_tooltip(tl)
	sv.add_child(graph)
	create_tween().tween_property(graph, "progress", 1.0, 1.4).set_delay(T_BODY + 0.4).set_trans(Tween.TRANS_SINE)
	return p


func _graph_tooltip(tl: Array) -> String:
	var lines: Array = []
	for e in tl:
		lines.append("Inning %d: %d runs · %d outs · %d cards · energy %.1f avg" % [int(e.get("inning", 0)), int(e.get("runs", 0)),
			int(e.get("outs", 0)), int(e.get("cards", 0)), float(e.get("energy_avg", 0.0))])
	return "\n".join(lines)


# ---------------------------------------------------------------- rewards

func _build_rewards() -> Control:
	var p := _panel("REWARDS", "gift")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rv = p.get_child(0)
	var rv := _rv
	# Coins, XP and RP counters fill one after another.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	rv.add_child(top)
	top.add_child(_counter("coin", int(result.get("coins", 0)), "+%s", "COINS", UITheme.GOLD, T_COINS))
	top.add_child(_counter("upgrade", int(result.get("xp", 0)), "+%s", "ACCOUNT XP", UITheme.GREEN, T_XP))
	top.add_child(_counter("trophy", int(result.get("rp", 0)), "+%s", "RANK POINTS", UITheme.BLUE, T_RP))
	# Account XP bar: fills from where the player was, looping on level-ups.
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 12)
	rv.add_child(lvl_row)
	var level := int(Profile.data.level)
	var levels := int(result.get("levels", 0))
	var lvl_l := UITheme.label("LEVEL %d" % (level - levels), UITheme.FS_LEAD, UITheme.GREEN, UITheme.font_header())
	lvl_l.custom_minimum_size = Vector2(110, 0)
	lvl_row.add_child(lvl_l)
	var xpbar := UITheme.bar(UITheme.GREEN, 16, 1.0, 0.0)
	xpbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xpbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvl_row.add_child(xpbar)
	var xp_now := int(Profile.data.xp)
	var xp_l := UITheme.label("%d / %d XP" % [xp_now, Profile.xp_to_next(level)], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	lvl_row.add_child(xp_l)
	var start := 0.0
	if levels == 0:
		start = clampf(float(xp_now - int(result.get("xp", 0))) / maxi(1, Profile.xp_to_next(level)), 0.0, 1.0)
	xpbar.value = start
	var banner := UITheme.label("", 26, UITheme.GREEN, UITheme.font_display())
	banner.visible = false
	var xt := create_tween()
	xt.tween_interval(T_XP)
	for i in levels:
		var lv := level - levels + i + 1
		xt.tween_property(xpbar, "value", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		xt.tween_callback(func() -> void:
			Audio.play("level_up", -4.0)
			lvl_l.text = "LEVEL %d" % lv
			banner.text = "ACCOUNT LEVEL UP!  Now level %d" % lv
			banner.visible = true
			xpbar.value = 0.0)
	xt.tween_property(xpbar, "value", clampf(float(xp_now) / maxi(1, Profile.xp_to_next(level)), 0.0, 1.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	rv.add_child(banner)
	if result.get("promoted", false):
		rv.add_child(_late(UITheme.label("PROMOTED TO %s!" % Profile.division().name.to_upper(), 32, UITheme.GOLD, UITheme.font_display()), T_RP + 0.4))
	elif Profile.promotion_available():
		rv.add_child(_late(UITheme.label("★ Promotion Challenge available: %s!" % Profile.next_division().name, UITheme.FS_BODY, UITheme.GOLD, UITheme.font_body_bold()), T_RP + 0.4))

	# Packs fly in.
	var packs: Array = result.get("packs", [])
	rv.add_child(UITheme.section_header("PACKS EARNED" if not packs.is_empty() else "NO PACKS THIS TIME", "gift", UITheme.GOLD, UITheme.FS_H3))
	var pack_row := HBoxContainer.new()
	pack_row.add_theme_constant_override("separation", 12)
	rv.add_child(pack_row)
	var i := 0
	var shown := mini(packs.size(), 7)
	for pk in packs.slice(0, shown):
		var art := PackArt.new(str(pk.type), str(pk.get("card", "")))
		art.custom_minimum_size = Vector2(84, 130)
		art.pivot_offset = Vector2(42, 65)
		art.modulate.a = 0.0
		art.scale = Vector2.ONE * 1.6
		art.rotation = deg_to_rad(-14.0 + 4.0 * i)
		art.tooltip_text = "%s — %s" % [DB.pack(str(pk.type)).name, pk.get("source", "")]
		pack_row.add_child(art)
		var t := create_tween()
		t.tween_interval(T_PACKS + i * 0.18)
		t.tween_callback(func() -> void: Audio.play("card_draw", -2.0))
		t.set_parallel(true)
		t.tween_property(art, "modulate:a", 1.0, 0.2)
		t.tween_property(art, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(art, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	if packs.size() > shown:
		pack_row.add_child(_late(UITheme.label("+%d" % (packs.size() - shown), 34, UITheme.GOLD, UITheme.font_display()), T_PACKS + shown * 0.18))
	if not packs.is_empty():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pack_row.add_child(spacer)
		var open := UITheme.button("OPEN PACKS", "primary", 28, "gift", UITheme.GOLD.darkened(0.3))
		open.custom_minimum_size = Vector2(230, 58)
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void: Router.goto("packs"))
		pack_row.add_child(_late(open, T_PACKS + shown * 0.18 + 0.2))

	rv.add_child(UITheme.section_header("TEAM PROGRESS", "roster", UITheme.GOLD, UITheme.FS_H3))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	rv.add_child(grid)
	var ti := 0
	for id in result.get("defender_xp", {}).keys():
		var tile := _progress_tile(id, result.defender_xp[id], T_TEAM + 0.3 + ti * 0.2)
		grid.add_child(tile)
		UITheme.animate_in(tile, T_TEAM + ti * 0.08)
		ti += 1
	return p


## Big counter that counts up from 0 to `value` at `delay`, with coin ticks.
func _counter(icon: String, value: int, fmt: String, caption: String, col: Color, delay: float) -> Control:
	var p := UITheme.tile_panel(Color(col, 0.35), 10)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var ic := UITheme.icon_rect(icon, 40, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -6)
	hb.add_child(vb)
	var l := UITheme.label(fmt % "0", 42, col, UITheme.font_display())
	vb.add_child(l)
	vb.add_child(UITheme.label(caption, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	p.modulate.a = 0.35
	var tw := create_tween()
	tw.tween_interval(delay)
	tw.tween_property(p, "modulate:a", 1.0, 0.15)
	var last := [-1]
	tw.tween_method(func(v: float) -> void:
		var n := int(round(v))
		l.text = fmt % UITheme.format_int(n)
		var step := int(v * 8.0 / maxf(value, 1))
		if step != last[0]:
			last[0] = step
			Audio.play("coin", -16.0, 0.08, 40), 0.0, float(value), 0.6 if value > 0 else 0.01).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		p.pivot_offset = p.size * 0.5
		p.scale = Vector2(1.06, 1.06)
		var t2 := p.create_tween()
		t2.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	return p


## Fades a control in at `delay`.
func _late(c: Control, delay: float) -> Control:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, UITheme.T_MED)
	return c


# ---------------------------------------------------------------- highlights

func _build_highlights() -> Control:
	var p := _panel("HIGHLIGHTS", "star")
	p.custom_minimum_size = Vector2(430, 0)
	var hv: VBoxContainer = p.get_child(0)
	var st: Dictionary = result.get("stats", {})
	var hl: Dictionary = st.get("highlights", {})
	var cards: Array = []
	var daily: Dictionary = result.get("daily", {})
	if not daily.is_empty():
		var dt := _daily_tile(daily)
		hv.add_child(dt)
		UITheme.animate_in(dt, T_BODY + 0.3)
	# 1. Biggest combo.
	var combo: Dictionary = hl.get("best_combo", {})
	var mc := int(combo.get("n", st.get("max_combo", 0)))
	if mc >= 2:
		var cname: String = {2: "DOUBLE PLAY", 3: "TRIPLE PLAY"}.get(mc, "GRAND SLAM COMBO ×%d" % mc)
		var where := " in inning %d" % int(combo.inning) if combo.has("inning") else ""
		cards.append(_highlight_card(UITheme.icon_rect("lightning", 48, UITheme.GOLD), "BIGGEST COMBO", cname,
			"%d outs in a row%s." % [mc, where], UITheme.GOLD))
	else:
		cards.append(_highlight_card(UITheme.icon_rect("lightning", 48, UITheme.MUTED), "BIGGEST COMBO", "NO COMBOS",
			"Get two outs in quick succession for a Double Play.", UITheme.MUTED))
	# 2. Best card play.
	var play: Dictionary = hl.get("best_play", {})
	if not play.is_empty() and DB.card(str(play.card)).has("name"):
		var c := DB.card(str(play.card))
		var art := TextureRect.new()
		art.texture = DB.card_texture(str(play.card))
		art.custom_minimum_size = Vector2(52, 52)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var col := DB.category_color(str(c.category))
		cards.append(_highlight_card(art, "BEST CARD PLAY", str(c.name).to_upper(),
			"%d out%s within %d seconds (inning %d)." % [int(play.outs), "" if int(play.outs) == 1 else "s", int(RunHighlights.PLAY_WINDOW), int(play.inning)], col.lightened(0.3)))
	else:
		var played := int(st.get("cards_played", 0))
		cards.append(_highlight_card(UITheme.icon_rect("deck", 48, UITheme.MUTED), "BEST CARD PLAY", "NO BIG PLAY" if played > 0 else "NO CARDS PLAYED",
			"Cards that lead to outs show up here." if played > 0 else "Play cards from your hand to swing the game.", UITheme.MUTED))
	# 3. MVP.
	var mvp: String = result.get("mvp", "")
	if mvp != "":
		var d := DB.defender(mvp)
		var outs := int(st.get("outs_by", {}).get(mvp, 0))
		var dmg := int(st.get("damage_by", {}).get(mvp, 0))
		var accent := Color(d.accent)
		cards.append(_highlight_card(MenuScreen.portrait_rect(mvp, 52, accent), "MVP", str(d.name).to_upper(),
			"%d outs · %s damage." % [outs, UITheme.format_int(dmg)], accent.lightened(0.3)))
	var j := 0
	for c in cards:
		hv.add_child(c)
		UITheme.animate_in(c, T_BODY + 0.5 + j * 0.25)
		j += 1
	# Records and achievements.
	var extra: Array = []
	for rec in result.get("records", []):
		extra.append(["trophy", str(rec)])
	for aid in result.get("achievements", []):
		extra.append(["star", "Achievement: %s" % DB.achievements[aid].name])
	if not extra.is_empty():
		hv.add_child(UITheme.section_header("RECORDS", "trophy", UITheme.GOLD, UITheme.FS_H3))
		for e in extra:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(UITheme.icon_rect(e[0], 22, UITheme.GOLD))
			var l := UITheme.label(e[1], UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold())
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			hv.add_child(_late(row, T_TEAM))
	var mastery: Array = result.get("mastery", [])
	if not mastery.is_empty():
		var ms := _mastery_strip(mastery, T_TEAM)
		hv.add_child(_late(ms, T_TEAM - 0.2))
	return p


## Daily Challenge result: score against today's best, the streak and the daily bonus.
func _daily_tile(d: Dictionary) -> Control:
	var p := UITheme.tile_panel(DAILY_ACCENT, 14, true)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	head.add_child(UITheme.icon_rect("calendar", 26, DAILY_ACCENT.lightened(0.25)))
	var h := UITheme.label("DAILY CHALLENGE", 30, DAILY_ACCENT.lightened(0.25), UITheme.font_display())
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	if bool(d.get("new_best", false)):
		var nb := UITheme.badge("NEW BEST!", UITheme.GOLD.darkened(0.25), UITheme.FS_SMALL)
		nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(_late(nb, T_BODY + 1.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 30)
	vb.add_child(row)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", -6)
	sc.add_child(UITheme.label(UITheme.format_int(int(d.get("score", 0))), 44, UITheme.GOLD, UITheme.font_display()))
	sc.add_child(UITheme.label("SCORE", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	row.add_child(sc)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", -6)
	bv.add_child(UITheme.label(UITheme.format_int(int(d.get("best", 0))), 44, UITheme.OFFWHITE, UITheme.font_display()))
	bv.add_child(UITheme.label("BEST TODAY", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	row.add_child(bv)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -6)
	var streak := int(d.get("streak", 0))
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	var fi := UITheme.icon_rect("fire", 30, DAILY_ACCENT.lightened(0.2))
	fi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(fi)
	sh.add_child(UITheme.label("%d" % streak, 44, DAILY_ACCENT.lightened(0.2), UITheme.font_display()))
	sv.add_child(sh)
	sv.add_child(UITheme.label("DAY STREAK", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	sv.tooltip_text = "Best streak: %d days" % int(d.get("best_streak", 0))
	row.add_child(sv)
	var parts: Array = []
	if bool(d.get("first_today", false)):
		parts.append("+%d coins" % int(d.get("bonus_coins", 0)))
	for pk in d.get("bonus_packs", []):
		parts.append(str(DB.pack(str(pk)).get("name", str(pk))))
	var txt := "Daily bonus: " + " · ".join(parts) if not parts.is_empty() \
		else "Attempt %d today. Next challenge in %s." % [int(d.get("attempts", 1)), DailyChallenge.countdown_text()]
	var l := UITheme.label(txt, UITheme.FS_SMALL, UITheme.GOLD if not parts.is_empty() else UITheme.OFFWHITE, UITheme.font_body_bold())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	return p


## Card mastery gains in one compact row: each card played shows its art, stars and plays
## added; a star earned fills with a sound and a "MASTERY ★2!" caption.
func _mastery_strip(mastery: Array, delay: float) -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.add_child(UITheme.section_header("CARD MASTERY", "star", UITheme.GOLD, UITheme.FS_H3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var caption := UITheme.label("", UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold())
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var shown := mastery.slice(0, 5)
	var k := 0
	for m in shown:
		var cid := str(m.get("id", ""))
		var sb := int(m.get("stars_before", 0))
		var sa := int(m.get("stars_after", 0))
		var earned := sa > sb
		var chip := UITheme.tile_panel(Color(UITheme.GOLD, 0.55 if earned else 0.15), 6, earned)
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.tooltip_text = "%s: %s" % [DB.card(cid).get("name", cid), CardMastery.status_text(int(m.get("after", 0)))]
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 3)
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		chip.add_child(cv)
		var art := TextureRect.new()
		art.texture = DB.card_texture(cid)
		art.custom_minimum_size = Vector2(46, 40)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		cv.add_child(art)
		var stars := MasteryUI.Stars.new(sb, 14.0)
		stars.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(stars)
		var plus := UITheme.label("+%d" % int(m.get("plays", 0)), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(plus)
		row.add_child(chip)
		UITheme.animate_in(chip, delay + k * 0.12)
		if earned:
			var nm := str(DB.card(cid).get("name", cid))
			var tw := create_tween()
			tw.tween_interval(delay + 0.6 + k * 0.45)
			tw.tween_callback(func() -> void:
				Audio.play("achievement", -4.0)
				stars.set_filled(sa)
				plus.text = "★%d!" % sa
				plus.add_theme_color_override("font_color", UITheme.GOLD)
				caption.text = "%s: MASTERY %s!%s" % [nm, "★".repeat(sa), "  Gold frame unlocked." if sa >= CardMastery.MAX_STARS else ""]
				chip.modulate = Color(1.6, 1.45, 1.1)
				chip.pivot_offset = chip.size * 0.5
				chip.scale = Vector2(1.12, 1.12))
			tw.tween_property(chip, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(chip, "modulate", Color.WHITE, 0.45)
		k += 1
	if mastery.size() > shown.size():
		var more := UITheme.label("+%d" % (mastery.size() - shown.size()), UITheme.FS_LEAD, UITheme.MUTED, UITheme.font_header())
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		more.tooltip_text = "More cards played this game"
		row.add_child(more)
	vb.add_child(caption)
	return vb


func _highlight_card(art: Control, kind: String, title: String, caption: String, col: Color) -> PanelContainer:
	var p := UITheme.tile_panel(Color(col, 0.4), 12)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	p.add_child(hb)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(Color(col, 0.14), Color(col, 0.55), 1, 10, 6))
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.add_child(art)
	hb.add_child(frame)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", -2)
	hb.add_child(vb)
	vb.add_child(UITheme.label(kind, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	var t := UITheme.label(title, 30, col, UITheme.font_display())
	t.clip_text = true
	vb.add_child(t)
	var c := UITheme.label(caption, UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body())
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(c)
	return p


# ---------------------------------------------------------------- buttons

func _build_buttons() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	var cfg0: Dictionary = battle.run.config if battle and battle.run else {}
	var is_daily: bool = cfg0.has("daily") or not (result.get("daily", {}) as Dictionary).is_empty()
	var again := UITheme.button("RETRY DAILY" if is_daily else "PLAY AGAIN", "primary", 32, "play", DAILY_ACCENT.darkened(0.15) if is_daily else Color(0, 0, 0, 0))
	again.custom_minimum_size = Vector2(300, 64)
	again.tooltip_text = "Same mode, difficulty, stadium and deck: %s · %s · %s" % [DB.mode(str(cfg0.get("mode", "standard"))).name,
		DB.difficulty(str(cfg0.get("difficulty", "standard"))).name, DB.arena(str(cfg0.get("arena", "steel_yard"))).name]
	if is_daily:
		again.tooltip_text = "Play today's Daily Challenge again and beat your best score"
	again.pressed.connect(_play_again)
	buttons.add_child(again)
	var deck := UITheme.button("CARDS & DECK", "secondary", 28, "deck")
	deck.custom_minimum_size = Vector2(260, 64)
	deck.pressed.connect(func() -> void: Router.goto("deck_builder"))
	buttons.add_child(deck)
	var menu := UITheme.button("MAIN MENU", "secondary", 28, "back")
	menu.custom_minimum_size = Vector2(240, 64)
	menu.pressed.connect(func() -> void: Router.goto("main_menu"))
	buttons.add_child(menu)
	var note := UITheme.label("Retry uses today's rules again; your best score counts." if is_daily
		else "Play Again uses the same mode, difficulty, stadium and deck.", UITheme.FS_MIN, UITheme.MUTED)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(note)
	UITheme.animate_in(col, T_BODY + 0.4)
	return col


## Starts the same game again: same mode, difficulty, stadium, deck, team, captain and
## formation (a new seed). Promotion Challenges go back to the Play screen, since the
## challenge depends on the current division.
func _play_again() -> void:
	if battle.run.config.has("daily"):
		Session.start(DailyChallenge.config_for())   # today's rules (a new day brings new ones)
		return
	var cfg: Dictionary = battle.run.config.duplicate(true)
	if str(cfg.get("mode", "")) == "ranked":
		Router.goto("play_menu")
		return
	cfg.seed = randi()
	cfg.resume = null
	cfg.erase("start_inning")
	cfg.erase("start_wave")
	cfg.erase("auto_test")
	var deck: Array = []
	for cid in cfg.get("deck", []):
		if Profile.is_card_owned(str(cid)):
			deck.append(cid)
	if deck.size() < Profile.data.deck.size():
		deck = Profile.data.deck.duplicate()
	cfg.deck = deck
	var team: Array = []
	for id in cfg.get("team", []):
		if Profile.is_defender_unlocked(str(id)):
			team.append(id)
	if team.size() < Profile.data.team.size():
		team = Profile.data.team.duplicate()
	cfg.team = team
	Profile.clear_run(true)
	Session.start(cfg)


# ---------------------------------------------------------------- helpers

## One defender's XP gain: the bar fills from before to after; each level gained flashes
## LEVEL UP! and shows the level road reward it unlocked.
func _progress_tile(id: String, d: Dictionary, delay: float) -> Control:
	var accent := Color(DB.defender(id).accent)
	var p := UITheme.tile_panel(Color(accent, 0.45), 8)
	p.custom_minimum_size = Vector2(230, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var nm := UITheme.label(DB.defender(id).name, UITheme.FS_BODY, accent.lightened(0.35), UITheme.font_header())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var lvl_l := UITheme.label("LV %d" % int(d.get("level_before", d.level)), UITheme.FS_BODY, UITheme.GOLD, UITheme.font_display())
	top.add_child(lvl_l)
	var bar := UITheme.bar(accent.lightened(0.15), 12, 1.0, 0.0)
	var lb := int(d.get("level_before", d.level))
	var need0 := maxi(1, Profile.defender_xp_needed(lb))
	bar.value = clampf(float(d.get("xp_before", 0)) / need0, 0.0, 1.0)
	vb.add_child(bar)
	var info := UITheme.label("+%d XP" % int(d.xp) + ("  ·  %d outs" % int(d.outs) if int(d.get("outs", 0)) > 0 else ""), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	info.clip_text = true
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


## Lets a panel's column scroll when it does not fit (large UI scale), keeping the buttons on screen.
func _scrollify(p: PanelContainer) -> PanelContainer:
	var vb := p.get_child(0)
	p.remove_child(vb)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	p.add_child(sc)
	return p


func _panel(title: String, icon := "") -> PanelContainer:
	var p := UITheme.card_panel(Color(1, 1, 1, 0.12), 16)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	vb.add_child(UITheme.section_header(title, icon, UITheme.GOLD, UITheme.FS_H2))
	return p
