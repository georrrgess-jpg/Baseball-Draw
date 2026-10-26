extends Node3D
## Card packs: the unopened-pack inventory, the pack shop and the 3D opening experience.
## Opening: the foil pack charges up and shakes, the top tears off in a burst of light,
## the cards rise out and fan into a row face down with an aura in their rarity colour,
## then each card flips when clicked — Epic and Legendary cards tremble first and land
## with light rays, a shockwave, confetti and a banner.
## Multi-open (OPEN ×5 / ×10): the packs fan out into a hand, merge into one glowing pack
## that tears with a bigger burst, and every card is dealt into a PackSummary grid.

const CARD_W := 0.86
const CARD_H := 1.204
const PACK_W := 1.3
const PACK_H := 2.0
const PACK_BULGE := 0.07
const CRIMP_H := 0.13
const PACK_POS := Vector3(0, 1.05, 0)
## How each pack type opens: longer, darker and bigger for the premium packs.
const TIER_FX := {
	"rookie": {"charge": 1.0, "spin": 0.0, "dim": 0.0, "rays": 1.6, "ray_count": 14.0, "arcs": false, "spiral": false, "pulses": 0, "confetti": false, "shake": 0.35, "push": 0.25},
	"pro": {"charge": 1.35, "spin": 0.0, "dim": 0.45, "rays": 2.4, "ray_count": 18.0, "arcs": true, "spiral": false, "pulses": 0, "confetti": false, "shake": 0.55, "push": 0.45},
	"champion": {"charge": 2.0, "spin": 1.0, "dim": 0.75, "rays": 3.4, "ray_count": 24.0, "arcs": false, "spiral": true, "pulses": 3, "confetti": true, "shake": 0.85, "push": 0.65},
	"signature": {"charge": 1.5, "spin": 0.5, "dim": 0.55, "rays": 2.6, "ray_count": 16.0, "arcs": false, "spiral": true, "pulses": 1, "confetti": false, "shake": 0.5, "push": 0.55},
}
const REVEAL_SOUNDS := {"common": "reveal_common", "uncommon": "reveal_common", "rare": "reveal_rare",
	"epic": "reveal_epic", "legendary": "reveal_legendary"}

var stage: Node3D
var camera: Camera3D
var state := "idle"            # idle | opening | reveal | done
var selected := {}             # {"type", "card"} of the pack shown on the stage
var _screen: MenuScreen
var _left: PanelContainer
var _right: PanelContainer
var _inv_box: VBoxContainer
var _shop_box: VBoxContainer
var _action: Button
var _open_multi_btns := {}     # count -> Button (OPEN ×5 / OPEN ×10)
var _buy_buttons := {}         # "type:count" -> Button
var _center: VBoxContainer
var _multi: PackSummary        # the ×5/×10 results grid while it is on screen
var _demo_multi := false       # debug: reveal the multi-open grid by itself
var _flash_type := ""          # pack type whose inventory row flashes after a purchase
var _hint: Label
var _banner: Label
var _flash: ColorRect
var _pack_root: Node3D
var _pack_top: Node3D
var _pack_mats: Array[ShaderMaterial] = []
var _pillow: ArrayMesh
var _crimp_meshes: Array[ArrayMesh] = []
var _stack: Array[Node3D] = []   # extra packs shown fanned out behind the pack for a multi-open
var _crimp_mats: Array[ShaderMaterial] = []
var _art_vp: SubViewport
var _art: PackArt
var _back_vp: SubViewport
var _rays: MeshInstance3D
var _rays_mat: ShaderMaterial
var _env: Environment
var _backdrop_mat: ShaderMaterial
var _spot: SpotLight3D
var _arc_light: OmniLight3D
var _spiral: GPUParticles3D
var _arc_sparks: GPUParticles3D
var _leak: GPUParticles3D
var _burst: GPUParticles3D
var _burst_big: GPUParticles3D
var _confetti: GPUParticles3D
var _burst_light: OmniLight3D
var _cards: Array = []         # {"root", "mesh", "mat", "vp", "view", "aura", "aura_mat", "fx", "data", "revealed", "badge"}
var _result: Dictionary = {}
var _shake := 0.0
var _cam_shake := 0.0
var _charge := 0.0
var _time := 0.0
var _spin := 0.0
var _pulse_amt := 0.0
var _pack_base := 1.0
var _star_tex: Texture2D
var _dot_tex: Texture2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_star_tex = _make_star_texture()
	_dot_tex = _make_dot_texture()
	_build_stage()
	_build_viewports()
	_build_pack()
	_build_ui()
	Profile.packs_changed.connect(_refresh_panels)
	_refresh_panels()
	_select_default()
	Audio.play_music("menu_theme")
	# Debug/screenshot helper: `--pack-demo=<type>` adds a pack, opens it and reveals every card.
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pack-demo="):
			var t := a.split("=")[1]
			var sig := ""
			if t == "signature":   # show a defender in the medallion
				for cid in DB.card_order:
					if str(DB.card(cid).get("linked", "")) == "nova":
						sig = cid
			Profile.add_pack(t, "Demo", sig)
			_show_pack(t, sig)
			_refresh_panels()
			get_tree().create_timer(1.2).timeout.connect(_open_selected)
			get_tree().create_timer(4.6).timeout.connect(_reveal_all)
		# `--pack-demo-multi=<type>:<count>` adds that many packs, opens them all at once and
		# flips every card; `--pack-demo-add=<type>:<count>` only adds them.
		# `--pack-demo-coins=<n>` sets the wallet (shop screenshots).
		elif a.begins_with("--pack-demo-multi=") or a.begins_with("--pack-demo-add="):
			var spec := a.split("=")[1].split(":")
			var n := int(spec[1]) if spec.size() > 1 else Profile.BUNDLE_SIZE
			for i in n:
				Profile.add_pack(spec[0], "Demo")
			_show_pack(spec[0])
			_refresh_panels()
			if a.begins_with("--pack-demo-multi="):
				_demo_multi = true
				get_tree().create_timer(1.2).timeout.connect(_open_multi.bind(n))
		elif a.begins_with("--pack-demo-coins="):
			Profile.data.coins = int(a.split("=")[1])
			Profile.changed.emit()
			_refresh_panels()


# ---------------------------------------------------------------- stage

