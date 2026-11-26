class_name ChainLightning
extends Node2D
## Releases `charges` lightning hops one after another. The first goes from the guitar to the
## nearest dummy ahead; each next hop jumps to the nearest dummy it hasn't hit yet, so the chain
## sweeps the whole group before revisiting anyone (then starts a new sweep). A lone dummy gets
## re-hit. So N charges = N hits, spread over as many targets as are in range.

const HOP_DELAY := 0.09
const FIRST_RANGE := 230.0       # px
const BOUNCE_RANGE := 260.0
const DAMAGE := 5
const BOLT_LIFE := 0.16

var charges := 1
var origin := Vector2.ZERO        # guitar headstock, screen px (world-local)
var aim := Vector2.DOWN           # facing on screen, for the first target / a miss
var sfx: Sfx

var _bolts: Array = []            # [PackedVector2Array, age]
var _current: Node2D
var _visited: Array[Node2D] = []
var _from := Vector2.ZERO
var _hops_left := 0
var _next_in := 0.0


func _ready() -> void:
	z_index = 15
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
	if _current == null:              # nothing in range: crackle off into the air
		_bolts.append([_jagged(_from, _from + aim * 70.0), 0.0])
		_hops_left = 0
		return
	var to: Vector2 = _current.hit_point()
	_bolts.append([_jagged(_from, to), 0.0])
	_current.take_damage(DAMAGE, &"lightning", (to - _from).normalized())
	_from = to
	_visited.append(_current)
	var next := _nearest(to, BOUNCE_RANGE, _visited)
	if next == null:                  # everyone in range has been hit: start a new sweep
		_visited = [_current]
		next = _nearest(to, BOUNCE_RANGE, _visited)
	if next:
		_current = next


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
		if e in exclude:
			continue
		var d := from.distance_to(e.hit_point())
		if d < best_d:
			best_d = d
			best = e
	return best


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
		for off in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1)]:
			draw_polyline(_offset(pts, off), Color("3a6cff", 0.8), 1.0)
		draw_polyline(pts, Color("bfe8ff") if flicker else Color.WHITE, 1.0)
		draw_rect(Rect2(pts[pts.size() - 1] - Vector2(2, 2), Vector2(5, 5)), Color("bfe8ff", 0.7))


func _offset(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + o)
	return out
