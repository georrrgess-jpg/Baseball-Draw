extends MenuScreen
## Mode, difficulty and stadium selection, with a summary of the team and deck.
## Modes are cards with their key facts, stadiums are picture tiles rendered from each arena
## (assets/textures/arenas), and the difficulty explainer lists exactly what changes.

const DAILY_ACCENT := Color("#FF8A3D")
const MODES := [
	# id, accent, icon, short facts
	["daily", DAILY_ACCENT, "calendar", ""],
	["standard", UITheme.SCARLET, "trophy", "9 innings · 3 bosses · full rewards"],
	["quick", UITheme.BLUE, "speed", "3 innings · 1 boss · about 10 minutes"],
	["endless", UITheme.PURPLE, "wave", "Survive · new modifier every inning · records"],
	["ranked", UITheme.GOLD, "crown", ""],
	["practice", UITheme.GREEN, "practice", "Sandbox · spawn any runner · no rewards"],
]
## What each difficulty number means, compared with Standard. [key, label, icon, kind]
## kind: "mult_bad" (higher is harder), "mult_good" (higher is easier), "int_good", "int_bad", "pct_bad", "reward".
const DIFF_ROWS := [
	["enemy_hp", "Runner health", "health", "mult_bad"],
	["enemy_speed", "Runner speed", "speed", "mult_bad"],
	["budget", "Runners per wave", "enemy", "mult_bad"],
	["ability_cd", "Runner ability cooldowns", "cooldown", "mult_good"],
	["energy_regen", "Your energy regeneration", "energy", "mult_good"],
	["run_limit", "Runs allowed before you lose", "runs", "int_good"],
	["shields", "Starting base shields", "shield", "int_good"],
	["elite_chance", "Elite runners (special affixes)", "boss", "pct_bad"],
	["reward", "Coin and XP rewards", "coin", "reward"],
	["rp", "Rank points", "trophy", "reward"],
]

var mode_id := "standard"
var _mode_buttons := {}
var _diff_buttons := {}
var _arena_flow: HFlowContainer
var _mode_info: VBoxContainer
var _diff_info: GridContainer
var _diff_text: Label
var _start: Button
var _summary: VBoxContainer
var _daily: Dictionary = {}          # today's Daily Challenge rules
var _countdown_labels: Array[Label] = []
var _countdown_t := 0.0


func _ready() -> void:
	_daily = DailyChallenge.today_rules()
	setup_screen("PLAY", "Choose a mode, difficulty and stadium")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	content.add_child(body)

	# ---- Modes
	var modes := panel()
	modes.custom_minimum_size = Vector2(500, 0)
	body.add_child(modes)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	modes.add_child(mv)
	mv.add_child(UITheme.section_header("GAME MODE", "play"))
	for m in MODES:
		var card := _mode_card(m[0], m[1], m[2], m[3])
		mv.add_child(card)
	_mode_info = VBoxContainer.new()
	_mode_info.add_theme_constant_override("separation", 6)
	_mode_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var info_panel := UITheme.tile_panel(UITheme.BORDER, 14)
	info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_panel.add_child(_vscroll(_mode_info))
	mv.add_child(info_panel)

	# ---- Difficulty + stadium
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 16)
	body.add_child(mid)
	var dp := panel()
	mid.add_child(dp)
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 10)
	dp.add_child(dv)
	dv.add_child(UITheme.section_header("DIFFICULTY", "boss"))
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	dv.add_child(dh)
	var cols := [UITheme.GREEN, UITheme.BLUE, UITheme.GOLD, UITheme.SCARLET]
	for id in DB.difficulty_order:
		var d := DB.difficulty(id)
		var b := UITheme.button(str(d.name).to_upper(), "secondary", 24, "", cols[DB.difficulty_order.find(id) % cols.size()])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(120, 50)
		b.pressed.connect(func() -> void: _select_difficulty(id))
		dh.add_child(b)
		_diff_buttons[id] = b
	_diff_text = UITheme.label("", UITheme.FS_BODY, UITheme.OFFWHITE)
	_diff_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_diff_text)
	_diff_info = GridContainer.new()
	_diff_info.columns = 2
	_diff_info.add_theme_constant_override("h_separation", 26)
	_diff_info.add_theme_constant_override("v_separation", 2)
	dv.add_child(_diff_info)

	var ap := panel()
	ap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(ap)
	var av := VBoxContainer.new()
	av.add_theme_constant_override("separation", 10)
	ap.add_child(av)
	av.add_child(UITheme.section_header("STADIUM", "map"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	av.add_child(scroll)
	_arena_flow = HFlowContainer.new()
	_arena_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_arena_flow.add_theme_constant_override("h_separation", 12)
	_arena_flow.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_arena_flow)
	_fill_arenas()

	# ---- Summary + start
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	right.add_theme_constant_override("separation", 14)
	body.add_child(right)
	var sp := panel()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 8)
	sp.add_child(_vscroll(_summary))
	_fill_summary()
	_start = UITheme.button("START  ▶", "primary", 48, "")
	_start.custom_minimum_size = Vector2(400, 92)
	_start.pressed.connect(_on_start)
	right.add_child(_start)

	var cur_diff: String = Profile.data.difficulty
	_select_difficulty(cur_diff, true)
	var last := str(Profile.data.flags.get("last_mode", "standard"))
	if last == "practice" or last == "ranked" or not _mode_buttons.has(last):
		last = "standard"
	if "--play-mode=daily" in OS.get_cmdline_user_args():   # screenshot helper
		Session.menu_tab = "daily"
	if Session.menu_tab == "daily":   # opened from the main menu's Daily Challenge tile
		Session.menu_tab = ""
		last = "daily"
	elif Profile.has_saved_run():
		last = "quick"
	_select_mode(last, true)


