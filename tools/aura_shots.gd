extends SceneTree
## Frames of the lightning charge aura at rising charge levels, then the release burst (cropped 4x).
##   godot --path . -s tools/aura_shots.gd -- <out.png>
const NOTES := [0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 4, 5, 3, 4, 2, 3]
const GRAB_AT := {2: "primed", 3: "1", 7: "5", 11: "9", 18: "16"}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var vp: SubViewport = main.get_node("Game/GameViewport")
	var p = main.get_node("Game/GameViewport/World/Player")
	p.position = Vector2(240, 260)
	var crops := []
	var grab := func():
		var img := vp.get_texture().get_image()
		var screen_pos: Vector2 = p.get_global_transform_with_canvas().origin
		var c := img.get_region(Rect2i(Vector2i(screen_pos) - Vector2i(50, 90), Vector2i(100, 110)))
		c.convert(Image.FORMAT_RGBA8)
		crops.append(c)
	for i in NOTES.size():
		p.play_note(NOTES[i])
		await create_timer(0.1).timeout
		if GRAB_AT.has(i):
			grab.call()
	await p.spellbook.cast
	await create_timer(0.07).timeout
	grab.call()                                   # release burst
	var sheet := Image.create(100 * crops.size(), 110, false, Image.FORMAT_RGBA8)
	for i in crops.size():
		sheet.blit_rect(crops[i], Rect2i(0, 0, 100, 110), Vector2i(i * 100, 0))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()
