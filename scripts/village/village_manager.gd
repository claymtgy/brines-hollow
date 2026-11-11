class_name VillageManager
extends Node
## Village gameplay: home detection, drifters (stranded -> recruited villagers), daily
## routines with voxel pathfinding, and co-op sync. Lives at /root/Main/Village.
##
## Authority (solo / host / dedicated server) simulates everything and broadcasts compact
## NPC states; clients just interpolate. The drifter roster is deterministic from the world
## seed, so every peer builds the same drifters; recruitment and homes live in
## SettlementManager (main.village), which Session already saves and syncs.

const VS := VoxelWorld.VS
const ROSTER := [
	["Mara", DrifterDef.Profession.FISHER], ["Tobin", DrifterDef.Profession.CARPENTER],
	["Elsie", DrifterDef.Profession.FARMER], ["Corwin", DrifterDef.Profession.SMOKER_CHEF],
	["Wren", DrifterDef.Profession.LAMPLIGHTER], ["Hollis", DrifterDef.Profession.TRADER],
]
## Castaways trapped in beached shipwrecks on the outer islands (big archipelago): pinned
## under fallen timbers, so they can only be freed at low water. Recruited, they sail home
## on their own once nobody is watching.
const CASTAWAYS := [
	["Ansel", DrifterDef.Profession.CARPENTER], ["Petra", DrifterDef.Profession.FISHER],
	["Noll", DrifterDef.Profession.TRADER],
]
const VOYAGE_DIST := 160.0      # metres: farther than this from home, a villager sails rather than walks
const INTERACT_RANGE := 2.6
const STATE_HZ := 8.0
const WATCH_RANGE := 90.0       # metres: farther than this from every player, NPCs skip walking
const SCAN_DEBOUNCE := 1.5

var main: Node
var npcs: Array[DrifterNPC] = []
var _ready_done := false
var _scan_t := -1.0             # >= 0: a home scan is pending
var _bed_sig := ""
var _bed_poll_t := 0.0
var _send_t := 0.0
var _path_queue: Array = []     # NPC indices waiting for a route
var _pather: VillagePath
var _ceil_memo := {}
var _ceil_cols := {}            # Vector2i -> [[y_lo, y_hi], ...] spans known to be roofed
var _world_ver := 0
var _prompt_npc: DrifterNPC = null
var _quests_bound := false
var _auto_work_t := 15.0
var _cook_t := 2.0
const LAMP_REFILL_BELOW := 1080.0   # seconds of lighthouse oil: 1.5 in-game days
const LAMP_OIL_SEC := 720.0         # one flask of fish oil, same as the player's refill
var _cook_station := {}         # npc idx -> station cell the cook is tending
var orders_ui: CookOrdersUI


func _ready() -> void:
	name = "Village"


func is_authority() -> bool:
	return not main.is_net or main.multiplayer.multiplayer_peer == null or main.multiplayer.is_server()


# ---------------------------------------------------------------- setup

func _try_init() -> void:
	if _ready_done or main.world == null or not main.world.ready_for_play or main.village == null:
		return
	if main.world.gen == null or main.world.gen.starter.is_empty():
		return
	_ready_done = true
	_pather = VillagePath.new(_standable)
	_build_roster()
	_bind_quests()
	_place_starter_bed()
	if is_authority():
		_ensure_columns(Vector3i(main.world.gen.starter.hut), 2)
		_scan_t = 0.5
	print("[village] %d drifters charted, %d recruited" % [npcs.size(), _recruited_count()])


func _build_roster() -> void:
	var gen: WorldGen = main.world.gen
	var st: Dictionary = gen.starter
	var hut: Vector3i = st.hut
	var rng := RandomNumberGenerator.new()
	rng.seed = gen.seed_value * 7919 + 17
	var taken: Array = []
	for i in ROSTER.size():
		var spot := _find_wreck_spot(hut, rng, taken, 50 + i * 26)
		taken.append(spot)
		var id := StringName("drifter_%d" % i)
		var def: DrifterDef = main.village.get_drifter(id)
		var recruited := def != null
		if def == null:
			def = DrifterDef.new(id, ROSTER[i][0], ROSTER[i][1])
		var npc := DrifterNPC.new()
		npc.name = "Drifter%d" % i
		add_child(npc)
		npc.setup(i, def, (Vector3(spot) + Vector3(0.5, 0.0, 0.5)) * VS, gen.seed_value * 31 + i * 101)
		npc.recruited = recruited
		npc.refresh_label()
		var away := Vector2(spot.x - hut.x, spot.z - hut.z)
		npc.facing = atan2(away.x, away.y)   # stranded drifters look out to sea
		if not recruited:
			_add_wreck_prop(npc)
			_spawn_wreck_gulls(npc.position)
		npcs.append(npc)
	_add_castaways()


## Which wrecks hold a castaway: every other one, from the second nearest out.
static func castaway_wrecks(wreck_count: int) -> Array:
	var out: Array = []
	for k in range(1, wreck_count, 2):
		if out.size() < CASTAWAYS.size():
			out.append(k)
	if out.is_empty() and wreck_count > 0:
		out.append(0)
	return out


## Where a castaway is pinned inside wreck record `w` (voxel cell, feet).
static func castaway_cell(w: Dictionary) -> Vector3i:
	var c: Vector3i = w.center
	var al: Vector2i = w.get("along", Vector2i(absi((w.dir as Vector2i).y), absi((w.dir as Vector2i).x)))
	var d: Vector2i = w.dir
	return Vector3i(c.x - al.x * 6 - d.x, c.y + 1, c.z - al.y * 6 - d.y)


func _add_castaways() -> void:
	var gen: WorldGen = main.world.gen
	var picks := castaway_wrecks(gen.wrecks.size())
	for k in picks.size():
		var w: Dictionary = gen.wrecks[picks[k]]
		var i := npcs.size()
		var id := StringName("castaway_%d" % k)
		var def: DrifterDef = main.village.get_drifter(id)
		var recruited := def != null
		if def == null:
			def = DrifterDef.new(id, CASTAWAYS[k][0], CASTAWAYS[k][1])
		var npc := DrifterNPC.new()
		npc.name = "Castaway%d" % k
		npc.castaway = true
		add_child(npc)
		npc.setup(i, def, (Vector3(castaway_cell(w)) + Vector3(0.5, 0.0, 0.5)) * VS, gen.seed_value * 37 + k * 131)
		npc.recruited = recruited
		npc.refresh_label()
		var d: Vector2i = w.dir
		npc.facing = atan2(d.x, d.y)
		npcs.append(npc)
		if not recruited:
			var smoke := _create_signal_smoke()
			smoke.position = Vector3(0, 0.5, 0)
			npc.add_child(smoke)
			_spawn_wreck_gulls(npc.position)


