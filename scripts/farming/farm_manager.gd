class_name FarmManager
extends RefCounted
## Coordinates all agriculture, crop plots, and salt pans in Brine's Hollow.
## Interfaces directly with the player inventory for planting and harvesting.

signal crop_planted(pos: Vector3i, crop_id: StringName)
signal crop_harvested(pos: Vector3i, crop_id: StringName, yield_count: int)
signal salt_harvested(pos: Vector3i, count: int)

var plots: Dictionary = {}      ## Vector3i -> CropPlot
var salt_pans: Dictionary = {}  ## Vector3i -> SaltPan
var sea_mid: float = 30.0
var tide_amp: float = 7.0


func _init(p_sea_mid: float = 30.0, p_tide_amp: float = 7.0) -> void:
	sea_mid = p_sea_mid
	tide_amp = p_tide_amp
	CropDB.init_db()
	ItemDB.init_db()


# -------------------------------------------------------------------------
# Plot & Pan Management
# -------------------------------------------------------------------------

## Tills an uncultivated plot at grid pos. Sets initial salinity based on elevation.
func till_plot(pos: Vector3i) -> CropPlot:
	if plots.has(pos):
		return plots[pos]

	# Calculate natural soil salinity based on tide elevation:
	# Below high tide: brackish marine mud (~0.85)
	# Just above high tide: low coastal salt (~0.25)
	# High cliff terraces: sweet loam soil (0.0)
	var high_tide: float = sea_mid + tide_amp
	var initial_sal: float = 0.0
	if float(pos.y) <= high_tide:
		initial_sal = 0.85
	elif float(pos.y) <= high_tide + 4.0:
		initial_sal = 0.25
	else:
		initial_sal = 0.0

	var plot := CropPlot.new(pos, initial_sal)
	plots[pos] = plot
	return plot


func get_plot(pos: Vector3i) -> CropPlot:
	return plots.get(pos, null)


func add_salt_pan(pos: Vector3i) -> SaltPan:
	if salt_pans.has(pos):
		return salt_pans[pos]
	var pan := SaltPan.new(pos)
	salt_pans[pos] = pan
	return pan


# -------------------------------------------------------------------------
# Inventory Interactions
# -------------------------------------------------------------------------

## Consumes a compatible seed from inventory and plants it in the plot.
func plant_from_inventory(pos: Vector3i, inv: Inventory) -> bool:
	var plot: CropPlot = get_plot(pos)
	if not plot or not plot.is_empty():
		return false

	# Check active hotbar item first
	var active_slot: ItemSlot = inv.get_active_item()
	var seed_def: CropDef = null
	if active_slot and not active_slot.is_empty():
		seed_def = CropDB.get_crop_by_seed(active_slot.item_id)

	# If active slot is not a seed, search the whole inventory
	var seed_item_id: StringName = &""
	if seed_def:
		seed_item_id = seed_def.seed_item_id
	else:
		for slot in inv.slots:
			if not slot.is_empty():
				var candidate: CropDef = CropDB.get_crop_by_seed(slot.item_id)
				if candidate:
					seed_def = candidate
					seed_item_id = slot.item_id
					break

	if not seed_def or seed_item_id == &"":
		return false

	# Consume 1 seed
	var removed: int = inv.remove_item(seed_item_id, 1)
	if removed <= 0:
		return false

	plot.plant(seed_def.id)
	crop_planted.emit(pos, seed_def.id)
	return true


## Waters a plot with freshwater (or seawater if from ocean bucket).
func water_plot(pos: Vector3i, amount: float = 0.5, water_salinity: float = 0.0) -> bool:
	var plot: CropPlot = get_plot(pos)
	if not plot:
		return false
	plot.water(amount, water_salinity)
	return true


## Harvests mature crop and deposits drops and seeds directly into inventory.
func harvest_to_inventory(pos: Vector3i, inv: Inventory, rng: RandomNumberGenerator = null) -> bool:
	var plot: CropPlot = get_plot(pos)
	if not plot or not plot.is_mature():
		return false

	var crop_id: StringName = plot.crop_id
	var drops: Dictionary = plot.harvest(rng)
	if drops.is_empty():
		return false

	# Deposit harvested produce
	var product_id: StringName = StringName(drops["product_id"])
	var product_cnt: int = int(drops["product_count"])
	var prod_rem: int = inv.add_item(product_id, product_cnt)

	# Deposit seeds
	var seed_id: StringName = StringName(drops["seed_id"])
	var seed_cnt: int = int(drops["seed_count"])
	var seed_rem: int = inv.add_item(seed_id, seed_cnt)

	var actual_yield: int = product_cnt - prod_rem
	crop_harvested.emit(pos, crop_id, actual_yield)
	return true


## Harvests dried sea salt from a salt pan into inventory.
func harvest_salt_to_inventory(pos: Vector3i, inv: Inventory) -> int:
	var pan: SaltPan = salt_pans.get(pos, null)
	if not pan or pan.accumulated_salt <= 0:
		return 0

	var count: int = pan.harvest()
	var remainder: int = inv.add_item(&"sea_salt", count)
	var added: int = count - remainder
	if added > 0:
		salt_harvested.emit(pos, added)
	return added


# -------------------------------------------------------------------------
# Simulation Tick
# -------------------------------------------------------------------------

func tick_all(delta_sec: float, current_tide_y: float, is_daylight: bool, is_raining: bool) -> void:
	for plot in plots.values():
		plot.tick(delta_sec, current_tide_y, is_raining)

	for pan in salt_pans.values():
		pan.tick(delta_sec, current_tide_y, is_daylight, is_raining)


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func serialize() -> Dictionary:
	var p_data: Array = []
	for p in plots.values():
		p_data.append(p.serialize())

	var s_data: Array = []
	for s in salt_pans.values():
		s_data.append(s.serialize())

	return {
		"plots": p_data,
		"salt_pans": s_data
	}


func deserialize(data: Dictionary) -> void:
	plots.clear()
	salt_pans.clear()

	if data.has("plots"):
		for p_dict in data["plots"]:
			var plot: CropPlot = CropPlot.deserialize(p_dict)
			plots[plot.pos] = plot

	if data.has("salt_pans"):
		for s_dict in data["salt_pans"]:
			var pan: SaltPan = SaltPan.deserialize(s_dict)
			salt_pans[pan.pos] = pan
