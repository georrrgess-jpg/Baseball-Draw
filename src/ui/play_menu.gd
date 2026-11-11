extends MenuScreen
## Play screen: big mode cards (what the mode is, your best record, what a win pays, lock state; Update 13:
## a mode a new manager has not unlocked yet is a teaser that says when it opens, Onboarding.mode_lock),
## the selected mode's details, a readable difficulty selector, a compact stadium carousel (locked
## stadiums listed with their unlock text), and the team, deck, win streak bonus and START.

const DAILY_ACCENT := Color("#FF8A3D")
## id, accent, icon. Rows of two; Practice gets a full-width slim card at the bottom.
const MODES := [
	["daily", DAILY_ACCENT, "calendar"],
	["standard", UITheme.SCARLET, "trophy"],
	["quick", UITheme.BLUE, "speed"],
	["boss_rush", Color("#E04A8A"), "boss"],
	["endless", UITheme.PURPLE, "wave"],
	["ranked", UITheme.GOLD, "crown"],
	["practice", UITheme.GREEN, "practice"],
]
## One-line pitch per mode (the Daily and the Promotion Challenge build theirs from today's state).
const PITCH := {
	"standard": "9 innings · 3 bosses · the full siege",
	"quick": "3 innings · 1 boss · about 10 minutes",
	"boss_rush": "3 innings · 3 bosses · draft a boon after each",
	"endless": "Survive · a new twist every inning · records",
	"practice": "Sandbox: spawn any runner, try any card. No rewards, no risk.",
}
## What each difficulty number means, compared with Standard. [key, label, icon, kind]
## kind: "mult_bad" (higher is harder), "mult_good" (higher is easier), "int_good", "pct_bad", "reward".
const DIFF_ROWS := [
	["enemy_hp", "Runner health", "health", "mult_bad"],
	["enemy_speed", "Runner speed", "speed", "mult_bad"],
	["budget", "Runners per wave", "enemy", "mult_bad"],
	["energy_regen", "Your energy", "energy", "mult_good"],
	["run_limit", "Runs allowed", "runs", "int_good"],
	["shields", "Base shields", "shield", "int_good"],
	["elite_chance", "Elite runners", "boss", "pct_bad"],
	["reward", "Rewards", "coin", "reward"],
]
const DIFF_COLORS := {"rookie": UITheme.GREEN, "standard": UITheme.BLUE, "veteran": UITheme.GOLD, "legend": UITheme.SCARLET}

var mode_id := "standard"
var _mode_buttons := {}
var _diff_buttons := {}
var _arena_flow: VBoxContainer    # the stadium panel's body (carousel, or today's stadium for the Daily)
var _mode_info: VBoxContainer
var _diff_info: GridContainer
var _diff_text: Label
var _start: Button
var _summary: VBoxContainer
var _streak_box: PanelContainer
var _daily: Dictionary = {}          # today's Daily Challenge rules
var _countdown_labels: Array[Label] = []
var _countdown_t := 0.0


func _ready() -> void:
	_daily = DailyChallenge.today_rules()
	setup_screen("PLAY", "Choose a mode, difficulty and stadium")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)

	# ---- Mode cards
	var modes := panel()
	modes.custom_minimum_size = Vector2(800, 0)
	body.add_child(modes)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	modes.add_child(mv)
	mv.add_child(UITheme.section_header("GAME MODE", "play"))
	var grid := VBoxContainer.new()
	grid.name = "ModeGrid"
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 10)
	mv.add_child(grid)
	var row: HBoxContainer = null
	for m in MODES:
		if not DB.mode(m[0]).has("name"):
			continue
		if m[0] == "practice" or row == null or row.get_child_count() >= 2:
			row = HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.size_flags_vertical = Control.SIZE_EXPAND_FILL if m[0] != "practice" else Control.SIZE_FILL
			grid.add_child(row)
		row.add_child(_mode_card(m[0], m[1], m[2]))

	# ---- Mode details, difficulty, stadium
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 14)
	body.add_child(mid)
	var info_panel := panel()
	info_panel.name = "ModeInfo"
	info_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mode_info = VBoxContainer.new()
	_mode_info.add_theme_constant_override("separation", 6)
	info_panel.add_child(_vscroll(_mode_info))
	mid.add_child(info_panel)
	mid.add_child(_build_difficulty())
	var ap := panel()
	ap.name = "StadiumPanel"
	mid.add_child(ap)
	_arena_flow = VBoxContainer.new()
	_arena_flow.add_theme_constant_override("separation", 8)
	ap.add_child(_arena_flow)

	# ---- Team, deck, streak bonus, START
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(390, 0)
	right.add_theme_constant_override("separation", 12)
	body.add_child(right)
	var sp := panel()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	_summary = VBoxContainer.new()
	_summary.add_theme_constant_override("separation", 8)
	sp.add_child(_vscroll(_summary))
	_streak_box = UITheme.tile_panel(Color(UITheme.FLAME, 0.5), 12)
	_streak_box.name = "StreakBonus"
	right.add_child(_streak_box)
	_start = UITheme.button("START  ▶", "primary", 48, "")
	_start.name = "StartButton"
	_start.custom_minimum_size = Vector2(390, 88)
	_start.pressed.connect(_on_start)
	right.add_child(_start)
	default_focus = _start

	var cur_diff: String = Profile.data.difficulty
	_select_difficulty(cur_diff, true)
	var last := str(Profile.data.flags.get("last_mode", "standard"))
	if last in ["practice", "ranked", "daily", "daily_long"] or not _mode_buttons.has(last) or Onboarding.mode_lock(last) != "":
		last = "standard" if Onboarding.mode_lock("standard") == "" else "quick"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--play-mode="):   # screenshot helper: --play-mode=daily, =boss_rush...
			var pm := a.split("=")[1]
			Session.menu_tab = "daily" if pm == "daily" else "mode:" + pm
	if Session.menu_tab == "daily":   # opened from the main menu's Daily Challenge tile
		last = "daily" if Onboarding.mode_lock("daily") == "" else last
	elif Session.menu_tab == "ranked":   # "Promotion Challenge" from the main menu or Results
		last = "ranked" if Onboarding.mode_lock("ranked") == "" else last
	elif Session.menu_tab.begins_with("mode:"):   # PLAY on the hub, with the mode picked there
		var want := Session.menu_tab.substr(5)
		if _mode_buttons.has(want) and Onboarding.mode_lock(want) == "":
			last = want
	elif Profile.has_saved_run():
		last = "quick"
	Session.menu_tab = ""
	_select_mode(last, true)
	set_help("play_menu", _hint_targets, func() -> Array: return ["play_streak"] if Profile.win_streak() > 0 else [])


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


