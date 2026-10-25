class_name CharacterModel
extends Node3D
## Wraps a rigged character (GLB from assets/models/characters) with a small API:
## looping base animations, one-shot actions that return to the base, uniform
## recolouring, hit flashes / status rims and bone lookups for spawning balls.
## Falls back to a simple procedural figure if the GLB is missing.

signal action_finished(name: String)

const MODEL_DIR := "res://assets/models/characters/"
const LOOPING := ["idle", "run", "sprint", "stunned", "celebrate", "ready", "victory", "walk"]

static var _scene_cache := {}
static var _material_cache := {}
static var _merged_cache := {}
static var _merged_material: ShaderMaterial
static var _overlay: ShaderMaterial

var model_id := ""
var anim: AnimationPlayer
var skeleton: Skeleton3D
var base_anim := "idle"
var action := ""
var _meshes: Array[MeshInstance3D] = []
var _fallback: Node3D
var _fallback_parts := {}
var _fallback_hand: Node3D
var _fallback_t := 0.0
var _flash := 0.0
var _rim := Color(0, 0, 0, 0)
var _overlay_on := false
var _hand_r := -1
var _hand_l := -1
var _head := -1
var _chest := -1
var height := 1.8


static func overlay_material() -> ShaderMaterial:
	if _overlay == null:
		_overlay = ShaderMaterial.new()
		_overlay.shader = load("res://assets/shaders/rim_overlay.gdshader")
	return _overlay


static func has_model(id: String) -> bool:
	return ResourceLoader.exists(MODEL_DIR + id + ".glb")


func setup(id: String, opts: Dictionary = {}) -> void:
	model_id = id
	var path := MODEL_DIR + id + ".glb"
	var packed: PackedScene = null
	if _scene_cache.has(path):
		packed = _scene_cache[path]
	elif ResourceLoader.exists(path):
		packed = load(path)
		_scene_cache[path] = packed
	if packed:
		var inst := packed.instantiate()
		add_child(inst)
		anim = _find(inst, "AnimationPlayer") as AnimationPlayer
		skeleton = _find(inst, "Skeleton3D") as Skeleton3D
		_collect_meshes(inst)
		if skeleton:
			_hand_r = skeleton.find_bone("hand.R")
			_hand_l = skeleton.find_bone("hand.L")
			_head = skeleton.find_bone("head")
			_chest = skeleton.find_bone("chest")
		if anim:
			for a in anim.get_animation_list():
				var res := anim.get_animation(a)
				if a in LOOPING:
					res.loop_mode = Animation.LOOP_LINEAR
				else:
					res.loop_mode = Animation.LOOP_NONE
			anim.animation_finished.connect(_on_anim_finished)
		var aabb := _combined_aabb()
		if aabb.size.y > 0.1:
			height = aabb.size.y
	else:
		_build_fallback(opts)
	if _fallback == null and bool(opts.get("merge", true)):
		_merge_surfaces(opts.get("colors", {}), "%s|%s" % [id, str(opts.get("colors", {}))])
	elif opts.has("colors"):
		recolor(opts.colors, opts.get("cache_key", id))
	if opts.has("shadows"):
		for m in _meshes:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if opts.shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var s: float = opts.get("scale", 1.0)
	if s != 1.0:
		scale = Vector3.ONE * s
		height *= s
	play_base(opts.get("base", "idle"))


func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null