func _build_stage() -> void:
	stage = Node3D.new()
	add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.05, 0.1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env = env
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	we.environment = env
	stage.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_energy = 1.2
	stage.add_child(key)
	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 4.5, 3.0)
	spot.look_at_from_position(spot.position, PACK_POS, Vector3.UP)
	spot.spot_range = 9.0
	spot.spot_angle = 28.0
	spot.light_energy = 6.0
	spot.light_color = Color(1.0, 0.96, 0.9)
	stage.add_child(spot)
	_spot = spot
	_arc_light = OmniLight3D.new()
	_arc_light.position = PACK_POS + Vector3(0, 0, 1.0)
	_arc_light.omni_range = 5.0
	_arc_light.light_energy = 0.0
	_arc_light.light_color = Color(0.75, 0.45, 1.0)
	stage.add_child(_arc_light)
	for side in [-1.0, 1.0]:
		var rim := OmniLight3D.new()
		rim.position = Vector3(2.6 * side, 2.2, -1.2)
		rim.light_color = Color(0.35, 0.55, 1.0) if side < 0 else Color(1.0, 0.4, 0.35)
		rim.light_energy = 2.5
		rim.omni_range = 6.0
		stage.add_child(rim)
	# Backdrop glow and slowly turning light rays behind the pack.
	var back := _glow_quad(Vector2(14, 9), Color(0.12, 0.25, 0.6), 0.55, 0.0)
	_backdrop_mat = back.material_override
	back.position = Vector3(0, 1.2, -3.5)
	stage.add_child(back)
	_rays = _glow_quad(Vector2(5.5, 5.5), Color(0.5, 0.75, 1.0), 0.35, 1.0)
	_rays_mat = _rays.material_override
	_rays.position = PACK_POS + Vector3(0, 0, -0.6)
	stage.add_child(_rays)
	# Floor with a soft pool of light.
	var floor_mi := MeshInstance3D.new()
	var fp := PlaneMesh.new()
	fp.size = Vector2(30, 30)
	floor_mi.mesh = fp
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.04, 0.06, 0.1)
	fm.roughness = 0.35
	fm.metallic = 0.5
	floor_mi.material_override = fm
	floor_mi.position.y = -0.55
	stage.add_child(floor_mi)
	var pool := _glow_quad(Vector2(4.5, 4.5), Color(0.25, 0.45, 0.9), 0.5, 0.0)
	pool.rotation_degrees.x = -90
	pool.position = Vector3(0, -0.54, 0.2)
	stage.add_child(pool)
	# Ambient dust motes.
	var dust := _particles(60, 6.0, _dot_tex, 0.05, false, 0.0)
	var dm: ParticleProcessMaterial = dust.process_material
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(5, 2.5, 2)
	dm.gravity = Vector3(0, 0.05, 0)
	dm.initial_velocity_min = 0.02
	dm.initial_velocity_max = 0.12
	dm.color = Color(0.6, 0.75, 1.0, 0.35)
	dust.position = Vector3(0, 1.5, -1)
	dust.emitting = true
	stage.add_child(dust)
	# Shared effect systems.
	_leak = _particles(80, 0.9, _star_tex, 0.09, false, 0.0)
	var lm: ParticleProcessMaterial = _leak.process_material
	lm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	lm.emission_box_extents = Vector3(PACK_W * 0.45, 0.02, 0.05)
	lm.direction = Vector3(0, 1, 0)
	lm.spread = 25.0
	lm.initial_velocity_min = 0.6
	lm.initial_velocity_max = 1.6
	lm.gravity = Vector3.ZERO
	_leak.position = PACK_POS + Vector3(0, PACK_H * 0.5, 0.05)
	stage.add_child(_leak)
	_burst = _particles(180, 1.3, _star_tex, 0.11, true, 1.0)
	var bm: ParticleProcessMaterial = _burst.process_material
	bm.direction = Vector3(0, 1, 0.3)
	bm.spread = 180.0
	bm.initial_velocity_min = 2.5
	bm.initial_velocity_max = 6.5
	bm.damping_min = 3.0
	bm.damping_max = 5.0
	bm.gravity = Vector3(0, -1.5, 0)
	_burst.position = PACK_POS + Vector3(0, PACK_H * 0.5, 0.1)
	stage.add_child(_burst)
	# Multi-opens: a second, wider burst on top of the usual one.
	_burst_big = _particles(260, 1.7, _star_tex, 0.13, true, 1.0)
	var bbm: ParticleProcessMaterial = _burst_big.process_material
	bbm.direction = Vector3(0, 1, 0.2)
	bbm.spread = 180.0
	bbm.initial_velocity_min = 4.0
	bbm.initial_velocity_max = 9.0
	bbm.damping_min = 3.5
	bbm.damping_max = 5.5
	bbm.gravity = Vector3(0, -1.0, 0)
	stage.add_child(_burst_big)
	_confetti = _make_confetti()
	stage.add_child(_confetti)
	# Premium packs: sparkles spiralling up around the pack, and electric sparks off its edges.
	_spiral = _particles(120, 1.6, _star_tex, 0.08, false, 0.0)
	var sm: ParticleProcessMaterial = _spiral.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	sm.emission_ring_axis = Vector3(0, 1, 0)
	sm.emission_ring_radius = 1.25
	sm.emission_ring_inner_radius = 1.0
	sm.emission_ring_height = 0.2
	sm.direction = Vector3(0, 1, 0)
	sm.spread = 8.0
	sm.initial_velocity_min = 1.2
	sm.initial_velocity_max = 2.4
	sm.gravity = Vector3.ZERO
	sm.tangential_accel_min = 2.0
	sm.tangential_accel_max = 4.0
	_spiral.position = PACK_POS + Vector3(0, -1.2, 0)
	stage.add_child(_spiral)
	_arc_sparks = _particles(70, 0.35, _star_tex, 0.06, false, 0.0)
	var am: ParticleProcessMaterial = _arc_sparks.process_material
	am.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	am.emission_box_extents = Vector3(PACK_W * 0.55, PACK_H * 0.52, 0.1)
	am.spread = 180.0
	am.initial_velocity_min = 2.0
	am.initial_velocity_max = 4.0
	am.gravity = Vector3.ZERO
	am.color = Color(0.85, 0.6, 1.0)
	_arc_sparks.position = PACK_POS
	stage.add_child(_arc_sparks)
	_burst_light = OmniLight3D.new()
	_burst_light.position = PACK_POS + Vector3(0, PACK_H * 0.5, 0.8)
	_burst_light.omni_range = 7.0
	_burst_light.light_energy = 0.0
	stage.add_child(_burst_light)
	camera = Camera3D.new()
	camera.fov = 36
	camera.position = Vector3(0, 1.15, 6.4)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 1.05, 0), Vector3.UP)


func _glow_quad(sz: Vector2, col: Color, intensity: float, rays: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = sz
	mi.mesh = q
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/packs/glow_rays.gdshader")
	m.set_shader_parameter("color", col)
	m.set_shader_parameter("intensity", intensity)
	m.set_shader_parameter("rays", rays)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _particles(amount: int, lifetime: float, tex: Texture2D, quad: float, one_shot: bool, explosiveness: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(4, int(amount * Settings.particle_scale()))
	p.lifetime = lifetime
	p.one_shot = one_shot
	p.explosiveness = explosiveness
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var curve := CurveTexture.new()
	var c := Curve.new()
	c.add_point(Vector2(0, 0.2))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(1, 0))
	curve.curve = c
	pm.scale_curve = curve
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(quad, quad)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = tex
	m.albedo_color = Color(2.2, 2.2, 2.2)
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	return p


func _make_confetti() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(20, int(160 * Settings.particle_scale()))
	p.lifetime = 3.2
	p.one_shot = true
	p.explosiveness = 0.85
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(3.0, 0.1, 0.5)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 4.5
	pm.gravity = Vector3(0, -3.2, 0)
	pm.damping_min = 0.6
	pm.damping_max = 1.4
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	g.colors = PackedColorArray([Color("#FFD23F"), Color("#FF5A36"), Color("#3FD0FF"), Color("#B45CFF"), Color("#5BD75B")])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.07, 0.11)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.position = Vector3(0, 3.6, 0.6)
	p.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	return p


func _make_star_texture() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x - n * 0.5 + 0.5) / (n * 0.5)
			var v := (y - n * 0.5 + 0.5) / (n * 0.5)
			var r := sqrt(u * u + v * v)
			var core := exp(-r * r * 18.0)
			var cross := exp(-u * u * 260.0) * exp(-absf(v) * 3.2) + exp(-v * v * 260.0) * exp(-absf(u) * 3.2)
			var a := clampf(core + cross * 0.85 + exp(-r * r * 4.0) * 0.25, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_dot_texture() -> Texture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


# ---------------------------------------------------------------- pack model

func _build_viewports() -> void:
	_art_vp = SubViewport.new()
	_art_vp.size = Vector2i(512, 788)
	_art_vp.transparent_bg = false
	_art_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_art_vp)
	_art = PackArt.new()
	_art.size = Vector2(512, 788)
	_art_vp.add_child(_art)
	_back_vp = SubViewport.new()
	_back_vp.size = Vector2i(300, 420)
	_back_vp.transparent_bg = true
	_back_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_back_vp)
	var back := CardView.new()
	back.face_down = true
	back.size = Vector2(300, 420)
	back.position = Vector2.ZERO
	_back_vp.add_child(back)


