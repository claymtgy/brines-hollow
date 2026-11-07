extends SceneTree
## Village gameplay: world-scale home detection, recruitment into homes, villager A*,
## and server-side trade validation.
##   godot --headless --path . -s tests/test_village_npcs.gd

var passed := 0
var total := 0
var solids := {}


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func solid(p: Vector3i) -> bool:
	return solids.has(p)


func ceiling(p: Vector3i) -> bool:
	for k in range(1, RoomDetector.CEILING_REACH + 1):
		if solids.has(p + Vector3i(0, k, 0)):
			return true
	return false


func box(a: Vector3i, b: Vector3i, on := true) -> void:
	for y in range(a.y, b.y + 1):
		for z in range(a.z, b.z + 1):
			for x in range(a.x, b.x + 1):
				if on:
					solids[Vector3i(x, y, z)] = true
				else:
					solids.erase(Vector3i(x, y, z))


## A 16 x 16 hut, walls 14 high, flat roof, with a doorway (door_w x door_h) and a window.
func build_hut(door_w: int, door_h: int, roof := true) -> void:
	solids.clear()
	box(Vector3i(-10, -1, -10), Vector3i(30, -1, 30))           # ground
	box(Vector3i(0, 0, 0), Vector3i(15, 13, 0))                 # walls
	box(Vector3i(0, 0, 15), Vector3i(15, 13, 15))
	box(Vector3i(0, 0, 0), Vector3i(0, 13, 15))
	box(Vector3i(15, 0, 0), Vector3i(15, 13, 15))
	if roof:
		box(Vector3i(0, 14, 0), Vector3i(15, 14, 15))
	box(Vector3i(4, 0, 0), Vector3i(4 + door_w - 1, door_h - 1, 0), false)   # doorway
	box(Vector3i(15, 6, 6), Vector3i(15, 9, 9), false)                       # window


