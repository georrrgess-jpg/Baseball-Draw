extends RefCounted
## Bespoke visual sequences for every ability card (anticipation -> impact -> aftermath),
## built from the VFX primitives. Purely cosmetic: gameplay is resolved in
## card_effects.gd at the same moments as before; these functions only draw.
## Debug: `-- --test-battle=practice --vfx-showcase=<card_id>` spawns a pack of runners
## and casts the card (see showcase()).

const FIRE := Color(1.0, 0.45, 0.08)
const GOLD := Color(1.0, 0.82, 0.3)
const VIOLET := Color(0.62, 0.42, 1.0)
const ICE := Color(0.55, 0.88, 1.0)
const TEAL := Color(0.2, 1.0, 0.8)
const PINK := Color(1.0, 0.42, 0.72)
const CYAN := Color(0.3, 0.85, 1.0)
const LOCK_BLUE := Color(0.35, 0.68, 1.0)
const MAGNET_RED := Color(1.0, 0.3, 0.25)

var vfx: VFX
var battle: Battle


func _init(p_vfx: VFX) -> void:
	vfx = p_vfx
	battle = p_vfx.battle as Battle


## Bigger, brighter, louder with rarity: commons crisp, legendaries huge.
static func rarity_scale(card_id: String) -> float:
	return {"common": 0.8, "uncommon": 0.9, "rare": 1.0, "epic": 1.15, "legendary": 1.35}.get(String(DB.card(card_id).get("rarity", "common")), 1.0)


static func card_color(card_id: String) -> Color:
	return DB.category_color(String(DB.card(card_id).get("category", "")))


func _dt() -> float:
	return vfx.get_process_delta_time()


func _rate(per_sec: float) -> bool:
	return randf() < per_sec * _dt() * vfx._scale


func _flat(p: Vector3, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.z)


## A punchy point impact: flash sprite, light, sparks, ring.
func impact_flash(pos: Vector3, color: Color, size := 1.0, light := 5.0, sparks := 14) -> void:
	vfx.emit_one("flash", pos, Vector3.ZERO, Color(color.lerp(Color.WHITE, 0.35), 0.95), size, 1.0)
	vfx.emit_one("ring", pos, Vector3.ZERO, color, size * 1.1, 1.0)
	vfx.spray("spark", pos, sparks, color.lerp(Color.WHITE, 0.3), 9.0 * sqrt(size), Vector3.UP, 1.3, 1.0)
	if light > 0.0:
		vfx.flash_light(pos + Vector3(0, 0.6, 0), color, light, 6.0 + 4.0 * size, 0.3)


# ---------------------------------------------------------------- anticipation

## Wind-up shown while a defender plays its cast animation (before the impact frame).
func anticipate(card_id: String, caster: Node3D, face_point: Vector3, windup: float, anim: String) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var col := card_color(card_id)
	var hand: Vector3 = caster.model.hand_position()
	var feet := _flat(caster.global_position)
	var s := rarity_scale(card_id)
	match card_id:
		"heat_wave":
			col = FIRE
		"thunderbolt":
			col = Color(1.0, 0.92, 0.35)
		"grand_relay":
			col = GOLD
		"power_catch":
			col = VIOLET
		"pickoff":
			col = TEAL
		"lockdown":
			col = LOCK_BLUE
		"diving_catch":
			col = PINK
		"twin_play":
			col = Color(0.35, 1.0, 0.55)
		"sky_hook":
			col = CYAN
	if anim != "special":
		# Quick throw: a spark of power gathering in the throwing hand.
		vfx.emit_one("glow", hand, Vector3.ZERO, Color(col.lerp(Color.WHITE, 0.3), 0.9), 1.2, windup * 2.0)
		vfx.spray("streak", hand, 6, col, 4.0, Vector3.UP, 1.0, 0.6, 0.5)
		return
	# Cast circle under the caster, energy streaming into the hand.
	vfx.decal("runes", feet, 1.4 * s, Color(col, 0.9), Color.WHITE, windup + 0.45, func(n: Node3D, k: float) -> void:
		var tt := k * (windup + 0.45)
		var grow := 1.0 - pow(1.0 - clampf(tt / 0.25, 0.0, 1.0), 3.0)
		n.scale = Vector3.ONE * 1.4 * s * (0.4 + 0.6 * grow)
		var flare := smoothstep(windup - 0.15, windup, tt) * (1.0 - smoothstep(windup, windup + 0.45, tt))
		var vis := grow * (1.0 - smoothstep(windup + 0.1, windup + 0.45, tt))
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, -tt * 3.0, flare)))
	for i in vfx._count(int(14 * s)):
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.3, 1), randf_range(-1, 1)).normalized()
		var start := hand + dir * randf_range(1.2, 2.2)
		vfx.emit_one("streak", start, (hand - start) / 0.32, col.lerp(Color.WHITE, 0.2), 0.8, 0.9)
	vfx.every_frame(windup, func(k: float) -> void:
		var h: Vector3 = caster.model.hand_position() if is_instance_valid(caster) else hand
		_charge_tick(card_id, h, k, col))
	match card_id:
		"lockdown":
			# The seal is already being drawn on the ground at the target.
			vfx.decal("runes", face_point, 2.2, Color(LOCK_BLUE, 0.45), Color.WHITE, windup, func(n: Node3D, k: float) -> void:
				(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, k * 0.6, k * 2.0, 0.0)))
		"pickoff":
			pass
		"thunderbolt":
			vfx.emit_one("glow", hand, Vector3.ZERO, Color(1.0, 0.95, 0.5, 1.0), 2.0, windup * 2.2)


func _charge_tick(card_id: String, h: Vector3, k: float, col: Color) -> void:
	if _rate(30.0):
		vfx.emit_one("glow", h, Vector3.ZERO, Color(col, 0.7), 0.5 + k, 0.4)
	match card_id:
		"heat_wave":
			if _rate(26.0):
				vfx.emit_one("fire", h + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), Vector3(0, 1.0, 0), FIRE, 0.45 + 0.3 * k, 0.6)
		"thunderbolt":
			if _rate(8.0):
				var p2: Vector3 = h + Vector3(randf_range(-1.2, 1.2), randf_range(-0.8, 1.0), randf_range(-1.2, 1.2))
				vfx.bolt(h, p2, Color(1.0, 0.92, 0.4), 0.09, 0.12, 0, 0.25, 1)
		"power_catch":
			if _rate(10.0):
				vfx.emit_one("magic", h, Vector3(randf_range(-1, 1), 1.5, randf_range(-1, 1)), VIOLET, 1.0, 0.6)
		_:
			if _rate(12.0):
				vfx.emit_one("magic", h + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)), Vector3(0, 0.6, 0), col, 0.8, 0.6)


