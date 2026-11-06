class_name CropDef
extends Resource
## Crop definition for Brine's Hollow agriculture.
## Configures growth stages, salinity tolerance (freshwater vs. tidal mud),
## watering requirements, and harvest drops.

enum SoilType {
	SWEET_SOIL,     ## Freshwater terrace loam; watered by rain cisterns / cans
	BRACKISH_SOIL,  ## Tidal mud; inundated twice daily by high tide
	ANY             ## Hardy halophytes that grow anywhere damp
}

@export var id: StringName = &""
@export var name: String = ""
@export var seed_item_id: StringName = &""
@export var harvest_item_id: StringName = &""
@export var min_yield: int = 1
@export var max_yield: int = 3
@export var extra_seed_chance: float = 0.25 ## Chance to yield an extra seed on harvest
@export var growth_stages: int = 4          ## 1: Sprout, 2: Vegetative, 3: Flowering, 4: Mature
@export var growth_duration_sec: float = 120.0
@export var preferred_soil: SoilType = SoilType.SWEET_SOIL
@export var min_salinity: float = 0.0       ## 0.0 = pure freshwater rain
@export var max_salinity: float = 0.4       ## 1.0 = ocean sea brine
@export var can_regrow: bool = false        ## If true, stays at stage 2 after harvest instead of clearing


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_seed_id: StringName = &"",
	p_harvest_id: StringName = &"",
	p_soil: SoilType = SoilType.SWEET_SOIL,
	p_duration: float = 120.0,
	p_min_sal: float = 0.0,
	p_max_sal: float = 0.4
) -> void:
	id = p_id
	name = p_name
	seed_item_id = p_seed_id
	harvest_item_id = p_harvest_id
	preferred_soil = p_soil
	growth_duration_sec = p_duration
	min_salinity = p_min_sal
	max_salinity = p_max_sal


## Calculates growth efficiency multiplier based on current soil salinity (0.0 to 1.0).
## Returns 0.0 if salinity is lethal, 1.0 at ideal salinity, or a penalty fraction.
func get_salinity_efficiency(salinity: float) -> float:
	if salinity < min_salinity:
		# Too fresh for marine crops (like samphire)
		var diff: float = min_salinity - salinity
		return max(0.1, 1.0 - diff * 2.0)
	elif salinity > max_salinity:
		# Too salty for freshwater crops (like wheat)
		var excess: float = salinity - max_salinity
		return max(0.0, 1.0 - excess * 3.0)
	return 1.0
