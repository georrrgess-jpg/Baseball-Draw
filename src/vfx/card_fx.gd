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
const VividFX := preload("res://src/vfx/vivid_fx.gd")

## Shared card palette (Update 8). Each entry is a colour-over-life ramp:
## [white-hot core, light tint, saturated body, deep edge]. Ramp particles, ground glows,
## flash rings and halos take their colour from it, so a category reads as one family
## (offense hot reds and oranges, control violets and blues, defense teals and greens,
## utility golds) while each card keeps its own entry (CARD_RAMP).
const PALETTE := {
	# offense
	"fire": [Color(1.0, 0.96, 0.78), Color(1.0, 0.72, 0.22), Color(1.0, 0.3, 0.02), Color(0.5, 0.03, 0.01)],
	"blaze": [Color(1.0, 0.98, 0.86), Color(1.0, 0.84, 0.38), Color(1.0, 0.5, 0.04), Color(0.78, 0.12, 0.0)],
	"comet": [Color(1.0, 0.95, 0.9), Color(1.0, 0.6, 0.42), Color(1.0, 0.22, 0.08), Color(0.55, 0.0, 0.08)],
	"scarlet": [Color(1.0, 0.92, 0.9), Color(1.0, 0.45, 0.38), Color(1.0, 0.06, 0.14), Color(0.42, 0.0, 0.14)],
	"crimson": [Color(1.0, 0.9, 0.96), Color(1.0, 0.4, 0.66), Color(0.92, 0.04, 0.4), Color(0.36, 0.0, 0.34)],
	"volt": [Color(1.0, 1.0, 0.92), Color(1.0, 0.96, 0.5), Color(1.0, 0.74, 0.08), Color(0.9, 0.3, 0.0)],
	"solar": [Color(1.0, 0.99, 0.88), Color(1.0, 0.86, 0.4), Color(1.0, 0.58, 0.06), Color(0.85, 0.16, 0.04)],
	# control
	"violet": [Color(0.96, 0.92, 1.0), Color(0.78, 0.58, 1.0), Color(0.52, 0.14, 1.0), Color(0.2, 0.02, 0.52)],
	"indigo": [Color(0.94, 0.94, 1.0), Color(0.62, 0.64, 1.0), Color(0.3, 0.26, 1.0), Color(0.1, 0.04, 0.5)],
	"ice": [Color(0.95, 1.0, 1.0), Color(0.62, 0.9, 1.0), Color(0.16, 0.56, 1.0), Color(0.04, 0.14, 0.6)],
	# defense
	"teal": [Color(0.92, 1.0, 0.97), Color(0.42, 1.0, 0.86), Color(0.0, 0.86, 0.68), Color(0.0, 0.32, 0.42)],
	"emerald": [Color(0.94, 1.0, 0.9), Color(0.52, 1.0, 0.6), Color(0.04, 0.86, 0.36), Color(0.0, 0.34, 0.2)],
	"aqua": [Color(0.93, 1.0, 1.0), Color(0.5, 0.95, 1.0), Color(0.02, 0.72, 0.96), Color(0.0, 0.26, 0.52)],
	# utility
	"gold": [Color(1.0, 1.0, 0.88), Color(1.0, 0.92, 0.46), Color(1.0, 0.7, 0.06), Color(0.72, 0.3, 0.0)],
	"amber": [Color(1.0, 0.96, 0.86), Color(1.0, 0.76, 0.36), Color(1.0, 0.46, 0.04), Color(0.6, 0.14, 0.0)],
	"lime": [Color(0.97, 1.0, 0.86), Color(0.82, 1.0, 0.42), Color(0.42, 0.96, 0.08), Color(0.1, 0.45, 0.0)],
	"sky": [Color(0.93, 1.0, 1.0), Color(0.56, 0.95, 1.0), Color(0.08, 0.76, 1.0), Color(0.0, 0.3, 0.7)],
	# the Legendary accent: gold into magenta into violet
	"legend": [Color(1.0, 1.0, 0.92), Color(1.0, 0.86, 0.42), Color(1.0, 0.32, 0.56), Color(0.46, 0.1, 0.86)],
}
## The family of each category (the cast pop uses it).
const CATEGORY_RAMP := {"offense": "fire", "control": "violet", "defense": "teal", "utility": "gold"}
## Each card's own entry within its family.
const CARD_RAMP := {
	"heat_wave": "fire", "power_throw": "comet", "splitter": "scarlet", "grand_slam_barrage": "fire",
	"grand_relay": "solar", "power_catch": "crimson", "thunderbolt": "volt", "called_shot": "solar",
	"line_drive": "blaze", "bean_ball": "scarlet", "around_the_horn": "blaze", "grand_salami": "fire",
	"curveball": "violet", "knuckleball": "violet", "shadow_change": "violet", "time_out": "ice",
	"changeup": "indigo", "pickoff": "ice", "rundown": "indigo", "rain_delay": "ice", "intentional_walk": "indigo",
	"lockdown": "aqua", "frost_field": "aqua", "wall_of_dirt": "emerald", "base_shield": "aqua",
	"bunt_trap": "teal", "diving_catch": "teal", "tag_at_the_plate": "teal", "perfect_game": "gold",
	"infield_fly": "teal", "golden_glove": "gold", "the_shift": "teal",
	"twin_play": "lime", "field_vision": "sky", "diamond_aura": "gold", "rally_cry": "amber",
	"magnet_glove": "amber", "sky_hook": "sky", "bullpen_call": "lime", "hot_corner": "fire",
	"seventh_inning_stretch": "gold", "momentum": "sky", "relief_pitcher": "lime", "instant_replay": "legend",
	# Update 9
	"scouting_report": "violet", "sprinkler_system": "aqua", "sweet_spot": "solar", "rally_monkey": "amber",
	"second_wind": "lime", "money_ball": "gold", "scoop_and_tag": "emerald", "signal_caller": "amber",
	"hidden_ball_trick": "indigo", "worm_burner": "blaze", "fireworks_night": "crimson", "ground_rule_double": "gold",
}

var vfx: VFX
var battle: Battle
var vv: VividFX
var _salami_n := 0


func _init(p_vfx: VFX) -> void:
	vfx = p_vfx
	battle = p_vfx.battle as Battle
	vv = VividFX.new(p_vfx, PALETTE)


static func ramp_of(card_id: String) -> String:
	return String(CARD_RAMP.get(card_id, CATEGORY_RAMP.get(String(DB.card(card_id).get("category", "")), "gold")))


## The saturated body colour of a palette entry (times `mult` for HDR glow).
static func body(ramp: String, mult := 1.0) -> Color:
	var c: Color = (PALETTE.get(ramp, PALETTE.gold) as Array)[2]
	return Color(c.r * mult, c.g * mult, c.b * mult, 1.0)


## A palette stop (0 core, 1 tint, 2 body, 3 edge) with alpha.
static func pal(ramp: String, stop: int, a := 1.0) -> Color:
	var c: Color = (PALETTE.get(ramp, PALETTE.gold) as Array)[stop]
	return Color(c, a)


## Colour for a ramp particle (the ramp row rides in alpha).
func rc(ramp: String, tint := Color.WHITE) -> Color:
	return vv.row_color(ramp, tint)


## The shared punch of an impact (Update 8): a white-hot core flare that is gone in a
## tenth of a second, a saturated soft halo, sparks whose colour cools over their life,
## a short flash ring on the ground and light pooled on the ground that cools over
## `glow` seconds. `size` ~1 for a runner-sized hit.
func punch(pos: Vector3, ramp: String, size := 1.0, sparks := 14, glow := 1.4, ring := true) -> void:
	var g := _flat(pos)
	vfx.emit_one("v_flare", pos, Vector3.ZERO, rc(ramp), 1.1 * size, 1.0)
	vfx.emit_one("v_glow", pos, Vector3.ZERO, rc(ramp), 3.4 * size, 1.2)
	if sparks > 0:
		vfx.spray("v_spark", pos, sparks, rc(ramp), 11.0 * sqrt(size), Vector3.UP, 1.3, 1.1, 1.0)
		vfx.emit("v_ember", pos, int(sparks * 0.5), rc(ramp), 3.5 * sqrt(size), 0.8, 1.0, 1.0, 1.0)
	if ring:
		vfx.shockwave(g, 2.6 * size, body(ramp, 1.25), 0.24, 0.045)
	if glow > 0.0:
		vv.ground_glow(g, 2.3 * size, ramp, glow)


## Legendary accent: a short burst of radial streaks and coloured screen edges (no streaks
## and a dimmer edge with reduce_flashes), never longer than ~0.45 s.
func legend_accent(pos: Vector3, ramp: String, strength := 1.0) -> void:
	vv.screen_accent(pos, body(ramp, 1.0), body("legend", 1.0), 0.55 * strength)


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
	# The pop is in the category's family colour, the motes in the card's own ramp.
	var fam: String = CATEGORY_RAMP.get(String(DB.card(card_id).get("category", "")), "gold")
	var ramp := ramp_of(card_id)
	var g := _flat(pos)
	var s := rarity_scale(card_id)
	vfx.shockwave(g, 1.9 * s, body(fam, 1.2), 0.3, 0.07)
	vfx.ring_emit("v_mote", g + Vector3(0, 0.15, 0), 0.6 * s, 10, rc(ramp), 0.6, 3.5, 0.9, 0.8)
	vfx.emit_one("v_flare", g + Vector3(0, 0.6, 0), Vector3.ZERO, rc(fam), 0.6 * s, 0.9)
	vv.ground_glow(g, 1.5 * s, fam, 0.8, 0.9)


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
	var col := body(ramp_of(card_id), 1.1)
	var hand: Vector3 = caster.model.hand_position()
	var feet := _flat(caster.global_position)
	var s := rarity_scale(card_id)
	match card_id:
		"diving_catch":
			col = PINK
	var ramp := ramp_of(card_id)
	if anim != "special":
		# Quick throw: a spark of power gathering in the throwing hand.
		vfx.emit_one("v_glow", hand, Vector3.ZERO, rc(ramp), 1.6, windup * 2.6)
		vfx.spray("v_spark", hand, 8, rc(ramp), 4.0, Vector3.UP, 1.0, 0.7, 0.6)
		return
	# A gathering glow in the hand and light pooling under the caster.
	vfx.emit_one("v_glow", hand, Vector3.ZERO, rc(ramp), 2.0, (windup + 0.1) * 1.6)
	vv.ground_glow(feet, 1.6 * s, ramp, windup + 0.4, 0.9)
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
			if _rate(14.0):
				vfx.emit_one("v_mote", h + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)), Vector3(0, 0.6, 0), rc(ramp_of(card_id)), 0.9, 0.6)


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
	punch(a + Vector3(0, 1.0, 0), "fire", 1.3, 12, 1.2, false)
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
		if i % 2 == 0:
			vv.ground_glow(p, width * 0.75, "fire", time + 0.6, 0.3, delay, 0.8)
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
	vfx.emit_one("ring", from + dir * 0.6, Vector3.ZERO, body("comet", 1.2), 0.9, 0.8)
	vfx.emit_one("ring", from + dir * 1.6, dir * 4.0, pal("comet", 1), 1.3, 0.9)
	vfx.spray("v_spark", from, 14, rc("comet"), 14.0, dir, 0.25, 1.0, 0.6)
	vfx.emit_one("v_flare", from, Vector3.ZERO, rc("comet"), 0.7, 0.8)


## Impacts carried by thrown balls (payload "fx"). Called by the projectile manager.
func ball_impact(kind: String, at: Vector3, color: Color, target: Node3D = null) -> void:
	match kind:
		"power":
			impact_flash(at, body("comet"), 1.5, 7.0, 10)
			punch(at, "comet", 1.6, 24, 1.6)
			vfx.emit_one("impact", at, Vector3.ZERO, pal("comet", 1), 1.6, 1.0)
			vfx.emit_one("ring", at, Vector3.ZERO, pal("comet", 1), 2.2, 1.2)
			vfx.shockwave(_flat(at), 3.0, body("comet", 1.1), 0.4, 0.07)
			vfx.decal("scorch", _flat(at), 1.2, Color(0.1, 0.05, 0.04, 0.7), body("comet"), 2.2)
			vfx.dust(at, 1.2)
			vfx.shake(0.12)
		"split":
			# Each split ball lands with its own clear scarlet pop and a small scorch.
			punch(at, "scarlet", 1.1, 12, 1.3)
			vfx.emit_one("ring", at, Vector3.ZERO, pal("scarlet", 1), 1.5, 0.9)
			vfx.emit("v_mote", at, 6, rc("scarlet"), 4.0, 0.7)
			vfx.decal("scorch", _flat(at), 0.85, Color(0.12, 0.04, 0.05, 0.6), body("scarlet"), 2.2)
		"bean", "bean_fast":
			_bean_impact(at, target, kind == "bean_fast")
		"relief":
			impact_flash(at, RELIEF, 0.8, 0.0, 4)
			punch(at, "lime", 0.8, 6, 0.6, false)
			vfx.emit("magic", at, 4, RELIEF, 3.0, 0.6)
		"knuckle":
			# A dizzy "pop": violet flash, a small spinning swirl on the ground under the
			# runner and a big spiral + question mark over its head that linger.
			var kc := Color(0.85, 0.6, 1.0)
			impact_flash(at, kc, 1.2, 4.0, 6)
			punch(at, "violet", 1.4, 14, 1.6)
			vfx.emit("magic", at, 18, kc, 5.0, 0.8)
			vfx.emit("smoke", at, 6, Color(0.45, 0.3, 0.65, 0.6), 2.0, 0.5, 1.0, 0.7)
			vfx.emit_one("ring", at, Vector3.ZERO, VIOLET, 1.8, 1.0)
			vfx.ground_fx("vortex", _flat(at), 1.5, Color(0.7, 0.45, 1.0, 0.9), Color(0.95, 0.85, 1.0), 1.6, Vector2(2.5, 0.0))
			vfx.shockwave(_flat(at), 2.2, VIOLET, 0.35, 0.07)
			vfx.glyph(at + Vector3(0, 1.5, 0), 11, 2.1, kc, 1.6, 0.0, 0.5)
			vfx.glyph(at + Vector3(0.9, 2.3, 0), 1, 1.3, Color(1.0, 0.85, 1.0), 1.3, 0.12, 0.6)
			vfx.ring_emit("magic", at + Vector3(0, 0.9, 0), 0.7, 12, kc, 1.5, 0.5, 0.9, 1.0)
		"hook":
			impact_flash(at, CYAN, 1.3, 6.0, 8)
			punch(at, "sky", 1.5, 16, 1.4)
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
			impact_flash(at, HOT, 1.0, 0.0, 4)
			punch(at, "fire", 0.9, 8, 0.8, false)
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
	vfx.beam(g, 0.9, 16.0, pal("solar", 2, 0.85), flight + 0.15)
	vfx.zone_ring(g, 1.6, pal("solar", 1, 0.95), flight + 0.1, 0.25, 3.0, 12.0)
	vv.ground_glow(g, 1.8, "solar", flight + 0.3, 0.9)
	vfx.ribbon(PackedVector3Array([sky, sky.lerp(land, 0.5), land + Vector3(0, 1.0, 0)]), pal("solar", 1), 0.14, flight + 0.15, 0.0, false)
	vfx.emit_one("v_flare", sky, Vector3.ZERO, rc("solar"), 1.4, 0.8)


