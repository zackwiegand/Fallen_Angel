class_name GremlinStates
## The gremlin's brain: a hierarchical state machine built from the states below.
##
##   calm          idle <-> pace around the spawn, looking around
##   investigate   suspicious: walk to the last noise / glimpse, look around
##   combat        alert_pause ("!") -> engage, which picks:
##                   throw     volley of fireballs at range (ranged token)
##                   reposition strafe after a volley
##                   charge    gallop in (melee token) -> slash (-> combo) -> back_off
##                   circle    no melee token: orbit and wait
##   search        lost sight: go to last known position, look around ("?")
##   return        walk home, then calm
##   hurt / dead   interrupts (forced by Gremlin.take_damage)


static func build(g: Gremlin) -> StateMachine:
	var m := StateMachine.new(g)
	var calm: AIState = m.add(&"calm", Composite.new())
	calm.sub = m.make_sub()
	calm.sub.add(&"idle", Idle.new())
	calm.sub.add(&"pace", Pace.new())
	(calm as Composite).initial = &"idle"
	(calm as Composite).guard = GremlinStates._calm_guard
	m.add(&"investigate", Investigate.new())
	var combat: AIState = m.add(&"combat", Combat.new())
	combat.sub = m.make_sub()
	combat.sub.add(&"alert_pause", AlertPause.new())
	combat.sub.add(&"engage", Engage.new())
	combat.sub.add(&"throw", Throw.new())
	combat.sub.add(&"reposition", Reposition.new())
	combat.sub.add(&"charge", Charge.new())
	combat.sub.add(&"slash", Slash.new())
	combat.sub.add(&"back_off", BackOff.new())
	combat.sub.add(&"circle", Circle.new())
	m.add(&"search", Search.new())
	m.add(&"return", Return.new())
	m.add(&"hurt", Hurt.new())
	m.add(&"dead", Dead.new())
	return m


static func _calm_guard(g: Gremlin) -> StringName:
	var p := g.perception
	if p.is_alert():
		return &"combat"
	if p.level() == Perception.Level.SUSPICIOUS and p.has_last_known:
		if p.can_see:                     # a glimpse: turn and stare while the meter fills
			g.face_toward(p.last_known)
		else:                             # a noise, or it slipped out of view: go look
			return &"investigate"
	return &""


## Base with a typed handle on the gremlin.
class GState extends AIState:
	var g: Gremlin:
		get: return agent as Gremlin


## A state that just runs a child machine, with an optional guard checked first every frame.
class Composite extends GState:
	var initial: StringName
	var guard: Callable

	func enter() -> void:
		sub.start(initial)

	func update(_delta: float) -> StringName:
		return guard.call(g) if guard.is_valid() else &""


# ================================================================== calm
class Idle extends GState:
	var _dur := 0.0
	var _looked := false

	func enter() -> void:
		g.play(&"idle")
		_dur = g.rng.randf_range(Gremlin.PACE_PAUSE_S.x, Gremlin.PACE_PAUSE_S.y)
		_looked = false

	func update(_delta: float) -> StringName:
		if not _looked and elapsed() > _dur * 0.5:          # glance around
			_looked = true
			g.facing = g.facing.rotated(g.rng.randf_range(-1.6, 1.6))
		return &"pace" if elapsed() >= _dur else &""


class Pace extends GState:
	const TIMEOUT_S := 6.0
	var _goal := Vector2.ZERO

	func enter() -> void:
		var a := g.rng.randf() * TAU
		var r := g.rng.randf_range(0.8, Gremlin.PACE_RADIUS_M)
		_goal = g.spawn_point + Ground.to_screen(Vector2.from_angle(a) * r / Ground.METRES_PER_PX)
		g.play(&"walk")

	func update(_delta: float) -> StringName:
		if g.go_to(_goal, Gremlin.WALK_MPS) or elapsed() > TIMEOUT_S:
			return &"idle"
		g.play_move()
		return &""


# ================================================================== suspicious
class Investigate extends GState:
	const TIMEOUT_S := 7.0
	var _look_t := -1.0

	func enter() -> void:
		g.bark("?", Color("ffd040"))
		_look_t = -1.0

	func update(_delta: float) -> StringName:
		var p := g.perception
		if p.is_alert():
			return &"combat"
		if p.consume_heard():
			_look_t = -1.0
		if _look_t < 0.0:
			if g.go_to(p.last_known, Gremlin.WALK_MPS * 1.3, 8.0):
				_look_t = elapsed()
			g.play_move()
		else:
			g.play_loop(&"idle")
			if fmod(elapsed() - _look_t, 0.9) < 0.02:
				g.facing = g.facing.rotated(g.rng.randf_range(-1.8, 1.8))
			if elapsed() - _look_t > Gremlin.SEARCH_LOOK_S:
				p.forget()
				return &"return"
		if elapsed() > TIMEOUT_S:
			p.forget()
			return &"return"
		return &""