## A reticle that tightens on the target during the wind-up (Pickoff).
func lock_on(target: Node3D, windup: float, color: Color) -> void:
	if target == null or not is_instance_valid(target):
		return
	var g: MeshInstance3D = vfx._take("glyph")
	g.global_position = target.center()
	g.set_instance_shader_parameter("color", color)
	g.set_instance_shader_parameter("anim", Vector4(0.25, 2, 0, 0))
	vfx.animate(g, windup + 0.15, func(n: Node3D, k: float) -> void:
		if is_instance_valid(target):
			n.global_position = target.center()
		var s := lerpf(4.5, 1.9, 1.0 - pow(1.0 - minf(k * 1.3, 1.0), 3.0))
		n.scale = Vector3.ONE * s
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(0.2 + k * 0.45, 2, 0, 0)))


# ---------------------------------------------------------------- offense

## Heat Wave: a wall of fire racing from the caster along the strip, scorching the ground.
func heat_wave(from: Vector3, to: Vector3, width: float, time: float) -> void:
	var a := _flat(from)
	var b := _flat(to)
	var dir := b - a
	var length := dir.length()
	dir = dir / maxf(length, 0.01)
	var side := Vector3(-dir.z, 0, dir.x)
	var travel := 0.3
	impact_flash(a + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 1.4, 7.0, 18)
	vfx.shockwave(a, 3.0, Color(1.0, 0.5, 0.15), 0.4, 0.07)
	var n := maxi(2, int(ceil(length / 1.3)))
	for i in n + 1:
		var k := float(i) / n
		var p := a.lerp(b, k)
		var delay := k * travel
		var wk := lerpf(0.6, 1.0, minf(k * 3.0, 1.0))
		var life := time + 0.4 - delay * 0.5
		for sgn in [-1.0, 1.0]:
			var off: Vector3 = side * sgn * width * 0.2 * wk + dir * randf_range(-0.35, 0.35)
			vfx.flame_sheet(p + off, width * 0.6 * wk, randf_range(3.0, 4.2) * wk, life, delay + randf() * 0.05)
		vfx.flame_sheet(p + dir * 0.6, width * 0.5 * wk, randf_range(3.8, 4.8) * wk, life * 0.8, delay + 0.03)
		if true:
			vfx.decal("scorch", p + side * randf_range(-0.3, 0.3), width * randf_range(0.6, 0.75), Color(0.07, 0.04, 0.03, 0.85), Color(1.0, 0.4, 0.08, 1.0), time + 3.5, Callable(), delay)
		vfx.after(delay, func() -> void:
			vfx.spray("fire", p + Vector3(0, 0.3, 0), 4, FIRE, 3.5, Vector3.UP, 0.7, 1.0, 0.8)
			vfx.spray("spark", p + Vector3(0, 0.4, 0), 4, Color(1.0, 0.7, 0.3), 7.0, (dir + Vector3.UP).normalized(), 0.7, 0.8))
	for j in 3:
		var hk := (j + 0.5) / 3.0
		vfx.heat_haze(a.lerp(b, hk) + Vector3(0, 0.2, 0), length / 3.0 * 1.25, 4.6, time + 0.7, travel * hk)
	vfx.after(travel * 0.5, func() -> void: vfx.flash_light(a.lerp(b, 0.5) + Vector3(0, 1.5, 0), FIRE, 6.0, 12.0, time * 0.7))
	vfx.after(travel, func() -> void: vfx.flash_light(b + Vector3(0, 1.5, 0), FIRE, 5.0, 10.0, time * 0.6))
	vfx.every_frame(time + 0.3, func(k: float) -> void:
		var dt := _dt()
		var c := vfx._count(int(ceil(40.0 * dt * length / 10.0)))
		for m in c:
			var p2 := a.lerp(b, randf()) + side * randf_range(-width * 0.45, width * 0.45)
			vfx.emit_one("ember", p2 + Vector3(0, randf_range(0.2, 1.5), 0), Vector3(randf_range(-0.5, 0.5), randf_range(1.5, 3.5), randf_range(-0.5, 0.5)), Color(1.0, 0.55, 0.15), 1.0, 1.0)
		if _rate(14.0 * (1.0 - k)):
			var p3 := a.lerp(b, randf()) + side * randf_range(-width * 0.4, width * 0.4)
			vfx.emit_one("fire", p3 + Vector3(0, 0.3, 0), Vector3(0, 2.0, 0), FIRE, randf_range(0.7, 1.1), 0.9)
		if _rate(10.0 * k):
			var p4 := a.lerp(b, randf()) + side * randf_range(-width * 0.4, width * 0.4)
			vfx.emit_one("smoke", p4 + Vector3(0, 1.4, 0), Vector3(0, 1.4, 0), Color(0.16, 0.13, 0.12, 0.55), 1.4, 1.2), travel)


