extends SceneTree
## Screenshot of the running game window.
##   godot --path . -s tools/screenshot.gd -- <out.png> [player_x player_y] [facing_index] [anim] [anim_time]
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var player = main.get_node("Game/GameViewport/World/Player")
	if a.size() >= 3:
		player.position = Vector2(float(a[1]), float(a[2]))
	if a.size() >= 4:
		player.rig.face(int(a[3]) * PI / 4.0)
	if a.size() >= 5:
		player.rig.anim_tree.active = false
		player.rig.anim_player.play(a[4])
		player.rig.anim_player.seek(float(a[5]) if a.size() >= 6 else 0.0, true)
		player.rig.anim_player.pause()
	for i in 8: await process_frame
	root.get_texture().get_image().save_png(a[0])
	print("saved ", a[0])
	quit()
