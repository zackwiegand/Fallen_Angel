class_name Pedalboard
extends Node
## The player's effect chain: collected pedals in signal order (guitar -> chain[0] -> ... -> amp),
## each on or bypassed. The order drives three things at once:
## - sound: the `Pedals` audio bus holds one effect per pedal in the same order (bypass = disabled);
## - spells: apply() runs a SpellCast through the active pedals in order, so a pedal changes the
##   cast for the pedals after it (Phaser -> Delay != Delay -> Phaser);
## - visuals: PedalTrail floats them after the player in this order.

signal chain_changed
signal pedal_added(id: StringName, from_position: Vector2)

const BUS := &"Pedals"

var chain: Array[StringName] = []
var _bypassed := {}              # id -> true


func _ready() -> void:
	ensure_bus()
	_rebuild_bus()


## Index of the Pedals bus, created (feeding Master) the first time.
static func ensure_bus() -> int:
	var i := AudioServer.get_bus_index(BUS)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, &"Master")
	return i


func has_pedal(id: StringName) -> bool:
	return id in chain


## Appends a pedal to the end of the chain (just before the amp). `from_position` = where it was
## picked up, so the trail can fly it in from there.
func add_pedal(id: StringName, from_position := Vector2.INF) -> bool:
	if has_pedal(id):
		return false
	chain.append(id)
	_rebuild_bus()
	pedal_added.emit(id, from_position)
	chain_changed.emit()
	return true


func move(from: int, to: int) -> void:
	to = clampi(to, 0, chain.size() - 1)
	if from == to or from < 0 or from >= chain.size():
		return
	var id := chain[from]
	chain.remove_at(from)
	chain.insert(to, id)
	_rebuild_bus()
	chain_changed.emit()


func is_bypassed(id: StringName) -> bool:
	return _bypassed.has(id)


func set_bypassed(id: StringName, off: bool) -> void:
	if off:
		_bypassed[id] = true
	else:
		_bypassed.erase(id)
	var bus := ensure_bus()
	var i := chain.find(id)
	if i >= 0 and i < AudioServer.get_bus_effect_count(bus):
		AudioServer.set_bus_effect_enabled(bus, i, not off)
	chain_changed.emit()


func toggle_bypass(id: StringName) -> void:
	set_bypassed(id, not is_bypassed(id))


## Pedals that are switched on, in signal order.
func active_defs() -> Array[PedalDef]:
	var out: Array[PedalDef] = []
	for id in chain:
		if not is_bypassed(id):
			out.append(PedalRegistry.get_def(id))
	return out


## Runs `cast` through the active pedals in order and returns it (transformed in place).
func apply(cast: SpellCast) -> SpellCast:
	for def in active_defs():
		def.transform(cast)
		cast.touched_by.append(def.id)
	return cast


## What the current chain does to each spell, for the menu.
func describe() -> PackedStringArray:
	var out := PackedStringArray()
	out.append(apply(SpellCast.fire(Vector2.ZERO, 0.0, Vector2.DOWN, null, null)).describe())
	out.append(apply(SpellCast.lightning(1, Vector2.ZERO, Vector2.DOWN, null, null)).describe())
	return out


## Short HUD summary, e.g. "CHIEF CD-3 > SKYMAN PHASER-R (off)".
func summary() -> String:
	if chain.is_empty():
		return "none"
	var parts: Array[String] = []
	for id in chain:
		parts.append(PedalRegistry.get_def(id).display_name() + (" (off)" if is_bypassed(id) else ""))
	return " > ".join(parts)


func _rebuild_bus() -> void:
	var bus := ensure_bus()
	while AudioServer.get_bus_effect_count(bus) > 0:
		AudioServer.remove_bus_effect(bus, 0)
	for id in chain:
		AudioServer.add_bus_effect(bus, PedalRegistry.get_def(id).make_audio_effect())
		AudioServer.set_bus_effect_enabled(bus, AudioServer.get_bus_effect_count(bus) - 1, not is_bypassed(id))
