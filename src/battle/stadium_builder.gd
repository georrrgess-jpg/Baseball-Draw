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
	mi.set_meta("part", "ground")


# ---------------------------------------------------------------- walls & gates

func _gate_angles() -> Array:
	var out := []
	for gid in layout.get("gates", {}).keys():
		var g: Array = layout.gates[gid]
		var p := Vector3(float(g[0]), 0, float(g[1]))
		out.append({"id": gid, "pos": p, "angle": Field.angle_from_center(p)})
	return out


## Gate geometry (Update 12). The gate props are scaled up so the tallest boss (the Grand Slammer,
## 6.7 m) fits through the doorway: taller than wide, which keeps the doors swinging true (the
## scale is the same along X and Z, the axes a door turns in). Every gate has a walled, roofed
## runner tunnel behind it.
const GATE_SCALE := Vector3(1.12, 1.42, 1.12)
const GATE_HALF_W := 4.0 * 1.12                # outer half width of the gate frame
const GATE_OPEN_HALF := 3.0 * 1.12             # half width of the doorway
const GATE_OPEN_H := 4.9 * 1.42                # doorway height
const GATE_HALF_D := 0.8 * 1.12                # half depth of the frame
const GATE_OUT := 0.5                          # gate centre sits this far outside the wall line
const TUNNEL_LEN := 9.0
const TUNNEL_IN_HALF := GATE_OPEN_HALF + 0.14  # interior half width
const TUNNEL_IN_H := 7.4                       # interior height (ceiling)
const TUNNEL_ROOF := 8.05                      # top of the roof slab
const TUNNEL_GAP := 1.5                        # clear space kept around every tunnel

var _keepouts: Array = []   # [{xf: Transform3D (on the ground, +Z toward home), lo: Vector2, hi: Vector2}] in gate-local x/z


func _gate_xform(gp: Vector3) -> Transform3D:
	var n := Node3D.new()
	_face(n, gp + (gp - Field.HOME).normalized() * GATE_OUT, Field.HOME)
	var xf := n.transform
	n.free()
	return xf


## The area every gate and its tunnel needs, plus TUNNEL_GAP all round (stands, crowd, towers,
## banners and signage stay out of it).
func _build_keepouts() -> void:
	_keepouts.clear()
	for g in _gate_angles():
		var xf := _gate_xform(g.pos)
		var back := -GATE_HALF_D - TUNNEL_LEN - 0.6
		_keepouts.append({"xf": xf, "lo": Vector2(-GATE_HALF_W - TUNNEL_GAP, back - TUNNEL_GAP), "hi": Vector2(GATE_HALF_W + TUNNEL_GAP, GATE_HALF_D + 0.5), "id": g.id})


## Is a ground footprint (a rectangle `half` around `center`, turned by `rot_y`) clear of every tunnel?
func _clear_of_tunnels(center: Vector3, half: Vector2, rot_y: float) -> bool:
	return _rects_clear(center, half, rot_y, _keepouts)


## Is the rectangle clear of every rectangle in `rects` (keep-out format)?
func _rects_clear(center: Vector3, half: Vector2, rot_y: float, rects: Array) -> bool:
	var ax := Vector3(cos(rot_y), 0, -sin(rot_y))
	var az := Vector3(sin(rot_y), 0, cos(rot_y))
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			corners.append(center + ax * half.x * sx + az * half.y * sz)
	for k in rects:
		var xf: Transform3D = k.xf
		var lo: Vector2 = k.lo
		var hi: Vector2 = k.hi
		var inv := xf.affine_inverse()
		var kc: Array[Vector3] = [xf * Vector3(lo.x, 0, lo.y), xf * Vector3(hi.x, 0, lo.y), xf * Vector3(hi.x, 0, hi.y), xf * Vector3(lo.x, 0, hi.y)]
		# Separating axis test on the XZ plane (two rectangles, four axes).
		var separated := false
		for axis in [xf.basis.x, xf.basis.z, ax, az]:
			var a := Vector3(axis.x, 0, axis.z).normalized()
			var amin := INF
			var amax := -INF
			for p in corners:
				amin = minf(amin, a.dot(p))
				amax = maxf(amax, a.dot(p))
			var bmin := INF
			var bmax := -INF
			for p in kc:
				bmin = minf(bmin, a.dot(p))
				bmax = maxf(bmax, a.dot(p))
			if amax < bmin or bmax < amin:
				separated = true
				break
		if not separated:
			return false
	return true


