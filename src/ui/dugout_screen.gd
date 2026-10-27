extends Control
## Between-innings dugout: performance summary, next-inning scouting, team stats
## and the upgrade shop (core upgrades + randomised specials). Run-only upgrades.

signal closed

var battle: Battle
var _coins_label: Label
var _shop: GridContainer
var _team_box: VBoxContainer
var _offers: Array = []
var _card_pick_layer: Control
var _just_bought := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg_path := "res://assets/textures/ui/dugout_bg.png"
	if ResourceLoader.exists(bg_path):
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.modulate = Color(0.7, 0.7, 0.75, 0.97)
		add_child(bg)
	else:
		var dim := ColorRect.new()
		dim.color = Color(0.03, 0.04, 0.07, 0.9)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.06, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_roll_offers()
	_build()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.35)
	Audio.ui("ui_slide")


func _roll_offers() -> void:
	var run: RunState = battle.run
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.run_seed, run.inning, "dugout"])
	var core: Array = []
	var specials: Array = []
	for id in DB.upgrade_order:
		var u: Dictionary = DB.upgrades[id]
		if run.upgrade_level(id) >= int(u.max):
			continue
		if u.kind == "core":
			core.append(id)
		else:
			specials.append(id)
	for i in range(specials.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = specials[i]
		specials[i] = specials[j]
		specials[j] = t
	_offers.clear()
	for id in core:
		_offers.append({"id": id, "discount": 1.0})
	for i in mini(2, specials.size()):
		var offer := {"id": specials[i], "discount": 0.8, "special": true}
		if DB.upgrades[specials[i]].kind == "random_defender":
			offer.defender = run.team[rng.randi() % run.team.size()]
		_offers.append(offer)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)

	var run: RunState = battle.run
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 36)
	var title := UITheme.title("THE DUGOUT", 80)
	head.add_child(title)
	var sub := VBoxContainer.new()
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inning_txt := "End of inning %d" % run.inning
	if run.max_innings > 0:
		inning_txt += " of %d" % run.max_innings
	sub.add_child(UITheme.header(inning_txt.to_upper(), 34, UITheme.GOLD))
	sub.add_child(UITheme.label("Spend your run coins on upgrades for the rest of this run.", 20, UITheme.MUTED))
	head.add_child(sub)
	var coin_box := HBoxContainer.new()
	coin_box.add_child(UITheme.icon_rect("coin", 44, UITheme.GOLD))
	_coins_label = UITheme.label(str(run.coins), 56, UITheme.GOLD, UITheme.font_display())
	coin_box.add_child(_coins_label)
	head.add_child(coin_box)
	outer.add_child(head)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	outer.add_child(body)

	# Left column: performance + next inning.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 12)
	body.add_child(left)
	var perf := _card_panel("MATCH PERFORMANCE", "outs")
	left.add_child(perf)
	var pv: VBoxContainer = perf.get_child(0)
	var rows := [
		["Runs allowed", "%d / %d" % [run.runs, run.run_limit]],
		["Runs this inning", str(run.runs_inning)],
		["Outs recorded", str(run.outs_total)],
		["Double / triple plays", "%d / %d" % [int(run.stats.get("double_plays", 0)), int(run.stats.get("triple_plays", 0))]],
		["Best combo", str(int(run.stats.get("max_combo", 0)))],
		["Cards played", str(int(run.stats.get("cards_played", 0)))],
		["Shields", str(run.shields)],
		["Score", UITheme.format_int(run.score)],
	]
	for r in rows:
		pv.add_child(_kv(r[0], r[1]))
	var mvp := run.mvp()
	if mvp != "":
		pv.add_child(_kv("Inning MVP", DB.defender(mvp).name, Color(DB.defender(mvp).accent).lightened(0.3)))

	var nxt := _card_panel("NEXT INNING SCOUTING", "enemy")
	left.add_child(nxt)
	var nv: VBoxContainer = nxt.get_child(0)
	var saved_inning := run.inning
	var saved_wave := run.wave
	run.inning += 1
	var total := {}
	for w in run.waves_per_inning:
		var info := WaveGenerator.generate(run, w, battle.routes.size())
		for k in info.preview.keys():
			total[k] = int(total.get(k, 0)) + int(info.preview[k])
		if info.boss != "":
			nv.add_child(UITheme.label("BOSS: " + DB.enemy(info.boss).name, 26, Color(1.0, 0.4, 0.3), UITheme.font_display()))
	var boss_next := run.boss_for_inning(run.inning)
	run.inning = saved_inning
	run.wave = saved_wave
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	for k in total.keys():
		var hb := HBoxContainer.new()
		var tex := DB.portrait(k)
		if tex:
			var r := TextureRect.new()
			r.texture = tex
			r.custom_minimum_size = Vector2(40, 40)
			r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hb.add_child(r)
		hb.add_child(UITheme.label("%s x%d" % [DB.enemy(k).name, int(total[k])], 18, Color(1.0, 0.65, 0.55), UITheme.font_body_bold()))
		hb.tooltip_text = DB.enemy(k).text
		flow.add_child(hb)
	nv.add_child(flow)
	if boss_next == "" and run.max_innings > 0 and run.inning + 1 >= run.max_innings:
		nv.add_child(UITheme.label("Final inning ahead!", 20, UITheme.GOLD))

	# Centre: upgrade shop.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 10)
	body.add_child(mid)
	mid.add_child(UITheme.label("Upgrades last for the rest of this game. Hover one for details.", UITheme.FS_SMALL, UITheme.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(scroll)
	_shop = GridContainer.new()
	_shop.columns = 2
	_shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop.add_theme_constant_override("h_separation", 12)
	_shop.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_shop)
	_fill_shop()

	# Right: team stats.
	var right := _card_panel("TEAM", "roster")
	right.custom_minimum_size = Vector2(380, 0)
	body.add_child(right)
	_team_box = right.get_child(0)
	_fill_team()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 14)
	outer.add_child(bottom)
	var hint := UITheme.label("Temporary upgrades last for this run only. Permanent progress is earned at the end of the run.", UITheme.FS_SMALL, UITheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)
	var go := UITheme.button("NEXT INNING  ▶", "primary", 40)
	go.custom_minimum_size = Vector2(380, 74)
	go.pressed.connect(_finish)
	bottom.add_child(go)


