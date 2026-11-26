extends SceneTree
## Renders the whole demo floor (1 texel = 1 px) plus 4x close-ups of a few spots, to check the art.
## Needs a window (not --headless):
##   godot --path . -s tools/floor_shots.gd -- <out_dir> [show_nav]
## Writes floor_overview.png and floor_crop_<name>.png. "show_nav" tints the navigation mesh.

const CROPS := {   # name: region in game px
	"start": Rect2i(40, 340, 240, 160),
	"colonnade": Rect2i(380, 110, 240, 160),
	"bone_corner": Rect2i(640, 70, 240, 160),
	"pillar_cluster": Rect2i(660, 380, 240, 160),
	"pedal_nook": Rect2i(20, 70, 240, 160),
}
const ZOOM := 4


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "user://floor_shots"
	DirAccess.make_dir_recursive_absolute(out)
	var world: Node2D = load("res://scenes/dungeon.tscn").instantiate()
	var walls: TileMapLayer = world.get_node("Walls")
	var room := Rect2i(walls.get_used_rect().position * 16, walls.get_used_rect().size * 16)
	var vp := SubViewport.new()
	vp.size = room.size
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	vp.add_child(world)
	var player := world.get_node("Player")
	(player.get_node("Camera2D") as Camera2D).enabled = false
	player.set_physics_process(false)      # no main.gd here, so no input actions to poll
	player.set_process(false)
	if a.size() > 1 and a[1] == "show_nav":
		var nav: NavigationRegion2D = world.get_node("Navigation")
		var poly := nav.navigation_polygon
		var overlay := Node2D.new()
		overlay.z_index = -1
		overlay.draw.connect(func() -> void:
			var verts := poly.get_vertices()
			for i in poly.get_polygon_count():
				var pts := PackedVector2Array()
				for k: int in poly.get_polygon(i):
					pts.append(verts[k])
				overlay.draw_colored_polygon(pts, Color(0.2, 0.9, 0.4, 0.18))
				pts.append(pts[0])
				overlay.draw_polyline(pts, Color(0.3, 1.0, 0.5, 0.6)))
		world.add_child(overlay)
	for i in 10:
		await process_frame
	var img := vp.get_texture().get_image()
	img.save_png(out.path_join("floor_overview.png"))
	for name: String in CROPS:
		var c: Image = img.get_region(CROPS[name])
		c.resize(c.get_width() * ZOOM, c.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
		c.save_png(out.path_join("floor_crop_%s.png" % name))
	print("saved floor shots to ", out)
	quit()
