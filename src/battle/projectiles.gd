class_name ProjectileManager
extends Node3D
## Pooled baseballs with ribbon trails. Balls fly on a shallow arc toward a
## (moving) runner or a fixed point, then resolve hits, misses, splash,
## ricochets and lightning chains.
## Cosmetic payload keys (never read by gameplay): "trail" picks a trail style
## (comet, fire, spiral, wobble, hook, heavy) and "fx" an impact effect drawn by
## battle.vfx.cards.ball_impact(). Spiral / wobble only offset the drawn ball; the
## flight time and landing point are unchanged.

const MAX_TRAIL := 12
const TRAIL_M := {"comet": 5.0, "fire": 4.5, "spiral": 6.0, "wobble": 6.0, "hook": 9.0, "heavy": 5.0}
const TRAIL_LEN := {"comet": 18, "fire": 16, "spiral": 24, "wobble": 22, "hook": 44, "heavy": 18}
## Defender throws (no card trail): trail length in metres, width multiplier and a sparkle
## [system, chance per 30 fps frame, size, life] per thrower trait, so every defender's
## throw reads in their own accent colour and flavour.
const STYLE_M := {"precision": 6.5, "cannon_arm": 4.8, "heavy_hitter": 4.6, "fastball": 4.6}
const STYLE_W := {"precision": 0.85, "cannon_arm": 1.45, "heavy_hitter": 1.2, "quick_hands": 0.95, "long_stretch": 1.25,
	"skipper": 1.05}
const STYLE_FX := {
	"fastball": ["ember", 0.6, 1.0, 0.7],
	"home_guard": ["glow", 0.35, 0.45, 0.45],
	"quick_hands": ["streak", 0.45, 0.6, 0.5],
	"cannon_arm": ["spark", 0.5, 0.75, 0.5],
	"precision": ["glow", 0.4, 0.35, 0.5],
	"heavy_hitter": ["magic", 0.55, 0.75, 0.6],
	"static_charge": ["spark", 0.8, 0.7, 0.35],
	"pickoff_artist": ["streak", 0.5, 0.6, 0.5],
	"gap_shooter": ["magic", 0.55, 0.7, 0.6],
	"long_stretch": ["glow", 0.4, 0.6, 0.5],
	"pitch_framing": ["magic", 0.4, 0.55, 0.5],
	"skipper": ["streak", 0.55, 0.55, 0.45],
}

class Ball:
	var node: Node3D
	var mesh: MeshInstance3D
	var trail: MeshInstance3D
	var imesh: ImmediateMesh
	var points: Array[Vector3] = []
	var active := false
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var target: Enemy = null
	var t := 0.0
	var duration := 0.5
	var arc := 1.0
	var payload: Dictionary = {}
	var on_arrive: Callable
	var color := Color.WHITE
	var width := 0.12
	var fading := 0.0
	var glow: MeshInstance3D
	var glow_mat: StandardMaterial3D
	var trail_kind := ""
	var max_trail := MAX_TRAIL
	var side := Vector3.RIGHT
	var bounce_t := 0.0          # > 0 while the ball glances off a runner (cosmetic)
	var style := ""              # defender throw style (the thrower's trait), cosmetic
	var hot := false             # draw a bright inner core along the trail
	var bounce_v := Vector3.ZERO

var battle: Battle
var balls: Array[Ball] = []
var _ball_mesh: Mesh
var _ball_mat: StandardMaterial3D
var _trail_mat: ShaderMaterial
var _trail_mat_acc: ShaderMaterial   # defender throws: narrower white core, wider accent glow
var _glow_tex: Texture2D
var _camera: Camera3D


