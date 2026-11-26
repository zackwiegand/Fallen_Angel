class_name PedalView
extends Node2D
## One effect pedal drawn as live 3D -> pixel, same look as the character: the pedal's .glb renders
## into its own small transparent SubViewport (toon materials, ortho camera 38 deg down, 1 texel =
## 1 game px) and shows 1:1 through the sprite outline shader. The node origin is the pedal's base
## centre (its "ground" point), so callers place it like any other floor-standing sprite.
## A new pedal = a new assets/pedals/pedal_<id>.glb (blender/pedals/build_pedals.py), no code change.
## The viewport only re-renders when facing or lit changes.

const _Player := preload("res://scripts/player.gd")   # shares the rig camera conventions

const CANVAS_PX := 40                  # fits the widest pedal at a 45 deg turn plus the outline
const CAM_TARGET_Y := 0.14             # camera looks at this height above the base (metres)
const SCENE_PATH := "res://assets/pedals/pedal_%s.glb"
const LED_PREFIX := "Led"              # "Led<x>" lit (Toon.EMISSIVE) <-> "Led<x>Off" bypassed

## Ground direction like player.facing (x = screen-right, y = away); snaps to 8 directions.
var facing := Vector2(0, -1):
	set(v):
		if v != Vector2.ZERO:
			facing = v
			_update_pose()
## Status LED: on = pedal engaged, off = bypassed.
var lit := true:
	set(v):
		lit = v
		_update_materials()

var pedal_id: StringName

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D                     # yaws to the snapped facing
var _model: Node3D
var _sprite: Sprite2D
var _jacks := {}                       # &"in"/&"out" -> position relative to the pivot (metres)
var _led_materials: Array[String] = []


func _init() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PedalViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.size = Vector2i(CANVAS_PX, CANVAS_PX)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var e := _Player.ELEVATION
	var target := Vector3(0, CAM_TARGET_Y, 0)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CANVAS_PX * _Player.METRES_PER_PX
	_camera.far = 60.0
	_camera.position = target + Vector3(0, sin(e), cos(e)) * 20.0
	_viewport.add_child(_camera)
	_camera.transform = _camera.transform.looking_at(target)
	_pivot = Node3D.new()
	_pivot.name = "Pivot"
	_viewport.add_child(_pivot)
	_sprite = Sprite2D.new()
	_sprite.name = "Sprite"
	_sprite.texture = _viewport.get_texture()
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/sprite_outline.gdshader")
	_sprite.material = mat
	# put the base (3D origin) on this node's position
	_sprite.offset = Vector2(0, -round(CAM_TARGET_Y * cos(e) / _Player.METRES_PER_PX))
	add_child(_sprite)


## Load the pedal model, e.g. &"chief_delay", &"skyman_phaser".
func setup(id: StringName) -> void:
	pedal_id = id
	if _model:
		_model.queue_free()
	var scene: PackedScene = load(SCENE_PATH % id)
	_model = scene.instantiate()
	_pivot.add_child(_model)
	_jacks.clear()
	for which: StringName in [&"in", &"out"]:
		var socket := _model.find_child("jack_" + which, true, false) as Node3D
		if socket:
			_jacks[which] = _local_to_model(socket).origin
	_led_materials.clear()
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with(LED_PREFIX):
				_led_materials.append(src.resource_name)
	_update_materials()
	_update_pose()


## Cable attach point (&"in" or &"out") in this node's local 2D space, for the current facing.
func jack_point(which: StringName) -> Vector2:
	var p: Vector3 = _pivot.transform * _jacks.get(which, Vector3.ZERO)
	return _project(p)


## Snapped yaw for a ground direction (model faces +Z = toward the camera at yaw 0).
static func facing_yaw(dir: Vector2) -> float:
	return snappedf(atan2(dir.x, -dir.y), PI / 4.0)


# ---------------------------------------------------------------- internals
func _update_pose() -> void:
	if _pivot == null:
		return
	_pivot.rotation.y = facing_yaw(facing)
	_redraw()


func _update_materials() -> void:
	if _model == null:
		return
	var recolor := {}
	if not lit:
		for m in _led_materials:
			recolor[m] = m + "Off"
	Toon.apply(_model, recolor)
	_redraw()


func _redraw() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Orthographic projection of a rig-space point (metres, origin = base centre) into local 2D px.
func _project(p: Vector3) -> Vector2:
	var e := _Player.ELEVATION
	var d := p - Vector3(0, CAM_TARGET_Y, 0)
	var right := d.x
	var up := d.y * cos(e) - d.z * sin(e)      # camera up axis = (0, cos e, -sin e)
	return _sprite.offset + Vector2(right, -up) / _Player.METRES_PER_PX


func _local_to_model(n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	while n and n != _model:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t
