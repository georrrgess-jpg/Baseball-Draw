class_name ShopScreen
extends MenuScreen
## The Shop (Update 9): today's deals (a free gift, two card deals, a pack deal and a star deal,
## each bought once per day) with the countdown to the midnight refresh, the pack shop (same
## prices as Card Packs) and the free agents: new defenders signed early for coins.
## Data and rules: Shop (src/core/shop.gd). `Router.open("shop", "agents")` opens it scrolled to
## the free agents.

## kind -> [caption, icon]
const KINDS := {
	"gift": ["FREE GIFT", "gift"],
	"card": ["CARD DEAL", "deck"],
	"pack": ["PACK DEAL", "gift"],
	"stars": ["STAR DEAL", "star"],
}
const DEAL_CARD := Vector2(164, 230)

var _root: VBoxContainer
var _scroll: ScrollContainer
var _deals_row: HBoxContainer
var _countdown: Label
var _packs_row: HBoxContainer
var _packs_owned: Label
var _agents_row: HBoxContainer
var _agents_panel: Control
## offer id -> its BUY / CLAIM button; "type:count" -> pack shop button; defender id -> SIGN button.
var deal_buttons := {}
var pack_buttons := {}
var agent_buttons := {}
var _flash_id := ""
var _tick := 0.0
var _last_secs := -1


func _ready() -> void:
	setup_screen("SHOP", "Daily deals, a free gift, card packs and free agents")
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	content.add_child(_scroll)
	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 14)
	_scroll.add_child(_root)
	_root.add_child(_deals_panel())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	_root.add_child(bottom)
	bottom.add_child(_pack_shop_panel())
	_agents_panel = _agents_panel_build()
	bottom.add_child(_agents_panel)
	_refresh()
	if Hints.SCREENS.has("shop"):
		set_help("shop", func() -> Dictionary: return {"shop_intro": _deals_row})
	if Router.open_arg == "agents":
		_scroll_to_agents.call_deferred()
	_focus_first.call_deferred()


func _enter_targets() -> Array:
	return _root.get_children() if _root else []


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or _countdown == null:
		return
	_tick = 0.5
	var secs := Shop.seconds_to_refresh()
	_countdown.text = "NEW DEALS IN  " + format_countdown(secs)
	# Midnight passed while the screen was open: today's deals are new.
	if _last_secs >= 0 and secs > _last_secs + 60:
		_refresh()
	_last_secs = secs


## "05:12:33" (hours:minutes:seconds) for the refresh countdown.
static func format_countdown(secs: int) -> String:
	secs = maxi(0, secs)
	return "%02d:%02d:%02d" % [secs / 3600, (secs / 60) % 60, secs % 60]


func _refresh() -> void:
	var focus_key := _focused_key()
	_fill_deals()
	_fill_packs()
	_fill_agents()
	_flash_id = ""
	if focus_key != "":
		_restore_focus.call_deferred(focus_key)


# ---------------------------------------------------------------- daily deals

func _deals_panel() -> Control:
	var p := UITheme.card_panel(Color(UITheme.GOLD, 0.35), 16)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var sh := UITheme.section_header("TODAY'S DEALS", "gift", UITheme.GOLD, UITheme.FS_H3)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	var pill := PanelContainer.new()
	var ps := UITheme.panel_style(Color(0.03, 0.05, 0.09, 0.9), Color(UITheme.GOLD, 0.45), 1, 18, 0)
	ps.content_margin_left = 14
	ps.content_margin_right = 14
	ps.content_margin_top = 2
	ps.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", ps)
	pill.tooltip_text = "Every deal can be bought once a day. New deals arrive at midnight."
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 8)
	pill.add_child(ph)
	ph.add_child(UITheme.icon_rect("cooldown", 26, UITheme.GOLD))
	_countdown = UITheme.label("NEW DEALS IN  " + format_countdown(Shop.seconds_to_refresh()), UITheme.FS_BODY + 2, UITheme.OFFWHITE, UITheme.font_header())
	_countdown.name = "Countdown"
	ph.add_child(_countdown)
	head.add_child(pill)
	_deals_row = HBoxContainer.new()
	_deals_row.name = "Deals"
	_deals_row.add_theme_constant_override("separation", 12)
	v.add_child(_deals_row)
	return p


