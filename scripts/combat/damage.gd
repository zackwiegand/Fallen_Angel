class_name Damage
## Damage helpers shared by spells, pedals and anything else that hurts things.
## Targets implement `take_damage(amount: int, kind: StringName, from_dir: Vector2)`.
##
## Echo hits (CHIEF delay) keep their element and add an "_echo" suffix to the kind
## (&"fire" -> &"fire_echo"), so a target can show them fainter / skip big reactions without the
## damage interface growing a parameter. Use base_kind() for element logic (resistances, burn).

const ECHO_SUFFIX := "_echo"


static func echo_kind(kind: StringName) -> StringName:
	return StringName(str(kind) + ECHO_SUFFIX)


static func is_echo(kind: StringName) -> bool:
	return str(kind).ends_with(ECHO_SUFFIX)


static func base_kind(kind: StringName) -> StringName:
	var s := str(kind)
	return StringName(s.trim_suffix(ECHO_SUFFIX))


## Halving falloff: the k-th repeat (1-based) of `amount` = amount / 2^k, rounded, at least 1.
## 10 -> 5, 3, 1;  12 -> 6, 3, 2.
static func falloff(amount: int, k: int) -> int:
	return maxi(1, roundi(amount / pow(2.0, k)))


## Hits `target` for `amount` now, then `echoes` fainter repeats every `echo_delay` seconds, each half
## the previous (falloff). Echo timers pause with the game. `sfx` (optional) pings on every echo.
static func deal(target: Node, amount: int, kind: StringName, from_dir: Vector2,
		echoes := 0, echo_delay := 0.0, sfx: Sfx = null) -> void:
	target.take_damage(amount, kind, from_dir)
	for k in range(1, echoes + 1):
		var echo_amount := falloff(amount, k)
		var timer := target.get_tree().create_timer(echo_delay * k, false)
		timer.timeout.connect(func() -> void:
			if not is_instance_valid(target) or target.is_queued_for_deletion():
				return
			target.take_damage(echo_amount, echo_kind(kind), from_dir)
			if is_instance_valid(sfx):
				sfx.play(&"echo_ping"))
