class_name RockerRig
extends Node3D
## The 3D rocker that gets rendered into a sprite. Lives inside the character's SubViewport.
##
## Layering: rocker_base.glb holds the skeleton, the body mesh and every animation. Gear is
## additive: skinned gear files (armor, boots) carry the same skeleton, and their meshes are
## re-parented onto the base Skeleton3D, so the base animations drive them. Guitars hang on a
## BoneAttachment3D on the "guitar" bone (the baked prop placement the hands are IK'd to).

signal action_finished(action: StringName)
## Timed moments in the motion (footfalls, strum hit, swing whoosh) for sound / effects.
signal anim_event(event: StringName)

const BASE_SCENE := preload("res://assets/rocker/rocker_base.glb")
const LOOPING := ["idle", "walk"]
const ACTIONS := [&"strum", &"swing", &"cast"]
## Seconds into each baked clip (times from sprite-poc anims.py):
##   walk: heel strikes at phase 0 and 0.5 of the 1.333 s cycle
##   strum: the picking hand slams the strings at phase 0.6 (1.0 s clip)
##   swing: contact is phase 0.47-0.62 (= seconds); the whoosh peaks SfxSynth.SWING_PEAK after its start
##   cast: the thrust releases at phase 0.45 of the 0.857 s clip (export_gltf.py CAST_RELEASE)
const ANIM_EVENTS := {
	"walk": [[0.01, &"step"], [0.667, &"step"]],
	"strum": [[0.6, &"strum"]],
	"swing": [[0.28, &"swing"], [0.52, &"swing_hit"]],
	"cast": [[0.386, &"cast_release"]],
}
const GUITAR_TIP := Vector3(1.15, 0, 0)     # headstock end, guitar space (same for every guitar)

## > 0 steps the animation at this rate for a sprite-like look; 0 = smooth.
@export var anim_fps := 0.0

var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var anim_tree: AnimationTree
var hands: GuitarHands           # procedural fret/pick layer over idle & walk
var playback: AnimationNodeStateMachinePlayback
var equipped := {}          # slot -> item dictionary

var _model: Node3D
var _slot_nodes := {}       # slot -> Array[Node]
var _guitar_mount: Node3D
var _step_accum := 0.0
var _last_state: StringName
var _pending_action: StringName   # requested but not yet entered (travel is applied next tick)


func _ready() -> void:
	_model = BASE_SCENE.instantiate()
	add_child(_model)
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	anim_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	Toon.apply(_model)
	_slot_nodes["body"] = _model.find_children("*", "MeshInstance3D", true, false)

	var mount := BoneAttachment3D.new()
	mount.name = "GuitarBone"
	mount.bone_name = "guitar"
	skeleton.add_child(mount)
	# The guitar bone's frame comes through glTF in Blender (Z-up) axes while the guitar files are
	# converted to Y-up, so undo that conversion here: +90 deg about X maps glTF axes back to Blender's.
	_guitar_mount = Node3D.new()
	_guitar_mount.name = "GuitarMount"
	_guitar_mount.rotation_degrees.x = 90.0
	mount.add_child(_guitar_mount)
	_add_event_tracks()
	_build_anim_tree()
	hands = GuitarHands.new()
	hands.name = "GuitarHands"
	skeleton.add_child(hands)


# ---------------------------------------------------------------- gear
func equip(slot: String, item: Dictionary) -> void:
	for n: Node in _slot_nodes.get(slot, []):
		n.queue_free()
	_slot_nodes[slot] = []
	equipped[slot] = item
	if item.is_empty():
		return
	var scene: Node = load(item.scene).instantiate()
	var recolor: Dictionary = item.get("recolor", {})
	if slot == "guitar":
		_guitar_mount.add_child(scene)
		Toon.apply(scene, recolor)
		_slot_nodes[slot] = [scene]
		return
	# skinned gear: move its meshes onto our skeleton; the Skin binds resolve by bone name
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xform := mi.transform
		var skin := mi.skin
		mi.get_parent().remove_child(mi)
		mi.owner = null
		skeleton.add_child(mi)
		mi.transform = xform
		mi.skin = skin
		mi.skeleton = mi.get_path_to(skeleton)
		Toon.apply(mi, recolor)
		_slot_nodes[slot].append(mi)
	scene.free()