func _fill_deals() -> void:
	for c in _deals_row.get_children():
		c.queue_free()
	deal_buttons.clear()
	var offers := Shop.offers()
	if offers.is_empty():
		var t := UITheme.tile_panel(UITheme.BORDER, 18)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		t.add_child(hb)
		hb.add_child(UITheme.icon_rect("gift", 44, UITheme.MUTED))
		var l := UITheme.label("Today's deals are being stocked. Check back soon: the shop refreshes every day at midnight.", UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold())
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		_deals_row.add_child(t)
		return
	for o in offers:
		_deals_row.add_child(_deal_tile(o))


## The colour of an offer: the card's rarity, the pack's accent, green for the gift, blue-white for stars.
static func offer_color(o: Dictionary) -> Color:
	match str(o.get("kind", "")):
		"card":
			return DB.rarity_color(str(DB.card(str(o.get("card", ""))).get("rarity", "common")))
		"pack":
			return Color(str(DB.pack(str(o.get("pack", "rookie"))).get("accent", "#9FD3FF")))
		"gift":
			return UITheme.GREEN
		"stars":
			return UITheme.STAR
	return UITheme.GOLD


static func is_free(o: Dictionary) -> bool:
	var pr: Dictionary = o.get("price", {})
	return int(pr.get("coins", 0)) <= 0 and int(pr.get("stars", 0)) <= 0