# ================================================================== combat
class Combat extends GState:
	func enter() -> void:
		# fresh engagement from a calm-ish state: react first ("!"); back from a stagger: keep fighting
		var fresh := machine.previous_name not in [&"hurt", &"combat"]
		if fresh:
			g.volley_done = false
		sub.start(&"alert_pause" if fresh else &"engage")

	func exit() -> void:
		g.release_tokens()
		g.set_telegraph(0.0)

	func update(_delta: float) -> StringName:
		var p := g.perception
		if g.target == null:
			return &"return"
		if not p.can_see and p.time_since_seen > Gremlin.LOSE_SIGHT_S:
			return &"search"
		return &""


class AlertPause extends GState:
	func enter() -> void:
		g.bark("!", Color("ff5a4a"))
		g.play(&"idle")

	func update(_delta: float) -> StringName:
		g.face_toward(g.perception.last_known)
		return &"engage" if elapsed() >= Gremlin.ALERT_PAUSE_S else &""


## The decision node: every frame, pick the next move from distance, sight, cooldowns and tokens.
class Engage extends GState:
	func update(_delta: float) -> StringName:
		var p := g.perception
		var t := g.target
		if not p.can_see:                               # chase to where we last saw them
			g.go_to(p.last_known, Gremlin.GALLOP_MPS, 8.0)
			g.play_move(true)
			return &""
		var d := g.target_dist()
		g.face_toward(t.global_position)
		if d > Gremlin.RANGED_MAX_M + 2.0:
			g.volley_done = false                       # they backed off: open with fireballs again
		var want_melee := d <= Gremlin.RANGED_MIN_M or g.volley_done
		if want_melee:
			if g.clock >= g.melee_ready_at and AttackTokens.request(t, &"melee", g):
				return &"charge"
			return &"circle"
		if d <= Gremlin.RANGED_MAX_M and g.clock >= g.ranged_ready_at and AttackTokens.request(t, &"ranged", g):
			return &"throw"
		if d > Gremlin.RANGED_MAX_M:
			g.go_to(t.global_position, Gremlin.GALLOP_MPS)
			g.play_move(true)
		else:                                           # in range, waiting on the cooldown: prowl closer
			var side := 1.0 if g.get_instance_id() % 2 == 0 else -1.0
			var dir := Ground.dir(g.global_position, t.global_position) * 0.6 \
					+ NavMover.orbit_dir(g.global_position, t.global_position, side) * 0.8
			g.move(dir, Gremlin.STRAFE_MPS, false)
			g.play_move()
		return &""


class Throw extends GState:
	var _count := 0
	var _thrown := 0
	var _t := 0.0
	var _released := false
	var _gap := 0.0

	func enter() -> void:
		_count = g.rng.randi_range(Gremlin.VOLLEY.x, Gremlin.VOLLEY.y)
		_thrown = 0
		_start_throw()

	func _start_throw() -> void:
		_t = 0.0
		_gap = 0.0
		_released = false
		g.play(&"throw")

	func exit() -> void:
		g.set_telegraph(0.0)
		AttackTokens.release(g.target, &"ranged", g)

	func on_event(event: StringName) -> void:
		if event == &"throw_release" and not _released:
			_release()

	func _release() -> void:
		_released = true
		_thrown += 1
		g.set_telegraph(0.0)
		g.throw_fireball()

	func update(delta: float) -> StringName:
		_t += delta
		var length := g.rig.anim_length(&"throw")
		if not _released:
			g.face_toward(g.target.global_position)
			g.set_telegraph(clampf(_t / (length * 0.6), 0.0, 1.0))
		if _t < length:
			return &""
		if not _released:                               # rig without the event: throw at the end
			_release()
		var d := g.target_dist()
		var keep := _thrown < _count and g.perception.can_see \
				and d >= Gremlin.RANGED_MIN_M * 0.8 and d <= Gremlin.RANGED_MAX_M + 1.0
		if keep:
			_gap += delta
			g.play_loop(&"idle")
			if _gap >= Gremlin.THROW_GAP_S:
				_start_throw()
			return &""
		g.ranged_ready_at = g.clock + g.rng.randf_range(Gremlin.RANGED_COOLDOWN_S.x, Gremlin.RANGED_COOLDOWN_S.y)
		g.volley_done = g.rng.randf() < 0.6
		return &"engage" if g.volley_done else &"reposition"


class Reposition extends GState:
	const DUR_S := 1.0
	var _side := 1.0

	func enter() -> void:
		_side = 1.0 if g.rng.randf() < 0.5 else -1.0

	func update(_delta: float) -> StringName:
		var t := g.target.global_position
		g.move(NavMover.orbit_dir(g.global_position, t, _side), Gremlin.STRAFE_MPS * 1.6, false)
		g.face_toward(t)
		g.play_move(true)
		return &"engage" if elapsed() >= DUR_S else &""


