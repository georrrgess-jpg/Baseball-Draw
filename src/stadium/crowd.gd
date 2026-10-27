class_name StadiumCrowd
extends Node3D
## The crowd: low-poly fans (head, torso, arms, legs; caps, hair and foam fingers as variants)
## drawn with one MultiMesh per grandstand and animated entirely in assets/shaders/crowd.gdshader.
## All stands share one ShaderMaterial, so a reaction is a handful of uniform writes per frame.
##
## Reactions: cheer() (arms up, jumping), groan() (hands on heads), stand_up() (standing ovation),
## start_wave() (the wave travels once around the stadium), plus the continuous excitement level
## (idle sway -> clapping and bouncing).

const SHOULDER := Vector3(0.215, 0.86, 0.0)
const STAND_OFFSET := Vector3(0.0, 0.42, 0.08)
## Grandstand seat grid (matches tools/blender/props/props_hero.py grandstand()).
const ROWS := 10
const SEATS := 20

static var _fan_mesh: ArrayMesh
static var _fan_mesh_low: ArrayMesh
static var _shader: Shader

var material: ShaderMaterial
## Extra materials driven by the same reactions (dugout players); meta "force_stand" keeps some standing.
var extra_materials: Array[ShaderMaterial] = []
var excitement := 0.2
var _cheer := 0.0
var _cheer_hold := 0.0
var _groan := 0.0
var _groan_hold := 0.0
var _stand := 0.0
var _stand_hold := 0.0
var _wave_t := -1.0
var _wave_dir := 1.0
var fan_count := 0


static func shader() -> Shader:
	if _shader == null:
		_shader = load("res://assets/shaders/crowd.gdshader")
	return _shader


func setup(theme: Dictionary) -> void:
	material = make_material(theme)
	set_process(true)


