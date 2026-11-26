extends SceneTree
## Review shots of the devil-gremlin at real sprite size (scaled up nearest), on the cobble floor.
##   godot --path . -s tools/gremlin_shots.gd -- <out_dir>
## Writes (needs a window, not --headless):
##   gremlin_sheet.png   key poses (rows) x 8 facings (columns)
##   gremlin_motion.png  every clip (rows) sampled over time, side view and 3/4 front view
##   gremlin_scale.png   a pack of gremlins next to the rocker in the game room

const CELL := 64
const SCALE := 4
const CROP := Rect2i(8, 4, 48, 46)   # part of the canvas around the gremlin that goes on the sheets
const FLOOR_ART := "res://assets/env/dungeon_tiles.png"
const POSES := [["idle", 0.0], ["walk", 0.25], ["gallop", 0.0], ["gallop", 0.5], ["throw", 0.3],
		["throw", 0.45], ["throw", 0.55], ["slash", 0.3], ["slash", 0.45], ["hit", 0.15], ["death", 1.0]]
const MOTION := ["idle", "walk", "gallop", "throw", "slash", "hit", "death"]
const MOTION_SAMPLES := 10


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://"
	DirAccess.make_dir_recursive_absolute(out)
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL, CELL)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var floor := TextureRect.new()
	var tile := AtlasTexture.new()
	tile.atlas = load(FLOOR_ART)
	tile.region = Rect2(0, 0, 64, 64)
	floor.texture = tile
	floor.stretch_mode = TextureRect.STRETCH_TILE
	floor.size = Vector2(CELL, CELL)
	vp.add_child(floor)
	var rig := GremlinRig.new()
	rig.position = Vector2(CELL / 2, round(CELL * 0.7))
	vp.add_child(rig)
	for i in 3: await process_frame

	# key poses x 8 facings
	var sheet := Image.create(CROP.size.x * 8 * SCALE, CROP.size.y * POSES.size() * SCALE, false, Image.FORMAT_RGBA8)
	for r in POSES.size():
		for d in 8:
			await _pose(rig, POSES[r][0], POSES[r][1], d)
			_blit(sheet, vp, Vector2i(d, r))
	sheet.save_png(out.path_join("gremlin_sheet.png"))

	# motion strips: each clip over time, facing right (side) and down-right (3/4 front)
	var strip := Image.create(CROP.size.x * MOTION_SAMPLES * SCALE, CROP.size.y * MOTION.size() * 2 * SCALE, false, Image.FORMAT_RGBA8)
	for r in MOTION.size():
		for k in MOTION_SAMPLES:
			for v in 2:
				await _pose(rig, MOTION[r], float(k) / MOTION_SAMPLES, [2, 1][v])
				_blit(strip, vp, Vector2i(k, r * 2 + v))
	strip.save_png(out.path_join("gremlin_motion.png"))

	# scale: gremlins around the rocker in the real room
	vp.queue_free()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: Node2D = main.get_node("Game/GameViewport/World")
	var player: Node2D = world.get_node("Player")
	var pack := [[Vector2(-34, 6), "idle", 0.2, 1], [Vector2(30, 10), "walk", 0.3, 7], [Vector2(-18, 26), "throw", 0.45, 0],
			[Vector2(46, -14), "slash", 0.45, 6], [Vector2(8, 30), "gallop", 0.5, 2]]
	for g: Array in pack:
		var e := GremlinRig.new()
		e.position = player.position + g[0]
		world.add_child(e)
		await process_frame
		await _pose(e, g[1], g[2], g[3])
	for i in 6: await process_frame
	var game: SubViewport = main.get_node("Game/GameViewport")
	var img := game.get_texture().get_image()
	var c := Vector2i(player.get_global_transform_with_canvas().origin)
	var crop := img.get_region(Rect2i(c - Vector2i(80, 70), Vector2i(160, 100)))
	crop.resize(crop.get_width() * SCALE, crop.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	crop.save_png(out.path_join("gremlin_scale.png"))
	print("saved shots to ", out)
	quit()


func _pose(rig: GremlinRig, anim: String, phase: float, dir: int) -> void:
	rig.anim_player.play(anim)
	rig.anim_player.seek(phase * rig.anim_player.current_animation_length, true)
	rig.anim_player.pause()
	var yaw := dir * PI / 4.0
	rig.facing = Vector2(sin(yaw), -cos(yaw))
	for i in 3: await process_frame


func _blit(sheet: Image, vp: SubViewport, cell: Vector2i) -> void:
	var img := vp.get_texture().get_image().get_region(CROP)
	img.convert(Image.FORMAT_RGBA8)
	img.resize(CROP.size.x * SCALE, CROP.size.y * SCALE, Image.INTERPOLATE_NEAREST)
	sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), cell * CROP.size * SCALE)