## Called Shot impact: a golden starburst, crown icon, ground crack; bigger on a boss.
func called_shot_impact(at: Vector3, boss: bool) -> void:
	var s := 1.5 if boss else 1.0
	impact_flash(at, body("solar"), 1.7 * s, 8.0, int(12 * s))
	punch(at, "solar", 1.8 * s, int(22 * s), 1.8)
	vfx.emit_one("ring", at, Vector3.ZERO, pal("solar", 1), 2.6 * s, 1.2)
	vfx.shockwave(_flat(at), 4.2 * s, body("solar", 1.2), 0.5, 0.1)
	vfx.shockwave(_flat(at), 2.4 * s, pal("solar", 1), 0.35, 0.06, 0.05)
	vfx.sphere_pulse(_flat(at, 0.2), 2.6 * s, pal("solar", 2, 0.6), 0.5)
	vfx.burst("gold", at)
	vfx.shake(0.2 * s)
	vfx.decal("crater", _flat(at), 1.6 * s, Color(0.25, 0.12, 0.06, 0.75), body("solar"), 2.5)
	vfx.beam(_flat(at), 1.1 * s, 12.0, body("solar"), 0.45)
	vfx.spray("debris", _flat(at, 0.3), 8, Color(0.5, 0.37, 0.27), 7.0, Vector3.UP, 0.8, 0.8, 1.0)
	vfx.glyph(at + Vector3(0, 1.6 * s, 0), 0, 1.5 * s, GOLD, 0.9, 0.0, 0.8)
	if boss:
		vfx.glyph(at + Vector3(0, 0.6, 0), 6, 1.6, Color(0.55, 0.75, 1.0), 1.1, 0.25, -0.6)


## Line Drive: a muzzle-flash crack at the bat / hand and a flat white streak.
func line_drive_release(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	vfx.emit_one("v_flare", from, Vector3.ZERO, rc("blaze"), 0.8, 0.8)
	vfx.emit_one("ring", from + dir * 0.8, dir * 6.0, pal("blaze", 1), 1.1, 0.8)
	vfx.spray("v_spark", from, 14, rc("blaze"), 16.0, dir, 0.15, 1.0, 0.5)


## Line Drive impact: a comic starburst, a ring the size of the hit area and a dirt spray.
func line_drive_impact(point: Vector3, r: float, dir: Vector3) -> void:
	var g := _flat(point)
	var col := pal("blaze", 1)
	impact_flash(g + Vector3(0, 0.7, 0), body("blaze"), 1.3, 6.0, 8)
	punch(g + Vector3(0, 0.7, 0), "blaze", 1.6, 18, 1.8, false)
	vfx.burst("explosion", g + Vector3(0, 0.6, 0), Color(1.0, 0.75, 0.4))
	vfx.shockwave(g, r, body("blaze", 1.2), 0.3, 0.09)
	vfx.shockwave(g, r * 1.25, pal("blaze", 1, 0.85), 0.45, 0.04, 0.06)
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	vfx.spray("dust", g + Vector3(0, 0.3, 0), 12, Color(0.62, 0.46, 0.33, 0.7), 6.0, (dir + Vector3(0, 0.8, 0)).normalized(), 0.7, 1.2, 0.9)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 6, Color(0.5, 0.37, 0.27), 7.0, (dir + Vector3(0, 1.0, 0)).normalized(), 0.6, 0.7, 1.0)
	vfx.decal("scorch", g, r * 0.8, Color(0.12, 0.08, 0.05, 0.7), Color(1.0, 0.6, 0.2), 4.0)
	# Linger: a skid mark where the liner hit and dust that hangs in the air.
	var skid := vfx.decal("crater", g - dir * 0.6, 1.0, Color(0.22, 0.15, 0.1, 0.65), Color(1.0, 0.75, 0.4), 3.5)
	skid.rotation.y = atan2(dir.x, dir.z)
	skid.scale = Vector3(r * 0.35, 1, r * 1.1)
	vfx.emit("mist", g + Vector3(0, 0.4, 0), 5, Color(0.62, 0.5, 0.4, 0.45), 1.2, 0.3, r * 0.5, 2.4, 2.2)
	vfx.every_frame(1.4, func(k: float) -> void:
		if _rate(9.0 * (1.0 - k)):
			var off := Vector2.from_angle(randf() * TAU) * randf() * r * 0.8
			vfx.emit_one("dust", g + Vector3(off.x, 0.3, off.y), Vector3(0, 0.6, 0), Color(0.62, 0.48, 0.36, 0.55), 1.6, 1.2)
		if _rate(5.0 * (1.0 - k)):
			vfx.emit_one("ember", g + Vector3(randf_range(-0.4, 0.4), 0.2, randf_range(-0.4, 0.4)), Vector3(0, 1.2, 0), Color(1.0, 0.6, 0.25), 0.8, 0.8))


## Tag at the Plate: the plate lights up teal and stays armed (a pulsing ring and a glove
## icon) until a runner is tagged or the window ends.
func tag_plate(dur: float) -> void:
	var h := Field.HOME
	vv.ground_glow(h, 2.8, "teal", 1.2, 0.9)
	vfx.emit_one("v_flare", h + Vector3(0, 0.8, 0), Vector3.ZERO, rc("teal"), 1.2, 1.0)
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
	impact_flash(c, TAG_TEAL, 1.4, 6.0, 8)
	punch(c, "teal", 1.6, 16, 1.6)
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
		impact_flash(mound + Vector3(0, 1.0, 0), BULLPEN, 1.6, 5.0, 8)
		punch(mound + Vector3(0, 1.0, 0), "lime", 1.8, 16, 1.6, false)
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
		impact_flash(df.model.chest_position(), HOT, 1.6, 7.0, 10)
		punch(df.model.chest_position(), "fire", 1.6, 16, 1.6, false)
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
	legend_accent(m + Vector3(0, 2.0, 0), "gold")
	vfx.ground_fx("diamond", m, 19.0, Color(GOLD, 0.85), Color.WHITE, 1.6)
	vfx.shockwave(m, 30.0, GOLD, 0.9, 0.04)
	vfx.shockwave(m, 18.0, Color(1.0, 0.95, 0.8, 0.9), 0.6, 0.06, 0.1)
	var bases := [Field.HOME, Field.FIRST, Field.SECOND, Field.THIRD]
	for i in bases.size():
		var b: Vector3 = bases[i]
		vfx.beam(b, 1.3, 14.0, GOLD, 1.1, i * 0.06)
		vfx.after(i * 0.06, func() -> void:
			impact_flash(b + Vector3(0, 0.6, 0), GOLD, 1.2, 0.0, 6)
			punch(b + Vector3(0, 0.6, 0), "gold", 1.4, 10, 1.8))
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
	vfx.bolt(c + Vector3(randf_range(-1.0, 1.0), 14.0, randf_range(-1.0, 1.0)), c, body("gold", 1.3), 0.18, 0.3, 2, 0.14, 2)
	punch(c, "gold", 1.0, 10, 1.0)
	vfx.shockwave(_flat(c), 1.6, GOLD, 0.35, 0.06)


## Splitter: the ball bursts in mid-air and fans out.
func splitter_burst(at: Vector3, ground: Vector3) -> void:
	impact_flash(at, body("scarlet"), 1.4, 6.0, 8)
	vfx.emit_one("v_flare", at, Vector3.ZERO, rc("scarlet"), 1.8, 1.0)
	vfx.emit_one("v_glow", at, Vector3.ZERO, rc("scarlet"), 4.0, 1.1)
	vfx.emit_one("ring", at, Vector3.ZERO, pal("scarlet", 1), 2.4, 1.0)
	vfx.spray("v_spark", at, 24, rc("scarlet"), 15.0, Vector3.DOWN, 1.2, 1.1, 0.8)
	vfx.shockwave(_flat(ground), 3.8, body("scarlet", 1.2), 0.4, 0.05)
	# Fan-shaped mark under the split, and glints that hang where the ball broke apart.
	vfx.ground_fx("rays", _flat(ground), 4.4, pal("scarlet", 2, 0.6), pal("scarlet", 1), 1.4)
	vv.ground_glow(_flat(ground), 4.0, "scarlet", 1.5, 0.8)
	vfx.zone_ring(_flat(ground), 5.0, pal("scarlet", 1, 0.85), 1.2, 0.1, 1.5, 10.0)
	for i in 6:
		vfx.emit_one("v_mote", at + Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.4), randf_range(-0.6, 0.6)), Vector3.ZERO, rc("scarlet"), 1.6, 1.0)
	vfx.flash_light(at, body("scarlet"), 4.0, 12.0, 0.35)


## Grand Slam Barrage: a burning target zone and an embers sky.
func barrage_start(point: Vector3, r: float, dur: float) -> void:
	legend_accent(point, "fire")
	vv.ground_glow(point, r * 1.1, "fire", 0.9, 0.9)
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
	impact_flash(at + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.25), 1.3, 8.0, 10)
	punch(at + Vector3(0, 0.6, 0), "fire", 1.2, 12, 1.8, false)
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
	vfx.bolt(a, b, body("solar", 1.2), 0.3, 0.32, 0, 0.05, 2)
	vfx.ribbon(vfx.arc_points(a, b, 0.6, 12), pal("solar", 1), 0.18, 0.55)
	vfx.ribbon(vfx.arc_points(a, b, 0.6, 12), body("solar", 1.1), 0.42, 0.4)
	vfx.beam(ground, 0.6, 5.0, body("solar"), 0.6)
	vfx.shockwave(ground, 1.8, body("solar", 1.2), 0.3, 0.07)
	vfx.emit_one("v_flare", b, Vector3.ZERO, rc("solar"), 0.8, 0.9)
	vfx.spray("v_spark", b, 10, rc("solar"), 8.0, Vector3.UP, 1.2, 0.9, 0.8)
	vv.ground_glow(ground, 1.5, "solar", 1.2, 0.8)


func relay_strike(from: Vector3, to: Vector3) -> void:
	vfx.bolt(from, to, body("solar", 1.3), 0.26, 0.32, 1, 0.09, 2)
	punch(to, "solar", 1.3, 16, 1.4)


## Power Catch: a lobbed ball; a warning circle; then a glove-slam that cracks the ground.
func power_catch_throw(point: Vector3, r: float, flight: float) -> void:
	var m: Node3D = vfx.telegraph(point, r, pal("crimson", 2, 0.9), flight)
	vfx.after(flight + 0.02, func() -> void:
		if is_instance_valid(m):
			m.queue_free())
	# Anticipation that reads from the battle camera: a filled violet target zone and rings
	# that tighten onto it in time with the falling ball.
	var g := _flat(point)
	vfx.zone_ring(g, r, pal("crimson", 2, 0.95), flight + 0.05, 0.22, 1.5, 12.0)
	var rings := maxi(1, int(flight / 0.3))
	for i in rings:
		vfx.shockwave(g, r * 1.8, pal("crimson", 1, 0.85), 0.3, 0.05, i * 0.3, true)
	vfx.every_frame(flight, func(k: float) -> void:
		if k > 0.5 and _rate(30.0):
			var off := Vector2.from_angle(randf() * TAU) * r * randf_range(0.8, 1.2)
			vfx.emit_one("streak", point + Vector3(off.x, 6.0, off.y), Vector3(-off.x * 0.4, -16.0, -off.y * 0.4), body("crimson", 1.2), 1.0, 0.7))


func power_catch_impact(point: Vector3, r: float) -> void:
	var g := _flat(point)
	impact_flash(g + Vector3(0, 0.8, 0), body("crimson"), 1.8, 8.0, 10)
	punch(g + Vector3(0, 0.8, 0), "crimson", 2.0, 22, 1.8, false)
	vfx.decal("crater", g, r * 1.25, Color(0.12, 0.04, 0.08, 0.85), body("crimson"), 4.5)
	vfx.shockwave(g, r * 1.4, body("crimson", 1.2), 0.45, 0.08)
	vfx.shockwave(g, r * 2.2, pal("crimson", 1, 0.75), 0.6, 0.04, 0.08)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 14, Color(0.45, 0.33, 0.25), 10.0, Vector3.UP, 0.9, 1.1, 1.0)
	vfx.ring_emit("dust", g + Vector3(0, 0.3, 0), r * 0.5, 18, Color(0.55, 0.42, 0.32, 0.75), 6.0, 0.8, 1.2, 1.1)
	vfx.ring_emit("v_spark", g + Vector3(0, 0.4, 0), 0.5, 18, rc("crimson"), 12.0, 1.0, 1.0, 0.7)
	vfx.beam(g, r * 0.5, 6.0, body("crimson"), 0.5)
	vfx.sphere_pulse(g + Vector3(0, 0.2, 0), r * 1.1, pal("crimson", 2, 0.6), 0.45)
	vfx.glyph(g + Vector3(0, 2.8, 0), 15, 1.6, pal("crimson", 1), 1.0, 0.05, 0.7)
	vfx.shake(0.12)


## Thunderbolt: a forked bolt from the caster plus a strike from the sky.
func thunderbolt(from: Vector3, to: Vector3) -> void:
	var col := Color(1.0, 0.92, 0.4)
	vfx.bolt(from, to, col, 0.34, 0.42, 3, 0.15, 4)
	var sky := to + Vector3(randf_range(-2, 2), 16.0, randf_range(-2, 2))
	vfx.bolt(sky, to, Color(1.0, 0.95, 0.6), 0.44, 0.45, 4, 0.12, 4, 0.04)
	impact_flash(to, col, 1.6, 9.0, 12)
	punch(to, "volt", 1.7, 20, 1.6)
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
	vfx.spray("v_spark", b, 10, rc("volt"), 7.0, Vector3.UP, 1.2, 0.8)
	vfx.emit_one("v_flare", b, Vector3.ZERO, rc("volt"), 0.7, 0.8)
	vv.ground_glow(_flat(b), 1.4, "volt", 0.9, 0.6)


# ---------------------------------------------------------------- control

## Curveball: a swirling vortex where the ball breaks.
func curveball_impact(point: Vector3, r: float) -> void:
	var g := _flat(point)
	vfx.ground_fx("vortex", g, r, pal("violet", 2, 0.95), pal("violet", 1), 1.3, Vector2(1.0, 0.0))
	vfx.shockwave(g, r * 1.15, body("violet", 1.2), 0.4, 0.05)
	punch(g + Vector3(0, 0.6, 0), "violet", 1.4, 12, 0.0, false)
	vv.ground_glow(g, r * 1.05, "violet", 1.6, 0.8)
	for i in vfx._count(18):
		var a := randf() * TAU
		var d := randf_range(0.4, r)
		var p := g + Vector3(cos(a) * d, randf_range(0.2, 1.2), sin(a) * d)
		var tangent := Vector3(-sin(a), 0.3, cos(a))
		vfx.emit_one("v_mote", p, tangent * 5.0, rc("violet"), 1.1, 1.0)


## Shadow Change: a pool of darkness swallows the area, then hurls the runners back.
func shadow_change(point: Vector3, r: float) -> void:
	var g := _flat(point)
	vfx.ground_fx("vortex", g, r, Color(0.55, 0.2, 0.95, 1.0), Color(0.8, 0.5, 1.0), 1.5, Vector2(-1.0, 1.0))
	vfx.shockwave(g, r * 1.3, Color(0.4, 0.15, 0.7, 0.9), 0.35, 0.06, 0.0, true)
	vfx.shockwave(g, r * 1.5, Color(0.7, 0.4, 1.0), 0.6, 0.07, 0.3)
	vfx.ring_emit("smoke", g + Vector3(0, 0.4, 0), r * 0.3, 22, Color(0.12, 0.04, 0.2, 0.85), 7.0, 1.0, 1.3, 1.0)
	vfx.disc_emit("smoke", g + Vector3(0, 0.2, 0), r * 0.7, 10, Color(0.1, 0.03, 0.16, 0.7), Vector3(0, 2.2, 0), 1.4, 1.0)
	vfx.ring_emit("streak", g + Vector3(0, 0.6, 0), r * 0.4, 18, Color(0.75, 0.45, 1.0), 14.0, 0.5, 1.0, 0.6)
	punch(g + Vector3(0, 1.0, 0), "violet", 2.0, 18, 0.0, false)
	vv.ground_glow(g, r * 1.1, "violet", 1.8, 0.9, 0.05)
	vfx.flash_light(g + Vector3(0, 1.5, 0), Color(0.6, 0.3, 1.0), 5.0, r * 2.5, 0.5)


