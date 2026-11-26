class_name PixelFont
## Tiny 3x5 bitmap digits (+ a music-note glyph "n") drawn as 1px rects with a dark outline,
## so text stays on the game's pixel grid.

const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"], "3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"], "7": ["111", "001", "010", "010", "010"],
	"8": ["111", "101", "111", "101", "111"], "9": ["111", "101", "111", "001", "111"],
	"n": ["0110", "0101", "0100", "1100", "1100"],
}
const OUTLINE := Color("080408")


static func width(text: String) -> int:
	var w := 0
	for ch in text:
		w += GLYPHS.get(ch, GLYPHS["0"])[0].length() + 1
	return w - 1


## Draws text with its top-left at pos (rounded to whole pixels).
static func draw(ci: CanvasItem, pos: Vector2, text: String, color: Color) -> void:
	var origin := pos.round()
	for pass_i in 2:
		var x := 0
		for ch in text:
			var g: Array = GLYPHS.get(ch, GLYPHS["0"])
			for row in g.size():
				var line: String = g[row]
				for col in line.length():
					if line[col] != "1":
						continue
					var p := origin + Vector2(x + col, row)
					if pass_i == 0:
						ci.draw_rect(Rect2(p - Vector2.ONE, Vector2(3, 3)), OUTLINE)
					else:
						ci.draw_rect(Rect2(p, Vector2.ONE), color)
			x += g[0].length() + 1
