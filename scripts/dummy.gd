extends StaticBody2D
## Practice dummy: takes hits (flash, wobble, damage numbers, burn tint for fire) but never dies.

const COLORS := {&"fire": Color("ff9a2a"), &"lightning": Color("9fe0ff"), &"melee": Color("ffffff")}

@onready var sprite: Sprite2D = $Sprite

var total_damage := 0
var _angle := 0.0
var _spin := 0.0
var _flash := 0.0
var _burn := 0.0


func _ready() -> void:
	add_to_group("enemies")
	sprite.material = sprite.material.duplicate()


## Where spells aim / numbers pop: the straw chest, above the base.
func hit_point() -> Vector2:
	return global_position + Vector2(0, -30)


func take_damage(amount: int, kind: StringName, from_dir: Vector2) -> void:
	total_damage += amount
	var echo := Damage.is_echo(kind)      # delay-pedal repeat: smaller wobble, fainter number
	kind = Damage.base_kind(kind)
	_spin += (signf(from_dir.x) if absf(from_dir.x) > 0.1 else randf_range(-1, 1)) * (2.0 if echo else 5.0)
	_flash = 0.5 if echo else 1.0
	if kind == &"fire":
		_burn = maxf(_burn, 0.8 if echo else 1.6)
	var color: Color = COLORS.get(kind, Color.WHITE)
	if echo:
		color = Color(color.lerp(Color("9ab8ff"), 0.4), 0.6)
	FloatText.spawn(get_parent(), global_position + Vector2(randf_range(-7, 7), -48 if echo else -54),
			str(amount), color, 12.0 if echo else 16.0)


func _process(delta: float) -> void:
	_spin += (-_angle * 140.0 - _spin * 7.0) * delta        # damped spring back to upright
	_angle = clampf(_angle + _spin * delta, -0.35, 0.35)
	sprite.rotation = _angle
	_flash = maxf(_flash - delta * 7.0, 0.0)
	_burn = maxf(_burn - delta, 0.0)
	var mat := sprite.material as ShaderMaterial
	mat.set_shader_parameter("flash", _flash)
	mat.set_shader_parameter("burn", minf(_burn, 1.0) * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.03)))