func _ready() -> void:
	var path := "res://assets/models/props/baseball.glb"
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = Color(0.98, 0.97, 0.93)
	_ball_mat.roughness = 0.45
	_ball_mat.emission_enabled = true
	_ball_mat.emission = Color(1, 1, 1)
	_ball_mat.emission_energy_multiplier = 0.25
	var sm := SphereMesh.new()
	sm.radius = 0.13
	sm.height = 0.26
	sm.radial_segments = 16
	sm.rings = 8
	_ball_mesh = sm
	if ResourceLoader.exists(path):
		var inst: Node = (load(path) as PackedScene).instantiate()
		var mi := _first_mesh(inst)
		if mi and mi.mesh:
			_ball_mesh = mi.mesh
		inst.free()
	# Glowing ribbon: white-hot core, coloured falloff (shared with the VFX bolts).
	_trail_mat = ShaderMaterial.new()
	_trail_mat.shader = load("res://assets/shaders/vfx/fx_bolt.gdshader")
	_trail_mat.set_shader_parameter("core_width", 0.24)
	_trail_mat.render_priority = 4
	_trail_mat_acc = _trail_mat.duplicate() as ShaderMaterial
	_trail_mat_acc.set_shader_parameter("core_width", 0.13)
	_trail_mat_acc.set_shader_parameter("energy", 1.5)
	_glow_tex = load("res://assets/textures/vfx/glow.png")
	for i in 48:
		balls.append(_make_ball())


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r:
			return r
	return null


func _make_ball() -> Ball:
	var b := Ball.new()
	b.node = Node3D.new()
	add_child(b.node)
	b.mesh = MeshInstance3D.new()
	b.mesh.mesh = _ball_mesh
	b.mesh.material_override = _ball_mat if _ball_mesh is SphereMesh else null
	if not (_ball_mesh is SphereMesh):
		b.mesh.scale = Vector3.ONE * 3.2
	b.mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	b.node.add_child(b.mesh)
	b.imesh = ImmediateMesh.new()
	b.trail = MeshInstance3D.new()
	b.trail.mesh = b.imesh
	b.trail.material_override = _trail_mat
	b.trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.trail.top_level = true
	add_child(b.trail)
	# Halo around coloured / special balls.
	b.glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	b.glow.mesh = q
	b.glow_mat = StandardMaterial3D.new()
	b.glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b.glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b.glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	b.glow_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	b.glow_mat.albedo_texture = _glow_tex
	b.glow_mat.no_depth_test = false
	b.glow_mat.render_priority = 4
	b.glow.material_override = b.glow_mat
	b.glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	b.node.add_child(b.glow)
	b.node.visible = false
	b.trail.visible = false
	return b


func _get_ball() -> Ball:
	for b in balls:
		if not b.active and b.fading <= 0.0 and b.bounce_t <= 0.0:
			return b
	var nb := _make_ball()
	balls.append(nb)
	return nb


func _prepare(b: Ball, from: Vector3, to: Vector3, speed: float, payload: Dictionary) -> void:
	b.active = true
	b.start = from
	b.end = to
	b.t = 0.0
	var dist := from.distance_to(to)
	b.duration = clampf(dist / maxf(speed, 1.0), 0.08, 3.0)
	b.arc = clampf(dist * (0.09 if not payload.get("big", false) else 0.16), 0.15, 3.0) * float(payload.get("arc_mult", 1.0))
	b.payload = payload
	b.color = payload.get("color", Color.WHITE)
	if payload.get("fire", false):
		b.color = Color(1.0, 0.45, 0.1)
	b.width = 0.16 if payload.get("big", false) or payload.get("fastball", false) else 0.11
	b.trail_kind = String(payload.get("trail", ""))
	b.max_trail = int(TRAIL_LEN.get(b.trail_kind, MAX_TRAIL))
	if b.trail_kind in ["comet", "hook", "heavy"]:
		b.width *= 1.7
	elif b.trail_kind == "fire":
		b.width *= 2.6
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	b.side = flat.cross(Vector3.UP).normalized() if flat.length() > 0.01 else Vector3.RIGHT
	# Defender throws: the trail takes the thrower's accent, saturated, with a hot core.
	var src = payload.get("source")
	b.style = ""
	if b.trail_kind == "" and is_instance_valid(src) and src is Defender:
		b.style = String(src.trait_id) if payload.get("fire", false) or src.trait_id != "fastball" else "ace"
		if b.color.s > 0.12:
			b.color = Color.from_hsv(b.color.h, clampf(b.color.s * 1.15, 0.7, 1.0), 1.0)
		b.width *= 1.6 * float(STYLE_W.get(b.style, 1.0))
	b.trail.material_override = _trail_mat_acc if b.style != "" else _trail_mat
	var special: bool = b.trail_kind != "" or payload.has("color") or bool(payload.get("fire", false))
	b.hot = special
	b.trail.set_instance_shader_parameter("intensity", 1.0)
	b.glow.visible = special
	if special:
		var gs := 2.4 if b.trail_kind == "fire" else (1.3 if b.trail_kind in ["comet", "hook", "heavy"] else (1.05 if b.style != "" else 0.8))
		if b.style == "fastball":
			gs = 1.6
		b.glow.scale = Vector3.ONE * gs
		var gc := b.color.lerp(Color.WHITE, 0.25)
		gc.a = 0.9
		b.glow_mat.albedo_color = gc
	b.points.clear()
	b.bounce_t = 0.0
	b.node.scale = Vector3.ONE
	b.node.visible = true
	b.trail.visible = true
	b.node.global_position = from
	b.mesh.scale = (Vector3.ONE * (1.35 if payload.get("big", false) else 1.0)) * (3.2 if not (_ball_mesh is SphereMesh) else 1.0)


