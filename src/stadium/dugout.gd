class_name StadiumDugout
extends RefCounted
## Procedural dugout: concrete pit, team-colour back wall and padded front lip, roof with a painted
## top and fascia, support posts, bench, railing, steps, bat rack, water cooler with cups, and a few
## players (the crowd fan mesh in uniform colours) sitting on the bench or leaning on the rail.
## The structure is one vertex-coloured mesh (one draw call); players are one MultiMesh.
## Local frame: +Z faces the field, origin on the ground at the middle of the front of the roof.

const W := 8.6
const ROOF_Y := 2.25


static var _vc_mat: StandardMaterial3D


static func vc_material() -> StandardMaterial3D:
	if _vc_mat == null:
		_vc_mat = StandardMaterial3D.new()
		_vc_mat.vertex_color_use_as_albedo = true
		_vc_mat.vertex_color_is_srgb = true
		_vc_mat.roughness = 0.78
	return _vc_mat


## colors: {team, trim, roof, pants, cap}; label: text painted on the roof.
static func build(colors: Dictionary, label: String, steps_right: bool, rng: RandomNumberGenerator,
		seated_mat: ShaderMaterial, standing_mat: ShaderMaterial) -> Node3D:
	var root := Node3D.new()
	root.name = "Dugout"
	var k := MeshKit.new()
	var team: Color = colors.team
	var trim: Color = colors.trim
	var roof: Color = colors.get("roof", team)
	var conc := Color(0.46, 0.46, 0.48)
	var conc_dark := Color(0.3, 0.3, 0.33)
	var steel := Color(0.55, 0.58, 0.62)
	var hw := W * 0.5
	# Floor and apron.
	k.color = conc_dark
	k.box_mm(Vector3(-hw - 0.3, 0.0, -2.75), Vector3(hw + 0.3, 0.05, 1.25), ["-y"])
	k.color = Color(0.36, 0.25, 0.17)
	k.box_mm(Vector3(-hw + 0.1, 0.05, -2.3), Vector3(hw - 0.1, 0.07, 0.75), ["-y"])  # rubber mat
	# Back wall: team colour with a trim stripe.
	k.color = team.darkened(0.15)
	k.box_mm(Vector3(-hw - 0.3, 0.0, -2.75), Vector3(hw + 0.3, ROOF_Y, -2.5), ["-y"])
	k.color = trim
	k.box_mm(Vector3(-hw, 1.15, -2.52), Vector3(hw, 1.32, -2.48), ["-y", "-z"])
	# Side walls (concrete) with hazard caps.
	for sx in [-1.0, 1.0]:
		k.color = conc
		k.box_mm(Vector3(minf(sx * hw, sx * (hw + 0.3)), 0.0, -2.75), Vector3(maxf(sx * hw, sx * (hw + 0.3)), ROOF_Y, 0.1), ["-y"])
	# Roof slab: painted top, darker underside, fascia with a trim stripe.
	k.color = roof
	k.box_mm(Vector3(-hw - 0.45, ROOF_Y, -2.95), Vector3(hw + 0.45, ROOF_Y + 0.18, 0.15), ["-y"])
	k.color = conc_dark.darkened(0.2)
	k.box_mm(Vector3(-hw - 0.45, ROOF_Y - 0.02, -2.95), Vector3(hw + 0.45, ROOF_Y, 0.15), ["+y"])
	k.color = team
	k.box_mm(Vector3(-hw - 0.5, ROOF_Y - 0.2, 0.15), Vector3(hw + 0.5, ROOF_Y + 0.26, 0.3), [])
	k.color = trim
	k.box_mm(Vector3(-hw - 0.5, ROOF_Y + 0.06, 0.3), Vector3(hw + 0.5, ROOF_Y + 0.14, 0.32), ["-z"])
	# Roof top: white border lines.
	k.color = Color(0.95, 0.94, 0.9)
	k.box_mm(Vector3(-hw - 0.2, ROOF_Y + 0.18, -0.15), Vector3(hw + 0.2, ROOF_Y + 0.2, -0.05), ["-y"])
	k.box_mm(Vector3(-hw - 0.2, ROOF_Y + 0.18, -2.75), Vector3(hw + 0.2, ROOF_Y + 0.2, -2.65), ["-y"])
	# Roof posts.
	k.color = steel
	for x in [-hw + 0.1, -hw * 0.33, hw * 0.33, hw - 0.1]:
		k.box(Vector3(x, ROOF_Y * 0.5, 0.05), Vector3(0.14, ROOF_Y, 0.14), ["-y", "+y"])
	# Padded front lip in team colour (the dugout's field-side wall), opening for the steps.
	var open_x := hw - 1.3 if steps_right else -hw + 1.3
	var lip0 := -hw if steps_right else open_x
	var lip1 := open_x if steps_right else hw
	k.color = conc
	k.box_mm(Vector3(lip0, 0.0, 0.85), Vector3(lip1, 0.55, 1.05), ["-y"])
	k.color = team
	k.box_mm(Vector3(lip0, 0.55, 0.8), Vector3(lip1, 0.72, 1.1), ["-y"])
	# Railing on the lip.
	k.color = steel
	var x := lip0 + 0.1
	while x <= lip1 - 0.05:
		k.box(Vector3(x, 1.0, 0.95), Vector3(0.05, 0.56, 0.05), ["-y"])
		x += 1.4
	k.box(Vector3(lip1 - 0.05, 1.0, 0.95), Vector3(0.05, 0.56, 0.05), ["-y"])
	k.cyl(Vector3(lip0, 1.27, 0.95), Vector3(lip1, 1.27, 0.95), 0.045, 6)
	# Steps up through the opening.
	k.color = conc.lightened(0.08)
	for i in 3:
		var y := 0.18 * (i + 1)
		var z0 := 0.75 + i * 0.12
		k.box_mm(Vector3(open_x - 0.55 if steps_right else -hw + 0.05, 0.0, z0),
			Vector3(hw - 0.05 if steps_right else open_x + 0.55, y, 1.25), ["-y"])
	k.color = Color(1.0, 0.8, 0.1)
	k.box_mm(Vector3(open_x - 0.55 if steps_right else -hw + 0.05, 0.54, 1.05),
		Vector3(hw - 0.05 if steps_right else open_x + 0.55, 0.56, 1.25), ["-y"])
	# Bench along the back wall.
	k.color = Color(0.55, 0.36, 0.2)
	k.box_mm(Vector3(-hw + 0.6, 0.42, -2.3), Vector3(hw - 1.6, 0.48, -1.88), ["-y"])
	k.box_mm(Vector3(-hw + 0.6, 0.62, -2.48), Vector3(hw - 1.6, 0.9, -2.42), [])
	k.color = Color(0.25, 0.25, 0.28)
	var bx := -hw + 0.8
	while bx < hw - 1.6:
		k.box(Vector3(bx, 0.21, -2.1), Vector3(0.06, 0.42, 0.36), ["-y", "+y"])
		bx += 1.2
	# Water cooler (orange) with a white lid on a crate, and a cup tower.
	var cx := hw - 0.9 if not steps_right else -hw + 0.9
	k.color = Color(0.22, 0.24, 0.3)
	k.box(Vector3(cx, 0.25, -1.6), Vector3(0.6, 0.5, 0.5), ["-y"])
	k.color = Color(1.0, 0.48, 0.08)
	k.cyl(Vector3(cx, 0.5, -1.6), Vector3(cx, 0.98, -1.6), 0.21, 10, false)
	k.color = Color(0.96, 0.96, 0.94)
	k.cyl(Vector3(cx, 0.98, -1.6), Vector3(cx, 1.06, -1.6), 0.22, 10, true)
	k.color = Color(0.92, 0.92, 0.92)
	k.cyl(Vector3(cx + 0.18, 0.62, -1.38), Vector3(cx + 0.18, 0.66, -1.38), 0.03, 5, true)
	k.color = Color(0.95, 0.95, 1.0)
	k.cyl(Vector3(cx - 0.12, 0.5, -1.4), Vector3(cx - 0.12, 0.72, -1.4), 0.045, 6, true)
	# Helmet shelf on the back wall (helmets as small domes in the team colour).
	var hx := -hw + 0.9 if not steps_right else hw - 2.4
	k.color = Color(0.25, 0.25, 0.28)
	k.box_mm(Vector3(hx - 0.1, 1.45, -2.5), Vector3(hx + 1.5, 1.5, -2.2), [])
	k.color = team.lightened(0.05)
	for i in 4:
		k.sphere(Vector3(hx + 0.15 + i * 0.37, 1.5, -2.35), Vector3(0.14, 0.13, 0.15), 6, 3, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "DugoutMesh"
	mi.mesh = k.commit()
	mi.material_override = vc_material()
	root.add_child(mi)
	# Bat rack near the steps (generated prop if available, simple bats otherwise).
	var rack := StadiumBuilder.prop("bat_rack")
	var rack_x := open_x - 1.2 if steps_right else open_x + 1.2
	if rack:
		root.add_child(rack)
		rack.position = Vector3(rack_x, 0.05, 0.45)
		rack.rotation.y = 0.0
	# Roof label (painted team name).
	var lab := Label3D.new()
	lab.text = label
	lab.font = load("res://assets/fonts/RussoOne-Regular.ttf")
	lab.font_size = 96
	lab.outline_size = 0
	lab.modulate = Color(0.8, 0.8, 0.78)
	lab.shaded = true
	lab.double_sided = false
	var text_w := lab.font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, lab.font_size).x
	lab.pixel_size = minf(0.009, (W - 2.6) / maxf(text_w, 1.0))
	lab.rotation = Vector3(-PI / 2, PI, 0)
	lab.position = Vector3(0, ROOF_Y + 0.205, -1.4)
	root.add_child(lab)
	_add_players(root, rng, steps_right, seated_mat, standing_mat, colors)
	return root


