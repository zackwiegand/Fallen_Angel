"""Export the metal rocker from the sprite-poc Blender scripts to modular glTF for Godot.

Run headless (no Blender UI needed):
    blender -b -P blender/export_gltf.py

What it does
  1. Builds the rocker exactly as sprite-poc does (rocker.py + anims.py + guitar_reaper.py),
     plus a plain under-layer (shirt, trousers, bare feet) so the body still reads with
     armour or boots unequipped.
  2. Splits every bone-parented part into a gear SLOT (body / armor / boots) and merges each
     slot into one mesh, rigidly skinned (weight 1) to the bone the part was parented to.
  3. Builds the export rig: the sprite-poc bones + "root" (carries the vertical lift / foot
     planting) + "guitar" (carries the prop placement, so any guitar follows it).
  4. Bakes idle / walk / strum / swing by running the procedural animation (IK hands on the
     guitar sockets, foot planting, foot roll) per sample and copying the resulting bone
     matrices into keyframes on the export rig.
  5. Writes, into assets/:
        rocker/rocker_base.glb          rig + body mesh + all animations
        gear/armor_gothic_plate.glb     rig + armour mesh (no animations)
        gear/boots_combat.glb           rig + boots mesh
        gear/guitar_<model>.glb         static guitar mesh, origin at the body centre
     Every skinned gear file carries the same skeleton, so Godot can bind any of them to the
     base skeleton by bone name and the base animations drive them all.

Guitars must keep the sprite-poc GUITAR CONTRACT (same socket positions), because the hands
were baked against the reaper's sockets.
"""
import bpy, math, os
from mathutils import Vector, Matrix

SRC = "/Users/patriciabrewer/dev/sprite-poc"
ASSETS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
SAMPLE_FPS = 30
GUITARS = ["reaper", "battleaxe"]

for _f in ("pipeline.py", "rocker.py", "anims.py"):
    exec(open(f"{SRC}/{_f}").read())

# ---------------------------------------------------------------- front-view tuning
# sprite-poc posed the arms for its diagonal camera (front-right of the character). The game camera
# is front-on (CLAUDE.md), so these override sprite-poc without editing its files.
FRET_X = 0.68                                    # fretting hand higher up the neck (sprite-poc: 0.5)
DEFAULT_POLE["R"] = Vector((-1.1, 0.2, 1.25))    # picking elbow out to the side (was forward, read as torqued in)
STRUM_ELBOW_LIFT = Vector((-0.45, 0.15, 0.8))    # wind-up raises the elbow up and out (was up and forward)

_sprite_poc_strum = anim_strum


def anim_strum(p):
    f = _sprite_poc_strum(p)
    up = f.pop("pole_lift", {}).get("R", 0.0)
    f["poles"] = {"L": DEFAULT_POLE["L"], "R": DEFAULT_POLE["R"] + STRUM_ELBOW_LIFT * up}
    return f


# ---------------------------------------------------------------- cast: fireball (new, Godot only)
# Raise the guitar like a staff (neck up), then thrust it forward flat, headstock leading; the
# fireball leaves the headstock at the thrust (CAST_RELEASE). Built as idle frame 0 + additive body
# motion, and starts/ends on the idle rest pose, so idle <-> cast blends cleanly.
CAST_RELEASE = 0.45


def _placement(pos, neck, face):
    """Guitar matrix (rig space) from body-centre position, neck direction (+X) and face normal (-Y)."""
    x = Vector(neck).normalized()
    y = -Vector(face)
    y = (y - x * y.dot(x)).normalized()
    m = Matrix((x, y, x.cross(y))).transposed().to_4x4()
    m.translation = Vector(pos)
    return m


CAST_KEYS = [   # phase, guitar placement (None = idle rest hold), easing into the next key
    (0.0, None, ease),
    (0.3, _placement((-0.25, -0.3, 1.25), (0.25, -0.35, 0.9), (0.0, -1.0, 0.2)), ease_in),   # raise
    (CAST_RELEASE, _placement((-0.1, -0.2, 1.2), (0.12, -1.0, 0.12), (0.0, 0.2, 1.0)), ease_out),  # thrust
    (0.65, _placement((-0.1, -0.12, 1.22), (0.12, -1.0, 0.16), (0.0, 0.2, 1.0)), ease),        # recoil hold
    (1.0, None, ease),
]
CAST_GRIP = [(0, FRET_X), (0.3, 0.5), (CAST_RELEASE, 0.36), (0.65, 0.36), (1.0, FRET_X)]   # left hand on neck
CAST_LEAN = [(0, 0), (0.3, -8), (CAST_RELEASE, 16, ease_out), (0.65, 14), (1, 0)]
CAST_TWIST = [(0, 0), (0.3, 10), (CAST_RELEASE, -10, ease_out), (0.65, -8), (1, 0)]
CAST_HEAD = [(0, 0), (0.3, 4), (CAST_RELEASE, -12), (0.65, -10), (1, 0)]       # eyes stay on the target
CAST_KNEE = [(0, 0), (0.3, -4), (CAST_RELEASE, 10, ease_out), (0.65, 10), (1, 0)]   # sink into the thrust


