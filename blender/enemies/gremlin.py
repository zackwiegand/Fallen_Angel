"""Devil-gremlin: small dark-red quadruped with gnarled horns, long clawed arms, a spade tail.

Run headless:
    blender -b -P blender/enemies/gremlin.py
    godot --headless --path . --import
Writes assets/enemies/gremlin/gremlin.glb (rig + body + clips), loaded by scripts/enemies/gremlin_rig.gd.

Size: at most a third of the rocker (~2.4 m with the head) -> horn tips at ~0.75 m on all fours.
Readability at ~20 px: dark red body, bone-ivory horns / claws / spikes, glowing yellow eyes and an
ember-lit mouth, so it never vanishes on dark cobbles. Faces -Y, left = +X, ground at z = 0.

Clips (seconds; event times are mirrored in GremlinRig.ANIM_EVENTS):
    idle 1.6 loop   twitchy breathing, head snaps, tail flicks
    walk 0.8 loop   slow lateral-sequence prowl                          (WALK_SPEED m/s)
    gallop 0.4 loop gorilla-style bound: arms reach, hind legs swing through (GALLOP_SPEED m/s)
    throw 1.0       rears up on the hind legs, hurls a fireball overhead (release THROW_RELEASE)
    slash 0.6       claw swipe across the front (hit SLASH_HIT)
    hit 0.4         flinch
    death 1.0       collapses onto its side (holds the last frame)
"""
import bpy, math, os, random
from mathutils import Vector, Matrix

exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "enemy_common.py")).read())

OUT = os.path.join(ASSETS, "enemies", "gremlin", "gremlin.glb")

# ---------------------------------------------------------------- materials
def gremlin_materials():
    toon_material("GremlinSkin", (0.035, 0.002, 0.003), (0.17, 0.012, 0.01), (0.45, 0.045, 0.028))
    toon_material("GremlinHorn", (0.1, 0.075, 0.045), (0.42, 0.35, 0.22), (0.82, 0.74, 0.54))
    toon_material("GremlinEye", None, None, None, emit=(1.0, 0.82, 0.1))
    toon_material("GremlinMaw", None, None, None, emit=(1.0, 0.32, 0.02))
    toon_material("GremlinFire", None, None, None, emit=(1.0, 0.6, 0.12))


# ---------------------------------------------------------------- rig
BONES = {
    "root":  ((0, 0, 0), (0, 0.1, 0), None),
    "hips":  ((0, 0.18, 0.36), (0, 0.0, 0.40), "root"),
    "spine": ((0, 0.0, 0.40), (0, -0.2, 0.47), "hips"),
    "head":  ((0, -0.22, 0.49), (0, -0.40, 0.52), "spine"),
    "tail1": ((0, 0.2, 0.36), (0, 0.34, 0.30), "hips"),
    "tail2": ((0, 0.34, 0.30), (0, 0.5, 0.34), "tail1"),
}
for _s, _x in (("L", 1), ("R", -1)):
    BONES.update({
        f"upper_arm.{_s}": ((0.16 * _x, -0.17, 0.45), (0.2 * _x, -0.16, 0.25), "spine"),
        f"forearm.{_s}":   ((0.2 * _x, -0.16, 0.25), (0.2 * _x, -0.25, 0.07), f"upper_arm.{_s}"),
        f"hand.{_s}":      ((0.2 * _x, -0.25, 0.07), (0.2 * _x, -0.33, 0.02), f"forearm.{_s}"),
        f"thigh.{_s}":     ((0.11 * _x, 0.17, 0.36), (0.14 * _x, 0.05, 0.2), "hips"),
        f"shin.{_s}":      ((0.14 * _x, 0.05, 0.2), (0.13 * _x, 0.18, 0.07), f"thigh.{_s}"),
        f"foot.{_s}":      ((0.13 * _x, 0.18, 0.07), (0.13 * _x, 0.07, 0.01), f"shin.{_s}"),
    })
HELD = Vector((-0.2, -0.3, 0.06))      # fireball in the right claw (visible only while throwing)
BONES["held"] = (tuple(HELD), tuple(HELD + Vector((0, 0, 0.05))), "hand.R")