func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D:
		_meshes.append(n)
		(n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_collect_meshes(c)


func _combined_aabb() -> AABB:
	var box := AABB()
	var first := true
	for m in _meshes:
		if m.mesh == null:
			continue
		var b := m.mesh.get_aabb()
		if first:
			box = b
			first = false
		else:
			box = box.merge(b)
	return box


static func merged_material() -> ShaderMaterial:
	if _merged_material == null:
		_merged_material = ShaderMaterial.new()
		_merged_material.shader = load("res://assets/shaders/character_merged.gdshader")
	return _merged_material


## Collapses every opaque material surface of each mesh into one vertex-coloured surface
## (one draw call per character instead of ~15). Uniform colours are baked in, and
## the result is cached per model + colour set so instances share the mesh.
## Transparent surfaces (the Phantom Captain's cape) stay separate with their own material.
func _merge_surfaces(colors: Dictionary, key: String) -> void:
	for mi in _meshes:
		if mi.mesh == null or mi.mesh.get_surface_count() <= 1:
			continue
		var ck := key + "|" + String(mi.name)
		var merged: ArrayMesh = _merged_cache.get(ck)
		if merged == null:
			merged = _build_merged(mi.mesh, colors)
			if merged == null:
				continue
			_merged_cache[ck] = merged
		mi.mesh = merged


static func _build_merged(src: Mesh, colors: Dictionary) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var uv2 := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var indices := PackedInt32Array()
	var use8 := false
	var skinned := false
	for s in src.get_surface_count():
		if src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			use8 = true
	var transparent: Array[int] = []
	for s in src.get_surface_count():
		var mat := src.surface_get_material(s) as BaseMaterial3D
		if mat and (mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or mat.albedo_color.a < 0.99):
			transparent.append(s)
			continue
		var arr := src.surface_get_arrays(s)
		var sv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var base := verts.size()
		var c := Color(0.8, 0.8, 0.8)
		var rough := 0.7
		var metal := 0.0
		var emis := 0.0
		if mat:
			c = mat.albedo_color
			rough = mat.roughness
			metal = mat.metallic
			if mat.emission_enabled:
				emis = clampf(mat.emission_energy_multiplier / 8.0, 0.0, 1.0)
				c = mat.emission if mat.emission.v > c.v else c
			if colors.has(mat.resource_name):
				c = Color(colors[mat.resource_name])
		var lin := c.srgb_to_linear()
		lin.a = emis
		verts.append_array(sv)
		if arr[Mesh.ARRAY_NORMAL] != null:
			normals.append_array(arr[Mesh.ARRAY_NORMAL])
		else:
			var z := PackedVector3Array()
			z.resize(sv.size())
			normals.append_array(z)
		for i in sv.size():
			cols.append(lin)
			uv2.append(Vector2(rough, metal))
		if arr[Mesh.ARRAY_BONES] != null:
			skinned = true
			var b: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var per := 8 if (src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS) else 4
			var want := 8 if use8 else 4
			if per == want:
				bones.append_array(b)
				weights.append_array(w)
			else:
				for v in sv.size():
					for k in want:
						bones.append(b[v * per + k] if k < per else 0)
						weights.append(w[v * per + k] if k < per else 0.0)
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(sv.size()))
		for i in idx:
			indices.append(base + i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	out[Mesh.ARRAY_COLOR] = cols
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = indices
	if skinned:
		out[Mesh.ARRAY_BONES] = bones
		out[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, [], {}, Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if use8 else 0)
	mesh.surface_set_material(0, merged_material())
	for s in transparent:
		var flags: int = src.surface_get_format(s) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s), [], {}, flags)
		mesh.surface_set_material(mesh.get_surface_count() - 1, src.surface_get_material(s))
	return mesh


## Replaces colours of named materials (Jersey, Pants, Cap...) — used for cosmetic uniforms.
func recolor(colors: Dictionary, cache_key: String) -> void:
	for m in _meshes:
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			if mat == null or not colors.has(mat.resource_name):
				continue
			var key := "%s|%s|%s" % [cache_key, mat.resource_name, str(colors[mat.resource_name])]
			var nm: Material = _material_cache.get(key)
			if nm == null:
				nm = mat.duplicate()
				if nm is BaseMaterial3D:
					(nm as BaseMaterial3D).albedo_color = Color(colors[mat.resource_name])
				_material_cache[key] = nm
			m.set_surface_override_material(i, nm)
	if _fallback:
		for k in _fallback_parts.keys():
			var part: MeshInstance3D = _fallback_parts[k]
			var mname: String = part.get_meta("mat", "")
			if colors.has(mname):
				var sm := StandardMaterial3D.new()
				sm.albedo_color = Color(colors[mname])
				sm.roughness = 0.7
				part.material_override = sm


## Makes the whole model translucent (decoys, phantom phase).
func set_ghost(alpha: float, tint := Color(0.7, 0.5, 1.0)) -> void:
	for m in _meshes:
		m.transparency = 1.0 - alpha
	if _fallback:
		for k in _fallback_parts.keys():
			(_fallback_parts[k] as MeshInstance3D).transparency = 1.0 - alpha
	set_rim(Color(tint, 0.9) if alpha < 0.99 else Color(0, 0, 0, 0))