func _init() -> void:
	ItemDB.init_db()
	# ---------------------------------------------------------------- homes
	var bed := Vector3i(10, 0, 10)
	var lamp := Vector3i(7, 12, 7)
	build_hut(7, 12)
	solids[lamp] = true
	var fx := {bed: "bed", lamp: "light"}
	var r := RoomDetector.scan_home(bed, solid, ceiling, fx)
	check(r.is_valid, "roofed hut with bed, light and a 7x12 doorway is a home (%s)" % r.error_message)
	check(r.volume >= RoomDetector.HOME_MIN_VOLUME and r.volume < 16 * 16 * 15, "fill stays inside the hut (volume %d)" % r.volume)
	check(r.has_door, "doorway detected as the entrance")
	r = RoomDetector.scan_home(bed, solid, ceiling, {lamp: "light"})
	check(not r.is_valid and not r.has_bed, "no bed -> not a home")
	r = RoomDetector.scan_home(bed, solid, ceiling, {bed: "bed"})
	check(not r.is_valid and not r.has_light, "no light -> not a home")
	build_hut(7, 6)
	solids[lamp] = true
	r = RoomDetector.scan_home(bed, solid, ceiling, fx)
	check(not r.has_door and not r.is_valid, "a 1.1 m opening is a window, not a door")
	build_hut(7, 12, false)
	r = RoomDetector.scan_home(bed, solid, ceiling, fx)
	check(not r.is_valid and not r.has_roof, "roofless walls are not a home")

	# ---------------------------------------------------------------- recruitment
	build_hut(7, 12)
	solids[lamp] = true
	r = RoomDetector.scan_home(bed, solid, ceiling, fx)
	var town := SettlementManager.new(Vector3i.ZERO, "Test Cove")
	var mara := DrifterDef.new(&"drifter_0", "Mara", DrifterDef.Profession.FISHER)
	town.recruit_drifter(mara)
	check(mara.is_homeless(), "recruited before any home: homeless")
	var rid := town.register_home(r, bed)
	check(rid == 0 and mara.assigned_room_id == 0, "registering a home moves the homeless drifter in")
	check(town.register_home(r, bed) == 0 and town.rooms.size() == 1, "same bed doesn't register twice")
	var broken := RoomDetector.RoomValidationResult.new()
	town.update_home(0, broken)
	check(town.valid_room_count() == 0 and town.get_vacant_room_id() == -1, "a broken home stops counting")
	town.update_home(0, r)
	check(town.valid_room_count() == 1, "fixing it restores the home")
	var tobin := DrifterDef.new(&"drifter_1", "Tobin", DrifterDef.Profession.CARPENTER)
	check(town.get_vacant_room_id() == -1, "no vacancy once Mara lives there")
	town.recruit_drifter(tobin)
	check(tobin.is_homeless(), "second drifter waits for another home")
	var data := town.serialize()
	var town2 := SettlementManager.new()
	town2.deserialize(data)
	check(town2.find_room_by_bed(bed) == 0 and town2.drifters.size() == 2, "homes and drifters survive save/load")

	# ---------------------------------------------------------------- A*
	solids.clear()
	box(Vector3i(-20, -1, -20), Vector3i(40, -1, 40))      # flat ground at y=0
	box(Vector3i(10, 0, -20), Vector3i(10, 12, 40))        # wall along x=10 ...
	box(Vector3i(10, 0, 20), Vector3i(10, 12, 23), false)  # ... with a gap at z 20..23
	var stand := func(x: int, y: int, z: int) -> bool:
		if not (solids.has(Vector3i(x, y - 1, z)) or solids.has(Vector3i(x + 1, y - 1, z))
				or solids.has(Vector3i(x, y - 1, z + 1)) or solids.has(Vector3i(x + 1, y - 1, z + 1))):
			return false
		for k in 9:
			for c: Vector3i in [Vector3i(x, y + k, z), Vector3i(x + 1, y + k, z), Vector3i(x, y + k, z + 1), Vector3i(x + 1, y + k, z + 1)]:
				if solids.has(c):
					return false
		return true
	var pf := VillagePath.new(stand)
	var path := pf.find_path(Vector3i(0, 0, 0), Vector3i(20, 0, 0))
	check(not path.is_empty() and path[-1] == Vector3i(20, 0, 0), "path found around the wall (%d steps)" % path.size())
	var through_gap := false
	for c: Vector3i in path:
		if c.x == 10 and c.z >= 20 and c.z <= 22:
			through_gap = true
	check(through_gap, "path goes through the gap in the wall")
	# steps: a 3-voxel ledge is climbable, a 4-voxel one is not
	solids.clear()
	box(Vector3i(-20, -1, -20), Vector3i(40, -1, 40))
	box(Vector3i(6, 0, -20), Vector3i(40, 2, 40))          # ledge 3 high from x=6
	pf = VillagePath.new(stand)
	path = pf.find_path(Vector3i(0, 0, 0), Vector3i(14, 3, 0))
	check(not path.is_empty() and path[-1].y == 3, "climbs a 3-voxel (0.54 m) step")
	solids.clear()
	box(Vector3i(-20, -1, -20), Vector3i(40, -1, 40))
	box(Vector3i(6, 0, -6), Vector3i(40, 3, 6))            # 4 high, but walk-around exists
	box(Vector3i(6, 0, -20), Vector3i(8, 3, 40))           # ... make it a full barrier
	pf = VillagePath.new(stand)
	path = pf.find_path(Vector3i(0, 0, 0), Vector3i(14, 4, 0))
	check(path.is_empty() or path[-1].x < 6, "won't climb a 4-voxel (0.72 m) wall")

	# ---------------------------------------------------------------- trade
	var m := MerchantBoat.new("Test Galleon", MerchantBoat.MerchantType.TRADE_GALLEON)
	var stock0 := m.stock.get_item_count(&"sea_brass_ingot")
	check(TradeRules.server_buy(m, &"sea_brass_ingot", 2) == 50 and m.stock.get_item_count(&"sea_brass_ingot") == stock0 - 2, "buy charges 25 each and takes stock")
	check(TradeRules.server_buy(m, &"sea_brass_ingot", 999) == -1, "can't buy more than the merchant has")
	check(TradeRules.server_buy(m, &"stone", 1) == -1, "can't buy what isn't for sale")
	check(TradeRules.server_sell(m, &"silver_mackerel", 5) == 20, "sell pays the merchant's price")
	check(TradeRules.server_sell(m, &"diving_rebreather", 1) == -1, "merchant refuses goods they don't buy")
	var f := TradeRules.server_fulfill(m, &"manifest_cured_fish")
	check(int(f.get("brass", 0)) == 140 and int(f.get("scrip", 0)) == 10, "manifest pays 140 brass + 10 scrip")
	check(TradeRules.server_fulfill(m, &"manifest_cured_fish").is_empty(), "a manifest can only be shipped once")
	var replica := TradeRules.deserialize_merchant(TradeRules.serialize_merchant(m))
	check(replica.stock.get_item_count(&"sea_brass_ingot") == m.stock.get_item_count(&"sea_brass_ingot") and replica.active_contracts[0].is_fulfilled,
			"merchant stock and contracts replicate to clients")

	print("Summary: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
