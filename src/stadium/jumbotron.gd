class_name StadiumJumbotron
extends Node3D
## Puts big moments on the outfield scoreboard. On Medium and High a second camera renders a small
## live picture of the action (a slow orbit around where the moment happened) into a SubViewport
## that the scoreboard shows with a caption; the viewport only renders while a moment is on screen.
## On Low the scoreboard plays an animated graphic instead, with no extra camera.

const FEED_SIZE := Vector2i(576, 256)

var display: ScoreboardDisplay
var live := true
var _viewport: SubViewport
var _cam: Camera3D
var _target: Variant = null      # Vector3 or Node3D
var _t := 0.0
var _dur := 0.0
var _yaw := 0.0
var _dist := 9.0
var _height := 3.6
var _priority := 0


func setup(p_display: ScoreboardDisplay) -> void:
	display = p_display
	live = int(Settings.get_value("graphics", "preset", 2)) >= 1 and not "--jumbotron-fallback" in OS.get_cmdline_user_args()
	if not live:
		return
	_viewport = SubViewport.new()
	_viewport.name = "JumbotronFeed"
	_viewport.size = FEED_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	_viewport.audio_listener_enable_3d = false
	add_child(_viewport)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.far = 260.0
	_viewport.add_child(_cam)


func active() -> bool:
	return _t < _dur


## Shows a moment for `duration` seconds. A lower `priority` does not interrupt a higher one.
func show_moment(caption: String, sub: String, target: Variant, duration := 4.0, priority := 1, dist := 9.0) -> void:
	if active() and priority < _priority:
		return
	_priority = priority
	_target = target
	_t = 0.0
	_dur = duration
	_dist = dist
	_height = dist * 0.4
	var p := _target_pos()
	# Start from the home-plate side so the viewer sees the play the same way round as the field.
	_yaw = atan2(p.x - 0.0, 18.0 - p.z) * 0.5
	var tex: Texture2D = null
	if live and _viewport:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		tex = _viewport.get_texture()
		_place_camera(0.0)
	if display:
		display.show_feed(tex, caption, sub, duration)


func _target_pos() -> Vector3:
	if _target is Node3D and is_instance_valid(_target):
		return (_target as Node3D).global_position
	if _target is Vector3:
		return _target
	return Vector3(0, 0, -4)


func _place_camera(dt: float) -> void:
	if _cam == null:
		return
	_yaw += dt * 0.22
	var p := _target_pos()
	var off := Vector3(sin(_yaw), 0, cos(_yaw)) * _dist
	_cam.global_position = p + off + Vector3(0, _height, 0)
	_cam.look_at(p + Vector3(0, 1.1, 0), Vector3.UP)


func _process(delta: float) -> void:
	if not active():
		return
	var dt := minf(delta / maxf(Engine.time_scale, 0.05), 0.1)
	_t += dt
	_place_camera(dt)
	if not active():
		_priority = 0
		if _viewport:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
