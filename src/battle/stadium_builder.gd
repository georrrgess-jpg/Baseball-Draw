class_name StadiumBuilder
extends RefCounted
## Assembles an arena around the field: sky, sun, environment, outfield fortress wall,
## enemy gates, grandstands with an animated crowd, light towers, dugouts, scoreboard,
## banners and a themed background skyline. Uses the generated props in
## assets/models/props when present and simple primitives otherwise.

const PROP_DIR := "res://assets/models/props/"

static var _prop_cache := {}

var root: Node3D
var theme: Dictionary
var layout: Dictionary
var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var gates: Dictionary = {}          # gate id -> Node3D (with doors)
var crowd: StadiumCrowd
var life: StadiumLife
var jumbotron: StadiumJumbotron
var mascot: StadiumMascot
var fireworks: StadiumFireworks
var with_gameplay := true
var scoreboard_viewport: SubViewport
var scoreboard_ui: Control
var rng := RandomNumberGenerator.new()
var _mat_cache := {}
var arena_name := ""


static func prop(name: String) -> Node3D:
	var path := PROP_DIR + name + ".glb"
	var packed: PackedScene = _prop_cache.get(path)
	if packed == null:
		if not ResourceLoader.exists(path):
			return null
		packed = load(path)
		_prop_cache[path] = packed
	return packed.instantiate() as Node3D


func build(parent: Node3D, arena: Dictionary, p_layout: Dictionary, p_with_gameplay := true) -> Node3D:
	theme = arena.get("theme", {})
	arena_name = str(arena.get("name", ""))
	layout = p_layout
	rng.seed = hash(arena.get("id", "x"))
	with_gameplay = p_with_gameplay
	root = Node3D.new()
	root.name = "Stadium"
	parent.add_child(root)
	crowd = StadiumCrowd.new()
	crowd.name = "CrowdLife"
	crowd.setup(theme)
	root.add_child(crowd)
	_build_environment()
	_build_ground()
	_build_outfield_wall()
	_build_side_walls()
	_build_stands()
	_build_light_towers()
	_build_dugouts()
	_build_scoreboard()
	_build_banners()
	_build_background()
	_build_ambient_particles()
	_build_life(parent)
	return root


## Stadium life: crowd reactions, jumbotron moments, the mascot and fireworks (src/stadium/).
func _build_life(parent: Node3D) -> void:
	jumbotron = StadiumJumbotron.new()
	jumbotron.name = "Jumbotron"
	root.add_child(jumbotron)
	jumbotron.setup(scoreboard_ui as ScoreboardDisplay)
	fireworks = StadiumFireworks.new()
	fireworks.name = "Fireworks"
	root.add_child(fireworks)
	if with_gameplay:
		var u := _home_uniform()
		mascot = StadiumMascot.new()
		mascot.name = "Mascot"
		mascot.build(u.team, u.trim, Color(0.95, 0.94, 0.9))
		root.add_child(mascot)
		mascot.home = _dugout_door
		mascot.spot = Vector3(-9.4, 0, 6.2)
	life = StadiumLife.new()
	life.name = "StadiumLife"
	root.add_child(life)
	life.setup(crowd, jumbotron, mascot, fireworks)
	if with_gameplay and parent.has_signal("state_changed"):
		life.attach_battle(parent)


func _c(key: String, fallback := "#ffffff") -> Color:
	return Color(theme.get(key, fallback))


