class_name VFX
extends Node3D
## Battle visual effects.
## - Particles: a set of shared GPUParticles3D systems (custom process shader in
##   assets/shaders/vfx/fx_particles.gdshader) fed with emit_particle(), so hundreds of
##   hits cost almost nothing. Counts scale with Settings.particle_scale().
## - Pooled effect meshes (ground decals, rings, flame sheets, beams, glyphs, bolts) that
##   share one pre-built material per kind and animate through instance uniforms.
## - Up to three short-lived flash lights, floating combat text, the Base Shield dome.
## Card-specific sequences live in card_fx.gd (reached as `vfx.cards`).

const CardFX := preload("res://src/vfx/card_fx.gd")
const FLAGS := GPUParticles3D.EMIT_FLAG_POSITION | GPUParticles3D.EMIT_FLAG_VELOCITY \
		| GPUParticles3D.EMIT_FLAG_COLOR | GPUParticles3D.EMIT_FLAG_CUSTOM
const TEX := "res://assets/textures/vfx/"
const SH := "res://assets/shaders/vfx/"
const MAX_LIGHTS := 3

## A running animation on a pooled (or owned) node. fn(node, k) is called every frame
## with k = 0..1; when done the node goes back to its pool (or is freed).
class Anim:
	var node: Node3D
	var kind := ""
	var t := 0.0
	var dur := 1.0
	var delay := 0.0
	var fn: Callable
	var done: Callable
	var free_node := false
	var has_node := false
	var shown := false

var systems := {}
var cards: CardFX
var tex := {}
var reduce_flashes := false
var battle: Node

var _labels: Array[Label3D] = []
var _label_i := 0
var _scale := 1.0
var _mats := {}
var _meshes := {}
var _pool := {}
var _anims: Array[Anim] = []
var _lights: Array[OmniLight3D] = []
var _light_t: Array[float] = []
var _light_dur: Array[float] = []
var _light_e: Array[float] = []
var _bolt_pool: Array[MeshInstance3D] = []
var _bolt_mat: ShaderMaterial
var _camera: Camera3D
var _status_budget := 0
var _dome: MeshInstance3D
var _dome_shields := -1
var _dome_build := 1.0
var _dome_ripple := 1.0
var _env_saturation := -1.0


func _ready() -> void:
	battle = get_parent()
	_scale = Settings.particle_scale()
	reduce_flashes = bool(Settings.get_value("accessibility", "reduce_flashes", false))
	for n in ["glow", "spark", "star", "smoke", "flame", "noise", "ring", "scorch", "cracks", "frost", "runes", "clock", "web", "chain", "icons"]:
		tex[n] = load(TEX + n + ".png")
	_build_materials()
	_build_systems()
	for i in 40:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0011
		l.font = UITheme.font_display()
		l.font_size = 40
		l.outline_size = 12
		l.outline_modulate = Color(0.05, 0.02, 0.02, 0.9)
		l.render_priority = 10
		l.outline_render_priority = 9
		l.visible = false
		add_child(l)
		_labels.append(l)
	for i in MAX_LIGHTS:
		var ol := OmniLight3D.new()
		ol.shadow_enabled = false
		ol.omni_attenuation = 1.4
		ol.light_energy = 0.0
		ol.visible = false
		add_child(ol)
		_lights.append(ol)
		_light_t.append(0.0)
		_light_dur.append(1.0)
		_light_e.append(0.0)
	cards = CardFX.new(self)
	_warm_up()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfx-showcase="):
			cards.showcase.call_deferred(a.split("=")[1])


# ---------------------------------------------------------------- setup

func _shader(name: String) -> Shader:
	return load(SH + name + ".gdshader")


func _mat(shader: String, params: Dictionary = {}, priority := 0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(shader)
	for k in params.keys():
		m.set_shader_parameter(k, params[k])
	m.render_priority = priority
	return m


func _build_materials() -> void:
	var noise: Texture2D = tex.noise
	_mats.ring = _mat("fx_ring", {"noise": noise}, 1)
	_mats.scorch = _mat("fx_decal", {"tex": tex.scorch, "noise": noise, "mode": 0}, 0)
	_mats.crater = _mat("fx_decal", {"tex": tex.cracks, "noise": noise, "mode": 1}, 0)
	_mats.frost = _mat("fx_decal", {"tex": tex.frost, "noise": noise, "mode": 2}, 1)
	_mats.runes = _mat("fx_decal", {"tex": tex.runes, "noise": noise, "mode": 3}, 2)
	_mats.clock = _mat("fx_decal", {"tex": tex.clock, "noise": noise, "mode": 4}, 2)
	_mats.web = _mat("fx_decal", {"tex": tex.web, "noise": noise, "mode": 5}, 2)
	_mats.vortex = _mat("fx_ground", {"noise": noise, "mode": 0}, 1)
	_mats.magnet = _mat("fx_ground", {"noise": noise, "mode": 1}, 1)
	_mats.diamond = _mat("fx_ground", {"noise": noise, "mode": 2}, 1)
	_mats.radar = _mat("fx_ground", {"noise": noise, "mode": 3}, 1)
	_mats.hexdisc = _mat("fx_ground", {"noise": noise, "mode": 4}, 1)
	_mats.rays = _mat("fx_ground", {"noise": noise, "mode": 5}, 1)
	_mats.flame = _mat("fx_flame_sheet", {"noise": noise}, 3)
	_mats.haze = _mat("fx_heat_haze", {"noise": noise}, 4)
	_mats.beam = _mat("fx_beam", {"noise": noise}, 3)
	_mats.pulse = _mat("fx_dome", {}, 3)
	_mats.glyph = _mat("fx_glyph", {"icons": tex.icons}, 6)
	_mats.cage = _mat("fx_cage", {"chain_tex": tex.chain}, 3)
	_mats.ice = _mat("fx_ice", {"noise": noise})
	_mats.status_ground = _mat("fx_status_ground", {"frost_tex": tex.frost}, 2)
	_mats.status_head = _mat("fx_status_head", {"icons": tex.icons}, 7)
	_bolt_mat = _mat("fx_bolt", {"core_width": 0.1}, 4)
	_mats.trail = _mat("fx_bolt", {"core_width": 0.22}, 4)

	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	cyl.radial_segments = 24
	cyl.rings = 1
	var cone := CylinderMesh.new()
	cone.top_radius = 0.82
	cone.bottom_radius = 1.0
	cone.height = 1.0
	cone.cap_top = false
	cone.cap_bottom = false
	cone.radial_segments = 24
	cone.rings = 1
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.is_hemisphere = true
	sphere.radial_segments = 32
	sphere.rings = 10
	var shard := PrismMesh.new()
	shard.size = Vector3(1.0, 1.0, 0.85)
	_meshes = {"plane": plane, "quad": quad, "cyl": cyl, "cone": cone, "sphere": sphere, "shard": shard,
		"crystal": _crystal_mesh()}


## Low-poly ice block (a ring of tilted prisms) used to encase frozen runners.
func _crystal_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var n := 7
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(0.55, 0.75)
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := rng.randf_range(0.75, 1.05)
		var tip := Vector3(cos(a) * r * 0.65, h, sin(a) * r * 0.65) + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		var w := rng.randf_range(0.28, 0.4)
		var side := Vector3(-sin(a), 0, cos(a)) * w
		var out := Vector3(cos(a), 0, sin(a)) * w * 0.8
		var b0 := base - side
		var b1 := base + out
		var b2 := base + side
		var b3 := base - out * 0.6
		var shoulder := (tip - base) * 0.78
		var s0 := b0 + shoulder * 0.98
		var s1 := b1 + shoulder
		var s2 := b2 + shoulder * 0.98
		var s3 := b3 + shoulder * 1.02
		var ring_b := [b0, b1, b2, b3]
		var ring_s := [s0, s1, s2, s3]
		for k in 4:
			var k2 := (k + 1) % 4
			_tri(st, ring_b[k], ring_b[k2], ring_s[k2])
			_tri(st, ring_b[k], ring_s[k2], ring_s[k])
			_tri(st, ring_s[k], ring_s[k2], tip)
	st.generate_normals()
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Wind outward-facing (Godot uses clockwise front faces).
	var nrm := (b - a).cross(c - a)
	var center := (a + b + c) / 3.0
	if nrm.dot(Vector3(center.x, 0.0, center.z)) > 0.0:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)


