class_name GuitarHands
extends SkeletonModifier3D
## Procedural "playing" layer on top of whatever animation is running (idle, walk ...).
## Runs after the AnimationTree each frame and re-aims both arms with a two-bone IK:
##   - fretting hand (L) slides along the guitar's neck to each note's position
##     (low notes near the headstock, high notes up toward the body, like a real neck)
##   - picking hand (R) flicks across the strings on every note, alternating down/up strokes
## Targets are offsets from the animated hand positions along the guitar's own axes, and the elbow
## keeps the animation's bend plane, so with no offset the pose is exactly the baked one: the layer
## blends in and out without pops and follows the guitar through breathing and walking.
## The rig disables it (SkeletonModifier3D.active) during swing / strum / cast.

const FRET_X := 0.68            # baked fretting-hand spot on the neck (export_gltf.py FRET_X)
const NECK_LOW := 0.80          # note 0 (E3): near the headstock
const NECK_HIGH := 0.28         # note 7 (A4): high up the neck, by the body
const SLIDE_TIME := 0.07        # fretting hand jump to a new note
const RETURN_TIME := 0.35       # drift back to the rest grip
const HOLD := 1.2               # seconds after the last note before drifting back
const PICK_TIME := 0.22
const PICK_AMP := 0.11          # metres across the strings (~3 px at sprite size)

var _bones := {}
var last_shift := {"L": 0.0, "R": 0.0}   # how far each hand was moved this frame (for tests / debug)
var _fret_x := FRET_X
var _fret_from := FRET_X
var _fret_to := FRET_X
var _slide := 1.0
var _slide_time := SLIDE_TIME
var _hold := 0.0
var _pick := 1.0
var _pick_dir := 1.0


func _ready() -> void:
	var sk := get_skeleton()
	for n in ["guitar", "chest", "upper_arm.L", "forearm.L", "hand.L", "upper_arm.R", "forearm.R", "hand.R"]:
		_bones[n] = sk.find_bone(n)


## Play note i (0..7): move the fretting hand to its spot and pick.
func note(i: int) -> void:
	_slide_to(lerpf(NECK_LOW, NECK_HIGH, i / 7.0), SLIDE_TIME)
	_hold = HOLD
	_pick = 0.0
	_pick_dir = -_pick_dir


## Snap back to the baked pose (when an action takes over the arms).
func reset() -> void:
	_fret_x = FRET_X
	_fret_to = FRET_X
	_slide = 1.0
	_pick = 1.0
	_hold = 0.0


func _slide_to(x: float, time: float) -> void:
	_fret_from = _fret_x
	_fret_to = x
	_slide = 0.0
	_slide_time = time


func _process(delta: float) -> void:
	_slide = minf(_slide + delta / _slide_time, 1.0)
	_fret_x = lerpf(_fret_from, _fret_to, 1.0 - pow(1.0 - _slide, 3.0))
	_pick = minf(_pick + delta / PICK_TIME, 1.0)
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_slide_to(FRET_X, RETURN_TIME)


## Pick stroke across the strings: quick strike through, then ease back to rest.
func _pick_offset() -> float:
	if _pick >= 1.0:
		return 0.0
	if _pick < 0.18:
		return lerpf(0.6, -1.0, _pick / 0.18) * PICK_AMP
	var u := (_pick - 0.18) / 0.82
	return -1.0 * (1.0 - u * u * (3.0 - 2.0 * u)) * PICK_AMP


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	last_shift = {"L": 0.0, "R": 0.0}
	# guitar axes in skeleton space; the +90 deg X matches the guitar mount (rocker_rig.gd)
	var gb := sk.get_bone_global_pose(_bones["guitar"]).basis.orthonormalized() * Basis(Vector3.RIGHT, PI / 2)
	var neck := gb * Vector3.RIGHT        # toward the headstock
	var across := gb * Vector3.UP         # across the strings (body's top edge)
	var face := gb * Vector3.BACK         # out of the playing face
	var wl := sk.get_bone_global_pose(_bones["hand.L"]).origin
	if absf(_fret_x - FRET_X) > 1e-4:
		_solve(sk, "L", wl + neck * (_fret_x - FRET_X))
	var pick := _pick_offset()
	if pick != 0.0:
		var wr := sk.get_bone_global_pose(_bones["hand.R"]).origin
		_solve(sk, "R", wr + across * pick * _pick_dir + face * absf(pick) * 0.3)


## Two-bone IK keeping the current elbow plane; hand keeps its pose relative to the forearm.
func _solve(sk: Skeleton3D, side: String, target: Vector3) -> void:
	var a: int = _bones["upper_arm." + side]
	var b: int = _bones["forearm." + side]
	var c: int = _bones["hand." + side]
	var ga := sk.get_bone_global_pose(a)
	var gb := sk.get_bone_global_pose(b)
	var gc := sk.get_bone_global_pose(c)
	var s := ga.origin
	var e := gb.origin
	var w := gc.origin
	var l1 := s.distance_to(e)
	var l2 := e.distance_to(w)
	var to_t := target - s
	var d := clampf(to_t.length(), absf(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	var dir := to_t.normalized()
	var pole := (e - s) - dir * (e - s).dot(dir)
	if pole.length() < 1e-5:
		return
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var e2 := s + dir * l1 * cos_a + pole * l1 * sqrt(1.0 - cos_a * cos_a)
	var w2 := s + dir * d
	last_shift[side] = w2.distance_to(w)
	var q1 := Basis(Quaternion((e - s).normalized(), (e2 - s).normalized()))
	var w1 := s + q1 * (w - s)
	var q2 := Basis(Quaternion((w1 - e2).normalized(), (w2 - e2).normalized()))
	var na := Transform3D(q1 * ga.basis, s)
	var nb := Transform3D(q2 * q1 * gb.basis, e2)
	var nc := Transform3D(q2 * q1 * gc.basis, w2)
	var parent := sk.get_bone_global_pose(sk.get_bone_parent(a))
	_set_local(sk, a, parent.affine_inverse() * na)
	_set_local(sk, b, na.affine_inverse() * nb)
	_set_local(sk, c, nb.affine_inverse() * nc)


func _set_local(sk: Skeleton3D, bone: int, local: Transform3D) -> void:
	sk.set_bone_pose_rotation(bone, local.basis.get_rotation_quaternion())
	sk.set_bone_pose_position(bone, local.origin)