func _build_pack() -> void:
	_pack_root = Node3D.new()
	_pack_root.position = PACK_POS
	stage.add_child(_pack_root)
	_pillow = _pillow_mesh()
	_crimp_meshes = [_crimp_mesh(-1.0), _crimp_mesh(1.0)]
	var body := MeshInstance3D.new()
	body.mesh = _pillow
	for i in 2:
		var m := ShaderMaterial.new()
		m.shader = preload("res://assets/shaders/packs/pack_foil.gdshader")
		m.set_shader_parameter("art", _art_vp.get_texture())
		m.set_shader_parameter("is_back", float(i))
		body.set_surface_override_material(i, m)
		_pack_mats.append(m)
	_pack_root.add_child(body)
	var bottom := MeshInstance3D.new()
	bottom.mesh = _crimp_meshes[0]
	bottom.material_override = _crimp_material()
	_pack_root.add_child(bottom)
	_pack_top = Node3D.new()
	_pack_root.add_child(_pack_top)
	var top := MeshInstance3D.new()
	top.mesh = _crimp_meshes[1]
	top.material_override = _crimp_material()
	_pack_top.add_child(top)


func _crimp_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://assets/shaders/packs/crimp.gdshader")
	_crimp_mats.append(m)
	return m


## Closed "pillow" pouch: front and back grids that bulge outwards and meet at the rim.
func _pillow_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var nx := 16
	var ny := 22
	for side in [1.0, -1.0]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in ny + 1:
			for i in nx + 1:
				var u := float(i) / nx
				var v := float(j) / ny
				var z: float = PACK_BULGE * pow(sin(PI * u), 0.4) * pow(sin(PI * v), 0.22) * side
				st.set_uv(Vector2(u if side > 0 else 1.0 - u, 1.0 - v))
				st.add_vertex(Vector3((u - 0.5) * PACK_W, (v - 0.5) * PACK_H, z))
		for j in ny:
			for i in nx:
				var a := j * (nx + 1) + i
				var b := a + 1
				var c := a + nx + 2
				var d := a + nx + 1
				if side > 0:
					for k in [a, c, b, a, d, c]:
						st.add_index(k)
				else:
					for k in [a, b, c, a, c, d]:
						st.add_index(k)
		st.generate_normals()
		st.commit(mesh)
	return mesh


## Heat-sealed strip with a saw-tooth edge at the top (dir 1) or bottom (dir -1).
func _crimp_mesh(dir: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var teeth := 26
	var y0 := dir * (PACK_H * 0.5 - 0.03)
	for i in teeth * 2:
		var u0 := float(i) / (teeth * 2)
		var u1 := float(i + 1) / (teeth * 2)
		var x0 := (u0 - 0.5) * PACK_W
		var x1 := (u1 - 0.5) * PACK_W
		var e0 := y0 + dir * (CRIMP_H + (0.03 if i % 2 == 0 else 0.0))
		var e1 := y0 + dir * (CRIMP_H + (0.0 if i % 2 == 0 else 0.03))
		var quad := [Vector3(x0, y0, 0), Vector3(x1, y0, 0), Vector3(x1, e1, 0), Vector3(x0, e0, 0)]
		var uvs := [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(Vector3(0, 0, 1))
			st.set_uv(uvs[k])
			st.add_vertex(quad[k])
	return st.commit()


func _show_pack(type: String, card := "") -> void:
	selected = {"type": type, "card": card}
	_art.set_pack(type, card)
	_art_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var pd := DB.pack(type)
	var foil := Color(str(pd.get("accent", "#9FD3FF")))
	for m in _pack_mats:
		m.set_shader_parameter("foil_color", foil)
		m.set_shader_parameter("charge", 0.0)
		m.set_shader_parameter("brightness", 1.0)
	var back_tex: Texture2D = DB._texture("res://assets/textures/packs/%s_back.png" % type)
	if back_tex and _pack_mats.size() > 1:
		_pack_mats[1].set_shader_parameter("art", back_tex)
		_pack_mats[1].set_shader_parameter("is_back", 0.0)
	for m in _crimp_mats:
		m.set_shader_parameter("color", Color(str(pd.get("color", "#2F7BE0"))).lightened(0.45))
		m.set_shader_parameter("charge", 0.0)
	_rays_mat.set_shader_parameter("color", Color(str(pd.get("color", "#2F7BE0"))).lightened(0.3))
	_rays_mat.set_shader_parameter("intensity", 0.35)
	_pack_root.visible = true
	for sp in _stack:
		sp.visible = false
	_pack_top.position = Vector3.ZERO
	_pack_top.rotation = Vector3.ZERO
	_pack_top.scale = Vector3.ONE
	_pack_top.visible = true
	_pack_base = 1.08 if type == "champion" else 1.0
	_pack_root.scale = Vector3.ONE * _pack_base
	_pack_root.rotation = Vector3.ZERO
	_pack_root.position = PACK_POS + Vector3(0, 3.0, 0)
	var tw := create_tween()
	tw.tween_property(_pack_root, "position", PACK_POS, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_screen = MenuScreen.new()
	layer.add_child(_screen)
	_screen.setup_screen("CARD PACKS", "Open packs to collect new cards. Duplicates become copies that upgrade your cards.")
	for i in 4:
		var c := _screen.get_child(i)
		if c is CanvasItem and not (c is MarginContainer):
			(c as CanvasItem).visible = false
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.content.add_child(body)
	_screen.content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_left = MenuScreen.panel()
	_left.custom_minimum_size = Vector2(390, 0)
	body.add_child(_left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	_left.add_child(lv)
	lv.add_child(UITheme.header("YOUR PACKS", 30, UITheme.GOLD))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(ls)
	_inv_box = VBoxContainer.new()
	_inv_box.add_theme_constant_override("separation", 8)
	_inv_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_inv_box)

	var center := VBoxContainer.new()
	_center = center
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.alignment = BoxContainer.ALIGNMENT_END
	center.add_theme_constant_override("separation", 10)
	body.add_child(center)
	_hint = UITheme.label("", 22, UITheme.OFFWHITE, UITheme.font_body_bold())
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_hint.add_theme_constant_override("outline_size", 6)
	center.add_child(_hint)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 14)
	center.add_child(actions)
	_action = UITheme.menu_button("OPEN PACK", UITheme.SCARLET, 34)
	_action.custom_minimum_size = Vector2(380, 72)
	_action.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_action.pressed.connect(_on_action)
	actions.add_child(_action)
	for n in [5, Profile.BUNDLE_SIZE]:
		var mb := UITheme.menu_button("OPEN ×%d" % n, UITheme.GOLD, 30)
		mb.custom_minimum_size = Vector2(200, 72)
		mb.add_theme_color_override("font_color", UITheme.GOLD.lightened(0.35))
		mb.visible = false
		mb.pressed.connect(_open_multi.bind(n))
		actions.add_child(mb)
		_open_multi_btns[n] = mb

	_right = MenuScreen.panel()
	_right.custom_minimum_size = Vector2(400, 0)
	body.add_child(_right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	_right.add_child(rv)
	rv.add_child(UITheme.header("PACK SHOP", 30, UITheme.GOLD))
	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 10)
	rv.add_child(_shop_box)

	# Let clicks on empty space reach the 3D stage (pack and cards); panels and buttons still catch theirs.
	_pass_through(_screen)

	_banner = Label.new()
	_banner.add_theme_font_override("font", UITheme.font_display())
	_banner.add_theme_font_size_override("font_size", 92)
	_banner.add_theme_constant_override("outline_size", 14)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_banner.offset_left = -600
	_banner.offset_right = 600
	_banner.offset_top = 120
	_banner.offset_bottom = 240
	_banner.pivot_offset = Vector2(600, 60)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0.0
	layer.add_child(_banner)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_flash)


func _pass_through(n: Node) -> void:
	if n is Control and not (n is BaseButton or n is PanelContainer or n is ScrollContainer or n is LineEdit):
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if n is PanelContainer or n is BaseButton:
		return
	for c in n.get_children():
		_pass_through(c)


func _pack_entries() -> Array:
	var entries: Array = []
	var seen := {}
	for i in Profile.data.packs.size():
		var pk: Dictionary = Profile.data.packs[i]
		var key := "%s|%s" % [pk.type, pk.get("card", "")]
		if seen.has(key):
			entries[seen[key]].count += 1
			continue
		seen[key] = entries.size()
		entries.append({"type": pk.type, "card": str(pk.get("card", "")), "count": 1, "source": str(pk.get("source", ""))})
	return entries


func _refresh_panels() -> void:
	for c in _inv_box.get_children():
		c.queue_free()
	var entries := _pack_entries()
	if entries.is_empty():
		var none := UITheme.label("No unopened packs.\n\nEarn packs by finishing games and levelling up, or buy them in the shop.", 20, UITheme.MUTED)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_inv_box.add_child(none)
	for e in entries:
		_inv_box.add_child(_inventory_row(e))
	for c in _shop_box.get_children():
		c.queue_free()
	_buy_buttons.clear()
	for id in DB.pack_order:
		if bool(DB.pack(id).get("for_sale", false)):
			_shop_box.add_child(_shop_row(id))
	_flash_type = ""
	_update_action()


func _inventory_row(e: Dictionary) -> Control:
	var is_sel: bool = selected.get("type", "") == e.type and selected.get("card", "") == e.card
	var p := MenuScreen.panel(Color(0.07, 0.11, 0.18, 0.95) if not is_sel else Color(0.12, 0.2, 0.34, 0.98),
		Color(UITheme.GOLD, 0.8) if is_sel else Color(1, 1, 1, 0.08), 8)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	p.add_child(hb)
	var art := PackArt.new(e.type, e.card)
	art.custom_minimum_size = Vector2(62, 95)
	hb.add_child(art)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	var pd := DB.pack(e.type)
	var name := str(pd.name) if e.card == "" else "%s — %s" % [pd.name, DB.card(e.card).name]
	var nl := UITheme.label(name, 22, UITheme.OFFWHITE, UITheme.font_header())
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(nl)
	vb.add_child(UITheme.label(e.source, 16, UITheme.MUTED))
	var cnt := UITheme.label("×%d" % e.count, 34, Color(str(pd.accent)), UITheme.font_display())
	hb.add_child(cnt)
	if _flash_type == e.type and e.card == "":
		# Just bought: the row lights up and the count pops.
		p.modulate = Color(1.8, 1.7, 1.2)
		var ft := p.create_tween().set_parallel(true)
		ft.tween_property(p, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		cnt.pivot_offset = Vector2(24, 24)
		cnt.scale = Vector2.ONE * 1.6
		ft.tween_property(cnt, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and state == "idle":
			Audio.ui("ui_click")
			_show_pack(e.type, e.card)
			_refresh_panels())
	return p


func _shop_row(id: String) -> Control:
	var pd := DB.pack(id)
	var p := MenuScreen.panel(Color(0.07, 0.11, 0.18, 0.95), Color(str(pd.accent), 0.35), 10)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	p.add_child(outer)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	outer.add_child(hb)
	var art := PackArt.new(id)
	art.custom_minimum_size = Vector2(70, 108)
	hb.add_child(art)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	hb.add_child(vb)
	vb.add_child(UITheme.label(str(pd.name), 24, Color(str(pd.accent)).lightened(0.3), UITheme.font_header()))
	var tl := UITheme.label(str(pd.tagline), 16, UITheme.MUTED)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(tl)
	var buys := HBoxContainer.new()
	buys.add_theme_constant_override("separation", 10)
	outer.add_child(buys)
	buys.add_child(_buy_button(id, 1))
	buys.add_child(_buy_button(id, Profile.BUNDLE_SIZE))
	return p


## BUY / BUY 10 with the price on the button and, underneath, the bundle saving or
## how much more the player needs.
func _buy_button(id: String, count: int) -> Control:
	var pd := DB.pack(id)
	var price := Profile.pack_price(id, count)
	var in_stars := int(price.stars) > 0
	var cost := int(price.stars) if in_stars else int(price.coins)
	var have := int(Profile.data.stars) if in_stars else int(Profile.data.coins)
	var can := Profile.can_buy_pack(id, count)
	var cur_col := Color(0.7, 0.85, 1.0) if in_stars else UITheme.GOLD
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	var b := UITheme.small_button("", UITheme.GOLD if can else UITheme.MUTED, 18)
	b.custom_minimum_size = Vector2(0, 46)
	b.disabled = not can or state != "idle"
	b.tooltip_text = "Buy %d %s%s" % [count, pd.name, "s" if count > 1 else ""]
	box.add_child(b)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not can:
		row.modulate = Color(1, 1, 1, 0.5)
	b.add_child(row)
	var bl := UITheme.label("BUY" if count == 1 else "BUY %d" % count, 19, UITheme.OFFWHITE, UITheme.font_body_bold())
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bl)
	row.add_child(UITheme.icon_rect("star" if in_stars else "coin", 20, cur_col))
	var pl := UITheme.label(UITheme.format_int(cost), 20, cur_col, UITheme.font_header())
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pl)
	var cap := UITheme.label("", 14, UITheme.MUTED, UITheme.font_body_bold())
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.custom_minimum_size = Vector2(0, 18)
	if have < cost:
		cap.text = "Need %s more %s" % [UITheme.format_int(cost - have), "stars" if in_stars else "coins"]
		cap.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	elif count > 1:
		var full := Profile.pack_price(id, 1)
		var saved := (int(full.stars) if in_stars else int(full.coins)) * count - cost
		if saved > 0:
			cap.text = "Save %s" % UITheme.format_int(saved)
			cap.add_theme_color_override("font_color", UITheme.GREEN)
	box.add_child(cap)
	b.pressed.connect(func() -> void:
		if state != "idle" or not Profile.buy_pack(id, count):
			return
		Audio.ui("purchase")
		if count > 1:
			Audio.play("coin", 0.0, 0.0, 0)
			Router.toast("Bought %d %ss!" % [count, pd.name], "info")
		else:
			Router.toast("Bought a %s!" % pd.name, "info")
		_flash_type = id
		_show_pack(id)
		_refresh_panels())
	_buy_buttons["%s:%d" % [id, count]] = b
	return box