WRIST = {s: Vector((0.2 * x, -0.25, 0.07)) for s, x in (("L", 1), ("R", -1))}
ANKLE = {s: Vector((0.13 * x, 0.18, 0.07)) for s, x in (("L", 1), ("R", -1))}
IK_CHAINS = []
for _s, _x in (("L", 1), ("R", -1)):
    IK_CHAINS += [(f"forearm.{_s}", WRIST[_s], (0.32 * _x, 0.25, 0.28)),     # elbows bend back (knuckle-walker)
                  (f"shin.{_s}", ANKLE[_s], (0.2 * _x, -0.35, 0.22))]       # knees forward
HEAD_GROW = (Matrix.Translation((0, -0.24, 0.5)) @ Matrix.Scale(1.2, 4)
             @ Matrix.Translation((0, 0.24, -0.5)))       # gremlin proportions: oversized head + horns
ORIENT = ["hand.L", "hand.R", "foot.L", "foot.R"]


def part_group(bone):
    for key, grp in (("upper_arm", "arm"), ("forearm", "arm"), ("hand", "arm"), ("held", "arm"),
                     ("thigh", "leg"), ("shin", "leg"), ("foot", "leg")):
        if bone.startswith(key):
            return f"{grp}.{bone[-1]}" if bone[-1] in "LR" else "arm.R"
    return "body"


