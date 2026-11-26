extends SceneTree
## Captures game frames during a scripted fireball and lightning cast (side by side, 3x).
##   godot --path . -s tools/spell_shots.gd -- <out.png>
func _initialize() -> void:
	_run.call_deferred()

func _grab(vp: SubViewport, shots: Array) -> void:
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	shots.append(img)

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var vp: SubViewport = main.get_node("Game/GameViewport")
	var p = main.get_node("Game/GameViewport/World/Player")
	var shots := []
	p.position = Vector2(180, 175)
	for n in [0, 1, 3]:
		p.play_note(n)
		await create_timer(0.08).timeout
	await create_timer(0.3).timeout
	_grab(vp, shots)                          # thrust / launch
	await create_timer(0.15).timeout
	_grab(vp, shots)                          # in flight
	await create_timer(0.25).timeout
	_grab(vp, shots)                          # impact
	await create_timer(1.0).timeout
	p.position = Vector2(240, 190)
	for n in [0, 2, 1, 3, 2, 4, 3, 5]:
		p.play_note(n)
		await create_timer(0.12).timeout
	_grab(vp, shots)                          # notes + charges
	await create_timer(0.62).timeout
	_grab(vp, shots)                          # chain
	await create_timer(0.1).timeout
	_grab(vp, shots)
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i % 3 * w, i / 3 * h))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()
