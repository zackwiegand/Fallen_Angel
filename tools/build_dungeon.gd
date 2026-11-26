extends SceneTree
## Generates the demo floor: pixel art atlases, TileSet and the dungeon scene.
## Two passes (the PNGs have to be imported before the TileSet can reference them):
##   godot --headless --path . -s tools/build_dungeon.gd -- art
##   godot --headless --path . --import
##   godot --headless --path . -s tools/build_dungeon.gd -- scene
##
## Pixel scale is the character's: 1 texel = 1 game pixel = 3/80 m, front 3/4 view at 38 deg.
## A 16px tile is 0.6 m wide, 0.97 m deep on the floor, or 0.76 m tall on a wall face.
## The atlas PNGs / TileSet / scene are ordinary resources: repaint the PNGs (same layout) or edit the map.
##
## Tile atlas, dungeon_tiles.png (128 x 256, 16px tiles). Floor and wall blocks of 4 columns tile seamlessly
## when placed by x % 4 (and y % 4 for floors); the floor variants share the base cobbles' mortar, so they
## mix freely with it:
##   cols 0-3  rows 0-3    cobble floor (place by x % 4, y % 4)
##   cols 4-7  rows 0-3    cobble variant "worn": retoned / sunken stones
##   cols 0-3  rows 4-7    cobble floor with the back wall's contact shadow (same pattern)
##   cols 4-7  rows 4-7    cobble variant "damaged": cracked / missing stones, mossy mortar
##   cols 0-3  rows 8-11   wall face, top to bottom (row 11 = base, has collision)
##   cols 0-3  row 12      wall cap (collision)       row 13  cap, dark edge on its right (left wall)
##             row 14      cap, dark edge on its left  row 15  cap without collision
##   cols 4-5  rows 8-11   pillar face, left/right half (row 11 = base, collision)
##   cols 4-5  row 12      pillar top
##   cols 6-7  row 9       broken pillar, jagged top   rows 10-11  its face (row 11 = base, collision)
##
## Decal atlas, dungeon_decals.png (128 x 128, transparent; drawn on the Decals layer over the floor,
## no collision). Multi-tile decals are placed cell by cell from their top-left cell:
##   row 0  cols 0-3  moss tufts          cols 4-5 rows 0-1  big moss patch    cols 6-7  moss at a wall base
##   row 1  cols 0-2  blood splats        col 3  blood smear                   cols 6-7  blood pool (2x1)
##   row 2  cols 0-3  cracks              cols 4-5  puddle (2x1)   col 6  pillar contact shadow   col 7  skull
##   row 3  cols 0-1  loose bones         cols 2-3  chain (2x1)    cols 4-7  rubble
##   rows 4-5  cols 0-2  bone pile, right corner (3x2)    cols 3-5  bone pile, left corner (3x2)

const ART := "res://assets/env/dungeon_tiles.png"
const DECALS := "res://assets/env/dungeon_decals.png"
const TILESET := "res://assets/env/dungeon_tileset.tres"
const SCENE := "res://scenes/dungeon.tscn"
const DUMMY_ART := "res://assets/env/dummy.png"
const T := 16
const WALL_ROWS := 4

# ---- floor layout (tiles). The walkable floor is x 1..W-2, rows FLOOR_TOP..H-3.
const W := 56
const H := 38
const FLOOR_TOP := 1 + WALL_ROWS
const FLOOR_WEIGHTS := [0.62, 0.24, 0.14]     # base, worn, damaged
const PLAYER_START := Vector2(200, 470)
# 7 dummies in a shallow arc above the player start (48px apart), so a long lightning chain can run the line
const DUMMY_SPOTS := [Vector2(56, 435), Vector2(104, 418), Vector2(152, 408), Vector2(200, 405),
		Vector2(248, 408), Vector2(296, 418), Vector2(344, 435)]
# pillars: footprint cell of the left half (the base row; the face rises above it)
const PILLARS := [Vector2i(8, 12), Vector2i(14, 12), Vector2i(26, 12), Vector2i(34, 12), Vector2i(42, 12),
		Vector2i(26, 22), Vector2i(42, 22), Vector2i(46, 29), Vector2i(49, 26), Vector2i(49, 32)]
const BROKEN_PILLARS := [Vector2i(12, 18), Vector2i(33, 17), Vector2i(38, 31), Vector2i(52, 10)]
const GREMLIN_SPAWNS := [Vector2i(30, 9), Vector2i(44, 8), Vector2i(51, 15), Vector2i(38, 16),
		Vector2i(30, 27), Vector2i(44, 34), Vector2i(53, 33), Vector2i(20, 8)]
const PEDAL_SPAWNS := {&"chief_delay": Vector2i(4, 7), &"skyman_phaser": Vector2i(52, 29)}
const NAV_AGENT_RADIUS := 6.0