func _process(delta: float) -> void:
	_countdown_t -= delta
	if _countdown_t > 0.0:
		return
	_countdown_t = 1.0
	var txt := DailyChallenge.countdown_text()
	for l in _countdown_labels:
		if is_instance_valid(l):
			l.text = str(l.get_meta("fmt", "%s")) % txt
	if DailyChallenge.today() != str(_daily.get("date", "")):   # midnight passed: a new challenge
		_daily = DailyChallenge.today_rules()
		if mode_id == "daily":
			_select_mode("daily", true)


## Wraps a column so it scrolls instead of pushing the layout off-screen at large UI scales.
func _vscroll(c: Control) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(c)
	return sc


# ---------------------------------------------------------------- modes

func _mode_card(id: String, accent: Color, icon: String, facts: String) -> Button:
	var m := DB.mode(id)
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 78)
	b.focus_mode = Control.FOCUS_NONE
	var mk := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		var s := UITheme.panel_style(bg, border, bw, 10, 0)
		s.border_width_left = 6
		return s
	b.add_theme_stylebox_override("normal", mk.call(UITheme.TILE_BG, Color(accent, 0.45), 1))
	b.add_theme_stylebox_override("hover", mk.call(Color(accent.darkened(0.72), 0.97), accent, 2))
	b.add_theme_stylebox_override("pressed", mk.call(Color(accent.darkened(0.55), 0.97), accent.lightened(0.2), 2))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.05, 0.06, 0.09, 0.85), Color(1, 1, 1, 0.08), 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16
	hb.offset_right = -12
	hb.add_theme_constant_override("separation", 14)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	# Mode art: the mode's emblem on a gradient chip in its colour.
	var art := Panel.new()
	art.custom_minimum_size = Vector2(60, 60)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_s := UITheme.panel_style(accent.darkened(0.35), accent.lightened(0.3), 2, 30, 0)
	art_s.shadow_color = Color(accent, 0.35)
	art_s.shadow_size = 8
	art.add_theme_stylebox_override("panel", art_s)
	var ic := UITheme.icon_rect(icon, 36, Color.WHITE)
	ic.position = Vector2(12, 12)
	art.add_child(ic)
	hb.add_child(art)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", -2)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	vb.add_child(UITheme.label(str(m.name).to_upper(), 30, UITheme.OFFWHITE, UITheme.font_display()))
	var sub := facts
	var locked := false
	if id == "daily":
		sub = "%s · %s · %s" % [DailyChallenge.pretty_date(str(_daily.date)), DB.difficulty(str(_daily.difficulty)).name,
			str(DailyChallenge.modifier_def(str(_daily.modifier)).get("name", str(_daily.format_name)))]
	if id == "ranked":
		var nd := Profile.next_division()
		if nd.is_empty():
			sub = "You are a Legend!"
			locked = true
		elif Profile.promotion_available():
			sub = "Promotion to %s available!" % nd.name
		else:
			sub = "Unlocks at %d RP (you have %d)" % [int(nd.rp_required), int(Profile.data.rp)]
			locked = true
	var sl := UITheme.label(sub, UITheme.FS_SMALL, UITheme.GOLD if (id == "ranked" and not locked) else UITheme.MUTED, UITheme.font_body_bold())
	sl.clip_text = true
	vb.add_child(sl)
	if locked:
		b.disabled = true
		b.tooltip_text = "Locked: earn rank points by winning games (higher difficulties earn more)."
		var lk := UITheme.icon_rect("lock", 26, UITheme.MUTED)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(lk)
	elif id == "daily":
		var played := DailyChallenge.played()
		var bd := UITheme.badge("BEST %s" % UITheme.format_int(DailyChallenge.best_score()) if played else "NEW TODAY",
			Color(DAILY_ACCENT.darkened(0.25), 0.95) if not played else Color(0.13, 0.4, 0.25, 0.95))
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(bd)
		b.tooltip_text = "One game per day with fixed rules and deck. Same for everyone today."
	elif id == "endless" and int(Profile.data.records.get("best_endless_inning", 0)) > 0:
		var bd := UITheme.badge("BEST: INN. %d" % int(Profile.data.records.best_endless_inning), Color(UITheme.PURPLE, 0.85))
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(bd)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.ui("ui_hover", -8.0))
	b.pressed.connect(func() -> void: _select_mode(id))
	UITheme.add_feedback(b, 1.015)
	_mode_buttons[id] = b
	return b


