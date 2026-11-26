class_name FloatText
extends Node2D
## Pixel text that pops up, rises and disappears (damage numbers, note glyphs).

const LIFE := 0.75

var text := ""
var color := Color.WHITE
var rise := 16.0
var _age := 0.0


static func spawn(parent: Node, pos: Vector2, txt: String, col: Color, rise_px := 16.0) -> FloatText:
	var f := FloatText.new()
	f.text = txt
	f.color = col
	f.rise = rise_px
	f.position = pos
	f.z_index = 20
	parent.add_child(f)
	return f


func _process(delta: float) -> void:
	_age += delta
	if _age >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var u := _age / LIFE
	var y := -rise * (1.0 - pow(1.0 - u, 3.0))            # ease-out rise
	var c := color
	if u > 0.7:
		c.a = 1.0 - (u - 0.7) / 0.3
	PixelFont.draw(self, Vector2(-PixelFont.width(text) / 2.0, y), text, c)
