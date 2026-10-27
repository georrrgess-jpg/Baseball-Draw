extends Node3D
## Renders a picture of every arena for the Play and Progression screens.
## Run: xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 res://tools/art/arena_thumbs.tscn
## Writes assets/textures/arenas/<id>.jpg (640x360). Optional user arg: -- --only=<arena_id>

const OUT := "res://assets/textures/arenas/"
const SIZE := Vector2i(640, 360)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.split("=")[1]
	for id in DB.arena_order:
		if only != "" and id != only:
			continue
		await _render(id)
	get_tree().quit(0)


func _render(id: String) -> void:
	var world := Node3D.new()
	add_child(world)
	var arena := DB.arena(id)
	var layout := DB.layout_for_arena(id)
	var stadium := StadiumBuilder.new()
	stadium.build(world, arena, layout, false)
	var routes: Array = []
	for r in layout.get("routes", []):
		routes.append(Route.from_points(r.id, r.gate, r.points))
	FieldBuilder.build(world, arena.get("theme", {}), routes)
	stadium.set_excitement(0.6)
	# A few defenders in the field so the picture reads as a ballpark in play.
	var colors: Dictionary = DB.uniforms.get("home", {}).get("colors", {})
	var spots := {"ace": Field.MOUND, "rico": Field.HOME + Vector3(0, 0, 1.2), "maya": Vector3(-4.5, 0, -6.5), "jax": Field.FIRST + Vector3(-1, 0, -1)}
	for did in spots.keys():
		if DB.defender(did).is_empty():
			continue
		var cm := CharacterModel.new()
		world.add_child(cm)
		cm.setup(did, {"accent": DB.defender_accent(did), "colors": colors, "cache_key": did, "base": "ready"})
		cm.position = spots[did]
		cm.rotation.y = PI
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.far = 800.0
	world.add_child(cam)
	cam.position = Field.HOME + Vector3(13.0, 13.0, 24.0)
	cam.look_at(Field.MOUND + Vector3(-3.0, 3.5, -16.0), Vector3.UP)
	cam.make_current()
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while frames < 40 or Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
		frames += 1
	var img := get_viewport().get_texture().get_image()
	var vs := img.get_size()
	# Crop to 16:9 and scale.
	var w := mini(vs.x, int(vs.y * 16.0 / 9.0))
	var h := int(w * 9.0 / 16.0)
	img = img.get_region(Rect2i((vs.x - w) / 2, (vs.y - h) / 2, w, h))
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	img.save_jpg(ProjectSettings.globalize_path(OUT + id + ".jpg"), 0.88)
	print("[THUMB] ", id)
	world.queue_free()
	await get_tree().process_frame
