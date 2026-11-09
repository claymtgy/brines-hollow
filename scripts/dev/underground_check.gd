class_name UndergroundCheck
extends RefCounted
## --undercheck[=SHOT_DIR]: the old brass mines, flooded sumps, springs and wells in a real
## world: planned, stamped, stocked, and working.

const VS := VoxelWorld.VS


static func run(main: Node, dir: String) -> void:
	var p: Player = main.player
	p.input_enabled = false
	var tree: SceneTree = main.get_tree()
	await tree.create_timer(1.0).timeout
	var gen: WorldGen = main.world.gen
	var hut: Vector3 = Vector3(gen.starter.hut)
	print("[under] %d mines, %d sumps, %d springs" % [gen.mines.size(), gen.sumps.size(), gen.springs.size()])
	for m: Dictionary in gen.mines:
		print("[under] mine on island %d (%s), %.0f m from the hut, entrance %s" % [int(m.island),
				main.atlas.name_of(int(m.island)), Vector2(m.entrance.x - hut.x, m.entrance.z - hut.z).length() * VS, m.entrance])
	main.hud.show_hud(false)
	if not gen.mines.is_empty():
		var m: Dictionary = gen.mines[0]
		var d: Vector2i = m.dir
		var ent: Vector3 = (m.entrance as Vector3) * VS
		_put(main, ent - Vector3(d.x, 0, d.y) * 6.0)
		main.sky.time_of_day = 0.45
		main.rig.yaw = atan2(-d.x, -d.y)
		main.rig.pitch = -0.2
		main.rig.dist = 6.0
		await tree.create_timer(4.0).timeout
		if dir != "":
			await main._shot(dir, "mine_portal")
		var gal: Vector3i = m.gallery
		var cal := 0
		var cop := 0
		for y in range(gal.y, gal.y + 16):
			for z in range(gal.z - 14, gal.z + 15):
				for x in range(gal.x - 14, gal.x + 15):
					var v: int = main.world.get_voxel(x, y, z)
					if v == Palette.CALAMINE:
						cal += 1
					elif v == Palette.COPPER_VEIN:
						cop += 1
		print("[under] gallery walls: %d calamine, %d copper voxels" % [cal, cop])
		print("[under] strongbox: %s" % _entity_near(main, m.chest, 5.0, "Miner's Strongbox"))
		var gp := (Vector3(gal) + Vector3(0.5, 0, 0.5)) * VS - Vector3(absi(d.y), 0, absi(d.x)) * 1.4
		_put(main, gp)
		await tree.create_timer(3.0).timeout
		_put(main, gp)
		main.rig.yaw = atan2(d.x, d.y)
		main.rig.pitch = -0.15
		main.rig.dist = 3.0
		main.sky.time_of_day = 0.95
		await tree.create_timer(2.0).timeout
		if dir != "":
			await main._shot(dir, "mine_gallery")
	if not gen.sumps.is_empty():
		var s: Dictionary = gen.sumps[0]
		var top: Vector3i = s.top
		var wy: float = main.sky.water_level_m()
		var flooded := 0
		var air := 0
		var ch: Vector3i = s.chest
		_put(main, Vector3(top) * VS + Vector3(0.5, 0, 0.5) * VS)
		await tree.create_timer(3.0).timeout
		for y in range(ch.y, top.y):
			if main.world.get_voxel(top.x, y, top.z) == 0:
				air += 1
				if (y + 0.5) * VS < wy:
					flooded += 1
		print("[under] sump shaft: %d open voxels, %d under the water line; depth %d voxels (%.1f m)" % [air, flooded, int(s.depth), int(s.depth) * VS])
		print("[under] sunken cache: %s" % _entity_near(main, s.chest, 6.0, "Sunken Cache"))
	var springs := 0
	var spring: WaterSourceEntity = null
	for e: WorldEntity in main.entities.entities.values():
		if e is WaterSourceEntity and not (e as WaterSourceEntity).is_well:
			springs += 1
			spring = e
	print("[under] spring entities: %d" % springs)
	if spring != null:
		var r: Dictionary = spring.server_action(&"draw", {}, 1)
		print("[under] spring gives %s" % [r.get("grant")])
		for e: WorldEntity in main.entities.entities.values():
			if e is WaterSourceEntity and not (e as WaterSourceEntity).is_well:
				print("[under] spring at %s, surface %d" % [e.grid_coord, gen.col_h(e.grid_coord.x, e.grid_coord.z)])
		_put(main, spring.position + Vector3(0.3, 0, 0.3))
		await tree.create_timer(3.0).timeout
		_put(main, spring.position + Vector3(0.3, 0, 0.3))
		main.rig.yaw = atan2(1.0, 1.0)
		main.rig.pitch = -0.6
		main.rig.dist = 2.2
		await tree.create_timer(3.0).timeout
		if dir != "":
			await main._shot(dir, "spring")
	# A stone well at home: four flasks, then dry until it seeps back.
	var w := WaterSourceEntity.make_well(Vector3i.ZERO)
	var g1: Dictionary = w.server_action(&"draw", {}, 1)
	var g2: Dictionary = w.server_action(&"draw", {}, 1)
	w.server_tick(WaterSourceEntity.WELL_SEEP_SEC + 1.0, {})
	print("[under] well: first draw %s, again %s, after a while %d stored" % [g1.get("grant"), g2.get("grant", "nothing"), w.stored])
	w.free()
	var wells := 0
	for e: WorldEntity in main.entities.entities.values():
		if e is WaterSourceEntity and (e as WaterSourceEntity).is_well:
			wells += 1
	print("[under] village wells: %d (villages %d)" % [wells, gen.villages.size()])
	p.inventory.add_item(&"spring_water", 1)
	print("[under] drink spring water: %s, fine brass recipe: %s" % [p.vitality.eat_food(&"spring_water", p.inventory),
			RecipeDB.has_recipe(&"furnace_fine_brass")])
	# Shipwrecks: a locker each, with a rare scroll; reading one teaches the recipe.
	print("[under] %d wrecks" % gen.wrecks.size())
	for wr: Dictionary in gen.wrecks:
		var c: Vector3i = wr.center
		var scroll := "none"
		for k: Vector3i in main.entities.entities:
			var e: WorldEntity = main.entities.entities[k]
			if e.entity_name == "Wreck Locker" and Vector3(k - (wr.chest as Vector3i)).length() < 8.0:
				for sl in (e as ChestEntity).container.inventory.slots:
					if sl != null and String(sl.item_id).begins_with(RecipeBook.SCROLL_PREFIX):
						scroll = String(sl.item_id)
		print("[under] wreck on island %d (%s), %.0f m from the hut, locker scroll: %s" % [int(wr.island),
				main.atlas.name_of(int(wr.island)), Vector2(c.x - hut.x, c.z - hut.z).length() * VS, scroll])
	print("[under] fine brass locked: %s, stone well locked: %s" % [not p.recipes.knows(&"furnace_fine_brass"), not p.recipes.knows(&"place_stone_well")])
	p.inventory.add_item(RecipeBook.scroll_item(&"furnace_fine_brass"), 1)
	print("[under] after reading the scroll: knows fine brass %s, scroll kept %d" % [p.recipes.knows(&"furnace_fine_brass"),
			p.inventory.get_item_count(RecipeBook.scroll_item(&"furnace_fine_brass"))])
	if not gen.wrecks.is_empty() and dir != "":
		var wr: Dictionary = gen.wrecks[0]
		var d: Vector2i = wr.dir
		var at := Vector3(wr.center) * VS - Vector3(d.x, 0, d.y) * 6.0
		_put(main, at)
		await tree.create_timer(3.0).timeout
		_put(main, at)
		main.sky.time_of_day = 0.42
		main.rig.yaw = atan2(-d.x, -d.y) + 0.9
		main.rig.pitch = -0.75
		main.rig.dist = 14.0
		await tree.create_timer(3.0).timeout
		await main._shot(dir, "wreck")
	tree.quit()


static func _entity_near(main: Node, at: Vector3i, r: float, want: String) -> String:
	for k: Vector3i in main.entities.entities:
		if Vector3(k - at).length() < r:
			var e: WorldEntity = main.entities.entities[k]
			if e.entity_name == want:
				return "%s at %s" % [want, k]
	return "MISSING"


static func _put(main: Node, at: Vector3) -> void:
	var p: Player = main.player
	# Unloaded chunks count as solid: hold the player still (the check only looks around),
	# or the unstuck nudge walks them up to the surface while the area streams in.
	p.set_process(false)
	p.set_physics_process(false)
	var x := floori(at.x / VS)
	var z := floori(at.z / VS)
	var col := Vector2i(x >> 5, z >> 5)
	if not main.world.store.is_column_generated(col):
		main.world.store.generate_column(col)
	var y0 := floori(at.y / VS) + 4
	var y := y0
	for yy in range(y0, y0 - 40, -1):
		if main.world.get_voxel(x, yy, z) != 0 and main.world.get_voxel(x, yy + 1, z) == 0 and main.world.get_voxel(x, yy + 2, z) == 0:
			y = yy + 1
			break
	p.position = Vector3(at.x, y * VS + 0.05, at.z)
