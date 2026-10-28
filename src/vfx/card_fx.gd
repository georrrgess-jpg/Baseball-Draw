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


# ---------------------------------------------------------------- acknowledgement & fizzles

## Short acknowledgement the moment a card is played: a card-coloured pop on the ground
## and a rising sparkle at `pos` (the caster's feet, the target spot or home plate), so
## every card visibly "goes off" even before its main effect lands.
func cast_ack(card_id: String, pos: Vector3) -> void:
	var col := card_color(card_id)
	var g := _flat(pos)
	var s := rarity_scale(card_id)
	vfx.shockwave(g, 1.9 * s, col.lerp(Color.WHITE, 0.25), 0.35, 0.08)
	vfx.ring_emit("magic", g + Vector3(0, 0.15, 0), 0.6 * s, 10, col.lerp(Color.WHITE, 0.2), 0.6, 3.5, 0.9, 0.8)
	vfx.emit_one("flash", g + Vector3(0, 0.6, 0), Vector3.ZERO, Color(col.lerp(Color.WHITE, 0.4), 0.7), 0.8 * s, 0.8)


## The card worked but had nothing to act on (empty area, immune target...).
func fizzle(pos: Vector3, text := "NO EFFECT") -> void:
	vfx.fizzle(pos, text)


## A visual-only throw at the spot a runner left (the target was gone at release).
func lost_throw(from: Vector3, to: Vector3, color: Color, trail := "comet") -> void:
	battle.projectiles.launch_at(from, to, 26.0, {"color": color, "trail": trail}, func(at: Vector3) -> void:
		vfx.dust(at, 0.5)
		vfx.fizzle(at, "NO TARGET"))


## Sky Hook with no runner on the field: the hook still flies out and comes back empty.
func hook_whiff(from: Vector3) -> void:
	var to := Field.MOUND + Vector3(randf_range(-2.0, 2.0), 0.4, -5.0)
	battle.projectiles.launch_at(from, to, 30.0, {"color": CYAN, "big": true, "arc_mult": 3.5, "trail": "hook"}, func(at: Vector3) -> void:
		impact_flash(at, CYAN, 0.8, 0.0, 8)
		vfx.fizzle(at, "NO RUNNERS"))


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
		"called_shot":
			col = GOLD
		"line_drive":
			col = Color(1.0, 0.92, 0.7)
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
	var ring: MeshInstance3D = vfx._take("ring")
	ring.set_instance_shader_parameter("color", Color(color, 0.95))
	ring.set_instance_shader_parameter("mode", 1.0)
	ring.set_instance_shader_parameter("params", Vector4(0.08, 0.15, 2.0, 8.0))
	vfx.animate(ring, windup + 0.15, func(n: Node3D, k: float) -> void:
		if is_instance_valid(target):
			n.global_position = _flat(target.global_position, 0.08)
		var s2 := lerpf(3.2, 1.0, 1.0 - pow(1.0 - minf(k * 1.3, 1.0), 3.0))
		n.scale = Vector3(s2, 1, s2)
		(n as MeshInstance3D).set_instance_shader_parameter("progress", minf(k * 4.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, k))))
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
			# A dizzy "pop": violet flash, a small spinning swirl on the ground under the
			# runner and a big spiral + question mark over its head that linger.
			var kc := Color(0.85, 0.6, 1.0)
			impact_flash(at, kc, 1.4, 4.0, 16)
			vfx.emit("magic", at, 18, kc, 5.0, 0.8)
			vfx.emit("smoke", at, 6, Color(0.45, 0.3, 0.65, 0.6), 2.0, 0.5, 1.0, 0.7)
			vfx.emit_one("ring", at, Vector3.ZERO, VIOLET, 1.8, 1.0)
			vfx.ground_fx("vortex", _flat(at), 1.5, Color(0.7, 0.45, 1.0, 0.9), Color(0.95, 0.85, 1.0), 1.6, Vector2(2.5, 0.0))
			vfx.shockwave(_flat(at), 2.2, VIOLET, 0.35, 0.07)
			vfx.glyph(at + Vector3(0, 1.5, 0), 11, 2.1, kc, 1.6, 0.0, 0.5)
			vfx.glyph(at + Vector3(0.9, 2.3, 0), 1, 1.3, Color(1.0, 0.85, 1.0), 1.3, 0.12, 0.6)
			vfx.ring_emit("magic", at + Vector3(0, 0.9, 0), 0.7, 12, kc, 1.5, 0.5, 0.9, 1.0)
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
		"hot":
			# Hot Corner throw: a fiery punch-through.
			impact_flash(at, HOT, 1.1, 0.0, 12)
			vfx.spray("fire", at, 4, HOT, 3.0, Vector3.UP, 0.8, 0.7, 0.6)
			if target and is_instance_valid(target) and float(target.get("armor")) > 0.0:
				vfx.spray("spark", at, 10, Color(1.0, 0.8, 0.5), 9.0, (at - vfx.camera_pos()).normalized(), 0.5, 0.9, 0.7)
				vfx.emit_one("ring", at, Vector3.ZERO, Color(1.0, 0.7, 0.3), 1.2, 0.8)
		_:
			impact_flash(at, color, 1.0, 0.0, 10)


