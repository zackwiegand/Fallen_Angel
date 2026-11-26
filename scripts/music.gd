class_name Music
extends Node
## Background chord loop (SfxSynth.music_loop): Em - C - G - D, in key with the note keys.
## Synthesized on a worker thread so the game never stalls; re-synthesized when the tempo changes
## (tap tempo), swapping in at the same point in the bar so it keeps time. Loops are cached per BPM.
## Sits a little under the notes since it plays continuously.

const VOLUME_DB := 2.0              # music only (dB): higher = louder. 0 = ~4 dB under a note, +4 = about equal

static var _cache := {}             # bpm (int) -> AudioStreamWAV

var player: AudioStreamPlayer
var muted := false
var bpm := int(SfxSynth.MUSIC_BPM)  # tempo of the loop currently playing / being built

var _task := -1
var _pending := false               # tempo changed again while a loop was still being built


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = VOLUME_DB
	add_child(player)
	_request()


## Change tempo; the new loop starts at the same phase as the old one once it's built.
func set_bpm(new_bpm: int) -> void:
	if new_bpm == bpm:
		return
	bpm = new_bpm
	_request()


func _request() -> void:
	if _cache.has(bpm):
		_swap(_cache[bpm])
		return
	if _task >= 0:
		_pending = true
		return
	_task = WorkerThreadPool.add_task(_synth.bind(bpm))


func _synth(b: int) -> void:
	_built.call_deferred(SfxSynth.music_loop(float(b)), b)


func _built(s: AudioStreamWAV, b: int) -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	_cache[b] = s
	if b == bpm:
		_swap(s)
	if _pending:
		_pending = false
		_request()


func _swap(s: AudioStreamWAV) -> void:
	var at := phase()
	player.stream = s
	if not muted:
		player.play(at * s.get_length())


## Position in the 4-bar loop, 0..1 (0 when not playing).
func phase() -> float:
	if not player.playing or player.stream == null:
		return 0.0
	return player.get_playback_position() / player.stream.get_length()


## Mute / unmute. On unmute, start at `at_phase` (the looper's position) so they stay together.
func toggle(at_phase := 0.0) -> void:
	muted = not muted
	if muted:
		player.stop()
	elif player.stream:
		player.play(at_phase * player.stream.get_length())


## Chord playing right now ("Em", "C", "G", "D"), for anything that wants to follow the harmony.
func current_chord() -> String:
	if not player.playing:
		return ""
	var i := int(phase() * SfxSynth.MUSIC_CHORDS.size()) % SfxSynth.MUSIC_CHORDS.size()
	return SfxSynth.MUSIC_CHORDS[i][0]


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
