extends MenuScreen
## Deck builder and card collection.
## Left: team roster / collection progress. Centre: filterable, sortable card grid.
## Right: selected card details, upgrade path, combos and comparison.
## Bottom (deck mode): the 8 equipped cards, deck statistics and deck actions.

var collection_mode := false
var deck: Array = []
var selected := ""
var compare_with := ""
var filter_rarity := ""
var filter_category := ""
var filter_defender := ""
var search := ""
var sort_mode := 0
var owned_only := false

var _grid: GridContainer
var _detail: VBoxContainer
var _deck_row: HBoxContainer
var _deck_stats: Label
var _left: VBoxContainer
var _rarity_btns := {}
var _cat_btns := {}
var _dirty := false
var _search: LineEdit


func _ready() -> void:
	collection_mode = Session.menu_tab == "collection"
	setup_screen("COLLECTION" if collection_mode else "DECK BUILDER",
		"Every ability card — upgrade them with copies from card packs" if collection_mode else "Build an 8-card deck. Hands hold up to 5 cards; energy caps at 10.")
	deck = Profile.data.deck.duplicate()
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)

	var lp := panel()
	lp.custom_minimum_size = Vector2(300, 0)
	body.add_child(lp)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	lp.add_child(_left)

	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	body.add_child(center)
	center.add_child(_build_filters())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(_grid)

	var rp := panel()
	rp.custom_minimum_size = Vector2(430, 0)
	body.add_child(rp)
	var rscroll := ScrollContainer.new()
	rscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.add_child(rscroll)
	_detail = VBoxContainer.new()
	_detail.custom_minimum_size = Vector2(396, 0)
	_detail.add_theme_constant_override("separation", 8)
	rscroll.add_child(_detail)

	if not collection_mode:
		content.add_child(_build_deck_bar())
	_fill_left()
	selected = deck[0] if deck.size() > 0 else DB.card_order[0]
	_refresh()


func _build_filters() -> Control:
	var p := panel(Color(0.04, 0.07, 0.12, 0.85), Color(1, 1, 1, 0.08), 10)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	vb.add_child(row1)
	row1.add_child(UITheme.icon_rect("search", 26, UITheme.MUTED))
	var le := LineEdit.new()
	_search = le
	le.placeholder_text = "Search cards... (F)"
	le.custom_minimum_size = Vector2(260, 0)
	le.text_changed.connect(func(t: String) -> void:
		search = t.to_lower()
		_refresh_grid())
	row1.add_child(le)
	row1.add_child(UITheme.icon_rect("sort", 26, UITheme.MUTED))
	var sort := OptionButton.new()
	for s in ["Sort: Rarity", "Sort: Cost", "Sort: Name", "Sort: Category", "Sort: Level"]:
		sort.add_item(s)
	sort.item_selected.connect(func(i: int) -> void:
		sort_mode = i
		_refresh_grid())
	row1.add_child(sort)
	var own := CheckBox.new()
	own.text = "Owned only"
	own.toggled.connect(func(v: bool) -> void:
		owned_only = v
		_refresh_grid())
	row1.add_child(own)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	vb.add_child(row2)
	row2.add_child(UITheme.icon_rect("filter", 24, UITheme.MUTED))
	for r in DB.RARITY_ORDER:
		var b := UITheme.small_button(r.capitalize(), DB.rarity_color(r), 18)
		b.toggle_mode = true
		b.add_theme_color_override("font_color", DB.rarity_color(r))
		b.pressed.connect(func() -> void:
			filter_rarity = "" if filter_rarity == r else r
			for k in _rarity_btns.keys():
				_rarity_btns[k].button_pressed = k == filter_rarity
			_refresh_grid())
		row2.add_child(b)
		_rarity_btns[r] = b
	var sep := Control.new()
	sep.custom_minimum_size = Vector2(14, 0)
	row2.add_child(sep)
	for c in DB.CATEGORY_ORDER:
		var b := UITheme.small_button(c.capitalize(), DB.category_color(c), 18)
		b.toggle_mode = true
		b.icon = DB.icon(c)
		b.expand_icon = false
		b.add_theme_color_override("icon_normal_color", DB.category_color(c))
		b.add_theme_constant_override("icon_max_width", 20)
		b.pressed.connect(func() -> void:
			filter_category = "" if filter_category == c else c
			for k in _cat_btns.keys():
				_cat_btns[k].button_pressed = k == filter_category
			_refresh_grid())
		row2.add_child(b)
		_cat_btns[c] = b
	return p