func _select_default() -> void:
	var entries := _pack_entries()
	if not entries.is_empty():
		_show_pack(entries[0].type, entries[0].card)
	else:
		_show_pack("rookie")
	_refresh_panels()


func _find_pack_index() -> int:
	for i in Profile.data.packs.size():
		var pk: Dictionary = Profile.data.packs[i]
		if pk.type == selected.get("type", "") and str(pk.get("card", "")) == selected.get("card", ""):
			return i
	return -1


## Unopened packs that match the pack on the stage (type, and card for signature packs).
func _selected_count() -> int:
	var n := 0
	for pk in Profile.data.packs:
		if pk.type == selected.get("type", "") and str(pk.get("card", "")) == selected.get("card", ""):
			n += 1
	return n


func _update_action() -> void:
	if _action == null:
		return
	var owned_n := _selected_count() if state == "idle" else 0
	for n in _open_multi_btns:
		var mb: Button = _open_multi_btns[n]
		mb.visible = owned_n >= int(n)
		mb.disabled = owned_n < int(n)
	match state:
		"idle":
			var owned := _find_pack_index() >= 0
			_action.disabled = not owned
			_action.text = "OPEN PACK" if owned else "NO PACKS TO OPEN"
			if owned:
				_hint.text = "Click the pack (or OPEN PACK) to tear it open!" if int(Profile.data.packs_opened) == 0 else ""
				if owned_n >= 5 and _hint.text == "":
					_hint.text = "%d %ss waiting: open them one by one, or several at once." % [owned_n, DB.pack(str(selected.type)).name]
			else:
				_hint.text = "Earn packs by playing, or buy one in the shop."
		"opening":
			_action.disabled = true
			_action.text = "OPENING..."
			_hint.text = ""
		"reveal":
			_action.disabled = _multi != null and not _multi.dealt
			if _multi:
				_action.text = "SKIP" if _multi.cascading else "REVEAL ALL"
				_hint.text = "Click a card to flip it, or reveal them all."
			else:
				_action.text = "REVEAL ALL"
				_hint.text = "Click a card to flip it."
		"done":
			_action.disabled = false
			if _multi:
				_action.text = "DONE"
				_hint.text = _multi.summary_text()
			else:
				var left := Profile.pack_count()
				_action.text = "OPEN NEXT PACK  (%d)" % left if left > 0 else "DONE"
				_hint.text = _summary_text()


