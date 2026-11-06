class_name NetFarm
extends FarmManager
## FarmManager that keeps the host / dedicated server authoritative in co-op.
##
## Solo, host and server: behaves exactly like FarmManager, and reports every change
## to the Session so it can be broadcast and saved.
## Clients: predict locally for instant feedback, then send the action to the server.
## The server validates against its own copy, broadcasts the resulting plot state to
## everyone (which corrects any misprediction), and grants harvest items only to the
## player who asked. Two players can't both harvest the same crop.

var session: Node = null   # Session; null in tests / before networking is up


func _is_authority() -> bool:
	return session == null or session.is_authority()


func till_plot(pos: Vector3i) -> CropPlot:
	var existed := plots.has(pos)
	var plot := super.till_plot(pos)
	if not existed:
		_changed(pos, {"a": "till"})
	return plot


func plant_from_inventory(pos: Vector3i, inv: Inventory) -> bool:
	if not super.plant_from_inventory(pos, inv):
		return false
	var plot: CropPlot = get_plot(pos)
	_changed(pos, {"a": "plant", "crop": plot.crop_id})
	return true


func water_plot(pos: Vector3i, amount: float = 0.5, water_salinity: float = 0.0) -> bool:
	if not super.water_plot(pos, amount, water_salinity):
		return false
	_changed(pos, {"a": "water", "amount": amount, "sal": water_salinity})
	return true


func harvest_to_inventory(pos: Vector3i, inv: Inventory, rng: RandomNumberGenerator = null) -> bool:
	if _is_authority():
		if not super.harvest_to_inventory(pos, inv, rng):
			return false
		_changed(pos, {})
		return true
	# Client: clear the plot visually now; the server decides what we actually get.
	var plot: CropPlot = get_plot(pos)
	if plot == null or not plot.is_mature():
		return false
	plot.harvest(rng)
	session.send_farm_action(pos, {"a": "harvest"})
	return true


func harvest_salt_to_inventory(pos: Vector3i, inv: Inventory) -> int:
	if _is_authority():
		var n := super.harvest_salt_to_inventory(pos, inv)
		if n > 0:
			_changed(pos, {})
		return n
	var pan: SaltPan = salt_pans.get(pos, null)
	if pan == null or pan.accumulated_salt <= 0:
		return 0
	var predicted: int = pan.accumulated_salt
	pan.harvest()
	session.send_farm_action(pos, {"a": "salt"})
	return predicted


## Authority: broadcast the new state. Client: forward the action to the server.
func _changed(pos: Vector3i, action: Dictionary) -> void:
	if session == null:
		return
	if _is_authority():
		session.broadcast_farm_cell(pos)
	elif not action.is_empty():
		session.send_farm_action(pos, action)


# ---------------------------------------------------------------- server side

## Applies a client's farm action on the authoritative copy.
## Returns items to grant the requester: [[item_id, count], ...].
func server_apply(pos: Vector3i, action: Dictionary) -> Array:
	var grants := []
	match String(action.get("a", "")):
		"till":
			super.till_plot(pos)
		"plant":
			var plot: CropPlot = get_plot(pos)
			if plot == null:
				plot = super.till_plot(pos)
			var crop := StringName(action.get("crop", ""))
			if plot.is_empty() and CropDB.get_crop(crop) != null:
				plot.plant(crop)
				crop_planted.emit(pos, crop)
			else:
				# Someone else got there first: refund the seed they spent.
				var def: CropDef = CropDB.get_crop(crop)
				if def != null:
					grants.append([def.seed_item_id, 1])
		"water":
			super.water_plot(pos, float(action.get("amount", 0.5)), float(action.get("sal", 0.0)))
		"harvest":
			var plot: CropPlot = get_plot(pos)
			if plot != null and plot.is_mature():
				var crop_id: StringName = plot.crop_id
				var drops: Dictionary = plot.harvest()
				if not drops.is_empty():
					grants.append([StringName(drops["product_id"]), int(drops["product_count"])])
					grants.append([StringName(drops["seed_id"]), int(drops["seed_count"])])
					crop_harvested.emit(pos, crop_id, int(drops["product_count"]))
		"salt":
			var pan: SaltPan = salt_pans.get(pos, null)
			if pan != null and pan.accumulated_salt > 0:
				var n: int = pan.harvest()
				grants.append([&"sea_salt", n])
				salt_harvested.emit(pos, n)
	return grants


## Serialized state of one cell (plot and/or pan), or {} if neither exists.
func cell_state(pos: Vector3i) -> Dictionary:
	var d := {}
	if plots.has(pos):
		d["plot"] = (plots[pos] as CropPlot).serialize()
	if salt_pans.has(pos):
		d["pan"] = (salt_pans[pos] as SaltPan).serialize()
	return d


func apply_cell_state(pos: Vector3i, d: Dictionary) -> void:
	if d.has("plot"):
		plots[pos] = CropPlot.deserialize(d["plot"])
	else:
		plots.erase(pos)
	if d.has("pan"):
		salt_pans[pos] = SaltPan.deserialize(d["pan"])
	else:
		salt_pans.erase(pos)
