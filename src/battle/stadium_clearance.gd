class_name StadiumClearance
extends RefCounted
## Geometry verification for the enemy gates (Update 12).
##
## Collects every triangle of a built stadium in world space and checks, for every gate, that no
## stadium geometry (walls, stands, crowd, posts, foul poles, ad boards, light towers, dugouts,
## signage, skyline, tunnels...) intrudes into:
##   * the doorway opening;
##   * the volume each door sweeps while it opens (sampled every 10 degrees);
##   * the tunnel space behind the gate where runners appear;
##   * the runner and boss corridors along every route from the back of the tunnel to 8 m out.
## Runs in the system suite (tests/test_suite.gd, `test_stadium_clearance`) and as a report tool:
##   godot --headless --path . res://tests/stadium_check.tscn

const DOORWAY_HALF := Vector3(2.95, 0.0, 0.8)   # x half width, z half depth (y from FLOOR to the header)
const DOORWAY_TOP := 4.85
const FLOOR := 0.1             # walkable: ground, floor paint, the 8.5 cm door threshold
const CORRIDOR_OUT := 8.0      # metres of route checked beyond the doorway
const SPAWN_HALF_W := 2.6      # half width of the spawn area behind the gate
const MIN_RUNNER := Vector2(1.6, 2.5)   # minimum corridor width / height (runners)
const DOOR_OPEN_DEG := 100.0
const GAP := 1.0               # clear space checked around every tunnel

## A volume: an oriented box in world space.
class Vol:
	var name := ""
	var gate := ""
	var xf := Transform3D.IDENTITY     # centre + orientation (unit axes)
	var h := Vector3.ONE               # half extents
	var inv := Transform3D.IDENTITY
	var aabb := AABB()
	var own_gate: Node = null          # geometry under this gate is ignored for this volume
	var own_tunnel: Node = null        # ...and geometry of this gate's tunnel

	func _init(p_name: String, p_gate: String, p_xf: Transform3D, p_h: Vector3, p_own: Node = null) -> void:
		name = p_name
		gate = p_gate
		xf = p_xf
		h = p_h
		own_gate = p_own
		inv = xf.affine_inverse()
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var p: Vector3 = xf * Vector3(sx * h.x, sy * h.y, sz * h.z)
					lo = lo.min(p)
					hi = hi.max(p)
		aabb = AABB(lo, hi - lo)


## One piece of stadium geometry: world-space triangles (flat array, 3 vertices per triangle).
class Piece:
	var part := ""
	var node: Node3D
	var tris := PackedVector3Array()
	var aabb := AABB()
	var gate_root: Node = null         # the gate this piece belongs to (if any)
	var tunnel_of: Node = null         # the gate whose tunnel this piece is part of (if any)


## Runner / boss envelopes measured from the real character models (battle scale), plus the
## widest lateral offset a runner can take from its route line (Battle.spawn_enemy).
static func enemy_envelopes() -> Dictionary:
	var out := {"runner": Vector2(MIN_RUNNER.x, MIN_RUNNER.y), "boss": Vector2(MIN_RUNNER.x, MIN_RUNNER.y)}
	for id in DB.enemies.keys():
		var data: Dictionary = DB.enemies[id]
		var model := CharacterModel.new()
		var mid := str(data.get("model", id))
		model.setup(mid, {"scale": Battle.UNIT_SCALE * float(data.get("scale", 1.0)) * (Enemy.fallback_scale_for(id) if not CharacterModel.has_model(mid) else 1.0)})
		# The rest pose is a T-pose: half the arm span is about the width of the running body.
		var box: AABB = model._combined_aabb()
		var body := box.size.x * 0.5 * model.scale.x if box.size.y > 0.1 else model.height * 0.4
		var h := model.height
		model.free()
		var w := 2.0 * (Battle.MAX_LATERAL + body * 0.5)
		var key := "boss" if bool(data.get("boss", false)) else "runner"
		var cur: Vector2 = out[key]
		out[key] = Vector2(maxf(cur.x, w), maxf(cur.y, h + 0.1))
	return out


