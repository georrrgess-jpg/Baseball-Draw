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
var _energy_bar: EnergyBar
var _energy_label: Label
var _deck_label: Label
var _draw_bar: ProgressBar
var _unit_panel: PanelContainer
var _unit_box: VBoxContainer
var _banner: Label
var _banner_sub: Label
var _banner_busy := false
var _banner_queue: Array = []
var _flash: ColorRect
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_enemy: Enemy
var _boss_fill: StyleBoxFlat
var _boss_state: Label            # Update 11: PHASED / REVEALED / VULNERABLE line under the bar
var _boss_window: ProgressBar     # time left in that state
var boss_state := ""              # "", "phased", "revealed", "vulnerable" (read by tests)
var _start_btn: Button
var _speed_btn: Button
var _setup_panel: PanelContainer
var _formation_cards: Array[Button] = []
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
## Combo hints (Update 8): pairs of hand slots whose cards combo, [[i, j, text]], and the layer
## that draws the links between them (drawing only: it never takes mouse input).
var _combo_pairs: Array = []
var _combo_links: ComboLinks
const COMBO_COLOR := Color("#4DF2A0")
var _scout_popup: Control
## Update 9: Dugout Draft overlay, active boon chips, Endless milestone line, early-call caption.
var _draft: Control
var _boon_box: HFlowContainer
var _boon_row: VBoxContainer
var _milestone_label: Label
var _start_sub: Label
var _start_pulse: Tween
var _double_badge: PanelContainer   # Ground Rule Double: "x2" over the hand while cards are cast twice


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
	# Scouting Book: record the runner types, bosses and elites met in this game.
	var tracker := Scouting.attach(battle)
	tracker.scouted.connect(_on_scouted)
	for a in OS.get_cmdline_user_args():   # screenshot helpers
		if a.begins_with("--hand="):   # e.g. --hand=curveball,heat_wave,power_throw
			var ids := Array(a.split("=")[1].split(",")).filter(func(id: String) -> bool: return DB.cards.has(id))
			get_tree().create_timer(1.0).timeout.connect(func() -> void:
				battle.cards.hand = ids
				battle.cards.hand_changed.emit())
		elif a.begins_with("--open-scout="):
			var sid := a.split("=")[1]
			get_tree().create_timer(2.5).timeout.connect(func() -> void: open_scouting(sid))
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
	# Endless: the next milestone (every 5 innings, paid at the end) and the best inning so far.
	_milestone_label = UITheme.label("", 16, UITheme.GOLD, UITheme.font_body_bold())
	_milestone_label.name = "EndlessMilestone"
	_milestone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_milestone_label.custom_minimum_size = Vector2(290, 0)
	_milestone_label.tooltip_text = "Every 5 innings cleared pays coins and a pack at the end of the game."
	_milestone_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_milestone_label.visible = false
	vb.add_child(_milestone_label)
	# Dugout Draft boons taken this game: small chips, hover for what each does.
	_boon_row = VBoxContainer.new()
	_boon_row.add_theme_constant_override("separation", 4)
	_boon_row.visible = false
	vb.add_child(_boon_row)
	_boon_row.add_child(UITheme.label("BOONS", 15, UITheme.MUTED, UITheme.font_body_bold()))
	_boon_box = HFlowContainer.new()
	_boon_box.name = "BoonChips"
	_boon_box.add_theme_constant_override("h_separation", 6)
	_boon_box.add_theme_constant_override("v_separation", 6)
	_boon_row.add_child(_boon_box)


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
	_combo_links = ComboLinks.new()
	_combo_links.name = "ComboLinks"
	_combo_links.hud = self
	_combo_links.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_combo_links.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_box.add_child(_combo_links)
	_double_badge = UITheme.badge("x2", Color(UITheme.GOLD.darkened(0.25), 0.95), 22)
	_double_badge.name = "DoubleCastBadge"
	_double_badge.position = Vector2(tray_w * 0.5 - 150, -44)
	_double_badge.custom_minimum_size = Vector2(300, 0)
	(_double_badge.get_child(0) as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_double_badge.visible = false
	_hand_box.add_child(_double_badge)
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
	_banner = UITheme.title("", 48, Color.WHITE)
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.position = Vector2(-700, 175)
	_banner.custom_minimum_size = Vector2(1400, 0)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.pivot_offset = Vector2(700, 30)
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
	_boss_fill = UITheme.panel_style(BOSS_FILL[""], Color(0, 0, 0, 0), 0, 4, 0)
	_boss_bar.add_theme_stylebox_override("fill", _boss_fill)
	vb.add_child(_boss_bar)
	_boss_window = ProgressBar.new()
	_boss_window.custom_minimum_size = Vector2(0, 5)
	_boss_window.show_percentage = false
	_boss_window.max_value = 1.0
	_boss_window.add_theme_stylebox_override("fill", UITheme.panel_style(Color(1, 1, 1, 0.9), Color(0, 0, 0, 0), 0, 2, 0))
	_boss_window.add_theme_stylebox_override("background", UITheme.panel_style(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0, 2, 0))
	_boss_window.modulate.a = 0.0
	vb.add_child(_boss_window)
	_boss_state = UITheme.label("", 17, Color(1, 1, 1), UITheme.font_display())
	_boss_state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_state.visible = false
	vb.add_child(_boss_state)


## Boss bar fill per state (Update 11).
const BOSS_FILL := {"": Color(1.0, 0.3, 0.15), "phased": Color(0.55, 0.35, 0.95, 0.45), "revealed": Color(1.0, 0.85, 0.35),
	"vulnerable": Color(1.0, 0.75, 0.2)}
const BOSS_STATE_TEXT := {"phased": "PHASED — defenders can't see it · throws and cards already on the way still land",
	"revealed": "REVEALED — +25% DAMAGE · HIT IT NOW!", "vulnerable": "ARMOR CRACKED — +25% DAMAGE, NO ARMOR"}
const BOSS_STATE_COLOR := {"phased": Color(0.78, 0.62, 1.0), "revealed": Color(1.0, 0.9, 0.5), "vulnerable": Color(1.0, 0.8, 0.3)}


## The boss bar's state line: PHASED (violet, the fill turns ghostly), REVEALED / VULNERABLE (gold,
## pulsing) with a thin meter for the time left in the window.
func _fill_boss_state(e: Enemy) -> void:
	var st := ""
	var left := 0.0
	var total := 1.0
	if e.is_phased():
		st = "phased"
		left = e.phased_t
		total = Enemy.PHASE_TIME
	elif e.is_revealed():
		st = "revealed"
		left = e.revealed_t
		total = Enemy.REVEAL_TIME
	elif e.vulnerable_t > 0.0:
		st = "vulnerable"
		left = e.vulnerable_t
		total = 4.0
	if st != boss_state:
		boss_state = st
		_boss_fill.bg_color = BOSS_FILL[st]
		_boss_state.visible = st != ""
		if st != "":
			_boss_state.text = BOSS_STATE_TEXT[st]
			_boss_state.add_theme_color_override("font_color", BOSS_STATE_COLOR[st])
			var wf: StyleBoxFlat = _boss_window.get_theme_stylebox("fill")
			wf.bg_color = BOSS_STATE_COLOR[st]
	_boss_window.modulate.a = 1.0 if st != "" else 0.0
	_boss_window.value = clampf(left / maxf(total, 0.01), 0.0, 1.0)
	if st == "revealed" or st == "vulnerable":
		var calm := bool(Settings.get_value("accessibility", "reduce_flashes", false))
		var k := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		_boss_fill.bg_color = BOSS_FILL[st].lerp(Color(1, 1, 0.9), (0.1 if calm else 0.35) * k)


func _build_controls() -> void:
	var tl := HBoxContainer.new()
	tl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tl.position = Vector2(14, 14)
	tl.add_theme_constant_override("separation", 8)
	root.add_child(tl)
	tl.add_child(_icon_button("pause", "Pause  (Esc)", toggle_pause))
	_speed_btn = _icon_button("fast_forward", "Game speed  (Shift)", func() -> void:
		battle.cycle_speed()
		refresh())
	_speed_btn.get_child(0).queue_free()   # the speed button shows its icon next to the text
	_speed_btn.icon = DB.icon("fast_forward")
	_speed_btn.expand_icon = true
	_speed_btn.add_theme_constant_override("icon_max_width", 22)
	_speed_btn.text = "1x"
	_speed_btn.custom_minimum_size = Vector2(84, 46)
	tl.add_child(_speed_btn)
	tl.add_child(_icon_button("map", "Top-down tactical view  (M)", func() -> void: battle.cam.toggle_tactical()))
	tl.add_child(_icon_button("range", "Show every defender's throwing range  (F)", func() -> void:
		var show: bool = not battle.defenders[0].show_range
		for df in battle.defenders:
			df.set_show_range(show)))

	_start_btn = UITheme.menu_button("PLAY BALL!", UITheme.SCARLET, 40)
	_start_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_start_btn.position = Vector2(-370, -104)
	_start_btn.custom_minimum_size = Vector2(350, 76)
	_start_btn.tooltip_text = "Begin the next wave (Space)"
	_start_btn.pressed.connect(func() -> void: battle.begin_wave())
	root.add_child(_start_btn)
	# Between waves the button reads NEXT WAVE NOW with what an early call pays and the countdown.
	_start_sub = UITheme.label("", 16, UITheme.GOLD, UITheme.font_body_bold())
	_start_sub.name = "EarlyCallCaption"
	_start_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_start_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_sub.offset_left = -170
	_start_sub.offset_right = 170
	_start_sub.offset_top = -26
	_start_sub.offset_bottom = -4
	_start_sub.add_theme_constant_override("outline_size", 4)
	_start_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_start_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_sub.visible = false
	_start_btn.add_child(_start_sub)


## Square icon button for the battle toolbar (icon + tooltip with its hotkey).
func _icon_button(icon_name: String, tip: String, action: Callable) -> Button:
	var b := UITheme.small_button("", UITheme.BLUE, 20)
	b.custom_minimum_size = Vector2(46, 46)
	var ic := UITheme.icon_rect(icon_name, 26, Color(0.88, 0.93, 1.0))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.set_anchors_preset(Control.PRESET_CENTER)
	ic.position = Vector2(-13, -13)
	ic.size = Vector2(26, 26)
	b.add_child(ic)
	b.tooltip_text = tip
	b.pressed.connect(action)
	return b


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
	_formation_cards.clear()
	for fid in DB.formation_order:
		var f: Dictionary = DB.formations[fid]
		var b := UITheme.small_button("", UITheme.SCARLET, 17)
		b.custom_minimum_size = Vector2(138, 92)
		b.tooltip_text = "%s — %s" % [f.name, f.text]
		b.pressed.connect(func() -> void:
			battle.apply_formation(fid)
			_update_formation_cards())
		var fc := FormationCard.new()
		fc.positions = f.get("positions", [])
		fc.title = str(f.name)
		fc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(fc)
		b.set_meta("fid", fid)
		_formation_cards.append(b)
		grid.add_child(b)
	_update_formation_cards()
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

func _update_formation_cards() -> void:
	for b: Button in _formation_cards:
		var on: bool = is_instance_valid(battle) and battle.run.formation == str(b.get_meta("fid"))
		(b.get_child(0) as FormationCard).active = on
		b.get_child(0).queue_redraw()


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
	for id in ["runner", "sprinter", "armored", "swarmer", "jumper", "base_stealer", "trickster", "captain", "slugger", "iron_slugger", "phantom_captain", "grand_slammer"]:
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
	_hand_box.move_child(_combo_links, -1)   # the links draw over the cards (they never take input)
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
	_update_cards.call_deferred()
	if not on:
		_card_tip.visible = false
		return
	var c := DB.card(cv.card_id)
	var lvl: int = battle.run.card_level(cv.card_id)
	var t := "[b][font_size=26]%s[/font_size][/b]  [color=#%s]%s · %s[/color]\n" % [c.name, DB.rarity_color(c.rarity).to_html(false), c.rarity.capitalize(), c.category.capitalize()]
	t += "Cost [color=#3FD0FF]%d energy[/color]" % int(c.cost)
	if float(c.cooldown) > 0:
		t += " · Cooldown %ds" % int(c.cooldown)
	# Levels 6-10 are Prestige ★1-★5 (Update 11, DB.level_label).
	var stars := DB.prestige_stars(lvl)
	t += (" · Prestige ★%d\n" % stars) if stars > 0 else (" · Level %d\n" % lvl)
	t += DB.card_text(cv.card_id, lvl)
	# The full rules text (the card face shows the short version).
	var details := DB.card_details(cv.card_id, lvl)
	if details != "":
		t += "\n[color=#B8C4D6][font_size=17]%s[/font_size][/color]" % details
	var linked: String = c.get("linked", "")
	if linked != "":
		var on_field := false
		for df: Defender in battle.defenders:
			if df.id == linked:
				on_field = true
		t += "\n[color=#%s]Signature of %s%s[/color]" % [DB.defender_accent(linked).to_html(false), DB.defender(linked).name,
			" — on the field: cast by them with their power." if on_field else " — not on the field: 75% power."]
	for pair in _combo_pairs:
		var other := -1
		if _card_views[pair[0]] == cv:
			other = pair[1]
		elif _card_views[pair[1]] == cv:
			other = pair[0]
		if other >= 0 and other < battle.cards.hand.size():
			t += "\n[color=#%s][b]COMBO with %s:[/b] %s[/color]" % [COMBO_COLOR.to_html(false), DB.card(battle.cards.hand[other]).name, pair[2]]
	t += "\n[color=#8D9AB0]Target: %s[/color]" % {"none": "instant (click to confirm)", "enemy": "a runner", "area": "an area", "path": "a point on a route", "defender": "a defender"}.get(c.target, c.target)
	_card_tip_label.text = t
	_card_tip.visible = true
	_card_tip.reset_size()
	var gp := cv.global_position
	_card_tip.global_position = Vector2(clampf(gp.x - 115, 10, root.size.x - 400), gp.y - _card_tip.size.y - 24)


func _update_cards() -> void:
	var cs: CardSystem = battle.cards
	var preview := 0
	for i in _card_views.size():
		var v: CardView = _card_views[i] if is_instance_valid(_card_views[i]) else null
		if v and (v._hover or i == battle.targeting_index) and i < cs.hand.size() and cs.hand[i] != "":
			preview = cs.cost_of(cs.hand[i])
			if v._hover:
				break
	if _energy_bar.preview_cost != preview:
		_energy_bar.preview_cost = preview
		_energy_bar.queue_redraw()
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
	_update_combos()


## Combo hints: which hand cards combo with each other (data/combos.json). Partners glow and are
## linked; the selected card's partner glows brightest. Drawing only: nothing here touches input.
func _update_combos() -> void:
	var cs: CardSystem = battle.cards
	var hand: Array = []
	for i in _card_views.size():
		hand.append(cs.hand[i] if i < cs.hand.size() and is_instance_valid(_card_views[i]) else "")
	_combo_pairs = combo_pairs(hand)
	var glow := {}
	var partner := {}
	for pair in _combo_pairs:
		glow[pair[0]] = true
		glow[pair[1]] = true
		if battle.targeting_index == pair[0]:
			partner[pair[1]] = true
		elif battle.targeting_index == pair[1]:
			partner[pair[0]] = true
	for i in _card_views.size():
		var cv: CardView = _card_views[i] if is_instance_valid(_card_views[i]) else null
		if cv:
			cv.combo_glow = 1.0 if glow.has(i) else 0.0
			cv.combo_partner = partner.has(i)
	if not _combo_pairs.is_empty():
		_maybe_hint_combo()


## Pairs of slots in `hand` (card ids, "" for an empty slot) whose cards form a combo:
## [[slot_a, slot_b, combo text]], each pair once, in slot order.
static func combo_pairs(hand: Array) -> Array:
	var out: Array = []
	for i in hand.size():
		var a := str(hand[i])
		if a == "":
			continue
		for j in range(i + 1, hand.size()):
			var b := str(hand[j])
			if b == "" or b == a:
				continue
			for c in DB.combos:
				if a in c.cards and b in c.cards:
					out.append([i, j, str(c.text)])
					break
	return out


## The first time a combo pair is in the hand (never during the battle tutorial): a tip.
func _maybe_hint_combo() -> void:
	if Hints.seen("battle_combo") or not Hints.enabled() or Hints.is_showing() or get_node_or_null("Tutorial") != null \
			or not bool(Profile.data.flags.get("battle_tutorial_done", false)) or battle.state == "results":
		return
	var target: Control = _card_views[_combo_pairs[0][0]]
	Hints.show_unseen(self, ["battle_combo"], func() -> Dictionary: return {"battle_combo": target})


# ---------------------------------------------------------------- scouting

## Opens the scouting card for a runner type over the battle (pauses until closed).
func open_scouting(enemy_id: String) -> void:
	if (_scout_popup and is_instance_valid(_scout_popup)) or battle.state == "results" or (_pause and is_instance_valid(_pause)):
		return
	Audio.ui("ui_click", -3.0)
	_card_tip.visible = false
	_scout_popup = ScoutingBook.popup(root, enemy_id)


## A runner type met for the first time: once, point at the threat panel's reports.
func _on_scouted(keys: Array) -> void:
	if Hints.seen("battle_scout") or not Hints.enabled() or Hints.is_showing() or get_node_or_null("Tutorial") != null \
			or not bool(Profile.data.flags.get("battle_tutorial_done", false)) or battle.practice:
		return
	for k in keys:
		if str(k) != "runner" and not Scouting.is_affix(str(k)):
			Hints.show_unseen(self, ["battle_scout"], func() -> Dictionary: return {"battle_scout": _threat_icons}, 0.6)
			return


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
	if run.mode_id == "boss_rush" and run.max_innings > 0:   # Boss Rush: which boss closes this round
		var boss_id := run.boss_for_inning(run.inning)
		if boss_id != "":
			mods.append("BOSS %d OF %d: %s" % [run.inning, run.max_innings, str(DB.enemy(boss_id).get("name", boss_id)).to_upper()])
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
	var doubles: int = cs.double_casts_left(run.inning) if cs.has_method("double_casts_left") else 0
	_double_badge.visible = doubles > 0 and battle.state != "results"
	if doubles > 0:
		(_double_badge.get_child(0) as Label).text = "x2  ·  NEXT %d CARD%s CAST TWICE" % [doubles, "" if doubles == 1 else "S"]
	_update_cards()

	# Start button: PLAY BALL in setup; NEXT WAVE NOW (+1 energy, the countdown) between waves.
	var show_start: bool = battle.state in ["setup", "break"] and not battle.practice
	_start_btn.visible = show_start
	if battle.state == "break":
		var auto := bool(Settings.get_value("gameplay", "auto_start_waves", true))
		_start_btn.text = "NEXT WAVE NOW"
		_start_sub.text = ("+%d ENERGY  ·  SPACE  ·  AUTO IN %ds" % [int(Battle.EARLY_CALL_ENERGY), int(ceil(battle.break_timer))]) if auto \
			else "+%d ENERGY  ·  SPACE" % int(Battle.EARLY_CALL_ENERGY)
		_start_btn.tooltip_text = "Call the next wave now (Space): +%d energy and bonus coins for the time you skip." % int(Battle.EARLY_CALL_ENERGY)
		_start_sub.visible = true
		_set_start_pulse(true)
	elif battle.state == "setup":
		_start_btn.text = "PLAY BALL!"
		_start_btn.tooltip_text = "Begin the next wave (Space)"
		_start_sub.visible = false
		_set_start_pulse(false)
	else:
		_set_start_pulse(false)
	_fill_boons()
	_fill_milestone()
	# Boss
	if _boss_enemy and is_instance_valid(_boss_enemy) and _boss_enemy.alive:
		_boss_bar.max_value = _boss_enemy.max_hp
		_boss_bar.value = _boss_enemy.hp
		var tag := ""
		if _boss_enemy.vulnerable_t > 0.0:
			tag = "  — VULNERABLE!"
		elif _boss_enemy.is_revealed():
			tag = "  — REVEALED!"
		elif _boss_enemy.is_phased() or _boss_enemy.untargetable_t > 0.0:
			tag = "  — PHASED"
		_boss_name.text = _boss_enemy.data.name.to_upper() + tag
		_fill_boss_state(_boss_enemy)
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
			return "Wave cleared! Reposition now, or call NEXT WAVE NOW for +%d energy and bonus coins (Space)." % int(Battle.EARLY_CALL_ENERGY)
		"draft":
			return "Dugout Draft: pick a boon (click a card or press 1-3)."
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
		r.tooltip_text = "%s — %s\nClick for its scouting report." % [DB.enemy(id).name, DB.enemy(id).text]
		r.mouse_filter = Control.MOUSE_FILTER_STOP
		r.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		r.name = "Threat_" + str(id)
		var eid := str(id)
		r.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				r.accept_event()
				open_scouting(eid))
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