## Power Throw: sonic rings at release, comet trail (projectile fx), heavy star impact.
func power_release(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	vfx.emit_one("ring", from + dir * 0.6, Vector3.ZERO, Color(1.0, 0.9, 0.55), 0.9, 0.8)
	vfx.emit_one("ring", from + dir * 1.6, dir * 4.0, Color(1.0, 0.85, 0.45), 1.3, 0.9)
	vfx.spray("streak", from, 10, Color(1.0, 0.9, 0.6), 12.0, dir, 0.25, 0.9, 0.6)
	vfx.emit_one("flash", from, Vector3.ZERO, Color(1.0, 0.9, 0.6, 0.8), 0.6, 0.8)


## Impacts carried by thrown balls (payload "fx"). Called by the projectile manager.
func ball_impact(kind: String, at: Vector3, color: Color, target: Node3D = null) -> void:
	match kind:
		"power":
			impact_flash(at, Color(1.0, 0.85, 0.4), 1.7, 7.0, 26)
			vfx.emit("magic", at, 12, GOLD, 6.0, 0.8)
			vfx.emit_one("ring", at, Vector3.ZERO, Color(1.0, 0.95, 0.7), 2.2, 1.2)
			vfx.shockwave(_flat(at), 2.6, Color(1.0, 0.8, 0.35), 0.4, 0.07)
			vfx.dust(at, 1.2)
			vfx.shake(0.12)
		"split":
			impact_flash(at, Color(0.75, 0.9, 1.0), 0.8, 0.0, 10)
			vfx.emit("magic", at, 4, Color(0.8, 0.9, 1.0), 3.0, 0.6)
		"knuckle":
			vfx.emit("magic", at, 14, Color(0.85, 0.6, 1.0), 4.0, 0.8)
			vfx.emit("smoke", at, 5, Color(0.45, 0.3, 0.65, 0.6), 2.0, 0.5, 1.0, 0.6)
			vfx.emit_one("ring", at, Vector3.ZERO, VIOLET, 1.3, 0.9)
			vfx.glyph(at + Vector3(0, 1.1, 0), 1, 1.5, Color(0.85, 0.65, 1.0), 1.1)
		"hook":
			impact_flash(at, CYAN, 1.5, 6.0, 20)
			vfx.emit_one("ring", at, Vector3.ZERO, Color(0.6, 0.95, 1.0), 2.0, 1.0)
			if target and is_instance_valid(target) and "route" in target:
				# The runner is yanked back along its path: a cyan drag streak.
				var e := target
				var back: Vector3 = -e.route.direction_at(e.d)
				var start: Vector3 = e.center()
				var pts := PackedVector3Array()
				for i in 9:
					pts.append(start + back * (i * 0.75) + Vector3(0, -0.3 * i / 8.0, 0))
				vfx.ribbon(pts, CYAN, 0.35, 0.5)
				vfx.spray("streak", start, 14, Color(0.6, 0.95, 1.0), 10.0, back, 0.3, 1.0, 0.7)
		_:
			impact_flash(at, color, 1.0, 0.0, 10)


## Splitter: the ball bursts in mid-air and fans out.
func splitter_burst(at: Vector3, ground: Vector3) -> void:
	impact_flash(at, Color(0.8, 0.92, 1.0), 1.6, 6.0, 26)
	vfx.emit_one("ring", at, Vector3.ZERO, Color(0.85, 0.95, 1.0), 2.4, 1.0)
	vfx.spray("streak", at, 18, Color(0.85, 0.95, 1.0), 14.0, Vector3.DOWN, 1.2, 1.0, 0.7)
	vfx.shockwave(_flat(ground), 3.5, Color(0.7, 0.88, 1.0), 0.45, 0.05)


## Grand Slam Barrage: a burning target zone and an embers sky.
func barrage_start(point: Vector3, r: float, dur: float) -> void:
	vfx.ground_fx("rays", point, r * 1.05, Color(1.0, 0.25, 0.05, 0.4), Color(1.0, 0.55, 0.15), dur + 0.6)
	vfx.zone_ring(point, r, Color(1.0, 0.35, 0.08, 0.95), dur + 0.6, 0.16, 1.2, 16.0)
	vfx.flash_light(point + Vector3(0, 6.0, 0), Color(1.0, 0.45, 0.15), 3.0, r * 3.0, dur)
	vfx.every_frame(dur, func(_k: float) -> void:
		if _rate(30.0):
			var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * r
			vfx.emit_one("ember", point + Vector3(off.x, randf_range(3.0, 9.0), off.y), Vector3(randf_range(-1, 1), -3.0, randf_range(-1, 1)), Color(1.0, 0.55, 0.15), 1.2, 1.0))


## A small landing marker that fills while a barrage ball falls.
func barrage_mark(land: Vector3, flight: float) -> void:
	var m: Node3D = vfx.telegraph(land, 1.8, Color(1.0, 0.3, 0.1, 0.85), flight)
	vfx.after(flight + 0.02, func() -> void:
		if is_instance_valid(m):
			m.queue_free())


func barrage_impact(at: Vector3) -> void:
	var g := _flat(at)
	impact_flash(at + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.25), 1.3, 8.0, 22)
	# Fireball: big flame tongues bursting up and out, then a column of smoke.
	for i in vfx._count(7):
		var d := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(1.0, 3.5)
		vfx.emit_one("fire", g + Vector3(d.x * 0.15, 0.4, d.z * 0.15), d + Vector3(0, randf_range(3.0, 5.5), 0), FIRE, randf_range(1.6, 2.4), randf_range(0.8, 1.1))
	vfx.ring_emit("fire", g + Vector3(0, 0.3, 0), 0.6, 10, FIRE, 6.0, 1.2, 1.1, 0.7)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 10, Color(0.36, 0.26, 0.2), 10.0, Vector3.UP, 0.8, 1.3, 1.0)
	vfx.ring_emit("dust", g + Vector3(0, 0.3, 0), 0.8, 10, Color(0.55, 0.42, 0.3, 0.7), 5.0, 0.6, 1.1, 1.0)
	vfx.emit("smoke", g + Vector3(0, 1.4, 0), 7, Color(0.14, 0.12, 0.11, 0.75), 1.6, 2.0, 1.0, 1.6, 1.3)
	vfx.emit("ember", g + Vector3(0, 0.5, 0), 10, Color(1.0, 0.55, 0.15), 6.0, 1.0)
	vfx.shockwave(g, 3.2, Color(1.0, 0.55, 0.2), 0.45, 0.07)
	vfx.decal("crater", g, randf_range(1.5, 1.9), Color(0.08, 0.05, 0.04, 0.85), Color(1.0, 0.4, 0.08), 5.0)


## Grand Relay: the ball zips defender to defender with golden links.
func relay_link(a: Vector3, b: Vector3, ground: Vector3) -> void:
	vfx.bolt(a, b, GOLD, 0.18, 0.3, 0, 0.05, 2)
	vfx.ribbon(vfx.arc_points(a, b, 0.6, 12), Color(1.0, 0.9, 0.5), 0.07, 0.5)
	vfx.beam(ground, 0.6, 5.0, GOLD, 0.6)
	vfx.shockwave(ground, 1.6, GOLD, 0.35, 0.08)
	vfx.burst("gold", b)


func relay_strike(from: Vector3, to: Vector3) -> void:
	vfx.bolt(from, to, Color(1.0, 0.85, 0.3), 0.24, 0.32, 1, 0.09, 2)
	impact_flash(to, GOLD, 1.1, 4.0, 14)


## Power Catch: a lobbed ball; a warning circle; then a glove-slam that cracks the ground.
func power_catch_throw(point: Vector3, r: float, flight: float) -> void:
	var m: Node3D = vfx.telegraph(point, r, Color(0.7, 0.4, 1.0, 0.85), flight)
	vfx.after(flight + 0.02, func() -> void:
		if is_instance_valid(m):
			m.queue_free())
	vfx.every_frame(flight, func(k: float) -> void:
		if k > 0.5 and _rate(30.0):
			var off := Vector2.from_angle(randf() * TAU) * r * randf_range(0.8, 1.2)
			vfx.emit_one("streak", point + Vector3(off.x, 6.0, off.y), Vector3(-off.x * 0.4, -16.0, -off.y * 0.4), Color(0.75, 0.5, 1.0), 1.0, 0.7))


