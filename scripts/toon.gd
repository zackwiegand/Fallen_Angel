class_name Toon
## Toon palette: the sprite-poc Blender materials (dark, mid, lite bands; linear values).
## glTF can't carry the Blender node trees, so imported materials are swapped by name for
## shared toon ShaderMaterials. Gear items can recolour by mapping a material name to another entry.

const SHADER := preload("res://shaders/toon.gdshader")

const PALETTE := {
	# name: [dark, mid, lite, spec, bands]
	"Armor": [Vector3(0.006, 0.006, 0.009), Vector3(0.028, 0.03, 0.04), Vector3(0.13, 0.14, 0.19), true],
	"Steel": [Vector3(0.04, 0.04, 0.05), Vector3(0.18, 0.18, 0.2), Vector3(0.6, 0.6, 0.63), true],
	"Leather": [Vector3(0.01, 0.005, 0.003), Vector3(0.05, 0.025, 0.015), Vector3(0.13, 0.07, 0.04), false],
	"Bracer": [Vector3(0.02, 0.008, 0.003), Vector3(0.085, 0.036, 0.014), Vector3(0.22, 0.11, 0.045), false],
	"Sole": [Vector3(0.004, 0.004, 0.004), Vector3(0.014, 0.013, 0.012), Vector3(0.04, 0.038, 0.035), false],
	"Skin": [Vector3(0.13, 0.05, 0.03), Vector3(0.42, 0.2, 0.12), Vector3(0.75, 0.45, 0.3), false],
	"Beard": [Vector3(0.22, 0.22, 0.25), Vector3(0.55, 0.55, 0.56), Vector3(0.92, 0.92, 0.88), false, Vector2(0.22, 0.62)],
	"Cloth": [Vector3(0.02, 0.006, 0.006), Vector3(0.08, 0.025, 0.022), Vector3(0.2, 0.07, 0.06), false],
	"GuitarRed": [Vector3(0.12, 0.0, 0.006), Vector3(0.5, 0.01, 0.02), Vector3(0.82, 0.05, 0.04), true],
	"Ebony": [Vector3(0.004, 0.004, 0.005), Vector3(0.02, 0.02, 0.022), Vector3(0.08, 0.08, 0.09), false],
	"Chrome": [Vector3(0.08, 0.08, 0.09), Vector3(0.4, 0.4, 0.42), Vector3(0.92, 0.92, 0.95), true],
	"AxeBlack": [Vector3(0.003, 0.003, 0.004), Vector3(0.012, 0.013, 0.016), Vector3(0.055, 0.062, 0.08), true],
	# recolour variants used by gear items
	"BonePlate": [Vector3(0.09, 0.07, 0.045), Vector3(0.36, 0.31, 0.22), Vector3(0.78, 0.72, 0.56), true],
	"Oxblood": [Vector3(0.03, 0.003, 0.003), Vector3(0.14, 0.015, 0.012), Vector3(0.34, 0.05, 0.04), false],
}
const EMISSIVE := {"Eye": Vector3(1.0, 0.05, 0.0)}

static var _cache := {}


static func material(mat_name: String) -> Material:
	if _cache.has(mat_name):
		return _cache[mat_name]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	if EMISSIVE.has(mat_name):
		m.set_shader_parameter("emissive", true)
		m.set_shader_parameter("emit_color", EMISSIVE[mat_name])
	elif PALETTE.has(mat_name):
		var p: Array = PALETTE[mat_name]
		m.set_shader_parameter("dark", p[0])
		m.set_shader_parameter("mid", p[1])
		m.set_shader_parameter("lite", p[2])
		m.set_shader_parameter("spec", p[3])
		if p.size() > 4:
			m.set_shader_parameter("bands", p[4])
	else:
		push_warning("Toon: no palette entry for material '%s'" % mat_name)
	_cache[mat_name] = m
	return m


## Replace every imported surface material under root with its toon material.
## recolor maps imported material names to other palette entries, e.g. {"Armor": "BonePlate"}.
static func apply(root: Node, recolor := {}) -> void:
	var meshes: Array = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		meshes.append(root)
	for mi: MeshInstance3D in meshes:
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var mat_name := src.resource_name if src else ""
			mi.set_surface_override_material(i, material(recolor.get(mat_name, mat_name)))