func _summary_text() -> String:
	var new_n := 0
	var copies := 0
	for c in _result.get("cards", []):
		if c.new:
			new_n += 1
		else:
			copies += int(c.copies)
	var parts: Array[String] = []
	if new_n > 0:
		parts.append("%d new card%s" % [new_n, "" if new_n == 1 else "s"])
	if copies > 0:
		parts.append("%d upgrade cop%s" % [copies, "y" if copies == 1 else "ies"])
	return " · ".join(parts)


func _on_action() -> void:
	match state:
		"idle":
			_open_selected()
		"reveal":
			if _multi:
				if not _multi.dealt:
					return
				if _multi.cascading:
					_multi.skip()
				else:
					_multi.reveal_all()
				_update_action()
			else:
				_reveal_all()
		"done":
			if _multi:
				_finish_multi()
			else:
				_finish_reveal()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp: Vector2 = get_viewport().get_mouse_position()
		match state:
			"idle":
				if _find_pack_index() >= 0 and _over_pack(mp):
					_open_selected()
			"reveal":
				var i := _card_at(mp)
				if i >= 0:
					_flip(i)
	elif event.is_action_pressed("start_wave") or event.is_action_pressed("confirm"):
		_on_action()
		get_viewport().set_input_as_handled()


func _over_pack(mp: Vector2) -> bool:
	var a := camera.unproject_position(_pack_root.global_position + Vector3(-PACK_W * 0.6, -PACK_H * 0.6, 0))
	var b := camera.unproject_position(_pack_root.global_position + Vector3(PACK_W * 0.6, PACK_H * 0.6, 0))
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs()).has_point(mp)


func _card_at(mp: Vector2) -> int:
	for i in _cards.size():
		var root: Node3D = _cards[i].root
		var a := camera.unproject_position(root.global_position + Vector3(-CARD_W * 0.5, -CARD_H * 0.5, 0))
		var b := camera.unproject_position(root.global_position + Vector3(CARD_W * 0.5, CARD_H * 0.5, 0))
		if Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs()).has_point(mp):
			return i
	return -1


func _set_panels_visible(on: bool) -> void:
	for p in [_left, _right]:
		var tw := create_tween()
		if on:
			p.visible = true
			tw.tween_property(p, "modulate:a", 1.0, 0.25)
		else:
			tw.tween_property(p, "modulate:a", 0.0, 0.2)
			tw.tween_callback(func() -> void: p.visible = false)


# ---------------------------------------------------------------- opening

func _open_selected() -> void:
	var idx := _find_pack_index()
	if idx < 0 or state != "idle":
		return
	_result = Profile.open_pack(idx)
	if _result.is_empty():
		return
	state = "opening"
	_update_action()
	_set_panels_visible(false)
	var best := "common"
	for c in _result.cards:
		if DB.rarity_index(c.rarity) > DB.rarity_index(best):
			best = c.rarity
	var best_col := DB.rarity_color(best)
	var pd := DB.pack(str(_result.type))
	var accent := Color(str(pd.accent))
	_create_cards()
	var fx: Dictionary = TIER_FX.get(str(_result.type), TIER_FX.rookie)
	var charge := float(fx.charge)
	_charge_fx(fx, accent, charge)
	var tw := create_tween()
	tw.tween_method(_set_charge, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "_shake", 1.0, charge)
	tw.parallel().tween_property(_pack_root, "position", PACK_POS + Vector3(0, 0.15 + 0.2 * float(fx.spin), 0.7), charge).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(camera, "position:z", 6.4 - float(fx.push), charge).set_trans(Tween.TRANS_SINE)
	if float(fx.spin) > 0.0:
		_spin = 0.0
		tw.parallel().tween_property(self, "_spin", TAU * float(fx.spin), charge * 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(_tear.bind(best, best_col, fx))
	tw.tween_interval(0.25)
	tw.tween_callback(_rise_cards)
	tw.tween_interval(0.55)
	tw.tween_callback(_drop_pack)
	tw.tween_interval(0.25)
	tw.tween_callback(_fan_cards)
	tw.parallel().tween_property(camera, "position:z", 6.4, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.75)
	tw.tween_callback(func() -> void:
		_spiral.emitting = false
		_arc_sparks.emitting = false
		state = "reveal"
		_update_action()
		if _cards.size() == 1:
			_flip(0))


## The tier's charge-up effects: light leaking from the seal, stage dimming, spiral
## sparkles, electric arcs and heartbeat pulses, spread over `charge` seconds.
func _charge_fx(fx: Dictionary, accent: Color, charge: float) -> void:
	Audio.play("pack_shake", 0.0, 0.0, 0)
	(_leak.process_material as ParticleProcessMaterial).color = Color(accent.lightened(0.3), 1.0)
	_leak.emitting = true
	_set_stage_dim(float(fx.dim), 0.5, accent)
	if bool(fx.spiral):
		(_spiral.process_material as ParticleProcessMaterial).color = Color(accent.lightened(0.4), 1.0)
		_spiral.emitting = true
	if bool(fx.arcs):
		_arc_sparks.emitting = true
		for i in int(charge * 7.0):
			get_tree().create_timer(0.12 + i * charge / (charge * 7.0) + _rng.randf_range(0.0, 0.08)).timeout.connect(_arc_flicker)
	for i in int(fx.pulses):
		get_tree().create_timer(charge * (0.35 + 0.6 * float(i) / maxf(1.0, float(fx.pulses)))).timeout.connect(_pulse.bind(accent))


# ---------------------------------------------------------------- multi-open

## Opens `n` packs like the one on the stage at once: one charge-up for the whole hand,
## then every card goes into a PackSummary grid.
func _open_multi(n: int) -> void:
	if state != "idle" or _selected_count() < n:
		return
	var type := str(selected.get("type", "rookie"))
	_result = Profile.open_packs(type, n, str(selected.get("card", "")))
	if _result.is_empty():
		return
	state = "opening"
	_update_action()
	_set_panels_visible(false)
	var best := "common"
	for c in _result.cards:
		if DB.rarity_index(c.rarity) > DB.rarity_index(best):
			best = c.rarity
	var best_col := DB.rarity_color(best)
	var accent := Color(str(DB.pack(type).accent))
	# A bigger version of the tier's effects: longer charge, more rays, always confetti.
	var fx: Dictionary = TIER_FX.get(type, TIER_FX.rookie).duplicate()
	fx.rays = float(fx.rays) + 0.9
	fx.ray_count = float(fx.ray_count) + 8.0
	fx.shake = float(fx.shake) + 0.25
	fx.confetti = true
	fx.pulses = maxi(int(fx.pulses), 1)
	var charge := float(fx.charge) + 0.7
	var spread := _fan_stack(n - 1)
	Audio.play("card_whoosh", 0.0, 0.0, 0)
	var tw := create_tween()
	tw.tween_interval(spread)
	tw.tween_callback(_charge_fx.bind(fx, accent, charge))
	tw.tween_method(_set_charge, 0.0, 1.0, charge).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "_shake", 1.0, charge)
	tw.parallel().tween_property(_pack_root, "position", PACK_POS + Vector3(0, 0.15 + 0.2 * float(fx.spin), 0.7), charge).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(camera, "position:z", 6.4 - float(fx.push) - 0.2, charge).set_trans(Tween.TRANS_SINE)
	if float(fx.spin) > 0.0:
		_spin = 0.0
		tw.parallel().tween_property(self, "_spin", TAU * float(fx.spin), charge * 0.85).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# The fanned packs fly into the front one during the charge; it swells with each.
	var k := _stack.filter(func(sp: Node3D) -> bool: return sp.visible).size()
	for i in k:
		get_tree().create_timer(spread + charge * (0.08 + 0.72 * float(i) / maxf(1.0, k))).timeout.connect(_merge_stack_pack.bind(i, k))
	tw.tween_callback(_tear.bind(best, best_col, fx))
	tw.tween_callback(_big_burst.bind(accent))
	tw.tween_interval(0.35)
	tw.tween_callback(_drop_pack)
	tw.tween_interval(0.15)
	tw.tween_callback(_show_multi_summary)
	tw.parallel().tween_property(camera, "position:z", 6.4, 0.8).set_trans(Tween.TRANS_SINE)


