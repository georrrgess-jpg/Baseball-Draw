extends SceneTree
# Checks the special nodes / materials the game relies on.
var fails := 0

func check(cond: bool, msg: String) -> void:
	print(("PASS  " if cond else "FAIL  ") + msg)
	if not cond:
		fails += 1

func load_prop(n: String) -> Node3D:
	var ps: PackedScene = load("res://assets/models/props/" + n + ".glb")
	return ps.instantiate() as Node3D

func mat_names(mi: MeshInstance3D) -> Array:
	var out := []
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		out.append(m.resource_name if m else "")
	return out

func surface_of(mi: MeshInstance3D, mname: String) -> int:
	for s in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(s)
		if m and m.resource_name == mname:
			return s
	return -1

func uv_report(mi: MeshInstance3D, s: int) -> Dictionary:
	var arr := mi.mesh.surface_get_arrays(s)
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var p00 := Vector3.ZERO
	var p11 := Vector3.ZERO
	for i in uv.size():
		lo = lo.min(uv[i]); hi = hi.max(uv[i])
		if uv[i].distance_to(Vector2(0, 0)) < 1e-4: p00 = vtx[i]
		if uv[i].distance_to(Vector2(1, 1)) < 1e-4: p11 = vtx[i]
	var idx = arr[Mesh.ARRAY_INDEX]
	return {"lo": lo, "hi": hi, "p00": p00, "p11": p11, "verts": vtx.size(), "tris": (idx.size() / 3) if idx else 0, "n0": nrm[0]}