# palettes: deep, dark, mid, lite, hi (+ mortar)
const FLOOR := [Color("1f1b22"), Color("29252d"), Color("332f37"), Color("3e3943"), Color("4b4650")]
const FLOOR_MORTAR := Color("17121a")
const BRICK := [Color("221e27"), Color("2e2a34"), Color("3c3843"), Color("4e4955"), Color("625c69")]
const BRICK_MORTAR := Color("141016")
const CAP := [Color("2a242d"), Color("4a4450"), Color("5b5561"), Color("6c6672"), Color("817a86")]
const OUTLINE := Color("0d080d")
const MOSS := [Color("1a2415"), Color("25331b"), Color("344822"), Color("486029")]
const BLOOD := [Color("3a0a0d"), Color("5c1216"), Color("821f23"), Color("a8352f")]
const BONE := [Color("564c3d"), Color("8f8268"), Color("c2b594"), Color("e2d8bc")]
const WATER := [Color("111318"), Color("192029"), Color("222c37"), Color("495a6c"), Color("7a8da0")]
const IRON := [Color("24242b"), Color("43434e"), Color("6e6e7c")]
const DIRT := [Color("1d1714"), Color("2a211b"), Color("372b22")]

var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rng.seed = 7
	var mode: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "art"
	if mode == "art":
		_build_art()
	else:
		_build_scene()
	quit()


# ------------------------------------------------------------------ art: tile atlas
func _build_art() -> void:
	var img := Image.create(128, 256, false, Image.FORMAT_RGBA8)
	var cob := _cobbles()
	var floor_img: Image = cob[0]
	img.blit_rect(floor_img, Rect2i(0, 0, 64, 64), Vector2i(0, 0))
	img.blit_rect(_worn(floor_img, cob[1], cob[2]), Rect2i(0, 0, 64, 64), Vector2i(64, 0))
	img.blit_rect(_shadowed(floor_img), Rect2i(0, 0, 64, 64), Vector2i(0, 64))
	img.blit_rect(_damaged(floor_img, cob[1], cob[2]), Rect2i(0, 0, 64, 64), Vector2i(64, 64))
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
	var face := _pillar_face()
	img.blit_rect(face, Rect2i(0, 0, 32, 64), Vector2i(64, 128))
	img.blit_rect(_pillar_top(), Rect2i(0, 0, 32, T), Vector2i(64, 192))
	img.blit_rect(_broken_top(face), Rect2i(0, 0, 32, T), Vector2i(96, 144))
	img.blit_rect(face, Rect2i(0, 32, 32, 32), Vector2i(96, 160))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/env"))
	img.save_png(ART)
	_decals().save_png(DECALS)
	_dummy().save_png(DUMMY_ART)
	print("wrote ", ART, " ", DECALS, " ", DUMMY_ART)


## Seamless 64x64 cobbles: wrapped Voronoi, squashed vertically for the 38 deg ground foreshortening,
## lit from the top (camera-side light) like the toon character.
## Returns [image, stone id per pixel, mortar flag per pixel] so variants can edit whole stones.
func _cobbles() -> Array:
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
	return [img, id, mortar]


## Stones that lie entirely inside one 16px tile without touching its border: editing only these keeps
## every tile edge identical to the base cobbles, so variant tiles mix with base tiles seamlessly.
## Returns {stone id: Array[Vector2i] pixels}.
func _interior_stones(id: Array, mortar: Array) -> Dictionary:
	var px := {}
	var bad := {}
	for y in 64:
		for x in 64:
			if mortar[y * 64 + x]:
				continue
			var s: int = id[y * 64 + x]
			if not px.has(s):
				px[s] = [Vector2i(x, y)]
			else:
				px[s].append(Vector2i(x, y))
			var first: Vector2i = px[s][0]
			if x % T == 0 or y % T == 0 or x % T == T - 1 or y % T == T - 1 \
					or x / T != first.x / T or y / T != first.y / T:
				bad[s] = true
	var out := {}
	for s: int in px:
		if not bad.has(s):
			out[s] = px[s]
	return out


