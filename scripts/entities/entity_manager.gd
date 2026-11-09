class_name EntityManager
extends Node3D
## All placed world entities (workstations, chests, barrels, beds, mirrors, crab pots, salt pans).
##
## TYPE REGISTRY (static, shared by every system):
##   EntityManager.register_type(id, factory, def := {})
##     id       StringName entity type id (saved in worlds, sent over the network)
##     factory  Callable(coord: Vector3i) -> WorldEntity, or a Script whose _init takes (coord)
##     def      optional: {"item": StringName placeable item id (defaults to id),
##                         "rule": &"ground" | &"intertidal" | &"shallows" (placement rule),
##                         "aliases": [StringName...]}
##   EntityManager.type_for_item(item_id) -> StringName   (&"" if the item isn't placeable)
##   EntityManager.get_type_def(id) -> Dictionary
##
## AUTHORITY (host / dedicated server owns entity state; see net/session.gd):
##   request_place(type, coord, rot)         place (validated by the server; clients are refunded on reject)
##   request_remove(coord)                   pick up (server grants pickup_items() to the requester)
##   request_action(entity, action, args)    run entity.server_action() on the server, broadcast state,
##                                           grant items to the requester
##   push_state(entity)                      trusted: send an entity's locally changed state to the server
##   spawn_entity(type, coord, rot)          authority-side/local spawn without networking (tests, loading)
##
## Saving & join sync go through Session.register_state(&"entities", ...).
## Collision: blocks(min_m, max_m, ignore) and point_solid(p, ignore) include solid entities and boats.

signal entity_spawned(entity: WorldEntity)
signal entity_removed(coord: Vector3i)

const STATE_BROADCAST_SEC := 0.5

static var current: EntityManager = null
static var _types: Dictionary = {}      # id -> {"factory": Callable, "item": StringName, "rule": StringName}
static var _aliases: Dictionary = {}    # alias id -> id
static var _item_types: Dictionary = {} # item id -> entity type id

## Vector3i -> WorldEntity
var entities: Dictionary = {}
var main: Node = null
var starter_done := false
var caves_stocked := false   # barnacled chests placed in the world's caves (layout 2+)
var camps_stocked := false   # a chest in each Mud-Claw camp (layout 2+)
var wrecks_stocked := false  # a locker in each beached shipwreck (layout 2+)
var _scroll_deck: Array = []  # rare recipe scrolls still to deal out (RecipeBook.FOUND_SCROLLS)
var hulk_stocked := false      # loose boulders above the Barnacled Hulk's strand
var outposts_stocked := false  # a War Horn Totem and a strongbox in each Sea-Reaver outpost
var under_stocked := false   # mine strongboxes, sump caches, springs, village wells (layout 2+)
var sleeping_peers: Dictionary = {}  # peer_id (int) -> bed grid_coord (Vector3i)


func count_beds() -> int:
	var n := 0
	for ent: WorldEntity in entities.values():
		if ent is BedEntity or ent.entity_type == WorldEntity.EntityType.BED:
			n += 1
	return n


func try_sleep_in_bed(bed: BedEntity, peer: int) -> Dictionary:
	# Ensure two players cannot claim the same single bed to bypass the all-players-have-a-bed rule
	for existing_peer in sleeping_peers.keys():
		if sleeping_peers[existing_peer] == bed.grid_coord and int(existing_peer) != peer:
			sleeping_peers.erase(existing_peer)
	# Prune any disconnected peers
	if main != null and main.is_net:
		for existing_peer in sleeping_peers.keys():
			var pid := int(existing_peer)
			if pid != _local_peer() and not main.remotes.has(pid):
				sleeping_peers.erase(existing_peer)
	sleeping_peers[peer] = bed.grid_coord

	var total_players: int = 1 + (main.remotes.size() if main != null and main.is_net else 0)
	var total_beds := maxi(1, count_beds())
	var sleeping_count := sleeping_peers.size()

	if total_beds < total_players:
		return {"toast": "Need a bed for every player (%d/%d beds placed) to sleep through to morning!" % [total_beds, total_players]}
	if sleeping_count < total_players:
		return {"toast": "Resting in bed (%d/%d players sleeping) — waiting for others..." % [sleeping_count, total_players]}

	sleeping_peers.clear()
	if main != null and main.sky != null:
		main.sky.time_of_day = 0.28
		if _net() and is_authority():
			main.time_sync.rpc(main.sky.time_of_day)
	return {"toast": "All players asleep — slept through to the morning!"}