## Shows `k` (up to 9) extra packs fanned out like a hand behind the front pack.
## Returns how long the fan takes to open.
func _fan_stack(k: int) -> float:
	k = clampi(k, 0, 9)
	while _stack.size() < k:
		var sp := Node3D.new()
		var body := MeshInstance3D.new()
		body.mesh = _pillow
		for i in 2:
			body.set_surface_override_material(i, _pack_mats[i])
		sp.add_child(body)
		var cm := _crimp_material()
		for cmesh in _crimp_meshes:
			var cr := MeshInstance3D.new()
			cr.mesh = cmesh
			cr.material_override = cm
			sp.add_child(cr)
		sp.visible = false
		stage.add_child(sp)
		_stack.append(sp)
	var col := Color(str(DB.pack(str(selected.get("type", "rookie"))).get("color", "#2F7BE0"))).lightened(0.45)
	for m in _crimp_mats:
		m.set_shader_parameter("color", col)
	var spread := 0.0
	for i in k:
		var sp: Node3D = _stack[i]
		# Spread the hand evenly on both sides, outermost packs furthest back.
		var t := (float(i) / maxf(1.0, k - 1) - 0.5) * 2.0 if k > 1 else 1.0
		var ang := t * clampf(0.09 * k, 0.18, 0.62)
		var pivot := PACK_POS + Vector3(0, -2.3, 0)
		var target := pivot + Vector3(sin(ang) * 2.45, cos(ang) * 2.45, -0.12 - 0.04 * absf(t) * k)
		sp.position = PACK_POS + Vector3(0, 0, -0.1)
		sp.rotation = Vector3.ZERO
		sp.scale = Vector3.ONE * _pack_base * 0.96
		sp.visible = true
		sp.set_meta("fan_pos", target)
		sp.set_meta("fan_rot", Vector3(0, 0, -ang))
		var d := 0.03 * i
		var tw := create_tween().set_parallel(true)
		tw.tween_property(sp, "position", target, 0.45).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "rotation", Vector3(0, 0, -ang), 0.45).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		spread = d + 0.5
	return spread


## One fanned pack flies into the front pack: the merge order runs from the outside in.
func _merge_stack_pack(i: int, k: int) -> void:
	if state != "opening":
		return
	var order: Array[int] = []
	for j in k:
		order.append(j)
	order.sort_custom(func(a: int, b: int) -> bool: return absf(a - (k - 1) * 0.5) > absf(b - (k - 1) * 0.5))
	var sp: Node3D = _stack[order[i]]
	var from: Vector3 = sp.get_meta("fan_pos", sp.position)
	var from_rot: Vector3 = sp.get_meta("fan_rot", sp.rotation)
	var s0 := sp.scale.x
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void:
		sp.position = from.lerp(_pack_root.position + Vector3(0, 0, -0.06), v)
		sp.rotation = from_rot.lerp(Vector3.ZERO, v)   # flat, not the front pack's spin
		sp.scale = Vector3.ONE * lerpf(s0, _pack_root.scale.x * 0.85, v), 0.0, 1.0, 0.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		sp.visible = false
		if state != "opening":
			return
		Audio.play("card_flip", -2.0, 0.1, 0)
		_pack_base += 0.2 / maxf(1.0, k)
		_pulse_amt = 0.06
		var pt := create_tween()
		pt.tween_property(self, "_pulse_amt", 0.0, 0.2)
		_flash_screen(Color(Color(str(DB.pack(str(selected.get("type", "rookie"))).accent)).lightened(0.5), 0.1), 0.15))


## Multi-opens: an extra wide burst and a second flash right after the tear.
func _big_burst(col: Color) -> void:
	var bm: ParticleProcessMaterial = _burst_big.process_material
	bm.color = Color(col.lightened(0.45), 1.0)
	_burst_big.global_position = _pack_root.global_position + Vector3(0, PACK_H * 0.45, 0.1)
	_burst_big.restart()
	_burst_big.emitting = true
	_cam_shake = maxf(_cam_shake, 0.7)
	var ft := create_tween()
	ft.tween_interval(0.12)
	ft.tween_callback(_flash_screen.bind(Color(col.lightened(0.7), 0.45), 0.5))


func _show_multi_summary() -> void:
	_spiral.emitting = false
	_arc_sparks.emitting = false
	_multi = PackSummary.new()
	_multi.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_multi.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.add_child(_multi)
	_center.move_child(_multi, 0)
	_multi.setup(_result, _star_tex)
	_multi.revealed.connect(_on_multi_revealed)
	_multi.all_revealed.connect(_on_multi_done)
	_multi.deal_finished.connect(func() -> void:
		if state != "opening":
			return
		state = "reveal"
		_update_action()
		if _demo_multi:
			_multi.reveal_all()
			_update_action())
	_multi.deal(camera.unproject_position(PACK_POS + Vector3(0, 0.35, 0.7)))


func _on_multi_revealed(rarity: String, _at: Vector2) -> void:
	var r := DB.rarity_index(rarity)
	var col := DB.rarity_color(rarity)
	if r >= 2:
		Audio.play(REVEAL_SOUNDS.get(rarity, "reveal_rare"), 0.0 if r >= 3 else -4.0, 0.0, 0 if r >= 3 else 60)
	else:
		Audio.play("reveal_common", -10.0, 0.08, 90)
	if r >= 3:
		_cam_shake = 0.3 if r == 3 else 0.6
		_banner_pop(rarity.to_upper() + "!", col)
		_rays_mat.set_shader_parameter("color", col)
		var rt := create_tween()
		rt.tween_method(func(v: float) -> void: _rays_mat.set_shader_parameter("intensity", v), 1.6 + 0.6 * (r - 3), 0.5, 1.2)
	if r >= 4:
		_flash_screen(Color(1.0, 0.92, 0.6, 0.55), 0.6)
		_confetti.restart()
		_confetti.emitting = true
		Audio.play("crowd_cheer", -6.0, 0.0, 0)


func _on_multi_done() -> void:
	if state != "reveal":
		return
	state = "done"
	_update_action()


func _finish_multi() -> void:
	state = "opening"
	_update_action()
	if _multi:
		_multi.outro()
		_multi = null
	_set_stage_dim(0.0, 0.6)
	_rays_mat.set_shader_parameter("ray_count", 14.0)
	var done := create_tween()
	done.tween_interval(0.45)
	done.tween_callback(_return_to_idle)


## Darkens the stage (premium packs open under a spotlight); 0 restores it.
func _set_stage_dim(amount: float, time: float, tint := Color.WHITE) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_env, "background_color", Color(0.03, 0.05, 0.1).lerp(Color(0.0, 0.0, 0.01), amount), time)
	tw.tween_property(_env, "ambient_light_energy", lerpf(0.55, 0.2, amount), time)
	tw.tween_property(_spot, "light_energy", lerpf(6.0, 9.0, amount), time)
	tw.tween_method(func(v: float) -> void: _backdrop_mat.set_shader_parameter("intensity", v), lerpf(0.55, 0.55, 0.0), lerpf(0.55, 0.12, amount), time)
	_spot.light_color = Color(1.0, 0.96, 0.9).lerp(tint.lightened(0.3), amount * 0.5)


## Pro packs: a crackle of electricity around the pack.
func _arc_flicker() -> void:
	if state != "opening":
		return
	Audio.play("lightning_zap", -10.0, 0.15, 40)
	var tw := create_tween()
	tw.tween_property(_arc_light, "light_energy", _rng.randf_range(4.0, 8.0), 0.03)
	tw.tween_property(_arc_light, "light_energy", 0.0, 0.12)
	_flash_screen(Color(0.75, 0.5, 1.0, 0.08), 0.12)


