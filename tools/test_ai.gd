extends SceneTree
## Headless enemy AI tests (gremlin brain, perception, tokens, death/respawn, player hits).
##   godot --headless --path . --fixed-fps 60 -s tools/test_ai.gd
## --fixed-fps makes every frame exactly 1/60 s, so the runs are deterministic and fast.
var fails: Array[String] = []
var main: Node
var world: Node2D
var player: CharacterBody2D

const GREMLIN := preload("res://scenes/enemies/gremlin.tscn")
const OPEN := Vector2(500, 520)         # open floor strip below the dummies (demo floor)

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)

func _initialize() -> void:
	create_timer(240.0).timeout.connect(func(): print("FAIL watchdog: test hung"); quit(99))
	_run.call_deferred()

func frames(sec: float) -> void:
	for i in int(sec * 60.0):
		await physics_frame

## Run `sec` of game time, calling probe(g) every physics frame.
func watch(sec: float, probe: Callable) -> void:
	for i in int(sec * 60.0):
		await physics_frame
		probe.call()

func m(px: float) -> float:
	return px * Ground.METRES_PER_PX

## Screen offset for a ground offset in metres.
func off(gx_m: float, gy_m: float) -> Vector2:
	return Ground.to_screen(Vector2(gx_m, gy_m) / Ground.METRES_PER_PX)

func spawn(at: Vector2, face := Vector2(0, -1)) -> Gremlin:
	var g: Gremlin = GREMLIN.instantiate()
	g.spawn_point = at
	g.position = at
	world.add_child(g)
	g.facing = face
	return g

