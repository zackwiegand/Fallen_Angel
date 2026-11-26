class_name ChargeAura
extends Node2D
## Crackling energy around the character while a spell charges up, in the spell's colours.
## Two instances wrap the sprite (by child order): `front` draws over it, the other behind it, so arcs
## read as going around the body. Polls the spellbook each frame for how built-up the spell is:
##   pattern recognised, no charge yet -> faint static
##   charges 1..30 -> more and longer arcs, wider aura, more sparks; ground ring from 6 charges
## Each new charge sends a pulse; releasing bursts outward and fades.

const PALETTES := {
	&"lightning": {"glow": Color("3a6cff"), "core": Color("bfe8ff"), "hot": Color.WHITE},
}
const CENTER := Vector2(0, -36)       # chest height above the feet (px)
const REFRESH := 0.05                 # arcs re-roll this often (crackle rate)
const FULL := 12.0                    # charges at which the aura reaches full size

var front := true
var spellbook: Spellbook
var spell := &"lightning"

var _arcs: Array[PackedVector2Array] = []
var _sparks: PackedVector2Array = []
var _reroll := 0.0
var _pulse := 1.0                     # 0 -> 1 after each new charge
var _burst := 1.0                     # 0 -> 1 after a release
var _burst_level := 0.0


func on_charge_changed(_spell: StringName, charges: int) -> void:
	if charges > 0:
		_pulse = 0.0


func discharge(level: float) -> void:
	_burst = 0.0
	_burst_level = level


func _level() -> float:
	if spellbook == null:
		return 0.0
	if spellbook.charges > 0:
		return 0.15 + float(spellbook.charges) / FULL
	return 0.08 if spellbook.skip_progress() >= 2 else 0.0


func _process(delta: float) -> void:
	_pulse = minf(_pulse + delta / 0.18, 1.0)
	_burst = minf(_burst + delta / 0.4, 1.0)
	_reroll -= delta
	if _reroll <= 0.0:
		_reroll = REFRESH
		_roll(_level())
	queue_redraw()


func _radius(level: float) -> Vector2:
	var l := minf(level, 1.8)            # keeps widening a little past FULL
	return Vector2(13.0 + 6.0 * l, 24.0 + 8.0 * l)


func _roll(level: float) -> void:
	_arcs.clear()
	_sparks.clear()
	if level <= 0.0:
		return
	var r := _radius(level)
	# arcs: count and length grow with charge; this instance draws its half of them
	var charges := spellbook.charges
	var n := mini(2 + charges, 22)      # every charge adds an arc (up to ~20 charges)
	if charges == 0:
		n = 1 if randf() < 0.4 else 0  # pattern recognised: faint static flickers now and then
	for i in n:
		if (randf() < 0.5) != front:
			continue
		var a := randf() * TAU
		var span := randf_range(0.5, 0.9 + minf(level, 2.0))
		var pts := PackedVector2Array()
		var steps := 4 + int(span * 3.0)
		for k in steps + 1:
			var t := a + span * k / steps
			var jitter := randf_range(-3.0, 3.0) if k > 0 and k < steps else 0.0
			pts.append((CENTER + Vector2(cos(t) * (r.x + jitter), sin(t) * (r.y + jitter))).round())
		_arcs.append(pts)
	for i in mini(charges * 2, 40):
		if (randf() < 0.5) != front:
			continue
		var t := randf() * TAU
		var k := randf_range(0.6, 1.25)
		_sparks.append((CENTER + Vector2(cos(t) * r.x * k, sin(t) * r.y * k)).round())


func _draw() -> void:
	var pal: Dictionary = PALETTES[spell]
	var level := _level()
	if level > 0.0:
		for pts in _arcs:
			for off in [Vector2(1, 0), Vector2(0, 1)]:
				draw_polyline(_offset(pts, off), Color(pal.glow, 0.8), 1.0)
			draw_polyline(pts, pal.core if randf() < 0.7 else pal.hot, 1.0)
		for p in _sparks:
			draw_rect(Rect2(p, Vector2.ONE), pal.hot if randf() < 0.4 else pal.core)
		if front and spellbook.charges >= 6:
			_ring(Vector2.ZERO, Vector2(16.0, 10.0) + Vector2(6, 4) * minf(level, 1.5), Color(pal.glow, 0.7), 18)
		if front and _pulse < 1.0:
			var pr := _radius(level) * (1.0 + 0.4 * _pulse)
			_ring(CENTER, pr, Color(pal.core, 1.0 - _pulse), 28)
	if front and _burst < 1.0:
		var br := _radius(_burst_level) * (1.0 + 1.5 * _burst)
		_ring(CENTER, br, Color(pal.hot, 1.0 - _burst), 32)
		_ring(CENTER, br * 0.8, Color(pal.glow, 1.0 - _burst), 32)
		if _burst < 0.5:                  # arcs shooting outward from the body
			var spokes := 6 + int(minf(_burst_level, 2.0) * 4.0)
			for i in spokes:
				var dir := Vector2.from_angle(TAU * (i + randf() * 0.5) / spokes)
				var inner := CENTER + dir * _radius(_burst_level) * 0.6
				var outer := CENTER + dir * br * 1.2
				var mid := inner.lerp(outer, 0.5) + dir.orthogonal() * randf_range(-3, 3)
				draw_polyline(PackedVector2Array([inner.round(), mid.round(), outer.round()]), pal.core, 1.0)


## Broken ellipse: a crackling ring, gaps re-rolled every frame.
func _ring(c: Vector2, r: Vector2, col: Color, segs: int) -> void:
	for i in segs:
		if randf() < 0.3:
			continue
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		draw_line((c + Vector2(cos(a0) * r.x, sin(a0) * r.y)).round(),
				(c + Vector2(cos(a1) * r.x, sin(a1) * r.y)).round(), col, 1.0)


func _offset(pts: PackedVector2Array, o: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + o)
	return out