func _mat(color: Color, rough := 0.7, metal := 0.0, emission := Color.BLACK, emission_energy := 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%s|%.2f" % [color.to_html(), rough, metal, emission.to_html(), emission_energy]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	_mat_cache[key] = m
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = null, rot_y := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.y = rot_y
	(parent if parent else root).add_child(mi)
	return mi


## Places a node at pos, rotated so its +Z faces `look_at_point` (on the XZ plane).
func _face(n: Node3D, pos: Vector3, look_at_point: Vector3) -> void:
	n.position = pos
	var to := look_at_point - pos
	n.rotation.y = atan2(to.x, to.z)


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/shaders/sky.gdshader")
	sm.set_shader_parameter("top_color", _c("sky_top"))
	sm.set_shader_parameter("horizon_color", _c("sky_horizon"))
	sm.set_shader_parameter("ground_color", _c("ground_horizon"))
	sm.set_shader_parameter("sun_tint", _c("sun_color"))
	var time: String = theme.get("time", "sunset")
	sm.set_shader_parameter("stars", 1.0 if time == "night" else (0.4 if time == "twilight" else 0.0))
	sm.set_shader_parameter("cloud_amount", 0.7 if time == "storm" else (0.35 if time == "night" else 0.55))
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _c("ambient")
	env.ambient_light_energy = float(theme.get("ambient_energy", 0.6))
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.35
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.8)
	env.set_glow_level(2, 0.6)
	env.set_glow_level(3, 0.25)
	env.set_glow_level(4, 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = _c("fog")
	env.fog_density = float(theme.get("fog_density", 0.003)) * 0.4
	env.fog_sun_scatter = 0.35
	env.fog_aerial_perspective = 0.1
	env.fog_sky_affect = 0.15
	env.volumetric_fog_density = 0.0016
	env.volumetric_fog_albedo = _c("fog").lightened(0.3)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 90.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.12
	if theme.get("time", "") == "dusk_snow":
		# Snow arenas washed out to grey from the battle camera: thinner haze, a little more contrast.
		env.fog_density *= 0.5
		env.volumetric_fog_density *= 0.5
		env.adjustment_contrast = 1.16
		env.adjustment_saturation = 1.2
	Settings.configure_environment(env)
	world_env.environment = env
	root.add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.light_color = _c("sun_color")
	sun.light_energy = float(theme.get("sun_energy", 1.5))
	sun.rotation_degrees = Vector3(float(theme.get("sun_pitch", -18)), float(theme.get("sun_yaw", 200)), 0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.8
	Settings.configure_sun(sun)
	root.add_child(sun)
	# A cool fill light from the opposite side keeps shadowed faces readable.
	var fill := DirectionalLight3D.new()
	fill.light_color = _c("ambient").lightened(0.2)
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-50, float(theme.get("sun_yaw", 200)) + 160.0, 0)
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	root.add_child(fill)


func _build_ground() -> void:
	# Concrete/asphalt surroundings beyond the field.
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(900, 900)
	mi.mesh = pm
	mi.position = Vector3(0, -0.06, 0)
	var m := _mat(_c("steel", "#3a4048").darkened(0.45), 0.95)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


# ---------------------------------------------------------------- walls & gates

func _gate_angles() -> Array:
	var out := []
	for gid in layout.get("gates", {}).keys():
		var g: Array = layout.gates[gid]
		var p := Vector3(float(g[0]), 0, float(g[1]))
		out.append({"id": gid, "pos": p, "angle": Field.angle_from_center(p)})
	return out


func _build_outfield_wall() -> void:
	var gate_list := _gate_angles()
	var wall_col := _c("wall")
	var r := Field.WALL_RADIUS
	var span := 45.0
	var seg_len := 6.0
	var step_deg := rad_to_deg(seg_len / r)
	var a := -span
	var ads := SurfaceTool.new()
	ads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ad_i := rng.randi() % 8
	while a < span - 0.01:
		var mid := a + step_deg * 0.5
		var pos := Field.wall_point(mid, r)
		var skip := false
		for g in gate_list:
			if Field.v2(g.pos).distance_to(Field.v2(pos)) < 5.2:
				skip = true
		if not skip:
			var seg := prop("wall_segment")
			if seg == null:
				seg = _fallback_wall(seg_len, wall_col)
			root.add_child(seg)
			_face(seg, pos, Field.HOME)
			_add_ad_board(ads, seg.transform, ad_i % 8)
			ad_i += 1
		a += step_deg
	_finish_ad_boards(ads)
	_build_foul_poles(gate_list)
	# Pillars at regular intervals hide the joins between straight segments.
	var b := -span
	while b <= span + 0.01:
		var pp := Field.wall_point(b, r)
		var near_gate := false
		for g in gate_list:
			if Field.v2(g.pos).distance_to(Field.v2(pp)) < 4.6:
				near_gate = true
		if not near_gate:
			var post := prop("wall_post")
			if post == null:
				post = Node3D.new()
				_box(Vector3(0.9, 4.8, 0.9), Vector3(0, 2.4, 0), _mat(_c("steel"), 0.5, 0.6), post)
				_box(Vector3(1.1, 0.25, 1.1), Vector3(0, 4.9, 0), _mat(_c("trim"), 0.5, 0.2), post)
			root.add_child(post)
			_face(post, pp, Field.HOME)
		b += step_deg
	# Gates
	var letters := ["a", "b", "c", "d"]
	var li := 0
	for g in gate_list:
		var gate := prop("gate_" + letters[li % 4])
		li += 1
		if gate == null:
			gate = prop("gate")
		if gate == null:
			gate = _fallback_gate()
		root.add_child(gate)
		var gp: Vector3 = g.pos
		# Push corner gates slightly outward so they sit in the wall line.
		_face(gate, gp + (gp - Field.HOME).normalized() * 0.4, Field.HOME)
		gates[g.id] = gate
		# Warning light for the gate.
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.25, 0.1)
		light.light_energy = 0.0
		light.omni_range = 9.0
		light.position = Vector3(0, 6.5, 1.5)
		light.shadow_enabled = false
		gate.add_child(light)
		gate.set_meta("light", light)


## An advertising board (fictional brands, tools/art/stadium_signs.py) on the field side of a wall segment.
func _add_ad_board(st: SurfaceTool, xf: Transform3D, idx: int) -> void:
	var u0 := float(idx % 2) * 0.5
	var v0 := float(idx / 2) * 0.25
	var hw := 2.55
	var y0 := 2.55
	var y1 := y0 + hw * 2.0 / 4.0
	var z := 0.64
	var corners := [Vector3(-hw, y0, z), Vector3(hw, y0, z), Vector3(hw, y1, z), Vector3(-hw, y1, z)]
	var uvs := [Vector2(u0, v0 + 0.25), Vector2(u0 + 0.5, v0 + 0.25), Vector2(u0 + 0.5, v0), Vector2(u0, v0)]
	var n := (xf.basis * Vector3(0, 0, 1)).normalized()
	for k in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n)
		st.set_uv(uvs[k])
		st.add_vertex(xf * corners[k])


