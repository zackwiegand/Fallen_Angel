class_name PedalDef
extends Resource
## One kind of effect pedal: its look (names, colours for UI / placeholder art), its sound (an
## AudioEffect for the `Pedals` bus) and its gameplay rule (how it transforms a SpellCast for the
## pedals after it). Subclass it per pedal and register it in PedalRegistry.

@export var id: StringName
@export var brand := ""                  # parody brand printed on the pedal
@export var model := ""                  # model name / number
@export var body_color := Color.WHITE
@export var accent_color := Color.BLACK  # knob panel / graphics
@export var label_color := Color.BLACK   # printed text
@export var led_color := Color("ff2a2a")
@export_multiline var rule := ""         # one-line gameplay rule for the menu


func display_name() -> String:
	return "%s %s" % [brand, model]


## A fresh effect for the Pedals bus (the bus keeps one per pedal, in chain order).
func make_audio_effect() -> AudioEffect:
	return null


## Changes `cast` in place; called in chain order, so a pedal sees what earlier pedals did.
func transform(_cast: SpellCast) -> void:
	pass
