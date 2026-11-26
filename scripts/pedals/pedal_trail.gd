class_name PedalTrail
extends Node2D
## The player's collected pedals floating after them in chain order, linked by sagging sound cables:
## guitar -> chain[0] -> chain[1] -> ...  (signal order, same as the Pedals bus and the menu).
## Moving: each pedal follows the one in front of it like a snake (the first follows the player).
## Idle (standing still for IDLE_AFTER s): they drift into a loose arc behind the player, in chain
## order, and bob. Every pedal is its own node in the y-sorted world (with a ground shadow); each
## cable sorts just behind the pedal it plugs into.

const FIRST_GAP := 24.0          # px from the player to the first pedal while moving
const FOLLOW_GAP := 21.0         # px between pedals while moving
const FOLLOW_RATE := 8.0         # how snappily they follow (1/s)
const BEHIND_BIAS := 0.7         # how strongly a following pedal swings round behind its leader
const IDLE_AFTER := 0.35         # s standing still before they gather
const IDLE_RADIUS := 34.0        # ground px from the player's feet
const IDLE_SPACING := 28.0       # ground px between neighbours on the idle arc (room for the cable)
const IDLE_MAX_SPREAD := deg_to_rad(200.0)   # the arc never wraps further round than this
const IDLE_RATE := 2.5
const HOVER := 11.0              # px above the ground
const BOB := 1.5
const BOB_SPEED := 2.6
const GUITAR_JACK := Vector2(8, -18)     # first cable leaves the hip on the first pedal's side (feet-relative)

var player: Node2D               # player.gd (pedalboard, facing, velocity, ground_to_screen)

var _floaters := {}              # id -> Floater
var _cables: Array[Cable] = []
var _still := 0.0
var _time := 0.0


func _ready() -> void:
	y_sort_enabled = true
	var board: Pedalboard = player.pedalboard
	board.pedal_added.connect(_on_pedal_added)
	board.chain_changed.connect(_rebuild)
	_rebuild()


func floater(id: StringName) -> Floater:
	return _floaters.get(id)


func _on_pedal_added(id: StringName, from_position: Vector2) -> void:
	_rebuild()
	var f: Floater = _floaters[id]
	f.position = from_position if from_position.is_finite() else player.position
	f.height = 0.0


func _rebuild() -> void:
	var chain: Array[StringName] = player.pedalboard.chain
	for id: StringName in _floaters.keys():
		if id not in chain:
			_floaters[id].queue_free()
			_floaters.erase(id)
	for id in chain:
		if not _floaters.has(id):
			var f := Floater.new()
			f.view = PedalView.new()
			f.view.setup(id)
			f.add_child(f.view)
			f.position = player.position
			add_child(f)
			_floaters[id] = f
	while _cables.size() < chain.size():
		var c := Cable.new()
		add_child(c)
		_cables.append(c)
	while _cables.size() > chain.size():
		_cables.pop_back().queue_free()


func _process(delta: float) -> void:
	_time += delta
	var board: Pedalboard = player.pedalboard
	var chain := board.chain
	var moving: bool = player.velocity.length() > 1.0
	_still = 0.0 if moving else _still + delta
	var idle := _still > IDLE_AFTER
	var back: Vector2 = -player.ground_to_screen(player.facing).normalized()
	var slots := _idle_slots(chain.size())
	for i in chain.size():
		var f: Floater = _floaters[chain[i]]
		var target: Vector2
		var rate := FOLLOW_RATE
		if idle:
			target = player.position + slots[i]
			rate = IDLE_RATE
		else:
			var leader: Vector2 = player.position if i == 0 else _floaters[chain[i - 1]].position
			var off := f.position - leader
			var dir := (off.normalized() + back * BEHIND_BIAS).normalized() if off.length() > 0.5 else back
			target = leader + dir * (FIRST_GAP if i == 0 else FOLLOW_GAP)
		f.position = f.position.lerp(target, 1.0 - exp(-rate * delta))
		f.height = lerpf(f.height, HOVER + sin(_time * BOB_SPEED + i * 1.3) * BOB, 1.0 - exp(-6.0 * delta))
		f.view.position = Vector2(0, -roundf(f.height))
		f.view.facing = player.facing
		f.view.lit = not board.is_bypassed(chain[i])
		f.queue_redraw()
	# cables: guitar -> first pedal's input, each output -> next input
	for i in _cables.size():
		var to: Floater = _floaters[chain[i]]
		var b := to.view.to_global(to.view.jack_point(&"in"))
		var a: Vector2
		if i == 0:                      # the guitar's jack, on the hip facing the first pedal
			a = player.global_position + Vector2(GUITAR_JACK.x * signf(b.x - player.global_position.x), GUITAR_JACK.y)
		else:
			a = _floaters[chain[i - 1]].view.to_global(_floaters[chain[i - 1]].view.jack_point(&"out"))
		_cables[i].position = to.position - Vector2(0, 0.5)       # sorts just behind its pedal
		_cables[i].step(a, b, delta)