func _accent(id: String) -> Color:
	for mm in MODES:
		if mm[0] == id:
			return mm[1]
	return UITheme.SCARLET


# ---------------------------------------------------------------- mode cards

## A big mode card: emblem, name, one-line pitch, a badge, your best record and what a win pays.
## Locked modes say what unlocks them. Toggle button: click, or focus it and press Enter.
func _mode_card(id: String, accent: Color, icon: String) -> Button:
	var m := DB.mode(id)
	var slim := id == "practice"
	var lock := Onboarding.mode_lock(id)
	var b := Button.new()
	b.name = "ModeCard_" + id
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 84 if slim else 176)
	b.clip_contents = true
	var mk := func(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
		var s := UITheme.panel_style(bg, border, bw, 12, 0)
		s.border_width_left = 6
		return s
	b.add_theme_stylebox_override("normal", mk.call(UITheme.TILE_BG, Color(accent, 0.45), 1))
	b.add_theme_stylebox_override("hover", mk.call(Color(accent.darkened(0.72), 0.97), accent, 2))
	b.add_theme_stylebox_override("pressed", mk.call(Color(accent.darkened(0.58), 0.97), accent.lightened(0.25), 3))
	b.add_theme_stylebox_override("hover_pressed", mk.call(Color(accent.darkened(0.52), 0.97), accent.lightened(0.35), 3))
	b.add_theme_stylebox_override("disabled", mk.call(Color(0.05, 0.06, 0.09, 0.85), Color(1, 1, 1, 0.08), 1))
	b.add_theme_stylebox_override("focus", mk.call(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.95), 3))
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 18
	vb.offset_right = -12
	vb.offset_top = 10
	vb.offset_bottom = -10
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(head)
	# Mode art: the mode's emblem on a round chip in its colour.
	var art := Panel.new()
	var side := 52.0 if slim else 60.0
	art.custom_minimum_size = Vector2(side, side)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art_s := UITheme.panel_style(accent.darkened(0.35) if lock == "" else Color(0.2, 0.22, 0.27), accent.lightened(0.3) if lock == "" else UITheme.MUTED, 2, int(side / 2), 0)
	art_s.shadow_color = Color(accent, 0.35 if lock == "" else 0.0)
	art_s.shadow_size = 8
	art.add_theme_stylebox_override("panel", art_s)
	var ic := UITheme.icon_rect("lock" if lock != "" else icon, side * 0.6, Color.WHITE if lock == "" else UITheme.MUTED)
	ic.position = Vector2(side * 0.2, side * 0.2)
	art.add_child(ic)
	head.add_child(art)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tv)
	var title := UITheme.label(str(m.name).to_upper(), 30, UITheme.OFFWHITE if lock == "" else Color(0.72, 0.77, 0.86), UITheme.font_display())
	title.clip_text = true
	tv.add_child(title)
	var pitch := UITheme.label(_pitch(id, lock), UITheme.FS_SMALL, _pitch_color(id, lock), UITheme.font_body_bold())
	pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitch.max_lines_visible = 2
	tv.add_child(pitch)
	# The badge sits in the head on the slim card, else at the end of the record row (so the name
	# and pitch keep the full width).
	var bd := _mode_badge(id, lock)
	if bd and slim:
		bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(bd)
	if not slim:
		var rule := ColorRect.new()
		rule.color = Color(accent, 0.22)
		rule.custom_minimum_size = Vector2(0, 2)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(rule)
		var rec := _record_text(id)
		var rec_row := _card_row("trophy", rec if rec != "" else "No record yet", UITheme.GOLD if rec != "" else UITheme.MUTED)
		if bd:
			bd.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			rec_row.add_child(bd)
		vb.add_child(rec_row)
		if lock != "" and not Onboarding.is_unlocked(id):   # a teaser: what the mode is and when it opens
			vb.add_child(_card_row("lock", lock, Color(1.0, 0.78, 0.6)))
		elif lock != "":
			vb.add_child(_card_row("lock", "Locked: " + lock, Color(1.0, 0.7, 0.6)))
		else:
			vb.add_child(_card_row("gift", _pays_text(id), Color(0.85, 0.95, 0.75)))
	if lock != "":
		b.disabled = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = "Locked: %s" % lock
		if id == "ranked":
			b.tooltip_text += "\nEarn rank points by winning games (higher difficulties earn more)."
		if not Onboarding.is_unlocked(id):
			b.tooltip_text = "%s: %s.\n%s" % [m.name, lock, str(m.get("text", ""))]
	else:
		b.tooltip_text = str(m.get("text", ""))
	b.mouse_entered.connect(func() -> void:
		if not b.disabled:
			Audio.ui("ui_hover", -8.0))
	b.pressed.connect(func() -> void: _select_mode(id))
	UITheme.add_feedback(b, 1.012)
	_mode_buttons[id] = b
	return b