func _card_panel(title: String, icon := "") -> PanelContainer:
	var p := UITheme.card_panel(UITheme.BORDER, 16)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	vb.add_child(UITheme.section_header(title, icon, UITheme.GOLD, UITheme.FS_H3))
	return p


## A small caption tag ("NOW", "NEXT") in a fixed width so the values line up.
func _tag(text: String, col: Color) -> Control:
	var l := UITheme.label(text, UITheme.FS_MIN, col, UITheme.font_body_bold())
	l.custom_minimum_size = Vector2(46, 0)
	return l


func _kv(k: String, v: String, vc := UITheme.OFFWHITE) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var kl := UITheme.label(k, 20, UITheme.MUTED)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(kl)
	hb.add_child(UITheme.label(v, 20, vc, UITheme.font_body_bold()))
	return hb


func _price(offer: Dictionary) -> int:
	var base := battle.run.upgrade_price(offer.id)
	if float(offer.get("discount", 1.0)) >= 1.0:
		return base
	return RunState.round_price(base * float(offer.discount))


## "Team damage +20%" for an upgrade at `level` (uses the upgrade's fx description).
func _fx_text(u: Dictionary, level: int, offer: Dictionary) -> String:
	var fx: Dictionary = u.get("fx", {})
	var t := str(fx.get("text", u.text))
	if fx.has("key"):
		var v := int(round(float(u.effect.get(fx.key, 0.0)) * float(fx.get("mult", 100)) * level))
		t = t % absi(v)
	if offer.has("defender"):
		t = "%s %s" % [DB.defender(offer.defender).name, t]
	return t


func _fill_shop() -> void:
	for c in _shop.get_children():
		c.queue_free()
	var run: RunState = battle.run
	var sections := [["TEAM UPGRADES", false], ["TODAY'S SPECIALS  ·  20% OFF", true]]
	for sec in sections:
		var header := UITheme.section_header(sec[0], "special" if sec[1] else "upgrade", UITheme.GOLD if sec[1] else UITheme.OFFWHITE, 24)
		_shop.add_child(header)
		_shop.add_child(Control.new())
		for offer in _offers:
			if bool(offer.get("special", false)) == sec[1]:
				_shop.add_child(_offer_card(offer, run))
	_just_bought = ""