## Gathered spots (player-relative) for n pedals: an arc behind the player on the ground plane,
## handed out right to left on screen so the chain reads like a real board (signal enters a
## pedal on its right, leaves on its left) and the cables don't cross behind the pedals.
func _idle_slots(n: int) -> Array[Vector2]:
	var spread := minf(IDLE_SPACING / IDLE_RADIUS * (n - 1), IDLE_MAX_SPREAD)
	var out: Array[Vector2] = []
	for i in n:
		var t := 0.5 if n == 1 else float(i) / (n - 1)
		var g: Vector2 = (-player.facing).rotated(lerpf(spread / 2.0, -spread / 2.0, t)) * IDLE_RADIUS
		out.append(player.ground_to_screen(g))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	for i in n:
		out[i] += Vector2(sin(_time * 0.7 + i * 2.0), cos(_time * 0.53 + i * 1.1)) * 1.5
	return out


## One floating pedal: the node sits on the ground (y-sort, shadow); the view hovers above it.
class Floater extends Node2D:
	var view: PedalView
	var height := 0.0

	func _draw() -> void:
		var r := lerpf(6.0, 4.0, clampf(height / 14.0, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.45))
		draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.3))


## A sagging sound cable between two jacks: a short verlet rope with pinned ends, drawn 1px dark
## with a few highlight glints and plug ends.
class Cable extends Node2D:
	const POINTS := 8
	const SLACK := 1.5            # rope length / jack distance
	const GRAVITY := 420.0        # px/s^2
	const DAMPING := 0.94
	const ITERATIONS := 6
	const DARK := Color("0a080c")
	const GLINT := Color("8a7e96")
	const PLUG := Color("a8a8b4")

	var _p := PackedVector2Array()     # global positions
	var _prev := PackedVector2Array()

	func step(a: Vector2, b: Vector2, delta: float) -> void:
		if _p.is_empty():
			for k in POINTS:
				_p.append(a.lerp(b, float(k) / (POINTS - 1)))
			_prev = _p.duplicate()
		var g := Vector2(0, GRAVITY) * delta * delta
		for k in range(1, POINTS - 1):
			var v := (_p[k] - _prev[k]) * DAMPING
			_prev[k] = _p[k]
			_p[k] += v + g
		var seg := maxf(a.distance_to(b) * SLACK / (POINTS - 1), 1.5)
		for _it in ITERATIONS:
			_p[0] = a
			_p[POINTS - 1] = b
			for k in POINTS - 1:
				var d := _p[k + 1] - _p[k]
				var l := d.length()
				if l < 0.0001:
					continue
				var fix := d * (1.0 - seg / l) * 0.5
				if k > 0:
					_p[k] += fix
				if k + 1 < POINTS - 1:
					_p[k + 1] -= fix
		_p[0] = a
		_p[POINTS - 1] = b
		queue_redraw()

	func _draw() -> void:
		if _p.size() < 2:
			return
		var pts := PackedVector2Array()
		for q in _p:
			pts.append(to_local(q).round())
		draw_polyline(pts, DARK, 1.0)
		for k in range(1, POINTS - 1, 2):               # sheen dots along the rubber
			draw_rect(Rect2(pts[k], Vector2.ONE), GLINT)
		for end in [pts[0], pts[pts.size() - 1]]:
			draw_rect(Rect2(end - Vector2.ONE, Vector2(2, 2)), PLUG)
