class_name GremlinRig
extends Node2D
## PLACEHOLDER (workstream D) with the agreed interface; workstream C replaces the internals with the
## live 3D render of the Blender gremlin (SubViewport -> Sprite2D, feet at this node's origin).
## Draws a small dark-red quadruped with horns and fakes clip timings + events on timers.

signal anim_event(event: StringName)

## [length s, loops, events {time: event}]
const CLIPS := {
	&"idle": [1.6, true, {}],
	&"walk": [0.9, true, {0.2: &"step", 0.65: &"step"}],
	&"gallop": [0.42, true, {0.1: &"step"}],
	&"throw": [0.75, false, {0.45: &"throw_release"}],
	&"slash": [0.6, false, {0.32: &"slash_hit"}],
	&"hit": [0.3, false, {}],
	&"death": [0.8, false, {0.8: &"death_done"}],
}

var facing := Vector2(0, -1):
	set(v):
		if v != Vector2.ZERO:
			facing = _snap8(v)

var _anim: StringName = &"idle"
var _t := 0.0


func play(anim: StringName) -> void:
	if not CLIPS.has(anim):
		push_warning("GremlinRig: no clip %s" % anim)
		return
	_anim = anim
	_t = 0.0


func anim_length(anim: StringName) -> float:
	return CLIPS[anim][0] if CLIPS.has(anim) else 0.0


## Throwing claw, local 2D (screen) position relative to the feet.
func hand_point() -> Vector2:
	var side := 1.0 if facing.x >= 0.0 else -1.0
	var raise := 0.0
	if _anim == &"throw":
		raise = -6.0 * sin(clampf(_t / 0.45, 0.0, 1.0) * PI * 0.5)
	return Vector2(side * 7.0, -14.0 + raise)


func _process(delta: float) -> void:
	var clip: Array = CLIPS[_anim]
	var prev := _t
	_t += delta
	var length: float = clip[0]
	for at: float in clip[2]:
		if prev < at and _t >= at:
			anim_event.emit(clip[2][at])
	if _t >= length:
		if clip[1]:
			_t = fmod(_t, length)
			for at: float in clip[2]:            # events right at the wrap
				if at <= _t:
					anim_event.emit(clip[2][at])
		else:
			_t = length
	queue_redraw()


func _draw() -> void:
	var dark := Color("3a0a0a")
	var body := Color("8a1a14")
	var hi := Color("c0392b")
	var horn := Color("d8c8a0")
	var side := 1.0 if facing.x >= 0.0 else -1.0
	var u := _t / anim_length(_anim)
	var bob := 0.0
	var lean := 0.0
	var squash := 1.0
	match _anim:
		&"walk": bob = absf(sin(u * TAU)) * -1.0
		&"gallop": bob = absf(sin(u * TAU)) * -3.0; lean = 2.0
		&"idle": squash = 1.0 + 0.05 * sin(u * TAU)
		&"throw": lean = -2.0 if u < 0.6 else 2.0
		&"slash": lean = -1.0 if u < 0.45 else 4.0
		&"hit": lean = -3.0
	if _anim == &"death":
		var k := minf(u * 1.5, 1.0)
		draw_set_transform(Vector2(0, 0), side * k * PI * 0.5, Vector2.ONE)
	# legs
	for lx in [-6.0, -3.0, 3.0, 6.0]:
		var step := sin(u * TAU + lx) * (2.0 if _anim in [&"walk", &"gallop"] else 0.0)
		draw_rect(Rect2(Vector2(lx * side - 1 + step, -5 + bob), Vector2(2, 5)), dark)
	# body + head
	draw_set_transform(Vector2(lean * side, bob), 0.0, Vector2(1, squash))
	draw_circle(Vector2(0, -9), 7.5, dark)
	draw_circle(Vector2(0, -9), 6.5, body)
	draw_circle(Vector2(-2 * side, -11), 2.5, hi)
	var head := Vector2(7 * side, -14)
	draw_circle(head, 4.5, dark)
	draw_circle(head, 3.5, body)
	draw_rect(Rect2(head + Vector2(side * 1 - 1, -1), Vector2(1, 1)), Color("ffd040"))
	# gnarled horns
	for hs in [-1.0, 1.0]:
		var base := head + Vector2(hs * 2.0, -3.0)
		draw_line(base, base + Vector2(hs * 2, -3), horn, 1.0)
		draw_line(base + Vector2(hs * 2, -3), base + Vector2(hs * 1, -6), horn, 1.0)
	# claw
	if _anim in [&"throw", &"slash"]:
		var hp := hand_point() - Vector2(lean * side, bob)
		draw_circle(hp, 2.0, dark)
	draw_set_transform(Vector2.ZERO)


static func _snap8(v: Vector2) -> Vector2:
	var a := snappedf(v.angle(), PI / 4.0)
	return Vector2.from_angle(a)