# ---------------------------------------------------------------- animation

func has_anim(name: String) -> bool:
	return anim != null and anim.has_animation(name)


func anim_length(name: String) -> float:
	if has_anim(name):
		return anim.get_animation(name).length
	return {"throw": 0.75, "pitch": 1.4, "catch": 0.6, "special": 1.2, "hit": 0.35, "defeat": 1.2, "leap": 0.8,
		"swing": 1.0, "slam": 1.4, "taunt": 1.5}.get(name, 1.0)


func play_base(name: String, blend := 0.2, speed := 1.0) -> void:
	if not has_anim(name) and anim != null:
		name = "idle" if has_anim("idle") else name
	base_anim = name
	if action == "":
		_play(name, blend, speed)


func set_base_speed(speed: float) -> void:
	if anim and action == "":
		anim.speed_scale = speed


## Plays a non-looping action, then returns to the base loop. Returns its duration.
func play_action(name: String, speed := 1.0, blend := 0.08) -> float:
	if anim != null and not has_anim(name):
		return 0.0
	action = name
	_play(name, blend, speed)
	return anim_length(name) / maxf(speed, 0.01)


func stop_action() -> void:
	if action != "":
		action = ""
		_play(base_anim, 0.15, 1.0)


func _play(name: String, blend: float, speed: float) -> void:
	_fallback_t = 0.0
	if anim == null:
		return
	if not has_anim(name):
		return
	anim.speed_scale = speed
	if anim.current_animation == name and name in LOOPING:
		return
	anim.play(name, blend)
	if not name in LOOPING:
		anim.seek(0.0, true)


func _on_anim_finished(name: StringName) -> void:
	if String(name) == action:
		var finished := action
		action = ""
		if finished != "defeat":
			_play(base_anim, 0.18, 1.0)
		action_finished.emit(finished)


func freeze_animation(frozen: bool) -> void:
	if anim:
		anim.speed_scale = 0.0 if frozen else 1.0


# ---------------------------------------------------------------- bones

func _bone_global(idx: int, fallback_offset: Vector3) -> Vector3:
	if skeleton and idx >= 0:
		return (skeleton.global_transform * skeleton.get_bone_global_pose(idx)).origin
	if _fallback_hand and fallback_offset == Vector3.ZERO:
		return _fallback_hand.global_position
	return global_transform * (fallback_offset * scale.x)


func hand_position() -> Vector3:
	return _bone_global(_hand_r, Vector3.ZERO if _fallback else Vector3(-0.3, 1.5, 0.1))


func glove_position() -> Vector3:
	return _bone_global(_hand_l, Vector3(0.3, 1.2, 0.3))


func head_position() -> Vector3:
	return _bone_global(_head, Vector3(0, height * 0.9 / maxf(scale.x, 0.01), 0))


func chest_position() -> Vector3:
	return _bone_global(_chest, Vector3(0, height * 0.65 / maxf(scale.x, 0.01), 0))


# ---------------------------------------------------------------- feedback

func flash(amount := 1.0) -> void:
	_flash = maxf(_flash, amount)
	_update_overlay()


func set_rim(c: Color) -> void:
	if c == _rim:
		return
	_rim = c
	_update_overlay()


func _update_overlay() -> void:
	var need := _flash > 0.01 or _rim.a > 0.01
	var targets: Array = _meshes if _fallback == null else _fallback_parts.values()
	if need != _overlay_on:
		_overlay_on = need
		for m: MeshInstance3D in targets:
			m.material_overlay = overlay_material() if need else null
	if need:
		for m: MeshInstance3D in targets:
			m.set_instance_shader_parameter("flash", _flash)
			m.set_instance_shader_parameter("rim_color", _rim)


func _process(delta: float) -> void:
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 5.5)
		_update_overlay()
	if _fallback:
		_animate_fallback(delta)


# ---------------------------------------------------------------- fallback figure

