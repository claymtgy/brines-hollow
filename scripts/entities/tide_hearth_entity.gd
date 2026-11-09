class_name TideHearthEntity
extends WorldEntity
## The Tide Hearth: the heart of your village. Build one and Brine's Hollow is founded around
## it: the town's boundary is measured from here (80 m for a camp, growing with each tier),
## villagers gather here to eat, and the town depot (what your villagers make) is collected
## here. Its fire counts as light. Only one hearth burns at a time: building another moves
## the town's heart.

const U := VoxelWorld.VS * 0.5

var _claim_t := 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"tide_hearth", "Tide Hearth", p_coord)
	entity_type = EntityType.WORKSTATION
	size = Vector3(16, 14, 16) * U


func _build_visuals() -> void:
	var g := Prefabs.Grid.new(16, 16, 16)
	for z in 16:
		for x in 16:
			var d := Vector2(x - 7.5, z - 7.5).length()
			if d <= 7.8 and d > 5.2:
				for y in 4:
					g.setv(x, y, z, Palette.COBBLE if (x + y * 2 + z) % 4 != 0 else Palette.SANDSTONE_C)
			elif d <= 5.2:
				g.setv(x, 0, z, Palette.STONE)
				if d <= 3.0:
					g.setv(x, 1, z, Palette.LANTERN)          # the coals
	# driftwood logs stacked in a cone over the fire
	for k in 6:
		var a := k * TAU / 6.0
		for t in 7:
			var r := 3.5 - t * 0.45
			g.setv(roundi(7.5 + cos(a) * r), 2 + t, roundi(7.5 + sin(a) * r), Palette.DRIFTWOOD if k % 2 == 0 else Palette.TRUNK)
	g.setv(7, 3, 7, Palette.LANTERN)
	g.setv(8, 4, 8, Palette.LANTERN)
	# a brass tide-gauge post with a ring of tide marks
	g.box(14, 0, 1, 14, 14, 1, Palette.DARK_WOOD)
	for y in [5, 8, 11]:
		g.setv(14, y, 2, Palette.METAL)
	g.box(13, 14, 0, 15, 15, 2, Palette.BUOY)
	_mesh_instance = _voxel_model(g)


func emits_light() -> bool:
	return true


func _village() -> SettlementManager:
	if manager == null or manager.main == null:
		return null
	return manager.main.get("village")


## Host: this hearth is the town's heart (the newest one wins).
func server_tick(delta: float, _env: Dictionary) -> bool:
	_claim_t -= delta
	if _claim_t > 0.0:
		return false
	_claim_t = 2.0
	var v := _village()
	if v == null:
		return false
	if not v.hearth_placed or v.hearth_pos != grid_coord:
		var first := not v.hearth_placed
		v.found_at(grid_coord)
		var vm: Node = manager.main.get("village_mgr")
		if vm != null and vm.has_method("on_hearth_founded"):
			vm.on_hearth_founded(first)
	return false


func get_interaction_prompt(_player: Player) -> String:
	var v := _village()
	var n := v.depot_count() if v != null else 0
	if n > 0:
		return "F  Tide Hearth: town report, and collect the depot (%d goods)" % n
	return "F  Tide Hearth: town report"


func client_interact(player: Player) -> void:
	interacted.emit(player)
	manager.request_action(self, &"collect", {})


func server_action(action: StringName, _args: Dictionary, _peer: int) -> Dictionary:
	if action != &"collect":
		return {}
	var v := _village()
	if v == null:
		return {}
	var goods := v.collect_depot()
	var vm: Node = manager.main.get("village_mgr")
	if vm != null and vm.has_method("sync_village"):
		vm.sync_village()
	var toast := v.report()
	if not goods.is_empty():
		var n := 0
		for gd: Array in goods:
			n += int(gd[1])
		toast += "  ·  collected %d goods from the depot" % n
	return {"grant": goods, "toast": toast}
