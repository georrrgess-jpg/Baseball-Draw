class_name TeamCompare
extends Control
## Defender comparison overlay (Team screen): two defenders side by side, like CardCompare in Cards & Deck.
## Each side shows the portrait, level, team status (starting six / bench / locked), trait, role and
## position bonus, signature card and the TeamAI score. The middle table lists every stat at the current
## level with bars (green = better, red = worse) and a one-line verdict. CHANGE opens a picker with every
## defender (locked ones shown as locked); "PUT X IN FOR Y" swaps a bench player into the starting six in
## the other one's place (and captaincy), keeping the team rules.
## Esc (via the host's overlay stack: the picker first, then the panel), CLOSE or a click on the dim
## background closes it.

signal closed
signal team_changed

const SIDE_W := 330.0
const LABEL_W := 200.0
const BAR_W := 150.0

var ids: Array = ["", ""]
var mode := "balanced"
var host: MenuScreen
var picker: Control           # the open CHANGE picker, or null
var picker_side := -1
var _panel: PanelContainer
var _body: HBoxContainer
var _verdict: Label
var _closing := false
## Buttons by name for focus and tests: "Change0", "Change1", "PutIn0", "PutIn1", "Close".
var buttons := {}


func _init(a := "", b := "", menu: MenuScreen = null, ai_mode := "balanced") -> void:
	ids = [a, b]
	host = menu
	mode = ai_mode if ai_mode in TeamAI.MODES else "balanced"
	name = "TeamCompare"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 40


func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Audio.ui("ui_back")
			close())
	add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	_panel = UITheme.card_panel(Color(UITheme.GOLD, 0.6), 22, Color(0.04, 0.065, 0.11, 0.98), 2)
	_panel.custom_minimum_size = Vector2(1460, 0)
	cc.add_child(_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	vb.add_child(head)
	var sh := UITheme.section_header("COMPARE DEFENDERS", "swap", UITheme.GOLD, UITheme.FS_H2)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	var ml := UITheme.label("Score style: %s" % TeamAI.MODE_NAMES[mode], UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	ml.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ml.tooltip_text = TeamAI.MODE_TEXT[mode]
	ml.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(ml)
	var close_b := UITheme.button("CLOSE", "secondary", UITheme.FS_BODY)
	close_b.name = "Close"
	close_b.tooltip_text = "Close (Esc)"
	close_b.pressed.connect(close)
	head.add_child(close_b)
	buttons["Close"] = close_b
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 20)
	vb.add_child(_body)
	_verdict = UITheme.label("", UITheme.FS_LEAD, UITheme.GOLD, UITheme.font_header())
	_verdict.name = "Verdict"
	_verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_verdict)
	var foot := UITheme.label("CHANGE picks any defender for a side.  ·  PUT IN swaps a bench player into the starting six.  ·  Esc closes.",
		UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(foot)
	_rebuild()
	UITheme.animate_in(_panel, 0.0, 0.94)
	_focus_default.call_deferred()


## Replaces one side (0 = left, 1 = right) and redraws.
func set_side(side: int, id: String) -> void:
	if not DB.defenders.has(id):
		return
	ids[clampi(side, 0, 1)] = id
	if is_inside_tree():
		_rebuild()


func close() -> void:
	if _closing:
		return
	_closing = true
	if picker and is_instance_valid(picker):
		picker.queue_free()
	closed.emit()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, UITheme.T_FAST)
	tw.tween_callback(queue_free)


## Keyboard / controller: arrows and Tab move only between this panel's buttons (or the picker's while
## it is open), never to the Team screen behind it.
func _input(event: InputEvent) -> void:
	if _closing or not is_visible_in_tree():
		return
	var root: Control = picker if picker and is_instance_valid(picker) and not picker.is_queued_for_deletion() else self
	if trap_focus(root, event):
		get_viewport().set_input_as_handled()
		if root == self and get_viewport().gui_get_focus_owner() == null:
			_focus_default()


