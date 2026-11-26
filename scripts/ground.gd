class_name Ground
## Ground-plane maths for gameplay code (AI, projectiles). The world is drawn in screen space, but
## distances, speeds and facings are measured on the ground: screen y is ground depth foreshortened
## by sin(38 deg) (front 3/4 camera, see CLAUDE.md). Ground y points *away* from the camera.
## Same constants as player.gd (METRES_PER_PX, ELEVATION).

const METRES_PER_PX := 3.0 / 80.0
const ELEVATION := deg_to_rad(38.0)


static func to_screen(g: Vector2) -> Vector2:
	return Vector2(g.x, -g.y * sin(ELEVATION))


static func to_ground(s: Vector2) -> Vector2:
	return Vector2(s.x, -s.y / sin(ELEVATION))


## Ground distance in metres between two screen positions.
static func dist_m(a: Vector2, b: Vector2) -> float:
	return to_ground(b - a).length() * METRES_PER_PX


## Unit ground direction from screen position a to b (zero if they coincide).
static func dir(a: Vector2, b: Vector2) -> Vector2:
	return to_ground(b - a).normalized()


## Screen-space velocity (px/s) for moving along ground direction `g_dir` at `speed_mps`.
static func velocity(g_dir: Vector2, speed_mps: float) -> Vector2:
	return to_screen(g_dir.normalized()) * speed_mps / METRES_PER_PX