## Angular extent (degrees, seen from home) that a gate's frame takes out of the outfield wall.
func _gate_half_angle() -> float:
	return rad_to_deg(atan2(GATE_HALF_W + 0.05, Field.WALL_RADIUS))


func _build_outfield_wall() -> void:
	var gate_list := _gate_angles()
	_build_keepouts()
	var wall_col := _c("wall")
	var r := Field.WALL_RADIUS
	var span := 45.0
	# The wall runs between the gates: each free stretch is filled with whole segments (scaled
	# slightly to fit) that butt into the gate pillars, so no segment ever reaches a doorway.
	var cuts: Array = []
	for g in gate_list:
		cuts.append([float(g.angle) - _gate_half_angle(), float(g.angle) + _gate_half_angle()])
	cuts.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var stretches: Array = []
	var a := -span
	for c in cuts:
		if c[0] > a + 0.5:
			stretches.append([a, minf(c[0], span), a <= -span + 0.01, false])
		a = maxf(a, c[1])
	if a < span - 0.5:
		stretches.append([a, span, false, true])
	var ads := SurfaceTool.new()
	ads.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ad_i := rng.randi() % 8
	var post_angles: Array = []
	for s in stretches:
		var a0: float = s[0]
		var a1: float = s[1]
		var arc := deg_to_rad(a1 - a0) * r
		var n := maxi(1, int(round(arc / 6.0)))
		var step := (a1 - a0) / n
		for i in n:
			var s0 := a0 + step * i
			var s1 := s0 + step
			var p0 := Field.wall_point(s0, r)
			var p1 := Field.wall_point(s1, r)
			var seg := prop("wall_segment")
			if seg == null:
				seg = _fallback_wall(6.0, wall_col)
			root.add_child(seg)
			seg.set_meta("part", "outfield wall")
			_face(seg, (p0 + p1) * 0.5, Field.HOME)
			seg.scale.x = p0.distance_to(p1) / 6.0
			_add_ad_board(ads, seg.transform, ad_i % 8)
			ad_i += 1
			# Posts at the joins and at the open ends (the foul poles); a gate pillar covers its own joins.
			if i > 0 or s[2]:
				post_angles.append(s0)
		if s[3]:
			post_angles.append(a1)
	_finish_ad_boards(ads)
	_build_foul_poles(gate_list)
	for pa in post_angles:
		var post := prop("wall_post")
		if post == null:
			post = Node3D.new()
			_box(Vector3(0.9, 4.8, 0.9), Vector3(0, 2.4, 0), _mat(_c("steel"), 0.5, 0.6), post)
			_box(Vector3(1.1, 0.25, 1.1), Vector3(0, 4.9, 0), _mat(_c("trim"), 0.5, 0.2), post)
		root.add_child(post)
		post.set_meta("part", "wall post")
		_face(post, Field.wall_point(pa, r), Field.HOME)
	# Gates
	var letters := ["a", "b", "c", "d"]
	var li := 0
	for g in gate_list:
		var letter: String = letters[li % 4]
		var gate := prop("gate_" + letter)
		li += 1
		if gate == null:
			gate = prop("gate")
		if gate == null:
			gate = _fallback_gate()
		root.add_child(gate)
		gate.name = "Gate_" + str(g.id)
		gate.set_meta("part", "gate %s" % g.id)
		gate.transform = _gate_xform(g.pos)
		gate.scale = GATE_SCALE
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
		_build_tunnel(g, gate, letter.to_upper())


## A textured, vertex-coloured material for procedural stadium pieces (triplanar, so pieces of any
## size share one texel density with the generated props).
func _tex_mat(tex: String, rough := 0.8, metal := 0.0, uv_scale := 0.35) -> StandardMaterial3D:
	var key := "tex|%s|%.2f|%.2f|%.2f" % [tex, rough, metal, uv_scale]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	var path := PROP_DIR + "textures/tex_" + tex + ".jpg"
	if ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * uv_scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m


