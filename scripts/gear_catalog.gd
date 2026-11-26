class_name GearCatalog
## Every equippable item, per slot. An empty dictionary means "nothing equipped".
## Skinned gear (armor, boots, ...) must be exported on the shared Rocker skeleton
## (blender/export_gltf.py); guitars are static meshes that ride the "guitar" bone.
## "recolor" remaps material names to other Toon.PALETTE entries, so one mesh can be several items.

const SLOTS := ["guitar", "armor", "boots"]

const ITEMS := {
	"guitar": [
		{"name": "Reaper", "scene": "res://assets/gear/guitar_reaper.glb"},
		{"name": "Battle-axe", "scene": "res://assets/gear/guitar_battleaxe.glb"},
	],
	"armor": [
		{"name": "Gothic plate", "scene": "res://assets/gear/armor_gothic_plate.glb"},
		{"name": "Bone plate", "scene": "res://assets/gear/armor_gothic_plate.glb", "recolor": {"Armor": "BonePlate"}},
		{},
	],
	"boots": [
		{"name": "Combat boots", "scene": "res://assets/gear/boots_combat.glb"},
		{"name": "Oxblood boots", "scene": "res://assets/gear/boots_combat.glb", "recolor": {"Leather": "Oxblood"}},
		{},
	],
}