func power_catch_impact(point: Vector3, r: float) -> void:
	var g := _flat(point)
	impact_flash(g + Vector3(0, 0.8, 0), VIOLET, 2.0, 8.0, 24)
	vfx.decal("crater", g, r * 1.25, Color(0.1, 0.06, 0.12, 0.85), Color(0.75, 0.45, 1.0), 4.5)
	vfx.shockwave(g, r * 1.4, Color(0.75, 0.45, 1.0), 0.5, 0.08)
	vfx.shockwave(g, r * 2.2, Color(0.85, 0.7, 1.0, 0.7), 0.7, 0.04, 0.08)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 14, Color(0.45, 0.33, 0.25), 10.0, Vector3.UP, 0.9, 1.1, 1.0)
	vfx.ring_emit("dust", g + Vector3(0, 0.3, 0), r * 0.5, 18, Color(0.55, 0.42, 0.32, 0.75), 6.0, 0.8, 1.2, 1.1)
	vfx.ring_emit("streak", g + Vector3(0, 0.4, 0), 0.5, 16, Color(0.8, 0.6, 1.0), 12.0, 1.0, 1.0, 0.6)
	vfx.burst("shadow", g + Vector3(0, 0.5, 0))
	vfx.beam(g, r * 0.5, 6.0, VIOLET, 0.5)


## Thunderbolt: a forked bolt from the caster plus a strike from the sky.
func thunderbolt(from: Vector3, to: Vector3) -> void:
	var col := Color(1.0, 0.92, 0.4)
	vfx.bolt(from, to, col, 0.34, 0.42, 3, 0.15, 4)
	var sky := to + Vector3(randf_range(-2, 2), 16.0, randf_range(-2, 2))
	vfx.bolt(sky, to, Color(1.0, 0.95, 0.6), 0.44, 0.45, 4, 0.12, 4, 0.04)
	impact_flash(to, col, 1.8, 9.0, 26)
	vfx.flash_light(from, col, 4.0, 8.0, 0.25)
	vfx.shockwave(_flat(to), 2.4, col, 0.35, 0.06)
	vfx.decal("scorch", _flat(to), 1.1, Color(0.06, 0.05, 0.04, 0.7), Color(1.0, 0.85, 0.3), 3.0)
	vfx.every_frame(0.5, func(_k: float) -> void:
		if _rate(30.0):
			vfx.emit_one("spark", to + Vector3(randf_range(-0.4, 0.4), randf_range(-0.6, 0.6), randf_range(-0.4, 0.4)), Vector3(randf_range(-3, 3), randf_range(1, 5), randf_range(-3, 3)), col, 0.8, 0.6))
	vfx.shake(0.15)


## A chain jump between runners (Thunderbolt chains).
func chain_arc(a: Vector3, b: Vector3, color: Color) -> void:
	vfx.bolt(a, b, color, 0.22, 0.32, 1, 0.18, 3)
	vfx.spray("spark", b, 10, color.lerp(Color.WHITE, 0.4), 7.0, Vector3.UP, 1.2, 0.8)
	vfx.emit_one("flash", b, Vector3.ZERO, Color(color, 0.8), 0.6, 0.8)


# ---------------------------------------------------------------- control

## Curveball: a swirling vortex where the ball breaks.
func curveball_impact(point: Vector3, r: float) -> void:
	var g := _flat(point)
	vfx.ground_fx("vortex", g, r, Color(0.5, 0.42, 1.0, 0.95), Color(0.85, 0.75, 1.0), 1.1, Vector2(1.0, 0.0))
	vfx.shockwave(g, r * 1.15, Color(0.6, 0.5, 1.0), 0.45, 0.05)
	vfx.emit_one("flash", g + Vector3(0, 0.6, 0), Vector3.ZERO, Color(0.6, 0.5, 1.0, 0.8), 1.0, 0.8)
	for i in vfx._count(18):
		var a := randf() * TAU
		var d := randf_range(0.4, r)
		var p := g + Vector3(cos(a) * d, randf_range(0.2, 1.2), sin(a) * d)
		var tangent := Vector3(-sin(a), 0.3, cos(a))
		vfx.emit_one("magic", p, tangent * 5.0, Color(0.65, 0.55, 1.0), 1.0, 0.9)


## Shadow Change: a pool of darkness swallows the area, then hurls the runners back.
func shadow_change(point: Vector3, r: float) -> void:
	var g := _flat(point)
	vfx.ground_fx("vortex", g, r, Color(0.55, 0.2, 0.95, 1.0), Color(0.8, 0.5, 1.0), 1.5, Vector2(-1.0, 1.0))
	vfx.shockwave(g, r * 1.3, Color(0.4, 0.15, 0.7, 0.9), 0.35, 0.06, 0.0, true)
	vfx.shockwave(g, r * 1.5, Color(0.7, 0.4, 1.0), 0.6, 0.07, 0.3)
	vfx.ring_emit("smoke", g + Vector3(0, 0.4, 0), r * 0.3, 22, Color(0.12, 0.04, 0.2, 0.85), 7.0, 1.0, 1.3, 1.0)
	vfx.disc_emit("smoke", g + Vector3(0, 0.2, 0), r * 0.7, 10, Color(0.1, 0.03, 0.16, 0.7), Vector3(0, 2.2, 0), 1.4, 1.0)
	vfx.ring_emit("streak", g + Vector3(0, 0.6, 0), r * 0.4, 18, Color(0.75, 0.45, 1.0), 14.0, 0.5, 1.0, 0.6)
	vfx.emit_one("flash", g + Vector3(0, 1.0, 0), Vector3.ZERO, Color(0.55, 0.25, 1.0, 0.9), 1.8, 1.0)
	vfx.flash_light(g + Vector3(0, 1.5, 0), Color(0.6, 0.3, 1.0), 5.0, r * 2.5, 0.5)


func shadow_victim(e: Node3D) -> void:
	vfx.burst("shadow", e.center())
	var back: Vector3 = -e.route.direction_at(e.d) if "route" in e else Vector3.FORWARD
	vfx.spray("streak", e.center(), 6, Color(0.7, 0.4, 1.0), 10.0, back, 0.3, 1.0, 0.6)
	vfx.emit("smoke", _flat(e.global_position, 0.3), 3, Color(0.12, 0.04, 0.2, 0.8), 1.5, 0.8, 1.0, 1.0)


