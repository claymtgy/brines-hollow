class_name Session
extends Node
## Phase 1B: persistence, join sync, player profiles, shared state, dedicated server.
##
## Authority model
##   Solo / host / dedicated server = authority. It owns terrain edits, farms, salt pans,
##   the village and boats, saves them to disk, and is the only machine that writes saves.
##   Clients keep a replica: terrain arrives as edited chunk columns at join (then live
##   commands), farm/village as snapshots plus per-cell updates.
##   Player inventories, quests and appearance are per-player profiles. The client simulates
##   them (trusted co-op for now) and the server stores them, keyed by a stable player key.
##
## Save layout: user://worlds/<name>/
##   world.json       seed, version, timestamps (human-readable)
##   terrain.dat      edited chunk columns (zstd)       {Vector2i: PackedByteArray}
##   state.dat        time, farm, village, boats, lights (zstd)
##   players/<key>.dat  one profile per player (zstd)
##
## Generic shared state (any system):
##   session.register_state(key: StringName, save: Callable() -> Variant, load: Callable(Variant))
##     * authority: `save` is written to state.dat["ext"][key] on every save; on load the stored
##       value is passed to `load` once the world is generated (or at registration, if later)
##     * joining players receive `save.call()` right after the terrain snapshot, before any
##       later live RPCs, and `load` runs on their machine (buffered until registered)
##     * live changes after that are the system's own business (its own RPCs)
##   signal world_ready(is_new_world: bool)  - after terrain + registered state are restored
##   is_new_world() -> bool                  - authority: no save existed for this world

const SAVE_VERSION := 1
const AUTOSAVE_SEC := 60.0
const SERVER_AUTOSAVE_SEC := 30.0
const PROFILE_SEND_SEC := 15.0
const FARM_SNAPSHOT_SEC := 10.0
const VILLAGE_SNAPSHOT_SEC := 20.0
const COLUMN_BATCH := 16

signal world_ready(is_new_world: bool)

var main: Node
var world_name := "hollow"
var dir := ""
var dedicated := false
var player_key := ""

var _profiles := {}            # authority: player_key -> profile Dictionary
var _peer_keys := {}           # authority: peer id -> player_key
var _loaded_state := {}        # authority: state.dat contents, applied as systems appear
var _pending_columns := []     # [[Vector2i, PackedByteArray]] until the world is ready
var _pending_farm: Variant = null
var _pending_village: Variant = null
var _pending_profile: Variant = null
var _profile_applied := false
var _farm_bound := false
var _village_applied := false
var _world_done := false
var _autosave_t := AUTOSAVE_SEC
var _profile_t := PROFILE_SEND_SEC
var _farm_t := FARM_SNAPSHOT_SEC
var _village_t := VILLAGE_SNAPSHOT_SEC
var _time_t := 1.0
var _args := {}
var _check_started := false
var _ext := {}                 # key -> {"save": Callable, "load": Callable}
var _pending_ext := {}         # key -> state received/loaded before its system registered
var _is_new_world := true


func setup(p_main: Node, args: Dictionary) -> void:
	main = p_main
	_args = args
	dedicated = args.has("server")
	world_name = String(args.get("world", "hollow")).validate_filename()
	if world_name == "":
		world_name = "hollow"
	dir = "user://worlds/%s/" % world_name
	player_key = _load_player_key(String(args.get("profile", "default")))
	if args.has("new-world") or args.has("new_world"):
		_archive_world()
	_is_new_world = not FileAccess.file_exists(dir + "world.json")
	# Not joining: our own save decides the seed and the time of day.
	if not args.has("join") and FileAccess.file_exists(dir + "world.json"):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + "world.json"))
		if meta is Dictionary and meta.has("seed"):
			main.seed_value = int(meta.seed)
		_loaded_state = _read_var(dir + "state.dat", {})
		if _loaded_state.has("tod"):
			main.sky.time_of_day = float(_loaded_state.tod)
		if _loaded_state.has("weather") and main.sky.weather != null:  # [weather] day clock
			main.sky.weather.deserialize(_loaded_state.weather)
		print("[session] world '%s' found (seed %d)" % [world_name, main.seed_value])
	main.multiplayer.peer_connected.connect(_on_peer_connected)
	main.multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	main.multiplayer.connected_to_server.connect(_on_connected_to_server)


