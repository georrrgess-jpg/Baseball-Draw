class_name Route
extends RefCounted
## A runner route: a polyline from an enemy gate to home plate with rounded corners.
## Enemies track progress as a distance along the route.

var id := ""
var gate := ""
var points: PackedVector3Array = PackedVector3Array()
var cumulative: PackedFloat32Array = PackedFloat32Array()
var length := 0.0
## Unrounded corner points (used for drawing route lanes).
var raw_points: PackedVector3Array = PackedVector3Array()


static func from_points(route_id: String, gate_id: String, pts: Array) -> Route:
	var r := Route.new()
	r.id = route_id
	r.gate = gate_id
	var raw: Array[Vector3] = []
	for p in pts:
		raw.append(Vector3(float(p[0]), 0.0, float(p[1])))
	r._build(raw)
	return r


## Rounds corners with short quadratic arcs so runners curve naturally around bases.
func _build(raw: Array[Vector3]) -> void:
	raw_points = PackedVector3Array(raw)
	var out: Array[Vector3] = [raw[0]]
	for i in range(1, raw.size() - 1):
		var prev := raw[i - 1]
		var cur := raw[i]
		var nxt := raw[i + 1]
		var r := minf(1.6, minf(prev.distance_to(cur), cur.distance_to(nxt)) * 0.3)
		var a := cur + (prev - cur).normalized() * r
		var b := cur + (nxt - cur).normalized() * r
		for s in 7:
			var t := float(s) / 6.0
			out.append(a.lerp(cur, t).lerp(cur.lerp(b, t), t))
	out.append(raw[raw.size() - 1])
	points = PackedVector3Array(out)
	cumulative.resize(points.size())
	cumulative[0] = 0.0
	for i in range(1, points.size()):
		cumulative[i] = cumulative[i - 1] + points[i - 1].distance_to(points[i])
	length = cumulative[cumulative.size() - 1]


func _segment(d: float) -> int:
	d = clampf(d, 0.0, length)
	var lo := 0
	var hi := cumulative.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if cumulative[mid] <= d:
			lo = mid
		else:
			hi = mid
	return lo


func position_at(d: float) -> Vector3:
	var i := _segment(d)
	var seg_len := cumulative[i + 1] - cumulative[i]
	var t := 0.0 if seg_len <= 0.0001 else (clampf(d, 0.0, length) - cumulative[i]) / seg_len
	return points[i].lerp(points[i + 1], t)


func direction_at(d: float) -> Vector3:
	var i := _segment(d)
	var dir := points[i + 1] - points[i]
	return dir.normalized() if dir.length_squared() > 0.000001 else Vector3.FORWARD


## Closest distance-along-route to a world point, plus the lateral distance.
func project(p: Vector3) -> Dictionary:
	var best_d := 0.0
	var best_dist := INF
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.000001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * t
		var dist := Vector2(p.x - q.x, p.z - q.z).length()
		if dist < best_dist:
			best_dist = dist
			best_d = cumulative[i] + sqrt(l2) * t
	return {"d": best_d, "dist": best_dist}


func distance_to_point(p: Vector3) -> float:
	return float(project(p).dist)