## Material for dugout players in uniform: jersey from the instance colour, cap and pants fixed.
func make_bench_material(cap: Color, pants: Color, standing: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	m.set_shader_parameter("uniform_mode", 1.0)
	m.set_shader_parameter("cap_a", _v3(cap))
	m.set_shader_parameter("pants_uniform", _v3(pants))
	m.set_shader_parameter("time_offset", randf() * 10.0)
	if standing:
		m.set_meta("force_stand", 1.0)
		m.set_shader_parameter("stand", 1.0)
	extra_materials.append(m)
	return m


static func make_material(theme: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	var cols: Array = theme.get("crowd", ["#1c2e4a", "#d7262e"])
	m.set_shader_parameter("cap_a", _v3(Color(cols[0])))
	m.set_shader_parameter("cap_b", _v3(Color(cols[1 % cols.size()])))
	m.set_shader_parameter("finger_color", _v3(Color(theme.get("accent", "#ffc83d")).lightened(0.1)))
	return m


static func _v3(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)


# ---------------------------------------------------------------- mesh

## One seated fan, origin on the row floor under the seat, facing +Z. Standing-pose positions
## go into CUSTOM0 so the shader can blend between sitting and standing.
## `low` builds a lighter version (about 60 % of the triangles) for the Low crowd setting.
static func fan_mesh(low := false) -> ArrayMesh:
	if low and _fan_mesh_low:
		return _fan_mesh_low
	if not low and _fan_mesh:
		return _fan_mesh
	var seg := 5 if low else 7
	var k := MeshKit.new(true)
	var off := STAND_OFFSET
	k.stand_offset = off
	# Torso (shirt).
	_part(k, 0, 0, 1.0)
	k.prism(Vector3(0, 0, -0.03), 0.44, 0.9, Vector2(0.165, 0.115), Vector2(0.215, 0.13), 6, true)
	if not low:
		# Collar / neck (skin).
		_part(k, 0, 1, 0.9)
		k.prism(Vector3(0, 0, -0.02), 0.88, 0.96, Vector2(0.06, 0.06), Vector2(0.055, 0.055), 5, false)
	# Head (skin).
	_part(k, 1, 1, 1.0)
	k.sphere(Vector3(0, 1.06, 0.0), Vector3(0.135, 0.15, 0.135), seg, 3 if low else 4)
	if not low:
		# Nose / face accent so heads read as facing the field.
		_part(k, 1, 1, 0.82)
		k.box(Vector3(0, 1.04, 0.13), Vector3(0.05, 0.05, 0.04))
	# Hair (variant).
	_part(k, 6, 4, 1.0)
	k.sphere(Vector3(0, 1.075, -0.012), Vector3(0.145, 0.15, 0.145), seg, 4, 0.5)
	# Cap: crown + brim (variant).
	_part(k, 5, 3, 1.0)
	k.sphere(Vector3(0, 1.085, 0.0), Vector3(0.148, 0.13, 0.148), seg, 3, 0.5)
	k.box(Vector3(0, 1.09, 0.16), Vector3(0.2, 0.025, 0.14), ["-y"])
	# Arms hang from the shoulders; the shader rotates them about SHOULDER.
	for side in [-1.0, 1.0]:
		var part := 2 if side < 0.0 else 3
		var sx: float = SHOULDER.x * side
		_part(k, part, 0, 0.95)
		k.box(Vector3(sx, SHOULDER.y - 0.11, 0), Vector3(0.12, 0.24, 0.12), ["+y"])
		_part(k, part, 1, 1.0)
		k.box(Vector3(sx, SHOULDER.y - 0.36, 0), Vector3(0.09, 0.26, 0.09), ["+y"])
		k.box(Vector3(sx, SHOULDER.y - 0.52, 0), Vector3(0.11, 0.08, 0.1))
	# Foam finger on the right hand (variant): a big mitt and the pointing finger.
	_part(k, 7, 5, 1.0)
	k.box(Vector3(SHOULDER.x, SHOULDER.y - 0.62, 0.0), Vector3(0.17, 0.2, 0.07))
	k.box(Vector3(SHOULDER.x, SHOULDER.y - 0.82, 0.0), Vector3(0.06, 0.2, 0.06), ["+y"])
	# Legs: seated (thighs forward, shins down) with explicit standing positions.
	_part(k, 4, 2, 0.85)
	_leg_box(k, Vector3(0, 0.5, 0.17), Vector3(0.34, 0.14, 0.46), Vector3(0, 0.67, 0.03), Vector3(0.34, 0.46, 0.14))
	_leg_box(k, Vector3(0, 0.25, 0.4), Vector3(0.3, 0.5, 0.13), Vector3(0, 0.23, 0.04), Vector3(0.3, 0.46, 0.13))
	var mesh := k.commit()
	if low:
		_fan_mesh_low = mesh
	else:
		_fan_mesh = mesh
	return mesh


static func _part(k: MeshKit, part: int, cls: int, shade: float) -> void:
	k.uv = Vector2(part, cls)
	k.uv2 = Vector2(shade, 0)
	k.color = Color.WHITE


## A box whose standing-pose corners are a second box (legs straighten when the fan stands).
static func _leg_box(k: MeshKit, c0: Vector3, s0: Vector3, c1: Vector3, s1: Vector3) -> void:
	var h0 := s0 * 0.5
	var h1 := s1 * 0.5
	var corners := [Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(-1, 1, -1),
		Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)]
	var p: Array[Vector3] = []
	var q: Array[Vector3] = []
	for s: Vector3 in corners:
		p.append(c0 + s * h0)
		q.append(c1 + s * h1)
	var faces := [[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6], [0, 4, 7, 3], [7, 6, 2, 3]]
	for f in faces:
		var n := (p[f[1]] - p[f[0]]).cross(p[f[2]] - p[f[0]]).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			k._v(p[f[i]], n, q[f[i]])


# ---------------------------------------------------------------- placement

## Fills a grandstand (12 m wide, 10 rows) with fans. `centre` is used for the wave angle.
func fill_stand(stand: Node3D, colors: Array, density: float, rng: RandomNumberGenerator, centre := Vector3(0, 0, -4)) -> void:
	if density <= 0.05:
		return
	var neutrals := [Color("#f4f1ea"), Color("#9aa3ad"), Color("#2a2d33"), Color("#3a5f8a"), Color("#c9b48a")]
	# Fill follows the crowd setting (High 92 %, Medium ~55 %, Low ~32 % of seats).
	var fill := clampf(0.92 * density, 0.0, 0.92)
	var xforms: Array[Transform3D] = []
	var cols: Array[Color] = []
	var customs: Array[Color] = []
	var stand_xf := stand.transform
	for r in ROWS:
		# Front rows fill first; a few gaps near the top at lower densities.
		var row_fill := fill * (1.0 - 0.25 * (1.0 - density) * float(r) / ROWS)
		for s in SEATS:
			if rng.randf() > row_fill:
				continue
			var local := Vector3(-5.7 + s * 0.6 + rng.randf_range(-0.04, 0.04), 1.0 + r * 0.45, 3.86 - r * 0.9)
			var basis := Basis(Vector3.UP, rng.randf_range(-0.18, 0.18)).scaled(Vector3.ONE * rng.randf_range(0.92, 1.08))
			xforms.append(Transform3D(basis, local))
			var c: Color
			if rng.randf() < 0.7:
				c = Color(colors[rng.randi() % colors.size()])
			else:
				c = neutrals[rng.randi() % neutrals.size()]
			cols.append(c.lightened(rng.randf_range(-0.08, 0.12)))
			var world := stand_xf * local
			var ang := atan2(world.x - centre.x, world.z - centre.z)
			var variant := rng.randi() % 8
			customs.append(Color(rng.randf(), rng.randf_range(0.1, 1.0), (variant + 0.01) / 8.0, ang / TAU + 0.5))
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = fan_mesh(density < 0.5)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, cols[i])
		mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Crowd"
	mmi.multimesh = mm
	mmi.material_override = material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Fans move in the shader; give the culling box room for raised arms and standing.
	mmi.extra_cull_margin = 1.5
	stand.add_child(mmi)
	fan_count += xforms.size()