## Pixels of mortar at least 2px inside their tile (safe to recolour without a seam).
func _inner_mortar(mortar: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in 64:
		for x in 64:
			if mortar[y * 64 + x] and x % T >= 2 and x % T <= T - 3 and y % T >= 2 and y % T <= T - 3:
				out.append(Vector2i(x, y))
	return out


## Variant "worn": interior stones retoned lighter/darker, some sunken (dark with a lit lower lip).
func _worn(src: Image, id: Array, mortar: Array) -> Image:
	var img: Image = src.duplicate()
	var stones := _interior_stones(id, mortar)
	for s: int in stones:
		var pixels: Array = stones[s]
		var r := rng.randf()
		if r < 0.35:
			_shift_tone(img, pixels, 1)
		elif r < 0.7:
			_shift_tone(img, pixels, -1)
		else:   # sunken: darker, lit lip along the bottom edge (light comes from the camera side)
			_shift_tone(img, pixels, -2)
			for p: Vector2i in pixels:
				var below_mortar: bool = p.y < 63 and mortar[(p.y + 1) * 64 + p.x]
				if below_mortar:
					img.set_pixel(p.x, p.y, FLOOR[2])
	for p in _inner_mortar(mortar):
		if rng.randf() < 0.08:
			img.set_pixel(p.x, p.y, FLOOR[0])     # grit in the joints
	return img


## Variant "damaged": interior stones cracked or missing (dirt), moss creeping along the joints.
func _damaged(src: Image, id: Array, mortar: Array) -> Image:
	var img: Image = src.duplicate()
	var stones := _interior_stones(id, mortar)
	for s: int in stones:
		var pixels: Array = stones[s]
		var r := rng.randf()
		if r < 0.35 and pixels.size() > 12:
			_crack_stone(img, pixels)
		elif r < 0.55:   # missing stone: a pit of dirt and pebbles, shadowed under the top edge
			for p: Vector2i in pixels:
				var above_mortar: bool = mortar[(p.y - 1) * 64 + p.x] if p.y > 0 else true
				var c: Color = DIRT[0] if above_mortar else DIRT[1 + int(rng.randf() < 0.3)]
				if rng.randf() < 0.08:
					c = FLOOR[3]
				img.set_pixel(p.x, p.y, c)
		elif r < 0.7:
			_shift_tone(img, pixels, -1)
	for p in _inner_mortar(mortar):
		if rng.randf() < 0.45:
			img.set_pixel(p.x, p.y, MOSS[int(rng.randf() < 0.3) + 1])
	return img


func _shift_tone(img: Image, pixels: Array, by: int) -> void:
	for p: Vector2i in pixels:
		var i := FLOOR.find(img.get_pixel(p.x, p.y))
		if i >= 0:
			img.set_pixel(p.x, p.y, FLOOR[clampi(i + by, 0, 4)])


## A jagged 1px crack across a stone, with a lit pixel under it.
func _crack_stone(img: Image, pixels: Array) -> void:
	var lo := Vector2i(999, 999)
	var hi := Vector2i(-1, -1)
	var inside := {}
	for p: Vector2i in pixels:
		lo = lo.min(p)
		hi = hi.max(p)
		inside[p] = true
	var y := (lo.y + hi.y) / 2 + rng.randi_range(-1, 1)
	for x in range(lo.x, hi.x + 1):
		if rng.randf() < 0.35:
			y += rng.randi_range(-1, 1)
		var p := Vector2i(x, y)
		if inside.has(p):
			img.set_pixel(p.x, p.y, FLOOR_MORTAR)
			if inside.has(p + Vector2i(0, 1)):
				img.set_pixel(p.x, p.y + 1, FLOOR[3])


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


## 32x64 free-standing pillar face (2 tiles wide, 4 rows tall): big staggered blocks, outlined sides,
## lit left edge, shaded right edge (hints at the side face), dark at the floor.
func _pillar_face() -> Image:
	var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
	var bh := 8
	for row in 64 / bh:
		var x0 := -((row % 2) * 9) - rng.randi_range(0, 2)
		while x0 < 32:
			var w: int = [10, 13, 15][rng.randi() % 3]
			var base: int = [1, 2, 2, 3][rng.randi() % 4]
			for y in bh:
				for dx in w:
					var px := x0 + dx
					if px < 0 or px >= 32:
						continue
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
					img.set_pixel(px, row * bh + y, c)
			x0 += w
	for y in 64:
		for x in [1, 2]:
			var c := img.get_pixel(x, y)
			if c != BRICK_MORTAR:
				img.set_pixel(x, y, BRICK[mini(BRICK.find(c) + (2 if x == 1 else 1), 4)])
		for x in [28, 29, 30]:
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, c.darkened(0.18 + 0.12 * (x - 28)))
		img.set_pixel(0, y, OUTLINE)
		img.set_pixel(31, y, OUTLINE)
	for y in range(57, 64):
		var k := 1.0 - 0.08 * (y - 56)
		for x in range(1, 31):
			var c := img.get_pixel(x, y)
			img.set_pixel(x, y, Color(c.r * k, c.g * k, c.b * k))
	return img


## 32x16 pillar top seen from above: lit slab, outlined, dark front lip.
func _pillar_top() -> Image:
	var img := Image.create(32, T, false, Image.FORMAT_RGBA8)
	for y in T:
		for x in 32:
			var b := 2
			if y == 1:
				b = 4
			elif y == 2:
				b = 3
			elif y >= T - 2:
				b = 0
			elif x >= 27:
				b = 1
			elif rng.randf() < 0.07:
				b = 1
			var c: Color = CAP[b]
			if y == 0 or x == 0 or x == 31:
				c = OUTLINE
			elif x == 15 and y > 2 and y < T - 2:
				c = CAP[0]
			img.set_pixel(x, y, c)
	return img


## 32x16 jagged top of a broken pillar (face row 2 with the stone above a ragged line knocked off).
func _broken_top(face: Image) -> Image:
	var img := Image.create(32, T, false, Image.FORMAT_RGBA8)
	img.blit_rect(face, Rect2i(0, 16, 32, T), Vector2i.ZERO)
	var top := rng.randi_range(4, 8)
	for x in 32:
		if rng.randf() < 0.45:
			top = clampi(top + rng.randi_range(-2, 2), 2, 11)
		for y in T:
			if y < top - 1:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
			elif y == top - 1:
				img.set_pixel(x, y, OUTLINE)
			elif y < top + 2 and x > 0 and x < 31:
				img.set_pixel(x, y, CAP[4 if y == top else 3])   # fresh broken surface catches the light
	return img


