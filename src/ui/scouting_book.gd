class_name ScoutingBook
extends MenuScreen
## Scouting Book: every runner type, boss and elite affix (Scouting has the data). A list on the
## left (portrait, name, NEW for entries met but not opened yet, a silhouette for entries not met
## yet), a 3D turntable of the model in the middle, and the report on the right: stats as bars,
## special ability, what it does, how to stop it and the cards that counter it.
## The same report opens in battle as a small pausing popup (ScoutingBook.popup).

var selected := ""
var _list: VBoxContainer
var _rows := {}               # key -> Button
var _detail: VBoxContainer
var _turntable: Turntable
var _stage_title: Label
var _stage_badges: HBoxContainer
var _progress_label: Label
var _progress_bar: ProgressBar
var _anim_buttons := {}


func _ready() -> void:
	setup_screen("SCOUTING BOOK", "Every runner, boss and elite: what it does and how to stop it")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	content.add_child(body)

	# ---- List
	var lp := panel()
	lp.custom_minimum_size = Vector2(400, 0)
	body.add_child(lp)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	lp.add_child(lv)
	lv.add_child(UITheme.section_header("OPPONENTS", "enemy"))
	var prog := HBoxContainer.new()
	prog.add_theme_constant_override("separation", 10)
	_progress_label = UITheme.label("", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	prog.add_child(_progress_label)
	_progress_bar = UITheme.bar(UITheme.GOLD, 10, 1.0, 0.0)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	prog.add_child(_progress_bar)
	lv.add_child(prog)
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(ls)
	_list = VBoxContainer.new()
	_list.name = "ScoutList"
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	ls.add_child(_list)

	# ---- Turntable
	var mp := panel(Color(0.03, 0.05, 0.09, 0.92))
	mp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mp)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 6)
	mp.add_child(mv)
	_stage_title = UITheme.title("", UITheme.FS_H1)
	_stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mv.add_child(_stage_title)
	_stage_badges = HBoxContainer.new()
	_stage_badges.alignment = BoxContainer.ALIGNMENT_CENTER
	_stage_badges.add_theme_constant_override("separation", 8)
	mv.add_child(_stage_badges)
	_turntable = Turntable.new()
	_turntable.name = "Turntable"
	_turntable.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_turntable.custom_minimum_size = Vector2(380, 420)
	mv.add_child(_turntable)
	var ctl := HBoxContainer.new()
	ctl.alignment = BoxContainer.ALIGNMENT_CENTER
	ctl.add_theme_constant_override("separation", 8)
	mv.add_child(ctl)
	for a in [["IDLE", "idle"], ["RUN", "run"]]:
		var b := UITheme.button(a[0], "secondary", UITheme.FS_SMALL, "", UITheme.GOLD)
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(110, UITheme.BTN_H_SMALL)
		var clip: String = a[1]
		b.pressed.connect(func() -> void: _set_anim(clip))
		ctl.add_child(b)
		_anim_buttons[clip] = b
	var drag := UITheme.label("Drag to turn", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	drag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ctl.add_child(drag)

	# ---- Report
	var rp := panel()
	rp.custom_minimum_size = Vector2(640, 0)
	body.add_child(rp)
	var rs := ScrollContainer.new()
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rs)
	_detail = VBoxContainer.new()
	_detail.name = "ScoutReport"
	_detail.custom_minimum_size = Vector2(580, 0)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	rs.add_child(_detail)

	for a in OS.get_cmdline_user_args():   # screenshot helpers
		if a == "--scout-demo":   # most entries met, a few still NEW or locked
			for k in Scouting.all_keys():
				if not k in ["grand_slammer", "affix:shielded", "decoy"]:
					Scouting.mark_met(k)
					if not k in ["trickster", "slugger", "affix:plated"]:
						Scouting.mark_viewed(k)
		elif a.begins_with("--scout-entry="):
			Scouting.open_on = a.split("=")[1]
	_fill_list()
	var first := Scouting.open_on
	Scouting.open_on = ""
	if first == "" or not Scouting.exists(first):
		first = _first_key()
	select(first, true)
	_set_anim("run")
	set_help("scouting_book", func() -> Dictionary: return {"scouting_intro": _list})