## Generic persistence + join sync for any system (see header).
func register_state(key: StringName, save_fn: Callable, load_fn: Callable) -> void:
	_ext[key] = {"save": save_fn, "load": load_fn}
	if _pending_ext.has(key):
		load_fn.call(_pending_ext[key])
		_pending_ext.erase(key)


func is_new_world() -> bool:
	return _is_new_world and is_authority()


func _load_ext(key: StringName, data: Variant) -> void:
	if _ext.has(key):
		(_ext[key].load as Callable).call(data)
	else:
		_pending_ext[key] = data


func is_authority() -> bool:
	return not main.is_net or main.multiplayer.multiplayer_peer == null or main.multiplayer.is_server()


# ---------------------------------------------------------------- lifecycle hooks

## Called by Main right after world.generate(), before buffered edit commands are replayed.
func on_world_generated() -> void:
	_world_done = true
	var store: VoxelStore = main.world.store
	if is_authority():
		var cols: Dictionary = _read_var(dir + "terrain.dat", {})
		for c: Vector2i in cols:
			store.import_column(c, cols[c])
		if not cols.is_empty():
			print("[session] restored %d edited columns" % cols.size())
		_restore_boats()
		for p: Vector3i in _loaded_state.get("lights", []):
			main.world._add_light(p, Palette.LANTERN)
		for f in DirAccess.get_files_at(dir + "players") if DirAccess.dir_exists_absolute(dir + "players") else []:
			if f.ends_with(".dat"):
				_profiles[f.trim_suffix(".dat")] = _read_var(dir + "players/" + f, {})
		if _profiles.has(player_key) and not dedicated:
			_pending_profile = _profiles[player_key]
		var ext: Dictionary = _loaded_state.get("ext", {})
		for key: StringName in ext:
			_load_ext(key, ext[key])
	for e: Array in _pending_columns:
		store.import_column(e[0], e[1])
	_pending_columns.clear()
	world_ready.emit(is_new_world())


func _restore_boats() -> void:
	var saved: Array = _loaded_state.get("boats", [])
	if saved.is_empty() or main.boats == null:
		return
	main.boats._spawned = true  # don't spawn the default fleet on top of the saved one
	for b: Array in saved:
		main.boats._create(int(b[0]), b[1], float(b[2]))
	print("[session] restored %d boat(s)" % saved.size())


## Dedicated server: no local player, no rendering. `--server[=port]`.
func start_dedicated(port: int) -> void:
	main._started = true
	main.hud.show_menu(false)
	print("[server] world '%s', seed %d: generating..." % [world_name, main.seed_value])
	await main.world.generate(main.seed_value)
	on_world_generated()
	main.farm = NetFarm.new(VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP)
	main.village = SettlementManager.new(Vector3i(main.world.gen.spawn), "Brine's Hollow")
	main.world.focus_points = []   # the server never meshes terrain
	# Listen only once the world exists, so every joiner gets a complete snapshot.
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 16)
	if err != OK:
		push_error("[server] could not listen on port %d (error %d)" % [port, err])
		main.get_tree().quit(1)
		return
	main.multiplayer.multiplayer_peer = peer
	main.is_net = true
	print("[server] ready, listening on UDP %d" % port)


func _process(delta: float) -> void:
	if main == null:
		return
	_bind_systems()
	_maybe_run_check()
	if dedicated and _world_done:
		_server_tick(delta)
	if not _world_done:
		return
	if is_authority():
		_autosave_t -= delta
		if _autosave_t <= 0.0:
			_autosave_t = SERVER_AUTOSAVE_SEC if dedicated else AUTOSAVE_SEC
			save_all()
		if main.is_net and main.multiplayer.multiplayer_peer != null:
			_farm_t -= delta
			if _farm_t <= 0.0 and main.farm != null:
				_farm_t = FARM_SNAPSHOT_SEC
				farm_full.rpc(main.farm.serialize())
			_village_t -= delta
			if _village_t <= 0.0 and main.village != null:
				_village_t = VILLAGE_SNAPSHOT_SEC
				village_full.rpc(main.village.serialize())
	elif main.player != null and main.multiplayer.multiplayer_peer != null:
		_profile_t -= delta
		if _profile_t <= 0.0:
			_profile_t = PROFILE_SEND_SEC
			profile_upload.rpc_id(1, player_key, capture_profile())