func _build_deck_bar() -> Control:
	var p := panel(Color(0.03, 0.05, 0.09, 0.95), Color(UITheme.SCARLET, 0.5), 12)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	p.add_child(hb)
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(260, 0)
	info.add_child(UITheme.header("EQUIPPED DECK", 28, UITheme.GOLD))
	_deck_stats = UITheme.label("", 18, UITheme.MUTED)
	_deck_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deck_stats.custom_minimum_size = Vector2(260, 0)
	info.add_child(_deck_stats)
	hb.add_child(info)
	_deck_row = HBoxContainer.new()
	_deck_row.add_theme_constant_override("separation", 8)
	_deck_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_deck_row)
	var actions := GridContainer.new()
	actions.columns = 2
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	hb.add_child(actions)
	var save := UITheme.small_button("Save Deck", UITheme.GREEN, 22)
	save.pressed.connect(_save_deck)
	actions.add_child(save)
	var auto := UITheme.small_button("Auto Build", UITheme.GOLD, 22)
	auto.pressed.connect(_auto_build)
	actions.add_child(auto)
	var clear := UITheme.small_button("Clear Deck", UITheme.SCARLET, 22)
	clear.pressed.connect(func() -> void:
		deck.clear()
		_dirty = true
		_refresh())
	actions.add_child(clear)
	var test := UITheme.small_button("Test Deck", UITheme.BLUE, 22)
	test.tooltip_text = "Try this deck on the Practice Field"
	test.pressed.connect(_test_deck)
	actions.add_child(test)
	for b in actions.get_children():
		(b as Button).custom_minimum_size = Vector2(150, 44)
	return p


# ---------------------------------------------------------------- left column

