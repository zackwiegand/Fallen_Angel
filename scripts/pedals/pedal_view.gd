class_name PedalView
extends Node2D
## How one pedal looks in the game: PLACEHOLDER art (a chunky box in the pedal's colours).
## Workstream A replaces the internals with a live 3D render of assets/pedals/pedal_<id>.glb; the
## interface below is the contract the trail, pickups and menu use.
## Origin = centre of the pedal's base (where it would sit on the floor); it draws upward from there.

const SIZE := Vector2i(14, 17)

var facing := Vector2(0, -1):           # ground direction like player.facing; snaps to 8 directions
	set(v):
		facing = v
		queue_redraw()
var lit := true:                        # LED on (false = bypassed)
	set(v):
		lit = v
		queue_redraw()

var _def: PedalDef


func setup(pedal_id: StringName) -> void:
	_def = PedalRegistry.get_def(pedal_id)
	queue_redraw()


## Local position of a jack: &"in" (the pedal's right side, as on real pedals) or &"out" (left).
func jack_point(which: StringName) -> Vector2:
	var x := SIZE.x / 2.0 + 1.0
	return Vector2(x if which == &"in" else -x, -SIZE.y * 0.55)


func _draw() -> void:
	if _def == null:
		return
	var w := SIZE.x
	var h := SIZE.y
	var r := Rect2(-w / 2, -h, w, h)
	draw_rect(r.grow(1), Color("0c0a10"))                                     # outline
	draw_rect(r, _def.body_color)
	draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(w - 2, 6)), _def.accent_color)   # knob panel
	for i in 3:
		var k := r.position + Vector2(2 + i * 4, 2)
		draw_rect(Rect2(k, Vector2(2, 2)), Color("1a1a1e"))
		draw_rect(Rect2(k, Vector2.ONE), Color("d8d8e0"))
	draw_rect(Rect2(r.position + Vector2(w / 2 - 1, 8), Vector2(2, 1)),
			_def.led_color if lit else Color("3a2228"))                        # LED
	draw_rect(Rect2(r.position + Vector2(2, 10), Vector2(w - 4, 1)), _def.label_color)  # brand stripe
	draw_rect(Rect2(r.position + Vector2(3, h - 5), Vector2(w - 6, 4)), Color("9a9aa4"))  # footswitch
	draw_rect(Rect2(r.position + Vector2(3, h - 5), Vector2(w - 6, 1)), Color("dcdce4"))
	for side in [-1, 1]:                                                       # jacks
		draw_rect(Rect2(Vector2(side * (w / 2 + 1) - 1, -h * 0.55 - 1), Vector2(2, 2)), Color("3a3a44"))
