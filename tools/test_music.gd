extends SceneTree
## Headless check of the background music: in key, loops cleanly, sits under the notes, plays in-game.
##   godot --headless --path . -s tools/test_music.gd
var fails: Array[String] = []

func check(label: String, ok: bool) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails.append(label)

func _initialize() -> void:
	_run.call_deferred()

func _pc(f: float) -> int:
	return posmod(int(round(12.0 * log(f / 440.0) / log(2.0))) + 9, 12)   # pitch class, C = 0

func _rms(w: AudioStreamWAV, from_s: float, to_s: float) -> float:
	var sum := 0.0
	var count := 0
	for i in range(int(from_s * w.mix_rate), mini(int(to_s * w.mix_rate), w.data.size() / 2)):
		var v := w.data.decode_s16(i * 2) / 32767.0
		sum += v * v
		count += 1
	return sqrt(sum / count)

func _run() -> void:
	create_timer(60.0).timeout.connect(func(): print("FAIL watchdog: test hung"); quit(99))
	var e_minor := [4, 6, 7, 9, 11, 0, 2]                 # E F# G A B C D
	var ok := true
	for ch in SfxSynth.MUSIC_CHORDS:
		for f: float in ch[1] + [ch[2]]:
			ok = ok and _pc(f) in e_minor
	check("every chord tone is in E natural minor", ok)
	var t0 := Time.get_ticks_msec()
	var w := SfxSynth.music_loop()
	print("synth %d ms, %.2f s loop" % [Time.get_ticks_msec() - t0, w.get_length()])
	check("loop is 4 bars at 100 BPM", absf(w.get_length() - 9.6) < 0.01)
	var last := w.data.decode_s16(w.data.size() - 2)
	var first := w.data.decode_s16(0)
	var max_step := 0
	for i in range(2, w.data.size(), 2):
		max_step = maxi(max_step, absi(w.data.decode_s16(i) - w.data.decode_s16(i - 2)))
	check("seamless loop (wrap jump %d vs max step %d)" % [absi(last - first), max_step], absi(last - first) <= max_step)
	# drums land on the grid: the kick on beat 1 of bar 2 is clearly louder than the next 16th
	var step := 2.4 / 16.0
	var on_kick := _rms(w, 2.4, 2.4 + 0.04)
	var off_step := _rms(w, 2.4 + step, 2.4 + step + 0.04)
	check("kick lands on the beat (%.2f vs off-step %.2f)" % [on_kick, off_step], on_kick > off_step * 1.4)   # off-step still has the kick tail + pad
	var note := SfxSynth.note(Spellbook.NOTE_FREQS[3])
	var music_db := linear_to_db(_rms(w, 0.0, 9.6)) + Music.VOLUME_DB
	var note_db := linear_to_db(_rms(note, 0.0, 0.4)) - 6.0
	print("music %.1f dB, note %.1f dB (first 0.4 s)" % [music_db, note_db])
	check("music sits under the notes (VOLUME_DB is a taste setting; just keep it below them)", music_db < note_db and music_db > note_db - 16.0)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(4.0).timeout
	check("music playing in game (chord %s)" % main.music.current_chord(), main.music.player.playing)
	# tap tempo -> the track is rebuilt at the new tempo and keeps its place
	var ph: float = main.music.phase()
	main.sequencer.set_bpm(125)
	await create_timer(1.5).timeout
	var len: float = main.music.player.stream.get_length()
	check("music rebuilt at 125 BPM (loop %.2f s)" % len, absf(len - 4 * 4 * 60.0 / 125.0) < 0.01 and main.music.player.playing)
	check("looper follows the track's phase (seq %.2f, music %.2f)" % [main.sequencer.phase(), main.music.phase()], absf(main.sequencer.phase() - main.music.phase()) < 0.03)
	print("FAILURES: ", fails.size())
	quit(fails.size())
