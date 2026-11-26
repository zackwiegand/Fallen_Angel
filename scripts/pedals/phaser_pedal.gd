class_name PhaserPedal
extends PedalDef
## Skyman Phaser-R. Sound: slow swirling phaser. Gameplay: spells pierce (pass through enemies)
## and shimmer purple. Placed after a delay it phases the delay's echoes too: each echo leaves as
## its own piercing ghost cast along the same path, instead of an extra hit on the target.


func _init() -> void:
	id = &"skyman_phaser"
	brand = "SKYMAN"
	model = "PHASER-R"
	body_color = Color("6a3ab8")
	accent_color = Color("c9a8ff")
	label_color = Color("f4ecff")
	led_color = Color("ff4ad8")
	rule = "Spells pierce through enemies."


func make_audio_effect() -> AudioEffect:
	var fx := AudioEffectPhaser.new()
	fx.range_min_hz = 300.0
	fx.range_max_hz = 2600.0
	fx.rate_hz = 0.6
	fx.feedback = 0.75
	fx.depth = 1.0
	return fx


func transform(cast: SpellCast) -> void:
	cast.pierce = true
	cast.phased = true
	if cast.echoes > 0:              # delay earlier in the chain: its repeats become ghost casts
		cast.ghosts += cast.echoes
		cast.ghost_delay = cast.echo_delay
		cast.echoes = 0
