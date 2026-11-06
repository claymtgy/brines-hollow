class_name FishDef
extends Resource
## Fish definition and ecological requirements for Brine's Hollow.

enum Habitat {
	SHALLOWS,     ## Beach shallows and tidal flats
	TIDAL_POOL,   ## Trapped limestone pools at low tide
	OPEN_WATER,   ## Pelagic ocean water away from cliffs
	CLIFF_SURGE,  ## Deep water pressing against cliff walls
	DEEP_TRENCH   ## Deep abyssal trenches requiring heavy sinkers
}

enum TidePref {
	ANY,
	LOW_TIDE_ONLY,   ## Trapped or visible only when water recedes
	HIGH_TIDE_ONLY,  ## Feeds on coastal shallows when tide floods
	EBB_FLOW         ## Active during tidal current shifts
}

enum WeatherPref {
	ANY,
	FAIR_ONLY,
	STORM_ONLY,      ## Only surfaces during violent gale squalls
	FOG_ONLY         ## Stalks through pea-soup sea mist
}

enum TimePref {
	ANY,
	DAY_ONLY,
	NIGHT_ONLY
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	LEGENDARY
}

@export var id: StringName = &""
@export var name: String = ""
@export var item_id: StringName = &""
@export var rarity: Rarity = Rarity.COMMON
@export var habitat: Habitat = Habitat.OPEN_WATER
@export var tide_pref: TidePref = TidePref.ANY
@export var weather_pref: WeatherPref = WeatherPref.ANY
@export var time_pref: TimePref = TimePref.ANY
@export var tackle_tier: int = 1         ## 1=Whittle Rod, 2=Ocean Caster, 3=Brass Reel, 4=Abyssal Rod
@export var base_stamina: float = 10.0   ## Seconds of thrashing resistance
@export var pull_strength: float = 0.5   ## Line tension pull rate (0.0 to 1.0)
@export var min_weight_kg: float = 0.5
@export var max_weight_kg: float = 3.0


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_item_id: StringName = &"",
	p_rarity: Rarity = Rarity.COMMON,
	p_habitat: Habitat = Habitat.OPEN_WATER,
	p_tide: TidePref = TidePref.ANY,
	p_weather: WeatherPref = WeatherPref.ANY,
	p_time: TimePref = TimePref.ANY,
	p_tier: int = 1
) -> void:
	id = p_id
	name = p_name
	item_id = p_item_id
	rarity = p_rarity
	habitat = p_habitat
	tide_pref = p_tide
	weather_pref = p_weather
	time_pref = p_time
	tackle_tier = p_tier


## Evaluates if this species is eligible to bite given current environmental conditions.
func is_catchable(
	tide_fraction: float, ## -1.0 (extreme low) to +1.0 (extreme high)
	is_daylight: bool,
	is_storming: bool,
	is_foggy: bool,
	rod_tier: int
) -> bool:
	# 1. Rod tier check
	if rod_tier < tackle_tier:
		return false

	# 2. Tide state check
	match tide_pref:
		TidePref.LOW_TIDE_ONLY:
			if tide_fraction > -0.15:
				return false
		TidePref.HIGH_TIDE_ONLY:
			if tide_fraction < 0.15:
				return false
		TidePref.EBB_FLOW:
			if absf(tide_fraction) > 0.4:
				return false # Only mid-tide transitions

	# 3. Weather check
	match weather_pref:
		WeatherPref.FAIR_ONLY:
			if is_storming or is_foggy:
				return false
		WeatherPref.STORM_ONLY:
			if not is_storming:
				return false
		WeatherPref.FOG_ONLY:
			if not is_foggy:
				return false

	# 4. Time of day check
	match time_pref:
		TimePref.DAY_ONLY:
			if not is_daylight:
				return false
		TimePref.NIGHT_ONLY:
			if is_daylight:
				return false

	return true