func shadow_victim(e: Node3D) -> void:
	vfx.burst("shadow", e.center())
	vfx.emit_one("v_glow", e.center(), Vector3.ZERO, rc("violet"), 1.6, 0.9)
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
	vfx.emit_one("v_flare", c + Vector3(0, 3.0, 0), Vector3.ZERO, rc("ice"), 3.0, 1.2)
	legend_accent(c + Vector3(0, 2.0, 0), "ice")
	_desaturate(freeze_time)


## Drains the world's colour while time is stopped (restored afterwards).
func _desaturate(time: float, to := 0.3) -> void:
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
		env.adjustment_saturation = lerpf(base, to, amt)
		if k >= 1.0:
			env.adjustment_saturation = base)


func time_out_victim(e: Node3D) -> void:
	vfx.burst("frost", e.center())
	vfx.emit_one("v_glow", e.center(), Vector3.ZERO, rc("ice"), 1.4, 1.0)
	vfx.ring_emit("snow", _flat(e.global_position, 0.3), 0.6, 6, Color(0.8, 0.95, 1.0), 2.0, 1.0)


## Changeup: the tempo drops. Three slow, heavy beats roll out from the plate in lavender
## (a rhythm, not a clock: the stopwatch belongs to Time Out), a slow radar sweep turns at
## the plate, and every runner drags a ghostly after-image.
func changeup() -> void:
	var c := Field.HOME
	var col := Color(0.5, 0.45, 1.0)
	vv.ground_glow(c, 4.5, "indigo", 1.6, 0.9)
	vfx.emit_one("v_flare", c + Vector3(0, 1.0, 0), Vector3.ZERO, rc("indigo"), 1.6, 1.0)
	for i in 3:
		vfx.shockwave(c, 30.0, Color(body("indigo", 1.1), 0.72 - i * 0.16), 1.4, 0.04 - i * 0.01, i * 0.32)
		vfx.after(i * 0.32, func() -> void:
			vfx.emit_one("ring", c + Vector3(0, 0.6, 0), Vector3.ZERO, pal("indigo", 1), 3.5, 1.2)
			vfx.ring_emit("v_mote", c + Vector3(0, 0.3, 0), 2.0, 14, rc("indigo"), 1.0, 1.0, 1.0, 1.0))
	vfx.ground_fx("radar", c, 4.5, Color(col, 0.8), Color(0.9, 0.85, 1.0), 1.6, Vector2(0.25, 0.0))
	vfx.beam(c, 1.2, 6.0, col, 0.7)
	vfx.flash_light(c + Vector3(0, 2.0, 0), col, 3.0, 12.0, 0.6)


func changeup_victim(e: Node3D) -> void:
	var col := Color(0.5, 0.45, 1.0)
	vfx.emit("v_mote", e.center(), 6, rc("indigo"), 1.5, 0.2)
	vfx.emit_one("ring", e.center(), Vector3.ZERO, Color(col, 0.8), 1.2, 1.4)
	# Slow-motion after-image: soft lavender streaks left behind along the path.
	if "route" in e and e.route:
		var back: Vector3 = -e.route.direction_at(e.d)
		for i in 3:
			vfx.emit_one("glow", e.center() + back * (0.5 + i * 0.5), back * 0.4, Color(col, 0.55 - i * 0.15), 1.4 - i * 0.25, 1.0)


## Pickoff: a laser-straight snap throw.
func pickoff_strike(from: Vector3, to: Vector3, picked: bool) -> void:
	var pts := PackedVector3Array([from, from.lerp(to, 0.5), to])
	var ice := body("ice", 1.2)
	vfx.ribbon(pts, ice, 0.45, 0.4, 0.0, false)
	vfx.ribbon(pts, pal("ice", 0), 0.14, 0.3, 0.0, false)
	vfx.line_emit("v_spark", from, to, 12, rc("ice"), (to - from).normalized() * 12.0, 0.15, 1.0, 0.4)
	punch(to, "ice", 1.7 if picked else 1.3, 16, 1.4)
	vfx.shockwave(_flat(to), 2.2, pal("ice", 1, 0.9), 0.3, 0.07)
	if picked:
		vfx.shockwave(_flat(to), 3.0, ice, 0.45, 0.07)
		vfx.emit("v_mote", to, 16, rc("ice"), 5.0, 1.0)
		vfx.glyph(to + Vector3(0, 1.4, 0), 2, 1.6, pal("ice", 1), 0.8)


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
		impact_flash(g + Vector3(0, 0.4, 0), LOCK_BLUE, 1.2, 6.0, 8)
		punch(g + Vector3(0, 0.4, 0), "aqua", 1.5, 14, 0.0, false)
		vv.ground_glow(g, r * 1.05, "aqua", 1.8, 0.9)
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
	punch(h + Vector3(0, 1.0, 0), "aqua", 1.6, 14, 1.6)
	vfx.beam(h, 2.3, 9.0, col, 0.9)
	vfx.shockwave(h, 4.5, col, 0.55, 0.06)
	vfx.glyph(h + Vector3(0, 3.6, 0), 14, 1.8, Color(0.5, 0.9, 1.0), 1.3, 0.15, 0.6)
	vfx.ring_emit("magic", h + Vector3(0, 0.2, 0), 2.4, 20, col, 0.5, 4.0, 1.0, 1.0)
	vfx.flash_light(h + Vector3(0, 2.0, 0), col, 5.0, 10.0, 0.6)


## Frost Field cast (the zone draws its own ice): an aqua punch at the centre, cold light
## that pools over the disc and shards of light thrown outward.
func frost_field_cast(point: Vector3, r: float) -> void:
	var g := _flat(point)
	punch(g + Vector3(0, 0.8, 0), "aqua", 1.6, 16, 0.0, false)
	vv.ground_glow(g, r * 1.05, "aqua", 1.8, 0.9)
	vfx.ring_emit("v_spark", g + Vector3(0, 0.3, 0), 0.4, 18, rc("aqua"), r * 2.5, 2.0, 1.0, 0.7)


## Wall of Dirt cast (the wall rises by itself): an emerald slam where it comes up, a
## ground ring and dirt thrown sideways, so the moment of the cast reads.
func wall_cast(point: Vector3) -> void:
	var g := _flat(battle.snap_to_route(point).point) if battle else _flat(point)
	punch(g + Vector3(0, 0.6, 0), "emerald", 1.5, 12, 1.6)
	vfx.shockwave(g, 4.0, body("emerald", 1.2), 0.35, 0.07)
	vfx.ring_emit("dust", g + Vector3(0, 0.3, 0), 0.8, 14, Color(0.55, 0.42, 0.3, 0.75), 6.0, 1.0, 1.2, 1.0)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 10, Color(0.45, 0.33, 0.25), 9.0, Vector3.UP, 0.9, 1.0, 1.0)
	vfx.shake(0.08)


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
		impact_flash(g + Vector3(0, 0.4, 0), col, 1.0, 3.0, 4)
		punch(g + Vector3(0, 0.4, 0), "teal", 1.3, 12, 1.8)
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
	impact_flash(g + Vector3(0, 0.6, 0), PINK, 1.2, 6.0, 8)
	punch(g + Vector3(0, 0.6, 0), "teal", 1.5, 14, 1.6)
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
	vfx.shockwave(c, 12.0, body("lime", 1.2), 0.5, 0.035)
	punch(c + Vector3(0, 1.0, 0), "lime", 1.4, 12, 1.4, false)
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
		vfx.ribbon(vfx.arc_points(c + Vector3(0, 1.5, 0), df.model.chest_position(), 2.0, 14), body("lime", 1.2), 0.14, 0.6)
		vfx.emit_one("v_flare", df.model.chest_position(), Vector3.ZERO, rc("lime"), 0.8, 0.9)
		vv.ground_glow(_flat(df.global_position), 1.5, "lime", 1.0, 0.8)


func field_vision(dur: float, bonus: float) -> void:
	var col := Color(0.45, 0.9, 1.0)   # cool scouting cyan (Rally Cry is the gold one)
	for df in battle.defenders:
		var rng: float = df.s_range * (1.0 + maxf(df.dyn_range, bonus))
		# A thin ring sweeping out to the new throwing range.
		vfx.shockwave(_flat(df.global_position), rng, Color(col, 0.85), 0.9, 0.025)
		vfx.ground_fx("radar", _flat(df.global_position), 2.2, Color(col, 0.6), Color.WHITE, 1.2)
		vfx.glyph(df.model.head_position() + Vector3(0, 1.0, 0), 10, 1.3, col, 1.2, randf() * 0.15, 0.6)
		defender_aura(df, Color(col, 0.6), dur, 1.15)
		vfx.emit_one("v_flare", df.model.head_position(), Vector3.ZERO, rc("sky"), 0.8, 0.9)
		vfx.emit("v_mote", df.model.head_position(), 6, rc("sky"), 3.0, 0.6)
		vv.ground_glow(_flat(df.global_position), 1.8, "sky", 1.2, 0.9)


func diamond_aura(df: Node3D, radius: float, dur: float) -> void:
	# A gold gem (utility) with a white-hot sparkle; the plate keeps the diamond pattern.
	var col := Color(1.0, 0.82, 0.32)
	defender_aura(df, Color(col, 0.8), dur, radius, "diamond")
	var top: Vector3 = df.model.head_position() + Vector3(0, 1.4, 0)
	vfx.glyph(top, 7, 2.2, Color(1.0, 0.9, 0.55), 1.6, 0.0, 0.8)
	vfx.beam(_flat(df.global_position), 1.2, 10.0, body("gold"), 0.9)
	vfx.shockwave(_flat(df.global_position), radius, body("gold", 1.2), 0.55, 0.05)
	impact_flash(top, col, 1.0, 5.0, 6)
	punch(top, "gold", 1.4, 14, 0.0, false)
	vv.ground_glow(_flat(df.global_position), radius, "gold", 1.4, 0.9, 0.0, 0.75)
	vfx.every_frame(dur, func(_k: float) -> void:
		if is_instance_valid(df) and _rate(10.0):
			var a := randf() * TAU
			var d := sqrt(randf()) * radius
			vfx.emit_one("v_mote", _flat(df.global_position) + Vector3(cos(a) * d, randf_range(0.2, 1.6), sin(a) * d), Vector3(0, 0.8, 0), rc("gold"), 1.0, 1.0))


## Rally Cry: a short shout from every defender (a small bubble, the shout icon and a quick
## light shaft) and one thin wave from the mound; then only a quiet ring under each defender.
func rally_cry(dur: float) -> void:
	var col := Color(1.0, 0.62, 0.18)   # warm amber: Diamond Aura owns the gold
	vfx.shockwave(Field.MOUND, 20.0, body("amber", 1.2), 0.6, 0.03)
	for df in battle.defenders:
		var p: Vector3 = _flat(df.global_position)
		vfx.sphere_pulse(p + Vector3(0, 0.3, 0), 1.9, Color(col, 0.5), 0.4, 0.05)
		vfx.beam(p, 0.7, 3.5, col, 0.5, 0.1)
		vfx.glyph(df.model.head_position() + Vector3(0, 0.9, 0), 9, 1.2, Color(1.0, 0.72, 0.3), 0.9, 0.1, 0.8)
		vfx.emit_one("v_flare", df.model.head_position(), Vector3.ZERO, rc("amber"), 0.9, 0.9)
		vv.ground_glow(p, 1.8, "amber", 1.1, 0.9, 0.05)
		defender_aura(df, Color(col, 0.8), dur, 1.3)
		vfx.after(0.15, func() -> void:
			if is_instance_valid(df):
				vfx.ring_emit("v_mote", p + Vector3(0, 0.3, 0), 0.8, 10, rc("amber"), 0.5, 3.5, 1.0, 1.0))


## Magnet Glove: a field that winds inward; tethers drag the runners to the centre.
func magnet(point: Vector3, r: float, pull: float, victims: Array) -> void:
	var g := _flat(point)
	vfx.ground_fx("magnet", g, r, Color(MAGNET_RED, 0.95), Color(1.0, 0.8, 0.3), pull + 0.6)
	punch(g + Vector3(0, 1.0, 0), "amber", 1.5, 12, 0.0, false)
	vv.ground_glow(g, r, "amber", pull + 0.6, 0.7, 0.0, 0.7)
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
	vfx.shockwave(Field.MOUND, 9.0, body("gold", 1.2), 0.6, 0.06)
	punch(Field.MOUND + Vector3(0, 1.0, 0), "gold", 1.6, 16, 1.5, false)
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
	battle.effects.clear_active()
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
		"hot_corner", "golden_glove":
			focus = target.lerp(Field.MOUND, 0.5)
			view = Vector3(25.0, -40.0, 28.0)
		"rain_delay", "momentum", "around_the_horn", "the_shift":
			focus = Field.MOUND
			view = Vector3(0.0, -50.0, 52.0)
		"bean_ball", "rundown", "intentional_walk", "infield_fly", "relief_pitcher", "instant_replay":
			focus = target.lerp(Field.MOUND, 0.3)
			view = Vector3(25.0, -40.0, 30.0)
		"grand_salami":
			focus = target.lerp(route.points[0], 0.3)
			view = Vector3(30.0, -42.0, 40.0)
		"scouting_report", "hidden_ball_trick", "signal_caller", "scoop_and_tag":
			focus = target.lerp(Field.MOUND, 0.3)
			view = Vector3(25.0, -40.0, 32.0)
		"sprinkler_system", "worm_burner":
			focus = target.lerp(route.points[0], 0.25)
			view = Vector3(30.0, -42.0, 36.0)
		"sweet_spot", "money_ball", "rally_monkey", "ground_rule_double":
			focus = Field.MOUND + Vector3(0, 0, 3)
			view = Vector3(0.0, -44.0, 44.0)
		"second_wind":
			focus = target.lerp(Field.MOUND, 0.5)
			view = Vector3(25.0, -40.0, 28.0)
		"fireworks_night":
			focus = target.lerp(Field.MOUND, 0.35) + Vector3(0, 3.0, 0)
			view = Vector3(20.0, -30.0, 44.0)
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
	if card_id == "instant_replay" and battle.effects.last_play.is_empty():
		battle.effects.last_play = {"id": "thunderbolt", "level": level, "target": {"point": target, "enemy": lead[0] if not lead.is_empty() else null, "valid": true}}
	if card_id == "golden_glove":
		# The gilded defender stands by the path just ahead of the pack; runners walk into its reach.
		var gd := d0 + 4.0
		var side := route.direction_at(gd).cross(Vector3.UP).normalized()
		if side.dot(Field.MOUND - route.position_at(gd)) < 0.0:
			side = -side
		df_target.place(route.position_at(gd) + side * 2.2)
		battle.spawn_enemy("runner", route, gd - 3.5, {"lateral": 0.0, "hp_mult": 60.0, "speed_mult": 0.5})
	if card_id == "rally_monkey":
		battle.run.runs_inning = maxi(battle.run.runs_inning, 1)   # show the clutch version
	if card_id == "second_wind":
		for sid in battle.effects.signature_cards(df_target):
			battle.cards.cooldowns[sid] = 9.0
	if card_id == "scoop_and_tag":
		# A couple of hurt runners in the sweep, so the tag-outs show.
		for en in battle.enemies_in_radius(target, 3.0).slice(0, 3):
			en.hp = en.max_hp * 0.2
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


# ---------------------------------------------------------------- Update 7 cards

# Saturated in Update 8 to sit in their category's family (see PALETTE).
const BEAN := Color(1.0, 0.24, 0.2)
const HORN := Color(1.0, 0.55, 0.14)
const RAIN := Color(0.42, 0.64, 1.0)
const WALK := Color(0.5, 0.56, 1.0)
const FLY := Color(0.62, 1.0, 0.9)
const GLOVE_GOLD := Color(1.0, 0.76, 0.18)
const SHIFT_TEAL := Color(0.12, 0.95, 0.8)
const ENERGY := Color(0.25, 0.82, 1.0)
const REPLAY := Color(0.4, 0.92, 1.0)
const RUNDOWN_V := Color(0.52, 0.46, 1.0)
const RELIEF := Color(0.5, 1.0, 0.36)


