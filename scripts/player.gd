extends CharacterBody2D
## 2D character whose sprite is a live render of the 3D rig (RigViewport -> Sprite).
## Front 3/4 view: the camera never rotates; it looks straight "north" (-Z) tilted 38 deg down.
## Screen x = ground x, screen y = ground depth foreshortened by sin(38). The rig turns to 8 facings.

const METRES_PER_PX := 3.0 / 80.0      # same world scale as the sprite-poc renders (~80px tall)
const ELEVATION := deg_to_rad(38.0)    # rig camera tilt; also the iso foreshortening of the ground
const CAM_TARGET_Y := 1.15             # rig camera looks at this height above the feet
const CANVAS_PX := 128                 # big enough for the full-reach swing
const SWING_REACH := 2.0               # metres in front that the swing connects
const SWING_DAMAGE := 8
## How far (ground metres) enemies hear the player's sounds (SoundStimulus -> Perception).
const NOISE_M := {&"note": 9.0, &"strum": 12.0, &"swing": 5.0, &"cast_release": 10.0, &"step": 2.0, &"lightning": 12.0}
const HURT_KNOCKBACK_MPS := 2.5
const HURT_FLASH_S := 0.25
const NOTE_COLORS := [Color("ff5a4a"), Color("ff9a2a"), Color("ffd84a"), Color("8ae05a"),
		Color("4ad8c8"), Color("5aa0ff"), Color("a87aff"), Color("ff7ad8")]

@export var walk_speed := 1.4          # metres / second on the ground

## Every live note (for the looper): note index 0..7 and the instrument it was played with.
signal note_played(index: int, instrument: int, octave: int)

@onready var rig: RockerRig = $RigViewport/Rig
@onready var rig_camera: Camera3D = $RigViewport/Camera
@onready var sprite: Sprite2D = $Sprite

var sfx: Sfx
var spellbook: Spellbook
var aura_back: ChargeAura
var aura_front: ChargeAura
var instrument := 0                    # Sfx.INSTRUMENTS index for the note keys
var octave := 0                        # [ / ] shift the note keys' pitch, -2..+2 (sound only)
const OCTAVE_RANGE := 2
var facing := Vector2(0, -1)           # ground direction (x = screen-right, y = away); starts facing camera
var _gear_index := {}
var _knockback := Vector2.ZERO         # screen px/s from enemy hits, decays
var _hurt_flash := 0.0


func _ready() -> void:
	$RigViewport.size = Vector2i(CANVAS_PX, CANVAS_PX)
	# fixed ortho camera in front of the character (+Z side), 38 deg down, same scale as sprite-poc
	rig_camera.size = CANVAS_PX * METRES_PER_PX
	var target := Vector3(0, CAM_TARGET_Y, 0)
	var e := ELEVATION
	rig_camera.position = target + Vector3(0, sin(e), cos(e)) * 20.0
	rig_camera.look_at(target)
	sprite.texture = $RigViewport.get_texture()
	# place the rig's feet (3D origin) on this node's position, for y-sorting and the shadow
	sprite.offset = Vector2(0, -round(CAM_TARGET_Y * cos(e) / METRES_PER_PX))
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	spellbook = Spellbook.new()
	spellbook.name = "Spellbook"
	add_child(spellbook)
	spellbook.cast.connect(_on_spell)
	spellbook.charge_changed.connect(_on_charge_changed)
	# charge aura wraps the sprite: one layer behind it, one in front (child order)
	aura_back = ChargeAura.new()
	aura_back.front = false
	aura_front = ChargeAura.new()
	for a: ChargeAura in [aura_back, aura_front]:
		a.spellbook = spellbook
		add_child(a)
	move_child(aura_back, sprite.get_index())
	move_child(aura_front, sprite.get_index() + 1)
	rig.anim_event.connect(sfx.play)
	rig.anim_event.connect(_on_anim_event)
	# enemies: the player is hittable and loud (Perception hears these)
	add_to_group("player")
	note_played.connect(func(_i: int, _inst: int, _oct: int) -> void: SoundStimulus.emit(self, NOISE_M[&"note"]))
	rig.anim_event.connect(_make_noise)
	spellbook.cast.connect(func(spell: StringName, _power: int) -> void: _make_noise(spell))
	for slot in GearCatalog.SLOTS:
		_gear_index[slot] = 0
		rig.equip(slot, GearCatalog.ITEMS[slot][0])


func _physics_process(_delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if rig.is_busy():
		input = Vector2.ZERO
	if input != Vector2.ZERO:
		facing = Vector2(input.x, -input.y).normalized()
		velocity = ground_to_screen(facing) * walk_speed / METRES_PER_PX
		# 3D ground direction: right = +X, away from camera = -Z (the model faces +Z at yaw 0)
		rig.face(atan2(facing.x, -facing.y))
	else:
		velocity = Vector2.ZERO
	rig.set_moving(input != Vector2.ZERO)
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * _delta)
	move_and_slide()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("swing"):
		rig.play_action(&"swing")
	elif event.is_action_pressed("strum"):
		rig.play_action(&"strum")
	for i in Spellbook.NOTE_NAMES.size():
		if event.is_action_pressed("note_%d" % i):
			play_note(i)
	if event.is_action_pressed("octave_down"):
		octave = maxi(octave - 1, -OCTAVE_RANGE)
	elif event.is_action_pressed("octave_up"):
		octave = mini(octave + 1, OCTAVE_RANGE)
	if event.is_action_pressed("cycle_instrument"):
		instrument = (instrument + 1) % Sfx.INSTRUMENTS.size()
	for slot in GearCatalog.SLOTS:
		if event.is_action_pressed("cycle_" + slot):
			cycle_gear(slot)


