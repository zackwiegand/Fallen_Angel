extends SceneTree
## Hi-res close-ups of the rig (same camera angle as the game, 4x the pixels) for posing work.
##   godot --path . -s tools/closeup.gd -- <out.png> "<anim>:<time>,..." "<yaw_deg>,..."
const RES := 384
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var poses := a[1].split(",")
	var yaws := a[2].split(",")
	var vp := SubViewport.new()
	vp.size = Vector2i(RES, RES)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.25, 0.22, 0.27)
	vp.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	cam.far = 60
	vp.add_child(cam)
	var e := deg_to_rad(38.0)
	var target := Vector3(0, 1.25, 0)
	cam.position = target + Vector3(0, sin(e), cos(e)) * 20.0
	cam.look_at(target)
	var rig := RockerRig.new()
	vp.add_child(rig)
	await process_frame
	rig.equip("guitar", GearCatalog.ITEMS.guitar[0])
	rig.equip("armor", GearCatalog.ITEMS.armor[0])
	rig.equip("boots", GearCatalog.ITEMS.boots[0])
	rig.anim_tree.active = false
	var sheet := Image.create(RES * yaws.size(), RES * poses.size(), false, Image.FORMAT_RGBA8)
	for r in poses.size():
		var p := poses[r].split(":")
		rig.anim_player.play(p[0])
		rig.anim_player.seek(float(p[1]), true)
		rig.anim_player.pause()
		for c in yaws.size():
			rig.rotation.y = deg_to_rad(float(yaws[c]))
			for i in 3: await process_frame
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(c, r) * RES)
	sheet.save_png(a[0])
	print("saved ", a[0])
	quit()
