class_name Minimap
extends Control
## Bottom-left tactical minimap: field, routes, defenders, runners and the camera focus.
## Clicking it moves the camera.

var battle: Battle
const WORLD := Rect2(-40, -32, 80, 50)


func _ready() -> void:
	custom_minimum_size = Vector2(300, 190)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _map(p: Vector3) -> Vector2:
	var u := (p.x - WORLD.position.x) / WORLD.size.x
	var v := (p.z - WORLD.position.y) / WORLD.size.y
	return Vector2(u * size.x, v * size.y)


func _unmap(m: Vector2) -> Vector3:
	return Vector3(WORLD.position.x + m.x / size.x * WORLD.size.x, 0, WORLD.position.y + m.y / size.y * WORLD.size.y)


func _gui_input(event: InputEvent) -> void:
	if battle == null:
		return
	if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or \
			(event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)):
		var p := _unmap(event.position)
		battle.cam._t_focus = Vector3(clampf(p.x, -30, 30), 0, clampf(p.z, -32, 18))
		accept_event()


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.06, 0.1, 0.88))
	if battle == null:
		return
	# Outfield grass fan and infield.
	var fan := PackedVector2Array([_map(Field.HOME)])
	for i in 31:
		fan.append(_map(Field.wall_point(lerpf(-45, 45, i / 30.0))))
	draw_colored_polygon(fan, Color(0.17, 0.36, 0.2, 0.9))
	var infield := PackedVector2Array([_map(Field.HOME), _map(Field.FIRST), _map(Field.SECOND), _map(Field.THIRD)])
	draw_colored_polygon(infield, Color(0.45, 0.3, 0.18, 0.9))
	draw_polyline(fan + PackedVector2Array([_map(Field.HOME)]), Color(1, 1, 1, 0.25), 1.5)
	# Routes
	for r: Route in battle.routes:
		var pts := PackedVector2Array()
		for p in r.raw_points:
			pts.append(_map(p))
		draw_polyline(pts, Color(1.0, 0.5, 0.15, 0.55), 2.0)
	for gid in battle.gate_positions.keys():
		var gp := _map(battle.gate_positions[gid])
		draw_rect(Rect2(gp - Vector2(5, 5), Vector2(10, 10)), Color(1.0, 0.3, 0.2))
	# Home plate shields
	var hp := _map(Field.HOME)
	draw_circle(hp, 4.0, Color.WHITE)
	if battle.run.shields > 0:
		draw_arc(hp, 9.0, 0, TAU, 20, Color(0.4, 0.85, 1.0), 2.0)
	# Defenders
	for df: Defender in battle.defenders:
		var p := _map(df.global_position)
		draw_circle(p, 6.5, Color(0, 0, 0, 0.6))
		draw_circle(p, 5.0, Color(df.data.accent))
		if df == battle.selected:
			draw_arc(p, 9.0, 0, TAU, 16, UITheme.GOLD, 2.0)
		if df.is_stunned():
			draw_arc(p, 8.0, 0, TAU, 12, Color(1, 1, 0.3), 1.5)
	# Enemies
	for e: Enemy in battle.enemies:
		if not e.alive:
			continue
		var p := _map(e.global_position)
		var r := 3.0
		if e.is_boss:
			r = 7.0
		elif e.id in ["captain", "slugger"]:
			r = 4.5
		draw_circle(p, r, Color(1.0, 0.25, 0.2) if e.id != "decoy" else Color(0.7, 0.5, 1.0, 0.6))
	# Camera focus
	var fp := _map(battle.cam.focus)
	draw_arc(fp, 14.0, 0, TAU, 20, Color(1, 1, 1, 0.5), 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)
