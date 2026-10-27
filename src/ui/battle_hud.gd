extends CanvasLayer
## In-battle HUD: scoreboard, threat tracker, card hand & energy, minimap,
## selected-unit panel, setup/practice tools, banners, boss bar and overlays
## (pause, dugout, results).

var battle: Battle

var root: Control
var _top_inning: Label
var _top_runs: HBoxContainer
var _top_outs: Label
var _top_wave: Label
var _top_coins: Label
var _top_score: Label
var _shield_label: Label
var _threat_count: Label
var _threat_bar: ProgressBar
var _threat_icons: HBoxContainer
var _threat_title: Label
var _mods_label: Label
const HAND_CARD := Vector2(146, 204)
const HAND_GAP := 12.0

var _hand_box: HandTray
var _card_views: Array = []        # one per hand slot: CardView, or null for an empty slot
var _energy_bar: Control
var _energy_label: Label
var _deck_label: Label
var _draw_bar: ProgressBar
var _unit_panel: PanelContainer
var _unit_box: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _flash: ColorRect
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_enemy: Enemy
var _start_btn: Button
var _speed_btn: Button
var _setup_panel: PanelContainer
var _practice_panel: PanelContainer
var _card_tip: PanelContainer
var _card_tip_label: RichTextLabel
var _drag_tip: PanelContainer
var _drag_tip_label: Label
var _enemy_tip: PanelContainer
var _enemy_tip_label: Label
var _pause: Control
var _dugout: Control
var _results: Control
var _synergy_box: VBoxContainer
var _preview_box: HFlowContainer
var _preview_cache_key := ""
var _preview_cache: Dictionary = {}
var _hint: Label
var _banner_tween: Tween
var _hand_snapshot := []
var _selected_card_rect := Rect2()


func _ready() -> void:
	layer = 10
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_flash()
	_build_top()
	_build_threats()
	_build_bottom()
	_build_minimap()
	_build_unit_panel()
	_build_banner()
	_build_boss_bar()
	_build_controls()
	_build_setup_panel()
	_build_practice_panel()
	_build_tooltips()
	battle.state_changed.connect(_on_state)
	battle.banner_requested.connect(banner)
	battle.selection_changed.connect(_on_selection)
	battle.targeting_changed.connect(func(_i: int) -> void: _update_cards())
	battle.card_denied.connect(_on_card_denied)
	battle.cards.hand_changed.connect(_rebuild_hand)
	battle.wave_started.connect(func(_w: Dictionary) -> void: refresh())
	_rebuild_hand()
	_on_state(battle.state)
	Router.set_toast_top(380.0)
	tree_exiting.connect(func() -> void: Router.set_toast_top(90.0))
	if not battle.practice and not battle.auto_test and not bool(Profile.data.flags.get("battle_tutorial_done", false)) \
			and not "--no-help" in OS.get_cmdline_user_args():
		start_tutorial()


# ---------------------------------------------------------------- builders

func _panel(bg := Color(0.04, 0.07, 0.12, 0.86), border := Color(1, 1, 1, 0.1), pad := 10) -> PanelContainer:
	var p := PanelContainer.new()
	if bool(Settings.get_value("accessibility", "high_contrast", false)):
		bg = Color(0.0, 0.0, 0.0, 0.97)
		border = Color(1, 1, 1, 0.6)
	p.add_theme_stylebox_override("panel", UITheme.panel_style(bg, border, 1, 10, pad))
	return p


func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_flash)
	var vig_path := "res://assets/textures/ui/vignette.png"
	if ResourceLoader.exists(vig_path):
		var v := TextureRect.new()
		v.texture = load(vig_path)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		v.stretch_mode = TextureRect.STRETCH_SCALE
		v.modulate = Color(1, 1, 1, 0.45)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(v)


## Scoreboard in the top-right corner (the top centre stays clear so the far gates are visible).
func _build_top() -> void:
	var p := _panel(Color(0.03, 0.05, 0.1, 0.9), Color(UITheme.SCARLET, 0.6), 10)
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	p.offset_right = -14
	p.offset_left = -330
	p.offset_top = 10
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	p.add_child(vb)
	var row1 := HBoxContainer.new()
	vb.add_child(row1)
	_top_inning = UITheme.label("INNING 1", 30, UITheme.GOLD, UITheme.font_display())
	_top_inning.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_top_inning)
	row1.add_child(UITheme.label("WAVE ", 15, UITheme.MUTED, UITheme.font_body_bold()))
	_top_wave = UITheme.label("1/3", 24, UITheme.OFFWHITE, UITheme.font_header())
	row1.add_child(_top_wave)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 14)
	vb.add_child(row2)
	var runs_box := VBoxContainer.new()
	runs_box.add_theme_constant_override("separation", 0)
	runs_box.add_child(UITheme.label("RUNS ALLOWED", 13, UITheme.MUTED, UITheme.font_body_bold()))
	runs_box.tooltip_text = "Runners who reach home plate score runs. Fill every circle and the game is over."
	runs_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_top_runs = HBoxContainer.new()
	_top_runs.add_theme_constant_override("separation", 5)
	runs_box.add_child(_top_runs)
	row2.add_child(runs_box)
	var sbox := VBoxContainer.new()
	sbox.add_theme_constant_override("separation", 0)
	sbox.add_child(UITheme.label("SHIELDS", 13, UITheme.MUTED, UITheme.font_body_bold()))
	_shield_label = UITheme.label("0", 22, Color(0.5, 0.9, 1.0), UITheme.font_header())
	sbox.add_child(_shield_label)
	row2.add_child(sbox)
	var obox := VBoxContainer.new()
	obox.add_theme_constant_override("separation", 0)
	obox.add_child(UITheme.label("OUTS", 13, UITheme.MUTED, UITheme.font_body_bold()))
	_top_outs = UITheme.label("0", 22, UITheme.GREEN, UITheme.font_header())
	obox.add_child(_top_outs)
	row2.add_child(obox)
	var cbox := HBoxContainer.new()
	cbox.size_flags_vertical = Control.SIZE_SHRINK_END
	cbox.add_child(UITheme.icon_rect("coin", 22, UITheme.GOLD))
	_top_coins = UITheme.label("0", 22, UITheme.GOLD, UITheme.font_header())
	cbox.add_child(_top_coins)
	row2.add_child(cbox)
	_top_score = UITheme.label("0", 18, UITheme.MUTED, UITheme.font_body_bold())
	# Not shown in the compact scoreboard (kept for the score text); freed with the HUD, see _exit_tree.


