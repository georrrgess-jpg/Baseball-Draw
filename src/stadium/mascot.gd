class_name StadiumMascot
extends Node3D
## "Slugger", the team mascot: a big baseball head with stitches, googly eyes and a cap on a
## jersey-wearing body. Between waves it runs out of the home dugout to a spot in foul territory,
## does a short bit (wave to the crowd, a dance, a jump-spin or a backflip) and runs back.
## It never stays out during a wave: begin_exit() sends it sprinting back to the dugout.
## Built from a handful of vertex-coloured meshes and animated procedurally (no skeleton).

signal bit_started(kind: String)

enum { HIDDEN, RUN_OUT, PERFORM, RUN_BACK }

var home := Vector3.ZERO        # dugout door (start and end of each appearance)
var spot := Vector3.ZERO        # where the bit happens
var state := HIDDEN
var _t := 0.0
var _anim_t := 0.0
var _bit := ""
var _bit_len := 4.0
var _speed := 4.2
var _rng := RandomNumberGenerator.new()

var _body: Node3D
var _head: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _shadow: MeshInstance3D


func build(team: Color, trim: Color, pants: Color) -> void:
	_rng.randomize()
	var mat := StadiumDugout.vc_material()
	_body = Node3D.new()
	add_child(_body)
	# Torso: jersey with a trim belt and a big number.
	var k := MeshKit.new()
	k.color = team
	k.prism(Vector3.ZERO, 0.75, 1.35, Vector2(0.3, 0.24), Vector2(0.34, 0.26), 8, true, true)
	k.color = trim
	k.prism(Vector3.ZERO, 0.72, 0.8, Vector2(0.305, 0.245), Vector2(0.305, 0.245), 8, false)
	k.color = pants
	k.prism(Vector3.ZERO, 0.55, 0.75, Vector2(0.29, 0.23), Vector2(0.3, 0.24), 8, false, true)
	k.color = Color(0.97, 0.96, 0.92)
	k.box(Vector3(0, 1.08, 0.25), Vector3(0.22, 0.26, 0.03))  # chest patch
	k.color = trim
	k.box(Vector3(0, 1.08, 0.267), Vector3(0.05, 0.18, 0.01))  # "1"
	_body.add_child(_mi(k.commit(), mat))
	# Head: the baseball.
	_head = Node3D.new()
	_head.position = Vector3(0, 1.82, 0)
	_body.add_child(_head)
	k = MeshKit.new()
	k.color = Color(0.97, 0.96, 0.92)
	k.sphere(Vector3.ZERO, Vector3(0.52, 0.5, 0.52), 14, 9)
	# Red stitches: two curved seams of short dashes.
	k.color = Color(0.85, 0.1, 0.12)
	for side in [-1.0, 1.0]:
		for i in 15:
			var a := lerpf(-1.5, 1.5, i / 14.0)
			k.box(Vector3(side * 0.4, 0.335 * sin(a), 0.335 * cos(a)) * 1.01, Vector3(0.1, 0.025, 0.025))
	# Eyes (big and friendly), a smile and rosy cheeks.
	for sx in [-1.0, 1.0]:
		k.color = Color(1, 1, 1)
		k.sphere(Vector3(sx * 0.17, 0.08, 0.43), Vector3(0.15, 0.17, 0.1), 8, 5)
		k.color = Color(0.06, 0.06, 0.1)
		k.sphere(Vector3(sx * 0.15, 0.06, 0.52), Vector3(0.065, 0.075, 0.04), 6, 4)
		k.color = Color(1.0, 0.55, 0.55)
		k.sphere(Vector3(sx * 0.3, -0.12, 0.4), Vector3(0.07, 0.05, 0.03), 6, 3)
	k.color = Color(0.55, 0.08, 0.1)
	for i in 7:
		var a := lerpf(-0.9, 0.9, i / 6.0)
		k.box(Vector3(sin(a) * 0.17, -0.2 - cos(a) * 0.06 + 0.06, 0.48 - absf(sin(a)) * 0.05), Vector3(0.06, 0.035, 0.03))
	# Cap with a long brim.
	k.color = team
	k.sphere(Vector3(0, 0.12, 0), Vector3(0.535, 0.48, 0.535), 12, 6, 0.6)
	k.box(Vector3(0, 0.33, 0.52), Vector3(0.6, 0.05, 0.42))
	k.color = trim
	k.sphere(Vector3(0, 0.6, 0), Vector3(0.07, 0.05, 0.07), 6, 3)
	_head.add_child(_mi(k.commit(), mat))
	# Arms (pivot at the shoulder) with big white gloves.
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.38, 1.28, 0)
		_body.add_child(arm)
		k = MeshKit.new()
		k.color = team
		k.cyl(Vector3.ZERO, Vector3(0, -0.3, 0), 0.1, 6)
		k.color = Color(0.97, 0.96, 0.92)
		k.cyl(Vector3(0, -0.3, 0), Vector3(0, -0.55, 0), 0.075, 6)
		k.sphere(Vector3(0, -0.66, 0.02), Vector3(0.14, 0.14, 0.11), 7, 4)
		arm.add_child(_mi(k.commit(), mat))
		if side < 0.0:
			_arm_l = arm
		else:
			_arm_r = arm
	# Legs (pivot at the hip) with big sneakers.
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.15, 0.62, 0)
		_body.add_child(leg)
		k = MeshKit.new()
		k.color = pants
		k.cyl(Vector3.ZERO, Vector3(0, -0.32, 0), 0.12, 6)
		k.color = team.darkened(0.2)
		k.cyl(Vector3(0, -0.32, 0), Vector3(0, -0.52, 0), 0.1, 6)
		k.color = Color(0.95, 0.95, 0.95)
		k.box(Vector3(0, -0.56, 0.07), Vector3(0.2, 0.12, 0.36))
		k.color = trim
		k.box(Vector3(0, -0.61, 0.07), Vector3(0.21, 0.03, 0.37))
		leg.add_child(_mi(k.commit(), mat))
		if side < 0.0:
			_leg_l = leg
		else:
			_leg_r = leg
	_shadow = Enemy._make_blob_shadow(0.7)
	add_child(_shadow)
	scale = Vector3.ONE * 1.05
	visible = false


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi


func is_out() -> bool:
	return state != HIDDEN


## Starts an appearance (ignored if already out). `kind` picks the bit, "" = random.
func appear(kind := "") -> void:
	if state != HIDDEN:
		return
	var bits := ["wave", "dance", "spin", "flip"]
	_bit = kind if kind != "" else bits[_rng.randi() % bits.size()]
	_bit_len = {"wave": 3.2, "dance": 4.0, "spin": 2.6, "flip": 2.4}.get(_bit, 3.0)
	position = home
	visible = true
	state = RUN_OUT
	_speed = 4.2
	_t = 0.0


## Sends the mascot back to the dugout (fast if `hurry`).
func begin_exit(hurry := false) -> void:
	if state == HIDDEN:
		return
	state = RUN_BACK
	_speed = 8.5 if hurry else 4.5


func _process(delta: float) -> void:
	if state == HIDDEN:
		return
	var dt := delta / maxf(Engine.time_scale, 0.05)
	dt = minf(dt, 0.1)
	_anim_t += dt
	match state:
		RUN_OUT:
			if _run_to(spot, dt):
				state = PERFORM
				_t = 0.0
				bit_started.emit(_bit)
		PERFORM:
			_t += dt
			_perform(dt)
			if _t >= _bit_len:
				state = RUN_BACK
				_speed = 4.5
		RUN_BACK:
			if _run_to(home, dt):
				state = HIDDEN
				visible = false


