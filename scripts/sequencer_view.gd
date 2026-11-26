class_name SequencerView
extends Control
## Piano-roll strip for the step Sequencer: up to 64 steps across, the 8 note keys up the side
## (Q at the bottom, F at the top). Steps in the sequence get a lit column (rests included), notes
## are coloured by instrument and tinted by octave, the playhead marks the sounding step, and while
## recording a red cursor marks where the next step goes.

const CELL := Vector2(14, 11)
const ROWS := 8
const INSTRUMENT_COLORS := [Color("ff9a3a"), Color("4ad8ff")]
const KEYS := ["Q", "W", "E", "R", "A", "S", "D", "F"]
const REC := Color("ff4a4a")

var sequencer: Sequencer


func _ready() -> void:
	custom_minimum_size = Vector2(Sequencer.STEPS * CELL.x + 40, ROWS * CELL.y + 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sequencer == null:
		return
	var font := get_theme_default_font()
	var origin := Vector2(26, 26)
	var grid := Vector2(Sequencer.STEPS * CELL.x, ROWS * CELL.y)
	var n := sequencer.length()
	draw_rect(Rect2(Vector2.ZERO, custom_minimum_size), Color(0.05, 0.03, 0.06, 0.85))
	draw_rect(Rect2(origin - Vector2(2, 2), grid + Vector2(4, 4)), Color(0, 0, 0, 0.7))
	# the sequence's own steps (rests included) are lit; beyond the end stays dark
	if n > 0:
		draw_rect(Rect2(origin, Vector2(n * CELL.x, grid.y)), Color(1, 1, 1, 0.05))
	for s in Sequencer.STEPS + 1:
		if s % 4 == 0:
			var shade := 0.16 if s % 16 == 0 else 0.08
			draw_rect(Rect2(origin + Vector2(s * CELL.x, 0), Vector2(1, grid.y)), Color(1, 1, 1, shade))
	for r in ROWS:
		draw_string(font, origin + Vector2(-18, (ROWS - r) * CELL.y - 1.5), KEYS[r], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.55))
	if n > 0:
		draw_rect(Rect2(origin + Vector2(n * CELL.x - 1, -2), Vector2(2, grid.y + 4)), Color(1, 1, 1, 0.5))   # loop end
	# playhead / record cursor
	var head := sequencer.play_index
	if sequencer.state == Sequencer.State.PLAYING and head >= 0:
		draw_rect(Rect2(origin + Vector2(head * CELL.x, 0), Vector2(CELL.x, grid.y)), Color(1, 1, 1, 0.14))
	if sequencer.state == Sequencer.State.RECORDING and n < Sequencer.STEPS:
		var blink := 0.35 + 0.35 * float(Time.get_ticks_msec() / 250 % 2)
		draw_rect(Rect2(origin + Vector2(n * CELL.x, 0), Vector2(CELL.x, grid.y)), Color(REC, blink))
	# notes
	for s in n:
		for note: Array in sequencer.steps[s]:
			var r := Rect2(origin + Vector2(s * CELL.x + 1, (ROWS - 1 - note[0]) * CELL.y + 1), CELL - Vector2(2, 2))
			var c: Color = INSTRUMENT_COLORS[note[1] % INSTRUMENT_COLORS.size()]
			c = c.lightened(0.3 * note[2]) if note[2] > 0 else c.darkened(-0.25 * note[2])   # octave
			if s == head and sequencer.state == Sequencer.State.PLAYING:
				c = c.lightened(0.5)
			draw_rect(r, c)
	# label
	var label := "SEQ  empty"
	var col := Color(1, 1, 1, 0.6)
	match sequencer.state:
		Sequencer.State.RECORDING:
			label = "● REC  step %d/%d" % [n + 1, Sequencer.STEPS]
			col = REC
			draw_rect(Rect2(origin - Vector2(3, 3), grid + Vector2(6, 6)), col, false, 1.0)
		Sequencer.State.PLAYING:
			label = "▶ PLAYING  %d steps" % n
			col = Color("8ae05a")
		Sequencer.State.IDLE:
			if n > 0:
				label = "■ STOPPED  %d steps" % n
	var tempo := "%d BPM" % sequencer.bpm
	if sequencer.taps_counted() > 0 and sequencer.taps_counted() < 3:
		tempo += " (tap %d…)" % sequencer.taps_counted()
	draw_string(font, origin + Vector2(0, -8), label + "      " + tempo
			+ "      Z rec on/off   Space rest   X play/stop   C clear   V instrument   [ ] octave   T tap tempo",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