## Low water: below half tide a castaway's timbers are clear of the sea and can be shifted.
func tide_low() -> bool:
	return main.sky.water_level_m() < VoxelWorld.SEA_MID * VS

## Deterministic beach spot on the home island, roughly `radius` voxels from the hut.
func _find_wreck_spot(hut: Vector3i, rng: RandomNumberGenerator, taken: Array, radius: int) -> Vector3i:
	var gen: WorldGen = main.world.gen
	var nat: ArchipelagoGen = gen.native
	var a0 := rng.randf() * TAU
	for ring in range(0, 14):
		var r := radius + ring * 12
		for k in 24:
			var a := a0 + k * TAU / 24.0
			var x := hut.x + int(cos(a) * r)
			var z := hut.z + int(sin(a) * r)
			var h := nat.column_height(x, z)
			if h < gen.sea_high or h > gen.sea_high + 8 or nat.column_kind(x, z) == 2:
				continue
			var p := Vector3i(x, h + 1, z)
			var ok := true
			for t: Vector3i in taken:
				if Vector2(t.x - p.x, t.z - p.z).length() < 40.0:
					ok = false
					break
			if ok:
				return p
	return Vector3i(hut.x + radius, hut.y, hut.z)


func _create_signal_smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "SignalSmoke"
	p.amount = 28
	p.lifetime = 4.2
	p.preprocess = 2.0
	p.speed_scale = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.2
	p.direction = Vector3(0.05, 1.0, 0.03)
	p.spread = 10.0
	p.gravity = Vector3(0.06, 1.25, 0.03)
	p.initial_velocity_min = 1.1
	p.initial_velocity_max = 1.9
	p.scale_amount_min = 0.7
	p.scale_amount_max = 2.4
	var sm_mat := StandardMaterial3D.new()
	sm_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm_mat.vertex_color_use_as_albedo = true
	var sm_mesh := SphereMesh.new()
	sm_mesh.radius = 0.2
	sm_mesh.height = 0.4
	sm_mesh.material = sm_mat
	p.mesh = sm_mesh
	p.color = Color(0.92, 0.94, 0.96, 0.48)
	return p


func _spawn_wreck_gulls(flock_pos: Vector3) -> void:
	if main == null or main.get("creatures") == null or not is_authority():
		return
	for k in 2:
		var g := main.creatures.spawn(&"gull", flock_pos + Vector3(randf_range(-2.5, 2.5), 8.5 + k * 1.5, randf_range(-2.5, 2.5))) as Gull
		if g != null:
			g.flock_center = flock_pos
			g.circle_r = randf_range(8.0, 13.0)
			g.altitude = 8.5 + k * 1.8


func _add_wreck_prop(npc: DrifterNPC) -> void:
	var g := Prefabs.Grid.new(6, 3, 4)
	g.box(0, 0, 0, 5, 0, 3, Palette.DRIFTWOOD)
	g.box(0, 1, 0, 0, 2, 3, Palette.DARK_WOOD)
	g.box(5, 1, 0, 5, 2, 3, Palette.DARK_WOOD)
	g.box(1, 1, 0, 4, 2, 0, Palette.PLANK)
	g.box(1, 1, 1, 2, 1, 2, Palette.BUOY)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	var mi := MeshInstance3D.new()
	mi.name = "Wreck"
	mi.mesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, mat, mat)
	mi.top_level = true
	mi.position = npc.position + Vector3(0.7, 0.0, -0.4)
	npc.add_child(mi)

	var smoke := _create_signal_smoke()
	smoke.position = Vector3(0.7, 0.4, -0.4)
	npc.add_child(smoke)


## The starter hut gets a bunk inside so it can become the first home.
func _place_starter_bed() -> void:
	# Entities are server-authoritative (agent A): only the host/server places it, and the
	# entity layer broadcasts + saves it. Saved worlds already contain the bunk.
	if main.entities == null or not main.entities.is_authority():
		return
	var st: Dictionary = main.world.gen.starter
	var hut: Vector3i = st.hut
	var fwd: Vector2i = st.front
	var side: Vector2i = st.side
	for off: Vector2i in [Vector2i(-5, 7), Vector2i(-5, -7), Vector2i(-3, 7), Vector2i(-6, 4)]:
		var c := Vector3i(hut.x + fwd.x * off.x + side.x * off.y, hut.y + 1, hut.z + fwd.y * off.x + side.y * off.y)
		if main.entities.has_entity_at(c):
			return
		var clear := true
		for k in 3:
			if main.world.get_voxel(c.x, c.y + k, c.z) != 0:
				clear = false
		if clear:
			main.entities._authority_place(&"fisher_bed", c, (int(st.hut_r) + 2) % 4, 1)
			return


func _recruited_count() -> int:
	var n := 0
	for npc in npcs:
		if npc.recruited:
			n += 1
	return n


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if main == null:
		return
	_try_init()
	if not _ready_done:
		return
	_bind_quests()
	if is_authority():
		_authority_tick(delta)
	_update_prompt()
	if Engine.get_process_frames() % 15 == 0:
		_refresh_npc_markers()


var _cond_t := 0.0
var _tier_bound: SettlementManager = null


## Host: a Tide Hearth now holds the town's heart.
func on_hearth_founded(first: bool) -> void:
	if first:
		_announce("%s is founded! The Tide Hearth marks the heart of your town." % main.village.settlement_name)
	sync_village()


func sync_village() -> void:
	_sync_village()


## Host: what the town has in store and how safe it is (for villager morale).
func _measure_town() -> void:
	var v: SettlementManager = main.village
	var foods := {}
	for s: ItemSlot in v.town_depot.inventory.slots:
		if s != null and not s.is_empty():
			var it: ItemDef = ItemDB.get_item(s.item_id)
			if it != null and it.category == ItemDef.Category.FOOD:
				foods[s.item_id] = true
	var lights := 0
	var bell := false
	var r_vox := v.territory_radius_m / VS
	if main.entities != null:
		for ent: WorldEntity in main.entities.entities.values():
			if Vector2(ent.grid_coord.x - v.hearth_pos.x, ent.grid_coord.z - v.hearth_pos.z).length() > r_vox:
				continue
			if ent is ChestEntity and ent.entity_id == &"pantry_barrel":
				for s: ItemSlot in (ent as ChestEntity).container.inventory.slots:
					if s != null and not s.is_empty():
						var it: ItemDef = ItemDB.get_item(s.item_id)
						if it != null and it.category == ItemDef.Category.FOOD:
							foods[s.item_id] = true
			elif ent.entity_id == &"village_bell":
				bell = true
			elif ent.emits_light():
				lights += 1
	v.food_kinds = foods.size()
	v.safety = clampf(0.35 + 0.06 * lights + (0.25 if bell else 0.0), 0.0, 1.0)
	_update_job_assignments()


