extends SceneTree
## Generates the placeholder dungeon: pixel art atlas, TileSet and a test room scene.
## Two passes (the PNG has to be imported before the TileSet can reference it):
##   godot --headless --path . -s tools/build_dungeon.gd -- art
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_dungeon.gd -- scene
##
## Pixel scale is the character's: 1 texel = 1 game pixel = 3/80 m, front 3/4 view at 38 deg.
## A 16px tile is 0.6 m wide, 0.97 m deep on the floor, or 0.76 m tall on a wall face.
## The atlas PNG / TileSet / scene are ordinary resources: repaint the PNG or edit the map freely.
##
## Atlas (64 x 256, 16px tiles, 4 columns tile seamlessly when placed by x % 4):
##   rows 0-3   cobble floor (place by x % 4, y % 4)
##   rows 4-7   cobble floor with the back wall's contact shadow (same pattern)
##   rows 8-11  wall face, top to bottom (row 11 = base, has collision)
##   row 12     wall cap (collision)            row 13  cap, dark edge on its right (left wall)
##   row 14     cap, dark edge on its left       row 15  cap without collision (pillar tops)

const ART := "res://assets/env/dungeon_tiles.png"
const TILESET := "res://assets/env/dungeon_tileset.tres"
const SCENE := "res://scenes/dungeon.tscn"
const DUMMY_ART := "res://assets/env/dummy.png"
# 7 dummies in a shallow arc across the room (48px apart), so a long lightning chain can run the line
const DUMMY_SPOTS := [Vector2(96, 175), Vector2(144, 158), Vector2(192, 148), Vector2(240, 145),
		Vector2(288, 148), Vector2(336, 158), Vector2(384, 175)]
const T := 16
const WALL_ROWS := 4

# palettes: deep, dark, mid, lite, hi (+ mortar)
const FLOOR := [Color("1f1b22"), Color("29252d"), Color("332f37"), Color("3e3943"), Color("4b4650")]
const FLOOR_MORTAR := Color("17121a")
const BRICK := [Color("221e27"), Color("2e2a34"), Color("3c3843"), Color("4e4955"), Color("625c69")]
const BRICK_MORTAR := Color("141016")
const CAP := [Color("2a242d"), Color("4a4450"), Color("5b5561"), Color("6c6672"), Color("817a86")]
const OUTLINE := Color("0d080d")

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 7
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "art"
	if mode == "art":
		_build_art()
	else:
		_build_scene()
	quit()


# ------------------------------------------------------------------ art
func _build_art() -> void:
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	var floor_img := _cobbles()
	img.blit_rect(floor_img, Rect2i(0, 0, 64, 64), Vector2i(0, 0))
	img.blit_rect(_shadowed(floor_img), Rect2i(0, 0, 64, 64), Vector2i(0, 64))
	img.blit_rect(_bricks(), Rect2i(0, 0, 64, 64), Vector2i(0, 128))
	var cap := _cap()
	for row in 4:
		var c: Image = cap.duplicate()
		for y in T:
			for tx in 4:
				if row == 1:
					c.set_pixel(tx * T + T - 1, y, OUTLINE)
				elif row == 2:
					c.set_pixel(tx * T, y, OUTLINE)
		img.blit_rect(c, Rect2i(0, 0, 64, T), Vector2i(0, 192 + row * T))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/env"))
	img.save_png(ART)
	_dummy().save_png(DUMMY_ART)
	print("wrote ", ART, " ", DUMMY_ART)


## Seamless 64x64 cobbles: wrapped Voronoi, squashed vertically for the 38 deg ground foreshortening,
## lit from the top (camera-side light) like the toon character.
func _cobbles() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var pts: Array[Vector2] = []
	var tone: Array[int] = []
	var cols := 6
	var rows := 8
	for cy in rows:
		for cx in cols:
			var off := 0.5 if cy % 2 else 0.0
			pts.append(Vector2((cx + off + rng.randf_range(0.25, 0.75)) * 64.0 / cols,
					(cy + rng.randf_range(0.3, 0.7)) * 64.0 / rows))
			tone.append([1, 2, 2, 2, 3][rng.randi() % 5])
	var id := []
	var mortar := []
	for y in 64:
		for x in 64:
			var d1 := INF
			var d2 := INF
			var best := 0
			for i in pts.size():
				for ox in [-64, 0, 64]:
					for oy in [-64, 0, 64]:
						var d := Vector2(x + 0.5 - pts[i].x - ox, (y + 0.5 - pts[i].y - oy) * 1.45).length()
						if d < d1:
							d2 = d1; d1 = d; best = i
						elif d < d2:
							d2 = d
			id.append(best)
			mortar.append(d2 - d1 < 1.4)
	var at := func(x: int, y: int) -> bool: return mortar[posmod(y, 64) * 64 + posmod(x, 64)]
	for y in 64:
		for x in 64:
			if at.call(x, y):
				img.set_pixel(x, y, FLOOR_MORTAR)
				continue
			var b: int = tone[id[y * 64 + x]]
			if at.call(x, y - 1):
				b += 2
			elif at.call(x, y - 2):
				b += 1
			elif at.call(x, y + 1) or at.call(x - 1, y):
				b -= 1
			if rng.randf() < 0.05:
				b -= 1
			img.set_pixel(x, y, FLOOR[clampi(b, 0, 4)])
	return img


