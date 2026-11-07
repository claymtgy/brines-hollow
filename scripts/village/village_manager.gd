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
		npcs.append(npc)


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
	if is_authority():
		_authority_tick(delta)
	_update_prompt()


func _authority_tick(delta: float) -> void:
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
		var r: int = npc.def.current_routine
		match r:
			DrifterDef.Routine.SLEEP:
				cell = _home_bed(npc)
				if cell == Vector3i(-1, -1, -1):
					cell = main.village.hearth_pos + Vector3i(npc.idx * 2 - 5, 0, 3)
			DrifterDef.Routine.WORK:
				cell = _work_spot(npc)
			DrifterDef.Routine.EAT:
				cell = _entity_cell([&"hearth_pot", &"campfire"], main.village.hearth_pos) + Vector3i(npc.idx % 3 - 1, 0, 2)
			_:
				var a := npc.idx * TAU / ROSTER.size()
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
			var e := dock + fwd * 28 + side * (npc.idx % 2 * 4 - 2)
			return Vector3i(e.x, dy, e.y)
		DrifterDef.Profession.CARPENTER:
			return _entity_cell([&"workbench"], hut) + Vector3i(1, 0, 1)
		DrifterDef.Profession.FARMER:
			if main.farm != null and not main.farm.plots.is_empty():
				return main.farm.plots.keys()[0] + Vector3i(0, 1, 2)
			var f := Vector2i(hut.x, hut.z) - side * 18 + fwd * 8
			return Vector3i(f.x, hut.y, f.y)
		DrifterDef.Profession.SMOKER_CHEF:
			return _entity_cell([&"campfire", &"hearth_pot"], hut) + Vector3i(1, 0, 0)
		DrifterDef.Profession.LAMPLIGHTER:
			var l := dock + side * 5
			return Vector3i(l.x, dy, l.y)
		_:
			var t := dock + fwd * 4
			return Vector3i(t.x, dy, t.y)


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
				changed = true
		else:
			var was: bool = main.village.rooms[rid].get("valid", true)
			main.village.update_home(rid, res)
			if was != res.is_valid:
				changed = true
				_announce("Home restored: quality %d" % res.quality_score if res.is_valid else "A home is no longer livable: " + res.error_message)
	print("[village] home scan: %d beds, %d valid homes (%d ms)" % [beds.size(), main.village.valid_room_count(), Time.get_ticks_msec() - t0])
	if changed:
		_sync_village()


func _solid(p: Vector3i) -> bool:
	return main.world.get_voxel(p.x, p.y, p.z) != 0


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
	var routine: String = ["sleeping", "working", "having a meal", "chatting in the square"][clampi(int(npc.def.current_routine), 0, 3)]
	var home := "no home yet"
	var bed := _home_bed(npc)
	if bed != Vector3i(-1, -1, -1):
		home = "home quality %d" % int(main.village.rooms[npc.def.assigned_room_id].get("quality", 0))
	main.hud.show_toast("%s (%s): %s - morale %d%%, %s" % [npc.def.name, npc.profession_name(), routine, int(npc.def.morale * 100), home])


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
	if main.village.get_vacant_room_id() < 0:
		_tell(peer, "%s says: \"I'd come, but I need a home - a roofed room with a bed, a light and a doorway.\"" % npc.def.name)
		return
	main.village.recruit_drifter(npc.def)
	_set_recruited(npc_idx)
	if main.is_net and main.multiplayer.multiplayer_peer != null:
		npc_recruited.rpc(npc_idx)
	_announce("%s the %s joined Brine's Hollow!" % [npc.def.name, npc.profession_name()])
	_sync_village()


func _set_recruited(npc_idx: int) -> void:
	var npc := npcs[npc_idx]
	npc.recruited = true
	npc.refresh_label()
	var wreck := npc.get_node_or_null("Wreck")
	if wreck != null:
		wreck.queue_free()


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
