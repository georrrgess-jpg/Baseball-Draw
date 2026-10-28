extends MenuScreen
## Cards & Deck.
## Top: YOUR DECK, eight slots. Click a deck card to remove it, drag cards to reorder;
## the next free slot glows. Deck changes save automatically once all 8 slots are full.
## Bottom left: the collection with category tabs, rarity chips, search and sort. Owned
## cards first; cards not collected yet sit in their own section with a link to card packs.
## Bottom right: the inspector for the hovered card. Upgrading lives in CardUpgradesScreen.

const SLOT_SIZE := Vector2(136, 190)
const SLOT_GAP := 10
const GRID_CARD := Vector2(150, 210)
const CLICK_SLOP := 9.0
const TARGET_TEXT := {"enemy": "One runner", "area": "An area you aim", "path": "A basepath",
	"defender": "One of your defenders", "none": "Instant, no aiming"}
const TABS := [["", "ALL", "collection"], ["offense", "OFFENSE", "offense"], ["control", "CONTROL", "control"],
	["defense", "DEFENSE", "defense"], ["utility", "UTILITY", "utility"], ["signature", "SIGNATURE", "star"]]
const SORTS := ["Sort: Rarity", "Sort: Cost", "Sort: Name", "Sort: Level"]

var collection_mode := false
var deck: Array = []
var selected := ""
var filter_rarity := ""
var filter_tab := ""
var search := ""
var sort_mode := 0
var _dirty := false

var _deck_panel: PanelContainer
var _slots: Array[Control] = []
var _slot_cards: Array = []          # CardView or null for each slot
var _glow_tween: Tween
var _count_label: Label
var _need_label: Label
var _stats_label: Label
var _saved_box: HBoxContainer
var _saved_tween: Tween
var _upgrade_badge: Label
var _col_views := {}                 # card id -> CardView in the collection
var _pills := {}                     # card id -> "IN DECK" label
var _owned_grid: GridContainer
var _locked_grid: GridContainer
var _owned_title: Label
var _locked_box: Control
var _locked_title: Label
var _empty_label: Label
var _new_label: Label
var _detail: VBoxContainer
var _tab_btns := {}
var _rarity_btns := {}
var _search: LineEdit
var _sets_row: HBoxContainer
var _press_id := ""
var _press_pos := Vector2.ZERO
var _press_from := -1


func _ready() -> void:
	CardUpgradesScreen.apply_debug_args()
	MasteryUI.apply_demo_args()
	collection_mode = Session.menu_tab == "collection"
	setup_screen("COLLECTION" if collection_mode else "CARDS & DECK",
		"Every ability card. New cards and upgrade copies come from card packs." if collection_mode
		else "Choose the 8 cards you take into every game.")
	deck = Profile.data.deck.duplicate()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo-remove="):   # screenshot helper: show a partly filled deck
			deck = deck.slice(0, maxi(0, deck.size() - int(a.split("=")[1])))
	content.add_theme_constant_override("separation", 12)
	if not collection_mode:
		content.add_child(_build_deck_panel())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	content.add_child(body)
	body.add_child(_build_collection())
	body.add_child(_build_inspector())
	selected = deck[0] if not deck.is_empty() else DB.card_order[0]
	if not collection_mode:
		_rebuild_deck()
		_update_deck_info()
	_refresh_collection()
	_refresh_detail()
	set_help("collection" if collection_mode else "deck_builder", _hint_targets, _hint_features)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--claim-set="):   # screenshot helper: the set-complete moment
			get_tree().create_timer(1.5).timeout.connect(_claim_set.bind(a.split("=")[1]))
		if a.begins_with("--inspect="):   # screenshot helper: show a card in the inspector
			_inspect.call_deferred(a.split("=")[1])


## Hint arrows: the deck slots, the card inspector (mastery) and the collection sets row.
func _hint_targets() -> Dictionary:
	return {"deck_intro": _deck_panel, "deck_mastery": _detail, "deck_sets": _sets_row}


## Feature hints shown automatically once the player has met them: mastery after a card has been
## played in a real game, sets once the player has packs or has opened one.
func _hint_features() -> Array:
	var extra: Array = []
	for cid in DB.card_order:
		if Profile.card_plays(cid) > 0:
			extra.append("deck_mastery")
			break
	if CollectionSets.claimable_count() > 0 or Profile.pack_count() > 0 or int(Profile.data.get("packs_opened", 0)) > 0:
		extra.append("deck_sets")
	return extra


# ================================================================ deck panel

