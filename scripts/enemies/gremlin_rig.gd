class_name GremlinRig
extends Node2D
## The devil-gremlin's sprite: a live render of assets/enemies/gremlin/gremlin.glb (built by
## blender/enemies/gremlin.py) in its own small transparent SubViewport, drawn 1:1 with the
## outline shader. Same camera as the rocker (fixed ortho, 38 deg down, METRES_PER_PX), so every
## creature shares one pixel scale. Feet (3D origin) sit at this node's origin, for y-sorting.
##
## Locomotion clips are in place; move the body at WALK_SPEED / GALLOP_SPEED so the claws stay planted.
## One-shot clips (throw, slash, hit) return to the last looping clip; death holds its last frame.

## Timed moments of the clips (method tracks): footfalls, fireball release, claw contact, death end.
signal anim_event(event: StringName)
## A one-shot clip (throw / slash / hit / death) reached its end.
signal action_finished(anim: StringName)

const SCENE := preload("res://assets/enemies/gremlin/gremlin.glb")
const OUTLINE := preload("res://shaders/sprite_outline.gdshader")
const PlayerScript := preload("res://scripts/player.gd")      # shared camera scale / tilt

const CANVAS_PX := 64               # room for the rear-up throw and the death roll
const CAM_TARGET_Y := 0.4           # rig camera looks at this height above the feet (m)
const WALK_SPEED := 0.429           # m/s that match the baked strides (gremlin.py WALK_SPEED)
const GALLOP_SPEED := 2.167         # (gremlin.py GALLOP_SPEED)
const BLEND := 0.12                 # cross-fade between clips (s)
const SHADOW_RADIUS := 8.0
const LOOPING: Array[StringName] = [&"idle", &"walk", &"gallop"]
## Seconds into each clip (gremlin.py: limb contact phases, THROW_RELEASE 0.55 of 1.0 s,
## SLASH_HIT 0.45 of 0.6 s).
const ANIM_EVENTS := {
	"walk": [[0.0, &"step"], [0.2, &"step"], [0.4, &"step"], [0.6, &"step"]],
	"gallop": [[0.0, &"step"], [0.2, &"step"]],
	"throw": [[0.55, &"throw_release"]],
	"slash": [[0.27, &"slash_hit"]],
	"death": [[0.98, &"death_done"]],
}

## Ground direction like player.facing (x = screen-right, y = away from the camera); the model
## snaps to the nearest of 8 directions.
var facing := Vector2(0, -1):
	set(v):
		if v != Vector2.ZERO:
			facing = v.normalized()
			if _model:
				_model.rotation.y = snappedf(atan2(facing.x, -facing.y), PI / 4.0)

var sprite: Sprite2D                 # e.g. for hit flashes (modulate / material)
var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var current: StringName = &"idle"

var _viewport: SubViewport
var _model: Node3D
var _loop: StringName = &"idle"
var _held_bone := -1


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "RigViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(CANVAS_PX, CANVAS_PX)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CANVAS_PX * PlayerScript.METRES_PER_PX
	cam.far = 60.0
	var target := Vector3(0, CAM_TARGET_Y, 0)
	var e := PlayerScript.ELEVATION
	_viewport.add_child(cam)
	cam.position = target + Vector3(0, sin(e), cos(e)) * 20.0
	cam.look_at(target)

	_model = SCENE.instantiate()
	_viewport.add_child(_model)
	Toon.apply(_model)
	skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	anim_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_held_bone = skeleton.find_bone("held")
	for n in LOOPING:
		anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	_add_event_tracks()
	anim_player.animation_finished.connect(_on_animation_finished)
	facing = facing

	sprite = Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = _viewport.get_texture()
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE
	sprite.material = mat
	sprite.offset = Vector2(0, -round(CAM_TARGET_Y * cos(e) / PlayerScript.METRES_PER_PX))
	add_child(sprite)
	anim_player.play(current)


## Play a clip: idle / walk / gallop loop; throw / slash / hit return to the last loop; death holds.
## Asking for the clip that is already looping keeps it running.
func play(anim: StringName) -> void:
	if anim in LOOPING:
		_loop = anim
		if current == anim and anim_player.is_playing():
			return
	current = anim
	anim_player.play(anim, BLEND)


func anim_length(anim: StringName) -> float:
	return anim_player.get_animation(anim).length


## The throwing claw (where a fireball leaves), relative to this node, in screen px.
func hand_point() -> Vector2:
	var g := hand_ground()
	return g[0] - Vector2(0, g[1])


## The throwing claw as [ground offset from the feet (px), height above the ground (px)], the
## convention ground-plane projectiles (Fireball) use.
func hand_ground() -> Array:
	var t := (skeleton.global_transform * skeleton.get_bone_global_pose(_held_bone)).origin
	var e := PlayerScript.ELEVATION
	return [Vector2(t.x, t.z * sin(e)) / PlayerScript.METRES_PER_PX, t.y * cos(e) / PlayerScript.METRES_PER_PX]


## Method tracks calling _on_anim_event at ANIM_EVENTS times. The imported Animation resources are
## shared between instances (same relative path in each), so they are only added once.
func _add_event_tracks() -> void:
	var path := _model.get_path_to(self)
	for anim_name: String in ANIM_EVENTS:
		var anim := anim_player.get_animation(anim_name)
		if anim.find_track(path, Animation.TYPE_METHOD) != -1:
			continue
		var t := anim.add_track(Animation.TYPE_METHOD)
		anim.track_set_path(t, path)
		for ev: Array in ANIM_EVENTS[anim_name]:
			anim.track_insert_key(t, ev[0], {"method": &"_on_anim_event", "args": [ev[1]]})


func _on_anim_event(event: StringName) -> void:
	anim_event.emit(event)


func _on_animation_finished(anim: StringName) -> void:
	if anim in LOOPING:
		return
	action_finished.emit(anim)
	if anim != &"death" and current == anim:
		current = _loop
		anim_player.play(_loop, BLEND)


func _draw() -> void:
	# contact shadow, foreshortened like the ground
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a), sin(a) * sin(PlayerScript.ELEVATION)) * SHADOW_RADIUS)
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