## Throws at a runner (homing on its current position).
func launch(from: Vector3, target: Enemy, speed: float, payload: Dictionary) -> void:
	var b := _get_ball()
	_prepare(b, from, target.center(), speed, payload)
	b.target = target
	b.on_arrive = Callable()


## Throws at a fixed point and calls on_arrive(position) when it lands.
func launch_at(from: Vector3, to: Vector3, speed: float, payload: Dictionary, on_arrive: Callable) -> void:
	var b := _get_ball()
	_prepare(b, from, to, speed, payload)
	b.target = null
	b.on_arrive = on_arrive


func tick(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	for b in balls:
		if b.bounce_t > 0.0 and not b.active:
			_bounce(b, delta)
		if b.active:
			_step(b, delta)
		elif b.fading > 0.0:
			b.fading -= delta
			if b.points.size() > 0:
				b.points.pop_back()
			_draw_trail(b)
			if b.fading <= 0.0 or b.points.is_empty():
				b.fading = 0.0
				b.trail.visible = false


func _step(b: Ball, delta: float) -> void:
	if b.target != null:
		if is_instance_valid(b.target) and b.target.alive:
			b.end = b.target.center()
	b.t += delta
	var k := clampf(b.t / b.duration, 0.0, 1.0)
	var pos := b.start.lerp(b.end, k)
	pos.y += sin(k * PI) * b.arc
	if b.trail_kind != "":
		pos += _visual_offset(b, k)
		_trail_particles(b, pos, delta)
	elif b.style != "":
		_style_particles(b, pos, delta)
	b.node.global_position = pos
	b.mesh.rotate_x(delta * 30.0)
	b.points.push_front(pos)
	if b.points.size() > b.max_trail * 2:
		b.points.pop_back()
	_trim_trail(b)
	_draw_trail(b)
	if k >= 1.0:
		b.active = false
		b.node.visible = false
		b.fading = 0.25
		_arrive(b)


## Deflection after a hit (or a whiff past the runner on a miss): the drawn ball flies
## off under gravity and shrinks away. Purely visual.
func _start_bounce(b: Ball, hit_target: bool) -> void:
	var d := b.end - b.start
	d.y = 0.0
	d = d.normalized() if d.length_squared() > 0.0001 else Vector3.FORWARD
	var side := d.cross(Vector3.UP)
	if hit_target:
		b.bounce_v = -d * randf_range(1.5, 3.0) + Vector3.UP * randf_range(4.5, 6.0) + side * randf_range(-2.2, 2.2)
	else:
		b.bounce_v = d * 12.0 + Vector3.UP * 1.0 + side * randf_range(-1.0, 1.0)
	b.bounce_t = 0.5 if hit_target else 0.3
	b.node.visible = true
	b.glow.visible = false
	b.node.global_position = b.end


func _bounce(b: Ball, delta: float) -> void:
	b.bounce_t -= delta
	b.bounce_v.y -= 18.0 * delta
	b.node.global_position += b.bounce_v * delta
	b.mesh.rotate_x(delta * 25.0)
	b.node.scale = Vector3.ONE * clampf(b.bounce_t / 0.15, 0.0, 1.0)
	if b.bounce_t <= 0.0:
		b.bounce_t = 0.0
		b.node.visible = false
		b.node.scale = Vector3.ONE


## Cosmetic sway of the drawn ball (spiral curveball, fluttering knuckleball).
func _visual_offset(b: Ball, k: float) -> Vector3:
	var env := sin(k * PI)
	match b.trail_kind:
		"spiral":
			var a := k * TAU * 2.5
			return (b.side * cos(a) + Vector3.UP * sin(a)) * 0.75 * env
		"wobble":
			return b.side * sin(k * 27.0) * 0.5 * env + Vector3.UP * sin(k * 17.0) * 0.25 * env
	return Vector3.ZERO


func _trail_particles(b: Ball, pos: Vector3, delta: float) -> void:
	var vfx = battle.vfx
	var sc: float = vfx._scale
	match b.trail_kind:
		"fire":
			for i in 3:
				if randf() < sc:
					var back := (b.start - b.end).normalized() * randf_range(0.0, 0.8)
					vfx.emit_one("fire", pos + back + Vector3(randf_range(-0.15, 0.15), randf_range(-0.15, 0.15), randf_range(-0.15, 0.15)), Vector3(randf_range(-0.5, 0.5), 1.5, randf_range(-0.5, 0.5)), Color(1.0, 0.45, 0.08), randf_range(0.9, 1.3), randf_range(0.5, 0.75))
			if randf() < 0.5 * sc:
				vfx.emit_one("smoke", pos, Vector3(0, 0.8, 0), Color(0.16, 0.13, 0.12, 0.5), 0.8, 0.8)
			if randf() < 0.6 * sc:
				vfx.emit_one("ember", pos, Vector3(randf_range(-1, 1), randf_range(-0.5, 1.5), randf_range(-1, 1)), Color(1.0, 0.6, 0.2), 1.0, 0.7)
		"comet":
			if randf() < 0.7 * sc:
				vfx.emit_one("glow", pos, Vector3.ZERO, Color(b.color, 0.6), 0.6, 0.4)
			if randf() < 0.4 * sc:
				vfx.emit_one("spark", pos, Vector3(randf_range(-2, 2), randf_range(-1, 2), randf_range(-2, 2)), b.color.lerp(Color.WHITE, 0.4), 0.7, 0.5)
		"spiral", "wobble", "heavy":
			if randf() < 0.5 * sc:
				vfx.emit_one("magic", pos, Vector3(randf_range(-0.5, 0.5), 0.3, randf_range(-0.5, 0.5)), b.color.lerp(Color.WHITE, 0.3), 0.7, 0.7)
		"hook":
			if randf() < 0.6 * sc:
				vfx.emit_one("magic", pos, Vector3(0, -0.3, 0), Color(0.6, 0.95, 1.0), 0.8, 1.0)


## Defender throws: a little sparkle in the thrower's colour and flavour (embers for Ace's
## fastball, crackles for Nova, chevron streaks for Dex...). Rates are per 30 fps frame.
func _style_particles(b: Ball, pos: Vector3, delta: float) -> void:
	var vfx = battle.vfx
	var r: float = delta * 30.0 * float(vfx._scale)
	if b.style == "fastball":
		# Ace's fastball: a burning ball.
		for i in 2:
			if randf() < r:
				vfx.emit_one("fire", pos + Vector3(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12), randf_range(-0.12, 0.12)),
					Vector3(randf_range(-0.4, 0.4), 1.2, randf_range(-0.4, 0.4)), Color(1.0, 0.42, 0.08), randf_range(0.6, 0.9), 0.55)
	var fx: Array = STYLE_FX.get(b.style, [])
	if fx.is_empty() or randf() >= float(fx[1]) * r:
		return
	var back := (b.start - b.end)
	back.y = 0.0
	back = back.normalized() if back.length_squared() > 0.0001 else Vector3.BACK
	var c := b.color.lerp(Color.WHITE, 0.3)
	var v := Vector3(randf_range(-0.6, 0.6), randf_range(-0.2, 0.8), randf_range(-0.6, 0.6))
	match String(fx[0]):
		"streak":
			v = back * 5.0
		"spark":
			v = Vector3(randf_range(-3, 3), randf_range(-1.5, 3), randf_range(-3, 3))
			if b.style == "static_charge":
				c = Color(1.0, 0.97, 0.6)
	vfx.emit_one(String(fx[0]), pos, v, c, float(fx[2]), float(fx[3]))


