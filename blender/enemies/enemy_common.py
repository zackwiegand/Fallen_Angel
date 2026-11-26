"""Shared Blender pipeline for enemy characters (exec'd by each enemy script, e.g. gremlin.py).

An enemy script provides:
    BONES     {name: (head, tail, parent)} rig-space rest bones, Z-up, the creature faces -Y,
              its left is +X (".L"); a "root" bone at the origin carries the whole body.
    IK_CHAINS [(ik_bone, target_point, pole_point)] two-bone IK chains ending at ik_bone's tail
              (e.g. forearm -> wrist), with targets/poles in rig space.
    ORIENT    [bone] bones whose rig-space orientation is held at rest by a Copy Rotation
              (hands / feet stay flat while the IK chain above them moves). Influence is animatable.
    build_model(rig)   makes the meshes and bind()s each one rigidly to a bone (rest pose).
    ANIMS     {name: (frame_fn(p, ctrl), duration_s)}; frame_fn poses the control rig for phase p.

The pipeline: control rig (IK + orient constraints, posed procedurally) -> per-frame bone matrices
copied as keyframes onto a constraint-free export rig at SAMPLE_FPS -> one rigidly skinned mesh
(vertex group per bone, weight 1, vertex colour "part" per bone group) -> GLB with every clip as an
NLA track. Godot imports it like rocker_base.glb (Toon materials swapped by material name).

Mesh helpers (add, loft, limb, bind, toon_material, reset_scene) come from the sprite-poc scripts,
which stay untouched.
"""
import bpy, math, os
from mathutils import Vector, Matrix

SRC = "/Users/patriciabrewer/dev/sprite-poc"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(REPO, "assets")
SAMPLE_FPS = 30

for _f in ("pipeline.py", "rocker.py", "anims.py"):     # helpers only; their builders are not called
    exec(open(f"{SRC}/{_f}").read())


# ---------------------------------------------------------------- mesh helpers (enemy-specific)
def ring_y(y, z, w, h, n=7, x0=0.0, flat=0.0):
    """Body cross-section across the creature's length: ellipse in the XZ plane at depth y.
    flat > 0 flattens the belly (lower half)."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n
        dz = math.cos(a) * h
        if dz < 0:
            dz *= 1.0 - flat
        pts.append((x0 + math.sin(a) * w, y, z + dz))
    return pts


def tube(name, pts, radii, mat, n=5, twist=0.0, jitter=None):
    """Faceted tube through a polyline with per-point radii (horns, tails). Each ring is
    perpendicular to the local direction; twist (deg/ring) rotates the facets for a gnarled look;
    jitter = per-point (side, up) offsets that make the path knotty."""
    P = [Vector(p) for p in pts]
    rings = []
    for i, p in enumerate(P):
        d = (P[min(i + 1, len(P) - 1)] - P[max(i - 1, 0)]).normalized()
        ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
        side = d.cross(ref).normalized()
        up = side.cross(d).normalized()
        if jitter:
            p = p + side * jitter[i][0] + up * jitter[i][1]
        ring = []
        for k in range(n):
            a = 2 * math.pi * k / n + math.radians(twist * i)
            ring.append(tuple(p + radii[i] * (math.cos(a) * side + math.sin(a) * up)))
        rings.append(ring)
    return loft(name, rings, mat)


# ---------------------------------------------------------------- rig
def build_rig(name, bones):
    rig = bpy.data.objects.new(name, bpy.data.armatures.new(name + "Skeleton"))
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode='EDIT')
    eb = rig.data.edit_bones
    for n, (h, t, _) in bones.items():
        b = eb.new(n)
        b.head, b.tail, b.roll = h, t, 0
    for n, (_, _, p) in bones.items():
        if p:
            eb[n].parent = eb[p]
    bpy.ops.object.mode_set(mode='OBJECT')
    for pb in rig.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    return rig


def _empty(name, parent, loc=None, matrix=None):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.04
    bpy.context.collection.objects.link(e)
    e.parent = parent
    if matrix is not None:
        e.matrix_world = parent.matrix_world @ matrix
    else:
        e.location = loc
    return e


def add_constraints(rig, ik_chains, orient):
    """IK chains (targets IK.<bone>, poles Pole.<bone>) with auto-calibrated pole angles, and
    Copy Rotation orient locks (targets Orient.<bone>). Returns {bone: target empty}."""
    targets = {}
    for bone, tgt, pole in ik_chains:
        t = _empty(f"IK.{bone}", rig, tgt)
        p = _empty(f"Pole.{bone}", rig, pole)
        c = rig.pose.bones[bone].constraints.new('IK')
        c.name = "IK"
        c.target, c.pole_target, c.chain_count = t, p, 2
        c.use_stretch = True
        for b in (bone, rig.pose.bones[bone].parent.name):
            rig.pose.bones[b].ik_stretch = 0.05
        c.pole_angle = _calibrate_pole(rig, bone, c)
        targets[bone] = t
    for bone in orient:
        e = _empty(f"Orient.{bone}", rig, matrix=rig.data.bones[bone].matrix_local)
        c = rig.pose.bones[bone].constraints.new('COPY_ROTATION')
        c.name = "Orient"
        c.target = e
    return targets


def _calibrate_pole(rig, bone, c):
    """Pole angle that keeps the chain's middle joint where it is at rest (target at rest)."""
    rest = rig.data.bones[bone].head_local.copy()
    best = (1e9, 0.0)
    for k in range(72):
        c.pole_angle = math.radians(k * 5 - 180)
        bpy.context.view_layer.update()
        err = (rig.pose.bones[bone].head - rest).length
        best = min(best, (err, c.pole_angle))
    return best[1]


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix()
        for c in pb.constraints:
            c.influence = 1.0
    bpy.context.view_layer.update()