# name: [amount, lifetime, draw, texture, gravity, damping, scale, size_mode, extra]
func _build_systems() -> void:
	var g := tex.glow as Texture2D
	_make_system("spark", 700, 0.55, "streak", tex.spark, Vector3(0, -11, 0), 2.0, 0.075, 0, {"align": true, "stretch": 0.05, "energy": 2.6, "aspect": 6.0})
	_make_system("streak", 300, 0.4, "streak", tex.spark, Vector3.ZERO, 0.8, 0.07, 4, {"align": true, "stretch": 0.06, "energy": 2.2, "aspect": 9.0})
	_make_system("glow", 400, 0.5, "add", g, Vector3.ZERO, 4.0, 0.55, 1, {"energy": 1.7, "fade_in": 0.02, "fade_pow": 1.2})
	_make_system("flash", 64, 0.22, "add", g, Vector3.ZERO, 0.0, 2.2, 5, {"energy": 3.2, "fade_in": 0.0, "fade_pow": 1.8})
	_make_system("ember", 500, 1.2, "add", g, Vector3(0, 1.8, 0), 1.2, 0.1, 6, {"energy": 3.4, "turbulence": 7.0})
	_make_system("fire", 600, 0.65, "flame", tex.flame, Vector3(0, 3.2, 0), 2.0, 0.95, 3, {"energy": 1.8, "turbulence": 3.0})
	_make_system("smoke", 300, 1.7, "blend", tex.smoke, Vector3(0, 0.9, 0), 1.6, 1.0, 2, {"spin": 0.6, "turbulence": 1.0})
	_make_system("dust", 300, 1.1, "blend", tex.smoke, Vector3(0, -0.6, 0), 2.6, 0.8, 2, {"spin": 0.4})
	_make_system("mist", 160, 2.2, "blend", tex.smoke, Vector3(0, 0.05, 0), 1.2, 1.7, 2, {"spin": 0.3, "shade": 0.25, "fade_in": 0.3})
	_make_system("magic", 500, 0.9, "add", tex.star, Vector3(0, 0.8, 0), 2.2, 0.24, 6, {"spin": 2.0, "energy": 2.4})
	_make_system("snow", 400, 1.8, "add", g, Vector3(0, -1.2, 0), 1.0, 0.11, 4, {"energy": 1.6, "turbulence": 2.0})
	_make_system("ring", 64, 0.4, "add", tex.ring, Vector3.ZERO, 0.0, 1.0, 5, {"energy": 2.2, "fade_in": 0.0, "fade_pow": 1.5})
	_make_system("debris", 200, 1.4, "rock", null, Vector3(0, -16, 0), 0.3, 0.26, 4, {"tumble": true, "spin": 8.0, "floor": 0.06})
	_make_system("shard", 160, 1.1, "ice", null, Vector3(0, -14, 0), 0.4, 0.22, 4, {"tumble": true, "spin": 7.0, "floor": 0.06})
	_make_system("confetti", 400, 2.4, "confetti", null, Vector3(0, -3.0, 0), 1.2, 0.17, 4, {"tumble": true, "spin": 10.0})


func _make_system(name: String, amount: int, lifetime: float, draw: String, texture: Texture2D, gravity: Vector3,
		damping: float, base_scale: float, size_mode: int, extra: Dictionary) -> void:
	var p := GPUParticles3D.new()
	p.amount = maxi(16, int(amount * maxf(_scale, 0.3)))
	p.lifetime = lifetime
	p.one_shot = false
	p.explosiveness = 0.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-90, -5, -90), Vector3(180, 70, 180))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ShaderMaterial.new()
	pm.shader = _shader("fx_particles")
	pm.set_shader_parameter("gravity", gravity)
	pm.set_shader_parameter("damping", damping)
	pm.set_shader_parameter("base_scale", base_scale)
	pm.set_shader_parameter("size_mode", size_mode)
	pm.set_shader_parameter("spin", float(extra.get("spin", 0.0)))
	pm.set_shader_parameter("turbulence", float(extra.get("turbulence", 0.0)))
	pm.set_shader_parameter("floor_y", float(extra.get("floor", -100.0)))
	pm.set_shader_parameter("align_velocity", bool(extra.get("align", false)))
	pm.set_shader_parameter("stretch", float(extra.get("stretch", 0.0)))
	pm.set_shader_parameter("tumble", bool(extra.get("tumble", false)))
	p.process_material = pm
	var mesh: Mesh
	var mat: Material
	match draw:
		"add", "streak", "blend", "flame":
			var q := QuadMesh.new()
			q.size = Vector2(1, 1)
			mesh = q
			var sm := ShaderMaterial.new()
			sm.shader = _shader({"add": "fx_particle_add", "streak": "fx_particle_streak", "blend": "fx_particle_blend", "flame": "fx_particle_flame"}[draw])
			sm.set_shader_parameter("tex", texture)
			if draw == "flame":
				sm.set_shader_parameter("noise", tex.noise)
			for k in ["energy", "fade_in", "fade_pow", "aspect", "shade", "soft"]:
				if extra.has(k):
					sm.set_shader_parameter(k, extra[k])
			sm.render_priority = 5 if draw != "blend" else 4
			mat = sm
		"rock":
			var rock := SphereMesh.new()
			rock.radius = 0.5
			rock.height = 0.75
			rock.radial_segments = 5
			rock.rings = 3
			mesh = rock
			var sm := StandardMaterial3D.new()
			sm.vertex_color_use_as_albedo = true
			sm.roughness = 1.0
			mat = sm
		"ice":
			mesh = _meshes.shard
			mat = _mats.ice
		"confetti":
			var q := QuadMesh.new()
			q.size = Vector2(1, 0.55)
			mesh = q
			var sm := StandardMaterial3D.new()
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.vertex_color_use_as_albedo = true
			sm.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat = sm
	p.draw_pass_1 = mesh
	p.material_override = mat
	add_child(p)
	p.emitting = true
	p.amount_ratio = 0.0
	systems[name] = p


