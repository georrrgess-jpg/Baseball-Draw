extends SceneTree
# Loads every GLB in res://assets/models/props, prints node tree, AABB and materials.
func _dump(n: Node, depth: int, root: Node, out: Array) -> void:
	var line := "  ".repeat(depth) + n.name + " <" + n.get_class() + ">"
	if n is Node3D:
		var t: Transform3D = (n as Node3D).transform
		line += " pos=(%.3f, %.3f, %.3f)" % [t.origin.x, t.origin.y, t.origin.z]
		var e: Vector3 = (n as Node3D).rotation_degrees
		if e.length() > 0.01:
			line += " rot=(%.1f, %.1f, %.1f)" % [e.x, e.y, e.z]
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh := mi.mesh
		var a := mesh.get_aabb()
		line += " aabb_pos=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f)" % [a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z]
		var mats := []
		var tris := 0
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var desc := m.resource_name if m else "<none>"
			if m is StandardMaterial3D:
				var sm := m as StandardMaterial3D
				if sm.emission_enabled:
					desc += "[emis %.1f]" % sm.emission_energy_multiplier
				if sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					desc += "[transp %d]" % sm.transparency
				if sm.cull_mode == BaseMaterial3D.CULL_DISABLED:
					desc += "[2side]"
				if sm.normal_enabled:
					desc += "[nrm]"
			mats.append(desc)
			var arr := mesh.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if idx else (arr[Mesh.ARRAY_VERTEX].size() / 3)
		line += " tris=%d mats=%s" % [tris, ", ".join(mats)]
	out.append(line)
	for c in n.get_children():
		_dump(c, depth + 1, root, out)

func _global_aabb(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		if acc[0] == null:
			acc[0] = a
		else:
			acc[0] = (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_global_aabb(c, t, acc)

func _initialize() -> void:
	var dir := DirAccess.open("res://assets/models/props")
	var files := []
	for f in dir.get_files():
		if f.ends_with(".glb"):
			files.append(f)
	files.sort()
	for f in files:
		var ps: PackedScene = load("res://assets/models/props/" + f)
		if ps == null:
			print("FAILED to load ", f)
			continue
		var inst := ps.instantiate()
		var out := []
		_dump(inst, 0, inst, out)
		var acc := [null]
		_global_aabb(inst, Transform3D.IDENTITY, acc)
		var a: AABB = acc[0]
		print("=== ", f, "  AABB pos=(%.2f, %.2f, %.2f) size=(%.2f, %.2f, %.2f)" % [a.position.x, a.position.y, a.position.z, a.size.x, a.size.y, a.size.z])
		for l in out:
			print(l)
		inst.free()
	quit()
