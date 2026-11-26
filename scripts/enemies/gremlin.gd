class_name Gremlin
extends CharacterBody2D
## Little devil-gremlin: crawls on all fours, paces around its spawn until it notices the player,
## then throws fireballs from range and gallops in for claw slashes up close.
## The body owns movement, health and actions; the decisions live in the brain (an HFSM, see
## gremlin_states.gd) and the senses in Perception. Distances in ground metres (see Ground).
##
## Brain:  calm (idle <-> pace) -> investigate -> combat (engage / throw / circle / charge / slash /
##         back_off) -> search -> return -> calm; hurt and dead interrupt from anywhere.

signal died(gremlin: Gremlin)

# --- health
const MAX_HP := 30
const RESPAWN_S := 8.0
const CORPSE_S := 1.2             # lies there after the death clip, then vanishes
const KNOCKBACK_MPS := 2.2
const STAGGER_S := 0.35

# --- movement (player walks 1.4 m/s)
const WALK_MPS := GremlinRig.WALK_SPEED       # match the baked strides so claws stay planted
const GALLOP_MPS := GremlinRig.GALLOP_SPEED
const STRAFE_MPS := 0.9
const RETURN_MPS := 1.0           # trotting home after giving up
const PACE_RADIUS_M := 2.5
const PACE_PAUSE_S := Vector2(1.2, 3.2)    # random idle time between pacing legs

# --- combat spacing
const RANGED_MIN_M := 3.5         # closer than this: stop throwing, go melee
const RANGED_MAX_M := 8.5         # throw from up to here (fireball range is ~9 m)
const CIRCLE_M := 2.6             # waiting-for-a-melee-token orbit radius
const SLASH_RANGE_M := 1.0        # start the slash at this distance
const SLASH_REACH_M := 1.5        # the slash connects within this distance at slash_hit
const SLASH_ARC_DOT := 0.2        # ... and roughly in front

# --- attacks
const VOLLEY := Vector2i(2, 3)    # fireballs per volley
const THROW_GAP_S := 0.25         # pause between throws in a volley
const RANGED_COOLDOWN_S := Vector2(3.0, 4.5)
const MELEE_COOLDOWN_S := 1.1
const SLASH_DAMAGE := 6
const COMBO_CHANCE := 0.4         # second slash if still in reach
const CHARGE_TIMEOUT_S := 3.0
const ALERT_PAUSE_S := 0.4        # "!" reaction before acting: readable, fair

# --- awareness
const LOSE_SIGHT_S := 4.0         # out of sight this long while in combat -> search
const SEARCH_LOOK_S := 2.5
const SEARCH_TIMEOUT_S := 8.0

const DAMAGE_COLORS := {&"fire": Color("ff9a2a"), &"lightning": Color("9fe0ff"), &"melee": Color("ffffff")}

@onready var rig: GremlinRig = $Rig
@onready var nav: NavMover = $Nav
@onready var perception: Perception = $Perception

var spawn_point := Vector2.ZERO
var hp := MAX_HP
var target: Node2D
var brain: StateMachine
var facing := Vector2(0, -1)      # ground direction
var clock := 0.0                  # own time (s) for cooldowns; deterministic under --fixed-fps
var ranged_ready_at := 0.0
var melee_ready_at := 0.0
var rng := RandomNumberGenerator.new()
var volley_done := false          # threw this engagement's volley -> commit to melee

var _anim: StringName = &""
var _knockback := Vector2.ZERO    # screen px/s
var _flash := 0.0
var _burn := 0.0
var _telegraph := 0.0             # 0..1 glow at the claw (throw windup)
var _puff := 0.0                  # respawn smoke
var _fx: Node2D


func _ready() -> void:
	add_to_group("enemies")
	motion_mode = MOTION_MODE_FLOATING
	if spawn_point == Vector2.ZERO:
		spawn_point = global_position
	rng.seed = hash(spawn_point)
	perception.body = self
	rig.anim_event.connect(_on_anim_event)
	_fx = Node2D.new()                       # drawn over the rig (telegraph ember, respawn puff)
	_fx.name = "Fx"
	add_child(_fx)
	_fx.draw.connect(_draw_fx)
	brain = GremlinStates.build(self)
	brain.start(&"calm")


func _physics_process(delta: float) -> void:
	clock += delta
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node2D
		perception.target = target
	perception.facing = facing
	if brain.current_name != &"dead":
		perception.tick(delta)
	velocity = Vector2.ZERO
	brain.update(delta)
	velocity += _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()
	rig.facing = facing


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 6.0, 0.0)
	_burn = maxf(_burn - delta, 0.0)
	_puff = maxf(_puff - delta * 1.5, 0.0)
	var c := Color.WHITE.lerp(Color(3, 3, 3), _flash)
	if _burn > 0.0:
		c = c * Color(1.6, 1.0, 0.6).lerp(Color.WHITE, 1.0 - minf(_burn, 1.0))
	rig.modulate = c
	if rig.has_method(&"set_flash"):        # a 3D rig may tint in its shader instead
		rig.call(&"set_flash", _flash)
	queue_redraw()
	_fx.queue_redraw()