## Puts one of every effect mesh on screen for a frame (below the field) so the GPU
## pipelines exist before the first cast.
func _warm_up() -> void:
	var nodes: Array[Node3D] = []
	for kind in ["ring", "scorch", "crater", "frost", "runes", "clock", "web", "vortex", "magnet", "diamond", "radar", "hexdisc", "rays",
			"flame", "haze", "beam", "pulse", "glyph", "cage", "ice_shell", "status_ground", "status_head"]:
		var mi := _take(kind)
		mi.global_position = Vector3(0, -3, 0)
		mi.scale = Vector3.ONE * 0.01
		nodes.append(mi)
	var b := _take_bolt()
	nodes.append(b)
	for s in systems.keys():
		_emit_raw(s, Vector3(0, -40, 0), Vector3.ZERO, Color(1, 1, 1, 0), 0.01, 0.05)
	get_tree().create_timer(0.2, false).timeout.connect(func() -> void:
		for n in nodes:
			if is_instance_valid(n):
				_release(n))


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_status_budget = int(70 * _scale) + 6
	for i in range(_anims.size() - 1, -1, -1):
		var an := _anims[i]
		an.t += delta
		if an.t < an.delay:
			continue
		if an.has_node and not is_instance_valid(an.node):
			_anims.remove_at(i)
			continue
		if not an.shown:
			an.shown = true
			if an.has_node and an.delay > 0.0:
				an.node.visible = true
		var k := clampf((an.t - an.delay) / maxf(an.dur, 0.0001), 0.0, 1.0)
		if an.fn.is_valid():
			an.fn.call(an.node, k)
		if k >= 1.0:
			_anims.remove_at(i)
			if an.done.is_valid():
				an.done.call()
			if an.has_node and is_instance_valid(an.node):
				if an.free_node:
					an.node.queue_free()
				elif an.kind != "":
					_release(an.node)
	for i in _lights.size():
		if _light_t[i] > 0.0:
			_light_t[i] = maxf(0.0, _light_t[i] - delta)
			var k := _light_t[i] / _light_dur[i]
			_lights[i].light_energy = _light_e[i] * k * k
			if _light_t[i] <= 0.0:
				_lights[i].visible = false
	_update_dome(delta)


## Runs fn(node, k) over `dur` seconds after `delay`; the node is hidden until then.
func animate(node: Node3D, dur: float, fn: Callable, delay := 0.0, done := Callable()) -> Anim:
	var an := Anim.new()
	an.node = node
	an.has_node = node != null
	an.kind = String(node.get_meta("fx_kind", "")) if node else ""
	an.dur = dur
	an.delay = delay
	an.fn = fn
	an.done = done
	if node and delay > 0.0:
		node.visible = false
	_anims.append(an)
	return an


## Calls fn after `delay` seconds of game time (pauses with the battle).
func after(delay: float, fn: Callable) -> void:
	if delay <= 0.0:
		fn.call()
		return
	var an := Anim.new()
	an.dur = 0.0
	an.delay = delay
	an.done = fn
	_anims.append(an)


## Calls fn(k) every frame for `dur` seconds (k = 0..1).
func every_frame(dur: float, fn: Callable, delay := 0.0) -> void:
	var an := Anim.new()
	an.dur = dur
	an.delay = delay
	an.fn = func(_n: Node3D, k: float) -> void: fn.call(k)
	_anims.append(an)


# ---------------------------------------------------------------- pools

func _kind_setup(kind: String) -> Array:
	# [mesh, material]
	match kind:
		"ring", "scorch", "crater", "frost", "runes", "clock", "web", "vortex", "magnet", "diamond", "radar", "hexdisc", "rays", "status_ground":
			return [_meshes.plane, _mats[kind]]
		"flame", "haze", "glyph", "status_head":
			return [_meshes.quad, _mats[kind]]
		"beam":
			return [_meshes.cyl, _mats.beam]
		"cage":
			return [_meshes.cone, _mats.cage]
		"pulse":
			return [_meshes.sphere, _mats.pulse]
		"ice_shell":
			return [_meshes.crystal, _mats.ice]
		"ice_shard":
			return [_meshes.shard, _mats.ice]
	push_error("VFX: unknown kind " + kind)
	return [_meshes.quad, _mats.glyph]


func _take(kind: String) -> MeshInstance3D:
	var list: Array = _pool.get(kind, [])
	var mi: MeshInstance3D
	while not list.is_empty():
		mi = list.pop_back()
		if is_instance_valid(mi):
			break
		mi = null
	if mi == null:
		var setup := _kind_setup(kind)
		mi = MeshInstance3D.new()
		mi.mesh = setup[0]
		mi.material_override = setup[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("fx_kind", kind)
		add_child(mi)
	mi.visible = true
	mi.rotation = Vector3.ZERO
	mi.scale = Vector3.ONE
	return mi


func _release(n: Node3D) -> void:
	if not is_instance_valid(n):
		return
	var kind := String(n.get_meta("fx_kind", ""))
	if kind == "":
		n.queue_free()
		return
	if kind == "bolt":
		(n as MeshInstance3D).mesh.clear_surfaces()
		n.visible = false
		_bolt_pool.append(n)
		return
	if n.get_parent() != self:
		n.reparent(self, false)
	n.visible = false
	if not _pool.has(kind):
		_pool[kind] = []
	(_pool[kind] as Array).append(n)


## A node with the shared mesh/material of `kind` that the caller owns (and frees).
func make_owned(kind: String) -> MeshInstance3D:
	var setup := _kind_setup(kind)
	var mi := MeshInstance3D.new()
	mi.mesh = setup[0]
	mi.material_override = setup[1]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ---------------------------------------------------------------- particles

func _emit_raw(system: String, pos: Vector3, vel: Vector3, color: Color, size: float, life: float) -> void:
	var p: GPUParticles3D = systems.get(system)
	if p == null:
		return
	p.emit_particle(Transform3D(Basis(), pos), vel, color, Color(randf(), 0.0, size, life), FLAGS)


func _count(n: int) -> int:
	if n <= 0:
		return 0
	var f := n * _scale
	var c := int(f)
	if randf() < f - c:
		c += 1
	return maxi(c, 1)


## One particle with an exact velocity, size multiplier and lifetime multiplier.
func emit_one(system: String, pos: Vector3, vel: Vector3, color: Color, size := 1.0, life := 1.0) -> void:
	_emit_raw(system, pos, vel, color, size, life)


## Emits n particles from a point with a random spread (count scales with the settings).
func emit(system: String, pos: Vector3, n: int, color: Color, speed := 4.0, up := 0.5, spread := 1.0, size := 1.0, life := 1.0) -> void:
	for i in _count(n):
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1.0) + up, randf_range(-1, 1)).normalized()
		var v := dir * speed * randf_range(0.5, 1.0) * spread
		var c := color
		c.v = clampf(c.v * randf_range(0.85, 1.15), 0.0, 4.0)
		_emit_raw(system, pos + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)), v, c,
			size * randf_range(0.7, 1.3), life * randf_range(0.75, 1.15))


