class_name Sfx
extends Node
## Plays the synthesized effects: animation events (RockerRig.anim_event), spell events and notes.
## Streams are synthesized once and shared by every character.

const SOUNDS := {
	# event: [volume_db, pitch_jitter]
	&"step": [-9.0, 0.08],
	&"swing": [-4.0, 0.05],
	&"strum": [-3.0, 0.0],
	&"cast_release": [-3.0, 0.05],
	&"explode": [-3.0, 0.08],
	&"zap": [-6.0, 0.12],
	&"hit": [-4.0, 0.1],
	&"charge_tick": [-12.0, 0.0],
	&"echo_ping": [-16.0, 0.04],
	&"pickup": [-6.0, 0.0],
}

## Playable instruments for the note keys: [name, volume offset dB]. Index is stored with every
## recorded note, so loops keep the instrument they were played with.
const INSTRUMENTS := [["Lead guitar", 0.0], ["Chip synth", 0.0]]

static var _streams := {}     # event -> Array[AudioStreamWAV] (variants)
static var _notes := []       # [instrument][note] -> AudioStreamWAV

## Base volume of notes from this Sfx (the looper's own Sfx plays a little lower).
var note_volume_db := -6.0
## Events that are the guitar itself, so they play on `instrument_bus` (through the pedals) with the notes.
const INSTRUMENT_EVENTS: Array[StringName] = [&"strum"]

## Audio bus for the sound effects (steps, swing, spells, hits...). Set before _ready.
var bus := &"Master"
## Audio bus for the instrument: notes + INSTRUMENT_EVENTS (the player's goes through the Pedals bus).
var instrument_bus := &"Master"

var _players := {}
var _note_players := {}      # Vector3i(instrument, note, octave) -> player; one each so notes ring over each other
var _hum: AudioStreamPlayer


func _ready() -> void:
	if _streams.is_empty():
		_streams[&"step"] = [SfxSynth.footstep(1), SfxSynth.footstep(2), SfxSynth.footstep(3), SfxSynth.footstep(4)]
		_streams[&"swing"] = [SfxSynth.swing()]
		_streams[&"strum"] = [SfxSynth.strum()]
		_streams[&"cast_release"] = [SfxSynth.fireball()]
		_streams[&"explode"] = [SfxSynth.explosion()]
		_streams[&"zap"] = [SfxSynth.zap()]
		_streams[&"hit"] = [SfxSynth.hit()]
		_streams[&"charge_tick"] = [SfxSynth.charge_tick()]
		_streams[&"hum"] = [SfxSynth.charge_hum()]
		_streams[&"echo_ping"] = [SfxSynth.echo_ping()]
		_streams[&"pickup"] = [SfxSynth.pickup()]
		var lead := []
		var chip := []
		for f: float in Spellbook.NOTE_FREQS:
			lead.append(SfxSynth.note(f))
			chip.append(SfxSynth.chip(f))
		_notes = [lead, chip]
	for event: StringName in SOUNDS:
		var p := AudioStreamPlayer.new()
		p.volume_db = SOUNDS[event][0]
		p.stream = _streams[event][0]
		p.max_polyphony = 4
		p.bus = instrument_bus if event in INSTRUMENT_EVENTS else bus
		add_child(p)
		_players[event] = p
	for inst in INSTRUMENTS.size():
		for i in _notes[inst].size():
			_note_player(inst, i, 0)
	_hum = AudioStreamPlayer.new()
	_hum.stream = _streams[&"hum"][0]
	_hum.bus = bus
	add_child(_hum)


func play(event: StringName) -> void:
	if not _players.has(event):
		return
	var p: AudioStreamPlayer = _players[event]
	p.stream = _streams[event].pick_random()
	if SOUNDS[event][1] > 0.0:
		p.pitch_scale = 1.0 + randf_range(-1.0, 1.0) * SOUNDS[event][1]
	p.play()


## Charging hum: louder and higher with more charges; stops at 0. A rising tick marks each new charge.
func set_charge(charges: int, previous: int) -> void:
	if charges <= 0:
		_hum.stop()
		return
	var l := minf(charges / 12.0, 1.0)
	_hum.volume_db = lerpf(-26.0, -11.0, l)
	_hum.pitch_scale = 0.85 + 0.025 * mini(charges, 20)
	if not _hum.playing:
		_hum.play()
	if charges > previous:
		var p: AudioStreamPlayer = _players[&"charge_tick"]
		p.pitch_scale = 1.0 + 0.06 * mini(charges, 20)
		p.play()


## octave shifts the pitch by whole octaves (-2..+2); it's a playback-rate change, so the note's
## length scales with it too (lower = longer), which suits the crunchy synth sounds.
func play_note(index: int, instrument := 0, octave := 0) -> void:
	_note_player(instrument, index, octave).play()


func _note_player(instrument: int, index: int, octave: int) -> AudioStreamPlayer:
	var key := Vector3i(instrument, index, octave)
	if not _note_players.has(key):
		var p := AudioStreamPlayer.new()
		p.stream = _notes[instrument][index]
		p.volume_db = note_volume_db + INSTRUMENTS[instrument][1]
		p.pitch_scale = pow(2.0, octave)
		p.max_polyphony = 2
		p.bus = instrument_bus
		add_child(p)
		_note_players[key] = p
	return _note_players[key]