# ------------------------------------------------------------------ art: decals
func _decals() -> Image:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for i in 4:
		img.blit_rect(_moss(16, 16, 5.5), Rect2i(0, 0, T, T), Vector2i(i * T, 0))
	img.blit_rect(_moss(32, 32, 12.0), Rect2i(0, 0, 32, 32), Vector2i(64, 0))
	for i in 2:
		img.blit_rect(_wall_moss(), Rect2i(0, 0, T, T), Vector2i(96 + i * T, 0))
	for i in 3:
		img.blit_rect(_splat(), Rect2i(0, 0, T, T), Vector2i(i * T, T))
	img.blit_rect(_smear(), Rect2i(0, 0, T, T), Vector2i(48, T))
	img.blit_rect(_blood_pool(), Rect2i(0, 0, 32, T), Vector2i(96, T))
	for i in 4:
		img.blit_rect(_crack(), Rect2i(0, 0, T, T), Vector2i(i * T, 32))
	img.blit_rect(_puddle(), Rect2i(0, 0, 32, T), Vector2i(64, 32))
	img.blit_rect(_contact_shadow(), Rect2i(0, 0, T, T), Vector2i(96, 32))
	var skull := Image.create(T, T, false, Image.FORMAT_RGBA8)
	_skull(skull, Vector2i(4, 5))
	_outline(skull)
	img.blit_rect(skull, Rect2i(0, 0, T, T), Vector2i(112, 32))
	for i in 2:
		img.blit_rect(_loose_bones(), Rect2i(0, 0, T, T), Vector2i(i * T, 48))
	img.blit_rect(_chain(), Rect2i(0, 0, 32, T), Vector2i(32, 48))
	for i in 4:
		img.blit_rect(_rubble(), Rect2i(0, 0, T, T), Vector2i(64 + i * T, 48))
	var pile := _bone_pile()
	img.blit_rect(pile, Rect2i(0, 0, 48, 32), Vector2i(0, 64))
	var pile_l := _bone_pile()
	pile_l.flip_x()
	img.blit_rect(pile_l, Rect2i(0, 0, 48, 32), Vector2i(48, 64))
	return img


## Noisy blob of moss, denser in the middle, ragged edge so it creeps into the floor.
func _moss(w: int, h: int, r: float) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c := Vector2(w, h) * 0.5
	var lumps: Array[Vector3] = []
	for i in 4:
		lumps.append(Vector3(c.x + rng.randf_range(-r, r) * 0.5, c.y + rng.randf_range(-r, r) * 0.35,
				r * rng.randf_range(0.45, 0.8)))
	for y in h:
		for x in w:
			var best := 9.0
			for l: Vector3 in lumps:
				best = minf(best, Vector2((x + 0.5 - l.x) / l.z, (y + 0.5 - l.y) / (l.z * 0.62)).length())
			var n := best + rng.randf_range(-0.25, 0.25)
			if n < 0.55:
				img.set_pixel(x, y, MOSS[3] if rng.randf() < 0.2 else MOSS[2])
			elif n < 0.85:
				img.set_pixel(x, y, MOSS[1] if rng.randf() < 0.7 else MOSS[2])
			elif n < 1.1 and rng.randf() < 0.5:
				img.set_pixel(x, y, MOSS[0])
	return img


## Moss hugging the foot of a wall: thick at the top edge, fraying downwards.
func _wall_moss() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	for x in T:
		var depth := rng.randi_range(2, 7)
		for y in depth:
			var k := float(y) / depth
			if rng.randf() < 1.0 - k * 0.6:
				img.set_pixel(x, y, MOSS[3] if (y == 0 and rng.randf() < 0.4) else MOSS[2 if k < 0.4 else 1])
		if rng.randf() < 0.3:
			img.set_pixel(x, depth + rng.randi_range(0, 2), MOSS[0])
	return img


func _splat() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var c := Vector2(rng.randf_range(6, 10), rng.randf_range(6, 9))
	var r := rng.randf_range(2.5, 4.0)
	_ellipse(img, c, r, r * 0.62, BLOOD[1])
	_ellipse(img, c + Vector2(-0.6, -0.5), r * 0.6, r * 0.35, BLOOD[2])
	img.set_pixel(int(c.x) - 1, int(c.y) - 1, BLOOD[3])
	for i in rng.randi_range(5, 9):    # droplets flung outwards, squashed by the view
		var a := rng.randf() * TAU
		var d := r + rng.randf_range(1.0, 5.0)
		var p := Vector2i(c + Vector2(cos(a) * d, sin(a) * d * 0.62))
		if Rect2i(0, 0, T, T).has_point(p):
			img.set_pixel(p.x, p.y, BLOOD[1 + int(rng.randf() < 0.3)])
	return img


func _smear() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var y := 6.0
	for x in range(1, 15):
		y += rng.randf_range(-0.5, 0.5)
		var thick := 3 if x < 6 else (2 if x < 11 else 1)
		for k in thick:
			img.set_pixel(x, int(y) + k, BLOOD[1 if k > 0 else 2])
	return img


func _blood_pool() -> Image:
	var img := Image.create(32, T, false, Image.FORMAT_RGBA8)
	_ellipse(img, Vector2(15, 8), 10.5, 5.0, BLOOD[0])
	_ellipse(img, Vector2(15, 7.6), 9.5, 4.2, BLOOD[1])
	_ellipse(img, Vector2(13, 7), 6.0, 2.5, BLOOD[2])
	for x in range(10, 14):
		img.set_pixel(x, 5, BLOOD[3])
	for i in 6:
		var p := Vector2i(rng.randi_range(2, 29), rng.randi_range(1, 14))
		if img.get_pixel(p.x, p.y).a == 0.0:
			img.set_pixel(p.x, p.y, BLOOD[1])
	return img