## Particles thrown into a cone around `dir` (cone 0 = straight, 1 = hemisphere).
func spray(system: String, pos: Vector3, n: int, color: Color, speed: float, dir: Vector3, cone := 0.4, size := 1.0, life := 1.0, jitter := 0.1) -> void:
	var d := dir.normalized() if dir.length() > 0.001 else Vector3.UP
	var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var up2 := side.cross(d).normalized()
	for i in _count(n):
		var a := randf() * TAU
		var r := sqrt(randf()) * cone
		var v := (d + (side * cos(a) + up2 * sin(a)) * r).normalized() * speed * randf_range(0.55, 1.0)
		var o := Vector3(randf_range(-jitter, jitter), randf_range(-jitter, jitter), randf_range(-jitter, jitter))
		_emit_raw(system, pos + o, v, color, size * randf_range(0.7, 1.3), life * randf_range(0.75, 1.15))


## A horizontal ring of particles moving outward (and up).
func ring_emit(system: String, center: Vector3, radius: float, n: int, color: Color, out_speed: float, up_speed := 0.0, size := 1.0, life := 1.0) -> void:
	var c := _count(n)
	for i in c:
		var a := TAU * (float(i) + randf() * 0.6) / c
		var dir := Vector3(cos(a), 0, sin(a))
		_emit_raw(system, center + dir * radius, dir * out_speed * randf_range(0.7, 1.1) + Vector3(0, up_speed * randf_range(0.6, 1.1), 0),
			color, size * randf_range(0.75, 1.25), life * randf_range(0.8, 1.15))


## Particles scattered over a disc on the ground.
func disc_emit(system: String, center: Vector3, radius: float, n: int, color: Color, vel: Vector3, size := 1.0, life := 1.0, height := 0.1) -> void:
	for i in _count(n):
		var a := randf() * TAU
		var d := sqrt(randf()) * radius
		_emit_raw(system, center + Vector3(cos(a) * d, randf() * height, sin(a) * d), vel * randf_range(0.6, 1.2), color, size * randf_range(0.7, 1.3), life * randf_range(0.75, 1.2))


## Particles spread along a segment.
func line_emit(system: String, a: Vector3, b: Vector3, n: int, color: Color, vel: Vector3, spread := 0.2, size := 1.0, life := 1.0) -> void:
	for i in _count(n):
		var p := a.lerp(b, randf()) + Vector3(randf_range(-spread, spread), randf_range(-spread, spread) * 0.5, randf_range(-spread, spread))
		_emit_raw(system, p, vel + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3)) * vel.length(), color, size * randf_range(0.7, 1.3), life * randf_range(0.8, 1.2))


## Per-frame status particles (burning, magnet streaks...) draw from a shared budget so
## 150 afflicted runners cannot flood the systems.
func status_emit(system: String, pos: Vector3, vel: Vector3, color: Color, size := 1.0, life := 1.0) -> void:
	if _status_budget <= 0:
		return
	_status_budget -= 1
	_emit_raw(system, pos, vel, color, size, life)


# ---------------------------------------------------------------- lights & camera

## A short flash of light (max three at once; the oldest is reused).
func flash_light(pos: Vector3, color: Color, energy := 4.0, light_range := 8.0, dur := 0.3) -> void:
	var best := 0
	var best_t := INF
	for i in _lights.size():
		if _light_t[i] < best_t:
			best_t = _light_t[i]
			best = i
	var l := _lights[best]
	l.global_position = pos
	l.light_color = color
	l.omni_range = light_range
	_light_e[best] = energy * (0.35 if reduce_flashes else 1.0)
	_light_t[best] = dur
	_light_dur[best] = dur
	l.light_energy = _light_e[best]
	l.visible = true


func shake(amount: float) -> void:
	if battle and battle.has_method("shake"):
		battle.shake(amount)


func camera_pos() -> Vector3:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	return _camera.global_position if _camera else Vector3(0, 30, 30)


# ---------------------------------------------------------------- hits & bursts

func burst(kind: String, pos: Vector3, color: Color = Color.WHITE) -> void:
	match kind:
		"hit":
			spray("spark", pos, 6, color.lerp(Color.WHITE, 0.5), 6.0, (camera_pos() - pos).normalized(), 0.9, 0.9, 0.7)
			emit_one("glow", pos, Vector3.ZERO, Color(color.lerp(Color.WHITE, 0.4), 0.8), 0.9, 0.5)
		"crit":
			spray("spark", pos, 16, Color(1.0, 0.9, 0.5), 9.0, Vector3.UP, 1.2, 1.1)
			emit_one("flash", pos, Vector3.ZERO, Color(1.0, 0.85, 0.5, 0.9), 0.8, 1.0)
			emit_one("ring", pos, Vector3.ZERO, Color(1.0, 0.85, 0.4), 1.2, 1.0)
			emit("magic", pos, 6, Color(1.0, 0.9, 0.5), 4.0, 0.6)
			shockwave(pos, 1.4, Color(1.0, 0.85, 0.4), 0.3)
		"explosion":
			emit_one("flash", pos, Vector3.ZERO, Color(1.0, 0.7, 0.35), 1.2, 1.2)
			emit("fire", pos, 10, Color(1.0, 0.45, 0.1), 5.0, 0.8, 1.0, 0.9)
			spray("spark", pos, 22, Color(1.0, 0.65, 0.25), 11.0, Vector3.UP, 1.3)
			emit("smoke", pos + Vector3(0, 0.4, 0), 6, Color(0.22, 0.19, 0.17, 0.75), 2.0, 1.0)
			emit("ember", pos, 12, Color(1.0, 0.5, 0.1), 5.0, 1.0)
		"fire":
			emit("fire", pos, 4, Color(1.0, 0.45, 0.08), 1.5, 1.2, 1.0, 0.6)
			emit("ember", pos, 5, Color(1.0, 0.55, 0.12), 2.5, 1.2)
		"frost":
			emit("snow", pos, 8, Color(0.75, 0.95, 1.0), 3.0, 0.6)
			spray("shard", pos, 3, Color.WHITE, 4.0, Vector3.UP, 1.0, 0.5, 0.8)
			emit_one("glow", pos, Vector3.ZERO, Color(0.5, 0.85, 1.0, 0.8), 1.4, 0.6)
		"shadow":
			emit("smoke", pos, 6, Color(0.16, 0.05, 0.25, 0.85), 2.5, 0.6, 1.0, 0.8)
			emit("magic", pos, 8, Color(0.75, 0.45, 1.0), 3.0)
			emit_one("glow", pos, Vector3.ZERO, Color(0.55, 0.25, 1.0, 0.8), 1.4, 0.6)
		"magic":
			emit("magic", pos, 10, color, 3.5, 0.8)
			emit_one("glow", pos, Vector3.ZERO, Color(color, 0.7), 1.2, 0.5)
		"gold":
			emit("magic", pos, 14, Color(1.0, 0.85, 0.3), 4.5, 1.0)
			emit_one("glow", pos, Vector3.ZERO, Color(1.0, 0.8, 0.3, 0.9), 1.6, 0.7)
		"out":
			spray("spark", pos, 10, Color(1.0, 0.95, 0.8), 7.0, Vector3.UP, 1.1)
			emit_one("ring", pos, Vector3.ZERO, Color(1.0, 0.95, 0.85, 0.8), 1.0, 0.8)
			emit("dust", Vector3(pos.x, 0.2, pos.z), 5, Color(0.6, 0.45, 0.32, 0.6), 2.0, 0.2)
		"confetti":
			var cols := [UITheme.SCARLET, UITheme.GOLD, UITheme.OFFWHITE, UITheme.BLUE, UITheme.GREEN]
			for i in 3:
				emit("confetti", pos, 18, cols[randi() % cols.size()], 7.0, 1.5)


