class_name Spellbook
extends Node
## Turns played notes into spells.
##
## The 8 note keys play E minor pentatonic, low to high, so any run sounds good:
##   Q  W  E  R  A  S  D  F
##   E3 G3 A3 B3 D4 E4 G4 A4      (scale degrees 1..8 = indices 0..7)
##
## Fire: any 3 notes within TRIAD_WINDOW that spell a major/minor triad (any order, octave or
##   inversion). In this scale that's E minor (E G B) or G major (G B D), e.g. Q W R or W R A.
## Lightning: the "skip" pattern, degrees 1 3 2 4 3 5 ... (leap 2, step back 1, repeat), up or down
##   (Q E W R E A ...), and back down again. Four notes = 1 charge, every further note +1. The chain is released when you
##   pause (SKIP_RELEASE) or break the pattern. Each charge is one hit / one bounce.

signal note_played(index: int)
signal cast(spell: StringName, power: int)
## A spell is building up (lightning charges); 0 = released / lost.
signal charge_changed(spell: StringName, charges: int)
signal changed

const NOTE_NAMES := ["E", "G", "A", "B", "D", "E", "G", "A"]
const NOTE_FREQS := [164.81, 196.00, 220.00, 246.94, 293.66, 329.63, 392.00, 440.00]
const PITCH_CLASS := [4, 7, 9, 11, 2, 4, 7, 9]
const TRIADS := [[4, 7, 11], [2, 7, 11]]      # E minor, G major (sorted pitch classes)
const TRIAD_WINDOW := 1.0                     # seconds for all three notes
const SKIP_RELEASE := 1.2                     # pause that releases a lightning chain (max gap between notes)
const MAX_CHARGES := 30

var history: Array[int] = []                  # recent note indices (for the HUD)
var charges := 0

var _times: Array[float] = []
var _run := 0                                 # notes in the current valid skip run
var _last_leap := 0
var _expect_leap := true
var _release_in := 0.0


func play_note(i: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var prev: int = history[-1] if not history.is_empty() else -1
	history.append(i)
	_times.append(now)
	if history.size() > 8:
		history.pop_front()
		_times.pop_front()
	note_played.emit(i)

	if _is_triad():
		_reset_run()
		history.clear()
		_times.clear()
		cast.emit(&"fire", 1)
		changed.emit()
		return
	_advance_skip(prev, i)
	changed.emit()


func _is_triad() -> bool:
	if history.size() < 3 or _times[-1] - _times[-3] > TRIAD_WINDOW:
		return false
	var pcs := [PITCH_CLASS[history[-1]], PITCH_CLASS[history[-2]], PITCH_CLASS[history[-3]]]
	pcs.sort()
	return pcs in TRIADS


## Skip pattern: intervals alternate leap (+-2) and step (+-1, opposite way to the leap before it).
## A leap may go either way, so the run can turn around anywhere after a step. At either end of the
## keys a leap may also bounce straight back (..5 7 5 6..), since another leap that way would run off
## the keyboard. Elsewhere leap-leap breaks the pattern, so Q E Q E spam can't build charges.
func _advance_skip(prev: int, i: int) -> void:
	if prev < 0 or _run == 0:
		_run = 1
		_expect_leap = true
	else:
		var d := i - prev
		var ok := false
		if _expect_leap:
			ok = absi(d) == 2
		elif absi(d) == 1:
			ok = signi(d) == -signi(_last_leap)
		elif absi(d) == 2:                      # leap right after a leap: only as a turnaround at the edge
			var beyond := prev + signi(_last_leap) * 2
			ok = signi(d) == -signi(_last_leap) and (beyond < 0 or beyond >= NOTE_NAMES.size())
		if ok:
			_run += 1
		else:
			_release()                          # pattern broken: fire what was built, start again
			_run = 2 if absi(d) == 2 else 1
		_expect_leap = absi(d) != 2
		if absi(d) == 2:
			_last_leap = d
	_set_charges(clampi(_run - 3, 0, MAX_CHARGES))
	_release_in = SKIP_RELEASE


func _release() -> void:
	if charges > 0:
		cast.emit(&"lightning", charges)
	_set_charges(0)


func _reset_run() -> void:
	_run = 0
	_set_charges(0)


func _set_charges(v: int) -> void:
	if v != charges:
		charges = v
		charge_changed.emit(&"lightning", v)


## Notes in the current skip run (2-3 = pattern recognised but no charge yet). For charge visuals.
func skip_progress() -> int:
	return _run


func _process(delta: float) -> void:
	if _run > 0:
		_release_in -= delta
		if _release_in <= 0.0:
			_release()
			_reset_run()
			changed.emit()


func describe() -> String:
	var names := history.map(func(i: int) -> String: return NOTE_NAMES[i])
	var s := "Notes: " + (" ".join(names) if not names.is_empty() else "-")
	if charges > 0:
		s += "    LIGHTNING x%d" % charges
	return s