## Branching hairline crack across the flagstones.
func _crack() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	var p := Vector2(rng.randf_range(1, 4), rng.randf_range(4, 11))
	var dir := Vector2(1, rng.randf_range(-0.4, 0.4)).normalized()
	for i in 16:
		var q := Vector2i(p)
		if not Rect2i(0, 0, T, T).has_point(q):
			break
		img.set_pixel(q.x, q.y, FLOOR_MORTAR)
		if q.y + 1 < T and rng.randf() < 0.6:
			img.set_pixel(q.x, q.y + 1, FLOOR[3])
		if rng.randf() < 0.18:    # a short branch
			var b := Vector2i(q.x, q.y + (1 if rng.randf() < 0.5 else -1) * 2)
			if Rect2i(0, 0, T, T).has_point(b):
				img.set_pixel(b.x, b.y, FLOOR_MORTAR)
		dir = dir.rotated(rng.randf_range(-0.5, 0.5))
		dir.x = maxf(dir.x, 0.3)
		p += dir.normalized()
	return img


func _puddle() -> Image:
	var img := Image.create(32, T, false, Image.FORMAT_RGBA8)
	_ellipse(img, Vector2(16, 8), 12.0, 5.5, WATER[0])
	_ellipse(img, Vector2(16, 8), 11.0, 4.6, WATER[1])
	_ellipse(img, Vector2(17, 8.5), 8.0, 3.0, WATER[2])
	for x in range(9, 15):       # reflection of the light above
		img.set_pixel(x, 6, WATER[3])
	img.set_pixel(10, 6, WATER[4])
	img.set_pixel(20, 10, WATER[3])
	img.set_pixel(21, 10, WATER[3])
	return img


## Soft dark band at the top of the floor tile right in front of a pillar's base.
func _contact_shadow() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	for y in 4:
		for x in T:
			img.set_pixel(x, y, Color(0, 0, 0, [0.5, 0.36, 0.22, 0.1][y]))
	return img


## 7x7 skull at `o` (top-left): dome, eye sockets, nose, teeth. Lit from the top-left.
func _skull(img: Image, o: Vector2i) -> void:
	var rows := [".XXXXX.", "XXXXXXX", "XOOXOOX", "XOOXOOX", "XXX.XXX", ".XXXXX.", ".X.X.X."]
	for y in rows.size():
		for x in 7:
			var ch: String = rows[y][x]
			if ch == ".":
				if y == 4 and x == 3:
					img.set_pixel(o.x + x, o.y + y, OUTLINE)
				continue
			var c: Color = BONE[2]
			if ch == "O":
				c = OUTLINE
			elif y <= 1 and x <= 3:
				c = BONE[3]
			elif x >= 5 or y >= 5:
				c = BONE[1]
			img.set_pixel(o.x + x, o.y + y, c)


## A bone from a to b: 1-2px shaft with knobbly ends.
func _bone(img: Image, a: Vector2, b: Vector2) -> void:
	var n := int(a.distance_to(b)) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		_px(img, Vector2i(p), BONE[2])
		_px(img, Vector2i(p) + Vector2i(0, 1), BONE[1])
	var side := (b - a).normalized().orthogonal()
	for e: Vector2 in [a, b]:
		_px(img, Vector2i(e + side), BONE[3])
		_px(img, Vector2i(e - side), BONE[2])
		_px(img, Vector2i(e - side) + Vector2i(0, 1), BONE[1])


func _px(img: Image, p: Vector2i, c: Color) -> void:
	if p.x >= 0 and p.y >= 0 and p.x < img.get_width() and p.y < img.get_height():
		img.set_pixel(p.x, p.y, c)


func _loose_bones() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	for i in 2:
		var c := Vector2(rng.randf_range(5, 11), rng.randf_range(5, 11))
		var a := rng.randf() * PI
		var l := rng.randf_range(3.0, 5.0)
		_bone(img, c - Vector2(cos(a), sin(a) * 0.62) * l, c + Vector2(cos(a), sin(a) * 0.62) * l)
	_outline(img)
	return img


## A slack length of iron chain lying on the floor: alternating face-on rings and edge-on links.
func _chain() -> Image:
	var img := Image.create(32, T, false, Image.FORMAT_RGBA8)
	var x := 2.0
	var i := 0
	while x < 29.0:
		var y := 7.0 + sin(x * 0.2) * 2.5
		if i % 2 == 0:
			for k in 8:
				var a := TAU * k / 8.0
				_px(img, Vector2i(roundi(x + 1.5 + cos(a) * 1.6), roundi(y + sin(a) * 1.2)), IRON[2 if k >= 4 else 1])
		else:
			for k in 3:
				_px(img, Vector2i(int(x) + k, int(y)), IRON[2])
				_px(img, Vector2i(int(x) + k, int(y) + 1), IRON[0])
		x += 3.0
		i += 1
	_outline(img)
	return img