## A ring that follows `follow` (a Node3D, or a fixed point when null) while `alive.call()`
## is true, then fades. Used by the lasting Update 7 mechanics.
func _live_ring(pos: Vector3, follow: Node3D, radius: float, color: Color, dur: float, alive: Callable, dashes := 0.0, spin := 0.0) -> void:
	var ring: MeshInstance3D = vfx._take("ring")
	ring.global_position = _flat(pos, 0.08)
	ring.scale = Vector3(radius, 1, radius)
	ring.set_instance_shader_parameter("color", color)
	ring.set_instance_shader_parameter("mode", 1.0)
	ring.set_instance_shader_parameter("params", Vector4(0.05, 0.14, spin, dashes))
	ring.set_instance_shader_parameter("progress", 0.0)
	var fade := [0.0]
	var fw: WeakRef = weakref(follow) if follow != null else null
	vfx.animate(ring, dur, func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var f: Object = fw.get_ref() if fw != null else null
		if f != null:
			n.global_position = _flat((f as Node3D).global_position, 0.08)
		var on: bool = alive.call() and tt < dur - 0.35
		fade[0] = move_toward(float(fade[0]), 1.0 if on else 0.0, _dt() * (6.0 if on else 3.0))
		var grow := 1.0 - pow(1.0 - clampf(tt / 0.25, 0.0, 1.0), 3.0)
		n.scale = Vector3.ONE * radius * (0.3 + 0.7 * grow)
		(n as MeshInstance3D).set_instance_shader_parameter("progress", float(fade[0]) * (0.8 + 0.2 * sin(tt * 6.0))))


## Bean Ball release: a red crack at the hand and a tight streak toward the runner.
func bean_release(from: Vector3, to: Vector3) -> void:
	var dir := (to - from).normalized()
	vfx.emit_one("v_flare", from, Vector3.ZERO, rc("scarlet"), 0.8, 0.8)
	vfx.emit_one("ring", from + dir * 0.6, dir * 5.0, pal("scarlet", 1), 1.0, 0.8)
	vfx.spray("v_spark", from, 14, rc("scarlet"), 15.0, dir, 0.16, 1.0, 0.5)


## Bean Ball impact: a comic POW, dizzy stars and a skid mark where the runner flies back.
func _bean_impact(at: Vector3, target: Node3D, fast: bool) -> void:
	var s := 1.35 if fast else 1.0
	impact_flash(at, BEAN, 1.3 * s, 6.0, int(8 * s))
	punch(at, "scarlet", 1.5 * s, int(16 * s), 1.6)
	vfx.emit_one("impact", at, Vector3.ZERO, Color(1.0, 0.85, 0.6), 1.7 * s, 1.0)
	vfx.emit_one("ring", at, Vector3.ZERO, Color(1.0, 0.75, 0.6), 2.0 * s, 1.0)
	vfx.shockwave(_flat(at), 2.4 * s, BEAN, 0.35, 0.08)
	for i in 5:
		var a := TAU * i / 5.0
		vfx.emit_one("magic", at + Vector3(0, 0.9, 0) + Vector3(cos(a), 0, sin(a)) * 0.6, Vector3(-sin(a), 0.3, cos(a)) * 2.5,
			Color(1.0, 0.9, 0.4), 1.6, 1.2)
	vfx.glyph(at + Vector3(0, 1.4, 0), 0, 1.5 * s, Color(1.0, 0.88, 0.4), 1.0, 0.0, 0.7)
	vfx.text_popup(at + Vector3(0, 2.2, 0), "BEANED x2!" if fast else "BEANED!", Color(1.0, 0.58, 0.48), 1.05 * s, 1.0)
	vfx.shake(0.1 * s)
	if target and is_instance_valid(target) and "route" in target and target.route:
		var back: Vector3 = -target.route.direction_at(target.d)
		var g := _flat(target.global_position) + back * 1.2 * s
		var skid := vfx.decal("crater", g, 1.0, Color(0.25, 0.16, 0.1, 0.6), BEAN, 2.6)
		skid.rotation.y = atan2(back.x, back.z)
		skid.scale = Vector3(0.55 * s, 1, 1.5 * s)
		vfx.spray("dust", _flat(target.global_position, 0.3), 10, Color(0.62, 0.46, 0.33, 0.7), 5.0, (back + Vector3(0, 0.6, 0)).normalized(), 0.6, 1.1, 1.0)


## Around the Horn: one leg of the throw, base to base: a bright arc, the base lights up.
func horn_link(a: Vector3, b: Vector3) -> void:
	var a3 := a + Vector3(0, 1.2, 0)
	var b3 := b + Vector3(0, 1.2, 0)
	var pts := vfx.arc_points(a3, b3, 1.4, 14)
	vfx.ribbon(pts, HORN, 0.36, 0.6)
	vfx.ribbon(pts, Color(1.0, 0.95, 0.85), 0.11, 0.45)
	vfx.line_emit("streak", a3, b3, 8, Color(1.0, 0.85, 0.6), (b3 - a3).normalized() * 10.0, 0.2, 1.0, 0.4)
	impact_flash(b3, HORN, 1.0, 3.0, 4)
	vfx.emit_one("v_flare", b3, Vector3.ZERO, rc("blaze"), 1.0, 0.9)
	vfx.spray("v_spark", b3, 10, rc("blaze"), 8.0, Vector3.UP, 1.2, 0.9, 0.8)
	vv.ground_glow(_flat(b), 2.0, "blaze", 1.6, 0.9)
	vfx.beam(_flat(b), 0.9, 6.0, HORN, 1.0)
	vfx.shockwave(_flat(b), 2.6, HORN, 0.4, 0.08)
	vfx.dust(b, 1.0)
	# The base path itself glows for a moment: the "horn" traced on the field.
	vfx.ribbon(PackedVector3Array([_flat(a, 0.12), _flat(a.lerp(b, 0.5), 0.12), _flat(b, 0.12)]), Color(HORN, 0.9), 0.5, 1.6, 0.0, false)
	vfx.ground_fx("hexdisc", b, 1.5, Color(HORN, 0.85), Color.WHITE, 1.4)


## Around the Horn: the throw from a base into a lead runner.
func horn_strike(from: Vector3, to: Vector3) -> void:
	var pts := PackedVector3Array([from, from.lerp(to, 0.5) + Vector3(0, 0.8, 0), to])
	vfx.ribbon(pts, HORN, 0.28, 0.4, 0.0, false)
	vfx.ribbon(pts, Color(1.0, 0.95, 0.85), 0.09, 0.3, 0.0, false)
	impact_flash(to, HORN, 1.2, 4.0, 6)
	punch(to, "blaze", 1.5, 14, 1.5)
	vfx.emit_one("impact", to, Vector3.ZERO, pal("blaze", 1), 1.3, 1.0)
	vfx.shockwave(_flat(to), 2.0, HORN, 0.3, 0.07)
	vfx.glyph(to + Vector3(0, 1.3, 0), 0, 1.1, Color(1.0, 0.85, 0.5), 0.8, 0.0, 0.6)


## Visual radius of the Grand Salami ball (Update 8: bigger so it reads from the battle camera;
## the hit radius in card_effects is unchanged).
const SALAMI_R := 1.6


## Grand Salami: a colossal flaming baseball (owned by the caller, freed when it stops).
func _giant_ball(at: Vector3, radius := 1.25) -> Node3D:
	var root := Node3D.new()
	vfx.add_child(root)
	root.global_position = _flat(at)
	var mi := MeshInstance3D.new()
	var pm = battle.projectiles
	mi.mesh = pm._ball_mesh
	var sphere: bool = pm._ball_mesh is SphereMesh
	mi.scale = Vector3.ONE * radius / 0.13 * (1.0 if sphere else 3.2)
	if sphere:
		mi.material_override = pm._ball_mat
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow.albedo_color = Color(1.0, 0.38, 0.08, 0.22)
	mi.material_overlay = glow
	mi.position = Vector3(0, radius, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	return root


## Grand Salami wind-up: a red target on the path, a growing shadow and the ball falling in
## flames from the sky.
func salami_drop(land: Vector3, flight: float) -> void:
	var g := _flat(land)
	var m: Node3D = vfx.telegraph(g, 3.0, Color(1.0, 0.3, 0.1, 0.9), flight)
	vfx.after(flight + 0.02, func() -> void:
		if is_instance_valid(m):
			m.queue_free())
	vfx.zone_ring(g, 3.6, Color(1.0, 0.4, 0.1, 0.95), flight + 0.1, 0.2, 2.0, 14.0)
	vfx.beam(g, 1.4, 22.0, Color(1.0, 0.45, 0.12, 0.8), flight + 0.1)
	vfx.decal("scorch", g, 2.4, Color(0.05, 0.03, 0.02, 0.7), FIRE, flight + 0.05, func(n: Node3D, k: float) -> void:
		n.scale = Vector3.ONE * lerpf(0.6, 2.6, k * k)
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, k, 0.0, 1.0)))
	var sky := g + Vector3(3.0, 26.0, 6.0)
	var ball := _giant_ball(sky, SALAMI_R)
	var an := vfx.animate(ball, flight, func(n: Node3D, k: float) -> void:
		var pos := sky.lerp(g, k * k)
		n.global_position = pos
		if _rate(80.0):
			vfx.emit_one("fire", pos + Vector3(randf_range(-0.6, 0.6), 1.2 + randf_range(-0.6, 0.6), randf_range(-0.6, 0.6)),
				(sky - g).normalized() * 6.0, FIRE, 2.4, 0.5)
		if _rate(30.0):
			vfx.emit_one("smoke", pos + Vector3(0, 1.4, 0), Vector3(0, 1.0, 0), Color(0.15, 0.12, 0.1, 0.7), 2.2, 1.0))
	an.free_node = true


## Grand Salami landing: a fiery explosion and a big crater.
func salami_impact(land: Vector3) -> void:
	var g := _flat(land)
	impact_flash(g + Vector3(0, 1.0, 0), Color(1.0, 0.55, 0.2), 2.6, 10.0, 14)
	punch(g + Vector3(0, 1.0, 0), "fire", 2.8, 26, 2.0, false)
	legend_accent(g + Vector3(0, 1.0, 0), "fire", 1.1)
	vfx.burst("explosion", g + Vector3(0, 0.8, 0))
	vfx.shockwave(g, 6.0, Color(1.0, 0.55, 0.2), 0.55, 0.1)
	vfx.shockwave(g, 9.0, Color(1.0, 0.8, 0.5, 0.7), 0.8, 0.04, 0.08)
	vfx.sphere_pulse(g + Vector3(0, 0.2, 0), 3.6, Color(1.0, 0.5, 0.15, 0.6), 0.5)
	vfx.decal("crater", g, 3.0, Color(0.08, 0.05, 0.04, 0.9), Color(1.0, 0.4, 0.08), 7.0)
	for i in vfx._count(10):
		var d := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)).normalized() * randf_range(1.5, 4.5)
		vfx.emit_one("fire", g + Vector3(0, 0.5, 0), d + Vector3(0, randf_range(4.0, 7.0), 0), FIRE, randf_range(2.2, 3.0), randf_range(0.8, 1.1))
	vfx.spray("debris", g + Vector3(0, 0.4, 0), 16, Color(0.36, 0.26, 0.2), 12.0, Vector3.UP, 0.8, 1.5, 1.2)
	vfx.emit("smoke", g + Vector3(0, 2.0, 0), 10, Color(0.14, 0.12, 0.11, 0.75), 2.0, 2.5, 1.5, 2.2, 1.6)
	vfx.text_popup(g + Vector3(0, 4.5, 0), "GRAND SALAMI!", Color(1.0, 0.6, 0.25), 1.4, 1.2)
	vfx.shake(0.35)


func salami_ball(land: Vector3) -> Node3D:
	return _giant_ball(land, SALAMI_R)


## The ball rolls: it spins, spits fire and kicks up dirt.
func salami_roll(node: Node3D, pos: Vector3, dir: Vector3, delta: float) -> void:
	node.global_position = _flat(pos)
	var mi := node.get_child(0) as Node3D
	var axis := dir.cross(Vector3.UP)
	if axis.length() > 0.01:
		mi.global_rotate(axis.normalized(), -13.0 * delta / SALAMI_R)
	var c := node.global_position + Vector3(0, SALAMI_R, 0)
	if _rate(60.0):
		vfx.emit_one("fire", c - dir * 1.0 + Vector3(randf_range(-0.6, 0.6), randf_range(-0.4, 0.8), randf_range(-0.6, 0.6)),
			-dir * 3.0 + Vector3(0, 2.5, 0), FIRE, 2.0, 0.55)
	if _rate(20.0):
		vfx.emit_one("ember", c, Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3)), Color(1.0, 0.55, 0.15), 1.2, 0.9)
	if _rate(14.0):
		vfx.dust(node.global_position + dir * 0.8, 0.8)


## A stretch of the fire trail the ball leaves behind.
func salami_fire(pos: Vector3, life: float) -> void:
	var g := _flat(pos)
	vfx.flame_sheet(g, 2.6, 2.6, maxf(life, 0.5))
	# Every other stretch: the trail glows hot for a couple of seconds, then the scorch stays.
	_salami_n += 1
	if _salami_n % 2 == 0:
		vv.ground_glow(g, 2.4, "fire", clampf(life, 0.5, 1.8) + 0.4, 0.3, 0.0, 0.6)
	vfx.decal("scorch", g, 1.8, Color(0.08, 0.05, 0.03, 0.85), Color(1.0, 0.45, 0.1), life + 2.0)
	vfx.emit("fire", g + Vector3(0, 0.4, 0), 3, FIRE, 1.5, 1.4, 0.6, 1.6, 0.8)
	vfx.emit("ember", g + Vector3(0, 0.4, 0), 3, Color(1.0, 0.55, 0.15), 2.0, 1.0)


func salami_hit(e: Node3D) -> void:
	var c: Vector3 = e.center()
	impact_flash(c, Color(1.0, 0.55, 0.2), 1.2, 0.0, 6)
	punch(c, "fire", 1.2, 10, 0.0, false)
	vfx.burst("fire", c)
	vfx.emit_one("impact", c, Vector3.ZERO, Color(1.0, 0.75, 0.4), 1.4, 1.0)


func salami_end(pos: Vector3) -> void:
	var g := _flat(pos)
	impact_flash(g + Vector3(0, 1.0, 0), FIRE, 1.6, 6.0, 8)
	punch(g + Vector3(0, 1.0, 0), "fire", 2.0, 18, 1.8, false)
	vfx.burst("explosion", g + Vector3(0, 0.8, 0))
	vfx.shockwave(g, 4.0, FIRE, 0.45, 0.07)
	vfx.emit("smoke", g + Vector3(0, 1.5, 0), 6, Color(0.14, 0.12, 0.11, 0.7), 1.6, 2.0, 1.0, 1.8, 1.4)


