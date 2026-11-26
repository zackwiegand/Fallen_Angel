class_name PedalRegistry
## Every pedal in the game by id. A new pedal = a PedalDef subclass + one line here
## (+ its model in assets/pedals/, see PedalView).

const PEDALS := {
	&"chief_delay": preload("res://scripts/pedals/delay_pedal.gd"),
	&"skyman_phaser": preload("res://scripts/pedals/phaser_pedal.gd"),
}

static var _defs := {}


static func get_def(id: StringName) -> PedalDef:
	if not _defs.has(id):
		assert(PEDALS.has(id), "unknown pedal %s" % id)
		_defs[id] = PEDALS[id].new()
	return _defs[id]


static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	out.assign(PEDALS.keys())
	return out
