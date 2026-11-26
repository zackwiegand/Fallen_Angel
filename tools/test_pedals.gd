extends SceneTree
## Headless pedal tests: chain order -> spell transform (all orders + bypass), echo damage values,
## Pedals bus effect order, fireball / lightning pierce + echoes on real dummies, and the in-game
## flow (pickups -> chain -> trail, menu reorder / bypass / pause).
##   godot --headless --path . -s tools/test_pedals.gd
const WATCHDOG_S := 60.0
const DELAY := &"chief_delay"
const PHASER := &"skyman_phaser"

var fails: Array[String] = []


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL watchdog: test hung")
		quit(1))
	_run.call_deferred()


func _board(chain: Array, bypass: Array = []) -> Pedalboard:
	var b := Pedalboard.new()
	root.add_child(b)
	for id: StringName in chain:
		b.add_pedal(id)
	for id: StringName in bypass:
		b.set_bypassed(id, true)
	return b


func _fire(b: Pedalboard) -> SpellCast:
	return b.apply(SpellCast.fire(Vector2.ZERO, 20.0, Vector2.UP, null, null))


func _run() -> void:
	_test_transforms()
	_test_falloff()
	_test_bus()
	await _test_fireball_pierce()
	await _test_lightning_pierce()
	await _test_game_flow()
	print("FAILURES: ", fails.size())
	quit(fails.size())


# ---------------------------------------------------------------- pure rules
func _test_transforms() -> void:
	var c := _fire(_board([]))
	check("no pedals: dry fireball", not c.pierce and c.echoes == 0 and c.ghosts == 0 and not c.phased)
	c = _fire(_board([DELAY]))
	check("delay: 3 echoes on the first target, no pierce", c.echoes == 3 and not c.pierce and c.ghosts == 0
			and is_equal_approx(c.echo_delay, DelayPedal.ECHO_TIME))
	c = _fire(_board([PHASER]))
	check("phaser: pierces + phased", c.pierce and c.phased and c.echoes == 0 and c.ghosts == 0)
	c = _fire(_board([PHASER, DELAY]))
	check("phaser > delay: pierce + echoes on every target", c.pierce and c.echoes == 3 and c.ghosts == 0)
	c = _fire(_board([DELAY, PHASER]))
	check("delay > phaser: 3 piercing ghosts, no echo ticks", c.pierce and c.phased and c.ghosts == 3
			and c.echoes == 0 and is_equal_approx(c.ghost_delay, DelayPedal.ECHO_TIME))
	c = _fire(_board([DELAY, PHASER], [PHASER]))
	check("delay > phaser(bypassed) == delay alone", c.echoes == 3 and not c.pierce and c.ghosts == 0)
	c = _fire(_board([DELAY, PHASER], [DELAY]))
	check("delay(bypassed) > phaser == phaser alone", c.pierce and c.ghosts == 0 and c.echoes == 0)
	check("touched_by records order", _fire(_board([PHASER, DELAY])).touched_by == [PHASER, DELAY])
	var b := _board([DELAY, PHASER])
	b.move(1, 0)
	check("move reorders the chain", b.chain == [PHASER, DELAY])
	check("describe mentions ghosts for delay > phaser", "GHOSTS" in _board([DELAY, PHASER]).describe()[0])
	print("  menu text: ", _board([PHASER, DELAY]).describe())


func _test_falloff() -> void:
	var got := [Damage.falloff(10, 1), Damage.falloff(10, 2), Damage.falloff(10, 3)]
	check("10 -> echoes %s == [5, 3, 1]" % [got], got == [5, 3, 1])
	got = [Damage.falloff(12, 1), Damage.falloff(12, 2), Damage.falloff(12, 3)]
	check("12 -> echoes %s == [6, 3, 2]" % [got], got == [6, 3, 2])
	got = [Damage.falloff(5, 1), Damage.falloff(5, 2), Damage.falloff(5, 3)]
	check("5 -> echoes %s == [3, 1, 1] (min 1)" % [got], got == [3, 1, 1])
	check("echo kind round-trip", Damage.base_kind(Damage.echo_kind(&"fire")) == &"fire"
			and Damage.is_echo(&"fire_echo") and not Damage.is_echo(&"fire"))


func _test_bus() -> void:
	var b := _board([PHASER, DELAY])
	var bus := AudioServer.get_bus_index(Pedalboard.BUS)
	check("Pedals bus exists and feeds Master", bus > 0 and AudioServer.get_bus_send(bus) == &"Master")
	var kinds := []
	for i in AudioServer.get_bus_effect_count(bus):
		kinds.append(AudioServer.get_bus_effect(bus, i).get_class())
	check("bus effects follow the chain %s" % [kinds], kinds == ["AudioEffectPhaser", "AudioEffectDelay"])
	b.move(0, 1)
	kinds.clear()
	for i in AudioServer.get_bus_effect_count(bus):
		kinds.append(AudioServer.get_bus_effect(bus, i).get_class())
	check("reorder updates the bus %s" % [kinds], kinds == ["AudioEffectDelay", "AudioEffectPhaser"])
	b.set_bypassed(DELAY, true)
	check("bypass disables the effect", not AudioServer.is_bus_effect_enabled(bus, 0)
			and AudioServer.is_bus_effect_enabled(bus, 1))
	var sfx := Sfx.new()
	sfx.bus = Pedalboard.BUS
	root.add_child(sfx)
	var routed := sfx.get_children().all(func(p: Node) -> bool: return p.bus == Pedalboard.BUS)
	check("player Sfx players route to the Pedals bus", routed)
	sfx.free()