## Call-outs ("DOUBLE PLAY!", "INNING 3"): one at a time, queued (max 2 waiting). A call-out of
## the same kind as the one showing (a growing combo) updates it in place instead of stacking.
func banner(text: String, color: Color) -> void:
	if _banner_busy and _banner_kind(text) == _banner_kind(_banner.text):
		_banner.text = text
		_banner.add_theme_color_override("font_color", color)
		_banner.scale = Vector2(1.12, 1.12)
		_run_banner_tween(false)
		return
	if _banner_busy:
		if _banner_queue.size() >= 2:
			_banner_queue.pop_front()
		_banner_queue.append([text, color])
		return
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.scale = Vector2(0.6, 0.6)
	_banner.modulate.a = 0.0
	_run_banner_tween(true)


func _run_banner_tween(fresh: bool) -> void:
	_banner_busy = true
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.12 if fresh else 0.05)
	_banner_tween.tween_property(_banner, "scale", Vector2.ONE, 0.25 if fresh else 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(0.85)
	_banner_tween.chain().tween_property(_banner, "modulate:a", 0.0, 0.25)
	_banner_tween.chain().tween_callback(_banner_finished)


func _banner_finished() -> void:
	_banner_busy = false
	if not _banner_queue.is_empty():
		var nxt: Array = _banner_queue.pop_front()
		banner(str(nxt[0]), nxt[1])


static func _banner_kind(t: String) -> String:
	# A growing combo (DOUBLE PLAY -> TRIPLE PLAY -> GRAND SLAM COMBO) upgrades one banner in place.
	if t in ["DOUBLE PLAY!", "TRIPLE PLAY!"] or t.begins_with("GRAND SLAM COMBO"):
		return "combo"
	var out := ""
	for ch in t:
		if not ch.is_valid_int():
			out += ch
	return out


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
	_reset_boss_state()


func hide_boss() -> void:
	_boss_enemy = null
	_boss_panel.visible = false
	_reset_boss_state()


func _reset_boss_state() -> void:
	boss_state = ""
	_boss_fill.bg_color = BOSS_FILL[""]
	_boss_state.visible = false
	_boss_window.modulate.a = 0.0


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
	# Flourish (impact at ~0.38 s, never holds up play): the played card lifts out of the hand
	# glowing in its category colour, flies to its target trailing light and bursts there.
	# Cards without a target point burst at their casting defender, or at home plate.
	var lvl: int = battle.run.card_level(id)
	var cv := CardView.new(id, lvl)
	cv.set_card(id, lvl)
	var sz := Vector2(146, 204)
	cv.custom_minimum_size = sz
	cv.size = sz
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.selected = true
	var from := _selected_card_rect.position if _selected_card_rect.size.x > 0.0 else Vector2(root.size.x * 0.5 - sz.x * 0.5, root.size.y - 250)
	_selected_card_rect = Rect2()
	var col := DB.category_color(DB.card(id).category)
	var calm := bool(Settings.get_value("accessibility", "reduce_flashes", false))
	var world: Variant = battle.last_cast_point
	var caster: Node3D = battle.effects.caster_info(id).get("caster")
	if str(DB.card(id).get("target", "none")) == "none" and caster and is_instance_valid(caster):
		world = caster.global_position + Vector3(0, 1.0, 0)
	elif not (world is Vector3):
		world = Field.HOME + Vector3(0, 0.5, 0)
	var to := from + Vector2(0, -260)
	var cam := battle.get_viewport().get_camera_3d()
	if cam and not cam.is_position_behind(world):
		to = cam.unproject_position(world) - sz * 0.5
	# Light trail behind the flying card (drawn under it).
	var trail := Line2D.new()
	trail.width = 34.0
	trail.default_color = Color(col.lightened(0.3), 0.9)
	var wc := Curve.new()
	wc.add_point(Vector2(0.0, 0.05))
	wc.add_point(Vector2(1.0, 1.0))
	trail.width_curve = wc
	var grad := Gradient.new()
	grad.set_color(0, Color(col, 0.0))
	grad.set_color(1, Color(col.lightened(0.45), 0.85))
	trail.gradient = grad
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	var tmat := CanvasItemMaterial.new()
	tmat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	trail.material = tmat
	root.add_child(trail)
	cv.position = from
	cv.pivot_offset = sz * 0.5
	root.add_child(cv)
	# Category-coloured halo behind the card while it lifts and flies.
	var halo := RingBurst.new()
	halo.kind = "halo"
	halo.color = col
	halo.size = sz
	halo.show_behind_parent = true
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(halo)
	var lifted := from + Vector2(0, -64)
	# The flight bends up and over (a quadratic curve through a raised midpoint).
	var mid := lifted.lerp(to, 0.5) + Vector2(0, -minf(120.0, lifted.distance_to(to) * 0.25))
	var tw := cv.create_tween()
	tw.tween_property(cv, "position", lifted, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(cv, "scale", Vector2(1.14, 1.14), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(halo, "t", 1.0, 0.1)
	tw.tween_callback(func() -> void: Audio.play("card_whoosh", -10.0, 0.08, 80))
	var fly := func(k: float) -> void:
		var e := k * k
		var q := lifted.lerp(mid, e).lerp(mid.lerp(to, e), e)
		cv.position = q
		cv.scale = Vector2.ONE * lerpf(1.14, 0.2, e)
		cv.rotation = deg_to_rad(10.0) * e
		trail.add_point(q + sz * 0.5)
		while trail.get_point_count() > 14:
			trail.remove_point(0)
	tw.tween_method(fly, 0.0, 1.0, 0.28)
	tw.tween_callback(func() -> void:
		_ring_burst(cv.position + sz * 0.5, col, calm)
		cv.queue_free()
		var ft := trail.create_tween()
		ft.tween_property(trail, "modulate:a", 0.0, 0.16)
		ft.tween_callback(trail.queue_free))


## Impact at the end of the cast flourish: a flash, two rings, rays and sparks.
func _ring_burst(at: Vector2, col: Color, calm := false) -> void:
	var fx := RingBurst.new()
	fx.color = col
	fx.calm = calm
	fx.position = at
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fx)
	var tw := fx.create_tween()
	tw.tween_property(fx, "t", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(fx.queue_free)


class RingBurst:
	extends Control
	var color := Color.WHITE
	var kind := "burst"        # "burst" (impact) or "halo" (glow behind the flying card)
	var calm := false          # reduce_flashes: no white core
	var _seed := randf() * TAU
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _draw() -> void:
		if kind == "halo":
			# Card-shaped glow; `t` fades it in during the lift, then it rides with the card.
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_corner_radius_all(14)
			sb.set_border_width_all(4)
			sb.border_color = Color(color.lightened(0.55), 0.95 * t)
			sb.shadow_color = Color(color.lightened(0.15), 0.75 * t)
			sb.shadow_size = 22
			draw_style_box(sb, Rect2(Vector2(-4, -4), size + Vector2(8, 8)))
			return
		var k := 1.0 - t
		# Core flash, then a fast ring and a slower ring.
		if not calm:
			draw_circle(Vector2.ZERO, 34.0 * k * k, Color(1, 1, 1, 0.85 * k))
		draw_circle(Vector2.ZERO, 22.0 + 30.0 * t, Color(color, 0.35 * k * k))
		draw_arc(Vector2.ZERO, 22.0 + 86.0 * t, 0, TAU, 48, Color(color.lightened(0.45), k), 7.0 * k + 1.0, true)
		var t2 := clampf(t * 1.4 - 0.25, 0.0, 1.0)
		if t2 > 0.0:
			draw_arc(Vector2.ZERO, 14.0 + 52.0 * t2, 0, TAU, 40, Color(color, 0.8 * (1.0 - t2)), 3.0 * (1.0 - t2) + 0.5, true)
		# Rays and sparks thrown outward.
		for i in 10:
			var a := _seed + TAU * i / 10.0
			var d := Vector2(cos(a), sin(a))
			var r0 := 18.0 + 70.0 * t
			var r1 := r0 + (26.0 if i % 2 == 0 else 14.0) * k
			draw_line(d * r0, d * r1, Color(color.lightened(0.6), k), 3.0 * k + 0.5, true)
			draw_circle(d.rotated(0.3) * (12.0 + 100.0 * sqrt(t)), 3.2 * k, Color(color.lightened(0.7), k))


# ---------------------------------------------------------------- state & overlays

func _on_state(s: String) -> void:
	_setup_panel.visible = s in ["setup"] and not battle.practice
	if s != "draft" and _draft and is_instance_valid(_draft) and not _draft.is_queued_for_deletion() and not bool(_draft.get("_picked")):
		_draft.queue_free()   # the game moved on without a pick (forfeit): drop the overlay
		_draft = null
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


# ---------------------------------------------------------------- Update 9: draft, boons, milestones

## Dugout Draft: three boon cards over the field (see BoonDraft). Battle.choose_boon takes the pick.
func show_draft(offers: Array) -> void:
	if _draft and is_instance_valid(_draft):
		_draft.queue_free()
	_card_tip.visible = false
	_unit_panel.visible = false
	var d := BoonDraft.new()
	d.name = "BoonDraft"
	d.battle = battle
	d.offers = offers.duplicate()
	_draft = d
	d.tree_exited.connect(func() -> void:
		if _draft == d:
			_draft = null)
	root.add_child(d)
	# First draft ever: a short tip pointing at the cards (after the reveal; not during the tutorial).
	if get_node_or_null("Tutorial") == null and not battle.practice and not battle.auto_test:
		Hints.show_unseen(self, ["battle_boons"], func() -> Dictionary:
			if not is_instance_valid(d):
				return {}
			return {"battle_boons": d.card_row if d.card_row else d}, 0.9)


func _fill_boons() -> void:
	var ids: Array = battle.run.boons
	var key := ",".join(PackedStringArray(ids.map(func(x: Variant) -> String: return str(x))))
	if _boon_box.get_meta("key", "-") == key:
		return
	_boon_box.set_meta("key", key)
	for c in _boon_box.get_children():
		c.queue_free()
	_boon_row.visible = not ids.is_empty()
	for b: Dictionary in Boons.summary(ids):
		_boon_box.add_child(_boon_chip(b))


## One active boon: a small rarity-coloured tile with its icon; the tooltip says what it does.
func _boon_chip(b: Dictionary) -> Control:
	var col := Boons.rarity_color(str(b.rarity))
	var chip := PanelContainer.new()
	chip.name = "Boon_" + str(b.id)
	chip.add_theme_stylebox_override("panel", UITheme.panel_style(Color(col.darkened(0.6), 0.95), Color(col, 0.9), 2, 8, 4))
	chip.tooltip_text = "%s (%s boon)\n%s" % [b.name, Boons.rarity_name(str(b.rarity)), b.text]
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_child(UITheme.icon_rect(str(b.icon), 26, col.lightened(0.5)))
	return chip


func _fill_milestone() -> void:
	var run: RunState = battle.run
	if not run.is_endless():
		_milestone_label.visible = false
		return
	var next := int(ceil(run.inning / 5.0)) * 5
	var best := int(Profile.data.get("records", {}).get("best_endless_inning", 0))
	var t := "NEXT MILESTONE: INNING %d" % next
	if best > 0:
		t += "   ·   BEST: %d" % best
	if not run.milestones.is_empty():
		t += "\nMilestones reached: %d" % run.milestones.size()
	_milestone_label.text = t
	_milestone_label.visible = true


## A soft glow pulse on NEXT WAVE NOW between waves (clear, not loud).
func _set_start_pulse(on: bool) -> void:
	if on == (_start_pulse != null and _start_pulse.is_valid()):
		return
	if _start_pulse and _start_pulse.is_valid():
		_start_pulse.kill()
	_start_pulse = null
	_start_btn.self_modulate = Color.WHITE
	if on:
		_start_pulse = _start_btn.create_tween().set_loops()
		_start_pulse.tween_property(_start_btn, "self_modulate", Color(1.18, 1.12, 0.95), 0.7).set_trans(Tween.TRANS_SINE)
		_start_pulse.tween_property(_start_btn, "self_modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)


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
	var preview_cost := 0       # cost of the hovered/selected card: shown on the bar
	var _t := 0.0

	func _process(delta: float) -> void:
		if preview_cost > 0:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var n := 10
		var gap := 4.0
		var w := (size.x - gap * (n - 1)) / n
		var pulse := 0.5 + 0.5 * sin(_t * 7.0)
		var spend_from := value - float(preview_cost)   # segments above this would be spent
		for i in n:
			var r := Rect2(i * (w + gap), 0, w, size.y)
			draw_rect(r, Color(0.02, 0.05, 0.1, 0.9))
			var fill := clampf(value - i, 0.0, 1.0)
			if fill > 0.0:
				var c := UITheme.ENERGY if fill >= 1.0 else UITheme.ENERGY.darkened(0.45)
				if preview_cost > 0 and spend_from >= 0.0 and float(i) + 1.0 > spend_from:
					c = c.lerp(Color.WHITE, 0.35 + 0.3 * pulse)   # what this card would spend
				draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), c)
				if fill >= 1.0:
					draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.35)), Color(1, 1, 1, 0.25))
			if preview_cost > 0 and spend_from < 0.0 and i < preview_cost and float(i) + 1.0 > value:
				draw_rect(r, Color(1.0, 0.35, 0.3, 0.55 + 0.4 * pulse), false, 2.0)   # missing energy
			else:
				draw_rect(r, Color(1, 1, 1, 0.18), false, 1.0)


