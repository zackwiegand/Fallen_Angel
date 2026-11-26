extends SceneTree
## Pedal look check (needs a window, not --headless):
##   godot --path . -s tools/pedal_shots.gd -- <out_dir>
## Writes
##   pedals_1x.png / pedals_4x.png  rows = each pedal lit, then bypassed; columns = 8 facings
##   pedals_jacks_4x.png            same with jack_in (green) / jack_out (red) points marked
##   pedals_scale_4x.png            the pedals next to the rocker in the demo room

const PEDALS: Array[StringName] = [&"chief_delay", &"skyman_phaser"]
const CELL := 40
const BG := Color("1a1418")
const ZOOM := 4


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/pedal_shots"
	DirAccess.make_dir_recursive_absolute(out)
	var sheet := await _sheet(false)
	sheet.save_png(out + "/pedals_1x.png")
	_zoom(sheet).save_png(out + "/pedals_4x.png")
	_zoom(await _sheet(true)).save_png(out + "/pedals_jacks_4x.png")
	_zoom(await _scale_shot()).save_png(out + "/pedals_scale_4x.png")
	print("saved ", out)
	quit()


func _sheet(jacks: bool) -> Image:
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * 8, CELL * PEDALS.size() * 2)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = BG
	bg.size = vp.size
	vp.add_child(bg)
	for p in PEDALS.size():
		for lit in 2:
			for d in 8:
				var view := PedalView.new()
				vp.add_child(view)
				view.setup(PEDALS[p])
				view.lit = lit == 0
				var a := d * PI / 4.0                  # same yaw order as tools/capture.gd
				view.facing = Vector2(sin(a), -cos(a))
				view.position = Vector2(d * CELL + CELL / 2, (p * 2 + lit) * CELL + CELL * 0.7)
				if jacks:
					var dots := _JackDots.new()
					dots.view = view
					view.add_child(dots)
	for i in 4: await process_frame
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


func _scale_shot() -> Image:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5: await process_frame
	var player: Node2D = main.get_node("Game/GameViewport/World/Player")
	var world := player.get_parent()
	for i in PEDALS.size():
		var view := PedalView.new()
		world.add_child(view)
		view.setup(PEDALS[i])
		view.facing = Vector2(0, -1)
		view.position = player.position + Vector2(-34 + i * 22, 6)
	for i in 4: await process_frame
	var img := (main.get_node("Game/GameViewport") as SubViewport).get_texture().get_image()
	var c := Vector2i(player.get_global_transform_with_canvas().origin)
	var cell := img.get_region(Rect2i(c - Vector2i(70, 80), Vector2i(140, 110)))
	main.queue_free()
	return cell


func _zoom(img: Image) -> Image:
	var z := img.duplicate() as Image
	z.convert(Image.FORMAT_RGBA8)
	z.resize(img.get_width() * ZOOM, img.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	return z


class _JackDots extends Node2D:
	var view: PedalView

	func _ready() -> void:
		z_index = 1

	func _draw() -> void:
		draw_rect(Rect2(view.jack_point(&"in").floor(), Vector2.ONE), Color.GREEN)
		draw_rect(Rect2(view.jack_point(&"out").floor(), Vector2.ONE), Color.RED)