func _card_row(icon: String, text: String, col: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := UITheme.icon_rect(icon, 20, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var l := UITheme.label(text, UITheme.FS_SMALL, col, UITheme.font_body_bold())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.max_lines_visible = 2
	row.add_child(l)
	return row


func _pitch(id: String, lock: String) -> String:
	match id:
		"daily":
			return "%s · %s · %s" % [DailyChallenge.pretty_date(str(_daily.date)), DB.difficulty(str(_daily.difficulty)).name,
				str(DailyChallenge.modifier_def(str(_daily.modifier)).get("name", str(_daily.get("format_name", ""))))]
		"ranked":
			var nd := Profile.next_division()
			if nd.is_empty():
				return "You are a Legend!"
			if lock == "":
				return "Promotion to %s available!" % nd.name
			return "Win it to reach %s" % nd.name
	return str(PITCH.get(id, DB.mode(id).get("text", "")))


func _pitch_color(id: String, lock: String) -> Color:
	if id == "ranked" and lock == "":
		return UITheme.GOLD
	if id == "daily":
		return DAILY_ACCENT.lightened(0.3)
	return UITheme.MUTED


func _mode_badge(id: String, lock: String) -> Control:
	if lock != "":
		if not Onboarding.is_unlocked(id):   # Rookie Camp: the level it opens at
			return UITheme.badge("LEVEL %d" % Onboarding.unlock_level(id), Color(0.25, 0.27, 0.32, 0.95))
		return UITheme.badge("LOCKED", Color(0.25, 0.27, 0.32, 0.95))
	match id:
		"daily":
			var played := DailyChallenge.played()
			return UITheme.badge("PLAYED" if played else "NEW TODAY", Color(0.13, 0.4, 0.25, 0.95) if played else Color(DAILY_ACCENT.darkened(0.25), 0.95))
		"boss_rush":
			return UITheme.badge("NEW", Color(_accent("boss_rush").darkened(0.2), 0.95))
		"ranked":
			return UITheme.badge("READY", UITheme.GOLD.darkened(0.35))
		"practice":
			return UITheme.badge("NO REWARDS", Color(0.16, 0.4, 0.26, 0.95))
	return null


## Your best record in a mode ("" when there is none).
func _record_text(id: String) -> String:
	var rec: Dictionary = Profile.data.get("records", {})
	match id:
		"daily":
			var parts: Array = []
			if DailyChallenge.played():
				parts.append("Best today %s" % UITheme.format_int(DailyChallenge.best_score()))
			if DailyChallenge.current_streak() > 0:
				parts.append("%d-day streak" % DailyChallenge.current_streak())
			return " · ".join(parts)
		"endless":
			if int(rec.get("best_endless_inning", 0)) <= 0:
				return ""
			return "Best: inning %d · %s points" % [int(rec.best_endless_inning), UITheme.format_int(int(rec.get("best_endless_score", 0)))]
		"boss_rush":
			var t := float(rec.get("best_time_boss_rush", 0.0))
			var best := int(rec.get("best_score_boss_rush", 0))
			var parts: Array = []
			if t > 0.0:
				parts.append("Best time %s" % Rewards.time_text(t))
			if best > 0:
				parts.append("%s points" % UITheme.format_int(best))
			return " · ".join(parts)
		"practice":
			return ""
	var s := int(rec.get("best_score_" + id, 0))
	return "Best score: %s" % UITheme.format_int(s) if s > 0 else ""


## What a game of the mode pays (on the current difficulty where it matters).
func _pays_text(id: String) -> String:
	var m := DB.mode(id)
	var diff := DB.difficulty(str(Profile.data.difficulty))
	var mult := float(m.get("reward_mult", 1.0)) * float(diff.get("reward", 1.0))
	match id:
		"daily":
			var rw := DailyChallenge.rewards()
			var day := DailyChallenge.day_record(DailyChallenge.today())
			if not bool(day.get("rewarded", false)):
				return "Today: +%d coins and a %s; a win adds a %s" % [int(rw.first_coins), DB.pack(str(rw.first_pack)).name, DB.pack(str(rw.win_pack)).name]
			if not bool(day.get("win_rewarded", false)):
				return "Win today for a %s" % DB.pack(str(rw.win_pack)).name
			return "Today's bonus collected. Beat your best score!"
		"standard":
			var pk := "Champion Pack" if str(Profile.data.difficulty) in ["veteran", "legend"] else "Pro Pack"
			return "Win: %s + coins ×%.2f · %d RP" % [pk, mult, int(round(60 * float(diff.get("rp", 1.0))))]
		"quick":
			return "Win: coins ×%.2f · %d RP · a Rookie Pack every game" % [mult, int(round(22 * float(diff.get("rp", 1.0))))]
		"boss_rush":
			return "Win: Pro Pack + coins ×%.2f · best time kept" % mult
		"endless":
			var m5 := Rewards.milestone_reward(5)
			return "Every 5 innings: %s+ coins and a Rookie Pack; Pro Packs at 10 and 20" % UITheme.format_int(int(m5.get("coins", 0)))
		"ranked":
			var nd := Profile.next_division()
			var n := int(Profile.data.division) + 1
			var pack := "Champion Pack" if n >= DB.division_index("gold") else "Pro Pack"
			return "Win: %s, +%s coins, +%d stars and a %s" % [str(nd.get("name", "promotion")), UITheme.format_int(300 * n), 10 * n, pack]
		"practice":
			return "No rewards, no risk"
	return "Coins ×%.2f" % mult


func _select_mode(id: String, quiet := false) -> void:
	mode_id = id
	for k in _mode_buttons.keys():
		_mode_buttons[k].set_pressed_no_signal(k == id)
	var m := DB.mode(id)
	for c in _mode_info.get_children():
		_mode_info.remove_child(c)
		c.queue_free()
	var accent := _accent(id)
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
		var keys: Array = m.bosses.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
		for k in keys:
			names.append(DB.enemy(str(m.bosses[k])).get("name", m.bosses[k]))
		facts.append(["boss", "Bosses: " + ", ".join(names)])
	elif m.has("boss_every"):
		facts.append(["boss", "A boss every %d innings" % int(m.boss_every)])
	if id in ["standard", "endless", "boss_rush"]:
		facts.append(["star", "Dugout Draft: after %s, pick 1 of 3 boons for the rest of the game" % {"standard": "innings 3 and 6", "endless": "every boss", "boss_rush": "bosses 1 and 2"}[id]])
	if bool(m.get("rewards", false)):
		facts.append(["coin", "Rewards ×%.2f" % float(m.get("reward_mult", 1.0))])
	else:
		facts.append(["coin", "No rewards, no risk"])
	if id == "ranked":
		var nd := Profile.next_division()
		if not nd.is_empty():
			facts.append(["crown", "%s difficulty with 2 challenge modifiers. Win to reach %s." % [DB.difficulty(nd.challenge_difficulty).name, nd.name]])
	for f in facts:
		_mode_info.add_child(_fact_row(f[0], f[1], accent))
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
		b.focus_mode = Control.FOCUS_NONE if b.disabled or id == "daily" else Control.FOCUS_ALL
		b.set_pressed_no_signal(k == (str(_daily.difficulty) if id == "daily" else str(Profile.data.difficulty)))
		# A disabled choice says why.
		b.tooltip_text = {"practice": "Practice has no difficulty: nothing is at stake.",
			"ranked": "The Promotion Challenge sets its own difficulty for your division.",
			"daily": "The Daily Challenge sets its own difficulty."}.get(id, "") if b.disabled else str(DB.difficulty(k).get("text", ""))
	_refresh_difficulty_info()
	_fill_arenas()
	_refresh_pays()
	if _summary:
		_fill_summary()
	_fill_streak()
	if _start:
		_start.text = "PLAY DAILY  ▶" if id == "daily" else "START  ▶"
	if not quiet:
		Audio.ui("ui_tab")
	# Meeting a mode for the first time explains it (Daily, Boss Rush, Promotion, Endless, Practice).
	if Hints.HINTS.has("play_" + id):
		Hints.show_unseen(self, ["play_" + id], _hint_targets, 0.7 if quiet else 0.15)


## Hint arrows: the mode list, each mode's card, and the win streak box.
func _hint_targets() -> Dictionary:
	var t := {}
	if _mode_buttons.has("standard"):
		t["play_modes"] = find_child("ModeGrid", true, false)
	for m in ["daily", "ranked", "endless", "practice", "boss_rush"]:
		if _mode_buttons.has(m):
			t["play_" + m] = _mode_buttons[m]
	if _streak_box:
		t["play_streak"] = _streak_box
	return t


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
	vb.add_child(_fact_row("gift", _pays_text("daily"), UITheme.GOLD))
	return p


func _fact_row(icon: String, text: String, accent: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ic := UITheme.icon_rect(icon, 22, accent.lightened(0.3))
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ic)
	var fl := UITheme.label(text, UITheme.FS_SMALL, Color(0.85, 0.89, 0.96), UITheme.font_body_bold())
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fl)
	return row


## The pay rows on the mode cards depend on the difficulty: refresh them when it changes.
func _refresh_pays() -> void:
	for id in ["standard", "quick", "boss_rush"]:
		var b: Button = _mode_buttons.get(id)
		if b == null or b.disabled:
			continue
		var vb: Node = b.get_child(0)
		var row: Node = vb.get_child(vb.get_child_count() - 1) if vb.get_child_count() > 0 else null
		if row is HBoxContainer and row.get_child_count() == 2 and row.get_child(1) is Label:
			(row.get_child(1) as Label).text = _pays_text(id)


# ---------------------------------------------------------------- difficulty

func _build_difficulty() -> Control:
	var dp := panel()
	dp.name = "DifficultyPanel"
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 8)
	dp.add_child(dv)
	var dhead := HBoxContainer.new()
	dhead.add_theme_constant_override("separation", 10)
	dv.add_child(dhead)
	var sh := UITheme.section_header("DIFFICULTY", "boss")
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dhead.add_child(sh)
	# Who you will face: a link to the Scouting Book (BACK returns here).
	var scout := UITheme.button("SCOUTING BOOK  ▶", "ghost", UITheme.FS_SMALL, "enemy", Color("#FF6B3D"))
	scout.name = "ScoutingBookLink"
	scout.tooltip_text = "Know who you will face: runners, bosses and elites, what they do and which cards stop them"
	scout.pressed.connect(func() -> void: Router.open("scouting_book"))
	dhead.add_child(scout)
	if not Onboarding.is_unlocked("scouting"):   # Rookie Camp: opens with the Scouting Book
		scout.visible = false
	var dh := HBoxContainer.new()
	dh.add_theme_constant_override("separation", 8)
	dv.add_child(dh)
	for id in DB.difficulty_order:
		dh.add_child(_difficulty_button(id))
	_diff_text = UITheme.label("", UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	_diff_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dv.add_child(_diff_text)
	_diff_info = GridContainer.new()
	_diff_info.columns = 2
	_diff_info.add_theme_constant_override("h_separation", 28)
	_diff_info.add_theme_constant_override("v_separation", 3)
	dv.add_child(_diff_info)
	return dp


## A two-line difficulty button: the name, and its reward multiplier.
func _difficulty_button(id: String) -> Button:
	var d := DB.difficulty(id)
	var col: Color = DIFF_COLORS.get(id, UITheme.BLUE)
	var b := UITheme.button("", "secondary", UITheme.FS_LEAD, "", col)
	b.name = "Diff_" + id
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 62)
	var pressed_s: StyleBoxFlat = b.get_theme_stylebox("pressed").duplicate()
	pressed_s.bg_color = col.darkened(0.45)
	pressed_s.border_color = col.lightened(0.35)
	pressed_s.set_border_width_all(3)
	b.add_theme_stylebox_override("pressed", pressed_s)
	b.add_theme_stylebox_override("hover_pressed", pressed_s)
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", -6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(vb)
	var n := UITheme.label(str(d.name).to_upper(), UITheme.FS_H3, UITheme.OFFWHITE, UITheme.font_header())
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(n)
	var tag := UITheme.label("×%.2f rewards" % float(d.get("reward", 1.0)), UITheme.FS_MIN, col.lightened(0.35), UITheme.font_body_bold())
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tag)
	b.pressed.connect(func() -> void: _select_difficulty(id))
	_diff_buttons[id] = b
	return b