## Rundown: two glowing bases, the chalk line between them, and a ring on the runner.
func rundown_start(e: Node3D, a: Vector3, b: Vector3, dur: float) -> void:
	var wr := weakref(e)
	var alive := func() -> bool:
		var o: Object = wr.get_ref()
		return o != null and o.alive and o.rundown_t > 0.0
	for q in [a, b]:
		var g := _flat(q)
		vfx.ground_fx("hexdisc", g, 1.5, Color(RUNDOWN_V, 0.95), Color.WHITE, dur)
		vfx.beam(g, 0.8, 5.0, RUNDOWN_V, 0.9)
		vfx.shockwave(g, 2.0, RUNDOWN_V, 0.35, 0.08)
		_live_ring(g, null, 0.75, Color(1.0, 1.0, 1.0, 0.95), dur, alive)
	var pts := PackedVector3Array()
	for i in 9:
		pts.append(_flat(a.lerp(b, i / 8.0), 0.1))
	vfx.ribbon(pts, Color(1.0, 1.0, 1.0, 0.95), 0.22, dur, 0.0, false)
	vfx.ribbon(pts, Color(RUNDOWN_V, 0.9), 0.5, dur * 0.7, 0.0, false)
	_live_ring(e.global_position, e, 1.0, Color(RUNDOWN_V, 0.95), dur + 0.4, alive, 10.0, 2.0)
	impact_flash(e.center(), RUNDOWN_V, 1.1, 4.0, 6)
	punch(e.center(), "indigo", 1.4, 14, 1.6)
	for q2 in [a, b]:
		vv.ground_glow(_flat(q2), 1.8, "indigo", 1.6, 0.9)
	vfx.glyph(_flat(a.lerp(b, 0.5), 2.6), 6, 1.3, RUNDOWN_V, 1.2, 0.0, 0.4)


## Rundown: tagged at a turn.
func rundown_tag(e: Node3D) -> void:
	var c: Vector3 = e.center()
	vfx.catch_pop(c, RUNDOWN_V)
	punch(c, "indigo", 1.1, 10, 0.9)
	vfx.shockwave(_flat(c), 1.6, RUNDOWN_V, 0.3, 0.07)
	vfx.text_popup(c + Vector3(0, 1.2, 0), "TAG!", Color(0.9, 0.85, 1.0), 0.8, 0.6)


## Rain Delay: rain over the whole field, puddles splashing, a grey sky and the gates
## shut (a blue seal and a padlock at each gate) until the delay is over.
func rain_delay(dur: float) -> void:
	vfx.emit("smoke", Field.MOUND + Vector3(0, 18, -6), 18, Color(0.2, 0.24, 0.3, 0.8), 6.0, 0.1, 3.0, 5.0, minf(dur, 2.5))
	vfx.flash_light(Field.MOUND + Vector3(0, 10, 0), Color(0.6, 0.75, 1.0), 3.0, 40.0, 0.25)
	vfx.shockwave(Field.MOUND, 30.0, body("ice", 1.2), 0.8, 0.03)
	vfx.emit_one("v_flare", Field.MOUND + Vector3(0, 6.0, -4.0), Vector3.ZERO, rc("ice"), 3.0, 1.2)
	vv.ground_glow(Field.MOUND, 9.0, "ice", 1.4, 0.5, 0.0, 0.6)
	_desaturate(dur, 0.6)
	vfx.every_frame(dur, func(k: float) -> void:
		var fade := 1.0 - smoothstep(0.85, 1.0, k)
		for i in 6:
			if _rate(260.0 * fade):
				var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 30.0
				var p := Field.MOUND + Vector3(off.x, randf_range(10.0, 18.0), off.y - 6.0)
				vfx.emit_one("streak", p, Vector3(1.5, -30.0, 0.5), Color(0.8, 0.9, 1.0, 0.9), 2.4, 0.6)
		if _rate(40.0 * fade):
			var off2 := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 26.0
			var gp := Field.MOUND + Vector3(off2.x, 0.06, off2.y - 4.0)
			vfx.emit_one("ring", gp, Vector3.ZERO, Color(0.8, 0.9, 1.0, 0.7), 0.7, 0.7)
			vfx.emit_one("snow", gp + Vector3(0, 0.1, 0), Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), Color(0.8, 0.9, 1.0), 1.2, 0.5)
		if _rate(6.0 * fade):
			var off3 := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 18.0
			vfx.emit_one("mist", Field.MOUND + Vector3(off3.x, 0.3, off3.y - 2.0), Vector3(0, 0.1, 0), Color(0.7, 0.78, 0.9, 0.35), 3.0, 2.0))
	if battle and "gate_positions" in battle:
		for gp2 in battle.gate_positions.values():
			var g: Vector3 = _flat(gp2)
			vfx.ground_fx("hexdisc", g, 3.0, Color(RAIN, 0.85), Color.WHITE, dur)
			punch(g + Vector3(0, 1.2, 0), "ice", 1.4, 10, 1.8, false)
			vfx.beam(g, 2.2, 8.0, RAIN, 0.8)
			vfx.glyph(g + Vector3(0, 3.2, 0), 5, 2.0, Color(0.7, 0.85, 1.0), dur, 0.0, 0.3)


## Intentional Walk: four balls pop over the runner (BALL FOUR), then a mint ring walks with it.
func intentional_walk(e: Node3D, dur: float) -> void:
	var c: Vector3 = e.center()
	for i in 4:
		var a := lerpf(-0.9, 0.9, i / 3.0)
		var p := c + Vector3(a * 1.1, 1.4 + 0.35 * cos(a), 0)
		vfx.glyph(p, 13, 1.4, Color(0.95, 1.0, 0.95), 1.2, i * 0.12, 0.35)
		vfx.after(i * 0.12, func() -> void:
			vfx.emit_one("v_flare", p, Vector3.ZERO, rc("indigo"), 0.55, 0.6)
			Audio.play("glove_catch", -14.0, 0.1))
	var wr := weakref(e)
	vfx.after(0.5, func() -> void:
		var o: Object = wr.get_ref()
		if o != null:
			vfx.text_popup((o as Node3D).center() + Vector3(0, 2.3, 0), "BALL FOUR!", Color(0.7, 1.0, 0.78), 1.0, 1.0))
	vfx.shockwave(_flat(c), 2.2, body("indigo", 1.2), 0.4, 0.07)
	punch(c, "indigo", 1.3, 12, 1.6)
	var alive := func() -> bool:
		var o: Object = wr.get_ref()
		return o != null and o.alive and o.slows.has("intentional_walk")
	_live_ring(e.global_position, e, 1.1, Color(WALK, 0.95), dur + 0.4, alive, 8.0, 0.6)
	vfx.every_frame(dur, func(_k: float) -> void:
		if alive.call() and _rate(5.0):
			vfx.emit_one("glow", _flat((wr.get_ref() as Node3D).global_position, 0.15), Vector3.ZERO, Color(WALK, 0.7), 0.9, 1.0))


## A walking runner reaches home: no run.
func walk_no_run(e: Node3D) -> void:
	var h := Field.HOME
	vfx.shockwave(h, 3.2, body("indigo", 1.2), 0.45, 0.08)
	punch(e.center(), "indigo", 1.3, 12, 1.4)
	vfx.text_popup(h + Vector3(0, 2.6, 0), "NO RUN!", Color(0.7, 1.0, 0.78), 1.2, 1.1)
	vfx.glyph(h + Vector3(0, 1.8, 0), 14, 1.4, WALK, 0.9, 0.0, 0.6)


## Infield Fly: the pop-up goes straight up and hangs (a glint high above the zone, a white
## ring on the ground) until a runner steps in.
func infield_fly(point: Vector3, r: float, dur: float, item: Dictionary) -> void:
	var g := _flat(point)
	var top := g + Vector3(0, 15.0, 0)
	punch(g + Vector3(0, 0.8, 0), "teal", 1.2, 0, 1.6)
	vfx.ribbon(PackedVector3Array([g + Vector3(0, 0.6, 0), g + Vector3(0, 8.0, 0), top]), Color(FLY, 0.9), 0.24, 0.7, 0.0, false)
	vfx.spray("v_spark", g + Vector3(0, 0.8, 0), 14, rc("teal"), 18.0, Vector3.UP, 0.12, 1.0, 0.6)
	vfx.shockwave(g, r * 1.4, FLY, 0.4, 0.07)
	var waiting := func() -> bool: return battle.effects.active.has(item) and item.victim == null
	var armed := func() -> bool: return battle.effects.active.has(item)
	_live_ring(g, null, r, Color(FLY, 0.95), dur + 2.0, armed, 14.0, 0.8)
	vfx.ground_fx("radar", g, r * 0.9, Color(0.75, 0.9, 1.0, 0.45), Color.WHITE, dur, Vector2(0.6, 0.0), func(n: Node3D, k: float) -> void:
		var tt := k * dur
		var vis := smoothstep(0.0, 0.3, tt) * (1.0 if waiting.call() else 0.0)
		n.scale = Vector3.ONE * r * 0.9
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(k, vis * 0.8, 0.6, 0.0)))
	var icon := vfx.glyph(g + Vector3(0, 3.0, 0), 2, 1.5, FLY, dur, 0.0, 0.0)
	vfx.every_frame(dur, func(_k: float) -> void:
		var on: bool = waiting.call()
		if is_instance_valid(icon):
			icon.visible = on
		if on:
			if _rate(14.0):
				vfx.emit_one("glow", top + Vector3(0, sin(Time.get_ticks_msec() * 0.003) * 0.3, 0), Vector3.ZERO, Color(1.0, 1.0, 1.0, 0.95), 1.4, 0.25)
			if _rate(6.0):
				vfx.emit_one("magic", top, Vector3(randf_range(-1, 1), -1.0, randf_range(-1, 1)), FLY, 1.0, 0.8))


## Infield Fly: a runner stepped in: the ball comes down on it.
func infield_fly_drop(point: Vector3, e: Node3D, delay: float) -> void:
	var top := _flat(point, 15.0)
	lock_on(e, delay, FLY)
	vfx.text_popup(e.center() + Vector3(0, 1.8, 0), "INFIELD FLY!", Color(0.9, 0.97, 1.0), 1.0, delay + 0.2)
	var wr := weakref(e)
	vfx.every_frame(delay, func(k: float) -> void:
		var o: Object = wr.get_ref()
		if o == null:
			return
		var pos := top.lerp((o as Node3D).center() + Vector3(0, 0.6, 0), k * k)
		vfx.emit_one("glow", pos, Vector3.ZERO, Color(1.0, 1.0, 1.0, 0.95), 1.0, 0.12)
		if _rate(30.0):
			vfx.emit_one("streak", pos, Vector3(0, -8.0, 0), FLY, 1.0, 0.3))


## Infield Fly: caught. The runner is out (a boss is stunned instead).
func infield_fly_catch(e: Node3D, out: bool) -> void:
	var c: Vector3 = e.center()
	impact_flash(c, FLY, 1.3, 6.0, 6)
	punch(c, "teal", 1.6, 16, 1.6)
	vfx.catch_pop(c + Vector3(0, 0.6, 0), FLY)
	vfx.shockwave(_flat(c), 2.8, FLY, 0.4, 0.08)
	vfx.beam(_flat(c), 0.9, 10.0, FLY, 0.5)
	vfx.glyph(c + Vector3(0, 1.5, 0), 13, 1.4, FLY, 0.9, 0.0, 0.7)
	vfx.text_popup(c + Vector3(0, 2.4, 0), "CALLED OUT!" if out else "CAUGHT!", Color(0.9, 0.97, 1.0), 1.2, 1.0)


## Golden Glove: gold light pours into the glove; while armed, a gold ring of its reach
## follows the defender and one orb per catch left circles it.
func golden_glove(df: Node3D, item: Dictionary) -> void:
	if df == null or not is_instance_valid(df):
		return
	var dur := float(item.t)
	var r := float(item.radius)
	var feet := _flat(df.global_position)
	vfx.beam(feet, 1.1, 9.0, GLOVE_GOLD, 0.7)
	vfx.shockwave(feet, r * 1.6, GLOVE_GOLD, 0.5, 0.08)
	impact_flash(df.model.glove_position(), GLOVE_GOLD, 1.3, 6.0, 8)
	punch(df.model.glove_position(), "gold", 1.5, 14, 1.4, false)
	vv.ground_glow(feet, r, "gold", 1.4, 0.9)
	vfx.ring_emit("magic", feet + Vector3(0, 0.3, 0), 1.2, 18, GLOVE_GOLD, 0.8, 4.5, 1.1, 0.9)
	vfx.glyph(df.model.head_position() + Vector3(0, 1.1, 0), 0, 1.5, GLOVE_GOLD, 1.0, 0.1, 0.6)
	var armed := func() -> bool: return battle.effects.active.has(item) and int(item.charges) > 0
	_live_ring(feet, df, r, Color(GLOVE_GOLD, 0.95), dur + 0.4, armed, 0.0, 0.0)
	var wr := weakref(df)
	vfx.every_frame(dur, func(_k: float) -> void:
		var o: Object = wr.get_ref()
		if o == null or not armed.call():
			return
		var df2 := o as Node3D
		var n := int(item.charges)
		var t := Time.get_ticks_msec() * 0.004
		for i in n:
			var a := t + TAU * i / float(n)
			var p: Vector3 = df2.global_position + Vector3(cos(a) * 1.0, 1.6 + 0.15 * sin(t * 2.0 + i), sin(a) * 1.0)
			vfx.emit_one("glow", p, Vector3.ZERO, Color(GLOVE_GOLD, 0.95), 0.75, 0.1)
		if _rate(8.0):
			vfx.emit_one("magic", df2.model.glove_position(), Vector3(0, 1.0, 0), GLOVE_GOLD, 0.9, 0.6))


## Golden Glove: snag! A gold arc from the glove to the runner.
func golden_catch(df: Node3D, e: Node3D, boss: bool) -> void:
	var c: Vector3 = e.center()
	var gl: Vector3 = df.model.glove_position()
	vfx.ribbon(vfx.arc_points(gl, c, 0.8, 10), GLOVE_GOLD, 0.3, 0.45)
	vfx.ribbon(vfx.arc_points(gl, c, 0.8, 10), Color(1.0, 0.97, 0.8), 0.1, 0.35)
	impact_flash(c, GLOVE_GOLD, 1.3, 6.0, 8)
	punch(c, "gold", 1.6, 16, 1.5)
	vfx.catch_pop(c, GLOVE_GOLD)
	vfx.burst("gold", c)
	vfx.shockwave(_flat(c), 2.4, GLOVE_GOLD, 0.35, 0.08)
	vfx.glyph(c + Vector3(0, 1.4, 0), 13, 1.3, GLOVE_GOLD, 0.8, 0.0, 0.7)
	vfx.text_popup(c + Vector3(0, 2.2, 0), "SNAGGED!" if not boss else "ROBBED!", Color(1.0, 0.88, 0.45), 1.1, 1.0)


## The Shift: chevrons at the spot, every defender slides along a teal arrow (with an
## after-image where it stood) and keeps a quiet teal ring until it jogs back.
func shift(point: Vector3, moves: Array, dur: float) -> void:
	var g := _flat(point)
	punch(g + Vector3(0, 0.8, 0), "teal", 1.5, 12, 1.6)
	vfx.zone_ring(g, 2.2, Color(SHIFT_TEAL, 0.95), 1.0, 0.25, 2.0, 12.0)
	vfx.shockwave(g, 5.0, SHIFT_TEAL, 0.45, 0.07, 0.0, true)
	vfx.glyph(g + Vector3(0, 2.4, 0), 6, 1.8, SHIFT_TEAL, 1.0, 0.0, 0.5)
	for m in moves:
		var df: Node3D = m.df
		if not is_instance_valid(df):
			continue
		var a: Vector3 = _flat(m.from, 0.12)
		var b: Vector3 = _flat(m.to, 0.12)
		vfx.emit_one("glow", a + Vector3(0, 1.2, 0), Vector3.ZERO, Color(SHIFT_TEAL, 0.6), 2.2, 0.9)
		if a.distance_to(b) > 0.5:
			vfx.ribbon(PackedVector3Array([a, a.lerp(b, 0.5), b]), Color(SHIFT_TEAL, 0.95), 0.45, 0.9, 0.0, true)
			vfx.line_emit("v_spark", a + Vector3(0, 0.6, 0), b + Vector3(0, 0.6, 0), 8, rc("teal"), (b - a).normalized() * 8.0, 0.3, 1.0, 0.4)
			vv.ground_glow(b, 1.6, "teal", 1.2, 0.9, 0.15)
			vfx.after(dur - 0.5, func() -> void:
				vfx.ribbon(PackedVector3Array([b, b.lerp(a, 0.5), a]), Color(SHIFT_TEAL, 0.6), 0.25, 0.6, 0.0, true))
		defender_aura(df, Color(SHIFT_TEAL, 0.85), dur, 1.15)