## Champion/Signature packs: a heartbeat pulse with a ring shockwave.
func _pulse(col: Color) -> void:
	if state != "opening":
		return
	Audio.play("earth_rumble", -6.0, 0.0, 0)
	_cam_shake = maxf(_cam_shake, 0.2)
	var sw := _glow_quad(Vector2(5, 5), col.lightened(0.3), 1.2, 0.0)
	sw.position = _pack_root.position + Vector3(0, 0, -0.1)
	var m: ShaderMaterial = sw.material_override
	stage.add_child(sw)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: m.set_shader_parameter("ring_radius", v), 0.2, 0.95, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sw.queue_free)
	_pulse_amt = 0.09
	var pt := create_tween()
	pt.tween_property(self, "_pulse_amt", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_charge(v: float) -> void:
	_charge = v
	for m in _pack_mats:
		m.set_shader_parameter("charge", v)
	for m in _crimp_mats:
		m.set_shader_parameter("charge", v * 0.6)


func _tear(best: String, best_col: Color, fx: Dictionary = {}) -> void:
	_shake = 0.0
	_leak.emitting = false
	_spiral.emitting = false
	_arc_sparks.emitting = false
	Audio.play("pack_tear", 2.0, 0.0, 0)
	_cam_shake = float(fx.get("shake", 0.35)) + 0.12 * DB.rarity_index(best)
	_rays_mat.set_shader_parameter("ray_count", float(fx.get("ray_count", 14.0)))
	if bool(fx.get("confetti", false)):
		_confetti.restart()
		_confetti.emitting = true
		Audio.play("crowd_cheer", -6.0, 0.0, 0)
	var bm: ParticleProcessMaterial = _burst.process_material
	bm.color = Color(best_col.lightened(0.35), 1.0)
	_burst.global_position = _pack_root.global_position + Vector3(0, PACK_H * 0.5, 0.1)
	_burst.restart()
	_burst.emitting = true
	_burst_light.light_color = best_col.lightened(0.2)
	_burst_light.global_position = _pack_root.global_position + Vector3(0, PACK_H * 0.55, 0.9)
	var lt := create_tween()
	lt.tween_property(_burst_light, "light_energy", 9.0, 0.06)
	lt.tween_property(_burst_light, "light_energy", 0.0, 0.8)
	_rays_mat.set_shader_parameter("color", best_col.lightened(0.15))
	var rt := create_tween()
	rt.tween_method(func(v: float) -> void: _rays_mat.set_shader_parameter("intensity", v), 0.35, float(fx.get("rays", 1.6)) + 0.3 * DB.rarity_index(best), 0.25)
	_flash_screen(Color(best_col.lightened(0.6), 0.35), 0.35)
	# The sealed top flies off with a spin.
	var tt := create_tween()
	tt.set_parallel(true)
	tt.tween_property(_pack_top, "position", Vector3(1.9, 2.4, 0.6), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tt.tween_property(_pack_top, "rotation", Vector3(0.6, 1.2, -2.6), 0.6)
	tt.tween_property(_pack_top, "scale", Vector3.ONE * 0.6, 0.6)
	tt.chain().tween_callback(func() -> void: _pack_top.visible = false)


func _create_cards() -> void:
	for c in _cards:
		c.root.queue_free()
		c.vp.queue_free()
	_cards.clear()
	var n: int = _result.cards.size()
	for i in n:
		var cd: Dictionary = _result.cards[i]
		var vp := SubViewport.new()
		vp.size = Vector2i(300, 420)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var view := CardView.new()
		view.set_card(cd.id, Profile.card_level(cd.id))
		view.size = Vector2(300, 420)
		vp.add_child(view)
		var root := Node3D.new()
		stage.add_child(root)
		var col := DB.rarity_color(cd.rarity)
		var r_idx := DB.rarity_index(cd.rarity)
		var aura := _glow_quad(Vector2(CARD_W * 2.2, CARD_H * 1.9), col, 0.0, 0.8 if r_idx >= 3 else 0.0)
		aura.position = Vector3(0, 0, -0.08)
		root.add_child(aura)
		var mesh := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(CARD_W, CARD_H)
		mesh.mesh = q
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://assets/shaders/packs/card3d.gdshader")
		mat.set_shader_parameter("front_tex", vp.get_texture())
		mat.set_shader_parameter("back_tex", _back_vp.get_texture())
		mat.set_shader_parameter("glow_color", col)
		mesh.material_override = mat
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.rotation.y = PI
		root.add_child(mesh)
		var fx := _particles(90 + 50 * r_idx, 1.1, _star_tex, 0.08 + 0.015 * r_idx, true, 1.0)
		var fm: ParticleProcessMaterial = fx.process_material
		fm.spread = 180.0
		fm.initial_velocity_min = 1.2 + 0.4 * r_idx
		fm.initial_velocity_max = 2.6 + 0.9 * r_idx
		fm.damping_min = 2.0
		fm.damping_max = 3.5
		fm.gravity = Vector3(0, -0.6, 0)
		fm.color = Color(col.lightened(0.3), 1.0)
		fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		fm.emission_box_extents = Vector3(CARD_W * 0.45, CARD_H * 0.45, 0.02)
		root.add_child(fx)
		root.position = _pack_root.position + Vector3(0, -0.1, 0.02 - 0.01 * i)
		root.scale = Vector3.ONE * 0.95
		root.visible = false
		_cards.append({"root": root, "mesh": mesh, "mat": mat, "vp": vp, "view": view, "aura": aura,
			"aura_mat": aura.material_override, "fx": fx, "data": cd, "revealed": false, "badge": null})


func _rise_cards() -> void:
	Audio.play("card_whoosh", 0.0, 0.0, 0)
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		c.root.visible = true
		var tw := create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(c.root, "position", _pack_root.position + Vector3(0, 0.72 + 0.04 * i, 0.15 + 0.02 * i), 0.5) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _drop_pack() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_pack_root, "position", _pack_root.position + Vector3(0, -3.2, -0.6), 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(_pack_root, "rotation", Vector3(-0.5, 0.4, 0.2), 0.55)
	tw.tween_method(func(v: float) -> void:
		for m in _pack_mats:
			m.set_shader_parameter("brightness", v), 1.0, 0.2, 0.55)
	tw.chain().tween_callback(func() -> void:
		_pack_root.visible = false
		_set_charge(0.0))
	var rt := create_tween()
	rt.tween_method(func(v: float) -> void: _rays_mat.set_shader_parameter("intensity", v), 1.6, 0.45, 0.8)


func _row_position(i: int, n: int) -> Vector3:
	var spacing := 1.08 if n >= 5 else 1.2
	var t := float(i) - (n - 1) * 0.5
	return Vector3(t * spacing, 1.05 - absf(t) * 0.05, 0.5 + (0.0 if n == 1 else -absf(t) * 0.04))


func _fan_cards() -> void:
	var n := _cards.size()
	Audio.play("card_whoosh", -2.0, 0.0, 0)
	for i in n:
		var c: Dictionary = _cards[i]
		var target := _row_position(i, n)
		var tw := create_tween()
		tw.tween_interval(0.06 * i)
		tw.set_parallel(true)
		tw.tween_property(c.root, "position", target, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(c.root, "rotation", Vector3(0, 0, -(float(i) - (n - 1) * 0.5) * 0.03), 0.55)
		tw.tween_property(c.root, "scale", Vector3.ONE * (1.25 if n == 1 else 1.0), 0.55)
		# Aura hints at rarity before the flip.
		var r_idx := DB.rarity_index(c.data.rarity)
		tw.tween_method(func(v: float) -> void: c.aura_mat.set_shader_parameter("intensity", v), 0.0, 0.2 + 0.16 * r_idx, 0.6)


func _flip(i: int) -> void:
	var c: Dictionary = _cards[i]
	if c.revealed:
		return
	c.revealed = true
	var r_idx := DB.rarity_index(c.data.rarity)
	var tw := create_tween()
	if r_idx >= 3:
		# Anticipation: the card trembles and glows before turning.
		var tremble := 0.45 if r_idx == 3 else 0.8
		tw.tween_method(func(v: float) -> void:
			c.mesh.position = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0) * 0.025 * v
			c.mat.set_shader_parameter("glow", v)
			c.aura_mat.set_shader_parameter("intensity", 0.9 + v * 1.4), 0.0, 1.0, tremble)
		tw.tween_callback(func() -> void: c.mesh.position = Vector3.ZERO)
	Audio.play("card_flip", 0.0, 0.05, 0)
	tw.set_parallel(true)
	tw.tween_property(c.mesh, "rotation:y", 0.0, 0.42 if r_idx < 3 else 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c.root, "scale", c.root.scale * 1.16, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(c.root, "scale", c.root.scale, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_callback(_reveal_fx.bind(i)).set_delay(0.0)
	tw.chain().tween_callback(func() -> void:
		c["face_up"] = true   # "revealed" is set when the flip starts (an Epic trembles first)
		_check_done())


func _reveal_fx(i: int) -> void:
	var c: Dictionary = _cards[i]
	var rarity: String = c.data.rarity
	var r_idx := DB.rarity_index(rarity)
	var col := DB.rarity_color(rarity)
	Audio.play(REVEAL_SOUNDS.get(rarity, "reveal_common"), 0.0, 0.0, 0)
	c.fx.restart()
	c.fx.emitting = true
	var aura_to: float = [0.22, 0.34, 0.55, 0.85, 1.25][r_idx]
	var at := create_tween()
	at.tween_method(func(v: float) -> void:
		c.aura_mat.set_shader_parameter("intensity", v)
		c.mat.set_shader_parameter("glow", maxf(0.0, (v - aura_to) / 2.0)), aura_to + 1.5, aura_to, 0.7)
	if r_idx >= 2:
		var sw := _glow_quad(Vector2(CARD_H * 3.2, CARD_H * 3.2), col.lightened(0.2), 1.4, 0.0)
		sw.position = c.root.position + Vector3(0, 0, -0.04)
		var swm: ShaderMaterial = sw.material_override
		stage.add_child(sw)
		var st := create_tween()
		st.tween_method(func(v: float) -> void: swm.set_shader_parameter("ring_radius", v), 0.15, 0.95, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		st.tween_callback(sw.queue_free)
	if r_idx >= 3:
		_cam_shake = 0.25 if r_idx == 3 else 0.55
		_banner_pop(rarity.to_upper() + "!", col)
	if r_idx >= 4:
		_flash_screen(Color(1.0, 0.92, 0.6, 0.6), 0.6)
		_confetti.restart()
		_confetti.emitting = true
		_rays_mat.set_shader_parameter("color", col)
		var rt := create_tween()
		rt.tween_method(func(v: float) -> void: _rays_mat.set_shader_parameter("intensity", v), 2.2, 0.5, 1.6)
	_add_badge(i)


func _add_badge(i: int) -> void:
	var c: Dictionary = _cards[i]
	var cd: Dictionary = c.data
	var lab := Label3D.new()
	lab.font = UITheme.font_display()
	lab.font_size = 64
	lab.outline_size = 14
	lab.pixel_size = 0.0032
	lab.outline_modulate = Color(0, 0, 0, 0.9)
	if cd.new:
		lab.text = "NEW!"
		lab.modulate = UITheme.GOLD
	else:
		lab.text = "+%d COP%s" % [int(cd.copies), "Y" if int(cd.copies) == 1 else "IES"]
		lab.modulate = Color(0.75, 0.9, 1.0)
		if Profile.can_upgrade_card(cd.id):
			lab.text = "UPGRADE READY"
			lab.modulate = UITheme.GREEN
	lab.position = Vector3(0, -CARD_H * 0.5 - 0.2, 0.05)
	lab.scale = Vector3.ONE * 0.2
	c.root.add_child(lab)
	c.badge = lab
	var tw := create_tween()
	tw.tween_property(lab, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _check_done() -> void:
	if state != "reveal":
		return
	for c in _cards:
		if not c.get("face_up", false):
			return
	state = "done"
	_update_action()


func _reveal_all() -> void:
	var delay := 0.0
	for i in _cards.size():
		if _cards[i].revealed:
			continue
		get_tree().create_timer(delay).timeout.connect(_flip.bind(i))
		delay += 0.3 if DB.rarity_index(_cards[i].data.rarity) < 3 else 0.9


func _finish_reveal() -> void:
	state = "opening"
	_update_action()
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var tw := create_tween()
		tw.tween_interval(0.04 * i)
		tw.set_parallel(true)
		tw.tween_property(c.root, "position", c.root.position + Vector3(0, -2.8, 0.4), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_property(c.root, "rotation:z", c.root.rotation.z + 0.4 * (1 if i % 2 == 0 else -1), 0.45)
		tw.chain().tween_callback(func() -> void:
			c.root.queue_free()
			c.vp.queue_free())
	_set_stage_dim(0.0, 0.6)
	_rays_mat.set_shader_parameter("ray_count", 14.0)
	var done := create_tween()
	done.tween_interval(0.6)
	done.tween_callback(_return_to_idle)


## Back to browsing: panels return and the stage shows the same kind of pack if any are
## left, else the first unopened pack (or a Rookie Pack to look at).
func _return_to_idle() -> void:
	_cards.clear()
	_result = {}
	state = "idle"
	_rays_mat.set_shader_parameter("intensity", 0.35)
	_set_panels_visible(true)
	var entries := _pack_entries()
	var same := entries.filter(func(e: Dictionary) -> bool: return e.type == selected.get("type", "") and e.card == selected.get("card", ""))
	if not same.is_empty():
		_show_pack(same[0].type, same[0].card)
	elif not entries.is_empty():
		_show_pack(entries[0].type, entries[0].card)
	else:
		_show_pack("rookie")
	_refresh_panels()


# ---------------------------------------------------------------- feedback

func _banner_pop(text: String, col: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", col.lightened(0.25))
	_banner.scale = Vector2.ONE * 0.4
	_banner.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.4)


func _flash_screen(col: Color, time: float) -> void:
	_flash.color = col
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, time)


func _process(delta: float) -> void:
	_time += delta
	if _pack_root and _pack_root.visible:
		if state == "idle":
			var mp := get_viewport().get_mouse_position()
			var vs := get_viewport().get_visible_rect().size
			var tilt := (mp / vs - Vector2(0.5, 0.5))
			_pack_root.rotation.y = lerpf(_pack_root.rotation.y, sin(_time * 0.6) * 0.22 + tilt.x * 0.35, delta * 4.0)
			_pack_root.rotation.x = lerpf(_pack_root.rotation.x, tilt.y * 0.2, delta * 4.0)
			_pack_root.position.y = lerpf(_pack_root.position.y, PACK_POS.y + sin(_time * 1.6) * 0.04, delta * 3.0)
		elif state == "opening" and _shake > 0.0:
			var a := _shake * _shake
			_pack_root.rotation = Vector3(_rng.randf_range(-1, 1) * 0.03, _rng.randf_range(-1, 1) * 0.05, _rng.randf_range(-1, 1) * 0.06) * a
			_pack_root.rotation.y += _spin
			_pack_root.scale = Vector3.ONE * _pack_base * (1.0 + 0.04 * a + sin(_time * 40.0) * 0.012 * a + _pulse_amt)
	# Gentle hover sway of revealed cards.
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		if state in ["reveal", "done"] and c.revealed:
			c.mesh.rotation.x = sin(_time * 1.3 + i) * 0.04
	if _cam_shake > 0.0:
		_cam_shake = maxf(0.0, _cam_shake - delta * 1.4)
		camera.h_offset = _rng.randf_range(-1, 1) * 0.06 * _cam_shake
		camera.v_offset = _rng.randf_range(-1, 1) * 0.06 * _cam_shake
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