func dust(pos: Vector3, amount := 1.0) -> void:
	emit("dust", Vector3(pos.x, 0.25, pos.z), int(6 * amount), Color(0.62, 0.46, 0.33, 0.55), 2.0 * amount, 0.15, 1.0, 0.7 + 0.2 * amount)


func puff(pos: Vector3, color: Color) -> void:
	emit("smoke", pos, 5, Color(color.darkened(0.4), 0.7), 1.6, 0.3, 1.0, 0.7)
	emit("magic", pos, 8, color, 3.0)


func ember(pos: Vector3) -> void:
	emit("ember", pos + Vector3(randf_range(-0.2, 0.2), randf_range(-0.3, 0.3), randf_range(-0.2, 0.2)), 1, Color(1.0, 0.5, 0.1), 1.0, 1.5, 0.6)


func speed_lines(e: Node3D) -> void:
	var back := -e.global_transform.basis.z
	for i in _count(6):
		var p := e.global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 1.6), randf_range(-0.3, 0.3))
		_emit_raw("streak", p, back * 7.0, Color(1.0, 0.9, 0.3), 0.8, 0.8)


# ---------------------------------------------------------------- text

func _next_label() -> Label3D:
	var l := _labels[_label_i]
	_label_i = (_label_i + 1) % _labels.size()
	var tw: Tween = l.get_meta("tween") if l.has_meta("tween") else null
	if tw and tw.is_valid():
		tw.kill()
	return l


func damage_number(pos: Vector3, amount: float, crit: bool, color := Color(1.0, 0.95, 0.85)) -> void:
	if not bool(Settings.get_value("gameplay", "damage_numbers", true)):
		return
	if amount < 1.0:
		return
	var l := _next_label()
	l.text = str(int(round(amount))) + ("!" if crit else "")
	l.modulate = Color(1.0, 0.8, 0.2) if crit else color
	l.font_size = 34 if crit else 24
	_animate_label(l, pos + Vector3(randf_range(-0.35, 0.35), 0.3, randf_range(-0.2, 0.2)), 0.75, 1.25 if crit else 1.0)


func text_popup(pos: Vector3, text: String, color: Color, scale := 1.0, duration := 1.0) -> void:
	var l := _next_label()
	l.text = text
	l.modulate = color
	l.font_size = int(32 * scale)
	_animate_label(l, pos, duration, scale)


func _animate_label(l: Label3D, pos: Vector3, duration: float, pop: float) -> void:
	l.global_position = pos
	l.visible = true
	l.scale = Vector3.ONE * 0.4
	var c := l.modulate
	c.a = 1.0
	l.modulate = c
	var oc := l.outline_modulate
	oc.a = 0.9
	l.outline_modulate = oc
	var tw := create_tween()
	l.set_meta("tween", tw)
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE * pop, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", pos + Vector3(0, 1.1, 0), duration).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tw.tween_property(l, "outline_modulate:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tw.chain().tween_callback(func() -> void: l.visible = false)


# ---------------------------------------------------------------- ground rings & decals

func _ground_node(kind: String, pos: Vector3, radius: float, y := 0.06) -> MeshInstance3D:
	var mi := _take(kind)
	mi.global_position = Vector3(pos.x, y, pos.z)
	mi.scale = Vector3(radius, 1, radius)
	return mi


## Expanding ground ring with a bright leading edge.
func shockwave(pos: Vector3, radius: float, color: Color, time := 0.45, thickness := 0.06, delay := 0.0, implode := false) -> void:
	var mi := _ground_node("ring", pos, radius, 0.07)
	mi.set_instance_shader_parameter("color", Color(color.r, color.g, color.b, color.a))
	mi.set_instance_shader_parameter("mode", 4.0 if implode else 0.0)
	mi.set_instance_shader_parameter("params", Vector4(thickness, 0.25, 0.0, 0.0))
	mi.set_instance_shader_parameter("progress", 0.0)
	animate(mi, time, func(n: Node3D, k: float) -> void: (n as MeshInstance3D).set_instance_shader_parameter("progress", k), delay)


## A danger zone that fills up until the attack lands. The caller frees the node.
func telegraph(pos: Vector3, radius: float, color: Color, time: float) -> Node3D:
	var mi := make_owned("ring")
	add_child(mi)
	mi.global_position = Vector3(pos.x, 0.07, pos.z)
	mi.scale = Vector3(radius, 1, radius)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("mode", 2.0)
	mi.set_instance_shader_parameter("params", Vector4(0.05, 0.22, 0.0, 0.0))
	mi.set_instance_shader_parameter("progress", 0.0)
	var an := animate(mi, time, func(n: Node3D, k: float) -> void: (n as MeshInstance3D).set_instance_shader_parameter("progress", k))
	an.kind = ""
	return mi


## Ground circle for an ability zone: scales in, holds, fades out after `time`.
func zone_ring(pos: Vector3, radius: float, color: Color, time: float, fill := 0.18, spin := 0.0, dashes := -1.0) -> MeshInstance3D:
	var mi := _ground_node("ring", pos, radius, 0.065)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("mode", 1.0)
	mi.set_instance_shader_parameter("params", Vector4(0.035, fill, spin, (24.0 if spin != 0.0 else 0.0) if dashes < 0.0 else dashes))
	mi.set_instance_shader_parameter("progress", 0.0)
	animate(mi, maxf(time, 0.3), func(n: Node3D, k: float) -> void:
		var tt := k * time
		var grow := clampf(tt / 0.2, 0.0, 1.0)
		var s := radius * (0.1 + 0.9 * (1.0 - pow(1.0 - grow, 3.0)))
		n.scale = Vector3(s, 1, s)
		var vis := minf(grow * 1.5, 1.0) * (1.0 - smoothstep(time - 0.4, time, tt))
		(n as MeshInstance3D).set_instance_shader_parameter("progress", vis))
	return mi


