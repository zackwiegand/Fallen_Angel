class_name PedalboardMenu
extends Control
## Pedalboard screen (Tab): pauses the game and shows the chain in signal order, guitar on the left
## to amp on the right. Left/Right move the cursor, Enter picks a pedal up / drops it (Left/Right
## while holding = reorder), B or Space footswitches it (bypass), Tab / Esc closes.
## Drawn in game pixels (PixelFont, 1 game px = `pixel_scale` window px) so it matches the world art.
## The pedals are real PedalView nodes, so the menu shows whatever art the pedals have.

const PANEL_W := 320             # game px (narrower windows shrink it)
const PANEL_H := 156
const CARD := Vector2(36, 42)
const CARD_GAP := 14
const ROW_Y := 26                # card top, from the panel top
const TEXT := Color(0.85, 0.8, 0.75)
const DIM := Color("7a6e6a")
const CURSOR := Color("ffd84a")
const ON := Color("8ae05a")
const OFF := Color("ff5a4a")
const BG := Color("141018")
const EDGE := Color("6a5a50")

var pedalboard: Pedalboard
var pixel_scale := 4

var cursor := 0
var holding := false
var _views: Array[PedalView] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	pedalboard.chain_changed.connect(_sync_views)


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	holding = false
	cursor = clampi(cursor, 0, maxi(pedalboard.chain.size() - 1, 0))
	get_tree().paused = true
	_sync_views()


func close() -> void:
	visible = false
	holding = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("pedal_menu"):
			open()
			get_viewport().set_input_as_handled()
		return
	var n := pedalboard.chain.size()
	if event.is_action_pressed("pedal_menu") or event.is_action_pressed("ui_cancel"):
		close()
	elif n > 0 and (event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true)):
		var to := clampi(cursor + (1 if event.is_action_pressed("ui_right", true) else -1), 0, n - 1)
		if holding:
			pedalboard.move(cursor, to)
		cursor = to
	elif n > 0 and event.is_action_pressed("pedal_bypass"):      # before ui_accept: Space is both
		pedalboard.toggle_bypass(pedalboard.chain[cursor])
	elif n > 0 and event.is_action_pressed("ui_accept"):
		holding = not holding
	else:
		return
	get_viewport().set_input_as_handled()
	_sync_views()


func _panel() -> Rect2:
	var view := size / pixel_scale
	var w := minf(PANEL_W, view.x - 8)
	return Rect2(((view - Vector2(w, PANEL_H)) / 2.0).floor(), Vector2(w, PANEL_H))


func _card_rect(i: int) -> Rect2:
	var p := _panel()
	var n := pedalboard.chain.size()
	var row_w := n * CARD.x + (n - 1) * CARD_GAP
	var x0 := p.position.x + floorf((p.size.x - row_w) / 2.0)
	var lift := -5 if holding and i == cursor else 0
	return Rect2(Vector2(x0 + i * (CARD.x + CARD_GAP), p.position.y + ROW_Y + lift), CARD)