func _kit_mesh(parent: Node3D, k: MeshKit, mat: Material, mesh_name: String, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = k.commit()
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## The runner tunnel behind a gate (Update 12): a short walled, roofed tunnel that cuts through the
## stands and concourse so the doors open from a clear runway. Runners appear inside it
## (Battle.TUNNEL_SPAWN) and walk out through the doorway. Built in the gate's own frame (+Z toward
## home plate): a full-height front section the doors open from, a lower rear section stepping down
## toward the concourse, steel portal frames, lamps and floor markings inside, the steel collars
## where the outfield wall meets the pillars, the lit VISITORS marquee and two entrance lamps.
func _build_tunnel(g: Dictionary, gate: Node3D, letter: String) -> void:
	var t := Node3D.new()
	t.name = "Tunnel_" + str(g.id)
	t.set_meta("part", "tunnel %s" % g.id)
	t.set_meta("tunnel_of", gate)
	root.add_child(t)
	t.transform = _gate_xform(g.pos)
	var iw := TUNNEL_IN_HALF
	var ow := GATE_HALF_W
	var zf := -GATE_HALF_D + 0.05
	var zb := zf - TUNNEL_LEN
	var split := zf - 5.6                     # front (full height) / rear (stepped down) sections
	# [z0, z1, interior height, roof top] for each section, back to front.
	var sections := [[zb - 0.6, split, TUNNEL_IN_H - 2.3, TUNNEL_ROOF - 2.3], [split, zf, TUNNEL_IN_H, TUNNEL_ROOF]]
	var trim := _c("trim")
	var accent := _c("accent", "#ff7a1a")
	var wall_col := _c("wall")

	# Shell: side walls, roofs, the step between the sections and the end wall, clad in the arena's
	# wall colour over dark concrete; a light concrete plinth all round.
	var shell := MeshKit.new()
	shell.color = wall_col.lightened(0.6)
	for sec in sections:
		var z0: float = sec[0]
		var z1: float = sec[1]
		var rt: float = sec[3]
		for s in [-1.0, 1.0]:
			shell.box_mm(Vector3(minf(s * iw, s * ow), 0.55, z0), Vector3(maxf(s * iw, s * ow), rt, z1))
	shell.box_mm(Vector3(-ow, 0.55, zb - 0.6), Vector3(ow, sections[0][2], zb), ["+y"])
	shell.box_mm(Vector3(-ow, sections[0][2], split - 0.35), Vector3(ow, TUNNEL_ROOF, split), ["-y"])
	_kit_mesh(t, shell, _tex_mat("concrete", 0.88, 0.0, 0.3), "Shell")
	var roof := MeshKit.new()
	roof.color = Color(0.7, 0.72, 0.76)
	for sec in sections:
		roof.box_mm(Vector3(-ow, sec[2], sec[0]), Vector3(ow, sec[3], sec[1]), ["-y"])
	_kit_mesh(t, roof, _tex_mat("roof", 0.8, 0.3, 0.4), "Roof")
	var plinth := MeshKit.new()
	plinth.color = Color(0.82, 0.82, 0.8)
	for s in [-1.0, 1.0]:
		plinth.box_mm(Vector3(minf(s * iw, s * (ow + 0.18)), 0, zb - 0.78), Vector3(maxf(s * iw, s * (ow + 0.18)), 0.55, zf - 0.05))
	plinth.box_mm(Vector3(-ow - 0.18, 0, zb - 0.78), Vector3(ow + 0.18, 0.55, zb))
	_kit_mesh(t, plinth, _tex_mat("concrete", 0.92), "Plinth")

	# Dark interior: lining, ceilings and the rubber floor.
	var dark := MeshKit.new()
	dark.color = Color(0.72, 0.74, 0.8)
	for sec in sections:
		var z0: float = maxf(sec[0], zb)
		var ih: float = sec[2]
		for s in [-1.0, 1.0]:
			dark.box_mm(Vector3(minf(s * (iw - 0.05), s * iw), 0.9, z0), Vector3(maxf(s * (iw - 0.05), s * iw), ih, sec[1]))
		dark.box_mm(Vector3(-iw, ih - 0.05, z0), Vector3(iw, ih, sec[1]), ["+y"])
	dark.box_mm(Vector3(-iw, sections[0][2], split - 0.4), Vector3(iw, TUNNEL_IN_H, split - 0.35), ["-z"])
	dark.color = Color(0.5, 0.52, 0.56)
	dark.box_mm(Vector3(-iw, 0, zb), Vector3(iw, 0.03, zf), ["-y"])
	_kit_mesh(t, dark, _tex_mat("concrete_dark", 0.92), "Lining")

	# Steel: portal frames down the tunnel, the end wall and its doors, pilasters outside, the
	# collars where the outfield wall meets the gate pillars, and the marquee frame.
	var steel := MeshKit.new()
	steel.color = Color(1, 1, 1)
	var frame_z: Array = []
	var fz := zf - 0.4
	while fz > zb + 0.3:
		frame_z.append(fz)
		fz -= 2.2
	for z in frame_z:
		var ih: float = TUNNEL_IN_H if z > split else sections[0][2]
		var rt: float = TUNNEL_ROOF if z > split else sections[0][3]
		for s in [-1.0, 1.0]:
			steel.box_mm(Vector3(minf(s * (iw - 0.32), s * (iw - 0.05)), 0.0, z - 0.18), Vector3(maxf(s * (iw - 0.32), s * (iw - 0.05)), ih, z + 0.18))
			steel.box_mm(Vector3(minf(s * ow, s * (ow + 0.26)), 0.55, z - 0.22), Vector3(maxf(s * ow, s * (ow + 0.26)), rt - 0.1, z + 0.22))
		steel.box_mm(Vector3(-iw + 0.05, ih - 0.38, z - 0.18), Vector3(iw - 0.05, ih - 0.05, z + 0.18))
	steel.color = Color(0.55, 0.58, 0.66)
	steel.box_mm(Vector3(-iw, 0.03, zb), Vector3(iw, sections[0][2] - 0.05, zb + 0.08), ["-z"])
	steel.color = Color(0.32, 0.34, 0.4)
	steel.box_mm(Vector3(-1.7, 0.03, zb + 0.08), Vector3(-0.03, 3.3, zb + 0.16), ["-z"])
	steel.box_mm(Vector3(0.03, 0.03, zb + 0.08), Vector3(1.7, 3.3, zb + 0.16), ["-z"])
	steel.color = Color(1, 1, 1)
	steel.box_mm(Vector3(-1.9, 3.3, zb + 0.08), Vector3(1.9, 3.48, zb + 0.2), ["-z"])
	for s in [-1.0, 1.0]:
		steel.box_mm(Vector3(minf(s * (ow - 0.1), s * (ow + 0.5)), 0.0, -1.15), Vector3(maxf(s * (ow - 0.1), s * (ow + 0.5)), 4.5, 1.1))
	var mz := zf - 0.75
	var my := TUNNEL_ROOF + 1.25      # the marquee stands on legs, clear of the gate's beacon and lamps
	steel.color = Color(0.4, 0.42, 0.48)
	steel.box_mm(Vector3(-3.9, my, mz - 0.35), Vector3(3.9, my + 2.3, mz))
	steel.color = Color(1, 1, 1)
	for s in [-1.0, 1.0]:
		steel.box_mm(Vector3(s * 3.75 - 0.18, TUNNEL_ROOF, mz - 0.7), Vector3(s * 3.75 + 0.18, my + 2.4, mz + 0.05))
		steel.box_mm(Vector3(s * 2.0 - 0.1, TUNNEL_ROOF, mz - 0.55), Vector3(s * 2.0 + 0.1, my, mz - 0.35))
	_kit_mesh(t, steel, _tex_mat("steel_charcoal", 0.5, 0.65, 0.5), "Steel")

	# Railings round both roofs (galvanised).
	var rail := MeshKit.new()
	rail.color = Color(0.85, 0.86, 0.88)
	for sec in sections:
		var z0: float = sec[0]
		var z1: float = sec[1]
		var rt: float = sec[3] + 0.24
		for s in [-1.0, 1.0]:
			var x: float = s * (ow - 0.15)
			rail.box_mm(Vector3(x - 0.03, rt + 1.0, z0 + 0.1), Vector3(x + 0.03, rt + 1.06, z1 - 0.1))
			rail.box_mm(Vector3(x - 0.02, rt + 0.5, z0 + 0.1), Vector3(x + 0.02, rt + 0.54, z1 - 0.1))
			var pz := z0 + 0.1
			while pz <= z1 - 0.05:
				rail.box_mm(Vector3(x - 0.035, rt, pz - 0.035), Vector3(x + 0.035, rt + 1.06, pz + 0.035))
				pz += 1.4
	rail.box_mm(Vector3(-ow + 0.15, sections[0][3] + 1.24, zb - 0.53), Vector3(ow - 0.15, sections[0][3] + 1.3, zb - 0.47))
	_kit_mesh(t, rail, _tex_mat("galv", 0.4, 0.8, 0.6), "Railings")

	# Painted parts in the arena's colours: wall band, roof copings, collar caps, floor markings.
	var paint := MeshKit.new()
	paint.color = trim
	for sec in sections:
		var z0: float = sec[0]
		var z1: float = sec[1]
		var rt: float = sec[3]
		for s in [-1.0, 1.0]:
			paint.box_mm(Vector3(minf(s * (ow - 0.3), s * (ow + 0.12)), rt, z0 - 0.12), Vector3(maxf(s * (ow - 0.3), s * (ow + 0.12)), rt + 0.24, z1))
		paint.box_mm(Vector3(-ow - 0.12, rt, z0 - 0.12), Vector3(ow + 0.12, rt + 0.24, z0 + 0.2))
	for s in [-1.0, 1.0]:
		paint.box_mm(Vector3(minf(s * ow, s * (ow + 0.09)), 4.0, zb - 0.6), Vector3(maxf(s * ow, s * (ow + 0.09)), 4.45, zf - 0.05))
		paint.box_mm(Vector3(minf(s * (ow - 0.16), s * (ow + 0.58)), 4.5, -1.22), Vector3(maxf(s * (ow - 0.16), s * (ow + 0.58)), 4.72, 1.17))
	paint.box_mm(Vector3(-ow - 0.09, 4.0, zb - 0.69), Vector3(ow + 0.09, 4.45, zb - 0.6))
	paint.color = wall_col.lightened(0.15)
	for s in [-1.0, 1.0]:
		paint.box_mm(Vector3(minf(s * (iw - 0.05), s * (iw - 0.07)), 2.6, zb), Vector3(maxf(s * (iw - 0.05), s * (iw - 0.07)), 3.0, zf))
	paint.color = Color(0.92, 0.92, 0.9)
	for s in [-1.0, 1.0]:
		paint.box_mm(Vector3(s * (iw - 0.6) - 0.07, 0.03, zb + 0.3), Vector3(s * (iw - 0.6) + 0.07, 0.042, zf - 1.0))
	paint.color = Color(1.0, 0.78, 0.1)
	var cz := zf - 2.0
	while cz > zb + 1.0:
		for s in [-1.0, 1.0]:
			paint.xform = Transform3D(Basis(Vector3.UP, -s * 0.85), Vector3(s * 0.62, 0.0, cz))
			paint.box(Vector3(0, 0.036, 0), Vector3(0.3, 0.012, 1.55))
		cz -= 2.1
	paint.xform = Transform3D.IDENTITY
	_kit_mesh(t, paint, _tex_mat("white_paint", 0.6, 0.1, 0.5), "Paint", false)

	# Hazard stripes: the threshold and a dado band down both walls.
	var haz := MeshKit.new()
	haz.box_mm(Vector3(-iw, 0.03, zf - 0.9), Vector3(iw, 0.045, zf))
	for s in [-1.0, 1.0]:
		haz.box_mm(Vector3(minf(s * (iw - 0.1), s * iw), 0.0, zb), Vector3(maxf(s * (iw - 0.1), s * iw), 0.9, zf))
	_kit_mesh(t, haz, _tex_mat("hazard", 0.7, 0.0, 0.6), "Hazard", false)

	# Lights: ceiling strips between the frames, bulkhead lamps on the walls, the marquee lamp bars
	# and two entrance lamps on the collars.
	var lamps := MeshKit.new()
	lamps.color = Color(1, 1, 1)
	for i in frame_z.size() - 1:
		var z: float = (float(frame_z[i]) + float(frame_z[i + 1])) * 0.5
		var ih: float = TUNNEL_IN_H if z > split else sections[0][2]
		for x in [-1.6, 1.6]:
			lamps.box(Vector3(x, ih - 0.1, z), Vector3(0.3, 0.08, 1.3))
		for s in [-1.0, 1.0]:
			lamps.box(Vector3(s * (iw - 0.14), 3.9, z), Vector3(0.1, 0.22, 0.42))
	for s in [-1.0, 1.0]:
		lamps.box(Vector3(s * (ow + 0.2), 4.95, 0.85), Vector3(0.4, 0.18, 0.3))
	lamps.box(Vector3(0, my + 0.22, mz + 0.03), Vector3(7.0, 0.1, 0.08))
	lamps.box(Vector3(0, my + 2.12, mz + 0.03), Vector3(7.0, 0.1, 0.08))
	_kit_mesh(t, lamps, _mat(Color(1.0, 0.97, 0.9), 0.4, 0.0, Color(1.0, 0.93, 0.78), 4.0), "Lamps", false)
	var glow := MeshKit.new()
	glow.color = Color(1, 1, 1)
	glow.box_mm(Vector3(-2.4, 3.65, zb + 0.08), Vector3(2.4, 4.45, zb + 0.14))
	_kit_mesh(t, glow, _mat(accent.darkened(0.35), 0.5, 0.0, accent, 1.6), "SignGlow", false)
	# Light bars down the field face of both pillars, beside the doorway (set_gate_open turns them
	# from red to green), in steel housings.
	var housing := MeshKit.new()
	housing.color = Color(0.25, 0.26, 0.3)
	var jb := MeshKit.new()
	jb.color = Color(1, 1, 1)
	var jx := GATE_OPEN_HALF + 0.5
	var jz := GATE_HALF_D + 0.04
	for s in [-1.0, 1.0]:
		housing.box_mm(Vector3(s * jx - 0.14, 0.7, jz - 0.04), Vector3(s * jx + 0.14, GATE_OPEN_H - 0.4, jz + 0.08))
		jb.box_mm(Vector3(s * jx - 0.07, 0.8, jz + 0.08), Vector3(s * jx + 0.07, GATE_OPEN_H - 0.5, jz + 0.12), ["-z"])
	_kit_mesh(t, housing, _tex_mat("steel_dark", 0.5, 0.6, 0.6), "JambHousing", false)
	var jamb_mat := StandardMaterial3D.new()
	jamb_mat.albedo_color = Color(0.2, 0.2, 0.2)
	jamb_mat.emission_enabled = true
	jamb_mat.emission = JAMB_SHUT
	jamb_mat.emission_energy_multiplier = 1.2
	_kit_mesh(t, jb, jamb_mat, "JambLights", false)
	gate.set_meta("jamb_mat", jamb_mat)

	# Signage: VISITORS over the end-wall doors and on the marquee above the gate.
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var inner := Label3D.new()
	inner.text = "VISITORS"
	inner.font = font
	inner.font_size = 96
	inner.pixel_size = 0.0068
	inner.outline_size = 0
	inner.modulate = Color(0.08, 0.08, 0.1)
	inner.position = Vector3(0, 4.05, zb + 0.16)
	t.add_child(inner)
	var sign := Label3D.new()
	sign.text = "VISITORS · GATE " + letter
	sign.font = font
	sign.font_size = 96
	sign.outline_size = 10
	sign.outline_modulate = Color(0.05, 0.05, 0.07)
	sign.modulate = Color(accent.r * 1.6, accent.g * 1.6, accent.b * 1.6)
	sign.shaded = false
	var text_w := font.get_string_size(sign.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sign.font_size).x
	sign.pixel_size = minf(0.012, 6.6 / maxf(text_w, 1.0))
	sign.position = Vector3(0, my + 1.17, mz + 0.02)
	t.add_child(sign)

	# A warm work light inside (not on Low quality).
	if int(Settings.get_value("graphics", "preset", 2)) > 0:
		var ol := OmniLight3D.new()
		ol.name = "TunnelLight"
		ol.light_color = Color(1.0, 0.88, 0.7)
		ol.light_energy = 1.6
		ol.omni_range = 10.0
		ol.omni_attenuation = 1.4
		ol.shadow_enabled = false
		ol.position = Vector3(0, TUNNEL_IN_H - 1.4, zf - 3.6)
		t.add_child(ol)




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
	mi.set_meta("part", "ad boards")


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
		mi.set_meta("part", "foul pole")
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
	# Jamb light bars: dim red while shut, bright green while the gate is open.
	var jamb: StandardMaterial3D = g.get_meta("jamb_mat", null)
	if jamb:
		tw.tween_property(jamb, "emission", JAMB_OPEN if open else JAMB_SHUT, 0.5)
		tw.tween_property(jamb, "emission_energy_multiplier", 3.2 if open else 1.2, 0.5)


const JAMB_SHUT := Color(1.0, 0.16, 0.08)
const JAMB_OPEN := Color(0.3, 1.0, 0.45)


func _build_side_walls() -> void:
	# Walls running from the foul poles back past the dugouts, then a backstop behind home.
	var wall_col := _c("wall")
	for side in [-1.0, 1.0]:
		var a := _side_wall_start(side)
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
			seg.set_meta("part", "side wall")
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
		seg.set_meta("part", "backstop")
		_face(seg, p, Field.HOME)
		seg.scale.x = 0.6
	var fence := prop("fence_chain")
	if fence:
		for i in 5:
			var ang := lerpf(-40.0, 40.0, i / 4.0)
			var rr := deg_to_rad(ang)
			var f2 := prop("fence_chain")
			root.add_child(f2)
			f2.set_meta("part", "backstop fence")
			_face(f2, Field.HOME + Vector3(sin(rr) * 7.6, 3.8, cos(rr) * 7.6), Field.HOME + Vector3(0, 3.8, 0))
		fence.free()


# ---------------------------------------------------------------- stands & crowd

func _build_stands() -> void:
	# Each entry: [front-centre point, facing direction (toward the field), keep canopy].
	# The grandstand's front edge is at local z = +4.5, so the origin sits 4.5 m behind it.
	# Stands (and their crowds) keep TUNNEL_GAP clear of every gate tunnel: a stand that would
	# touch one slides along its row of seats until it is clear, or is left out.
	var placements: Array = []
	var taken: Array = [_rect(_scoreboard_pos(), Vector2(10.6, 2.6), PI)]
	for side in [-1.0, 1.0]:
		var a := _side_wall_start(side)
		var b := Vector3(side * 16.5, 0, 12.0)
		var dir := (b - a).normalized()
		var outward := Vector3(-dir.z, 0, dir.x)
		if outward.x * side < 0:
			outward = -outward
		for t in [0.22, 0.68]:
			for dt in [0.0, 0.04, -0.04, 0.08, -0.08, 0.12, 0.16, 0.2, 0.24, 0.28, 0.32]:
				if t + dt > 0.75:
					continue
				var p := a.lerp(b, t + dt) + outward * 3.2
				if _stand_fits(p, -outward, taken):
					placements.append([p, -outward, true])
					taken.append(_stand_rect(p, -outward))
					break
	for ang in [-62.0, 0.0, 62.0]:
		var rr := deg_to_rad(ang)
		var dir := Vector3(sin(rr), 0, cos(rr))
		placements.append([Field.HOME + dir * 11.5, -dir, false])
	placements.append_array(_outfield_stands(taken))
	var crowd_cols: Array = theme.get("crowd", ["#1c2e4a", "#d7262e", "#f4f1ea"])
	var density := float(Settings.get_value("graphics", "crowd", 1.0))
	for pl in placements:
		var stand := prop("grandstand")
		if stand == null:
			stand = _fallback_stand()
		root.add_child(stand)
		stand.set_meta("part", "grandstand")
		var front: Vector3 = pl[0]
		var f: Vector3 = pl[1]
		f.y = 0
		f = f.normalized()
		stand.position = front - f * 4.5
		stand.rotation.y = atan2(f.x, f.z)
		if pl.size() > 3:
			stand.scale.x = float(pl[3]) / 12.0
		if not pl[2]:
			var canopy := stand.find_child("Canopy", true, false) as Node3D
			if canopy:
				canopy.visible = false
		crowd.fill_stand(stand, crowd_cols, density, rng)


## Grandstands behind the outfield wall, packed between the gate tunnels: full 12 m stands where
## they fit, narrower ones (down to 7 m) in the tighter gaps, so every tunnel is flanked by seating
## with a clean TUNNEL_GAP either side. Laid out for the right half and mirrored (the layouts are
## symmetric); a mirrored stand that does not fit is left out.
func _outfield_stands(taken: Array) -> Array:
	var out: Array = []
	var right: Array = []
	var r := Field.WALL_RADIUS + 3.4
	for width in [12.0, 10.0, 8.5, 7.0]:
		var a := 0.0
		while a <= 47.0:
			var p := Field.wall_point(a, r)
			var f := (Field.HOME - p).normalized()
			var ok := _stand_fits(p, f, taken, width)
			if ok and a > 0.01:
				# Leave room for the mirror image on the left.
				var pm := Field.wall_point(-a, r)
				ok = _stand_fits(pm, (Field.HOME - pm).normalized(), taken + [_stand_rect(p, f, width)], width)
			if ok:
				right.append([a, width])
				taken.append(_stand_rect(p, f, width))
				if a > 0.01:
					var pm := Field.wall_point(-a, r)
					taken.append(_stand_rect(pm, (Field.HOME - pm).normalized(), width))
				a += rad_to_deg(width / r)
			else:
				a += 0.5
	for e in right:
		for sgn in ([1.0] if e[0] < 0.01 else [1.0, -1.0]):
			var p := Field.wall_point(e[0] * sgn, r)
			out.append([p, (Field.HOME - p).normalized(), true, e[1]])
	return out


## A ground rectangle in the keep-out format (`half` around `center`, turned by `rot_y`).
func _rect(center: Vector3, half: Vector2, rot_y: float) -> Dictionary:
	return {"xf": Transform3D(Basis(Vector3.UP, rot_y), Vector3(center.x, 0, center.z)), "lo": -half, "hi": half}


## A grandstand's footprint (seats, back wall and canopy) for a front-centre point and facing.
func _stand_rect(front: Vector3, f: Vector3, width := 12.0) -> Dictionary:
	f.y = 0
	f = f.normalized()
	var origin := front - f * 4.5
	return _rect(origin - f * 0.12, Vector2(width * 0.5 + 0.15, 4.95), atan2(f.x, f.z))


func _stand_fits(front: Vector3, f: Vector3, taken: Array, width := 12.0) -> bool:
	var r := _stand_rect(front, f, width)
	var xf: Transform3D = r.xf
	var half: Vector2 = r.hi
	var rot := atan2(xf.basis.z.x, xf.basis.z.z)
	return _clear_of_tunnels(xf.origin, half, rot) and _rects_clear(xf.origin, half, rot, taken)


## Where a side wall starts at a foul pole. When a corner gate stands there, the side wall starts
## at that gate's outer collar instead, so it never crosses the doorway or the door swing.
func _side_wall_start(side: float) -> Vector3:
	var start := Field.wall_point(45.0 * side, Field.WALL_RADIUS) + Vector3(side * 1.0, 0, 0)
	for g in _gate_angles():
		if absf(float(g.angle) - 45.0 * side) < 12.0:
			var xf := _gate_xform(g.pos)
			var e0 := xf * Vector3(GATE_HALF_W + 0.3, 0, 0.5)
			var e1 := xf * Vector3(-GATE_HALF_W - 0.3, 0, 0.5)
			start = e0 if Field.angle_from_center(e0) * side > Field.angle_from_center(e1) * side else e1
	return start


func _scoreboard_pos() -> Vector3:
	var r := Field.WALL_RADIUS + 9.0
	var pos := Field.wall_point(0.0, r)
	while r < Field.WALL_RADIUS + 30.0 and not _clear_of_tunnels(pos, Vector2(10.6, 2.6), PI):
		r += 1.0
		pos = Field.wall_point(0.0, r)
	return pos


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
	for p0 in spots:
		# A tower base that would touch a gate tunnel steps further out.
		var p: Vector3 = p0
		var k := 0
		while k < 12 and not _clear_of_tunnels(p, Vector2(3.0, 3.0), 0.0):
			p += (p0 - Vector3(0, 0, -4)).normalized() * 1.5
			k += 1
		var tower := prop("light_tower")
		if tower == null:
			tower = _fallback_tower()
		root.add_child(tower)
		tower.set_meta("part", "light tower")
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
		d.set_meta("part", "dugout")
		var pos := Vector3(side * 13.6, 0, 4.6)
		_face(d, pos, Vector3(0, 0, 1.5))
		if is_home:
			var door_x := -StadiumDugout.W * 0.5 + 0.7
			_dugout_door = d.transform * Vector3(door_x, 0, 1.6)


func _build_scoreboard() -> void:
	var board := prop("scoreboard")
	var pos := _scoreboard_pos()   # pushed back behind a centre-field gate's tunnel
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
	board.set_meta("part", "scoreboard")
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
		# Banners stand behind the wall; one that would touch a gate tunnel moves along the wall.
		var p := Vector3.INF
		for da in [0.0, 3.0, -3.0, 6.0, -6.0, 9.0, -9.0]:
			var a2: float = angles[i] + da
			if absf(a2) > 44.0:
				continue
			var q := Field.wall_point(a2, Field.WALL_RADIUS + 1.6)
			var to := Field.HOME - q
			var rot := atan2(to.x, to.z)
			var c := q + Vector3(cos(rot), 0, -sin(rot)) * 1.15
			if _clear_of_tunnels(c, Vector2(1.6, 0.7), rot):
				p = q
				break
		if p == Vector3.INF:
			continue
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
		pole.set_meta("part", "banner pole")
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
		p.set_meta("part", "skyline (mid ring)")
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
			p.set_meta("part", "skyline (far)")
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
		mi.set_meta("part", "mountains")
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
		cap.set_meta("part", "mountains")
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
		t.set_meta("part", "pine trees")


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