## Momentum: a burst of chevrons at the plate; while it lasts, a cyan ring pulses there.
func momentum(dur: float) -> void:
	var h := Field.HOME
	punch(h + Vector3(0, 1.0, 0), "sky", 1.6, 14, 1.4)
	vfx.shockwave(h, 8.0, body("sky", 1.2), 0.5, 0.05)
	vfx.beam(h, 1.2, 8.0, ENERGY, 0.6)
	vfx.glyph(h + Vector3(0, 2.8, 0), 6, 2.0, ENERGY, 1.0, 0.0, 1.2)
	vfx.glyph(h + Vector3(0, 2.0, 0), 8, 1.4, Color(0.7, 0.95, 1.0), 0.9, 0.15, 1.2)
	vfx.ring_emit("streak", h + Vector3(0, 0.3, 0), 1.0, 16, ENERGY, 1.0, 9.0, 1.0, 0.6)
	var armed := func() -> bool: return battle.buff_active("momentum")
	_live_ring(h, null, 2.4, Color(ENERGY, 0.9), dur, armed, 12.0, 1.5)


## Momentum: an out pays energy; a spark of it flies from the runner down to the hand.
func momentum_gain(pos: Vector3, amount: float) -> void:
	var dest := Field.HOME + Vector3(0, 3.5, 2.0)
	var pts := vfx.arc_points(pos, dest, 3.0, 12)
	vfx.ribbon(pts, ENERGY, 0.2, 0.5)
	vfx.emit_one("v_flare", pos, Vector3.ZERO, rc("sky"), 0.8, 0.8)
	for i in 6:
		var p: Vector3 = pts[i * 2]
		vfx.after(i * 0.05, func() -> void: vfx.emit_one("glow", p, Vector3.ZERO, Color(ENERGY, 0.9), 1.0, 0.35))
	vfx.text_popup(pos + Vector3(0, 1.4, 0), "+%s ENERGY" % (str(int(amount)) if is_equal_approx(amount, roundf(amount)) else "%.1f" % amount),
		Color(0.6, 0.95, 1.0), 0.8, 0.8)


## Relief Pitcher: a bench arm from the bullpen (a defender not on the field), owned by
## CardEffects, which moves it.
func make_reliever(start: Vector3, spot: Vector3) -> Node3D:
	var used := {}
	for df in battle.defenders:
		used[df.id] = true
	var pick := ""
	for id in DB.defender_order:
		if not used.has(id) and DB.defender(id).get("role", "") == "pitcher":
			pick = id
			break
	if pick == "":
		for id in DB.defender_order:
			if not used.has(id):
				pick = id
				break
	if pick == "":
		pick = String(DB.defender_order[0])
	var holder := Node3D.new()
	battle.add_child(holder)
	holder.global_position = start
	var to := spot - start
	holder.rotation.y = atan2(to.x, to.z)
	var model := CharacterModel.new()
	holder.add_child(model)
	var colors: Dictionary = battle._uniform_colors.duplicate()
	colors["Undershirt"] = DB.defender(pick).get("accent", "#FFFFFF")
	model.setup(pick, {"accent": Color(DB.defender(pick).get("accent", "#FFFFFF")), "colors": colors, "cache_key": pick, "base": "run",
		"scale": Battle.UNIT_SCALE * 1.12})
	model.set_rim(Color(RELIEF, 0.7))
	var hw := weakref(holder)
	vfx.every_frame(0.9, func(_k: float) -> void:
		var o: Object = hw.get_ref()
		if o != null and _rate(20.0):
			vfx.emit_one("glow", (o as Node3D).global_position + Vector3(0, 0.3, 0), Vector3(0, 0.5, 0), Color(RELIEF, 0.8), 1.0, 0.5))
	return holder


## Relief Pitcher: the bullpen gate lights up and a green streak shows where he comes from.
func reliever_call(gate: Vector3, start: Vector3, spot: Vector3) -> void:
	vfx.beam(gate, 1.6, 8.0, RELIEF, 0.8)
	vfx.shockwave(_flat(gate), 4.0, RELIEF, 0.5, 0.06)
	var pts := vfx.arc_points(gate + Vector3(0, 1.5, 0), start + Vector3(0, 1.0, 0), 6.0, 16)
	vfx.ribbon(pts, RELIEF, 0.4, 0.8)
	vfx.ribbon(pts, Color(0.9, 1.0, 0.85), 0.12, 0.6)
	impact_flash(start + Vector3(0, 0.8, 0), RELIEF, 1.2, 4.0, 6)
	punch(start + Vector3(0, 0.8, 0), "lime", 1.4, 12, 1.4)
	vfx.zone_ring(_flat(spot), 1.4, Color(RELIEF, 0.9), 1.0, 0.3, 2.0, 8.0)
	vfx.ribbon(PackedVector3Array([_flat(start, 0.12), _flat(start.lerp(spot, 0.5), 0.12), _flat(spot, 0.12)]), Color(RELIEF, 0.8), 0.35, 1.0, 0.0, true)


## Relief Pitcher in position: a green pitching circle and his throwing range.
func reliever_arrive(spot: Vector3, rng: float, dur: float) -> void:
	var g := _flat(spot)
	punch(g + Vector3(0, 1.0, 0), "lime", 1.5, 14, 1.8)
	vfx.ground_fx("hexdisc", g, 1.3, Color(RELIEF, 0.8), Color.WHITE, dur)
	vfx.zone_ring(g, rng, Color(RELIEF, 0.55), dur, 0.03, 0.4, 32.0)
	vfx.shockwave(g, rng, RELIEF, 0.6, 0.04)
	vfx.beam(g, 0.9, 6.0, RELIEF, 0.5)
	vfx.text_popup(g + Vector3(0, 3.6, 0), "NOW PITCHING!", Color(0.7, 1.0, 0.65), 1.0, 1.1)


func reliever_leave(pos: Vector3) -> void:
	vfx.shockwave(_flat(pos), 2.0, RELIEF, 0.35, 0.06)


func reliever_gone(pos: Vector3) -> void:
	vfx.puff(pos + Vector3(0, 1.0, 0), RELIEF)
	vfx.emit_one("v_flare", pos + Vector3(0, 1.0, 0), Vector3.ZERO, rc("lime"), 1.0, 0.7)


## Instant Replay: the moment rewinds: implode rings and a big rewind spiral at the spot,
## then the replayed card goes off there.
func instant_replay(at: Vector3, card_id: String) -> void:
	var g := _flat(at)
	for i in 3:
		vfx.shockwave(g, 7.0 - i * 1.5, Color(REPLAY, 0.95 - i * 0.2), 0.35, 0.06, i * 0.1, true)
	vfx.beam(g, 1.2, 10.0, REPLAY, 0.6)
	punch(g + Vector3(0, 1.2, 0), "legend", 1.8, 18, 1.6)
	vv.ground_glow(g, 4.0, "sky", 1.0, 0.9, 0.0, 0.8)
	legend_accent(g + Vector3(0, 1.2, 0), "sky")
	vfx.glyph(g + Vector3(0, 3.6, 0), 11, 2.6, REPLAY, 1.0, 0.0, 0.3)
	vfx.glyph(g + Vector3(1.6, 4.6, 0), 6, 1.2, Color(1.0, 0.35, 0.35), 0.9, 0.05, 0.3)
	vfx.text_popup(g + Vector3(0, 6.0, 0), "REPLAY", Color(0.75, 1.0, 1.0), 1.3, 1.0)
	vfx.ring_emit("v_mote", g + Vector3(0, 0.4, 0), 3.0, 20, rc("sky"), -4.0, 2.0, 1.0, 0.6)
	if battle:
		battle.hud_flash(Color(0.5, 0.95, 1.0, 0.12))


# ---------------------------------------------------------------- Update 9 cards

const SCOUT_V := Color(0.86, 0.45, 1.0)
const WATER := Color(0.3, 0.88, 1.0)
const SWEET := Color(1.0, 0.62, 0.16)
const MONKEY := Color(1.0, 0.66, 0.2)
const WIND := Color(0.55, 1.0, 0.32)
const COIN := Color(1.0, 0.8, 0.2)
const SCOOP := Color(0.55, 1.0, 0.3)
const SIGNAL := Color(1.0, 0.6, 0.12)
const TRICK := Color(0.66, 0.48, 1.0)
const WORM := Color(1.0, 0.5, 0.1)
const SLICK := Color(1.0, 0.62, 0.28)
## Firework shell colours (crimson, gold, sky, lime, violet): one per rocket in turn.
const FIREWORK_RAMPS := ["crimson", "solar", "sky", "lime", "violet"]
var _env_brightness := -1.0
var _dim_gen := 0


## A glyph over a target's head that follows it while `alive` holds (and fades out after).
func _follow_glyph(target: Node3D, cell: int, size: float, color: Color, dur: float, alive: Callable, lift := 1.2) -> void:
	if target == null or not is_instance_valid(target):
		return
	var g: MeshInstance3D = vfx._take("glyph")
	var wr := weakref(target)
	var head := func() -> Vector3:
		var o: Object = wr.get_ref()
		if o == null:
			return g.global_position
		var n3 := o as Node3D
		return n3.global_position + Vector3(0, (n3.get("height") if n3.get("height") != null else 1.8) + lift, 0)
	g.global_position = head.call()
	g.set_instance_shader_parameter("color", color)
	var fade := [0.0]
	vfx.animate(g, dur, func(n: Node3D, k: float) -> void:
		var on: bool = alive.call() and k < 0.97
		fade[0] = move_toward(float(fade[0]), 1.0 if on else 0.0, _dt() * (6.0 if on else 4.0))
		n.global_position = head.call()
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - k * dur * 4.0)
		n.scale = Vector3.ONE * size * pop * maxf(float(fade[0]), 0.01)
		(n as MeshInstance3D).set_instance_shader_parameter("anim", Vector4(0.5, cell, 0, 0)))


## Ground ribbon along a stretch of a base path (d0..d1), `width` wide.
func _path_ribbon(rt: Route, d0: float, d1: float, color: Color, width: float, life: float, y := 0.1) -> void:
	var pts := PackedVector3Array()
	var n := maxi(2, int((d1 - d0) / 1.2) + 1)
	for i in n:
		pts.append(_flat(rt.position_at(lerpf(d0, d1, float(i) / float(n - 1))), y))
	vfx.ribbon(pts, color, width, life, 0.0, false)


## Scouting Report: a scope locks on the picked runner, then violet links jump to every runner
## of its type; each one carries a reticle and a dashed ring while it is scouted.
func scouting_report(e: Node3D, victims: Array, dur: float) -> void:
	if e == null or not is_instance_valid(e):
		return
	var c: Vector3 = e.center()
	lock_on(e, 0.35, SCOUT_V)
	punch(c, "violet", 1.4, 14, 1.4)
	vfx.shockwave(_flat(c), 3.0, body("violet", 1.2), 0.4, 0.07)
	vfx.beam(_flat(c), 0.9, 7.0, SCOUT_V, 0.6)
	vfx.text_popup(c + Vector3(0, 2.6, 0), "SCOUTED!", Color(0.95, 0.75, 1.0), 1.1, 1.0)
	var i := 0
	for v in victims:
		var en := v as Node3D
		if en == null or not is_instance_valid(en):
			continue
		var delay := 0.12 + 0.05 * i
		i += 1
		var wr := weakref(en)
		var alive := func() -> bool:
			var o: Object = wr.get_ref()
			return o != null and o.alive and o.scout_t > 0.0
		if en != e:
			var to: Vector3 = en.center()
			vfx.after(delay, func() -> void:
				var o: Object = wr.get_ref()
				var dest: Vector3 = (o as Node3D).center() if o != null else to
				vfx.ribbon(vfx.arc_points(c, dest, 1.6, 12), body("violet", 1.3), 0.12, 0.5)
				vfx.ribbon(vfx.arc_points(c, dest, 1.6, 12), pal("violet", 0), 0.05, 0.4)
				punch(dest, "violet", 0.8, 8, 0.8, false))
		_live_ring(en.global_position, en, 1.0, Color(SCOUT_V, 0.95), dur, alive, 8.0, 1.2)
		_follow_glyph(en, 2, 1.1, SCOUT_V, dur, alive, 1.3)


## Sprinkler System: sprinkler heads pop up along the path and throw arcs of water over it;
## the wet grass glows aqua and ripples until the water turns off.
func sprinkler(rt: Route, d0: float, d1: float, dur: float) -> void:
	var mid := rt.position_at((d0 + d1) * 0.5)
	punch(_flat(mid, 0.8), "aqua", 1.3, 12, 0.0, false)
	vfx.shockwave(_flat(mid), (d1 - d0) * 0.6, body("aqua", 1.2), 0.45, 0.05)
	_path_ribbon(rt, d0, d1, Color(WATER, 0.42), 3.4, dur)
	_path_ribbon(rt, d0, d1, Color(0.85, 1.0, 1.0, 0.5), 0.35, dur, 0.12)
	var heads: Array = []
	var n := maxi(2, int((d1 - d0) / 3.0) + 1)
	for i in n:
		var d := lerpf(d0, d1, float(i) / float(n - 1))
		var pos := rt.position_at(d)
		var side := rt.direction_at(d).cross(Vector3.UP).normalized() * (1.7 if i % 2 == 0 else -1.7)
		heads.append([_flat(pos + side), -side.normalized()])
		vv.ground_glow(_flat(pos), 2.0, "aqua", dur, 0.5, 0.05 * i, 0.55)
		vfx.after(0.05 * i, func() -> void:
			vfx.spray("snow", _flat(pos + side, 0.3), 10, Color(0.8, 0.97, 1.0), 6.0, Vector3.UP - side * 0.3, 0.5, 1.0, 0.7)
			vfx.emit_one("ring", _flat(pos, 0.08), Vector3.ZERO, Color(WATER, 0.8), 1.4, 0.8))
	vfx.every_frame(dur, func(k: float) -> void:
		var fade := 1.0 - smoothstep(0.88, 1.0, k)
		for hd in heads:
			var hp: Vector3 = hd[0]
			var into: Vector3 = hd[1]
			if _rate(26.0 * fade):
				# A droplet thrown over the path in an arc.
				vfx.emit_one("snow", hp + Vector3(0, 0.3, 0), into * randf_range(2.0, 3.6) + Vector3(randf_range(-1.2, 1.2), randf_range(3.0, 4.5), randf_range(-1.2, 1.2)),
					Color(0.75, 0.95, 1.0, 0.9), 1.1, 0.8)
			if _rate(3.0 * fade):
				vfx.emit_one("mist", hp + into * 1.6 + Vector3(0, 0.4, 0), Vector3(0, 0.2, 0), Color(0.7, 0.9, 1.0, 0.3), 2.2, 1.4)
		if _rate(10.0 * fade):
			var p2 := rt.position_at(randf_range(d0, d1))
			vfx.emit_one("ring", _flat(p2, 0.08) + Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)), Vector3.ZERO, Color(0.8, 0.97, 1.0, 0.75), 0.6, 0.6))


## A wet runner slips: a splash, sliding streaks and "SLIP!".
func slip(e: Node3D) -> void:
	var g := _flat(e.global_position, 0.1)
	vfx.emit_one("ring", g, Vector3.ZERO, Color(WATER, 0.9), 1.4, 0.7)
	vfx.spray("snow", g + Vector3(0, 0.2, 0), 12, Color(0.8, 0.97, 1.0), 5.0, Vector3.UP, 1.1, 1.0, 0.6)
	vfx.emit_one("v_flare", g + Vector3(0, 0.5, 0), Vector3.ZERO, rc("aqua"), 0.6, 0.6)
	vfx.text_popup(e.center() + Vector3(0, 1.2, 0), "SLIP!", Color(0.6, 0.95, 1.0), 0.75, 0.7)