## Hooks systems up as Main creates them (keeps Main's startup code untouched).
func _bind_systems() -> void:
	if not _farm_bound and main.farm != null:
		_farm_bound = true
		if main.farm is NetFarm:
			(main.farm as NetFarm).session = self
		var fs: Variant = _pending_farm if _pending_farm != null else _loaded_state.get("farm")
		if fs != null:
			main.farm.deserialize(fs)
		_pending_farm = null
	if not _village_applied and main.village != null:
		_village_applied = true
		var vs: Variant = _pending_village if _pending_village != null else _loaded_state.get("village")
		if vs != null:
			main.village.deserialize(vs)
		_pending_village = null
	if not _profile_applied and main.player != null and _pending_profile != null:
		_profile_applied = true
		apply_profile(_pending_profile)
		_pending_profile = null


func _server_tick(delta: float) -> void:
	if main.farm != null:
		main.farm.tick_all(delta, main.sky.water_level_vox, main.sky.is_day(), main.sky.is_raining())
	if main.village != null:
		main.village.tick_settlement(delta, main.sky.time_of_day)
	_time_t -= delta
	if _time_t <= 0.0:
		_time_t = 1.0
		main.time_sync.rpc(main.sky.time_of_day)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST or not _world_done:
		return
	if is_authority():
		save_all()
	elif main.player != null and main.multiplayer.multiplayer_peer != null:
		# Leaving a server: hand over our latest profile before the window closes.
		profile_upload.rpc_id(1, player_key, capture_profile())
		main.multiplayer.multiplayer_peer.poll()


# ---------------------------------------------------------------- player profiles

func capture_profile() -> Dictionary:
	var p: Player = main.player
	var d := {"v": SAVE_VERSION, "t": Time.get_unix_time_from_system()}
	if p == null:
		return d
	d["inv"] = p.inventory.serialize()
	d["cust"] = p.customizer.serialize()
	d["recipes"] = p.recipes.serialize()
	d["pos"] = p.position
	d["yaw"] = main.rig.yaw
	if main.quests != null:
		d["quests"] = main.quests.serialize()
	return d


func apply_profile(d: Dictionary) -> void:
	var p: Player = main.player
	if p == null or d.is_empty():
		return
	if d.has("inv"):
		p.inventory.deserialize(d.inv)
	if d.has("cust"):
		p.customizer.deserialize(d.cust)
	if d.has("recipes"):
		p.recipes.deserialize(d.recipes)
	if d.has("quests") and main.quests != null:
		main.quests.deserialize(d.quests)
	if d.has("pos"):
		p.position = d.pos
		main.rig.yaw = float(d.get("yaw", main.rig.yaw))
	main.hud.show_toast("Welcome back")
	print("[session] restored profile for this player")


func _load_player_key(profile: String) -> String:
	var path := "user://profile_%s.cfg" % profile.validate_filename()
	var cfg := ConfigFile.new()
	cfg.load(path)
	var key: String = cfg.get_value("player", "key", "")
	if key == "":
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		key = "%08x%08x" % [rng.randi(), rng.randi()]
		cfg.set_value("player", "key", key)
		cfg.save(path)
	return key


# ---------------------------------------------------------------- saving