## Holds the melee token into the slash; gives it back if the charge fails.
class Charge extends GState:
	func update(_delta: float) -> StringName:
		var p := g.perception
		var d := g.target_dist()
		if d <= Gremlin.SLASH_RANGE_M:
			return &"slash"
		if elapsed() > Gremlin.CHARGE_TIMEOUT_S or (not p.can_see and p.time_since_seen > 1.0):
			AttackTokens.release(g.target, &"melee", g)
			g.melee_ready_at = g.clock + 0.5
			return &"engage"
		g.go_to(g.target.global_position, Gremlin.GALLOP_MPS, 2.0)
		g.play_move(true)
		return &""


class Slash extends GState:
	var _t := 0.0
	var _hit := false
	var _combo := false

	func enter() -> void:
		_combo = false
		_start()

	func _start() -> void:
		_t = 0.0
		_hit = false
		g.face_toward(g.target.global_position)
		g.play(&"slash")

	func on_event(event: StringName) -> void:
		if event == &"slash_hit" and not _hit:
			_hit = true
			g.slash_connects()

	func update(delta: float) -> StringName:
		_t += delta
		var length := g.rig.anim_length(&"slash")
		if _t < length * 0.4:                           # windup tracks the target; the strike commits
			g.face_toward(g.target.global_position)
		if _t < length:
			return &""
		if not _hit:
			_hit = true
			g.slash_connects()
		if not _combo and g.target_dist() <= Gremlin.SLASH_REACH_M and g.rng.randf() < Gremlin.COMBO_CHANCE:
			_combo = true
			_start()
			return &""
		return &"back_off"


class BackOff extends GState:
	const DUR_S := 0.6

	func enter() -> void:
		AttackTokens.release(g.target, &"melee", g)
		g.melee_ready_at = g.clock + Gremlin.MELEE_COOLDOWN_S

	func update(_delta: float) -> StringName:
		var t := g.target.global_position
		g.move(Ground.dir(t, g.global_position), Gremlin.WALK_MPS * 1.5, false)
		g.face_toward(t)
		g.play_move()
		return &"engage" if elapsed() >= DUR_S else &""


## No melee token: orbit at a respectful distance and keep asking (the "battle circle").
class Circle extends GState:
	const RETRY_S := 0.6
	var _side := 1.0

	func enter() -> void:
		_side = 1.0 if g.rng.randf() < 0.5 else -1.0

	func update(_delta: float) -> StringName:
		var t := g.target.global_position
		var d := g.target_dist()
		var radial := Ground.dir(g.global_position, t) * clampf((d - Gremlin.CIRCLE_M) * 1.5, -1.0, 1.0)
		g.move(NavMover.orbit_dir(g.global_position, t, _side) + radial, Gremlin.STRAFE_MPS, false)
		g.face_toward(t)
		g.play_move()
		return &"engage" if elapsed() >= RETRY_S else &""


# ================================================================== lost them
class Search extends GState:
	var _look_t := -1.0

	func enter() -> void:
		g.bark("?", Color("ffd040"))
		_look_t = -1.0

	func update(_delta: float) -> StringName:
		var p := g.perception
		if p.can_see:
			return &"combat"
		if p.consume_heard():
			_look_t = -1.0
		if _look_t < 0.0:
			if g.go_to(p.last_known, Gremlin.WALK_MPS * 1.5, 8.0):
				_look_t = elapsed()
			g.play_move()
		else:
			g.play_loop(&"idle")
			if fmod(elapsed() - _look_t, 0.8) < 0.02:
				g.facing = g.facing.rotated(g.rng.randf_range(-2.0, 2.0))
			if elapsed() - _look_t > Gremlin.SEARCH_LOOK_S:
				p.forget()
				return &"return"
		if elapsed() > Gremlin.SEARCH_TIMEOUT_S:
			p.forget()
			return &"return"
		return &""


class Return extends GState:
	func update(_delta: float) -> StringName:
		var p := g.perception
		if p.is_alert():
			return &"combat"
		if p.consume_heard() and p.level() == Perception.Level.SUSPICIOUS:
			return &"investigate"
		if g.go_to(g.spawn_point, Gremlin.RETURN_MPS, 6.0):
			return &"calm"
		g.play_move()
		return &""


# ================================================================== interrupts
class Hurt extends GState:
	func enter() -> void:
		g.release_tokens()
		g.set_telegraph(0.0)
		g.play(&"hit")

	func update(_delta: float) -> StringName:
		return &"combat" if elapsed() >= Gremlin.STAGGER_S else &""


class Dead extends GState:
	var _gone := false

	func enter() -> void:
		_gone = false
		g.die()
		g.play(&"death")

	func update(_delta: float) -> StringName:
		var t := elapsed()
		if not _gone and t >= g.rig.anim_length(&"death") + Gremlin.CORPSE_S:
			_gone = true
			g.visible = false
		if t >= Gremlin.RESPAWN_S:
			g.respawn()
		return &""
