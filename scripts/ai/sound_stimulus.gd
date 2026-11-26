class_name SoundStimulus
## Sound stimuli for AI hearing. Anything loud calls SoundStimulus.emit(); every Perception in the tree hears
## it if it's within the radius (ground metres). Radii are gameplay values, not audio volumes.
##   SoundStimulus.emit(self, 9.0)                     # a guitar note heard 9 m away


static func emit(source: Node2D, radius_m: float, at: Variant = null) -> void:
	if source == null or not source.is_inside_tree():
		return
	var pos: Vector2 = source.global_position if at == null else at
	source.get_tree().call_group(Perception.GROUP, &"hear_noise", pos, radius_m, source)
