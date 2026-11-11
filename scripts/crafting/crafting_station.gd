class_name CraftingStation
extends RefCounted
## Manages station-based crafting, culinary cooking, fuel consumption, and timed batch processing.

signal craft_started(recipe_id: StringName, duration: float)
signal craft_progress_updated(progress_ratio: float)
signal craft_completed(recipe_id: StringName, output_item_id: StringName, count: int)
signal fuel_updated(remaining_sec: float)
signal station_halted(reason: String)

const MAX_FUEL_SEC: float = 240.0

var station_id: StringName = &"none"
var station_name: String = "Field Crafting"
var requires_fuel: bool = false
var fuel_remaining_sec: float = 0.0

## Stations whose recipes take real time: you start a dish, it cooks while you do
## other things, and the result waits in the station's tray until collected.
const COOKING_STATIONS: Array[StringName] = [&"campfire", &"hearth_pot", &"smokehouse", &"saltery", &"brewery"]
const MAX_QUEUE := 5            ## dishes waiting behind the one on the fire

var active_recipe: RecipeDef = null
var cook_timer: float = 0.0
var total_cook_time: float = 0.0
var is_active: bool = false
var queue: Array[StringName] = []      ## recipe ids paid for and waiting their turn
var output: Dictionary = {}            ## item id -> count, finished and waiting in the tray
var output_batches: Dictionary = {}    ## item id -> how many cooks produced it (for quest credit)
var _halt_reported := false

## Batches left including the one cooking now (kept for older callers).
var batch_remaining: int:
	get:
		return (1 if is_active else 0) + queue.size()


static func is_cooking_station(tag: StringName) -> bool:
	return COOKING_STATIONS.has(tag)


## True when this recipe cooks over time instead of finishing instantly.
static func is_timed(r: RecipeDef) -> bool:
	return r != null and r.craft_time_sec > 0.0 and is_cooking_station(r.required_station)


func queue_full() -> bool:
	return is_active and queue.size() >= MAX_QUEUE


## Fire went out mid-cook: the dish waits (keeps its progress) until refuelled.
func is_paused() -> bool:
	return is_active and requires_fuel and fuel_remaining_sec <= 0.0


func cook_progress() -> float:
	return clampf(cook_timer / total_cook_time, 0.0, 1.0) if is_active and total_cook_time > 0.0 else 0.0


func seconds_left() -> float:
	return maxf(0.0, total_cook_time - cook_timer) if is_active else 0.0


func output_count() -> int:
	var n := 0
	for k in output:
		n += int(output[k])
	return n

## Fuel burn durations per item (in seconds)
const FUEL_BURN_TIMES: Dictionary = {
	&"driftwood": 20.0,
	&"pine_wood": 45.0,
	&"dark_wood": 60.0,
	&"wood_plank": 15.0,
	&"kelp_frond": 10.0,
	&"leaves": 8.0
}

const FUEL_PRIORITY: Array[StringName] = [
	&"driftwood",
	&"pine_wood",
	&"wood_plank",
	&"dark_wood",
	&"kelp_frond",
	&"leaves"
]


func _init(p_station_id: StringName = &"none", p_name: String = "Field Crafting", p_req_fuel: bool = false) -> void:
	station_id = p_station_id
	station_name = p_name
	requires_fuel = p_req_fuel


static func is_fuel_item(item_id: StringName) -> bool:
	return FUEL_BURN_TIMES.has(item_id)


static func has_any_fuel(inv: Inventory) -> bool:
	if inv == null:
		return false
	for fid: StringName in FUEL_PRIORITY:
		if inv.has_item(fid, 1):
			return true
	return false


## Adds fuel from inventory. Returns count of fuel items actually consumed.
func add_fuel_from_inventory(inv: Inventory, fuel_id: StringName, count: int = 1) -> int:
	if not FUEL_BURN_TIMES.has(fuel_id) or count <= 0:
		return 0
	var burn_per_unit: float = FUEL_BURN_TIMES[fuel_id]
	var removed := inv.remove_item(fuel_id, count)
	if removed > 0:
		fuel_remaining_sec = minf(MAX_FUEL_SEC, fuel_remaining_sec + removed * burn_per_unit)
		fuel_updated.emit(fuel_remaining_sec)
	return removed


## Recharges the fire using 1 fuel item from inventory (prioritizing preferred_item if valid).
func recharge_from_inventory(inv: Inventory, preferred_item: StringName = &"") -> Dictionary:
	if inv == null:
		return {"recharged": false, "reason": "No inventory"}
	if fuel_remaining_sec >= MAX_FUEL_SEC - 1.0:
		return {"recharged": false, "reason": "Fire is already fully stoked (%.0fs)" % fuel_remaining_sec}
	var order: Array[StringName] = []
	if preferred_item != &"" and FUEL_BURN_TIMES.has(preferred_item):
		order.append(preferred_item)
	for fid: StringName in FUEL_PRIORITY:
		if not order.has(fid):
			order.append(fid)
	for fid: StringName in order:
		if inv.has_item(fid, 1):
			var burn_sec: float = float(FUEL_BURN_TIMES[fid])
			var removed := inv.remove_item(fid, 1)
			if removed > 0:
				fuel_remaining_sec = minf(MAX_FUEL_SEC, fuel_remaining_sec + removed * burn_sec)
				fuel_updated.emit(fuel_remaining_sec)
				return {
					"recharged": true,
					"item_id": fid,
					"added_sec": burn_sec,
					"remaining_sec": fuel_remaining_sec
				}
	return {"recharged": false, "reason": "Requires wood, driftwood, or planks for fuel"}