## Chunks of broken masonry (no collision): top-lit blocks with an outline.
func _rubble() -> Image:
	var img := Image.create(T, T, false, Image.FORMAT_RGBA8)
	for i in rng.randi_range(2, 4):
		var w := rng.randi_range(2, 5)
		var h := rng.randi_range(2, 3)
		var o := Vector2i(rng.randi_range(1, T - w - 1), rng.randi_range(4, T - h - 2))
		for y in h:
			for x in w:
				if (x == 0 or x == w - 1) and y == 0 and rng.randf() < 0.5:
					continue       # chipped corners
				_px(img, o + Vector2i(x, y), CAP[4 if y == 0 else (1 if y == h - 1 else 2)])
	_outline(img)
	return img


## 48x32 heap of bones and skulls piled into a corner (against walls behind and to the right).
func _bone_pile() -> Image:
	var img := Image.create(48, 32, false, Image.FORMAT_RGBA8)
	var height := func(x: float) -> float:    # mound profile, highest towards the corner (right)
		var u := (x - 32.0) / 26.0
		return maxf(0.0, 24.0 * (1.0 - u * u)) if x < 32.0 else 24.0 - (x - 32.0) * 0.55
	var mask := func(x: int, y: int) -> bool: return height.call(x) > 1.0 and y >= 30 - height.call(x) and y <= 30
	for y in 32:     # dark interstices so the heap reads solid
		for x in 48:
			if mask.call(x, y):
				img.set_pixel(x, y, Color("1e1913"))
	var bones: Array[Vector3] = []
	for i in 70:
		var p := Vector2(rng.randf_range(4, 47), rng.randf_range(4, 30))
		if mask.call(int(p.x), int(p.y)):
			bones.append(Vector3(p.x, p.y, rng.randf() * PI))
	bones.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)   # back to front
	for b: Vector3 in bones:
		var d := Vector2(cos(b.z), sin(b.z) * 0.62) * rng.randf_range(2.5, 5.0)
		_bone(img, Vector2(b.x, b.y) - d, Vector2(b.x, b.y) + d)
	for s: Vector2i in [Vector2i(30, 9), Vector2i(19, 18), Vector2i(36, 21), Vector2i(10, 24)]:
		_skull(img, s)
	for y in 32:    # trim to the mound so bones don't poke out into thin air
		for x in 48:
			if not mask.call(x, y) and y < 30 - height.call(x) - 2:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	_outline(img)
	return img


func _ellipse(img: Image, c: Vector2, rx: float, ry: float, col: Color) -> void:
	for y in img.get_height():
		for x in img.get_width():
			var nx := (x + 0.5 - c.x) / rx
			var ny := (y + 0.5 - c.y) / ry
			if nx * nx + ny * ny <= 1.0:
				img.set_pixel(x, y, col)


## 1px dark outline around every opaque shape (like the character sprite).
func _outline(img: Image) -> void:
	var out: Array[Vector2i] = []
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height() \
						and img.get_pixel(q.x, q.y).a > 0.9:
					out.append(Vector2i(x, y))
					break
	for o in out:
		img.set_pixel(o.x, o.y, OUTLINE)


# ------------------------------------------------------------------ tileset
func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(T, T)
	ts.add_physics_layer()
	var src := TileSetAtlasSource.new()
	src.texture = load(ART)
	src.texture_region_size = Vector2i(T, T)
	ts.add_source(src, 0)
	var full := PackedVector2Array([Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8)])
	var cells: Array[Vector2i] = []
	for y in 16:
		for x in 4:
			cells.append(Vector2i(x, y))
	for y in 8:
		for x in range(4, 8):
			cells.append(Vector2i(x, y))
	for y in range(8, 13):
		cells.append_array([Vector2i(4, y), Vector2i(5, y)])
	for y in range(9, 12):
		cells.append_array([Vector2i(6, y), Vector2i(7, y)])
	for c in cells:
		src.create_tile(c)
		var td := src.get_tile_data(c, 0)
		var solid := false
		if c.y >= 8 and c.y < 12:      # wall / pillar face: sort the whole face by its base line
			td.y_sort_origin = (11 - c.y) * T + T / 2
			solid = c.y == 11
		elif c.y == 12 and c.x >= 4:   # pillar top sits WALL_ROWS above the footprint
			td.y_sort_origin = WALL_ROWS * T + T / 2
		elif c.y >= 12:                # caps sit WALL_ROWS above the wall's footprint
			td.y_sort_origin = WALL_ROWS * T + T / 2
			solid = c.y != 15
		if solid:
			td.add_collision_polygon(0)
			td.set_collision_polygon_points(0, 0, full)
	var dec := TileSetAtlasSource.new()
	dec.texture = load(DECALS)
	dec.texture_region_size = Vector2i(T, T)
	ts.add_source(dec, 1)
	var dimg: Image = dec.texture.get_image()
	for y in 8:
		for x in 8:
			if not dimg.get_region(Rect2i(x * T, y * T, T, T)).is_invisible():
				dec.create_tile(Vector2i(x, y))
	ResourceSaver.save(ts, TILESET)
	return load(TILESET)


# ------------------------------------------------------------------ scene
var _floor_layer: TileMapLayer
var _decals_layer: TileMapLayer
var _walls: TileMapLayer
var _covered := {}       # cells hidden under pillar faces / tops, or holding a decal already


