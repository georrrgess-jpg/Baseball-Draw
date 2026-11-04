extends Control
## End-of-run results: outcome and a line score, then three columns. THE GAME: the game-flow
## graph and each defender's XP. REWARDS, built up in sequence: coins count up (with the win
## streak, first-win-of-the-day, Endless milestone and extra-copy bonuses), the account XP and
## Season bars fill (tier-ups flash), rank points tick, missions, packs fly in. HIGHLIGHTS: the
## Daily result, biggest combo, best card play, MVP, the boons drafted, records and card mastery.
## Every animation is a tween bound to the control it moves and killed when that control leaves
## the tree, so closing the screen mid-animation never runs a callback on a freed control.

var battle: Battle
var result: Dictionary = {}

## Reward build-up timeline (seconds after the screen opens).
const T_BODY := 1.2
const T_COINS := 1.7
const T_BONUS := 2.25
const T_XP := 2.4
const T_SEASON := 2.9
const T_RP := 3.1
const T_PACKS := 3.5
const T_TEAM := 4.0

const DAILY_ACCENT := Color("#FF8A3D")
const SEASON_ACCENT := Color("#B27BF0")

var _rv: VBoxContainer
var _again: Button
var _season_row: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_demo_result()
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	UITheme.bound_tween(dim).tween_property(dim, "color:a", 0.7, 1.0).set_delay(1.0)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)
	var won: bool = result.get("won", false)
	var practice: bool = result.get("practice", false)
	var title := UITheme.title("VICTORY!" if won else ("PRACTICE OVER" if practice else "DEFEAT"), 80,
		UITheme.GOLD if won else (UITheme.BLUE if practice else UITheme.SCARLET))
	title.name = "ResultTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	title.resized.connect(func() -> void: title.pivot_offset = title.size * 0.5)
	title.scale = Vector2(0.5, 0.5)
	title.modulate.a = 0.0
	var tw := UITheme.bound_tween(title)
	tw.set_parallel(true)
	tw.tween_property(title, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.6)
	tw.tween_property(title, "modulate:a", 1.0, 0.3).set_delay(0.6)

	if practice:
		var b := UITheme.button("MAIN MENU", "primary", 34, "back")
		b.custom_minimum_size = Vector2(320, UITheme.BTN_H_LARGE)
		b.pressed.connect(func() -> void: Router.goto("main_menu"))
		_again = b
		var cc := CenterContainer.new()
		cc.add_child(b)
		vb.add_child(cc)
		return

	var mode := DB.mode(result.get("mode", "standard"))
	var daily: Dictionary = result.get("daily", {})
	var mode_name: String = mode.get("name", "Game")
	if not daily.is_empty():
		mode_name = "DAILY CHALLENGE  ·  %s" % DailyChallenge.pretty_date(str(daily.get("date", "")))
	var sub := UITheme.header("%s  ·  %s  ·  %s" % [mode_name, DB.difficulty(result.get("difficulty", "standard")).get("name", ""), DB.arena(result.get("arena", "steel_yard")).get("name", "")], 28,
		DAILY_ACCENT.lightened(0.2) if not daily.is_empty() else UITheme.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var line := _build_line_score()
	vb.add_child(line)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(body)
	var left := _scrollify(_build_game())
	body.add_child(left)
	var mid := _scrollify(_build_rewards())
	body.add_child(mid)
	var right := _scrollify(_build_highlights())
	body.add_child(right)
	var k := 0
	for c in [line, left, mid, right]:
		UITheme.animate_in(c, T_BODY - 0.15 + k * 0.1)
		k += 1
	vb.add_child(_build_buttons())
	if _season_row:
		Hints.first_visit(self, "results", func() -> Dictionary: return {"results_season": _season_row} if is_instance_valid(_season_row) else {}, [], T_TEAM + 1.2)


## Screenshot helper (`--demo-results`, with `--show-results`): Update 9 result keys the game left
## empty get sample values (a win streak, extra copies, boons), so every section shows.
func _demo_result() -> void:
	if not "--demo-results" in OS.get_cmdline_user_args() or result.is_empty() or result.get("practice", false):
		return
	var demo := {"streak": 3, "streak_bonus": 0.2, "streak_bonus_coins": 38, "overflow_coins": 80,
		"boons": Boons.all().slice(0, 3).map(func(b: Dictionary) -> String: return str(b.get("id", "")))}
	var extra := 0
	for k in demo.keys():
		var v: Variant = result.get(k, null)
		if v == null or (typeof(v) in [TYPE_INT, TYPE_FLOAT] and float(v) == 0.0) or (typeof(v) == TYPE_ARRAY and (v as Array).is_empty()):
			result[k] = demo[k]
			if k.ends_with("_coins"):
				extra += int(demo[k])
	result["coins_total"] = int(result.get("coins_total", result.get("coins", 0))) + extra


# ---------------------------------------------------------------- line score

## The box score under the title: innings, outs, runs, cards, double/triple plays and the score.
func _build_line_score() -> Control:
	var st: Dictionary = result.get("stats", {})
	var row := HBoxContainer.new()
	row.name = "LineScore"
	row.add_theme_constant_override("separation", 10)
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
		var ts: StyleBoxFlat = tile.get_theme_stylebox("panel").duplicate()
		ts.content_margin_top = 6
		ts.content_margin_bottom = 6
		tile.add_theme_stylebox_override("panel", ts)
		row.add_child(tile)
	return row


# ---------------------------------------------------------------- the game: graph, boons, team

func _build_game() -> PanelContainer:
	var p := _panel("THE GAME", "outs")
	p.custom_minimum_size = Vector2(450, 0)
	var sv: VBoxContainer = p.get_child(0)
	sv.add_child(UITheme.section_header("GAME FLOW", "wave", UITheme.GOLD, UITheme.FS_H3))
	var st: Dictionary = result.get("stats", {})
	var tl: Array = st.get("timeline", [])
	var graph := RunGraph.new(tl)
	graph.custom_minimum_size.y = maxf(graph.custom_minimum_size.y, 140.0)
	graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph.progress = 0.0
	graph.tooltip_text = _graph_tooltip(tl)
	sv.add_child(graph)
	UITheme.bound_tween(graph).tween_property(graph, "progress", 1.0, 1.4).set_delay(T_BODY + 0.4).set_trans(Tween.TRANS_SINE)
	# Each defender's XP: the bar fills from before to after, level-ups flash.
	var dxp: Dictionary = result.get("defender_xp", {})
	if not dxp.is_empty():
		sv.add_child(UITheme.section_header("TEAM PROGRESS", "roster", UITheme.GOLD, UITheme.FS_H3))
		var grid := GridContainer.new()
		grid.name = "TeamProgress"
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		sv.add_child(grid)
		var ti := 0
		for id in dxp.keys():
			var tile := _progress_tile(id, dxp[id], T_TEAM + 0.3 + ti * 0.2)
			grid.add_child(tile)
			UITheme.animate_in(tile, T_TEAM + ti * 0.08)
			ti += 1
	return p


## One boon taken this game, in one line: its icon, its name in its rarity colour and what it does.
func _boon_row(b: Dictionary) -> Control:
	var col := DB.rarity_color(str(b.get("rarity", "common"))).lightened(0.25)
	var p := UITheme.tile_panel(Color(col, 0.45), 4)
	p.name = "Boon_" + str(b.get("id", ""))
	p.tooltip_text = "%s (%s): %s" % [b.get("name", ""), str(b.get("rarity", "common")).capitalize(), b.get("text", "")]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var icon := str(b.get("icon", "star"))
	var ic := UITheme.icon_rect(icon if DB.icon(icon) != null else "star", 24, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var n := UITheme.label(str(b.get("name", "")).to_upper(), UITheme.FS_BODY, col, UITheme.font_header())
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(n)
	var t := UITheme.label(str(b.get("text", "")), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body())
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hb.add_child(t)
	return p


func _graph_tooltip(tl: Array) -> String:
	var lines: Array = []
	for e in tl:
		lines.append("Inning %d: %d runs · %d outs · %d cards · energy %.1f avg" % [int(e.get("inning", 0)), int(e.get("runs", 0)),
			int(e.get("outs", 0)), int(e.get("cards", 0)), float(e.get("energy_avg", 0.0))])
	return "\n".join(lines)


# ---------------------------------------------------------------- rewards

func _build_rewards() -> PanelContainer:
	var p := _panel("REWARDS", "gift")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rv = p.get_child(0)
	var rv := _rv
	# Coins, XP and RP counters fill one after another.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	rv.add_child(top)
	# The total of the game (bonuses included); the chips below break the bonuses out.
	top.add_child(_counter("coin", int(result.get("coins_total", result.get("coins", 0))), "+%s", "COINS", UITheme.GOLD, T_COINS))
	top.add_child(_counter("upgrade", int(result.get("xp", 0)), "+%s", "ACCOUNT XP", UITheme.GREEN, T_XP))
	top.add_child(_counter("trophy", int(result.get("rp", 0)), "+%s", "RANK POINTS", UITheme.BLUE, T_RP))
	var bonus := _bonus_chips()
	if bonus:
		rv.add_child(bonus)
	rv.add_child(_level_row())
	var season := _season_block()
	if season:
		rv.add_child(season)
	if result.get("promoted", false):
		rv.add_child(_late(_promotion_block(), T_RP + 0.4))
	# (An available Promotion Challenge is the first WHAT'S NEXT button below.)
	var ms := _milestones_row()
	if ms:
		rv.add_child(_late(ms, T_BONUS + 0.3))
	rv.add_child(_late(MissionsPanel.results_strip(result), T_RP + 0.3))   # Update 6 missions + first-win bonus
	rv.add_child(_packs_block())
	return p


## The coin bonuses on top of the game's coins, as small chips under the counters: the win
## streak, the first win of the day, Endless milestones and extra copies turned into coins.
## Null when there is none.
func _bonus_chips() -> Control:
	var chips: Array = []
	var streak := int(result.get("streak", 0))
	if streak > 0:
		var sc := int(result.get("streak_bonus_coins", 0))
		var pct := int(round(float(result.get("streak_bonus", 0.0)) * 100.0))
		chips.append(["fire", "%d-WIN STREAK" % streak, sc, UITheme.FLAME, "Win streak: +10%% coins per win in a row (max +50%%). This win: +%d%%." % pct])
	if int(result.get("first_win_today_coins", 0)) > 0:
		chips.append(["trophy", "FIRST WIN TODAY ×2", int(result.first_win_today_coins), UITheme.GREEN, "Your first win each day pays double coins."])
	if int(result.get("milestone_coins", 0)) > 0:
		chips.append(["wave", "MILESTONES", int(result.milestone_coins), UITheme.PURPLE.lightened(0.3), "Endless milestones: every 5 innings cleared pays coins and a pack."])
	if int(result.get("overflow_coins", 0)) > 0:
		chips.append(["collection", "EXTRA COPIES", int(result.overflow_coins), UITheme.BLUE.lightened(0.3), "Copies of cards already at max level were turned into coins."])
	if chips.is_empty():
		return null
	var row := HFlowContainer.new()
	row.name = "CoinBonuses"
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 6)
	var k := 0
	for c in chips:
		var col: Color = c[3]
		var p := PanelContainer.new()
		var s := UITheme.panel_style(Color(col.darkened(0.72), 0.95), Color(col, 0.7), 1, 14, 0)
		s.content_margin_left = 10
		s.content_margin_right = 12
		s.content_margin_top = 3
		s.content_margin_bottom = 3
		p.add_theme_stylebox_override("panel", s)
		p.tooltip_text = c[4]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		p.add_child(hb)
		hb.add_child(UITheme.icon_rect(c[0], 22, col.lightened(0.1)))
		hb.add_child(UITheme.label(c[1], UITheme.FS_SMALL, col.lightened(0.3), UITheme.font_body_bold()))
		if int(c[2]) > 0:
			hb.add_child(UITheme.icon_rect("coin", 18, UITheme.GOLD))
			hb.add_child(UITheme.label("+%s" % UITheme.format_int(int(c[2])), UITheme.FS_BODY, UITheme.GOLD, UITheme.font_header()))
		row.add_child(_late(p, T_BONUS + k * 0.15))
		k += 1
	return row


## Account XP bar: fills from where the player was, looping on level-ups.
func _level_row() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var lvl_row := HBoxContainer.new()
	lvl_row.add_theme_constant_override("separation", 12)
	box.add_child(lvl_row)
	var level := int(Profile.data.level)
	var levels := int(result.get("levels", 0))
	var lvl_l := UITheme.label("LEVEL %d" % (level - levels), UITheme.FS_LEAD, UITheme.GREEN, UITheme.font_header())
	lvl_l.custom_minimum_size = Vector2(130, 0)
	lvl_row.add_child(lvl_l)
	var xpbar := UITheme.bar(UITheme.GREEN, 14, 1.0, 0.0)
	xpbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xpbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvl_row.add_child(xpbar)
	var xp_now := int(Profile.data.xp)
	var xp_l := UITheme.label("%d / %d XP" % [xp_now, Profile.xp_to_next(level)], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	xp_l.custom_minimum_size = Vector2(150, 0)
	xp_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lvl_row.add_child(xp_l)
	var start := 0.0
	if levels == 0:
		start = clampf(float(xp_now - int(result.get("xp", 0))) / maxi(1, Profile.xp_to_next(level)), 0.0, 1.0)
	xpbar.value = start
	var banner := UITheme.label("", UITheme.FS_LEAD, UITheme.GREEN, UITheme.font_display())
	banner.visible = false
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(banner)
	var xt := UITheme.bound_tween(box)
	xt.tween_interval(T_XP)
	for i in levels:
		var lv := level - levels + i + 1
		xt.tween_property(xpbar, "value", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		xt.tween_callback(func() -> void:
			Audio.play("level_up", -4.0)
			lvl_l.text = "LEVEL %d" % lv
			banner.text = "LEVEL UP — %d!  %s" % [lv, LevelRoad.reward_text(lv, true)]
			banner.visible = true
			xpbar.value = 0.0)
	xt.tween_property(xpbar, "value", clampf(float(xp_now) / maxi(1, Profile.xp_to_next(level)), 0.0, 1.0), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return box


## Season XP: the tier bar fills from before this game, flashing each tier reached with its
## reward (tiers above 30 are bonus Pro Packs, already granted), and a link to the Season Pass when
## a reward is waiting. Null when the game gave no season XP.
func _season_block() -> Control:
	var gained := int(result.get("season_xp", 0))
	if gained <= 0:
		return null
	var after_xp := int(result.get("season_xp_after", Season.xp()))
	var before_xp := int(result.get("season_xp_before", maxi(0, after_xp - gained)))
	var p0 := _season_pos(before_xp)
	var p1 := _season_pos(after_xp)
	var box := VBoxContainer.new()
	box.name = "SeasonXP"
	box.add_theme_constant_override("separation", 2)
	_season_row = box
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var tl := UITheme.label(_season_tier_label(int(p0[0])), UITheme.FS_LEAD, SEASON_ACCENT, UITheme.font_header())
	tl.custom_minimum_size = Vector2(130, 0)
	var cur := Season.current()
	tl.tooltip_text = "%s%s" % [cur.get("name", "Season"), (": " + str(cur.theme)) if str(cur.get("theme", "")) != "" else ""]
	tl.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(tl)
	var bar := UITheme.bar(SEASON_ACCENT, 14, 1.0, float(p0[1]))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "Season XP: 100 per game, +60 for a win, +80 per mission, +100 for the Daily Challenge"
	row.add_child(bar)
	var gl := UITheme.label("+%d SEASON XP" % gained, UITheme.FS_SMALL, SEASON_ACCENT.lightened(0.25), UITheme.font_body_bold())
	gl.custom_minimum_size = Vector2(150, 0)
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(gl)
	var banner := HBoxContainer.new()
	banner.add_theme_constant_override("separation", 10)
	banner.visible = false
	box.add_child(banner)
	var bl := UITheme.label("", UITheme.FS_BODY, SEASON_ACCENT.lightened(0.3), UITheme.font_display())
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.add_child(bl)
	var go := UITheme.button("SEASON PASS  ▶", "secondary", UITheme.FS_SMALL, "star", SEASON_ACCENT)
	go.name = "SeasonLink"
	go.custom_minimum_size = Vector2(0, 40)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.tooltip_text = "Claim your season rewards"
	go.pressed.connect(func() -> void: Router.goto("season"))
	banner.add_child(go)
	var rewards := {}
	for t in Season.tiers():
		if typeof(t) == TYPE_DICTIONARY:
			rewards[int(t.get("tier", 0))] = str(t.get("text", Season.reward_text(t.get("reward", {}))))
	# Each step past a tier (or a bonus Pro Pack) fills the bar, flashes and names the reward.
	var steps: Array = []
	for t in range(int(p0[0]) + 1, int(p1[0]) + 1):
		steps.append(t)
	var tw := UITheme.bound_tween(box)
	tw.tween_interval(T_SEASON)
	for t in steps.slice(maxi(0, steps.size() - 6)):
		var tier: int = t
		tw.tween_property(bar, "value", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			Audio.play("level_up", -5.0)
			tl.text = _season_tier_label(tier)
			if tier > Season.TIERS:
				bl.text = "BONUS PRO PACK!  Added to your packs"
			else:
				var rtxt: String = rewards.get(tier, "")
				bl.text = "SEASON TIER %d!%s" % [tier, ("  " + rtxt + " to claim") if rtxt != "" else ""]
			banner.visible = true
			bar.value = 0.0)
	tw.tween_property(bar, "value", float(p1[1]), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var waiting := Season.claimable().size()
	if steps.is_empty() and waiting > 0:
		bl.text = "%d season reward%s to claim" % [waiting, "" if waiting == 1 else "s"]
		banner.visible = true
	return box


## [step, fraction] on the season track for `x` XP: tiers 1-30 every XP_PER_TIER, then one step per
## bonus Pro Pack (Season.bonus_xp() each).
static func _season_pos(x: int) -> Array:
	var cap := Season.TIERS * Season.XP_PER_TIER
	if x < cap:
		return [x / Season.XP_PER_TIER, float(x % Season.XP_PER_TIER) / Season.XP_PER_TIER]
	var bonus := maxi(1, Season.bonus_xp())
	return [Season.TIERS + (x - cap) / bonus, float((x - cap) % bonus) / bonus]


static func _season_tier_label(step: int) -> String:
	return "TIER %d" % step if step <= Season.TIERS else "TIER 30 +%d" % (step - Season.TIERS)


## PROMOTED TO ...! with the promotion reward (coins, stars and a pack).
func _promotion_block() -> Control:
	var p := UITheme.tile_panel(Color(UITheme.GOLD, 0.85), 10, true)
	p.name = "PromotionReward"
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	hb.add_child(UITheme.icon_rect("crown", 34, UITheme.GOLD))
	var l := UITheme.label("PROMOTED TO %s!" % str(Profile.division().name).to_upper(), 30, UITheme.GOLD, UITheme.font_display())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var pr: Variant = result.get("promotion_reward", {})
	if typeof(pr) == TYPE_DICTIONARY and not (pr as Dictionary).is_empty():
		var rr := UITheme.reward_row(pr, UITheme.FS_BODY)
		rr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(rr)
	return p


## Endless milestones reached this game (every 5 innings), with their coins. Null when none.
func _milestones_row() -> Control:
	var ms: Array = result.get("milestones", [])
	if ms.is_empty():
		return null
	var p := UITheme.tile_panel(Color(UITheme.PURPLE, 0.7), 8, true)
	p.name = "Milestones"
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	hb.add_child(UITheme.icon_rect("wave", 28, UITheme.PURPLE.lightened(0.3)))
	var names: Array = ms.map(func(m: Variant) -> String: return str(int(m)))
	var l := UITheme.label("ENDLESS MILESTONE%s: INNING %s" % ["S" if ms.size() > 1 else "", ", ".join(names)], UITheme.FS_LEAD, UITheme.PURPLE.lightened(0.4), UITheme.font_display())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	if int(result.get("milestone_coins", 0)) > 0:
		hb.add_child(UITheme.reward_row({"coins": int(result.milestone_coins)}, UITheme.FS_BODY))
	return p


## Packs fly in, then OPEN PACKS.
func _packs_block() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var packs: Array = result.get("packs", [])
	box.add_child(UITheme.section_header("PACKS EARNED" if not packs.is_empty() else "NO PACKS THIS TIME", "gift", UITheme.GOLD, UITheme.FS_H3))
	var pack_row := HBoxContainer.new()
	pack_row.name = "PacksEarned"
	pack_row.add_theme_constant_override("separation", 10)
	box.add_child(pack_row)
	var i := 0
	var shown := mini(packs.size(), 6)
	for pk in packs.slice(0, shown):
		var art := PackArt.new(str(pk.type), str(pk.get("card", "")))
		art.custom_minimum_size = Vector2(62, 96)
		art.pivot_offset = Vector2(31, 48)
		art.modulate.a = 0.0
		art.scale = Vector2.ONE * 1.6
		art.rotation = deg_to_rad(-14.0 + 4.0 * i)
		art.tooltip_text = "%s — %s" % [DB.pack(str(pk.type)).get("name", pk.type), pk.get("source", "")]
		pack_row.add_child(art)
		var t := UITheme.bound_tween(art)
		t.tween_interval(T_PACKS + i * 0.18)
		t.tween_callback(func() -> void: Audio.play("card_draw", -2.0))
		t.set_parallel(true)
		t.tween_property(art, "modulate:a", 1.0, 0.2)
		t.tween_property(art, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t.tween_property(art, "rotation", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1
	if packs.size() > shown:
		var more := UITheme.label("+%d" % (packs.size() - shown), 34, UITheme.GOLD, UITheme.font_display())
		more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pack_row.add_child(_late(more, T_PACKS + shown * 0.18))
	if not packs.is_empty():
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pack_row.add_child(spacer)
		var open := UITheme.button("OPEN PACKS", "primary", 28, "gift", UITheme.GOLD.darkened(0.3))
		open.name = "OpenPacks"
		open.custom_minimum_size = Vector2(220, 56)
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void: Router.goto("packs"))
		pack_row.add_child(_late(open, T_PACKS + shown * 0.18 + 0.2))
	return box


## Big counter that counts up from 0 to `value` at `delay`, with coin ticks. Its tween is bound to
## its own panel and dies with it (the callbacks capture the panel and its label).
func _counter(icon: String, value: int, fmt: String, caption: String, col: Color, delay: float) -> Control:
	var p := UITheme.tile_panel(Color(col, 0.35), 10)
	p.name = "Counter_" + caption.replace(" ", "_")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var ic := UITheme.icon_rect(icon, 34, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -6)
	hb.add_child(vb)
	var l := UITheme.label(fmt % "0", 36, col, UITheme.font_display())
	l.name = "Value"
	vb.add_child(l)
	vb.add_child(UITheme.label(caption, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	p.modulate.a = 0.35
	var tw := UITheme.bound_tween(p)
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
		p.scale = Vector2(1.06, 1.06))
	tw.tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return p


## Fades a control in at `delay`.
func _late(c: Control, delay: float) -> Control:
	c.modulate.a = 0.0
	var tw := UITheme.bound_tween(c)
	tw.tween_interval(delay)
	tw.tween_property(c, "modulate:a", 1.0, UITheme.T_MED)
	return c


# ---------------------------------------------------------------- highlights

func _build_highlights() -> PanelContainer:
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
		cards.append(_highlight_card(UITheme.icon_rect("lightning", 40, UITheme.GOLD), "BIGGEST COMBO", cname,
			"%d outs in a row%s." % [mc, where], UITheme.GOLD))
	else:
		cards.append(_highlight_card(UITheme.icon_rect("lightning", 40, UITheme.MUTED), "BIGGEST COMBO", "NO COMBOS",
			"Get two outs in quick succession for a Double Play.", UITheme.MUTED))
	# 2. Best card play.
	var play: Dictionary = hl.get("best_play", {})
	if not play.is_empty() and DB.card(str(play.card)).has("name"):
		var c := DB.card(str(play.card))
		var art := TextureRect.new()
		art.texture = DB.card_texture(str(play.card))
		art.custom_minimum_size = Vector2(40, 40)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var col := DB.category_color(str(c.category))
		cards.append(_highlight_card(art, "BEST CARD PLAY", str(c.name).to_upper(),
			"%d out%s within %d seconds (inning %d)." % [int(play.outs), "" if int(play.outs) == 1 else "s", int(RunHighlights.PLAY_WINDOW), int(play.inning)], col.lightened(0.3)))
	else:
		var played := int(st.get("cards_played", 0))
		cards.append(_highlight_card(UITheme.icon_rect("deck", 40, UITheme.MUTED), "BEST CARD PLAY", "NO BIG PLAY" if played > 0 else "NO CARDS PLAYED",
			"Cards that lead to outs show up here." if played > 0 else "Play cards from your hand to swing the game.", UITheme.MUTED))
	# 3. MVP.
	var mvp: String = result.get("mvp", "")
	if mvp != "":
		var d := DB.defender(mvp)
		var outs := int(st.get("outs_by", {}).get(mvp, 0))
		var dmg := int(st.get("damage_by", {}).get(mvp, 0))
		var accent := Color(d.accent)
		cards.append(_highlight_card(MenuScreen.portrait_rect(mvp, 40, accent), "MVP", str(d.name).to_upper(),
			"%d outs · %s damage." % [outs, UITheme.format_int(dmg)], accent.lightened(0.3)))
	var j := 0
	for c in cards:
		hv.add_child(c)
		UITheme.animate_in(c, T_BODY + 0.5 + j * 0.25)
		j += 1
	# Dugout Draft boons taken this game.
	var boons: Array = Boons.summary(result.get("boons", []))
	if not boons.is_empty():
		var bv := VBoxContainer.new()
		bv.name = "BoonsTaken"
		bv.add_theme_constant_override("separation", 6)
		bv.add_child(UITheme.section_header("BOONS DRAFTED", "star", UITheme.GOLD, UITheme.FS_H3))
		for b in boons:
			bv.add_child(_boon_row(b))
		hv.add_child(_late(bv, T_BODY + 1.2))
	# Records and achievements.
	var extra: Array = []
	for rec in result.get("records", []):
		extra.append(["trophy", str(rec)])
	for aid in result.get("achievements", []):
		extra.append(["star", "Achievement: %s" % DB.achievements.get(aid, {}).get("name", str(aid))])
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
	var p := UITheme.tile_panel(DAILY_ACCENT, 12, true)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	head.add_child(UITheme.icon_rect("calendar", 26, DAILY_ACCENT.lightened(0.25)))
	var h := UITheme.label("DAILY CHALLENGE", 28, DAILY_ACCENT.lightened(0.25), UITheme.font_display())
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(h)
	if bool(d.get("new_best", false)):
		var nb := UITheme.badge("NEW BEST!", UITheme.GOLD.darkened(0.25), UITheme.FS_SMALL)
		nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(_late(nb, T_BODY + 1.0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	vb.add_child(row)
	var sc := VBoxContainer.new()
	sc.add_theme_constant_override("separation", -6)
	sc.add_child(UITheme.label(UITheme.format_int(int(d.get("score", 0))), 40, UITheme.GOLD, UITheme.font_display()))
	sc.add_child(UITheme.label("SCORE", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	row.add_child(sc)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", -6)
	bv.add_child(UITheme.label(UITheme.format_int(int(d.get("best", 0))), 40, UITheme.OFFWHITE, UITheme.font_display()))
	bv.add_child(UITheme.label("BEST TODAY", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	row.add_child(bv)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", -6)
	var streak := int(d.get("streak", 0))
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 4)
	var fi := UITheme.icon_rect("fire", 28, DAILY_ACCENT.lightened(0.2))
	fi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(fi)
	sh.add_child(UITheme.label("%d" % streak, 40, DAILY_ACCENT.lightened(0.2), UITheme.font_display()))
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
			var tw := UITheme.bound_tween(chip)
			tw.tween_interval(delay + 0.6 + k * 0.45)
			tw.tween_callback(func() -> void:
				Audio.play("achievement", -4.0)
				stars.set_filled(sa)
				plus.text = "★%d!" % sa
				plus.add_theme_color_override("font_color", UITheme.GOLD)
				if is_instance_valid(caption):
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
	var p := UITheme.tile_panel(Color(col, 0.4), 6)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
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
	var t := UITheme.label(title, 26, col, UITheme.font_display())
	t.clip_text = true
	vb.add_child(t)
	var c := UITheme.label(caption, UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body())
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(c)
	return p


# ---------------------------------------------------------------- buttons

func _build_buttons() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	var next := _build_next_steps()
	if next:
		col.add_child(next)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	col.add_child(buttons)
	var cfg0: Dictionary = battle.run.config if battle and battle.run else {}
	var is_daily: bool = cfg0.has("daily") or not (result.get("daily", {}) as Dictionary).is_empty()
	var again := UITheme.button("RETRY DAILY" if is_daily else "PLAY AGAIN", "primary", 32, "play", DAILY_ACCENT.darkened(0.15) if is_daily else Color(0, 0, 0, 0))
	again.name = "PlayAgain"
	again.custom_minimum_size = Vector2(300, 60)
	again.tooltip_text = "Same mode, difficulty, stadium and deck: %s · %s · %s" % [DB.mode(str(cfg0.get("mode", result.get("mode", "standard")))).get("name", ""),
		DB.difficulty(str(cfg0.get("difficulty", result.get("difficulty", "standard")))).get("name", ""), DB.arena(str(cfg0.get("arena", result.get("arena", "steel_yard")))).get("name", "")]
	if is_daily:
		again.tooltip_text = "Play today's Daily Challenge again: same rules, and your best score counts"
	again.pressed.connect(_play_again)
	buttons.add_child(again)
	_again = again
	var deck := UITheme.button("CARDS & DECK", "secondary", 28, "deck")
	deck.custom_minimum_size = Vector2(260, 60)
	deck.pressed.connect(func() -> void: Router.goto("deck_builder"))
	buttons.add_child(deck)
	var menu := UITheme.button("MAIN MENU", "secondary", 28, "back")
	menu.custom_minimum_size = Vector2(240, 60)
	menu.tooltip_text = "Back to the main menu (Esc)"
	menu.pressed.connect(func() -> void: Router.goto("main_menu"))
	buttons.add_child(menu)
	UITheme.animate_in(col, T_BODY + 0.4)
	return col


# ---------------------------------------------------------------- what's next

## "WHAT'S NEXT": up to three one-click suggestions (open packs, upgrade a ready card, a
## finished mission, the promotion challenge, today's Daily...), best first. Null when there is
## nothing to suggest.
func _build_next_steps() -> Control:
	var just_daily: bool = not (result.get("daily", {}) as Dictionary).is_empty()
	var list: Array = NextSteps.suggestions(just_daily).slice(0, 3)
	if list.is_empty():
		return null
	var row := HBoxContainer.new()
	row.name = "WhatsNext"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var cap := UITheme.label("WHAT'S NEXT", UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_header())
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	for sg in list:
		row.add_child(NextSteps.button(sg, 300.0))
	return row


## Esc leaves the results for the main menu (like the MAIN MENU button); a first direction key or
## d-pad press focuses PLAY AGAIN so the buttons can be used without a mouse.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		Audio.ui("ui_back")
		Router.goto("main_menu")
		return
	if MenuScreen.focus_on_nav(self, event, _again):
		get_viewport().set_input_as_handled()


## Starts the same game again: same mode, difficulty, stadium, deck, team, captain and
## formation (a new seed). Promotion Challenges go back to the Play screen, since the
## challenge depends on the current division.
func _play_again() -> void:
	if battle == null or battle.run == null:
		Router.goto("play_menu")
		return
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
	var accent := Color(DB.defender(id).get("accent", "#ffffff"))
	var p := UITheme.tile_panel(Color(accent, 0.45), 6)
	p.name = "Progress_" + id
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	p.add_child(hb)
	var pt := DB.portrait(id)
	if pt:
		var tr := TextureRect.new()
		tr.texture = pt
		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(tr)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 1)
	hb.add_child(vb)
	var top := HBoxContainer.new()
	vb.add_child(top)
	var nm := UITheme.label(DB.defender(id).get("name", id), UITheme.FS_BODY, accent.lightened(0.35), UITheme.font_header())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	top.add_child(nm)
	var lvl_l := UITheme.label("LV %d" % int(d.get("level_before", d.get("level", 1))), UITheme.FS_BODY, UITheme.GOLD, UITheme.font_display())
	top.add_child(lvl_l)
	var bar := UITheme.bar(accent.lightened(0.15), 10, 1.0, 0.0)
	var lb := int(d.get("level_before", d.get("level", 1)))
	var need0 := maxi(1, Profile.defender_xp_needed(lb))
	bar.value = clampf(float(d.get("xp_before", 0)) / need0, 0.0, 1.0)
	vb.add_child(bar)
	var info := UITheme.label("+%d XP" % int(d.get("xp", 0)) + ("  ·  %d outs" % int(d.outs) if int(d.get("outs", 0)) > 0 else ""), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	info.clip_text = true
	vb.add_child(info)
	var levels := int(d.get("levels", 0))
	var after := clampf(float(d.get("xp_after", 0)) / maxi(1, Profile.defender_xp_needed(int(d.get("level", 1)))), 0.0, 1.0)
	if int(d.get("level", 1)) >= DB.defender_max_level:
		after = 1.0
	var tw := UITheme.bound_tween(p)
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
	var p := UITheme.card_panel(Color(1, 1, 1, 0.12), 14)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	vb.add_child(UITheme.section_header(title, icon, UITheme.GOLD, UITheme.FS_H2))
	return p