# ---------------------------------------------------------------- Update 5 cards

const HOT := Color(1.0, 0.42, 0.12)
const TAG_TEAL := Color(0.35, 1.0, 0.85)
const BULLPEN := Color(0.55, 1.0, 0.5)


## Called Shot: the ball comes down out of the sky with a long golden streak; a light pillar
## marks the landing spot during the fall.
func called_shot_drop(sky: Vector3, land: Vector3, flight: float) -> void:
	var g := _flat(land)
	vfx.beam(g, 0.9, 16.0, Color(GOLD, 0.8), flight + 0.15)
	vfx.zone_ring(g, 1.6, Color(1.0, 0.85, 0.35, 0.95), flight + 0.1, 0.25, 3.0, 12.0)
	vfx.ribbon(PackedVector3Array([sky, sky.lerp(land, 0.5), land + Vector3(0, 1.0, 0)]), Color(1.0, 0.9, 0.5), 0.12, flight + 0.15, 0.0, false)
	vfx.emit_one("flash", sky, Vector3.ZERO, Color(1.0, 0.95, 0.7, 0.9), 1.6, 0.8)


## Called Shot impact: a golden starburst, crown icon, ground crack; bigger on a boss.
func called_shot_impact(at: Vector3, boss: bool) -> void:
	var s := 1.5 if boss else 1.0
	impact_flash(at, GOLD, 1.9 * s, 8.0, int(26 * s))
	vfx.emit_one("ring", at, Vector3.ZERO, Color(1.0, 0.95, 0.75), 2.6 * s, 1.2)
	vfx.shockwave(_flat(at), 4.2 * s, GOLD, 0.55, 0.1)
	vfx.shockwave(_flat(at), 2.4 * s, Color(1.0, 0.95, 0.8), 0.35, 0.06, 0.05)
	vfx.sphere_pulse(_flat(at, 0.2), 2.6 * s, Color(GOLD, 0.6), 0.5)
	vfx.burst("gold", at)
	vfx.shake(0.2 * s)
	vfx.decal("crater", _flat(at), 1.6 * s, Color(0.25, 0.16, 0.08, 0.7), GOLD, 2.5)
	vfx.beam(_flat(at), 1.1 * s, 12.0, GOLD, 0.45)
	vfx.spray("debris", _flat(at, 0.3), 8, Color(0.5, 0.37, 0.27), 7.0, Vector3.UP, 0.8, 0.8, 1.0)
	vfx.glyph(at + Vector3(0, 1.6 * s, 0), 0, 1.5 * s, GOLD, 0.9, 0.0, 0.8)
	if boss:
		vfx.glyph(at + Vector3(0, 0.6, 0), 6, 1.6, Color(0.55, 0.75, 1.0), 1.1, 0.25, -0.6)


## Line Drive: a muzzle-flash crack at the bat / hand and a flat white streak.
func line_drive_release(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	vfx.emit_one("flash", from, Vector3.ZERO, Color(1.0, 0.95, 0.8, 0.9), 0.8, 0.8)
	vfx.emit_one("ring", from + dir * 0.8, dir * 6.0, Color(1.0, 0.95, 0.8), 1.1, 0.8)
	vfx.spray("streak", from, 12, Color(1.0, 0.95, 0.8), 16.0, dir, 0.15, 1.0, 0.5)


## Line Drive impact: a comic starburst, a ring the size of the hit area and a dirt spray.
func line_drive_impact(point: Vector3, r: float, dir: Vector3) -> void:
	var g := _flat(point)
	var col := Color(1.0, 0.9, 0.6)
	impact_flash(g + Vector3(0, 0.7, 0), col, 1.5, 6.0, 20)
	vfx.burst("explosion", g + Vector3(0, 0.6, 0), Color(1.0, 0.75, 0.4))
	vfx.shockwave(g, r, col, 0.3, 0.09)
	vfx.shockwave(g, r * 1.25, Color(1.0, 0.75, 0.4, 0.8), 0.45, 0.04, 0.06)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	vfx.spray("dust", g + Vector3(0, 0.3, 0), 12, Color(0.62, 0.46, 0.33, 0.7), 6.0, (dir + Vector3(0, 0.8, 0)).normalized(), 0.7, 1.2, 0.9)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 6, Color(0.5, 0.37, 0.27), 7.0, (dir + Vector3(0, 1.0, 0)).normalized(), 0.6, 0.7, 1.0)
	vfx.decal("scorch", g, r * 0.7, Color(0.12, 0.08, 0.05, 0.55), Color(1.0, 0.6, 0.2), 1.8)


