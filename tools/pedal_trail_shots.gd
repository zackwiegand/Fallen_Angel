extends SceneTree
## Captures the pedal features in the real game: trail while walking / gathered at idle, a
## Delay > Phaser fireball (piercing ghosts) and Phaser > Delay echo numbers (world sheet, 2x), and
## the pedalboard menu (full window). Needs a window (not --headless).
##   godot --path . -s tools/pedal_trail_shots.gd -- <out_dir>
func _initialize() -> void:
	_run.call_deferred()


func _grab(vp: Viewport) -> Image:
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## 96x72 game px around the player, 5x nearest: to judge the pedals and cables at pixel level.
func _zoom(img: Image, vp: SubViewport, p: Node2D) -> Image:
	var at := vp.get_canvas_transform() * p.global_position
	var r := Rect2i(Vector2i(at) - Vector2i(48, 52), Vector2i(96, 72))
	r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - r.size)
	var z := img.get_region(r)
	z.resize(r.size.x * 5, r.size.y * 5, Image.INTERPOLATE_NEAREST)
	return z


func _run() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.4).timeout
	var vp: SubViewport = main.get_node("Game/GameViewport")
	var world: Node = main.get_node("Game/GameViewport/World")
	var p = world.get_node("Player")
	var shots: Array[Image] = []
	shots.append(_grab(vp))                                   # pickups on the floor
	for pk in world.get_children().filter(func(n: Node) -> bool: return n is PedalPickup):
		p.global_position = pk.global_position
		await create_timer(0.2).timeout
	p.global_position = Vector2(120, 250)
	Input.action_press("move_right")
	await create_timer(1.2).timeout
	shots.append(_grab(vp))                                   # walking: snake trail
	var zooms: Array[Image] = [_zoom(shots[-1], vp, p)]
	Input.action_release("move_right")
	Input.action_press("move_up")
	await create_timer(0.6).timeout
	Input.action_release("move_up")
	await create_timer(1.6).timeout
	shots.append(_grab(vp))                                   # idle: gathered behind
	zooms.append(_zoom(shots[-1], vp, p))
	Input.action_press("move_down")
	await create_timer(0.4).timeout
	Input.action_release("move_down")
	await create_timer(1.6).timeout
	zooms.append(_zoom(_grab(vp), vp, p))                     # idle facing the camera
	var zsheet := Image.create(zooms[0].get_width() * zooms.size(), zooms[0].get_height(), false, Image.FORMAT_RGBA8)
	for i in zooms.size():
		zsheet.blit_rect(zooms[i], Rect2i(Vector2i.ZERO, zooms[i].get_size()), Vector2i(i * zooms[0].get_width(), 0))
	zsheet.save_png(out_dir.path_join("pedal_trail_zoom.png"))
	# Delay > Phaser fireball at the middle dummy: original + ghosts, all piercing
	p.pedalboard.chain.assign([&"chief_delay", &"skyman_phaser"])
	p.pedalboard.chain_changed.emit()
	p.position = Vector2(240, 230)
	p.facing = Vector2(0, 1)
	p.rig.face(PI)
	for n in [0, 1, 3]:
		p.play_note(n)
	await create_timer(0.75).timeout
	shots.append(_grab(vp))                                   # first fireball + ghost 1
	await create_timer(0.3).timeout
	shots.append(_grab(vp))                                   # ghosts following
	# Phaser > Delay: echo numbers on the dummies
	p.pedalboard.move(1, 0)
	await create_timer(1.0).timeout
	for n in [0, 1, 3]:
		p.play_note(n)
	await create_timer(1.25).timeout
	shots.append(_grab(vp))                                   # echo ticks
	var w := shots[0].get_width()
	var h := shots[0].get_height()
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i % 3 * w, i / 3 * h))
	sheet.resize(sheet.get_width() * 2, sheet.get_height() * 2, Image.INTERPOLATE_NEAREST)
	sheet.save_png(out_dir.path_join("pedal_world.png"))
	# menu
	var menu: PedalboardMenu = main.get_node("PedalboardMenu")
	menu.open()
	menu.cursor = 1
	menu._sync_views()
	await create_timer(0.3).timeout
	_grab(root).save_png(out_dir.path_join("pedal_menu.png"))
	menu.holding = true
	menu.cursor = 0
	p.pedalboard.set_bypassed(p.pedalboard.chain[1], true)
	menu._sync_views()
	await create_timer(0.3).timeout
	_grab(root).save_png(out_dir.path_join("pedal_menu_holding.png"))
	menu.close()
	quit()
