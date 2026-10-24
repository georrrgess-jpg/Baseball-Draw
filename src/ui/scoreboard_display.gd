class_name ScoreboardDisplay
extends Control
## The live stadium scoreboard, rendered into a SubViewport texture.

var inning := 1
var max_innings := 9
var runs := 0
var run_limit := 3
var outs := 0
var wave := 1
var waves := 3
var message := ""
var _msg_t := 0.0
var _t := 0.0


func _ready() -> void:
	set_process(true)


func set_state(p_inning: int, p_max: int, p_runs: int, p_limit: int, p_outs: int, p_wave: int, p_waves: int) -> void:
	inning = p_inning
	max_innings = p_max
	runs = p_runs
	run_limit = p_limit
	outs = p_outs
	wave = p_wave
	waves = p_waves
	queue_redraw()


func flash(text: String, time := 2.5) -> void:
	message = text
	_msg_t = time
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			message = ""
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.06))
	# LED grid texture.
	for y in range(0, int(size.y), 4):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.35), 1.0)
	# Layout is authored for 640x320 and scaled uniformly to the screen.
	var k := minf(size.x / 640.0, size.y / 320.0)
	draw_set_transform(Vector2((size.x - 640.0 * k) * 0.5, (size.y - 320.0 * k) * 0.5), 0.0, Vector2(k, k))
	var w := 640.0
	var h := 320.0
	var display := UITheme.font_display()
	var header := UITheme.font_header()
	if message != "":
		var pulse := 0.75 + 0.25 * sin(_t * 10.0)
		draw_rect(Rect2(0, 0, w, h), Color(0.88, 0.15, 0.18, 0.25 * pulse))
		_draw_centered(display, message, Vector2(w * 0.5, h * 0.58), 84, Color(1.0, 0.85, 0.3) * pulse + Color(0, 0, 0, 1))
		return
	_draw_centered(display, "BASEBALL DRAW", Vector2(w * 0.5, 62), 54, Color(0.96, 0.95, 0.92))
	draw_rect(Rect2(40, 78, w - 80, 4), Color(0.88, 0.15, 0.18))
	var inning_text := "INNING %d" % inning if max_innings <= 0 else "INNING %d / %d" % [inning, max_innings]
	_draw_centered(header, inning_text, Vector2(w * 0.5, 132), 44, Color(1.0, 0.75, 0.25))
	# Runs vs limit
	_draw_centered(header, "RUNS", Vector2(w * 0.22, 190), 34, Color(0.7, 0.8, 0.95))
	_draw_centered(display, "%d" % runs, Vector2(w * 0.22, 268), 88, Color(1.0, 0.35, 0.3) if runs > 0 else Color(0.95, 0.95, 0.95))
	_draw_centered(header, "OUTS", Vector2(w * 0.5, 190), 34, Color(0.7, 0.8, 0.95))
	_draw_centered(display, "%d" % outs, Vector2(w * 0.5, 268), 88, Color(0.4, 1.0, 0.55))
	_draw_centered(header, "WAVE", Vector2(w * 0.78, 190), 34, Color(0.7, 0.8, 0.95))
	_draw_centered(display, "%d/%d" % [wave, waves], Vector2(w * 0.78, 268), 72, Color(0.95, 0.95, 0.95))


func _draw_centered(font: Font, text: String, center: Vector2, fsize: int, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	draw_string(font, center - Vector2(ts.x * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)