func _run_to(target: Vector3, dt: float) -> bool:
	var to := target - position
	to.y = 0.0
	var d := to.length()
	if d < 0.15:
		_pose_idle()
		return true
	var step := minf(d, _speed * dt)
	position += to / d * step
	var want := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, want, minf(1.0, dt * 10.0))
	# Run cycle: swinging limbs, a bouncy body and a bobbing head.
	var f := _anim_t * (_speed * 2.2)
	_leg_l.rotation = Vector3(sin(f) * 0.9, 0, 0)
	_leg_r.rotation = Vector3(-sin(f) * 0.9, 0, 0)
	_arm_l.rotation = Vector3(-sin(f) * 1.0, 0, -0.25)
	_arm_r.rotation = Vector3(sin(f) * 1.0, 0, 0.25)
	_body.position.y = absf(sin(f)) * 0.12
	_body.rotation = Vector3(0.18, 0, 0)
	_head.rotation = Vector3(0, 0, sin(f * 0.5) * 0.08)
	return false


func _pose_idle() -> void:
	_leg_l.rotation = Vector3.ZERO
	_leg_r.rotation = Vector3.ZERO
	_arm_l.rotation = Vector3(0, 0, -0.2)
	_arm_r.rotation = Vector3(0, 0, 0.2)
	_body.position.y = 0.0
	_body.rotation = Vector3.ZERO
	_head.rotation = Vector3.ZERO


func _perform(dt: float) -> void:
	# Face the camera side of the field (home plate) while performing.
	var to := Vector3(0, 0, 18) - position
	rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(1.0, dt * 6.0))
	var t := _t
	_pose_idle()
	match _bit:
		"wave":
			# Big two-handed wave to the crowd, rocking side to side.
			_arm_r.rotation = Vector3(0, 0, 2.6 + sin(t * 9.0) * 0.45)
			_arm_l.rotation = Vector3(0, 0, -2.6 - sin(t * 9.0 + 1.0) * 0.45)
			_body.rotation.z = sin(t * 4.5) * 0.12
			_head.rotation.z = sin(t * 4.5) * 0.15
		"dance":
			var b := t * 7.0
			_body.position.y = absf(sin(b)) * 0.1
			_body.rotation.y = sin(b * 0.5) * 0.5
			_body.rotation.z = sin(b) * 0.1
			_arm_l.rotation = Vector3(0, 0, -0.6 - 2.0 * maxf(0.0, sin(b * 0.5)))
			_arm_r.rotation = Vector3(0, 0, 0.6 + 2.0 * maxf(0.0, -sin(b * 0.5)))
			_leg_l.rotation.x = maxf(0.0, sin(b)) * 0.6
			_leg_r.rotation.x = maxf(0.0, -sin(b)) * 0.6
			_head.rotation.x = sin(b) * 0.12
		"spin":
			# Crouch, jump with a full spin, land with arms up.
			var k := clampf((t - 0.5) / 1.1, 0.0, 1.0)
			var crouch := clampf(t / 0.5, 0.0, 1.0) if t < 0.5 else 0.0
			_body.position.y = -crouch * 0.15 + sin(k * PI) * 1.3
			_body.rotation.y = smoothstep(0.0, 1.0, k) * TAU
			var arms := 2.7 if k > 0.0 else 0.4
			_arm_l.rotation = Vector3(0, 0, -arms)
			_arm_r.rotation = Vector3(0, 0, arms)
			_leg_l.rotation.x = sin(k * PI) * 0.5
			_leg_r.rotation.x = -sin(k * PI) * 0.3
		"flip":
			# A backflip: jump and rotate backwards about the hips.
			var k := clampf((t - 0.35) / 1.0, 0.0, 1.0)
			_body.position.y = sin(k * PI) * 1.6
			_body.rotation.x = -smoothstep(0.0, 1.0, k) * TAU
			var tuck := sin(k * PI)
			_leg_l.rotation.x = -tuck * 1.4
			_leg_r.rotation.x = -tuck * 1.4
			_arm_l.rotation = Vector3(-tuck * 1.2, 0, -0.3 - (2.4 if k >= 1.0 else 0.0))
			_arm_r.rotation = Vector3(-tuck * 1.2, 0, 0.3 + (2.4 if k >= 1.0 else 0.0))
	_shadow.scale = Vector3.ONE * clampf(1.0 - _body.position.y * 0.35, 0.4, 1.0)