func _vsep() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.15)
	c.custom_minimum_size = Vector2(2, 40)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _build_threats() -> void:
	var p := _panel()
	p.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	p.position = Vector2(-330, 128)
	p.custom_minimum_size = Vector2(316, 0)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	p.add_child(vb)
	var hb := HBoxContainer.new()
	_threat_title = UITheme.label("RUNNERS LEFT", 18, UITheme.MUTED, UITheme.font_body_bold())
	_threat_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(_threat_title)
	_threat_count = UITheme.label("0", 28, Color(1.0, 0.45, 0.35), UITheme.font_header())
	hb.add_child(_threat_count)
	vb.add_child(hb)
	_threat_bar = ProgressBar.new()
	_threat_bar.custom_minimum_size = Vector2(0, 10)
	_threat_bar.show_percentage = false
	_threat_bar.add_theme_stylebox_override("fill", UITheme.panel_style(Color(1.0, 0.4, 0.3), Color(0, 0, 0, 0), 0, 4, 0))
	vb.add_child(_threat_bar)
	vb.add_child(UITheme.label("UPCOMING THREATS", 15, UITheme.MUTED, UITheme.font_body_bold()))
	_threat_icons = HBoxContainer.new()
	_threat_icons.add_theme_constant_override("separation", 6)
	vb.add_child(_threat_icons)
	_mods_label = UITheme.label("", 15, Color(1.0, 0.7, 0.45), UITheme.font_body_bold())
	_mods_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mods_label.custom_minimum_size = Vector2(290, 0)
	vb.add_child(_mods_label)


func _build_bottom() -> void:
	# Card hand: five fixed slots, so cards never slide under the cursor.
	_hand_box = HandTray.new()
	_hand_box.hud = self
	var tray_w := HAND_CARD.x * CardSystem.MAX_HAND + HAND_GAP * (CardSystem.MAX_HAND - 1)
	_hand_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hand_box.offset_left = -tray_w * 0.5
	_hand_box.offset_right = tray_w * 0.5
	_hand_box.offset_top = -236.0
	_hand_box.offset_bottom = -236.0 + HAND_CARD.y
	_hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hand_box)
	# Energy bar
	var eb := HBoxContainer.new()
	eb.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	eb.position = Vector2(-410, -36)
	eb.custom_minimum_size = Vector2(820, 28)
	eb.add_theme_constant_override("separation", 10)
	eb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(eb)
	eb.add_child(UITheme.icon_rect("energy", 28, UITheme.ENERGY))
	_energy_label = UITheme.label("5", 28, UITheme.ENERGY, UITheme.font_display())
	_energy_label.custom_minimum_size = Vector2(42, 0)
	eb.add_child(_energy_label)
	_energy_bar = EnergyBar.new()
	_energy_bar.custom_minimum_size = Vector2(560, 22)
	_energy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eb.add_child(_energy_bar)
	var deck_box := VBoxContainer.new()
	deck_box.add_theme_constant_override("separation", 0)
	_deck_label = UITheme.label("Deck 4 · Discard 0", 15, UITheme.MUTED, UITheme.font_body_bold())
	deck_box.add_child(_deck_label)
	_draw_bar = ProgressBar.new()
	_draw_bar.custom_minimum_size = Vector2(140, 6)
	_draw_bar.show_percentage = false
	_draw_bar.max_value = 1.0
	_draw_bar.add_theme_stylebox_override("fill", UITheme.panel_style(UITheme.GOLD, Color(0, 0, 0, 0), 0, 3, 0))
	deck_box.add_child(_draw_bar)
	eb.add_child(deck_box)
	# The energy row sits just under the cards: it must never take clicks meant for them.
	_ignore_mouse(eb)


func _build_minimap() -> void:
	var p := _panel(Color(0.03, 0.05, 0.1, 0.85), Color(1, 1, 1, 0.1), 6)
	p.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	p.offset_left = 14.0
	p.offset_top = -190.0
	p.offset_bottom = -12.0
	root.add_child(p)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var mm := Minimap.new()
	mm.battle = battle
	mm.custom_minimum_size = Vector2(250, 154)
	vb.add_child(mm)
	_hint = UITheme.label("", 15, UITheme.MUTED, UITheme.font_body_bold())
	_hint.custom_minimum_size = Vector2(250, 0)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_hint)


func _build_unit_panel() -> void:
	_unit_panel = _panel(Color(0.04, 0.07, 0.12, 0.92), Color(1, 1, 1, 0.12), 12)
	_unit_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_unit_panel.position = Vector2(-372, -470)
	_unit_panel.custom_minimum_size = Vector2(356, 0)
	_unit_panel.visible = false
	root.add_child(_unit_panel)
	_unit_box = VBoxContainer.new()
	_unit_box.add_theme_constant_override("separation", 6)
	_unit_panel.add_child(_unit_box)


func _build_banner() -> void:
	_banner = UITheme.title("", 60, Color.WHITE)
	_banner.add_theme_constant_override("outline_size", 12)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-700, 175)
	_banner.custom_minimum_size = Vector2(1400, 0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.pivot_offset = Vector2(700, 40)
	root.add_child(_banner)


func _build_boss_bar() -> void:
	_boss_panel = _panel(Color(0.08, 0.02, 0.03, 0.9), Color(1.0, 0.3, 0.2, 0.7), 8)
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-360, 96)
	_boss_panel.custom_minimum_size = Vector2(720, 0)
	_boss_panel.visible = false
	_boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_boss_panel)
	var vb := VBoxContainer.new()
	_boss_panel.add_child(vb)
	_boss_name = UITheme.label("BOSS", 26, Color(1.0, 0.6, 0.4), UITheme.font_display())
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.custom_minimum_size = Vector2(0, 16)
	_boss_bar.show_percentage = false
	_boss_bar.add_theme_stylebox_override("fill", UITheme.panel_style(Color(1.0, 0.3, 0.15), Color(0, 0, 0, 0), 0, 4, 0))
	vb.add_child(_boss_bar)


