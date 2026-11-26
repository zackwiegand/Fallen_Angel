extends SceneTree
func _init():
	var base: Node = load("res://assets/rocker/rocker_base.glb").instantiate()
	_dump(base, "")
	var sk: Skeleton3D = base.find_children("*", "Skeleton3D", true, false)[0]
	print("bones: ", sk.get_bone_count(), " ", range(sk.get_bone_count()).map(func(i): return sk.get_bone_name(i)))
	var ap: AnimationPlayer = base.find_children("*", "AnimationPlayer", true, false)[0]
	for n in ap.get_animation_list():
		var a := ap.get_animation(n)
		print(n, " len ", a.length, " tracks ", a.get_track_count(), " first ", a.track_get_path(0))
	for f in ["res://assets/gear/armor_gothic_plate.glb", "res://assets/rocker/rocker_base.glb"]:
		var g: Node = load(f).instantiate()
		var mi: MeshInstance3D = g.find_children("*", "MeshInstance3D", true, false)[0]
		print(f, " skin binds ", mi.skin.get_bind_count(), " name0='", mi.skin.get_bind_name(0), "' bone0=", mi.skin.get_bind_bone(0))
		print("  mats ", range(mi.mesh.get_surface_count()).map(func(i): return mi.mesh.surface_get_material(i).resource_name))
	quit()
func _dump(n: Node, ind: String):
	print(ind, n.name, " (", n.get_class(), ")")
	for c in n.get_children(): _dump(c, ind + "  ")