## Textured ground decal (scorch, crater, frost, runes, clock, web). Instance uniforms:
## color, color2, anim(x age, y visibility, z rotation, w spread/flare). `fn(node, k)`
## may override the animation; by default it ages, fades in quickly and out at the end.
func decal(kind: String, pos: Vector3, radius: float, color: Color, color2: Color, dur: float, fn := Callable(), delay := 0.0, y := 0.05) -> MeshInstance3D:
	var mi := _ground_node(kind, pos, radius, y)
	mi.rotation.y = randf() * TAU if kind in ["scorch", "crater"] else 0.0
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("color2", color2)
	mi.set_instance_shader_parameter("anim", Vector4(0, 0, 0, 1))
	if not fn.is_valid():
		fn = func(n: Node3D, k: float) -> void:
			var vis := smoothstep(0.0, 0.04, k) * (1.0 - smoothstep(0.7, 1.0, k))
			(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, 0.0, 1.0))
	animate(mi, dur, fn, delay)
	return mi


## Procedural ground pattern (vortex, magnet, diamond, radar, hexdisc, rays).
func ground_fx(kind: String, pos: Vector3, radius: float, color: Color, color2: Color, dur: float, extra := Vector2(1.0, 0.0), fn := Callable(), delay := 0.0) -> MeshInstance3D:
	var mi := _ground_node(kind, pos, radius, 0.075)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("color2", color2)
	mi.set_instance_shader_parameter("anim", Vector4(0, 0, extra.x, extra.y))
	if not fn.is_valid():
		fn = func(n: Node3D, k: float) -> void:
			var tt := k * dur
			var grow := clampf(tt / 0.25, 0.0, 1.0)
			var s := radius * (0.3 + 0.7 * (1.0 - pow(1.0 - grow, 3.0)))
			n.scale = Vector3(s, 1, s)
			var vis := grow * (1.0 - smoothstep(dur - 0.45, dur, tt))
			(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, extra.x, extra.y))
	animate(mi, dur, fn, delay)
	return mi


# ---------------------------------------------------------------- vertical effects

## A camera-facing sheet of fire standing on the ground.
func flame_sheet(pos: Vector3, width: float, height: float, dur: float, delay := 0.0, tint := Color(1.0, 0.45, 0.08, 1.0)) -> void:
	var mi := _take("flame")
	mi.global_position = Vector3(pos.x, maxf(pos.y, 0.0), pos.z)
	mi.scale = Vector3(width, height, 1.0)
	mi.set_instance_shader_parameter("seed", randf() * 10.0)
	mi.set_instance_shader_parameter("tint", tint)
	mi.set_instance_shader_parameter("progress", 0.0)
	animate(mi, dur, func(n: Node3D, k: float) -> void: (n as MeshInstance3D).set_instance_shader_parameter("progress", k), delay)


func heat_haze(pos: Vector3, width: float, height: float, dur: float, delay := 0.0) -> void:
	var mi := _take("haze")
	mi.global_position = Vector3(pos.x, 0.0, pos.z)
	mi.scale = Vector3(width, height, 1.0)
	mi.set_instance_shader_parameter("progress", 0.0)
	animate(mi, dur, func(n: Node3D, k: float) -> void: (n as MeshInstance3D).set_instance_shader_parameter("progress", k), delay)


## Vertical light pillar.
func beam(pos: Vector3, radius: float, height: float, color: Color, dur: float, delay := 0.0) -> void:
	var mi := _take("beam")
	mi.global_position = Vector3(pos.x, height * 0.5, pos.z)
	mi.scale = Vector3(radius, height, radius)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("progress", 0.0)
	animate(mi, dur, func(n: Node3D, k: float) -> void:
		var w := radius * (0.6 + 0.4 * minf(k * 6.0, 1.0)) * (1.0 - 0.5 * k)
		n.scale = Vector3(w, height, w)
		(n as MeshInstance3D).set_instance_shader_parameter("progress", k), delay)


## Expanding energy bubble (shouts, pulses).
func sphere_pulse(pos: Vector3, radius: float, color: Color, dur: float, delay := 0.0) -> void:
	var mi := _take("pulse")
	mi.global_position = Vector3(pos.x, pos.y, pos.z)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("mode", 1.0)
	mi.set_instance_shader_parameter("build", 0.0)
	animate(mi, dur, func(n: Node3D, k: float) -> void:
		var s := radius * (0.15 + 0.85 * (1.0 - pow(1.0 - k, 2.5)))
		n.scale = Vector3(s, s * 0.8, s)
		(n as MeshInstance3D).set_instance_shader_parameter("build", k), delay)


## A big floating icon (0 star, 1 ?, 2 reticle, 3 snowflake, 4 link, 5 padlock, 6 chevrons,
## 7 gem, 8 bolt, 9 shout, 10 eye, 11 spiral, 12 plus, 13 ball, 14 shield, 15 broken shield).
func glyph(pos: Vector3, cell: int, size: float, color: Color, dur: float, delay := 0.0, rise := 0.6) -> MeshInstance3D:
	var mi := _take("glyph")
	mi.global_position = pos
	mi.scale = Vector3(size, size, size)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("anim", Vector4(0, cell, 0, 0))
	animate(mi, dur, func(n: Node3D, k: float) -> void:
		n.global_position = pos + Vector3(0, rise * (1.0 - pow(1.0 - k, 2.0)), 0)
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, cell, 0, 0)), delay)
	return mi


## Cage of light bars around a point (Lockdown).
func cage(pos: Vector3, radius: float, height: float, color: Color, dur: float, delay := 0.0) -> void:
	var mi := _take("cage")
	mi.global_position = Vector3(pos.x, height * 0.5, pos.z)
	mi.scale = Vector3(radius, height, radius)
	mi.set_instance_shader_parameter("color", color)
	mi.set_instance_shader_parameter("progress", 0.0)
	mi.set_instance_shader_parameter("vis", 1.0)
	animate(mi, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var m := n as MeshInstance3D
		m.set_instance_shader_parameter("progress", 1.0 - pow(1.0 - clampf(tt / 0.22, 0.0, 1.0), 3.0))
		m.set_instance_shader_parameter("vis", 1.0 - smoothstep(dur - 0.35, dur, tt)), delay)