func _build_fallback(opts: Dictionary) -> void:
	_fallback = Node3D.new()
	add_child(_fallback)
	var accent: Color = opts.get("accent", Color(0.9, 0.3, 0.2))
	var body_col: Color = opts.get("body", Color("#1C2E4A"))
	var parts := {
		"torso": [Vector3(0, 1.15, 0), Vector3(0.24, 0.36, 0.0), body_col, "Jersey"],
		"head": [Vector3(0, 1.62, 0), Vector3(0.15, 0.0, 0.0), Color("#c68e63"), "Skin"],
		"cap": [Vector3(0, 1.73, 0.02), Vector3(0.155, 0.0, 0.0), body_col, "Cap"],
		"leg_l": [Vector3(0.11, 0.48, 0), Vector3(0.09, 0.5, 0.0), Color("#EDEBE6"), "Pants"],
		"leg_r": [Vector3(-0.11, 0.48, 0), Vector3(0.09, 0.5, 0.0), Color("#EDEBE6"), "Pants"],
		"arm_l": [Vector3(0.33, 1.15, 0), Vector3(0.07, 0.45, 0.0), accent, "Undershirt"],
		"arm_r": [Vector3(-0.33, 1.15, 0), Vector3(0.07, 0.45, 0.0), accent, "Undershirt"],
	}
	for k in parts.keys():
		var spec: Array = parts[k]
		var mi := MeshInstance3D.new()
		if spec[1].y > 0.0:
			var cap := CapsuleMesh.new()
			cap.radius = spec[1].x
			cap.height = spec[1].y + spec[1].x * 2.0
			mi.mesh = cap
		else:
			var sp := SphereMesh.new()
			sp.radius = spec[1].x
			sp.height = spec[1].x * 2.0
			mi.mesh = sp
		var m := StandardMaterial3D.new()
		m.albedo_color = spec[2]
		m.roughness = 0.7
		mi.material_override = m
		mi.position = spec[0]
		mi.set_meta("mat", spec[3])
		_fallback.add_child(mi)
		_fallback_parts[k] = mi
	_fallback_hand = Node3D.new()
	(_fallback_parts["arm_r"] as Node3D).add_child(_fallback_hand)
	_fallback_hand.position = Vector3(0, -0.3, 0.05)


func _animate_fallback(delta: float) -> void:
	_fallback_t += delta
	var t := _fallback_t
	var name := action if action != "" else base_anim
	var arm_r: Node3D = _fallback_parts["arm_r"]
	var arm_l: Node3D = _fallback_parts["arm_l"]
	var leg_l: Node3D = _fallback_parts["leg_l"]
	var leg_r: Node3D = _fallback_parts["leg_r"]
	_fallback.position.y = 0.0
	_fallback.rotation = Vector3.ZERO
	match name:
		"run", "sprint":
			var s := sin(t * 14.0)
			leg_l.rotation.x = s * 0.7
			leg_r.rotation.x = -s * 0.7
			arm_l.rotation.x = -s * 0.8
			arm_r.rotation.x = s * 0.8
			_fallback.position.y = absf(s) * 0.06
			_fallback.rotation.x = 0.15
		"throw", "pitch", "special", "swing", "slam":
			var length := anim_length(name)
			var k := clampf(t / length, 0.0, 1.0)
			arm_r.rotation.x = lerpf(-2.6, 1.2, smoothstep(0.25, 0.5, k))
			_fallback.rotation.y = lerpf(-0.5, 0.4, smoothstep(0.2, 0.5, k))
			if t >= length:
				_finish_fallback_action()
		"defeat":
			_fallback.rotation.x = -clampf(t * 2.5, 0.0, 1.5)
			if t >= 1.2 and action != "":
				_finish_fallback_action()
		"stunned":
			_fallback.rotation.z = sin(t * 6.0) * 0.15
		"celebrate", "victory":
			_fallback.position.y = absf(sin(t * 6.0)) * 0.25
			arm_r.rotation.x = -2.8
			arm_l.rotation.x = -2.8
		_:
			if action != "" and t >= anim_length(action):
				_finish_fallback_action()
			leg_l.rotation.x = 0.0
			leg_r.rotation.x = 0.0
			arm_l.rotation.x = sin(t * 2.0) * 0.05
			arm_r.rotation.x = -sin(t * 2.0) * 0.05
			_fallback.position.y = sin(t * 2.5) * 0.01


func _finish_fallback_action() -> void:
	var finished := action
	action = ""
	_fallback_t = 0.0
	if finished != "":
		action_finished.emit(finished)