## Trails are capped by length in metres rather than by point count, so they look the same
## at any frame rate (a 30 fps frame used to stretch a plain throw's trail to ~10 m).
func _trim_trail(b: Ball) -> void:
	var max_len: float = TRAIL_M.get(b.trail_kind, 3.6) if b.style == "" else float(STYLE_M.get(b.style, 4.2))
	var total := 0.0
	for i in range(1, b.points.size()):
		total += b.points[i].distance_to(b.points[i - 1])
		if total > max_len:
			b.points.resize(i + 1)
			return


func _draw_trail(b: Ball) -> void:
	b.imesh.clear_surfaces()
	if b.points.size() < 2 or _camera == null:
		return
	var cam := _camera.global_position
	b.imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := b.points.size()
	for i in n:
		var p: Vector3 = b.points[i]
		var nxt: Vector3 = b.points[mini(i + 1, n - 1)]
		var prv: Vector3 = b.points[maxi(i - 1, 0)]
		var dir := (prv - nxt)
		if dir.length_squared() < 0.000001:
			dir = Vector3.FORWARD
		var side := dir.cross(cam - p).normalized()
		var f := 1.0 - float(i) / float(n)
		var w := b.width * (0.25 + 0.75 * f)
		var c := Color(b.color.r, b.color.g, b.color.b, f * f * 0.95)
		b.imesh.surface_set_color(c)
		b.imesh.surface_set_uv(Vector2(0, f))
		b.imesh.surface_add_vertex(p + side * w)
		b.imesh.surface_set_color(c)
		b.imesh.surface_set_uv(Vector2(1, f))
		b.imesh.surface_add_vertex(p - side * w)
	b.imesh.surface_end()
	if not b.hot or n < 3:
		return
	# Hot core: a thin, near-white strip down the middle of the front half of the trail.
	var m := maxi(3, int(n * 0.6))
	var hc := b.color.lerp(Color(1.0, 0.98, 0.9), 0.45)
	b.imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in m:
		var p: Vector3 = b.points[i]
		var nxt: Vector3 = b.points[mini(i + 1, n - 1)]
		var prv: Vector3 = b.points[maxi(i - 1, 0)]
		var dir := (prv - nxt)
		if dir.length_squared() < 0.000001:
			dir = Vector3.FORWARD
		var side := dir.cross(cam - p).normalized()
		var f := 1.0 - float(i) / float(m)
		var w := b.width * 0.3 * (0.3 + 0.7 * f)
		var c := Color(hc.r, hc.g, hc.b, f * 0.9)
		b.imesh.surface_set_color(c)
		b.imesh.surface_set_uv(Vector2(0, f))
		b.imesh.surface_add_vertex(p + side * w)
		b.imesh.surface_set_color(c)
		b.imesh.surface_set_uv(Vector2(1, f))
		b.imesh.surface_add_vertex(p - side * w)
	b.imesh.surface_end()