func _select_difficulty(id: String, quiet := false) -> void:
	Profile.data.difficulty = id
	for k in _diff_buttons.keys():
		_diff_buttons[k].set_pressed_no_signal(k == id)
	_refresh_difficulty_info()
	_refresh_pays()
	if not quiet:
		Audio.ui("ui_toggle")
		Profile.save_soon()


## The explainer: the key numbers, coloured easier (green) or harder (red) than Standard.
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
		_diff_text.text = "%s: %s" % [DB.difficulty(id).name, DB.difficulty(id).text] + ("  (set by the challenge)" if mode_id in ["ranked", "daily"] else "")
	_diff_text.add_theme_color_override("font_color", Color(DIFF_COLORS.get(id, UITheme.BLUE)).lightened(0.45))
	for c in _diff_info.get_children():
		_diff_info.remove_child(c)
		c.queue_free()
	var d := DB.difficulty(id)
	var base := DB.difficulty("standard")
	for r in DIFF_ROWS:
		var key: String = r[0]
		if not d.has(key):
			continue
		var v := float(d[key])
		var b := float(base.get(key, v))
		if key == "shields":   # a mode can override the starting shields
			v = float(DB.mode(mode_id).get("tuning", {}).get(id, {}).get("shields", v))
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
		var nl := UITheme.label(r[1], UITheme.FS_SMALL, Color(0.75, 0.8, 0.9), UITheme.font_body_bold())
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.clip_text = true
		row.add_child(nl)
		row.add_child(UITheme.label(txt, UITheme.FS_BODY, col, UITheme.font_header()))
		_diff_info.add_child(row)