func _offer_card(offer: Dictionary, run: RunState) -> Control:
	var u: Dictionary = DB.upgrades[offer.id]
	var lvl := run.upgrade_level(offer.id)
	var maxed := lvl >= int(u.max)
	if offer.id == "base_shield" and run.shields >= 3:
		maxed = true
	var price := _price(offer)
	var can_buy := not maxed and run.coins >= price
	var accent: Color = UITheme.GOLD if offer.get("special", false) else UITheme.BLUE
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.08, 0.14, 0.95), Color(accent, 0.75 if can_buy else 0.3), 2, 12, 14))
	p.custom_minimum_size = Vector2(440, 0)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	p.add_child(hb)
	var icon_panel := PanelContainer.new()
	icon_panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(accent, 0.18), Color(accent, 0.6), 1, 10, 10))
	icon_panel.add_child(UITheme.icon_rect(u.get("icon", "upgrade"), 54, accent))
	icon_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(icon_panel)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 4)
	hb.add_child(vb)
	var title_row := HBoxContainer.new()
	var nl := UITheme.label(u.name, 26, UITheme.OFFWHITE, UITheme.font_header())
	nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(nl)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	for i in int(u.max):
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.add_theme_stylebox_override("panel", UITheme.panel_style(accent if i < lvl else Color(1, 1, 1, 0.1), Color(accent, 0.5), 1, 7, 0))
		pips.add_child(dot)
	title_row.add_child(pips)
	vb.add_child(title_row)
	# What you have now and what the next level gives.
	var fx: Dictionary = u.get("fx", {})
	if fx.has("key"):
		var now_row := HBoxContainer.new()
		now_row.add_theme_constant_override("separation", 10)
		now_row.add_child(_tag("NOW", UITheme.MUTED))
		now_row.add_child(UITheme.label(_fx_text(u, lvl, offer) if lvl > 0 else "Not bought yet", UITheme.FS_SMALL, Color(0.82, 0.86, 0.94) if lvl > 0 else UITheme.MUTED, UITheme.font_body_bold()))
		vb.add_child(now_row)
		if not maxed:
			var next_row := HBoxContainer.new()
			next_row.add_theme_constant_override("separation", 10)
			next_row.add_child(_tag("NEXT", UITheme.GREEN))
			next_row.add_child(UITheme.label(_fx_text(u, lvl + 1, offer), UITheme.FS_BODY + 1, UITheme.GREEN, UITheme.font_body_bold()))
			vb.add_child(next_row)
	else:
		var d := UITheme.label(_fx_text(u, 1, offer), 19, Color(0.86, 0.9, 0.97), UITheme.font_body_bold())
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(d)
	# The price is the button: coin icon + amount (gold when affordable).
	var buy := UITheme.button("MAXED" if maxed else str(price), "primary" if can_buy else "secondary", 26, "" if maxed else "coin", UITheme.GOLD.darkened(0.3))
	if not maxed and not can_buy:
		buy.tooltip_text = "Need %d more coins" % (price - run.coins)
	buy.custom_minimum_size = Vector2(130, 56)
	buy.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy.disabled = not can_buy
	if buy.tooltip_text == "":
		buy.tooltip_text = str(u.text)
	buy.pressed.connect(func() -> void: _buy(offer))
	hb.add_child(buy)
	p.tooltip_text = str(u.text)
	if _just_bought == str(offer.id) + str(offer.get("defender", "")):
		_celebrate.call_deferred(p, accent, _fx_text(u, 1, offer) if not fx.has("key") else "LEVEL %d" % lvl)
	return p