# ---------------------------------------------------------------- reactions

func set_excitement(v: float) -> void:
	excitement = v


func cheer(amount := 1.0, hold := 1.6) -> void:
	_cheer = maxf(_cheer, amount)
	_cheer_hold = maxf(_cheer_hold, hold)
	_groan = 0.0
	_groan_hold = 0.0


func groan(amount := 1.0, hold := 1.4) -> void:
	_groan = maxf(_groan, amount)
	_groan_hold = maxf(_groan_hold, hold)
	_cheer = minf(_cheer, 0.2)


func stand_up(hold := 5.0) -> void:
	_stand_hold = maxf(_stand_hold, hold)


func sit_down() -> void:
	_stand_hold = 0.0


func start_wave(direction := 1.0) -> void:
	if _wave_t >= 0.0:
		return
	_wave_t = 0.0
	_wave_dir = direction


func wave_running() -> bool:
	return _wave_t >= 0.0


func _process(delta: float) -> void:
	if material == null:
		return
	# Use real time so slow motion and pause menus do not freeze reactions oddly.
	var dt := delta / maxf(Engine.time_scale, 0.05)
	dt = minf(dt, 0.1)
	_cheer_hold -= dt
	if _cheer_hold <= 0.0:
		_cheer = move_toward(_cheer, 0.0, dt * 1.2)
	_groan_hold -= dt
	if _groan_hold <= 0.0:
		_groan = move_toward(_groan, 0.0, dt * 1.0)
	_stand_hold -= dt
	_stand = move_toward(_stand, 1.0 if _stand_hold > 0.0 else 0.0, dt * 1.6)
	var wave_amt := 0.0
	var wave_pos := -10.0
	if _wave_t >= 0.0:
		_wave_t += dt
		var dur := 9.0
		var k := _wave_t / dur
		wave_pos = (-PI - 0.6 + k * (TAU + 1.2)) * _wave_dir
		wave_amt = 1.0
		if _wave_t >= dur:
			_wave_t = -1.0
			wave_amt = 0.0
	for m: ShaderMaterial in [material] + extra_materials:
		m.set_shader_parameter("excitement", excitement)
		m.set_shader_parameter("cheer", _cheer)
		m.set_shader_parameter("groan", _groan)
		m.set_shader_parameter("stand", maxf(_stand, float(m.get_meta("force_stand", 0.0))))
		m.set_shader_parameter("wave_pos", wave_pos)
		m.set_shader_parameter("wave_amt", wave_amt)