## The hand area: draws empty slots behind the cards. The first one is the next card: a card
## back that fills with gold as the draw timer runs, with the seconds left.
class HandTray:
	extends Control
	var hud: Node
	var _box_empty: StyleBoxFlat
	var _box_next: StyleBoxFlat
	var _box_fill: StyleBoxFlat

	func _ready() -> void:
		_box_empty = StyleBoxFlat.new()
		_box_empty.bg_color = Color(0.02, 0.04, 0.08, 0.28)
		_box_empty.border_color = Color(1, 1, 1, 0.12)
		_box_empty.set_border_width_all(2)
		_box_empty.set_corner_radius_all(12)
		_box_next = StyleBoxFlat.new()
		_box_next.bg_color = Color(0.06, 0.1, 0.2, 0.82)
		_box_next.border_color = Color(UITheme.GOLD, 0.45)
		_box_next.set_border_width_all(2)
		_box_next.set_corner_radius_all(12)
		_box_fill = StyleBoxFlat.new()
		_box_fill.bg_color = Color(UITheme.GOLD, 0.2)
		_box_fill.corner_radius_bottom_left = 12
		_box_fill.corner_radius_bottom_right = 12

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
			if not first_empty:
				draw_style_box(_box_empty, r)
				continue
			first_empty = false
			var p := cs.next_draw_progress()
			draw_style_box(_box_next, r)
			var fh := (r.size.y - 4.0) * p
			if fh > 1.0:
				draw_style_box(_box_fill, Rect2(r.position.x + 2, r.end.y - 2 - fh, r.size.x - 4, fh))
			# Card-back emblem: a diamond with a ball.
			var c := r.get_center() + Vector2(0, -14)
			var d := 30.0
			var col := Color(UITheme.GOLD, 0.35 + 0.4 * p)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), Color(col, 0.18))
			draw_polyline(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0), c + Vector2(0, -d)]), col, 2.0, true)
			draw_circle(c, 9.0, Color(1, 1, 1, 0.3 + 0.5 * p))
			var f := UITheme.font_body_bold()
			var t := "NEXT CARD"
			var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(f, Vector2(r.get_center().x - tw * 0.5, r.end.y - 52), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.6))
			if hud.battle.state == "wave":
				var secs := "%ds" % int(ceil((1.0 - p) * cs.draw_interval))
				var sw := f.get_string_size(secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 22).x
				draw_string(f, Vector2(r.get_center().x - sw * 0.5, r.end.y - 24), secs, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(UITheme.GOLD, 0.9))