## The entry to show first: the first NEW one, else the first met one, else the very first.
func _first_key() -> String:
	var keys := Scouting.all_keys()
	for k in keys:
		if Scouting.is_new(k):
			return k
	for k in keys:
		if Scouting.is_met(k):
			return k
	return keys[0] if not keys.is_empty() else ""


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	for g in Scouting.GROUPS:
		var keys := Scouting.keys_in_group(g)
		if keys.is_empty():
			continue
		var head := UITheme.label(str(Scouting.GROUP_TITLES[g]), UITheme.FS_MIN, Color(1, 1, 1, 0.55), UITheme.font_body_bold())
		var hm := MarginContainer.new()
		hm.add_theme_constant_override("margin_top", 6)
		hm.add_child(head)
		_list.add_child(hm)
		for k in keys:
			var row := _row(k)
			_list.add_child(row)
			_rows[k] = row
	var n := Scouting.met_count()
	var total := Scouting.all_keys().size()
	_progress_label.text = "%d / %d SCOUTED" % [n, total]
	_progress_bar.max_value = maxi(total, 1)
	_progress_bar.value = n


func _row(key: String) -> Button:
	var met := Scouting.is_met(key)
	var accent := Scouting.threat_color(key) if met else Color(0.35, 0.4, 0.5)
	var b := Button.new()
	b.name = "Row_" + key.replace(":", "_")
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 66)
	b.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.9), Color(accent, 0.3), 1, 8, 6))
	b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0.1, 0.14, 0.22, 0.95), accent, 2, 8, 6))
	b.add_theme_stylebox_override("pressed", UITheme.panel_style(accent.darkened(0.6), accent, 2, 8, 6))
	b.add_theme_stylebox_override("hover_pressed", UITheme.panel_style(accent.darkened(0.5), accent, 2, 8, 6))
	b.add_theme_stylebox_override("focus", UITheme.panel_style(Color(0, 0, 0, 0), Color(UITheme.GOLD, 0.6), 1, 8, 6))
	b.mouse_entered.connect(func() -> void: Audio.ui("ui_hover", -9.0))
	b.pressed.connect(func() -> void:
		Audio.ui("ui_click", -3.0)
		select(key))
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 8
	hb.offset_right = -10
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(hb)
	var pic := entry_picture(key, 50, met)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(pic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	vb.add_child(UITheme.label(Scouting.entry_name(key) if met else "? ? ?", UITheme.FS_LEAD, UITheme.OFFWHITE if met else UITheme.MUTED, UITheme.font_header()))
	var sub := UITheme.label(Scouting.threat_text(key).capitalize() if met else "Not scouted yet", UITheme.FS_MIN, accent.lightened(0.2) if met else UITheme.MUTED, UITheme.font_body_bold())
	vb.add_child(sub)
	if Scouting.is_new(key):
		var nb := UITheme.badge("NEW", UITheme.SCARLET)
		nb.name = "NewBadge"
		nb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(nb)
	elif not met:
		var lk := UITheme.icon_rect("lock", 22, UITheme.MUTED)
		lk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(lk)
	return b


## Portrait (or the affix icon) in a frame; a dark silhouette with a lock when not met yet.
static func entry_picture(key: String, side: float, met: bool) -> PanelContainer:
	var accent := Scouting.threat_color(key) if met else Color(0.3, 0.33, 0.4)
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(accent.darkened(0.7), accent, 2, 8, 2))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := Scouting.portrait(key)
	var r := TextureRect.new()
	r.custom_minimum_size = Vector2(side, side)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex:
		r.texture = tex
	else:
		r.texture = DB.icon(Scouting.icon_name(key))
		r.custom_minimum_size = Vector2(side, side)
		r.modulate = accent.lightened(0.3)
	if not met:
		r.modulate = Color(0.06, 0.08, 0.13)
	elif key == "decoy":
		r.modulate = Color(0.75, 0.6, 1.0, 0.6)
	frame.add_child(r)
	return frame


