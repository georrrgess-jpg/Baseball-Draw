class_name Field
extends RefCounted
## Fixed diamond geometry, zones and placement rules shared by every arena.
## Coordinates are on the XZ plane (y = 0 is the field surface).

const HOME := Vector3(0, 0, 10)
const FIRST := Vector3(9.5, 0, 0.5)
const SECOND := Vector3(0, 0, -9)
const THIRD := Vector3(-9.5, 0, 0.5)
const MOUND := Vector3(0, 0, 1)
const WALL_RADIUS := 36.0
const INFIELD_RADIUS := 21.0     # distance from home where the infield arc ends
const FAIR_HALF_ANGLE := 45.0

const MOUND_ZONE := 2.7
const HOME_ZONE := 4.6
const PATH_CLEARANCE := 1.6
const BASE_CLEARANCE := 1.2
const UNIT_SPACING := 1.5

const ZONE_NAMES := {"mound": "Pitcher's Mound", "home": "Home Plate", "infield": "Infield", "outfield": "Outfield"}


static func v2(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Which tactical zone a position falls in.
static func zone_at(p: Vector3) -> String:
	if v2(p).distance_to(v2(MOUND)) <= MOUND_ZONE:
		return "mound"
	var dh := v2(p).distance_to(v2(HOME))
	if dh <= HOME_ZONE:
		return "home"
	if dh < INFIELD_RADIUS:
		return "infield"
	return "outfield"


## Angle (degrees) of a point measured from straight-away centre field, seen from home plate.
static func angle_from_center(p: Vector3) -> float:
	var d := v2(p) - v2(HOME)
	return rad_to_deg(atan2(d.x, -d.y))


## Whether a defender may stand here (ignoring other units and routes, which the battle checks).
static func in_playable_area(p: Vector3) -> bool:
	var dh := v2(p).distance_to(v2(HOME))
	if dh > WALL_RADIUS - 2.5:
		return false
	if p.z > HOME.z + 3.4:
		return false
	if dh < 5.5:
		return true   # behind / around the plate is allowed for catchers
	return absf(angle_from_center(p)) <= FAIR_HALF_ANGLE + 6.0


static func bases() -> Array[Vector3]:
	return [HOME, FIRST, SECOND, THIRD]


## Point on the outfield wall arc at the given angle from centre (degrees).
static func wall_point(angle_deg: float, radius := WALL_RADIUS) -> Vector3:
	var a := deg_to_rad(angle_deg)
	return HOME + Vector3(sin(a), 0, -cos(a)) * radius
