class_name SettlementManager
extends RefCounted
## Manages the player's village, municipal boundaries, housing, and drifters.

signal town_tier_upgraded(new_tier: TownTier)
signal drifter_recruited(drifter: DrifterDef)
signal drifter_assigned_room(drifter: DrifterDef, room_id: int)
signal room_registered(room_id: int, quality_score: int)

enum TownTier {
	CAMP,       ## 1-3 villagers; basic hearth
	HAMLET,     ## 4-8 villagers; wooden pier, 3+ houses
	VILLAGE,    ## 9-16 villagers; town bell, workshops
	PORT        ## 17+ villagers; lighthouse, deep trade galleon dock
}

var settlement_name: String = "Brine's Hollow"
var hearth_pos: Vector3i = Vector3i.ZERO
var territory_radius_m: float = 80.0
var current_tier: TownTier = TownTier.CAMP

var rooms: Array[Dictionary] = []           ## Validated housing records
var drifters: Array[DrifterDef] = []        ## Recruited villagers
var town_depot: StorageContainer            ## Automated shared village stockpile
var hearth_placed := false                  ## a Tide Hearth has founded the town
## Town conditions, measured by VillageManager (authority) every few seconds:
var food_kinds := 0                         ## distinct foods in the depot and pantry barrels
var safety := 0.5                           ## 0..1: lanterns, the harbour bell
var _morale_t := 0.0


func _init(p_hearth_pos: Vector3i = Vector3i.ZERO, p_name: String = "Brine's Hollow") -> void:
	hearth_pos = p_hearth_pos
	settlement_name = p_name
	town_depot = StorageContainer.new("Town Depot", 36)
	ItemDB.init_db()


# -------------------------------------------------------------------------
# Housing Management
# -------------------------------------------------------------------------

## Validates and registers a room around interior coordinate start_pos.
## Returns room index (>=0) if valid, or -1 if invalid.
func validate_and_register_room(start_pos: Vector3i, query_voxel: Callable) -> int:
	var result: RoomDetector.RoomValidationResult = RoomDetector.validate_room(start_pos, query_voxel)
	if not result.is_valid:
		return -1

	var room_record: Dictionary = {
		"id": rooms.size(),
		"center": start_pos,
		"bounds_min": result.room_bounds_min,
		"bounds_max": result.room_bounds_max,
		"volume": result.volume,
		"quality": result.quality_score,
		"assigned_drifter_id": &""
	}
	rooms.append(room_record)
	room_registered.emit(room_record["id"], result.quality_score)
	_check_tier_progression()
	return room_record["id"]


func get_vacant_room_id() -> int:
	for r in rooms:
		if r["assigned_drifter_id"] == &"" and r.get("valid", true):
			return r["id"]
	return -1


## World-scale homes (RoomDetector.scan_home): one record per bed.
## Returns the room id; an existing record for the same bed is updated in place.
func register_home(result: RoomDetector.RoomValidationResult, bed: Vector3i) -> int:
	var rid := find_room_by_bed(bed)
	if rid >= 0:
		update_home(rid, result)
		return rid
	var room_record: Dictionary = {
		"id": rooms.size(),
		"center": bed,
		"bed": bed,
		"bounds_min": result.room_bounds_min,
		"bounds_max": result.room_bounds_max,
		"volume": result.volume,
		"quality": result.quality_score,
		"valid": true,
		"assigned_drifter_id": &""
	}
	rooms.append(room_record)
	room_registered.emit(room_record["id"], result.quality_score)
	# Homeless villagers move in straight away.
	for d in drifters:
		if d.is_homeless():
			assign_drifter_to_room(d.id, room_record["id"])
			break
	_check_tier_progression()
	return room_record["id"]


## Re-validation after nearby edits. Invalid homes keep their record (and resident) but
## don't count until they're fixed.
func update_home(room_id: int, result: RoomDetector.RoomValidationResult) -> void:
	if room_id < 0 or room_id >= rooms.size():
		return
	var r: Dictionary = rooms[room_id]
	r["valid"] = result.is_valid
	if result.is_valid:
		r["bounds_min"] = result.room_bounds_min
		r["bounds_max"] = result.room_bounds_max
		r["volume"] = result.volume
		r["quality"] = result.quality_score