func _authority_tick(delta: float) -> void:
	if _tier_bound != main.village:
		_tier_bound = main.village
		main.village.town_tier_upgraded.connect(func(t: int) -> void:
			if t > 0:
				_announce("%s has grown into a %s! The town's bounds reach %d m." % [main.village.settlement_name,
					SettlementManager.TIER_NAMES[clampi(t, 0, 3)], int(main.village.territory_radius_m)])
			_sync_village())
	_cond_t -= delta
	if _cond_t <= 0.0:
		_cond_t = 5.0
		_measure_town()
	# Home scans: debounced after nearby edits, and when beds appear / move.
	_bed_poll_t -= delta
	if _bed_poll_t <= 0.0:
		_bed_poll_t = 2.0
		var sig := _beds_signature()
		if sig != _bed_sig:
			_bed_sig = sig
			if _scan_t < 0.0:
				_scan_t = SCAN_DEBOUNCE
	if _scan_t >= 0.0:
		_scan_t -= delta
		if _scan_t < 0.0:
			_scan_homes()
	# Routines -> routes. One route per frame keeps A* off the frame-time budget.
	for npc in npcs:
		_choose_target(npc)
	if not _path_queue.is_empty():
		_route(npcs[_path_queue.pop_front()])
	var watchers := _watch_points()
	for npc in npcs:
		if npc.voyage:
			if not _watched(npc, watchers):
				npc.voyage = false
				npc.teleport_to_goal()
				npc.refresh_label()
			continue
		npc.simulate(delta)
		if not npc.path.is_empty() and not _watched(npc, watchers):
			npc.teleport_to_goal()
		npc.activity = _activity(npc)
	# Broadcast compact states.
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / STATE_HZ
			npc_states.rpc(_pack_states())

	_auto_work_t -= delta
	if _auto_work_t <= 0.0:
		_auto_work_t = 15.0
		_villager_automation()
	_cook_t -= delta
	if _cook_t <= 0.0:
		_cook_t = 2.0
		cook_shift()
		lamplighter_shift()


func _villager_automation() -> void:
	if main == null or main.entities == null:
		return
	var has_workers := false
	for npc in npcs:
		if npc.recruited and npc.activity == 2:
			has_workers = true
			break
	if not has_workers:
		return

	var primary_chest: ChestEntity = null
	for ent: WorldEntity in main.entities.entities.values():
		if ent is ChestEntity and (ent as ChestEntity).container != null:
			primary_chest = ent as ChestEntity
			break
	if primary_chest == null:
		return

	for npc in npcs:
		if not npc.recruited or npc.activity != 2:
			continue
		match npc.def.profession:
			DrifterDef.Profession.FISHER:
				primary_chest.container.deposit(&"shore_crab", 1)
			DrifterDef.Profession.FARMER:
				primary_chest.container.deposit(&"sea_salt", 1)
			DrifterDef.Profession.CARPENTER:
				primary_chest.container.deposit(&"driftwood", 1)
			DrifterDef.Profession.SMOKER_CHEF:
				if not cook_orders().has_orders():   # with orders set, they cook those instead
					primary_chest.container.deposit(&"smoked_fish_ration", 1)
			DrifterDef.Profession.RANCHER:
				primary_chest.container.deposit(&"salt_milk", 1)


# ---------------------------------------------------------------- the cook's pantry orders

func cook_orders() -> CookOrders:
	return main.village.cook_orders


func _in_town(cell: Vector3i) -> bool:
	var v: SettlementManager = main.village
	return Vector2(cell.x - v.hearth_pos.x, cell.z - v.hearth_pos.z).length() <= v.territory_radius_m / VS


## Where the town keeps food, in the order the cook fills them:
## pantry barrels, the community stockpile chest, then the depot.
func town_stores() -> Array:
	var pantries: Array = []
	var chests: Array = []
	if main.entities != null:
		for ent: WorldEntity in main.entities.entities.values():
			if ent is ChestEntity and (ent as ChestEntity).container != null and _in_town(ent.grid_coord):
				if ent.entity_id == &"pantry_barrel":
					pantries.append((ent as ChestEntity).container.inventory)
				elif ent.entity_id == &"community_chest":
					chests.append((ent as ChestEntity).container.inventory)
	var out: Array = pantries + chests
	out.append(main.village.town_depot.inventory)
	return out


## Cooking fires and pots inside the town's bounds.
func town_cook_stations() -> Array:
	var out: Array = []
	if main.entities != null:
		for ent: WorldEntity in main.entities.entities.values():
			if ent is StationEntity and (ent as StationEntity).is_cooking_station() and _in_town(ent.grid_coord):
				out.append(ent)
	return out


func has_cook() -> bool:
	for npc in npcs:
		if npc.recruited and npc.def.profession == DrifterDef.Profession.SMOKER_CHEF:
			return true
	return false


## Sets how many of a meal the cook keeps in store (clients ask the host).
func set_cook_order(item_id: StringName, n: int) -> void:
	if is_authority():
		cook_orders().set_target(item_id, n)
		_sync_village()
	else:
		cook_orders().set_target(item_id, n)   # show it now; the host's copy follows
		req_cook_order.rpc_id(1, String(item_id), n)


@rpc("any_peer", "call_remote", "reliable")
func req_cook_order(item_id: String, n: int) -> void:
	if is_authority() and _ready_done:
		cook_orders().set_target(StringName(item_id), n)
		_sync_village()