func select(key: String, quiet := false) -> void:
	if key == "":
		return
	selected = key
	for k in _rows.keys():
		(_rows[k] as Button).set_pressed_no_signal(k == key)
	var was_new := Scouting.is_new(key)
	Scouting.mark_viewed(key)
	if was_new and _rows.has(key):
		var nb: Node = (_rows[key] as Node).find_child("NewBadge", true, false)
		if nb:
			var tw := (nb as Control).create_tween()
			tw.tween_property(nb, "modulate:a", 0.0, UITheme.T_MED)
			tw.tween_callback(nb.queue_free)
	var met := Scouting.is_met(key)
	_stage_title.text = Scouting.entry_name(key).to_upper() if met else "NOT SCOUTED YET"
	for c in _stage_badges.get_children():
		c.queue_free()
	if met:
		_stage_badges.add_child(UITheme.badge(Scouting.threat_text(key), Scouting.threat_color(key).darkened(0.25)))
	_turntable.show_key(key, not met)
	for c in _detail.get_children():
		c.queue_free()
	_detail.add_child(build_report(key, false))
	if not quiet:
		UITheme.animate_in(_detail, 0.0, 0.985)


func _set_anim(clip: String) -> void:
	for k in _anim_buttons.keys():
		(_anim_buttons[k] as Button).set_pressed_no_signal(k == clip)
	_turntable.set_clip(clip)


# ---------------------------------------------------------------- the report (book and popup)