func _finish_ad_boards(st: SurfaceTool) -> void:
	var path := "res://assets/textures/stadium/ad_boards.png"
	if not ResourceLoader.exists(path):
		return
	var mi := MeshInstance3D.new()
	mi.name = "AdBoards"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(path)
	m.roughness = 0.55
	# Boards are lit from behind at night so they read against the dark wall.
	var night: bool = theme.get("time", "") in ["night", "storm", "twilight", "dusk_snow"]
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = 0.55 if night else 0.12
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Yellow foul poles where the foul lines meet the wall (skipped where a gate stands).
func _build_foul_poles(gate_list: Array) -> void:
	for side in [-1.0, 1.0]:
		var p := Field.wall_point(45.0 * side, Field.WALL_RADIUS + 0.9)
		var blocked := false
		for g in gate_list:
			if Field.v2(g.pos).distance_to(Field.v2(p)) < 7.0:
				blocked = true
		if blocked:
			continue
		var k := MeshKit.new()
		k.color = Color(1.0, 0.82, 0.12)
		k.cyl(Vector3.ZERO, Vector3(0, 15.0, 0), 0.2, 8)
		# Screen fin on the fair side.
		k.box_mm(Vector3(-0.03, 5.2, -0.05), Vector3(0.03, 14.6, 0.75))
		k.color = Color(0.25, 0.25, 0.28)
		k.cyl(Vector3.ZERO, Vector3(0, 0.6, 0), 0.32, 8)
		var mi := MeshInstance3D.new()
		mi.name = "FoulPole"
		mi.mesh = k.commit()
		mi.material_override = StadiumDugout.vc_material()
		root.add_child(mi)
		mi.position = p
		# Fin points toward centre field.
		var to := Field.wall_point(0.0) - p
		mi.rotation.y = atan2(to.x, to.z)


func _fallback_wall(length: float, col: Color) -> Node3D:
	var n := Node3D.new()
	_box(Vector3(length + 0.05, 3.6, 0.8), Vector3(0, 1.8, -0.4), _mat(col, 0.85), n)
	_box(Vector3(length + 0.05, 0.3, 1.0), Vector3(0, 3.75, -0.4), _mat(_c("trim"), 0.6, 0.3), n)
	_box(Vector3(length + 0.05, 2.2, 0.1), Vector3(0, 1.3, 0.02), _mat(col.darkened(0.2), 0.95), n)
	return n


func _fallback_gate() -> Node3D:
	var n := Node3D.new()
	var steel := _mat(_c("steel"), 0.45, 0.7)
	_box(Vector3(1.2, 6.5, 1.4), Vector3(-4.4, 3.25, -0.4), steel, n)
	_box(Vector3(1.2, 6.5, 1.4), Vector3(4.4, 3.25, -0.4), steel, n)
	_box(Vector3(10.0, 1.2, 1.6), Vector3(0, 6.6, -0.4), steel, n)
	var l := Node3D.new()
	l.name = "DoorL"
	l.position = Vector3(-3.8, 0, -0.3)
	n.add_child(l)
	_box(Vector3(3.8, 5.6, 0.3), Vector3(1.9, 2.8, 0), _mat(_c("wall").darkened(0.2), 0.6, 0.5), l)
	var r := Node3D.new()
	r.name = "DoorR"
	r.position = Vector3(3.8, 0, -0.3)
	n.add_child(r)
	_box(Vector3(3.8, 5.6, 0.3), Vector3(-1.9, 2.8, 0), _mat(_c("wall").darkened(0.2), 0.6, 0.5), r)
	var beacon := _box(Vector3(0.6, 0.4, 0.6), Vector3(0, 7.4, -0.4), _mat(Color(1, 0.2, 0.1), 0.4, 0.0, Color(1, 0.2, 0.05), 3.0), n)
	beacon.name = "Beacon"
	return n


## Swings a gate's doors open or closed.
func set_gate_open(gate_id: String, open: bool) -> void:
	var g: Node3D = gates.get(gate_id)
	if g == null:
		return
	var l := g.find_child("DoorL", true, false) as Node3D
	var r := g.find_child("DoorR", true, false) as Node3D
	var tw := g.create_tween()
	tw.set_parallel(true)
	if l:
		tw.tween_property(l, "rotation:y", deg_to_rad(-100.0) if open else 0.0, 0.8).set_trans(Tween.TRANS_CUBIC)
	if r:
		tw.tween_property(r, "rotation:y", deg_to_rad(100.0) if open else 0.0, 0.8).set_trans(Tween.TRANS_CUBIC)
	var light: OmniLight3D = g.get_meta("light", null)
	if light:
		tw.tween_property(light, "light_energy", 3.0 if open else 0.0, 0.4)


