class_name Fireball
extends Area2D
## Flies along the ground plane at a fixed height (drawn `height` px above its ground position, so
## it y-sorts and collides by where it is over the floor). Explodes on dummies or walls.

const SPEED := 6.0 / (3.0 / 80.0)     # 6 m/s in px
const RANGE_S := 1.4                  # seconds before it fizzles
const DAMAGE := 12

var velocity := Vector2.ZERO
var height := 30.0
var caster: Node2D
var sfx: Sfx

var _age := 0.0
var _trail: Array[Vector3] = []        # x, y (local to ground pos), age


func _ready() -> void:
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	shape.scale = Vector2(1, 0.62)
	add_child(shape)
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	_age += delta
	position += velocity * delta
	for i in _trail.size():
		_trail[i] = Vector3(_trail[i].x - velocity.x * delta, _trail[i].y - velocity.y * delta, _trail[i].z + delta)
	_trail = _trail.filter(func(p: Vector3) -> bool: return p.z < 0.25)
	if Engine.get_physics_frames() % 2 == 0:
		_trail.append(Vector3(randf_range(-2, 2), -height + randf_range(-2, 2), 0.0))
	if _age > RANGE_S:
		_explode()
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if body == caster:
		return
	if body.has_method("take_damage"):
		body.take_damage(DAMAGE, &"fire", velocity.normalized())
	_explode()


func _explode() -> void:
	if is_queued_for_deletion():
		return
	var boom := Explosion.new()
	boom.position = position
	boom.height = height
	get_parent().add_child(boom)
	if sfx:
		sfx.play(&"explode")
	queue_free()


func _draw() -> void:
	# ground shadow, then embers, then the flickering core with a dark rim
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
	draw_circle(Vector2.ZERO, 4, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	for p in _trail:
		var c := Color("ffb020").lerp(Color("8a1408"), p.z / 0.25)
		draw_rect(Rect2(Vector2(p.x, p.y).round(), Vector2.ONE * (2 if p.z < 0.1 else 1)), c)
	var o := Vector2(0, -height).round()
	var f := 1 if (Engine.get_frames_drawn() / 3) % 2 == 0 else 0
	draw_circle(o, 6 + f, Color("3a0804"))
	draw_circle(o, 5 + f, Color("c8280c"))
	draw_circle(o + Vector2(-1, -1), 3 + f, Color("ff8a1c"))
	draw_circle(o + Vector2(-1, -1), 2, Color("ffe070"))
	draw_rect(Rect2(o + Vector2(-2, -2), Vector2.ONE), Color.WHITE)


class Explosion extends Node2D:
	const LIFE := 0.4
	var height := 30.0
	var _age := 0.0
	var _debris: Array[Vector2] = []

	func _ready() -> void:
		z_index = 10
		for i in 10:
			_debris.append(Vector2.from_angle(randf() * TAU) * randf_range(30, 70))

	func _process(delta: float) -> void:
		_age += delta
		if _age > LIFE:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := _age / LIFE
		var o := Vector2(0, -height).round()
		var r := lerpf(4.0, 15.0, sqrt(u))
		if u < 0.6:
			draw_circle(o, r + 1, Color("3a0804"))
			draw_circle(o, r, Color("c8280c"))
			draw_circle(o, r * 0.7, Color("ff8a1c"))
			draw_circle(o, r * 0.4 * (1.0 - u), Color("ffe070"))
		else:
			draw_arc(o, r, 0, TAU, 24, Color("c8280c", 1.0 - u), 1.0)
		for d in _debris:
			var p := o + d * u + Vector2(0, 40 * u * u)
			draw_rect(Rect2(p.round(), Vector2.ONE), Color("ff8a1c") if u < 0.5 else Color("6a1006"))