## Host, every couple of seconds: each cook on shift tends up to two town fires: carries
## finished dishes to the stores, feeds the fire, and starts the meal furthest below its order.
func cook_shift() -> void:
	if main == null or main.village == null or main.entities == null:
		return
	var orders := cook_orders()
	var stations := town_cook_stations()
	var stores := town_stores()
	# Dishes already done go to the stores whoever's on shift (night, or the cook left).
	for st: StationEntity in stations:
		var key := CookOrders.key_for(st.grid_coord)
		if orders.pending.has(key) and orders.collect(st.station, key, stores) > 0:
			main.entities.push_state(st)
	for k: String in orders.pending.keys():   # a fire that was knocked down
		var found := false
		for st: StationEntity in stations:
			if CookOrders.key_for(st.grid_coord) == k:
				found = true
		if not found:
			orders.pending.erase(k)
	if not orders.has_orders() or stations.is_empty():
		_cook_station.clear()
		return
	var book: RecipeBook = main.player.recipes if main.player != null else null
	var free := stations.duplicate()
	# Fires a cook already has something on stay with them.
	free.sort_custom(func(a: StationEntity, b: StationEntity) -> bool:
		return orders.pending.has(CookOrders.key_for(a.grid_coord)) and not orders.pending.has(CookOrders.key_for(b.grid_coord)))
	for npc in npcs:
		if not npc.recruited or npc.def.profession != DrifterDef.Profession.SMOKER_CHEF:
			continue
		if npc.def.current_routine != DrifterDef.Routine.WORK:
			_cook_station.erase(npc.idx)
			continue
		var tended := 0
		for st: StationEntity in free.duplicate():
			if tended >= 2:
				break
			var key := CookOrders.key_for(st.grid_coord)
			if st.station.is_active and not orders.pending.has(key):
				free.erase(st)
				continue   # a player's dish is on this one
			var r := orders.work_station(st.station, key, stores, book)
			if r != null or orders.pending.has(key):
				free.erase(st)
				tended += 1
				if tended == 1:
					_cook_station[npc.idx] = st.grid_coord   # where they stand to work
				if r != null:
					main.entities.push_state(st)


## Host: a lamplighter who's up and about tops up the lighthouse lamp with Refined Fish Oil
## from the town's stores whenever it's down to under a day and a half of oil.
## Returns true when they poured some in.
func lamplighter_shift() -> bool:
	var beam: LighthouseBeam = main.get("_beam") if main != null else null
	if beam == null or beam.fuel_sec >= LAMP_REFILL_BELOW or not beam.can_refuel():
		return false
	var who: DrifterNPC = null
	for npc in npcs:
		if npc.recruited and npc.def.profession == DrifterDef.Profession.LAMPLIGHTER \
				and npc.def.current_routine != DrifterDef.Routine.SLEEP:
			who = npc
			break
	if who == null:
		return false
	for inv: Inventory in town_stores():
		if inv.remove_item(&"fish_oil", 1) == 1:
			beam.add_fuel(LAMP_OIL_SEC)
			_announce("%s filled the lighthouse lamp (%d hours of light)." % [who.def.name, int(beam.fuel_hours_left())])
			return true
	return false


## Talking to the cook opens their pantry orders.
func open_cook_orders(npc: DrifterNPC) -> void:
	if orders_ui == null:
		orders_ui = CookOrdersUI.new()
		orders_ui.name = "CookOrdersUI"
		main.add_child(orders_ui)
	orders_ui.open(self, npc.def.name)


func _activity(npc: DrifterNPC) -> int:
	if not npc.path.is_empty():
		return 1
	if not npc.recruited:
		return 0
	match npc.def.current_routine:
		DrifterDef.Routine.WORK: return 2
		DrifterDef.Routine.SLEEP: return 3 if _home_bed(npc) != Vector3i(-1, -1, -1) else 0
	return 0


func _watch_points() -> Array:
	var pts := []
	if main.player != null:
		pts.append(main.player.position)
	for id in main.remotes:
		pts.append(main.remotes[id].position)
	return pts


func _watched(npc: DrifterNPC, pts: Array) -> bool:
	for p: Vector3 in pts:
		if p.distance_to(npc.position) < WATCH_RANGE or (npc.path_goal != Vector3.INF and p.distance_to(npc.path_goal) < WATCH_RANGE):
			return true
	return false


# ---------------------------------------------------------------- routines

## Picks where the NPC should be for its routine; queues a route when that changes.
func _choose_target(npc: DrifterNPC) -> void:
	var cell: Vector3i
	var key: String
	if not npc.recruited:
		cell = Vector3i((npc.wreck_pos / VS).floor())
		key = "wreck"
	else:
		var incursion_active := StormIncursionManager.current != null and StormIncursionManager.current.active
		if incursion_active:
			cell = _entity_cell([&"defense_barricade", &"village_bell"], main.village.hearth_pos) + Vector3i(npc.idx % 3 - 1, 0, 1)
			key = "defend@%s" % cell
		else:
			var r: int = npc.def.current_routine
			match r:
				DrifterDef.Routine.SLEEP:
					cell = _home_bed(npc)
					if cell == Vector3i(-1, -1, -1):
						cell = main.village.hearth_pos + Vector3i(npc.idx * 2 - 5, 0, 3)
				DrifterDef.Routine.WORK:
					cell = _work_spot(npc)
				DrifterDef.Routine.EAT:
					cell = _entity_cell([&"tide_hearth", &"hearth_pot", &"campfire"], main.village.hearth_pos) + Vector3i(npc.idx % 3 - 1, 0, 2)
				_:
					var a := npc.idx * TAU / maxi(1, npcs.size())
					cell = Vector3i(main.world.gen.spawn) + Vector3i(int(cos(a) * 6), 0, int(sin(a) * 6))
			key = "%d@%s" % [r, cell]
	if key == npc.target_key:
		return
	npc.target_key = key
	if not _path_queue.has(npc.idx):
		_path_queue.append(npc.idx)
	npc.set_meta("goal_cell", cell)


func _route(npc: DrifterNPC) -> void:
	var goal: Vector3i = npc.get_meta("goal_cell", Vector3i((npc.position / VS).floor()))
	var start := Vector3i((npc.position / VS).floor())
	if Vector2(goal.x - start.x, goal.z - start.z).length() * VS > VOYAGE_DIST:
		# Across the sea: no walking route. They sail home when nobody is looking.
		npc.set_path([], (Vector3(goal) + Vector3(0.5, 0.0, 0.5)) * VS, npc.target_key)
		npc.voyage = true
		npc.refresh_label()
		return
	_ensure_between(start, goal)
	if _pather._stand_memo.size() > 150000:
		_pather.clear_cache()
	var t0 := Time.get_ticks_usec()
	var cells := _pather.find_path(start, goal)
	if OS.is_debug_build() and main._args.has("villagecheck"):
		print("[village] route %s: %s -> %s = %d cells (%d ms, start_y %d, goal_y %d)" % [npc.def.name, start, goal, cells.size(),
			(Time.get_ticks_usec() - t0) / 1000, _pather.find_stand(start.x & ~1, start.y, start.z & ~1, 8, 12), _pather.find_stand(goal.x & ~1, goal.y, goal.z & ~1, 8, 12)])
	var pts := []
	for c: Vector3i in cells:
		pts.append(Vector3((c.x + 1) * VS, c.y * VS, (c.z + 1) * VS))
	var goal_m: Vector3 = pts[-1] if not pts.is_empty() else Vector3(goal) * VS
	npc.set_path(pts, goal_m, npc.target_key)


