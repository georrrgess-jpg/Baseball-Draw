class_name MissionsPanel
extends VBoxContainer
## Mission UI (Update 6), three reusable layouts:
## * MissionsPanel.new()            the full panel for Progression → Missions: the "Learn the
##                                  ropes" chain, three daily missions with progress, rewards,
##                                  CLAIM and the free daily REROLL, and the weekly mission;
## * MissionsPanel.compact_widget() a small summary for the main menu that opens the full panel;
## * MissionsPanel.results_strip(r) "MISSION COMPLETE!" tiles on the Results screen, each
##                                  claimable on the spot (or today's progress when none finished).
## Claiming plays a short moment: the row flashes gold, the reward floats up, a sound and a toast.

signal mission_claimed(reward: Dictionary)

const TIER_COLORS := {0: Color("#3DDC84"), 1: Color("#2F7DE1"), 2: Color("#9B5DE5"), 3: Color("#F5B82E")}
const WEEKLY_COLOR := Color("#FF8A3D")

var _countdown: Label
var _week_countdown: Label
var _t := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	rebuild()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 1.0
	if _countdown and is_instance_valid(_countdown):
		_countdown.text = "New missions in %s" % DailyChallenge.countdown_text()
	if _week_countdown and is_instance_valid(_week_countdown):
		_week_countdown.text = "Resets in %s" % _long_countdown(Missions.seconds_to_next_week())


static func _long_countdown(secs: int) -> String:
	var d := secs / 86400
	if d > 0:
		return "%dd %dh" % [d, (secs % 86400) / 3600]
	return DailyChallenge.countdown_text(secs)