# ---------------------------------------------------------------- model
def build_model(rig):
    gremlin_materials()

    def B(bone, name, obj):
        if bone == "head":        # big-headed: everything on the head scales up around the neck
            obj.matrix_world = HEAD_GROW @ obj.matrix_world
        bind(rig, obj, bone, name)

    S, H = "GremlinSkin", "GremlinHorn"
    # torso: narrow rump, hunched barrel chest (gorilla shoulders above the hips)
    B("hips", "Rump", loft("Rump", [ring_y(0.25, 0.36, 0.06, 0.055), ring_y(0.17, 0.38, 0.1, 0.085, flat=0.2),
                                    ring_y(0.03, 0.41, 0.12, 0.105, flat=0.2)], S))
    B("spine", "Chest", loft("Chest", [ring_y(0.07, 0.41, 0.115, 0.1, flat=0.2), ring_y(-0.05, 0.455, 0.155, 0.13, flat=0.25),
                                       ring_y(-0.16, 0.475, 0.16, 0.12, flat=0.25), ring_y(-0.25, 0.485, 0.1, 0.08)], S))
    for i, (y, z) in enumerate(((0.12, 0.47), (0.0, 0.53), (-0.11, 0.59))):       # bone spikes down the back
        B("hips" if i == 0 else "spine", f"Spike{i}", add("cone", (0, y, z), (0.02, 0.02, 0.045), (-25, 0, 0), H, vertices=4))

    # head: blocky skull, jutting snout with a glowing maw and fangs, slanted eyes, pointed ears
    B("head", "Skull", add("uv_sphere", (0, -0.31, 0.525), (0.1, 0.1, 0.085), mat=S, segments=7, ring_count=5))
    B("head", "Snout", loft("Snout", [ring_y(-0.35, 0.5, 0.085, 0.06, n=6), ring_y(-0.44, 0.48, 0.065, 0.042, n=6)], S))
    B("head", "Maw", add("cube", (0, -0.445, 0.468), (0.05, 0.012, 0.011), mat="GremlinMaw"))
    for x in (-1, 1):
        B("head", "Fang", add("cone", (0.032 * x, -0.452, 0.462), (0.013, 0.013, 0.024), (180, 0, 0), H, vertices=4))
        B("head", "Eye", add("cube", (0.046 * x, -0.4, 0.548), (0.03, 0.012, 0.018), (0, -22 * x, 0), "GremlinEye"))
        B("head", "Brow", add("cube", (0.05 * x, -0.395, 0.578), (0.045, 0.02, 0.016), (0, -24 * x, 0), S))
        B("head", "Ear", add("cone", (0.105 * x, -0.29, 0.55), (0.028, 0.018, 0.065), (0, 72 * x, -15 * x), S, vertices=4))

    # horns: thick gnarled, knotty and twisted, sweeping out and up, then hooking forward-down
    rnd = random.Random(7)
    path = [(0.045, -0.31, 0.58), (0.085, -0.29, 0.635), (0.135, -0.255, 0.68), (0.19, -0.22, 0.705),
            (0.235, -0.215, 0.685), (0.26, -0.245, 0.64), (0.262, -0.285, 0.6)]
    radii = [0.045, 0.05, 0.036, 0.034, 0.024, 0.016, 0.004]          # knots: radius bumps along the horn
    for x in (-1, 1):
        jit = [(rnd.uniform(-0.018, 0.018), rnd.uniform(-0.018, 0.018)) for _ in path]
        jit[0] = jit[-1] = (0, 0)
        pts = [(px * x, py, pz) for px, py, pz in path]
        B("head", f"Horn.{'L' if x > 0 else 'R'}", tube("Horn", pts, radii, H, n=5, twist=31 * x, jitter=jit))

    # arms: long, thick gorilla arms, big ivory claws
    for s, x in (("L", 1), ("R", -1)):
        ua, fa, hd = f"upper_arm.{s}", f"forearm.{s}", f"hand.{s}"
        sh, el, wr = Vector((0.16 * x, -0.17, 0.45)), Vector((0.2 * x, -0.16, 0.25)), WRIST[s]
        B(ua, f"Shoulder.{s}", add("uv_sphere", tuple(sh + Vector((0.01 * x, 0, -0.01))), (0.07, 0.07, 0.065), mat=S, segments=6, ring_count=4))
        B(ua, f"UpperArm.{s}", limb(f"UpperArm.{s}", sh, el, 0.058, 0.04, S, n=6, ridge=0.1, mid=(0.35, 0.062)))
        B(fa, f"Elbow.{s}", add("uv_sphere", tuple(el), (0.042, 0.042, 0.042), mat=S, segments=6, ring_count=4))
        B(fa, f"Forearm.{s}", limb(f"Forearm.{s}", el, wr, 0.05, 0.038, S, n=6, ridge=0.1, mid=(0.3, 0.056)))
        B(hd, f"Fist.{s}", add("cube", tuple(wr + Vector((0, -0.025, -0.022))), (0.042, 0.038, 0.03), mat=S))
        for k in (-1, 0, 1):
            B(hd, f"Claw{k + 1}.{s}", add("cone", tuple(wr + Vector((0.026 * k, -0.06, -0.035))),
                                           (0.015, 0.015, 0.042), (118, 0, 0), H, vertices=4))
    # fireball held in the right claw (the "held" bone scales it in and out)
    B("held", "HeldFire", add("uv_sphere", tuple(HELD), (0.07, 0.07, 0.07), mat="GremlinFire", segments=6, ring_count=4))

    # legs: meaty thighs, thin digitigrade shins, clawed feet
    for s, x in (("L", 1), ("R", -1)):
        th, kn, an = Vector((0.11 * x, 0.17, 0.36)), Vector((0.14 * x, 0.05, 0.2)), ANKLE[s]
        B(f"thigh.{s}", f"Thigh.{s}", limb(f"Thigh.{s}", th, kn, 0.065, 0.042, S, n=6, ridge=0.1, mid=(0.35, 0.07)))
        B(f"shin.{s}", f"Knee.{s}", add("uv_sphere", tuple(kn), (0.038, 0.038, 0.038), mat=S, segments=6, ring_count=4))
        B(f"shin.{s}", f"Shin.{s}", limb(f"Shin.{s}", kn, an, 0.036, 0.028, S, n=6, ridge=0.1))
        B(f"foot.{s}", f"Foot.{s}", loft(f"Foot.{s}", [ring_y(0.19, 0.05, 0.03, 0.03, n=5, x0=0.13 * x),
                                                         ring_y(0.08, 0.025, 0.04, 0.022, n=5, x0=0.13 * x)], S))
        for k in (-1, 1):
            B(f"foot.{s}", f"Toe{k}.{s}", add("cone", (0.13 * x + 0.02 * k, 0.05, 0.015), (0.012, 0.012, 0.03), (100, 0, 0), H, vertices=4))

    # spade tail
    B("tail1", "Tail1", limb("Tail1", (0, 0.2, 0.37), (0, 0.34, 0.3), 0.026, 0.018, S, n=5, ridge=0))
    B("tail2", "Tail2", limb("Tail2", (0, 0.34, 0.3), (0, 0.49, 0.335), 0.017, 0.01, S, n=5, ridge=0))
    B("tail2", "Spade", add("cone", (0, 0.515, 0.345), (0.045, 0.014, 0.05), (-75, 0, 0), S, vertices=4))


