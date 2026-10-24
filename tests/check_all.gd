extends Node
## Loads every script under res://src so parse/compile errors surface with autoloads present.

func _ready() -> void:
	var files: Array[String] = []
	_collect("res://src", files)
	_collect("res://tests", files)
	var bad := 0
	for f in files:
		var s: Script = load(f)
		if s == null or not s.can_instantiate():
			print("FAILED: ", f)
			bad += 1
	print("CHECKED %d scripts, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad > 0 else 0)


func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in d.get_directories():
		_collect(dir + "/" + sub, out)