func rebuild() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	Missions.refresh()
	var s := Missions.state()
	if Missions.starter_active():
		add_child(_starter_block(s.starter))
	# Daily missions.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	var sh := UITheme.section_header("DAILY MISSIONS", "target", UITheme.GOLD, UITheme.FS_H2)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	_countdown = UITheme.label("New missions in %s" % DailyChallenge.countdown_text(), UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	_countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_countdown)
	var rl := Missions.rerolls_left()
	var rb := UITheme.badge("%d FREE REROLL%s" % [rl, "" if rl == 1 else "S"] if rl > 0 else "REROLL USED", Color(0.16, 0.36, 0.62) if rl > 0 else Color(0.2, 0.22, 0.28))
	rb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(rb)
	for i in s.daily.size():
		add_child(_row(s.daily[i], "daily", i))
	# Weekly mission.
	var wh := HBoxContainer.new()
	wh.add_theme_constant_override("separation", 14)
	add_child(wh)
	var wsh := UITheme.section_header("WEEKLY MISSION", "calendar", WEEKLY_COLOR.lightened(0.15), UITheme.FS_H2)
	wsh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wh.add_child(wsh)
	_week_countdown = UITheme.label("Resets in %s" % _long_countdown(Missions.seconds_to_next_week()), UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	_week_countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wh.add_child(_week_countdown)
	for i in s.weekly.size():
		add_child(_row(s.weekly[i], "weekly", i))
	var foot := UITheme.label("Missions completed: %s  ·  Progress counts in every game except Practice, and live during the game. Finished missions you forget to claim are paid out when they reset." % UITheme.format_int(int(s.completed)),
		UITheme.FS_MIN, UITheme.MUTED, UITheme.font_small())
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(foot)


# ---------------------------------------------------------------- rows

## One mission: tier pip, text, progress bar, reward and the action (CLAIM / REROLL / done).
func _row(inst: Dictionary, kind: String, index: int, show_reroll := true) -> PanelContainer:
	var col: Color = WEEKLY_COLOR if kind == "weekly" else TIER_COLORS.get(int(inst.tier), UITheme.BLUE)
	var claimable := Missions.can_claim(inst)
	var claimed := bool(inst.claimed)
	var p := UITheme.tile_panel(Color(UITheme.GOLD, 0.9) if claimable else Color(col, 0.45 if not claimed else 0.15), 12, claimable)
	p.name = "Mission_%s_%d" % [kind, index]
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	p.add_child(hb)
	var pip := PanelContainer.new()
	pip.add_theme_stylebox_override("panel", UITheme.panel_style(Color(col, 0.22), Color(col, 0.8), 2, 26, 6))
	pip.custom_minimum_size = Vector2(52, 52)
	pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pic := UITheme.icon_rect("check" if claimed else ("calendar" if kind == "weekly" else "target"), 30, UITheme.GREEN if claimed else col.lightened(0.25))
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pip.add_child(pic)
	hb.add_child(pip)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hb.add_child(info)
	var tl := UITheme.label(Missions.text(inst), UITheme.FS_LEAD, UITheme.MUTED if claimed else UITheme.OFFWHITE, UITheme.font_header())
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(tl)
	var br := HBoxContainer.new()
	br.add_theme_constant_override("separation", 10)
	info.add_child(br)
	var bar := UITheme.bar(UITheme.GOLD if Missions.is_done(inst) else col, 12, float(inst.goal), float(inst.progress))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	br.add_child(bar)
	var prog := "DONE" if Missions.is_done(inst) else "%s / %s" % [UITheme.format_int(int(inst.progress)), UITheme.format_int(int(inst.goal))]
	if bool(inst.get("max", false)) and not Missions.is_done(inst):
		prog = "best %d / %d" % [int(inst.progress), int(inst.goal)]
	br.add_child(UITheme.label(prog, UITheme.FS_SMALL, UITheme.GOLD if Missions.is_done(inst) else UITheme.MUTED, UITheme.font_body_bold()))
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 0)
	rbox.custom_minimum_size = Vector2(200, 0)
	rbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rbox.add_child(UITheme.label("REWARD", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	var rw := reward_chips(Missions.reward(inst), 26)
	rw.name = "Reward"
	rbox.add_child(rw)
	hb.add_child(rbox)
	var act: Control
	if claimed:
		act = UITheme.badge("CLAIMED", Color(0.13, 0.45, 0.28), UITheme.FS_SMALL)
	elif claimable:
		var b := UITheme.button("CLAIM", "primary", UITheme.FS_LEAD, "gift", UITheme.GOLD.darkened(0.25))
		b.name = "ClaimButton"
		b.custom_minimum_size = Vector2(150, UITheme.BTN_H)
		b.pressed.connect(func() -> void: _claim(kind, index, p, rw))
		var pulse := b.create_tween().set_loops()
		pulse.tween_property(b, "self_modulate", Color(1.25, 1.15, 0.9), 0.7).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(b, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
		act = b
	elif kind == "daily" and show_reroll and Missions.can_reroll(index):
		var b := UITheme.button("REROLL", "secondary", UITheme.FS_BODY, "swap")
		b.name = "RerollButton"
		b.custom_minimum_size = Vector2(150, UITheme.BTN_H_SMALL)
		b.tooltip_text = "Swap this mission for another of the same tier (one free reroll per day)"
		b.pressed.connect(func() -> void:
			if Missions.reroll(index):
				Audio.ui("ui_confirm")
				rebuild())
		act = b
	else:
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(150, 0)
		act = sp
	act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(act)
	return p


## "Learn the ropes": the starter chain as five dots plus the current step.
func _starter_block(inst: Dictionary) -> Control:
	var steps := Missions.starter_steps()
	var step := int(inst.get("step", 0))
	var p := UITheme.card_panel(Color(UITheme.GREEN, 0.6), 16, Color(0.03, 0.1, 0.07, 0.92), 2)
	p.name = "StarterChain"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	vb.add_child(head)
	var sh := UITheme.section_header("LEARN THE ROPES", "info", UITheme.GREEN, UITheme.FS_H2)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	head.add_child(UITheme.label("STEP %d OF %d" % [step + 1, steps.size()], UITheme.FS_SMALL, UITheme.GREEN, UITheme.font_body_bold()))
	var chain := HBoxContainer.new()
	chain.add_theme_constant_override("separation", 6)
	vb.add_child(chain)
	for i in steps.size():
		var done := i < step
		var cur := i == step
		var dot := PanelContainer.new()
		dot.add_theme_stylebox_override("panel", UITheme.panel_style(Color(UITheme.GREEN, 0.85) if done else (Color(UITheme.GREEN, 0.25) if cur else Color(0.08, 0.1, 0.16, 0.95)),
			UITheme.GOLD if cur else Color(1, 1, 1, 0.15), 2, 8, 6))
		dot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dot.tooltip_text = "%s — %s" % [str(steps[i].text), Missions.reward_text(steps[i].get("reward", {}))]
		var dl := UITheme.label(("✓ " if done else "%d. " % (i + 1)) + str(steps[i].text), UITheme.FS_MIN, Color.WHITE if (done or cur) else UITheme.MUTED, UITheme.font_body_bold())
		dl.clip_text = true
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dot.add_child(dl)
		chain.add_child(dot)
	vb.add_child(_row(inst, "starter", 0, false))
	var h := Missions.hint(inst)
	if h != "":
		vb.add_child(UITheme.label("Tip: " + h, UITheme.FS_SMALL, Color(0.75, 0.95, 0.82), UITheme.font_body_bold()))
	return p


## Reward icons with amounts (coins, a pack, stars).
static func reward_chips(r: Dictionary, size := 22) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.tooltip_text = "Reward: " + Missions.reward_text(r)
	if int(r.get("coins", 0)) > 0:
		hb.add_child(_chip("coin", UITheme.format_int(int(r.coins)), UITheme.GOLD, size))
	if str(r.get("pack", "")) != "":
		var pk := str(r.pack)
		var col := Color(str(DB.pack(pk).get("color", "#2F7BE0"))).lightened(0.35)
		hb.add_child(_chip("gift", str(DB.pack(pk).get("name", pk)).replace(" Pack", "").to_upper(), col, size))
	if int(r.get("stars", 0)) > 0:
		hb.add_child(_chip("star", str(int(r.stars)), UITheme.STAR, size))
	return hb


static func _chip(icon: String, text: String, col: Color, size: int) -> HBoxContainer:
	var c := HBoxContainer.new()
	c.add_theme_constant_override("separation", 4)
	c.add_child(UITheme.icon_rect(icon, size, col))
	c.add_child(UITheme.label(text, size - 2, col, UITheme.font_header()))
	return c


# ---------------------------------------------------------------- claim moment

func _claim(kind: String, index: int, row: Control, reward_box: Control) -> void:
	var r := Missions.claim(kind, index)
	if r.is_empty():
		return
	claim_fx(row, reward_box, r)
	mission_claimed.emit(r)
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		if is_inside_tree():
			rebuild())


## The claim moment, shared by every layout: the row flashes gold, each reward floats up
## out of its chip, a chime plays and a toast lists what was added.
static func claim_fx(row: Control, reward_box: Control, r: Dictionary) -> void:
	Audio.play("achievement", -3.0)
	Audio.play("coin", -6.0)
	var tw := row.create_tween()
	tw.tween_property(row, "modulate", Color(1.6, 1.4, 0.8), 0.08)
	tw.tween_property(row, "modulate", Color.WHITE, 0.45).set_trans(Tween.TRANS_QUAD)
	row.pivot_offset = row.size * 0.5
	var st := row.create_tween()
	st.tween_property(row, "scale", Vector2(1.03, 1.03), 0.1).set_trans(Tween.TRANS_BACK)
	st.tween_property(row, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_QUAD)
	var top := row.get_tree().root
	var origin := reward_box.get_global_rect().get_center() if reward_box and reward_box.is_inside_tree() else row.get_global_rect().get_center()
	var items: Array = []
	if int(r.get("coins", 0)) > 0:
		items.append(["coin", "+%s" % UITheme.format_int(int(r.coins)), UITheme.GOLD])
	if str(r.get("pack", "")) != "":
		items.append(["gift", "+1 " + str(DB.pack(str(r.pack)).get("name", r.pack)), Color(str(DB.pack(str(r.pack)).get("accent", "#FFFFFF")))])
	if int(r.get("stars", 0)) > 0:
		items.append(["star", "+%d" % int(r.stars), UITheme.STAR])
	var layer := CanvasLayer.new()
	layer.layer = 90
	top.add_child(layer)
	var k := 0
	for it in items:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(UITheme.icon_rect(it[0], 34, it[2]))
		var l := UITheme.label(it[1], 34, it[2], UITheme.font_display())
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		hb.add_child(l)
		layer.add_child(hb)
		hb.position = origin + Vector2(-60 + k * 30, -20 - k * 8)
		hb.modulate.a = 0.0
		var ft := hb.create_tween()
		ft.tween_interval(k * 0.12)
		ft.set_parallel(true)
		ft.tween_property(hb, "modulate:a", 1.0, 0.12)
		ft.tween_property(hb, "position:y", hb.position.y - 90.0, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ft.chain().tween_property(hb, "modulate:a", 0.0, 0.3)
		k += 1
	layer.get_tree().create_timer(1.8, true, false, true).timeout.connect(layer.queue_free)
	Router.toast("Mission reward: %s" % Missions.reward_text(r), "achievement")


# ---------------------------------------------------------------- compact (main menu)

## Main menu summary: the three daily missions (or the current starter step first) with
## progress, a badge when something can be claimed, and a button to the full panel.
static func compact_widget() -> PanelContainer:
	Missions.refresh()
	var claimable := Missions.claimable_count()
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.8) if claimable > 0 else Color(UITheme.BLUE, 0.45), 14, Color(0.04, 0.07, 0.12, 0.88), 2 if claimable > 0 else 1)
	p.name = "MissionsWidget"
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	head.add_child(UITheme.icon_rect("target", 28, UITheme.GOLD))
	var hl := UITheme.label("MISSIONS", 26, UITheme.GOLD, UITheme.font_display())
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hl)
	if claimable > 0:
		head.add_child(UITheme.badge("%d TO CLAIM" % claimable, UITheme.GOLD.darkened(0.35)))
	var b := UITheme.button("OPEN", "secondary", UITheme.FS_SMALL, "", UITheme.GOLD)
	b.name = "MissionsButton"
	b.custom_minimum_size = Vector2(90, 36)
	b.tooltip_text = "Progression → Missions"
	b.pressed.connect(func() -> void:
		Session.menu_tab = "missions"
		Router.goto("progression"))
	head.add_child(b)
	var list: Array = []
	if Missions.starter_active():
		list.append(Missions.state().starter)
	list.append_array(Missions.state().daily)
	for inst in list.slice(0, 3):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var done := Missions.is_done(inst)
		row.add_child(UITheme.icon_rect("check" if bool(inst.claimed) else ("gift" if done else "target"), 18,
			UITheme.GREEN if bool(inst.claimed) else (UITheme.GOLD if done else UITheme.MUTED)))
		var t := UITheme.label(("NEW MANAGER: " if inst.kind == "starter" else "") + Missions.text(inst), UITheme.FS_MIN, UITheme.MUTED if bool(inst.claimed) else UITheme.OFFWHITE, UITheme.font_body_bold())
		t.clip_text = true
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(t)
		row.add_child(UITheme.label("CLAIM!" if done and not bool(inst.claimed) else ("%d/%d" % [int(inst.progress), int(inst.goal)]),
			UITheme.FS_MIN, UITheme.GOLD if done else UITheme.MUTED, UITheme.font_body_bold()))
		vb.add_child(row)
	return p


