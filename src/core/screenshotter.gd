class_name Screenshotter
extends Node
## Test helper: `-- --shots=<dir> --shot-times=4,8,15` saves viewport screenshots at the
## given real-time seconds (persisting across scene changes), then quits.

var out_dir := ""
var times: Array[float] = []
var _t := 0.0
var _i := 0
var prefix := "shot"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)


func _process(delta: float) -> void:
	_t += delta / maxf(Engine.time_scale, 0.01)
	if _i < times.size() and _t >= times[_i]:
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_%02d.png" % [out_dir, prefix, _i]
		img.save_png(path)
		print("[SHOT] saved ", path, " size=", img.get_size())
		_i += 1
		if _i >= times.size():
			get_tree().create_timer(0.2, true, false, true).timeout.connect(func() -> void: get_tree().quit(0))