func clear() -> void:
	for g in world.get_children():
		if g is Gremlin or g is EnemyFireball:
			g.free()
	AttackTokens.reset()
	player._knockback = Vector2.ZERO

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(0.3)
	world = main.get_node("Game/GameViewport/World")
	player = world.get_node("Player")
	var spawner := world.get_node_or_null("Enemies")
	check("main adds an EnemySpawner with gremlins", spawner != null and spawner.gremlins.size() > 0)
	if spawner:
		spawner.free()
	check("player is in group 'player' and hittable", player.is_in_group("player") and player.has_method("take_damage"))

	# --- pacing: player far away and quiet -> stays calm, wanders near its spawn
	clear()
	player.position = Vector2(820, 545)
	var S := Vector2(100, 300)
	var g := spawn(S)
	var max_d := [0.0]
	var states := {}
	await watch(14.0, func():
		max_d[0] = maxf(max_d[0], Ground.dist_m(S, g.global_position))
		states[g.brain.path()] = true)
	check("pacing: stays calm (%s)" % [states.keys()], states.keys().all(func(s): return String(s).begins_with("calm")))
	check("pacing: walks around (max %.2f m from spawn)" % max_d[0], max_d[0] > 0.5)
	check("pacing: stays near spawn (max %.2f m <= %.1f)" % [max_d[0], Gremlin.PACE_RADIUS_M + 0.6], max_d[0] <= Gremlin.PACE_RADIUS_M + 0.6)

	# --- alert by sight: player 4 m in front
	clear()
	g = spawn(OPEN, Vector2(1, 0))                         # facing screen-right
	player.position = OPEN + off(4.0, 0)
	var t_alert := [-1.0]
	var tt := [0.0]
	await watch(2.0, func():
		tt[0] += 1.0 / 60.0
		if t_alert[0] < 0 and g.perception.is_alert():
			t_alert[0] = tt[0])
	check("sight: alerted by a player 4 m ahead (%.2f s)" % t_alert[0], t_alert[0] > 0.0 and t_alert[0] < 1.0)
	check("sight: in combat (%s)" % g.brain.path(), g.brain.current_name == &"combat")

	# --- not seen behind; heard instead
	clear()
	g = spawn(OPEN, Vector2(1, 0))
	player.position = OPEN + off(-5.0, 0)                  # 5 m behind it
	await frames(0.5)
	check("sight: doesn't see a quiet player 5 m behind (awareness %.2f)" % g.perception.awareness, not g.perception.is_alert())
	player.play_note(0)
	await frames(0.1)
	check("hearing: one note -> suspicious (%.2f, %s)" % [g.perception.awareness, g.brain.path()],
			g.perception.level() == Perception.Level.SUSPICIOUS and g.brain.current_name == &"investigate")
	player.play_note(2)
	await frames(0.1)
	check("hearing: second note -> alert", g.perception.is_alert())

	# --- ranged at distance
	clear()
	player.position = OPEN
	g = spawn(player.position + off(-6.5, 0), Vector2(1, 0))
	var seen_states := {}
	var fireballs := [0]
	var hits := [0]
	var was_flash := [false]
	await watch(5.0, func():
		seen_states[g.brain.path()] = true
		for c in world.get_children():
			if c is EnemyFireball and not c.has_meta("counted"):
				c.set_meta("counted", true)
				fireballs[0] += 1
		var fl: bool = player._hurt_flash > 0.0
		if fl and not was_flash[0]:
			hits[0] += 1
		was_flash[0] = fl)
	check("ranged: throws from 6.5 m (%d fireballs, states %s)" % [fireballs[0], seen_states.keys()],
			fireballs[0] >= 2 and seen_states.has("combat/throw"))
	check("ranged: fireballs hit a standing player (%d hits)" % hits[0], hits[0] >= 1)

	# --- melee up close
	clear()
	player.position = OPEN
	g = spawn(player.position + off(-2.0, 0), Vector2(1, 0))
	seen_states = {}
	hits[0] = 0
	was_flash[0] = false
	await watch(5.0, func():
		seen_states[g.brain.path()] = true
		var fl: bool = player._hurt_flash > 0.0
		if fl and not was_flash[0]:
			hits[0] += 1
		was_flash[0] = fl
		player.position = OPEN)               # stand still (no knockback walk-off)
	check("melee: charges and slashes up close (%s)" % [seen_states.keys()], seen_states.has("combat/slash"))
	check("melee: no throwing at 2 m", not seen_states.has("combat/throw"))
	check("melee: claws connect (%d hits)" % hits[0], hits[0] >= 1)

	# --- attack tokens: 5 gremlins around the player, at most 2 in melee at once
	clear()
	player.position = OPEN
	var pack: Array[Gremlin] = []
	for i in 5:
		var a := TAU * i / 5.0
		pack.append(spawn(player.position + off(cos(a) * 2.5, sin(a) * 2.5), -Vector2.from_angle(a)))
	var max_tok := [0]
	var max_melee := [0]
	var circled := [false]
	await watch(6.0, func():
		max_tok[0] = maxi(max_tok[0], AttackTokens.count(player, &"melee"))
		var n := 0
		for p in pack:
			var s := p.brain.path()
			if s in ["combat/charge", "combat/slash"]:
				n += 1
			if s == "combat/circle":
				circled[0] = true
		max_melee[0] = maxi(max_melee[0], n)
		player.position = OPEN)
	check("tokens: <= %d melee tokens held (max %d)" % [AttackTokens.limits[&"melee"], max_tok[0]], max_tok[0] <= AttackTokens.limits[&"melee"])
	check("tokens: <= 2 gremlins charging/slashing at once (max %d)" % max_melee[0], max_melee[0] <= 2 and max_melee[0] >= 1)
	check("tokens: the others circle and wait", circled[0])

	# --- de-aggro: player vanishes -> search -> return -> calm
	clear()
	player.position = OPEN
	S = player.position + off(-3.0, 0)
	g = spawn(S, Vector2(1, 0))
	await frames(1.0)
	check("de-aggro: starts in combat", g.brain.current_name == &"combat")
	player.position = Vector2(4000, 4000)
	seen_states = {}
	await watch(45.0, func(): seen_states[g.brain.current_name] = true)
	check("de-aggro: searched, returned, calmed down (%s, now %s)" % [seen_states.keys(), g.brain.path()],
			seen_states.has(&"search") and seen_states.has(&"return") and g.brain.current_name == &"calm")
	check("de-aggro: back home (%.2f m)" % Ground.dist_m(S, g.global_position), Ground.dist_m(S, g.global_position) < Gremlin.PACE_RADIUS_M + 0.6)

	# --- death and respawn
	clear()
	player.position = Vector2(820, 545)
	S = Vector2(100, 300)
	g = spawn(S)
	await frames(0.2)
	g.take_damage(10, &"melee", Vector2.RIGHT)
	check("damage: hurt + alerted (%s, hp %d)" % [g.brain.current_name, g.hp], g.brain.current_name == &"hurt" and g.hp == Gremlin.MAX_HP - 10 and g.perception.is_alert())
	g.take_damage(100, &"fire", Vector2.RIGHT)
	await frames(0.1)
	check("death: dead and out of 'enemies'", g.is_dead() and not g.is_in_group("enemies"))
	await frames(Gremlin.RESPAWN_S * 0.5)
	check("death: corpse vanished", not g.visible)
	await frames(Gremlin.RESPAWN_S * 0.5 + 0.3)
	check("respawn: back at spawn, full hp, calm, hittable (%s)" % g.brain.path(),
			g.visible and g.hp == Gremlin.MAX_HP and g.is_in_group("enemies") and g.brain.current_name == &"calm"
			and Ground.dist_m(S, g.global_position) < 0.5)

	# --- player hit feedback: number + flash + shove, spells still work
	clear()
	player.position = OPEN
	var before := world.get_children().filter(func(c): return c is FloatText).size()
	var p0 := player.position
	player.take_damage(5, &"claw", Vector2.RIGHT)
	await frames(0.05)
	var after := world.get_children().filter(func(c): return c is FloatText).size()
	check("player hit: damage number spawned", after > before)
	check("player hit: flash + shove right", player._hurt_flash > 0.0 and player.position.x > p0.x)
	check("player hit: notes still play", not player.rig.is_busy())

	# --- enemy fireball flies past other gremlins
	clear()
	player.position = Vector2(820, 545)
	await frames(0.1)                                        # let physics see the move
	var a1 := spawn(OPEN + Vector2(30, 0))
	var fb := EnemyFireball.new()
	fb.position = OPEN
	fb.velocity = Ground.velocity(Vector2.RIGHT, EnemyFireball.SPEED_MPS)
	fb.caster = null
	world.add_child(fb)
	await frames(0.5)
	check("enemy fireball passes through gremlins", is_instance_valid(fb) and fb.position.x > 160.0 and a1.hp == Gremlin.MAX_HP)
	clear()

	print("ALL PASS" if fails.is_empty() else "FAILURES: %d" % fails.size())
	quit(fails.size())