func _build_side_walls() -> void:
	# Walls running from the foul poles back past the dugouts, then a backstop behind home.
	var wall_col := _c("wall")
	for side in [-1.0, 1.0]:
		var a := Field.wall_point(45.0 * side, Field.WALL_RADIUS) + Vector3(side * 1.0, 0, 0)
		var b := Vector3(side * 16.5, 0, 12.0)
		var dir := b - a
		var length := dir.length()
		var n := int(ceil(length / 6.0))
		for i in n:
			var p := a + dir * ((i + 0.5) / n)
			var seg := prop("wall_segment")
			if seg == null:
				seg = _fallback_wall(length / n, wall_col)
			root.add_child(seg)
			seg.position = p
			# Face the field (perpendicular to the wall line, toward the inside).
			var normal := Vector3(-dir.z, 0, dir.x).normalized()
			if normal.dot(Vector3(0, 0, 0) - p) < 0:
				normal = -normal
			seg.rotation.y = atan2(normal.x, normal.z)
			seg.scale.x = (length / n) / 6.0
	# Backstop behind home plate.
	for i in 7:
		var ang := lerpf(-60.0, 60.0, i / 6.0)
		var rr := deg_to_rad(ang)
		var p := Field.HOME + Vector3(sin(rr) * 7.5, 0, cos(rr) * 7.5)
		var seg := prop("wall_segment")
		if seg == null:
			seg = _fallback_wall(3.0, wall_col)
		root.add_child(seg)
		_face(seg, p, Field.HOME)
		seg.scale.x = 0.6
	var fence := prop("fence_chain")
	if fence:
		for i in 5:
			var ang := lerpf(-40.0, 40.0, i / 4.0)
			var rr := deg_to_rad(ang)
			var f2 := prop("fence_chain")
			root.add_child(f2)
			_face(f2, Field.HOME + Vector3(sin(rr) * 7.6, 3.8, cos(rr) * 7.6), Field.HOME + Vector3(0, 3.8, 0))
		fence.free()


# ---------------------------------------------------------------- stands & crowd

func _build_stands() -> void:
	# Each entry: [front-centre point, facing direction (toward the field), keep canopy].
	# The grandstand's front edge is at local z = +4.5, so the origin sits 4.5 m behind it.
	var placements: Array = []
	for side in [-1.0, 1.0]:
		var a := Field.wall_point(45.0 * side, Field.WALL_RADIUS) + Vector3(side * 1.0, 0, 0)
		var b := Vector3(side * 16.5, 0, 12.0)
		var dir := (b - a).normalized()
		var outward := Vector3(-dir.z, 0, dir.x)
		if outward.x * side < 0:
			outward = -outward
		for t in [0.22, 0.68]:
			var p := a.lerp(b, t) + outward * 3.2
			placements.append([p, -outward, true])
	for ang in [-62.0, 0.0, 62.0]:
		var rr := deg_to_rad(ang)
		var dir := Vector3(sin(rr), 0, cos(rr))
		placements.append([Field.HOME + dir * 11.5, -dir, false])
	for ang in [-42.0, -15.0, 15.0, 42.0]:
		var blocked := false
		for g in _gate_angles():
			if absf(g.angle - ang) < 11.0:
				blocked = true
		if blocked:
			continue
		var p := Field.wall_point(ang, Field.WALL_RADIUS + 3.4)
		placements.append([p, (Field.HOME - p).normalized(), true])
	var crowd_cols: Array = theme.get("crowd", ["#1c2e4a", "#d7262e", "#f4f1ea"])
	var density := float(Settings.get_value("graphics", "crowd", 1.0))
	for pl in placements:
		var stand := prop("grandstand")
		if stand == null:
			stand = _fallback_stand()
		root.add_child(stand)
		var front: Vector3 = pl[0]
		var f: Vector3 = pl[1]
		f.y = 0
		f = f.normalized()
		stand.position = front - f * 4.5
		stand.rotation.y = atan2(f.x, f.z)
		if not pl[2]:
			var canopy := stand.find_child("Canopy", true, false) as Node3D
			if canopy:
				canopy.visible = false
		crowd.fill_stand(stand, crowd_cols, density, rng)


func _fallback_stand() -> Node3D:
	var n := Node3D.new()
	var conc := _mat(Color(0.42, 0.42, 0.45), 0.9)
	var seat := _mat(_c("wall").lightened(0.1), 0.6)
	for r in 10:
		_box(Vector3(12, 0.45 * r + 1.0, 0.9), Vector3(0, (0.45 * r + 1.0) * 0.5, 4.05 - r * 0.9), conc, n)
		_box(Vector3(11.6, 0.2, 0.4), Vector3(0, 1.0 + r * 0.45 + 0.3, 3.95 - r * 0.9), seat, n)
	return n


func set_excitement(v: float) -> void:
	if crowd:
		crowd.set_excitement(v)


# ---------------------------------------------------------------- lights, dugouts, scoreboard