## Checks a built stadium. Returns a list of intrusions: {gate, zone, part, at}.
static func check(stadium: StadiumBuilder, layout: Dictionary, envelopes: Dictionary) -> Array:
	var vols: Array = []
	var routes: Array[Route] = []
	for r in layout.get("routes", []):
		routes.append(Route.from_points(r.id, r.gate, r.points))
	# Doors open (the pose runners walk past), remembering the rest pose.
	var door_rest := {}
	for gid in stadium.gates.keys():
		var g: Node3D = stadium.gates[gid]
		for dn in ["DoorL", "DoorR"]:
			var door := g.find_child(dn, true, false) as Node3D
			if door:
				door_rest[door] = door.rotation.y
				door.rotation.y = deg_to_rad(-DOOR_OPEN_DEG if dn == "DoorL" else DOOR_OPEN_DEG)
	for gid in stadium.gates.keys():
		var g: Node3D = stadium.gates[gid]
		var gxf := g.global_transform.orthonormalized()
		# Doorway.
		var gs := g.global_transform.basis.get_scale()
		var dh := Vector3(DOORWAY_HALF.x * gs.x, (DOORWAY_TOP * gs.y - FLOOR) * 0.5, DOORWAY_HALF.z * gs.z)
		# (The gate's own frame and doors define the doorway; the corridors check runners against them.)
		vols.append(Vol.new("doorway", gid, gxf * Transform3D(Basis(), Vector3(0, FLOOR + dh.y, 0)), dh, g))
		# Door sweeps.
		for door in door_rest.keys():
			if not g.is_ancestor_of(door):
				continue
			var dbox := _node_local_aabb(door)
			if dbox.size == Vector3.ZERO:
				continue
			var sgn := -1.0 if String(door.name) == "DoorL" else 1.0
			for k in 11:
				door.rotation.y = deg_to_rad(sgn * DOOR_OPEN_DEG * k / 10.0)
				var dxf: Transform3D = door.global_transform.orthonormalized()
				var c := dbox.get_center() * gs
				var hh := dbox.size * 0.5 * gs - Vector3(0.03, 0.03, 0.03)
				var bottom := maxf(c.y - hh.y, FLOOR)
				var top := c.y + hh.y
				c.y = (bottom + top) * 0.5
				hh.y = (top - bottom) * 0.5
				vols.append(Vol.new("%s sweep %d deg" % [door.name, int(DOOR_OPEN_DEG * k / 10.0)], gid, dxf * Transform3D(Basis(), c), hh, g))
			door.rotation.y = deg_to_rad(sgn * DOOR_OPEN_DEG)
		# Spawn area behind the gate (in the gate's frame, -Z is away from the field).
		var depth := Battle.TUNNEL_SPAWN + 1.0
		var sh := Vector3(SPAWN_HALF_W, (envelopes.runner.y - FLOOR) * 0.5, depth * 0.5)
		var route_start := Vector3.ZERO
		for r in routes:
			if r.gate == gid:
				route_start = r.points[0]
		var start_local := gxf.affine_inverse() * route_start
		var z1 := minf(start_local.z, 0.0) - DOORWAY_HALF.z * gs.z
		vols.append(Vol.new("spawn area", gid, gxf * Transform3D(Basis(), Vector3(0, FLOOR + sh.y, z1 - sh.z)), sh, null))
		# The clean gap around the gate's tunnel (stands, crowd, towers, signage keep out).
		var tunnel := stadium.root.get_node_or_null("Tunnel_" + str(gid))
		if tunnel:
			var z_front := -StadiumBuilder.GATE_HALF_D - 0.3
			var z_back := -StadiumBuilder.GATE_HALF_D - StadiumBuilder.TUNNEL_LEN - 0.6 - GAP
			var gh := Vector3(StadiumBuilder.GATE_HALF_W + GAP, (StadiumBuilder.TUNNEL_ROOF + 2.6 - FLOOR) * 0.5, (z_front - z_back) * 0.5)
			var gv := Vol.new("tunnel clearance", gid, gxf * Transform3D(Basis(), Vector3(0, FLOOR + gh.y, (z_front + z_back) * 0.5)), gh, g)
			gv.own_tunnel = g
			vols.append(gv)
	# Route corridors: from the back of the tunnel to CORRIDOR_OUT beyond the doorway.
	for r in routes:
		var g: Node3D = stadium.gates.get(r.gate)
		for kind in ["runner", "boss"]:
			var env: Vector2 = envelopes[kind]
			var d := -Battle.TUNNEL_SPAWN
			var step := 0.75
			while d < CORRIDOR_OUT - 0.01:
				var a := r.entry_position(d)
				var b := r.entry_position(d + step)
				var mid := (a + b) * 0.5
				var fwd := b - a
				fwd.y = 0
				fwd = fwd.normalized()
				var side := Vector3(-fwd.z, 0, fwd.x)
				var basis := Basis(side, Vector3.UP, fwd)
				var h := Vector3(env.x * 0.5, (env.y - FLOOR) * 0.5, step * 0.5 + 0.05)
				vols.append(Vol.new("%s corridor (%s, %.1f m)" % [r.id, kind, d], r.gate, Transform3D(basis, mid + Vector3(0, FLOOR + h.y, 0)), h, null))
				d += step
	# Geometry.
	var pieces := _collect(stadium.root, stadium)
	var hits := []
	var seen := {}
	for v: Vol in vols:
		for p: Piece in pieces:
			if v.own_gate != null and p.gate_root == v.own_gate:
				continue
			if v.own_tunnel != null and p.tunnel_of == v.own_tunnel:
				continue
			if not p.aabb.intersects(v.aabb):
				continue
			var at := _first_hit(p.tris, v)
			if at == Vector3.INF:
				continue
			var key := "%s|%s|%s" % [v.gate, _zone_group(v.name), p.part]
			if seen.has(key):
				continue
			seen[key] = true
			hits.append({"gate": v.gate, "zone": v.name, "part": p.part, "at": at})
	for door in door_rest.keys():
		door.rotation.y = door_rest[door]
	return hits