func save_all() -> void:
	if not is_authority() or not _world_done:
		return
	var t0 := Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(dir + "players")
	var store: VoxelStore = main.world.store
	var cols := {}
	for c: Vector2i in store.get_edited_columns():
		cols[c] = store.export_column(c)
	_write_var(dir + "terrain.dat", cols)
	var boats := []
	if main.boats != null:
		for b: Boat in main.boats.boats.values():
			boats.append([b.id, b.position, b.yaw])
	var state := {
		"v": SAVE_VERSION,
		"tod": main.sky.time_of_day,
		"weather": main.sky.weather.serialize() if main.sky.weather != null else {},
		"farm": main.farm.serialize() if main.farm != null else {},
		"village": main.village.serialize() if main.village != null else {},
		"boats": boats,
		"lights": main.world._lights.keys(),
		"ext": _save_ext(),
	}
	_write_var(dir + "state.dat", state)
	if main.player != null and not dedicated:
		_profiles[player_key] = capture_profile()
	for key: String in _profiles:
		_write_var(dir + "players/%s.dat" % key.validate_filename(), _profiles[key])
	var meta := {"name": world_name, "seed": main.seed_value, "version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system()}
	var f := FileAccess.open(dir + "world.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(meta, "  "))
	print("[session] saved '%s': %d columns, %d players (%d ms)" % [
		world_name, cols.size(), _profiles.size(), Time.get_ticks_msec() - t0])


func _save_ext() -> Dictionary:
	var out := {}
	for key: StringName in _ext:
		out[key] = (_ext[key].save as Callable).call()
	return out


func _write_var(path: String, value: Variant) -> void:
	# Write to a temp file then swap, so a crash mid-save never corrupts the old save.
	var tmp := path + ".tmp"
	var f := FileAccess.open_compressed(tmp, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("[session] cannot write %s (%d)" % [tmp, FileAccess.get_open_error()])
		return
	f.store_var(value)
	f.close()
	DirAccess.rename_absolute(tmp, path)


func _read_var(path: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		push_error("[session] cannot read %s" % path)
		return fallback
	var v: Variant = f.get_var()
	return v if typeof(v) == typeof(fallback) else fallback


func _archive_world() -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	var dest := "user://worlds/%s.bak-%d" % [world_name, Time.get_unix_time_from_system()]
	DirAccess.rename_absolute(dir.trim_suffix("/"), dest)
	print("[session] previous world archived to ", dest)


# ---------------------------------------------------------------- join sync (server -> client)

func _on_peer_connected(id: int) -> void:
	if not main.multiplayer.is_server() or not _world_done:
		return
	# Everything goes out in this same frame, ahead of any later edit commands, so the
	# client always applies "snapshot, then live edits" in the right order.
	var store: VoxelStore = main.world.store
	var batch := []
	var sent := 0
	for c: Vector2i in store.get_edited_columns():
		batch.append([c, store.export_column(c)])
		if batch.size() >= COLUMN_BATCH:
			sent += batch.size()
			terrain_columns.rpc_id(id, _pack(batch))
			batch = []
	if not batch.is_empty():
		sent += batch.size()
		terrain_columns.rpc_id(id, _pack(batch))
	if main.farm != null:
		farm_full.rpc_id(id, main.farm.serialize())
	if main.village != null:
		village_full.rpc_id(id, main.village.serialize())
	for key: StringName in _ext:
		ext_state.rpc_id(id, key, _pack((_ext[key].save as Callable).call()))
	print("[session] peer %d joined: sent %d edited columns, %d state blocks" % [id, sent, _ext.size()])


func _on_peer_disconnected(id: int) -> void:
	_peer_keys.erase(id)


func _on_connected_to_server() -> void:
	hello.rpc_id(1, player_key)


static func _pack(v: Variant) -> PackedByteArray:
	var raw := var_to_bytes(v)
	var out := PackedByteArray()
	out.resize(8)
	out.encode_u64(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
	return out


static func _unpack(data: PackedByteArray) -> Variant:
	var n := data.decode_u64(0)
	return bytes_to_var(data.slice(8).decompress(n, FileAccess.COMPRESSION_ZSTD))


@rpc("authority", "call_remote", "reliable")
func ext_state(key: StringName, data: PackedByteArray) -> void:
	_load_ext(key, _unpack(data))


@rpc("authority", "call_remote", "reliable")
func terrain_columns(data: PackedByteArray) -> void:
	var batch: Array = _unpack(data)
	if _world_done:
		for e: Array in batch:
			main.world.store.import_column(e[0], e[1])
	else:
		_pending_columns.append_array(batch)


@rpc("any_peer", "call_remote", "reliable")
func hello(key: String) -> void:
	if not main.multiplayer.is_server():
		return
	var id := main.multiplayer.get_remote_sender_id()
	key = key.validate_filename().substr(0, 32)
	_peer_keys[id] = key
	if _profiles.has(key):
		restore_profile.rpc_id(id, _profiles[key])
	print("[session] peer %d is player %s%s" % [id, key, " (returning)" if _profiles.has(key) else " (new)"])


@rpc("authority", "call_remote", "reliable")
func restore_profile(d: Dictionary) -> void:
	_pending_profile = d
	_profile_applied = false


@rpc("any_peer", "call_remote", "reliable")
func profile_upload(key: String, d: Dictionary) -> void:
	if not main.multiplayer.is_server():
		return
	var id := main.multiplayer.get_remote_sender_id()
	if _peer_keys.get(id, "") != key.validate_filename().substr(0, 32):
		return  # only accept a profile for the key this peer said hello with
	_profiles[_peer_keys[id]] = d


# ---------------------------------------------------------------- shared state: farm & village

@rpc("authority", "call_remote", "reliable")
func farm_full(d: Dictionary) -> void:
	if main.farm != null:
		main.farm.deserialize(d)
	else:
		_pending_farm = d


@rpc("authority", "call_remote", "reliable")
func village_full(d: Dictionary) -> void:
	if main.village != null:
		main.village.deserialize(d)
	else:
		_pending_village = d


## Authority: tell every client about one farm cell's new state.
func broadcast_farm_cell(pos: Vector3i) -> void:
	if main.is_net and main.multiplayer.multiplayer_peer != null and main.farm is NetFarm:
		farm_cell.rpc(pos, (main.farm as NetFarm).cell_state(pos))


## Client: ask the server to perform a farm action.
func send_farm_action(pos: Vector3i, action: Dictionary) -> void:
	if main.multiplayer.multiplayer_peer != null:
		farm_req.rpc_id(1, pos, action)


@rpc("any_peer", "call_remote", "reliable")
func farm_req(pos: Vector3i, action: Dictionary) -> void:
	if not main.multiplayer.is_server() or not (main.farm is NetFarm):
		return
	var id := main.multiplayer.get_remote_sender_id()
	var grants: Array = (main.farm as NetFarm).server_apply(pos, action)
	farm_cell.rpc(pos, (main.farm as NetFarm).cell_state(pos))
	if not grants.is_empty():
		grant_items.rpc_id(id, grants)


@rpc("authority", "call_remote", "reliable")
func farm_cell(pos: Vector3i, d: Dictionary) -> void:
	if main.farm is NetFarm:
		(main.farm as NetFarm).apply_cell_state(pos, d)


@rpc("authority", "call_remote", "reliable")
func grant_items(grants: Array) -> void:
	var p: Player = main.player
	if p == null:
		return
	var parts := []
	for g: Array in grants:
		var n: int = int(g[1])
		if n <= 0:
			continue
		p.inventory.add_item(StringName(g[0]), n)
		var def: ItemDef = ItemDB.get_item(StringName(g[0]))
		parts.append("%d %s" % [n, def.name if def != null else String(g[0])])
	if not parts.is_empty():
		main.hud.show_toast("Received " + ", ".join(parts))


# ---------------------------------------------------------------- dev checks
#   --persistcheck=write | verify      solo save -> quit -> reload
#   --synccheck (server) / --synccheck=a|b (clients, use --profile=a|b)

func _check_cell() -> Vector3i:
	return Vector3i(main.world.gen.spawn) + Vector3i(0, 0, 8)


func _check_report(tag: String) -> void:
	var c := _check_cell()
	var inv_stone: int = main.player.inventory.get_item_count(&"stone") if main.player != null else -1
	var plots: int = main.farm.plots.size() if main.farm != null else -1
	var planted := 0
	if main.farm != null:
		for pl: CropPlot in main.farm.plots.values():
			if not pl.is_empty():
				planted += 1
	# Hash of the edited columns' raw data: comparable between server and clients even
	# though the server never generates the untouched terrain around them.
	var cols: Array = main.world.store.get_edited_columns()
	cols.sort_custom(func(x: Vector2i, y: Vector2i) -> bool: return x.x < y.x or (x.x == y.x and x.y < y.y))
	var eh := 17
	for col: Vector2i in cols:
		eh = hash([eh, col, main.world.store.export_column(col)])
	# Entities (Agent A): count + the check crab pot's bait + check barrel's stored fish.
	var ents := -1
	var pot_bait := -1
	var barrel_fish := -1
	if main.entities != null:
		ents = main.entities.get_count()
		var pot: WorldEntity = main.entities.get_entity_at(c + Vector3i(-8, 0, 4))
		if pot is CrabPotEntity:
			pot_bait = (pot as CrabPotEntity).pot.bait_count
		var barrel: WorldEntity = main.entities.get_entity_at(c + Vector3i(14, 0, -12))
		if barrel is ChestEntity:
			barrel_fish = (barrel as ChestEntity)._stored_count()
	print("[%s] edits_hash=%d checksum=%d edited_cols=%d plots=%d planted=%d inv_stone=%d boats=%d entities=%d pot_bait=%d barrel=%d" % [
		tag, eh, main._region_checksum(c, 14), cols.size(), plots, planted,
		inv_stone, main.boats.boats.size() if main.boats != null else -1, ents, pot_bait, barrel_fish])


func _check_edits() -> void:
	var c := _check_cell()
	main._on_command_requested({"t": "prefab", "p": c, "r": 1, "id": 7})
	main._on_command_requested({"t": "dig", "p": c + Vector3i(5, -1, 0), "r": 3})
	main._on_command_requested({"t": "place", "p": c + Vector3i(-5, 2, 3), "r": 2, "m": Palette.ROOF_BLUE})
	var cell := c + Vector3i(0, -1, -6)
	main.farm.till_plot(cell)
	main.player.inventory.add_item(&"seed_shore_wheat", 1)
	main.farm.plant_from_inventory(cell, main.player.inventory)
	main.player.inventory.add_item(&"stone", 7)
	# Entities (Agent A): a crab pot and a sea barrel, placed through the authority.
	if main.entities != null:
		main.entities.request_place(&"crab_pot", c + Vector3i(-8, 0, 4), 0)
		main.entities.request_place(&"sea_barrel", c + Vector3i(14, 0, -12), 1)


## Entities (Agent A): bait the check pot and stock the check barrel (after they exist).
func _check_entity_actions() -> void:
	if main.entities == null:
		return
	var c := _check_cell()
	var pot: WorldEntity = main.entities.get_entity_at(c + Vector3i(-8, 0, 4))
	if pot != null:
		main.entities.request_action(pot, &"bait", {"item": &"kelp_frond", "n": 2})
	var barrel: WorldEntity = main.entities.get_entity_at(c + Vector3i(14, 0, -12))
	if barrel != null:
		main.entities.request_action(barrel, &"deposit", {"item": &"silver_mackerel", "n": 3})


func _maybe_run_check() -> void:
	if _check_started or not _world_done:
		return
	if _args.has("persistcheck") and main.player != null and main.farm != null and _farm_bound \
			and (_profile_applied or not _profiles.has(player_key)):
		_check_started = true
		_persist_check(String(_args.persistcheck))
	elif _args.has("synccheck") and (dedicated and main.farm != null or main.player != null):
		_check_started = true
		_sync_check(String(_args.synccheck))


func _persist_check(mode: String) -> void:
	await get_tree().create_timer(1.0).timeout
	if mode == "write":
		_check_edits()
		await get_tree().create_timer(1.0).timeout
		_check_entity_actions()
		await get_tree().create_timer(0.5).timeout
		_check_report("persist-write")
		save_all()
	else:
		_check_report("persist-verify")
	get_tree().quit()


func _sync_check(role: String) -> void:
	match role:
		"", "server":
			await get_tree().create_timer(float(_args.get("checktime", "20"))).timeout
			_check_report("sync-server")
			save_all()
		"a":
			await get_tree().create_timer(2.0).timeout
			_check_edits()
			await get_tree().create_timer(1.5).timeout
			_check_entity_actions()
			await get_tree().create_timer(1.5).timeout
			_check_report("sync-a")
			profile_upload.rpc_id(1, player_key, capture_profile())
			await get_tree().create_timer(1.0).timeout
		_:
			await get_tree().create_timer(float(_args.get("checktime", "4"))).timeout
			_check_report("sync-" + role)
	get_tree().quit()