def _blend(a, b, u):
    la, qa, _ = a.decompose()
    lb, qb, _ = b.decompose()
    return Matrix.Translation(la.lerp(lb, u)) @ qa.slerp(qb, u).to_matrix().to_4x4()


def anim_cast(p):
    f = anim_idle(0.0)
    rest = f["guitar"]
    for k0, k1 in zip(CAST_KEYS, CAST_KEYS[1:]):
        if p <= k1[0]:
            u = k0[2]((p - k0[0]) / (k1[0] - k0[0]))
            f["guitar"] = _blend(k0[1] or rest, k1[1] or rest, u)
            break
    lean, twist, knee = track(CAST_LEAN, p), track(CAST_TWIST, p), track(CAST_KNEE, p)
    f["rots"] = f["rots"] + [
        ("spine", 'X', lean), ("chest", 'Z', twist), ("head", 'X', track(CAST_HEAD, p)),
        ("thigh.L", 'X', -0.6 * knee), ("shin.L", 'X', 1.3 * knee), ("foot.L", 'X', -0.7 * knee),
        ("thigh.R", 'X', -0.6 * knee), ("shin.R", 'X', 1.3 * knee), ("foot.R", 'X', -0.7 * knee),
    ]
    f["plant"] = True                              # boots stay on the ground as the knees bend (idle: low sole = 0)
    f["hands"] = {"L": ("local", (track(CAST_GRIP, p), 0.0, -0.08)), "R": ("strum", STRUM_REST)}
    lean0, twist0 = f["body"]
    f["body"] = (lean0 + lean, twist0 + twist)
    return f


ANIMS["cast"] = (lambda p, socks: anim_cast(p), 12, 14, 128)


# ---------------------------------------------------------------- run: heavy charge (new, Godot only)
# The walk's old warrior breaking into a charge: same hunch, rigid boots and toe-out, but leaning into
# it with a longer stride and a short flight phase. Running mechanics applied:
#  - each leg: contact -> compression ("down", knee loads) -> push-off at ~35% -> flight -> swing
#    with a high heel tuck -> reach for the next contact. Stance is shorter than swing, so the
#    thigh curve is time-warped (back extreme at toe-off, not at 50%).
#  - the body is lowest just after contact and highest mid-flight; flight is short (heavy man).
#  - older runner: limited hip extension, knees never straight, a ponderous cadence.
# The guitar stays in the playing hold (hands on the sockets) and bounces a beat behind the body,
# rocking with the stride, so the arms pump with it. Contacts at phase 0 (L) and 0.5 (R), the same
# leg phases as the walk, so rocker_rig.gd can cross-fade walk <-> run in step.
RUN_STRIDE = (38, 22)            # thigh forward / backward swing (deg): weak hip extension
RUN_TUCK = 58                    # swing knee fold (deg); a sprinter's high heel tuck reads as kneeling at sprite size
RUN_TOE_OFF = 0.36               # stance share of the leg cycle
RUN_LEAN = 12                    # forward lean on top of the hunch (walk: 2)
RUN_FOOT_PITCH = [(0, -12), (0.08, 0), (0.24, 0), (0.4, 34), (0.55, 30), (0.78, 4), (0.92, -10), (1.0, -12)]
RUN_LIFT = [(0, 0.0), (0.12, -0.055), (0.36, 0.0, linear), (0.68, 0.065), (1.0, 0.0)]   # per step


def _run_warp(q):
    """Leg phase -> gait angle: stance (0..TOE_OFF) covers the first half of the swing curve."""
    if q < RUN_TOE_OFF:
        return 0.5 * q / RUN_TOE_OFF
    return 0.5 + 0.5 * (q - RUN_TOE_OFF) / (1.0 - RUN_TOE_OFF)