## Tag at the Plate: the plate lights up teal and stays armed (a pulsing ring and a glove
## icon) until a runner is tagged or the window ends.
func tag_plate(dur: float) -> void:
	var h := Field.HOME
	vfx.ground_fx("hexdisc", h, 2.6, Color(TAG_TEAL, 0.8), Color.WHITE, 0.9)
	vfx.shockwave(h, 3.6, TAG_TEAL, 0.45, 0.07)
	vfx.beam(h, 1.4, 6.0, TAG_TEAL, 0.6)
	vfx.ring_emit("magic", h + Vector3(0, 0.2, 0), 1.8, 16, TAG_TEAL, 0.5, 3.5, 1.0, 0.9)
	vfx.dust(h, 1.2)
	var ring: MeshInstance3D = vfx._take("ring")
	ring.global_position = Vector3(h.x, 0.08, h.z)
	ring.scale = Vector3(2.3, 1, 2.3)
	ring.set_instance_shader_parameter("color", Color(TAG_TEAL, 0.95))
	ring.set_instance_shader_parameter("mode", 1.0)
	ring.set_instance_shader_parameter("params", Vector4(0.06, 0.1, 1.2, 10.0))
	ring.set_instance_shader_parameter("progress", 0.0)
	var icon := vfx.glyph(h + Vector3(0, 2.4, 0), 13, 1.2, TAG_TEAL, dur, 0.0, 0.0)
	var fade := [1.0]
	vfx.animate(ring, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var armed := battle.buff_active("plate_tag")
		fade[0] = move_toward(fade[0], 1.0 if armed else 0.0, _dt() * 4.0)
		var vis := smoothstep(0.0, 0.15, tt) * float(fade[0]) * (1.0 - smoothstep(dur - 0.4, dur, tt))
		var pulse := 0.75 + 0.25 * sin(tt * 7.0)
		(n as MeshInstance3D).set_instance_shader_parameter("progress", vis * pulse)
		if is_instance_valid(icon):
			icon.visible = float(fade[0]) > 0.05)


## A runner reaching home is tagged out (or a boss is blocked and shoved back).
func plate_tag(e: Node3D, tagged: bool) -> void:
	var c: Vector3 = e.center()
	impact_flash(c, TAG_TEAL, 1.6, 6.0, 20)
	vfx.burst("out", c)
	vfx.shockwave(_flat(Field.HOME), 3.8, TAG_TEAL, 0.45, 0.08)
	vfx.dust(Field.HOME, 2.0)
	vfx.glyph(c + Vector3(0, 1.4, 0), 14, 1.6, TAG_TEAL, 0.9, 0.0, 0.8)
	vfx.text_popup(Field.HOME + Vector3(0, 2.8, 0), "TAGGED OUT!" if tagged else "BLOCKED!", Color(0.5, 1.0, 0.9), 1.2, 1.1)
	var catcher: Node3D = null
	var best := INF
	for df in battle.defenders:
		var dd := Field.v2(df.global_position).distance_to(Field.v2(Field.HOME))
		if dd < best:
			best = dd
			catcher = df
	if catcher and best < 14.0:
		vfx.ribbon(vfx.arc_points(catcher.model.glove_position(), c, 0.8, 10), TAG_TEAL, 0.14, 0.35)


