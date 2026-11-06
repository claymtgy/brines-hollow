class_name CropDB
extends RefCounted
## Database registry for all cultivable crops in Brine's Hollow.

static var _registry: Dictionary = {}
static var _seed_to_crop: Dictionary = {}
static var _initialized := false


static func init_db() -> void:
	if _initialized:
		return
	_initialized = true
	_registry.clear()
	_seed_to_crop.clear()

	# 1. Shore Wheat: Sweet soil staple; sensitive to salt spray
	var wheat := CropDef.new(
		&"shore_wheat", "Shore Wheat", &"seed_shore_wheat", &"shore_wheat",
		CropDef.SoilType.SWEET_SOIL, 90.0, 0.0, 0.25
	)
	wheat.min_yield = 2
	wheat.max_yield = 4
	wheat.extra_seed_chance = 0.35
	register_crop(wheat)

	# 2. Samphire (Sea Asparagus): Halophyte; thrives in tidal brackish mud; regrows stems
	var samphire := CropDef.new(
		&"samphire", "Sea Samphire", &"seed_samphire", &"samphire",
		CropDef.SoilType.BRACKISH_SOIL, 110.0, 0.35, 1.0
	)
	samphire.min_yield = 2
	samphire.max_yield = 3
	samphire.can_regrow = true
	samphire.extra_seed_chance = 0.15
	register_crop(samphire)

	# 3. Tide Kale: Resilient shoreline cabbage; moderate salt tolerance
	var kale := CropDef.new(
		&"tide_kale", "Tide Kale", &"seed_tide_kale", &"tide_kale",
		CropDef.SoilType.ANY, 100.0, 0.10, 0.70
	)
	kale.min_yield = 1
	kale.max_yield = 3
	kale.extra_seed_chance = 0.25
	register_crop(kale)

	# 4. Root Potato: Mountain/high terrace sweet soil tuber; heavy food yield
	var potato := CropDef.new(
		&"root_potato", "Root Potato", &"seed_root_potato", &"root_potato",
		CropDef.SoilType.SWEET_SOIL, 140.0, 0.0, 0.20
	)
	potato.min_yield = 3
	potato.max_yield = 5
	potato.extra_seed_chance = 0.50
	register_crop(potato)


static func register_crop(def: CropDef) -> void:
	_registry[def.id] = def
	_seed_to_crop[def.seed_item_id] = def


static func get_crop(crop_id: StringName) -> CropDef:
	if not _initialized:
		init_db()
	return _registry.get(crop_id, null)


static func get_crop_by_seed(seed_id: StringName) -> CropDef:
	if not _initialized:
		init_db()
	return _seed_to_crop.get(seed_id, null)


static func has_crop(crop_id: StringName) -> bool:
	if not _initialized:
		init_db()
	return _registry.has(crop_id)