def leg_run(side, q, pelvis_yaw=0.0):
    q %= 1.0
    sgn = 1 if side == "L" else -1
    c = math.cos(2 * math.pi * _run_warp(q))
    thigh = -c * (RUN_STRIDE[0] if c > 0 else RUN_STRIDE[1])          # forward at contact
    if q < RUN_TOE_OFF:     # stance: loads on contact, drives off nearly (never fully) straight
        u = q / RUN_TOE_OFF
        knee = 22 + (12 - 22) * u + 18 * bump(q - 0.12, 0.07)
    else:                   # swing: heel tucks up behind, then the shin reaches for the ground
        u = (q - RUN_TOE_OFF) / (1.0 - RUN_TOE_OFF)
        knee = 12 + 10 * u + RUN_TUCK * math.sin(math.pi * min(u / 0.8, 1.0)) ** 1.5
    foot = -(thigh + knee) + track(RUN_FOOT_PITCH, q)
    return [(f"thigh.{side}", 'X', thigh), (f"thigh.{side}", 'Y', -4 * sgn),
            (f"shin.{side}", 'X', knee), (f"foot.{side}", 'X', foot),
            (f"foot.{side}", 'Z', TOE_OUT * sgn - pelvis_yaw)]


def anim_run(p):
    c = math.cos(2 * math.pi * p)
    s2 = (2 * p) % 1.0                                    # step phase (both steps alike)
    lift = track(RUN_LIFT, s2)
    dip = -lift / 0.055 if lift < 0 else 0.0              # 0..1 compression
    lean = RUN_LEAN + 4 * dip
    twist = 9 * c
    yaw = -8 * c
    rots = HUNCH + [
        ("pelvis", 'Z', yaw), ("pelvis", 'Y', 3 * math.sin(2 * math.pi * p)),
        ("spine", 'X', lean), ("chest", 'Z', twist + 6 * c),
        ("head", 'X', -0.7 * lean + 3 * dip), ("head", 'Z', -5 * c),   # eyes stay on the road ahead
    ] + leg_run("L", p, yaw) + leg_run("R", p + 0.5, yaw)
    lag = track(RUN_LIFT, (s2 - 0.1) % 1.0)              # strap-hung guitar bounces a beat late
    guitar = hold_placement(lean, twist, dz=0.5 * lag, pitch=5 * math.sin(2 * math.pi * p), roll=3 * dip)
    return dict(rots=rots, plant=True, lift=lift, guitar=guitar, hands=PLAY_GRIP, body=(lean + 16, twist))


ANIMS["run"] = (lambda p, socks: anim_run(p), 12, 16, 128)    # 0.75 s cycle


# ---------------------------------------------------------------- gear slots
ARMOR_PARTS = ("Fauld", "Belt", "Buckle", "Plackart", "Placket", "Cuirass", "Gorget", "Pauldron",
               "Lame", "Spike", "Armband", "Stud", "Bracer", "Cuisse", "Tasset", "Poleyn", "Greave")
BOOT_PARTS = ("BootShaft", "BootCuff", "Vamp", "Heel", "SoleMid", "Strap", "ToeBox", "ToeCap", "SoleFront")


def slot_of(obj):
    if obj.name.startswith(BOOT_PARTS):
        return "boots"
    if obj.name.startswith(ARMOR_PARTS):
        return "armor"
    return "body"


# part groups as vertex colours, for a later object-ID / inner-outline pass in Godot
PART_COLORS = {"body": (1, 0, 0), "leg.L": (1, 1, 0), "leg.R": (0, 1, 1), "arm.L": (0, 1, 0), "arm.R": (0, 0, 1)}