# ---------------------------------------------------------------- notes & spells
func play_note(i: int) -> void:
	if rig.is_busy():
		return
	sfx.play_note(i, instrument, octave)
	rig.play_note(i)
	note_played.emit(i, instrument, octave)
	FloatText.spawn(get_parent(), guitar_tip() + Vector2(randf_range(-3, 3), -4), "n", NOTE_COLORS[i], 14.0)
	spellbook.play_note(i)


var _charges := 0


func _on_charge_changed(spell: StringName, charges: int) -> void:
	aura_front.on_charge_changed(spell, charges)
	sfx.set_charge(charges, _charges)
	_charges = charges


func _on_spell(spell: StringName, power: int) -> void:
	match spell:
		&"fire":
			rig.play_action(&"cast")          # the fireball leaves on the thrust (cast_release)
		&"lightning":
			aura_front.discharge(0.15 + power / ChargeAura.FULL)
			var chain := ChainLightning.new()
			chain.charges = power
			chain.origin = guitar_tip()
			chain.aim = ground_to_screen(facing).normalized()
			chain.sfx = sfx
			get_parent().add_child(chain)


func _on_anim_event(event: StringName) -> void:
	match event:
		&"cast_release":
			var fb := Fireball.new()
			var tip := _tip_ground()
			fb.position = tip[0]
			fb.height = tip[1]
			fb.velocity = ground_to_screen(facing) * Fireball.SPEED
			fb.caster = self
			fb.sfx = sfx
			get_parent().add_child(fb)
		&"swing_hit":
			var hit := false
			for e: Node2D in get_tree().get_nodes_in_group("enemies"):
				var d := screen_to_ground(e.global_position - global_position) * METRES_PER_PX
				if d.length() < SWING_REACH and d.normalized().dot(facing) > 0.3:
					e.take_damage(SWING_DAMAGE, &"melee", ground_to_screen(facing).normalized())
					hit = true
			if hit:
				sfx.play(&"hit")


# ---------------------------------------------------------------- enemies: getting hit, noise
## Enemy hits: red flash, a shove and a damage number. No health/death yet (user decision); notes,
## spells and the current animation keep going.
func take_damage(amount: int, kind: StringName, from_dir: Vector2) -> void:
	_hurt_flash = HURT_FLASH_S
	_knockback = from_dir.normalized() * HURT_KNOCKBACK_MPS / METRES_PER_PX
	FloatText.spawn(get_parent(), global_position + Vector2(randf_range(-5, 5), -72), str(amount),
			Color("ff8a1c") if kind == &"fire" else Color("ff3a2a"))
	sfx.play(&"hit")


func hit_point() -> Vector2:
	return global_position + Vector2(0, -40)


func _process(delta: float) -> void:
	if _hurt_flash > 0.0:
		_hurt_flash = maxf(_hurt_flash - delta, 0.0)
		(sprite.material as ShaderMaterial).set_shader_parameter("flash", 0.8 * _hurt_flash / HURT_FLASH_S)


func _make_noise(event: StringName) -> void:
	if NOISE_M.has(event):
		SoundStimulus.emit(self, NOISE_M[event])


# ---------------------------------------------------------------- projection helpers
static func ground_to_screen(g: Vector2) -> Vector2:
	return Vector2(g.x, -g.y * sin(ELEVATION))


static func screen_to_ground(s: Vector2) -> Vector2:
	return Vector2(s.x, -s.y / sin(ELEVATION))


## Headstock as [ground position (world px), height above the ground (px)].
func _tip_ground() -> Array:
	var t := rig.guitar_tip_world()     # rig space: x right, y up, +z toward the camera
	var ground := global_position + Vector2(t.x, t.z * sin(ELEVATION)) / METRES_PER_PX
	return [ground, t.y * cos(ELEVATION) / METRES_PER_PX]


## Headstock on screen (world px).
func guitar_tip() -> Vector2:
	var tg := _tip_ground()
	return tg[0] - Vector2(0, tg[1])


# ---------------------------------------------------------------- gear
func cycle_gear(slot: String) -> void:
	var items: Array = GearCatalog.ITEMS[slot]
	_gear_index[slot] = (_gear_index[slot] + 1) % items.size()
	rig.equip(slot, items[_gear_index[slot]])


func gear_summary() -> String:
	var parts := []
	for slot in GearCatalog.SLOTS:
		var item: Dictionary = rig.equipped.get(slot, {})
		parts.append("%s: %s" % [slot, item.get("name", "none")])
	return "  |  ".join(parts)


func _draw() -> void:
	# soft contact shadow, an ellipse foreshortened like the ground
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * 13.0, sin(a) * 13.0 * sin(ELEVATION)))
	draw_colored_polygon(pts, Color(0, 0, 0, 0.35))