## Ice crystal growing out of the ground and dissolving away.
func ice_spike(pos: Vector3, size: Vector3, dur: float, delay := 0.0, tilt := Vector3.ZERO) -> void:
	var mi := _take("ice_shard")
	mi.global_position = pos
	mi.rotation = tilt
	mi.scale = Vector3(size.x, 0.01, size.z)
	mi.set_instance_shader_parameter("fade", 1.0)
	mi.set_instance_shader_parameter("tint", Color(0.62, 0.9, 1.0, 1.0))
	animate(mi, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var g := clampf(tt / 0.25, 0.0, 1.0)
		var e := 1.0 + 2.70158 * pow(g - 1.0, 3.0) + 1.70158 * pow(g - 1.0, 2.0)
		n.scale = Vector3(size.x, maxf(size.y * e, 0.01), size.z)
		n.position.y = pos.y + size.y * e * 0.5
		(n as MeshInstance3D).set_instance_shader_parameter("fade", 1.0 - smoothstep(dur - 0.4, dur, tt)), delay)


# ---------------------------------------------------------------- bolts & ribbons

func _take_bolt() -> MeshInstance3D:
	while not _bolt_pool.is_empty():
		var b: MeshInstance3D = _bolt_pool.pop_back()
		if is_instance_valid(b):
			b.visible = true
			return b
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _bolt_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("fx_kind", "bolt")
	add_child(mi)
	return mi


## Jagged path between a and b by midpoint displacement.
func _jagged(a: Vector3, b: Vector3, jag: float, depth: int) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var amt := a.distance_to(b) * jag
	for d in depth:
		var np := PackedVector3Array()
		for i in pts.size() - 1:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			np.append(p0)
			var dir := (p1 - p0).normalized()
			var perp := dir.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
			np.append((p0 + p1) * 0.5 + perp * randf_range(-amt, amt))
		np.append(pts[pts.size() - 1])
		pts = np
		amt *= 0.55
	return pts


func _strip(im: ImmediateMesh, pts: PackedVector3Array, width: float, color: Color, taper := true) -> void:
	if pts.size() < 2:
		return
	var cam := camera_pos()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := pts.size()
	for i in n:
		var p := pts[i]
		var dir := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)])
		if dir.length_squared() < 0.000001:
			dir = Vector3.UP
		var side := dir.cross(cam - p).normalized()
		var f := float(i) / float(n - 1)
		var w := width
		var c := color
		if taper:
			w *= 0.35 + 0.65 * sin(PI * clampf(f * 0.92 + 0.04, 0.0, 1.0))
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(0, f))
		im.surface_add_vertex(p + side * w)
		im.surface_set_color(c)
		im.surface_set_uv(Vector2(1, f))
		im.surface_add_vertex(p - side * w)
	im.surface_end()


func _draw_bolt(im: ImmediateMesh, a: Vector3, b: Vector3, color: Color, width: float, jag: float, branches: int) -> void:
	im.clear_surfaces()
	var main := _jagged(a, b, jag, 4)
	_strip(im, main, width, color)
	for i in branches:
		var idx := randi_range(2, main.size() - 3)
		var start := main[idx]
		var dir := (b - a).normalized()
		var len := a.distance_to(b) * randf_range(0.15, 0.35)
		var off := dir.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
		var end := start + (dir * 0.6 + off * 0.8).normalized() * len
		_strip(im, _jagged(start, end, jag * 1.2, 3), width * 0.5, Color(color, color.a * 0.8))


## Branching, flickering lightning bolt with a white core and a coloured glow.
func bolt(a: Vector3, b: Vector3, color: Color, width := 0.1, life := 0.3, branches := 2, jag := 0.16, flickers := 3, delay := 0.0) -> void:
	var mi := _take_bolt()
	var im := mi.mesh as ImmediateMesh
	var state := [-1]
	_draw_bolt(im, a, b, color, width, jag, branches)
	mi.set_instance_shader_parameter("intensity", 1.0)
	var an := animate(mi, life, func(n: Node3D, k: float) -> void:
		var step := int(k * flickers)
		if step != state[0] and step < flickers:
			state[0] = step
			if step > 0:
				_draw_bolt(im, a, b, color, width, jag, branches)
		var fl := (1.0 - k) * (0.65 + 0.35 * sin(k * 70.0)) * 1.6
		(n as MeshInstance3D).set_instance_shader_parameter("intensity", fl), delay)
	an.kind = "bolt"


## Smooth glowing ribbon along `pts` that fades out (dash streaks, arcs, beams).
func ribbon(pts: PackedVector3Array, color: Color, width: float, life: float, delay := 0.0, taper := true) -> void:
	var mi := _take_bolt()
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	_strip(im, pts, width, color, taper)
	mi.set_instance_shader_parameter("intensity", 1.0)
	var an := animate(mi, life, func(n: Node3D, k: float) -> void:
		(n as MeshInstance3D).set_instance_shader_parameter("intensity", pow(1.0 - k, 1.5) * 1.4), delay)
	an.kind = "bolt"


## A ribbon whose points are recomputed every frame by pts_fn(k) (tethers, field lines).
func live_ribbon(pts_fn: Callable, color: Color, width: float, life: float, delay := 0.0) -> void:
	var mi := _take_bolt()
	var im := mi.mesh as ImmediateMesh
	im.clear_surfaces()
	mi.set_instance_shader_parameter("intensity", 0.0)
	var an := animate(mi, life, func(n: Node3D, k: float) -> void:
		var pts: PackedVector3Array = pts_fn.call(k)
		im.clear_surfaces()
		if pts.size() >= 2:
			_strip(im, pts, width, color, true)
		(n as MeshInstance3D).set_instance_shader_parameter("intensity", smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.75, 1.0, k)) * 1.3), delay)
	an.kind = "bolt"


## Points on an arc from a to b bulging `lift` metres upward.
static func arc_points(a: Vector3, b: Vector3, lift: float, n := 16) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in n + 1:
		var k := float(i) / n
		pts.append(a.lerp(b, k) + Vector3(0, sin(k * PI) * lift, 0))
	return pts


func lightning(a: Vector3, b: Vector3, color: Color, width := 0.08) -> void:
	bolt(a, b, color, width * 2.4, 0.28, 1 if a.distance_to(b) < 6.0 else 2, 0.15, 2)
	spray("spark", b, 8, color.lerp(Color.WHITE, 0.4), 6.0, Vector3.UP, 1.2, 0.8)
	emit_one("glow", b, Vector3.ZERO, Color(color, 0.9), 1.4, 0.5)


