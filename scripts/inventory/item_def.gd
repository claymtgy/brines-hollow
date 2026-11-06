class_name ItemDef
extends Resource
## Data-driven item definition for Brine's Hollow.
## Defines identity, category, stacking limits, voxel material mappings,
## and gameplay properties (tools, cooking buffs, seeds, gear).

enum Category {
	MATERIAL,     ## Raw voxels, ores, timber, stone, crafting ingredients
	FOOD,         ## Raw ingredients, crops, fish, cooked meals, brews
	TOOL,         ## Harvest tools, fishing rods, weapons, chisels
	EQUIPMENT,    ## Backpacks, clothing, cloaks, diving helmets, rings
	BLUEPRINT,    ## Prefab building blueprints and architectural scrolls
	SPECIAL       ## Boss trophies, currencies (scrip/guilders), quest curios
}

@export var id: StringName = &""
@export var name: String = ""
@export var description: String = ""
@export var category: Category = Category.MATERIAL
@export var max_stack: int = 999
@export var voxel_mat: int = -1         ## Palette material index if placeable as a voxel, or -1
@export var tags: PackedStringArray = [] ## e.g. ["fish", "fresh"], ["seed"], ["ore"], ["timber"]

## Optional subsystem properties
@export var food_data: Dictionary = {}   ## {"stamina_regen": 1.2, "duration": 180.0, "swim_speed": 1.25}
@export var tool_data: Dictionary = {}   ## {"tier": 1, "power": 1.5, "durability": 100, "weapon_type": "cutlass"}
@export var armor_data: Dictionary = {}  ## {"defense": 4, "cold_resist": 0.5, "safe_depth": 35.0, "swim_speed": 1.1}
@export var weapon_data: Dictionary = {} ## {"weapon_type": WeaponDef.WeaponType.CUTLASS, "damage": 22, "reach": 2.2}
@export var equip_slot: StringName = &"" ## &"head", &"body", &"legs", &"boots", &"backpack", &"accessory"
@export var value_brass: int = 1         ## Base trader price in Brass Guilders


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_category: Category = Category.MATERIAL,
	p_max_stack: int = 999,
	p_voxel_mat: int = -1,
	p_tags: PackedStringArray = PackedStringArray()
) -> void:
	id = p_id
	name = p_name
	category = p_category
	max_stack = p_max_stack
	voxel_mat = p_voxel_mat
	tags = p_tags


func is_stackable() -> bool:
	return max_stack > 1


func has_tag(tag: String) -> bool:
	return tag in tags


func is_voxel() -> bool:
	return voxel_mat >= 0
