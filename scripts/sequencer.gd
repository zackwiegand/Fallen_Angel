class_name Sequencer
extends Node
## Step sequencer (synth style), clocked in 16th notes at the current tempo:
##   toggle_record(): start step entry (clears the old sequence) / stop and start looping
##   record():        while recording, each note press appends a step; notes pressed within
##                    CHORD_WINDOW of each other land on the same step (chords, e.g. triads)
##   add_rest():      while recording, appends an empty step (Space)
##   toggle_play():   start / stop playback;  clear(): erase
##   tap():           tap tempo - after 3 taps the tempo follows the average interval (60..200 BPM);
##                    a 2 s pause starts a new count.
## The sequence is as long as what was entered (max STEPS) and loops at that length; playback starts
## on the next 16th of the backing track so it stays on the grid. Each note keeps its instrument and
## octave. Playback is sound only (no spells, no hands).

signal changed
signal step_played(step: int, notes: Array)
signal bpm_changed(bpm: int)

enum State { IDLE, RECORDING, PLAYING }

const STEPS := 64               # max sequence length
const GRID := 64                # 16ths per backing-track loop (4 bars)
const CHORD_WINDOW := 0.06      # seconds: presses closer than this share a step
const BPM_RANGE := Vector2i(60, 200)
const TAP_RESET := 2.0          # seconds without a tap before a new tap count starts
const TAP_AVERAGE := 4          # intervals averaged

var state := State.IDLE
var steps: Array = []           # each step: Array of [note, instrument, octave]; empty = rest
var music: Music                # clock source while the backing track plays
var sfx: Sfx
var bpm := int(SfxSynth.MUSIC_BPM)
var play_index := -1            # step currently sounding (-1 = none yet)

var _clock := 0.0               # seconds into the 4-bar grid
var _last_grid := -1
var _tick := 0                  # 16ths elapsed since start (never wraps)
var _start_tick := 0
var _last_note_time := -INF
var _taps: Array[float] = []


func step_len() -> float:
	return 60.0 / bpm / 4.0


func loop_len() -> float:
	return step_len() * GRID


## Position in the backing track's 4-bar loop, 0..1.
func phase() -> float:
	return _clock / loop_len()


## 16th of the backing track's 4-bar loop we're on (0..63).
func current_step() -> int:
	return int(_clock / step_len()) % GRID


func length() -> int:
	return steps.size()


func note_count() -> int:
	var n := 0
	for s in steps:
		n += s.size()
	return n


# ---------------------------------------------------------------- controls
func toggle_record() -> void:
	if state == State.RECORDING:
		_stop_recording()
	else:
		steps.clear()
		play_index = -1
		_last_note_time = -INF
		state = State.RECORDING
	changed.emit()


func _stop_recording() -> void:
	if steps.is_empty():
		state = State.IDLE
	else:
		_start_playing()


func toggle_play() -> void:
	match state:
		State.IDLE:
			if not steps.is_empty():
				_start_playing()
		State.RECORDING:
			_stop_recording()
		State.PLAYING:
			state = State.IDLE
			play_index = -1
	changed.emit()


func _start_playing() -> void:
	state = State.PLAYING
	play_index = -1
	_start_tick = _tick + 1     # begin on the next 16th of the grid


func clear() -> void:
	steps.clear()
	state = State.IDLE
	play_index = -1
	changed.emit()


## A live note. While recording it becomes the next step (or joins the last step if pressed
## together with it). `now` (seconds) is for tests.
func record(note: int, instrument: int, octave := 0, now := -1.0) -> void:
	if state != State.RECORDING:
		return
	if now < 0.0:
		now = Time.get_ticks_usec() / 1e6
	var entry := [note, instrument, octave]
	if not steps.is_empty() and not steps[-1].is_empty() and now - _last_note_time <= CHORD_WINDOW:
		if not entry in steps[-1]:
			steps[-1].append(entry)
	else:
		steps.append([entry])
	_last_note_time = now
	_check_full()
	changed.emit()


## A rest step while recording (Space).
func add_rest() -> void:
	if state != State.RECORDING:
		return
	steps.append([])
	_last_note_time = -INF
	_check_full()
	changed.emit()


func _check_full() -> void:
	if steps.size() >= STEPS:
		_stop_recording()


# ---------------------------------------------------------------- tempo
## Tap tempo. `now` (seconds) is for tests; defaults to the real clock.
func tap(now := -1.0) -> void:
	if now < 0.0:
		now = Time.get_ticks_usec() / 1e6
	if not _taps.is_empty() and now - _taps[-1] > TAP_RESET:
		_taps.clear()
	_taps.append(now)
	if _taps.size() > TAP_AVERAGE + 1:
		_taps.pop_front()
	if _taps.size() >= 3:
		var avg := (_taps[-1] - _taps[0]) / (_taps.size() - 1)
		set_bpm(clampi(roundi(60.0 / avg), BPM_RANGE.x, BPM_RANGE.y))
	changed.emit()


func taps_counted() -> int:
	return _taps.size()


## New tempo, keeping the current place in the grid.
func set_bpm(new_bpm: int) -> void:
	if new_bpm == bpm:
		return
	var at := phase()
	bpm = new_bpm
	_clock = at * loop_len()
	bpm_changed.emit(bpm)
	changed.emit()


# ---------------------------------------------------------------- clock
func _process(delta: float) -> void:
	if music and music.player.playing:
		_clock = music.phase() * loop_len()      # follow the track by phase (also mid tempo change)
	else:
		_clock = fmod(_clock + delta, loop_len())
	var cur := current_step()
	if _last_grid < 0:
		_last_grid = cur
		return
	while _last_grid != cur:                     # every 16th passed, even after a hitch
		_last_grid = (_last_grid + 1) % GRID
		_tick += 1
		_on_tick()


func _on_tick() -> void:
	if state != State.PLAYING or steps.is_empty() or _tick < _start_tick:
		return
	play_index = (_tick - _start_tick) % steps.size()
	var notes: Array = steps[play_index]
	for n: Array in notes:
		if sfx:
			sfx.play_note(n[0], n[1], n[2])
	if not notes.is_empty():
		step_played.emit(play_index, notes)