# ---------------------------------------------------------------- body API for the brain
func move(g_dir: Vector2, speed_mps: float, face_move := true) -> void:
	var d := g_dir + nav.separation() * 0.6
	if d.length() < 0.01:
		return
	velocity = Ground.velocity(d.normalized(), speed_mps)
	if face_move:
		facing = d.normalized()


## Walk/gallop toward a screen position using the nav map; returns true when there.
func go_to(goal: Vector2, speed_mps: float, arrive_px := 4.0) -> bool:
	var d := nav.direction_to_goal(goal, arrive_px)
	if d == Vector2.ZERO:
		return true
	move(d, speed_mps)
	return false


func face_toward(p: Vector2) -> void:
	var d := Ground.dir(global_position, p)
	if d != Vector2.ZERO:
		facing = d


func target_dist() -> float:
	return Ground.dist_m(global_position, target.global_position) if target else INF


## Start a clip from the top.
func play(anim: StringName) -> void:
	_anim = anim
	rig.play(anim)


## Keep a looping clip running (no restart if it's already playing).
func play_loop(anim: StringName) -> void:
	if _anim != anim:
		play(anim)


## Locomotion clip from this frame's velocity.
func play_move(fast := false) -> void:
	play_loop((&"gallop" if fast else &"walk") if velocity.length() > 1.0 else &"idle")


func bark(text: String, color: Color) -> void:
	FloatText.spawn(get_parent(), global_position + Vector2(0, -30), text, color, 8.0)


func set_telegraph(v: float) -> void:
	_telegraph = v


func throw_fireball() -> void:
	var hand := rig.hand_point()
	var fb := EnemyFireball.new()
	fb.position = global_position + Vector2(hand.x, 0)
	fb.height = -hand.y
	var aim := target.global_position if target else global_position + Ground.to_screen(facing) * 50.0
	var g := Ground.dir(fb.position, aim).rotated(rng.randf_range(-0.08, 0.08))
	fb.velocity = Ground.velocity(g, EnemyFireball.SPEED_MPS)
	fb.caster = self
	get_parent().add_child(fb)


## The slash's hit frame: connects if the target is in reach and in front.
func slash_connects() -> bool:
	if target == null or not target.has_method(&"take_damage"):
		return false
	var to := Ground.to_ground(target.global_position - global_position) * Ground.METRES_PER_PX
	if to.length() > SLASH_REACH_M or to.normalized().dot(facing) < SLASH_ARC_DOT:
		return false
	target.take_damage(SLASH_DAMAGE, &"claw", Ground.to_screen(facing).normalized())
	return true


func release_tokens() -> void:
	AttackTokens.release_all(self)


func is_dead() -> bool:
	return brain.current_name == &"dead"


# ---------------------------------------------------------------- damage
func hit_point() -> Vector2:
	return global_position + Vector2(0, -12)


func take_damage(amount: int, kind: StringName, from_dir: Vector2) -> void:
	if is_dead():
		return
	hp -= amount
	_flash = 1.0
	if kind == &"fire":
		_burn = 1.4
	FloatText.spawn(get_parent(), global_position + Vector2(rng.randf_range(-4, 4), -28), str(amount),
			DAMAGE_COLORS.get(kind, Color.WHITE))
	_knockback = from_dir.normalized() * KNOCKBACK_MPS / Ground.METRES_PER_PX
	# the player is the only attacker; fall back to "where the hit came from"
	perception.notify_attacked(target.global_position if target else global_position - from_dir.normalized() * 60.0)
	if hp <= 0:
		brain.force(&"dead")
	else:
		brain.force(&"hurt")


func die() -> void:
	release_tokens()
	remove_from_group("enemies")
	$Feet.set_deferred("disabled", true)
	_telegraph = 0.0
	died.emit(self)


func respawn() -> void:
	global_position = spawn_point
	hp = MAX_HP
	facing = Vector2(0, -1)
	visible = true
	_puff = 1.0
	add_to_group("enemies")
	$Feet.set_deferred("disabled", false)
	perception.reset()
	brain.force(&"calm")


func _on_anim_event(event: StringName) -> void:
	brain.dispatch(event)


func _draw() -> void:
	# contact shadow
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 8.0, sin(a) * 8.0 * sin(Ground.ELEVATION)))
	if visible and not (is_dead() and brain.time_in_state > 1.0):
		draw_colored_polygon(pts, Color(0, 0, 0, 0.3))


func _draw_fx() -> void:
	# throw telegraph: an ember swelling in the claw
	if _telegraph > 0.0:
		var h := rig.hand_point()
		var f := 1.0 if (Engine.get_frames_drawn() / 3) % 2 == 0 else 0.0
		_fx.draw_circle(h, 1.5 + _telegraph * 3.0 + f, Color("3a0804"))
		_fx.draw_circle(h, 1.0 + _telegraph * 2.5 + f, Color("ff5a10"))
		_fx.draw_circle(h, 0.5 + _telegraph * 1.5, Color("ffe070"))
	if _puff > 0.0:
		for i in 6:
			var a := TAU * i / 6.0
			var r := (1.0 - _puff) * 12.0 + 3.0
			_fx.draw_circle(Vector2(cos(a) * r, -6 + sin(a) * r * 0.5), 3.0 * _puff, Color(0.25, 0.08, 0.06, _puff))