## Keeps keyboard focus inside `root` (a popup): returns true when the event would have moved focus
## out of it (the caller then marks it handled). With nothing focused inside, focuses the first
## focusable control in it.
static func trap_focus(root: Control, event: InputEvent) -> bool:
	if root == null or not root.is_inside_tree():
		return false
	var nav := ""
	for a in ["ui_left", "ui_right", "ui_up", "ui_down", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action_pressed(a, true):
			nav = a
			break
	if nav == "":
		return false
	var fo := root.get_viewport().gui_get_focus_owner()
	if fo == null or not root.is_ancestor_of(fo):
		var first := _first_focusable(root)
		if first:
			first.grab_focus()
		return true
	# Godot's own neighbour search also sees the screen behind the popup, so the popup moves focus
	# itself: Tab in tree order (wrapping), arrows to the nearest control in that direction.
	var all: Array = []
	_focusables(root, all)
	var i := all.find(fo)
	if nav == "ui_focus_next" or nav == "ui_focus_prev":
		if all.size() > 1:
			(all[(i + (1 if nav == "ui_focus_next" else -1) + all.size()) % all.size()] as Control).grab_focus()
		return true
	var dir: Vector2 = {"ui_left": Vector2.LEFT, "ui_right": Vector2.RIGHT, "ui_up": Vector2.UP, "ui_down": Vector2.DOWN}[nav]
	var from := fo.get_global_rect()
	var best: Control = null
	var best_d := INF
	for c: Control in all:
		if c == fo:
			continue
		var r := c.get_global_rect()
		var d := r.get_center() - from.get_center()
		# Only controls past the current one in that direction.
		var along := d.dot(dir)
		var edge := (from.size.x + r.size.x) * 0.25 if dir.x != 0.0 else (from.size.y + r.size.y) * 0.25
		if along < edge:
			continue
		var score := along + absf(d.dot(Vector2(-dir.y, dir.x))) * 2.0
		if score < best_d:
			best_d = score
			best = c
	if best:
		best.grab_focus()
	return true


static func _focusables(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			if (c as Control).focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
				out.append(c)
			_focusables(c, out)


static func _first_focusable(n: Node) -> Control:
	var all: Array = []
	_focusables(n, all)
	return all[0] if not all.is_empty() else null


func _focus_default() -> void:
	for k in ["PutIn0", "PutIn1", "Change1", "Close"]:
		var b: Button = buttons.get(k)
		if b and is_instance_valid(b) and b.is_visible_in_tree() and not b.disabled:
			b.grab_focus()
			return


# ================================================================ layout

func _rebuild() -> void:
	var had: String = ""
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	for k in buttons:
		if buttons[k] == f:
			had = k
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	for k in ["Change0", "Change1", "PutIn0", "PutIn1"]:
		buttons.erase(k)
	var ctx := TeamAI.profile_context()
	_body.add_child(_side(0, ctx))
	_body.add_child(_table(ctx))
	_body.add_child(_side(1, ctx))
	_verdict.text = TeamAI.verdict(ids[0], ids[1], ctx, mode)
	if had != "":
		var b: Button = buttons.get(had)
		if b and not b.disabled:
			b.grab_focus.call_deferred()
		else:
			_focus_default.call_deferred()


## "Account level 15 or sign for 5,000 coins" (the Team screen's wording).
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


func _status(id: String) -> String:
	if not Profile.is_defender_unlocked(id):
		return "locked"
	if id in Profile.data.team:
		return "captain" if id == Profile.data.captain else "team"
	return "bench"


func _side(side: int, ctx: Dictionary) -> Control:
	var id: String = ids[side]
	var other: String = ids[1 - side]
	var d := DB.defender(id)
	var accent := DB.defender_accent(id)
	var st := _status(id)
	var vb := VBoxContainer.new()
	vb.name = "Side%d" % side
	vb.custom_minimum_size = Vector2(SIDE_W, 0)
	vb.add_theme_constant_override("separation", 6)
	var pr := MenuScreen.portrait_rect(id, 150, accent if st != "locked" else Color(0.3, 0.3, 0.36))
	pr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if st == "locked":
		pr.modulate = Color(0.4, 0.4, 0.48)
	vb.add_child(pr)
	var nm := UITheme.title(str(d.name).to_upper(), 44, accent.lightened(0.25) if st != "locked" else UITheme.MUTED)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var sub := UITheme.label("Lv %d  ·  %s  ·  #%d" % [Profile.defender_level(id), DB.roles[d.role].name, int(d.number)],
		UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_header())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var badge_text: String = {"captain": "CAPTAIN · STARTING SIX", "team": "STARTING SIX", "bench": "BENCH", "locked": "LOCKED"}[st]
	var badge_col: Color = {"captain": UITheme.GOLD.darkened(0.25), "team": UITheme.SCARLET, "bench": Color(0.25, 0.32, 0.45), "locked": Color(0.3, 0.3, 0.36)}[st]
	var bd := UITheme.badge(badge_text, badge_col, UITheme.FS_MIN)
	bd.name = "Status"
	bd.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(bd)
	if st == "locked":
		var ll := UITheme.label("Locked: " + unlock_text(id), UITheme.FS_MIN, UITheme.SCARLET, UITheme.font_body_bold())
		ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(ll)
	vb.add_child(UITheme.hsep())
	var tl := UITheme.label("%s: %s" % [d.trait.name, d.trait.text], UITheme.FS_MIN, Color(0.85, 0.9, 1.0))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tl)
	var pl := UITheme.label("Position bonus: " + str(DB.roles[d.role].bonus_text), UITheme.FS_MIN, UITheme.GREEN)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(pl)
	var sig := str(d.signature)
	var sig_state := "in your deck" if sig in Profile.data.deck else ("owned" if Profile.is_card_owned(sig) else "not collected")
	var sl := UITheme.label("Signature: %s (%s)" % [DB.card(sig).name, sig_state], UITheme.FS_MIN, UITheme.GOLD, UITheme.font_body_bold())
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sl)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(sp)
	# PUT X IN FOR Y: this side is an unlocked bench player and the other side is in the starting six.
	var ost := _status(other)
	if st == "bench" and (ost == "team" or ost == "captain"):
		var pb := UITheme.button("PUT %s IN FOR %s" % [str(d.name).to_upper(), str(DB.defender(other).name).to_upper()], "primary", UITheme.FS_SMALL, "swap", UITheme.GREEN.darkened(0.3))
		pb.name = "PutIn%d" % side
		pb.tooltip_text = "%s takes %s's place in the starting six%s." % [d.name, DB.defender(other).name, " and the captaincy" if ost == "captain" else ""]
		pb.pressed.connect(func() -> void: put_in(side))
		vb.add_child(pb)
		buttons[pb.name] = pb
	var chg := UITheme.button("CHANGE", "secondary", UITheme.FS_BODY, "swap")
	chg.name = "Change%d" % side
	chg.tooltip_text = "Pick another defender for this side"
	chg.pressed.connect(func() -> void: open_picker(side))
	vb.add_child(chg)
	buttons[chg.name] = chg
	return vb