func _fill_left() -> void:
	for c in _left.get_children():
		c.queue_free()
	if collection_mode:
		_left.add_child(UITheme.header("COLLECTION", 30, UITheme.GOLD))
		var total := 0
		for r in DB.RARITY_ORDER:
			var have := 0
			var all := 0
			for cid in DB.card_order:
				if DB.card(cid).rarity == r:
					all += 1
					if Profile.is_card_owned(cid):
						have += 1
			total += have
			var row := HBoxContainer.new()
			var l := UITheme.label(r.capitalize(), 22, DB.rarity_color(r), UITheme.font_body_bold())
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(l)
			row.add_child(UITheme.label("%d / %d" % [have, all], 22, UITheme.OFFWHITE, UITheme.font_body_bold()))
			_left.add_child(row)
			var pb := ProgressBar.new()
			pb.max_value = all
			pb.value = have
			pb.show_percentage = false
			pb.custom_minimum_size = Vector2(0, 8)
			pb.add_theme_stylebox_override("fill", UITheme.panel_style(DB.rarity_color(r), Color(0, 0, 0, 0), 0, 3, 0))
			_left.add_child(pb)
		_left.add_child(UITheme.hsep())
		_left.add_child(UITheme.label("%d of %d cards collected." % [total, DB.card_order.size()], 20, UITheme.OFFWHITE))
		var how := UITheme.label("Earn card packs by finishing runs. Higher difficulties drop rarer cards. Duplicate copies upgrade cards (up to level 5). Unlocking a defender grants their signature card.", 18, UITheme.MUTED)
		how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		how.custom_minimum_size = Vector2(270, 0)
		_left.add_child(how)
		return
	_left.add_child(UITheme.header("ROSTER", 30, UITheme.GOLD))
	var hint := UITheme.label("Click a defender to show their signature card. Signature cards are cast by that defender with their power.", 16, UITheme.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(270, 0)
	_left.add_child(hint)
	for id in DB.defender_order:
		var d := DB.defender(id)
		var unlocked := Profile.is_defender_unlocked(id)
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = filter_defender == id
		b.custom_minimum_size = Vector2(0, 58)
		b.disabled = not unlocked
		var accent := Color(d.accent)
		b.add_theme_stylebox_override("normal", UITheme.panel_style(Color(0.06, 0.09, 0.15, 0.9), Color(accent, 0.3), 1, 8, 6))
		b.add_theme_stylebox_override("hover", UITheme.panel_style(Color(0.1, 0.14, 0.22, 0.95), accent, 2, 8, 6))
		b.add_theme_stylebox_override("pressed", UITheme.panel_style(accent.darkened(0.55), accent, 2, 8, 6))
		b.add_theme_stylebox_override("disabled", UITheme.panel_style(Color(0.04, 0.05, 0.08, 0.7), Color(1, 1, 1, 0.04), 1, 8, 6))
		var hb := HBoxContainer.new()
		hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_theme_constant_override("separation", 10)
		var pr := portrait_rect(id, 44, accent)
		pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(pr)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -4)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		var n := UITheme.label(d.name + ("  ★" if id in Profile.data.team else ""), 22, accent.lightened(0.3) if unlocked else UITheme.MUTED, UITheme.font_header())
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(n)
		var sub := "%s · Lv %d" % [DB.roles[d.role].name, Profile.defender_level(id)] if unlocked else Profile.defender_unlock_text(id)
		var sl := UITheme.label(sub, 15, UITheme.MUTED, UITheme.font_body_bold())
		sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(sl)
		hb.add_child(vb)
		b.add_child(hb)
		b.pressed.connect(func() -> void:
			filter_defender = "" if filter_defender == id else id
			if filter_defender != "":
				selected = d.signature
			_fill_left()
			_refresh())
		_left.add_child(b)


# ---------------------------------------------------------------- grid & details

func _sorted_cards() -> Array:
	var ids: Array = []
	for cid in DB.card_order:
		var c := DB.card(cid)
		if filter_rarity != "" and c.rarity != filter_rarity:
			continue
		if filter_category != "" and c.category != filter_category:
			continue
		if owned_only and not Profile.is_card_owned(cid):
			continue
		if search != "" and not (search in str(c.name).to_lower() or search in str(c.text).to_lower()):
			continue
		if filter_defender != "" and c.get("linked", "") != filter_defender and DB.defender(filter_defender).signature != cid:
			continue
		ids.append(cid)
	ids.sort_custom(func(a, b) -> bool:
		var ca := DB.card(a)
		var cb := DB.card(b)
		match sort_mode:
			1:
				return int(ca.cost) < int(cb.cost) if int(ca.cost) != int(cb.cost) else str(ca.name) < str(cb.name)
			2:
				return str(ca.name) < str(cb.name)
			3:
				var ia := DB.CATEGORY_ORDER.find(ca.category)
				var ib := DB.CATEGORY_ORDER.find(cb.category)
				return ia < ib if ia != ib else str(ca.name) < str(cb.name)
			4:
				return Profile.card_level(a) > Profile.card_level(b)
		var ra := DB.RARITY_ORDER.find(ca.rarity)
		var rb := DB.RARITY_ORDER.find(cb.rarity)
		return ra > rb if ra != rb else str(ca.name) < str(cb.name))
	return ids


func _refresh() -> void:
	_refresh_grid()
	_refresh_detail()
	_refresh_deck()