func _build_controls() -> void:
	var tl := HBoxContainer.new()
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(14, 14)
	tl.add_theme_constant_override("separation", 8)
	root.add_child(tl)
	var pause := UITheme.small_button("II", UITheme.BLUE, 18)
	pause.custom_minimum_size = Vector2(46, 0)
	pause.tooltip_text = "Pause (Esc)"
	pause.pressed.connect(toggle_pause)
	tl.add_child(pause)
	_speed_btn = UITheme.small_button("1x", UITheme.GOLD, 18)
	_speed_btn.tooltip_text = "Fast-forward (Shift)"
	_speed_btn.custom_minimum_size = Vector2(64, 0)
	_speed_btn.pressed.connect(func() -> void:
		battle.cycle_speed()
		refresh())
	tl.add_child(_speed_btn)
	var map_btn := UITheme.small_button("MAP", UITheme.BLUE, 18)
	map_btn.tooltip_text = "Top-down tactical view (M)"
	map_btn.pressed.connect(func() -> void: battle.cam.toggle_tactical())
	tl.add_child(map_btn)
	var range_btn := UITheme.small_button("RANGES", UITheme.BLUE, 18)
	range_btn.tooltip_text = "Show every defender's throwing range (F)"
	range_btn.pressed.connect(func() -> void:
		var show: bool = not battle.defenders[0].show_range
		for df in battle.defenders:
			df.set_show_range(show))
	tl.add_child(range_btn)

	_start_btn = UITheme.menu_button("PLAY BALL!", UITheme.SCARLET, 40)
	_start_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_start_btn.position = Vector2(-370, -104)
	_start_btn.custom_minimum_size = Vector2(350, 76)
	_start_btn.tooltip_text = "Begin the next wave (Space)"
	_start_btn.pressed.connect(func() -> void: battle.begin_wave())
	root.add_child(_start_btn)