## Combo links over the hand: a soft arc from card to card above every combo pair in the hand,
## with sparks running along it. A pair that includes the selected card is drawn brightest.
## Pure drawing (mouse_filter IGNORE, drawn last in the tray), so card clicks are untouched.
class ComboLinks:
	extends Control
	var hud: Node
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		var pairs: Array = hud._combo_pairs if hud else []
		visible = not pairs.is_empty()
		if pairs.is_empty():
			return
		queue_redraw()
		for p in pairs:   # the glow pulses: keep both cards redrawing while linked
			for k in [p[0], p[1]]:
				var cv: Variant = hud._card_views[k]
				if is_instance_valid(cv):
					(cv as CanvasItem).queue_redraw()

	static func _top(cv: CardView) -> Vector2:
		var s := cv.size.x / 150.0
		var rise := s * (cv.lift_px * cv._lift + cv.lift_px * 1.2 * cv._sel)
		return cv.position + Vector2(cv.size.x * 0.5, -rise)

	func _draw() -> void:
		if hud == null:
			return
		var pairs: Array = hud._combo_pairs
		var sel: int = hud.battle.targeting_index
		var calm := bool(Settings.get_value("accessibility", "reduce_flashes", false))
		var col: Color = hud.COMBO_COLOR
		var n := 0
		for p in pairs:
			var a: Variant = hud._card_views[p[0]]
			var b: Variant = hud._card_views[p[1]]
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			var hot: bool = sel == p[0] or sel == p[1]
			var alpha := 1.0 if hot else (0.4 if sel >= 0 else 0.75)
			var pa := _top(a) + Vector2(22, 4)
			var pb := _top(b) + Vector2(-22, 4)
			var lift := 26.0 + 0.08 * absf(pb.x - pa.x) + 10.0 * (n % 2)
			var ctrl := (pa + pb) * 0.5 + Vector2(0, -lift * 2.0)
			var pts := PackedVector2Array()
			for k in 25:
				var u := k / 24.0
				pts.append(pa.lerp(ctrl, u).lerp(ctrl.lerp(pb, u), u))
			draw_polyline(pts, Color(col, 0.22 * alpha), 11.0 if hot else 8.0, true)
			draw_polyline(pts, Color(col.lightened(0.25), 0.95 * alpha), 3.0 if hot else 2.2, true)
			for end in [pa, pb]:
				draw_circle(end, 5.5 if hot else 4.5, Color(0.02, 0.06, 0.05, 0.9 * alpha))
				draw_arc(end, 5.5 if hot else 4.5, 0, TAU, 16, Color(col, alpha), 1.6, true)
			# Sparks running along the arc (they stay put with reduced flashes).
			for k in 3:
				var u := fmod(_t * (0.0 if calm else 0.55) + k / 3.0, 1.0)
				var q: Vector2 = pa.lerp(ctrl, u).lerp(ctrl.lerp(pb, u), u)
				var fade := sin(u * PI)
				draw_circle(q, 3.2 if hot else 2.6, Color(1.0, 1.0, 0.95, 0.9 * fade * alpha))
				draw_circle(q, 7.0, Color(col, 0.18 * fade * alpha))
			if hot:
				var f := UITheme.font_body_bold()
				var label := "COMBO"
				var mid: Vector2 = pa.lerp(ctrl, 0.5).lerp(ctrl.lerp(pb, 0.5), 0.5)
				var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
				var box := Rect2(mid + Vector2(-tw * 0.5 - 8, -24), Vector2(tw + 16, 20))
				draw_rect(box, Color(0.02, 0.08, 0.06, 0.92))
				draw_rect(box, Color(col, 0.9), false, 1.5)
				draw_string(f, box.position + Vector2(8, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.lightened(0.3))
			n += 1


## Formation preset button face: a mini diamond with the six defender spots, and the name.
class FormationCard:
	extends Control
	var positions: Array = []
	var title := ""
	var active := false

	func _draw() -> void:
		var area := Rect2(Vector2(8, 6), Vector2(size.x - 16, size.y - 30))
		# Field x -24..24, z -22 (deep outfield) .. 14 (behind home), uniform scale, centred.
		var k := minf(area.size.x / 48.0, area.size.y / 36.0)
		var origin := area.get_center() - Vector2(0.0, -4.0) * k
		var to_px := func(x: float, z: float) -> Vector2:
			return origin + Vector2(x, z) * k
		var grass := Color(0.25, 0.6, 0.3, 0.55 if active else 0.35)
		var home: Vector2 = to_px.call(0.0, 10.0)
		var arc := PackedVector2Array([home])
		for i in 13:
			var a := deg_to_rad(-135.0 + 90.0 * i / 12.0)
			arc.append(home + Vector2(cos(a), sin(a)) * 30.0 * k)
		draw_colored_polygon(arc, grass)
		var bases := [to_px.call(0.0, 10.0), to_px.call(9.5, 0.5), to_px.call(0.0, -9.0), to_px.call(-9.5, 0.5)]
		draw_colored_polygon(PackedVector2Array(bases), Color(0.75, 0.5, 0.3, 0.6 if active else 0.4))
		for p in positions:
			var c: Vector2 = to_px.call(float(p[0]), float(p[1]))
			draw_circle(c, 4.2, Color(0, 0, 0, 0.5))
			draw_circle(c, 3.2, UITheme.GOLD if active else Color(0.9, 0.95, 1.0))
		var f := UITheme.font_body_bold()
		var fs := 17
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - tw) * 0.5, size.y - 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UITheme.GOLD if active else Color.WHITE)
		if active:
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(UITheme.GOLD, 0.9), false, 2.0)


func _exit_tree() -> void:
	# _top_score is never added to the tree, so it would outlive the HUD (an orphan Label that kept a
	# font and its glyph textures alive: the "ObjectDB instances leaked at exit" warning).
	if is_instance_valid(_top_score) and not _top_score.is_inside_tree():
		_top_score.free()