func find_room_by_bed(bed: Vector3i) -> int:
	for r in rooms:
		if r.has("bed") and r["bed"] == bed:
			return r["id"]
	return -1


func valid_room_count() -> int:
	var n := 0
	for r in rooms:
		if r.get("valid", true):
			n += 1
	return n


# -------------------------------------------------------------------------
# Drifter Recruitment & Assignment
# -------------------------------------------------------------------------

func recruit_drifter(drifter: DrifterDef) -> bool:
	if has_drifter(drifter.id):
		return false

	drifters.append(drifter)
	drifter_recruited.emit(drifter)

	# Auto-assign to first vacant room if available
	var vacant_id: int = get_vacant_room_id()
	if vacant_id >= 0:
		assign_drifter_to_room(drifter.id, vacant_id)

	_check_tier_progression()
	return true


func has_drifter(drifter_id: StringName) -> bool:
	for d in drifters:
		if d.id == drifter_id:
			return true
	return false


func get_drifter(drifter_id: StringName) -> DrifterDef:
	for d in drifters:
		if d.id == drifter_id:
			return d
	return null


func assign_drifter_to_room(drifter_id: StringName, room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false

	var drifter: DrifterDef = get_drifter(drifter_id)
	if not drifter:
		return false

	# Clear previous assignment
	if drifter.assigned_room_id >= 0 and drifter.assigned_room_id < rooms.size():
		rooms[drifter.assigned_room_id]["assigned_drifter_id"] = &""

	rooms[room_id]["assigned_drifter_id"] = drifter_id
	drifter.assigned_room_id = room_id
	drifter.morale = min(1.0, drifter.morale + 0.15) # Housing comfort boosts morale
	drifter_assigned_room.emit(drifter, room_id)
	return true


# -------------------------------------------------------------------------
# Progression & Simulation
# -------------------------------------------------------------------------

## A Tide Hearth was built at `c`: the town is founded (or its heart moved) here.
func found_at(c: Vector3i) -> void:
	hearth_pos = c
	hearth_placed = true
	_check_tier_progression()


func _check_tier_progression() -> void:
	var count: int = drifters.size()
	var new_tier: TownTier = TownTier.CAMP

	if not hearth_placed:
		new_tier = TownTier.CAMP           # a town needs its hearth before it can grow
	elif count >= 17:
		new_tier = TownTier.PORT
	elif count >= 9:
		new_tier = TownTier.VILLAGE
	elif count >= 4 and rooms.size() >= 3:
		new_tier = TownTier.HAMLET

	if new_tier != current_tier:
		current_tier = new_tier
		match current_tier:
			TownTier.HAMLET: territory_radius_m = 100.0
			TownTier.VILLAGE: territory_radius_m = 130.0
			TownTier.PORT: territory_radius_m = 160.0
		town_tier_upgraded.emit(current_tier)


func get_town_morale() -> float:
	if drifters.is_empty():
		return 1.0
	var sum := 0.0
	for d in drifters:
		sum += d.morale
	return sum / float(drifters.size())


const TIER_NAMES := ["Castaway Camp", "Coastal Hamlet", "Brine Village", "Thriving Port Town"]


## Where a villager's morale is heading: a dry home (and how good it is), the variety of food
## in the town's stores, how safe the town feels, and having a hearth to gather round.
## Returns {total, home, food, safety, hearth}. Morale drives work speed: 0.7x to 1.3x.
func morale_parts(d: DrifterDef) -> Dictionary:
	var home := 0.12
	if not d.is_homeless() and d.assigned_room_id < rooms.size():
		var r: Dictionary = rooms[d.assigned_room_id]
		home = 0.2 if not r.get("valid", true) else 0.32 + 0.18 * clampf(float(r.get("quality", 10)) / 100.0, 0.0, 1.0)
	var food: float = [0.0, 0.08, 0.15, 0.22, 0.26, 0.3][clampi(food_kinds, 0, 5)]
	var safe := 0.22 * clampf(safety, 0.0, 1.0)
	var hearth := 0.08 if hearth_placed else 0.0
	return {"total": clampf(home + food + safe + hearth, 0.0, 1.0), "home": home, "food": food, "safety": safe, "hearth": hearth}


## Simulation tick for routines and work shifts
func tick_settlement(delta_sec: float, day_fraction: float) -> void:
	_morale_t -= delta_sec
	var drift := _morale_t <= 0.0
	if drift:
		_morale_t = 5.0
	for d in drifters:
		d.update_routine(day_fraction)
		d.tick_work(delta_sec, town_depot)
		if drift:
			# morale settles toward its target over a few in-game hours
			d.morale = move_toward(d.morale, float(morale_parts(d).total), 0.02)


func depot_count() -> int:
	var n := 0
	for s: ItemSlot in town_depot.inventory.slots:
		if s != null and not s.is_empty():
			n += s.count
	return n


## Empties the town depot. Returns [[item_id, count], ...] for whoever collected it.
func collect_depot() -> Array:
	var out: Array = []
	for s: ItemSlot in town_depot.inventory.slots:
		if s != null and not s.is_empty():
			out.append([s.item_id, s.count])
	for g: Array in out:
		town_depot.inventory.remove_item(g[0], int(g[1]))
	return out


## One line for the hearth: tier, people, morale and what's pulling it down.
func report() -> String:
	if not hearth_placed:
		return "%s has no hearth yet: build a Tide Hearth to found the town." % settlement_name
	var m := get_town_morale()
	var hint := ""
	var homeless := 0
	for d in drifters:
		if d.is_homeless():
			homeless += 1
	if homeless > 0:
		hint = "%d need a home" % homeless
	elif food_kinds < 3:
		hint = "stock more kinds of food (pantry barrels)"
	elif safety < 0.6:
		hint = "light the town with lanterns, hang a harbour bell"
	else:
		hint = "the town is content"
	return "%s, a %s: %d villager%s, morale %d%% (work %+d%%)  ·  %s" % [settlement_name,
		TIER_NAMES[clampi(int(current_tier), 0, 3)], drifters.size(), "" if drifters.size() == 1 else "s",
		int(m * 100.0), int(round((0.7 + m * 0.6 - 1.0) * 100.0)), hint]


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func serialize() -> Dictionary:
	var r_data: Array = []
	for r in rooms:
		r_data.append(r.duplicate(true))

	var d_data: Array = []
	for d in drifters:
		d_data.append(d.serialize())

	return {
		"name": settlement_name,
		"hearth": {"x": hearth_pos.x, "y": hearth_pos.y, "z": hearth_pos.z},
		"radius": territory_radius_m,
		"tier": current_tier,
		"hearth_placed": hearth_placed,
		"food_kinds": food_kinds,
		"safety": safety,
		"rooms": r_data,
		"drifters": d_data,
		"depot": town_depot.serialize()
	}


func deserialize(data: Dictionary) -> void:
	settlement_name = data.get("name", "Brine's Hollow")
	var h: Dictionary = data.get("hearth", {})
	hearth_pos = Vector3i(h.get("x", 0), h.get("y", 0), h.get("z", 0))
	territory_radius_m = float(data.get("radius", 80.0))
	current_tier = int(data.get("tier", 0))
	hearth_placed = bool(data.get("hearth_placed", false))
	food_kinds = int(data.get("food_kinds", 0))
	safety = float(data.get("safety", 0.5))

	rooms.clear()
	if data.has("rooms"):
		for r in data["rooms"]:
			rooms.append(r.duplicate(true))

	drifters.clear()
	if data.has("drifters"):
		for d_dict in data["drifters"]:
			drifters.append(DrifterDef.deserialize(d_dict))

	if data.has("depot"):
		town_depot.deserialize(data["depot"])