func _build_light_towers() -> void:
	var spots := [Vector3(-40, 0, -29), Vector3(40, 0, -29), Vector3(-47, 0, 2), Vector3(47, 0, 2), Vector3(-27, 0, 33), Vector3(27, 0, 33)]
	var lamp_energy := float(theme.get("lamp_energy", 2.0))
	var night: bool = theme.get("time", "") in ["night", "storm", "twilight", "dusk_snow"]
	var spot_count := 0
	for p in spots:
		var tower := prop("light_tower")
		if tower == null:
			tower = _fallback_tower()
		root.add_child(tower)
		_face(tower, p, Vector3(0, 0, -4))
		for mi in _all_meshes(tower):
			for s in mi.mesh.get_surface_count():
				var mat := mi.mesh.surface_get_material(s)
				if mat and mat.resource_name == "LampEmissive" and mat is BaseMaterial3D:
					var nm: BaseMaterial3D = mat.duplicate()
					nm.emission_enabled = true
					nm.emission = Color(1.0, 0.95, 0.85)
					nm.emission_energy_multiplier = 2.0 + lamp_energy * 2.0
					mi.set_surface_override_material(s, nm)
		if night:
			_add_lamp_halo(tower, lamp_energy)
		if night and spot_count < 4 and p.z < 20:
			var sl := SpotLight3D.new()
			sl.light_color = Color(1.0, 0.95, 0.85)
			sl.light_energy = lamp_energy * 3.5
			sl.spot_range = 95.0
			sl.spot_angle = 34.0
			sl.spot_attenuation = 0.6
			sl.shadow_enabled = false
			root.add_child(sl)
			sl.position = p + Vector3(0, 22.6, 0)
			sl.look_at_from_position(sl.position, Vector3(p.x * 0.15, 0, p.z * 0.15 - 4.0), Vector3.UP)
			spot_count += 1


static var _halo_tex: GradientTexture2D


## A soft additive glow around a light tower's lamp bank (night arenas).
func _add_lamp_halo(tower: Node3D, lamp_energy: float) -> void:
	if _halo_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.18, 0.5, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 0.95, 0.85, 0.55), Color(1, 0.9, 0.75, 0.12), Color(1, 0.9, 0.75, 0)])
		_halo_tex = GradientTexture2D.new()
		_halo_tex.gradient = g
		_halo_tex.fill = GradientTexture2D.FILL_RADIAL
		_halo_tex.fill_from = Vector2(0.5, 0.5)
		_halo_tex.fill_to = Vector2(1.0, 0.5)
		_halo_tex.width = 64
		_halo_tex.height = 64
	var anchor := tower.find_child("LightAnchor", true, false) as Node3D
	var q := MeshInstance3D.new()
	q.name = "LampHalo"
	var qm := QuadMesh.new()
	qm.size = Vector2(9.0, 7.0)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _halo_tex
	m.albedo_color = Color(1.0, 0.93, 0.8, clampf(0.25 + lamp_energy * 0.06, 0.3, 0.6))
	m.disable_fog = true
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if anchor:
		anchor.add_child(q)
		q.position = Vector3(0, 0.3, 0.6)
	else:
		tower.add_child(q)
		q.position = Vector3(0, 23.0, 0.8)


func _all_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out


func _fallback_tower() -> Node3D:
	var n := Node3D.new()
	_box(Vector3(0.8, 22, 0.8), Vector3(0, 11, 0), _mat(_c("steel"), 0.5, 0.7), n)
	_box(Vector3(5, 3, 0.6), Vector3(0, 23, 0), _mat(_c("steel").darkened(0.3), 0.5, 0.7), n)
	var lamp := _mat(Color(1, 0.97, 0.9), 0.3, 0.0, Color(1, 0.95, 0.8), 3.0 + float(theme.get("lamp_energy", 2.0)) * 2.0)
	for x in 4:
		for y in 3:
			_box(Vector3(0.9, 0.7, 0.2), Vector3(-1.8 + x * 1.2, 22.0 + y * 0.9, 0.35), lamp, n)
	var anchor := Node3D.new()
	anchor.name = "LightAnchor"
	anchor.position = Vector3(0, 23, 0.5)
	n.add_child(anchor)
	return n


var _dugout_door := Vector3(-12.0, 0, 6.0)


## Colours of the player's team uniform (home dugout, mascot).
func _home_uniform() -> Dictionary:
	var u: Dictionary = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.get("home", {})).get("colors", {})
	return {"team": Color(u.get("Jersey", "#1c2e4a")), "trim": Color(u.get("JerseyTrim", "#d7262e")),
		"pants": Color(u.get("Pants", "#edebe6")), "cap": Color(u.get("Cap", "#1c2e4a"))}


func _build_dugouts() -> void:
	var home := _home_uniform()
	var visitor_team := _c("wall").lerp(Color(0.25, 0.25, 0.28), 0.25)
	for side in [-1.0, 1.0]:
		var is_home: bool = side < 0.0
		var colors := {}
		if is_home:
			colors = {"team": home.team, "trim": home.trim, "roof": home.team.darkened(0.1), "jersey": home.team}
		else:
			colors = {"team": visitor_team, "trim": _c("trim"), "roof": visitor_team.darkened(0.1), "jersey": Color(0.62, 0.64, 0.68)}
		var cap: Color = home.cap if is_home else visitor_team
		var pants: Color = home.pants if is_home else Color(0.78, 0.78, 0.8)
		var seated := crowd.make_bench_material(cap, pants, false)
		var standing := crowd.make_bench_material(cap, pants, true)
		# Steps at the end nearest home plate.
		var d := StadiumDugout.build(colors, "DEFENDERS" if is_home else "VISITORS", side > 0.0, rng, seated, standing)
		root.add_child(d)
		var pos := Vector3(side * 13.6, 0, 4.6)
		_face(d, pos, Vector3(0, 0, 1.5))
		if is_home:
			var door_x := -StadiumDugout.W * 0.5 + 0.7
			_dugout_door = d.transform * Vector3(door_x, 0, 1.6)


