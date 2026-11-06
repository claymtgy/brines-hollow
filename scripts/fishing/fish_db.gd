class_name FishDB
extends RefCounted
## Fish species almanac and bite roll generator for Brine's Hollow.

static var _registry: Dictionary = {}
static var _initialized := false


static func init_db() -> void:
	if _initialized:
		return
	_initialized = true
	_registry.clear()

	# 1. Silver Mackerel: Common pelagic high-tide schooling fish
	var mackerel := FishDef.new(
		&"silver_mackerel", "Silver Mackerel", &"silver_mackerel",
		FishDef.Rarity.COMMON, FishDef.Habitat.OPEN_WATER,
		FishDef.TidePref.HIGH_TIDE_ONLY, FishDef.WeatherPref.ANY, FishDef.TimePref.DAY_ONLY, 1
	)
	mackerel.pull_strength = 0.4
	mackerel.base_stamina = 6.0
	mackerel.min_weight_kg = 0.8
	mackerel.max_weight_kg = 2.4
	register_fish(mackerel)

	# 2. Tidepool Flounder: Bottom-dweller trapped in sandy pools at low tide
	var flounder := FishDef.new(
		&"tidepool_flounder", "Tidepool Flounder", &"tidepool_flounder",
		FishDef.Rarity.COMMON, FishDef.Habitat.TIDAL_POOL,
		FishDef.TidePref.LOW_TIDE_ONLY, FishDef.WeatherPref.ANY, FishDef.TimePref.ANY, 1
	)
	flounder.pull_strength = 0.3
	flounder.base_stamina = 5.0
	flounder.min_weight_kg = 0.5
	flounder.max_weight_kg = 1.8
	register_fish(flounder)

	# 3. Cliff Salmon: Powerful upstream swimmer near cliff surge at high tide
	var salmon := FishDef.new(
		&"cliff_salmon", "Cliff Salmon", &"cliff_salmon",
		FishDef.Rarity.UNCOMMON, FishDef.Habitat.CLIFF_SURGE,
		FishDef.TidePref.HIGH_TIDE_ONLY, FishDef.WeatherPref.ANY, FishDef.TimePref.ANY, 2
	)
	salmon.pull_strength = 0.65
	salmon.base_stamina = 12.0
	salmon.min_weight_kg = 2.5
	salmon.max_weight_kg = 6.8
	register_fish(salmon)

	# 4. Lightning Eel: Surfaces only in violent squalls
	var eel := FishDef.new(
		&"lightning_eel", "Lightning Eel", &"lightning_eel",
		FishDef.Rarity.RARE, FishDef.Habitat.OPEN_WATER,
		FishDef.TidePref.ANY, FishDef.WeatherPref.STORM_ONLY, FishDef.TimePref.ANY, 2
	)
	eel.pull_strength = 0.8
	eel.base_stamina = 15.0
	eel.min_weight_kg = 1.8
	eel.max_weight_kg = 4.5
	register_fish(eel)

	# 5. Ghost Squid: Phosphorescent nocturnal hunter
	var squid := FishDef.new(
		&"ghost_squid", "Ghost Squid", &"ghost_squid",
		FishDef.Rarity.RARE, FishDef.Habitat.DEEP_TRENCH,
		FishDef.TidePref.ANY, FishDef.WeatherPref.ANY, FishDef.TimePref.NIGHT_ONLY, 2
	)
	squid.pull_strength = 0.7
	squid.base_stamina = 14.0
	squid.min_weight_kg = 1.2
	squid.max_weight_kg = 3.6
	register_fish(squid)

	# 6. Abyssal Leviathan Ray: Legendary trophy catch of the deep trenches
	var ray := FishDef.new(
		&"abyssal_ray", "Abyssal Leviathan Ray", &"silver_mackerel", # Yields trophy/special
		FishDef.Rarity.LEGENDARY, FishDef.Habitat.DEEP_TRENCH,
		FishDef.TidePref.LOW_TIDE_ONLY, FishDef.WeatherPref.ANY, FishDef.TimePref.NIGHT_ONLY, 3
	)
	ray.pull_strength = 0.95
	ray.base_stamina = 25.0
	ray.min_weight_kg = 18.0
	ray.max_weight_kg = 45.0
	register_fish(ray)


static func register_fish(def: FishDef) -> void:
	_registry[def.id] = def


static func get_fish(fish_id: StringName) -> FishDef:
	if not _initialized:
		init_db()
	return _registry.get(fish_id, null)


static func get_all_fish() -> Array[FishDef]:
	if not _initialized:
		init_db()
	var arr: Array[FishDef] = []
	for f in _registry.values():
		arr.append(f)
	return arr


## Finds all catchable fish given current environmental conditions.
static func get_eligible_fish(
	tide_fraction: float,
	is_daylight: bool,
	is_storming: bool,
	is_foggy: bool,
	rod_tier: int
) -> Array[FishDef]:
	if not _initialized:
		init_db()
	var eligible: Array[FishDef] = []
	for def: FishDef in _registry.values():
		if def.is_catchable(tide_fraction, is_daylight, is_storming, is_foggy, rod_tier):
			eligible.append(def)
	return eligible


## Rolls a random bite from eligible species. Higher rarity has lower weight.
static func roll_bite(
	tide_fraction: float,
	is_daylight: bool,
	is_storming: bool,
	is_foggy: bool,
	rod_tier: int,
	rng: RandomNumberGenerator = null
) -> FishDef:
	var pool := get_eligible_fish(tide_fraction, is_daylight, is_storming, is_foggy, rod_tier)
	if pool.is_empty():
		return null

	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var weights: Array[float] = []
	var total_weight: float = 0.0

	for fish in pool:
		var w: float = 1.0
		match fish.rarity:
			FishDef.Rarity.COMMON: w = 100.0
			FishDef.Rarity.UNCOMMON: w = 35.0
			FishDef.Rarity.RARE: w = 10.0
			FishDef.Rarity.LEGENDARY: w = 2.0
		weights.append(w)
		total_weight += w

	var roll: float = r.randf() * total_weight
	var acc: float = 0.0
	for i in pool.size():
		acc += weights[i]
		if roll <= acc:
			return pool[i]

	return pool[pool.size() - 1]
