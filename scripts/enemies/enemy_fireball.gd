class_name EnemyFireball
extends Area2D
## A gremlin's lobbed fireball. Same convention as the player's Fireball: it lives on the ground
## plane (position = ground point, y-sorts and collides there) and is drawn `height` px above it.
## Hits the "player" group, bursts on walls/pillars and static props; flies through other enemies.
## Slower than the player's spells so it can be dodged.

const SPEED_MPS := 4.0
const RANGE_S := 2.3              # ~9 m
const DAMAGE := 5
const RADIUS := 3.5

var velocity := Vector2.ZERO      # screen px/s
var height := 14.0
var caster: Node2D

var _age := 0.0
var _trail: Array[Vector3] = []   # x, y (local), age


func _ready() -> void:
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS
	shape.shape = circle
	shape.scale = Vector2(1, 0.62)
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	position += velocity * delta
	for i in _trail.size():
		_trail[i] = Vector3(_trail[i].x - velocity.x * delta, _trail[i].y - velocity.y * delta, _trail[i].z + delta)
	_trail = _trail.filter(func(p: Vector3) -> bool: return p.z < 0.2)
	if Engine.get_physics_frames() % 2 == 0:
		_trail.append(Vector3(randf_range(-1, 1), -height + randf_range(-1, 1), 0.0))
	if _age > RANGE_S:
		_burst()
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body == caster:
		return
	if body.is_in_group("player"):
		if body.has_method(&"take_damage"):
			body.take_damage(DAMAGE, &"fire", velocity.normalized())
		_burst()
	elif body is CharacterBody2D and body.is_in_group("enemies"):
		return                                     # allies: fly past
	else:
		_burst()                                   # walls, pillars, dummies


func _burst() -> void:
	if is_queued_for_deletion():
		return
	var b := Burst.new()
	b.position = position
	b.height = height
	get_parent().add_child(b)
	queue_free()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
	draw_circle(Vector2.ZERO, 3, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)
	for p in _trail:
		draw_rect(Rect2(Vector2(p.x, p.y).round(), Vector2.ONE), Color("ff6a10").lerp(Color("5a0806"), p.z / 0.2))
	var o := Vector2(0, -height).round()
	var f := 1 if (Engine.get_frames_drawn() / 3) % 2 == 0 else 0
	draw_circle(o, 4 + f, Color("2a0404"))
	draw_circle(o, 3 + f, Color("b01a0a"))
	draw_circle(o, 2, Color("ff7a14"))
	draw_rect(Rect2(o + Vector2(-1, -1), Vector2.ONE), Color("ffe070"))


## Small pop of embers where it lands.
class Burst extends Node2D:
	const LIFE := 0.3
	var height := 14.0
	var _age := 0.0

	func _ready() -> void:
		z_index = 10

	func _process(delta: float) -> void:
		_age += delta
		if _age > LIFE:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := _age / LIFE
		var o := Vector2(0, -height).round()
		var r := lerpf(2.0, 8.0, sqrt(u))
		if u < 0.5:
			draw_circle(o, r, Color("b01a0a"))
			draw_circle(o, r * 0.6, Color("ff7a14"))
		else:
			draw_arc(o, r, 0, TAU, 16, Color("b01a0a", 1.0 - u), 1.0)
