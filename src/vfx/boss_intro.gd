class_name BossIntro
extends Node
## Boss entrance: the camera swings to the boss's gate, the gate bursts open and a name card
## ("THE GRAND SLAMMER" + one line on its threat) slides across the top of the screen, then
## the camera returns to where the player was looking. About 2.7 s in total; a click or Space
## skips it (the click still reaches the game, so a card can be picked straight away).
## The game keeps running underneath; nothing here changes the simulation.
## Owns its own CanvasLayer above the HUD; every control ignores the mouse.

signal finished

const T_BURST := 0.35
const T_CARD := 0.45
const T_RETURN := 2.35
const T_END := 2.7

const THREATS := {
	"iron_slugger": "Iron plating shrugs off throws. Hit it hard after each ground slam.",
	"phantom_captain": "Phases out and conjures decoys. Strike when it turns solid.",
	"grand_slammer": "Home-run swings stun your fielders. Calls in backup as it weakens.",
}
const TAGS := {"grand_slammer": "FINAL BOSS"}

var battle: Battle
var boss: Enemy
var gate := Vector3.ZERO
var _t := 0.0
var _saved := []
var _burst_done := false
var _returned := false
var _layer: CanvasLayer
var _root: Control
var _band: Panel
var _title: Label
var _threat: Label
var _tag: Label
var _hint: Label
var _card_tw: Tween


static func color_for(id: String) -> Color:
	return {"iron_slugger": Color(1.0, 0.55, 0.15), "phantom_captain": Color(0.72, 0.42, 1.0),
		"grand_slammer": Color(1.0, 0.78, 0.22)}.get(id, Color(1.0, 0.5, 0.2))


func _ready() -> void:
	var cam := battle.cam
	_saved = [cam._t_focus, cam._t_yaw, cam._t_pitch, cam._t_distance]
	cam.cinematic = true
	cam.set_view(gate.lerp(Field.HOME, 0.16), cam._t_yaw, -27.0, 23.0)
	cam.shake(0.2)
	_build_card()


func _build_card() -> void:
	var col := color_for(boss.id)
	_layer = CanvasLayer.new()
	_layer.layer = 12
	add_child(_layer)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root)
	var vs := _root.get_viewport_rect().size
	var ui := clampf(vs.y / 1080.0, 0.6, 1.6)
	_band = Panel.new()
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.07, 0.86)
	sb.border_color = Color(col, 0.95)
	sb.border_width_top = int(4 * ui)
	sb.border_width_bottom = int(4 * ui)
	sb.skew = Vector2(-0.12, 0)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = int(18 * ui)
	_band.add_theme_stylebox_override("panel", sb)
	var bh := 178.0 * ui
	_band.size = Vector2(vs.x * 0.74, bh)
	_band.position = Vector2(vs.x * 0.13, vs.y * 0.17)
	_band.pivot_offset = _band.size * 0.5
	_root.add_child(_band)
	_tag = _label(TAGS.get(boss.id, "BOSS"), int(22 * ui), Color(1.0, 0.32, 0.25), UITheme.font_header())
	_tag.position = Vector2(0, 12 * ui)
	_tag.size = Vector2(_band.size.x, 30 * ui)
	_band.add_child(_tag)
	_title = _label("THE " + String(boss.data.get("name", boss.id)).to_upper(), int(66 * ui), col.lerp(Color.WHITE, 0.25), UITheme.font_display())
	_title.add_theme_constant_override("outline_size", int(14 * ui))
	_title.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.0, 0.95))
	_title.position = Vector2(0, 38 * ui)
	_title.size = Vector2(_band.size.x, 80 * ui)
	_band.add_child(_title)
	_threat = _label(THREATS.get(boss.id, String(boss.data.get("text", ""))), int(24 * ui), UITheme.OFFWHITE, UITheme.font_body_bold())
	_threat.position = Vector2(0, 116 * ui)
	_threat.size = Vector2(_band.size.x, 32 * ui)
	_band.add_child(_threat)
	_hint = _label("Click or Space to skip", int(16 * ui), Color(UITheme.MUTED, 0.85), UITheme.font_body())
	_hint.position = Vector2(0, bh + 8 * ui)
	_hint.size = Vector2(_band.size.x, 22 * ui)
	_band.add_child(_hint)
	_band.modulate.a = 0.0


func _label(text: String, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _card_in() -> void:
	_card_tw = create_tween().set_parallel(true)
	_band.scale = Vector2(1.25, 0.2)
	_card_tw.tween_property(_band, "modulate:a", 1.0, 0.16)
	_card_tw.tween_property(_band, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_title.position.x = 90.0
	_card_tw.tween_property(_title, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_threat.modulate.a = 0.0
	_card_tw.tween_property(_threat, "modulate:a", 1.0, 0.25).set_delay(0.18)


func _card_out(time: float) -> void:
	if _card_tw and _card_tw.is_valid():
		_card_tw.kill()
	_card_tw = create_tween().set_parallel(true)
	_card_tw.tween_property(_band, "modulate:a", 0.0, time)
	_card_tw.tween_property(_band, "scale", Vector2(1.08, 0.6), time).set_ease(Tween.EASE_IN)


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	if not _burst_done and _t >= T_BURST:
		_burst_done = true
		battle.vfx.boss_gate_burst(gate, color_for(boss.id))
		battle.cam.shake(0.45)
	if _band.modulate.a == 0.0 and _t >= T_CARD and _t < T_RETURN and (_card_tw == null or not _card_tw.is_valid()):
		_card_in()
	if not _returned and _t >= T_RETURN:
		_return(0.3)
	if _t >= T_END:
		_finish()


func _return(card_time: float) -> void:
	_returned = true
	_card_out(card_time)
	var cam := battle.cam
	cam.set_view(_saved[0], _saved[1], _saved[2], _saved[3])
	cam.cinematic = false


## Click or Space skips; the event is not consumed, so a click on a card still picks it.
func _input(event: InputEvent) -> void:
	if _returned:
		return
	var skip := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		skip = true
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_SPACE:
		skip = true
		get_viewport().set_input_as_handled()
	if skip:
		_t = maxf(_t, T_RETURN)
		_return(0.15)
		_t = T_END - 0.15


func _finish() -> void:
	if not _returned:
		_return(0.15)
	finished.emit()
	queue_free()


## Ends the intro at once (the battle is leaving, or another cinematic takes over).
func abort() -> void:
	if is_queued_for_deletion():
		return
	_finish()