func _build_scoreboard() -> void:
	var board := prop("scoreboard")
	var pos := Field.wall_point(0.0, Field.WALL_RADIUS + 9.0)
	var has_gate_center := false
	for g in _gate_angles():
		if absf(g.angle) < 8.0:
			has_gate_center = true
	if has_gate_center:
		pos = Field.wall_point(0.0, Field.WALL_RADIUS + 13.0)
	var screen: MeshInstance3D = null
	if board == null:
		board = Node3D.new()
		_box(Vector3(0.8, 7, 0.8), Vector3(-6, 3.5, -0.5), _mat(_c("steel"), 0.5, 0.7), board)
		_box(Vector3(0.8, 7, 0.8), Vector3(6, 3.5, -0.5), _mat(_c("steel"), 0.5, 0.7), board)
		_box(Vector3(16.6, 8.6, 0.6), Vector3(0, 10.8, -0.5), _mat(_c("wall").darkened(0.3), 0.5, 0.4), board)
		screen = MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(15.4, 7.4)
		screen.mesh = q
		screen.position = Vector3(0, 10.8, -0.15)
		board.add_child(screen)
	else:
		screen = board.find_child("Screen", true, false) as MeshInstance3D
		_add_scoreboard_nameplate(board)
	root.add_child(board)
	_face(board, pos, Field.HOME)
	board.scale = Vector3.ONE * 1.15
	scoreboard_viewport = SubViewport.new()
	scoreboard_viewport.size = Vector2i(1152, 512)
	scoreboard_viewport.transparent_bg = false
	scoreboard_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(scoreboard_viewport)
	scoreboard_ui = ScoreboardDisplay.new()
	scoreboard_ui.size = Vector2(1152, 512)
	scoreboard_viewport.add_child(scoreboard_ui)
	if screen:
		var m := StandardMaterial3D.new()
		m.albedo_texture = scoreboard_viewport.get_texture()
		m.emission_enabled = true
		m.emission_texture = scoreboard_viewport.get_texture()
		m.emission_energy_multiplier = 1.4
		m.roughness = 0.4
		screen.material_override = m


## The scoreboard model has a header plate with one stadium's name modelled in; cover it
## with a plate in the frame's own scarlet steel and this arena's name.
func _add_scoreboard_nameplate(board: Node3D) -> void:
	if arena_name == "":
		return
	var plate_mat: Material = null
	var frame := board.find_child("ScoreboardFrame", true, false) as MeshInstance3D
	if frame and frame.mesh:
		for i in frame.mesh.get_surface_count():
			var m := frame.mesh.surface_get_material(i)
			if m and m.resource_name == "SteelScarlet":
				plate_mat = m
	if plate_mat == null:
		plate_mat = _mat(Color(0.62, 0.08, 0.1), 0.5, 0.6)
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(9.3, 1.08, 0.1)
	plate.mesh = bm
	plate.material_override = plate_mat
	plate.position = Vector3(0, 14.75, 0.5)
	board.add_child(plate)
	var label := Label3D.new()
	label.text = arena_name.to_upper()
	label.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	label.font_size = 96
	label.outline_size = 0
	label.modulate = Color(0.95, 0.95, 0.92)
	label.shaded = true
	label.double_sided = false
	var text_w := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size).x
	label.pixel_size = minf(0.0095, 8.6 / maxf(text_w, 1.0))
	label.position = Vector3(0, 14.75, 0.56)
	board.add_child(label)


func _build_banners() -> void:
	var tex := _banner_texture()
	var angles := [-40.0, -22.0, 22.0, 40.0]
	for i in angles.size():
		var p := Field.wall_point(angles[i], Field.WALL_RADIUS + 1.6)
		var pole := prop("banner_pole")
		if pole == null:
			pole = Node3D.new()
			_box(Vector3(0.2, 9.0, 0.2), Vector3(0, 4.5, 0), _mat(_c("steel"), 0.4, 0.8), pole)
			var bm := MeshInstance3D.new()
			bm.name = "Banner"
			var pm := PlaneMesh.new()
			pm.size = Vector2(2.4, 4.4)
			pm.subdivide_width = 12
			pm.subdivide_depth = 10
			pm.orientation = PlaneMesh.FACE_Z
			bm.mesh = pm
			bm.position = Vector3(1.3, 6.4, 0)
			pole.add_child(bm)
		root.add_child(pole)
		_face(pole, p, Field.HOME)
		var banner := pole.find_child("Banner", true, false) as MeshInstance3D
		if banner:
			var m := ShaderMaterial.new()
			m.shader = load("res://assets/shaders/banner.gdshader")
			m.set_shader_parameter("tex", tex)
			m.set_shader_parameter("phase", float(i) * 1.7)
			banner.material_override = m