func _refresh_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for cid in _sorted_cards():
		var cv := CardView.new(cid, Profile.card_level(cid))
		cv.set_card(cid, Profile.card_level(cid))
		cv.custom_minimum_size = Vector2(160, 224)
		cv.owned = Profile.is_card_owned(cid)
		cv.selected = cid == selected
		if cid in deck and not collection_mode:
			cv.count_badge = "IN"
		elif Profile.can_upgrade_card(cid):
			cv.count_badge = "▲"
		var id: String = cid
		cv.clicked.connect(func(_c: CardView) -> void:
			if Input.is_key_pressed(KEY_SHIFT) and selected != "" and selected != id:
				compare_with = selected
			else:
				compare_with = ""
			if selected == id and not collection_mode:
				_toggle_in_deck(id)
			selected = id
			Audio.ui("card_hover")
			_refresh())
		_grid.add_child(cv)


func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if selected == "":
		return
	var c := DB.card(selected)
	var lvl := Profile.card_level(selected)
	var owned := Profile.is_card_owned(selected)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var big := CardView.new(selected, lvl)
	big.set_card(selected, lvl)
	big.custom_minimum_size = Vector2(190, 266)
	big.owned = owned
	top.add_child(big)
	if compare_with != "":
		var other := CardView.new(compare_with, Profile.card_level(compare_with))
		other.set_card(compare_with, Profile.card_level(compare_with))
		other.custom_minimum_size = Vector2(190, 266)
		other.owned = Profile.is_card_owned(compare_with)
		top.add_child(other)
	_detail.add_child(top)
	if compare_with != "":
		_detail.add_child(_compare_table(selected, compare_with))
		var clear := UITheme.small_button("Stop comparing", UITheme.BLUE, 18)
		clear.pressed.connect(func() -> void:
			compare_with = ""
			_refresh_detail())
		_detail.add_child(clear)
		return
	_detail.add_child(UITheme.label(c.name.to_upper(), 40, UITheme.OFFWHITE, UITheme.font_display()))
	var meta := UITheme.label("%s · %s · Cost %d · Cooldown %ss · Target: %s" % [c.rarity.capitalize(), c.category.capitalize(), int(c.cost),
		str(int(c.cooldown)) if float(c.cooldown) > 0 else "none", c.target], 18, DB.rarity_color(c.rarity), UITheme.font_body_bold())
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(meta)
	var desc := UITheme.label(DB.card_text(selected, lvl), 20, UITheme.OFFWHITE)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	var linked: String = c.get("linked", "")
	if linked != "":
		_detail.add_child(UITheme.label("Signature card of %s — cast by them on the field." % DB.defender(linked).name, 18, DB.defender_accent(linked).lightened(0.3), UITheme.font_body_bold()))
	if not owned:
		_detail.add_child(UITheme.label("NOT YET COLLECTED — found in end-of-run card packs.", 19, UITheme.SCARLET, UITheme.font_body_bold()))
	# Upgrade path
	_detail.add_child(UITheme.hsep())
	_detail.add_child(UITheme.header("UPGRADE PATH", 26, UITheme.GOLD))
	var growth: Array = c.get("growth", [])
	if growth.is_empty():
		_detail.add_child(UITheme.label("This card's effect is fixed; upgrades are cosmetic.", 17, UITheme.MUTED))
	else:
		var grid := GridContainer.new()
		grid.columns = DB.card_max_level + 1
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_child(UITheme.label("", 16))
		for l in DB.card_max_level:
			grid.add_child(UITheme.label("L%d" % (l + 1), 17, UITheme.GOLD if l + 1 == lvl else UITheme.MUTED, UITheme.font_body_bold()))
		for g in growth:
			grid.add_child(UITheme.label(str(g).replace("_", " "), 16, UITheme.MUTED))
			for l in DB.card_max_level:
				var v := DB.card_param(selected, g, l + 1)
				grid.add_child(UITheme.label(("%d" % int(round(v))) if v >= 10 else ("%.2f" % v), 17, UITheme.OFFWHITE if l + 1 == lvl else UITheme.MUTED, UITheme.font_body_bold()))
		_detail.add_child(grid)
	if owned:
		var cost := Profile.upgrade_cost(selected)
		if cost.is_empty():
			_detail.add_child(UITheme.label("MAX LEVEL", 22, UITheme.GOLD, UITheme.font_display()))
		else:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(UITheme.label("Copies %d / %d" % [Profile.card_copies(selected), int(cost.copies)], 19,
				UITheme.GREEN if Profile.card_copies(selected) >= int(cost.copies) else UITheme.MUTED, UITheme.font_body_bold()))
			var up := UITheme.small_button("Upgrade  %d" % int(cost.coins), UITheme.GOLD, 21)
			up.icon = DB.icon("coin")
			up.expand_icon = false
			up.add_theme_constant_override("icon_max_width", 22)
			up.disabled = not Profile.can_upgrade_card(selected)
			up.pressed.connect(func() -> void:
				if Profile.upgrade_card(selected):
					Audio.play("level_up")
					Router.toast("%s upgraded to level %d!" % [c.name, Profile.card_level(selected)], "level")
					_refresh())
			row.add_child(up)
			_detail.add_child(row)
	# Combos
	var combos := DB.combos_for(selected)
	if not combos.is_empty():
		_detail.add_child(UITheme.hsep())
		_detail.add_child(UITheme.header("SYNERGIES", 26, UITheme.GOLD))
		for cb in combos:
			var other := DB.card(cb.card)
			var l := UITheme.label("+ %s: %s" % [other.name, cb.text], 17, UITheme.GREEN if cb.card in deck else UITheme.OFFWHITE)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_detail.add_child(l)
	if not collection_mode and owned:
		var eq := UITheme.small_button("Remove from deck" if selected in deck else "Add to deck", UITheme.SCARLET if selected in deck else UITheme.GREEN, 22)
		eq.disabled = not selected in deck and deck.size() >= Profile.DECK_SIZE
		eq.pressed.connect(func() -> void: _toggle_in_deck(selected))
		_detail.add_child(eq)
	_detail.add_child(UITheme.label("Tip: Shift-click another card to compare.", 15, UITheme.MUTED))