## Sweet Spot: every defender lights up gold-red (a starburst at the hand, a star overhead)
## and keeps a hot ring while every throw crits.
func sweet_spot(dur: float) -> void:
	var m := Field.MOUND
	vfx.shockwave(m, 24.0, body("solar", 1.25), 0.6, 0.035)
	punch(m + Vector3(0, 1.2, 0), "solar", 1.8, 18, 1.6, false)
	vfx.flash_light(m + Vector3(0, 3.0, 0), SWEET, 4.0, 24.0, 0.4)
	vfx.text_popup(m + Vector3(0, 4.0, 0), "EVERY THROW CRITS!", Color(1.0, 0.82, 0.4), 1.1, 1.2)
	for df in battle.defenders:
		var hand: Vector3 = df.model.hand_position()
		vfx.emit_one("v_flare", hand, Vector3.ZERO, rc("solar"), 1.1, 1.0)
		vfx.radial_streaks(hand, 10, body("solar", 1.3), 7.0, 0.8, 0.5)
		vfx.glyph(df.model.head_position() + Vector3(0, 1.0, 0), 0, 1.3, Color(1.0, 0.85, 0.35), 0.9, 0.0, 0.8)
		vv.ground_glow(_flat(df.global_position), 1.6, "solar", 1.0, 0.9)
		defender_aura(df, Color(SWEET, 0.9), dur, 1.25)
	vfx.every_frame(dur, func(_k: float) -> void:
		for df in battle.defenders:
			if is_instance_valid(df) and _rate(6.0):
				vfx.emit_one("v_spark", df.model.hand_position(), Vector3(randf_range(-1, 1), 2.0, randf_range(-1, 1)), rc("solar"), 0.8, 0.5))


## Rally Monkey: an amber pom-pom burst over the plate; clutch, it's a full party (confetti,
## chevrons racing up and the drawn card flying to the hand).
func rally_monkey(clutch: bool, drawn: Array, energy: float) -> void:
	var h := Field.HOME + Vector3(0, 0, -2.0)
	var s := 1.4 if clutch else 1.0
	punch(h + Vector3(0, 1.5, 0), "amber", 1.6 * s, int(16 * s), 1.6)
	vfx.shockwave(h, 9.0 * s, body("amber", 1.25), 0.5, 0.05)
	vfx.beam(h, 1.0 * s, 9.0, MONKEY, 0.7)
	vfx.glyph(h + Vector3(0, 3.4, 0), 9, 2.0 * s, MONKEY, 1.0, 0.0, 1.0)
	vfx.glyph(h + Vector3(-1.4, 2.6, 0), 6, 1.2, Color(1.0, 0.85, 0.4), 0.9, 0.08, 1.4)
	vfx.glyph(h + Vector3(1.4, 2.6, 0), 6, 1.2, Color(1.0, 0.85, 0.4), 0.9, 0.16, 1.4)
	vfx.ring_emit("v_mote", h + Vector3(0, 0.3, 0), 1.2, int(16 * s), rc("amber"), 1.0, 5.0, 1.1, 1.0)
	vv.ground_glow(h, 3.0 * s, "amber", 1.4, 0.9)
	vfx.text_popup(h + Vector3(0, 5.4, 0), "+%d ENERGY" % int(energy), Color(1.0, 0.86, 0.45), 1.15, 1.2)
	if clutch:
		vfx.text_popup(h + Vector3(0, 6.8, 0), "CLUTCH!", Color(1.0, 0.6, 0.25), 1.4, 1.3)
		vfx.burst("confetti", h + Vector3(0, 6, 0))
		vfx.burst("confetti", Field.MOUND + Vector3(0, 6, 0))
		vfx.flash_light(h + Vector3(0, 3.0, 0), MONKEY, 5.0, 18.0, 0.5)
		for i in drawn.size():
			flying_card(drawn[i], h + Vector3(0, 2.4, 0), float(i) * 2.0, 0.25 + i * 0.09)


## Second Wind: a green gust spirals up around the defender, the signature card flies back to
## the hand recharged, and a quick lime ring stays while it throws faster.
func second_wind(df: Node3D, dur: float, reset: Array) -> void:
	if df == null or not is_instance_valid(df):
		return
	var feet := _flat(df.global_position)
	punch(df.model.chest_position(), "lime", 1.5, 14, 1.6)
	vfx.shockwave(feet, 4.0, body("lime", 1.25), 0.45, 0.07)
	vfx.beam(feet, 1.0, 8.0, WIND, 0.6)
	vv.ground_glow(feet, 2.4, "lime", 1.5, 0.9)
	vfx.glyph(df.model.head_position() + Vector3(0, 1.0, 0), 12, 1.5, WIND, 1.0, 0.0, 0.9)
	defender_aura(df, Color(WIND, 0.9), dur, 1.3)
	# The gust: streaks winding up around the body.
	for i in 18:
		var a := i * 0.7
		var p := feet + Vector3(cos(a) * 1.1, 0.2 + i * 0.16, sin(a) * 1.1)
		vfx.after(i * 0.02, func() -> void:
			vfx.emit_one("streak", p, Vector3(-sin(a), 0.6, cos(a)) * 6.0, Color(WIND, 0.9), 1.0, 0.45)
			vfx.emit_one("v_mote", p, Vector3(0, 1.4, 0), rc("lime"), 0.8, 0.8))
	if not reset.is_empty():
		flying_card(String(reset[0]), df.model.head_position() + Vector3(0, 1.6, 0), 0.0, 0.2, 1.5)
		vfx.text_popup(df.model.head_position() + Vector3(0, 2.8, 0), "SIGNATURE READY!", Color(0.75, 1.0, 0.6), 1.0, 1.2)
	var wr := weakref(df)
	vfx.every_frame(dur, func(k: float) -> void:
		var o: Object = wr.get_ref()
		if o == null or not _rate(10.0 * (1.0 - smoothstep(0.85, 1.0, k))):
			return
		var a2 := randf() * TAU
		var base: Vector3 = _flat((o as Node3D).global_position) + Vector3(cos(a2) * 1.0, randf_range(0.3, 1.6), sin(a2) * 1.0)
		vfx.emit_one("streak", base, Vector3(-sin(a2), 0.8, cos(a2)) * 4.0, Color(WIND, 0.75), 0.7, 0.4))


## Money Ball: a shower of gold at the plate and a gold ring there while outs pay double.
func money_ball(dur: float) -> void:
	var h := Field.HOME + Vector3(0, 0, -1.0)
	punch(h + Vector3(0, 1.2, 0), "gold", 1.6, 16, 1.6)
	vfx.shockwave(h, 10.0, body("gold", 1.25), 0.5, 0.05)
	vfx.beam(h, 1.1, 9.0, COIN, 0.7)
	vfx.burst("gold", h + Vector3(0, 2.0, 0))
	vfx.glyph(h + Vector3(0, 3.2, 0), 13, 2.0, COIN, 1.1, 0.0, 1.0)
	vfx.text_popup(h + Vector3(0, 5.0, 0), "2X COINS!", Color(1.0, 0.88, 0.4), 1.3, 1.2)
	for i in vfx._count(26):
		var d := Vector3(randf_range(-1, 1), randf_range(1.2, 2.2), randf_range(-1, 1)).normalized()
		vfx.emit_one("spark", h + Vector3(0, 1.6, 0), d * randf_range(6.0, 10.0), Color(1.0, 0.85, 0.3), 2.2, 1.4)
	var armed := func() -> bool: return battle.buff_active("money_ball")
	_live_ring(h, null, 2.6, Color(COIN, 0.9), dur, armed, 16.0, 1.0)


## An out under Money Ball: the extra coins pop up in gold.
func money_ball_coin(pos: Vector3, coin: int) -> void:
	vfx.text_popup(pos + Vector3(-0.6, 0.9, 0), "+%d x2" % coin, Color(1.0, 0.86, 0.3), 0.85, 0.9)
	vfx.spray("spark", pos, 8, Color(1.0, 0.85, 0.3), 6.0, Vector3.UP, 0.6, 1.4, 0.8)
	vfx.emit_one("v_flare", pos, Vector3.ZERO, rc("gold"), 0.7, 0.6)


## Scoop & Tag: Moose's long reach sweeps a lime crescent across the area, kicking up dirt.
func scoop_sweep(from: Vector3, point: Vector3, r: float) -> void:
	var g := _flat(point)
	var to := g - _flat(from)
	var base_a := atan2(to.z, to.x) + PI   # start on the caster's side
	var sweep := 0.28
	var steps := 12
	vv.ground_glow(g, r, "emerald", 1.4, 0.9)
	vfx.ground_fx("rays", g, r * 1.05, Color(SCOOP, 0.55), Color(0.9, 1.0, 0.8), 1.0)
	vfx.flash_light(g + Vector3(0, 2.0, 0), SCOOP, 4.0, r * 3.0, 0.4)
	for i in steps:
		var k0 := float(i) / steps
		var k1 := float(i + 1) / steps
		var a0 := base_a - 1.9 + 3.8 * k0
		var a1 := base_a - 1.9 + 3.8 * k1
		var p0 := g + Vector3(cos(a0), 0, sin(a0)) * r * 0.85
		var p1 := g + Vector3(cos(a1), 0, sin(a1)) * r * 0.85
		vfx.after(sweep * k0, func() -> void:
			var pts := PackedVector3Array([p0 + Vector3(0, 0.7, 0), p0.lerp(p1, 0.5) + Vector3(0, 0.75, 0), p1 + Vector3(0, 0.7, 0)])
			vfx.ribbon(pts, body("emerald", 1.3), 0.9, 0.45, 0.0, false)
			vfx.ribbon(pts, pal("emerald", 0), 0.28, 0.35, 0.0, false)
			vfx.spray("v_spark", p1 + Vector3(0, 0.6, 0), 4, rc("emerald"), 8.0, (p1 - p0).normalized() + Vector3.UP * 0.3, 0.4, 1.0, 0.5)
			if i % 3 == 0:
				vfx.dust(p1, 0.8))
	vfx.after(sweep, func() -> void:
		punch(g + Vector3(0, 0.8, 0), "emerald", 1.6, 16, 0.0, false)
		vfx.shockwave(g, r * 1.25, body("emerald", 1.25), 0.4, 0.07)
		vfx.spray("debris", g + Vector3(0, 0.3, 0), 12, Color(0.45, 0.34, 0.24), 9.0, Vector3.UP, 1.0, 1.0, 0.9)
		vfx.glyph(g + Vector3(0, 3.0, 0), 13, 1.6, SCOOP, 0.9, 0.0, 0.8))


## Scoop & Tag: a hurt runner is tagged out.
func scoop_tag(e: Node3D) -> void:
	var c: Vector3 = e.center()
	vfx.catch_pop(c, SCOOP)
	punch(c, "emerald", 1.3, 12, 1.0)
	vfx.text_popup(c + Vector3(0, 1.6, 0), "TAGGED!", Color(0.8, 1.0, 0.6), 0.95, 0.9)


## Signal Caller: Rosa flashes the signs: amber arcs fly to the marked runners, each gets its
## number and a reticle ring that follows it while the mark lasts.
func signal_caller(caster: Node3D, marked: Array, dur: float) -> void:
	var from: Vector3 = caster.model.head_position() + Vector3(0, 0.6, 0) if caster and is_instance_valid(caster) else Field.HOME + Vector3(0, 2.0, 0)
	punch(from, "amber", 1.2, 12, 0.0, false)
	vfx.shockwave(_flat(from), 3.0, body("amber", 1.2), 0.4, 0.07)
	for i in marked.size():
		var en := marked[i] as Node3D
		if en == null or not is_instance_valid(en):
			continue
		var wr := weakref(en)
		var alive := func() -> bool:
			var o: Object = wr.get_ref()
			return o != null and o.alive and o.signal_t > 0.0
		var delay := 0.08 * i
		vfx.after(delay, func() -> void:
			var o: Object = wr.get_ref()
			if o == null:
				return
			var c: Vector3 = (o as Node3D).center()
			vfx.ribbon(vfx.arc_points(from, c, 3.0, 14), body("amber", 1.3), 0.16, 0.55)
			vfx.ribbon(vfx.arc_points(from, c, 3.0, 14), pal("amber", 0), 0.06, 0.45)
			punch(c, "amber", 1.2, 12, 1.2)
			# Staggered heights, so the numbers of a bunched pack don't overlap.
			vfx.text_popup(c + Vector3(0, 2.4 + i * 0.9, 0), str(i + 1), Color(1.0, 0.85, 0.45), 1.5, 1.1))
		_live_ring(en.global_position, en, 1.05, Color(SIGNAL, 0.95), dur, alive, 6.0, 2.0)
		_follow_glyph(en, 2, 1.15, SIGNAL, dur, alive, 1.3)


## Signal Caller: an out on a signalled runner refunds energy (an amber spark to the hand).
func signal_refund(pos: Vector3, amount: float) -> void:
	var dest := Field.HOME + Vector3(0, 3.5, 2.0)
	var pts := vfx.arc_points(pos, dest, 3.0, 12)
	vfx.ribbon(pts, SIGNAL, 0.2, 0.5)
	vfx.emit_one("v_flare", pos, Vector3.ZERO, rc("amber"), 0.8, 0.8)
	vfx.text_popup(pos + Vector3(0, 1.4, 0), "+%s ENERGY" % (str(int(amount)) if is_equal_approx(amount, roundf(amount)) else "%.1f" % amount),
		Color(1.0, 0.86, 0.45), 0.8, 0.8)


## Hidden Ball Trick: a spotlight and a "?" follow the strongest runner through the reveal;
## bosses get an indigo reticle.
func hidden_ball_start(victim: Node3D, bosses: Array, reveal: float) -> void:
	var targets: Array = []
	if victim and is_instance_valid(victim):
		targets.append(victim)
	targets.append_array(bosses)
	for t in targets:
		var en := t as Node3D
		var wr := weakref(en)
		var alive := func() -> bool:
			var o: Object = wr.get_ref()
			return o != null and o.alive
		_live_ring(en.global_position, en, 1.3, Color(TRICK, 0.95), reveal + 0.3, alive, 10.0, 3.0)
		# A big "?" well above the health bars (they stack up over a crowd).
		_follow_glyph(en, 1, 2.3, Color(0.88, 0.74, 1.0), reveal + 0.2, alive, 2.8)
		var c: Vector3 = en.center()
		punch(c, "indigo", 1.1, 10, 0.0, false)
		vfx.sphere_pulse(c, 1.6, Color(TRICK, 0.6), 0.4)
		vfx.emit("smoke", c, 6, Color(0.2, 0.1, 0.35, 0.7), 1.5, 0.6, 1.0, 1.4, 1.0)
		# A spotlight cone that tracks the runner during the reveal.
		vfx.every_frame(reveal, func(k: float) -> void:
			var o: Object = wr.get_ref()
			if o == null or not _rate(30.0):
				return
			var g2: Vector3 = _flat((o as Node3D).global_position)
			vfx.emit_one("glow", g2 + Vector3(randf_range(-0.4, 0.4), randf_range(2.0, 6.0), randf_range(-0.4, 0.4)), Vector3(0, -3.0, 0),
				Color(TRICK, 0.55 + 0.3 * k), 1.2, 0.4)
			if _rate(4.0):
				vfx.emit_one("ring", g2 + Vector3(0, 0.08, 0), Vector3.ZERO, Color(0.85, 0.75, 1.0, 0.8), 1.6 - k, 0.4))


## Hidden Ball Trick: the reveal! The ball pops out over the runner and it is out.
func hidden_ball_out(e: Node3D) -> void:
	var c: Vector3 = e.center()
	impact_flash(c, TRICK, 1.4, 5.0, 10)
	punch(c, "indigo", 1.8, 18, 1.6)
	vfx.shockwave(_flat(c), 3.4, body("indigo", 1.3), 0.4, 0.08)
	vfx.beam(_flat(c), 1.0, 9.0, TRICK, 0.5)
	vfx.glyph(c + Vector3(0, 1.2, 0), 13, 1.8, Color(1.0, 1.0, 1.0), 1.0, 0.0, 1.4)
	vfx.radial_streaks(c, 12, body("indigo", 1.3), 8.0, 0.9, 0.5)
	vfx.text_popup(c + Vector3(0, 2.6, 0), "GOTCHA!", Color(0.9, 0.8, 1.0), 1.4, 1.1)