# ---------------------------------------------------------------- animation helpers
def T(rig, name):
    return bpy.data.objects[f"IK.{name}"]


def held_scale(rig, s):
    rig.pose.bones["held"].scale = (max(s, 0.001),) * 3


def plant_limbs(rig, offsets=None):
    """IK targets at the rest contact points + per-limb (dy, dz) offsets ("LF", "RF", "LH", "RH")."""
    offsets = offsets or {}
    for s in ("L", "R"):
        dy, dz = offsets.get(s + "F", (0, 0))
        T(rig, f"forearm.{s}").location = WRIST[s] + Vector((0, dy, dz))
        dy, dz = offsets.get(s + "H", (0, 0))
        T(rig, f"shin.{s}").location = ANKLE[s] + Vector((0, dy, dz))


def body(rig, z=0.0, y=0.0, pitch=0.0, roll=0.0, yaw=0.0, spine=0.0, head=(0.0, 0.0, 0.0), tail=(0.0, 0.0)):
    """Whole-body pose: root offset, hips pitch (-: front rises), spine flex, head (pitch, yaw, roll),
    tail (lift, sway)."""
    pb = rig.pose.bones["root"]
    pb.location = (0, 0, 0)
    rot_pivot(rig, "root", 'Z', yaw, (0, 0, 0))
    rot_pivot(rig, "root", 'Y', roll, (0, 0, 0.15))      # rolls about the belly, not the feet
    if z or y:
        pb.matrix = Matrix.Translation((0, y, z)) @ pb.matrix
        bpy.context.view_layer.update()
    rot_pivot(rig, "hips", 'X', pitch)
    rot_pivot(rig, "spine", 'X', spine)
    hp, hy, hr = head
    rot_pivot(rig, "head", 'X', hp - pitch - spine)        # head holds level unless told otherwise
    rot_pivot(rig, "head", 'Z', hy)
    rot_pivot(rig, "head", 'Y', hr)
    rot_pivot(rig, "tail1", 'X', -tail[0])
    rot_pivot(rig, "tail1", 'Z', tail[1])
    rot_pivot(rig, "tail2", 'X', -tail[0] * 0.8)
    rot_pivot(rig, "tail2", 'Z', tail[1] * 1.2)


def shoulder(rig, s):
    return rig.pose.bones[f"upper_arm.{s}"].head.copy()


def arm_to(rig, s, ground_w, offset, orient=1.0):
    """Blend arm s between its planted wrist (weight ground_w) and shoulder + rig-space offset."""
    tgt = shoulder(rig, s) + Vector(offset)
    T(rig, f"forearm.{s}").location = tgt.lerp(T(rig, f"forearm.{s}").location, ground_w)
    rig.pose.bones[f"hand.{s}"].constraints["Orient"].influence = orient


def wave(p, k=1.0, ph=0.0):
    return math.sin(2 * math.pi * (k * p + ph))


# ---------------------------------------------------------------- clips
# Locomotion is in place; the game moves the body at the speed that matches the planted limbs:
# speed = excursion / (duty * duration).
WALK_T, WALK_DUTY, WALK_EXC = 0.8, 0.7, 0.24
GALLOP_T, GALLOP_DUTY, GALLOP_EXC = 0.4, 0.3, 0.26
WALK_SPEED = WALK_EXC / (WALK_DUTY * WALK_T)
GALLOP_SPEED = GALLOP_EXC / (GALLOP_DUTY * GALLOP_T)
THROW_RELEASE = 0.55        # phase of the 1.0 s throw
SLASH_HIT = 0.45            # phase of the 0.6 s slash