var _dirty := {}                 # authority: Vector3i -> true (state to broadcast)
var _broadcast_t := 0.0


# ---------------------------------------------------------------- registry

static func register_type(id: StringName, factory: Variant, def: Dictionary = {}) -> void:
	var f: Callable
	if factory is Callable:
		f = factory
	elif factory is Script:
		var script: Script = factory
		f = func(coord: Vector3i) -> WorldEntity: return script.new(coord)
	else:
		push_error("EntityManager.register_type: factory must be a Callable or Script")
		return
	var item: StringName = def.get("item", id)
	_types[id] = {"factory": f, "item": item, "rule": def.get("rule", &"ground")}
	if item != &"":
		_item_types[item] = id
	for a: StringName in def.get("aliases", []):
		_aliases[a] = id


## Removes a registered type (mods unloading, tests cleaning up). Script-defined
## factories hold their script alive, so drop them before that script is freed.
static func unregister_type(id: StringName) -> void:
	var d: Dictionary = _types.get(id, {})
	_types.erase(id)
	if not d.is_empty() and _item_types.get(d.item, &"") == id:
		_item_types.erase(d.item)
	for a: StringName in _aliases.keys():
		if _aliases[a] == id:
			_aliases.erase(a)


static func ensure_types() -> void:
	if _types.is_empty():
		Placeables.register_builtin()


static func resolve_type(id: StringName) -> StringName:
	ensure_types()
	return _aliases.get(id, id)


static func get_type_def(id: StringName) -> Dictionary:
	ensure_types()
	return _types.get(resolve_type(id), {})


static func type_for_item(item: StringName) -> StringName:
	ensure_types()
	return _item_types.get(item, &"")


func _init() -> void:
	ensure_types()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func is_authority() -> bool:
	if main == null or not main.is_net or main.multiplayer.multiplayer_peer == null:
		return true
	return main.multiplayer.is_server()


# ---------------------------------------------------------------- local spawn / remove

## Creates an entity locally (no networking). Unknown ids become generic placeholder entities.
func spawn_entity(type: StringName, coord: Vector3i, rot: int = 0) -> WorldEntity:
	if entities.has(coord):
		remove_entity(coord)
	var id := resolve_type(type)
	var ent: WorldEntity = null
	if _types.has(id):
		ent = (_types[id].factory as Callable).call(coord)
		if ent.item_id == &"":
			ent.item_id = _types[id].item
	else:
		ent = WorldEntity.new(type, String(type).capitalize(), coord)
	ent.manager = self
	ent.rotation_steps = rot
	ent.rotation.y = rot * (PI * 0.5)
	add_child(ent)
	entities[coord] = ent
	entity_spawned.emit(ent)
	return ent


func remove_entity(coord: Vector3i) -> bool:
	if not entities.has(coord):
		return false
	var ent: WorldEntity = entities[coord]
	entities.erase(coord)
	ent.queue_free()
	entity_removed.emit(coord)
	return true


func get_entity_at(coord: Vector3i) -> WorldEntity:
	return entities.get(coord, null)


func has_entity_at(coord: Vector3i) -> bool:
	return entities.has(coord)


func get_closest_interactable(player_pos: Vector3, max_reach: float = 3.2) -> WorldEntity:
	if main != null and main.get("player") != null:
		var p: Player = main.player
		if p != null and is_instance_valid(p) and p.get("hovered_entity") != null:
			var hent: WorldEntity = p.hovered_entity
			if is_instance_valid(hent) and player_pos.distance_to(hent.position) <= maxf(max_reach, hent.interaction_radius):
				return hent
	var closest: WorldEntity = null
	var closest_dist: float = max_reach
	for ent: WorldEntity in entities.values():
		var d := player_pos.distance_to(ent.position)
		if d <= ent.interaction_radius and d < closest_dist:
			closest_dist = d
			closest = ent
	return closest


func raycast_entity(origin: Vector3, dir: Vector3, max_dist: float = 40.0) -> Dictionary:
	var best_ent: WorldEntity = null
	var best_t: float = max_dist
	var norm_dir := dir.normalized()
	var seg_to := origin + norm_dir * max_dist
	for ent: WorldEntity in entities.values():
		if not is_instance_valid(ent):
			continue
		var box := ent.get_aabb().grow(0.06)
		var hit_pt = box.intersects_segment(origin, seg_to)
		if hit_pt is Vector3:
			var d := origin.distance_to(hit_pt as Vector3)
			if d < best_t:
				best_t = d
				best_ent = ent
	if best_ent != null:
		return {"entity": best_ent, "dist": best_t}
	return {}