func _arrive(b: Ball) -> void:
	if b.on_arrive.is_valid():
		b.on_arrive.call(b.end)
		return
	var t := b.target
	var p := b.payload
	if t == null or not is_instance_valid(t) or not t.targetable():
		# The runner is gone: re-aim at a nearby runner if possible.
		var alt := battle.nearest_enemy(b.end, 3.5)
		if alt and not p.get("retargeted", false):
			p.retargeted = true
			launch(b.end, alt, 22.0, p)
		else:
			battle.vfx.dust(Vector3(b.end.x, 0, b.end.z), 0.4)
		return
	p["_dir"] = b.end - b.start
	var landed := hit(t, p, b.end)
	if not p.get("_skipped", false):
		_start_bounce(b, landed)


## Resolves a thrown ball against a runner. Returns false on a miss.
func hit(t: Enemy, p: Dictionary, at: Vector3) -> bool:
	var evasion := t.evasion
	if battle.field_vision_active:
		evasion = 0.0
	var miss_chance := clampf(evasion * (1.15 - float(p.get("accuracy", 80.0)) / 100.0), 0.0, 0.9)
	if randf() < miss_chance:
		battle.vfx.text_popup(at + Vector3(0, 0.5, 0), "MISS", Color(0.75, 0.8, 0.9), 0.8)
		Audio.play("swing_whoosh", -16.0, 0.1, 120)
		return false
	var source: Defender = p.get("source")
	# dir / at / color only drive the runner's hit reaction (Enemy._hit_feedback).
	var dealt := t.take_damage(float(p.damage), {"source": source, "kind": "fire" if p.get("fire", false) else "throw",
		"crit": p.get("crit", false), "pierce": p.get("pierce", 0.0), "dir": p.get("_dir", Vector3.ZERO), "at": at,
		"color": p.get("color", Color.WHITE), "card": p.get("card", "")})
	battle.on_damage_dealt(source, t, dealt, p.get("crit", false))
	Audio.play("crit_hit" if p.get("crit", false) else "ball_hit", -4.0 if p.get("crit", false) else -7.0, 0.08, 40)
	if p.get("crit", false):
		battle.vfx.burst("crit", at, p.get("color", Color.WHITE))
		battle.cam.punch(0.35)
	if p.has("fx"):
		battle.vfx.cards.ball_impact(String(p.fx), at, p.get("color", Color.WHITE), t)
	if p.has("burn") and t.alive:
		var bv: Vector2 = p.burn
		t.apply_burn(bv.x, bv.y, source)
	if p.has("stun") and t.alive:
		t.apply_stun(float(p.stun))
	if p.has("knockback") and t.alive:
		t.knockback(float(p.knockback))
	if p.has("splash"):
		var r := float(p.splash)
		battle.vfx.shockwave(Vector3(at.x, 0.05, at.z), r, Color(0.75, 0.5, 1.0), 0.35)
		for e: Enemy in battle.enemies_in_radius(at, r):
			if e != t:
				var sd := e.take_damage(float(p.damage) * 0.5, {"source": source, "kind": "splash", "dir": e.global_position - at})
				battle.on_damage_dealt(source, e, sd, false)
				if p.has("stun") and e.alive:
					e.apply_stun(float(p.stun))
	if p.has("ricochet") and float(p.ricochet) > 0.0 and not p.get("is_ricochet", false):
		var nxt := battle.nearest_enemy(at, 6.0, [t])
		if nxt:
			var rp := p.duplicate()
			rp.damage = float(p.damage) * float(p.ricochet)
			rp.is_ricochet = true
			rp.erase("splash")
			launch(at, nxt, 26.0, rp)
	if float(p.get("skip", 0.0)) > 0.0 and not p.get("is_skip", false):
		_skip(t, p, at)
	if int(p.get("chain", 0)) > 0:
		var cp0 := p.duplicate()
		cp0.chained = [t]
		hit_chain_continue(t, cp0, at)
	return true


