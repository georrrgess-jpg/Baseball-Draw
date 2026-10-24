extends Node
## Defines every input action with its default bindings and handles rebinding.
## Custom bindings are saved to user://controls.cfg.

signal bindings_changed

const PATH := "user://controls.cfg"

## action -> [display name, [default keys/buttons]]. Keys are Key enums, mouse buttons are "mouse:N".
var ACTIONS := {
	"pan_up": ["Pan camera up", [KEY_W, KEY_UP]],
	"pan_down": ["Pan camera down", [KEY_S, KEY_DOWN]],
	"pan_left": ["Pan camera left", [KEY_A, KEY_LEFT]],
	"pan_right": ["Pan camera right", [KEY_D, KEY_RIGHT]],
	"zoom_in": ["Zoom in", ["mouse:%d" % MOUSE_BUTTON_WHEEL_UP, KEY_EQUAL]],
	"zoom_out": ["Zoom out", ["mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN, KEY_MINUS]],
	"select": ["Select / confirm", ["mouse:%d" % MOUSE_BUTTON_LEFT]],
	"cancel": ["Cancel / context", ["mouse:%d" % MOUSE_BUTTON_RIGHT]],
	"card_prev": ["Previous card", [KEY_Q]],
	"card_next": ["Next card", [KEY_E]],
	"card_1": ["Card 1", [KEY_1]],
	"card_2": ["Card 2", [KEY_2]],
	"card_3": ["Card 3", [KEY_3]],
	"card_4": ["Card 4", [KEY_4]],
	"card_5": ["Card 5", [KEY_5]],
	"start_wave": ["Begin next wave", [KEY_SPACE]],
	"fast_forward": ["Fast-forward", [KEY_SHIFT]],
	"rotate": ["Rotate camera / formation", [KEY_R]],
	"cycle_defender": ["Cycle defenders", [KEY_TAB]],
	"info": ["Filter / info", [KEY_F]],
	"tactical_map": ["Tactical map", [KEY_M]],
	"center_camera": ["Center camera", [KEY_C]],
	"confirm": ["Confirm", [KEY_ENTER, KEY_KP_ENTER]],
	"pause": ["Pause / back", [KEY_ESCAPE]],
}

## Actions that can be rebound from the Settings screen (mouse actions stay fixed).
const REBINDABLE := ["pan_up", "pan_down", "pan_left", "pan_right", "card_prev", "card_next", "card_1", "card_2",
	"card_3", "card_4", "card_5", "start_wave", "fast_forward", "rotate", "cycle_defender", "info",
	"tactical_map", "center_camera", "confirm", "pause"]

var custom := {}  # action -> keycode (primary binding override)


func _ready() -> void:
	_load()
	_apply()


func _make_event(spec: Variant) -> InputEvent:
	if typeof(spec) == TYPE_STRING and String(spec).begins_with("mouse:"):
		var mb := InputEventMouseButton.new()
		mb.button_index = int(String(spec).substr(6)) as MouseButton
		return mb
	var k := InputEventKey.new()
	k.physical_keycode = int(spec) as Key
	return k


func _apply() -> void:
	for action in ACTIONS.keys():
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		var specs: Array = ACTIONS[action][1].duplicate()
		if custom.has(action):
			specs[0] = int(custom[action])
		for s in specs:
			InputMap.action_add_event(action, _make_event(s))
	bindings_changed.emit()


func rebind(action: String, keycode: int) -> void:
	if not action in REBINDABLE:
		return
	# Swap with any action that already uses this key as its primary binding.
	for other in REBINDABLE:
		if other != action and primary_keycode(other) == keycode:
			custom[other] = primary_keycode(action)
	custom[action] = keycode
	_apply()
	_save()


func reset_defaults() -> void:
	custom.clear()
	_apply()
	_save()


func primary_keycode(action: String) -> int:
	if custom.has(action):
		return int(custom[action])
	var first: Variant = ACTIONS[action][1][0]
	return int(first) if typeof(first) == TYPE_INT else -1


func binding_text(action: String) -> String:
	if not ACTIONS.has(action):
		return "?"
	var spec: Variant = ACTIONS[action][1][0]
	if custom.has(action):
		spec = custom[action]
	if typeof(spec) == TYPE_STRING:
		match int(String(spec).substr(6)):
			MOUSE_BUTTON_LEFT: return "LMB"
			MOUSE_BUTTON_RIGHT: return "RMB"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		return "Mouse"
	return OS.get_keycode_string(int(spec))


func display_name(action: String) -> String:
	return ACTIONS.get(action, [action])[0]


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for action in REBINDABLE:
		if cfg.has_section_key("keys", action):
			custom[action] = int(cfg.get_value("keys", action))


func _save() -> void:
	var cfg := ConfigFile.new()
	for action in custom.keys():
		cfg.set_value("keys", action, custom[action])
	cfg.save(PATH)