## Name, where it shows up, stat bars, ability, what it does, how to stop it, good cards.
## `compact` is the in-battle popup (smaller cards, no flavour line).
static func build_report(key: String, compact: bool) -> Control:
	var margin := MarginContainer.new()   # room for the scroll bar on the right
	margin.name = "Report"
	margin.add_theme_constant_override("margin_right", 16)
	var vb := VBoxContainer.new()
	margin.add_child(vb)
	vb.add_theme_constant_override("separation", 8 if compact else 10)
	var met := Scouting.is_met(key)
	if not met:
		var lk := UITheme.tile_panel(Color(1, 1, 1, 0.12), 16)
		var lv := VBoxContainer.new()
		lv.add_theme_constant_override("separation", 8)
		lk.add_child(lv)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		h.add_child(UITheme.icon_rect("lock", 30, UITheme.MUTED))
		h.add_child(UITheme.header("NOT SCOUTED YET", UITheme.FS_H2, UITheme.OFFWHITE))
		lv.add_child(h)
		var t := UITheme.label("Meet this opponent in a game and its full report opens here: numbers, what it does, how to stop it and the cards that counter it.", UITheme.FS_BODY, UITheme.OFFWHITE)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(t)
		var w := UITheme.label(Scouting.where_text(key) + ".", UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_body_bold())
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lv.add_child(w)
		vb.add_child(lk)
		return margin
	var where := HBoxContainer.new()
	where.add_theme_constant_override("separation", 8)
	where.add_child(UITheme.icon_rect("inning", 20, UITheme.MUTED))
	var wl := UITheme.label(Scouting.where_text(key), UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	where.add_child(wl)
	vb.add_child(where)
	if not compact and not Scouting.is_affix(key):
		var fl := UITheme.label("“%s”" % str(DB.enemy(key).get("text", "")), UITheme.FS_SMALL, Color(0.85, 0.88, 0.95), UITheme.font_brush())
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(fl)

	vb.add_child(UITheme.section_header("STATS", "info", UITheme.GOLD, UITheme.FS_H3 if not compact else UITheme.FS_LEAD))
	var grid := GridContainer.new()
	grid.name = "StatBars"
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4 if compact else 6)
	for r in Scouting.stat_rows(key):
		var lab := HBoxContainer.new()
		lab.add_theme_constant_override("separation", 8)
		lab.custom_minimum_size = Vector2(150 if not compact else 136, 0)
		lab.add_child(UITheme.icon_rect(str(r[0]), 20, r[4]))
		lab.add_child(UITheme.label(str(r[1]), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		grid.add_child(lab)
		var bar := UITheme.bar(r[4], 12, 1.0, float(r[3]))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(bar)
		var v := UITheme.label(str(r[2]), UITheme.FS_SMALL, UITheme.OFFWHITE, UITheme.font_header())
		v.custom_minimum_size = Vector2(84, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(v)
	vb.add_child(grid)
	var cap_text := "Base numbers. Bars compare with the other %s; harder difficulties and later innings add health and speed." % \
		("bosses" if Scouting.group_of(key) == "bosses" else "runners")
	if Scouting.is_affix(key):
		cap_text = "Added on top of the runner's normal numbers."
	var cap := UITheme.label(cap_text, UITheme.FS_MIN, UITheme.MUTED)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not compact:
		vb.add_child(cap)
	else:
		grid.tooltip_text = cap_text

	var ab := HBoxContainer.new()
	ab.name = "Ability"
	ab.add_theme_constant_override("separation", 10)
	ab.add_child(UITheme.icon_rect("special", 22, UITheme.GOLD))
	ab.add_child(UITheme.label("SPECIAL ABILITY", UITheme.FS_SMALL, UITheme.GOLD, UITheme.font_header()))
	var abl := UITheme.label(Scouting.ability_name(key), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_body_bold())
	abl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ab.add_child(abl)
	vb.add_child(ab)
	vb.add_child(_text_block("WHAT IT DOES", "enemy", Scouting.what_it_does(key), Color(1.0, 0.55, 0.45), compact))
	var stop := _text_block("HOW TO STOP IT", "shield", Scouting.how_to_stop(key), UITheme.GREEN, compact)
	stop.name = "HowToStop"
	vb.add_child(stop)

	vb.add_child(UITheme.section_header("GOOD CARDS AGAINST IT", "deck", UITheme.GOLD, UITheme.FS_H3 if not compact else UITheme.FS_LEAD))
	var cards := HBoxContainer.new()
	cards.name = "GoodCards"
	cards.add_theme_constant_override("separation", 12)
	var csize := Vector2(96, 134) if compact else Vector2(118, 165)
	var any_locked := false
	for cid in Scouting.good_cards(key):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.custom_minimum_size = Vector2(csize.x, 0)
		cell.set_meta("card", cid)
		var owned := Profile.is_card_owned(cid)
		any_locked = any_locked or not owned
		var cv := CardView.new(cid, Profile.card_level(cid))
		cv.set_card(cid, Profile.card_level(cid))
		cv.custom_minimum_size = csize
		cv.owned = owned
		cv.show_level = owned
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var wrap := Control.new()
		wrap.custom_minimum_size = csize
		wrap.tooltip_text = "%s: %s%s" % [DB.card(cid).name, DB.card_text(cid, Profile.card_level(cid)), "" if owned else "\n(Not collected yet: find it in card packs.)"]
		wrap.add_child(cv)
		cv.size = csize
		cell.add_child(wrap)
		var why := UITheme.label(Scouting.reason(cid, key).capitalize(), UITheme.FS_MIN, UITheme.GREEN if owned else UITheme.MUTED, UITheme.font_body_bold())
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		why.custom_minimum_size = Vector2(csize.x, 0)
		cell.add_child(why)
		cards.add_child(cell)
	vb.add_child(cards)
	if any_locked:
		var nl := UITheme.label("Greyed-out cards are not in your collection yet: they come from card packs.", UITheme.FS_MIN, UITheme.MUTED)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(nl)
	return margin


static func _text_block(title: String, icon: String, text: String, color: Color, compact: bool, bold := false) -> Control:
	var p := UITheme.tile_panel(Color(color, 0.35), 10 if compact else 12)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(UITheme.icon_rect(icon, 20, color))
	h.add_child(UITheme.label(title, UITheme.FS_SMALL, color, UITheme.font_header()))
	v.add_child(h)
	var l := UITheme.label(text, UITheme.FS_LEAD if bold else (UITheme.FS_SMALL if compact else UITheme.FS_BODY), UITheme.OFFWHITE,
		UITheme.font_body_bold() if bold else null)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	return p


# ---------------------------------------------------------------- in-battle popup

## Opens the compact scouting card over the battle (pauses the game while open; Esc or CLOSE
## resumes). Opening it from the threat panel counts as meeting the runner.
static func popup(parent: Control, key: String) -> ScoutPopup:
	Scouting.mark_met(key)
	Scouting.mark_viewed(key)
	var p := ScoutPopup.new()
	p.key = key
	p.name = "ScoutPopup"
	parent.add_child(p)
	return p


class ScoutPopup extends Control:
	signal closed
	var key := ""
	var _was_paused := false
	var _panel: PanelContainer

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_was_paused = get_tree().paused
		get_tree().paused = true
		var dim := ColorRect.new()
		dim.color = Color(0.01, 0.02, 0.05, 0.66)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				close())
		add_child(dim)
		var center := CenterContainer.new()
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		var accent := Scouting.threat_color(key)
		_panel = UITheme.card_panel(Color(accent, 0.75), 22, Color(0.05, 0.08, 0.14, 0.97), 2)
		_panel.name = "ScoutCard"
		center.add_child(_panel)
		var outer := VBoxContainer.new()
		outer.add_theme_constant_override("separation", 10)
		_panel.add_child(outer)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 14)
		outer.add_child(head)
		head.add_child(ScoutingBook.entry_picture(key, 56, true))
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -6)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(UITheme.label("SCOUTING REPORT", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		tv.add_child(UITheme.title(Scouting.entry_name(key).to_upper(), 48))
		head.add_child(tv)
		var tb := UITheme.badge(Scouting.threat_text(key), accent.darkened(0.25), UITheme.FS_SMALL)
		tb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(tb)
		var body := HBoxContainer.new()
		body.add_theme_constant_override("separation", 18)
		outer.add_child(body)
		var tt := Turntable.new()
		tt.custom_minimum_size = Vector2(320, 690)
		body.add_child(tt)
		tt.show_key.call_deferred(key, false)
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(620, 690)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		body.add_child(sc)
		var rep := ScoutingBook.build_report(key, true)
		rep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(rep)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 10)
		outer.add_child(row)
		var note := UITheme.label("The game is paused. Every report is kept in the Scouting Book (main menu).", UITheme.FS_MIN, UITheme.MUTED)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(note)
		var ok := UITheme.button("BACK TO THE GAME", "primary", UITheme.FS_LEAD, "play", UITheme.GREEN.darkened(0.2))
		ok.name = "CloseButton"
		ok.tooltip_text = "Close the report and resume (Esc)"
		ok.custom_minimum_size = Vector2(260, UITheme.BTN_H)
		ok.pressed.connect(close)
		row.add_child(ok)
		UITheme.animate_in(_panel, 0.0, 0.95)
		Audio.ui("ui_slide")

	func close() -> void:
		if is_queued_for_deletion():
			return
		Audio.ui("ui_back")
		get_tree().paused = _was_paused
		closed.emit()
		queue_free()

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- turntable

## A 3D turntable in a SubViewport: the runner model in its battle colours on a pedestal, turning
## slowly (drag to turn it), playing its idle or run clip. Not-scouted entries show a dark ghost.
class Turntable extends SubViewportContainer:
	var _vp: SubViewport
	var _pivot: Node3D
	var _model: CharacterModel
	var _camera: Camera3D
	var _key_light: DirectionalLight3D
	var _ring: MeshInstance3D
	var _yaw := 0.5
	var _drag := false
	var _clip := "run"
	var _locked := false
	var _pending := ""

	func _init() -> void:
		stretch = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_default_cursor_shape = Control.CURSOR_DRAG
		_vp = SubViewport.new()
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.msaa_3d = Viewport.MSAA_4X
		_vp.size = Vector2i(400, 480)
		add_child(_vp)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.45, 0.5, 0.65)
		env.ambient_light_energy = 0.75
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		we.environment = env
		_vp.add_child(we)
		_key_light = DirectionalLight3D.new()
		_key_light.rotation_degrees = Vector3(-35, 35, 0)
		_key_light.light_energy = 1.4
		_key_light.light_color = Color(1.0, 0.92, 0.82)
		_vp.add_child(_key_light)
		var rim := OmniLight3D.new()
		rim.position = Vector3(-1.6, 2.6, -2.0)
		rim.light_color = Color(0.4, 0.6, 1.0)
		rim.light_energy = 3.0
		rim.omni_range = 7.0
		_vp.add_child(rim)
		var rim2 := OmniLight3D.new()
		rim2.position = Vector3(1.8, 1.4, -1.6)
		rim2.light_color = Color(1.0, 0.35, 0.3)
		rim2.light_energy = 2.2
		rim2.omni_range = 6.0
		_vp.add_child(rim2)
		var ped := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 1.05
		cm.bottom_radius = 1.2
		cm.height = 0.24
		ped.mesh = cm
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.12, 0.16, 0.24)
		pm.metallic = 0.6
		pm.roughness = 0.35
		ped.material_override = pm
		ped.position.y = -0.12
		_vp.add_child(ped)
		_ring = FieldBuilder.make_ring(1.1, Color(1.0, 0.22, 0.15, 0.9), 0.04, 0.12)
		_ring.position.y = 0.01
		_vp.add_child(_ring)
		_pivot = Node3D.new()
		_vp.add_child(_pivot)
		_camera = Camera3D.new()
		_camera.fov = 30
		_vp.add_child(_camera)
		_frame(1.8)

	func _frame(h: float) -> void:
		# Fit a model of height h (after normalising, always about 1.8 m) with room for the pedestal.
		var dist := 5.3 * maxf(h, 1.0) / 1.8
		var pos := Vector3(0, h * 0.68, dist)
		_camera.transform = Transform3D(Basis.looking_at(Vector3(0, h * 0.48, 0) - pos, Vector3.UP), pos)

	## Shows an entry's model: its own colours (or the colours of the type it borrows), an elite's
	## red glow, a decoy's ghost, or a dark silhouette when `locked`.
	func show_key(key: String, locked := false) -> void:
		_locked = locked
		if _model:
			_model.queue_free()
			_model = null
		var mid := Scouting.model_id(key)
		var data := DB.enemy(key) if not Scouting.is_affix(key) else DB.enemy("runner")
		_model = CharacterModel.new()
		_pivot.add_child(_model)
		var opts := {"accent": Color("#FF7A1A"), "body": Color("#2B2F36"), "shadows": false}
		if data.has("colors"):
			opts.colors = data.colors
		_model.setup(mid, opts)
		# Every model stands about 1.8 m tall on the turntable (bosses are scaled down to fit).
		var h := maxf(_model.height, 0.1)
		_model.scale = Vector3.ONE * (1.8 / h)
		_model.height = 1.8
		_frame(1.8)
		var boss := Scouting.group_of(key) == "bosses"
		(_ring.material_override as ShaderMaterial).set_shader_parameter("color", Color(1.0, 0.5, 0.1, 0.95) if boss else Color(1.0, 0.22, 0.15, 0.9))
		if locked:
			_model.set_ghost(0.35, Color(0.25, 0.32, 0.55))
			_key_light.light_energy = 0.15
		else:
			_key_light.light_energy = 1.4
			if key == "decoy":
				_model.set_ghost(0.55)
			elif Scouting.is_affix(key):
				_model.set_rim(Color(1.0, 0.2, 0.1, 0.6))
		_apply_clip()

	func set_clip(clip: String) -> void:
		_clip = clip
		_apply_clip()

	func _apply_clip() -> void:
		if _model == null:
			return
		var c := _clip
		if _locked:
			c = "idle"
		_model.play_base(c, 0.2)
		if _model.anim:
			_model.anim.speed_scale = 0.8 if c == "run" else 1.0

	func _process(delta: float) -> void:
		if not _drag:
			_yaw += delta * 0.45
		_pivot.rotation.y = _yaw

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			_drag = (event as InputEventMouseButton).pressed
			accept_event()
		elif event is InputEventMouseMotion and _drag:
			_yaw += (event as InputEventMouseMotion).relative.x * 0.012
			accept_event()