def anim_idle(p, rig):
    held_scale(rig, 0)
    br = wave(p)                                                     # one breath per loop
    look = track([(0, 0), (0.22, 0), (0.26, 24, ease_out), (0.5, 24), (0.54, -8, ease_out), (0.72, -8),
                  (0.76, 0, ease_out), (1, 0)], p)                   # twitchy head snaps
    tilt = track([(0, 0), (0.52, 0), (0.56, 14, ease_out), (0.7, 14), (0.74, 0), (1, 0)], p)
    flick = track([(0, 0), (0.08, 0), (0.12, 25, ease_out), (0.2, -10), (0.3, 0), (1, 0)], p)
    body(rig, z=0.008 * br - 0.01, pitch=-2 * br, spine=-2 * br, head=(4 * br, look, tilt),
         tail=(18 + 6 * br, 10 * wave(p, 1, 0.25) + flick))
    plant_limbs(rig)


def anim_walk(p, rig):
    held_scale(rig, 0)
    off = {}
    for limb, ph in (("LH", 0.0), ("LF", 0.25), ("RH", 0.5), ("RF", 0.75)):   # lateral-sequence walk
        lift = 0.06 if limb[1] == "F" else 0.05
        off[limb] = gait(p + ph, WALK_DUTY, WALK_EXC, lift)
    body(rig, z=0.012 * wave(p, 2, 0.1) - 0.005, pitch=1.5 * wave(p, 2), roll=3 * wave(p, 1, 0.1),
         yaw=4 * wave(p, 1, 0.35), spine=2 * wave(p, 2, 0.25), head=(6, -5 * wave(p, 1, 0.35), 0),
         tail=(14, 16 * wave(p, 1, 0.1)))
    plant_limbs(rig, off)


def anim_gallop(p, rig):
    held_scale(rig, 0)
    off = {}
    # fore pair lands, then the hind legs swing through and land just behind the hands
    for limb, ph in (("LF", 0.0), ("RF", -0.08), ("LH", -0.5), ("RH", -0.58)):
        reach = 0.14 if limb[1] == "F" else 0.07
        lift = 0.1 if limb[1] == "F" else 0.07
        dy, dz = gait(p + ph, GALLOP_DUTY, GALLOP_EXC + reach, lift)
        off[limb] = (dy - (0.05 if limb[1] == "F" else 0.08), dz)
    pitch = -9 * wave(p, 1, -0.15)                                  # front rises as the hind legs push
    flex = 9 * wave(p, 1, 0.1)                                      # spine gathers / extends
    lift = 0.035 * max(0.0, wave(p, 2, -0.2))                      # two flight bounces per stride
    body(rig, z=lift, pitch=pitch, spine=flex, head=(4, 0, 0), tail=(30 + 10 * wave(p, 1, 0.2), 8 * wave(p, 1)))
    plant_limbs(rig, off)


def anim_throw(p, rig):
    r = THROW_RELEASE
    rear = track([(0, 0), (0.3, 1, ease_out), (0.7, 1), (0.92, 0, ease_in), (1, 0)], p)
    held_scale(rig, track([(0, 0), (0.12, 0), (0.28, 1, ease_out), (r, 1), (r + 0.001, 0), (1, 0)], p))
    lean = track([(0, 0), (0.3, 0), (0.45, -8), (r, 14, ease_out), (0.7, 10), (1, 0)], p)   # whips forward
    body(rig, z=0.05 * rear, y=0.04 * rear, pitch=-58 * rear + lean, spine=-8 * rear,
         head=(track([(0, 0), (0.45, -10), (r, 8), (1, 0)], p), 0, 0), tail=(-30 * rear + 15, 0))
    plant_limbs(rig)
    # right claw: fireball up behind the head, then hurled overhead and forward
    R = track([(0, (0, -0.1, -0.35)), (0.3, (-0.05, 0.05, 0.12)), (0.45, (-0.02, 0.16, 0.22)),
               (r, (-0.02, -0.3, 0.06), ease_out), (0.7, (0.0, -0.3, -0.2)), (1, (0, -0.1, -0.35))], p)
    L = track([(0, (0, -0.1, -0.35)), (0.3, (0.08, -0.16, -0.08)), (r, (0.12, -0.1, -0.02)), (0.7, (0.1, -0.15, -0.15)),
               (1, (0, -0.1, -0.35))], p)                         # off arm out for balance
    arm_to(rig, "R", 1 - rear, R, orient=1 - rear)
    arm_to(rig, "L", 1 - rear, L, orient=1 - rear)