func _compare_table(a: String, b: String) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	var ca := DB.card(a)
	var cb := DB.card(b)
	var rows := [["Cost", str(int(ca.cost)), str(int(cb.cost))], ["Cooldown", str(int(ca.cooldown)), str(int(cb.cooldown))],
		["Rarity", ca.rarity.capitalize(), cb.rarity.capitalize()], ["Category", ca.category.capitalize(), cb.category.capitalize()],
		["Level", str(Profile.card_level(a)), str(Profile.card_level(b))], ["Target", ca.target, cb.target]]
	for r in rows:
		g.add_child(UITheme.label(r[0], 17, UITheme.MUTED))
		g.add_child(UITheme.label(r[1], 18, UITheme.OFFWHITE, UITheme.font_body_bold()))
		g.add_child(UITheme.label(r[2], 18, UITheme.OFFWHITE, UITheme.font_body_bold()))
	return g


func _toggle_in_deck(id: String) -> void:
	if collection_mode or not Profile.is_card_owned(id):
		return
	if id in deck:
		deck.erase(id)
		Audio.ui("ui_back")
	elif deck.size() < Profile.DECK_SIZE:
		deck.append(id)
		Audio.play("card_draw", -4.0)
	else:
		Router.toast("Your deck is full (8 cards). Remove one first.", "warn")
		Audio.ui("ui_error")
		return
	_dirty = true
	_refresh()