static func _add_players(root: Node3D, rng: RandomNumberGenerator, steps_right: bool,
		seated_mat: ShaderMaterial, standing_mat: ShaderMaterial, colors: Dictionary) -> void:
	var hw := W * 0.5
	var jersey: Color = colors.get("jersey", colors.team)
	var seated: Array[Transform3D] = []
	var bench_x := -hw + 1.0
	while bench_x < hw - 1.8:
		if rng.randf() < 0.55:
			seated.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.25, 0.25)), Vector3(bench_x + rng.randf_range(-0.1, 0.1), 0.0, -2.12)))
		bench_x += 0.75
	# Two or three players leaning on the rail, watching the field.
	var leaning: Array[Transform3D] = []
	var lip0 := -hw + 0.4 if steps_right else -hw + 1.9
	var lip1 := hw - 1.9 if steps_right else hw - 0.4
	var n := 2 + rng.randi() % 2
	for i in n:
		var lx := lerpf(lip0, lip1, (i + 0.5 + rng.randf_range(-0.25, 0.25)) / n)
		leaning.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)), Vector3(lx, 0.0, 0.42)))
	for pair in [[seated, seated_mat], [leaning, standing_mat]]:
		var list: Array[Transform3D] = pair[0]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = StadiumCrowd.fan_mesh()
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
			mm.set_instance_color(i, jersey)
			# Variant 4/5: cap, no foam finger.
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf_range(0.3, 0.9), (4 + rng.randi() % 2 + 0.01) / 8.0, 0.5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = pair[1]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 1.5
		root.add_child(mmi)