func _deal_tile(o: Dictionary) -> Control:
	var id := str(o.get("id", ""))
	var kind := str(o.get("kind", ""))
	var bought := bool(o.get("bought", false))
	var col := offer_color(o)
	var p := UITheme.tile_panel(Color(col, 0.18 if bought else 0.6), 12, not bought and kind == "gift")
	p.name = "Deal_" + id
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.custom_minimum_size = Vector2(250, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	p.add_child(v)
	# Caption row: kind and, for discounted packs, the saving.
	var cap := HBoxContainer.new()
	cap.add_theme_constant_override("separation", 6)
	v.add_child(cap)
	var info: Array = KINDS.get(kind, ["DEAL", "gift"])
	cap.add_child(UITheme.icon_rect(str(info[1]), 20, col))
	var cl := UITheme.label(str(info[0]), UITheme.FS_MIN, col, UITheme.font_body_bold())
	cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.add_child(cl)
	var off := _discount_pct(o)
	if off > 0 and not bought:
		cap.add_child(UITheme.badge("-%d%%" % off, UITheme.SCARLET))
	# Picture.
	var pic := CenterContainer.new()
	pic.custom_minimum_size = Vector2(0, DEAL_CARD.y + 6)
	v.add_child(pic)
	pic.add_child(_deal_picture(o, col))
	if bought:
		pic.modulate = Color(0.55, 0.55, 0.6)
	# Title and text.
	var title := str(o.get("title", ""))
	if title == "":
		title = _default_title(o)
	var tl := UITheme.label(title, UITheme.FS_H3 if title.length() < 16 else UITheme.FS_LEAD, UITheme.OFFWHITE if not bought else UITheme.MUTED, UITheme.font_header())
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(tl)
	var sub := str(o.get("text", ""))
	if kind == "card" and str(o.get("card", "")) != "":
		sub = _copies_text(str(o.card), int(o.get("copies", 1)))
	if sub != "":
		var sl := UITheme.label(sub, UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.max_lines_visible = 2
		v.add_child(sl)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	v.add_child(_deal_button(o, col))
	if _flash_id == id:
		p.modulate = Color(1.8, 1.7, 1.3)
		p.create_tween().tween_property(p, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return p


func _deal_picture(o: Dictionary, col: Color) -> Control:
	var card_id := str(o.get("card", ""))
	var pack_id := str(o.get("pack", ""))
	if card_id != "" and DB.cards.has(card_id):
		var cv := CardView.new(card_id, maxi(1, Profile.card_level(card_id)))
		cv.set_card(card_id, maxi(1, Profile.card_level(card_id)))
		cv.custom_minimum_size = DEAL_CARD
		cv.lift_px = 4.0
		cv.count_badge = "×%d" % int(o.get("copies", 1)) if int(o.get("copies", 1)) > 1 else ""
		cv.tooltip_text = "%s — %s" % [DB.card(card_id).name, DB.card_text(card_id, maxi(1, Profile.card_level(card_id)))]
		return cv
	if pack_id != "" and DB.packs.has(pack_id):
		var pa := PackArt.new(pack_id)
		pa.custom_minimum_size = Vector2(DEAL_CARD.y * 0.65, DEAL_CARD.y)
		return pa
	# Gift / stars: a big glowing icon with the amount.
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	var glow := PanelContainer.new()
	glow.add_theme_stylebox_override("panel", UITheme.panel_style(Color(col, 0.16), Color(col, 0.55), 2, 60, 18))
	glow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glow.add_child(UITheme.icon_rect("star" if str(o.get("kind", "")) == "stars" else "gift", 108, col))
	box.add_child(glow)
	var amt := _amount_text(o)
	if amt != "":
		var al := UITheme.label(amt, UITheme.FS_H2, col.lightened(0.2), UITheme.font_display())
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(al)
	return box


## "+25" for stars or coins inside a gift / star deal (when the offer says how many).
static func _amount_text(o: Dictionary) -> String:
	for k in ["stars", "coins", "amount"]:
		if int(o.get(k, 0)) > 0:
			return "+%s" % UITheme.format_int(int(o[k]))
	return ""


static func _default_title(o: Dictionary) -> String:
	match str(o.get("kind", "")):
		"card":
			return str(DB.card(str(o.get("card", ""))).get("name", "Card copies"))
		"pack":
			return str(DB.pack(str(o.get("pack", ""))).get("name", "Card pack"))
		"gift":
			return "Free gift"
		"stars":
			return "Stars"
	return "Deal"


## Percent off a pack deal against the pack shop price (0 when not a pack or not cheaper).
static func _discount_pct(o: Dictionary) -> int:
	if str(o.get("kind", "")) != "pack" or not DB.packs.has(str(o.get("pack", ""))):
		return 0
	var full := Profile.pack_price(str(o.pack), 1)
	var pr: Dictionary = o.get("price", {})
	var full_v := int(full.coins) if int(pr.get("coins", 0)) > 0 else int(full.stars)
	var now := int(pr.get("coins", 0)) if int(pr.get("coins", 0)) > 0 else int(pr.get("stars", 0))
	if full_v <= 0 or now >= full_v:
		return 0
	return int(round(100.0 * float(full_v - now) / full_v))


## "3 copies  ·  Lv 3 needs 4 (you have 2)": what the deal does for the card.
static func _copies_text(card_id: String, copies: int) -> String:
	var t := "%d cop%s" % [copies, "y" if copies == 1 else "ies"]
	if not Profile.is_card_owned(card_id):
		return t + "  ·  a new card!"
	var cost := Profile.upgrade_cost(card_id)
	if cost.is_empty():
		return t + "  ·  max level"
	return t + "  ·  Lv %d needs %d (you have %d)" % [Profile.card_level(card_id) + 1, int(cost.copies), Profile.card_copies(card_id)]


func _deal_button(o: Dictionary, col: Color) -> Control:
	var id := str(o.get("id", ""))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var b: Button
	if bool(o.get("bought", false)):
		b = UITheme.button("CLAIMED" if is_free(o) else "BOUGHT", "secondary", UITheme.FS_SMALL, "check", UITheme.GREEN)
		b.disabled = true
		b.tooltip_text = "Bought today. New deals arrive at midnight."
	elif is_free(o):
		b = UITheme.button("CLAIM FREE", "primary", UITheme.FS_LEAD, "gift", UITheme.GREEN.darkened(0.2))
		b.tooltip_text = "Free once a day"
	else:
		b = price_button("BUY", o.get("price", {}), Shop.can_buy(id))
	b.custom_minimum_size.y = UITheme.BTN_H_SMALL
	b.pressed.connect(_buy_offer.bind(id))
	box.add_child(b)
	var cap := UITheme.label("", UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(0, 20)
	if not bool(o.get("bought", false)) and not is_free(o):
		var need := shortfall(o.get("price", {}))
		if need != "":
			cap.text = need
			cap.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
		elif _discount_pct(o) > 0:
			var full := Profile.pack_price(str(o.pack), 1)
			cap.text = "Usually %s %s" % [UITheme.format_int(maxi(int(full.coins), int(full.stars))), "coins" if int(full.coins) > 0 else "stars"]
	box.add_child(cap)
	deal_buttons[id] = b
	return box


## "Need 120 more coins" when the wallet is short of `price` ({coins, stars}), else "".
static func shortfall(price: Dictionary) -> String:
	var coins := int(price.get("coins", 0))
	var stars := int(price.get("stars", 0))
	if coins > int(Profile.data.coins):
		return "Need %s more coins" % UITheme.format_int(coins - int(Profile.data.coins))
	if stars > int(Profile.data.stars):
		return "Need %s more stars" % UITheme.format_int(stars - int(Profile.data.stars))
	return ""


## A button that reads "BUY  ⦿ 250": the label, then the price with its currency icon.
static func price_button(text: String, price: Dictionary, can: bool, accent := UITheme.GOLD) -> Button:
	var coins := int(price.get("coins", 0))
	var stars := int(price.get("stars", 0))
	var b := UITheme.button("", "secondary", UITheme.FS_SMALL, "", accent)
	b.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
	b.disabled = not can
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not can:
		row.modulate = Color(1, 1, 1, 0.5)
	b.add_child(row)
	var tl := UITheme.label(text, UITheme.FS_SMALL + 1, UITheme.OFFWHITE, UITheme.font_body_bold())
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tl)
	for cur in [["coin", coins, UITheme.GOLD], ["star", stars, UITheme.STAR]]:
		if int(cur[1]) <= 0:
			continue
		row.add_child(UITheme.icon_rect(str(cur[0]), 20, cur[2]))
		var pl := UITheme.label(UITheme.format_int(int(cur[1])), UITheme.FS_BODY + 2, cur[2], UITheme.font_header())
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(pl)
	b.set_meta("price_text", "%s %s" % [text, UITheme.format_int(coins if coins > 0 else stars)])
	return b


func _buy_offer(id: String) -> void:
	var o := _offer(id)
	if o.is_empty() or bool(o.get("bought", false)):
		return
	if not Shop.can_buy(id):
		Audio.ui("ui_error")
		var need := shortfall(o.get("price", {}))
		Router.toast(need + "." if need != "" else "That deal is not available right now.", "warn")
		return
	var res := Shop.buy(id)
	if res.is_empty() or (res.has("ok") and not bool(res.ok)):
		Audio.ui("ui_error")
		Router.toast("That deal is not available right now.", "warn")
		_refresh()
		return
	Audio.play("purchase")
	var title := str(o.get("title", "")) if str(o.get("title", "")) != "" else _default_title(o)
	match str(o.get("kind", "")):
		"gift":
			Router.toast("Free gift claimed: %s!" % title, "level")
		"card":
			Router.toast("Bought %d %s cop%s." % [int(o.get("copies", 1)), DB.card(str(o.card)).name, "y" if int(o.get("copies", 1)) == 1 else "ies"], "info")
		"pack":
			Router.toast("Bought a %s! Open it in Card Packs." % DB.pack(str(o.pack)).name, "info")
		_:
			Router.toast("Bought: %s." % title, "info")
	_flash_id = id
	_refresh()


func _offer(id: String) -> Dictionary:
	for o in Shop.offers():
		if str(o.get("id", "")) == id:
			return o
	return {}


# ---------------------------------------------------------------- pack shop

func _pack_shop_panel() -> Control:
	var p := UITheme.card_panel(Color(UITheme.BLUE, 0.35), 16)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.size_flags_stretch_ratio = 1.45
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	var sh := UITheme.section_header("PACK SHOP", "deck", UITheme.GOLD, UITheme.FS_H3)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	_packs_owned = UITheme.label("", UITheme.FS_SMALL, UITheme.MUTED, UITheme.font_body_bold())
	head.add_child(_packs_owned)
	var open := UITheme.button("OPEN PACKS  ▶", "ghost", UITheme.FS_SMALL, "", UITheme.GOLD)
	open.custom_minimum_size = Vector2(0, UITheme.BTN_H_SMALL)
	open.tooltip_text = "Open your packs in Card Packs"
	open.pressed.connect(func() -> void: Router.open("packs"))
	head.add_child(open)
	_packs_row = HBoxContainer.new()
	_packs_row.name = "PackShop"
	_packs_row.add_theme_constant_override("separation", 10)
	v.add_child(_packs_row)
	return p


func _fill_packs() -> void:
	for c in _packs_row.get_children():
		c.queue_free()
	pack_buttons.clear()
	var n := Profile.pack_count()
	_packs_owned.text = "You have %d unopened pack%s" % [n, "" if n == 1 else "s"] if n > 0 else ""
	for id in DB.pack_order:
		if bool(DB.pack(id).get("for_sale", false)):
			_packs_row.add_child(_pack_tile(id))


func _pack_tile(id: String) -> Control:
	var pd := DB.pack(id)
	var accent := Color(str(pd.accent))
	var t := UITheme.tile_panel(Color(accent, 0.35), 10)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.tooltip_text = str(pd.get("tagline", ""))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	t.add_child(hb)
	var art := PackArt.new(id)
	art.custom_minimum_size = Vector2(82, 126)
	art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(art)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 4)
	hb.add_child(v)
	v.add_child(UITheme.label(str(pd.name), UITheme.FS_BODY + 2, accent.lightened(0.2), UITheme.font_header()))
	for count in [1, Profile.BUNDLE_SIZE]:
		v.add_child(_pack_buy(id, count))
	return t


func _pack_buy(id: String, count: int) -> Control:
	var price := Profile.pack_price(id, count)
	var can := Profile.can_buy_pack(id, count)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var b := price_button("BUY" if count == 1 else "×%d" % count, price, can)
	b.tooltip_text = "Buy %d %s%s" % [count, DB.pack(id).name, "s" if count > 1 else ""]
	if count > 1 and can:
		var full := Profile.pack_price(id, 1)
		var in_stars := int(price.stars) > 0
		var saved := (int(full.stars) if in_stars else int(full.coins)) * count - (int(price.stars) if in_stars else int(price.coins))
		if saved > 0:
			b.tooltip_text += " (save %s %s)" % [UITheme.format_int(saved), "stars" if in_stars else "coins"]
	b.pressed.connect(func() -> void:
		if not Profile.buy_pack(id, count):
			Audio.ui("ui_error")
			return
		Audio.ui("purchase")
		Router.toast(("Bought a %s! Open it in Card Packs." % DB.pack(id).name) if count == 1 else "Bought %d %ss! Open them in Card Packs." % [count, DB.pack(id).name], "info")
		_refresh())
	box.add_child(b)
	pack_buttons["%s:%d" % [id, count]] = b
	return box


# ---------------------------------------------------------------- free agents

func _agents_panel_build() -> Control:
	var p := UITheme.card_panel(Color(UITheme.SCARLET, 0.4), 16)
	p.name = "FreeAgents"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var sh := UITheme.section_header("FREE AGENTS", "roster", UITheme.GOLD, UITheme.FS_H3)
	sh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sh)
	_agents_row = HBoxContainer.new()
	_agents_row.add_theme_constant_override("separation", 10)
	v.add_child(_agents_row)
	return p


func _fill_agents() -> void:
	for c in _agents_row.get_children():
		c.queue_free()
	agent_buttons.clear()
	var list := Shop.free_agents()
	if list.is_empty():
		_agents_row.add_child(UITheme.label("No free agents right now.", UITheme.FS_BODY, UITheme.MUTED))
		return
	for a in list:
		_agents_row.add_child(_agent_tile(a))


func _agent_tile(a: Dictionary) -> Control:
	var id := str(a.id)
	var d := DB.defender(id)
	var accent := DB.defender_accent(id)
	var signed := bool(a.get("signed", false))
	var t := UITheme.tile_panel(Color(accent, 0.45 if not signed else 0.2), 10)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.tooltip_text = "%s — %s\n%s: %s" % [d.name, d.get("title", ""), d.trait.name, d.trait.text]
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	t.add_child(v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	v.add_child(hb)
	var pr := MenuScreen.portrait_rect(id, 76, accent)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(pr)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.alignment = BoxContainer.ALIGNMENT_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(tv)
	tv.add_child(UITheme.label(str(d.name), UITheme.FS_LEAD, accent.lightened(0.3), UITheme.font_header()))
	tv.add_child(UITheme.label(str(DB.roles[d.role].name), UITheme.FS_MIN, UITheme.OFFWHITE, UITheme.font_body_bold()))
	tv.add_child(UITheme.label(str(d.trait.name), UITheme.FS_MIN, Color(0.75, 0.85, 1.0), UITheme.font_body_bold()))
	var lvl := int(a.get("level", 0))
	tv.add_child(UITheme.label("Joins free at Lv %d" % lvl if not signed and lvl > 0 else ("On your team" if signed else ""), UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
	var b: Button
	if signed:
		b = UITheme.button("SIGNED", "secondary", UITheme.FS_SMALL, "check", UITheme.GREEN)
		b.tooltip_text = "See %s on the Team screen" % d.name
		b.pressed.connect(func() -> void: Router.open("roster", id))
	else:
		b = price_button("SIGN", {"coins": int(a.price)}, true, UITheme.GOLD)
		var short := shortfall({"coins": int(a.price)})
		if short != "":
			b.tooltip_text = short
		b.pressed.connect(func() -> void: confirm_sign(self, id, func(_ok: bool) -> void: _refresh()))
	b.custom_minimum_size.y = UITheme.BTN_H_SMALL
	v.add_child(b)
	agent_buttons[id] = b
	return t


func _scroll_to_agents() -> void:
	await get_tree().process_frame
	if is_instance_valid(_agents_panel):
		_scroll.ensure_control_visible(_agents_panel)
		if agent_buttons.size() > 0:
			(agent_buttons.values()[0] as Control).grab_focus()


## The free agent entry of `id` from Shop.free_agents(), or {}.
static func agent_info(id: String) -> Dictionary:
	for a in Shop.free_agents():
		if str(a.get("id", "")) == id:
			return a
	return {}


## Confirmation popup for signing a free agent: who it is, the price, the wallet and what the
## player gets. SIGN calls Shop.sign_agent; `on_done(ok)` runs afterwards. Returns the popup
## (or null when `id` is not a free agent). Used by the Shop and the Team screen.
static func confirm_sign(host: MenuScreen, id: String, on_done := Callable()) -> Control:
	var a := agent_info(id)
	if a.is_empty() or bool(a.get("signed", false)):
		return null
	var d := DB.defender(id)
	var accent := DB.defender_accent(id)
	var price := int(a.price)
	var have := int(Profile.data.coins)
	var can := have >= price
	var shade := ColorRect.new()
	shade.name = "SignConfirm"
	shade.color = Color(0, 0, 0, 0.62)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	host.add_child(shade)
	host.push_overlay(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var p := UITheme.card_panel(Color(accent, 0.8), 26, Color(0.04, 0.07, 0.12, 0.98), 2)
	p.custom_minimum_size = Vector2(700, 0)
	center.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 20)
	vb.add_child(top)
	top.add_child(MenuScreen.portrait_rect(id, 132, accent))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(UITheme.label("FREE AGENT", UITheme.FS_MIN, UITheme.GOLD, UITheme.font_body_bold()))
	tv.add_child(UITheme.title("SIGN %s?" % str(d.name).to_upper(), 52, accent.lightened(0.25)))
	tv.add_child(UITheme.label("%s — %s" % [d.get("title", ""), DB.roles[d.role].name], UITheme.FS_LEAD, UITheme.OFFWHITE, UITheme.font_header()))
	var tr := UITheme.label("%s: %s" % [d.trait.name, d.trait.text], UITheme.FS_SMALL, Color(0.85, 0.9, 1.0))
	tr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(tr)
	vb.add_child(UITheme.hsep())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	row.add_child(UITheme.label("PRICE", UITheme.FS_BODY, UITheme.MUTED, UITheme.font_body_bold()))
	row.add_child(UITheme.icon_rect("coin", 34, UITheme.GOLD))
	row.add_child(UITheme.label(UITheme.format_int(price), UITheme.FS_H1, UITheme.GOLD, UITheme.font_display()))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var wallet := UITheme.label("You have %s coins" % UITheme.format_int(have), UITheme.FS_BODY, UITheme.OFFWHITE, UITheme.font_body_bold())
	wallet.name = "Wallet"
	row.add_child(wallet)
	var afford := UITheme.label("", UITheme.FS_BODY, UITheme.GREEN, UITheme.font_body_bold())
	afford.name = "Afford"
	afford.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if can:
		afford.text = "After signing: %s coins left." % UITheme.format_int(have - price)
	else:
		afford.text = "You need %s more coins." % UITheme.format_int(price - have)
		afford.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	vb.add_child(afford)
	var sig := str(d.get("signature", ""))
	var gets := "%s joins your roster now" % d.name
	if sig != "" and DB.cards.has(sig) and not Profile.is_card_owned(sig):
		gets += ", with a Signature Pack holding %s" % DB.card(sig).name
	var lvl := int(a.get("level", 0))
	var info := gets + "." + (" Or wait: %s joins for free at account level %d (you are level %d)." % [d.name, lvl, int(Profile.data.level)] if lvl > 0 else "")
	var il := UITheme.label(info, UITheme.FS_SMALL, UITheme.MUTED)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(il)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	btns.add_theme_constant_override("separation", 12)
	vb.add_child(btns)
	var cancel := UITheme.button("CANCEL", "secondary")
	cancel.name = "Cancel"
	cancel.pressed.connect(func() -> void:
		Audio.ui("ui_back")
		shade.queue_free())
	btns.add_child(cancel)
	var go := UITheme.button("SIGN  %s" % UITheme.format_int(price), "primary", UITheme.FS_LEAD, "coin", UITheme.GOLD.darkened(0.25))
	go.name = "Sign"
	go.disabled = not can
	go.tooltip_text = "" if can else "You need %s more coins." % UITheme.format_int(price - have)
	go.pressed.connect(func() -> void:
		shade.queue_free()
		var ok := Shop.sign_agent(id)
		if ok:
			Audio.play("purchase")
			Audio.play("level_up")
			Router.toast("%s signed! Find the Signature Pack in Card Packs." % d.name if sig != "" else "%s signed!" % d.name, "level")
		else:
			Audio.ui("ui_error")
			Router.toast("Could not sign %s right now." % d.name, "warn")
		if on_done.is_valid():
			on_done.call(ok))
	btns.add_child(go)
	(go if can else cancel).grab_focus.call_deferred()
	shade.modulate.a = 0.0
	shade.create_tween().tween_property(shade, "modulate:a", 1.0, 0.15)
	return shade


# ---------------------------------------------------------------- focus

func _focus_first() -> void:
	if Router.open_arg == "agents":
		return
	for id in deal_buttons:
		var b: Button = deal_buttons[id]
		if is_instance_valid(b) and not b.disabled:
			b.grab_focus()
			return
	for k in pack_buttons:
		var b: Button = pack_buttons[k]
		if is_instance_valid(b) and not b.disabled:
			b.grab_focus()
			return


## Which shop button has focus ("deal:<id>", "pack:<type>:<n>", "agent:<id>"), so a refresh can
## put the focus back on the rebuilt button.
func _focused_key() -> String:
	var f := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if f == null:
		return ""
	for pair in [["deal:", deal_buttons], ["pack:", pack_buttons], ["agent:", agent_buttons]]:
		var dict: Dictionary = pair[1]
		for k in dict:
			if dict[k] == f:
				return str(pair[0]) + str(k)
	return ""


func _restore_focus(key: String) -> void:
	var dict: Dictionary = deal_buttons if key.begins_with("deal:") else (pack_buttons if key.begins_with("pack:") else agent_buttons)
	var k := key.substr(key.find(":") + 1)
	var b: Button = dict.get(k)
	if b == null or not is_instance_valid(b):
		return
	if b.disabled:
		_focus_first()
	else:
		b.grab_focus()
