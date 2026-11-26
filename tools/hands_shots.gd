extends SceneTree
## Close-ups of the note-playing hands layer: rest, low note, high note, mid-pick, for a few facings.
## Row 1 hi-res (game camera angle), row 2 the same at real sprite scale x3.
##   godot --path . -s tools/hands_shots.gd -- <out.png>
const RES := 320
const YAWS := [0.0, 45.0, 90.0]

func _initialize() -> void:
	_run.call_deferred()

func _vp(size: int, ortho: float) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(size, size)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.14, 0.18)
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ortho
	cam.far = 60
	vp.add_child(cam)
	var e := deg_to_rad(38.0)
	cam.position = Vector3(0, 1.25, 0) + Vector3(0, sin(e), cos(e)) * 20.0
	cam.look_at(Vector3(0, 1.25, 0))
	return vp

func _run() -> void:
	var hi := _vp(RES, 2.6)
	var lo := _vp(70, 70 * 3.0 / 80.0)
	var rigs: Array[RockerRig] = []
	for vp in [hi, lo]:
		var rig := RockerRig.new()
		vp.add_child(rig)
		rigs.append(rig)
	await process_frame
	for rig in rigs:
		for slot in GearCatalog.SLOTS:
			rig.equip(slot, GearCatalog.ITEMS[slot][0])
	await create_timer(0.5).timeout
	var shots := []    # [hi, lo] pairs
	for yaw in YAWS:
		for step in ["rest", "low", "high", "pick"]:
			for rig in rigs:
				rig.rotation.y = deg_to_rad(yaw)
				match step:
					"rest": rig.hands.reset()
					"low": rig.play_note(0)
					"high": rig.play_note(7)
					"pick": rig.play_note(4)
			await create_timer(0.05 if step == "pick" else 0.3).timeout
			var pair := []
			for vp: SubViewport in [hi, lo]:
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				pair.append(img)
			shots.append(pair)
			if step == "pick":
				await create_timer(0.4).timeout
	var lo_scale := 4
	var cell := Vector2i(RES, RES + 70 * lo_scale)
	var sheet := Image.create(cell.x * shots.size(), cell.y, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i][0], Rect2i(0, 0, RES, RES), Vector2i(i * cell.x, 0))
		var lo_img: Image = shots[i][1]
		lo_img.resize(70 * lo_scale, 70 * lo_scale, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(lo_img, Rect2i(0, 0, 280, 280), Vector2i(i * cell.x + 20, RES))
	sheet.save_png(OS.get_cmdline_user_args()[0])
	quit()
