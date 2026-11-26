extends SceneTree
## Headless chain-lightning targeting tests with stand-in enemies (no world needed):
## nearest first, fewest-hits-first spreading within BOUNCE_RANGE (a mob gets hit evenly), lone target
## re-hit, BOUNCE_RANGE / CHAIN_REACH / FIRST_RANGE limits.
##   godot --headless --path . -s tools/test_lightning.gd
const WATCHDOG_S := 30.0
const TARGET_SRC := """
extends Node2D
var log: Array
func hit_point() -> Vector2:
	return global_position
func take_damage(amount: int, kind: StringName, from_dir: Vector2) -> void:
	log.append(str(name))
"""

var fails: Array[String] = []
var _target_script: GDScript
var _log: Array = []


func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)


func _initialize() -> void:
	create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print("FAIL watchdog: test hung")
		quit(1))
	_target_script = GDScript.new()
	_target_script.source_code = TARGET_SRC
	_target_script.reload()
	_run.call_deferred()


## Spawns stand-in enemies at `spots` ({name: position}), fires `charges` hops from `origin` aiming
## `aim`, waits for the chain to finish and returns the hit order (names).
func _chain(spots: Dictionary, charges: int, origin := Vector2.ZERO, aim := Vector2.DOWN) -> Array:
	var world := Node2D.new()
	root.add_child(world)
	_log = []
	for n: String in spots:
		var t := Node2D.new()
		t.set_script(_target_script)
		t.name = n
		t.position = spots[n]
		t.log = _log
		t.add_to_group("enemies")
		world.add_child(t)
	var chain := ChainLightning.new()
	chain.charges = charges
	chain.origin = origin
	chain.aim = aim
	world.add_child(chain)
	await create_timer(ChainLightning.HOP_DELAY * charges + 0.5).timeout
	var out := _log.duplicate()
	world.queue_free()
	await process_frame
	return out


func _run() -> void:
	var step := ChainLightning.BOUNCE_RANGE * 0.6     # neighbours in range, two steps apart are not
	var far := ChainLightning.BOUNCE_RANGE * 1.5

	var hits := await _chain({"A": Vector2(0, 40), "B": Vector2(0, 40 + far)}, 1)
	check("first bolt hits the nearest enemy (%s)" % [hits], hits == ["A"])

	hits = await _chain({"A": Vector2(0, 40), "B": Vector2(step, 40), "C": Vector2(2 * step, 40)}, 3)
	check("hops to new enemies in range first (%s)" % [hits], hits == ["A", "B", "C"])

	hits = await _chain({"A": Vector2(0, 40), "B": Vector2(step, 40), "C": Vector2(2 * step, 40)}, 6)
	check("A and C out of each other's range -> spreads via B (%s)" % [hits],
			hits == ["A", "B", "C", "B", "A", "B"])

	var r := 70.0                                      # a mob of 4 around the caster (2.6 m circle)
	var mob := {"N": Vector2(0, -r * 0.62), "E": Vector2(r, 0), "S": Vector2(0, r * 0.62), "W": Vector2(-r, 0)}
	hits = await _chain(mob, 8, Vector2.ZERO, Vector2.RIGHT)
	var counts := {}
	for n: String in hits:
		counts[n] = counts.get(n, 0) + 1
	check("mob of 4: first 4 hops hit all 4 (%s)" % [hits], hits.slice(0, 4).duplicate().all(
			func(n: String) -> bool: return hits.slice(0, 4).count(n) == 1))
	check("mob of 4, 8 charges: 2 hits each (%s)" % [counts], counts.size() == 4 and counts.values().all(
			func(c: int) -> bool: return c == 2))

	hits = await _chain({"A": Vector2(0, 40), "B": Vector2(step, 40), "Far": Vector2(step + far, 40)}, 5)
	check("never jumps farther than BOUNCE_RANGE (%s)" % [hits], "Far" not in hits and hits.size() == 5)

	hits = await _chain({"A": Vector2(0, 40)}, 3)
	check("lone enemy is struck again (%s)" % [hits], hits == ["A", "A", "A"])

	var line := {}
	for i in 12:                                       # a long line of enemies, each in bounce range
		line["E%d" % i] = Vector2(0, 40 + i * step)
	hits = await _chain(line, 12)
	var reach_ok := hits.all(func(n: String) -> bool: return line[n].length() <= ChainLightning.CHAIN_REACH)
	check("chain stays within CHAIN_REACH of the caster (%s)" % [hits], reach_ok and hits.size() == 12)

	hits = await _chain({"A": Vector2(0, ChainLightning.FIRST_RANGE + 20)}, 2)
	check("nothing within FIRST_RANGE -> no hits (%s)" % [hits], hits.is_empty())

	print("ALL PASS" if fails.is_empty() else "FAILURES: %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