func _select_mode(id: String, quiet := false) -> void:
	mode_id = id
	for k in _mode_buttons.keys():
		_mode_buttons[k].button_pressed = k == id
	var m := DB.mode(id)
	for c in _mode_info.get_children():
		c.queue_free()
	var accent: Color = UITheme.SCARLET
	for mm in MODES:
		if mm[0] == id:
			accent = mm[1]
	_countdown_labels.clear()
	if id == "daily":
		_fill_daily_info(accent)
		_after_mode_change(id, quiet)
		return
	_mode_info.add_child(UITheme.header(str(m.name).to_upper(), UITheme.FS_H3, accent.lightened(0.25)))
	var t := UITheme.label(str(m.text), UITheme.FS_BODY, UITheme.OFFWHITE)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.add_child(t)
	var facts: Array = []
	if int(m.get("innings", 0)) > 0:
		facts.append(["inning", "%d innings, %d waves each" % [int(m.innings), int(m.get("waves_per_inning", 3))]])
	elif id == "endless":
		facts.append(["inning", "Endless innings, %d waves each" % int(m.get("waves_per_inning", 3))])
	if m.has("bosses"):
		var names: Array = []
		for k in m.bosses.keys():
			names.append(DB.enemy(str(m.bosses[k])).get("name", m.bosses[k]))
		facts.append(["boss", "Bosses: " + ", ".join(names)])
	elif m.has("boss_every"):
		facts.append(["boss", "A boss every %d innings" % int(m.boss_every)])
	if bool(m.get("rewards", false)):
		facts.append(["coin", "Rewards ×%.2f" % float(m.get("reward_mult", 1.0))])
	else:
		facts.append(["coin", "No rewards, no risk"])
	if id == "ranked":
		var nd := Profile.next_division()
		if not nd.is_empty():
			facts.append(["crown", "%s difficulty with 2 challenge modifiers. Win to reach %s." % [DB.difficulty(nd.challenge_difficulty).name, nd.name]])
	if id == "endless":
		facts.append(["trophy", "Best: inning %d · %s points" % [int(Profile.data.records.get("best_endless_inning", 0)), UITheme.format_int(int(Profile.data.records.get("best_endless_score", 0)))]])
	for f in facts:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(UITheme.icon_rect(f[0], 22, accent.lightened(0.3)))
		var fl := UITheme.label(f[1], UITheme.FS_SMALL, Color(0.85, 0.89, 0.96), UITheme.font_body_bold())
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(fl)
		_mode_info.add_child(row)
	if Profile.has_saved_run() and id != "practice":
		var w := UITheme.label("Starting a new game replaces your saved run in progress.", UITheme.FS_MIN, Color(1.0, 0.6, 0.5))
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mode_info.add_child(w)
	_after_mode_change(id, quiet)