## Time Out: a giant stopwatch freezes the field; the world drains of colour.
func time_out(freeze_time: float) -> void:
	var c := Field.MOUND + Vector3(0, 0, -2)
	var spin := 1.0
	var dur := freeze_time + 0.6
	vfx.decal("clock", c, 15.0, Color(0.45, 0.8, 1.0, 0.75), Color(0.8, 0.95, 1.0), dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var grow := 1.0 - pow(1.0 - clampf(tt / 0.35, 0.0, 1.0), 3.0)
		n.scale = Vector3.ONE * 15.0 * (0.7 + 0.3 * grow)
		var hand := TAU * spin * (1.0 - pow(1.0 - clampf(tt / 0.8, 0.0, 1.0), 3.0))
		var flare := (1.0 - smoothstep(0.75, 1.2, tt)) * 0.45
		var vis := grow * (1.0 - smoothstep(dur - 0.6, dur, tt)) * (0.6 + 0.4 * flare)
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, hand, flare)), 0.0, 0.07)
	vfx.shockwave(c, 34.0, Color(0.6, 0.9, 1.0), 0.9, 0.03)
	vfx.shockwave(c, 20.0, Color(0.8, 0.95, 1.0, 0.8), 0.7, 0.04, 0.15)
	vfx.glyph(c + Vector3(0, 7.0, 0), 3, 5.0, Color(0.7, 0.95, 1.0), 1.4, 0.0, 1.5)
	vfx.flash_light(c + Vector3(0, 8.0, 0), Color(0.6, 0.85, 1.0), 3.0, 40.0, 0.8)
	_desaturate(freeze_time)


## Drains the world's colour while time is stopped (restored afterwards).
func _desaturate(time: float) -> void:
	var env: Environment = null
	if battle and "stadium" in battle and battle.stadium and battle.stadium.world_env:
		env = battle.stadium.world_env.environment
	if env == null or not env.adjustment_enabled:
		return
	if vfx._env_saturation < 0.0:
		vfx._env_saturation = env.adjustment_saturation
	var base: float = vfx._env_saturation
	vfx.every_frame(time, func(k: float) -> void:
		var tt := k * time
		var amt := smoothstep(0.0, 0.25, tt) * (1.0 - smoothstep(time - 0.5, time, tt))
		env.adjustment_saturation = lerpf(base, 0.3, amt)
		if k >= 1.0:
			env.adjustment_saturation = base)


func time_out_victim(e: Node3D) -> void:
	vfx.burst("frost", e.center())
	vfx.ring_emit("snow", _flat(e.global_position, 0.3), 0.6, 6, Color(0.8, 0.95, 1.0), 2.0, 1.0)


## Changeup: a slow tempo wave rolls out from the plate.
func changeup() -> void:
	var c := Field.HOME
	var col := Color(0.55, 0.55, 1.0)
	vfx.shockwave(c, 36.0, col, 1.4, 0.03)
	vfx.shockwave(c, 36.0, Color(0.75, 0.75, 1.0, 0.7), 1.6, 0.02, 0.25)
	vfx.decal("clock", c, 5.0, Color(col, 0.8), Color.WHITE, 1.4, func(n: Node3D, k: float) -> void:
		var vis := smoothstep(0.0, 0.1, k) * (1.0 - smoothstep(0.6, 1.0, k))
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, -TAU * 0.5 * k, 0.5)))


func changeup_victim(e: Node3D) -> void:
	vfx.emit("magic", e.center(), 6, Color(0.6, 0.6, 1.0), 2.0, 0.2)
	vfx.emit_one("ring", e.center(), Vector3.ZERO, Color(0.6, 0.6, 1.0, 0.7), 0.9, 1.4)


## Pickoff: a laser-straight snap throw.
func pickoff_strike(from: Vector3, to: Vector3, picked: bool) -> void:
	var pts := PackedVector3Array([from, from.lerp(to, 0.5), to])
	vfx.ribbon(pts, TEAL, 0.22, 0.35, 0.0, false)
	vfx.ribbon(pts, Color(0.8, 1.0, 0.95), 0.06, 0.25, 0.0, false)
	impact_flash(to, TEAL, 1.3 if picked else 1.0, 5.0, 16)
	if picked:
		vfx.shockwave(_flat(to), 3.0, TEAL, 0.45, 0.07)
		vfx.emit("magic", to, 16, Color(0.6, 1.0, 0.9), 5.0, 1.0)
		vfx.glyph(to + Vector3(0, 1.4, 0), 2, 1.6, TEAL, 0.8)


# ---------------------------------------------------------------- defense

## Lockdown: a rune seal snaps shut, light bars cage the area.
func lockdown(point: Vector3, r: float, root: float) -> void:
	var g := _flat(point)
	var dur := root + 0.5
	vfx.decal("runes", g, r * 1.1, Color(LOCK_BLUE, 0.95), Color(0.9, 0.95, 1.0), dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var snap := clampf(tt / 0.22, 0.0, 1.0)
		var s := lerpf(r * 1.7, r * 1.1, 1.0 - pow(1.0 - snap, 4.0))
		n.scale = Vector3(s, 1, s)
		var rot := (1.0 - pow(1.0 - snap, 2.0)) * 2.4 + tt * 0.15
		var flare := (1.0 - smoothstep(0.2, 0.7, tt)) * 1.5 + 0.25
		var vis := (1.0 - smoothstep(dur - 0.4, dur, tt))
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, rot, flare)))
	vfx.shockwave(g, r * 1.8, Color(0.5, 0.8, 1.0), 0.25, 0.06, 0.0, true)
	vfx.after(0.2, func() -> void:
		vfx.cage(g, r * 1.02, 2.4, Color(0.4, 0.75, 1.0), root + 0.2)
		impact_flash(g + Vector3(0, 0.4, 0), LOCK_BLUE, 1.4, 6.0, 18)
		vfx.ring_emit("spark", g + Vector3(0, 0.2, 0), r, 24, Color(0.6, 0.85, 1.0), 2.0, 7.0, 0.9, 0.8)
		vfx.glyph(g + Vector3(0, 3.4, 0), 5, 1.9, Color(0.55, 0.85, 1.0), 1.2, 0.0, 0.5)
		vfx.shake(0.1))


