class_name NavMover
extends NavigationAgent2D
## Path following + simple steering for a CharacterBody2D enemy.
## Uses the navigation map when the level has one (TileMapLayer navigation layer); otherwise steers
## straight at the goal and lets move_and_slide() slide along walls. Separation keeps a pack from
## stacking on one spot (cheap, deterministic; no RVO).
## All directions returned are unit *ground* directions (see Ground).

const REPATH_PX := 6.0            # only re-query the path when the goal moved this far
const SEPARATION_M := 0.9         # neighbours closer than this push away
const SEPARATION_GROUP := &"enemies"

var _goal := Vector2.INF


func _ready() -> void:
	path_desired_distance = 4.0
	target_desired_distance = 4.0
	avoidance_enabled = false


## True once the navigation map is synced and has at least one region.
func has_navmesh() -> bool:
	var map := get_navigation_map()
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return false
	return not NavigationServer2D.map_get_regions(map).is_empty()


## Ground direction to walk this frame to reach `goal` (screen position); ZERO when arrived.
func direction_to_goal(goal: Vector2, arrive_px := 4.0) -> Vector2:
	var body := get_parent() as Node2D
	if body.global_position.distance_to(goal) <= arrive_px:
		return Vector2.ZERO
	var next := goal
	if has_navmesh():
		if _goal == Vector2.INF or _goal.distance_to(goal) > REPATH_PX:
			_goal = goal
			target_position = goal
		if not is_navigation_finished():
			next = get_next_path_position()
	return Ground.dir(body.global_position, next)


## Push away from nearby group members (ground direction, length 0..1).
func separation() -> Vector2:
	var body := get_parent() as Node2D
	var push := Vector2.ZERO
	for other: Node in body.get_tree().get_nodes_in_group(SEPARATION_GROUP):
		if other == body or not other is CharacterBody2D:
			continue
		var g := Ground.to_ground(body.global_position - (other as Node2D).global_position) * Ground.METRES_PER_PX
		var d := g.length()
		if d < SEPARATION_M and d > 0.001:
			push += g / d * (1.0 - d / SEPARATION_M)
	return push.limit_length(1.0)


## Tangent ground direction for circling `center` (screen pos) clockwise (side = 1) or counter (-1).
static func orbit_dir(from: Vector2, center: Vector2, side: float) -> Vector2:
	var radial := Ground.dir(center, from)
	return Vector2(-radial.y, radial.x) * side
