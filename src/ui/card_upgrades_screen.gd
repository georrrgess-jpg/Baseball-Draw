class_name CardUpgradesScreen
extends MenuScreen
## Card Upgrades: level owned cards up with duplicate copies (from card packs) and coins.
## Left: every owned card with its level, copy progress and cost, ready cards first.
## Right: the selected card's before -> after stats, the cost and a big UPGRADE button.
## Update 11: at level 5 the next step is PRESTIGE (a PrestigeCeremony plays), then Prestige ★1-★5
## (levels 6-10). Upgrade All leaves the Prestige step out unless "Include Prestige" is ticked.

## Screen that BACK returns to. Callers set it right before opening this screen.
static var return_to := "main_menu"
static var _demo_done := false

const STAT_NAMES := {
	"damage": "Damage", "burn_dps": "Burn damage", "duration": "Duration", "vulnerability": "Extra damage taken",
	"confuse": "Confuse time", "pushback": "Pushback", "freeze": "Freeze time", "root": "Root time",
	"crit_bonus": "Crit chance bonus", "hp": "Wall strength", "chain_damage": "Ricochet damage",
	"damage_bonus": "Ally damage bonus", "pull_time": "Hold time", "stun": "Stun time",
}
const PERCENT_STATS := ["vulnerability", "crit_bonus", "chain_damage", "damage_bonus", "speed_bonus", "per_defender"]
const UNITS := {"duration": "s", "burn_time": "s", "confuse": "s", "freeze": "s", "root": "s", "stun": "s",
	"pull_time": "s", "pushback": "m", "burn_dps": "/s"}
const TILE_CARD := Vector2(104, 146)
const BIG_CARD := Vector2(236, 330)

var selected := ""
var _back_to := "main_menu"
var _list: GridContainer
var _detail: VBoxContainer
var _ready_label: Label
var _ready_icon: TextureRect
var _busy := false
var _all_btn: Button

# Detail widgets the upgrade animation drives.
var _d_card: CardView
var _d_flash: Panel
var _d_holder: Control
var _d_pips: Array[Control] = []
var _ceremony: PrestigeCeremony
var _include_prestige := false   # Upgrade All opt-in (off every time the screen opens)
var _d_stats: Array = []      # [Label, from, to, key]
var _d_level: Label
var _d_button: Button


func _ready() -> void:
	apply_debug_args()
	MasteryUI.apply_demo_args()
	_back_to = return_to
	return_to = "main_menu"
	setup_screen("CARD UPGRADES", "Level up your cards to make them stronger in every game.")
	content.add_theme_constant_override("separation", 12)
	content.add_child(_build_top_bar())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)

	var lp := panel(Color(0.035, 0.06, 0.1, 0.9), Color(1, 1, 1, 0.08), 14)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(lp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 3
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("h_separation", 12)
	_list.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_list)

	var rp := panel(Color(0.04, 0.065, 0.11, 0.95), Color(UITheme.GOLD, 0.3), 18)
	rp.custom_minimum_size = Vector2(640, 0)
	body.add_child(rp)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 12)
	rp.add_child(_detail)

	# Start on the first ready card whose stats grow (its before -> after is the most telling).
	var ids := _sorted_ids()
	selected = ids[0] if not ids.is_empty() else ""
	for cid in ids:
		if Profile.can_upgrade_card(cid) and not DB.card(cid).get("growth", []).is_empty():
			selected = cid
			break
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--select-card=") and Profile.is_card_owned(a.split("=")[1]):   # screenshot helper
			selected = a.split("=")[1]
	_rebuild()
	set_help("card_upgrades", func() -> Dictionary: return {"upgrades_intro": _detail})
	if "--open-upgrade-all" in OS.get_cmdline_user_args():   # screenshot helper
		_confirm_upgrade_all.call_deferred()
	if "--card-gallery" in OS.get_cmdline_user_args():   # screenshot helper: card faces before/after Prestige
		_card_gallery.call_deferred()
	for a in OS.get_cmdline_user_args():   # screenshot helper: --prestige-now=<card> plays the ceremony at once
		if a.begins_with("--prestige-now=") and Profile.can_prestige_card(a.split("=")[1]):
			_do_upgrade.call_deferred(a.split("=")[1])