func get_count() -> int:
	return entities.size()


# ---------------------------------------------------------------- ticking

func tick(delta: float) -> void:
	for ent: WorldEntity in entities.values():
		ent.tick(delta)


func _process(delta: float) -> void:
	tick(delta)
	if main == null or not is_authority():
		return
	var env := _env()
	for ent: WorldEntity in entities.values():
		if ent.server_tick(delta, env):
			_dirty[ent.grid_coord] = true
	_broadcast_t -= delta
	if _broadcast_t <= 0.0 and not _dirty.is_empty():
		_broadcast_t = STATE_BROADCAST_SEC
		for c: Vector3i in _dirty:
			var e: WorldEntity = entities.get(c)
			if e != null:
				_broadcast_state(e)
		_dirty.clear()


func _env() -> Dictionary:
	var sky: SkyCycle = main.sky if main != null else null
	if sky == null:
		return {"tide_vox": VoxelWorld.SEA_MID, "daylight": true, "time": 0.5}
	return {"tide_vox": sky.water_level_vox, "daylight": sky.is_day(), "time": sky.time_of_day}


# ---------------------------------------------------------------- networking: requests

func _net() -> bool:
	return main != null and main.is_net and main.multiplayer.multiplayer_peer != null


## Place an entity (call after the local player has paid for it). Returns false if rejected
## locally; clients get the item refunded if the server rejects.
func request_place(type: StringName, coord: Vector3i, rot: int) -> bool:
	var id := resolve_type(type)
	if not is_authority():
		req_place.rpc_id(1, id, coord, rot)
		return true
	return _authority_place(id, coord, rot, _local_peer()) != null


func request_remove(coord: Vector3i) -> void:
	if not is_authority():
		req_remove.rpc_id(1, coord)
		return
	_authority_remove(coord, _local_peer())


func request_action(ent: WorldEntity, action: StringName, args: Dictionary = {}) -> void:
	if not is_authority():
		req_action.rpc_id(1, ent.grid_coord, action, args)
		return
	_authority_action(ent.grid_coord, action, args, _local_peer())


func push_state(ent: WorldEntity) -> void:
	if is_authority():
		_dirty[ent.grid_coord] = true
	elif _net():
		req_state.rpc_id(1, ent.grid_coord, ent.serialize())


func _local_peer() -> int:
	return main.multiplayer.get_unique_id() if _net() else 1


@rpc("any_peer", "call_remote", "reliable")
func req_place(type: StringName, coord: Vector3i, rot: int) -> void:
	if not is_authority():
		return
	var peer := main.multiplayer.get_remote_sender_id()
	if _authority_place(type, coord, rot, peer) == null:
		var item: StringName = get_type_def(type).get("item", &"")
		if item != &"":
			_grant(peer, [[item, 1]], "Can't place that there")


