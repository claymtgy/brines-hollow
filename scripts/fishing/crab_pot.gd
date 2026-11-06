class_name CrabPot
extends RefCounted
## Passive wicker/iron crab and lobster pot.
## Placed on tidal flats or off docks, consumes bait during high tide, catches shellfish.

signal pot_harvested(count: int)

var pos: Vector3i = Vector3i.ZERO
var bait_item_id: StringName = &""
var bait_count: int = 0
var trapped_catch: Dictionary = {} ## item_id -> count
const MAX_CATCH := 10


func _init(p_pos: Vector3i = Vector3i.ZERO) -> void:
	pos = p_pos


func is_baited() -> bool:
	return bait_item_id != &"" and bait_count > 0


## Adds bait to the pot.
func add_bait(p_id: StringName, p_count: int) -> int:
	if bait_item_id != &"" and bait_item_id != p_id:
		return p_count # Different bait type
	bait_item_id = p_id
	bait_count += p_count
	return 0


## Simulates tidal cycle catch.
## tide_y: current ocean tide height
## rng: random generator
func tick_tidal_cycle(tide_y: float, rng: RandomNumberGenerator = null) -> void:
	# Pot must be submerged in seawater to catch shellfish
	if float(pos.y) > tide_y:
		return

	if not is_baited():
		return

	var r: RandomNumberGenerator = rng if rng != null else RandomNumberGenerator.new()

	# 75% chance per tidal soak to catch shellfish if baited
	if r.randf() < 0.75:
		var catch_id: StringName = &"shore_crab" if r.randf() < 0.65 else &"brine_oyster"
		var catch_cnt: int = r.randi_range(1, 2)

		var current_cnt: int = trapped_catch.get(catch_id, 0)
		var total_trapped: int = 0
		for c in trapped_catch.values():
			total_trapped += c

		if total_trapped < MAX_CATCH:
			var to_add: int = min(catch_cnt, MAX_CATCH - total_trapped)
			trapped_catch[catch_id] = current_cnt + to_add

		# Consume 1 bait
		bait_count -= 1
		if bait_count <= 0:
			bait_item_id = &""


## Empties trapped catch into the player inventory.
func harvest_to_inventory(inv: Inventory) -> int:
	var total_collected: int = 0
	for catch_id in trapped_catch.keys():
		var count: int = trapped_catch[catch_id]
		if count > 0:
			var remainder: int = inv.add_item(catch_id, count)
			var transferred: int = count - remainder
			total_collected += transferred
			trapped_catch[catch_id] = remainder

	if total_collected > 0:
		pot_harvested.emit(total_collected)
	return total_collected


func serialize() -> Dictionary:
	var catch_dict: Dictionary = {}
	for k in trapped_catch:
		catch_dict[String(k)] = trapped_catch[k]

	return {
		"x": pos.x, "y": pos.y, "z": pos.z,
		"bait_id": String(bait_item_id),
		"bait_count": bait_count,
		"catch": catch_dict
	}


static func deserialize(d: Dictionary) -> CrabPot:
	var pot := CrabPot.new(Vector3i(d["x"], d["y"], d["z"]))
	pot.bait_item_id = StringName(d.get("bait_id", ""))
	pot.bait_count = int(d.get("bait_count", 0))
	var raw_catch: Dictionary = d.get("catch", {})
	for k in raw_catch:
		pot.trapped_catch[StringName(k)] = int(raw_catch[k])
	return pot