# ---------------------------------------------------------------- facing
## Snap to the nearest of 8 directions. yaw is the Godot Y rotation; the model faces +Z at 0.
func face(yaw: float) -> void:
	rotation.y = snappedf(yaw, PI / 4.0)


# ---------------------------------------------------------------- animation
## Method tracks calling _on_anim_event at ANIM_EVENTS times. The imported Animation resources are
## shared between instances, so only add them once.
func _add_event_tracks() -> void:
	var rig_path := _model.get_path_to(self)     # tracks resolve from the mixer root (the model)
	for anim_name: String in ANIM_EVENTS:
		var anim := anim_player.get_animation(anim_name)
		if anim.find_track(rig_path, Animation.TYPE_METHOD) != -1:
			continue
		var t := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(t, rig_path)
		for ev: Array in ANIM_EVENTS[anim_name]:
			anim.track_insert_key(t, ev[0], {"method": &"_on_anim_event", "args": [ev[1]]})


func _on_anim_event(event: StringName) -> void:
	anim_event.emit(event)


func _build_anim_tree() -> void:
	for n in LOOPING:
		anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	var sm := AnimationNodeStateMachine.new()
	for n in ["idle", "walk", "strum", "swing", "cast"]:
		var a := AnimationNodeAnimation.new()
		a.animation = n
		sm.add_node(n, a)
	# idle rest pose == strum frame 0, so idle <-> strum cuts; the swing gets real blends
	_link(sm, "Start", "idle", 0.0).advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO   # start idling without a travel()
	_link(sm, "idle", "walk", 0.15)
	_link(sm, "walk", "idle", 0.2)
	_link(sm, "idle", "strum", 0.0)
	_link(sm, "walk", "strum", 0.15)
	_link(sm, "idle", "swing", 0.1)
	_link(sm, "walk", "swing", 0.1)
	_link(sm, "strum", "idle", 0.0, true)
	_link(sm, "swing", "idle", 0.2, true)
	_link(sm, "idle", "cast", 0.1)
	_link(sm, "walk", "cast", 0.1)
	_link(sm, "cast", "idle", 0.15, true)

	anim_tree = AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.tree_root = sm
	_model.add_child(anim_tree)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.active = true
	if anim_fps > 0.0:
		anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	playback = anim_tree.get("parameters/playback")


func _link(sm: AnimationNodeStateMachine, from: String, to: String, xfade: float, at_end := false) -> AnimationNodeStateMachineTransition:
	var t := AnimationNodeStateMachineTransition.new()
	t.xfade_time = xfade
	if at_end:
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
		t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(from, to, t)
	return t


## Headstock position in the rig's 3D world (for spawning spells from the guitar).
func guitar_tip_world() -> Vector3:
	return _guitar_mount.global_transform * GUITAR_TIP


func is_busy() -> bool:
	return _pending_action != &"" or playback.get_current_node() in ACTIONS


## Locomotion: idle or walk (ignored while an action plays).
func set_moving(moving: bool) -> void:
	if not is_busy():
		playback.travel(&"walk" if moving else &"idle")


## One-shot actions: strum, swing or cast.
func play_action(action: StringName) -> void:
	if not is_busy():
		_pending_action = action
		playback.travel(action)


## Fret + pick note i (0..7) on the guitar, over whatever locomotion is playing.
func play_note(i: int) -> void:
	hands.note(i)


func _process(delta: float) -> void:
	var free_hands := not is_busy()
	if hands.active != free_hands:
		hands.active = free_hands
		hands.reset()
	if anim_fps > 0.0:
		_step_accum += delta
		var step := 1.0 / anim_fps
		while _step_accum >= step:
			_step_accum -= step
			anim_tree.advance(step)
	var state := playback.get_current_node()
	if state == _pending_action:
		_pending_action = &""
	if state != _last_state:
		if _last_state in ACTIONS:
			action_finished.emit(_last_state)
		_last_state = state