def build_underlayer(arm):
    """Plain clothes + skin hidden under the armour/boots, visible when those slots are empty.
    Kept slightly inside the armour so it never pokes through."""
    toon_material("Cloth", (0.02, 0.006, 0.006), (0.08, 0.025, 0.022), (0.2, 0.07, 0.06))

    def B(bone, name, obj):
        bind(arm, obj, bone, name)

    B("pelvis", "UnderHips", loft("UnderHips", [keel(0.9, 0.33, 0.24, 0.22), keel(1.17, 0.31, 0.23, 0.21)], "Cloth"))
    B("spine", "UnderBelly", loft("UnderBelly", [keel(1.15, 0.31, 0.23, 0.21), keel(1.47, 0.34, 0.25, 0.21)], "Cloth"))
    B("chest", "UnderChest", loft("UnderChest", [keel(1.45, 0.34, 0.25, 0.21), keel(1.62, 0.42, 0.28, 0.24),
                                                 keel(1.78, 0.45, 0.28, 0.25), keel(1.94, 0.3, 0.18, 0.18)], "Cloth"))
    for s, x in (("L", 1), ("R", -1)):
        B(f"upper_arm.{s}", f"UnderShoulder.{s}", add("uv_sphere", (0.49 * x, 0.02, 1.76), (0.14, 0.14, 0.13),
                                                     mat="Skin", smooth=True, segments=8, ring_count=5))
        B(f"thigh.{s}", f"UnderThigh.{s}", limb(f"UnderThigh.{s}", (0.215 * x, 0, 0.98), (0.228 * x, 0, 0.58), 0.14, 0.115, "Cloth", n=8, ridge=0))
        B(f"shin.{s}", f"UnderKnee.{s}", add("uv_sphere", (0.23 * x, -0.01, 0.56), (0.11, 0.11, 0.1), mat="Cloth", segments=8, ring_count=5))
        B(f"shin.{s}", f"UnderShin.{s}", limb(f"UnderShin.{s}", (0.232 * x, 0, 0.56), (0.25 * x, 0, 0.16), 0.11, 0.09, "Cloth", n=8, ridge=0))
        bx = 0.25 * x
        B(f"shin.{s}", f"UnderAnkle.{s}", limb(f"UnderAnkle.{s}", (bx, 0, 0.18), (bx, 0, 0.09), 0.075, 0.07, "Skin", n=8, ridge=0, smooth=True))
        B(f"foot.{s}", f"UnderFoot.{s}", loft(f"UnderFoot.{s}", [boot_section(bx, 0.08, 0.06, 0.012, 0.12),
                                                                boot_section(bx, -0.13, 0.075, 0.012, 0.08)], "Skin"))
        B(f"toe.{s}", f"UnderToes.{s}", loft(f"UnderToes.{s}", [boot_section(bx, -0.13, 0.075, 0.012, 0.08),
                                                               boot_section(bx, -0.27, 0.06, 0.012, 0.055)], "Skin"))


# ---------------------------------------------------------------- export rig
EXTRA_BONES = {"root": ((0, 0, 0), (0, 0.3, 0), None), "guitar": ((0, 0, 0), (0, 0.3, 0), "root")}


def build_export_rig():
    """sprite-poc bones (same rest frames) under a root bone, plus the guitar prop bone.
    root/guitar rest = identity, so their pose matrices are plain rig-space transforms."""
    rig = bpy.data.objects.new("Rocker", bpy.data.armatures.new("RockerSkeleton"))
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    allb = {**EXTRA_BONES, **BONES}
    for n, (h, t, _) in allb.items():
        b = eb.new(n); b.head, b.tail, b.roll = h, t, 0
    for n, (_, _, p) in allb.items():
        eb[n].parent = eb[p or "root"] if n != "root" else None
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return rig


def slot_meshes(src_arm, rig):
    """Merge the bone-parented parts per slot into one rigidly-skinned mesh on the export rig."""
    dg = bpy.context.evaluated_depsgraph_get()
    pieces = {}
    for o in list(src_arm.children):
        if o.type != 'MESH' or o.parent_type != 'BONE':
            continue
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))   # bevel modifiers applied
        me.transform(o.matrix_world)                                # rest pose, rig space
        col = me.color_attributes.new("part", 'BYTE_COLOR', 'CORNER')
        c = PART_COLORS[part_group(o)]
        for d in col.data:
            d.color = (*c, 1)
        p = bpy.data.objects.new(o.name + "_x", me)
        bpy.context.collection.objects.link(p)
        p.vertex_groups.new(name=o.parent_bone).add(range(len(me.vertices)), 1.0, 'REPLACE')
        pieces.setdefault(slot_of(o), []).append(p)
    out = {}
    for slot, objs in pieces.items():
        with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs):
            bpy.ops.object.join()
        m = objs[0]
        m.name = m.data.name = {"body": "Body", "armor": "Armor", "boots": "Boots"}[slot]
        m.parent = rig
        m.modifiers.new("Armature", 'ARMATURE').object = rig
        out[slot] = m
    return out


# ---------------------------------------------------------------- baking
def anim_phase(name, t):
    """Animation time (s) -> phase. Swing frames use sprite-poc's path-spaced return timing."""
    _, n, fps, _ = ANIMS[name]
    if name != "swing":
        return min(t * fps / n, 1.0)
    i = t * fps
    k = min(int(i), n - 1)
    p0, p1 = phase_of(name, k), (phase_of(name, k + 1) if k + 1 < n else 1.0)
    return p0 + (p1 - p0) * min(i - k, 1.0)