## Bullpen Call: the bullpen gate in the outfield lights up and a stream of green light
## (the fresh arm) arcs in to the mound. There the drawn cards pop out as real little cards
## and fly down to the hand, with a big "+N" energy bolt, so it reads from the battle camera.
func bullpen_call(drawn: Array = [], energy := 0.0) -> void:
	var gate := Field.wall_point(-38.0, 29.0)
	var mound := Field.MOUND
	vfx.beam(gate, 1.6, 8.0, BULLPEN, 0.8)
	vfx.shockwave(_flat(gate), 4.0, BULLPEN, 0.5, 0.06)
	vfx.flash_light(gate + Vector3(0, 3.0, 0), BULLPEN, 4.0, 14.0, 0.5)
	var pts := vfx.arc_points(gate + Vector3(0, 1.5, 0), mound + Vector3(0, 1.2, 0), 7.0, 18)
	vfx.ribbon(pts, BULLPEN, 0.45, 0.7)
	vfx.ribbon(pts, Color(0.9, 1.0, 0.85), 0.12, 0.55)
	for i in 10:
		var t := float(i) / 9.0
		var p: Vector3 = pts[int(t * (pts.size() - 1))]
		vfx.after(t * 0.35, func() -> void:
			vfx.emit_one("glow", p, Vector3(0, 0.5, 0), Color(BULLPEN, 0.8), 1.4, 0.6)
			vfx.emit_one("magic", p, Vector3(randf_range(-1, 1), 1.0, randf_range(-1, 1)), BULLPEN, 1.2, 0.7))
	vfx.after(0.4, func() -> void:
		impact_flash(mound + Vector3(0, 1.0, 0), BULLPEN, 1.8, 5.0, 20)
		vfx.shockwave(mound, 6.0, BULLPEN, 0.5, 0.07)
		vfx.beam(mound, 1.2, 7.0, BULLPEN, 0.5)
		vfx.ring_emit("magic", mound + Vector3(0, 0.3, 0), 1.4, 18, BULLPEN, 1.0, 4.5, 1.2, 0.9)
		var n := maxi(drawn.size(), 1)
		for i in n:
			var id: String = drawn[i] if i < drawn.size() else ""
			var side := (float(i) - (n - 1) * 0.5) * 3.2
			flying_card(id, mound + Vector3(side * 0.6, 2.8, 0), side, i * 0.09)
		if energy > 0.0:
			vfx.glyph(mound + Vector3(0, 4.6, 0), 8, 3.0, Color(0.45, 0.9, 1.0), 1.1, 0.05, 1.0)
			vfx.text_popup(mound + Vector3(0, 6.2, 0), "+%d ENERGY" % int(energy), Color(0.55, 0.92, 1.0), 1.25, 1.2))


## A little card (frame in its category colour, its art on the face, a dark text panel)
## that pops out at `from`, hangs for a beat, then flies down toward the hand at the bottom
## of the screen and fades. Used for card draws (Bullpen Call, Seventh-Inning Stretch).
func flying_card(card_id: String, from: Vector3, side: float, delay := 0.0, size := 1.7) -> void:
	# No id (hand already full): a gold-framed navy card back.
	var col := card_color(card_id) if card_id != "" else Color(0.96, 0.75, 0.3)
	var root := Node3D.new()
	vfx.add_child(root)
	root.global_position = from
	var parts: Array[Sprite3D] = []
	# Frame, text panel, art (back to front).
	var specs := [[Vector2(1.5, 2.1), Vector2.ZERO, col.lightened(0.25), null, 5],
		[Vector2(1.3, 0.78), Vector2(0, -0.55), Color(0.06, 0.09, 0.16), null, 6],
		[Vector2(1.3, 0.98), Vector2(0, 0.38), Color.WHITE if card_id != "" else Color(0.14, 0.22, 0.42), DB.card_texture(card_id) if card_id != "" else null, 6]]
	for sp in specs:
		var sz: Vector2 = sp[0]
		var tex: Texture2D = sp[3]
		if tex == null:
			tex = _white_tex()
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.no_depth_test = true
		spr.render_priority = int(sp[4])
		spr.pixel_size = sz.x / float(tex.get_width())
		spr.scale = Vector3(1, (sz.y / sz.x) * float(tex.get_width()) / float(tex.get_height()), 1)
		spr.offset = Vector2(sp[1]) / spr.pixel_size / Vector2(1, spr.scale.y)
		spr.modulate = sp[2]
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(spr)
		parts.append(spr)
	var start := from
	var dest := Field.HOME + Vector3(side * 0.8, 3.5, 2.0)
	var dur := 1.05
	root.scale = Vector3.ONE * 0.01
	var an := vfx.animate(root, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var pop := 1.0 - pow(1.0 - clampf(tt / 0.16, 0.0, 1.0), 3.0)
		var over := 1.0 + 0.25 * sin(clampf(tt / 0.16, 0.0, 1.0) * PI)
		var fly := clampf((tt - 0.45) / 0.55, 0.0, 1.0)
		var fe := fly * fly
		var hover := Vector3(0, 0.5 * pop, 0) + Vector3(side * 0.25, 0, 0) * pop
		n.global_position = (start + hover).lerp(dest, fe) + Vector3(0, sin(fe * PI) * 2.0, 0)
		n.scale = Vector3.ONE * maxf(0.01, size * pop * over * lerpf(1.0, 0.55, fe))
		var a := 1.0 - smoothstep(0.75, 1.0, fly)
		for spr in parts:
			spr.modulate.a = a
		if fly > 0.0 and _rate(40.0):
			vfx.emit_one("glow", n.global_position, Vector3.ZERO, Color(col, 0.7), 0.9, 0.35), delay)
	an.free_node = true
	vfx.after(delay, func() -> void:
		vfx.emit_one("flash", from, Vector3.ZERO, Color(col.lerp(Color.WHITE, 0.5), 0.9), 1.6, 0.8)
		vfx.spray("spark", from, 10, col.lerp(Color.WHITE, 0.4), 6.0, Vector3.UP, 1.2, 0.9, 0.7))