func _after_mode_change(id: String, quiet: bool) -> void:
	for k in _diff_buttons.keys():
		var b: Button = _diff_buttons[k]
		var fixed: bool = id == "daily" and k == str(_daily.difficulty)   # shown selected, not clickable
		b.disabled = id in ["practice", "ranked", "daily"] and not fixed
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE if id == "daily" else Control.MOUSE_FILTER_STOP
		b.button_pressed = k == (str(_daily.difficulty) if id == "daily" else str(Profile.data.difficulty))
	_refresh_difficulty_info()
	_fill_arenas()
	if _summary:
		_fill_summary()
	if _start:
		_start.text = "PLAY DAILY  ▶" if id == "daily" else "START  ▶"
	if not quiet:
		Audio.ui("ui_tab")


## Today's Daily Challenge: its rules, your record, the bonus and when the next one starts.
func _fill_daily_info(accent: Color) -> void:
	var d := _daily
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	var h := UITheme.header("DAILY CHALLENGE", UITheme.FS_H3, accent.lightened(0.25))
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	head.add_child(UITheme.label(DailyChallenge.pretty_date(str(d.date)).to_upper(), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold()))
	_mode_info.add_child(head)
	var t := UITheme.label("One game a day with the same rules and deck for every manager. Beat your best score and keep your streak going.", UITheme.FS_SMALL, UITheme.OFFWHITE)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.add_child(t)
	var md := DailyChallenge.modifier_def(str(d.modifier))
	var bosses: Array = []
	var keys: Array = d.bosses.keys()
	keys.sort()
	for k in keys:
		bosses.append(str(DB.enemy(str(d.bosses[k])).get("name", d.bosses[k])))
	var a := DB.arena(str(d.arena))
	var facts := [
		["inning", "%s: %d innings, %s difficulty" % [d.format_name, int(d.innings), DB.difficulty(str(d.difficulty)).name]],
		["lightning", "Twist: %s. %s" % [md.get("name", "None"), md.get("text", "")]],
		["map", "Stadium: %s (%s)" % [a.name, a.modifier.name] + ("" if str(d.arena) in Profile.data.arenas_unlocked else ". Not unlocked yet: play it today!")],
		["boss", "Boss%s: %s" % ["es" if bosses.size() > 1 else "", ", ".join(bosses)]],
		["deck", "Fixed deck, every card at level %d. Cards you don't own yet are in it too." % int(d.card_level)],
	]
	for f in facts:
		_mode_info.add_child(_fact_row(f[0], f[1], accent))
	var note := UITheme.label("Daily games are not saved mid-game." + (" Your saved run is kept." if Profile.has_saved_run() else ""), UITheme.FS_MIN, UITheme.MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_info.add_child(note)


## Under today's stadium: best score today, the streak, the countdown and the daily bonus.
func _daily_record_block() -> Control:
	var p := UITheme.tile_panel(Color(DAILY_ACCENT, 0.45), 12)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(560, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var rec := HBoxContainer.new()
	rec.add_theme_constant_override("separation", 8)
	vb.add_child(rec)
	var played := DailyChallenge.played()
	var tiles := [["trophy", UITheme.format_int(DailyChallenge.best_score()) if played else "-", "BEST TODAY", UITheme.GOLD],
		["fire", "%d" % DailyChallenge.current_streak(), "DAY STREAK (BEST %d)" % int(Profile.data.daily.best_streak), DAILY_ACCENT.lightened(0.2)],
		["cooldown", DailyChallenge.countdown_text(), "NEXT CHALLENGE", UITheme.OFFWHITE]]
	for t in tiles:
		var st := UITheme.stat_tile(t[0], t[1], t[2], t[3], 0)
		st.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rec.add_child(st)
		if t[0] == "cooldown":
			var vl: Label = st.get_child(0).get_child(1).get_child(0)
			vl.set_meta("fmt", "%s")
			_countdown_labels.append(vl)
	var day := DailyChallenge.day_record(DailyChallenge.today())
	var rw := DailyChallenge.rewards()
	var bonus := ""
	if not bool(day.get("rewarded", false)):
		bonus = "Daily bonus: your first game today gives +%d coins and a %s. A win adds a %s." % [int(rw.first_coins), DB.pack(str(rw.first_pack)).name, DB.pack(str(rw.win_pack)).name]
	elif not bool(day.get("win_rewarded", false)):
		bonus = "Daily bonus: win today's challenge for a %s." % DB.pack(str(rw.win_pack)).name
	else:
		bonus = "Today's bonus is collected. Play again to beat your best score."
	vb.add_child(_fact_row("gift", bonus, UITheme.GOLD))
	return p


func _fact_row(icon: String, text: String, accent: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UITheme.icon_rect(icon, 22, accent.lightened(0.3)))
	var fl := UITheme.label(text, UITheme.FS_SMALL, Color(0.85, 0.89, 0.96), UITheme.font_body_bold())
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fl)
	return row


# ---------------------------------------------------------------- difficulty

func _select_difficulty(id: String, quiet := false) -> void:
	Profile.data.difficulty = id
	for k in _diff_buttons.keys():
		_diff_buttons[k].button_pressed = k == id
	_refresh_difficulty_info()
	if not quiet:
		Audio.ui("ui_toggle")
		Profile.save_soon()


## The explainer: every number that differs from Standard, coloured easier (green) or harder (red).
func _refresh_difficulty_info() -> void:
	if _diff_info == null:
		return
	var id: String = Profile.data.difficulty
	if mode_id == "ranked":
		var nd := Profile.next_division()
		id = str(nd.get("challenge_difficulty", "standard")) if not nd.is_empty() else id
	if mode_id == "daily":
		id = str(_daily.difficulty)
	if mode_id == "practice":
		_diff_text.text = "Practice uses Standard numbers with unlimited runs."
		id = "standard"
	else:
		_diff_text.text = str(DB.difficulty(id).text) + ("  (set by the challenge)" if mode_id in ["ranked", "daily"] else "")
	for c in _diff_info.get_children():
		c.queue_free()
	var d := DB.difficulty(id)
	var base := DB.difficulty("standard")
	for r in DIFF_ROWS:
		var key: String = r[0]
		if not d.has(key):
			continue
		var v := float(d[key])
		var b := float(base.get(key, v))
		var txt := ""
		var col := Color(0.85, 0.89, 0.96)
		match r[3]:
			"mult_bad", "mult_good":
				var pct := int(round((v - 1.0) * 100.0))
				txt = "normal" if pct == 0 else ("%+d%%" % pct)
				if pct != 0:
					col = UITheme.GREEN if ((pct < 0) == (r[3] == "mult_bad")) else Color(1.0, 0.45, 0.4)
			"int_good":
				txt = str(int(v))
				if v != b:
					col = UITheme.GREEN if v > b else Color(1.0, 0.45, 0.4)
			"pct_bad":
				txt = "none" if v <= 0.0 else "%d%%" % int(round(v * 100.0))
				if v > b:
					col = Color(1.0, 0.45, 0.4)
			"reward":
				txt = "×%.2f" % v
				if v != b:
					col = UITheme.GOLD if v > b else UITheme.MUTED
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(UITheme.icon_rect(r[2], 20, UITheme.MUTED))
		var nl := UITheme.label(r[1], UITheme.FS_MIN + 1, UITheme.MUTED, UITheme.font_body_bold())
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		row.add_child(nl)
		row.add_child(UITheme.label(txt, UITheme.FS_SMALL, col, UITheme.font_body_bold()))
		_diff_info.add_child(row)


# ---------------------------------------------------------------- stadiums

func _fill_arenas() -> void:
	if _arena_flow == null:
		return
	for c in _arena_flow.get_children():
		c.queue_free()
	if mode_id == "daily":   # the challenge sets the stadium (locked ones too)
		_arena_flow.add_child(_arena_tile(str(_daily.arena), true))
		_arena_flow.add_child(_daily_record_block())
		return
	for id in DB.arena_order:
		_arena_flow.add_child(_arena_tile(id))


func _arena_tile(id: String, daily := false) -> Button:
	var a := DB.arena(id)
	var unlocked: bool = daily or id in Profile.data.arenas_unlocked
	var selected: bool = daily or Profile.data.arena == id
	var accent := Color(a.theme.get("accent", "#ffffff"))
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = selected
	b.disabled = not unlocked
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(266, 204)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.12), 2, 10, 0))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0, 0, 0, 0.2), Color(accent, 0.9), 3, 10, 0))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(Color(0, 0, 0, 0.2), accent.lightened(0.2), 4, 10, 0))
	b.add_theme_stylebox_override("disabled", UITheme.panel_style(Color(0, 0, 0, 0.5), Color(1, 1, 1, 0.06), 1, 10, 0))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.clip_contents = true
	var tex := UITheme.arena_thumbnail(id)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.offset_left = 3
		tr.offset_top = 3
		tr.offset_right = -3
		tr.offset_bottom = -3
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			tr.modulate = Color(0.35, 0.35, 0.4)
		b.add_child(tr)
	else:
		var sky := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(a.theme.sky_top))
		g.set_color(1, Color(a.theme.sky_horizon))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		sky.texture = gt
		sky.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not unlocked:
			sky.modulate = Color(0.4, 0.4, 0.45)
		b.add_child(sky)
	# Caption strip along the bottom.
	var strip := PanelContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = 3
	strip.offset_right = -3
	strip.offset_bottom = -3
	var ss := UITheme.panel_style(Color(0.02, 0.03, 0.06, 0.82), Color(0, 0, 0, 0), 0, 0, 0)
	ss.content_margin_left = 10
	ss.content_margin_right = 10
	ss.content_margin_top = 4
	ss.content_margin_bottom = 5
	ss.corner_radius_bottom_left = 8
	ss.corner_radius_bottom_right = 8
	strip.add_theme_stylebox_override("panel", ss)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(strip)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -4)
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(sv)
	sv.add_child(UITheme.label(str(a.name).to_upper(), 26, UITheme.OFFWHITE if unlocked else UITheme.MUTED, UITheme.font_header()))
	var sub := "%s: %s" % [a.modifier.name, a.modifier.text] if unlocked else Profile.arena_unlock_text(id)
	var sl := UITheme.label(sub, UITheme.FS_MIN, accent.lightened(0.3) if unlocked else Color(1.0, 0.7, 0.6), UITheme.font_body_bold())
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.custom_minimum_size = Vector2(240, 0)
	sv.add_child(sl)
	if not unlocked:
		var lk := VBoxContainer.new()
		lk.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		lk.offset_top = 26
		lk.offset_left = -60
		lk.offset_right = 60
		lk.alignment = BoxContainer.ALIGNMENT_CENTER
		lk.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var li := UITheme.icon_rect("lock", 40, Color(1, 1, 1, 0.85))
		li.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		lk.add_child(li)
		var ll := UITheme.label("LOCKED", UITheme.FS_SMALL, Color(1, 1, 1, 0.85), UITheme.font_body_bold())
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lk.add_child(ll)
		b.add_child(lk)
		b.tooltip_text = "Locked. %s to unlock." % Profile.arena_unlock_text(id)
	else:
		b.tooltip_text = str(a.text)
	if selected:
		var chk := UITheme.badge("TODAY'S STADIUM" if daily else "SELECTED", Color((DAILY_ACCENT if daily else accent).darkened(0.2), 0.95))
		chk.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		chk.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		chk.offset_right = -10
		chk.offset_top = 10
		b.add_child(chk)
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.ui("ui_hover", -8.0))
	if daily:
		b.custom_minimum_size = Vector2(560, 250)
		b.tooltip_text = "Today's stadium, set by the Daily Challenge. %s" % str(a.text)
		b.pressed.connect(func() -> void: b.button_pressed = true)
		return b
	b.pressed.connect(func() -> void:
		Profile.data.arena = id
		Profile.save_soon()
		Audio.ui("ui_toggle")
		_fill_arenas())
	UITheme.add_feedback(b, 1.02)
	return b