# ---------------------------------------------------------------- stadiums

## The stadium panel: a carousel of the unlocked stadiums (◀ ▶, or click a thumbnail), and the
## locked ones as short lines with what unlocks them. The Daily shows today's stadium instead.
func _fill_arenas() -> void:
	if _arena_flow == null:
		return
	for c in _arena_flow.get_children():
		_arena_flow.remove_child(c)
		c.queue_free()
	var unlocked: Array = []
	var locked: Array = []
	for id in DB.arena_order:
		(unlocked if id in Profile.data.arenas_unlocked else locked).append(id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_arena_flow.add_child(head)
	var sh := UITheme.section_header("TODAY'S STADIUM" if mode_id == "daily" else "STADIUM", "map")
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	if mode_id == "daily":   # the challenge sets the stadium (locked ones too)
		_arena_flow.add_child(_arena_preview(str(_daily.arena), true))
		_arena_flow.add_child(_daily_record_block())
		return
	if not str(Profile.data.arena) in unlocked:
		Profile.data.arena = unlocked[0] if not unlocked.is_empty() else "steel_yard"
	head.add_child(UITheme.label("%d / %d" % [unlocked.size(), DB.arena_order.size()], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold()))
	var prev := UITheme.icon_button("back", "Previous stadium", UITheme.BLUE, 44)
	prev.name = "ArenaPrev"
	prev.pressed.connect(func() -> void: _cycle_arena(-1))
	head.add_child(prev)
	var nxt := UITheme.icon_button("play", "Next stadium", UITheme.BLUE, 44)
	nxt.name = "ArenaNext"
	nxt.pressed.connect(func() -> void: _cycle_arena(1))
	head.add_child(nxt)
	prev.disabled = unlocked.size() < 2
	nxt.disabled = unlocked.size() < 2
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_arena_flow.add_child(row)
	var pv := _arena_preview(str(Profile.data.arena), false)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(pv)
	if unlocked.size() > 1:
		var thumbs := GridContainer.new()   # one column up to 3 stadiums, then two
		thumbs.name = "ArenaThumbs"
		thumbs.columns = ceili(unlocked.size() / 3.0)
		thumbs.add_theme_constant_override("h_separation", 6)
		thumbs.add_theme_constant_override("v_separation", 6)
		row.add_child(thumbs)
		for id in unlocked:
			thumbs.add_child(_arena_thumb(id))
	if not locked.is_empty():
		var lv := VBoxContainer.new()
		lv.name = "LockedArenas"
		lv.add_theme_constant_override("separation", 2)
		_arena_flow.add_child(lv)
		var shown := locked.slice(0, 3)
		for id in shown:
			var lr := HBoxContainer.new()
			lr.add_theme_constant_override("separation", 8)
			lr.mouse_filter = Control.MOUSE_FILTER_PASS
			lr.tooltip_text = "%s: %s" % [DB.arena(id).name, DB.arena(id).get("text", "")]
			lr.add_child(UITheme.icon_rect("lock", 18, Color(1.0, 0.7, 0.6)))
			var nl := UITheme.label(str(DB.arena(id).name).to_upper(), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_header())
			lr.add_child(nl)
			var ul := UITheme.label(Profile.arena_unlock_text(id), UITheme.FS_SMALL, Color(1.0, 0.75, 0.65), UITheme.font_body_bold())
			ul.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ul.clip_text = true
			lr.add_child(ul)
			lv.add_child(lr)
		if locked.size() > shown.size():
			var rest: Array = []
			for id in locked.slice(shown.size()):
				rest.append("%s: %s" % [DB.arena(id).name, Profile.arena_unlock_text(id)])
			var more := UITheme.label("+%d more locked" % (locked.size() - shown.size()), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
			more.mouse_filter = Control.MOUSE_FILTER_PASS
			more.tooltip_text = "\n".join(rest)
			lv.add_child(more)


func _cycle_arena(step: int) -> void:
	var unlocked: Array = DB.arena_order.filter(func(id: String) -> bool: return id in Profile.data.arenas_unlocked)
	if unlocked.size() < 2:
		return
	var i := unlocked.find(str(Profile.data.arena))
	_pick_arena(unlocked[posmod(i + step, unlocked.size())])


## Selects a stadium and rebuilds the carousel; keyboard focus stays on the same button.
func _pick_arena(id: String) -> void:
	var f := get_viewport().gui_get_focus_owner()
	var focus_name := str(f.name) if f != null and _arena_flow.is_ancestor_of(f) else ""
	Profile.data.arena = id
	Profile.save_soon()
	Audio.ui("ui_toggle")
	_fill_arenas()
	if focus_name != "":
		var again := _arena_flow.find_child(focus_name, true, false)
		if again is Control:
			(again as Control).grab_focus.call_deferred()


## The selected stadium as a wide picture with its name and modifier.
func _arena_preview(id: String, daily: bool) -> Control:
	var a := DB.arena(id)
	var accent := Color(a.theme.get("accent", "#ffffff"))
	var p := Panel.new()
	p.name = "ArenaPreview"
	p.custom_minimum_size = Vector2(0, 190 if daily else 150)
	p.clip_contents = true
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0, 0, 0, 0.4), (DAILY_ACCENT if daily else accent).lightened(0.2), 3, 10, 0))
	p.tooltip_text = ("Today's stadium, set by the Daily Challenge. " if daily else "") + str(a.get("text", ""))
	_add_arena_picture(p, id, 3)
	var strip := PanelContainer.new()
	strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	strip.offset_left = 3
	strip.offset_right = -3
	strip.offset_bottom = -3
	var ss := UITheme.panel_style(Color(0.02, 0.03, 0.06, 0.82), Color(0, 0, 0, 0), 0, 0, 0)
	ss.content_margin_left = 12
	ss.content_margin_right = 12
	ss.content_margin_top = 4
	ss.content_margin_bottom = 6
	ss.corner_radius_bottom_left = 8
	ss.corner_radius_bottom_right = 8
	strip.add_theme_stylebox_override("panel", ss)
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(strip)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -4)
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(sv)
	sv.add_child(UITheme.label(str(a.name).to_upper(), 28, UITheme.OFFWHITE, UITheme.font_header()))
	var sl := UITheme.label("%s: %s" % [a.modifier.name, a.modifier.text], UITheme.FS_SMALL, accent.lightened(0.35), UITheme.font_body_bold())
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sv.add_child(sl)
	var chk := UITheme.badge("TODAY'S STADIUM" if daily else "SELECTED", Color((DAILY_ACCENT if daily else accent).darkened(0.25), 0.95))
	chk.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	chk.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	chk.offset_right = -10
	chk.offset_top = 10
	p.add_child(chk)
	if daily and not id in Profile.data.arenas_unlocked:
		var nb := UITheme.badge("NOT UNLOCKED YET: PLAY IT TODAY", Color(0.35, 0.15, 0.1, 0.95))
		nb.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		nb.offset_left = 10
		nb.offset_top = 10
		p.add_child(nb)
	return p


