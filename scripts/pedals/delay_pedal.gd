class_name DelayPedal
extends PedalDef
## CHIEF CD-3 Digital Delay. Sound: clean digital repeats, each about half as loud.
## Gameplay: every target the spell hits takes ECHOES extra hits, each half the last, ECHO_TIME apart
## (in time with the audio repeats). A Phaser after it turns those echoes into ghost casts instead.

const ECHO_TIME := 0.3          # seconds; also the audio repeat time
const ECHOES := 3
const FEEDBACK_DB := -6.0       # each audio repeat half the amplitude of the last, like the damage


func _init() -> void:
	id = &"chief_delay"
	brand = "CHIEF"
	model = "CD-3"
	body_color = Color("f2f0ea")
	accent_color = Color("1f5fd0")
	label_color = Color("16161c")
	rule = "Spell hits echo 3x, each half the damage."


func make_audio_effect() -> AudioEffect:
	var fx := AudioEffectDelay.new()
	fx.dry = 1.0
	fx.tap1_active = false
	fx.tap2_active = false
	fx.feedback_active = true
	fx.feedback_delay_ms = ECHO_TIME * 1000.0
	fx.feedback_level_db = FEEDBACK_DB
	fx.feedback_lowpass = 9000.0
	return fx


func transform(cast: SpellCast) -> void:
	cast.echoes += ECHOES
	cast.echo_delay = ECHO_TIME
