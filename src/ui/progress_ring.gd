class_name ProgressRing
extends Container
## A circular progress ring (rank points, account XP). Children are centred inside it.
## `value` is 0..1 and can be tweened.

var value := 0.0:
	set(v):
		value = clampf(v, 0.0, 1.0)
		queue_redraw()
var color := Color("#F5B82E")
var track := Color(1, 1, 1, 0.1)
var thickness := 12.0


func _init(p_color := Color("#F5B82E"), diameter := 240.0, p_thickness := 12.0) -> void:
	color = p_color
	thickness = p_thickness
	custom_minimum_size = Vector2(diameter, diameter)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - thickness * 0.5 - 2.0
	draw_arc(c, r, 0.0, TAU, 96, track, thickness, true)
	if value > 0.0:
		var a0 := -PI * 0.5
		draw_arc(c, r, a0, a0 + TAU * value, maxi(8, int(96 * value)), color, thickness, true)
		# Bright cap at the leading end.
		var a1 := a0 + TAU * value
		draw_circle(c + Vector2(cos(a1), sin(a1)) * r, thickness * 0.62, color.lightened(0.35))


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for ch in get_children():
			if ch is Control and (ch as Control).visible:
				var s := (ch as Control).get_combined_minimum_size()
				fit_child_in_rect(ch, Rect2((size - s) * 0.5, s))