## A small clickable picture of an unlocked stadium (the carousel's thumbnails).
func _arena_thumb(id: String) -> Button:
	var a := DB.arena(id)
	var accent := Color(a.theme.get("accent", "#ffffff"))
	var selected: bool = Profile.data.arena == id
	var b := Button.new()
	b.name = "Arena_" + id
	b.custom_minimum_size = Vector2(112, 44)
	b.clip_contents = true
	b.tooltip_text = "%s: %s" % [a.name, a.modifier.text]
	b.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0, 0, 0, 0.4), accent.lightened(0.2) if selected else Color(1, 1, 1, 0.15), 3 if selected else 1, 8, 0))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0, 0, 0, 0.2), accent, 2, 8, 0))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(Color(0, 0, 0, 0.2), accent.lightened(0.3), 3, 8, 0))
	b.add_theme_stylebox_override("focus", UITheme.panel_style(Color(0, 0, 0, 0), UITheme.GOLD, 3, 8, 0))
	_add_arena_picture(b, id, 2)
	if not selected:
		b.self_modulate = Color(0.75, 0.75, 0.8)
	b.pressed.connect(func() -> void: _pick_arena(id))
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -8.0))
	UITheme.add_feedback(b, 1.04)
	return b


func _add_arena_picture(host: Control, id: String, inset: int) -> void:
	var a := DB.arena(id)
	var tex := UITheme.arena_thumbnail(id)
	var tr := TextureRect.new()
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.offset_left = inset
	tr.offset_top = inset
	tr.offset_right = -inset
	tr.offset_bottom = -inset
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		tr.texture = tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	else:
		var g := Gradient.new()
		g.set_color(0, Color(a.theme.sky_top))
		g.set_color(1, Color(a.theme.sky_horizon))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(0, 1)
		tr.texture = gt
	host.add_child(tr)