func _build_deck_panel() -> Control:
	_deck_panel = panel(Color(0.03, 0.05, 0.1, 0.94), Color(UITheme.GOLD, 0.35), 14)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	_deck_panel.add_child(hb)

	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(250, 0)
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 0)
	hb.add_child(info)
	info.add_child(UITheme.title("YOUR DECK", 50, UITheme.GOLD))
	var cnt := HBoxContainer.new()
	cnt.add_theme_constant_override("separation", 14)
	_count_label = UITheme.label("", 46, UITheme.OFFWHITE, UITheme.font_header())
	cnt.add_child(_count_label)
	_saved_box = HBoxContainer.new()
	_saved_box.add_theme_constant_override("separation", 4)
	_saved_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_saved_box.add_child(UITheme.icon_rect("check", 24, UITheme.GREEN))
	_saved_box.add_child(UITheme.label("SAVED", 22, UITheme.GREEN, UITheme.font_body_bold()))
	_saved_box.modulate.a = 0.0
	cnt.add_child(_saved_box)
	info.add_child(cnt)
	_need_label = UITheme.label("", 22, UITheme.GOLD, UITheme.font_body_bold())
	_need_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_need_label.custom_minimum_size = Vector2(250, 0)
	info.add_child(_need_label)
	_stats_label = UITheme.label("", 18, UITheme.MUTED, UITheme.font_body_bold())
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.custom_minimum_size = Vector2(250, 0)
	info.add_child(_stats_label)

	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", SLOT_GAP)
	slots.alignment = BoxContainer.ALIGNMENT_CENTER
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(slots)
	for i in Profile.DECK_SIZE:
		var s := _make_slot(i)
		slots.add_child(s)
		_slots.append(s)
		_slot_cards.append(null)

	var act := VBoxContainer.new()
	act.custom_minimum_size = Vector2(270, 0)
	act.alignment = BoxContainer.ALIGNMENT_CENTER
	act.add_theme_constant_override("separation", 8)
	hb.add_child(act)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	act.add_child(row)
	var auto := UITheme.small_button("Auto Build", UITheme.GOLD, 22)
	auto.tooltip_text = "Fill the deck with a balanced pick of your best cards"
	auto.icon = DB.icon("special")
	auto.add_theme_constant_override("icon_max_width", 20)
	auto.pressed.connect(_auto_build)
	row.add_child(auto)
	var clear := UITheme.small_button("Clear", UITheme.SCARLET, 22)
	clear.tooltip_text = "Empty all 8 slots"
	clear.pressed.connect(_clear_deck)
	row.add_child(clear)
	for b in row.get_children():
		(b as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		(b as Button).custom_minimum_size = Vector2(0, 44)
	var test := UITheme.small_button("Test Deck on the Practice Field", UITheme.BLUE, 21)
	test.custom_minimum_size = Vector2(0, 44)
	test.pressed.connect(_test_deck)
	act.add_child(test)
	var up := UITheme.menu_button("UPGRADE CARDS  ▶", UITheme.GOLD, 28, -0.12)
	up.custom_minimum_size = Vector2(0, 58)
	up.tooltip_text = "Level up your cards with copies and coins"
	up.pressed.connect(_open_upgrades)
	act.add_child(up)
	_upgrade_badge = UITheme.label("", 19, Color.WHITE, UITheme.font_body_bold())
	_upgrade_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_upgrade_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bs := UITheme.panel_style(UITheme.SCARLET, Color.WHITE, 2, 14, 0)
	bs.content_margin_left = 7
	bs.content_margin_right = 7
	_upgrade_badge.add_theme_stylebox_override("normal", bs)
	_upgrade_badge.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_upgrade_badge.position = Vector2(-26, -12)
	_upgrade_badge.custom_minimum_size = Vector2(30, 28)
	_upgrade_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	up.add_child(_upgrade_badge)
	_update_upgrade_badge()
	return _deck_panel


func _make_slot(i: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = SLOT_SIZE
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := Panel.new()
	bg.name = "Bg"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", _slot_style(false))
	slot.add_child(bg)
	var empty := VBoxContainer.new()
	empty.name = "Empty"
	empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	empty.alignment = BoxContainer.ALIGNMENT_CENTER
	empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty.add_theme_constant_override("separation", 6)
	var plus := UITheme.icon_rect("plus", 50, Color(1, 1, 1, 0.55))
	plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	empty.add_child(plus)
	var num := UITheme.label("EMPTY", 18, Color(1, 1, 1, 0.4), UITheme.font_body_bold())
	num.name = "Text"
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_child(num)
	slot.add_child(empty)
	slot.set_drag_forwarding(func(_p: Vector2) -> Variant: return null, _can_drop_slot.bind(i), _drop_slot.bind(i))
	return slot


func _slot_style(next: bool) -> StyleBoxFlat:
	var s := UITheme.panel_style(Color(0.0, 0.02, 0.05, 0.55) if not next else Color(0.2, 0.15, 0.02, 0.55),
		Color(UITheme.GOLD, 0.95) if next else Color(1, 1, 1, 0.16), 3 if next else 2, 12, 0)
	return s


## Rebuilds the cards in the slots. `hidden` stays invisible (a card is flying to it);
## cards from `slide_from` on slide in from the right (a card before them was removed).
func _rebuild_deck(hidden := -1, slide_from := -1) -> void:
	if _deck_panel == null:
		return
	if _glow_tween:
		_glow_tween.kill()
	for i in Profile.DECK_SIZE:
		var slot := _slots[i]
		var old: Variant = _slot_cards[i]
		if old != null and is_instance_valid(old):
			(old as Node).queue_free()
		_slot_cards[i] = null
		var empty := slot.get_node("Empty") as Control
		var bg := slot.get_node("Bg") as Panel
		empty.modulate.a = 1.0
		var is_next := i == deck.size()
		bg.add_theme_stylebox_override("panel", _slot_style(is_next))
		var txt := empty.get_node("Text") as Label
		txt.text = "ADD A CARD" if is_next else "EMPTY"
		txt.add_theme_color_override("font_color", Color(UITheme.GOLD, 0.95) if is_next else Color(1, 1, 1, 0.4))
		(empty.get_child(0) as TextureRect).modulate = Color(UITheme.GOLD, 0.95) if is_next else Color(1, 1, 1, 0.45)
		if i >= deck.size():
			empty.visible = true
			if is_next:
				_glow_tween = empty.create_tween().set_loops()
				_glow_tween.tween_property(empty, "modulate:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
				_glow_tween.tween_property(empty, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)
			continue
		empty.visible = false
		var cid: String = deck[i]
		var cv := CardView.new(cid, Profile.card_level(cid))
		cv.set_card(cid, Profile.card_level(cid))
		cv.custom_minimum_size = SLOT_SIZE
		cv.size = SLOT_SIZE
		cv.mastery = CardMastery.stars(cid)
		cv.tooltip_text = "Click to remove · drag to reorder"
		var idx := i
		cv.gui_input.connect(func(e: InputEvent) -> void: _card_input(e, cid, cv, idx))
		cv.hovered.connect(func(_c: CardView, on: bool) -> void:
			if on:
				_inspect(cid))
		cv.set_drag_forwarding(_drag_card.bind(cid, idx), _can_drop_slot.bind(i), _drop_slot.bind(i))
		slot.add_child(cv)
		_slot_cards[i] = cv
		if i == hidden:
			cv.modulate.a = 0.0
		if slide_from >= 0 and i >= slide_from:
			cv.position.x = SLOT_SIZE.x + SLOT_GAP
			cv.create_tween().tween_property(cv, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _update_deck_info() -> void:
	if _deck_panel == null:
		return
	var n := deck.size()
	_count_label.text = "%d / %d" % [n, Profile.DECK_SIZE]
	_count_label.add_theme_color_override("font_color", UITheme.GREEN if n == Profile.DECK_SIZE else UITheme.OFFWHITE)
	if n == Profile.DECK_SIZE:
		_need_label.text = "Ready to play!"
		_need_label.add_theme_color_override("font_color", UITheme.GREEN)
	else:
		var miss := Profile.DECK_SIZE - n
		_need_label.text = "Add %d more card%s" % [miss, "" if miss == 1 else "s"]
		_need_label.add_theme_color_override("font_color", UITheme.GOLD)
	var total := 0
	for cid in deck:
		total += int(DB.card(cid).cost)
	var combos := 0
	for cb in DB.combos:
		if cb.cards[0] in deck and cb.cards[1] in deck:
			combos += 1
	if n == 0:
		_stats_label.text = "Click cards below to add them."
	else:
		_stats_label.text = "Avg cost %.1f  ·  %d combo%s" % [float(total) / n, combos, "" if combos == 1 else "s"]


func _update_upgrade_badge() -> void:
	if _upgrade_badge == null:
		return
	var n := 0
	for cid in DB.card_order:
		if Profile.can_upgrade_card(cid):
			n += 1
	_upgrade_badge.text = str(n)
	_upgrade_badge.visible = n > 0
	_upgrade_badge.tooltip_text = "%d card%s ready to upgrade" % [n, "" if n == 1 else "s"]


func _flash_saved() -> void:
	if _saved_tween:
		_saved_tween.kill()
	_saved_box.modulate.a = 1.0
	_saved_box.scale = Vector2(1.15, 1.15)
	_saved_tween = _saved_box.create_tween()
	_saved_tween.tween_property(_saved_box, "scale", Vector2.ONE, 0.2)
	_saved_tween.tween_interval(1.4)
	_saved_tween.tween_property(_saved_box, "modulate:a", 0.0, 0.5)


## Called after every deck edit: saves a complete deck and refreshes the marks.
func _after_change() -> void:
	_dirty = true
	if deck.size() == Profile.DECK_SIZE and Profile.set_deck(deck):
		_dirty = false
		_flash_saved()
	_update_deck_info()
	_update_marks()
	_refresh_detail()


# ================================================================ deck edits

func _add_card(id: String, from: Control) -> void:
	if collection_mode:
		return
	if not Profile.is_card_owned(id):
		Audio.ui("ui_error")
		return
	if id in deck:
		_remove_at(deck.find(id))
		return
	if deck.size() >= Profile.DECK_SIZE:
		_deck_full()
		return
	var idx := deck.size()
	deck.append(id)
	Audio.play("card_whoosh", -6.0)
	_rebuild_deck(idx)
	_fly(id, from.get_global_rect(), idx)
	_after_change()


func _remove_at(i: int) -> void:
	if i < 0 or i >= deck.size():
		return
	var cv: Variant = _slot_cards[i]
	deck.remove_at(i)
	_slot_cards[i] = null
	Audio.ui("ui_back")
	if cv != null and is_instance_valid(cv):
		var ghost := cv as CardView
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.reparent(self)
		ghost.pivot_offset = ghost.size * 0.5
		var tw := ghost.create_tween().set_parallel()
		tw.tween_property(ghost, "scale", Vector2(0.55, 0.55), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(ghost, "position:y", ghost.position.y + 70.0, 0.22).set_ease(Tween.EASE_IN)
		tw.tween_property(ghost, "modulate:a", 0.0, 0.22)
		tw.chain().tween_callback(ghost.queue_free)
	_rebuild_deck(-1, i)
	_after_change()


## A copy of the card flies from the collection into its slot.
func _fly(id: String, src: Rect2, idx: int) -> void:
	var fc := CardView.new(id, Profile.card_level(id))
	fc.set_card(id, Profile.card_level(id))
	fc.custom_minimum_size = Vector2.ZERO
	fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fc.show_level = false
	add_child(fc)
	fc.position = src.position - global_position
	fc.size = src.size
	fc.z_index = 20
	var dst := _slots[idx].get_global_rect()
	var mid := (src.position + dst.position) * 0.5 - global_position + Vector2(0, -60)
	var tw := fc.create_tween()
	tw.set_parallel()
	tw.tween_method(func(t: float) -> void:
		var a := (src.position - global_position).lerp(mid, t)
		var b := mid.lerp(dst.position - global_position, t)
		fc.position = a.lerp(b, t)
		fc.size = src.size.lerp(dst.size, t)
		fc.pivot_offset = fc.size * 0.5
		fc.rotation = sin(t * PI) * -0.12, 0.0, 1.0, 0.36).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.chain().tween_callback(func() -> void:
		fc.queue_free()
		_land(idx, id))


func _land(idx: int, id: String) -> void:
	if idx >= _slot_cards.size():
		return
	var cv: Variant = _slot_cards[idx]
	if cv == null or not is_instance_valid(cv) or (cv as CardView).card_id != id:
		return
	_pop(cv as CardView)
	Audio.play("card_draw", -5.0)


func _pop(cv: CardView, delay := 0.0) -> void:
	cv.pivot_offset = SLOT_SIZE * 0.5
	var tw := cv.create_tween()
	if delay > 0.0:
		cv.modulate.a = 0.0
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void:
		cv.modulate.a = 1.0
		cv.scale = Vector2(1.18, 1.18))
	tw.tween_property(cv, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _deck_full() -> void:
	Audio.ui("ui_error")
	_need_label.text = "Deck is full! Click a deck card to remove it first."
	_need_label.add_theme_color_override("font_color", UITheme.SCARLET)
	var x := _deck_panel.position.x
	var tw := _deck_panel.create_tween()
	for k in 4:
		tw.tween_property(_deck_panel, "position:x", x + (9.0 if k % 2 == 0 else -9.0), 0.04)
	tw.tween_property(_deck_panel, "position:x", x, 0.04)
	tw.tween_interval(1.8)
	tw.tween_callback(_update_deck_info)


func _clear_deck() -> void:
	if deck.is_empty():
		return
	for i in range(deck.size() - 1, -1, -1):
		var cv: Variant = _slot_cards[i]
		if cv != null and is_instance_valid(cv):
			var c := cv as CardView
			c.pivot_offset = c.size * 0.5
			var tw := c.create_tween().set_parallel()
			tw.tween_property(c, "scale", Vector2(0.6, 0.6), 0.18).set_delay(0.025 * i)
			tw.tween_property(c, "modulate:a", 0.0, 0.18).set_delay(0.025 * i)
	deck.clear()
	Audio.ui("ui_back")
	_after_change()
	await get_tree().create_timer(0.4).timeout
	if is_inside_tree() and deck.is_empty():
		_rebuild_deck()


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
	Audio.play("card_whoosh", -4.0)
	_rebuild_deck()
	for i in deck.size():
		if _slot_cards[i] != null:
			_pop(_slot_cards[i] as CardView, 0.05 * i)
	_after_change()


func _test_deck() -> void:
	if deck.is_empty():
		Router.toast("Add some cards first.", "warn")
		return
	var cfg := Session.new_run_config("practice")
	cfg.deck = deck.duplicate()
	Session.start(cfg)


func _open_upgrades() -> void:
	if deck.size() == Profile.DECK_SIZE:
		Profile.set_deck(deck)
		_dirty = false
	Router.open("card_upgrades")   # BACK returns here


# ================================================================ input, drag & drop

## Click = press and release without moving (so dragging never adds a card by accident).
func _card_input(e: InputEvent, id: String, cv: CardView, deck_index: int) -> void:
	if not e is InputEventMouseButton:
		return
	var mb := e as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_inspect(id)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_press_id = id
		_press_from = deck_index
		_press_pos = mb.position
		_inspect(id)
	elif _press_id == id and _press_from == deck_index and mb.position.distance_to(_press_pos) < CLICK_SLOP:
		_press_id = ""
		if deck_index >= 0:
			_remove_at(deck_index)
		else:
			_add_card(id, cv)


func _drag_card(_pos: Vector2, id: String, from_index: int) -> Variant:
	if collection_mode or not Profile.is_card_owned(id):
		return null
	_press_id = ""
	var wrap := Control.new()
	var pv := CardView.new(id, Profile.card_level(id))
	pv.set_card(id, Profile.card_level(id))
	pv.custom_minimum_size = SLOT_SIZE * 0.9
	pv.size = SLOT_SIZE * 0.9
	pv.position = -SLOT_SIZE * 0.45
	pv.rotation = -0.06
	pv.modulate.a = 0.92
	wrap.add_child(pv)
	set_drag_preview(wrap)
	Audio.play("card_hover", -6.0)
	return {"deck_card": id, "from": from_index}


func _can_drop_slot(_pos: Vector2, data: Variant, _i: int) -> bool:
	return not collection_mode and data is Dictionary and (data as Dictionary).has("deck_card")


func _drop_slot(_pos: Vector2, data: Variant, i: int) -> void:
	var id: String = data.deck_card
	var from: int = data.from
	var target := i
	if from >= 0:
		target = mini(i, deck.size() - 1)
		if target == from:
			return
		var tmp: String = deck[target]
		deck[target] = deck[from]
		deck[from] = tmp
	elif id in deck:
		var k := deck.find(id)
		target = mini(i, deck.size() - 1)
		var tmp2: String = deck[target]
		deck[target] = id
		deck[k] = tmp2
	elif i < deck.size():
		deck[i] = id
	elif deck.size() < Profile.DECK_SIZE:
		deck.append(id)
		target = deck.size() - 1
	else:
		_deck_full()
		return
	Audio.play("card_draw", -5.0)
	_rebuild_deck()
	if _slot_cards[target] != null:
		_pop(_slot_cards[target] as CardView)
	_after_change()


## Dropping a deck card anywhere on the collection removes it from the deck.
func _accept_removals(c: Control) -> void:
	c.set_drag_forwarding(func(_q: Vector2) -> Variant: return null, _can_drop_collection, _drop_collection)


func _can_drop_collection(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and int((data as Dictionary).get("from", -1)) >= 0


func _drop_collection(_pos: Vector2, data: Variant) -> void:
	_remove_at(int(data.from))


# ================================================================ collection

func _build_collection() -> Control:
	var p := panel(Color(0.035, 0.06, 0.1, 0.9), Color(1, 1, 1, 0.08), 14)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accept_removals(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 6)
	vb.add_child(row1)
	for t in TABS:
		var key: String = t[0]
		var b := UITheme.small_button(t[1], UITheme.SCARLET, 22)
		b.toggle_mode = true
		b.button_pressed = key == filter_tab
		b.icon = DB.icon(t[2])
		b.add_theme_constant_override("icon_max_width", 22)
		var col: Color = DB.category_color(key) if key in DB.CATEGORY_ORDER else (UITheme.GOLD if key == "signature" else UITheme.OFFWHITE)
		b.add_theme_color_override("icon_normal_color", col)
		b.add_theme_color_override("icon_pressed_color", Color.WHITE)
		b.add_theme_stylebox_override("pressed", UITheme.button_style(UITheme.SCARLET_DEEP, UITheme.SCARLET, 0.0, 2))
		b.custom_minimum_size = Vector2(0, 46)
		if key == "signature":
			b.tooltip_text = "Signature cards belong to a defender, who casts them on the field"
		b.pressed.connect(func() -> void:
			filter_tab = key
			for k in _tab_btns.keys():
				_tab_btns[k].button_pressed = k == filter_tab
			Audio.ui("ui_tab")
			_refresh_collection())
		row1.add_child(b)
		_tab_btns[key] = b
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(sp)
	_new_label = UITheme.label("", 20, Color.WHITE, UITheme.font_body_bold())
	var ns := UITheme.panel_style(UITheme.SCARLET, Color(0, 0, 0, 0), 0, 8, 0)
	ns.content_margin_left = 10
	ns.content_margin_right = 10
	_new_label.add_theme_stylebox_override("normal", ns)
	_new_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row1.add_child(_new_label)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 6)
	vb.add_child(row2)
	row2.add_child(UITheme.label("RARITY", 18, UITheme.MUTED, UITheme.font_body_bold()))
	for r in [""] + DB.RARITY_ORDER:
		var rk: String = r
		var b := UITheme.small_button("Any" if rk == "" else rk.capitalize(), DB.rarity_color(rk) if rk != "" else UITheme.OFFWHITE, 19)
		b.toggle_mode = true
		b.button_pressed = rk == filter_rarity
		b.add_theme_color_override("font_color", DB.rarity_color(rk) if rk != "" else UITheme.OFFWHITE)
		b.add_theme_stylebox_override("pressed", UITheme.button_style(Color(0.16, 0.2, 0.3, 1), DB.rarity_color(rk) if rk != "" else UITheme.OFFWHITE, 0.0, 2))
		b.add_theme_color_override("font_pressed_color", Color.WHITE)
		b.pressed.connect(func() -> void:
			filter_rarity = rk
			for k in _rarity_btns.keys():
				_rarity_btns[k].button_pressed = k == filter_rarity
			_refresh_collection())
		row2.add_child(b)
		_rarity_btns[rk] = b
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(sp2)
	row2.add_child(UITheme.icon_rect("search", 24, UITheme.MUTED))
	_search = LineEdit.new()
	_search.placeholder_text = "Search cards (F)"
	_search.custom_minimum_size = Vector2(230, 0)
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(t: String) -> void:
		search = t.to_lower()
		_refresh_collection())
	row2.add_child(_search)
	var sort := OptionButton.new()
	for s in SORTS:
		sort.add_item(s)
	sort.item_selected.connect(func(i: int) -> void:
		sort_mode = i
		_refresh_collection())
	row2.add_child(sort)

	# Collection book: set completion per category, with a one-time reward per set.
	_sets_row = HBoxContainer.new()
	_sets_row.add_theme_constant_override("separation", 8)
	vb.add_child(_sets_row)
	_refresh_sets()

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_accept_removals(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var oh := HBoxContainer.new()
	oh.add_theme_constant_override("separation", 14)
	_owned_title = UITheme.header("", 30, UITheme.OFFWHITE)
	oh.add_child(_owned_title)
	var hint := UITheme.label("Click a card to add or remove it  ·  drag it onto a slot  ·  hover to see details" if not collection_mode
		else "Hover a card to see its details", 19, UITheme.MUTED, UITheme.font_body_bold())
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	oh.add_child(hint)
	list.add_child(oh)
	_owned_grid = _make_grid()
	list.add_child(_owned_grid)
	_empty_label = UITheme.label("No cards you own match these filters.", 20, UITheme.MUTED)
	list.add_child(_empty_label)

	var lp := panel(Color(0.02, 0.03, 0.06, 0.8), Color(1, 1, 1, 0.08), 10)
	_locked_box = lp
	list.add_child(lp)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 12)
	lp.add_child(lh)
	lh.add_child(UITheme.icon_rect("lock", 30, UITheme.MUTED))
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", -4)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locked_title = UITheme.header("", 28, UITheme.MUTED)
	lv.add_child(_locked_title)
	lv.add_child(UITheme.label("Find these in card packs. Win games and level up to earn packs.", 18, UITheme.MUTED, UITheme.font_body_bold()))
	lh.add_child(lv)
	var go := UITheme.small_button("Open Card Packs  ▶", UITheme.BLUE, 21)
	go.custom_minimum_size = Vector2(0, 44)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.pressed.connect(func() -> void:
		_save_before_leaving()
		Router.open("packs"))
	lh.add_child(go)
	_locked_grid = _make_grid()
	list.add_child(_locked_grid)
	return p


func _make_grid() -> GridContainer:
	var g := GridContainer.new()
	_accept_removals(g)
	g.columns = 8
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 14)
	return g


func _matches(cid: String) -> bool:
	var c := DB.card(cid)
	if filter_rarity != "" and c.rarity != filter_rarity:
		return false
	if filter_tab == "signature":
		if str(c.get("linked", "")) == "":
			return false
	elif filter_tab != "" and c.category != filter_tab:
		return false
	if search != "" and not (search in str(c.name).to_lower() or search in DB.card_text(cid, 1).to_lower()):
		return false
	return true


func _sorted(ids: Array) -> Array:
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := DB.card(a)
		var cb := DB.card(b)
		match sort_mode:
			1:
				return int(ca.cost) < int(cb.cost) if int(ca.cost) != int(cb.cost) else str(ca.name) < str(cb.name)
			2:
				return str(ca.name) < str(cb.name)
			3:
				var la := Profile.card_level(a)
				var lb := Profile.card_level(b)
				return la > lb if la != lb else str(ca.name) < str(cb.name)
		var ra := DB.RARITY_ORDER.find(ca.rarity)
		var rb := DB.RARITY_ORDER.find(cb.rarity)
		return ra > rb if ra != rb else str(ca.name) < str(cb.name))
	return ids


func _refresh_collection() -> void:
	for g in [_owned_grid, _locked_grid]:
		for c in g.get_children():
			c.queue_free()
	_col_views.clear()
	_pills.clear()
	var owned: Array = []
	var locked: Array = []
	var total_owned := 0
	for cid in DB.card_order:
		if Profile.is_card_owned(cid):
			total_owned += 1
		if not _matches(cid):
			continue
		if Profile.is_card_owned(cid):
			owned.append(cid)
		else:
			locked.append(cid)
	for cid in _sorted(owned):
		_owned_grid.add_child(_make_grid_card(cid))
	for cid in _sorted(locked):
		_locked_grid.add_child(_make_grid_card(cid))
	_owned_title.text = "YOUR CARDS  %d / %d" % [total_owned, DB.card_order.size()]
	_empty_label.visible = owned.is_empty()
	_locked_box.visible = not locked.is_empty()
	_locked_title.text = "NOT COLLECTED YET  (%d)" % locked.size()
	_update_new_label()


func _make_grid_card(cid: String) -> Control:
	var cell := Control.new()
	cell.custom_minimum_size = GRID_CARD + Vector2(0, 12)
	cell.mouse_filter = Control.MOUSE_FILTER_PASS
	var owned := Profile.is_card_owned(cid)
	var cv := CardView.new(cid, Profile.card_level(cid))
	cv.set_card(cid, Profile.card_level(cid))
	cv.custom_minimum_size = GRID_CARD
	cv.size = GRID_CARD
	cv.owned = owned
	cv.show_level = owned
	cv.mastery = CardMastery.stars(cid)
	cv.selected = cid == selected
	cv.count_badge = _badge_for(cid)
	cv.gui_input.connect(func(e: InputEvent) -> void: _card_input(e, cid, cv, -1))
	cv.hovered.connect(func(_c: CardView, on: bool) -> void:
		if on:
			_inspect(cid))
	cv.set_drag_forwarding(_drag_card.bind(cid, -1), _can_drop_collection, _drop_collection)
	_accept_removals(cell)
	cell.add_child(cv)
	_col_views[cid] = cv
	if owned and not collection_mode:
		var pill := UITheme.label("IN DECK", 17, Color(0.02, 0.1, 0.05), UITheme.font_body_bold())
		pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pill.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pill.add_theme_stylebox_override("normal", UITheme.panel_style(UITheme.GREEN, Color(0.02, 0.08, 0.04, 0.9), 2, 12, 0))
		pill.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
		pill.custom_minimum_size = Vector2(92, 26)
		pill.size = pill.custom_minimum_size
		pill.position = Vector2((GRID_CARD.x - 92.0) * 0.5, GRID_CARD.y - 14.0)
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.visible = cid in deck
		cell.add_child(pill)
		_pills[cid] = pill
	return cell


func _badge_for(cid: String) -> String:
	if not Profile.is_card_owned(cid):
		return ""
	if bool(Profile.data.cards.get(cid, {}).get("fresh", false)):
		return "NEW"
	if Profile.can_upgrade_card(cid):
		return "▲"
	return ""


## Updates the IN DECK pills without rebuilding the grid (keeps hover state).
func _update_marks() -> void:
	for cid in _pills.keys():
		var pill: Label = _pills[cid]
		var on: bool = cid in deck
		if pill.visible != on:
			pill.visible = on
			if on:
				pill.pivot_offset = pill.size * 0.5
				pill.scale = Vector2(0.4, 0.4)
				pill.create_tween().tween_property(pill, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_new_label() -> void:
	var n := Profile.fresh_card_count()
	_new_label.text = "%d NEW CARD%s" % [n, "" if n == 1 else "S"]
	_new_label.visible = n > 0


func _inspect(id: String) -> void:
	if bool(Profile.data.cards.get(id, {}).get("fresh", false)):
		Profile.mark_card_seen(id)
		if _col_views.has(id):
			var v: CardView = _col_views[id]
			v.count_badge = _badge_for(id)
			v.refresh()
		_update_new_label()
	if id == selected:
		return
	if _col_views.has(selected):
		var old: CardView = _col_views[selected]
		old.selected = false
		old.refresh()
	selected = id
	if _col_views.has(id):
		var cur: CardView = _col_views[id]
		cur.selected = true
		cur.refresh()
	_refresh_detail()


# ================================================================ collection sets

func _refresh_sets() -> void:
	if _sets_row == null:
		return
	for c in _sets_row.get_children():
		c.queue_free()
	for sid in CollectionSets.ids():
		_sets_row.add_child(_set_tile(sid))


func _set_tile(sid: String) -> Control:
	var inf := CollectionSets.info(sid)
	var prog := CollectionSets.progress(sid)
	var complete := CollectionSets.is_complete(sid)
	var claimed := CollectionSets.is_claimed(sid)
	var claimable := complete and not claimed
	var col: Color = DB.category_color(sid) if sid in DB.CATEGORY_ORDER else UITheme.GOLD
	var tile := UITheme.tile_panel(Color(UITheme.GOLD if claimable else col, 0.9 if claimable else 0.35), 8, claimable)
	tile.name = "Set_" + sid
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size = Vector2(150, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	tile.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	top.add_child(UITheme.icon_rect(str(inf[2]), 20, col.lightened(0.2)))
	var nm := UITheme.label(str(inf[1]), UITheme.FS_MIN, UITheme.OFFWHITE, UITheme.font_body_bold())
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if claimed:
		top.add_child(UITheme.icon_rect("check", 20, UITheme.GREEN))
	else:
		top.add_child(UITheme.label("%d/%d" % [int(prog.owned), int(prog.total)], UITheme.FS_SMALL, UITheme.GOLD if complete else UITheme.OFFWHITE, UITheme.font_header()))
	var pack_name: String = DB.pack(CollectionSets.reward_pack(sid)).get("name", "Pack")
	if claimable:
		var b := UITheme.button("CLAIM %s" % pack_name.to_upper(), "primary", UITheme.FS_MIN, "gift", UITheme.GOLD.darkened(0.25))
		b.custom_minimum_size = Vector2(0, 32)
		b.pressed.connect(func() -> void: _claim_set(sid))
		vb.add_child(b)
		var pulse := tile.create_tween().set_loops()
		pulse.tween_property(tile, "self_modulate", Color(1.25, 1.15, 0.85), 0.7).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(tile, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	else:
		var bar := UITheme.bar(UITheme.GREEN if claimed else col, 8, float(maxi(1, int(prog.total))), float(prog.owned))
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vb.add_child(bar)
	if claimed:
		tile.tooltip_text = "%s set complete. Reward claimed: %s." % [str(inf[1]).capitalize(), pack_name]
	else:
		var left := int(prog.total) - int(prog.owned)
		tile.tooltip_text = "%s set: %d of %d cards collected. Collect %s for a %s." % [str(inf[1]).capitalize(), int(prog.owned), int(prog.total),
			"the last %d" % left if left > 0 else "them all", pack_name] if not claimable else "Set complete! Claim your %s." % pack_name
	return tile


## Claims a set's reward with a short celebration: the pack drops in over a burst of light.
func _claim_set(sid: String) -> void:
	var pack := CollectionSets.claim(sid)
	if pack == "":
		return
	Audio.play("achievement")
	Audio.play("crowd_cheer", -10.0)
	_refresh_sets()
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 50
	add_child(layer)
	push_overlay(layer)   # Esc closes the celebration first
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.72, 0.25)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.8), 28, Color(0.05, 0.07, 0.12, 0.97), 2)
	p.custom_minimum_size = Vector2(560, 0)
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vb)
	var inf := CollectionSets.info(sid)
	var t := UITheme.title("%s SET COMPLETE!" % str(inf[1]) if sid != "all" else "COLLECTION COMPLETE!", 48, UITheme.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var art_box := CenterContainer.new()
	art_box.custom_minimum_size = Vector2(0, 230)
	vb.add_child(art_box)
	var rays := _Rays.new()
	rays.custom_minimum_size = Vector2(260, 230)
	art_box.add_child(rays)
	var art := PackArt.new(pack)
	art.custom_minimum_size = Vector2(130, 200)
	art.position = Vector2(65, 15)
	art.pivot_offset = Vector2(65, 100)
	art.scale = Vector2(0.2, 0.2)
	art.rotation = -0.5
	rays.add_child(art)
	var at := art.create_tween().set_parallel()
	at.tween_property(art, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	at.tween_property(art, "rotation", 0.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var l := UITheme.label("+1 %s added to your packs" % str(DB.pack(pack).get("name", "Pack")), UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_body_bold())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	vb.add_child(row)
	var open := UITheme.button("OPEN PACKS", "primary", UITheme.FS_LEAD, "gift", UITheme.GOLD.darkened(0.25))
	open.pressed.connect(func() -> void:
		_save_before_leaving()
		Router.open("packs"))
	row.add_child(open)
	var ok := UITheme.button("NICE!", "secondary", UITheme.FS_LEAD)
	ok.pressed.connect(func() -> void:
		var ft := layer.create_tween()
		ft.tween_property(layer, "modulate:a", 0.0, 0.18)
		ft.tween_callback(layer.queue_free))
	row.add_child(ok)
	UITheme.animate_in(p, 0.0, 0.85)


func _save_before_leaving() -> void:
	if _dirty and deck.size() == Profile.DECK_SIZE:
		Profile.set_deck(deck)
		_dirty = false


## Slowly turning light rays behind a reward.
class _Rays extends Control:
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		for i in 12:
			var a := _t * 0.35 + TAU * i / 12.0
			var w := 0.12
			var r := maxf(size.x, size.y) * 0.62
			var g := Color(1.0, 0.82, 0.3, 0.32)
			draw_polygon(PackedVector2Array([c, c + Vector2(cos(a - w), sin(a - w)) * r, c + Vector2(cos(a + w), sin(a + w)) * r]),
				PackedColorArray([g, Color(g, 0.0), Color(g, 0.0)]))
		draw_circle(c, 60.0, Color(1.0, 0.85, 0.4, 0.1))


# ================================================================ inspector

func _build_inspector() -> Control:
	var p := panel(Color(0.04, 0.065, 0.11, 0.95), Color(1, 1, 1, 0.1), 16)
	p.custom_minimum_size = Vector2(450, 0)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	_detail = VBoxContainer.new()
	_detail.custom_minimum_size = Vector2(410, 0)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 10)
	sc.add_child(_detail)
	return p


func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	if selected == "":
		return
	var c := DB.card(selected)
	var lvl := Profile.card_level(selected)
	var owned := Profile.is_card_owned(selected)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	_detail.add_child(top)
	var big := CardView.new(selected, lvl)
	big.set_card(selected, lvl)
	big.custom_minimum_size = Vector2(180, 252)
	big.owned = owned
	big.mastery = CardMastery.stars(selected)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(big)
	var stats := VBoxContainer.new()
	stats.add_theme_constant_override("separation", 6)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(stats)
	stats.add_child(_stat("energy", "ENERGY COST", str(int(c.cost)), UITheme.ENERGY))
	stats.add_child(_stat("cooldown", "COOLDOWN", ("%ds" % int(c.cooldown)) if float(c.cooldown) > 0 else "None", UITheme.OFFWHITE))
	stats.add_child(_stat("target", "TARGET", str(TARGET_TEXT.get(str(c.target), str(c.target))), UITheme.OFFWHITE))
	stats.add_child(_stat(str(c.category), str(c.category).to_upper(), str(c.rarity).capitalize(), DB.rarity_color(c.rarity)))
	if owned:
		stats.add_child(_stat("upgrade", "LEVEL", "%d / %d" % [lvl, DB.card_max_level], UITheme.GOLD))

	var nm := UITheme.title(str(c.name).to_upper(), 40)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(nm)
	var desc := UITheme.label(DB.card_text(selected, lvl), 22, UITheme.OFFWHITE)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(desc)
	if owned or Profile.card_plays(selected) > 0:
		_detail.add_child(MasteryUI.block(selected))

	var linked: String = c.get("linked", "")
	if linked != "":
		var acc := DB.defender_accent(linked)
		var lrow := HBoxContainer.new()
		lrow.add_theme_constant_override("separation", 10)
		lrow.add_child(portrait_rect(linked, 40, acc))
		var ll := UITheme.label("Signature card of %s. %s casts it with their own power." % [DB.defender(linked).name, DB.defender(linked).name],
			18, acc.lightened(0.35), UITheme.font_body_bold())
		ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lrow.add_child(ll)
		_detail.add_child(lrow)

	var combos := DB.combos_for(selected)
	if not combos.is_empty():
		_detail.add_child(UITheme.hsep())
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 8)
		ch.add_child(UITheme.icon_rect("synergy", 24, UITheme.GOLD))
		ch.add_child(UITheme.header("COMBOS", 26, UITheme.GOLD))
		_detail.add_child(ch)
		for cb in combos:
			var other := DB.card(cb.card)
			var in_deck: bool = cb.card in deck
			var row := VBoxContainer.new()
			row.add_theme_constant_override("separation", -2)
			var head := UITheme.label("+ %s%s" % [other.name, "  (in your deck)" if in_deck else ""], 19,
				UITheme.GREEN if in_deck else DB.category_color(other.category).lightened(0.3), UITheme.font_body_bold())
			row.add_child(head)
			var t := UITheme.label(str(cb.text), 17, UITheme.MUTED)
			t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(t)
			_detail.add_child(row)

	_detail.add_child(UITheme.hsep())
	if not owned:
		var lk := HBoxContainer.new()
		lk.add_theme_constant_override("separation", 10)
		lk.add_child(UITheme.icon_rect("lock", 26, UITheme.SCARLET))
		var ll2 := UITheme.label("Not collected yet. Find it in card packs.", 20, UITheme.SCARLET, UITheme.font_body_bold())
		ll2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ll2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lk.add_child(ll2)
		_detail.add_child(lk)
		var go := UITheme.small_button("Open Card Packs  ▶", UITheme.BLUE, 22)
		go.custom_minimum_size = Vector2(0, 46)
		go.pressed.connect(func() -> void:
			_save_before_leaving()
			Router.open("packs"))
		_detail.add_child(go)
		return
	if collection_mode:
		return
	var in_deck := selected in deck
	var id := selected
	var btn := UITheme.small_button("Remove from Deck" if in_deck else "Add to Deck", UITheme.SCARLET if in_deck else UITheme.GREEN, 24)
	btn.custom_minimum_size = Vector2(0, 50)
	btn.disabled = not in_deck and deck.size() >= Profile.DECK_SIZE
	btn.pressed.connect(func() -> void:
		if id in deck:
			_remove_at(deck.find(id))
		elif _col_views.has(id):
			_add_card(id, _col_views[id]))
	_detail.add_child(btn)
	if Profile.can_upgrade_card(selected):
		var up := UITheme.label("▲  Ready to upgrade: open UPGRADE CARDS", 18, UITheme.GOLD, UITheme.font_body_bold())
		_detail.add_child(up)


func _stat(icon: String, title: String, value: String, col: Color) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var ic := UITheme.icon_rect(icon, 26, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(ic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -6)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(UITheme.label(title, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	var v := UITheme.label(value, 22, col, UITheme.font_body_bold())
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(v)
	hb.add_child(vb)
	return hb


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
		Router.toast("Deck not saved: it needs all 8 cards. Your last full deck is kept.", "warn")
	super.go_back()