# ---------------------------------------------------------------- summary

func _fill_summary() -> void:
	for c in _summary.get_children():
		c.queue_free()
	_summary.add_child(UITheme.section_header("YOUR TEAM", "roster", UITheme.GOLD, UITheme.FS_H3))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	for id in Profile.data.team:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pr := portrait_rect(id, 84, DB.defender_accent(id))
		pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(pr)
		var n: String = DB.defender(id).name + (" (C)" if id == Profile.data.captain else "")
		var l := UITheme.label(n, UITheme.FS_SMALL, DB.defender_accent(id).lightened(0.3), UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		grid.add_child(vb)
	_summary.add_child(grid)
	var edit_team := UITheme.button("Edit team", "secondary", 20, "roster")
	edit_team.pressed.connect(func() -> void: Router.goto("roster"))
	_summary.add_child(edit_team)
	_summary.add_child(UITheme.hsep())
	var daily := mode_id == "daily"
	_summary.add_child(UITheme.section_header("TODAY'S DECK" if daily else "DECK", "deck", UITheme.GOLD, UITheme.FS_H3))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for cid in (_daily.deck if daily else Profile.data.deck):
		var c := DB.card(cid)
		var chip := PanelContainer.new()
		var cs := UITheme.panel_style(DB.category_color(c.category).darkened(0.6), DB.rarity_color(c.rarity), 1, 6, 0)
		cs.content_margin_left = 8
		cs.content_margin_right = 8
		cs.content_margin_top = 2
		cs.content_margin_bottom = 2
		chip.add_theme_stylebox_override("panel", cs)
		chip.tooltip_text = str(c.get("text", ""))
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 6)
		var cost := UITheme.label(str(int(c.cost)), UITheme.FS_SMALL, UITheme.ENERGY, UITheme.font_header())
		ch.add_child(cost)
		ch.add_child(UITheme.label(str(c.name), UITheme.FS_MIN + 1, UITheme.OFFWHITE, UITheme.font_body_bold()))
		if daily and not Profile.is_card_owned(cid):
			ch.add_child(UITheme.icon_rect("lock", 16, UITheme.MUTED))
			chip.tooltip_text += "\n(Not in your collection yet: try it today!)"
		chip.add_child(ch)
		flow.add_child(chip)
	_summary.add_child(flow)
	if daily:
		var dl := UITheme.label("The deck is fixed for today. Every card plays at level %d." % int(_daily.card_level), UITheme.FS_MIN, UITheme.MUTED)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_summary.add_child(dl)
		return
	var edit_deck := UITheme.button("Edit deck", "secondary", 20, "deck")
	edit_deck.pressed.connect(func() -> void:
		Session.menu_tab = "deck"
		Router.goto("deck_builder"))
	_summary.add_child(edit_deck)
	var fname: String = DB.formations.get(Profile.data.formation, {}).get("name", "Custom")
	var fl := UITheme.label("Formation: %s. Change it on the field before the first pitch." % fname, UITheme.FS_MIN, UITheme.MUTED)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(fl)


func _on_start() -> void:
	Audio.ui("ui_confirm")
	if mode_id == "daily":
		# The daily game never touches the saved run or the player's deck.
		Profile.save_now()
		Session.start(DailyChallenge.config_for())
		return
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
		Profile.clear_run(true)
		Profile.data.flags["last_mode"] = mode_id
	Profile.save_now()
	Session.start(cfg)