@rpc("any_peer", "call_remote", "reliable")
func req_remove(coord: Vector3i) -> void:
	if is_authority():
		_authority_remove(coord, main.multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func req_action(coord: Vector3i, action: StringName, args: Dictionary) -> void:
	if is_authority():
		_authority_action(coord, action, args, main.multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func req_state(coord: Vector3i, data: Dictionary) -> void:
	if not is_authority():
		return
	var ent: WorldEntity = entities.get(coord)
	if ent == null or String(data.get("id", "")) != String(ent.entity_id):
		return
	ent.deserialize(data)
	_broadcast_state(ent)


# ---------------------------------------------------------------- networking: authority side

func _authority_place(type: StringName, coord: Vector3i, rot: int, _peer: int) -> WorldEntity:
	if not _types.has(type) or entities.has(coord) or overlaps_any(type, coord, rot):
		return null
	var ent := spawn_entity(type, coord, rot)
	if _net():
		net_spawn.rpc(type, coord, rot, ent.serialize())
	return ent


func _authority_remove(coord: Vector3i, peer: int) -> void:
	var ent: WorldEntity = entities.get(coord)
	if ent == null or ent.item_id == &"":
		return
	var items := ent.pickup_items()
	remove_entity(coord)
	if _net():
		net_remove.rpc(coord)
	_grant(peer, items, "Picked up %s" % ent.entity_name)


func _authority_action(coord: Vector3i, action: StringName, args: Dictionary, peer: int) -> void:
	var ent: WorldEntity = entities.get(coord)
	if ent == null:
		return
	var res: Dictionary = ent.server_action(action, args, peer)
	if res.get("changed", false):
		_broadcast_state(ent)
	var grants: Array = res.get("grant", [])
	var toast: String = res.get("toast", "")
	if not grants.is_empty() or toast != "":
		_grant(peer, grants, toast)


func _broadcast_state(ent: WorldEntity) -> void:
	ent.state_changed.emit()
	if _net():
		net_state.rpc(ent.grid_coord, ent.serialize())


## Gives items to `peer` (local inventory if it's us, otherwise via RPC) with an optional toast.
func _grant(peer: int, items: Array, toast: String) -> void:
	if peer == _local_peer() or not _net():
		_apply_grant(items, toast)
	else:
		net_grant.rpc_id(peer, items, toast)


func _apply_grant(items: Array, toast: String) -> void:
	var p: Player = main.player if main != null else null
	if p != null:
		for g: Array in items:
			if int(g[1]) > 0:
				var left := p.inventory.add_item(StringName(g[0]), int(g[1]))
				if left > 0:
					toast += "  (inventory full: %d %s lost)" % [left, g[0]]
	if toast != "" and main != null and main.hud != null:
		main.hud.show_toast(toast)


@rpc("authority", "call_remote", "reliable")
func net_spawn(type: StringName, coord: Vector3i, rot: int, data: Dictionary) -> void:
	var ent := spawn_entity(type, coord, rot)
	ent.deserialize(data)


@rpc("authority", "call_remote", "reliable")
func net_remove(coord: Vector3i) -> void:
	remove_entity(coord)


@rpc("authority", "call_remote", "reliable")
func net_state(coord: Vector3i, data: Dictionary) -> void:
	var ent: WorldEntity = entities.get(coord)
	if ent == null:
		ent = spawn_entity(StringName(data.get("id", "")), coord, int(data.get("rot", 0)))
	ent.deserialize(data)
	ent.state_changed.emit()


@rpc("authority", "call_remote", "reliable")
func net_grant(items: Array, toast: String) -> void:
	_apply_grant(items, toast)


# ---------------------------------------------------------------- persistence & join sync

func serialize() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for ent: WorldEntity in entities.values():
		list.append(ent.serialize())
	return list


func deserialize(data: Array) -> void:
	for ent: WorldEntity in entities.values():
		ent.queue_free()
	entities.clear()
	for entry in data:
		if entry is Dictionary:
			var t := StringName(entry.get("id", ""))
			var coord := Vector3i(int(entry.get("x", 0)), int(entry.get("y", 0)), int(entry.get("z", 0)))
			var rot := int(entry.get("rot", 0))
			var ent := spawn_entity(t, coord, rot)
			if ent != null:
				ent.deserialize(entry)


## Session state hooks (saved in state.dat, sent to joining players).
func save_state() -> Dictionary:
	return {"list": serialize(), "starter_done": starter_done, "caves_stocked": caves_stocked, "camps_stocked": camps_stocked, "under_stocked": under_stocked, "wrecks_stocked": wrecks_stocked, "outposts_stocked": outposts_stocked, "hulk_stocked": hulk_stocked}


func load_state(d: Dictionary) -> void:
	deserialize(d.get("list", []))
	starter_done = bool(d.get("starter_done", false))
	caves_stocked = bool(d.get("caves_stocked", false))
	camps_stocked = bool(d.get("camps_stocked", false))
	under_stocked = bool(d.get("under_stocked", false))
	wrecks_stocked = bool(d.get("wrecks_stocked", false))
	outposts_stocked = bool(d.get("outposts_stocked", false))
	hulk_stocked = bool(d.get("hulk_stocked", false))


## Called by Main with the Session once both exist.
func bind(p_main: Node) -> void:
	main = p_main
	var session: Session = main.session
	if session == null:
		return
	session.register_state(&"entities", save_state, load_state)
	session.world_ready.connect(_on_world_ready)
	if "--entitycheck" in OS.get_cmdline_user_args():
		_run_entity_check()


## Dev: `--entitycheck` place a crab pot on the tidal flats with the real placement rules,
## bait it, fast-forward through a high tide on the real sky clock, collect the catch.
func _run_entity_check() -> void:
	while main.player == null or not main.world.ready_for_play:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var p: Player = main.player
	var w: VoxelWorld = main.world
	var low := int(VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP)
	var spot := Vector3i(-1, -1, -1)
	var sp := Vector3i(p.position / VoxelWorld.VS)
	for r in range(2, 200):
		for k in 16:
			var x := sp.x + int(cos(k * TAU / 16) * r)
			var z := sp.z + int(sin(k * TAU / 16) * r)
			var y := _ground_y(x, z, int(VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP) + 2)
			if y >= low + 1 and y <= int(VoxelWorld.SEA_MID):
				p.placement._place_type = &"crab_pot"
				var pr := p.placement._probe(&"crab_pot", Vector3i(x, y, z), 0)
				var ok: bool = p.placement._check(pr, pr.get_aabb()) == ""
				pr.free()
				if ok:
					spot = Vector3i(x, y, z)
					break
		if spot.y >= 0:
			break
	print("[entitycheck] intertidal spot ", spot)
	p.inventory.add_item(&"crab_pot", 1)
	p.inventory.add_item(&"kelp_frond", 3)
	p.position = (Vector3(spot) + Vector3(6.5, 3, 0.5)) * VoxelWorld.VS
	p.tool = 4
	for i in 8:
		if p.inventory.get_active_item() != null and p.inventory.get_active_item().item_id == &"crab_pot":
			break
		p.inventory.active_hotbar_index = i
	p.target = {"cell": spot - Vector3i(0, 1, 0), "normal": Vector3i(0, 1, 0)}
	p.placement._place_type = p.placement.active_type()
	p.placement._place_coord = spot
	var probe := p.placement._probe(&"crab_pot", spot, 0)
	var reason := p.placement._check(probe, probe.get_aabb())
	probe.free()
	p.placement._place_ok = reason == ""
	print("[entitycheck] placement check: '%s'" % reason)
	p.placement.try_use()
	await get_tree().process_frame
	var pot: CrabPotEntity = entities.get(spot)
	print("[entitycheck] placed=%s items_left=%d" % [pot != null, p.inventory.get_item_count(&"crab_pot")])
	if pot == null:
		get_tree().quit(1)
		return
	p.inventory.active_hotbar_index = 0
	pot.client_interact(p)   # bait
	await get_tree().process_frame
	print("[entitycheck] baited=%d kelp_left=%d" % [pot.pot.bait_count, p.inventory.get_item_count(&"kelp_frond")])
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--entityshot="):   # windowed runs are throttled: skip the tide, just shoot
			await _entity_shots(a.trim_prefix("--entityshot="), spot)
			get_tree().quit()
			return
	main.sky.time_scale = 60.0
	var t0: float = main.sky.time_of_day
	var saw_high := false
	while pot._catch_count() == 0 and fposmod(main.sky.time_of_day - t0, 1.0) < 0.95:
		await get_tree().process_frame
		saw_high = saw_high or pot.submerged
	main.sky.time_scale = 1.0
	print("[entitycheck] submerged_seen=%s catch=%d bait_left=%d" % [saw_high, pot._catch_count(), pot.pot.bait_count])
	var before: int = p.inventory.get_item_count(&"shore_crab") + p.inventory.get_item_count(&"brine_oyster")
	pot.client_interact(p)   # collect
	await get_tree().process_frame
	var after: int = p.inventory.get_item_count(&"shore_crab") + p.inventory.get_item_count(&"brine_oyster")
	print("[entitycheck] collected=%d pot_now=%d" % [after - before, pot._catch_count()])
	get_tree().quit(0 if after > before else 1)


func _entity_shots(dir: String, pot_spot: Vector3i) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var p: Player = main.player
	main.sky.time_of_day = 0.42
	# 1) the crab pot on the flats, plus a sea barrel placed next to it
	_authority_place(&"sea_barrel", pot_spot + Vector3i(6, 0, 0), 1, 1)
	main.rig.dist = 4.0
	main.rig.pitch = -0.45
	for i in 6:
		await get_tree().process_frame
	await _grab(dir + "/entities_tidal.png")
	# 2) the starter homestead furniture
	var sp: Vector3i = Vector3i(main.world.gen.spawn)
	p.position = (Vector3(sp) + Vector3(0.5, 1, 0.5)) * VoxelWorld.VS
	p.position.y = _ground_y(sp.x, sp.z, sp.y + 12) * VoxelWorld.VS
	main.rig.dist = 6.5
	main.rig.pitch = -0.6
	for i in 10:
		await get_tree().process_frame
	await _grab(dir + "/entities_homestead.png")
	# 3) placement ghost (Blueprints tool, sea barrel)
	p.tool = 2
	p.placement.entity_blueprint = &"sea_barrel"
	main.rig.pitch = -0.75
	for i in 6:
		await get_tree().process_frame
	await _grab(dir + "/entities_ghost.png")


func _grab(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[entitycheck] shot ", path)


func _on_world_ready(_is_new: bool) -> void:
	if is_authority() and not starter_done:
		spawn_starter()
	if is_authority() and not caves_stocked:
		stock_caves()
	if is_authority() and not camps_stocked:
		stock_camps()
	if is_authority() and not under_stocked:
		stock_underground()
	if is_authority() and not wrecks_stocked:
		stock_wrecks()
	if is_authority() and not outposts_stocked:
		stock_outposts()
	if is_authority() and not hulk_stocked:
		stock_hulk()


## The loose boulders on the rocks above the Hulk's strand. Authority only, once.
func stock_hulk() -> void:
	hulk_stocked = true
	if main == null or main.world == null or main.world.gen == null or main.world.gen.hulk.is_empty():
		return
	var n := 0
	for b: Vector3i in main.world.gen.hulk.boulders:
		if _place_at(&"loose_boulder", b, 0, 8) != null:
			n += 1
	print("[hulk] %d loose boulders on the rocks" % n)


## The War Horn Totem and a strongbox in each Sea-Reaver outpost. Authority only, once.
func stock_outposts() -> void:
	outposts_stocked = true
	if main == null or main.world == null or main.world.gen == null:
		return
	var gen: WorldGen = main.world.gen
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(main.seed_value) ^ 0x5EA4
	var n := {"totem": 0, "box": 0}
	for i in gen.outposts.size():
		var rec: Dictionary = gen.outposts[i]
		var t := _place_at(&"war_horn_totem", rec.totem, 0, 6)
		if t is WarHornEntity:
			(t as WarHornEntity).outpost = i
			n.totem += 1
		var ent := _place_at(&"barnacled_chest", rec.chest, 0, 6)
		if ent is ChestEntity:
			(ent as ChestEntity).entity_name = "Reaver Strongbox"
			for it: Array in ChestEntity.outpost_loot(rng):
				(ent as ChestEntity).container.inventory.add_item(it[0], it[1])
			(ent as ChestEntity).container.inventory.add_item(_deal_scroll(), 1)
			n.box += 1
	if not gen.outposts.is_empty():
		print("[outposts] %d outposts, %d totems, %d strongboxes" % [gen.outposts.size(), n.totem, n.box])


## The next rare recipe scroll from this world's shuffled deck (reshuffled when it runs out).
func _deal_scroll() -> StringName:
	RecipeBook.register_scroll_items()
	if _scroll_deck.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(main.seed_value) ^ 0x5C2011
		_scroll_deck = RecipeBook.FOUND_SCROLLS.duplicate()
		for i in range(_scroll_deck.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t: Variant = _scroll_deck[i]
			_scroll_deck[i] = _scroll_deck[j]
			_scroll_deck[j] = t
	return RecipeBook.scroll_item(_scroll_deck.pop_back())


## A captain's locker in each beached wreck: salvage, coin, and a rare recipe scroll.
func stock_wrecks() -> void:
	wrecks_stocked = true
	if main == null or main.world == null or main.world.gen == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(main.seed_value) ^ 0x3EC4
	var placed := 0
	for w: Dictionary in main.world.gen.wrecks:
		var d: Vector2i = w.dir
		var al: Vector2i = w.get("along", Vector2i.ZERO)
		var ent: WorldEntity = null
		for k: int in [0, 4, -4, 8, -8, 12]:
			ent = _place_at(&"barnacled_chest", (w.chest as Vector3i) + Vector3i(al.x * k, 0, al.y * k), 1 if d.x != 0 else 0, 6)
			if ent != null:
				break
		if ent is ChestEntity:
			(ent as ChestEntity).entity_name = "Wreck Locker"
			for it: Array in ChestEntity.wreck_loot(rng):
				(ent as ChestEntity).container.inventory.add_item(it[0], it[1])
			(ent as ChestEntity).container.inventory.add_item(_deal_scroll(), 1)
			placed += 1
	if not main.world.gen.wrecks.is_empty():
		print("[wrecks] %d shipwrecks, %d lockers placed" % [main.world.gen.wrecks.size(), placed])


## The old brass mines' strongboxes, a cache at the bottom of each flooded sump, a freshwater
## spring in each karst cavern, and a stone well in each NPC village. Authority only, once.
func stock_underground() -> void:
	under_stocked = true
	if main == null or main.world == null or main.world.gen == null:
		return
	var gen: WorldGen = main.world.gen
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(main.seed_value) ^ 0x5A3F
	var n := {"mine": 0, "sump": 0, "spring": 0, "well": 0}
	for m: Dictionary in gen.mines:
		var ent := _place_at(&"barnacled_chest", m.chest, rng.randi_range(0, 3), 4)
		if ent is ChestEntity:
			(ent as ChestEntity).entity_name = "Miner's Strongbox"
			for it: Array in ChestEntity.mine_loot(rng):
				(ent as ChestEntity).container.inventory.add_item(it[0], it[1])
			(ent as ChestEntity).container.inventory.add_item(RecipeBook.scroll_item(RecipeBook.MINE_SCROLL), 1)
			n.mine += 1
	for s: Dictionary in gen.sumps:
		var ent := _place_at(&"barnacled_chest", s.chest, rng.randi_range(0, 3), 3)
		if ent is ChestEntity:
			(ent as ChestEntity).entity_name = "Sunken Cache"
			for it: Array in ChestEntity.sump_loot(rng):
				(ent as ChestEntity).container.inventory.add_item(it[0], it[1])
			(ent as ChestEntity).container.inventory.add_item(_deal_scroll(), 1)
			n.sump += 1
	for p: Vector3i in gen.springs:
		for off: Vector3i in [Vector3i.ZERO, Vector3i(4, 0, 0), Vector3i(-4, 0, 0), Vector3i(0, 0, 4), Vector3i(0, 0, -4)]:
			if _place_at(&"freshwater_spring", p + off, 0, 3) != null:
				n.spring += 1
				break
	for v: Dictionary in gen.villages:
		var c: Vector3 = v.center
		var side: Vector2i = v.side
		for off in [10, -10, 16, -16]:
			var w := Vector3i(roundi(c.x) + side.x * off, roundi(c.y), roundi(c.z) + side.y * off)
			if _place_at(&"stone_well", w, 0, 6) != null:
				n.well += 1
				break
	print("[under] %d mine strongboxes, %d sump caches, %d springs, %d village wells" % [n.mine, n.sump, n.spring, n.well])


## Place `type` on the ground near voxel `p` (searching `up` voxels above it). Null if blocked.
func _place_at(type: StringName, p: Vector3i, rot: int, up: int) -> WorldEntity:
	var col := Vector2i(p.x >> 5, p.z >> 5)
	if not main.world.store.is_column_generated(col):
		main.world.store.generate_column(col)
	var y := _ground_y(p.x, p.z, p.y + up)
	if y <= 0:
		return null
	return _authority_place(type, Vector3i(p.x, y, p.z), rot, 1)


## One barnacled chest in each Mud-Claw camp, in front of the totem. Authority only, once per world.
func stock_camps() -> void:
	camps_stocked = true
	if main == null or main.world == null or main.world.gen == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(main.seed_value) ^ 0xC1A3
	var placed := 0
	for rec: Dictionary in main.world.gen.camps:
		var p: Vector3i = rec.chest
		var col := Vector2i(p.x >> 5, p.z >> 5)
		if not main.world.store.is_column_generated(col):
			main.world.store.generate_column(col)
		var y := _ground_y(p.x, p.z, p.y + 6)
		if y <= 0:
			continue
		var g: Vector2 = rec.gate
		var rot := 0
		if absf(g.x) > absf(g.y):
			rot = 1 if g.x > 0 else 3
		else:
			rot = 0 if g.y > 0 else 2
		var ent := _authority_place(&"barnacled_chest", Vector3i(p.x, y, p.z), rot, 1)
		if ent is ChestEntity:
			for it: Array in ChestEntity.camp_loot(rng):
				(ent as ChestEntity).container.inventory.add_item(it[0], it[1])
			if rng.randf() < 0.3:
				(ent as ChestEntity).container.inventory.add_item(_deal_scroll(), 1)
			placed += 1
	if not main.world.gen.camps.is_empty():
		print("[camps] %d Mud-Claw camps, %d camp chests placed" % [main.world.gen.camps.size(), placed])


## One barnacled chest in each tidal grotto and karst cavern. Authority only, once per world.
func stock_caves() -> void:
	caves_stocked = true
	if main == null or main.world == null or main.world.gen == null:
		return
	var sites: Array = main.world.gen.cave_sites()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(main.seed_value) ^ 0xBA4AC1E
	var placed := 0
	for s: Dictionary in sites:
		var p: Vector3i = s.pos
		var col := Vector2i(p.x >> 5, p.z >> 5)
		if not main.world.store.is_column_generated(col):
			main.world.store.generate_column(col)
		var y := _ground_y(p.x, p.z, p.y + 2)
		if y <= 0:
			continue
		var c := Vector3i(p.x, y, p.z)
		var ent := _authority_place(&"barnacled_chest", c, rng.randi_range(0, 3), 1)
		if ent is ChestEntity:
			for it: Array in ChestEntity.cave_loot(int(s.kind), rng):
				(ent as ChestEntity).container.inventory.add_item(it[0], it[1])
			if rng.randf() < 0.35:
				(ent as ChestEntity).container.inventory.add_item(_deal_scroll(), 1)
			placed += 1
	if not sites.is_empty():
		print("[caves] %d cave systems, %d barnacled chests placed" % [sites.size(), placed])


## The homestead's starter furniture. Authority only, once per world (saved flag).
func spawn_starter() -> void:
	starter_done = true
	if main == null or main.world == null or main.world.gen == null:
		return
	var sp: Vector3i = Vector3i(main.world.gen.spawn)
	var layout := [
		[&"workbench", Vector3i(5, 0, 2)], [&"campfire", Vector3i(7, 0, -3)],
		[&"hearth_pot", Vector3i(3, 0, 7)], [&"driftwood_chest", Vector3i(-5, 0, 2)],
		[&"fisher_bed", Vector3i(-6, 0, -5)], [&"barber_mirror", Vector3i(5, 0, -6)],
		[&"feed_trough", Vector3i(8, 0, 4)], [&"poultry_coop", Vector3i(-8, 0, 6)],
	]
	for e: Array in layout:
		var c: Vector3i = sp + (e[1] as Vector3i)
		c.y = _ground_y(c.x, c.z, sp.y + 12)
		if c.y > 0 and not overlaps_any(e[0], c, 0):
			_authority_place(e[0], c, 0, 1)


func _ground_y(x: int, z: int, from_y: int) -> int:
	var w: VoxelWorld = main.world
	for y in range(from_y, maxi(1, from_y - 40), -1):
		var m := w.get_voxel(x, y - 1, z)
		if m != 0 and not Palette.is_foliage(m) and w.get_voxel(x, y, z) == 0:
			return y
	return -1


# ---------------------------------------------------------------- collision

## Would an entity of `type` at coord/rot overlap a solid entity?
func overlaps_any(type: StringName, coord: Vector3i, rot: int) -> bool:
	var probe := WorldEntity.new(type, "", coord)
	var proto: WorldEntity = null
	var id := resolve_type(type)
	if _types.has(id):
		proto = (_types[id].factory as Callable).call(coord)
		probe.size = proto.size
		proto.free()
	probe.rotation_steps = rot
	var box := probe.get_aabb().grow(-0.01)
	probe.free()
	for ent: WorldEntity in entities.values():
		if ent.solid and ent.get_aabb().intersects(box):
			return true
	return false


## True if the box (metres) overlaps a solid entity or a boat hull (except `ignore`).
func blocks(min_m: Vector3, max_m: Vector3, ignore: Object = null) -> bool:
	var box := AABB(min_m, max_m - min_m)
	for ent: WorldEntity in entities.values():
		if ent.solid and ent != ignore and ent.get_aabb().intersects(box):
			return true
	return _boat_blocks(box, ignore)


func point_solid(p: Vector3, ignore: Object = null) -> bool:
	return blocks(p - Vector3.ONE * 0.01, p + Vector3.ONE * 0.01, ignore)


const BOAT_HALF := Vector3(0.72, 0.0, 1.85)   # hull half-extents (beam, -, length)


func _boat_blocks(box: AABB, ignore: Object) -> bool:
	if main == null or main.boats == null:
		return false
	var seated_in: Object = main.player.boat if main.player != null else null
	var c := box.get_center()
	var he := box.size * 0.5
	var r := maxf(he.x, he.z)
	for b: Boat in main.boats.boats.values():
		if b == ignore or (ignore == null and b == seated_in):
			continue
		var bottom := b.position.y - 0.35
		var top := b.position.y + 0.55
		if box.position.y > top or box.end.y < bottom:
			continue
		var d := c - b.position
		var local := Vector2(d.x * cos(b.yaw) - d.z * sin(b.yaw), d.x * sin(b.yaw) + d.z * cos(b.yaw))
		if absf(local.x) < BOAT_HALF.x + r and absf(local.y) < BOAT_HALF.z + r:
			return true
	return false