## "left corridor (runner, 2.3 m)" -> "left corridor (runner)" so a report lists each part once per zone.
static func _zone_group(n: String) -> String:
	var i := n.find(", ")
	if i > 0:
		return n.substr(0, i) + ")"
	var j := n.find(" sweep")
	if j > 0:
		return n.substr(0, j + 6)
	return n


static func _node_local_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var inv := n.global_transform.affine_inverse()
	for mi in _meshes(n):
		var b: AABB = (inv * mi.global_transform) * mi.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as MeshInstance3D).visible:
		out.append(n)
	for c in n.get_children():
		if c is Node3D and not (c as Node3D).visible:
			continue
		out.append_array(_meshes(c))
	return out


## Every visible mesh (and every crowd fan, as a box) in world space, labelled by stadium part.
static func _collect(root: Node3D, stadium: StadiumBuilder) -> Array:
	var gate_of := {}
	for gid in stadium.gates.keys():
		gate_of[stadium.gates[gid]] = true
	var out: Array = []
	_collect_node(root, root, gate_of, null, out)
	return out


static func _collect_node(n: Node, root: Node3D, gate_of: Dictionary, gate_root: Node, out: Array, tunnel_of: Node = null) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if gate_of.has(n):
		gate_root = n
	if n.has_meta("tunnel_of"):
		tunnel_of = n.get_meta("tunnel_of")
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mi := n as MeshInstance3D
		var faces := _faces(mi.mesh)
		if faces.size() > 0:
			var p := Piece.new()
			p.node = mi
			p.part = part_name(mi, root)
			p.gate_root = gate_root
			p.tunnel_of = tunnel_of
			p.tris = mi.global_transform * faces
			p.aabb = mi.global_transform * mi.mesh.get_aabb()
			if p.aabb.end.y > FLOOR:
				out.append(p)
	elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		if mm.mesh:
			var box := mm.mesh.get_aabb()
			var p := Piece.new()
			p.node = mmi
			p.part = part_name(mmi, root)
			p.gate_root = gate_root
			p.tunnel_of = tunnel_of
			var tris := PackedVector3Array()
			var lo := Vector3.INF
			var hi := -Vector3.INF
			for i in mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count:
				var xf := mmi.global_transform * mm.get_instance_transform(i)
				var bt := _box_tris(box)
				var wt := xf * bt
				tris.append_array(wt)
				var wb: AABB = xf * box
				lo = lo.min(wb.position)
				hi = hi.max(wb.end)
			p.tris = tris
			p.aabb = AABB(lo, hi - lo)
			out.append(p)
	for c in n.get_children():
		_collect_node(c, root, gate_of, gate_root, out, tunnel_of)


static var _face_cache := {}
static var _box_cache := {}


static func _faces(mesh: Mesh) -> PackedVector3Array:
	if not _face_cache.has(mesh):
		_face_cache[mesh] = mesh.get_faces()
	return _face_cache[mesh]


static func _box_tris(b: AABB) -> PackedVector3Array:
	if _box_cache.has(b):
		return _box_cache[b]
	var c: Array[Vector3] = []
	for i in 8:
		c.append(b.position + Vector3(b.size.x * (i & 1), b.size.y * ((i >> 1) & 1), b.size.z * ((i >> 2) & 1)))
	var idx := [0, 1, 3, 0, 3, 2, 4, 6, 7, 4, 7, 5, 0, 4, 5, 0, 5, 1, 2, 3, 7, 2, 7, 6, 0, 2, 6, 0, 6, 4, 1, 5, 7, 1, 7, 3]
	var out := PackedVector3Array()
	for k in idx:
		out.append(c[k])
	_box_cache[b] = out
	return out


## The stadium part a node belongs to: the nearest "part" meta up the tree, else its top-level node's name.
static func part_name(n: Node, root: Node) -> String:
	if n is MultiMeshInstance3D and String(n.name).begins_with("Crowd"):
		return "crowd"
	var cur := n
	var top := n
	while cur and cur != root:
		if cur.has_meta("part"):
			return str(cur.get_meta("part"))
		top = cur
		cur = cur.get_parent()
	return String(top.name).trim_prefix("@").get_slice("@", 0)


## First triangle centre (world) that intrudes into the volume, or Vector3.INF.
static func _first_hit(tris: PackedVector3Array, v: Vol) -> Vector3:
	var lo := v.aabb.position
	var hi := v.aabb.end
	var n := tris.size()
	var i := 0
	while i < n:
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		i += 3
		if maxf(a.y, maxf(b.y, c.y)) < FLOOR:
			continue
		if minf(a.x, minf(b.x, c.x)) > hi.x or maxf(a.x, maxf(b.x, c.x)) < lo.x:
			continue
		if minf(a.z, minf(b.z, c.z)) > hi.z or maxf(a.z, maxf(b.z, c.z)) < lo.z:
			continue
		if minf(a.y, minf(b.y, c.y)) > hi.y or maxf(a.y, maxf(b.y, c.y)) < lo.y:
			continue
		if tri_box(v.inv * a, v.inv * b, v.inv * c, v.h):
			return (a + b + c) / 3.0
	return Vector3.INF


## Triangle vs axis-aligned box centred at the origin with half extents h (separating axis test).
static func tri_box(v0: Vector3, v1: Vector3, v2: Vector3, h: Vector3) -> bool:
	if minf(v0.x, minf(v1.x, v2.x)) > h.x or maxf(v0.x, maxf(v1.x, v2.x)) < -h.x:
		return false
	if minf(v0.y, minf(v1.y, v2.y)) > h.y or maxf(v0.y, maxf(v1.y, v2.y)) < -h.y:
		return false
	if minf(v0.z, minf(v1.z, v2.z)) > h.z or maxf(v0.z, maxf(v1.z, v2.z)) < -h.z:
		return false
	var e0 := v1 - v0
	var e1 := v2 - v1
	var e2 := v0 - v2
	var nrm := e0.cross(e1)
	if nrm.length_squared() < 1e-12:
		return true   # degenerate sliver inside the box bounds
	var r := h.x * absf(nrm.x) + h.y * absf(nrm.y) + h.z * absf(nrm.z)
	if absf(nrm.dot(v0)) > r:
		return false
	for e in [e0, e1, e2]:
		for ax in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]:
			var axis: Vector3 = (ax as Vector3).cross(e)
			if axis.length_squared() < 1e-12:
				continue
			var p0 := axis.dot(v0)
			var p1 := axis.dot(v1)
			var p2 := axis.dot(v2)
			var rr := h.x * absf(axis.x) + h.y * absf(axis.y) + h.z * absf(axis.z)
			if minf(p0, minf(p1, p2)) > rr or maxf(p0, maxf(p1, p2)) < -rr:
				return false
	return true


## Size of the last stadium check_arena built (performance budget): meshes, lights, fans, stands.
static var last_stats := {}


static func _count(n: Node, cls: String) -> int:
	var c := 1 if n.is_class(cls) else 0
	for k in n.get_children():
		c += _count(k, cls)
	return c


## Builds an arena's stadium under `parent` (no gameplay), checks it and frees it.
static func check_arena(parent: Node, arena_id: String, envelopes: Dictionary) -> Array:
	var holder := Node3D.new()
	holder.name = "ClearanceCheck"
	parent.add_child(holder)
	var sb := StadiumBuilder.new()
	if sb == null:
		holder.free()
		return [{"gate": "-", "zone": "build", "part": "StadiumBuilder failed to load", "at": Vector3.ZERO}]
	var layout := DB.layout_for_arena(arena_id)
	sb.build(holder, DB.arena(arena_id), layout, false)
	var hits := check(sb, layout, envelopes)
	last_stats = {"meshes": _count(sb.root, "MeshInstance3D"), "lights": _count(sb.root, "OmniLight3D") + _count(sb.root, "SpotLight3D"),
		"fans": sb.crowd.fan_count if sb.crowd else 0, "stands": sb.root.get_children().filter(func(c: Node) -> bool: return str(c.get_meta("part", "")) == "grandstand").size()}
	# A stadium that failed to build has nothing to intrude: report that as a failure too.
	if sb.gates.size() != layout.get("gates", {}).size() or sb.root == null or sb.root.get_child_count() < 20:
		hits.append({"gate": "-", "zone": "build", "part": "stadium incomplete (%d of %d gates)" % [sb.gates.size(), layout.get("gates", {}).size()], "at": Vector3.ZERO})
	holder.free()
	return hits


static func format_report(arena_id: String, hits: Array) -> String:
	var lines: Array[String] = ["%s: %d intrusion(s)" % [arena_id, hits.size()]]
	for h in hits:
		var at: Vector3 = h.at
		lines.append("  gate %s  %-34s <- %s  at (%.1f, %.1f, %.1f)" % [h.gate, _zone_group(h.zone), h.part, at.x, at.y, at.z])
	return "\n".join(lines)