## Floor copy with a soft contact shadow at the top of each 16px tile row (for the row under a wall).
func _shadowed(src: Image) -> Image:
	var img: Image = src.duplicate()
	for y in 64:
		var k: float = [0.45, 0.55, 0.68, 0.8, 0.9][y % T] if y % T < 5 else 1.0
		for x in 64:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))
	return img


## 64x64 wall face (4 tile rows tall): staggered stone blocks, lit top edge, shaded bottom,
## darkened near the floor.
func _bricks() -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var bh := 8
	for row in 64 / bh:
		var stagger := (row % 2) * 8 + rng.randi_range(-2, 2)
		var x0 := -16 + stagger
		while x0 < 64:
			var w: int = [12, 16, 16, 20][rng.randi() % 4]
			var base: int = [1, 2, 2, 2, 3][rng.randi() % 5]
			for y in bh:
				for dx in w:
					var px := posmod(x0 + dx, 64)
					var py := row * bh + y
					var c: Color
					if y == bh - 1 or dx == w - 1:
						c = BRICK_MORTAR
					else:
						var b: int = base
						if y == 0:
							b += 1
						elif y == bh - 2 or dx == w - 2:
							b -= 1
						if rng.randf() < 0.04:
							b -= 1
						c = BRICK[clampi(b, 0, 4)]
					img.set_pixel(px, py, c)
			x0 += w
	for y in range(58, 64):   # ambient occlusion where the wall meets the floor
		var k := 1.0 - 0.09 * (y - 57)
		for x in 64:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))
	return img


## 64x16 wall cap: top-lit slabs with a dark front lip.
func _cap() -> Image:
	var img := Image.create(64, T, false, Image.FORMAT_RGBA8)
	var seams := [0, 21, 43]
	for y in T:
		for x in 64:
			var b := 2
			if y == 0:
				b = 4
			elif y == 1:
				b = 3
			elif y >= T - 2:
				b = 0
			elif rng.randf() < 0.06:
				b = 1
			var c: Color = CAP[b]
			if x in seams and y < T - 2:
				c = CAP[0]
			img.set_pixel(x, y, c)
	return img


# ------------------------------------------------------------------ tileset + room
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = load(ART)
	src.texture_region_size = Vector2i(T, T)
	ts.add_source(src, 0)
	var full := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	for y in 16:
		for x in 4:
			var c := Vector2i(x, y)
			src.create_tile(c)
			var td := src.get_tile_data(c, 0)
			var solid := false
			if y >= 8 and y < 12:      # wall face: sort the whole wall by its base line
				td.y_sort_origin = (11 - y) * T + T / 2
				solid = y == 11
			elif y >= 12:              # caps sit WALL_ROWS above the wall's footprint
				td.y_sort_origin = WALL_ROWS * T + T / 2
				solid = y != 15
			if solid:
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, full)
	ResourceSaver.save(ts, TILESET)
	return load(TILESET)