func lockdown_victim(e: Node3D) -> void:
	vfx.emit("magic", e.center(), 6, LOCK_BLUE, 2.5, 0.4)
	var feet := _flat(e.global_position, 0.3)
	for i in 3:
		var a := randf() * TAU
		var p := feet + Vector3(cos(a), 0, sin(a)) * 1.2
		vfx.bolt(p, e.center(), Color(0.5, 0.8, 1.0), 0.09, 0.25, 0, 0.1, 1, 0.2)


## Base Shield cast: hex light rises from the plate (the dome itself animates in vfx.gd).
func base_shield() -> void:
	var h := Field.HOME
	var col := Color(0.35, 0.85, 1.0)
	vfx.ground_fx("hexdisc", h, 3.4, Color(col, 0.9), Color.WHITE, 1.6)
	vfx.beam(h, 2.3, 9.0, col, 0.9)
	vfx.shockwave(h, 4.5, col, 0.55, 0.06)
	vfx.glyph(h + Vector3(0, 3.6, 0), 14, 1.8, Color(0.5, 0.9, 1.0), 1.3, 0.15, 0.6)
	vfx.ring_emit("magic", h + Vector3(0, 0.2, 0), 2.4, 20, col, 0.5, 4.0, 1.0, 1.0)
	vfx.flash_light(h + Vector3(0, 2.0, 0), col, 5.0, 10.0, 0.6)


## Diving Catch: a pink dash streak, then a skidding, dirt-spraying landing.
func diving_catch(from: Vector3, point: Vector3, r: float) -> void:
	var a := from + Vector3(0, 1.0, 0)
	var b := _flat(point, 0.6)
	var dir := (b - a)
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	vfx.ribbon(vfx.arc_points(a, b, 1.2, 14), PINK, 0.5, 0.5)
	vfx.ribbon(vfx.arc_points(a, b, 1.2, 14), Color(1.0, 0.85, 0.95), 0.14, 0.35)
	vfx.line_emit("streak", a, b, 14, PINK, dir * 9.0, 0.5, 1.0, 0.7)
	var g := _flat(point)
	impact_flash(g + Vector3(0, 0.6, 0), PINK, 1.4, 6.0, 18)
	vfx.spray("dust", g + Vector3(0, 0.3, 0), 14, Color(0.6, 0.45, 0.33, 0.75), 7.0, (dir + Vector3(0, 0.5, 0)).normalized(), 0.6, 1.2, 1.0)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 8, Color(0.5, 0.37, 0.27), 7.0, (dir + Vector3(0, 0.9, 0)).normalized(), 0.5, 0.7, 1.0)
	vfx.emit("magic", g + Vector3(0, 0.8, 0), 12, Color(1.0, 0.6, 0.85), 5.0, 1.0)
	var skid := vfx.decal("crater", g + dir * 0.8, r * 0.7, Color(0.25, 0.16, 0.1, 0.6), Color(1.0, 0.45, 0.7), 3.0)
	skid.rotation.y = atan2(dir.x, dir.z)
	skid.scale = Vector3(r * 0.45, 1, r * 1.0)


# ---------------------------------------------------------------- utility

## A glowing aura that follows a defender for the length of a buff.
func defender_aura(df: Node3D, color: Color, dur: float, radius := 1.3, kind := "ring") -> void:
	if df == null or not is_instance_valid(df):
		return
	var mi: MeshInstance3D = vfx._take("ring" if kind == "ring" else kind)
	mi.reparent(df, false)
	mi.position = Vector3(0, 0.08, 0)
	mi.scale = Vector3(radius, 1, radius)
	if kind == "ring":
		mi.set_instance_shader_parameter("color", color)
		mi.set_instance_shader_parameter("mode", 1.0)
		mi.set_instance_shader_parameter("params", Vector4(0.08, 0.3, 1.5, 6.0))
		mi.set_instance_shader_parameter("progress", 0.0)
	else:
		mi.set_instance_shader_parameter("color", color)
		mi.set_instance_shader_parameter("color2", Color.WHITE)
		mi.set_instance_shader_parameter("anim", Vector4(0, 0, 1, 0))
	vfx.animate(mi, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var vis := smoothstep(0.0, 0.3, tt) * (1.0 - smoothstep(dur - 0.6, dur, tt))
		var pulse := 0.85 + 0.15 * sin(tt * 4.0)
		var m := n as MeshInstance3D
		if kind == "ring":
			m.set_instance_shader_parameter("progress", vis * pulse)
		else:
			m.set_instance_shader_parameter("anim", Vector4(k, vis, 1.0, 0.0)))


func twin_play(caster: Node3D, dur: float) -> void:
	var col := Color(0.35, 1.0, 0.55)
	var c: Vector3 = _flat(caster.global_position) if caster and is_instance_valid(caster) else Field.HOME
	vfx.shockwave(c, 30.0, col, 1.2, 0.03)
	vfx.flash_light(c + Vector3(0, 2.0, 0), col, 4.0, 10.0, 0.5)
	# Two orbs spiralling up from the caster.
	for side in [0.0, PI]:
		for i in 10:
			var a: float = side + i * 0.55
			var p := c + Vector3(cos(a) * 0.9, 0.4 + i * 0.32, sin(a) * 0.9)
			vfx.after(i * 0.03, func() -> void:
				vfx.emit_one("glow", p, Vector3(0, 1.0, 0), Color(col, 0.9), 0.9, 0.6)
				vfx.emit_one("magic", p, Vector3(cos(a + 1.6), 1.0, sin(a + 1.6)) * 2.0, col, 1.0, 0.8))
	for df in battle.defenders:
		defender_aura(df, Color(col, 0.85), dur, 1.25)
		vfx.ribbon(vfx.arc_points(c + Vector3(0, 1.5, 0), df.model.chest_position(), 2.0, 14), col, 0.12, 0.6)
		vfx.burst("magic", df.model.chest_position(), col)


func field_vision(dur: float, bonus: float) -> void:
	var col := Color(1.0, 0.88, 0.35)
	for df in battle.defenders:
		var rng: float = df.s_range * (1.0 + maxf(df.dyn_range, bonus))
		# A thin ring sweeping out to the new throwing range.
		vfx.shockwave(_flat(df.global_position), rng, Color(col, 0.85), 0.9, 0.025)
		vfx.ground_fx("radar", _flat(df.global_position), 2.2, Color(col, 0.6), Color.WHITE, 1.2)
		vfx.glyph(df.model.head_position() + Vector3(0, 1.0, 0), 10, 1.3, col, 1.2, randf() * 0.15, 0.6)
		defender_aura(df, Color(col, 0.6), dur, 1.15)
		vfx.burst("magic", df.model.head_position(), col)


