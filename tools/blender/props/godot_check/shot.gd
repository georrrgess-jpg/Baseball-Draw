extends SceneTree
# Usage: godot --path <proj> --rendering-driver vulkan --script shot.gd -- mode=props|scene out=DIR [only=a,b] [open=1]
#        [layout=stadium|walltest|dugout] [cx= cy= cz= tx= ty= tz= fov= suny= sunp= fog= inspect=1]
var args := {}
var world: Node3D

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	_run()

func _env(fog := 0.0, inspect := false) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.13, 0.16, 0.32)
	psm.sky_horizon_color = Color(0.98, 0.55, 0.32)
	psm.sky_curve = 0.12
	psm.ground_bottom_color = Color(0.08, 0.07, 0.08)
	psm.ground_horizon_color = Color(0.55, 0.33, 0.25)
	psm.sun_angle_max = 30.0
	if inspect:
		psm.sky_top_color = Color(0.22, 0.32, 0.55)
		psm.sky_horizon_color = Color(0.85, 0.7, 0.6)
		psm.ground_horizon_color = Color(0.45, 0.4, 0.36)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	if fog > 0.0:
		env.fog_enabled = true
		env.fog_light_color = Color(0.85, 0.55, 0.42)
		env.fog_density = fog
		env.fog_sky_affect = 0.0
		env.fog_aerial_perspective = 0.5
	we.environment = env
	return we

func _sun(inspect := false) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 300.0
	if inspect:
		sun.light_color = Color(1.0, 0.86, 0.72)
		sun.light_energy = 1.8
		sun.rotation_degrees = Vector3(-38, -35, 0)
	else:
		sun.light_color = Color(1.0, 0.66, 0.42)
		sun.light_energy = 1.9
		sun.rotation_degrees = Vector3(float(args.get("sunp", "-14")), float(args.get("suny", "-60")), 0)
	return sun

