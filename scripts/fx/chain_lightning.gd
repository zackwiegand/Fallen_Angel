class_name ChainLightning
extends Node2D
## Releases `charges` lightning hops one after another, by priority:
##   1. the first bolt strikes the nearest enemy ahead (within FIRST_RANGE of the guitar);
##   2. each next bolt jumps to the nearest enemy it hasn't hit yet within BOUNCE_RANGE of the current one;
##   3. if there's no new enemy in range, it bounces back to the enemy it came from (a lone enemy is re-hit).
## Every target must also stay within CHAIN_REACH of the cast origin, so the chain can't walk across the map.
## So N charges = N hits, spread over the enemies close together near the caster.
## The pedal chain (SpellCast) sets the rest: pierce = each bolt passes through its target and carries
## on PIERCE_OVERSHOOT px, striking everything on its line too; echoes = Damage.deal repeats on every
## hit; phased = purple bolts; ghost = a delay repeat of the whole chain (translucent).

const HOP_DELAY := 0.09
const FIRST_RANGE := 160.0       # px (~6 m) guitar -> first target
const BOUNCE_RANGE := 80.0       # px (~3 m) max jump between targets
const CHAIN_REACH := 200.0       # px (~7.5 m) no target farther than this from the cast origin
const DAMAGE := 5
const BOLT_LIFE := 0.16
const PIERCE_OVERSHOOT := 45.0   # px a piercing bolt carries on past its target
const PIERCE_WIDTH := 9.0        # px from the bolt line that still gets struck
const COLORS := {false: [Color("3a6cff", 0.8), Color("bfe8ff"), Color.WHITE],      # glow, core, flicker
		true: [Color("8a3cff", 0.85), Color("e6c8ff"), Color("ffe8ff")]}           # phased: purple

var charges := 1
var origin := Vector2.ZERO        # guitar headstock, screen px (world-local)
var aim := Vector2.DOWN           # facing on screen, for the first target / a miss
var sfx: Sfx
var damage := DAMAGE
var pierce := false
var echoes := 0
var echo_delay := 0.0
var phased := false
var ghost := false

var _bolts: Array = []            # [PackedVector2Array, age]
var _current: Node2D
var _previous: Node2D             # the target the chain came from (bounce-back fallback)
var _visited: Array[Node2D] = []
var _from := Vector2.ZERO
var _hops_left := 0
var _next_in := 0.0


func _ready() -> void:
	z_index = 15
	if ghost:
		modulate = Color(1, 1, 1, 0.65)
	_hops_left = charges
	_from = origin
	_current = _pick_first()


func _process(delta: float) -> void:
	_next_in -= delta
	if _hops_left > 0 and _next_in <= 0.0:
		_hop()
		_next_in = HOP_DELAY
	for b in _bolts:
		b[1] += delta
	_bolts = _bolts.filter(func(b: Array) -> bool: return b[1] < BOLT_LIFE)
	if _hops_left == 0 and _bolts.is_empty():
		queue_free()
	queue_redraw()


func _hop() -> void:
	_hops_left -= 1
	if sfx:
		sfx.play(&"zap")
	if not _alive(_current):          # nothing in range (or it died): crackle off into the air
		_bolts.append([_jagged(_from, _from + aim * 70.0), 0.0])
		_hops_left = 0
		return
	var to: Vector2 = _current.hit_point()
	var dir := (to - _from).normalized()
	if pierce:                        # the bolt passes through and strikes whatever is on its line
		var end := to + dir * PIERCE_OVERSHOOT
		_bolts.append([_jagged(_from, end), 0.0])
		for e: Node2D in get_tree().get_nodes_in_group("enemies"):
			if e != _current and _on_line(e.hit_point(), _from, end):
				Damage.deal(e, damage, &"lightning", dir, echoes, echo_delay, sfx)
	else:
		_bolts.append([_jagged(_from, to), 0.0])
	Damage.deal(_current, damage, &"lightning", dir, echoes, echo_delay, sfx)
	_from = to
	if _current not in _visited:
		_visited.append(_current)
	var next := _nearest(to, BOUNCE_RANGE, _visited)     # 2. a new enemy in range
	if next == null and _alive(_previous):                # 3. none: bounce back to where it came from
		next = _previous
	if next == null:                                      # lone target: strike it again
		next = _current if _alive(_current) else null
	_previous = _current
	_current = next


func _alive(e: Node2D) -> bool:
	return is_instance_valid(e) and e.is_in_group("enemies")


func _pick_first() -> Node2D:
	var best: Node2D = null
	var best_score := INF
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		var d: Vector2 = e.hit_point() - origin
		if d.length() > FIRST_RANGE:
			continue
		var score := d.length() - 80.0 * d.normalized().dot(aim)     # prefer what we're facing
		if score < best_score:
			best_score = score
			best = e
	return best


func _nearest(from: Vector2, max_range: float, exclude: Array[Node2D]) -> Node2D:
	var best: Node2D = null
	var best_d := max_range
	for e: Node2D in get_tree().get_nodes_in_group("enemies"):
		if e in exclude or origin.distance_to(e.hit_point()) > CHAIN_REACH:
			continue
		var d := from.distance_to(e.hit_point())
		if d < best_d:
			best_d = d
			best = e
	return best


func _on_line(p: Vector2, a: Vector2, b: Vector2) -> bool:
	return Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) <= PIERCE_WIDTH


func _jagged(a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var n := maxi(3, int(a.distance_to(b) / 9.0))
	var side := (b - a).orthogonal().normalized()
	for i in range(1, n):
		pts.append((a.lerp(b, float(i) / n) + side * randf_range(-5, 5)).round())
	pts.append(b)
	return pts


func _draw() -> void:
	for b in _bolts:
		var pts: PackedVector2Array = b[0]
		var flicker: bool = int(b[1] / 0.04) % 2 == 0
		var c: Array = COLORS[phased]
		for off in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)]:
			draw_polyline(_offset(pts, off), c[0], 1.0)
		draw_polyline(pts, c[1] if flicker else c[2], 1.0)
		draw_rect(Rect2(pts[pts.size() - 1] - Vector2(2, 2), Vector2(5, 5)), Color(c[1], 0.7))


func _offset(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + o)
	return out