## Debug/screenshot helper: `--grant-demo-cards` fills the profile with a varied collection.
static func apply_debug_args() -> void:
	if _demo_done or not "--grant-demo-cards" in OS.get_cmdline_user_args():
		return
	_demo_done = true
	var locked := ["grand_slam_barrage", "time_out", "shadow_change", "thunderbolt", "pickoff", "bunt_trap", "diving_catch"]
	var levels := [1, 2, 3, 1, 2, 1, 4, 2, 1, 3]
	var i := 0
	for cid in DB.card_order:
		if not Profile.data.cards.has(cid):
			continue
		var c: Dictionary = Profile.data.cards[cid]
		c.owned = not cid in locked
		c.erase("fresh")
		if not c.owned:
			continue
		c.level = int(levels[i % levels.size()])
		var need: int = int(DB.COPIES_TO_UPGRADE[DB.card(cid).rarity][mini(int(c.level), DB.card_max_level - 1)])
		c.copies = [need, need - 1, 0, need - 2, 1, need - 1][i % 6] if need > 0 else 0
		c.copies = maxi(0, int(c.copies))
		i += 1
	for cid in ["magnet_glove", "seventh_inning_stretch", "diamond_aura"]:
		Profile.data.cards[cid]["fresh"] = true
	if "--prestige-demo" in OS.get_cmdline_user_args():
		# Update 11 screenshots: a late-game collection with Prestige cards and one ready to prestige.
		var demo := {"power_throw": 8, "heat_wave": 6, "curveball": 10, "frost_field": 7, "lockdown": 5, "twin_play": 9,
			"wall_of_dirt": 5, "rally_cry": 6, "splitter": 5, "sky_hook": 4, "field_vision": 5}
		for cid in demo.keys():
			if Profile.data.cards.has(cid):
				Profile.data.cards[cid].owned = true
				Profile.data.cards[cid].level = int(demo[cid])
				Profile.data.cards[cid].copies = 3
		Profile.data.cards.lockdown.copies = DB.upgrade_copies("rare", 5) + 2
		Profile.data.cards.wall_of_dirt.copies = DB.upgrade_copies("common", 5)
		Profile.data.cards.rally_cry.copies = DB.upgrade_copies("uncommon", 6)
		Profile.data.coins = maxi(int(Profile.data.coins), 24000)
		Profile.save_now()   # so a later screenshot run (e.g. a battle) can reuse this profile
	Profile.data.deck = Profile.STARTER_DECK.duplicate()
	Profile.data.coins = maxi(int(Profile.data.coins), 2400)
	Profile.changed.emit()


func _build_top_bar() -> Control:
	var p := panel(Color(0.03, 0.05, 0.09, 0.92), Color(UITheme.GOLD, 0.3), 12)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	p.add_child(hb)
	_ready_icon = UITheme.icon_rect("upgrade", 46, UITheme.GOLD)
	hb.add_child(_ready_icon)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -4)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	_ready_label = UITheme.label("", 36, UITheme.GOLD, UITheme.font_header())
	vb.add_child(_ready_label)
	vb.add_child(UITheme.label("Duplicate cards from packs become copies. Spend copies + coins to level a card up. At level %d, PRESTIGE it for Prestige ★1-★%d." % [DB.PRESTIGE_LEVEL,
		DB.card_max_level - DB.PRESTIGE_LEVEL], 20, UITheme.MUTED, UITheme.font_body_bold()))
	_all_btn = UITheme.menu_button("UPGRADE ALL", UITheme.GOLD, 26)
	_all_btn.custom_minimum_size = Vector2(260, 56)
	_all_btn.pressed.connect(_confirm_upgrade_all)
	hb.add_child(_all_btn)
	var packs := UITheme.menu_button("GET CARD PACKS  ▶", UITheme.BLUE, 26)
	packs.custom_minimum_size = Vector2(290, 56)
	packs.pressed.connect(func() -> void: Router.open("packs"))
	hb.add_child(packs)
	return p


# ---------------------------------------------------------------- list

func _sorted_ids() -> Array:
	var ids: Array = []
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			ids.append(cid)
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ka := _sort_key(a)
		var kb := _sort_key(b)
		return ka > kb if ka != kb else str(DB.card(a).name) < str(DB.card(b).name))
	return ids


## Ready cards first, then by how close they are to the next level; maxed cards last.
func _sort_key(id: String) -> float:
	var cost := Profile.upgrade_cost(id)
	if cost.is_empty():
		return -1.0
	if Profile.can_upgrade_card(id):
		return 10.0 + DB.rarity_index(DB.card(id).rarity) * 0.1
	return clampf(float(Profile.card_copies(id)) / maxf(float(cost.copies), 1.0), 0.0, 1.0)


func ready_count() -> int:
	var n := 0
	for cid in DB.card_order:
		if Profile.can_upgrade_card(cid):
			n += 1
	return n


func _rebuild() -> void:
	var n := ready_count()
	if n > 0:
		_ready_label.text = "%d CARD%s READY TO UPGRADE" % [n, "" if n == 1 else "S"]
		_ready_label.add_theme_color_override("font_color", UITheme.GOLD)
		_ready_icon.modulate = UITheme.GOLD
	else:
		_ready_label.text = "NO CARDS READY YET"
		_ready_label.add_theme_color_override("font_color", UITheme.OFFWHITE)
		_ready_icon.modulate = UITheme.MUTED
	_update_all_button()
	for c in _list.get_children():
		c.queue_free()
	var ids := _sorted_ids()
	if ids.is_empty():
		_list.add_child(UITheme.label("You don't own any cards yet. Open card packs to start your collection.", 22, UITheme.MUTED))
	for cid in ids:
		_list.add_child(_make_tile(cid))
	_refresh_detail()


