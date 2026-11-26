extends SceneTree
## Headless test: smooth camera scrolling (PixelCamera + main.gd shifting the upscaled view).
## Emulates the final window position of a fixed world point and of the player:
##   window px = (round(canvas origin + p) - margin) * PIXEL_SCALE + view shift
## While walking / running in any direction (away from the room edges) the world must scroll in even
## steps (per-frame step varies by <= 1 window px, i.e. no 0/1/2 game-px judder) and the player must stay
## within one game pixel on screen.
##   godot --headless --path . -s tools/test_camera.gd
const WATCHDOG_S := 60.0
const DIRS := [[&"move_right"], [&"move_up"], [&"move_right", &"move_up"], [&"move_left", &"move_down"],
		[&"move_left", &"move_up"]]

var fails: Array[String] = []


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL watchdog: test hung")
		quit(1))
	_run.call_deferred()


func _hold(actions: Array, pressed: bool) -> void:
	for a: StringName in actions:
		var ev := InputEventAction.new()
		ev.action = a
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var player: CharacterBody2D = main.get_node("Game/GameViewport/World/Player")
	var vp: Viewport = player.get_viewport()
	var enemies := main.get_node_or_null("Game/GameViewport/World/Enemies")
	if enemies:
		enemies.free()                                 # nothing should shove the player around
	var sprite: Sprite2D = player.sprite
	var game: Control = main.get_node("Game")
	var scale: int = main.PIXEL_SCALE
	var margin := PixelCamera.MARGIN_PX
	var to_window := func(p: Vector2) -> Vector2:
		var vp_px := (vp.canvas_transform.origin + p).round()
		return (vp_px - Vector2.ONE * margin) * scale + Vector2(game.offset_left + margin * scale,
				game.offset_top + margin * scale)
	var landmark := Vector2(300, 200)                  # any fixed point on the floor
	for dirs: Array in DIRS:
		for running in [false, true]:
			player.global_position = Vector2(470, 460)     # open floor, away from pillars and the room edges
			await physics_frame
			await process_frame
			player._last_tap.clear()                       # re-pressing an arrow mustn't count as a double-tap
			_hold(dirs, true)
			player.running = running                       # set directly (test_run covers the double-tap)
			for i in 15:                                   # get up to speed
				await process_frame
			var steps_x := []
			var steps_y := []
			var player_px := []
			var last: Vector2 = to_window.call(landmark)
			for i in 45:
				await process_frame
				var w: Vector2 = to_window.call(landmark)
				steps_x.append(w.x - last.x)
				steps_y.append(w.y - last.y)
				last = w
				player_px.append(to_window.call(sprite.global_position + sprite.offset))
			_hold(dirs, false)
			await create_timer(0.3).timeout
			var even: bool = steps_x.max() - steps_x.min() <= 1 and steps_y.max() - steps_y.min() <= 1
			var xs := player_px.map(func(v: Vector2) -> float: return v.x)
			var ys := player_px.map(func(v: Vector2) -> float: return v.y)
			var steady: bool = xs.max() - xs.min() <= scale and ys.max() - ys.min() <= scale
			var label := "%s %s" % ["run" if running else "walk", "+".join(dirs)]
			check("%s: world scrolls evenly (x steps %s..%s, y steps %s..%s window px)" % [label,
					steps_x.min(), steps_x.max(), steps_y.min(), steps_y.max()], even)
			check("%s: player within 1 game px on screen" % label, steady)
	print("ALL PASS" if fails.is_empty() else "FAILURES: %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
