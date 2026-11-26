extends SceneTree
## Headless smoke test: animation state machine + gear cycling.
##   godot --headless --path . -s tools/test_logic.gd
func _initialize() -> void:
	_run.call_deferred()

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _wait(0.2)
	var p = main.get_node("Game/GameViewport/World/Player")
	var rig: RockerRig = p.rig
	var fails: Array[String] = []
	var check := func(label: String, ok: bool):
		print(("PASS " if ok else "FAIL ") + label)
		if not ok: fails.append(label)
	check.call("starts idle", rig.playback.get_current_node() == &"idle")
	Input.action_press("move_right"); await _wait(0.3)
	check.call("walks", rig.playback.get_current_node() == &"walk")
	Input.action_release("move_right"); await _wait(0.4)
	rig.play_action(&"swing"); await _wait(0.3)
	check.call("swing busy", rig.is_busy() and rig.playback.get_current_node() == &"swing")
	Input.action_press("move_right"); await _wait(0.1)
	check.call("can't walk mid-swing", rig.playback.get_current_node() == &"swing" and p.velocity == Vector2.ZERO)
	Input.action_release("move_right")
	await _wait(1.6)
	check.call("swing returns to idle", rig.playback.get_current_node() == &"idle")
	rig.play_action(&"strum"); await _wait(0.2)
	check.call("strums", rig.playback.get_current_node() == &"strum")
	await _wait(1.3)
	check.call("strum returns to idle", rig.playback.get_current_node() == &"idle")
	var sk := rig.skeleton
	for slot in GearCatalog.SLOTS:
		for i in GearCatalog.ITEMS[slot].size():
			p.cycle_gear(slot)
			await process_frame
	var meshes := sk.find_children("*", "MeshInstance3D", true, false).size()
	check.call("gear cycled back to defaults (body+armor+boots+guitar meshes = %d)" % meshes, meshes == 4)
	print("FAILURES: ", fails.size())
	quit(fails.size())
