class_name ArmorDef
extends Resource
## Defines protective equipment attributes, environmental protections, and aquatic mobility tradeoffs.

enum Slot {
	HEAD,
	BODY,
	LEGS,
	BOOTS,
	ACCESSORY
}

enum WeightClass {
	LIGHT,      ## Cloth, linen, oiled canvas - fast swimming, buoyant
	MEDIUM,     ## Boiled seal-leather, reinforced waders - balanced
	HEAVY       ## Chitin carapace, plate, lead diving gear - negative buoyancy, deep pressure proof
}

@export var id: StringName = &""
@export var name: String = ""
@export var slot: Slot = Slot.BODY
@export var weight_class: WeightClass = WeightClass.LIGHT

## Defense attributes
@export var defense: int = 1                     ## Flat damage reduction
@export var crush_reduction: float = 0.0         ## % blunt/impact resistance (0.0 to 1.0)
@export var slash_reduction: float = 0.0         ## % slashing resistance (0.0 to 1.0)
@export var pierce_reduction: float = 0.0        ## % puncture resistance (0.0 to 1.0)

## Environmental resistance
@export var cold_protection: float = 0.0         ## Hypothermia / storm resistance (0.0 to 1.0)
@export var max_safe_depth_m: float = 15.0       ## Depth before barotrauma/pressure damage begins
@export var extra_breath_sec: float = 0.0        ## Air tank / gill rebreather extension

## Aquatic mobility tradeoffs
@export var swim_speed_mult: float = 1.0         ## 1.2 for flippers, 0.3 for lead diving suit
@export var buoyancy_force: float = 1.0          ## >1.0 floats upward; <0.0 sinks to ocean floor
@export var stamina_sprint_mult: float = 1.0     ## Fatigue modifier on land

## Visual attachment key (for CharacterModel paperdoll rendering)
@export var visual_mesh_key: String = ""


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_slot: Slot = Slot.BODY,
	p_defense: int = 1,
	p_weight: WeightClass = WeightClass.LIGHT
) -> void:
	id = p_id
	name = p_name
	slot = p_slot
	defense = p_defense
	weight_class = p_weight