func _sync_views() -> void:
	var chain := pedalboard.chain
	while _views.size() < chain.size():
		var v := PedalView.new()
		add_child(v)
		_views.append(v)
	while _views.size() > chain.size():
		_views.pop_back().queue_free()
	for i in chain.size():
		var v := _views[i]
		v.setup(chain[i])
		v.lit = not pedalboard.is_bypassed(chain[i])
		v.facing = Vector2(0, -1)
		var r := _card_rect(i)
		v.position = (r.position + Vector2(r.size.x / 2.0, r.size.y - 13)) * pixel_scale
		v.scale = Vector2.ONE * pixel_scale
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * pixel_scale)
	var p := _panel()
	draw_rect(p.grow(2), Color("08060a"))
	draw_rect(p.grow(1), EDGE)
	draw_rect(p, BG)
	var x := p.position.x + 6
	_text(Vector2(x, p.position.y + 5), "PEDALBOARD", CURSOR)
	_text_right(Vector2(p.end.x - 6, p.position.y + 5), "TAB CLOSE", DIM)
	var chain := pedalboard.chain
	if chain.is_empty():
		_text_center(Vector2(p.get_center().x, p.position.y + 50), "NO PEDALS YET", TEXT)
		_text_center(Vector2(p.get_center().x, p.position.y + 60), "FIND THEM ON THE FLOOR", DIM)
		return
	# signal flow: GUITAR > card > card > AMP, cables between
	var mid_y := p.position.y + ROW_Y + 18
	var first := _card_rect(0)
	var last := _card_rect(chain.size() - 1)
	_text_right(Vector2(first.position.x - 6, mid_y - 2), "GTR", DIM)
	_text(Vector2(last.end.x + 6, mid_y - 2), "AMP", DIM)
	_cable(Vector2(first.position.x - 5, mid_y), Vector2(first.position.x, mid_y))
	_cable(Vector2(last.end.x, mid_y), Vector2(last.end.x + 5, mid_y))
	for i in chain.size():
		var r := _card_rect(i)
		var def := PedalRegistry.get_def(chain[i])
		var on := not pedalboard.is_bypassed(chain[i])
		if i + 1 < chain.size():
			_cable(Vector2(r.end.x, mid_y), Vector2(_card_rect(i + 1).position.x, mid_y))
		var edge := CURSOR if i == cursor else Color("4a3e48")
		draw_rect(r.grow(1), edge)
		draw_rect(r, Color("201a24") if on else Color("161218"))
		_text_center(Vector2(r.get_center().x, r.position.y + 2), str(i + 1), DIM)
		_text_center(Vector2(r.get_center().x, r.end.y + 4), def.brand, TEXT if on else DIM)
		_text_center(Vector2(r.get_center().x, r.end.y + 11), def.model, TEXT if on else DIM)
		_text_center(Vector2(r.get_center().x, r.end.y + 18), "ON" if on else "OFF", ON if on else OFF)
	# what this order does
	var y := p.position.y + ROW_Y + CARD.y + 32
	var sel := PedalRegistry.get_def(chain[cursor])
	for line in _wrap(sel.display_name() + ": " + sel.rule, p.size.x - 12):
		_text(Vector2(x, y), line, CURSOR)
		y += 8
	y += 2
	for desc in pedalboard.describe():
		for line in _wrap(desc, p.size.x - 12):
			_text(Vector2(x, y), line, TEXT)
			y += 8
	var hint := "< > MOVE PEDAL   ENTER DROP" if holding else "< > SELECT   ENTER PICK UP   B/SPACE ON-OFF"
	_text(Vector2(x, p.end.y - 9), hint, DIM)


func _cable(a: Vector2, b: Vector2) -> void:
	var mid := (a + b) / 2.0 + Vector2(0, 2)
	draw_polyline(PackedVector2Array([a, mid, b]), Color("08060a"), 1.0)


func _text(pos: Vector2, s: String, c: Color) -> void:
	PixelFont.draw(self, pos, s.to_upper(), c)


func _text_right(pos: Vector2, s: String, c: Color) -> void:
	_text(pos - Vector2(PixelFont.width(s.to_upper()), 0), s, c)


func _text_center(pos: Vector2, s: String, c: Color) -> void:
	_text(pos - Vector2(floorf(PixelFont.width(s.to_upper()) / 2.0), 0), s, c)


## Greedy word wrap to `max_px` game px of PixelFont text.
func _wrap(s: String, max_px: float) -> PackedStringArray:
	var out := PackedStringArray()
	var line := ""
	for word in s.to_upper().split(" ", false):
		var trial := word if line.is_empty() else line + " " + word
		if PixelFont.width(trial) > max_px and not line.is_empty():
			out.append(line)
			line = word
		else:
			line = trial
	if not line.is_empty():
		out.append(line)
	return out