func diamond_aura(df: Node3D, radius: float, dur: float) -> void:
	var col := Color(0.6, 0.88, 1.0)
	defender_aura(df, Color(col, 0.75), dur, radius, "diamond")
	var top: Vector3 = df.model.head_position() + Vector3(0, 1.4, 0)
	vfx.glyph(top, 7, 2.2, Color(0.7, 0.92, 1.0), 1.6, 0.0, 0.8)
	vfx.beam(_flat(df.global_position), 1.2, 10.0, col, 0.9)
	vfx.shockwave(_flat(df.global_position), radius, col, 0.6, 0.05)
	impact_flash(top, col, 1.2, 5.0, 14)
	vfx.every_frame(dur, func(_k: float) -> void:
		if is_instance_valid(df) and _rate(10.0):
			var a := randf() * TAU
			var d := sqrt(randf()) * radius
			vfx.emit_one("magic", _flat(df.global_position) + Vector3(cos(a) * d, randf_range(0.2, 1.6), sin(a) * d), Vector3(0, 0.8, 0), Color(0.75, 0.95, 1.0), 1.0, 1.0))


func rally_cry(dur: float) -> void:
	var col := Color(1.0, 0.82, 0.3)
	var c := Field.HOME + Vector3(0, 1.5, 0)
	for i in 3:
		vfx.sphere_pulse(c, 5.0 + i * 3.0, Color(col, 0.45), 0.6, i * 0.16)
		vfx.shockwave(Field.HOME, 18.0 + i * 8.0, col, 0.9, 0.04, i * 0.16)
	vfx.glyph(c + Vector3(0, 2.0, 0), 9, 2.4, col, 1.0)
	for df in battle.defenders:
		var p: Vector3 = _flat(df.global_position)
		vfx.beam(p, 0.8, 5.0, col, 0.7, 0.2)
		vfx.glyph(df.model.head_position() + Vector3(0, 0.9, 0), 6, 1.2, Color(1.0, 0.85, 0.35), 1.0, 0.25, 0.8)
		defender_aura(df, Color(col, 0.8), dur, 1.3)
		vfx.after(0.25, func() -> void:
			if is_instance_valid(df):
				vfx.ring_emit("magic", p + Vector3(0, 0.3, 0), 0.8, 10, col, 0.5, 3.5, 1.0, 1.0))


## Magnet Glove: a field that winds inward; tethers drag the runners to the centre.
func magnet(point: Vector3, r: float, pull: float, victims: Array) -> void:
	var g := _flat(point)
	vfx.ground_fx("magnet", g, r, Color(MAGNET_RED, 0.95), Color(1.0, 0.8, 0.3), pull + 0.6)
	vfx.shockwave(g, r * 1.5, Color(1.0, 0.45, 0.3, 0.9), 0.4, 0.06, 0.0, true)
	vfx.glyph(g + Vector3(0, 2.6, 0), 8, 1.6, Color(1.0, 0.75, 0.3), pull + 0.3, 0.0, 0.2)
	vfx.flash_light(g + Vector3(0, 2.0, 0), Color(1.0, 0.5, 0.3), 4.0, r * 2.0, pull)
	var shown := 0
	for e in victims:
		if shown >= 12:
			break
		shown += 1
		var en: Node3D = e
		var bend := randf_range(-1.5, 1.5)
		vfx.live_ribbon(func(_k: float) -> PackedVector3Array:
			if not is_instance_valid(en):
				return PackedVector3Array()
			var a2: Vector3 = en.center()
			var b2: Vector3 = g + Vector3(0, 1.0, 0)
			var pts := PackedVector3Array()
			var side := (b2 - a2).cross(Vector3.UP).normalized() * bend
			for i in 11:
				var t := float(i) / 10.0
				pts.append(a2.lerp(b2, t) + side * sin(t * PI) + Vector3(0, sin(t * PI) * 0.6, 0))
			return pts, Color(1.0, 0.45, 0.3), 0.08, pull + 0.3)
	vfx.every_frame(pull + 0.3, func(_k: float) -> void:
		if _rate(9.0):
			var a := randf() * TAU
			vfx.bolt(g + Vector3(0, 1.0, 0), g + Vector3(cos(a) * r * 0.5, 0.2, sin(a) * r * 0.5), Color(1.0, 0.85, 0.35), 0.09, 0.15, 0, 0.25, 1)
		if _rate(40.0):
			var a2 := randf() * TAU
			var d := r * randf_range(0.6, 1.0)
			var p := g + Vector3(cos(a2) * d, randf_range(0.2, 1.0), sin(a2) * d)
			vfx.emit_one("streak", p, (g - p).normalized() * 8.0 + Vector3(-sin(a2), 0, cos(a2)) * 2.0, Color(1.0, 0.55, 0.35), 0.9, 0.6))


## Seventh-Inning Stretch: fireworks over the stadium and confetti over the field.
func stretch() -> void:
	var cols := [Color(1.0, 0.3, 0.25), Color(1.0, 0.85, 0.3), Color(0.35, 0.7, 1.0), Color(0.4, 1.0, 0.55), Color(1.0, 0.5, 0.9)]
	for i in 7:
		var ang := lerpf(-50.0, 50.0, i / 6.0) + randf_range(-6, 6)
		var base := Field.wall_point(ang, 31.0)
		var top := Field.wall_point(ang, 22.0) + Vector3(randf_range(-3, 3), randf_range(10.0, 15.0), randf_range(-3, 3))
		var col: Color = cols[i % cols.size()]
		var delay := i * 0.16 + randf() * 0.1
		var rise := 0.7
		vfx.after(delay, func() -> void:
			vfx.ribbon(vfx.arc_points(base, top, 0.0, 6), Color(1.0, 0.85, 0.5), 0.06, rise + 0.2)
			vfx.every_frame(rise, func(k: float) -> void:
				if _rate(40.0):
					vfx.emit_one("ember", base.lerp(top, k), Vector3(randf_range(-0.5, 0.5), -1.0, randf_range(-0.5, 0.5)), Color(1.0, 0.7, 0.3), 1.0, 0.6)))
		vfx.after(delay + rise, func() -> void:
			vfx.emit_one("flash", top, Vector3.ZERO, Color(col.lerp(Color.WHITE, 0.4), 0.9), 4.0, 1.4)
			vfx.emit_one("ring", top, Vector3.ZERO, col, 6.0, 1.6)
			vfx.flash_light(top, col, 6.0, 30.0, 0.5)
			for k in vfx._count(60):
				var d := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				vfx.emit_one("spark", top, d * randf_range(8.0, 11.0), col.lerp(Color.WHITE, 0.25), 2.8, 2.2)
			for k in vfx._count(10):
				var d2 := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
				vfx.emit_one("glow", top + d2 * 1.5, d2 * 6.0, Color(col, 0.8), 3.0, 1.6)
			vfx.emit("magic", top, 26, col.lerp(Color.WHITE, 0.5), 9.0, 0.0, 1.0, 2.2, 1.8))
	for p in [Field.HOME + Vector3(0, 7, -8), Field.MOUND + Vector3(-6, 7, 0), Field.MOUND + Vector3(6, 7, 0)]:
		vfx.burst("confetti", p)


