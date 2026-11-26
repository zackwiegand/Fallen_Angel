class_name SpellCast
extends RefCounted
## One spell on its way out of the guitar. The player fills it in, the pedal chain transforms it
## pedal by pedal in signal order (Pedalboard.apply), then launch() spawns the projectile(s).
## Keeping the cast as plain data means pedal rules are testable without a world.

const SPELL_NAMES := {&"fire": "FIREBALL", &"lightning": "LIGHTNING"}

var spell: StringName              # &"fire" / &"lightning"
var damage := 0                    # per hit
var power := 1                     # lightning: number of hops in the chain

# --- what the pedals change
var pierce := false                # passes through enemies instead of stopping at the first one
var echoes := 0                    # extra hits on every target it hits, halving (Damage.deal)
var echo_delay := 0.0              # seconds between echo hits (= the delay pedal's time)
var ghosts := 0                    # delayed repeat casts along the same path, halving damage
var ghost_delay := 0.0             # seconds between ghost casts
var phased := false                # shimmering purple aura
var touched_by: Array[StringName] = []   # pedal ids that transformed it, in order

# --- launch parameters (world px)
var origin := Vector2.ZERO         # fire: ground position under the headstock; lightning: headstock on screen
var height := 0.0                  # fire: height of the headstock above the ground
var direction := Vector2.DOWN      # screen direction of travel / aim
var caster: Node2D
var sfx: Sfx


static func fire(at_ground: Vector2, at_height: float, dir: Vector2, by: Node2D, with_sfx: Sfx) -> SpellCast:
	var c := SpellCast.new()
	c.spell = &"fire"
	c.damage = Fireball.DAMAGE
	c.origin = at_ground
	c.height = at_height
	c.direction = dir.normalized()
	c.caster = by
	c.sfx = with_sfx
	return c


static func lightning(charges: int, at: Vector2, dir: Vector2, by: Node2D, with_sfx: Sfx) -> SpellCast:
	var c := SpellCast.new()
	c.spell = &"lightning"
	c.damage = ChainLightning.DAMAGE
	c.power = charges
	c.origin = at
	c.direction = dir.normalized()
	c.caster = by
	c.sfx = with_sfx
	return c


## Damage of the original hit and each repeat (echo or ghost), e.g. [12, 6, 3, 2].
func damage_series(repeats: int) -> Array[int]:
	var out: Array[int] = [damage]
	for k in range(1, repeats + 1):
		out.append(Damage.falloff(damage, k))
	return out


## One line for the pedalboard menu, e.g. "FIREBALL 12 DMG - PIERCES - ECHOES 6 3 2 ON EVERY TARGET".
func describe() -> String:
	var parts: Array[String] = ["%s %d DMG%s" % [SPELL_NAMES.get(spell, str(spell).to_upper()), damage,
			" PER HIT" if spell == &"lightning" else ""]]
	if ghosts > 0:
		var g := damage_series(ghosts).slice(1)
		parts.append("+%d %sGHOSTS %s" % [ghosts, "PHASED " if phased else "", " ".join(g.map(str))])
	if pierce:
		parts.append("ALL PIERCE" if ghosts > 0 else "PIERCES")
	if echoes > 0:
		var e := damage_series(echoes).slice(1)
		parts.append("ECHOES %s ON %s" % [" ".join(e.map(str)), "EVERY TARGET" if pierce else "FIRST TARGET"])
	if parts.size() == 1:
		parts.append("DRY")
	return " - ".join(parts)


## Spawns the spell into `world`: the original now, ghosts after ghost_delay, 2x ghost_delay, ...
func launch(world: Node) -> void:
	_spawn(world, damage, false)
	for k in range(1, ghosts + 1):
		var ghost_damage := Damage.falloff(damage, k)
		var timer := world.get_tree().create_timer(ghost_delay * k, false)
		timer.timeout.connect(func() -> void:
			if is_instance_valid(world):
				_spawn(world, ghost_damage, true))


func _spawn(world: Node, hit_damage: int, ghost: bool) -> void:
	match spell:
		&"fire":
			var fb := Fireball.new()
			fb.position = origin
			fb.height = height
			fb.velocity = direction * Fireball.SPEED
			fb.caster = caster
			fb.sfx = sfx
			fb.damage = hit_damage
			fb.pierce = pierce
			fb.echoes = echoes
			fb.echo_delay = echo_delay
			fb.phased = phased
			fb.ghost = ghost
			world.add_child(fb)
		&"lightning":
			var chain := ChainLightning.new()
			chain.charges = power
			chain.origin = origin
			chain.aim = direction
			chain.sfx = sfx
			chain.damage = hit_damage
			chain.pierce = pierce
			chain.echoes = echoes
			chain.echo_delay = echo_delay
			chain.phased = phased
			chain.ghost = ghost
			world.add_child(chain)