func _home_bed(npc: DrifterNPC) -> Vector3i:
	var rid: int = npc.def.assigned_room_id
	if rid < 0 or rid >= main.village.rooms.size():
		return Vector3i(-1, -1, -1)
	var room: Dictionary = main.village.rooms[rid]
	if not room.get("valid", true) or not room.has("bed"):
		return Vector3i(-1, -1, -1)
	return room["bed"]


func _work_spot(npc: DrifterNPC) -> Vector3i:
	var st: Dictionary = main.world.gen.starter
	var dock: Vector2i = st.dock_o
	var fwd: Vector2i = st.front
	var side: Vector2i = st.side
	var hut: Vector3i = st.hut
	var dy: int = int(st.dock_y) + 1
	match npc.def.profession:
		DrifterDef.Profession.FISHER:
			var s := _entity_cell([&"fisher_station"], Vector3i(-1, -1, -1))
			if s != Vector3i(-1, -1, -1):
				return s + Vector3i(1, 0, 0)
			var e := dock + fwd * 28 + side * (npc.idx % 2 * 4 - 2)
			return Vector3i(e.x, dy, e.y)
		DrifterDef.Profession.CARPENTER:
			var s := _entity_cell([&"sawhorse", &"workbench"], Vector3i(-1, -1, -1))
			if s != Vector3i(-1, -1, -1):
				return s + Vector3i(1, 0, 0)
			return _entity_cell([&"workbench"], hut) + Vector3i(1, 0, 1)
		DrifterDef.Profession.FARMER:
			var s := _entity_cell([&"farming_station"], Vector3i(-1, -1, -1))
			if s != Vector3i(-1, -1, -1):
				return s + Vector3i(1, 0, 0)
			if main.farm != null and not main.farm.plots.is_empty():
				return main.farm.plots.keys()[0] + Vector3i(0, 1, 2)
			var f := Vector2i(hut.x, hut.z) - side * 18 + fwd * 8
			return Vector3i(f.x, hut.y, f.y)
		DrifterDef.Profession.RANCHER:
			var s := _entity_cell([&"ranch_station", &"feed_trough", &"poultry_coop"], Vector3i(-1, -1, -1))
			if s != Vector3i(-1, -1, -1):
				return s + Vector3i(1, 0, 0)
			var r_pos := Vector2i(hut.x, hut.z) + side * 12 + fwd * 6
			return Vector3i(r_pos.x, hut.y, r_pos.y)
		DrifterDef.Profession.SMOKER_CHEF:
			if _cook_station.has(npc.idx):
				return _cook_station[npc.idx] + Vector3i(1, 0, 0)
			return _entity_cell([&"hearth_pot", &"campfire", &"smokehouse", &"saltery", &"brewery"], hut) + Vector3i(1, 0, 0)
		DrifterDef.Profession.LAMPLIGHTER:
			var l := dock + side * 5
			return Vector3i(l.x, dy, l.y)
		_:
			var t := dock + fwd * 4
			return Vector3i(t.x, dy, t.y)


## Scans placed job blocks in the village and assigns open stations to recruited villagers.
func _update_job_assignments() -> void:
	if main == null or main.entities == null:
		return
	var station_professions := {
		&"farming_station": DrifterDef.Profession.FARMER,
		&"ranch_station": DrifterDef.Profession.RANCHER,
		&"fisher_station": DrifterDef.Profession.FISHER,
		&"sawhorse": DrifterDef.Profession.CARPENTER,
	}
	var placed_stations: Array[Dictionary] = []
	for ent: WorldEntity in main.entities.entities.values():
		if station_professions.has(ent.entity_id):
			placed_stations.append({"type": ent.entity_id, "coord": ent.grid_coord, "prof": station_professions[ent.entity_id]})

	for s in placed_stations:
		var prof: int = s["prof"]
		var has_worker := false
		for npc in npcs:
			if npc.recruited and npc.def.profession == prof:
				has_worker = true
				break
		if not has_worker:
			for npc in npcs:
				if npc.recruited and npc.def.profession != prof:
					npc.def.profession = prof
					npc.refresh_label()
					break


func _entity_cell(ids: Array, fallback: Vector3i) -> Vector3i:
	if main.entities != null:
		for want: StringName in ids:
			for ent: WorldEntity in main.entities.entities.values():
				if ent.entity_id == want:
					return ent.grid_coord
	return fallback


# ---------------------------------------------------------------- world queries

## Standing spot for a villager (0.5 m wide, 1.6 m tall body) with solid ground below.
func _standable(x: int, y: int, z: int) -> bool:
	var w: VoxelWorld = main.world
	var cx := (x + 1) * VS
	var cz := (z + 1) * VS
	# Body = exactly the 2x2 cell column (anything wider clips 1-voxel steps on every slope).
	if w.get_voxel(x, y - 1, z) == 0 and w.get_voxel(x + 1, y - 1, z) == 0 \
			and w.get_voxel(x, y - 1, z + 1) == 0 and w.get_voxel(x + 1, y - 1, z + 1) == 0:
		return false
	if y * VS < main.sky.water_level_m() - 0.6:
		return false   # villagers don't wade out deep
	return not w.aabb_collides(Vector3(cx - 0.16, y * VS + 0.01, cz - 0.16), Vector3(cx + 0.16, y * VS + 1.6, cz + 0.16))


func _ensure_columns(c: Vector3i, r: int) -> void:
	var col := Vector2i(c.x >> 5, c.z >> 5)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			main.world.store.generate_column(col + Vector2i(dx, dz))


## Real (stamped, edited) terrain along a route, not the height-field stand-in.
func _ensure_between(a: Vector3i, b: Vector3i) -> void:
	var ca := Vector2i(a.x >> 5, a.z >> 5)
	var cb := Vector2i(b.x >> 5, b.z >> 5)
	for cz in range(mini(ca.y, cb.y) - 1, maxi(ca.y, cb.y) + 2):
		for cx in range(mini(ca.x, cb.x) - 1, maxi(ca.x, cb.x) + 2):
			main.world.store.generate_column(Vector2i(cx, cz))


# ---------------------------------------------------------------- homes