## Stars circling over a stunned unit's head.
func stun_stars(target: Node3D, time: float) -> void:
	var h: float = target.model.height if "model" in target and target.model else 1.8
	var mi := make_owned("status_head")
	target.add_child(mi)
	mi.position = Vector3(0, h + 0.25, 0)
	mi.scale = Vector3(1.3, 0.65, 1.0) * clampf(h / 2.4, 0.8, 1.6)
	mi.set_instance_shader_parameter("st", Vector4(1, 0, 0, 0))
	var an := animate(mi, time, func(n: Node3D, k: float) -> void:
		(n as MeshInstance3D).set_instance_shader_parameter("st", Vector4(minf(k * time * 6.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, k)), 0, 0, 0)))
	an.kind = ""
	an.free_node = true
	# Cleansed early (Rally Cry): drop the stars with the stun.
	if "stun_t" in target:
		an.fn = func(n: Node3D, k: float) -> void:
			var on := 1.0 if float(target.stun_t) > 0.0 else 0.0
			(n as MeshInstance3D).set_instance_shader_parameter("st", Vector4(minf(k * time * 6.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, k)) * on, 0, 0, 0))


## Compat: a burning strip of ground (now the full Heat Wave sequence).
func fire_line(from: Vector3, to: Vector3, width: float, time: float) -> void:
	cards.heat_wave(from, to, width, time)


# ---------------------------------------------------------------- statuses

func make_status_ground() -> MeshInstance3D:
	return make_owned("status_ground")


func make_status_head() -> MeshInstance3D:
	return make_owned("status_head")


func make_ice_shell() -> MeshInstance3D:
	return make_owned("ice_shell")


func make_status_cage() -> MeshInstance3D:
	return make_owned("cage")


## Called every frame for a burning unit.
func status_burn(pos: Vector3, h: float, delta: float) -> void:
	if randf() < delta * 14.0:
		status_emit("fire", pos + Vector3(randf_range(-0.25, 0.25), randf_range(0.2, h * 0.7), randf_range(-0.25, 0.25)),
			Vector3(0, 0.8, 0), Color(1.0, 0.42, 0.08), randf_range(0.4, 0.65), randf_range(0.6, 0.9))
	if randf() < delta * 4.0:
		status_emit("ember", pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.4, h), randf_range(-0.3, 0.3)),
			Vector3(randf_range(-0.4, 0.4), 1.2, randf_range(-0.4, 0.4)), Color(1.0, 0.55, 0.15), 1.0, 1.0)
	if randf() < delta * 2.0:
		status_emit("smoke", pos + Vector3(0, h * 0.9, 0), Vector3(0, 1.0, 0), Color(0.2, 0.18, 0.17, 0.35), 0.6, 0.8)


## A burn damage tick: the flames on the unit flare up (replaces a damage number).
func burn_tick(pos: Vector3) -> void:
	status_emit("fire", pos, Vector3(0, 1.6, 0), Color(1.0, 0.5, 0.1), 0.9, 0.7)
	status_emit("glow", pos, Vector3.ZERO, Color(1.0, 0.45, 0.1, 0.7), 1.2, 0.5)
	status_emit("ember", pos, Vector3(randf_range(-1, 1), 2.5, randf_range(-1, 1)), Color(1.0, 0.6, 0.2), 1.0, 0.8)


func status_chill(pos: Vector3, h: float, delta: float) -> void:
	if randf() < delta * 3.0:
		status_emit("snow", pos + Vector3(randf_range(-0.4, 0.4), randf_range(0.3, h), randf_range(-0.4, 0.4)),
			Vector3(0, -0.3, 0), Color(0.8, 0.95, 1.0), 1.0, 0.8)


func status_magnet(pos: Vector3, to_center: Vector3, h: float, delta: float) -> void:
	if randf() < delta * 16.0:
		var back := -to_center.normalized()
		status_emit("streak", pos + Vector3(randf_range(-0.3, 0.3), randf_range(0.3, h), randf_range(-0.3, 0.3)) + back * 0.3,
			back * 6.0, Color(1.0, 0.4, 0.3), 0.8, 0.7)


# ---------------------------------------------------------------- shield dome

## Hex-cell energy dome over home plate while Base Shields are up. Battle toggles its
## visibility and `strength`; VFX animates build-up, hit ripples and the break.
func make_shield_dome() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.5
	sm.height = 2.5
	sm.is_hemisphere = true
	sm.radial_segments = 48
	sm.rings = 14
	mi.mesh = sm
	var m := ShaderMaterial.new()
	m.shader = _shader("fx_dome")
	m.render_priority = 3
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("color", Color(0.3, 0.85, 1.0, 1.0))
	mi.set_instance_shader_parameter("mode", 0.0)
	mi.set_instance_shader_parameter("build", 1.0)
	mi.set_instance_shader_parameter("ripple", Vector4(0, 0, 1, 1))
	add_child(mi)
	_dome = mi
	return mi


func _update_dome(delta: float) -> void:
	if _dome == null or not is_instance_valid(_dome) or battle == null or not ("run" in battle) or battle.run == null:
		return
	var s: int = battle.run.shields
	if _dome_shields < 0:
		_dome_shields = s
	if s != _dome_shields:
		if s > _dome_shields:
			if _dome_shields == 0:
				_dome_build = 0.0
			_dome_ripple = 0.0
			_dome.set_instance_shader_parameter("ripple", Vector4(0, 1, 0, 0))
		else:
			_shield_hit(s == 0)
		_dome_shields = s
	if _dome_build < 1.0:
		_dome_build = minf(1.0, _dome_build + delta / 0.9)
		_dome.set_instance_shader_parameter("build", _dome_build)
	if _dome_ripple < 1.0:
		_dome_ripple = minf(1.0, _dome_ripple + delta / 0.7)
		var r: Vector4 = _dome.get_instance_shader_parameter("ripple")
		_dome.set_instance_shader_parameter("ripple", Vector4(r.x, r.y, r.z, _dome_ripple))


func _shield_hit(broken: bool) -> void:
	var home := Field.HOME
	var from := home + Vector3(0, 0, -6)
	var best := INF
	if "enemies" in battle:
		for e in battle.enemies:
			if is_instance_valid(e):
				var dd: float = Field.v2(e.global_position).distance_to(Field.v2(home))
				if dd < best:
					best = dd
					from = e.global_position
	var dir := (from - home)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.1 else Vector3(0, 0, -1)
	dir = (dir + Vector3(0, 0.45, 0)).normalized()
	_dome_ripple = 0.0
	_dome.set_instance_shader_parameter("ripple", Vector4(dir.x, dir.y, dir.z, 0.0))
	var hit := home + dir * 2.5
	var c := Color(0.4, 0.9, 1.0)
	emit_one("flash", hit, Vector3.ZERO, Color(c, 0.9), 1.0, 1.0)
	spray("spark", hit, 18, c.lerp(Color.WHITE, 0.3), 9.0, dir, 0.8)
	flash_light(hit, c, 5.0, 8.0, 0.35)
	if broken:
		ring_emit("shard", home + Vector3(0, 1.2, 0), 1.8, 18, Color.WHITE, 5.0, 4.0, 0.7, 1.0)
		spray("magic", home + Vector3(0, 1.5, 0), 24, c, 6.0, Vector3.UP, 1.4)
		shockwave(home, 4.5, c, 0.6)
		glyph(home + Vector3(0, 3.2, 0), 15, 1.6, c, 1.0)