# ---------------------------------------------------------------- results

## Results screen block: a FIRST WIN BONUS line, then a "MISSION COMPLETE!" tile per mission
## this game finished (claim right there), or today's mission progress when none finished.
static func results_strip(result: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "MissionsResults"
	box.add_theme_constant_override("separation", 8)
	box.add_child(UITheme.section_header("MISSIONS", "target", UITheme.GOLD, UITheme.FS_H3))
	if bool(result.get("first_win", false)):
		var fw := UITheme.tile_panel(Color(UITheme.GREEN, 0.8), 10, true)
		var fh := HBoxContainer.new()
		fh.add_theme_constant_override("separation", 10)
		fw.add_child(fh)
		fh.add_child(UITheme.icon_rect("trophy", 30, UITheme.GREEN))
		var fl := UITheme.label("FIRST WIN BONUS!", 26, UITheme.GREEN, UITheme.font_display())
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fh.add_child(fl)
		fh.add_child(reward_chips({"coins": int(result.get("first_win_coins", 0)), "pack": Rewards.FIRST_WIN_PACK}, 20))
		box.add_child(fw)
	var fresh: Array = result.get("missions", [])
	if fresh.is_empty():
		Missions.refresh()
		var list: Array = []
		if Missions.starter_active():
			list.append(Missions.state().starter)
		list.append_array(Missions.state().daily)
		for inst in list.slice(0, 3):
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			var t := UITheme.label(Missions.text(inst), UITheme.FS_SMALL, UITheme.MUTED if bool(inst.claimed) else UITheme.OFFWHITE, UITheme.font_body_bold())
			t.clip_text = true
			t.custom_minimum_size = Vector2(260, 0)
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(t)
			var bar := UITheme.bar(UITheme.GOLD if Missions.is_done(inst) else UITheme.BLUE, 10, float(inst.goal), float(inst.progress))
			bar.custom_minimum_size = Vector2(140, 10)
			bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(bar)
			row.add_child(UITheme.label("%d/%d" % [int(inst.progress), int(inst.goal)], UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
			box.add_child(row)
		return box
	for f in fresh:
		box.add_child(_complete_tile(f))
	return box


static func _complete_tile(f: Dictionary) -> PanelContainer:
	var p := UITheme.tile_panel(Color(UITheme.GOLD, 0.9), 10, true)
	p.name = "MissionComplete_%s" % str(f.id)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	hb.add_child(UITheme.icon_rect("target", 34, UITheme.GOLD))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(v)
	v.add_child(UITheme.label("MISSION COMPLETE!", 26, UITheme.GOLD, UITheme.font_display()))
	var tl := UITheme.label(str(f.text), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_body_bold())
	tl.clip_text = true
	v.add_child(tl)
	var rw := reward_chips(f.get("reward", {}), 20)
	rw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(rw)
	var found := Missions.find(str(f.kind), str(f.id))
	var inst: Dictionary = found[1]
	if Missions.can_claim(inst):
		var b := UITheme.button("CLAIM", "primary", UITheme.FS_BODY, "gift", UITheme.GOLD.darkened(0.25))
		b.name = "ClaimButton"
		b.custom_minimum_size = Vector2(130, UITheme.BTN_H_SMALL)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(func() -> void:
			var again := Missions.find(str(f.kind), str(f.id))
			var r := Missions.claim(str(f.kind), int(again[0]))
			if r.is_empty():
				return
			claim_fx(p, rw, r)
			var done := UITheme.badge("CLAIMED", Color(0.13, 0.45, 0.28), UITheme.FS_SMALL)
			done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			hb.add_child(done)
			b.queue_free())
		hb.add_child(b)
	elif bool(inst.get("claimed", false)) or inst.is_empty():
		var done := UITheme.badge("CLAIMED", Color(0.13, 0.45, 0.28), UITheme.FS_SMALL)
		done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(done)
	return p