var _white: Texture2D


func _white_tex() -> Texture2D:
	if _white == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white = ImageTexture.create_from_image(img)
	return _white


## Hot Corner: anticipation (flame streaks rush into the defender), impact (an eruption of
## flame and a fire column), then for the whole buff a burning ring with flame licks at the
## feet, a torch in the throwing hand and a fiery flare on every throw it makes.
func hot_corner(df: Node3D, dur: float) -> void:
	if df == null or not is_instance_valid(df):
		return
	var feet := _flat(df.global_position)
	var chest: Vector3 = df.model.chest_position()
	# Anticipation: streaks converge on the chest and the ground ring implodes.
	for i in vfx._count(16):
		var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 0.8), randf_range(-1, 1)).normalized()
		var st := chest + d * randf_range(2.2, 3.2)
		vfx.emit_one("streak", st, (chest - st) / 0.16, Color(1.0, 0.6, 0.2), 1.0, 0.7)
	vfx.shockwave(feet, 3.0, Color(1.0, 0.5, 0.15, 0.9), 0.18, 0.06, 0.0, true)
	# Impact at 0.16 s.
	vfx.after(0.16, func() -> void:
		if not is_instance_valid(df):
			return
		var f := _flat(df.global_position)
		impact_flash(df.model.chest_position(), HOT, 1.8, 7.0, 24)
		vfx.shockwave(f, 4.0, HOT, 0.45, 0.08)
		vfx.beam(f, 0.9, 7.0, Color(1.0, 0.5, 0.12), 0.6)
		vfx.heat_haze(f + Vector3(0, 0.2, 0), 2.6, 4.0, 1.4)
		for i in 7:
			var a := i * TAU / 7.0
			vfx.flame_sheet(f + Vector3(cos(a), 0, sin(a)) * 1.0, 1.1, randf_range(2.4, 3.2), 0.85, i * 0.025)
		vfx.spray("fire", f + Vector3(0, 0.4, 0), 10, FIRE, 5.0, Vector3.UP, 0.6, 1.3, 0.8)
		vfx.emit("ember", f + Vector3(0, 0.8, 0), 16, Color(1.0, 0.6, 0.2), 5.0, 1.2)
		vfx.decal("scorch", f, 1.6, Color(0.08, 0.05, 0.04, 0.7), Color(1.0, 0.45, 0.1), 2.5)
		vfx.glyph(df.model.head_position() + Vector3(0, 1.2, 0), 15, 1.8, Color(1.0, 0.62, 0.25), 1.6, 0.0, 0.7)
		vfx.text_popup(df.model.head_position() + Vector3(0, 2.4, 0), "RED HOT!", Color(1.0, 0.62, 0.3), 1.0, 1.2))
	defender_aura(df, Color(HOT, 0.95), dur, 1.35)
	var last := [-1.0, 0.0]   # previous release countdown, time since the last flame lick
	vfx.every_frame(dur, func(k: float) -> void:
		if not is_instance_valid(df):
			return
		var f2 := _flat(df.global_position)
		var hand: Vector3 = df.model.hand_position()
		var fade := 1.0 - smoothstep(0.9, 1.0, k)
		if _rate(20.0 * fade):
			vfx.emit_one("fire", hand + Vector3(randf_range(-0.08, 0.08), 0, randf_range(-0.08, 0.08)), Vector3(0, 1.4, 0), HOT, 0.75, 0.55)
		if _rate(8.0 * fade):
			vfx.emit_one("ember", f2 + Vector3(randf_range(-0.9, 0.9), 0.3, randf_range(-0.9, 0.9)), Vector3(0, 1.8, 0), Color(1.0, 0.55, 0.2), 1.1, 1.0)
		# A small flame licks up somewhere on the ring every ~0.3 s.
		last[1] = float(last[1]) + _dt()
		if float(last[1]) > 0.3 and fade > 0.5:
			last[1] = 0.0
			var a := randf() * TAU
			vfx.flame_sheet(f2 + Vector3(cos(a), 0, sin(a)) * 1.25, 0.6, randf_range(0.9, 1.4), 0.5)
		# Every throw it makes flares at the release: the fire trail starts with a burst.
		var pr := float(df.get("_pending_release"))
		if float(last[0]) >= 0.0 and pr < 0.0:
			_hot_release(df)
		last[0] = pr)


