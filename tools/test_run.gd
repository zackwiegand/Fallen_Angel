extends SceneTree
## Headless test: double-tap run, hold keeps running, grace buffer, walk <-> run phase sync.
##   godot --headless --path . -s tools/test_run.gd
const Player := preload("res://scripts/player.gd")

var fails: Array[String] = []
var p: CharacterBody2D
var rig: RockerRig


func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): print("FAIL watchdog: test hung"); quit(99))
	_run.call_deferred()


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


func _check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)


## Real input events, so the taps go through _unhandled_input like the keyboard.
func _key(action: StringName, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _tap(action: StringName, hold := 0.06) -> void:
	_key(action, true)
	await _wait(hold)
	_key(action, false)


func _speed() -> float:
	return Player.screen_to_ground(p.velocity).length() * Player.METRES_PER_PX


## How far the left boot is ahead of the right (m, skeleton space; the model faces +Z).
func _foot_lead() -> float:
	var sk := rig.skeleton
	var l := sk.get_bone_global_pose(sk.find_bone("foot.L")).origin
	var r := sk.get_bone_global_pose(sk.find_bone("foot.R")).origin
	return l.z - r.z


func _stop() -> void:
	for a: StringName in Player.MOVE_ACTIONS:
		_key(a, false)
	await _wait(Player.RUN_GRACE + 0.3)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.3)
	p = main.get_node("Game/GameViewport/World/Player")
	rig = p.rig

	# single press: walk
	_key(&"move_right", true)
	await _wait(0.3)
	_check("single press walks (%.2f m/s)" % _speed(), not p.running and is_equal_approx(_speed(), p.walk_speed))
	_check("walk clip", rig.playback.get_current_node() == &"walk")
	await _stop()

	# two taps too far apart: still a walk
	await _tap(&"move_right")
	await _wait(Player.RUN_TAP_WINDOW + 0.15)
	_key(&"move_right", true)
	await _wait(0.3)
	_check("slow taps don't run", not p.running)
	await _stop()

	# taps on different arrows: not a double-tap
	await _tap(&"move_left")
	_key(&"move_right", true)
	await _wait(0.3)
	_check("left then right doesn't run", not p.running)
	await _stop()

	# double-tap: run
	await _tap(&"move_right")
	await _wait(0.06)
	_key(&"move_right", true)
	await _wait(0.4)
	_check("double-tap runs (%.2f m/s)" % _speed(), p.running and is_equal_approx(_speed(), p.run_speed))
	_check("run clip", rig.playback.get_current_node() == &"run")

	# keeps running while held, also when changing direction with another arrow held
	_key(&"move_up", true)
	await _wait(0.1)
	_key(&"move_right", false)
	await _wait(0.5)
	_check("hold keeps running through a direction change", p.running and rig.playback.get_current_node() == &"run")

	# quick reversal: let go, press the opposite arrow inside the grace buffer
	_key(&"move_up", false)
	await _wait(Player.RUN_GRACE * 0.5)
	_key(&"move_down", true)
	await _wait(0.3)
	_check("quick reversal keeps the run", p.running and is_equal_approx(_speed(), p.run_speed))

	# release past the grace: run ends, walking again needs a fresh double-tap
	_key(&"move_down", false)
	await _wait(Player.RUN_GRACE + 0.1)
	_check("release ends the run", not p.running)
	await _wait(0.4)
	_check("idle after release", rig.playback.get_current_node() == &"idle")
	_key(&"move_down", true)
	await _wait(0.3)
	_check("next press walks", not p.running and rig.playback.get_current_node() == &"walk")

	# walk -> run keeps the stride: the same foot is forward before and after the double-tap
	for target: float in [0.45, 0.95]:
		while absf(rig.gait_phase() - target) > 0.04:
			await process_frame
		var before := _foot_lead()
		await _tap(&"move_down")          # the double-tap gap passes through idle for ~0.06 s
		_key(&"move_down", true)
		for i in 4:
			await process_frame
		var after := _foot_lead()
		_check("walk->run keeps the stride at phase %.2f (lead %+.2f -> %+.2f m)" % [target, before, after],
				p.running and signf(before) == signf(after) and absf(after) > 0.1)
		await _stop()
		_key(&"move_down", true)
		await _wait(0.3)
	await _stop()

	# an action from a run stops the character; holding the direction resumes the run afterwards
	await _tap(&"move_left")
	_key(&"move_left", true)
	await _wait(0.3)
	rig.play_action(&"swing")
	await _wait(0.3)
	_check("swing from run stops movement", rig.playback.get_current_node() == &"swing" and p.velocity == Vector2.ZERO)
	await _wait(1.6)
	_check("holding through the swing resumes running", p.running and rig.playback.get_current_node() == &"run")
	await _stop()

	print("FAILURES: ", fails.size())
	quit(fails.size())