# ---------------------------------------------------------------- debug showcase

## `--vfx-showcase=<card_id>[,<card_id>...]`: waits for the Practice Field, spawns a slow
## pack of tough runners, frames the camera (unless --cam-view is given) and casts the card
## after `--vfx-delay=<s>` (default 1.0). With `--vfx-shots=t1,t2 --vfx-out=<dir>` it saves
## frames t seconds after each cast (a card may carry its own times: `card@0.2/0.6`),
## clears the field, moves on to the next card and quits at the end.
## tools/art/vfx/showcase.sh wraps this with a fixed timestep.
func showcase(list: String) -> void:
	var tree := vfx.get_tree()
	while is_instance_valid(battle) and battle.state != "setup":
		await tree.process_frame
	var args := OS.get_cmdline_user_args()
	var shots: Array[float] = []
	var out_dir := ""
	for a in args:
		if a.begins_with("--vfx-shots="):
			for t in a.split("=")[1].split(","):
				shots.append(float(t))
		elif a.begins_with("--vfx-out="):
			out_dir = a.split("=")[1]
	var entries := list.split(",")
	for i in entries.size():
		var parts := entries[i].split("@")
		var times: Array[float] = shots.duplicate()
		if parts.size() > 1:
			times.clear()
			for t in parts[1].split("/"):
				times.append(float(t))
		if not is_instance_valid(battle):
			return
		await _showcase_one(parts[0], times, out_dir)
		if i < entries.size() - 1:
			_showcase_clear()
			await tree.create_timer(2.5, false).timeout
	if out_dir != "" and (not shots.is_empty() or list.contains("@")):
		tree.quit(0)


func _showcase_clear() -> void:
	for e in battle.enemies.duplicate():
		battle.enemies.erase(e)
		e.queue_free()
	for z in battle.zones.duplicate():
		battle.zones.erase(z)
		z.queue_free()
	for w in battle.walls.duplicate():
		w.crumble()
	for t in battle.traps.duplicate():
		battle.traps.erase(t)
		t.queue_free()
	battle.buffs.clear()
	for df in battle.defenders:
		df.stun_t = 0.0


func _showcase_one(card_id: String, times: Array[float], out_dir: String) -> void:
	var tree := vfx.get_tree()
	if not DB.cards.has(card_id):
		push_warning("vfx showcase: unknown card " + card_id)
		return
	var args := OS.get_cmdline_user_args()
	var delay := 1.0
	var level := 1
	var cam_arg := ""
	for a in args:
		if a.begins_with("--vfx-delay="):
			delay = float(a.split("=")[1])
		elif a.begins_with("--vfx-level="):
			level = int(a.split("=")[1])
		elif a.begins_with("--vfx-cam="):
			cam_arg = a.split("=")[1]
	var linked: String = DB.card(card_id).get("linked", "")
	if linked != "":
		var present := false
		for df in battle.defenders:
			present = present or df.id == linked
		if not present and battle.defenders.size() > 1:
			battle.swap_defender(battle.defenders[1], linked)
			battle.select_defender(null)
	var route: Route = battle.routes[0]
	var d0 := route.length * 0.55
	var target := route.position_at(d0)
	var kinds := ["runner", "swarmer", "runner", "armored", "runner", "sprinter"]
	for i in 11:
		battle.spawn_enemy(kinds[i % kinds.size()], route, d0 - 2.6 + i * 0.5, {"lateral": randf_range(-1.3, 1.3), "hp_mult": 60.0, "speed_mult": 0.08})
	var focus := target
	var view := Vector3(20.0, -38.0, 24.0)
	match card_id:
		"base_shield":
			focus = Field.HOME + Vector3(0, 0, 0.5)
			view = Vector3(180.0, -30.0, 17.0)
		"time_out", "changeup", "rally_cry", "twin_play", "field_vision":
			focus = Field.MOUND + Vector3(0, 0, 2)
			view = Vector3(0.0, -48.0, 46.0)
		"seventh_inning_stretch":
			focus = Field.MOUND + Vector3(0, 6, -10)
			view = Vector3(0.0, -18.0, 52.0)
		"heat_wave", "grand_relay", "thunderbolt", "pickoff", "sky_hook", "diving_catch", "power_catch":
			focus = target.lerp(Field.MOUND, 0.35)
			view = Vector3(25.0, -42.0, 34.0)
	if cam_arg != "":
		var v := cam_arg.split(",")
		view = Vector3(float(v[0]), float(v[1]), float(v[2]))
	var has_cam_view := false
	for a in args:
		has_cam_view = has_cam_view or a.begins_with("--cam-view=")
	if not has_cam_view:
		battle.cam.set_view(focus, view.x, view.y, view.z, true)
		battle.cam.cinematic = true
	print("[VFX] showcase %s target=%s" % [card_id, target])
	await tree.create_timer(delay, false).timeout
	if not is_instance_valid(battle):
		return
	var lead := battle.lead_runners(1)
	var df_target: Node3D = battle.defenders[0]
	var best := INF
	for df in battle.defenders:
		var dd := Field.v2(df.global_position).distance_to(Field.v2(target))
		if dd < best:
			best = dd
			df_target = df
	battle.effects.execute(card_id, level, {"point": target, "enemy": lead[0] if not lead.is_empty() else null, "defender": df_target, "valid": true})
	print("[VFX] cast %s" % card_id)
	if times.is_empty() or out_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	var elapsed := 0.0
	for i in times.size():
		await tree.create_timer(maxf(times[i] - elapsed, 0.0), false).timeout
		elapsed = times[i]
		await RenderingServer.frame_post_draw
		var img := vfx.get_viewport().get_texture().get_image()
		var path := "%s/%s_%d.png" % [out_dir, card_id, int(round(times[i] * 100.0))]
		img.save_png(path)
		print("[VFX] saved ", path)