# ---------------------------------------------------------------- real dummies
## Three dummies in a column above `x`, the fireball flying up into them from below.
func _column(x: float) -> Array:
	var scene: PackedScene = load("res://scenes/dummy.tscn")
	var out := []
	for y in [200.0, 160.0, 120.0]:
		var d: Node2D = scene.instantiate()
		d.position = Vector2(x, y)
		root.add_child(d)
		out.append(d)
	return out


func _shoot(chain: Array, x: float) -> Array:
	var dummies := _column(x)
	await physics_frame
	var cast := _fire(_board(chain))
	cast.origin = Vector2(x, 260)
	cast.height = 20.0
	cast.launch(root)
	await create_timer(Fireball.RANGE_S + DelayPedal.ECHO_TIME * 3 + 0.6).timeout
	var dmg := dummies.map(func(d: Node) -> int: return d.total_damage)
	for d in dummies:
		d.queue_free()
	return dmg


func _test_fireball_pierce() -> void:
	var dry := await _shoot([], 40)
	check("dry fireball stops at the first dummy %s" % [dry], dry == [12, 0, 0])
	var phased := await _shoot([PHASER], 120)
	check("phased fireball pierces all three %s" % [phased], phased == [12, 12, 12])
	var delayed := await _shoot([DELAY], 200)
	check("delay: first dummy takes 12+6+3+2 %s" % [delayed], delayed == [23, 0, 0])
	var pd := await _shoot([PHASER, DELAY], 280)
	check("phaser > delay: every dummy takes 23 %s" % [pd], pd == [23, 23, 23])
	var dp := await _shoot([DELAY, PHASER], 360)
	check("delay > phaser: original + 3 ghosts pierce all %s" % [dp], dp == [23, 23, 23])


func _test_lightning_pierce() -> void:
	for phaser in [false, true]:
		var dummies := _column(440)
		await physics_frame
		var b := _board([PHASER] if phaser else [])
		var cast := b.apply(SpellCast.lightning(1, Vector2(440, 260), Vector2.UP, null, null))
		cast.launch(root)
		await create_timer(0.5).timeout
		var dmg := dummies.map(func(d: Node) -> int: return d.total_damage)
		if phaser:
			check("phased bolt passes through to the dummy behind %s" % [dmg], dmg[0] == 5 and dmg[1] == 5)
		else:
			check("dry bolt hits only its target %s" % [dmg], dmg == [5, 0, 0])
		for d in dummies:
			d.queue_free()
		await physics_frame


# ---------------------------------------------------------------- in-game flow
func _test_game_flow() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var world: Node = main.get_node("Game/GameViewport/World")
	var p = world.get_node("Player")
	var pickups := world.get_children().filter(func(n: Node) -> bool: return n is PedalPickup)
	check("two pedal pickups on the floor (got %d)" % pickups.size(), pickups.size() == 2)
	var order: Array[StringName] = []
	for pk: PedalPickup in pickups:
		order.append(pk.pedal_id)
		p.global_position = pk.global_position
		await create_timer(0.15).timeout
	check("walking over pickups fills the chain in pickup order %s" % [p.pedalboard.chain], p.pedalboard.chain == order)
	var trail: PedalTrail = world.get_children().filter(func(n: Node) -> bool: return n is PedalTrail)[0]
	check("trail floats both pedals", trail.floater(DELAY) != null and trail.floater(PHASER) != null)
	await create_timer(1.5).timeout     # idle: they gather near the player
	var near := [DELAY, PHASER].all(func(id: StringName) -> bool:
		return trail.floater(id).position.distance_to(p.position) < 45.0)
	check("idle pedals hover near the player", near)

	var menu: PedalboardMenu = main.get_node("PedalboardMenu")
	menu._unhandled_input(_action("pedal_menu"))
	check("Tab opens the menu and pauses", menu.is_open() and paused)
	var first: StringName = p.pedalboard.chain[0]
	menu._unhandled_input(_action("ui_accept"))
	menu._unhandled_input(_action("ui_right"))
	menu._unhandled_input(_action("ui_accept"))
	check("pick up + right + drop moves the first pedal to the end", p.pedalboard.chain[1] == first)
	menu._unhandled_input(_action("pedal_bypass"))
	check("B bypasses the pedal under the cursor", p.pedalboard.is_bypassed(first))
	menu._unhandled_input(_action("pedal_bypass"))
	menu._unhandled_input(_action("pedal_menu"))
	check("Tab closes and unpauses", not menu.is_open() and not paused and not p.pedalboard.is_bypassed(first))
	main.queue_free()
	await process_frame


func _action(name: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev
