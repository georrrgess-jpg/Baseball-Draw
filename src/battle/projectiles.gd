class_name ProjectileManager
extends Node3D
## Pooled baseballs with ribbon trails. Balls fly on a shallow arc toward a
## (moving) runner or a fixed point, then resolve hits, misses, splash,
## ricochets and lightning chains.

const MAX_TRAIL := 12

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

var battle: Battle
var balls: Array[Ball] = []
var _ball_mesh: Mesh
var _ball_mat: StandardMaterial3D
var _trail_mat: StandardMaterial3D
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
	_trail_mat = StandardMaterial3D.new()
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_mat.disable_receive_shadows = true
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
	b.node.visible = false
	b.trail.visible = false
	return b


func _get_ball() -> Ball:
	for b in balls:
		if not b.active and b.fading <= 0.0:
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
	b.points.clear()
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
	b.node.global_position = pos
	b.mesh.rotate_x(delta * 30.0)
	b.points.push_front(pos)
	if b.points.size() > MAX_TRAIL:
		b.points.pop_back()
	_draw_trail(b)
	if k >= 1.0:
		b.active = false
		b.node.visible = false
		b.fading = 0.25
		_arrive(b)


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
		var w := b.width * f
		var c := Color(b.color.r, b.color.g, b.color.b, f * 0.9)
		b.imesh.surface_set_color(c)
		b.imesh.surface_add_vertex(p + side * w)
		b.imesh.surface_set_color(c)
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
	hit(t, p, b.end)


## Resolves a thrown ball against a runner.
func hit(t: Enemy, p: Dictionary, at: Vector3) -> void:
	var evasion := t.evasion
	if battle.field_vision_active:
		evasion = 0.0
	var miss_chance := clampf(evasion * (1.15 - float(p.get("accuracy", 80.0)) / 100.0), 0.0, 0.9)
	if randf() < miss_chance:
		battle.vfx.text_popup(at + Vector3(0, 0.5, 0), "MISS", Color(0.75, 0.8, 0.9), 0.8)
		Audio.play("swing_whoosh", -16.0, 0.1, 120)
		return
	var source: Defender = p.get("source")
	var dealt := t.take_damage(float(p.damage), {"source": source, "kind": "fire" if p.get("fire", false) else "throw",
		"crit": p.get("crit", false), "pierce": p.get("pierce", 0.0)})
	battle.on_damage_dealt(source, t, dealt, p.get("crit", false))
	Audio.play("crit_hit" if p.get("crit", false) else "ball_hit", -5.0 if p.get("crit", false) else -9.0, 0.08, 40)
	battle.vfx.burst("crit" if p.get("crit", false) else "hit", at, p.get("color", Color.WHITE))
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
				var sd := e.take_damage(float(p.damage) * 0.6, {"source": source, "kind": "splash"})
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
	if int(p.get("chain", 0)) > 0:
		var cp0 := p.duplicate()
		cp0.chained = [t]
		hit_chain_continue(t, cp0, at)


func hit_chain_continue(t: Enemy, p: Dictionary, at: Vector3) -> void:
	var chained: Array = p.get("chained", [t])
	var nxt := battle.nearest_enemy(at, 7.0, chained)
	if nxt == null:
		return
	var cp := p.duplicate()
	cp.chain = int(p.chain) - 1
	cp.damage = float(p.damage) * float(p.get("chain_mult", 0.5))
	cp.chained = chained + [nxt]
	battle.vfx.lightning(at, nxt.center(), Color(1.0, 0.95, 0.4))
	var dealt := nxt.take_damage(float(cp.damage), {"source": p.get("source"), "kind": "lightning"})
	battle.on_damage_dealt(p.get("source"), nxt, dealt, false)
	if cp.chain > 0:
		hit_chain_continue(nxt, cp, nxt.center())


func clear_all() -> void:
	for b in balls:
		b.active = false
		b.fading = 0.0
		b.node.visible = false
		b.trail.visible = false
		b.points.clear()
