class_name EnemySpawner
extends Node2D
## Spawns gremlins at the level's `gremlin_spawn` Marker2Ds (each gremlin paces around and respawns
## at its own marker). Without markers it falls back to a few spots on the floor away from the player.
## Add it as a child of the y-sorted World; it y-sorts its children with the rest of the room.

const GREMLIN_SCENE := preload("res://scenes/enemies/gremlin.tscn")
const MARKER_GROUP := &"gremlin_spawn"
## Fallback spots as fractions of the floor's used rect, used when the level has no markers.
const FALLBACK := [Vector2(0.15, 0.25), Vector2(0.85, 0.3), Vector2(0.8, 0.85)]

var gremlins: Array[Gremlin] = []


func _ready() -> void:
	y_sort_enabled = true
	_spawn_all.call_deferred()      # markers / floor may be added after us


func _spawn_all() -> void:
	for p in spawn_points():
		spawn(p)


func spawn_points() -> Array[Vector2]:
	var pts: Array[Vector2] = []
	for m: Node in get_tree().get_nodes_in_group(MARKER_GROUP):
		if m is Node2D:
			pts.append((m as Node2D).global_position)
	if pts.is_empty():
		var floor_layer := get_parent().get_node_or_null(^"Floor") as TileMapLayer
		if floor_layer:
			var r := floor_layer.get_used_rect()
			var ts := Vector2(floor_layer.tile_set.tile_size)
			for f: Vector2 in FALLBACK:
				var cell := Vector2(r.position) + Vector2(r.size) * f
				pts.append(floor_layer.to_global(cell * ts + ts * 0.5))
	return pts


func spawn(at: Vector2) -> Gremlin:
	var g: Gremlin = GREMLIN_SCENE.instantiate()
	g.spawn_point = at
	g.position = at - global_position
	add_child(g)
	gremlins.append(g)
	return g