func _initialize() -> void:
	# ---------------- gate
	var g := load_prop("gate")
	for n in ["DoorL", "DoorR", "Beacon"]:
		check(g.has_node(n), "gate: node %s exists (path '%s', class %s)" % [n, n, g.get_node(n).get_class() if g.has_node(n) else "-"])
	var dl: Node3D = g.get_node("DoorL")
	var dr: Node3D = g.get_node("DoorR")
	check(dl.position.is_equal_approx(Vector3(-3, 0, 0.55)), "gate: DoorL pivot at outer hinge %s" % dl.position)
	check(dr.position.is_equal_approx(Vector3(3, 0, 0.55)), "gate: DoorR pivot at outer hinge %s" % dr.position)
	var al: AABB = (dl as MeshInstance3D).mesh.get_aabb()
	var ar: AABB = (dr as MeshInstance3D).mesh.get_aabb()
	check(al.position.x > -0.1 and al.end.x > 2.9, "gate: DoorL leaf extends +X from hinge (%.2f..%.2f)" % [al.position.x, al.end.x])
	check(ar.end.x < 0.1 and ar.position.x < -2.9, "gate: DoorR leaf extends -X from hinge (%.2f..%.2f)" % [ar.position.x, ar.end.x])
	# open test: the far edge must move toward +Z (field)
	var far_l := Basis(Vector3.UP, deg_to_rad(-90)) * Vector3(3, 0, 0)
	var far_r := Basis(Vector3.UP, deg_to_rad(90)) * Vector3(-3, 0, 0)
	check(far_l.z > 2.9 and far_r.z > 2.9, "gate: DoorL rot.y=-90deg and DoorR rot.y=+90deg swing the leaves toward +Z (%.2f, %.2f)" % [far_l.z, far_r.z])
	var bm := mat_names(g.get_node("Beacon"))
	var be: StandardMaterial3D = (g.get_node("Beacon") as MeshInstance3D).mesh.surface_get_material(bm.find("BeaconEmissive"))
	check(be != null and be.emission_enabled, "gate: Beacon has emissive material BeaconEmissive (energy %.1f) at %s" % [be.emission_energy_multiplier if be else 0.0, (g.get_node("Beacon") as Node3D).position])
	g.free()
	# ---------------- gate variants: identical special nodes + stencil label
	for gv in ["gate_a", "gate_b", "gate_c", "gate_d"]:
		var gg := load_prop(gv)
		var ok := gg.has_node("DoorL") and gg.has_node("DoorR") and gg.has_node("Beacon") and gg.has_node("Stencil")
		ok = ok and (gg.get_node("DoorL") as Node3D).position.is_equal_approx(Vector3(-3, 0, 0.55))
		ok = ok and (gg.get_node("DoorR") as Node3D).position.is_equal_approx(Vector3(3, 0, 0.55))
		ok = ok and (gg.get_node("Beacon") as Node3D).position.is_equal_approx(Vector3(0, 6, 0))
		check(ok, "%s: DoorL/DoorR/Beacon/Stencil present at the same pivots as gate.glb" % gv)
		gg.free()
	# ---------------- scoreboard
	var sb := load_prop("scoreboard")
	check(sb.has_node("Screen"), "scoreboard: node Screen exists")
	var scr: MeshInstance3D = sb.get_node("Screen")
	var si := surface_of(scr, "Screen")
	check(si == 0 and scr.mesh.get_surface_count() == 1, "scoreboard: Screen has single surface with material 'Screen'")
	var r := uv_report(scr, si)
	check(r.lo.is_equal_approx(Vector2.ZERO) and r.hi.is_equal_approx(Vector2.ONE), "scoreboard: Screen UV range %s..%s" % [r.lo, r.hi])
	print("      Screen node pos %s, UV(0,0) at local %s (top-left), UV(1,1) at %s, normal %s, AABB %s" % [scr.position, r.p00, r.p11, r.n0, scr.mesh.get_aabb()])
	check(r.p00.x < 0 and r.p00.y > 0 and r.n0.z > 0.99, "scoreboard: UV(0,0) is top-left seen from the field, faces +Z")
	sb.free()
	# ---------------- banner
	var bp := load_prop("banner_pole")
	check(bp.has_node("Banner"), "banner_pole: node Banner exists")
	var ban: MeshInstance3D = bp.get_node("Banner")
	var bi := surface_of(ban, "Banner")
	var br := uv_report(ban, bi)
	check(bi == 0, "banner_pole: Banner material 'Banner'")
	check(br.lo.is_equal_approx(Vector2.ZERO) and br.hi.is_equal_approx(Vector2.ONE), "banner_pole: Banner UV range %s..%s" % [br.lo, br.hi])
	check(br.tris >= 12 * 8 * 2, "banner_pole: Banner subdivided (%d tris, %d verts)" % [br.tris, br.verts])
	var bmat: StandardMaterial3D = ban.mesh.surface_get_material(bi)
	check(bmat.cull_mode == BaseMaterial3D.CULL_DISABLED, "banner_pole: Banner material double-sided")
	print("      Banner node pos %s, UV(0,0) at local %s, UV(1,1) at local %s, AABB %s" % [ban.position, br.p00, br.p11, ban.mesh.get_aabb()])
	bp.free()
	# ---------------- light tower
	var lt := load_prop("light_tower")
	check(lt.has_node("LightAnchor"), "light_tower: node LightAnchor exists (%s)" % (lt.get_node("LightAnchor").get_class() if lt.has_node("LightAnchor") else "-"))
	var la: Node3D = lt.get_node("LightAnchor")
	print("      LightAnchor pos %s rot %s" % [la.position, la.rotation_degrees])
	var tower: MeshInstance3D = lt.get_node("LightTower")
	var li := surface_of(tower, "LampEmissive")
	var lm: StandardMaterial3D = tower.mesh.surface_get_material(li)
	check(li >= 0 and lm.emission_enabled, "light_tower: LampEmissive material emissive (energy %.1f, %d tris)" % [lm.emission_energy_multiplier, uv_report(tower, li).tris])
	var sp_basis := Basis.from_euler(Vector3(deg_to_rad(-24), deg_to_rad(180), 0))
	print("      a SpotLight3D child with rotation_degrees (-24,180,0) points along %s" % (sp_basis * Vector3(0, 0, -1)))
	lt.free()
	# ---------------- container / buildings
	var ct := load_prop("container")
	check(surface_of(ct.get_node("Container"), "Container") >= 0, "container: material 'Container' present (node path 'Container')")
	ct.free()
	for b in ["building_a", "building_b", "building_c"]:
		var bn := load_prop(b)
		var mi: MeshInstance3D = bn.get_child(0)
		var wi := surface_of(mi, "Windows")
		var wm: StandardMaterial3D = mi.mesh.surface_get_material(wi) if wi >= 0 else null
		check(wi >= 0 and wm.emission_enabled, "%s: emissive 'Windows' material" % b)
		bn.free()
	var fc := load_prop("fence_chain")
	var fm: StandardMaterial3D = (fc.get_child(0) as MeshInstance3D).mesh.surface_get_material(surface_of(fc.get_child(0), "ChainLink"))
	check(fm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and fm.cull_mode == BaseMaterial3D.CULL_DISABLED, "fence_chain: ChainLink is alpha-scissor + double-sided")
	fc.free()
	# ---------------- grandstand seat rows (measured from seat-pan top faces)
	var gs := load_prop("grandstand")
	check(gs.has_node("Grandstand") and gs.has_node("Canopy"), "grandstand: nodes Grandstand + Canopy")
	var gm: MeshInstance3D = gs.get_node("Grandstand")
	var rows := {}
	for mname in ["SeatNavy", "SeatScarlet"]:
		var s := surface_of(gm, mname)
		var arr := gm.mesh.surface_get_arrays(s)
		var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for t in range(0, idx.size(), 3):
			var a := vtx[idx[t]]; var b := vtx[idx[t + 1]]; var c := vtx[idx[t + 2]]
			var n := nrm[idx[t]]
			if n.y > 0.99 and absf(a.y - b.y) < 1e-3 and absf(a.y - c.y) < 1e-3:
				var key := snappedf(a.y, 0.01)
				if not rows.has(key): rows[key] = [1e9, -1e9, 1e9, -1e9]
				var rr: Array = rows[key]
				for p in [a, b, c]:
					rr[0] = min(rr[0], p.x); rr[1] = max(rr[1], p.x); rr[2] = min(rr[2], p.z); rr[3] = max(rr[3], p.z)
	var keys := rows.keys()
	keys.sort()
	check(keys.size() == 10, "grandstand: 10 seat rows found")
	for k in keys.size():
		var rr: Array = rows[keys[k]]
		print("      row %d: seat-pan top y=%.2f  x %.2f..%.2f  pan z %.2f..%.2f (pan centre z %.2f)" % [k, keys[k], rr[0], rr[1], rr[2], rr[3], (rr[2] + rr[3]) / 2])
	gs.free()
	print("verify: %d failure(s)" % fails)
	quit(1 if fails else 0)
