class_name CropPlot
extends RefCounted
## Represents an individual tilled soil crop plot in the voxel world.
## Manages hydration, salinity, growth progress, and stages.

signal stage_advanced(plot: CropPlot, new_stage: int)
signal crop_matured(plot: CropPlot)

var pos: Vector3i = Vector3i.ZERO
var crop_id: StringName = &""
var current_stage: int = 0         ## 0 = empty, 1 = sprout, ..., max = mature
var growth_progress: float = 0.0   ## 0.0 to 1.0 across total maturation time
var hydration: float = 0.0         ## 0.0 to 1.0 (water level)
var salinity: float = 0.0          ## 0.0 = pure sweet water, 1.0 = ocean sea brine
var is_fertilized: bool = false    ## 1.5x growth rate if fertilized with kelp compost


func _init(p_pos: Vector3i = Vector3i.ZERO, p_salinity: float = 0.0) -> void:
	pos = p_pos
	salinity = clampf(p_salinity, 0.0, 1.0)


func is_empty() -> bool:
	return crop_id == &"" or current_stage <= 0


func is_mature() -> bool:
	if is_empty():
		return false
	var def: CropDef = CropDB.get_crop(crop_id)
	return def != null and current_stage >= def.growth_stages


func plant(p_crop_id: StringName) -> bool:
	if not is_empty() or not CropDB.has_crop(p_crop_id):
		return false
	crop_id = p_crop_id
	current_stage = 1
	growth_progress = 0.0
	return true


func water(amount: float, water_salinity: float = 0.0) -> void:
	var old_hydro: float = hydration
	hydration = clampf(hydration + amount, 0.0, 1.0)

	# Weighted blend of existing soil salinity and new water salinity
	if hydration > 0.0:
		var added_water: float = hydration - old_hydro
		if added_water > 0.0:
			salinity = clampf((salinity * old_hydro + water_salinity * added_water) / hydration, 0.0, 1.0)


## Simulation tick called periodically or per frame.
## Parameters:
##   delta_sec: elapsed simulation seconds
##   current_tide_y: current ocean tide height in voxels
##   is_raining: whether freshwater rainfall is active
func tick(delta_sec: float, current_tide_y: float, is_raining: bool) -> void:
	# 1. Tidal inundation check: if plot Y is at or below sea level, it gets flooded with saltwater
	if float(pos.y) <= current_tide_y:
		hydration = 1.0
		salinity = lerpf(salinity, 1.0, 0.2) # Rapidly rises to full marine salinity
	elif is_raining:
		hydration = clampf(hydration + 0.1 * (delta_sec / 10.0), 0.0, 1.0)
		salinity = lerpf(salinity, 0.0, 0.05) # Rain slowly leaches out salt
	else:
		# Gradual daily drying
		hydration = max(0.0, hydration - 0.01 * (delta_sec / 60.0))

	if is_empty() or is_mature():
		return

	var def: CropDef = CropDB.get_crop(crop_id)
	if not def:
		return

	# Growth requires minimum hydration
	if hydration < 0.05:
		return

	# Check salinity tolerance
	var sal_mult: float = def.get_salinity_efficiency(salinity)
	if sal_mult <= 0.0:
		return # Growth halted due to lethal salt or lack thereof

	var fert_mult: float = 1.5 if is_fertilized else 1.0
	var rate: float = (delta_sec / def.growth_duration_sec) * sal_mult * fert_mult
	growth_progress = min(1.0, growth_progress + rate)

	# Update growth stage
	var target_stage: int = 1 + int(growth_progress * float(def.growth_stages - 1))
	if target_stage > current_stage:
		current_stage = target_stage
		stage_advanced.emit(self, current_stage)
		if is_mature():
			crop_matured.emit(self)


## Harvests the crop. Returns a dictionary of item yields:
## {"product_id": ..., "product_count": ..., "seed_id": ..., "seed_count": ...}
func harvest(rng: RandomNumberGenerator = null) -> Dictionary:
	if not is_mature():
		return {}

	var def: CropDef = CropDB.get_crop(crop_id)
	if not def:
		return {}

	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()
	var product_cnt: int = r.randi_range(def.min_yield, def.max_yield)
	var seed_cnt: int = 1 # Always return at least the base seed
	if r.randf() < def.extra_seed_chance:
		seed_cnt += 1

	var result: Dictionary = {
		"product_id": def.harvest_item_id,
		"product_count": product_cnt,
		"seed_id": def.seed_item_id,
		"seed_count": seed_cnt
	}

	# Regrowth check (e.g. Samphire / Tide Kale regrows from stem)
	if def.can_regrow:
		current_stage = 2 # Reset to vegetative stage
		growth_progress = 0.33
	else:
		crop_id = &""
		current_stage = 0
		growth_progress = 0.0
		is_fertilized = false

	return result


func serialize() -> Dictionary:
	return {
		"x": pos.x, "y": pos.y, "z": pos.z,
		"crop": String(crop_id),
		"stage": current_stage,
		"progress": growth_progress,
		"hydration": hydration,
		"salinity": salinity,
		"fertilized": is_fertilized
	}


static func deserialize(d: Dictionary) -> CropPlot:
	var plot := CropPlot.new(Vector3i(d["x"], d["y"], d["z"]), float(d.get("salinity", 0.0)))
	plot.crop_id = StringName(d.get("crop", ""))
	plot.current_stage = int(d.get("stage", 0))
	plot.growth_progress = float(d.get("progress", 0.0))
	plot.hydration = float(d.get("hydration", 0.0))
	plot.is_fertilized = bool(d.get("fertilized", false))
	return plot