## Directly injects fuel time (useful for tests or ambient fires).
func add_fuel_time(seconds: float) -> void:
	if seconds > 0.0:
		fuel_remaining_sec = minf(MAX_FUEL_SEC, fuel_remaining_sec + seconds)
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

	if not is_timed(recipe):
		# Instant crafting
		for b in batches:
			if recipe.consume_ingredients(inv):
				inv.add_item(recipe.output_item_id, recipe.output_count)
				craft_completed.emit(recipe.id, recipe.output_item_id, recipe.output_count)
			else:
				break
		return true

	# Timed cooking: every batch is paid for up front, then cooks in turn.
	if queue_full():
		station_halted.emit("Station is already busy")
		return false
	var started := 0
	for b in maxi(1, batches):
		if queue_full() or not recipe.consume_ingredients(inv):
			break
		started += 1
		if is_active:
			queue.append(recipe.id)
		else:
			_start(recipe)
	if started == 0:
		station_halted.emit("Failed to consume ingredients")
		return false
	return true


func _start(recipe: RecipeDef) -> void:
	active_recipe = recipe
	total_cook_time = recipe.craft_time_sec
	cook_timer = 0.0
	is_active = true
	_halt_reported = false
	craft_started.emit(recipe.id, total_cook_time)


## Takes a waiting (not yet cooking) dish off the queue and refunds its ingredients.
func cancel_queued(index: int, inv: Inventory) -> bool:
	if index < 0 or index >= queue.size():
		return false
	var r := RecipeDB.get_recipe(queue[index])
	queue.remove_at(index)
	if r != null and inv != null and inv.get("creative_mode") != true:
		for inp: Dictionary in r.inputs:
			inv.add_item(StringName(inp.get("item_id", &"")), int(inp.get("count", 1)))
	return true


## Moves finished dishes from the tray into `inv`. Returns {item_id: count} actually taken;
## whatever doesn't fit stays in the tray.
func take_output(inv: Inventory) -> Dictionary:
	var taken := {}
	for item_id: StringName in output.keys():
		var have: int = int(output[item_id])
		var left := inv.add_item(item_id, have) if inv != null else have
		var moved := have - left
		if moved > 0:
			taken[item_id] = moved
		if left <= 0:
			output.erase(item_id)
		else:
			output[item_id] = left
	return taken


## Advances the cook timer and burns fuel. Call every frame or tick with delta seconds.
## Finished dishes go into `destination_inv` when given, otherwise into the station's tray.
func tick(delta: float, destination_inv: Inventory = null) -> void:
	if not is_active or active_recipe == null:
		return
	if requires_fuel:
		if fuel_remaining_sec <= 0.0:
			if not _halt_reported:
				_halt_reported = true
				station_halted.emit("Fuel depleted mid-cook")
			return   # paused: the dish keeps its progress until the fire is fed
		fuel_remaining_sec = maxf(0.0, fuel_remaining_sec - delta)
		fuel_updated.emit(fuel_remaining_sec)
	_halt_reported = false

	cook_timer += delta
	craft_progress_updated.emit(cook_progress())
	if cook_timer < total_cook_time:
		return

	var r := active_recipe
	var left := r.output_count
	if destination_inv != null:
		left = destination_inv.add_item(r.output_item_id, r.output_count)
	if left > 0:
		output[r.output_item_id] = int(output.get(r.output_item_id, 0)) + left
		output_batches[r.output_item_id] = int(output_batches.get(r.output_item_id, 0)) + 1
	craft_completed.emit(r.id, r.output_item_id, r.output_count)

	is_active = false
	active_recipe = null
	cook_timer = 0.0
	total_cook_time = 0.0
	while not queue.is_empty():
		var nxt := RecipeDB.get_recipe(queue.pop_front())
		if nxt != null:
			_start(nxt)
			break


func serialize_cooking() -> Dictionary:
	var q: Array = []
	for id in queue:
		q.append(String(id))
	var out := {}
	for k in output:
		out[String(k)] = int(output[k])
	var ob := {}
	for k in output_batches:
		ob[String(k)] = int(output_batches[k])
	return {"queue": q, "output": out, "output_batches": ob}


func deserialize_cooking(d: Dictionary) -> void:
	queue.clear()
	for id in d.get("queue", []):
		if RecipeDB.has_recipe(StringName(id)):
			queue.append(StringName(id))
	output.clear()
	for k in d.get("output", {}):
		output[StringName(k)] = int(d["output"][k])
	output_batches.clear()
	for k in d.get("output_batches", {}):
		output_batches[StringName(k)] = int(d["output_batches"][k])