func _table(ctx: Dictionary) -> Control:
	var a: String = ids[0]
	var b: String = ids[1]
	# Stats at the current level with permanent modifiers (level, gear, traits), like the Team screen's
	# stat grid; the position bonus is listed on each side.
	var ra := TeamAI.rate(a, ctx, mode, false)
	var rb := TeamAI.rate(b, ctx, mode, false)
	var sa := TeamAI.defender_score(a, ctx, mode)
	var sb := TeamAI.defender_score(b, ctx, mode)
	var pa := Profile.defender_mods(a)
	var pb := Profile.defender_mods(b)
	var tsa := float(DB.defender(a).stats.throw_speed) * (1.0 + float(pa.throw_speed))
	var tsb := float(DB.defender(b).stats.throw_speed) * (1.0 + float(pb.throw_speed))
	var vb := VBoxContainer.new()
	vb.name = "Table"
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 3)
	# [label, text a, text b, num a, num b, higher is better (1, -1, 0)]
	var rows: Array = [
		["Level", "%d / %d" % [int(ra.level), DB.defender_max_level], "%d / %d" % [int(rb.level), DB.defender_max_level], float(ra.level), float(rb.level), 1],
		["Damage", "%d" % int(ra.damage), "%d" % int(rb.damage), float(ra.damage), float(rb.damage), 1],
		["Throw interval", "%.2fs" % float(ra.interval), "%.2fs" % float(rb.interval), float(ra.interval), float(rb.interval), -1],
		["Range", "%.1f m" % float(ra.range), "%.1f m" % float(rb.range), float(ra.range), float(rb.range), 1],
		["Throw speed", "%d m/s" % int(tsa), "%d m/s" % int(tsb), tsa, tsb, 1],
		["Accuracy", "%d" % int(ra.accuracy), "%d" % int(rb.accuracy), float(ra.accuracy), float(rb.accuracy), 1],
		["Crit chance", "%d%%" % int(round(float(ra.crit) * 100)), "%d%%" % int(round(float(rb.crit) * 100)), float(ra.crit), float(rb.crit), 1],
		["Damage / second", "%.0f" % float(ra.eff), "%.0f" % float(rb.eff), float(ra.eff), float(rb.eff), 1],
		["Vs bosses", "%.0f" % float(ra.boss_v), "%.0f" % float(rb.boss_v), float(ra.boss_v), float(rb.boss_v), 1],
		["Vs crowds", "%.0f" % float(ra.crowd_v), "%.0f" % float(rb.crowd_v), float(ra.crowd_v), float(rb.crowd_v), 1],
		["Control", "%.0f" % float(ra.control), "%.0f" % float(rb.control), float(ra.control), float(rb.control), 1],
		["Team boost", "+%d%%" % int(round((float(ra.amp) + float(ra.amp_boss)) * 100)), "+%d%%" % int(round((float(rb.amp) + float(rb.amp_boss)) * 100)),
			float(ra.amp) + float(ra.amp_boss), float(rb.amp) + float(rb.amp_boss), 1],
		["TeamAI score", "%.1f" % sa, "%.1f" % sb, sa, sb, 1],
	]
	for i in rows.size():
		vb.add_child(_row(rows[i], i))
	var legend := UITheme.label("Green = better, red = worse.  Stats at the current level with gear and training traits.  Vs bosses / crowds: TeamAI's estimates in damage per second, team boosts included.",
		UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(legend)
	return vb


func _row(r: Array, i: int) -> Control:
	var p := PanelContainer.new()
	p.name = "Row_" + str(r[0])
	var st := UITheme.panel_style(Color(1, 1, 1, 0.045 if i % 2 == 0 else 0.0), Color(0, 0, 0, 0), 0, 6, 0)
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	st.content_margin_left = 10
	st.content_margin_right = 10
	p.add_theme_stylebox_override("panel", st)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	p.add_child(hb)
	var dir := int(r[5])
	var va := float(r[3])
	var vb := float(r[4])
	var win := 0   # 1 = left better, 2 = right better
	if dir != 0 and absf(va - vb) > 0.001:
		win = 1 if (va - vb) * dir > 0.0 else 2
	# Bar length: share of the larger value (for lower-is-better rows, of the smaller value's inverse).
	var fa := 0.0
	var fb := 0.0
	if dir > 0:
		var m := maxf(maxf(absf(va), absf(vb)), 0.0001)
		fa = va / m
		fb = vb / m
	elif dir < 0:
		var mn := minf(va, vb)
		fa = mn / maxf(va, 0.0001)
		fb = mn / maxf(vb, 0.0001)
	hb.add_child(_cell(str(r[1]), fa, win, 1, true))
	var lab := UITheme.label(str(r[0]).to_upper(), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	lab.custom_minimum_size = Vector2(LABEL_W, 0)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(lab)
	hb.add_child(_cell(str(r[2]), fb, win, 2, false))
	if win != 0:
		p.set_meta("better", "left" if win == 1 else "right")
	return p


## A value with its bar: green when this side is better, red when worse, grey on a tie.
func _cell(text: String, frac: float, win: int, me: int, left: bool) -> Control:
	var hb := HBoxContainer.new()
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.alignment = BoxContainer.ALIGNMENT_END if left else BoxContainer.ALIGNMENT_BEGIN
	hb.add_theme_constant_override("separation", 10)
	var col := UITheme.OFFWHITE
	var bar_col := Color(1, 1, 1, 0.3)
	if win == me:
		col = UITheme.GREEN
		bar_col = UITheme.GREEN
	elif win != 0:
		col = Color(1.0, 0.55, 0.5)
		bar_col = Color(UITheme.SCARLET, 0.85)
	var v := UITheme.label(text, UITheme.FS_BODY, col, UITheme.font_body_bold())
	v.custom_minimum_size = Vector2(92, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if left else HORIZONTAL_ALIGNMENT_LEFT
	var track := Control.new()
	track.custom_minimum_size = Vector2(BAR_W, 12)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.4)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(bg)
	var fill := ColorRect.new()
	fill.name = "Bar"
	fill.color = bar_col
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := BAR_W * clampf(frac, 0.0, 1.0)
	fill.size = Vector2(w, 12)
	fill.position = Vector2(BAR_W - w if left else 0.0, 0)
	track.add_child(fill)
	if left:
		hb.add_child(track)
		hb.add_child(v)
	else:
		hb.add_child(v)
		hb.add_child(track)
	return hb


# ================================================================ actions

## Puts the defender on `side` into the starting six in place of the other side's defender.
func put_in(side: int) -> bool:
	var incoming: String = ids[side]
	var outgoing: String = ids[1 - side]
	var unlocked: Array = []
	for id in DB.defender_order:
		if Profile.is_defender_unlocked(id):
			unlocked.append(id)
	var r := TeamAI.swap_in(Profile.data.team, str(Profile.data.captain), incoming, outgoing, unlocked)
	if r.is_empty():
		Audio.ui("ui_error")
		return false
	Profile.set_team(r.team, r.captain)
	Audio.ui("ui_confirm")
	Router.toast("%s is in for %s." % [DB.defender(incoming).name, DB.defender(outgoing).name], "info")
	team_changed.emit()
	_rebuild()
	return true


## CHANGE: a grid of every defender (locked ones dimmed with a lock). Picking one replaces the side.
func open_picker(side: int) -> void:
	if picker and is_instance_valid(picker):
		picker.queue_free()
	picker_side = side
	var shade := ColorRect.new()
	shade.name = "DefenderPicker"
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Audio.ui("ui_back")
			shade.queue_free())
	add_child(shade)
	picker = shade
	shade.tree_exiting.connect(func() -> void:
		if picker == shade:
			picker = null
			picker_side = -1
			if not _closing and is_inside_tree():
				var b: Button = buttons.get("Change%d" % side)
				if b and is_instance_valid(b):
					b.grab_focus.call_deferred())
	if host:
		host.push_overlay(shade)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.add_child(cc)
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.7), 20, Color(0.04, 0.065, 0.11, 0.99), 2)
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("PICK A DEFENDER FOR THE %s SIDE" % ("LEFT" if side == 0 else "RIGHT"), "roster", UITheme.GOLD, UITheme.FS_H3))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vb.add_child(grid)
	var first: Button = null
	for id in DB.defender_order:
		var b := _pick_tile(id, side)
		grid.add_child(b)
		if id == ids[side] or (first == null and not b.disabled):
			first = b
	var foot := UITheme.label("Locked defenders can be compared too.  ·  Esc goes back.", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(foot)
	if first:
		first.grab_focus.call_deferred()
	Audio.ui("ui_tab")


func _pick_tile(id: String, side: int) -> Button:
	var d := DB.defender(id)
	var st := _status(id)
	var accent := DB.defender_accent(id)
	var b := Button.new()
	b.name = "Pick_" + id
	b.custom_minimum_size = Vector2(150, 150)
	b.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.95), Color(accent, 0.35) if st != "locked" else Color(1, 1, 1, 0.07), 1, 10, 4))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0.1, 0.14, 0.22, 0.98), accent, 2, 10, 4))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(accent.darkened(0.6), accent, 2, 10, 4))
	b.add_theme_stylebox_override("focus", UITheme.panel_style(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.95), 2, 10, 4))
	b.tooltip_text = "%s — %s, Lv %d%s" % [d.name, DB.roles[d.role].name, Profile.defender_level(id),
		{"captain": " · captain", "team": " · starting six", "bench": " · bench", "locked": " · locked"}[st]]
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var ph := Control.new()
	ph.custom_minimum_size = Vector2(84, 84)
	ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ph)
	var pr := MenuScreen.portrait_rect(id, 84, accent if st != "locked" else Color(0.3, 0.3, 0.36))
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ph.add_child(pr)
	if st == "locked":
		pr.modulate = Color(0.35, 0.35, 0.42)
		var lk := UITheme.icon_rect("lock", 30, UITheme.OFFWHITE)
		lk.position = Vector2(27, 27)
		ph.add_child(lk)
	var nl := UITheme.label(str(d.name), UITheme.FS_BODY, accent.lightened(0.3) if st != "locked" else UITheme.MUTED, UITheme.font_header())
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(nl)
	var sub := UITheme.label({"captain": "CAPTAIN", "team": "STARTING SIX", "bench": "BENCH", "locked": "LOCKED"}[st], UITheme.FS_MIN,
		UITheme.GOLD if st == "captain" else (UITheme.SCARLET.lightened(0.2) if st == "team" else UITheme.MUTED), UITheme.font_body_bold())
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(sub)
	if id == ids[1 - side]:
		b.disabled = true
		b.tooltip_text += "\nAlready on the other side."
	b.pressed.connect(func() -> void: pick(id))
	return b


## Picks `id` for the side the picker is open for, and closes the picker.
func pick(id: String) -> void:
	var side := picker_side
	if side < 0 or id == ids[1 - side]:
		Audio.ui("ui_error")
		return
	if picker and is_instance_valid(picker):
		picker.queue_free()
	Audio.ui("ui_confirm")
	set_side(side, id)
	var b: Button = buttons.get("Change%d" % side)
	if b:
		b.grab_focus.call_deferred()
