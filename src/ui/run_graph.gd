class_name RunGraph
extends Control
## Game-flow chart for the Results screen: runs allowed per inning as bars and the average
## energy per inning as a line (0–10). `progress` (0..1) reveals it left to right.

var timeline: Array = []
var progress := 1.0:
	set(v):
		progress = v
		queue_redraw()

const RUNS_COL := Color("#E0262F")
const ENERGY_COL := Color("#3FD0FF")
const GRID_COL := Color(1, 1, 1, 0.08)


func _init(p_timeline: Array = []) -> void:
	timeline = p_timeline
	custom_minimum_size = Vector2(300, 220)
	mouse_filter = Control.MOUSE_FILTER_PASS


func _draw() -> void:
	var font := UITheme.font_body_bold()
	var fs := UITheme.FS_MIN
	var legend_h := 26.0
	var axis_h := 24.0
	var left := 30.0
	var right := 30.0
	var plot := Rect2(left, legend_h + 6.0, size.x - left - right, size.y - legend_h - axis_h - 10.0)
	# Legend.
	draw_rect(Rect2(0, 6, 14, 14), RUNS_COL)
	draw_string(font, Vector2(20, 19), "Runs allowed", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.88, 0.95))
	var lx := 140.0
	draw_line(Vector2(lx, 13), Vector2(lx + 18, 13), ENERGY_COL, 3.0, true)
	draw_circle(Vector2(lx + 9, 13), 4.0, ENERGY_COL)
	draw_string(font, Vector2(lx + 24, 19), "Avg. energy", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.85, 0.88, 0.95))
	if timeline.is_empty():
		draw_string(font, Vector2(0, plot.position.y + plot.size.y * 0.5), "No game-flow data for this run.",
			HORIZONTAL_ALIGNMENT_CENTER, size.x, UITheme.FS_SMALL, UITheme.MUTED)
		return
	# Grid: energy 0, 5, 10 on the right axis.
	for k in 3:
		var y := plot.end.y - plot.size.y * k / 2.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), GRID_COL, 1.0)
		draw_string(font, Vector2(plot.end.x + 4, y + 6), str(k * 5), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(ENERGY_COL, 0.7))
	var n := timeline.size()
	var max_runs := 2
	for e in timeline:
		max_runs = maxi(max_runs, int(e.get("runs", 0)))
	var slot := plot.size.x / n
	var bar_w := minf(slot * 0.5, 46.0)
	var shown := progress * n
	var pts := PackedVector2Array()
	for i in n:
		var e: Dictionary = timeline[i]
		var reveal := clampf(shown - i, 0.0, 1.0)
		var cx := plot.position.x + slot * (i + 0.5)
		# Inning label (thin out when there are many innings).
		var step := maxi(1, int(ceil(n / 12.0)))
		if i % step == 0 or i == n - 1:
			draw_string(font, Vector2(cx - 30, plot.end.y + axis_h - 4), str(int(e.get("inning", i + 1))),
				HORIZONTAL_ALIGNMENT_CENTER, 60, fs, UITheme.MUTED)
		if reveal <= 0.0:
			continue
		var runs := int(e.get("runs", 0))
		if runs > 0:
			var h := plot.size.y * 0.85 * runs / float(max_runs) * reveal
			draw_rect(Rect2(cx - bar_w * 0.5, plot.end.y - h, bar_w, h), RUNS_COL)
			draw_string(font, Vector2(cx - 30, plot.end.y - h - 4), str(runs), HORIZONTAL_ALIGNMENT_CENTER, 60, fs, Color(1, 0.7, 0.68))
		else:
			# A clean inning: a small green tick on the baseline.
			draw_rect(Rect2(cx - bar_w * 0.5, plot.end.y - 3, bar_w, 3), Color(UITheme.GREEN, 0.8 * reveal))
		var en := clampf(float(e.get("energy_avg", 0.0)), 0.0, 10.0)
		if reveal >= 1.0 or i == 0:
			pts.append(Vector2(cx, plot.end.y - plot.size.y * en / 10.0))
	if pts.size() >= 2:
		draw_polyline(pts, ENERGY_COL, 3.0, true)
	for p in pts:
		draw_circle(p, 5.0, ENERGY_COL)
		draw_circle(p, 2.5, Color(0.04, 0.07, 0.12))
	draw_string(font, Vector2(plot.position.x - left, plot.end.y + axis_h - 4), "INN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UITheme.MUTED, 0.7))