func _build_scene() -> void:
	var ts := _build_tileset()
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.set_script(load("res://scripts/dungeon.gd"))
	var floor_layer := TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = ts
	floor_layer.z_index = -1
	var walls := TileMapLayer.new()
	walls.name = "Walls"
	walls.tile_set = ts
	walls.y_sort_enabled = true
	world.add_child(floor_layer)
	world.add_child(walls)

	var w := 30
	var h := 20
	var floor_top := 1 + WALL_ROWS
	for y in range(floor_top, h - 1):
		for x in range(1, w - 1):
			var shadow := 4 if y == floor_top else 0
			floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(x % 4, shadow + y % 4))
	for x in range(1, w - 1):
		walls.set_cell(Vector2i(x, 0), 0, Vector2i(x % 4, 12))                 # back wall cap
		for r in WALL_ROWS:
			walls.set_cell(Vector2i(x, 1 + r), 0, Vector2i(x % 4, 8 + r))     # back wall face
		walls.set_cell(Vector2i(x, h - 2), 0, Vector2i(x % 4, 12))             # low front wall
		walls.set_cell(Vector2i(x, h - 1), 0, Vector2i(x % 4, 11))
	for y in h:
		walls.set_cell(Vector2i(0, y), 0, Vector2i(y % 4, 13))                 # side walls (caps only:
		walls.set_cell(Vector2i(w - 1, y), 0, Vector2i(y % 4, 14))             # their faces are edge-on)
	var owned: Array[Node] = [floor_layer, walls]
	for i in DUMMY_SPOTS.size():                                               # practice dummies
		var d: Node2D = load("res://scenes/dummy.tscn").instantiate()
		d.name = "Dummy%d" % (i + 1)
		d.position = DUMMY_SPOTS[i]
		world.add_child(d)
		owned.append(d)

	var player: Node2D = load("res://scenes/player.tscn").instantiate()
	player.position = Vector2(240, 210)
	world.add_child(player)
	owned.append(player)
	for n in owned:
		n.owner = world
	var packed := PackedScene.new()
	packed.pack(world)
	ResourceSaver.save(packed, SCENE)
	world.free()
	print("wrote ", SCENE)


## 26x56 straw practice dummy, front view, lit from the top-left like the tiles; base centre at the
## bottom middle (13, 55). Sized to the shared pixel scale (~2 m tall).
func _dummy() -> Image:
	var img := Image.create(26, 56, false, Image.FORMAT_RGBA8)
	var wood := [Color("3b2414"), Color("5e3a1f"), Color("7d5230")]
	var sack := [Color("5a4027"), Color("8a6a3e"), Color("b8955a")]
	var straw := [Color("a88a38"), Color("d8c060")]
	var rope := Color("2e2016")
	var shade := func(nx: float, ny: float, pal: Array) -> Color:
		var l := -nx * 0.6 - ny * 0.8
		return pal[2] if l > 0.35 else (pal[1] if l > -0.35 else pal[0])
	var ellipse := func(cx: float, cy: float, rx: float, ry: float, pal: Array) -> void:
		for y in 56:
			for x in 26:
				var nx := (x + 0.5 - cx) / rx
				var ny := (y + 0.5 - cy) / ry
				if nx * nx + ny * ny <= 1.0:
					img.set_pixel(x, y, shade.call(nx, ny, pal))
	# stand: a cross-plank base and the post
	for x in range(5, 21):
		for y in range(52, 56):
			img.set_pixel(x, y, wood[2] if y == 52 else wood[1 if (x + y) % 5 else 0])
	for y in range(8, 52):
		for x in range(11, 15):
			img.set_pixel(x, y, wood[2] if x == 11 else (wood[0] if x == 14 else wood[1]))
	# crossbar arms with straw tufts
	for x in range(2, 24):
		for y in range(19, 22):
			img.set_pixel(x, y, wood[2] if y == 19 else wood[1])
	for t in [Vector2i(1, 20), Vector2i(0, 19), Vector2i(0, 21), Vector2i(24, 20), Vector2i(25, 19), Vector2i(25, 21)]:
		img.set_pixel(t.x, t.y, straw[1])
	# straw-stuffed burlap body, rope bands, painted target, straw poking out below
	ellipse.call(13.0, 31.0, 8.5, 11.0, sack)
	for x in range(5, 22):
		for y in [25, 37]:
			if img.get_pixel(x, y).a > 0.0:
				img.set_pixel(x, y, rope)
	ellipse.call(13.0, 31.0, 3.5, 3.5, [Color("7a1410"), Color("a0201c"), Color("d8483a")])
	img.set_pixel(13, 31, Color("f0d8c0"))
	for x in range(7, 20, 2):
		img.set_pixel(x, 42, straw[x % 4 / 2])
		img.set_pixel(x + 1, 43, straw[0])
	# sack head with stitched X eyes, tied at the neck
	ellipse.call(13.0, 11.5, 6.0, 6.5, sack)
	for e in [Vector2i(10, 10), Vector2i(16, 10)]:
		for k in [-1, 0, 1]:
			img.set_pixel(e.x + k, e.y + k, rope)
			img.set_pixel(e.x + k, e.y - k, rope)
	for x in range(11, 16):
		img.set_pixel(x, 14, rope)
	for x in range(10, 17):
		img.set_pixel(x, 18, rope)
	# 1px dark outline around the silhouette, like the character sprite
	var outline := []
	for y in 56:
		for x in 26:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < 26 and q.y < 56 and img.get_pixel(q.x, q.y).a > 0.0:
					outline.append(Vector2i(x, y))
					break
	for o: Vector2i in outline:
		img.set_pixel(o.x, o.y, OUTLINE)
	return img
