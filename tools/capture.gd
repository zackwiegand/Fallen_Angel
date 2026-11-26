extends SceneTree
## Renders a contact sheet of the live game: rows = animation poses, columns = 8 facings.
##   godot --path . -s tools/capture.gd -- <out.png> [guitar armor boots indices]
const POSES := [["idle", 0.0], ["walk", 0.35], ["strum", 0.62], ["swing", 0.75], ["swing", 0.3]]
const CELL := 112
const SCALE := 3

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/capture.png"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5: await process_frame
	var player = main.get_node("Game/GameViewport/World/Player")
	var rig: RockerRig = player.rig
	for k in range(1, args.size()):
		for c in int(args[k]): player.cycle_gear(GearCatalog.SLOTS[k - 1])
	rig.anim_tree.active = false
	var vp: SubViewport = main.get_node("Game/GameViewport")
	var sheet := Image.create(CELL * 8 * SCALE, CELL * POSES.size() * SCALE, false, Image.FORMAT_RGBA8)
	for r in POSES.size():
		rig.anim_player.play(POSES[r][0])
		rig.anim_player.seek(POSES[r][1] * rig.anim_player.current_animation_length, true)
		rig.anim_player.pause()
		for d in 8:
			rig.face(d * PI / 4.0)
			for i in 3: await process_frame
			var img := vp.get_texture().get_image()
			var c := Vector2i(160, 90) - Vector2i(CELL / 2, CELL / 2 + 22)
			var cell := img.get_region(Rect2i(c, Vector2i(CELL, CELL)))
			cell.convert(Image.FORMAT_RGBA8)
			cell.resize(CELL * SCALE, CELL * SCALE, Image.INTERPOLATE_NEAREST)
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, cell.get_size()), Vector2i(d, r) * CELL * SCALE)
	sheet.save_png(out)
	print("saved ", out)
	quit()