## Skipper (Sid): the ball drops past the runner it hit, skips off the dirt along its line of
## flight and hits one runner behind (within skip_range m) for `skip` x the damage.
func skip_target(t: Enemy, dir: Vector3, r: float) -> Enemy:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.0001:
		return null
	d = d.normalized()
	var best: Enemy = null
	var best_d := r
	for e in battle.enemies:
		if e == t or not e.targetable() or e.id == "decoy":
			continue
		var to := e.global_position - t.global_position
		to.y = 0.0
		var dist := to.length()
		if dist > best_d:
			continue
		# Behind the target along the throw (a wide cone; runners on top of it always count).
		if dist > 0.4 and to.normalized().dot(d) < 0.25:
			continue
		best_d = dist
		best = e
	return best


func _skip(t: Enemy, p: Dictionary, at: Vector3) -> void:
	var dir: Vector3 = p.get("_dir", Vector3.ZERO)
	var src = p.get("source")
	if dir.length_squared() < 0.0001 and is_instance_valid(src) and src is Node3D:
		dir = at - (src as Node3D).global_position
	var nxt := skip_target(t, dir, float(p.get("skip_range", 4.0)))
	var d := Vector3(dir.x, 0.0, dir.z).normalized() if Vector3(dir.x, 0.0, dir.z).length_squared() > 0.0001 else Vector3.FORWARD
	var gap := 1.6
	if nxt:
		gap = clampf(Field.v2(nxt.global_position).distance_to(Field.v2(t.global_position)) * 0.45, 0.5, 1.8)
	var bounce := Vector3(at.x, 0.12, at.z) + d * gap
	var sp := p.duplicate()
	sp.damage = float(p.damage) * float(p.skip)
	sp.is_skip = true
	sp.crit = false
	sp.arc_mult = 0.35
	for k in ["splash", "ricochet", "chain", "fx", "_skipped", "_dir"]:
		sp.erase(k)
	p["_skipped"] = true
	var col: Color = p.get("color", Color.WHITE)
	# First leg: down to the dirt; then a low hop into the runner behind (or off along the line).
	launch_at(at, bounce, 24.0, {"source": src, "color": col, "arc_mult": 0.25}, func(pos: Vector3) -> void:
		battle.vfx.dust(Vector3(pos.x, 0.0, pos.z), 0.7)
		battle.vfx.impact_ring(Vector3(pos.x, 0.08, pos.z), Vector3.UP, col, 0.7, 0.3)
		if is_instance_valid(nxt) and nxt.targetable():
			launch(pos, nxt, 22.0, sp)
		else:
			launch_at(pos, pos + d * 2.5 + Vector3(0, -0.1, 0), 16.0, {"source": src, "color": col, "arc_mult": 0.4},
				func(p2: Vector3) -> void: battle.vfx.dust(Vector3(p2.x, 0.0, p2.z), 0.4)))
	Audio.play("ball_hit", -14.0, 0.15, 60)


func hit_chain_continue(t: Enemy, p: Dictionary, at: Vector3) -> void:
	var chained: Array = p.get("chained", [t])
	var nxt := battle.nearest_enemy(at, 7.0, chained)
	if nxt == null:
		return
	var cp := p.duplicate()
	cp.chain = int(p.chain) - 1
	cp.damage = float(p.damage) * float(p.get("chain_mult", 0.5))
	cp.chained = chained + [nxt]
	battle.vfx.cards.chain_arc(at, nxt.center(), Color(1.0, 0.95, 0.4))
	var dealt := nxt.take_damage(float(cp.damage), {"source": p.get("source"), "kind": "lightning", "dir": nxt.center() - at,
		"color": Color(1.0, 0.95, 0.4), "card": p.get("card", "")})
	battle.on_damage_dealt(p.get("source"), nxt, dealt, false)
	if cp.chain > 0:
		hit_chain_continue(nxt, cp, nxt.center())


func clear_all() -> void:
	for b in balls:
		b.active = false
		b.fading = 0.0
		b.bounce_t = 0.0
		b.node.visible = false
		b.trail.visible = false
		b.points.clear()