## Called by Main for every applied edit command (all peers; only the authority acts).
func on_world_edit(cmd: Dictionary) -> void:
	if not _ready_done or not is_authority():
		return
	_pather.clear_cache()
	_ceil_memo.clear()
	_ceil_cols.clear()
	var p: Vector3i = cmd.get("p", Vector3i.ZERO)
	var near: bool = Vector3(p - main.village.hearth_pos).length() * VS < main.village.territory_radius_m
	for npc in npcs:
		npc.target_key = ""    # re-route around whatever changed
	if near and _scan_t < 0.0:
		_scan_t = SCAN_DEBOUNCE


func _beds_signature() -> String:
	var parts := []
	if main.entities != null:
		for ent: WorldEntity in main.entities.entities.values():
			if ent.entity_type == WorldEntity.EntityType.BED:
				parts.append(str(ent.grid_coord))
	parts.sort()
	return ",".join(parts)


## A livable home now stands (built or patched up): counts for "make a home" objectives.
func _home_built() -> void:
	if main.get("player") != null and main.player != null:
		main.player.quest_event(QuestDef.ObjectiveType.BUILD_ROOM, &"shelter")


func _scan_homes() -> void:
	if main.entities == null:
		return
	var t0 := Time.get_ticks_msec()
	var fixtures := {}
	var beds := []
	for ent: WorldEntity in main.entities.entities.values():
		if ent.entity_type == WorldEntity.EntityType.BED:
			fixtures[ent.grid_coord] = "bed"
			beds.append(ent.grid_coord)
		elif ent.entity_id in [&"campfire", &"hearth_pot"]:
			fixtures[ent.grid_coord] = "light"
		else:
			fixtures[ent.grid_coord] = "decor"
	for lp: Vector3i in main.world._lights.keys():
		fixtures[lp] = "light"
	var changed := false
	for bed: Vector3i in beds:
		if Vector3(bed - main.village.hearth_pos).length() * VS > main.village.territory_radius_m * 1.5:
			continue
		_ensure_columns(bed, 1)
		var res := RoomDetector.scan_home(bed, _solid, _ceiling, fixtures)
		var rid: int = main.village.find_room_by_bed(bed)
		if rid < 0:
			if res.is_valid:
				main.village.register_home(res, bed)
				_announce("New home registered: quality %d" % res.quality_score)
				_home_built()
				changed = true
		else:
			var was: bool = main.village.rooms[rid].get("valid", true)
			main.village.update_home(rid, res)
			if was != res.is_valid:
				changed = true
				_announce("Home restored: quality %d" % res.quality_score if res.is_valid else "A home is no longer livable: " + res.error_message)
				if res.is_valid:
					_home_built()
	print("[village] home scan: %d beds, %d valid homes (%d ms)" % [beds.size(), main.village.valid_room_count(), Time.get_ticks_msec() - t0])
	if changed:
		_sync_village()


func _solid(p: Vector3i) -> bool:
	var m: int = main.world.get_voxel(p.x, p.y, p.z)
	return m != 0 and not Palette.is_plant(m)


func _ceiling(p: Vector3i) -> bool:
	var col := Vector2i(p.x, p.z)
	for span: Vector2i in _ceil_cols.get(col, []):
		if p.y >= span.x and p.y < span.y:
			return true
	if _ceil_memo.has(p):
		return _ceil_memo[p]
	var hit: Dictionary = main.world.raycast((Vector3(p) + Vector3(0.5, 0.5, 0.5)) * VS, Vector3.UP,
			RoomDetector.CEILING_REACH * VS, true)
	var roofed := not hit.is_empty()
	if roofed:
		var spans: Array = _ceil_cols.get(col, [])
		spans.append(Vector2i(p.y, (hit.cell as Vector3i).y))
		_ceil_cols[col] = spans
	else:
		_ceil_memo[p] = false
	return roofed


# ---------------------------------------------------------------- interaction

func _nearest_npc(pos: Vector3) -> DrifterNPC:
	var best: DrifterNPC = null
	var bd := INTERACT_RANGE
	for npc in npcs:
		var d := npc.position.distance_to(pos)
		if d < bd:
			best = npc
			bd = d
	return best


func _update_prompt() -> void:
	var p: Player = main.player
	if p == null or p.is_seated() or (main.settings_menu != null and main.settings_menu.is_open()):
		_prompt_npc = null
		return
	_prompt_npc = _nearest_npc(p.position)
	if _prompt_npc == null:
		return
	var key: String = main.controller.get_action_glyph(&"interact") if main.controller != null and main.controller.has_method("get_action_glyph") else "F"
	if _prompt_npc.recruited:
		main.hud.set_prompt("%s  Talk to %s" % [key, _prompt_npc.def.name])
	elif _prompt_npc.castaway and not tide_low():
		main.hud.set_prompt("%s is pinned under the timbers. Free them at low water." % _prompt_npc.def.name)
	elif _prompt_npc.castaway:
		main.hud.set_prompt("%s  Free %s the %s and offer a home in Brine's Hollow" % [key, _prompt_npc.def.name, _prompt_npc.profession_name()])
	else:
		main.hud.set_prompt("%s  Invite %s the %s to Brine's Hollow" % [key, _prompt_npc.def.name, _prompt_npc.profession_name()])


func _unhandled_input(e: InputEvent) -> void:
	if _prompt_npc == null or not e.is_action_pressed("interact"):
		return
	var p: Player = main.player
	if p == null or not p.input_enabled:
		return
	if main.entities != null and main.entities.get_closest_interactable(p.position) != null:
		return   # an object is closer: let the player handle it
	get_viewport().set_input_as_handled()
	if _prompt_npc.recruited:
		_talk(_prompt_npc)
	elif is_authority():
		_try_recruit(_prompt_npc.idx, main.multiplayer.get_unique_id() if main.is_net else 1)
	else:
		req_recruit.rpc_id(1, _prompt_npc.idx)


