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
# Jumbotron moment: a live camera feed (or null for the animated graphic) with a caption.
var feed: Texture2D
var feed_caption := ""
var feed_sub := ""
var _feed_t := 0.0
var _feed_total := 0.0


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


## Shows a big moment for `time` seconds: `tex` is a live camera feed (null = animated graphic).
func show_feed(tex: Texture2D, caption: String, sub: String, time: float) -> void:
	feed = tex
	feed_caption = caption
	feed_sub = sub
	_feed_t = time
	_feed_total = time
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _feed_t > 0.0:
		_feed_t -= delta
		if _feed_t <= 0.0:
			feed = null
		queue_redraw()
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
	if _feed_t > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_moment(display, header)
		return
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


## Jumbotron moment: live feed with a broadcast-style caption bar, or an animated graphic.
func _draw_moment(display: Font, header: Font) -> void:
	var w := size.x
	var h := size.y
	var age := _feed_total - _feed_t
	var appear := clampf(age / 0.25, 0.0, 1.0)
	var fade := clampf(_feed_t / 0.3, 0.0, 1.0)
	if feed:
		draw_texture_rect(feed, Rect2(Vector2.ZERO, size), false)
		# Scanlines keep the LED look.
		for y in range(0, int(h), 4):
			draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.18), 1.0)
		# LIVE tag.
		var blink := 0.6 + 0.4 * sin(_t * 6.0)
		draw_rect(Rect2(24, 22, 150, 52), Color(0.05, 0.05, 0.08, 0.75))
		draw_circle(Vector2(52, 48), 12, Color(1.0, 0.15, 0.15, blink))
		draw_string(header, Vector2(74, 62), "LIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 38, Color(1, 1, 1))
	else:
		# Animated graphic: rotating rays, a spinning baseball and the caption.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.06, 0.16))
		var c := Vector2(w * 0.5, h * 0.42)
		for i in 16:
			var a := _t * 0.6 + TAU * i / 16.0
			var col := Color(0.88, 0.15, 0.18, 0.55) if i % 2 == 0 else Color(1.0, 0.75, 0.25, 0.35)
			var pts := PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * w, c + Vector2(cos(a + 0.2), sin(a + 0.2)) * w])
			draw_colored_polygon(pts, col)
		var r := 70.0 * (0.8 + 0.2 * appear) + 6.0 * sin(_t * 8.0)
		draw_circle(c, r, Color(0.97, 0.96, 0.92))
		# Two curved seams with stitches, rocking slightly.
		var rock := sin(_t * 3.0) * 0.12
		for side in [-1.0, 1.0]:
			var sc := c + Vector2(side * r * 1.3, 0).rotated(rock)
			var base := (PI if side > 0.0 else 0.0) + rock
			draw_arc(sc, r * 0.82, base - 0.75, base + 0.75, 16, Color(0.85, 0.1, 0.12), 3.0)
			for i in 7:
				var a := base + lerpf(-0.65, 0.65, i / 6.0)
				var p := sc + Vector2(cos(a), sin(a)) * r * 0.82
				var tang := Vector2(-sin(a), cos(a)) * 7.0
				var nrm := Vector2(cos(a), sin(a)) * 5.0
				draw_line(p - nrm - tang * 0.4, p + nrm + tang * 0.4, Color(0.85, 0.1, 0.12), 3.0)
		for y in range(0, int(h), 4):
			draw_line(Vector2(0, y), Vector2(w, y), Color(0, 0, 0, 0.3), 1.0)
	# Caption bar slides in from the left.
	var bar_h := 118.0
	var bar_y := h - bar_h - 24.0
	var slide := (1.0 - appear) * -w
	draw_rect(Rect2(slide, bar_y, w, bar_h), Color(0.88, 0.15, 0.18, 0.92 * fade))
	draw_rect(Rect2(slide, bar_y, w, 8), Color(1.0, 0.75, 0.25, fade))
	var cap_size := 84
	var ts := display.get_string_size(feed_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size)
	if ts.x > w - 80.0:
		cap_size = int(cap_size * (w - 80.0) / ts.x)
		ts = display.get_string_size(feed_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cap_size)
	var pulse := 1.0 + 0.04 * sin(_t * 9.0)
	draw_string(display, Vector2(slide + (w - ts.x * pulse) * 0.5, bar_y + bar_h * 0.5 + cap_size * 0.36), feed_caption,
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(cap_size * pulse), Color(1, 0.97, 0.9, fade))
	if feed_sub != "":
		var ss := header.get_string_size(feed_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
		draw_rect(Rect2((w - ss.x) * 0.5 - 18.0, bar_y - 56.0, ss.x + 36.0, 52.0), Color(0.03, 0.05, 0.12, 0.85 * fade))
		draw_string(header, Vector2((w - ss.x) * 0.5, bar_y - 16.0), feed_sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(1.0, 0.8, 0.3, fade))