func _build_setup_panel() -> void:
	_setup_panel = _panel(Color(0.04, 0.07, 0.12, 0.92), Color(1, 1, 1, 0.12), 12)
	_setup_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_setup_panel.position = Vector2(14, 64)
	_setup_panel.custom_minimum_size = Vector2(300, 0)
	root.add_child(_setup_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_setup_panel.add_child(vb)
	vb.add_child(UITheme.header("FORMATION", 26, UITheme.GOLD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for fid in DB.formation_order:
		var f: Dictionary = DB.formations[fid]
		var b := UITheme.small_button(f.name, UITheme.SCARLET, 19)
		b.custom_minimum_size = Vector2(138, 34)
		b.tooltip_text = f.text
		b.pressed.connect(func() -> void: battle.apply_formation(fid))
		grid.add_child(b)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var mirror := UITheme.small_button("Mirror", UITheme.BLUE, 19)
	mirror.tooltip_text = "Flip the formation left/right"
	mirror.pressed.connect(func() -> void: battle.mirror_formation())
	row.add_child(mirror)
	var save := UITheme.small_button("Save", UITheme.GREEN, 19)
	save.tooltip_text = "Save these positions as your custom formation"
	save.pressed.connect(_save_custom_formation)
	row.add_child(save)
	var load_b := UITheme.small_button("Load", UITheme.GREEN, 19)
	load_b.tooltip_text = "Load your saved custom formation"
	load_b.pressed.connect(func() -> void:
		if Profile.data.custom_formations.has("custom"):
			battle.apply_formation("custom")
		else:
			Router.toast("No custom formation saved yet.", "warn"))
	row.add_child(load_b)
	vb.add_child(row)
	vb.add_child(UITheme.hsep())
	vb.add_child(UITheme.header("TEAM SYNERGIES", 22, UITheme.GOLD))
	_synergy_box = VBoxContainer.new()
	_synergy_box.add_theme_constant_override("separation", 2)
	vb.add_child(_synergy_box)

func _save_custom_formation() -> void:
	var by_id := {}
	for df: Defender in battle.defenders:
		by_id[df.id] = [snappedf(df.post.x, 0.01), snappedf(df.post.z, 0.01)]
	Profile.data.custom_formations["custom"] = {"name": "Custom", "by_id": by_id}
	Profile.data.formation = "custom"
	Profile.save_soon()
	Router.toast("Custom formation saved.", "info")
	Audio.ui("ui_confirm")


func _build_practice_panel() -> void:
	_practice_panel = _panel(Color(0.04, 0.07, 0.12, 0.92), Color(0.3, 0.8, 1.0, 0.4), 12)
	_practice_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_practice_panel.position = Vector2(14, 64)
	_practice_panel.custom_minimum_size = Vector2(350, 0)
	_practice_panel.visible = false
	root.add_child(_practice_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_practice_panel.add_child(vb)
	vb.add_child(UITheme.header("PRACTICE FIELD", 30, Color(0.5, 0.9, 1.0)))
	vb.add_child(UITheme.label("Spawn runners on a route:", 17, UITheme.MUTED))
	var route_opt := OptionButton.new()
	for r: Route in battle.routes:
		route_opt.add_item(r.id.capitalize())
	route_opt.add_item("Random")
	route_opt.select(route_opt.item_count - 1)
	vb.add_child(route_opt)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	for id in ["runner", "sprinter", "armored", "swarmer", "jumper", "trickster", "captain", "slugger", "iron_slugger", "phantom_captain", "grand_slammer"]:
		var b := UITheme.small_button(DB.enemy(id).name, Color(1.0, 0.4, 0.3), 18)
		b.custom_minimum_size = Vector2(162, 34)
		b.pressed.connect(func() -> void:
			var ri := route_opt.selected
			if ri >= battle.routes.size():
				ri = randi() % battle.routes.size()
			var n: int = 6 if id == "swarmer" else 1
			for i in n:
				battle.spawn_enemy(id, battle.routes[ri], 0.0, {"lateral": randf_range(-1.0, 1.0)}))
		grid.add_child(b)
	var inf := CheckBox.new()
	inf.text = "Infinite energy"
	inf.button_pressed = true
	inf.toggled.connect(func(v: bool) -> void: battle.cards.infinite_energy = v)
	vb.add_child(inf)
	var nocd := CheckBox.new()
	nocd.text = "No card cooldowns"
	nocd.toggled.connect(func(v: bool) -> void:
		battle.cards.cooldown_mult = 0.0 if v else 1.0
		battle.cards.cooldowns.clear())
	vb.add_child(nocd)
	vb.add_child(UITheme.label("Test any card (even uncollected):", 17, UITheme.MUTED))
	var card_row := HBoxContainer.new()
	var card_opt := OptionButton.new()
	card_opt.custom_minimum_size = Vector2(230, 0)
	for cid in DB.card_order:
		card_opt.add_item(DB.card(cid).name)
	card_row.add_child(card_opt)
	var give := UITheme.small_button("To hand", UITheme.GOLD, 18)
	give.pressed.connect(func() -> void:
		var cid: String = DB.card_order[card_opt.selected]
		var slot := battle.cards.hand.find("")
		if slot >= 0:
			battle.cards.hand[slot] = cid
		elif battle.cards.hand.size() < CardSystem.MAX_HAND:
			battle.cards.hand.append(cid)
		else:
			battle.cards.hand[0] = cid
		battle.cards.hand_changed.emit())
	card_row.add_child(give)
	vb.add_child(card_row)
	vb.add_child(UITheme.label("Swap the selected defender for:", 17, UITheme.MUTED))
	var def_row := HBoxContainer.new()
	var def_opt := OptionButton.new()
	def_opt.custom_minimum_size = Vector2(230, 0)
	for did in DB.defender_order:
		def_opt.add_item(DB.defender(did).name + ("" if Profile.is_defender_unlocked(did) else " (locked)"))
	def_row.add_child(def_opt)
	var swap := UITheme.small_button("Swap", UITheme.BLUE, 18)
	swap.pressed.connect(func() -> void:
		if battle.selected == null:
			Router.toast("Select a defender on the field first (click or Tab).", "warn")
			return
		battle.swap_defender(battle.selected, DB.defender_order[def_opt.selected]))
	def_row.add_child(swap)
	vb.add_child(def_row)
	var clear := UITheme.small_button("Clear field", UITheme.BLUE, 19)
	clear.pressed.connect(func() -> void:
		for e: Enemy in battle.enemies.duplicate():
			e.die({}))
	vb.add_child(clear)
	vb.add_child(UITheme.label("Practice never costs or earns permanent resources.", 15, UITheme.MUTED))


func _build_tooltips() -> void:
	_card_tip = _panel(Color(0.03, 0.05, 0.09, 0.97), Color(UITheme.GOLD, 0.5), 12)
	_card_tip.custom_minimum_size = Vector2(380, 0)
	_card_tip.visible = false
	_card_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_card_tip)
	_card_tip_label = RichTextLabel.new()
	_card_tip_label.bbcode_enabled = true
	_card_tip_label.fit_content = true
	_card_tip_label.custom_minimum_size = Vector2(356, 0)
	_card_tip_label.add_theme_font_size_override("normal_font_size", 19)
	_card_tip_label.add_theme_font_override("bold_font", UITheme.font_body_bold())
	_card_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_tip.add_child(_card_tip_label)
	_drag_tip = _panel(Color(0.03, 0.05, 0.09, 0.95), Color(1, 1, 1, 0.2), 8)
	_drag_tip.visible = false
	_drag_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_drag_tip)
	_drag_tip_label = UITheme.label("", 19)
	_drag_tip.add_child(_drag_tip_label)
	_enemy_tip = _panel(Color(0.08, 0.03, 0.03, 0.92), Color(1.0, 0.35, 0.3, 0.6), 8)
	_enemy_tip.visible = false
	_enemy_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_enemy_tip)
	_enemy_tip_label = UITheme.label("", 18)
	_enemy_tip.add_child(_enemy_tip_label)


# ---------------------------------------------------------------- hand

func _rebuild_hand() -> void:
	# Update slot by slot: cards that stay keep their node (and hover/selection state);
	# only a played or replaced card is removed and only a new card is dealt in.
	var cs: CardSystem = battle.cards
	_card_views.resize(CardSystem.MAX_HAND)
	for i in CardSystem.MAX_HAND:
		var id: String = cs.hand[i] if i < cs.hand.size() else ""
		var cv: CardView = _card_views[i] if is_instance_valid(_card_views[i]) else null
		if cv and cv.card_id == id:
			continue
		if cv:
			cv.visible = false
			cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cv.queue_free()
		_card_views[i] = _deal_card(i, id) if id != "" else null
	_update_cards()


func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


func _slot_pos(i: int) -> Vector2:
	return Vector2(i * (HAND_CARD.x + HAND_GAP), 0.0)


func _deal_card(i: int, id: String) -> CardView:
	var cv := CardView.new(id, battle.run.card_level(id))
	cv.set_card(id, battle.run.card_level(id))
	cv.custom_minimum_size = HAND_CARD
	cv.size = HAND_CARD
	cv.position = _slot_pos(i)
	cv.lift_px = 14.0
	cv.hotkey = str(i + 1)
	cv.clicked.connect(func(_c: CardView) -> void: battle.select_card(i))
	cv.hovered.connect(_on_card_hover)
	_hand_box.add_child(cv)
	# Deal-in: a quick pop from the bottom of the slot (the click area stays in place).
	cv.pivot_offset = Vector2(HAND_CARD.x * 0.5, HAND_CARD.y)
	cv.scale = Vector2(0.85, 0.85)
	cv.modulate.a = 0.0
	var tw := cv.create_tween()
	tw.tween_property(cv, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "modulate:a", 1.0, 0.1)
	# A card dealt under a resting mouse gets no mouse_entered until the mouse moves.
	if cv.get_global_rect().has_point(cv.get_global_mouse_position()):
		cv._hover = true
	return cv


## A card was clicked but can't be played: shake it and say why, right above it.
func _on_card_denied(index: int, reason: String) -> void:
	if index < 0 or index >= _card_views.size() or not is_instance_valid(_card_views[index]):
		banner(reason.to_upper(), Color(1.0, 0.55, 0.45))
		return
	var cv: CardView = _card_views[index]
	cv.deny()
	var l := UITheme.label(reason, 22, Color(1.0, 0.82, 0.75), UITheme.font_body_bold())
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.15, 0.02, 0.02, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	l.reset_size()
	var r := cv.get_global_rect()
	l.global_position = Vector2(r.get_center().x - l.size.x * 0.5, r.position.y - 64)
	var tw := l.create_tween()
	tw.tween_property(l, "global_position:y", l.global_position.y - 26, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.6)
	tw.tween_callback(l.queue_free)


func _on_card_hover(cv: CardView, on: bool) -> void:
	if not on:
		_card_tip.visible = false
		return
	var c := DB.card(cv.card_id)
	var lvl: int = battle.run.card_level(cv.card_id)
	var t := "[b][font_size=26]%s[/font_size][/b]  [color=#%s]%s · %s[/color]\n" % [c.name, DB.rarity_color(c.rarity).to_html(false), c.rarity.capitalize(), c.category.capitalize()]
	t += "Cost [color=#3FD0FF]%d energy[/color]" % int(c.cost)
	if float(c.cooldown) > 0:
		t += " · Cooldown %ds" % int(c.cooldown)
	t += " · Level %d\n" % lvl
	t += DB.card_text(cv.card_id, lvl)
	var linked: String = c.get("linked", "")
	if linked != "":
		var on_field := false
		for df: Defender in battle.defenders:
			if df.id == linked:
				on_field = true
		t += "\n[color=#%s]Signature of %s%s[/color]" % [DB.defender_accent(linked).to_html(false), DB.defender(linked).name,
			" — on the field: cast by them with their power." if on_field else " — not on the field: 75% power."]
	t += "\n[color=#8D9AB0]Target: %s[/color]" % {"none": "instant (click to confirm)", "enemy": "a runner", "area": "an area", "path": "a point on a route", "defender": "a defender"}.get(c.target, c.target)
	_card_tip_label.text = t
	_card_tip.visible = true
	_card_tip.reset_size()
	var gp := cv.global_position
	_card_tip.global_position = Vector2(clampf(gp.x - 115, 10, root.size.x - 400), gp.y - _card_tip.size.y - 24)


func _update_cards() -> void:
	var cs: CardSystem = battle.cards
	for i in _card_views.size():
		var cv: CardView = _card_views[i] if is_instance_valid(_card_views[i]) else null
		if cv == null or i >= cs.hand.size() or cs.hand[i] == "":
			continue
		var id: String = cs.hand[i]
		var cd := cs.cooldown_left(id)
		var total := float(DB.card(id).cooldown) * cs.cooldown_mult
		cv.cooldown_left = cd
		cv.cooldown_frac = clampf(cd / maxf(total, 0.01), 0.0, 1.0) if cd > 0 else 0.0
		cv.playable = cs.check(i) == "" and (battle.state == "wave" or battle.practice)
		cv.selected = i == battle.targeting_index
		if cv.selected:
			_selected_card_rect = cv.get_global_rect()
		cv.queue_redraw()


# ---------------------------------------------------------------- refresh

func refresh() -> void:
	var run: RunState = battle.run
	if run.max_innings > 0:
		_top_inning.text = "INNING %d/%d" % [run.inning, run.max_innings]
	else:
		_top_inning.text = "INNING %d" % run.inning if not battle.practice else "PRACTICE"
	for c in _top_runs.get_children():
		c.queue_free()
	if battle.practice:
		_top_runs.add_child(UITheme.label("%d" % run.runs, 26, UITheme.OFFWHITE, UITheme.font_header()))
	else:
		for i in run.run_limit:
			var dot := Panel.new()
			dot.custom_minimum_size = Vector2(22, 22)
			var filled := i < run.runs
			dot.add_theme_stylebox_override("panel", UITheme.panel_style(Color(1.0, 0.25, 0.2) if filled else Color(0, 0, 0, 0.4), Color(1, 1, 1, 0.4), 2, 11, 0))
			_top_runs.add_child(dot)
	_shield_label.text = str(run.shields)
	_top_outs.text = str(run.outs_inning)
	var wave_n := mini(run.wave + (1 if battle.state == "wave" else 0), maxi(run.waves_per_inning, 1))
	_top_wave.text = "%d/%d" % [maxi(wave_n, 1), run.waves_per_inning] if not battle.practice else "-"
	_top_coins.text = UITheme.format_int(run.coins)
	_top_score.text = "SCORE " + UITheme.format_int(run.score)
	_speed_btn.text = "%dx" % int(Battle.SPEEDS[battle.speed_index])

	# Threats
	var alive := 0
	var by_type := {}
	for e: Enemy in battle.enemies:
		if e.alive and e.id != "decoy":
			alive += 1
			by_type[e.id] = int(by_type.get(e.id, 0)) + 1
	var pending := battle.spawn_queue.size()
	for s in battle.spawn_queue:
		by_type[s.enemy] = int(by_type.get(s.enemy, 0)) + 1
	if battle.state == "wave":
		_threat_title.text = "RUNNERS LEFT"
		_threat_count.text = str(alive + pending)
		_threat_bar.max_value = maxi(battle.wave_total, 1)
		_threat_bar.value = battle.wave_total - (alive + pending)
		_fill_threat_icons(by_type)
	elif battle.state in ["setup", "break"]:
		var ck := "%d:%d" % [run.inning, run.wave]
		if ck != _preview_cache_key:
			_preview_cache_key = ck
			_preview_cache = WaveGenerator.generate(run, run.wave, battle.routes.size())
		var info := _preview_cache
		_threat_title.text = "NEXT WAVE"
		_threat_count.text = str(int(info.total))
		_threat_bar.value = 0
		_fill_threat_icons(info.preview)
		_fill_preview(info.preview)

	var mods: Array[String] = []
	var am: Dictionary = battle.arena.get("modifier", {})
	if am.size() > 2:
		mods.append("%s: %s" % [am.name, am.text])
	for mid in run.modifiers:
		var md: Dictionary = DB.endless_modifiers.get(mid, {})
		if not md.is_empty():
			mods.append("%s: %s" % [md.name, md.text])
	var dname: String = DB.difficulty(run.difficulty_id).name
	_mods_label.text = "\n".join(mods)
	_mods_label.visible = mods.size() > 0
	_threat_title.tooltip_text = "Difficulty: %s" % dname
	# Energy & deck
	var cs: CardSystem = battle.cards
	_energy_label.text = str(int(cs.energy))
	_energy_bar.value = cs.energy
	_energy_bar.queue_redraw()
	_deck_label.text = "Deck %d · Discard %d" % [cs.draw_pile.size(), cs.discard.size()]
	_draw_bar.value = cs.next_draw_progress()
	_update_cards()

	# Start button
	var show_start: bool = battle.state in ["setup", "break"] and not battle.practice
	_start_btn.visible = show_start
	if battle.state == "break":
		var auto := bool(Settings.get_value("gameplay", "auto_start_waves", true))
		_start_btn.text = "NEXT WAVE  %ds" % int(ceil(battle.break_timer)) if auto else "NEXT WAVE"
	elif battle.state == "setup":
		_start_btn.text = "PLAY BALL!"
	# Boss
	if _boss_enemy and is_instance_valid(_boss_enemy) and _boss_enemy.alive:
		_boss_bar.max_value = _boss_enemy.max_hp
		_boss_bar.value = _boss_enemy.hp
		var tag := ""
		if _boss_enemy.vulnerable_t > 0.0:
			tag = "  — VULNERABLE!"
		elif _boss_enemy.untargetable_t > 0.0:
			tag = "  — PHASED"
		_boss_name.text = _boss_enemy.data.name.to_upper() + tag
	# Hints
	_hint.text = _context_hint()
	_hint.visible = _hint.text != ""
	if battle.selected and _unit_panel.visible:
		_fill_unit_panel(battle.selected)
	_fill_synergies()


func _context_hint() -> String:
	if battle.targeting_index >= 0:
		var c := DB.card(battle.targeting_card())
		match c.get("target", ""):
			"area": return "Click the field to cast %s. Right-click to cancel." % c.name
			"enemy": return "Click a runner to cast %s. Right-click to cancel." % c.name
			"path": return "Click a basepath to place %s." % c.name
			"defender": return "Click a defender to empower them."
			_: return "Click anywhere (or press the key again) to cast %s." % c.name
	match battle.state:
		"setup":
			return "Drag defenders into position, pick a formation, then press PLAY BALL (Space)."
		"break":
			return "Wave cleared! Reposition now, or call the next wave early for bonus coins (Space)."
		"wave":
			return ""
	return ""


func _fill_threat_icons(by_type: Dictionary) -> void:
	var key := str(by_type)
	if _threat_icons.get_meta("key", "") == key:
		return
	_threat_icons.set_meta("key", key)
	for c in _threat_icons.get_children():
		c.queue_free()
	var keys := by_type.keys()
	keys.sort_custom(func(a, b) -> bool: return float(DB.enemy(a).hp) > float(DB.enemy(b).hp))
	for id in keys.slice(0, 6):
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", -4)
		var tex := DB.portrait(id if id != "decoy" else "trickster")
		var r := TextureRect.new()
		r.custom_minimum_size = Vector2(42, 42)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.texture = tex if tex else DB.icon("boss" if DB.enemy(id).get("boss", false) else "enemy")
		if tex == null:
			r.modulate = Color(1.0, 0.45, 0.35)
		r.tooltip_text = "%s — %s" % [DB.enemy(id).name, DB.enemy(id).text]
		r.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(r)
		var l := UITheme.label("x%d" % int(by_type[id]), 15, UITheme.OFFWHITE, UITheme.font_body_bold())
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(l)
		_threat_icons.add_child(box)


func _fill_preview(preview: Dictionary) -> void:
	if _preview_box == null:
		return
	var key := str(preview)
	if _preview_box.get_meta("key", "") == key:
		return
	_preview_box.set_meta("key", key)
	for c in _preview_box.get_children():
		c.queue_free()
	for id in preview.keys():
		var e := DB.enemy(id)
		var l := UITheme.label("%s x%d" % [e.name, int(preview[id])], 17, Color(1.0, 0.6, 0.5), UITheme.font_body_bold())
		l.tooltip_text = e.text
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_preview_box.add_child(l)


func _fill_synergies() -> void:
	if not _setup_panel.visible:
		return
	var key := ""
	for s in battle.active_synergies:
		key += s.data.id
	if _synergy_box.get_meta("key", "-") == key:
		return
	_synergy_box.set_meta("key", key)
	for c in _synergy_box.get_children():
		c.queue_free()
	var any := false
	for syn in DB.synergies:
		var active := false
		for sy in battle.active_synergies:
			if sy.data.id == syn.id:
				active = true
		if not active:
			continue
		any = true
		var l := UITheme.label("● " + syn.name, 17, UITheme.GREEN, UITheme.font_body_bold())
		l.tooltip_text = syn.text
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		_synergy_box.add_child(l)
	if not any:
		_synergy_box.add_child(UITheme.label("None yet — pair defenders to unlock bonuses.", 15, UITheme.MUTED))


# ---------------------------------------------------------------- unit panel

func _on_selection(df: Defender) -> void:
	_unit_panel.visible = df != null
	if df:
		_fill_unit_panel(df, true)


func _fill_unit_panel(df: Defender, rebuild := false) -> void:
	if not rebuild and _unit_box.get_meta("id", "") == df.id and _unit_box.get_meta("state", "") == battle.state:
		var stats: Label = _unit_box.get_meta("stats_label")
		if is_instance_valid(stats):
			stats.text = _unit_stats_text(df)
		return
	_unit_box.set_meta("id", df.id)
	_unit_box.set_meta("state", battle.state)
	for c in _unit_box.get_children():
		c.queue_free()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	var pt := TextureRect.new()
	pt.texture = DB.portrait(df.id)
	pt.custom_minimum_size = Vector2(84, 84)
	pt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UITheme.panel_style(Color(df.data.accent).darkened(0.6), Color(df.data.accent), 2, 8, 2))
	frame.add_child(pt)
	hb.add_child(frame)
	var nb := VBoxContainer.new()
	nb.add_theme_constant_override("separation", 0)
	nb.add_child(UITheme.label(df.data.name.to_upper() + ("  (C)" if df.is_captain else ""), 34, Color(df.data.accent).lightened(0.3), UITheme.font_display()))
	nb.add_child(UITheme.label("%s · Lv %d · #%d" % [DB.roles[df.role].name, Profile.defender_level(df.id), int(df.data.number)], 18, UITheme.MUTED, UITheme.font_body_bold()))
	var zone_l := UITheme.label(("IN POSITION: " + Field.ZONE_NAMES.get(df.zone, df.zone)) if df.in_position else ("Zone: " + Field.ZONE_NAMES.get(df.zone, df.zone)), 16,
		UITheme.GREEN if df.in_position else UITheme.MUTED, UITheme.font_body_bold())
	zone_l.tooltip_text = DB.roles[df.role].bonus_text
	zone_l.mouse_filter = Control.MOUSE_FILTER_PASS
	nb.add_child(zone_l)
	hb.add_child(nb)
	_unit_box.add_child(hb)
	var stats := UITheme.label(_unit_stats_text(df), 18, UITheme.OFFWHITE, UITheme.font_body())
	_unit_box.set_meta("stats_label", stats)
	_unit_box.add_child(stats)
	var trait_l := UITheme.label("%s: %s" % [df.data.trait.name, df.data.trait.text], 16, Color(0.85, 0.9, 1.0))
	trait_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	trait_l.custom_minimum_size = Vector2(330, 0)
	_unit_box.add_child(trait_l)
	var sig := DB.card(df.data.signature)
	var sig_l := UITheme.label("Signature card: " + sig.get("name", "-"), 16, UITheme.GOLD, UITheme.font_body_bold())
	_unit_box.add_child(sig_l)
	# Targeting priority
	var row := HBoxContainer.new()
	row.add_child(UITheme.label("Target:", 18, UITheme.MUTED))
	var opt := OptionButton.new()
	var modes := ["first", "last", "strongest", "weakest", "fastest", "closest"]
	for m in modes:
		opt.add_item(m.capitalize())
	opt.select(modes.find(df.targeting))
	opt.item_selected.connect(func(i: int) -> void:
		df.targeting = modes[i]
		battle.run.targeting[df.id] = modes[i])
	row.add_child(opt)
	_unit_box.add_child(row)
	if battle.state == "setup" and not df.is_captain:
		var cap := UITheme.small_button("Make Captain", UITheme.GOLD, 19)
		cap.pressed.connect(func() -> void:
			battle.set_captain(df)
			_fill_unit_panel(df, true))
		_unit_box.add_child(cap)


