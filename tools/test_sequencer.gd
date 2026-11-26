extends SceneTree
## Headless step-sequencer test with a hand-driven clock (no music): step entry, chords, rests,
## length = steps entered, 64 max, loop playback order, instrument/octave kept, stop/clear, tap tempo.
##   godot --headless --path . -s tools/test_sequencer.gd
var fails: Array[String] = []
var seq: Sequencer
var played := []           # [index, [[note, instrument, octave], ...]]

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): print("FAIL watchdog: test hung"); quit(99))
	_run.call_deferred()

var _t := 0.0
func advance(sixteenths: float) -> void:
	var end := _t + sixteenths * seq.step_len()
	while _t < end - 1e-6:
		var dt := minf(0.01, end - _t)
		seq._process(dt)
		_t += dt

func _run() -> void:
	seq = Sequencer.new()
	root.add_child(seq)
	seq.set_process(false)
	seq.step_played.connect(func(i, notes): played.append([i, notes.duplicate(true)]))
	seq._process(0.0)

	check("starts idle and empty", seq.state == Sequencer.State.IDLE and seq.length() == 0)
	seq.toggle_record()
	check("Z -> recording", seq.state == Sequencer.State.RECORDING)
	seq.record(0, 0, 0, 1.0)                 # step 0: E
	seq.record(2, 0, 0, 1.5)                 # step 1: A
	seq.add_rest()                           # step 2: rest
	seq.record(0, 1, 0, 2.0)                 # step 3: Em triad, pressed together (chip synth)
	seq.record(1, 1, 0, 2.02)
	seq.record(3, 1, 0, 2.05)
	seq.record(7, 0, 1, 2.5)                 # step 4: high A, an octave up
	check("5 steps entered (got %d)" % seq.length(), seq.length() == 5)
	check("rest is an empty step", seq.steps[2].is_empty())
	check("notes pressed together form a chord step", seq.steps[3] == [[0, 1, 0], [1, 1, 0], [3, 1, 0]])
	check("octave + instrument kept", seq.steps[4] == [[7, 0, 1]])
	advance(8)
	check("nothing plays while recording", played.is_empty())
	seq.toggle_record()
	check("Z again -> stops recording and plays", seq.state == Sequencer.State.PLAYING)
	advance(12.05)
	var order := played.map(func(p): return p[0])
	check("loops at 5 steps, rest silent (got %s)" % [order], order == [0, 1, 3, 4, 0, 1, 3, 4, 0, 1])
	check("chord plays together", played[2][1].size() == 3)

	seq.toggle_play()
	played.clear()
	advance(8)
	check("X stops", seq.state == Sequencer.State.IDLE and played.is_empty())
	seq.toggle_play()
	advance(1.05)
	check("X plays again from step 0", seq.state == Sequencer.State.PLAYING and played.size() == 1 and played[0][0] == 0)

	seq.toggle_record()
	check("Z while playing starts a new sequence", seq.state == Sequencer.State.RECORDING and seq.length() == 0)
	for i in 70:
		seq.record(i % 8, 0, 0, 10.0 + i)
	check("stops at 64 steps and plays", seq.length() == 64 and seq.state == Sequencer.State.PLAYING)
	seq.toggle_record()
	seq.toggle_record()
	check("Z, Z with nothing entered -> idle", seq.state == Sequencer.State.IDLE and seq.length() == 0)
	seq.toggle_record(); seq.record(0, 0, 0, 100.0); seq.toggle_record()
	seq.clear()
	check("C clears", seq.length() == 0 and seq.state == Sequencer.State.IDLE)

	# tap tempo
	var bpms := []
	seq.bpm_changed.connect(func(b): bpms.append(b))
	seq.tap(200.0); seq.tap(200.5)
	check("2 taps don't change tempo yet", seq.bpm == 100 and bpms.is_empty())
	seq.tap(201.0)
	check("3 taps at 0.5 s -> 120 BPM (got %d)" % seq.bpm, seq.bpm == 120)
	seq.tap(201.55); seq.tap(202.1); seq.tap(202.65); seq.tap(203.2)
	check("steady 0.55 s taps -> 109 BPM (got %d)" % seq.bpm, seq.bpm == 109)
	seq.tap(210.0); seq.tap(210.4)
	check("2 s pause starts a new count (still %d)" % seq.bpm, seq.bpm == 109 and seq.taps_counted() == 2)
	seq.tap(210.8)
	check("new count: 0.4 s taps -> 150 BPM (got %d)" % seq.bpm, seq.bpm == 150)
	seq.tap(220.0); seq.tap(220.1); seq.tap(220.2)
	check("clamped to 200 BPM max (got %d)" % seq.bpm, seq.bpm == 200)
	var before := seq.current_step()
	seq.set_bpm(140)
	check("tempo change keeps the grid position (%d -> %d)" % [before, seq.current_step()], seq.current_step() == before)
	print("FAILURES: ", fails.size())
	quit(fails.size())
