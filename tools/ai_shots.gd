extends SceneTree
## Captures frames of a scripted gremlin encounter: calm pacing, "!" alert, throw windup, fireball in
## flight, slash, and a pack circling while two attack. 3 x 2 sheet of 200x130 crops around the player, 3x.
##   godot --path . -s tools/ai_shots.gd -- <out.png>          (needs a window)

const GREMLIN := preload("res://scenes/enemies/gremlin.tscn")
const CROP := Vector2i(200, 130)

var main: Node
var world: Node2D
var player: CharacterBody2D
var vp: SubViewport
var shots: Array[Image] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): print("watchdog"); quit(99))
	_run.call_deferred()

func frames(sec: float) -> void:
	for i in int(sec * 60.0):
		await physics_frame

func off(gx_m: float, gy_m: float) -> Vector2:
	return Ground.to_screen(Vector2(gx_m, gy_m) / Ground.METRES_PER_PX)

func spawn(at: Vector2, face: Vector2) -> Gremlin:
	var g: Gremlin = GREMLIN.instantiate()
	g.spawn_point = at
	g.position = at
	world.add_child(g)
	g.facing = face
	return g

func grab(center: Vector2) -> void:
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	# world -> viewport pixels through the canvas transform (camera)
	var s := vp.get_canvas_transform() * center
	var r := Rect2i(Vector2i(s) - CROP / 2, CROP)
	r = r.intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	shots.append(img.get_region(r))

func clear() -> void:
	for c in world.get_children():
		if c is Gremlin or c is EnemyFireball:
			c.free()
	AttackTokens.reset()

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(0.4)
	world = main.get_node("Game/GameViewport/World")
	vp = main.get_node("Game/GameViewport")
	player = world.get_node("Player")
	if world.has_node("Enemies"):
		world.get_node("Enemies").free()
	var P := Vector2(500, 520)
	player.position = P

	# 1 calm: gremlin pacing, facing away from the player
	var g := spawn(P + off(-4.5, 0), Vector2(-1, 0))
	await frames(0.8)
	await grab(P + Vector2(-50, -10))
	# 2 alert: a note -> "!"
	player.play_note(0)
	player.play_note(2)
	await frames(0.15)
	await grab(P + Vector2(-50, -10))
	# 3 throw windup (ember in the claw)
	for i in 120:
		await physics_frame
		if g.brain.path() == "combat/throw" and g._telegraph > 0.6:
			break
	await grab(P + Vector2(-50, -10))
	# 4 fireball in flight
	for i in 60:
		await physics_frame
		if world.get_children().any(func(c): return c is EnemyFireball):
			break
	await frames(0.25)
	await grab(P + Vector2(-50, -10))
	# 5 slash up close
	clear()
	g = spawn(P + off(-1.6, 0), Vector2(1, 0))
	g.perception.notify_attacked(P)
	for i in 240:
		await physics_frame
		player.position = P
		if g.brain.path() == "combat/slash" and g.brain.current.sub.time_in_state > 0.28:
			break
	await grab(P + Vector2(-10, -10))
	# 6 pack: two attack, the rest circle
	clear()
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		var pg := spawn(P + off(cos(a) * 2.6, sin(a) * 2.6), -Vector2.from_angle(a))
		pg.perception.notify_attacked(P)
	await frames(1.6)
	player.position = P
	await grab(P + Vector2(0, -15))

	var w := CROP.x
	var h := CROP.y
	var sheet := Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, shots[i].get_size()), Vector2i(i % 3 * w, i / 3 * h))
	sheet.resize(sheet.get_width() * 3, sheet.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://ai_shots.png"
	sheet.save_png(out)
	print("saved ", out)
	quit()