# ---------------------------------------------------------------- summary

func _fill_summary() -> void:
	for c in _summary.get_children():
		_summary.remove_child(c)
		c.queue_free()
	var team_head := HBoxContainer.new()
	team_head.add_theme_constant_override("separation", 8)
	var th := UITheme.section_header("YOUR TEAM", "roster", UITheme.GOLD, UITheme.FS_H3)
	th.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	team_head.add_child(th)
	var edit_team := UITheme.button("EDIT", "secondary", UITheme.FS_SMALL, "roster")
	edit_team.name = "EditTeam"
	edit_team.tooltip_text = "Change your team and captain"
	edit_team.custom_minimum_size = Vector2(96, 40)
	edit_team.pressed.connect(func() -> void: Router.open("roster"))
	team_head.add_child(edit_team)
	if not Onboarding.is_unlocked("team"):   # Rookie Camp: the Team screen opens at level 2
		edit_team.disabled = true
		edit_team.tooltip_text = "Team: %s" % Onboarding.lock_text("team")
	_summary.add_child(team_head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	for id in Profile.data.team:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pr := portrait_rect(id, 76, DB.defender_accent(id))
		pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(pr)
		var n: String = DB.defender(id).name + (" (C)" if id == Profile.data.captain else "")
		var l := UITheme.label(n, UITheme.FS_SMALL, DB.defender_accent(id).lightened(0.3), UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(l)
		grid.add_child(vb)
	_summary.add_child(grid)
	_summary.add_child(UITheme.hsep())
	var daily := mode_id == "daily"
	var deck_head := HBoxContainer.new()
	deck_head.add_theme_constant_override("separation", 8)
	var dh := UITheme.section_header("TODAY'S DECK" if daily else "DECK", "deck", UITheme.GOLD, UITheme.FS_H3)
	dh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_head.add_child(dh)
	if not daily:
		var edit_deck := UITheme.button("EDIT", "secondary", UITheme.FS_SMALL, "deck")
		edit_deck.name = "EditDeck"
		edit_deck.tooltip_text = "Change the 8 cards you take into the game"
		edit_deck.custom_minimum_size = Vector2(96, 40)
		edit_deck.pressed.connect(func() -> void:
			Session.menu_tab = "deck"
			Router.open("deck_builder"))
		deck_head.add_child(edit_deck)
	_summary.add_child(deck_head)
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
	var note := ""
	if daily:
		note = "The deck is fixed for today. Every card plays at level %d." % int(_daily.card_level)
	else:
		var fname: String = DB.formations.get(Profile.data.formation, {}).get("name", "Custom")
		note = "Formation: %s. Change it on the field before the first pitch." % fname
	var fl := UITheme.label(note, UITheme.FS_MIN, UITheme.MUTED)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_child(fl)


## The win streak and first-win-of-the-day bonuses the next game can earn.
func _fill_streak() -> void:
	if _streak_box == null:
		return
	for c in _streak_box.get_children():
		_streak_box.remove_child(c)
		c.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_streak_box.add_child(vb)
	var streak := Profile.win_streak()
	var bonus := Profile.streak_bonus()
	var flame := UITheme.flame_chip(streak, bonus, UITheme.FS_BODY)
	flame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vb.add_child(flame)
	var rewarded := bool(DB.mode(mode_id).get("rewards", false))
	var lines: Array = []
	if not rewarded:
		lines.append(["info", "Practice has no rewards: the streak waits for your next real game.", UITheme.MUTED])
	else:
		if streak > 0:
			lines.append(["coin", "A win now pays +%d%% coins and keeps the streak going (+%d%% next)." % [int(round(bonus * 100.0)), int(round(minf(0.5, bonus + 0.1) * 100.0))], UITheme.GOLD])
		else:
			lines.append(["coin", "Win to start a streak: +10% coins per win in a row, up to +50%.", UITheme.OFFWHITE])
		if Profile.is_first_win_today():
			lines.append(["trophy", "First win today: double coins!", UITheme.GREEN])
	for ln in lines:
		var row := _fact_row(ln[0], ln[1], ln[2])
		(row.get_child(1) as Label).add_theme_color_override("font_color", ln[2])
		vb.add_child(row)


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
