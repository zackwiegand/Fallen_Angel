"""Effect pedals: procedural models exported as static glTF for the 3D -> pixel pipeline.

    blender -b -P blender/pedals/build_pedals.py

Writes assets/pedals/pedal_<id>.glb (+ blender/pedals/pedals.blend for inspection), then run
`godot --headless --path . --import`. Godot swaps the imported materials by name for Toon.PALETTE
entries (scripts/toon.gd), so every material name used here needs a palette entry there.

PEDAL CONTRACT (every pedal file):
  - Origin = centre of the base on the ground. Blender axes: +Z up, the footswitch edge faces -Y
    (glTF/Godot +Z, toward the camera when the pedal faces it), +X = the pedal's right.
  - One merged static mesh named "pedal_<id>" plus two Empties "jack_in" (the pedal's right side,
    like real pedals) and "jack_out" (left side) at the jack tips: the cable attach points.
  - The status LED uses a "Led*" material; PedalView swaps it for "<name>Off" when bypassed.
  - Units are the game's: 1 px = 3/80 m (player.gd METRES_PER_PX). Sizes are exaggerated far past
    real pedals so knobs / footswitch / LED stay 2-3 px at sprite size (about 16 px wide).

Reference cues (original models; parody brands, no real logos):
  CHIEF "CD-3 Digital Delay" (after the classic compact white delay stompbox):
    - compact upright box, white enclosure, a rear deck carrying a row of 4 black knobs
    - big hinged pedal plate covering the front two thirds, black rubber pad on its front half
    - blue model band printed across the plate, small red check LED on the deck, side jacks
  Skyman "Phaser-R" (after a mid-size boutique purple phaser):
    - wider, flatter box with rounded edges, dark anodized purple (shiny -> speculars shimmer)
    - 6 silver knobs in two rows of three (the toggles between them are dropped: 1 px noise)
    - two chrome stomp switches on the front edge, each with an LED above it, lilac label strip
"""
import bpy, bmesh, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, "assets", "pedals")

# name: (dark, mid, lite) preview colours only; the game reads Toon.PALETTE by material name
MATERIALS = {
    "ChiefWhite": (0.25, 0.27, 0.3), "ChiefBlue": (0.02, 0.1, 0.5), "Rubber": (0.01, 0.01, 0.01),
    "KnobBlack": (0.02, 0.02, 0.02), "Chrome": (0.5, 0.5, 0.52), "LedRed": (1.0, 0.02, 0.01),
    "SkymanPurple": (0.12, 0.03, 0.25), "SkymanLilac": (0.5, 0.35, 0.8), "KnobSilver": (0.6, 0.6, 0.62),
    "LedViolet": (0.8, 0.3, 1.0),
}


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for name, col in MATERIALS.items():
        m = bpy.data.materials.new(name)
        m.diffuse_color = (*col, 1.0)


def _finish(o, mat, bevel=0.0):
    o.data.materials.append(bpy.data.materials[mat])
    if bevel > 0:
        mod = o.modifiers.new("Bevel", 'BEVEL')
        mod.width = bevel
        mod.segments = 1            # chamfer: one crisp facet catches a highlight band
        mod.limit_method = 'ANGLE'
    return o


