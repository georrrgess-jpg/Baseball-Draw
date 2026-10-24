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
	var perf := _card_panel("MATCH PERFORMANCE")
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

	var nxt := _card_panel("NEXT INNING SCOUTING")
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
	mid.add_child(UITheme.header("UPGRADES", 38, UITheme.OFFWHITE))
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
	var right := _card_panel("TEAM")
	right.custom_minimum_size = Vector2(380, 0)
	body.add_child(right)
	_team_box = right.get_child(0)
	_fill_team()

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 14)
	outer.add_child(bottom)
	var hint := UITheme.label("Temporary upgrades last for this run only. Permanent progress is earned at the end of the run.", 18, UITheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(hint)
	var go := UITheme.menu_button("NEXT INNING  ▶", UITheme.SCARLET, 40)
	go.custom_minimum_size = Vector2(380, 74)
	go.pressed.connect(_finish)
	bottom.add_child(go)


func _card_panel(title: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.04, 0.07, 0.12, 0.9), Color(1, 1, 1, 0.1), 1, 10, 16))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	vb.add_child(UITheme.header(title, 28, UITheme.GOLD))
	return p


func _kv(k: String, v: String, vc := UITheme.OFFWHITE) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var kl := UITheme.label(k, 20, UITheme.MUTED)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(kl)
	hb.add_child(UITheme.label(v, 20, vc, UITheme.font_body_bold()))
	return hb


func _price(offer: Dictionary) -> int:
	return int(round(battle.run.upgrade_price(offer.id) * float(offer.get("discount", 1.0))))


func _fill_shop() -> void:
	for c in _shop.get_children():
		c.queue_free()
	var run: RunState = battle.run
	for offer in _offers:
		var u: Dictionary = DB.upgrades[offer.id]
		var lvl := run.upgrade_level(offer.id)
		var maxed := lvl >= int(u.max)
		if offer.id == "base_shield" and run.shields >= 3:
			maxed = true
		var price := _price(offer)
		var p := PanelContainer.new()
		var accent: Color = UITheme.GOLD if offer.get("special", false) else UITheme.BLUE
		p.add_theme_stylebox_override("panel", UITheme.panel_style(Color(0.05, 0.08, 0.14, 0.95), Color(accent, 0.5), 2, 10, 14))
		p.custom_minimum_size = Vector2(440, 150)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		p.add_child(hb)
		var icon_panel := PanelContainer.new()
		icon_panel.add_theme_stylebox_override("panel", UITheme.panel_style(Color(accent, 0.18), Color(accent, 0.6), 1, 10, 10))
		icon_panel.add_child(UITheme.icon_rect(u.get("icon", "upgrade"), 54, accent))
		hb.add_child(icon_panel)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 2)
		var name: String = u.name
		if offer.has("defender"):
			name += ": " + DB.defender(offer.defender).name
		var title_row := HBoxContainer.new()
		var nl := UITheme.label(name, 26, UITheme.OFFWHITE, UITheme.font_header())
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_row.add_child(nl)
		if offer.get("special", false):
			title_row.add_child(UITheme.label("SPECIAL -20%", 16, UITheme.GOLD, UITheme.font_body_bold()))
		vb.add_child(title_row)
		var desc := UITheme.label(u.text, 18, Color(0.82, 0.86, 0.94))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(desc)
		var pips := HBoxContainer.new()
		for i in int(u.max):
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(16, 8)
			dot.add_theme_stylebox_override("panel", UITheme.panel_style(accent if i < lvl else Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 0, 3, 0))
			pips.add_child(dot)
		vb.add_child(pips)
		hb.add_child(vb)
		var buy := UITheme.small_button("MAX" if maxed else "%d" % price, UITheme.GOLD, 24)
		buy.icon = null if maxed else DB.icon("coin")
		buy.add_theme_color_override("icon_normal_color", UITheme.GOLD)
		buy.expand_icon = false
		buy.custom_minimum_size = Vector2(110, 54)
		buy.disabled = maxed or run.coins < price
		buy.pressed.connect(func() -> void: _buy(offer))
		hb.add_child(buy)
		_shop.add_child(p)


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
		vb.add_child(UITheme.label("DMG %d · %.2fs · %.0fm · %d outs" % [int(df.s_damage), df.s_interval, df.s_range, df.outs], 16, UITheme.MUTED))
		hb.add_child(vb)
		_team_box.add_child(hb)


func _finish() -> void:
	Audio.ui("ui_confirm")
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(func() -> void:
		closed.emit()
		queue_free())