func _build_scene() -> void:
	var ts := _build_tileset()
	var world := Node2D.new()
	world.name = "World"
	world.y_sort_enabled = true
	world.set_script(load("res://scripts/dungeon.gd"))
	_floor_layer = TileMapLayer.new()
	_floor_layer.name = "Floor"
	_floor_layer.tile_set = ts
	_floor_layer.z_index = -1
	_decals_layer = TileMapLayer.new()
	_decals_layer.name = "Decals"
	_decals_layer.tile_set = ts
	_decals_layer.z_index = -1
	_walls = TileMapLayer.new()
	_walls.name = "Walls"
	_walls.tile_set = ts
	_walls.y_sort_enabled = true
	world.add_child(_floor_layer)
	world.add_child(_decals_layer)
	world.add_child(_walls)

	for y in range(FLOOR_TOP, H - 1):
		for x in range(1, W - 1):
			if y == FLOOR_TOP:
				_floor_layer.set_cell(Vector2i(x, y), 0, Vector2i(x % 4, 4 + y % 4))
			else:
				var r := rng.randf()
				var v := 0 if r < FLOOR_WEIGHTS[0] else (1 if r < FLOOR_WEIGHTS[0] + FLOOR_WEIGHTS[1] else 2)
				var atlas: Vector2i = [Vector2i(x % 4, y % 4), Vector2i(4 + x % 4, y % 4), Vector2i(4 + x % 4, 4 + y % 4)][v]
				_floor_layer.set_cell(Vector2i(x, y), 0, atlas)
	for x in range(1, W - 1):
		_walls.set_cell(Vector2i(x, 0), 0, Vector2i(x % 4, 12))                 # back wall cap
		for r in WALL_ROWS:
			_walls.set_cell(Vector2i(x, 1 + r), 0, Vector2i(x % 4, 8 + r))     # back wall face
		_walls.set_cell(Vector2i(x, H - 2), 0, Vector2i(x % 4, 12))             # low front wall
		_walls.set_cell(Vector2i(x, H - 1), 0, Vector2i(x % 4, 11))
	for y in H:
		_walls.set_cell(Vector2i(0, y), 0, Vector2i(y % 4, 13))                 # side walls (caps only:
		_walls.set_cell(Vector2i(W - 1, y), 0, Vector2i(y % 4, 14))             # their faces are edge-on)
	var obstacles: Array[Rect2] = []
	for p: Vector2i in PILLARS:
		for dx in 2:
			_walls.set_cell(p + Vector2i(dx, -WALL_ROWS), 0, Vector2i(4 + dx, 12))
			for r in WALL_ROWS:
				_walls.set_cell(p + Vector2i(dx, r - WALL_ROWS + 1), 0, Vector2i(4 + dx, 8 + r))
			for r in WALL_ROWS + 1:
				_covered[p + Vector2i(dx, -r)] = true
		obstacles.append(Rect2(p * T, Vector2(2 * T, T)))
	for p: Vector2i in BROKEN_PILLARS:
		for dx in 2:
			for r in 3:
				_walls.set_cell(p + Vector2i(dx, r - 2), 0, Vector2i(6 + dx, 9 + r))
				_covered[p + Vector2i(dx, r - 2)] = true
		obstacles.append(Rect2(p * T, Vector2(2 * T, T)))
	_place_decals()

	var owned: Array[Node] = [_floor_layer, _decals_layer, _walls]
	for i in DUMMY_SPOTS.size():                                               # practice dummies
		var d: Node2D = load("res://scenes/dummy.tscn").instantiate()
		d.name = "Dummy%d" % (i + 1)
		d.position = DUMMY_SPOTS[i]
		world.add_child(d)
		owned.append(d)
		obstacles.append(Rect2(DUMMY_SPOTS[i] - Vector2(8, 5), Vector2(16, 10)))
	var nav := NavigationRegion2D.new()
	nav.name = "Navigation"
	nav.navigation_polygon = _bake_navigation(obstacles)
	world.add_child(nav)
	owned.append(nav)
	var spawns := Node2D.new()
	spawns.name = "Spawns"
	world.add_child(spawns)
	owned.append(spawns)
	for i in GREMLIN_SPAWNS.size():
		owned.append(_marker(spawns, "GremlinSpawn%d" % (i + 1), GREMLIN_SPAWNS[i], &"gremlin_spawn"))
	for id: StringName in PEDAL_SPAWNS:
		var m := _marker(spawns, "PedalSpawn_%s" % id, PEDAL_SPAWNS[id], &"pedal_spawn")
		m.set_meta(&"pedal_id", id)
		owned.append(m)

	var player: Node2D = load("res://scenes/player.tscn").instantiate()
	player.position = PLAYER_START
	world.add_child(player)
	owned.append(player)
	for n in owned:
		n.owner = world
	var packed := PackedScene.new()
	packed.pack(world)
	ResourceSaver.save(packed, SCENE)
	world.free()
	print("wrote ", SCENE)


func _marker(parent: Node, node_name: String, cell: Vector2i, group: StringName) -> Marker2D:
	var m := Marker2D.new()
	m.name = node_name
	m.position = Vector2(cell * T) + Vector2(T, T) * 0.5
	m.add_to_group(group, true)
	parent.add_child(m)
	return m


