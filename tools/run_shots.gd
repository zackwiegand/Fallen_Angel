extends SceneTree
## Run clip review: an 8-facing sheet of run poses (straight from the 128 px rig canvas) and a
## side-view frame strip at the clip's sprite rate. Also checks that no pose crops at the canvas edge.
##   godot --path . -s tools/run_shots.gd -- <out_dir>
const PHASES := [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]
const STRIP_FRAMES := 12          # export_gltf.py ANIMS["run"]: 12 frames at 16 fps
const STRIP_FACINGS := [2, 1]     # facing index (x 45 deg): side view, front 3/4
const STRIP_CROP := Rect2i(24, 20, 80, 100)   # the character's part of the 128 px canvas
const SCALE := 3
const BG := Color("3a3440")

var _last_canvas: Image           # raw rig canvas of the last pose (for the crop check)


func _initialize() -> void:
	create_timer(120.0).timeout.connect(func(): print("FAIL watchdog: hung"); quit(99))
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	var player = main.get_node("Game/GameViewport/World/Player")
	var rig: RockerRig = player.rig
	var canvas: SubViewport = player.get_node("RigViewport")
	rig.anim_tree.active = false
	var px: int = canvas.size.x
	var cropped := 0

	var sheet := Image.create(px * 8 * SCALE, px * PHASES.size() * SCALE, false, Image.FORMAT_RGBA8)
	sheet.fill(BG)
	for r in PHASES.size():
		for d in 8:
			var cell := await _pose(rig, canvas, &"run", PHASES[r], d)
			cropped += _edge_pixels(_last_canvas)
			_blit(sheet, cell, Vector2i(d, r) * px * SCALE)
	sheet.save_png(out.path_join("run_8dir.png"))

	# one strip per facing, cropped to the character so it can be judged at sprite size
	for f: int in STRIP_FACINGS:
		var strip := Image.create(STRIP_CROP.size.x * STRIP_FRAMES * SCALE, STRIP_CROP.size.y * SCALE, false, Image.FORMAT_RGBA8)
		for k in STRIP_FRAMES:
			var cell := await _pose(rig, canvas, &"run", float(k) / STRIP_FRAMES, f)
			_blit(strip, cell.get_region(STRIP_CROP), Vector2i(k * STRIP_CROP.size.x * SCALE, 0))
		strip.save_png(out.path_join("run_strip_facing%d.png" % f))

	print("opaque pixels on the canvas edge: ", cropped, " (0 = nothing crops)")
	print("saved ", out)
	quit(1 if cropped > 0 else 0)


func _pose(rig: RockerRig, canvas: SubViewport, anim: StringName, phase: float, facing: int) -> Image:
	rig.anim_player.play(anim)
	rig.anim_player.seek(phase * rig.anim_player.current_animation_length, true)
	rig.anim_player.pause()
	rig.face(facing * PI / 4.0)
	for i in 3:
		await process_frame
	_last_canvas = canvas.get_texture().get_image()
	_last_canvas.convert(Image.FORMAT_RGBA8)
	# what the game shows: the sprite (outline shader) in the game viewport, same 128 px window
	var sprite: Sprite2D = canvas.get_parent().get_node("Sprite")
	var vp := sprite.get_viewport()
	var c := Vector2i(sprite.get_global_transform_with_canvas().origin + sprite.offset)
	var img := vp.get_texture().get_image().get_region(Rect2i(c - canvas.size / 2, canvas.size))
	img.convert(Image.FORMAT_RGBA8)
	return img


func _blit(dst: Image, cell: Image, at: Vector2i) -> void:
	var big := cell.duplicate() as Image
	big.resize(cell.get_width() * SCALE, cell.get_height() * SCALE, Image.INTERPOLATE_NEAREST)
	dst.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), at)


func _edge_pixels(img: Image) -> int:
	var n := 0
	var w := img.get_width()
	var h := img.get_height()
	for i in w:
		for p: Vector2i in [Vector2i(i, 0), Vector2i(i, h - 1), Vector2i(0, i), Vector2i(w - 1, i)]:
			if img.get_pixelv(p).a > 0.5:
				n += 1
	return n