func _ground(size: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	pm.material = m
	mi.mesh = pm
	return mi

func place(n: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var ps: PackedScene = load("res://assets/models/props/" + n + ".glb")
	var inst: Node3D = ps.instantiate()
	inst.position = pos
	inst.rotation_degrees.y = rot_y
	world.add_child(inst)
	return inst

func _aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_aabb(c, t, acc)

func _snap(path: String) -> void:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("saved ", path)

func _new_world(fog := 0.0, inspect := false) -> void:
	if world:
		world.queue_free()
		await process_frame
	world = Node3D.new()
	root.add_child(world)
	world.add_child(_env(fog, inspect))
	world.add_child(_sun(inspect))

func _run() -> void:
	var mode: String = args.get("mode", "props")
	var out: String = args.get("out", "/tmp")
	root.size = Vector2i(int(args.get("w", "960")), int(args.get("h", "540")))
	if mode == "props":
		var dir := DirAccess.open("res://assets/models/props")
		var files := []
		for f in dir.get_files():
			if f.ends_with(".glb"):
				files.append(f.get_basename())
		files.sort()
		var only: String = args.get("only", "")
		for n in files:
			if only != "" and not (n in only.split(",")):
				continue
			await _new_world(0.0, true)
			var g := _ground(400.0, Color(0.23, 0.30, 0.17))
			world.add_child(g)
			var inst := place(n, Vector3.ZERO)
			if n == "gate" and args.get("open", "0") == "1":
				inst.get_node("DoorL").rotation.y = -deg_to_rad(100)
				inst.get_node("DoorR").rotation.y = deg_to_rad(100)
			var acc := [null]
			_aabb(inst, Transform3D.IDENTITY, acc)
			var a: AABB = acc[0]
			var c := a.get_center()
			var r := a.size.length() * 0.5
			var cam := Camera3D.new()
			cam.fov = 40.0
			cam.near = 0.01
			cam.far = 2000.0
			var yaw := deg_to_rad(float(args.get("yaw", "30")))
			var pitch := deg_to_rad(float(args.get("pitch", "18")))
			var d := r / tan(deg_to_rad(cam.fov * 0.5)) * 1.05
			var dirv := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
			world.add_child(cam)
			if args.has("cx"):
				var cp := Vector3(float(args["cx"]), float(args["cy"]), float(args["cz"]))
				var tp := Vector3(float(args["tx"]), float(args["ty"]), float(args["tz"]))
				cam.look_at_from_position(cp, tp, Vector3.UP)
			else:
				cam.look_at_from_position(c + dirv * d, c, Vector3.UP)
			cam.current = true
			await _snap(out + "/" + n + ".png")
	elif mode == "scene":
		await _new_world(float(args.get("fog", "0.0012")), args.get("inspect", "0") == "1")
		var layout: String = args.get("layout", "stadium")
		if layout == "stadium":
			build_scene()
		elif layout == "walltest":
			_plane(Vector3(0, 0, 0), Vector2(200, 200), Color(0.22, 0.26, 0.15))
			for i in range(3):
				place("wall_segment", Vector3(-6 + i * 6.0, 0, 0))
			place("wall_post", Vector3(9, 0, 0))
			place("wall_segment", Vector3(9, 0, 3), -90)
		elif layout == "dugout":
			var gcol := Color(0.22, 0.26, 0.15)
			_plane(Vector3(0, 0, -40), Vector2(100, 77.6), gcol)
			_plane(Vector3(0, 0, 41.3), Vector2(100, 80), gcol)
			_plane(Vector3(-27.6, 0, 0), Vector2(45, 3), gcol)
			_plane(Vector3(27.6, 0, 0), Vector2(45, 3), gcol)
			place("dugout", Vector3(0, 0, 0))
			place("ball_bucket", Vector3(3, 0, 3))
			place("bat_rack", Vector3(5.8, 0, 2.5), -30)
		var cam := Camera3D.new()
		cam.fov = float(args.get("fov", "55"))
		cam.far = 3000.0
		world.add_child(cam)
		var cp := Vector3(float(args.get("cx", "6")), float(args.get("cy", "14")), float(args.get("cz", "62")))
		var tp := Vector3(float(args.get("tx", "0")), float(args.get("ty", "6")), float(args.get("tz", "0")))
		cam.look_at_from_position(cp, tp, Vector3.UP)
		cam.current = true
		await _snap(out + "/" + args.get("name", "scene") + ".png")
	quit()

func _plane(c: Vector3, size: Vector2, col: Color, rough := 0.95) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	pm.material = m
	mi.mesh = pm
	mi.position = c
	world.add_child(mi)

func build_scene() -> void:
	# ground with a cut-out for the sunken dugout at (-34, 0, 30) rotated 90
	var gcol := Color(0.22, 0.26, 0.15)
	var hx0 := -35.7; var hx1 := -32.7; var hz0 := 24.9; var hz1 := 35.1
	_plane(Vector3((-1500 + hx0) / 2, 0, 0), Vector2(1500 + hx0, 3000), gcol)
	_plane(Vector3((hx1 + 1500) / 2, 0, 0), Vector2(1500 - hx1, 3000), gcol)
	_plane(Vector3((hx0 + hx1) / 2, 0, (-1500 + hz0) / 2), Vector2(hx1 - hx0, 1500 + hz0), gcol)
	_plane(Vector3((hx0 + hx1) / 2, 0, (hz1 + 1500) / 2), Vector2(hx1 - hx0, 1500 - hz1), gcol)
	# warning track + outfield grass
	_plane(Vector3(0, 0.01, 3.0), Vector2(82, 5), Color(0.47, 0.31, 0.2), 1.0)
	_plane(Vector3(0, 0.012, 45.5), Vector2(64, 80), Color(0.16, 0.36, 0.12))
	_plane(Vector3(0, 0.014, 60), Vector2(26, 26), Color(0.5, 0.33, 0.22), 1.0)
	# outfield wall line along X at z=0 (field toward +Z)
	place("gate", Vector3(0, 0, 0.0))
	for i in range(6):
		var x := 7.0 + i * 6.0
		place("wall_segment", Vector3(x, 0, 0))
		place("wall_segment", Vector3(-x, 0, 0))
	for i in range(6):
		var x := 4.0 + i * 6.0
		place("wall_post", Vector3(x, 0, 0))
		place("wall_post", Vector3(-x, 0, 0))
	place("fortress_tower", Vector3(-42.5, 0, 0.5), 45)
	place("fortress_tower", Vector3(42.5, 0, 0.5), -45)
	place("light_tower", Vector3(-24, 0, -10))
	place("light_tower", Vector3(24, 0, -10))
	place("scoreboard", Vector3(11, 0, -17), -6)
	place("banner_pole", Vector3(-6.2, 0, 1.6))
	place("banner_pole", Vector3(6.2, 0, 1.6))
	place("banner_pole", Vector3(-19.0, 0, 1.6))
	place("banner_pole", Vector3(19.0, 0, 1.6))
	for i in range(3):
		place("grandstand", Vector3(-45.5, 0, 18 + i * 12.0), 90)
	place("dugout", Vector3(-34.2, 0, 30), 90)
	# background industry
	place("smokestack", Vector3(-62, 0, -95))
	place("smokestack", Vector3(-54, 0, -112))
	place("crane", Vector3(48, 0, -115), 200)
	place("warehouse", Vector3(-18, 0, -78))
	place("warehouse", Vector3(26, 0, -70), 8)
	place("water_tower", Vector3(78, 0, -60))
	place("building_a", Vector3(-140, 0, -280))
	place("building_b", Vector3(-55, 0, -320), 10)
	place("building_c", Vector3(70, 0, -300), -5)
	place("building_a", Vector3(150, 0, -330), 30)
	place("building_c", Vector3(-210, 0, -340))
	place("building_b", Vector3(10, 0, -420))
	var cpos := [Vector3(8, 0, -38), Vector3(8, 2.59, -38), Vector3(15, 0, -36), Vector3(-30, 0, -40), Vector3(-36.5, 0, -40)]
	var crot := [20.0, 24.0, 95.0, 0.0, 0.0]
	for k in range(cpos.size()):
		var c := place("container", cpos[k], crot[k])
		var mi: MeshInstance3D = c.get_node("Container")
		var tint: Color = [Color(0.85, 0.25, 0.2), Color(0.25, 0.45, 0.75), Color(0.95, 0.65, 0.2), Color(0.3, 0.55, 0.35), Color(0.8, 0.8, 0.8)][k]
		for si in mi.mesh.get_surface_count():
			var mat = mi.mesh.surface_get_material(si)
			if mat and mat.resource_name == "Container":
				var dup: StandardMaterial3D = mat.duplicate()
				dup.albedo_color = tint
				mi.set_surface_override_material(si, dup)
	# field-side props near the wall
	place("barricade", Vector3(-10, 0, 7), 8)
	place("barricade", Vector3(-12.2, 0, 7.5), 18)
	place("sandbags", Vector3(10.5, 0, 6.5), -12)
	place("sandbags", Vector3(12.8, 0, 5.8), -40)
	place("crate", Vector3(15.5, 0, 3.6), 18)
	place("crate", Vector3(16.6, 0, 4.9), -8)
	place("crate", Vector3(15.9, 1.2, 4.2), 40)
	place("barrel", Vector3(14.2, 0, 4.4))
	place("barrel", Vector3(13.6, 0, 3.6), 40)
	place("speaker_stack", Vector3(-15.5, 0, 3.8), 25)
	place("floodlight_small", Vector3(-3.6, 0, 7.0), -20)
	place("floodlight_small", Vector3(3.6, 0, 7.0), 20)
	place("fence_chain", Vector3(-30.5, 0, 9.0), 90)
	place("fence_chain", Vector3(-30.5, 0, 13.0), 90)
	place("fence_chain", Vector3(-30.5, 0, 17.0), 90)
	place("ball_bucket", Vector3(-31.6, 0, 22.0))
	place("bat_rack", Vector3(-31.4, 0, 24.0), 90)