func _make_tile(id: String) -> Control:
	var c := DB.card(id)
	var lvl := Profile.card_level(id)
	var cost := Profile.upgrade_cost(id)
	var ready := Profile.can_upgrade_card(id)
	var maxed := cost.is_empty()
	var pres_step := not maxed and bool(cost.get("prestige", false))
	var tile := PanelContainer.new()
	tile.name = "Tile_" + id
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(0, 172)
	var border := Color(1, 1, 1, 0.08)
	var bg := Color(0.06, 0.09, 0.15, 0.92)
	if id == selected:
		border = UITheme.GOLD
		bg = Color(0.12, 0.13, 0.17, 0.98)
	elif ready and pres_step:
		border = Color(CardView.PRESTIGE_GOLD, 0.95)
		bg = Color(0.1, 0.08, 0.16, 0.95)
	elif ready:
		border = Color(UITheme.GREEN, 0.75)
	tile.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 2 if (ready or id == selected) else 1, 10, 10))
	tile.mouse_filter = Control.MOUSE_FILTER_STOP
	tile.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(id))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	tile.add_child(hb)
	var cv := CardView.new(id, lvl)
	cv.set_card(id, lvl)
	cv.custom_minimum_size = TILE_CARD
	cv.show_level = false
	cv.mastery = CardMastery.stars(id)
	cv.selected = id == selected
	cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cv.clicked.connect(func(_c: CardView) -> void: _select(id))
	hb.add_child(cv)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 5)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(info)
	var nm := UITheme.label(str(c.name), 27, UITheme.OFFWHITE, UITheme.font_header())
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size = Vector2(120, 0)
	info.add_child(nm)
	var lrow := HBoxContainer.new()
	lrow.add_theme_constant_override("separation", 8)
	lrow.add_child(UITheme.label(DB.level_label(lvl), 20, CardView.PRESTIGE_GOLD if DB.prestige_stars(lvl) > 0 else UITheme.GOLD, UITheme.font_body_bold()))
	var pips := _pips(lvl, 12, not maxed)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lrow.add_child(pips)
	info.add_child(lrow)
	if maxed:
		info.add_child(UITheme.label("MAX PRESTIGE", 28, CardView.PRESTIGE_GOLD, UITheme.font_display()))
		info.add_child(UITheme.label("Hall of Fame: fully upgraded!", 17, UITheme.MUTED, UITheme.font_body_bold()))
		return tile
	info.add_child(_copies_bar(Profile.card_copies(id), int(cost.copies), 24, 17))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	var enough_coins := int(Profile.data.coins) >= int(cost.coins)
	crow.add_child(UITheme.icon_rect("coin", 22, UITheme.GOLD))
	crow.add_child(UITheme.label(UITheme.format_int(int(cost.coins)), 21, UITheme.GOLD if enough_coins else UITheme.SCARLET, UITheme.font_body_bold()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(sp)
	if ready:
		var up := _prestige_button(20, Vector2(124, 38)) if pres_step else _upgrade_button(20, Vector2(112, 38))
		up.pressed.connect(func() -> void: _do_upgrade(id))
		crow.add_child(up)
	else:
		var why := UITheme.label(_missing_text(id, true), 17, UITheme.MUTED, UITheme.font_body_bold())
		crow.add_child(why)
	info.add_child(crow)
	return tile


## A gold UPGRADE button that pulses while it is available.
func _upgrade_button(size: int, min_size: Vector2) -> Button:
	var b := UITheme.menu_button("UPGRADE", UITheme.GOLD, size, -0.12)
	b.custom_minimum_size = min_size
	b.add_theme_stylebox_override("normal", UITheme.button_style(Color(0.55, 0.38, 0.05, 0.95), UITheme.GOLD, -0.12, 2))
	b.add_theme_color_override("font_color", Color.WHITE)
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "self_modulate", Color(1.35, 1.25, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	return b


## The PRESTIGE button: holo violet with a gold rim, pulsing while it is available.
func _prestige_button(size: int, min_size: Vector2) -> Button:
	var b := UITheme.menu_button("PRESTIGE", CardView.PRESTIGE_GOLD, size, -0.12)
	b.name = "PrestigeButton"
	b.custom_minimum_size = min_size
	b.add_theme_stylebox_override("normal", UITheme.button_style(Color(0.36, 0.16, 0.5, 0.97), CardView.PRESTIGE_GOLD, -0.12, 3))
	b.add_theme_stylebox_override("hover", UITheme.button_style(Color(0.48, 0.24, 0.62, 1.0), CardView.PRESTIGE_GOLD.lightened(0.3), -0.12, 3))
	b.add_theme_color_override("font_color", Color.WHITE)
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "self_modulate", Color(1.3, 1.2, 1.35), 0.7).set_trans(Tween.TRANS_SINE)
	tw.tween_property(b, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	return b


func _missing_text(id: String, short := false) -> String:
	var cost := Profile.upgrade_cost(id)
	if cost.is_empty():
		return "Max level"
	var need_copies := int(cost.copies) - Profile.card_copies(id)
	var need_coins := int(cost.coins) - int(Profile.data.coins)
	if need_copies > 0:
		if short:
			return "%d more cop%s" % [need_copies, "y" if need_copies == 1 else "ies"]
		return "Needs %d more cop%s. Duplicates from card packs become copies." % [need_copies, "y" if need_copies == 1 else "ies"]
	if need_coins > 0:
		if short:
			return "%s more coins" % UITheme.format_int(need_coins)
		return "Needs %s more coins. Win games to earn coins." % UITheme.format_int(need_coins)
	return ""


func _copies_bar(have: int, need: int, height: int, font_size: int) -> Control:
	var pb := ProgressBar.new()
	pb.max_value = maxi(need, 1)
	pb.value = mini(have, need)
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(0, height)
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var full := have >= need
	pb.add_theme_stylebox_override("fill", UITheme.panel_style(UITheme.GREEN.darkened(0.15) if full else UITheme.BLUE, Color(0, 0, 0, 0), 0, 4, 0))
	var l := UITheme.label("%d / %d copies" % [have, need], font_size, Color.WHITE, UITheme.font_body_bold())
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	pb.add_child(l)
	return pb


## Level pips: five round pips for levels 1-5, filled gold up to `level`; from level 5 on, five Prestige
## stars follow (gold up to the Prestige level). The next one is outlined green when it can be reached.
## Item i always stands for level i + 1, so the upgrade animation can pop item `level`.
func _pips(level: int, size: int, show_next: bool, store := false) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", int(size * 0.4))
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := DB.card_max_level if level >= DB.PRESTIGE_LEVEL else DB.PRESTIGE_LEVEL
	for i in count:
		var p: Control
		if i < DB.PRESTIGE_LEVEL:
			p = Panel.new()
			p.add_theme_stylebox_override("panel", _pip_style(i < level, show_next and i == level, size))
		else:
			if i == DB.PRESTIGE_LEVEL:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(size * 0.3, size)
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hb.add_child(gap)
			p = Label.new()
			p.text = "★"
			p.add_theme_font_override("font", UITheme.font_body_bold())
			p.add_theme_font_size_override("font_size", int(size * 1.45))
			p.add_theme_constant_override("outline_size", maxi(2, int(size * 0.25)))
			p.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			p.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_set_star(p, i < level, show_next and i == level)
		p.custom_minimum_size = Vector2(size, size)
		p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(p)
		if store:
			_d_pips.append(p)
	return hb


func _set_star(l: Label, filled: bool, next: bool) -> void:
	l.add_theme_color_override("font_color", CardView.PRESTIGE_GOLD if filled else Color(1, 1, 1, 0.16))
	l.add_theme_color_override("font_outline_color", Color(UITheme.GREEN, 0.95) if next else Color(0, 0, 0, 0.75))


## Fills pip/star `i` (for the upgrade animation).
func _fill_pip(p: Control) -> void:
	if p is Label:
		_set_star(p as Label, true, false)
	elif p is Panel:
		p.add_theme_stylebox_override("panel", _pip_style(true, false, int(p.custom_minimum_size.x)))


func _pip_style(filled: bool, next: bool, size: int) -> StyleBoxFlat:
	var s := UITheme.panel_style(UITheme.GOLD if filled else Color(1, 1, 1, 0.1),
		Color(UITheme.GREEN, 0.95) if next else Color(0, 0, 0, 0.6), maxi(2, int(size * 0.14)), size, 0)
	return s


# ---------------------------------------------------------------- detail

func _select(id: String) -> void:
	if _busy or id == selected:
		return
	selected = id
	Audio.ui("card_hover")
	_rebuild()


func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	_d_pips.clear()
	_d_stats.clear()
	if selected == "":
		_detail.add_child(UITheme.label("Open card packs to collect cards.", 22, UITheme.MUTED))
		return
	var c := DB.card(selected)
	var lvl := Profile.card_level(selected)
	var cost := Profile.upgrade_cost(selected)
	var maxed := cost.is_empty()
	var pres_step := not maxed and bool(cost.get("prestige", false))

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	_detail.add_child(top)
	_d_holder = Control.new()
	_d_holder.custom_minimum_size = BIG_CARD
	top.add_child(_d_holder)
	_d_card = CardView.new(selected, lvl)
	_d_card.set_card(selected, lvl)
	_d_card.mastery = CardMastery.stars(selected)
	_d_card.custom_minimum_size = BIG_CARD
	_d_card.size = BIG_CARD
	_d_card.pivot_offset = BIG_CARD * 0.5
	_d_holder.add_child(_d_card)
	_d_flash = Panel.new()
	_d_flash.size = BIG_CARD
	_d_flash.pivot_offset = BIG_CARD * 0.5
	_d_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_d_flash.add_theme_stylebox_override("panel", UITheme.panel_style(Color(1, 0.97, 0.85, 1), Color(0, 0, 0, 0), 0, 18, 0))
	_d_flash.modulate.a = 0.0
	_d_holder.add_child(_d_flash)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(right)
	var nm := UITheme.title(str(c.name).to_upper(), 42)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(nm)
	right.add_child(UITheme.label("%s  ·  %s" % [str(c.rarity).capitalize(), str(c.category).capitalize()], 20, DB.rarity_color(c.rarity), UITheme.font_body_bold()))
	_d_level = UITheme.label("", 40, UITheme.OFFWHITE, UITheme.font_header())
	if maxed:
		_d_level.text = "MAX: PRESTIGE ★%d" % DB.prestige_stars(lvl)
	elif pres_step:
		_d_level.text = "LEVEL %d  ▶  PRESTIGE ★1" % lvl
	elif DB.prestige_stars(lvl) > 0:
		_d_level.text = "PRESTIGE ★%d  ▶  ★%d" % [DB.prestige_stars(lvl), DB.prestige_stars(lvl + 1)]
	else:
		_d_level.text = "LEVEL %d  ▶  %d" % [lvl, lvl + 1]
	if maxed or DB.prestige_stars(lvl) > 0 or pres_step:
		_d_level.add_theme_color_override("font_color", CardView.PRESTIGE_GOLD if not maxed else UITheme.GOLD)
	_d_level.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_d_level)
	right.add_child(_pips(lvl, 26, not maxed, true))
	right.add_child(UITheme.hsep())
	right.add_child(UITheme.header("CURRENT STATS" if maxed else "WHAT GETS BETTER", 26, UITheme.GOLD))
	var growth: Array = c.get("growth", [])
	if growth.is_empty():
		var l := UITheme.label("This card's effect is fixed. Leveling it shows your mastery.", 19, UITheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(l)
	else:
		var grid := GridContainer.new()
		grid.columns = 2 if maxed else 4
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 4)
		right.add_child(grid)
		for g in growth:
			var key := str(g)
			var now := DB.card_param(selected, key, lvl)
			grid.add_child(UITheme.label(stat_name(key), 21, UITheme.MUTED, UITheme.font_body_bold()))
			var cur := UITheme.label(format_stat(key, now), 24, UITheme.OFFWHITE, UITheme.font_header())
			grid.add_child(cur)
			if maxed:
				continue
			var nxt := DB.card_param(selected, key, lvl + 1)
			var arrow := UITheme.label("▶  " + format_stat(key, nxt), 24, UITheme.GREEN, UITheme.font_header())
			grid.add_child(arrow)
			grid.add_child(UITheme.label("+%d%%" % int(round((nxt / maxf(now, 0.0001) - 1.0) * 100.0)), 19, Color(UITheme.GREEN, 0.75), UITheme.font_body_bold()))
			_d_stats.append([cur, now, nxt, key])
	_detail.add_child(MasteryUI.strip(selected))

	if maxed:
		var done := UITheme.label("Prestige ★%d: this card is fully upgraded. Hall of Fame!" % DB.prestige_stars(lvl), 22, UITheme.GOLD, UITheme.font_body_bold())
		_detail.add_child(done)
		_add_how_it_works()
		return
	if pres_step:
		_detail.add_child(_prestige_info())

	# Cost: copies and coins, each with have / need.
	var cp := panel(Color(0.02, 0.04, 0.08, 0.85), Color(1, 1, 1, 0.08), 14)
	_detail.add_child(cp)
	var chb := HBoxContainer.new()
	chb.add_theme_constant_override("separation", 24)
	cp.add_child(chb)
	var copies_col := VBoxContainer.new()
	copies_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copies_col.add_theme_constant_override("separation", 4)
	var ch := HBoxContainer.new()
	ch.add_child(UITheme.icon_rect("deck", 24, UITheme.OFFWHITE))
	ch.add_child(UITheme.label("CARD COPIES", 21, UITheme.OFFWHITE, UITheme.font_body_bold()))
	copies_col.add_child(ch)
	copies_col.add_child(_copies_bar(Profile.card_copies(selected), int(cost.copies), 30, 20))
	chb.add_child(copies_col)
	var coins_col := VBoxContainer.new()
	coins_col.custom_minimum_size = Vector2(190, 0)
	coins_col.add_theme_constant_override("separation", 4)
	var kh := HBoxContainer.new()
	kh.add_child(UITheme.icon_rect("coin", 24, UITheme.GOLD))
	kh.add_child(UITheme.label("COINS", 21, UITheme.OFFWHITE, UITheme.font_body_bold()))
	coins_col.add_child(kh)
	var enough := int(Profile.data.coins) >= int(cost.coins)
	coins_col.add_child(UITheme.label("%s  (you have %s)" % [UITheme.format_int(int(cost.coins)), UITheme.format_int(int(Profile.data.coins))],
		21, UITheme.GOLD if enough else UITheme.SCARLET, UITheme.font_body_bold()))
	chb.add_child(coins_col)

	var ready := Profile.can_upgrade_card(selected)
	var btn_text := "PRESTIGE" if pres_step else ("UPGRADE TO ★%d" % DB.prestige_stars(lvl + 1) if lvl >= DB.PRESTIGE_LEVEL else "UPGRADE TO LEVEL %d" % (lvl + 1))
	if ready:
		_d_button = _prestige_button(40, Vector2(0, 76)) if pres_step else _upgrade_button(40, Vector2(0, 76))
		_d_button.text = btn_text
		_d_button.pressed.connect(func() -> void: _do_upgrade(selected))
	else:
		_d_button = UITheme.menu_button(btn_text, UITheme.MUTED, 40, -0.12)
		_d_button.custom_minimum_size = Vector2(0, 76)
		_d_button.disabled = true
	_detail.add_child(_d_button)
	if not ready:
		var why := HBoxContainer.new()
		why.add_theme_constant_override("separation", 12)
		var wl := UITheme.label(_missing_text(selected), 20, UITheme.OFFWHITE, UITheme.font_body_bold())
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		why.add_child(wl)
		if Profile.card_copies(selected) < int(cost.copies):
			var pk := UITheme.small_button("Card Packs  ▶", UITheme.BLUE, 20)
			pk.pressed.connect(func() -> void: Router.open("packs"))
			why.add_child(pk)
		_detail.add_child(why)
	_add_how_it_works()


func _add_how_it_works() -> void:
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(sp)
	var p := panel(Color(0.02, 0.035, 0.07, 0.7), Color(1, 1, 1, 0.06), 12)
	_detail.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	vb.add_child(UITheme.header("HOW UPGRADES WORK", 24, UITheme.GOLD))
	var steps := [["gift", "Open card packs. Duplicates of cards you own become copies."],
		["deck", "Collect enough copies for the card's next level."],
		["coin", "Pay the coins and press UPGRADE: its stats grow +%d%% per level." % int(round(DB.card_growth_rate * 100.0))],
		["star", "At level %d, PRESTIGE it: a holo frame and Prestige ★1-★%d, +%d%% per step." % [DB.PRESTIGE_LEVEL,
			DB.card_max_level - DB.PRESTIGE_LEVEL, int(round(DB.card_prestige_growth * 100.0))]]]
	for i in steps.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UITheme.label("%d" % (i + 1), 24, UITheme.GOLD, UITheme.font_display()))
		row.add_child(UITheme.icon_rect(steps[i][0], 22, UITheme.OFFWHITE))
		var l := UITheme.label(steps[i][1], 19, UITheme.OFFWHITE, UITheme.font_body_bold())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		vb.add_child(row)


## What Prestige does, shown above the cost when the card's next step is the Prestige step.
func _prestige_info() -> Control:
	var p := panel(Color(0.12, 0.07, 0.2, 0.92), Color(CardView.PRESTIGE_GOLD, 0.6), 12)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	hb.add_child(UITheme.icon_rect("star", 40, CardView.PRESTIGE_GOLD))
	var l := UITheme.label("PRESTIGE turns this card into a Prestige card: an iridescent holo frame and a gold crest, "
		+ "and opens levels 6-10 (Prestige ★1-★5). Each Prestige step adds +%d%% to its stats." % int(round(DB.card_prestige_growth * 100.0)),
		19, UITheme.OFFWHITE, UITheme.font_body_bold())
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	return p


static func stat_name(key: String) -> String:
	return str(STAT_NAMES.get(key, key.replace("_", " ").capitalize()))


static func format_stat(key: String, v: float) -> String:
	if key in PERCENT_STATS:
		return "%d%%" % int(round(v * 100.0))
	var unit: String = UNITS.get(key, "")
	if v >= 10.0 or absf(v - roundf(v)) < 0.05:
		return "%d%s" % [int(round(v)), unit]
	return "%.1f%s" % [v, unit]


# ---------------------------------------------------------------- upgrade

func _do_upgrade(id: String) -> void:
	if _busy:
		return
	if not Profile.can_upgrade_card(id):
		Audio.ui("ui_error")
		return
	if selected != id:
		selected = id
		_rebuild()
	var lvl := Profile.card_level(id)
	if DB.is_prestige_step(lvl):
		await _do_prestige(id)
		return
	if not Profile.upgrade_card(id):
		return
	_busy = true
	_d_button.disabled = true
	Audio.play("purchase")
	Audio.play("card_play", -3.0)
	var name_text := str(DB.card(id).name)
	# Card: wind up, flash white, pop bigger, settle.
	var tw := create_tween()
	tw.tween_property(_d_card, "scale", Vector2(0.9, 0.9), 0.14).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		Audio.play("level_up")
		_d_card.set_card(id, lvl + 1)
		_d_flash.modulate.a = 0.95
		_d_flash.scale = Vector2(1.14, 1.14)
		var fl := create_tween().set_parallel()
		fl.tween_property(_d_flash, "modulate:a", 0.0, 0.5)
		fl.tween_property(_d_flash, "scale", Vector2(1.0, 1.0), 0.18)
		_float_text("LEVEL UP!"))
	tw.tween_property(_d_card, "scale", Vector2(1.14, 1.14), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_d_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# Pip fills with a pop.
	if lvl < _d_pips.size():
		var pip := _d_pips[lvl]
		pip.pivot_offset = pip.custom_minimum_size * 0.5
		var pt := create_tween()
		pt.tween_interval(0.14)
		pt.tween_callback(func() -> void: _fill_pip(pip))
		pt.tween_property(pip, "scale", Vector2(1.6, 1.6), 0.12)
		pt.tween_property(pip, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	# Level line and stat numbers count up to their new values.
	_d_level.text = DB.level_label(lvl + 1, true)
	_d_level.add_theme_color_override("font_color", UITheme.GOLD)
	for row in _d_stats:
		var l: Label = row[0]
		var key: String = row[3]
		var from: float = row[1]
		var to: float = row[2]
		l.add_theme_color_override("font_color", UITheme.GREEN)
		var st := create_tween()
		st.tween_interval(0.14)
		st.tween_method(func(v: float) -> void: l.text = format_stat(key, v), from, to, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.25).timeout
	if not is_inside_tree():
		return
	Router.toast("%s is now %s!" % [name_text, "Prestige ★%d" % DB.prestige_stars(lvl + 1) if lvl + 1 > DB.PRESTIGE_LEVEL else "level %d" % (lvl + 1)], "level")
	_busy = false
	_rebuild()


## The Prestige step: pays, then plays the ceremony from the detail card (skippable with a click or Esc).
func _do_prestige(id: String) -> void:
	_busy = true
	for i in 2:   # the detail panel may have just been rebuilt: let it lay out first
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_busy = false
	var from_rect := _d_card.get_global_rect() if is_instance_valid(_d_card) else Rect2()
	var lvl := Profile.card_level(id)
	if not Profile.upgrade_card(id):
		Audio.ui("ui_error")
		return
	_busy = true
	if is_instance_valid(_d_button):
		_d_button.disabled = true
	if is_instance_valid(_d_card):
		_d_card.modulate.a = 0.0   # the ceremony card takes its place
	Audio.play("purchase")
	await play_ceremony(id, lvl, from_rect)
	if not is_inside_tree():
		return
	Router.toast("%s is now a Prestige card (★1)!" % str(DB.card(id).name), "level")
	_busy = false
	_rebuild()


## Plays one Prestige ceremony and waits for it to end (or be skipped). Returns true when skipped.
func play_ceremony(id: String, from_level: int, from_rect := Rect2()) -> bool:
	_ceremony = PrestigeCeremony.play(self, id, from_level, from_rect)
	await _ceremony.finished
	var was_skipped := _ceremony.skipped
	_ceremony = null
	return was_skipped


# ---------------------------------------------------------------- upgrade all

func _update_all_button() -> void:
	if _all_btn == null:
		return
	var plan := Profile.upgrade_all_plan()
	var n: int = plan.levels
	if n == 0 and not (plan.prestige_ready as Array).is_empty():   # only Prestige steps are affordable
		n = (plan.prestige_ready as Array).size()
		_all_btn.disabled = _busy
		_all_btn.text = "UPGRADE ALL"
		_all_btn.tooltip_text = "%d card%s can be prestiged (tick Include Prestige)." % [n, "" if n == 1 else "s"]
		return
	_all_btn.disabled = n == 0 or _busy
	_all_btn.text = "UPGRADE ALL (%d)" % n if n > 0 else "UPGRADE ALL"
	_all_btn.tooltip_text = ("Spend copies and coins on every upgrade you can afford: %d level-up%s for %s coins."
		% [n, "" if n == 1 else "s", UITheme.format_int(plan.coins)]) if n > 0 \
		else "Nothing to upgrade yet: cards need enough copies (from packs) and coins."


## Confirmation popup: exactly what will level up and what it costs. Update 11: an "Include Prestige"
## checkbox (off by default) adds the affordable Prestige steps; the list and totals follow it.
func _confirm_upgrade_all() -> void:
	if _busy:
		return
	var base := Profile.upgrade_all_plan(false, false)
	if base.cards.is_empty() and (base.prestige_ready as Array).is_empty():
		Audio.ui("ui_error")
		return
	var plan := Profile.upgrade_all_plan(false, _include_prestige)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	push_overlay(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var p := UITheme.card_panel(UITheme.GOLD, 24)
	p.custom_minimum_size = Vector2(620, 0)
	center.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	vb.add_child(UITheme.section_header("UPGRADE ALL", "upgrade", UITheme.GOLD))
	var summary := UITheme.label("", 22, UITheme.OFFWHITE, UITheme.font_body_bold())
	summary.name = "UpgradeAllSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "UpgradeAllRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	# Prestige opt-in: only offered when a Prestige step could be paid.
	var ready_n := (Profile.upgrade_all_plan(false, true).prestige as Array).size()
	var check := CheckBox.new()
	check.name = "IncludePrestige"
	check.text = "  Include Prestige (%d card%s ready: holo frame, levels 6-10)" % [ready_n, "" if ready_n == 1 else "s"]
	check.add_theme_font_override("font", UITheme.font_body_bold())
	check.add_theme_font_size_override("font_size", 20)
	check.add_theme_color_override("font_color", CardView.PRESTIGE_GOLD)
	check.add_theme_color_override("font_hover_color", CardView.PRESTIGE_GOLD.lightened(0.3))
	check.add_theme_color_override("font_pressed_color", CardView.PRESTIGE_GOLD)
	check.button_pressed = _include_prestige and ready_n > 0
	check.visible = ready_n > 0
	vb.add_child(check)
	vb.add_child(UITheme.label("Cheapest upgrades go first; a card can gain several levels.", 18, UITheme.MUTED))
	var go := UITheme.button("UPGRADE ALL", "primary", UITheme.FS_LEAD, "upgrade")
	go.name = "UpgradeAllGo"
	var fill := func() -> void:
		var pl := Profile.upgrade_all_plan(false, _include_prestige)
		var np := (pl.prestige as Array).size()
		summary.text = "%d card%s · %d level-up%s%s · %s coins (you have %s)" % [pl.cards.size(), "" if pl.cards.size() == 1 else "s",
			pl.levels, "" if pl.levels == 1 else "s", (" · %d PRESTIGE" % np) if np > 0 else "", UITheme.format_int(pl.coins),
			UITheme.format_int(int(Profile.data.coins))]
		for ch in rows.get_children():
			ch.queue_free()
		for e in pl.cards:
			rows.add_child(_all_row(e))
		scroll.custom_minimum_size = Vector2(0, clampi(pl.cards.size(), 1, 8) * 44)
		go.disabled = pl.cards.is_empty()
	check.toggled.connect(func(on: bool) -> void:
		_include_prestige = on
		Audio.ui("ui_toggle")
		fill.call())
	fill.call()
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	var cancel := UITheme.button("CANCEL", "secondary")
	cancel.pressed.connect(func() -> void:
		Audio.ui("ui_back")
		shade.queue_free())
	btns.add_child(cancel)
	go.pressed.connect(func() -> void:
		shade.queue_free()
		_do_upgrade_all())
	btns.add_child(go)
	shade.modulate.a = 0.0
	create_tween().tween_property(shade, "modulate:a", 1.0, 0.15)


## One line of the Upgrade All list: rarity bar, name, "LV 2 ▶ 4" (or "LV 5 ▶ PRESTIGE ★1").
func _all_row(e: Dictionary) -> Control:
	var c := DB.card(e.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := ColorRect.new()
	dot.color = DB.rarity_color(c.rarity)
	dot.custom_minimum_size = Vector2(8, 36)
	row.add_child(dot)
	var nm := UITheme.label(str(c.name), 22, Color.WHITE, UITheme.font_body_bold())
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var to_txt := DB.level_label(int(e.to)).replace("P★", "PRESTIGE ★") if int(e.to) > DB.PRESTIGE_LEVEL else "%d" % int(e.to)
	var from_txt := DB.level_label(int(e.from))
	row.add_child(UITheme.label("%s  ▶  %s" % [from_txt, to_txt], 22, CardView.PRESTIGE_GOLD if bool(e.get("prestige", false)) else UITheme.GOLD, UITheme.font_header()))
	return row


func _do_upgrade_all() -> void:
	if _busy:
		return
	var done := Profile.upgrade_all(_include_prestige)
	if done.is_empty():
		return
	_busy = true
	# Prestige steps taken get their ceremony first (a click skips one, Esc skips each in turn).
	var prestiged := done.filter(func(e: Dictionary) -> bool: return bool(e.get("prestige", false)))
	for e in prestiged.slice(0, 3):
		await play_ceremony(str(e.id), DB.PRESTIGE_LEVEL)
		if not is_inside_tree():
			return
	var levels := 0
	for e in done:
		levels += int(e.to) - int(e.from)
	Audio.play("purchase")
	Audio.play("level_up")
	# Show the last upgraded card in the detail panel with the usual level-up pop.
	selected = str(done[done.size() - 1].id)
	_rebuild()
	if is_instance_valid(_d_card):
		_d_card.pivot_offset = _d_card.size * 0.5
		var tw := create_tween()
		tw.tween_property(_d_card, "scale", Vector2(1.14, 1.14), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_d_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_float_text("+%d LEVEL%s!" % [levels, "" if levels == 1 else "S"])
	Router.toast("Upgraded %d card%s (%d level-up%s%s)." % [done.size(), "" if done.size() == 1 else "s", levels, "" if levels == 1 else "s",
		(", %d prestiged" % prestiged.size()) if not prestiged.is_empty() else ""], "level")
	await get_tree().create_timer(0.9).timeout
	if not is_inside_tree():
		return
	_busy = false
	_rebuild()


func _float_text(text: String) -> void:
	var l := UITheme.title(text, 54, UITheme.GOLD)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(BIG_CARD.x + 80, 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	var r := _d_holder.get_global_rect()
	l.global_position = Vector2(r.get_center().x - l.custom_minimum_size.x * 0.5, r.position.y + r.size.y * 0.35)
	l.pivot_offset = Vector2(l.custom_minimum_size.x * 0.5, 30)
	l.scale = Vector2(0.5, 0.5)
	var tw := l.create_tween()
	tw.set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 90.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)


## Screenshot helper (`--card-gallery`): the same cards at level 5 and at Prestige ★1, ★3 and ★5, in the
## sizes used by the upgrade tiles, the battle hand and the inspector.
func _card_gallery() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.09, 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + k, 24)
	shade.add_child(m)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(vb)
	var title := UITheme.title("PRESTIGE CARDS: LEVEL 5 (UNCHANGED)  ▶  PRESTIGE ★1 / ★3 / ★5", 40, CardView.PRESTIGE_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var ids := ["power_throw", "frost_field", "heat_wave", "grand_slam_barrage"]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--gallery-cards="):
			ids = Array(a.split("=")[1].split(","))
	var cols := [["LEVEL 5", 5, 0], ["PRESTIGE ★1", 6, 1], ["PRESTIGE ★3", 8, 3], ["PRESTIGE ★5", 10, 5]]
	var make := func(cid: String, col: Array, sz: Vector2) -> CardView:
		var cv := CardView.new(cid, int(col[1]))
		cv.set_card(cid, int(col[1]))
		cv.prestige = int(col[2])
		cv.custom_minimum_size = sz
		return cv
	for r in ceili(ids.size() / 2.0):
		var hb := HBoxContainer.new()
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 40)
		vb.add_child(hb)
		for i in range(r * 2, mini(ids.size(), r * 2 + 2)):
			var grp := VBoxContainer.new()
			grp.add_theme_constant_override("separation", 4)
			hb.add_child(grp)
			var cards := HBoxContainer.new()
			cards.add_theme_constant_override("separation", 10)
			grp.add_child(cards)
			for col in cols:
				var cv: CardView = make.call(str(ids[i]), col, Vector2(146, 204))
				cv.mastery = 2 if i == 1 else -1
				cards.add_child(cv)
			var labs := HBoxContainer.new()
			labs.add_theme_constant_override("separation", 10)
			grp.add_child(labs)
			for col in cols:
				var l := UITheme.label(str(col[0]), 15, UITheme.GOLD if int(col[2]) > 0 else UITheme.MUTED, UITheme.font_body_bold())
				l.custom_minimum_size = Vector2(146, 0)
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				labs.add_child(l)
	var big := HBoxContainer.new()
	big.alignment = BoxContainer.ALIGNMENT_CENTER
	big.add_theme_constant_override("separation", 22)
	vb.add_child(big)
	for col in [["power_throw", 5, 0], ["power_throw", 10, 5], ["grand_slam_barrage", 5, 0], ["grand_slam_barrage", 8, 3]]:
		var cv: CardView = make.call(str(col[0]), col.slice(0), Vector2(180, 252))
		big.add_child(cv)
	var small := VBoxContainer.new()
	small.add_theme_constant_override("separation", 8)
	big.add_child(small)
	for cid in ["heat_wave", "thunderbolt"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		small.add_child(row)
		for col in cols:
			row.add_child(make.call(cid, col, Vector2(84, 118)))


func go_back() -> void:
	if _back_to == "main_menu" or not Router.SCENES.has(_back_to):
		super.go_back()
		return
	Audio.ui("ui_back")
	Profile.save_now()
	Router.goto(_back_to)
