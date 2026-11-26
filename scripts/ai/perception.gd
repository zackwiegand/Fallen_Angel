class_name Perception
extends Node
## Senses for an enemy: sight (cone + 360 deg "close" sense, line of sight vs walls), hearing (SoundStimulus
## events) and an awareness meter with a last-known position. Measured on the ground plane, in metres.
##
## awareness 0..1: CALM below SUSPICIOUS, SUSPICIOUS (investigate) up to 1.0, ALERT at 1.0.
## Seeing the target fills it (faster when close); noise adds a burst; damage alerts instantly.
## ALERT is latched: it only drops when the brain calls forget() (after it gave up searching).
## Call tick(delta) from the owner's _physics_process so the order is deterministic.

signal alerted(target: Node2D)

enum Level { CALM, SUSPICIOUS, ALERT }

const GROUP := &"noise_listeners"
const SUSPICIOUS := 0.35
## Awareness gained per second while the target is in view, at the edge of sight range vs close.
const SEE_RATE_FAR := 0.9
const SEE_RATE_NEAR := 4.0
const DECAY := 0.12               # per second while not seeing (below ALERT only)
const LKP_TRACK_S := 0.4          # keep updating the last-known position briefly after losing sight
const MAX_LOS_SKIPS := 6          # non-wall bodies a sight ray may pass through

@export var sight_range_m := 9.0
@export var fov_deg := 130.0
@export var close_range_m := 1.8  # sensed in any direction (no cone)
@export var hearing_scale := 1.0  # multiplies every noise radius

var body: Node2D                  # the agent; defaults to the parent
var target: Node2D               # who we're looking for (the player)
var facing := Vector2(0, -1)     # ground direction the eyes point (set by the agent)

var awareness := 0.0
var can_see := false
var last_known := Vector2.ZERO   # screen position
var has_last_known := false
var time_since_seen := INF
var heard_recently := false      # a noise moved last_known since the brain last looked (consume_heard)


func _ready() -> void:
	if body == null:
		body = get_parent() as Node2D
	add_to_group(GROUP)


func level() -> Level:
	if awareness >= 1.0:
		return Level.ALERT
	if awareness >= SUSPICIOUS:
		return Level.SUSPICIOUS
	return Level.CALM


func is_alert() -> bool:
	return awareness >= 1.0


func tick(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		can_see = false
		return
	var was_alert := is_alert()
	can_see = _sees(target)
	if can_see:
		time_since_seen = 0.0
		_set_last_known(target.global_position)
		var d := Ground.dist_m(body.global_position, target.global_position)
		var u := clampf(d / sight_range_m, 0.0, 1.0)
		awareness = minf(awareness + lerpf(SEE_RATE_NEAR, SEE_RATE_FAR, u) * delta, 1.0)
	else:
		time_since_seen += delta
		if time_since_seen < LKP_TRACK_S:          # "they went that way"
			_set_last_known(target.global_position)
		if not was_alert:
			awareness = maxf(awareness - DECAY * delta, 0.0)
	if is_alert() and not was_alert:
		alerted.emit(target)


## SoundStimulus.emit() lands here. Louder (closer) noises add more awareness; a close loud noise alerts.
func hear_noise(at: Vector2, radius_m: float, source: Node) -> void:
	if body == null or source == body:
		return
	var r := radius_m * hearing_scale
	var d := Ground.dist_m(body.global_position, at)
	if d > r:
		return
	var was_alert := is_alert()
	var loud := 1.0 - d / r
	awareness = minf(awareness + 0.4 + loud * 0.9, 1.0)
	_set_last_known(at)
	heard_recently = true
	if is_alert() and not was_alert:
		alerted.emit(target)


## Being hit always alerts, and points at the attacker.
func notify_attacked(from: Vector2) -> void:
	var was_alert := is_alert()
	awareness = 1.0
	_set_last_known(from)
	if not was_alert:
		alerted.emit(target)


## Give up: drop to "suspicious-ish" so it settles back to calm on its own.
func forget() -> void:
	awareness = minf(awareness, SUSPICIOUS * 0.9)
	has_last_known = false


func reset() -> void:
	awareness = 0.0
	can_see = false
	has_last_known = false
	time_since_seen = INF
	heard_recently = false


func consume_heard() -> bool:
	var h := heard_recently
	heard_recently = false
	return h


func _set_last_known(p: Vector2) -> void:
	last_known = p
	has_last_known = true


func _sees(t: Node2D) -> bool:
	var to := Ground.to_ground(t.global_position - body.global_position) * Ground.METRES_PER_PX
	var d := to.length()
	if d > sight_range_m:
		return false
	if d > close_range_m and facing != Vector2.ZERO:
		if absf(rad_to_deg(facing.angle_to(to))) > fov_deg * 0.5:
			return false
	return line_of_sight(body, t)


## True if nothing wall-like (a TileMapLayer, i.e. walls and pillars) blocks the ray between the two
## bodies' feet. Other bodies (dummies, other enemies) don't block sight.
static func line_of_sight(from: Node2D, to: Node2D) -> bool:
	var space := from.get_world_2d().direct_space_state
	var exclude: Array[RID] = []
	if from is CollisionObject2D:
		exclude.append((from as CollisionObject2D).get_rid())
	for i in MAX_LOS_SKIPS:
		var q := PhysicsRayQueryParameters2D.create(from.global_position, to.global_position)
		q.exclude = exclude
		var hit := space.intersect_ray(q)
		if hit.is_empty() or hit.collider == to:
			return true
		if hit.collider is TileMapLayer:
			return false
		exclude.append(hit.rid)
	return true