## Purchase feedback: the upgrade pops and flashes, and a label floats up from it.
func _celebrate(p: Control, col: Color, text: String) -> void:
	if not is_instance_valid(p):
		return
	p.pivot_offset = p.size * 0.5
	p.scale = Vector2(1.06, 1.06)
	p.modulate = Color(1.6, 1.5, 1.2)
	var tw := p.create_tween().set_parallel(true)
	tw.tween_property(p, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(p, "modulate", Color.WHITE, 0.45)
	var l := UITheme.label(text, 28, col.lightened(0.3), UITheme.font_display())
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.global_position = p.get_global_rect().get_center() - Vector2(60, 20)
	var lt := l.create_tween()
	lt.tween_property(l, "global_position:y", l.global_position.y - 70, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	lt.parallel().tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.5)
	lt.tween_callback(l.queue_free)


func _buy(offer: Dictionary) -> void:
	var run: RunState = battle.run
	var price := _price(offer)
	if run.coins < price:
		Audio.ui("ui_error")
		return
	var u: Dictionary = DB.upgrades[offer.id]
	if offer.id == "new_pitch_card":
		_show_card_pick(offer, price)
		return
	run.coins -= price
	run.upgrades[offer.id] = run.upgrade_level(offer.id) + 1
	match offer.id:
		"base_shield":
			battle.add_shield(1)
		"card_mastery":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash([run.run_seed, run.inning, "mastery", run.upgrade_level(offer.id)])
			var cid: String = run.deck[rng.randi() % run.deck.size()]
			run.card_level_bonus[cid] = int(run.card_level_bonus.get(cid, 0)) + 1
			Router.toast("%s is now level %d for this run!" % [DB.card(cid).name, run.card_level(cid)], "level")
		"hot_streak":
			var did: String = offer.get("defender", run.team[0])
			run.defender_bonus[did] = float(run.defender_bonus.get(did, 0.0)) + float(u.effect.defender_damage)
	Audio.play("purchase")
	_coins_label.text = str(run.coins)
	battle._refresh_team_stats()
	_just_bought = str(offer.id) + str(offer.get("defender", ""))
	_fill_shop()
	_fill_team()


func _show_card_pick(offer: Dictionary, price: int) -> void:
	var run: RunState = battle.run
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run.run_seed, run.inning, "pick", run.upgrade_level("new_pitch_card")])
	var pool: Array = []
	for cid in DB.card_order:
		if not cid in run.deck:
			pool.append(cid)
	if pool.is_empty():
		Router.toast("Your deck already holds every card!", "warn")
		return
	var choices: Array = []
	for i in mini(3, pool.size()):
		var k := rng.randi() % pool.size()
		choices.append(pool[k])
		pool.remove_at(k)
	_card_pick_layer = Control.new()
	_card_pick_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_pick_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_card_pick_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_pick_layer.add_child(dim)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.position = Vector2(-420, -260)
	vb.custom_minimum_size = Vector2(840, 0)
	vb.add_theme_constant_override("separation", 20)
	_card_pick_layer.add_child(vb)
	var t := UITheme.title("CHOOSE A NEW PITCH", 60)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 30)
	vb.add_child(hb)
	for cid in choices:
		var cv := CardView.new(cid, run.card_level(cid))
		cv.set_card(cid, run.card_level(cid))
		cv.custom_minimum_size = Vector2(220, 308)
		cv.clicked.connect(func(_c: CardView) -> void:
			run.coins -= price
			run.upgrades[offer.id] = run.upgrade_level(offer.id) + 1
			run.deck.append(cid)
			run.temp_cards.append(cid)
			battle.cards.add_card(cid)
			Audio.play("card_draw")
			Router.toast("%s added to your deck for this run." % DB.card(cid).name, "info")
			_coins_label.text = str(run.coins)
			_card_pick_layer.queue_free()
			_fill_shop())
		hb.add_child(cv)
	var cancel := UITheme.small_button("Cancel", UITheme.BLUE, 22)
	cancel.pressed.connect(func() -> void: _card_pick_layer.queue_free())
	var cc := CenterContainer.new()
	cc.add_child(cancel)
	vb.add_child(cc)


func _fill_team() -> void:
	while _team_box.get_child_count() > 1:
		var c := _team_box.get_child(1)
		_team_box.remove_child(c)
		c.queue_free()
	for df: Defender in battle.defenders:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		var pt := TextureRect.new()
		pt.texture = DB.portrait(df.id)
		pt.custom_minimum_size = Vector2(48, 48)
		pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hb.add_child(pt)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", -2)
		vb.add_child(UITheme.label(df.data.name + (" (C)" if df.is_captain else ""), 22, Color(df.data.accent).lightened(0.3), UITheme.font_header()))
		vb.add_child(UITheme.label("DMG %d · %.2fs · %.0fm · %d outs" % [int(df.s_damage), df.s_interval, df.s_range, df.outs], UITheme.FS_MIN, UITheme.MUTED, UITheme.font_body_bold()))
		hb.add_child(vb)
		_team_box.add_child(hb)


func _finish() -> void:
	Audio.ui("ui_confirm")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())
