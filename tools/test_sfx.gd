extends SceneTree
## Headless check: synthesized sounds (length, peak, crush levels) + animation event timing.
##   godot --headless --path . -s tools/test_sfx.gd
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var streams := {"step": SfxSynth.footstep(1), "swing": SfxSynth.swing(), "strum": SfxSynth.strum()}
	print("synth time %d ms" % (Time.get_ticks_msec() - t0))
	for k in streams:
		var w: AudioStreamWAV = streams[k]
		var peak := 0
		var levels := {}
		for i in range(0, w.data.size(), 2):
			var v := w.data.decode_s16(i)
			peak = maxi(peak, absi(v))
			levels[v] = true
		print("%s: %.2fs peak %.2f, %d distinct levels" % [k, w.get_length(), peak / 32767.0, levels.size()])

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var p = main.get_node("Game/GameViewport/World/Player")
	var rig: RockerRig = p.rig
	var log := []
	var start := [0]
	rig.anim_event.connect(func(e): log.append("%s@%.2f" % [e, (Time.get_ticks_msec() - start[0]) / 1000.0]))
	for test in [["walk", 2.0], ["strum", 1.3], ["swing", 1.6]]:
		log.clear()
		start[0] = Time.get_ticks_msec()
		if test[0] == "walk":
			Input.action_press("move_right")
		else:
			rig.play_action(StringName(test[0]))
		await create_timer(test[1]).timeout
		Input.action_release("move_right")
		await create_timer(0.4).timeout
		print(test[0], " events (s after start): ", log)
	quit()
