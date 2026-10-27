class_name FieldBuilder
extends RefCounted
## Builds the playing surface (shader-driven), mound, bases and home plate.

static var _ring_shader: Shader


static func ring_shader() -> Shader:
	if _ring_shader == null:
		_ring_shader = load("res://assets/shaders/ring.gdshader")
	return _ring_shader


## Creates a flat ground ring (range circle, target marker, telegraph...).
static func make_ring(radius: float, color: Color, thickness := 0.04, fill := 0.1, dashes := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(2, 2)
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = ring_shader()
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("thickness", thickness)
	m.set_shader_parameter("fill", fill)
	m.set_shader_parameter("dashes", dashes)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale = Vector3(radius, 1, radius)
	mi.position.y = 0.04
	return mi


static func build(parent: Node3D, theme: Dictionary, routes: Array) -> ShaderMaterial:
	var root := Node3D.new()
	root.name = "Field"
	parent.add_child(root)

	# Ground surface.
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 140)
	pm.subdivide_width = 4
	pm.subdivide_depth = 4
	ground.mesh = pm
	ground.position = Vector3(0, 0, -6)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/field.gdshader")
	mat.set_shader_parameter("grass_a", Color(theme.get("grass_a", "#3f8a3a")))
	mat.set_shader_parameter("grass_b", Color(theme.get("grass_b", "#4c9a44")))
	var dirt := Color(theme.get("dirt", "#b06a3e"))
	mat.set_shader_parameter("dirt_color", dirt)
	mat.set_shader_parameter("track_color", dirt.darkened(0.3))
	mat.set_shader_parameter("route_color", Color(theme.get("accent", "#ff7a1a")))
	var uni: Dictionary = DB.uniforms.get(Profile.data.get("uniform", "home"), DB.uniforms.get("home", {})).get("colors", {})
	var dim := {"night": 1.0, "storm": 0.6, "twilight": 0.45, "dusk_snow": 0.35}
	mat.set_shader_parameter("surround_dim", float(dim.get(str(theme.get("time", "")), 0.0)))
	mat.set_shader_parameter("team_color", Color(uni.get("Jersey", "#1c2e4a")))
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.02
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = noise
	mat.set_shader_parameter("noise_tex", nt)
	var nn := FastNoiseLite.new()
	nn.noise_type = FastNoiseLite.TYPE_CELLULAR
	nn.frequency = 0.08
	var nmt := NoiseTexture2D.new()
	nmt.width = 256
	nmt.height = 256
	nmt.seamless = true
	nmt.as_normal_map = true
	nmt.bump_strength = 4.0
	nmt.noise = nn
	mat.set_shader_parameter("detail_normal", nmt)
	set_routes(mat, routes)
	ground.material_override = mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ground)

	# Pitcher's mound with rubber.
	var mound := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 2.75
	cm.height = 0.28
	cm.radial_segments = 40
	mound.mesh = cm
	mound.position = Field.MOUND + Vector3(0, 0.12, 0)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = dirt.darkened(0.04)
	dm.roughness = 0.97
	dm.albedo_texture = nt
	dm.uv1_triplanar = true
	dm.uv1_scale = Vector3(0.15, 0.15, 0.15)
	mound.material_override = dm
	root.add_child(mound)
	var rubber := MeshInstance3D.new()
	var rb := BoxMesh.new()
	rb.size = Vector3(0.75, 0.05, 0.18)
	rubber.mesh = rb
	rubber.position = Field.MOUND + Vector3(0, 0.27, 0)
	rubber.material_override = _white()
	root.add_child(rubber)

	# Bases (rotated squares) and home plate (pentagon).
	for b in [Field.FIRST, Field.SECOND, Field.THIRD]:
		var bag := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.62, 0.12, 0.62)
		bag.mesh = bm
		bag.position = b + Vector3(0, 0.06, 0)
		bag.rotation.y = PI / 4
		bag.material_override = _white()
		root.add_child(bag)
	root.add_child(_home_plate())
	return mat


static func set_routes(mat: ShaderMaterial, routes: Array) -> void:
	var segs: Array[Vector4] = []
	var starts: Array[float] = []
	var seen := {}
	for r: Route in routes:
		var along := 0.0
		for i in r.raw_points.size() - 1:
			var a := r.raw_points[i]
			var b := r.raw_points[i + 1]
			var key := "%.1f,%.1f,%.1f,%.1f" % [a.x, a.z, b.x, b.z]
			if segs.size() < 48 and not seen.has(key) and a.distance_to(b) > 0.05:
				seen[key] = true
				segs.append(Vector4(a.x, a.z, b.x, b.z))
				starts.append(along)
			along += a.distance_to(b)
	var count := segs.size()
	while segs.size() < 48:
		segs.append(Vector4.ZERO)
		starts.append(0.0)
	mat.set_shader_parameter("segs", segs)
	mat.set_shader_parameter("seg_start", PackedFloat32Array(starts))
	mat.set_shader_parameter("seg_count", count)


static func _white() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.97, 0.96, 0.93)
	m.roughness = 0.6
	return m


static func _home_plate() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := 0.5
	# Pentagon pointing toward the catcher (+Z).
	var pts := [Vector3(-s, 0, -s * 0.6), Vector3(s, 0, -s * 0.6), Vector3(s, 0, s * 0.2), Vector3(0, 0, s * 0.9), Vector3(-s, 0, s * 0.2)]
	var h := Vector3(0, 0.05, 0)
	st.set_normal(Vector3.UP)
	for i in range(1, pts.size() - 1):
		st.add_vertex(pts[0] + h)
		st.add_vertex(pts[i + 1] + h)
		st.add_vertex(pts[i] + h)
	for i in pts.size():
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[(i + 1) % pts.size()]
		var n := (b - a).cross(Vector3.UP).normalized() * -1.0
		st.set_normal(n)
		st.add_vertex(a)
		st.add_vertex(a + h)
		st.add_vertex(b + h)
		st.add_vertex(a)
		st.add_vertex(b + h)
		st.add_vertex(b)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.position = Field.HOME + Vector3(0, 0.005, 0)
	mi.material_override = _white()
	return mi