func _refresh_deck() -> void:
	if collection_mode or _deck_row == null:
		return
	for c in _deck_row.get_children():
		c.queue_free()
	for i in Profile.DECK_SIZE:
		if i < deck.size():
			var cid: String = deck[i]
			var cv := CardView.new(cid, Profile.card_level(cid))
			cv.set_card(cid, Profile.card_level(cid))
			cv.custom_minimum_size = Vector2(104, 146)
			cv.show_level = false
			cv.tooltip_text = "Click to remove"
			cv.clicked.connect(func(_c: CardView) -> void: _toggle_in_deck(cid))
			_deck_row.add_child(cv)
		else:
			var slot := Panel.new()
			slot.custom_minimum_size = Vector2(104, 146)
			slot.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0, 0, 0, 0.3), Color(1, 1, 1, 0.15), 2, 8, 0))
			_deck_row.add_child(slot)
	var cats := {}
	var total_cost := 0
	for cid in deck:
		var c := DB.card(cid)
		cats[c.category] = int(cats.get(c.category, 0)) + 1
		total_cost += int(c.cost)
	var avg := float(total_cost) / maxf(deck.size(), 1)
	var txt := "%d / %d cards · avg cost %.1f\n" % [deck.size(), Profile.DECK_SIZE, avg]
	for k in DB.CATEGORY_ORDER:
		txt += "%s %d  " % [k.capitalize(), int(cats.get(k, 0))]
	var combos := 0
	for cb in DB.combos:
		if cb.cards[0] in deck and cb.cards[1] in deck:
			combos += 1
	txt += "\nCombos in deck: %d" % combos
	if _dirty:
		txt += "\n(unsaved changes)"
	_deck_stats.text = txt


func _save_deck() -> bool:
	if deck.size() != Profile.DECK_SIZE:
		Router.toast("A deck needs exactly 8 cards (now %d)." % deck.size(), "warn")
		Audio.ui("ui_error")
		return false
	Profile.set_deck(deck)
	_dirty = false
	Router.toast("Deck saved.", "info")
	Audio.ui("ui_confirm")
	_refresh_deck()
	return true


## Builds a balanced deck: team signatures first, then the best owned cards per category.
func _auto_build() -> void:
	var picks: Array = []
	for id in Profile.data.team:
		var sig: String = DB.defender(id).signature
		if Profile.is_card_owned(sig) and not sig in picks and picks.size() < 3:
			picks.append(sig)
	var score := func(cid: String) -> float:
		var c := DB.card(cid)
		return DB.RARITY_ORDER.find(c.rarity) * 1.5 + Profile.card_level(cid) * 1.2 - absf(float(c.cost) - 3.5) * 0.4
	for cat in DB.CATEGORY_ORDER:
		var have := 0
		for p in picks:
			if DB.card(p).category == cat:
				have += 1
		var opts: Array = []
		for cid in DB.card_order:
			if Profile.is_card_owned(cid) and DB.card(cid).category == cat and not cid in picks:
				opts.append(cid)
		opts.sort_custom(func(a, b) -> bool: return score.call(a) > score.call(b))
		for cid in opts:
			if have >= 2 or picks.size() >= Profile.DECK_SIZE:
				break
			picks.append(cid)
			have += 1
	var rest: Array = []
	for cid in DB.card_order:
		if Profile.is_card_owned(cid) and not cid in picks:
			rest.append(cid)
	rest.sort_custom(func(a, b) -> bool: return score.call(a) > score.call(b))
	for cid in rest:
		if picks.size() >= Profile.DECK_SIZE:
			break
		picks.append(cid)
	deck = picks
	_dirty = true
	Audio.ui("ui_confirm")
	_refresh()


func _test_deck() -> void:
	if deck.is_empty():
		Router.toast("Add some cards first.", "warn")
		return
	var cfg := Session.new_run_config("practice")
	cfg.deck = deck.duplicate()
	Session.start(cfg)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("info") and _search and not _search.has_focus():
		_search.grab_focus()
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func go_back() -> void:
	if _dirty and deck.size() == Profile.DECK_SIZE:
		Profile.set_deck(deck)
	elif _dirty:
		Router.toast("Deck not saved: it needs exactly 8 cards.", "warn")
	super.go_back()
