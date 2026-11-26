extends SceneTree
## Headless check of the GuitarHands layer: no-op at rest, fretting hand lands on each note's neck
## spot (idle and walking), pick stroke moves the picking hand, off during actions.
##   godot --headless --path . -s tools/test_hands.gd
var fails: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)

func _initialize() -> void:
	_run.call_deferred()

# Modifier output only exists between the modifier running and skinning, so sample it there.
var _seen := {}

func _sample(rig: RockerRig) -> void:
	var sk := rig.skeleton
	var g := sk.get_bone_global_pose(sk.find_bone("guitar"))
	for side in ["L", "R"]:
		_seen[side] = sk.get_bone_global_pose(sk.find_bone("hand." + side)).origin
	_seen["neck_x"] = (g.affine_inverse() * _seen["L"]).x

func _hand(_rig: RockerRig, side: String) -> Vector3:
	return _seen[side]

## Fretting hand position along the neck, in guitar-space x (same units as GuitarHands / FRET_X).
func _neck_x(_rig: RockerRig) -> float:
	return _seen["neck_x"]

func _run() -> void:
	var rig := RockerRig.new()
	root.add_child(rig)
	await process_frame
	rig.equip("guitar", GearCatalog.ITEMS.guitar[0])
	rig.hands.modification_processed.connect(_sample.bind(rig))
	await create_timer(1.0).timeout
	check("rest grip at FRET_X (%.3f)" % _neck_x(rig), absf(_neck_x(rig) - GuitarHands.FRET_X) < 0.01)
	for state in ["idle", "walk"]:
		rig.set_moving(state == "walk")
		await create_timer(0.4).timeout
		for i in [0, 3, 7]:
			rig.play_note(i)
			await create_timer(0.15).timeout
			var want := lerpf(GuitarHands.NECK_LOW, GuitarHands.NECK_HIGH, i / 7.0)
			check("%s: note %d fret hand at %.2f (want %.2f)" % [state, i, _neck_x(rig), want], absf(_neck_x(rig) - want) < 0.05)
	rig.set_moving(false)
	await create_timer(GuitarHands.HOLD + GuitarHands.RETURN_TIME + 0.3).timeout
	check("drifts back to rest grip (%.3f)" % _neck_x(rig), absf(_neck_x(rig) - GuitarHands.FRET_X) < 0.01)
	# pick: the picking hand is pushed across the strings during a stroke, then left alone
	var peak := 0.0
	rig.play_note(2)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
		peak = maxf(peak, rig.hands.last_shift["R"])
	check("pick stroke moves picking hand (peak %.3f m)" % peak, peak > 0.06)
	await create_timer(0.3).timeout
	check("picking hand back on the baked pose (%.4f m)" % rig.hands.last_shift["R"], rig.hands.last_shift["R"] < 0.001)
	rig.play_action(&"swing")
	await create_timer(0.2).timeout
	check("layer off during swing", not rig.hands.active)
	print("FAILURES: ", fails.size())
	quit(fails.size())