def anim_slash(p, rig):
    held_scale(rig, 0)
    h = SLASH_HIT
    up = track([(0, 0), (0.3, 1, ease_out), (h, 0.7), (0.65, 0.4), (1, 0)], p)
    lunge = track([(0, 0), (0.3, 0.03), (h, -0.08, ease_out), (0.7, -0.06), (1, 0)], p)
    twist = track([(0, 0), (0.3, -18), (h, 22, ease_out), (0.7, 18), (1, 0)], p)
    body(rig, z=0.02 * up, y=lunge, pitch=-22 * up, yaw=twist, head=(0, -twist * 0.5, 0), tail=(20, -twist))
    plant_limbs(rig, {"LF": (lunge * 0.5, 0)})
    # right claw: raised up and out, then raked across the front and down
    R = track([(0, (-0.04, -0.08, -0.38)), (0.3, (-0.2, 0.0, 0.14)), (h, (0.08, -0.32, -0.12), ease_out),
               (0.65, (0.16, -0.22, -0.28)), (1, (-0.04, -0.08, -0.38))], p)
    w = track([(0, 1), (0.15, 0), (0.75, 0), (1, 1)], p)
    arm_to(rig, "R", w, R, orient=w)


def anim_hit(p, rig):
    held_scale(rig, 0)
    k = track([(0, 0), (0.15, 1, ease_out), (0.45, 0.6), (1, 0)], p)
    body(rig, z=0.03 * k, y=0.05 * k, pitch=-16 * k, roll=6 * k, head=(-22 * k, 10 * k, -8 * k), tail=(40 * k + 10, 0))
    plant_limbs(rig, {"LF": (0.03 * k, 0.04 * k), "RF": (0.02 * k, 0.05 * k)})


def anim_death(p, rig):
    held_scale(rig, 0)
    jolt = track([(0, 0), (0.15, 1, ease_out), (0.35, 0), (1, 0)], p)
    fall = track([(0, 0), (0.15, 0), (0.6, 1, ease_in), (0.7, 0.92), (0.8, 1), (1, 1)], p)   # small bounce
    body(rig, z=0.04 * jolt - 0.07 * fall, pitch=-25 * jolt + 6 * fall, roll=-80 * fall,
         head=(-20 * jolt + 25 * fall, 0, -15 * fall), tail=(20 - 30 * fall, 30 * fall))
    plant_limbs(rig)
    limp = track([(0, 0), (0.2, 0), (0.55, 1), (1, 1)], p)
    for pb in rig.pose.bones:
        for c in pb.constraints:
            c.influence = 1 - limp                                 # limbs go slack as it falls


GREMLIN_ANIMS = {
    "idle": (anim_idle, 1.6), "walk": (anim_walk, WALK_T), "gallop": (anim_gallop, GALLOP_T),
    "throw": (anim_throw, 1.0), "slash": (anim_slash, 0.6), "hit": (anim_hit, 0.4), "death": (anim_death, 1.0),
}

if not globals().get("GREMLIN_LIBRARY_ONLY"):
    print(f"WALK_SPEED {WALK_SPEED:.3f} m/s, GALLOP_SPEED {GALLOP_SPEED:.3f} m/s")
    build_enemy("Gremlin", BONES, IK_CHAINS, ORIENT, build_model, part_group, GREMLIN_ANIMS, OUT,
                os.path.join(REPO, "blender", "enemies", "gremlin.blend"))