def box(name, x0, x1, y0, y1, z0, z1, mat, bevel=0.0, front_drop=0.0):
    """Axis-aligned box; front_drop lowers the -Y top edge (sloped pedal plate)."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    v = [bm.verts.new((x, y, z - (front_drop if (z == z1 and y == y0) else 0.0)))
         for z in (z0, z1) for y in (y0, y1) for x in (x0, x1)]
    for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
        bm.faces.new([v[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return _finish(o, mat, bevel)


def cylinder(name, loc, radius, depth, mat, axis='Z', verts=10, bevel=0.0):
    rot = {'Z': (0, 0, 0), 'X': (0, math.pi / 2, 0), 'Y': (math.pi / 2, 0, 0)}[axis]
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.name = name
    return _finish(o, mat, bevel)


def label(name, text, loc, size, mat, depth=0.006):
    """Flat raised text (only legible in close-ups; at sprite size it reads as a speckled band)."""
    bpy.ops.object.text_add(location=loc)
    o = bpy.context.active_object
    o.data.body = text
    o.data.size = size
    o.data.extrude = depth
    o.data.align_x = 'CENTER'
    o.data.align_y = 'CENTER'
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.active_object
    o.name = name
    o.data.materials.clear()
    return _finish(o, mat)


def jack(side, y, z, x_face, mat="Chrome"):
    """Side jack barrel + the cable attach Empty at its tip. side: +1 right (in), -1 left (out)."""
    length = 0.07
    cylinder(f"jack_{side}", (x_face + side * length / 2, y, z), 0.045, length, mat, axis='X', verts=8)
    e = bpy.data.objects.new("jack_in" if side > 0 else "jack_out", None)
    e.empty_display_size = 0.05
    e.location = (x_face + side * length, y, z)
    bpy.context.collection.objects.link(e)
    return e


def merge(name, objs):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target='MESH')          # applies the bevel modifiers
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = o.data.name = name
    for p in o.data.polygons:
        p.use_smooth = False
    return o


# ---------------------------------------------------------------- CHIEF CD-3 Digital Delay
def build_chief():
    W, D, H = 0.30, 0.46, 0.22                    # half width, half depth, body height
    parts = [
        box("base", -W, W, -D, D, 0.0, 0.03, "Rubber"),                         # dark sole line
        box("body", -W, W, -D, D, 0.03, H, "ChiefWhite", bevel=0.025),
        # rear deck lip behind the knobs, a little higher than the body
        box("deck", -W, W, 0.16, D, H, H + 0.04, "ChiefWhite", bevel=0.015),
        # hinged pedal plate over the front two thirds (a slope wouldn't survive 16 px; keep it flat)
        box("plate", -W + 0.015, W - 0.015, -D + 0.01, 0.14, H, H + 0.11, "ChiefWhite", bevel=0.02),
        # rubber pad on the plate's front half
        box("pad", -W + 0.05, W - 0.05, -D + 0.05, -0.13, H + 0.1, H + 0.14, "Rubber", bevel=0.01),
        # blue model band across the plate
        box("band", -W + 0.015, W - 0.015, -0.08, 0.08, H + 0.1, H + 0.13, "ChiefBlue"),
    ]
    for i, x in enumerate((-0.21, -0.07, 0.07, 0.21)):
        parts.append(cylinder(f"knob{i}", (x, 0.30, H + 0.08), 0.06, 0.08, "KnobBlack", verts=10))
        parts.append(cylinder(f"cap{i}", (x, 0.30, H + 0.125), 0.035, 0.01, "Chrome", verts=8))
    parts.append(box("led", -0.25, -0.17, 0.39, 0.45, H + 0.04, H + 0.08, "LedRed"))
    parts.append(label("brand", "CHIEF", (0.0, 0.0, H + 0.132), 0.085, "ChiefWhite"))
    socks = [jack(+1, 0.12, 0.13, W), jack(-1, 0.12, 0.13, -W)]
    parts += [o for o in bpy.data.objects if o.name.startswith("jack_") and o.type == 'MESH']
    return merge("pedal_chief_delay", parts), socks


# ---------------------------------------------------------------- Skyman Phaser-R
def build_skyman():
    W, D, H = 0.36, 0.40, 0.20
    parts = [
        box("base", -W, W, -D, D, 0.0, 0.03, "Rubber"),
        box("body", -W, W, -D, D, 0.03, H, "SkymanPurple", bevel=0.06),
        # lilac label strip along the front edge (Skyman / Phaser-R print)
        box("strip", -W + 0.06, W - 0.06, -0.33, -0.25, H - 0.01, H + 0.012, "SkymanLilac"),
    ]
    for row, y in enumerate((0.24, 0.05)):      # 6 short knobs: dots, not pillars
        for i, x in enumerate((-0.22, 0.0, 0.22)):
            parts.append(cylinder(f"knob{row}{i}", (x, y, H + 0.025), 0.06, 0.05, "KnobSilver", verts=10))
    for i, x in enumerate((-0.2, 0.2)):              # stomp switches + LEDs
        parts.append(cylinder(f"nut{i}", (x, -0.19, H + 0.015), 0.07, 0.03, "Chrome", verts=6))
        parts.append(cylinder(f"stomp{i}", (x, -0.19, H + 0.06), 0.055, 0.07, "Chrome", verts=10))
    for i, x in enumerate((-0.075, 0.075)):          # LEDs inboard of the stomps so they aren't hidden
        parts.append(box(f"led{i}", x - 0.04, x + 0.04, -0.2, -0.12, H, H + 0.07, "LedViolet"))
    parts.append(label("brand", "Skyman", (0.0, -0.29, H + 0.013), 0.06, "SkymanPurple"))
    socks = [jack(+1, 0.1, 0.12, W), jack(-1, 0.1, 0.12, -W)]
    parts += [o for o in bpy.data.objects if o.name.startswith("jack_") and o.type == 'MESH']
    return merge("pedal_skyman_phaser", parts), socks


# ---------------------------------------------------------------- export
def export(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_apply=True,
        export_yup=True, export_animations=False, export_image_format='NONE')
    print("wrote", path)


PEDALS = {"chief_delay": build_chief, "skyman_phaser": build_skyman}


def main():
    reset_scene()
    x = 0.0
    for pid, build in PEDALS.items():
        mesh, socks = build()
        for s in socks:
            s.parent = mesh
        export(f"{ASSETS}/pedal_{pid}.glb", [mesh, *socks])
        mesh.location.x += x                 # keep it in the .blend, out of the next pedal's way
        for s in socks:                      # free the plain jack names for the next pedal
            s.name = f"{pid}.{s.name}"
        x += 1.2
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(ROOT, "blender", "pedals", "pedals.blend"))


main()