func _unit_stats_text(df: Defender) -> String:
	var t := "DMG %d   SPD %.2fs   RNG %.1fm\n" % [int(df.effective_damage()), df.effective_interval(), df.effective_range()]
	t += "Throw %d m/s   ACC %d   Crit %d%%\n" % [int(df.s_throw_speed), int(df.s_accuracy), int((df.s_crit + df.dyn_crit) * 100)]
	var tgt := "—"
	if df.target and is_instance_valid(df.target) and df.target.alive:
		tgt = df.target.data.name
	if df.is_stunned():
		tgt = "STUNNED"
	t += "Outs %d   Damage %s   Target: %s" % [df.outs, UITheme.format_int(int(df.damage_dealt)), tgt]
	return t


func _process(_delta: float) -> void:
	var e: Enemy = battle.hover_enemy
	if e == null or not is_instance_valid(e) or not e.alive or battle.targeting_index >= 0 or battle.dragging != null:
		_enemy_tip.visible = false
		return
	var parts: Array[String] = ["%s  %d / %d HP" % [e.data.name, int(ceil(e.hp)), int(e.max_hp)]]
	var traits: Array[String] = []
	if e.armor > 0.0:
		traits.append("armor %d%%" % int(e.armor * 100))
	if e.runs > 1:
		traits.append("scores %d runs" % e.runs)
	if e.affix != "":
		traits.append("ELITE: " + e.affix.capitalize())
	var st: Array[String] = []
	if e.mark_t > 0.0: st.append("curved")
	if e.burn_t > 0.0: st.append("burning")
	if e.chill_t > 0.0: st.append("chilled")
	if e.stun_t > 0.0: st.append("stunned")
	if e.root_t > 0.0: st.append("rooted")
	if e.freeze_t > 0.0: st.append("frozen")
	if e.confuse_t > 0.0: st.append("confused")
	if e.vulnerable_t > 0.0: st.append("VULNERABLE")
	if not traits.is_empty():
		parts.append(" · ".join(traits))
	if not st.is_empty():
		parts.append("Status: " + ", ".join(st))
	_enemy_tip_label.text = "\n".join(parts)
	_enemy_tip.visible = true
	_enemy_tip.reset_size()
	_enemy_tip.global_position = get_viewport().get_mouse_position() + Vector2(22, 14)