func _hot_release(df: Node3D) -> void:
	var hand: Vector3 = df.model.hand_position()
	var tgt = df.get("target")
	var dir := Vector3.FORWARD
	if tgt is Node3D and is_instance_valid(tgt):
		dir = ((tgt as Node3D).global_position + Vector3(0, 1.0, 0) - hand).normalized()
	vfx.emit_one("flash", hand, Vector3.ZERO, Color(1.0, 0.7, 0.35, 0.95), 1.3, 0.8)
	vfx.emit_one("ring", hand + dir * 0.5, dir * 3.0, Color(1.0, 0.55, 0.2), 1.2, 0.8)
	vfx.spray("fire", hand, 6, FIRE, 6.0, dir, 0.35, 1.0, 0.5)
	vfx.spray("spark", hand, 8, Color(1.0, 0.75, 0.35), 10.0, dir, 0.3, 0.9, 0.5)


## Perfect Game: the whole diamond lights up gold, a pillar rises at every base and a crown
## shines over the mound; home plate keeps a gold tag ring while the window lasts.
func perfect_game(tag_time: float) -> void:
	var m := Field.MOUND
	vfx.ground_fx("diamond", m, 19.0, Color(GOLD, 0.85), Color.WHITE, 1.6)
	vfx.shockwave(m, 30.0, GOLD, 0.9, 0.04)
	vfx.shockwave(m, 18.0, Color(1.0, 0.95, 0.8, 0.9), 0.6, 0.06, 0.1)
	var bases := [Field.HOME, Field.FIRST, Field.SECOND, Field.THIRD]
	for i in bases.size():
		var b: Vector3 = bases[i]
		vfx.beam(b, 1.3, 14.0, GOLD, 1.1, i * 0.06)
		vfx.after(i * 0.06, func() -> void:
			impact_flash(b + Vector3(0, 0.6, 0), GOLD, 1.3, 0.0, 14))
	vfx.glyph(m + Vector3(0, 6.0, 0), 0, 4.0, GOLD, 1.6, 0.0, 1.2)
	vfx.flash_light(m + Vector3(0, 8.0, 0), GOLD, 6.0, 40.0, 0.9)
	vfx.burst("confetti", Field.HOME + Vector3(0, 7, -6))
	vfx.burst("confetti", m + Vector3(0, 8, 0))
	# Gold tag ring at the plate while the tag window is open.
	var ring: MeshInstance3D = vfx._take("ring")
	ring.global_position = Vector3(Field.HOME.x, 0.08, Field.HOME.z)
	ring.scale = Vector3(2.6, 1, 2.6)
	ring.set_instance_shader_parameter("color", Color(GOLD, 0.95))
	ring.set_instance_shader_parameter("mode", 1.0)
	ring.set_instance_shader_parameter("params", Vector4(0.06, 0.1, 1.2, 10.0))
	ring.set_instance_shader_parameter("progress", 0.0)
	vfx.animate(ring, tag_time, func(n: Node3D, k: float) -> void:
		var tt := k * tag_time
		var vis := smoothstep(0.0, 0.2, tt) * (1.0 - smoothstep(tag_time - 0.5, tag_time, tt))
		(n as MeshInstance3D).set_instance_shader_parameter("progress", vis * (0.75 + 0.25 * sin(tt * 6.0))))


## One runner struck by Perfect Game: a bolt of gold light from above.
func perfect_strike(e: Node3D) -> void:
	var c: Vector3 = e.center()
	vfx.bolt(c + Vector3(randf_range(-1.0, 1.0), 14.0, randf_range(-1.0, 1.0)), c, Color(1.0, 0.88, 0.45), 0.16, 0.3, 2, 0.14, 2)
	impact_flash(c, GOLD, 1.0, 0.0, 10)
	vfx.shockwave(_flat(c), 1.6, GOLD, 0.35, 0.06)


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
	# Anticipation that reads from the battle camera: a filled violet target zone and rings
	# that tighten onto it in time with the falling ball.
	var g := _flat(point)
	vfx.zone_ring(g, r, Color(0.72, 0.42, 1.0, 0.95), flight + 0.05, 0.22, 1.5, 12.0)
	var rings := maxi(1, int(flight / 0.3))
	for i in rings:
		vfx.shockwave(g, r * 1.8, Color(0.8, 0.55, 1.0, 0.8), 0.3, 0.05, i * 0.3, true)
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
	vfx.sphere_pulse(g + Vector3(0, 0.2, 0), r * 1.1, Color(VIOLET, 0.6), 0.45)
	vfx.glyph(g + Vector3(0, 2.8, 0), 15, 1.6, Color(0.85, 0.65, 1.0), 1.0, 0.05, 0.7)
	vfx.shake(0.12)


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


