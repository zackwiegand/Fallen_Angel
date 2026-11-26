extends SceneTree
## Headless checks for the demo floor: size, spawn markers, navigation.
##   godot --headless --path . -s tools/test_floor.gd

const OLD_ROOM_AREA := 480 * 320
const PEDAL_IDS := [&"chief_delay", &"skyman_phaser"]

var fails: Array[String] = []


func check(what: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails.append(what)


func _initialize() -> void:
	var watchdog := create_timer(20.0)
	watchdog.timeout.connect(func() -> void:
		print("FAIL watchdog timeout")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var world: Node2D = main.get_node("Game/GameViewport/World")
	var player: Node2D = world.get_node("Player")
	var walls: TileMapLayer = world.get_node("Walls")
	for i in 3:
		await physics_frame
	var room := walls.get_used_rect().size * walls.tile_set.tile_size
	check("floor is 3-4x the old room (%s px)" % room, room.x * room.y >= 3 * OLD_ROOM_AREA)
	var cam: Camera2D = player.get_node("Camera2D")
	check("camera limits cover the floor", cam.limit_right - cam.limit_left == room.x and cam.limit_bottom - cam.limit_top == room.y)

	var gremlins := get_nodes_in_group(&"gremlin_spawn")
	check("6-10 gremlin spawns (%d)" % gremlins.size(), gremlins.size() >= 6 and gremlins.size() <= 10)
	check("gremlin spawns away from the start", gremlins.all(func(m: Node2D) -> bool:
		return m.global_position.distance_to(player.global_position) > 160.0))
	var pedals := get_nodes_in_group(&"pedal_spawn")
	var ids := pedals.map(func(m: Node) -> StringName: return m.get_meta(&"pedal_id", &""))
	check("pedal spawns %s" % [ids], PEDAL_IDS.all(func(id: StringName) -> bool: return id in ids))

	# navigation: a path from the start to every marker, never through a pillar's collision
	var map := world.get_world_2d().navigation_map
	NavigationServer2D.map_force_update(map)
	var space := world.get_world_2d().direct_space_state
	for m: Node2D in gremlins + pedals:
		var path := NavigationServer2D.map_get_path(map, player.global_position, m.global_position, true)
		var ok := path.size() >= 2 and path[path.size() - 1].distance_to(m.global_position) < 4.0
		for i in path.size() - 1:
			var q := PhysicsRayQueryParameters2D.create(path[i], path[i + 1])
			var hit := space.intersect_ray(q)
			if hit and hit.collider == walls:
				ok = false
		check("nav path to %s (%d points)" % [m.name, path.size()], ok)
	print("FAILURES: ", fails.size())
	quit(0 if fails.is_empty() else 1)