func _banner_texture() -> Texture2D:
	var img := Image.create(256, 672, false, Image.FORMAT_RGBA8)
	img.fill(_c("wall"))
	var trim := _c("trim")
	img.fill_rect(Rect2i(0, 0, 256, 26), trim)
	img.fill_rect(Rect2i(0, 646, 256, 26), trim)
	img.fill_rect(Rect2i(0, 34, 256, 6), _c("accent"))
	img.fill_rect(Rect2i(0, 632, 256, 6), _c("accent"))
	var logo_path := "res://assets/textures/logo/logo_small.png"
	if ResourceLoader.exists(logo_path):
		var logo: Image = (load(logo_path) as Texture2D).get_image()
		if logo:
			logo = logo.duplicate()
			logo.decompress()
			logo.convert(Image.FORMAT_RGBA8)
			var w := 230
			var h := int(float(logo.get_height()) / logo.get_width() * w)
			logo.resize(w, h, Image.INTERPOLATE_BILINEAR)
			img.blend_rect(logo, Rect2i(0, 0, w, h), Vector2i(13, 336 - h / 2))
	else:
		# Simple baseball emblem if the logo has not been generated.
		for y in 672:
			for x in 256:
				var dd := Vector2(x - 128, y - 336).length()
				if dd < 70:
					img.set_pixel(x, y, Color(0.96, 0.95, 0.9))
				if absf(dd - 58) < 3 and absf(x - 128) > 30:
					img.set_pixel(x, y, Color(0.85, 0.1, 0.1))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- background

func _build_background() -> void:
	var bg: String = theme.get("background", "industrial")
	var ring_props := []
	match bg:
		"industrial":
			ring_props = ["smokestack", "crane", "warehouse", "water_tower", "container", "warehouse", "smokestack"]
		"city", "city_night":
			ring_props = ["building_a", "building_b", "building_c", "warehouse", "building_b"]
		"fortress":
			ring_props = ["fortress_tower", "smokestack", "warehouse", "fortress_tower", "crane"]
		"mountains":
			ring_props = ["water_tower", "warehouse", "container"]
		"castle":
			ring_props = ["fortress_tower", "building_c", "fortress_tower", "building_a"]
	# Mid ring (industry) behind the stands.
	var count := 16
	for i in count:
		var ang := lerpf(-170.0, 170.0, float(i) / (count - 1)) + rng.randf_range(-6, 6)
		var rr := deg_to_rad(ang)
		var dist := rng.randf_range(78.0, 110.0)
		var pos := Vector3(sin(rr) * dist, 0, -cos(rr) * dist + 4.0)
		var name: String = ring_props[i % ring_props.size()] if ring_props.size() > 0 else ""
		var p := prop(name) if name != "" else null
		if p == null:
			p = _fallback_building(rng.randf_range(10, 28))
		root.add_child(p)
		_face(p, pos, Vector3.ZERO)
		p.rotation.y += rng.randf_range(-0.4, 0.4)
		if name == "container":
			p.scale = Vector3.ONE * 1.4
			_tint_named(p, "Container", Color.from_hsv(rng.randf(), 0.6, 0.6))
	# Far skyline or mountains.
	if bg == "mountains":
		_build_mountains()
	else:
		var night: bool = theme.get("time", "") in ["night", "twilight", "storm"]
		for i in 26:
			var ang := lerpf(-180.0, 180.0, float(i) / 26.0) + rng.randf_range(-4, 4)
			var rr := deg_to_rad(ang)
			var dist := rng.randf_range(170.0, 240.0)
			var pos := Vector3(sin(rr) * dist, 0, -cos(rr) * dist)
			var names := ["building_a", "building_b", "building_c"]
			var p := prop(names[i % 3])
			if p == null:
				p = _fallback_building(rng.randf_range(30, 80), night)
			root.add_child(p)
			_face(p, pos, Vector3.ZERO)
			p.scale = Vector3.ONE * rng.randf_range(0.9, 1.5)
			if night:
				_boost_named(p, "Windows", 3.0)


func _tint_named(n: Node, mat_name: String, c: Color) -> void:
	for mi in _all_meshes(n):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == mat_name and mat is BaseMaterial3D:
				var nm: BaseMaterial3D = mat.duplicate()
				nm.albedo_color = c
				mi.set_surface_override_material(s, nm)


func _boost_named(n: Node, mat_name: String, energy: float) -> void:
	for mi in _all_meshes(n):
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s)
			if mat and mat.resource_name == mat_name and mat is BaseMaterial3D:
				var nm: BaseMaterial3D = mat.duplicate()
				nm.emission_enabled = true
				nm.emission_energy_multiplier = energy
				mi.set_surface_override_material(s, nm)


func _fallback_building(h: float, lit := false) -> Node3D:
	var n := Node3D.new()
	var w := rng.randf_range(8, 18)
	var col := _c("steel").darkened(rng.randf_range(0.2, 0.5))
	_box(Vector3(w, h, w * 0.8), Vector3(0, h * 0.5, 0), _mat(col, 0.8, 0.2), n)
	if lit:
		var win := _mat(Color(1.0, 0.85, 0.5), 0.5, 0.0, Color(1.0, 0.8, 0.45), 1.6)
		for i in int(h / 6):
			_box(Vector3(w * 0.8, 0.6, 0.1), Vector3(0, 3 + i * 5.5, w * 0.4 + 0.05), win, n)
	return n


