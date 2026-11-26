extends SceneTree
## Headless spell tests: note-pattern detection, then fireball / lightning / swing damage in the room.
##   godot --headless --path . -s tools/test_spells.gd
var fails: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _spells(notes: Array) -> Array:
	var sb := Spellbook.new()
	root.add_child(sb)
	var out := []
	sb.cast.connect(func(s, p): out.append("%s%d" % [s, p]))
	for n in notes:
		sb.play_note(n)
	sb._process(Spellbook.SKIP_RELEASE + 0.1)   # pause -> release
	sb.free()
	return out

func _run() -> void:
	for t in [
		[[0, 1, 3], ["fire1"]], [[1, 3, 4], ["fire1"]], [[3, 1, 0], ["fire1"]], [[5, 3, 1], ["fire1"]],
		[[0, 3, 6], ["fire1"]], [[3, 4, 6], ["fire1"]],
		[[0, 2, 1], []], [[0, 2, 1, 3], ["lightning1"]], [[0, 2, 1, 3, 2, 4], ["lightning3"]],
		[[7, 5, 6, 4, 5], ["lightning2"]], [[0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 4, 5], ["lightning12"]],
		[[0, 1, 2, 3, 4, 5, 6, 7], []], [[7, 6, 5, 4, 3, 2, 1, 0], []],
		[[0, 2, 1, 3, 7], ["lightning1"]],
		# up, then stagger back down with a step at the top (Q E W R E A R S A D S F D A S R A E R W E Q W ...)
		[[0, 2, 1, 3, 2, 4, 3, 5, 4, 6, 5, 7, 6, 4, 5, 3, 4, 2, 3, 1, 2, 0, 1], ["lightning20"]],
		# turnaround with a leap at the top edge (..5 7 5 6 4..)
		[[3, 5, 4, 6, 5, 7, 5, 6, 4, 5, 3], ["lightning8"]],
		# leap-leap spam mid-keyboard does not build charges
		[[0, 2, 0, 2, 0, 2], []],
	]:
		var got := _spells(t[0])
		check("%s -> %s (got %s)" % [t[0], t[1], got], got == t[1])

	# charge build-up is visible to code: charge_changed 1, 2, 3, then 0 on release
	var sb := Spellbook.new()
	root.add_child(sb)
	var seen := []
	sb.charge_changed.connect(func(_s, c): seen.append(c))
	for n in [0, 2, 1]:
		sb.play_note(n)
	check("pattern recognised before first charge (progress %d)" % sb.skip_progress(), sb.skip_progress() == 3 and sb.charges == 0)
	for n in [3, 2, 4]:
		sb.play_note(n)
	sb._process(Spellbook.SKIP_RELEASE + 0.1)
	check("charge_changed sequence %s" % [seen], seen == [1, 2, 3, 0])
	sb.free()

	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	var world: Node = main.get_node("Game/GameViewport/World")
	var p = world.get_node("Player")
	if world.has_node("Enemies"):              # spell maths against the dummies only (no gremlins)
		world.get_node("Enemies").free()
	var dummies := get_nodes_in_group("enemies")
	check("7 dummies in the room", dummies.size() == 7)

	# fireball: stand 60px below the middle dummy (Dummy4), facing it (positions relative to the level)
	var mid: Node2D = world.get_node("Dummy4")
	p.position = mid.position + Vector2(0, 60)
	p.facing = Vector2(0, 1)
	p.rig.face(PI)
	for n in [0, 1, 3]:
		p.play_note(n)
	await create_timer(0.2).timeout
	check("triad starts cast", p.rig.playback.get_current_node() == &"cast")
	await create_timer(1.4).timeout
	check("fireball hit Dummy4 for 12 (got %d)" % mid.total_damage, mid.total_damage == 12)

	# lightning: 10 skip notes = 7 charges -> 7 hits on the dummies near the player (targeting order
	# itself is covered by tools/test_lightning.gd)
	for d in dummies: d.total_damage = 0
	p.position = mid.position + Vector2(0, 65)
	for n in [0, 2, 1, 3, 2, 4, 3, 5, 4, 6]:
		p.play_note(n)
		await create_timer(0.15).timeout
	await create_timer(Spellbook.SKIP_RELEASE + 1.2).timeout
	var hit_counts: Array = dummies.map(func(d): return d.total_damage / 5)
	var total: int = hit_counts.reduce(func(a, c): return a + c, 0)
	check("lightning x7 = 7 hits on nearby dummies (hits per dummy %s)" % [hit_counts], total == 7 and hit_counts[3] >= 1)

	# swing: 25px left of Dummy1, facing right
	var before: int = world.get_node("Dummy1").total_damage
	p.position = world.get_node("Dummy1").position + Vector2(-25, 2)
	p.facing = Vector2(1, 0)
	p.rig.face(PI / 2)
	p.rig.play_action(&"swing")
	await create_timer(1.6).timeout
	check("swing hit Dummy1 for 8", world.get_node("Dummy1").total_damage - before == 8)
	print("FAILURES: ", fails.size())
	quit(fails.size())
