class_name MeshKit
extends RefCounted
## Small procedural mesh builder: boxes, prisms, cylinders and low-poly spheres with
## per-vertex colour, merged into one ArrayMesh so a whole prop costs one draw call.
## Optional CUSTOM0 data (used by the crowd shader for the standing pose).

var st := SurfaceTool.new()
var color := Color.WHITE
var uv := Vector2.ZERO
var uv2 := Vector2.ZERO
## Offset applied to CUSTOM0 (standing pose) for every vertex added while set.
var stand_offset := Vector3.ZERO
var use_custom := false
var xform := Transform3D.IDENTITY


func _init(p_use_custom := false) -> void:
	use_custom = p_use_custom
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if use_custom:
		st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)


func _v(p: Vector3, n: Vector3, stand_p: Variant = null) -> void:
	var wp := xform * p
	var wn := (xform.basis * n).normalized()
	st.set_color(color)
	st.set_uv(uv)
	st.set_normal(wn)
	if use_custom:
		st.set_uv2(uv2)
		var sp: Vector3 = (xform * stand_p) if stand_p != null else wp + stand_offset
		st.set_custom(0, Color(sp.x, sp.y, sp.z, 0.0))
	st.add_vertex(wp)


## Quad a-b-c-d, counter-clockwise when seen from the side the normal points to.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	_v(a, n)
	_v(c, n)
	_v(b, n)
	_v(a, n)
	_v(d, n)
	_v(c, n)


## Axis-aligned box; `skip` lists faces to leave out ("-y", "+z", ...).
func box(center: Vector3, size: Vector3, skip: Array = []) -> void:
	var h := size * 0.5
	var c := center
	var p := [c + Vector3(-h.x, -h.y, -h.z), c + Vector3(h.x, -h.y, -h.z), c + Vector3(h.x, h.y, -h.z), c + Vector3(-h.x, h.y, -h.z),
		c + Vector3(-h.x, -h.y, h.z), c + Vector3(h.x, -h.y, h.z), c + Vector3(h.x, h.y, h.z), c + Vector3(-h.x, h.y, h.z)]
	if not "+z" in skip:
		quad(p[4], p[5], p[6], p[7])
	if not "-z" in skip:
		quad(p[1], p[0], p[3], p[2])
	if not "+x" in skip:
		quad(p[5], p[1], p[2], p[6])
	if not "-x" in skip:
		quad(p[0], p[4], p[7], p[3])
	if not "+y" in skip:
		quad(p[7], p[6], p[2], p[3])
	if not "-y" in skip:
		quad(p[0], p[1], p[5], p[4])


## Box from min to max corner.
func box_mm(lo: Vector3, hi: Vector3, skip: Array = []) -> void:
	box((lo + hi) * 0.5, hi - lo, skip)


## Box oriented along the segment a->b (square cross-section `w`).
func beam(a: Vector3, b: Vector3, w: float) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		return
	var y := dir / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var saved := xform
	xform = saved * Transform3D(Basis(x, y, z), a)
	box(Vector3(0, len * 0.5, 0), Vector3(w, len, w))
	xform = saved


## Vertical prism (n sides) between y0 and y1 with elliptical radii; optional top cap.
func prism(center: Vector3, y0: float, y1: float, r0: Vector2, r1: Vector2, sides := 6, top := true, bottom := false) -> void:
	for i in sides:
		var a0 := TAU * i / sides + PI / sides
		var a1 := TAU * (i + 1) / sides + PI / sides
		var b0 := center + Vector3(cos(a0) * r0.x, y0, sin(a0) * r0.y)
		var b1 := center + Vector3(cos(a1) * r0.x, y0, sin(a1) * r0.y)
		var t0 := center + Vector3(cos(a0) * r1.x, y1, sin(a0) * r1.y)
		var t1 := center + Vector3(cos(a1) * r1.x, y1, sin(a1) * r1.y)
		var am := (a0 + a1) * 0.5
		var n := Vector3(cos(am), (r0.x - r1.x) / maxf(y1 - y0, 0.01) * 0.5, sin(am)).normalized()
		_v(b0, n)
		_v(b1, n)
		_v(t1, n)
		_v(b0, n)
		_v(t1, n)
		_v(t0, n)
		if top:
			_v(center + Vector3(0, y1, 0), Vector3.UP)
			_v(t0, Vector3.UP)
			_v(t1, Vector3.UP)
		if bottom:
			_v(center + Vector3(0, y0, 0), Vector3.DOWN)
			_v(b1, Vector3.DOWN)
			_v(b0, Vector3.DOWN)


## Cylinder between two points.
func cyl(a: Vector3, b: Vector3, r: float, sides := 8, caps := true) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 1e-4:
		return
	var y := dir / len
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var saved := xform
	xform = saved * Transform3D(Basis(x, y, z), a)
	prism(Vector3.ZERO, 0.0, len, Vector2(r, r), Vector2(r, r), sides, caps, caps)
	xform = saved


## Low-poly ellipsoid (smooth normals). `lat_from` > 0 cuts off the bottom (hemisphere = 0.5).
func sphere(center: Vector3, radius: Vector3, seg := 6, rings := 4, lat_from := 0.0) -> void:
	for r in rings:
		var v0 := float(r) / rings
		var v1 := float(r + 1) / rings
		if v1 <= lat_from + 1e-4:
			continue
		v0 = maxf(v0, lat_from)
		var th0 := PI * (1.0 - v0)
		var th1 := PI * (1.0 - v1)
		for s in seg:
			var p0 := TAU * s / seg
			var p1 := TAU * (s + 1) / seg
			var n00 := Vector3(sin(th0) * cos(p0), cos(th0), sin(th0) * sin(p0))
			var n01 := Vector3(sin(th0) * cos(p1), cos(th0), sin(th0) * sin(p1))
			var n10 := Vector3(sin(th1) * cos(p0), cos(th1), sin(th1) * sin(p0))
			var n11 := Vector3(sin(th1) * cos(p1), cos(th1), sin(th1) * sin(p1))
			var q00 := center + n00 * radius
			var q01 := center + n01 * radius
			var q10 := center + n10 * radius
			var q11 := center + n11 * radius
			if r > 0 or lat_from > 0.0:
				_v(q00, n00)
				_v(q01, n01)
				_v(q11, n11)
			if r < rings - 1:
				_v(q00, n00)
				_v(q11, n11)
				_v(q10, n10)


## Flat disc (y-up) for cutouts like the cooler lid.
func disc(center: Vector3, r: float, sides := 10) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		_v(center, Vector3.UP)
		_v(center + Vector3(cos(a0) * r, 0, sin(a0) * r), Vector3.UP)
		_v(center + Vector3(cos(a1) * r, 0, sin(a1) * r), Vector3.UP)


func commit() -> ArrayMesh:
	st.index()
	return st.commit()