func _talk(npc: DrifterNPC) -> void:
	if main.player != null:
		npc.face_player(main.player.position)

	if main.quests != null and main.player != null:
		main.player.quest_event(QuestDef.ObjectiveType.TALK_TO, npc.def.id)
		main.player.quest_event(QuestDef.ObjectiveType.TALK_TO, StringName(npc.def.name))
		main.quests.check_paused_rewards(main.player.inventory)

	if main.quests != null:
		var avail_q: QuestDef = _get_available_quest_for_npc(npc)
		if avail_q != null:
			main.quests.accept_quest(avail_q.id)
			main.hud.show_toast("%s (%s): \"Here, take this task: %s\"" % [npc.def.name, npc.profession_name(), avail_q.title])
			_refresh_npc_markers()
			return

	# High Morale Daily Gratitude Gift
	var now: float = Time.get_ticks_msec() / 1000.0
	if npc.recruited and npc.def.morale >= 0.75 and (now - npc.def.last_gift_time > 180.0) and main.player != null and main.player.inventory != null:
		npc.def.last_gift_time = now
		var gift_item: StringName = &"silver_mackerel"
		var gift_count: int = 1
		match npc.def.profession:
			DrifterDef.Profession.FISHER:
				gift_item = &"silver_mackerel"; gift_count = 1
			DrifterDef.Profession.FARMER:
				gift_item = &"shore_wheat"; gift_count = 2
			DrifterDef.Profession.CARPENTER:
				gift_item = &"wood_plank"; gift_count = 2
			DrifterDef.Profession.SMOKER_CHEF:
				gift_item = &"smoked_fish_ration"; gift_count = 1
			DrifterDef.Profession.LAMPLIGHTER:
				gift_item = &"fish_oil"; gift_count = 1
			DrifterDef.Profession.TRADER:
				gift_item = &"brass_guilder"; gift_count = 2
			DrifterDef.Profession.RANCHER:
				gift_item = &"salt_milk" if randf() < 0.5 else &"sea_egg"; gift_count = 1
			DrifterDef.Profession.BUILDER:
				gift_item = &"cobblestone"; gift_count = 2
		main.player.inventory.add_item(gift_item, gift_count)
		var iname := TradeManager._item_name(gift_item)
		main.hud.show_toast("%s the %s: \"Here, captain—fresh %s (%d) from today's work! Our village is thriving.\"" % [
			npc.def.name, npc.profession_name(), iname, gift_count
		])
		return

	if npc.def.profession == DrifterDef.Profession.SMOKER_CHEF:
		open_cook_orders(npc)
		return

	# Contextual immersion dialogue
	var line := ""
	match npc.def.current_routine:
		DrifterDef.Routine.SLEEP:
			line = "*Zzz... resting up for tomorrow's low tide...*"
		DrifterDef.Routine.EAT:
			line = "Nothing beats a warm meal by the hearth after a long shift!"
		DrifterDef.Routine.SOCIALIZE:
			line = "Good company and the sound of waves—a fine evening in the Hollow."
		DrifterDef.Routine.WORK:
			match npc.def.profession:
				DrifterDef.Profession.FISHER:
					line = "Tides are running sweet today. The mackerel are biting near the outer stacks!"
				DrifterDef.Profession.FARMER:
					line = "The sweet-soil beds are thriving! Brackish rye is shooting up nicely."
				DrifterDef.Profession.CARPENTER:
					line = "Splitting driftwood planks at the sawhorse. Shipshape timber for our harbor!"
				DrifterDef.Profession.SMOKER_CHEF:
					line = "Got the smokehouse stoked with dry beech. These cured rations will keep for months!"
				DrifterDef.Profession.LAMPLIGHTER:
					line = "Wicks trimmed and lanterns filled with fish oil. The beacon burns through the thickest fog."
				DrifterDef.Profession.TRADER:
					line = "Fair winds and full holds! Visiting merchant ships always look for our cured goods."
				DrifterDef.Profession.RANCHER:
					line = "The salt-goats are grazing peacefully. Just sheared a fresh bundle of shore wool!"
				DrifterDef.Profession.BUILDER:
					line = "Cobblestone and timber squared away. Building up Brine's Hollow stone by stone!"

	main.hud.show_toast("%s the %s: \"%s\"" % [npc.def.name, npc.profession_name(), line])


func _get_available_quest_for_npc(npc: DrifterNPC) -> QuestDef:
	if main == null or main.quests == null:
		return null
	return npc.get_available_quest(main.quests)


func _bind_quests() -> void:
	if main == null or main.quests == null or _quests_bound:
		return
	_quests_bound = true
	main.quests.quest_accepted.connect(func(_q: Variant) -> void: _refresh_npc_markers())
	main.quests.quest_progressed.connect(func(_q: Variant, _s: Variant) -> void: _refresh_npc_markers())
	main.quests.quest_completed.connect(func(_q: Variant) -> void: _refresh_npc_markers())
	main.quests.quest_rewards_paused.connect(func(_q: Variant) -> void: _refresh_npc_markers())
	_refresh_npc_markers()


func _refresh_npc_markers() -> void:
	if main == null or main.quests == null:
		return
	for npc in npcs:
		npc.refresh_marker(main.quests)


func _try_recruit(npc_idx: int, peer: int) -> void:
	if npc_idx < 0 or npc_idx >= npcs.size():
		return
	var npc := npcs[npc_idx]
	if npc.recruited:
		return
	var who: Vector3 = main.player.position if peer == main.multiplayer.get_unique_id() or not main.is_net else \
			(main.remotes[peer].position if main.remotes.has(peer) else Vector3.INF)
	if who.distance_to(npc.position) > INTERACT_RANGE + 3.0:
		return
	if npc.castaway and not tide_low():
		_tell(peer, "The sea is still over the timbers pinning %s. Come back at low water." % npc.def.name)
		return
	if main.village.get_vacant_room_id() < 0:
		if npc.castaway:
			_tell(peer, "%s says: \"Thank you! But where would I live? Build a roofed room with a bed, a light and a doorway, then come back for me.\"" % npc.def.name)
		else:
			_tell(peer, "%s says: \"I'd come, but I need a home - a roofed room with a bed, a light and a doorway.\"" % npc.def.name)
		return
	main.village.recruit_drifter(npc.def)
	_set_recruited(npc_idx)
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		npc_recruited.rpc(npc_idx)
	if npc.castaway:
		_announce("You freed %s the %s from the wreck! They'll patch a boat and sail for Brine's Hollow." % [npc.def.name, npc.profession_name()])
	else:
		_announce("%s the %s joined Brine's Hollow!" % [npc.def.name, npc.profession_name()])
	_sync_village()


func _set_recruited(npc_idx: int) -> void:
	var npc := npcs[npc_idx]
	if not npc.recruited and main != null:
		if main.player != null and main.player.recipes != null:
			main.player.recipes.on_drifter_recruited(int(npc.def.profession))   # they teach their trade
		if main.quests != null:
			var inv: Inventory = main.player.inventory if main.player != null else null
			main.quests.notify_event(QuestDef.ObjectiveType.TALK_TO, &"drifter_recruit", 1, inv)
		if main.player != null:
			main.player.quest_event(QuestDef.ObjectiveType.TALK_TO, &"drifter_recruit")
	npc.recruited = true
	npc.refresh_label()
	var wreck := npc.get_node_or_null("Wreck")
	if wreck != null:
		wreck.queue_free()
	var smoke := npc.get_node_or_null("SignalSmoke")
	if smoke != null:
		smoke.queue_free()
	_refresh_npc_markers()


