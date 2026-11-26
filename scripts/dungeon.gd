extends Node2D
## Test room. Keeps the player's camera inside the room bounds.


func _ready() -> void:
	var walls: TileMapLayer = $Walls
	var r := walls.get_used_rect()
	var size := walls.tile_set.tile_size
	var cam: Camera2D = $Player/Camera2D
	cam.limit_left = r.position.x * size.x
	cam.limit_top = r.position.y * size.y
	cam.limit_right = r.end.x * size.x
	cam.limit_bottom = r.end.y * size.y