def bake(src_arm, guitar, socks, rig):
    bpy.context.scene.render.fps = SAMPLE_FPS     # keys are placed at SAMPLE_FPS frames per second
    bpy.context.scene.render.fps_base = 1.0
    rig.animation_data_create()
    for name, (fn, n, fps, _) in ANIMS.items():
        dur = n / fps
        act = bpy.data.actions.new(name)
        rig.animation_data.action = act
        prev = {}
        frames = round(dur * SAMPLE_FPS)
        for k in range(frames + 1):
            apply_frame(src_arm, guitar, socks, fn(anim_phase(name, k / SAMPLE_FPS), socks))
            src_arm.rotation_euler.z = 0
            bpy.context.view_layer.update()
            target = {"root": Matrix.Translation(src_arm.matrix_world.translation), "guitar": guitar.matrix_world.copy()}
            for b in BONES:
                target[b] = src_arm.matrix_world @ src_arm.pose.bones[b].matrix
            for pb in rig.pose.bones:     # parents come first in pose.bones order
                rest = pb.bone.matrix_local
                if pb.parent:
                    prest = pb.parent.bone.matrix_local
                    basis = (target[pb.parent.name] @ prest.inverted() @ rest).inverted() @ target[pb.name]
                else:
                    basis = rest.inverted() @ target[pb.name]
                loc, q, sc = basis.decompose()
                if pb.name in prev and prev[pb.name].dot(q) < 0:
                    q.negate()            # keep quaternions continuous for slerp
                prev[pb.name] = q
                pb.location, pb.rotation_quaternion, pb.scale = loc, q, sc
                for path in ("location", "rotation_quaternion", "scale"):
                    pb.keyframe_insert(path, frame=k)
        track = rig.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        rig.animation_data.action = None
        print(f"baked {name}: {frames + 1} samples, {dur:.3f}s")
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix()


# ---------------------------------------------------------------- export
def export(path, objs, animations):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_apply=True,
        export_yup=True, export_skins=True, export_def_bones=False,
        export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_animations=animations, export_animation_mode='NLA_TRACKS',
        export_force_sampling=True, export_anim_slide_to_zero=True,
        export_optimize_animation_size=False, export_image_format='NONE')
    print("wrote", path)


def build_guitar_mesh(model):
    """Guitar parts merged into one static mesh (origin = body centre); sockets kept as empties."""
    exec(open(f"{SRC}/guitar_{model}.py").read(), globals())
    root = build_guitar(f"G_{model}")
    bpy.context.view_layer.update()
    parts = [c for c in root.children if c.type == 'MESH']
    socks = [c for c in root.children if "socket_" in c.name]
    for p in parts:
        mw = p.matrix_world.copy()
        p.parent = None
        p.matrix_world = mw
    with bpy.context.temp_override(active_object=parts[0], selected_editable_objects=parts):
        bpy.ops.object.join()
    g = parts[0]
    g.name = g.data.name = f"guitar_{model}"
    for s in socks:
        if s.name.endswith("socket_fret"):
            s.location.x = FRET_X
        s.parent = g
        s.name = s.name.split("socket_")[1] + "_socket"
    bpy.data.objects.remove(root)
    return g, socks


def main():
    reset_scene()
    rocker_materials()
    src = build_armature("SrcRig")
    build_body(src)
    build_underlayer(src)
    exec(open(f"{SRC}/guitar_reaper.py").read(), globals())
    guitar = build_guitar("Guitar")
    guitar.parent = src
    socks = {c.name.split("socket_")[1]: c for c in guitar.children if "socket_" in c.name}
    socks["fret"].location.x = FRET_X

    rig = build_export_rig()
    reset_pose(src)
    src.location = (0, 0, 0)
    bpy.context.view_layer.update()
    slots = slot_meshes(src, rig)
    bake(src, guitar, socks, rig)

    export(f"{ASSETS}/rocker/rocker_base.glb", [rig, slots["body"]], True)
    export(f"{ASSETS}/gear/armor_gothic_plate.glb", [rig, slots["armor"]], False)
    export(f"{ASSETS}/gear/boots_combat.glb", [rig, slots["boots"]], False)

    for o in [guitar, *guitar.children_recursive]:
        o.hide_set(True)
    for model in GUITARS:
        g, gs = build_guitar_mesh(model)
        export(f"{ASSETS}/gear/guitar_{model}.glb", [g, *gs], False)
        for o in (g, *gs):     # remove so the next guitar's sockets keep their plain names
            bpy.data.objects.remove(o)
    bpy.ops.wm.save_as_mainfile(filepath=f"{ASSETS}/../blender/rocker_export.blend")


if not globals().get("EXPORT_LIBRARY_ONLY"):
    main()