# ---------------------------------------------------------------- notifications

func banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.scale = Vector2(0.6, 0.6)
	_banner.modulate.a = 0.0
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.12)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(0.9)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.3)


func flash(c: Color) -> void:
	if bool(Settings.get_value("accessibility", "reduce_flashes", false)):
		c.a *= 0.35
	_flash.color = c
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.6)


func show_boss(e: Enemy) -> void:
	_boss_enemy = e
	_boss_panel.visible = true
	_boss_bar.max_value = e.max_hp
	_boss_bar.value = e.hp


func hide_boss() -> void:
	_boss_enemy = null
	_boss_panel.visible = false


func drag_info(df: Defender, p: Vector3, err: String) -> void:
	if df == null:
		_drag_tip.visible = false
		return
	var zone := Field.zone_at(p)
	var role_zone: String = DB.roles[df.role].zone
	var txt := ""
	if err != "":
		txt = "✗ " + err
		_drag_tip_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4))
	elif zone == role_zone:
		txt = "✓ " + DB.roles[df.role].bonus_text
		_drag_tip_label.add_theme_color_override("font_color", UITheme.GREEN)
	else:
		txt = "%s — best in the %s" % [Field.ZONE_NAMES.get(zone, zone), Field.ZONE_NAMES.get(role_zone, role_zone)]
		_drag_tip_label.add_theme_color_override("font_color", UITheme.OFFWHITE)
	_drag_tip_label.text = txt
	_drag_tip.visible = true
	_drag_tip.reset_size()
	_drag_tip.global_position = get_viewport().get_mouse_position() + Vector2(24, 18)