func _announce(text: String) -> void:
	main.hud.show_toast(text)
	print("[village] ", text)
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		village_event.rpc(text)


func _tell(peer: int, text: String) -> void:
	if not main.is_net or peer == main.multiplayer.get_unique_id():
		main.hud.show_toast(text)
	else:
		village_event.rpc_id(peer, text)


func _sync_village() -> void:
	if main.is_net and main.multiplayer.multiplayer_peer != null and main.session != null:
		main.session.village_full.rpc(main.village.serialize())


# ---------------------------------------------------------------- network

func _pack_states() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for npc in npcs:
		out.append_array([npc.idx, npc.position.x, npc.position.y, npc.position.z, npc.facing,
			npc.speed, npc.activity, 1.0 if npc.recruited else 0.0])
	return out


@rpc("authority", "call_remote", "unreliable_ordered")
func npc_states(data: PackedFloat32Array) -> void:
	if not _ready_done:
		return
	for i in range(0, data.size() - 7, 8):
		var k := int(data[i])
		if k < 0 or k >= npcs.size():
			continue
		var npc := npcs[k]
		npc.apply_net(Vector3(data[i + 1], data[i + 2], data[i + 3]), data[i + 4], data[i + 5], int(data[i + 6]))
		if data[i + 7] > 0.5 and not npc.recruited:
			_set_recruited(k)


@rpc("authority", "call_remote", "reliable")
func npc_recruited(npc_idx: int) -> void:
	if _ready_done and npc_idx >= 0 and npc_idx < npcs.size():
		_set_recruited(npc_idx)


@rpc("authority", "call_remote", "reliable")
func village_event(text: String) -> void:
	if main.hud != null:
		main.hud.show_toast(text)


@rpc("any_peer", "call_remote", "reliable")
func req_recruit(npc_idx: int) -> void:
	if is_authority() and _ready_done:
		_try_recruit(npc_idx, main.multiplayer.get_remote_sender_id())


# ---------------------------------------------------------------- dev check

func _grab(dir: String, name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("[villageshot] ", name)


func _frame(focus: Vector3, yaw: float, dist: float, pitch := -0.3) -> void:
	main.player.position = focus + Vector3(cos(yaw) * 1.6, 0.3, sin(yaw) * 1.6)
	main.rig.yaw = yaw
	main.rig.pitch = pitch
	main.rig.dist = dist
	for i in 4:
		await get_tree().process_frame


func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	main.player.input_enabled = false
	if "help" in main.hud and main.hud.help != null:
		main.hud.help.visible = false
	main.sky.time_of_day = 0.33
	await get_tree().create_timer(2.0).timeout
	# 1. a stranded drifter by their wreck
	var d1 := npcs[1]
	await _frame(d1.position, d1.facing + PI * 0.75, 4.5)
	await _grab(dir, "b1_stranded_drifter")
	# 2. merchant ship docked beside the pier
	main.sky.time_of_day = 0.45
	await get_tree().create_timer(1.5).timeout
	var t: TradeManager = main.trade
	var st: Dictionary = main.world.gen.starter
	var fwd := Vector3(st.front.x, 0, st.front.y)
	await _frame(t.trade_point() - fwd * 6.0 + Vector3(0, 1.5, 0), atan2(-fwd.x, -fwd.z), 11.0, -0.25)
	await _grab(dir, "b2_merchant_docked")
	# 3. trade window
	main.player.position = t.trade_point() + Vector3(0, 1, 0)
	main.player.inventory.add_item(&"silver_mackerel", 6)
	main.player.inventory.add_item(&"brass_guilder", 40)
	t.ui.open()
	await _grab(dir, "b3_trade_ui")
	t.ui.close()
	# 4. recruited villager heading to work
	main.player.position = npcs[0].position + Vector3(1.0, 0.3, 0.0)
	_try_recruit(0, 1)
	main.sky.time_of_day = 0.40
	await get_tree().create_timer(3.0).timeout
	await _frame(npcs[0].position, npcs[0].facing + PI, 5.0)
	await _grab(dir, "b4_villager_at_work")
	get_tree().quit()


## --villagecheck: recruit the nearest drifter, then watch them walk to work.
## --villagecheck=watch (co-op client): report what the host's NPC broadcasts look like here.
func run_check(role := "") -> void:
	while not _ready_done or main.player == null:
		await get_tree().process_frame
	if role.begins_with("shot:"):
		await _shots(role.trim_prefix("shot:"))
		return
	if role == "watch":
		await get_tree().create_timer(3.0).timeout
		var a := npcs[0].position
		for i in 6:
			await get_tree().create_timer(1.0).timeout
			main.player.position = npcs[0].position + Vector3(2.0, 0.5, 0.0)
			print("[villagecheck-client] t=%d npc0 pos=%s recruited=%s activity=%d" % [i, npcs[0].position.snapped(Vector3.ONE * 0.01), npcs[0].recruited, npcs[0].activity])
		print("[villagecheck-client] npc0 moved %.1f m on this client" % a.distance_to(npcs[0].position))
		get_tree().quit()
		return
	await get_tree().create_timer(2.5).timeout
	print("[villagecheck] homes valid=%d vacant=%d" % [main.village.valid_room_count(), main.village.get_vacant_room_id()])
	var npc := npcs[0]
	main.player.position = npc.position + Vector3(1.0, 0.3, 0)
	_try_recruit(0, main.multiplayer.get_unique_id() if main.is_net else 1)
	print("[villagecheck] recruited=%s room=%d drifters=%d" % [npc.recruited, npc.def.assigned_room_id, main.village.drifters.size()])
	main.sky.time_of_day = 0.40   # working hours
	var start := npc.position
	for i in 8:
		await get_tree().create_timer(1.0).timeout
		main.player.position = npc.position + Vector3(2.0, 0.5, 0.0)   # keep watching (no teleport)
		print("[villagecheck] t=%d pos=%s path=%d activity=%d" % [i, npc.position.snapped(Vector3.ONE * 0.01), npc.path.size(), npc.activity])
	print("[villagecheck] walked %.1f m toward work" % start.distance_to(npc.position))
	if main.is_net:
		await get_tree().create_timer(10.0).timeout   # let co-op clients finish watching
	if main.session != null and is_authority():
		main.session.save_all()
	get_tree().quit()
