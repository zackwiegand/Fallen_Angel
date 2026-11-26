class_name PedalPickup
extends Area2D
## A pedal lying on the floor, bobbing over a glint; walking over it adds it to the end of the
## player's chain (Pedalboard.add_pedal) and it flies into the trail from here.
## spawn_all() places one per `pedal_spawn` marker in the level (Marker2D, metadata `pedal_id`), or at
## FALLBACK offsets from the player when the level has no markers.

const SCENE_PATH := "res://scenes/pedals/pedal_pickup.tscn"    # loaded at runtime (the scene uses this script)
const FALLBACK := {&"chief_delay": Vector2(-56, 34), &"skyman_phaser": Vector2(56, 34)}   # from the player
const BOB_SPEED := 3.0
const POPUP_COLOR := Color("ffd84a")

@export var pedal_id: StringName

var _view: PedalView
var _time := 0.0


## Spawns pickups into `world` for every pedal the player doesn't own yet.
static func spawn_all(world: Node, player: Node2D) -> Array[PedalPickup]:
	var spots := {}
	for m: Node in world.get_tree().get_nodes_in_group("pedal_spawn"):
		if m is Node2D and m.has_meta("pedal_id"):
			spots[StringName(m.get_meta("pedal_id"))] = (m as Node2D).global_position
	if spots.is_empty():
		for id: StringName in FALLBACK:
			spots[id] = player.global_position + FALLBACK[id]
	var out: Array[PedalPickup] = []
	var scene: PackedScene = load(SCENE_PATH)
	for id: StringName in spots:
		if player.pedalboard.has_pedal(id):
			continue
		var p: PedalPickup = scene.instantiate()
		p.pedal_id = id
		p.position = spots[id]
		world.add_child(p)
		out.append(p)
	return out


func _ready() -> void:
	_view = PedalView.new()
	_view.setup(pedal_id)
	add_child(_view)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_view.position = Vector2(0, -roundf(3.0 + sin(_time * BOB_SPEED) * 2.0))
	_view.facing = Vector2(0, -1)
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if not ("pedalboard" in body) or body.pedalboard == null:
		return
	if not body.pedalboard.add_pedal(pedal_id, _view.global_position):
		return
	var def := PedalRegistry.get_def(pedal_id)
	FloatText.spawn(get_parent(), global_position + Vector2(0, -30), def.display_name(), POPUP_COLOR, 14.0)
	if "sfx" in body and body.sfx:
		body.sfx.play(&"pickup")
	queue_free()


func _draw() -> void:
	# shadow + a little rotating glint so it reads as "pick me up"
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.45))
	draw_circle(Vector2.ZERO, 7.0, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	var a := _time * 2.0
	for i in 4:
		var p := (Vector2(cos(a + i * TAU / 4.0) * 11.0, sin(a + i * TAU / 4.0) * 5.0) + Vector2(0, -6)).round()
		draw_rect(Rect2(p, Vector2.ONE), Color("fff4b0", 0.5 + 0.5 * sin(_time * 6.0 + i)))