## Navigation mesh over the walkable floor with pillars, rubble and dummies cut out, shrunk by the
## agent radius so NavigationAgent2D paths keep enemies off the walls.
func _bake_navigation(obstacles: Array[Rect2]) -> NavigationPolygon:
	var poly := NavigationPolygon.new()
	poly.agent_radius = NAV_AGENT_RADIUS
	var geo := NavigationMeshSourceGeometryData2D.new()
	var walk := Rect2(Vector2(T, FLOOR_TOP * T), Vector2((W - 2) * T, (H - 2 - FLOOR_TOP) * T))
	geo.add_traversable_outline(_rect_outline(walk))
	for r in obstacles:
		geo.add_obstruction_outline(_rect_outline(r))
	NavigationServer2D.bake_from_source_geometry_data(poly, geo)
	print("navigation: ", poly.get_polygon_count(), " polygons")
	return poly


func _rect_outline(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Scatter the decals: moss along walls and pillar bases, blood (a trail running to the bone pile),
## cracks, puddles, loose bones, chains, rubble round the broken pillars, bone piles in two corners.
func _place_decals() -> void:
	var put := func(cell: Vector2i, atlas: Vector2i, size: Vector2i) -> bool:
		for y in size.y:
			for x in size.x:
				var c := cell + Vector2i(x, y)
				if _covered.has(c) or c.x < 1 or c.x > W - 2 or c.y < FLOOR_TOP or c.y > H - 3:
					return false
		for y in size.y:
			for x in size.x:
				_decals_layer.set_cell(cell + Vector2i(x, y), 1, atlas + Vector2i(x, y))
				_covered[cell + Vector2i(x, y)] = true
		return true
	# fixed set pieces
	put.call(Vector2i(W - 4, FLOOR_TOP), Vector2i(0, 4), Vector2i(3, 2))     # bone pile, top-right corner
	put.call(Vector2i(1, H - 4), Vector2i(3, 4), Vector2i(3, 2))             # bone pile, bottom-left corner
	put.call(Vector2i(W - 7, FLOOR_TOP + 2), Vector2i(6, 1), Vector2i(2, 1))  # pool by the heap
	var trail := Vector2(W - 8, FLOOR_TOP + 3)
	for i in 9:                                                              # drag trail into the room
		trail += Vector2(-1.3, 0.8)
		put.call(Vector2i(trail), Vector2i([0, 3, 1, 3, 2][i % 5], 1), Vector2i.ONE)
	for p in [Vector2i(30, 30), Vector2i(10, 15), Vector2i(36, 32), Vector2i(48, 19), Vector2i(22, 26)]:
		put.call(p, Vector2i(4, 2), Vector2i(2, 1))                          # puddles
	for p in [Vector2i(20, 16), Vector2i(40, 26), Vector2i(6, 22), Vector2i(29, 6), Vector2i(53, 22), Vector2i(17, 33)]:
		put.call(p, Vector2i(4, 0), Vector2i(2, 2))                          # big moss patches
	for p: Vector2i in PILLARS + BROKEN_PILLARS:                             # contact shadow at the base
		for dx in 2:
			put.call(p + Vector2i(dx, 1), Vector2i(6, 2), Vector2i.ONE)
	for p: Vector2i in BROKEN_PILLARS:                                       # fallen masonry around breaks
		for c: Vector2i in [p + Vector2i(-1, 0), p + Vector2i(2, 0), p + Vector2i(-1, 1), p + Vector2i(2, 1),
				p + Vector2i(0, 2), p + Vector2i(1, 2)]:
			if rng.randf() < 0.75:
				put.call(c, Vector2i(4 + rng.randi() % 4, 3), Vector2i.ONE)
	for x in range(1, W - 1):                                                # moss at the back wall's foot
		if rng.randf() < 0.3:
			put.call(Vector2i(x, FLOOR_TOP), Vector2i(6 + rng.randi() % 2, 0), Vector2i.ONE)
	for p: Vector2i in [Vector2i(18, FLOOR_TOP), Vector2i(41, FLOOR_TOP), Vector2i(W - 6, H - 3)]:
		put.call(p, Vector2i(2, 3), Vector2i(2, 1))                          # chains
	# random scatter; keep the player start readable
	for y in range(FLOOR_TOP, H - 2):
		for x in range(1, W - 1):
			var c := Vector2i(x, y)
			if Vector2(c * T).distance_to(PLAYER_START) < 40.0:
				continue
			var r := rng.randf()
			if r < 0.025:
				put.call(c, Vector2i(rng.randi() % 4, 2), Vector2i.ONE)       # crack
			elif r < 0.06:
				put.call(c, Vector2i(rng.randi() % 4, 0), Vector2i.ONE)       # moss tuft
			elif r < 0.077:
				put.call(c, Vector2i(rng.randi() % 3, 1), Vector2i.ONE)       # blood splat
			elif r < 0.085:
				put.call(c, Vector2i(rng.randi() % 2, 3), Vector2i.ONE)       # loose bones
			elif r < 0.088:
				put.call(c, Vector2i(7, 2), Vector2i.ONE)                     # skull


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