func hidden_ball_boss(e: Node3D) -> void:
	var c: Vector3 = e.center()
	punch(c, "indigo", 2.0, 16, 1.4)
	vfx.radial_streaks(c, 10, body("indigo", 1.3), 9.0, 1.0, 0.5)
	vfx.text_popup(c + Vector3(0, 3.0, 0), "TRICKED!", Color(0.9, 0.8, 1.0), 1.3, 1.0)


## Worm Burner: Sid's sidearm release, a low blazing liner into the dirt.
func worm_release(from: Vector3, land: Vector3, flight: float) -> void:
	var dir := (land - from).normalized()
	vfx.emit_one("v_flare", from, Vector3.ZERO, rc("blaze"), 1.0, 0.8)
	vfx.spray("v_spark", from, 16, rc("blaze"), 14.0, dir, 0.2, 1.0, 0.5)
	battle.projectiles.launch_at(from, land + Vector3(0, 0.2, 0), from.distance_to(land) / maxf(flight, 0.05),
		{"color": WORM, "big": true, "arc_mult": 0.25, "trail": "comet"}, func(_at: Vector3) -> void: pass)
	var m: Node3D = vfx.telegraph(_flat(land), 1.8, Color(WORM, 0.9), flight)
	vfx.after(flight + 0.02, func() -> void:
		if is_instance_valid(m):
			m.queue_free())


func worm_land(land: Vector3) -> void:
	var g := _flat(land)
	impact_flash(g + Vector3(0, 0.5, 0), WORM, 1.3, 6.0, 10)
	punch(g + Vector3(0, 0.5, 0), "blaze", 1.6, 16, 1.6, false)
	vfx.shockwave(g, 3.4, body("blaze", 1.25), 0.4, 0.08)
	vfx.spray("debris", g + Vector3(0, 0.3, 0), 12, Color(0.45, 0.32, 0.22), 9.0, Vector3.UP, 0.9, 1.1, 0.9)
	vfx.decal("crater", g, 1.5, Color(0.08, 0.05, 0.04, 0.8), WORM, 4.0)


## The grounder itself: a small blazing ball (owned by CardEffects).
func worm_ball(land: Vector3) -> Node3D:
	var n := _giant_ball(land, 0.42)
	n.set_meta("skip", 0)
	return n


## Skipping along: a hop every 3 m, a burst of dust and sparks at each landing.
func worm_roll(node: Node3D, pos: Vector3, dir: Vector3, dist: float) -> void:
	const HOP := 3.0
	var k := dist / HOP
	var hop := absf(sin(k * PI)) * 0.9
	node.global_position = _flat(pos) + Vector3(0, hop, 0)
	var mi := node.get_child(0) as Node3D
	var axis := dir.cross(Vector3.UP)
	if axis.length() > 0.01:
		mi.global_rotate(axis.normalized(), -0.6)
	var skip := int(floor(k))
	if skip != int(node.get_meta("skip", 0)):
		node.set_meta("skip", skip)
		var g := _flat(pos)
		vfx.dust(g, 0.9)
		vfx.emit_one("ring", g + Vector3(0, 0.08, 0), Vector3.ZERO, Color(WORM, 0.9), 1.3, 0.5)
		vfx.spray("v_spark", g + Vector3(0, 0.2, 0), 10, rc("blaze"), 9.0, dir + Vector3.UP * 0.6, 0.5, 1.0, 0.5)
		vfx.emit_one("v_flare", g + Vector3(0, 0.3, 0), Vector3.ZERO, rc("blaze"), 0.7, 0.4)
	if _rate(70.0):
		vfx.emit_one("fire", node.global_position + Vector3(0, 0.4, 0), -dir * 2.0 + Vector3(0, 1.5, 0), FIRE, 1.1, 0.4)


## The furrow the grounder tears behind it: a scorched groove with flames licking up.
func worm_trail(pos: Vector3, dir: Vector3) -> void:
	var g := _flat(pos)
	vfx.decal("scorch", g, 1.1, Color(0.08, 0.05, 0.03, 0.85), WORM, 4.5)
	vfx.flame_sheet(g, 1.4, 1.2, 0.6)
	vv.ground_glow(g, 1.6, "blaze", 1.3, 0.3, 0.0, 0.7)
	vfx.emit("ember", g + Vector3(0, 0.3, 0), 3, Color(1.0, 0.55, 0.15), 2.0, 1.0)
	vfx.spray("debris", g + Vector3(0, 0.2, 0), 3, Color(0.45, 0.32, 0.22), 5.0, dir + Vector3.UP, 0.6, 0.7, 0.6)


func worm_hit(e: Node3D) -> void:
	var c: Vector3 = e.center()
	impact_flash(c, WORM, 1.0, 0.0, 6)
	punch(c, "blaze", 1.2, 10, 0.0, false)
	vfx.emit_one("impact", c, Vector3.ZERO, Color(1.0, 0.75, 0.4), 1.3, 1.0)


func worm_end(pos: Vector3) -> void:
	var g := _flat(pos)
	punch(g + Vector3(0, 0.6, 0), "blaze", 1.4, 14, 1.2, false)
	vfx.shockwave(g, 3.0, body("blaze", 1.2), 0.4, 0.07)
	vfx.dust(g, 1.2)


## Worm Burner's slick: the torn-up path glistens orange while it slows runners.
func slick(rt: Route, d0: float, d1: float, dur: float) -> void:
	_path_ribbon(rt, d0, d1, Color(SLICK, 0.35), 2.8, dur)
	_path_ribbon(rt, d0, d1, Color(1.0, 0.85, 0.6, 0.35), 0.3, dur, 0.12)
	vfx.every_frame(dur, func(k: float) -> void:
		if _rate(8.0 * (1.0 - smoothstep(0.85, 1.0, k))):
			var p2 := rt.position_at(randf_range(d0, d1))
			vfx.emit_one("glow", _flat(p2, 0.2) + Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.8, 0.8)), Vector3(0, 0.3, 0), Color(SLICK, 0.6), 0.8, 0.6))


## Darkens the world for a moment (Fireworks Night: lights down for the show), restored after.
func _dim_world(time: float, to := 0.7) -> void:
	var env: Environment = vv._env()
	if env == null or not env.adjustment_enabled:
		return
	if _env_brightness < 0.0:
		_env_brightness = env.adjustment_brightness
	var base := _env_brightness
	_dim_gen += 1
	var gen := _dim_gen
	vfx.every_frame(time, func(k: float) -> void:
		if gen != _dim_gen:
			return
		var tt := k * time
		var amt := smoothstep(0.0, 0.4, tt) * (1.0 - smoothstep(time - 0.7, time, tt))
		env.adjustment_brightness = lerpf(base, base * to, amt)
		if k >= 1.0:
			env.adjustment_brightness = base)


## Fireworks Night: the lights go down and the crowd roars before the first rocket.
func fireworks_start(span: float) -> void:
	var m := Field.MOUND
	legend_accent(m + Vector3(0, 6.0, 0), "crimson")
	_dim_world(span + 1.6, 0.72)
	vfx.shockwave(m, 30.0, body("crimson", 1.25), 0.8, 0.03)
	vfx.flash_light(m + Vector3(0, 12.0, 0), Color(1.0, 0.4, 0.7), 4.0, 40.0, 0.6)
	vfx.text_popup(m + Vector3(0, 7.0, 0), "FIREWORKS NIGHT!", Color(1.0, 0.7, 0.9), 1.6, 1.4)
	for p in [Field.HOME + Vector3(0, 8, -8), m + Vector3(-8, 8, 0), m + Vector3(8, 8, 0)]:
		vfx.burst("confetti", p)


## One rocket streaking off the stands toward its runner.
func firework_rocket(from: Vector3, to: Vector3, flight: float, i: int) -> void:
	var ramp: String = FIREWORK_RAMPS[i % FIREWORK_RAMPS.size()]
	var pts := vfx.arc_points(from, to, 5.0, 16)
	vfx.ribbon(pts, body(ramp, 1.3), 0.14, flight + 0.25)
	vfx.ribbon(pts, pal(ramp, 0), 0.05, flight + 0.15)
	vfx.emit_one("v_flare", from, Vector3.ZERO, rc(ramp), 0.9, 0.6)
	vfx.every_frame(flight, func(k: float) -> void:
		var idx := clampi(int(k * (pts.size() - 1)), 0, pts.size() - 1)
		var p: Vector3 = pts[idx]
		if _rate(60.0):
			vfx.emit_one("ember", p, Vector3(randf_range(-0.6, 0.6), -1.5, randf_range(-0.6, 0.6)), Color(1.0, 0.75, 0.4), 1.0, 0.6)
		if _rate(30.0):
			vfx.emit_one("v_glow", p, Vector3.ZERO, rc(ramp), 0.9, 0.25))


## A shell bursts: a sphere of coloured sparks. On a runner (`hit`) the shell bursts a few
## metres above it and its core streaks down onto the runner.
func firework_burst(at: Vector3, i: int, hit: bool) -> void:
	var ramp: String = FIREWORK_RAMPS[i % FIREWORK_RAMPS.size()]
	var col := body(ramp, 1.0)
	var shell := at + (Vector3(0, 3.2, 0) if hit else Vector3.ZERO)
	vfx.emit_one("flash", shell, Vector3.ZERO, Color(col.lerp(Color.WHITE, 0.4), 0.9), 3.2, 1.0)
	vfx.emit_one("v_glow", shell, Vector3.ZERO, rc(ramp), 5.0, 1.0)
	vfx.emit_one("ring", shell, Vector3.ZERO, pal(ramp, 1), 4.2, 1.0)
	for k in vfx._count(46):
		var d := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(-1, 1)).normalized()
		vfx.emit_one("v_spark", shell, d * randf_range(8.0, 12.0), rc(ramp), 1.5, 1.3)
	vfx.emit("v_ember", shell, 12, rc(ramp), 4.0, 0.8, 1.0, 1.1, 1.5)
	vfx.flash_light(shell, col, 4.0, 14.0, 0.3)
	if hit:
		vfx.ribbon(PackedVector3Array([shell, shell.lerp(at, 0.5), at]), body(ramp, 1.3), 0.2, 0.3, 0.0, true)
		punch(at, ramp, 1.3, 8, 1.2, true)


## The grand finale: three huge shells over the crowd, gold willow embers raining down and a
## blast on the ground.
func fireworks_finale(center: Vector3, r: float) -> void:
	var g := _flat(center)
	legend_accent(g + Vector3(0, 4.0, 0), "crimson", 1.2)
	for j in 3:
		var ramp: String = ["crimson", "solar", "sky"][j]
		var top := g + Vector3((j - 1) * 3.0, 5.0 + j * 1.0, 0)
		vfx.after(j * 0.12, func() -> void:
			firework_burst(top, FIREWORK_RAMPS.find(ramp), false)
			for k in vfx._count(30):
				var d := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)).normalized()
				vfx.emit_one("spark", top, d * randf_range(9.0, 13.0), body(ramp, 1.0).lerp(Color.WHITE, 0.25), 2.6, 2.0))
	vfx.after(0.3, func() -> void:
		impact_flash(g + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.75), 2.4, 10.0, 14)
		punch(g + Vector3(0, 1.0, 0), "crimson", 2.6, 24, 2.0, false)
		vfx.shockwave(g, r * 1.2, body("crimson", 1.3), 0.6, 0.08)
		vfx.shockwave(g, r * 1.6, body("solar", 1.1), 0.8, 0.04, 0.08)
		vv.ground_glow(g, r, "crimson", 1.8, 0.9)
		vfx.ground_fx("rays", g, r, Color(1.0, 0.35, 0.65, 0.6), Color(1.0, 0.9, 0.6), 1.2)
		vfx.burst("confetti", g + Vector3(0, 6, 0))
		vfx.text_popup(g + Vector3(0, 5.0, 0), "GRAND FINALE!", Color(1.0, 0.75, 0.9), 1.5, 1.3))
	vfx.every_frame(1.6, func(k: float) -> void:
		if _rate(60.0 * (1.0 - k)):
			var off := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * r
			vfx.emit_one("ember", g + Vector3(off.x, randf_range(6.0, 10.0), off.y), Vector3(0, -2.5, 0), Color(1.0, 0.8, 0.35), 1.3, 1.2), 0.25)


## Ground Rule Double: the ball bounces over the wall in gold: a "2X" over the plate and a
## gold ring there while charges are left this inning.
func ground_rule_double(n: int) -> void:
	var h := Field.HOME + Vector3(0, 0, -1.5)
	legend_accent(h + Vector3(0, 3.0, 0), "gold")
	punch(h + Vector3(0, 1.4, 0), "gold", 2.2, 22, 1.8)
	vfx.shockwave(h, 16.0, body("gold", 1.3), 0.6, 0.05)
	vfx.shockwave(h, 9.0, body("legend", 1.1), 0.5, 0.06, 0.12)
	vfx.beam(h, 1.4, 14.0, GOLD, 0.9)
	vfx.flash_light(h + Vector3(0, 4.0, 0), GOLD, 5.0, 24.0, 0.6)
	vfx.text_popup(h + Vector3(0, 6.0, 0), "%dX" % 2, Color(1.0, 0.88, 0.4), 2.4, 1.6)
	vfx.text_popup(h + Vector3(0, 4.4, 0), "NEXT %d CARDS" % n, Color(1.0, 0.95, 0.75), 1.0, 1.6)
	# Two balls orbit the plate: the doubled cast.
	for side in [0.0, PI]:
		for i in 14:
			var a: float = side + i * 0.45
			var p := h + Vector3(cos(a) * 1.6, 0.6 + i * 0.28, sin(a) * 1.6)
			vfx.after(i * 0.03, func() -> void:
				vfx.emit_one("glow", p, Vector3(0, 0.8, 0), Color(GOLD, 0.9), 1.0, 0.6)
				vfx.emit_one("v_mote", p, Vector3(cos(a + 1.6), 1.0, sin(a + 1.6)) * 2.0, rc("gold"), 0.9, 0.8))
	var cs: CardSystem = battle.cards
	var inning: int = battle.run.inning
	var armed := func() -> bool: return cs != null and cs.double_casts_left(inning) > 0
	_live_ring(h, null, 2.8, Color(GOLD, 0.95), 90.0, armed, 2.0, 1.6)


## A doubled card: a gold "x2" and a ring at the target that fills until the echo lands.
func double_mark(card_id: String, at: Vector3, delay: float) -> void:
	var g := _flat(at)
	var m: Node3D = vfx.telegraph(g, 2.2, Color(GOLD, 0.9), delay)
	vfx.after(delay + 0.02, func() -> void:
		if is_instance_valid(m):
			m.queue_free())
	vfx.text_popup(g + Vector3(0, 3.4, 0), "x2", Color(1.0, 0.88, 0.4), 1.4, delay + 0.3)
	vfx.emit_one("v_flare", g + Vector3(0, 1.0, 0), Vector3.ZERO, rc("gold"), 0.9, 0.7)


## The echo goes off: a gold flare at the target.
func double_go(card_id: String, at: Vector3) -> void:
	var g := _flat(at)
	punch(g + Vector3(0, 1.0, 0), "gold", 1.3, 12, 0.8, true)
	vfx.radial_streaks(g + Vector3(0, 1.0, 0), 8, body("gold", 1.3), 7.0, 0.8, 0.4)
	vfx.text_popup(g + Vector3(0, 2.8, 0), "DOUBLE!", Color(1.0, 0.86, 0.35), 1.1, 0.9)