func on_card_played(id: String) -> void:
	_card_tip.visible = false
	# Flourish: the played card rises from its slot in the hand, then swoops to its target
	# and bursts into a ring there.
	var cv := CardView.new(id, battle.run.card_level(id))
	cv.set_card(id, battle.run.card_level(id))
	var sz := Vector2(146, 204)
	cv.custom_minimum_size = sz
	cv.size = sz
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.selected = true
	var from := _selected_card_rect.position if _selected_card_rect.size.x > 0.0 else Vector2(root.size.x * 0.5 - sz.x * 0.5, root.size.y - 250)
	cv.position = from
	cv.pivot_offset = sz * 0.5
	root.add_child(cv)
	_selected_card_rect = Rect2()
	var to := from + Vector2(0, -260)
	var cam := battle.get_viewport().get_camera_3d()
	if battle.last_cast_point is Vector3 and cam and not cam.is_position_behind(battle.last_cast_point):
		to = cam.unproject_position(battle.last_cast_point) - sz * 0.5
	var col := DB.category_color(DB.card(id).category)
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", from + Vector2(0, -70), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "position", to, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "scale", Vector2(0.22, 0.22), 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(cv, "rotation", deg_to_rad(8.0), 0.3)
	tw.tween_callback(func() -> void:
		_ring_burst(cv.position + sz * 0.5, col)
		cv.queue_free())


func _ring_burst(at: Vector2, col: Color) -> void:
	var fx := RingBurst.new()
	fx.color = col
	fx.position = at
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fx)
	var tw := fx.create_tween()
	tw.tween_property(fx, "t", 1.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fx.queue_free)


