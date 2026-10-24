class_name CameraRig
extends Node3D
## Elevated tactical camera: WASD pan, wheel zoom, R rotate (90° steps),
## C to recentre, M for a top-down tactical map, plus screen shake and
## scripted cinematic moves (boss intros, victory orbit).

var camera: Camera3D
var focus := Vector3(0, 0, -4)
var yaw := 0.0
var pitch := -52.0
var distance := 40.0
var tactical := false
var cinematic := false

var _t_focus := focus
var _t_yaw := yaw
var _t_pitch := pitch
var _t_distance := distance
var _shake := 0.0
var _shake_t := 0.0
var _orbit_speed := 0.0

const MIN_DIST := 14.0
const MAX_DIST := 62.0
const BOUNDS := Rect2(-30, -32, 60, 50)


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 46.0
	camera.near = 0.3
	camera.far = 600.0
	add_child(camera)
	_apply(true)


func set_view(p_focus: Vector3, p_yaw: float, p_pitch: float, p_distance: float, instant := false) -> void:
	_t_focus = p_focus
	_t_yaw = p_yaw
	_t_pitch = p_pitch
	_t_distance = p_distance
	if instant:
		focus = _t_focus
		yaw = _t_yaw
		pitch = _t_pitch
		distance = _t_distance
		_apply(true)


func default_view(instant := false) -> void:
	tactical = false
	set_view(Vector3(0, 0, 1.2), _t_yaw, -57.0, 44.0, instant)


func toggle_tactical() -> void:
	tactical = not tactical
	if tactical:
		set_view(Vector3(0, 0, -6), _t_yaw, -84.0, 66.0)
	else:
		default_view()


func rotate_step(dir := 1) -> void:
	_t_yaw += 90.0 * dir


func center() -> void:
	_t_focus = Vector3(0, 0, 1.2)


func shake(amount: float) -> void:
	amount *= Settings.shake_scale()
	_shake = maxf(_shake, amount)


func orbit(speed_deg: float) -> void:
	_orbit_speed = speed_deg


func handle_input(delta: float) -> void:
	if cinematic:
		return
	var pan := Vector2.ZERO
	if Input.is_action_pressed("pan_up"):
		pan.y -= 1
	if Input.is_action_pressed("pan_down"):
		pan.y += 1
	if Input.is_action_pressed("pan_left"):
		pan.x -= 1
	if Input.is_action_pressed("pan_right"):
		pan.x += 1
	if bool(Settings.get_value("gameplay", "edge_pan", false)):
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x < 6: pan.x -= 1
		if mp.x > vs.x - 6: pan.x += 1
		if mp.y < 6: pan.y -= 1
		if mp.y > vs.y - 6: pan.y += 1
	if pan != Vector2.ZERO:
		var speed := 22.0 * float(Settings.get_value("gameplay", "camera_speed", 1.0)) * (_t_distance / 40.0)
		var r := deg_to_rad(_t_yaw)
		var fwd := Vector3(-sin(r), 0, -cos(r))
		var right := Vector3(cos(r), 0, -sin(r))
		# Engine.time_scale speeds up delta during fast-forward; keep panning speed constant.
		var real_delta := delta / maxf(Engine.time_scale, 0.01)
		_t_focus += (right * pan.x - fwd * pan.y) * speed * real_delta
		_t_focus.x = clampf(_t_focus.x, BOUNDS.position.x, BOUNDS.end.x)
		_t_focus.z = clampf(_t_focus.z, BOUNDS.position.y, BOUNDS.end.y)


func zoom(step: float) -> void:
	_t_distance = clampf(_t_distance * (1.0 + step), MIN_DIST, MAX_DIST)
	# Lower the camera angle a little when zoomed in for a more cinematic view.
	if not tactical:
		_t_pitch = lerpf(-40.0, -60.0, inverse_lerp(MIN_DIST, MAX_DIST, _t_distance))


func _process(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	if get_tree().paused:
		real_delta = get_process_delta_time()
	if _orbit_speed != 0.0:
		_t_yaw += _orbit_speed * real_delta
	var k := clampf(real_delta * 6.0, 0.0, 1.0)
	focus = focus.lerp(_t_focus, k)
	yaw = lerpf(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	distance = lerpf(distance, _t_distance, k)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - real_delta * 1.8)
		_shake_t += real_delta * 40.0
	_apply(false)


func _apply(_instant: bool) -> void:
	if camera == null:
		return
	var r := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var offset := Vector3(sin(r) * cos(p), -sin(p), cos(r) * cos(p)) * distance
	var pos := focus + offset
	if _shake > 0.0:
		pos += Vector3(sin(_shake_t * 1.3), sin(_shake_t * 1.7), cos(_shake_t * 1.1)) * _shake * 0.35
	camera.global_position = pos
	camera.look_at(focus + Vector3(0, 1.0, 0), Vector3.UP)


## Ray from the camera through a screen point, intersected with the field plane (y = height).
func ground_point(screen_pos: Vector2, height := 0.0) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return null
	var t := (height - origin.y) / dir.y
	if t < 0.0:
		return null
	return origin + dir * t