## Changeup: the tempo drops. Three slow, heavy beats roll out from the plate in lavender
## (a rhythm, not a clock: the stopwatch belongs to Time Out), a slow radar sweep turns at
## the plate, and every runner drags a ghostly after-image.
func changeup() -> void:
	var c := Field.HOME
	var col := Color(0.62, 0.55, 1.0)
	for i in 3:
		vfx.shockwave(c, 30.0, Color(col, 0.95 - i * 0.2), 1.5, 0.05 - i * 0.01, i * 0.32)
		vfx.after(i * 0.32, func() -> void:
			vfx.emit_one("ring", c + Vector3(0, 0.6, 0), Vector3.ZERO, Color(0.8, 0.75, 1.0), 3.5, 1.2)
			vfx.ring_emit("magic", c + Vector3(0, 0.3, 0), 2.0, 14, col, 1.0, 1.0, 1.0, 1.0))
	vfx.ground_fx("radar", c, 4.5, Color(col, 0.8), Color(0.9, 0.85, 1.0), 1.6, Vector2(0.25, 0.0))
	vfx.beam(c, 1.2, 6.0, col, 0.7)
	vfx.flash_light(c + Vector3(0, 2.0, 0), col, 3.0, 12.0, 0.6)


func changeup_victim(e: Node3D) -> void:
	var col := Color(0.62, 0.55, 1.0)
	vfx.emit("magic", e.center(), 6, Color(0.7, 0.65, 1.0), 1.5, 0.2)
	vfx.emit_one("ring", e.center(), Vector3.ZERO, Color(col, 0.8), 1.2, 1.4)
	# Slow-motion after-image: soft lavender streaks left behind along the path.
	if "route" in e and e.route:
		var back: Vector3 = -e.route.direction_at(e.d)
		for i in 3:
			vfx.emit_one("glow", e.center() + back * (0.5 + i * 0.5), back * 0.4, Color(col, 0.55 - i * 0.15), 1.4 - i * 0.25, 1.0)


## Pickoff: a laser-straight snap throw.
func pickoff_strike(from: Vector3, to: Vector3, picked: bool) -> void:
	var pts := PackedVector3Array([from, from.lerp(to, 0.5), to])
	vfx.ribbon(pts, TEAL, 0.4, 0.4, 0.0, false)
	vfx.ribbon(pts, Color(0.8, 1.0, 0.95), 0.12, 0.3, 0.0, false)
	vfx.line_emit("streak", from, to, 10, Color(0.6, 1.0, 0.9), (to - from).normalized() * 12.0, 0.15, 1.0, 0.4)
	impact_flash(to, TEAL, 1.6 if picked else 1.2, 5.0, 18)
	vfx.shockwave(_flat(to), 2.2, Color(TEAL, 0.9), 0.3, 0.07)
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


## Bunt Trap: the trap snaps down on the path: a web seal that tightens, a dirt puff and
## a chain icon, so the spot reads even when a runner springs it at once.
func bunt_trap_cast(at: Vector3) -> void:
	var g := _flat(at)
	var col := card_color("bunt_trap")
	vfx.decal("web", g, 1.8, Color(col.lightened(0.3), 0.95), Color.WHITE, 1.6, func(n: Node3D, k: float) -> void:
		var tt := k * 1.6
		var snap := 1.0 - pow(1.0 - clampf(tt / 0.18, 0.0, 1.0), 3.0)
		var sc := lerpf(3.2, 1.8, snap)
		n.scale = Vector3(sc, 1, sc)
		var vis := minf(tt / 0.08, 1.0) * (1.0 - smoothstep(1.1, 1.6, tt))
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis, tt * 0.5, snap)))
	vfx.shockwave(g, 3.0, col.lightened(0.2), 0.2, 0.08, 0.0, true)
	vfx.after(0.18, func() -> void:
		impact_flash(g + Vector3(0, 0.4, 0), col, 1.1, 3.0, 12)
		vfx.dust(g, 1.3)
		vfx.glyph(g + Vector3(0, 2.0, 0), 4, 1.5, col.lightened(0.35), 1.0, 0.0, 0.6))


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

## A glowing aura that follows a defender for the length of a buff. It lands bright for
## about half a second, then settles into a quiet ground ring so long buffs don't cover
## the field.
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
		mi.set_instance_shader_parameter("params", Vector4(0.07, 0.12, 1.5, 6.0))
		mi.set_instance_shader_parameter("progress", 0.0)
	else:
		mi.set_instance_shader_parameter("color", color)
		mi.set_instance_shader_parameter("color2", Color.WHITE)
		mi.set_instance_shader_parameter("anim", Vector4(0, 0, 1, 0))
	vfx.animate(mi, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var vis := smoothstep(0.0, 0.2, tt) * (1.0 - smoothstep(dur - 0.6, dur, tt))
		var settle := 1.0 - 0.5 * smoothstep(0.4, 1.1, tt)
		var pulse := 0.88 + 0.12 * sin(tt * 4.0)
		var m := n as MeshInstance3D
		if kind == "ring":
			m.set_instance_shader_parameter("progress", vis * settle * pulse)
		else:
			m.set_instance_shader_parameter("anim", Vector4(k, vis * (0.55 + 0.45 * settle), 1.0, 0.0)))