class RingBurst:
	extends Control
	var color := Color.WHITE
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _draw() -> void:
		var r := 20.0 + 70.0 * t
		draw_arc(Vector2.ZERO, r, 0, TAU, 40, Color(color.lightened(0.4), 1.0 - t), 6.0 * (1.0 - t) + 1.0, true)
		draw_circle(Vector2.ZERO, 26.0 * (1.0 - t), Color(1, 1, 1, 0.8 * (1.0 - t)))


# ---------------------------------------------------------------- state & overlays

func _on_state(s: String) -> void:
	_setup_panel.visible = s in ["setup"] and not battle.practice
	_practice_panel.visible = battle.practice
	_hand_box.visible = s != "results"
	if s == "setup":
		_synergy_box.set_meta("key", "-")
	refresh()


func start_tutorial() -> void:
	var tut: CanvasLayer = load("res://src/ui/battle_tutorial.gd").new()
	tut.set("hud", self)
	tut.set("battle", battle)
	tut.name = "Tutorial"
	add_child(tut)


## Rules reference (pause menu → HOW TO PLAY). Pauses the game while open.
func show_help() -> void:
	_show_help()


func _show_help() -> void:
	var p := _panel(Color(0.04, 0.07, 0.12, 0.97), Color(UITheme.GOLD, 0.7), 20)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.position = Vector2(-380, -250)
	p.custom_minimum_size = Vector2(760, 0)
	root.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	p.add_child(vb)
	vb.add_child(UITheme.title("HOW TO PLAY", 56, UITheme.GOLD))
	var lines := [
		"[b]Defend home plate.[/b] Rival runners pour out of the outfield gates and race along the glowing routes. Every runner your defenders put out is an [color=#3DDC84]OUT[/color]; every runner that reaches home scores a [color=#ff5a50]RUN[/color]. Allow too many runs and the game is over.",
		"[b]Position your team.[/b] Drag defenders before the first pitch or between waves. A green ring means they're in their best zone (pitcher on the mound, catcher behind the plate, infielders in the dirt, outfielders on the grass). Try the formation buttons.",
		"[b]Play cards.[/b] Press [color=#F5B82E]1-5[/color] or click a card, then click a target. Cards cost energy, which refills over time. Signature cards are cast by their defender.",
		"[b]Keys:[/b] Space next wave · Shift fast-forward · WASD/wheel camera · R rotate · M map · Tab cycle defenders · F show ranges · Esc pause.",
	]
	for l in lines:
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.text = l
		r.custom_minimum_size = Vector2(720, 0)
		r.add_theme_font_size_override("normal_font_size", 20)
		r.add_theme_font_override("bold_font", UITheme.font_body_bold())
		r.add_theme_font_size_override("bold_font_size", 21)
		vb.add_child(r)
	var b := UITheme.menu_button("GOT IT — PLAY BALL!", UITheme.SCARLET, 32)
	b.text = "GOT IT"
	b.pressed.connect(func() -> void:
		Profile.data.flags["battle_help"] = true
		Profile.save_soon()
		get_tree().paused = false
		p.queue_free())
	vb.add_child(b)


func toggle_pause() -> void:
	if battle.state == "results":
		return
	if _pause and is_instance_valid(_pause):
		_pause.queue_free()
		_pause = null
		get_tree().paused = false
		return
	var script: Script = load("res://src/ui/pause_menu.gd")
	_pause = script.new()
	_pause.battle = battle
	_pause.closed.connect(func() -> void:
		_pause = null
		get_tree().paused = false)
	root.add_child(_pause)
	get_tree().paused = true


func open_dugout() -> void:
	var script: Script = load("res://src/ui/dugout_screen.gd")
	_dugout = script.new()
	_dugout.battle = battle
	_dugout.closed.connect(func() -> void:
		_dugout = null
		battle.next_inning())
	root.add_child(_dugout)


func show_results(result: Dictionary) -> void:
	_setup_panel.visible = false
	_practice_panel.visible = false
	_unit_panel.visible = false
	_start_btn.visible = false
	_hand_box.visible = false
	hide_boss()
	# Clear the battle HUD so the results own the screen.
	for c in root.get_children():
		if c != _flash:
			(c as CanvasItem).visible = false
	var script: Script = load("res://src/ui/results_screen.gd")
	_results = script.new()
	_results.battle = battle
	_results.result = result
	root.add_child(_results)


class EnergyBar extends Control:
	var value := 5.0

	func _draw() -> void:
		var n := 10
		var gap := 4.0
		var w := (size.x - gap * (n - 1)) / n
		for i in n:
			var r := Rect2(i * (w + gap), 0, w, size.y)
			draw_rect(r, Color(0.02, 0.05, 0.1, 0.9))
			var fill := clampf(value - i, 0.0, 1.0)
			if fill > 0.0:
				var c := UITheme.ENERGY if fill >= 1.0 else UITheme.ENERGY.darkened(0.45)
				draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), c)
				if fill >= 1.0:
					draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.25))
			draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)


## The hand area: draws empty slots (with the next-card timer in the first one) behind the cards.
class HandTray:
	extends Control
	var hud: Node

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if hud == null:
			return
		var cs: CardSystem = hud.battle.cards
		var first_empty := true
		for i in CardSystem.MAX_HAND:
			var empty: bool = i >= cs.hand.size() or cs.hand[i] == ""
			if not empty:
				continue
			var r := Rect2(hud._slot_pos(i), hud.HAND_CARD)
			draw_rect(r, Color(0.02, 0.04, 0.08, 0.35))
			draw_rect(r, Color(1, 1, 1, 0.16), false, 2.0)
			if first_empty:
				first_empty = false
				var p := cs.next_draw_progress()
				var fh := r.size.y * p
				draw_rect(Rect2(r.position.x, r.end.y - fh, r.size.x, fh), Color(UITheme.GOLD, 0.16))
				var f := UITheme.font_body_bold()
				var t := "NEXT CARD"
				var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				draw_string(f, r.get_center() + Vector2(-tw * 0.5, 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.45))


func _exit_tree() -> void:
	# _top_score is never added to the tree, so it would outlive the HUD (an orphan Label that kept a
	# font and its glyph textures alive: the "ObjectDB instances leaked at exit" warning).
	if is_instance_valid(_top_score) and not _top_score.is_inside_tree():
		_top_score.free()
