class_name Fireball
extends Area2D
## Flies along the ground plane at a fixed height (drawn `height` px above its ground position, so
## it y-sorts and collides by where it is over the floor). Explodes on dummies or walls.
## The pedal chain (SpellCast) sets the rest: damage, pierce (passes through enemies, still stops at
## walls), echoes (Damage.deal repeats on every target hit), phased (purple shimmer), ghost (a
## delay repeat: translucent, smaller blast).

const SPEED := 6.0 / (3.0 / 80.0)     # 6 m/s in px
const RANGE_S := 1.4                  # seconds before it fizzles
const DAMAGE := 12
const PHASE_COLORS := [Color("f0d0ff"), Color("c27aff"), Color("8a3cff")]

var velocity := Vector2.ZERO
var height := 30.0
var caster: Node2D
var sfx: Sfx
var damage := DAMAGE
var pierce := false
var echoes := 0
var echo_delay := 0.0
var phased := false
var ghost := false

var _age := 0.0
var _trail: Array[Vector3] = []        # x, y (local to ground pos), age
var _hit: Array[Node] = []             # targets already hit (a piercing fireball hits each once)


func _ready() -> void:
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	shape.scale = Vector2(1, 0.62)
	add_child(shape)
	body_entered.connect(_on_body_entered)
	if ghost:
		modulate = Color(1, 1, 1, 0.7)


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
	if body == caster or body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		if body in _hit:
			return
		_hit.append(body)
		Damage.deal(body, damage, &"fire", velocity.normalized(), echoes, echo_delay, sfx)
		if pierce:                      # burst through it and keep flying
			_burst(0.6)
			if sfx:
				sfx.play(&"hit")
			return
	_explode()


func _explode() -> void:
	if is_queued_for_deletion():
		return
	_burst(0.7 if ghost else 1.0)
	if sfx:
		sfx.play(&"explode")
	queue_free()


func _burst(size: float) -> void:
	var boom := Explosion.new()
	boom.position = position
	boom.height = height
	boom.size = size
	boom.phased = phased
	boom.modulate = modulate
	get_parent().add_child(boom)


func _draw() -> void:
	# ground shadow, then embers, then the flickering core with a dark rim
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
	draw_circle(Vector2.ZERO, 4, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO)
	for p in _trail:
		var c := Color("ffb020").lerp(Color("8a1408"), p.z / 0.25)
		if phased:
			c = c.lerp(PHASE_COLORS[1], 0.55)
		draw_rect(Rect2(Vector2(p.x, p.y).round(), Vector2.ONE * (2 if p.z < 0.1 else 1)), c)
	var o := Vector2(0, -height).round()
	var f := 1 if (Engine.get_frames_drawn() / 3) % 2 == 0 else 0
	if phased:
		_draw_phase_aura(o)
	draw_circle(o, 6 + f, Color("3a0804"))
	draw_circle(o, 5 + f, Color("c8280c"))
	draw_circle(o + Vector2(-1, -1), 3 + f, Color("ff8a1c"))
	draw_circle(o + Vector2(-1, -1), 2, Color("ffe070"))
	draw_rect(Rect2(o + Vector2(-2, -2), Vector2.ONE), Color.WHITE)


## Shimmering purple shell (Skyman phaser): a faint halo and sparkles orbiting at a wobbling radius.
func _draw_phase_aura(o: Vector2) -> void:
	var t := _age * 9.0
	draw_arc(o, 9.0 + sin(t) * 0.8, 0, TAU, 20, Color(PHASE_COLORS[2], 0.5), 1.0)
	for i in 7:
		var a := t * 0.7 + i * TAU / 7.0
		var r := 8.0 + sin(t * 1.7 + i * 2.1) * 1.5
		var p := (o + Vector2(cos(a), sin(a) * 0.8) * r).round()
		draw_rect(Rect2(p, Vector2.ONE), PHASE_COLORS[(i + int(t)) % PHASE_COLORS.size()])


class Explosion extends Node2D:
	const LIFE := 0.4
	var height := 30.0
	var size := 1.0                 # 1 = full blast; pierce bursts and ghosts are smaller
	var phased := false
	var _age := 0.0
	var _debris: Array[Vector2] = []

	func _ready() -> void:
		z_index = 10
		for i in 10:
			_debris.append(Vector2.from_angle(randf() * TAU) * randf_range(30, 70) * size)

	func _process(delta: float) -> void:
		_age += delta
		if _age > LIFE:
			queue_free()
		queue_redraw()

	func _draw() -> void:
		var u := _age / LIFE
		var o := Vector2(0, -height).round()
		var r := lerpf(4.0, 15.0, sqrt(u)) * size
		var rim := Color("3a0804")
		var outer := Color("c8280c")
		var mid := Color("ff8a1c")
		if phased:                      # purple-shifted fire
			rim = Color("1e0838")
			outer = Color("a03ce0")
			mid = Color("ff8ad0")
		if u < 0.6:
			draw_circle(o, r + 1, rim)
			draw_circle(o, r, outer)
			draw_circle(o, r * 0.7, mid)
			draw_circle(o, r * 0.4 * (1.0 - u), Color("ffe070"))
		else:
			draw_arc(o, r, 0, TAU, 24, Color(outer, 1.0 - u), 1.0)
		for d in _debris:
			var p := o + d * u + Vector2(0, 40 * u * u)
			draw_rect(Rect2(p.round(), Vector2.ONE), mid if u < 0.5 else rim.lightened(0.25))