func _build_mountains() -> void:
	var m := _mat(Color(0.55, 0.62, 0.74), 0.95)
	var snow := _mat(Color(0.92, 0.95, 1.0), 0.8)
	for i in 14:
		var ang := lerpf(-180.0, 180.0, float(i) / 14.0)
		var rr := deg_to_rad(ang)
		var dist := rng.randf_range(190.0, 260.0)
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = rng.randf_range(45, 80)
		cm.height = rng.randf_range(50, 95)
		cm.radial_segments = 7
		mi.mesh = cm
		mi.material_override = m
		mi.position = Vector3(sin(rr) * dist, cm.height * 0.5 - 4.0, -cos(rr) * dist)
		root.add_child(mi)
		var cap := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.0
		cc.bottom_radius = cm.bottom_radius * 0.32
		cc.height = cm.height * 0.32
		cc.radial_segments = 7
		cap.mesh = cc
		cap.material_override = snow
		cap.position = mi.position + Vector3(0, cm.height * 0.34 + 0.2, 0)
		root.add_child(cap)
	# A ring of pine trees.
	var pine := _mat(Color(0.16, 0.3, 0.22), 0.9)
	for i in 60:
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(62.0, 120.0)
		var t := MeshInstance3D.new()
		var cm2 := CylinderMesh.new()
		cm2.top_radius = 0.0
		cm2.bottom_radius = rng.randf_range(2.0, 3.5)
		cm2.height = rng.randf_range(8, 15)
		cm2.radial_segments = 6
		t.mesh = cm2
		t.material_override = pine
		t.position = Vector3(cos(ang) * dist, cm2.height * 0.5, sin(ang) * dist)
		root.add_child(t)


func _build_ambient_particles() -> void:
	var kind: String = theme.get("particles", "none")
	if kind == "none":
		return
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(45, 1, 40)
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	gt.width = 32
	gt.height = 32
	m.albedo_texture = gt
	var scale_amt := Settings.particle_scale()
	match kind:
		"embers":
			p.amount = int(220 * scale_amt)
			p.lifetime = 9.0
			pm.gravity = Vector3(0.3, 0.35, 0)
			pm.initial_velocity_min = 0.2
			pm.initial_velocity_max = 0.8
			pm.direction = Vector3(0, 1, 0)
			pm.spread = 60
			pm.scale_min = 0.05
			pm.scale_max = 0.12
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.6
			pm.color = Color(1.0, 0.55, 0.2)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			p.position = Vector3(0, 0.5, -6)
		"dust":
			p.amount = int(160 * scale_amt)
			p.lifetime = 10.0
			pm.gravity = Vector3(0.2, 0.05, 0)
			pm.scale_min = 0.04
			pm.scale_max = 0.09
			pm.turbulence_enabled = true
			pm.color = Color(1.0, 0.9, 0.6, 0.6)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			pm.emission_box_extents = Vector3(45, 6, 40)
			p.position = Vector3(0, 6, -6)
		"snow":
			p.amount = int(900 * scale_amt)
			p.lifetime = 8.0
			pm.gravity = Vector3(0.4, -1.4, 0)
			pm.scale_min = 0.06
			pm.scale_max = 0.14
			pm.turbulence_enabled = true
			pm.turbulence_noise_strength = 0.8
			pm.color = Color(0.95, 0.97, 1.0, 0.9)
			pm.emission_box_extents = Vector3(50, 1, 45)
			p.position = Vector3(0, 18, -6)
		"rain":
			p.amount = int(1200 * scale_amt)
			p.lifetime = 1.2
			pm.gravity = Vector3(1.0, -28.0, 0)
			pm.scale_min = 1.0
			pm.scale_max = 1.3
			pm.color = Color(0.7, 0.8, 0.95, 0.22)
			quad.size = Vector2(0.025, 1.1)
			m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
			pm.emission_box_extents = Vector3(50, 1, 45)
			p.position = Vector3(0, 20, -6)
		"confetti":
			p.amount = int(260 * scale_amt)
			p.lifetime = 9.0
			pm.gravity = Vector3(0.2, -0.6, 0)
			pm.scale_min = 0.06
			pm.scale_max = 0.12
			pm.turbulence_enabled = true
			pm.hue_variation_min = -1.0
			pm.hue_variation_max = 1.0
			pm.color = Color(1.0, 0.75, 0.3)
			pm.emission_box_extents = Vector3(48, 1, 42)
			p.position = Vector3(0, 16, -6)
	p.process_material = pm
	if kind != "rain":
		quad.size = Vector2(0.12, 0.12) if kind != "snow" else Vector2(0.16, 0.16)
		pm.scale_min = 1.0
		pm.scale_max = 1.6
	quad.material = m
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-60, -25, -60), Vector3(120, 60, 120))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.preprocess = 6.0
	root.add_child(p)