func twin_play(caster: Node3D, dur: float) -> void:
	var col := Color(0.35, 1.0, 0.55)
	var c: Vector3 = _flat(caster.global_position) if caster and is_instance_valid(caster) else Field.HOME
	# One quick sweep (not a field-wide ring that hangs around).
	vfx.shockwave(c, 12.0, col, 0.55, 0.035)
	vfx.flash_light(c + Vector3(0, 2.0, 0), col, 4.0, 10.0, 0.4)
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


## Rally Cry: a short shout from every defender (a small bubble, the shout icon and a quick
## light shaft) and one thin wave from the mound; then only a quiet ring under each defender.
func rally_cry(dur: float) -> void:
	var col := Color(1.0, 0.82, 0.3)
	vfx.shockwave(Field.MOUND, 20.0, col, 0.7, 0.03)
	for df in battle.defenders:
		var p: Vector3 = _flat(df.global_position)
		vfx.sphere_pulse(p + Vector3(0, 0.3, 0), 1.9, Color(col, 0.5), 0.4, 0.05)
		vfx.beam(p, 0.7, 3.5, col, 0.5, 0.1)
		vfx.glyph(df.model.head_position() + Vector3(0, 0.9, 0), 9, 1.2, Color(1.0, 0.85, 0.35), 0.9, 0.1, 0.8)
		defender_aura(df, Color(col, 0.8), dur, 1.3)
		vfx.after(0.15, func() -> void:
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
func stretch(drawn: Array = [], energy := 0.0) -> void:
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
	# A golden pop on the infield so the cast reads even when the fireworks are off screen.
	vfx.shockwave(Field.MOUND, 9.0, GOLD, 0.7, 0.06)
	vfx.glyph(Field.MOUND + Vector3(0, 3.0, 0), 12, 2.2, GOLD, 1.2, 0.0, 1.2)
	vfx.ring_emit("magic", Field.MOUND + Vector3(0, 0.3, 0), 1.5, 18, GOLD, 1.0, 5.0, 1.1, 1.0)
	# The drawn cards pop out over the mound and fly to the hand; the energy shows as "+N".
	for i in drawn.size():
		var side := (float(i) - (drawn.size() - 1) * 0.5) * 2.4
		flying_card(drawn[i], Field.MOUND + Vector3(side * 0.5, 2.4, 0), side, 0.25 + i * 0.09)
	if energy > 0.0:
		vfx.text_popup(Field.MOUND + Vector3(0, 5.6, 0), "+%d ENERGY" % int(energy), Color(0.55, 0.92, 1.0), 1.25, 1.3)


# ---------------------------------------------------------------- debug showcase

## `--vfx-showcase=<card_id>[,<card_id>...]`: waits for the Practice Field, spawns a slow
## pack of tough runners, frames the camera (unless --cam-view is given) and casts the card
## after `--vfx-delay=<s>` (default 1.0). With `--vfx-shots=t1,t2 --vfx-out=<dir>` it saves
## frames t seconds after each cast (a card may carry its own times: `card@0.2/0.6`),
## clears the field, waits `--vfx-gap=<s>` (default 2.5), moves on to the next card and quits
## at the end.
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
	var gap := 2.5
	for a in args:
		if a.begins_with("--vfx-gap="):
			gap = float(a.split("=")[1])
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
			await tree.create_timer(gap, false).timeout
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
	# --vfx-empty casts on an empty field (checks the no-target / fizzle visuals).
	for i in (0 if "--vfx-empty" in args else 11):
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
		"heat_wave", "grand_relay", "thunderbolt", "pickoff", "sky_hook", "diving_catch", "power_catch", "called_shot", "line_drive":
			focus = target.lerp(Field.MOUND, 0.35)
			view = Vector3(25.0, -42.0, 34.0)
		"tag_at_the_plate":
			# A runner arrives at the plate shortly after the cast and is tagged out.
			focus = Field.HOME + Vector3(0, 0, -1.5)
			view = Vector3(160.0, -32.0, 19.0)
		"perfect_game", "bullpen_call":
			focus = Field.MOUND + Vector3(0, 0, 2)
			view = Vector3(0.0, -46.0, 50.0)
		"hot_corner":
			focus = target.lerp(Field.MOUND, 0.5)
			view = Vector3(25.0, -40.0, 28.0)
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
	if card_id in ["tag_at_the_plate", "perfect_game"]:
		# A runner reaches the plate during the tag window.
		var home_route: Route = battle.routes[battle.routes.size() - 1]
		battle.spawn_enemy("runner", home_route, home_route.length - 2.4, {"lateral": 0.0, "hp_mult": 60.0, "speed_mult": 1.0})
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
