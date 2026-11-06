class_name CraftingStation
extends RefCounted
## Manages station-based crafting, culinary cooking, fuel consumption, and timed batch processing.

signal craft_started(recipe_id: StringName, duration: float)
signal craft_progress_updated(progress_ratio: float)
signal craft_completed(recipe_id: StringName, output_item_id: StringName, count: int)
signal fuel_updated(remaining_sec: float)
signal station_halted(reason: String)

var station_id: StringName = &"none"
var station_name: String = "Field Crafting"
var requires_fuel: bool = false
var fuel_remaining_sec: float = 0.0

var active_recipe: RecipeDef = null
var batch_remaining: int = 0
var cook_timer: float = 0.0
var total_cook_time: float = 0.0
var is_active: bool = false

## Fuel burn durations per item (in seconds)
const FUEL_BURN_TIMES: Dictionary = {
	&"driftwood": 20.0,
	&"dark_wood": 60.0,
	&"wood_plank": 15.0,
	&"kelp_frond": 10.0
}


func _init(p_station_id: StringName = &"none", p_name: String = "Field Crafting", p_req_fuel: bool = false) -> void:
	station_id = p_station_id
	station_name = p_name
	requires_fuel = p_req_fuel


## Adds fuel from inventory. Returns count of fuel items actually consumed.
func add_fuel_from_inventory(inv: Inventory, fuel_id: StringName, count: int = 1) -> int:
	if not FUEL_BURN_TIMES.has(fuel_id) or count <= 0:
		return 0
	var burn_per_unit: float = FUEL_BURN_TIMES[fuel_id]
	var removed := inv.remove_item(fuel_id, count)
	if removed > 0:
		fuel_remaining_sec += removed * burn_per_unit
		fuel_updated.emit(fuel_remaining_sec)
	return removed


## Directly injects fuel time (useful for tests or ambient fires).
func add_fuel_time(seconds: float) -> void:
	if seconds > 0.0:
		fuel_remaining_sec += seconds
		fuel_updated.emit(fuel_remaining_sec)


func is_fueled() -> bool:
	return not requires_fuel or fuel_remaining_sec > 0.0


## Starts crafting a recipe. If craft_time_sec is 0, completes instantly into inv.
func craft_recipe(recipe_id: StringName, inv: Inventory, batches: int = 1) -> bool:
	var recipe := RecipeDB.get_recipe(recipe_id)
	if recipe == null:
		station_halted.emit("Unknown recipe: %s" % recipe_id)
		return false

	if recipe.required_station != &"none" and recipe.required_station != station_id:
		station_halted.emit("Recipe requires station '%s', current is '%s'" % [recipe.required_station, station_id])
		return false

	if requires_fuel and fuel_remaining_sec <= 0.0:
		station_halted.emit("Station requires fuel")
		return false

	if not recipe.can_craft_with(inv):
		station_halted.emit("Missing required ingredients")
		return false

	if recipe.craft_time_sec <= 0.0:
		# Instant crafting
		for b in batches:
			if recipe.consume_ingredients(inv):
				inv.add_item(recipe.output_item_id, recipe.output_count)
				craft_completed.emit(recipe.id, recipe.output_item_id, recipe.output_count)
			else:
				break
		return true

	# Timed / Cooking processing
	if is_active:
		station_halted.emit("Station is already busy")
		return false

	if not recipe.consume_ingredients(inv):
		station_halted.emit("Failed to consume ingredients")
		return false

	active_recipe = recipe
	batch_remaining = batches
	total_cook_time = recipe.craft_time_sec
	cook_timer = 0.0
	is_active = true
	craft_started.emit(recipe.id, total_cook_time)
	return true


## Advances the cook timer and burns fuel. Call every frame or tick with delta seconds.
func tick(delta: float, destination_inv: Inventory = null) -> void:
	if requires_fuel and fuel_remaining_sec > 0.0 and is_active:
		fuel_remaining_sec = maxf(0.0, fuel_remaining_sec - delta)
		fuel_updated.emit(fuel_remaining_sec)
		if fuel_remaining_sec <= 0.0 and is_active:
			is_active = false
			station_halted.emit("Fuel depleted mid-cook")
			return

	if not is_active or active_recipe == null:
		return

	cook_timer += delta
	var progress := clampf(cook_timer / total_cook_time, 0.0, 1.0)
	craft_progress_updated.emit(progress)

	if cook_timer >= total_cook_time:
		# Batch item completed!
		if destination_inv:
			destination_inv.add_item(active_recipe.output_item_id, active_recipe.output_count)
		craft_completed.emit(active_recipe.id, active_recipe.output_item_id, active_recipe.output_count)

		batch_remaining -= 1
		if batch_remaining > 0:
			cook_timer = 0.0
			craft_started.emit(active_recipe.id, total_cook_time)
		else:
			is_active = false
			active_recipe = null
			cook_timer = 0.0
			total_cook_time = 0.0