def rot_pivot(rig, bone, axis, deg, pivot=None):
    """Rotate a pose bone about a rig-space axis through its head (or pivot)."""
    if not deg:
        return
    pb = rig.pose.bones[bone]
    c = Vector(pivot) if pivot is not None else pb.head.copy()
    R = Matrix.Translation(c) @ Matrix.Rotation(math.radians(deg), 4, axis) @ Matrix.Translation(-c)
    pb.matrix = R @ pb.matrix
    bpy.context.view_layer.update()


# ---------------------------------------------------------------- mesh
PART_COLORS = {"body": (1, 0, 0), "leg.L": (1, 1, 0), "leg.R": (0, 1, 1), "arm.L": (0, 1, 0), "arm.R": (0, 0, 1)}


def skin_parts(ctrl, rig, name, part_group):
    """Merge every bone-parented mesh of the control rig into one mesh, rigidly skinned to the
    export rig (vertex group = parent bone)."""
    dg = bpy.context.evaluated_depsgraph_get()
    pieces = []
    for o in list(ctrl.children):
        if o.type != 'MESH' or o.parent_type != 'BONE':
            continue
        me = bpy.data.meshes.new_from_object(o.evaluated_get(dg))
        me.transform(o.matrix_world)
        col = me.color_attributes.new("part", 'BYTE_COLOR', 'CORNER')
        c = PART_COLORS.get(part_group(o.parent_bone), (1, 0, 0))
        for d in col.data:
            d.color = (*c, 1)
        p = bpy.data.objects.new(o.name + "_x", me)
        bpy.context.collection.objects.link(p)
        p.vertex_groups.new(name=o.parent_bone).add(range(len(me.vertices)), 1.0, 'REPLACE')
        pieces.append(p)
        o.hide_set(True)
    with bpy.context.temp_override(active_object=pieces[0], selected_editable_objects=pieces):
        bpy.ops.object.join()
    m = pieces[0]
    m.name = m.data.name = name
    m.parent = rig
    m.modifiers.new("Armature", 'ARMATURE').object = rig
    return m


# ---------------------------------------------------------------- baking
def bake(ctrl, rig, anims):
    """Sample each clip's frame function on the control rig and key the resulting bone matrices
    (rig space) onto the export rig, one NLA track per clip."""
    bpy.context.scene.render.fps = SAMPLE_FPS
    bpy.context.scene.render.fps_base = 1.0
    rig.animation_data_create()
    for name, (fn, dur) in anims.items():
        act = bpy.data.actions.new(name)
        rig.animation_data.action = act
        prev = {}
        frames = round(dur * SAMPLE_FPS)
        for k in range(frames + 1):
            reset_pose(ctrl)
            fn(k / frames, ctrl)
            bpy.context.view_layer.update()
            target = {pb.name: pb.matrix.copy() for pb in ctrl.pose.bones}
            for pb in rig.pose.bones:     # parents come first
                rest = pb.bone.matrix_local
                if pb.parent:
                    prest = pb.parent.bone.matrix_local
                    basis = (target[pb.parent.name] @ prest.inverted() @ rest).inverted() @ target[pb.name]
                else:
                    basis = rest.inverted() @ target[pb.name]
                loc, q, sc = basis.decompose()
                if pb.name in prev and prev[pb.name].dot(q) < 0:
                    q.negate()
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


def export(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_apply=True,
        export_yup=True, export_skins=True, export_def_bones=False,
        export_vertex_color='ACTIVE', export_all_vertex_colors=False,
        export_animations=True, export_animation_mode='NLA_TRACKS',
        export_force_sampling=True, export_anim_slide_to_zero=True,
        export_optimize_animation_size=False, export_image_format='NONE')
    print("wrote", path)


# ---------------------------------------------------------------- gait helpers
def gait(u, duty, excursion, lift):
    """In-place locomotion for one limb at cycle phase u: (dy, dz) offset from its rest contact
    point. Stance (u < duty): slides back from -excursion/2 to +excursion/2 (-Y is forward).
    Swing: eases forward again, lifted by `lift` at mid-swing. Ground speed = excursion / (duty * T)."""
    u %= 1.0
    if u < duty:
        return -excursion / 2 + excursion * u / duty, 0.0
    s = (u - duty) / (1 - duty)
    return excursion / 2 - excursion * ease(s), lift * math.sin(math.pi * s)


def build_enemy(name, bones, ik_chains, orient, build_model, part_group, anims, out_path, blend_path=None):
    reset_scene()
    ctrl = build_rig(name + "Ctrl", bones)
    build_model(ctrl)
    add_constraints(ctrl, ik_chains, orient)
    rig = build_rig(name, bones)
    reset_pose(ctrl)
    mesh = skin_parts(ctrl, rig, name + "Body", part_group)
    bake(ctrl, rig, anims)
    export(out_path, [rig, mesh])
    if blend_path:
        bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    return ctrl, rig
