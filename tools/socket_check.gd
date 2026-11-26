extends SceneTree
## Checks the guitar mount: hand bones vs guitar socket nodes (should coincide, as baked in Blender).
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var rig := RockerRig.new()
	root.add_child(rig)
	await process_frame
	rig.equip("guitar", GearCatalog.ITEMS.guitar[0])
	rig.anim_tree.active = false
	rig.anim_player.play("idle"); rig.anim_player.seek(0.0, true); rig.anim_player.pause()
	await process_frame
	await process_frame
	var sk := rig.skeleton
	var g: Node3D = rig.find_children("guitar_reaper", "", true, false)[0]
	print("guitar node basis x(neck)=", g.global_basis.x.snapped(Vector3.ONE*0.01), " face(+Z local)=", g.global_basis.z.snapped(Vector3.ONE*0.01))
	print("guitar bone pose basis x=", (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("guitar"))).basis.x.snapped(Vector3.ONE*0.01))
	for pair in [["hand.L", "fret_socket"], ["hand.R", "strum_socket"]]:
		var hb := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(pair[0]))
		var s: Node3D = rig.find_children(pair[1], "", true, false)[0]
		print(pair[0], " head ", hb.origin.snapped(Vector3.ONE*0.01), "  ", pair[1], " ", s.global_position.snapped(Vector3.ONE*0.01))
	quit()
