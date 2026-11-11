class_name Main
extends Node3D
## Brine's Hollow prototype entry point.
## Co-op model: host-authoritative. Everyone generates the same world from the seed;
## edits are small commands relayed by the host (plus a log replayed for late joiners).
##
## Command line (after `--`):  --solo | --host | --join=IP   [--seed=N] [--time=0.5] [--shot=DIR]

const PORT := 24565
const VS := VoxelWorld.VS

var seed_value := 1106
## World layout (VoxelWorld.apply_layout): new worlds get LAYOUT_NEW; a saved world keeps
## the layout in its world.json (1 when missing); a joining client takes the host's.
var world_layout := VoxelWorld.LAYOUT_NEW
var sky: SkyCycle
var world: VoxelWorld
var player: Player
var rig: CameraRig
var hud: Hud
var boats: BoatManager
var farm: FarmManager
var farm_visuals: FarmVisuals
var quests: QuestManager
var village: SettlementManager
var entities: EntityManager
var session: Session
var creatures: CreatureNet   # Agent C: creatures & optional combat
var tutorial: Tutorial        # Wren's starter missions
var settings: GameSettings
var settings_menu: SettingsMenu
var inventory_ui: InventoryUI
var crafting_ui: CraftingUI
var build_menu_ui: BuildMenuUI
var quest_log_ui: QuestLogUI
var village_mgr: VillageManager
var trade: TradeManager
var livestock_mgr: Node
var npc_villages: NpcVillages
var ambient_fish: AmbientFishManager = null
const FloatingLanternManager = preload("res://scripts/festivals/floating_lanterns.gd")
var floating_lanterns: Node3D = null
var atlas := IslandAtlas.new()   # island names + which ones this player has found
var _atlas_gen: Object = null
var _atlas_t := 0.0
var controller: ControllerManager = ControllerManager.new()

static var force_menu := false
var is_net := false
var edit_log: Array = []
var remotes := {}
var _pending_cmds: Array = []
var _send_t := 0.0
var _time_sync_t := 0.0
var _started := false
var _menu_launch := false   # true when the player starts from the main menu (not CLI)
var _quitting := false
var _args := {}
var _assigned_spawn_idx: int = -1
var _menu_cam_orbit := 0.0


func _ready() -> void:
	controller.setup_input_map()
	var raw_args := OS.get_cmdline_user_args()
	for a in OS.get_cmdline_args():
		if a.begins_with("--") and not raw_args.has(a):
			raw_args.append(a)
	for a in raw_args:
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if _args.has("seed"):
		seed_value = int(_args.seed)
	if _args.has("layout"):
		world_layout = int(_args.layout)

	sky = SkyCycle.new()
	add_child(sky)
	if _args.has("time"):
		sky.time_of_day = float(_args.time)
	world = VoxelWorld.new()
	world.sky = sky
	add_child(world)
	world.loading_progress.connect(func(t: String, f: float) -> void: hud.set_loading(true, t, f))
	world.dug.connect(_on_dug)
	world.tree_felled.connect(_on_tree_felled)

	rig = CameraRig.new()
	add_child(rig)
	rig.world = world
	rig.first_person_changed.connect(func(fp: bool) -> void:
		if settings != null:
			settings.first_person = fp
			settings.save()
	)
	rig.cam.far = 1500.0  # archipelago: distant islands stay visible through the fog
	# Menu backdrop: look out over the sea.
	rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.08, 0.6, 0)),
			Vector3(VoxelWorld.WX * VS * 0.5, 9, VoxelWorld.WZ * VS + 25))

	hud = Hud.new()
	hud.set_controller(controller)
	add_child(hud)
	hud.solo_pressed.connect(start_solo)
	hud.host_pressed.connect(start_host)
	hud.join_pressed.connect(start_join)

	# Rowboats (spawning, boarding, co-op sync). Must exist on every peer before RPCs arrive.
	boats = BoatManager.new()
	boats.name = "Boats"
	boats.main = self
	add_child(boats)

	# Persistence, join sync, player profiles, shared state, dedicated server (Phase 1B).
	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.setup(self, _args)
	session.register_state(&"lighthouse",
		func() -> Variant:
			return {"fuel": _beam.fuel_sec if _beam != null else (_saved_lighthouse_fuel if _saved_lighthouse_fuel >= 0.0 else 720.0)},
		func(d: Variant) -> void:
			if d is Dictionary:
				var f := float(d.get("fuel", 720.0))
				_saved_lighthouse_fuel = f
				if _beam != null:
					_beam.fuel_sec = f
	)

	# Entities (Agent A): created up front so the node exists on every peer before RPCs arrive.
	# Saved/synced via Session.register_state; starter furniture spawns once per world.
	entities = EntityManager.new()
	entities.name = "EntityManager"
	add_child(entities)
	entities.bind(self)

	# --- Agent C: creatures & optional combat (host-simulated; see scripts/creatures/) ---
	creatures = CreatureNet.new()
	creatures.name = "Creatures"
	creatures.main = self
	add_child(creatures)
	# --- end Agent C ---

	# Player settings (user://settings.cfg). Dev args override for this run only:
	#   --preset=deck|low|medium|high   --deck   --radius=N
	settings = GameSettings.load_or_default()
	if _args.has("deck"):
		settings.apply_preset(GameSettings.Preset.DECK)
	elif _args.has("preset"):
		var pi := ["deck", "low", "medium", "high"].find(String(_args.preset).to_lower())
		if pi >= 0:
			settings.apply_preset(pi)
	if _args.has("radius"):
		settings.view_distance = int(_args.radius)
	settings.apply(self)
	get_viewport().size_changed.connect(func() -> void:
		get_viewport().scaling_3d_scale = settings.effective_render_scale(get_viewport())
		if DisplayServer.get_name() != "headless":
			var f := settings.effective_ui_scale(get_viewport())
			if not is_equal_approx(get_tree().root.content_scale_factor, f):
				get_tree().root.content_scale_factor = f)
	settings_menu = SettingsMenu.new()
	settings_menu.name = "SettingsMenu"
	add_child(settings_menu)
	settings_menu.setup(self, settings)

	inventory_ui = InventoryUI.new()
	inventory_ui.name = "InventoryUI"
	add_child(inventory_ui)
	inventory_ui.setup(self)

	crafting_ui = CraftingUI.new()
	crafting_ui.name = "CraftingUI"
	add_child(crafting_ui)
	crafting_ui.setup(self)

	build_menu_ui = BuildMenuUI.new()
	build_menu_ui.name = "BuildMenuUI"
	add_child(build_menu_ui)
	build_menu_ui.setup(self)

	quest_log_ui = QuestLogUI.new()
	quest_log_ui.name = "QuestLogUI"
	add_child(quest_log_ui)
	quest_log_ui.setup(self)

	# --- Village & trade (agent B): drifters, homes, routines, merchant ships. Their RPC
	# nodes (/root/Main/Village, /root/Main/Trade) must exist on every peer.
	village_mgr = VillageManager.new()
	village_mgr.main = self
	add_child(village_mgr)
	trade = TradeManager.new()
	trade.main = self
	add_child(trade)
	# --- NPC villages on the other islands (big archipelago worlds)
	npc_villages = NpcVillages.new()
	npc_villages.main = self
	add_child(npc_villages)
	# --- Storm Incursion defense manager
	var storm_incursion := StormIncursionManager.new()
	storm_incursion.name = "StormIncursion"
	add_child(storm_incursion)

	# --- Domestic livestock (pens, feed, yields, herding)
	const LivestockManagerClass := preload("res://scripts/livestock/livestock_manager.gd")
	livestock_mgr = LivestockManagerClass.new()
	livestock_mgr.main = self
	add_child(livestock_mgr)
	# --- Starter tutorial (Wren the Wayfarer). Crafting lives in InventoryUI.
	tutorial = Tutorial.new()
	tutorial.name = "Tutorial"
	add_child(tutorial)
	tutorial.setup(self)
	if _args.has("villagecheck"):
		village_mgr.call_deferred("run_check", String(_args.villagecheck))
	elif _args.has("villagescheck"):
		npc_villages.call_deferred("run_check")
	elif _args.has("tradecheck"):
		trade.call_deferred("run_check")
	# --- end village & trade

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if force_menu:
		force_menu = false
		_menu_launch = true   # the world picked in this menu must be the one that loads
		hud.show_menu(true)
	elif _args.has("server"):
		session.start_dedicated(int(_args.server) if String(_args.server).is_valid_int() else PORT)
	elif _args.has("host"):
		start_host()
	elif _args.has("join"):
		start_join(_args.join if _args.join != "" else "127.0.0.1")
	elif _args.has("solo") or _args.has("tutorialcheck") or _args.has("shot") or _args.has("bench") or _args.has("boatcheck") or _args.has("skiffcheck") or _args.has("lhcheck") or _args.has("campcheck") or _args.has("undercheck") \
			or (_args.has("villagecheck") and not _args.has("join") and not _args.has("host")) or _args.has("tradecheck"):
		start_solo()
	else:
		_menu_launch = true
		hud.show_menu(true)


func _setup_input() -> void:
	controller.setup_input_map()


# ---------------------------------------------------------------- session start

func start_solo() -> void:
	is_net = false
	_begin_world()


## The game port; `--port=N` overrides it (dev checks that run beside another host).
func net_port() -> int:
	return int(_args.port) if String(_args.get("port", "")).is_valid_int() else PORT


func start_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(net_port(), 8)
	if err != OK:
		hud.show_menu(true, "Could not host on port %d (error %d)." % [net_port(), err])
		return
	multiplayer.multiplayer_peer = peer
	is_net = true
	_begin_world()


func start_join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, net_port())
	if err != OK:
		hud.show_menu(true, "Could not start client (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	is_net = true
	if hud != null and session != null:
		session.save_skin_preference(hud.menu_customizer.serialize())
	hud.show_menu(true, "Connecting to %s..." % ip)


func return_to_main_menu() -> void:
	if _quitting:
		return
	_quitting = true
	if session != null and session.is_authority():
		session.save_all()
	elif session != null and player != null and multiplayer != null and multiplayer.multiplayer_peer != null:
		session.profile_upload.rpc_id(1, session.player_key, session.capture_profile())
		await get_tree().create_timer(0.3).timeout
	if multiplayer != null and multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null
	is_net = false
	Main.force_menu = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file("res://main.tscn")


func save_and_quit() -> void:
	if _quitting:
		return
	_quitting = true
	if session != null and session.is_authority():
		session.save_all()
	elif session != null and player != null and multiplayer != null and multiplayer.multiplayer_peer != null:
		session.profile_upload.rpc_id(1, session.player_key, session.capture_profile())
		await get_tree().create_timer(0.3).timeout
	get_tree().quit()


## Nearest column to `sp` whose top voxel is natural ground with open air above it.
func _find_clear_spawn(sp: Vector3i) -> Vector3:
	var ground := [Palette.GRASS, Palette.GRASS_DRY, Palette.SAND, Palette.WET_SAND, Palette.DIRT, Palette.GRAVEL]
	for r in range(0, 30):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var x := sp.x + dx
				var z := sp.z + dz
				var y := VoxelWorld.WY - 1
				while y > 0 and (world.get_voxel(x, y, z) == 0 or Palette.is_plant(world.get_voxel(x, y, z))):
					y -= 1
				if ground.has(world.get_voxel(x, y, z)) and y + 1 > VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP:
					return Vector3(x + 0.5, y + 1, z + 0.5)
	return Vector3(sp) + Vector3(0.5, 0, 0.5)


func _begin_world() -> void:
	if _started:
		return
	_started = true
	# Only a game started from the main menu takes its world/seed fields; command-line
	# launches (--world, --seed, --host, dev checks) keep what they asked for.
	if _menu_launch and hud != null and hud.menu != null and (not is_net or multiplayer.is_server()):
		hud.apply_menu_selections_to_main(self)
	hud.show_menu(false)
	hud.set_loading(true, "Starting...", 0.0)
	VoxelWorld.apply_layout(world_layout)
	print("[world] layout %d: %d x %d x %d voxels, sea at %d" % [VoxelWorld.layout, VoxelWorld.WX, VoxelWorld.WY, VoxelWorld.WZ, int(VoxelWorld.SEA_MID)])
	await world.generate(seed_value)
	session.on_world_generated()  # saved / host terrain first, then buffered live edits
	for cmd in _pending_cmds:
		world.apply_command(cmd)
	_pending_cmds.clear()

	farm = NetFarm.new(VoxelWorld.SEA_MID, VoxelWorld.TIDE_AMP)
	farm_visuals = FarmVisuals.new()
	farm_visuals.name = "FarmVisuals"
	farm_visuals.setup(farm, world)
	add_child(farm_visuals)
	quests = QuestManager.new()
	village = SettlementManager.new(Vector3i(world.gen.spawn), "Brine's Hollow")

	# Act I (the story quests) is handed over by Wren once the lessons are done or skipped;
	# see Tutorial.start_story().

	player = Player.new()
	player.world = world
	player.rig = rig
	player.sky = sky
	player.hud = hud
	player.farm = farm
	player.quests = quests
	player.village = village
	player.entities = entities
	player.controller = controller
	player.inventory_ui = inventory_ui
	player.crafting_ui = crafting_ui
	player.build_menu_ui = build_menu_ui
	add_child(player)
	if session != null and not session.selected_customizer_data.is_empty():
		player.customizer.deserialize(session.selected_customizer_data)
	player.bind_quest_signals()
	var chosen_spawn: Dictionary = {}
	if _args.has("homestead") or _args.has("bench") or _args.has("boatcheck") or _args.has("skiffcheck") or _args.has("lhcheck") or _args.has("shot"):
		chosen_spawn = world.gen.starter_spawns[0] if world.gen != null and not world.gen.starter_spawns.is_empty() else {"pos": world.gen.spawn, "yaw": world.gen.spawn_yaw, "name": "Homestead Pier"}
	elif _assigned_spawn_idx >= 0 and world.gen != null:
		chosen_spawn = world.gen.get_spawn_by_index(_assigned_spawn_idx)
	elif world.gen != null:
		# Every castaway washes up on the homestead beach, beside the ruined hut, so a new
		# player starts with a landmark and co-op crews start together.
		chosen_spawn = world.gen.get_spawn_by_index(0)
	else:
		chosen_spawn = {"pos": Vector3.ZERO, "yaw": 0.0, "name": "Coast"}
	var spawn_at := Vector3(chosen_spawn.pos)
	if is_net and world.gen != null and not world.gen.starter.is_empty():
		# Spread a crew along the beach a few steps apart instead of on top of each other.
		var side: Vector2i = world.gen.starter.side
		var slot := float(posmod(multiplayer.get_unique_id(), 5)) - 2.0
		spawn_at += Vector3(side.x, 0, side.y) * slot * 8.0

	player.position = _find_clear_spawn(Vector3i(spawn_at)) * VS
	player.command_requested.connect(_on_command_requested)
	rig.target = player
	rig.yaw = chosen_spawn.yaw

	if ambient_fish == null:
		ambient_fish = AmbientFishManager.new()
		ambient_fish.name = "AmbientFish"
		add_child(ambient_fish)
		ambient_fish.setup(world, sky, player)
	if floating_lanterns == null:
		floating_lanterns = FloatingLanternManager.new()
		floating_lanterns.name = "FloatingLanterns"
		add_child(floating_lanterns)
		floating_lanterns.setup(world, sky, player)
	hud.set_loading(false)
	hud.show_hud(true)
	hud.show_toast("You wash ashore beside a storm-battered hut." if chosen_spawn.get("id", 0) == 0 else "Washed ashore: %s" % chosen_spawn.get("name", "Starter Island"))
	if _args.has("boatcheck"):
		boats.run_check(_args.boatcheck)
	elif _args.has("skiffcheck"):
		boats.run_skiff_check(String(_args.skiffcheck))
	elif _args.has("lhcheck"):
		_run_lighthouse_check(String(_args.lhcheck))
	elif _args.has("campcheck"):
		creatures.camps.run_check(String(_args.campcheck))
	elif _args.has("undercheck"):
		UndergroundCheck.run(self, String(_args.undercheck))
	elif _args.has("netcheck"):
		_run_netcheck()
	elif _args.has("bench"):
		_run_bench()
	elif not _args.has("shot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_run_screenshots(_args.shot)


# ---------------------------------------------------------------- islands

## Names the islands once the world exists, then announces each landfall.
var _beam: LighthouseBeam = null
var _saved_lighthouse_fuel: float = -1.0


## --lhcheck=DIR: look at the starter lighthouse by day and at night.
func _run_lighthouse_check(dir: String) -> void:
	player.input_enabled = false
	var lp: Variant = world.gen.starter.get("lighthouse")
	print("[lighthouse] site %s" % [lp])
	if not (lp is Vector3i):
		get_tree().quit()
		return
	var c: Vector3 = Vector3(lp as Vector3i) * VS
	var hut: Vector3 = Vector3(world.gen.starter.hut) * VS
	print("[lighthouse] %.1f m from the hut, lantern %.1f m up" % [Vector2(c.x - hut.x, c.z - hut.z).length(), c.y - hut.y])
	var away := Vector3(hut.x - c.x, 0, hut.z - c.z).normalized()
	player.position = Vector3(c.x, 0, c.z) + away * 9.0
	player.position.y = float(world.gen.col_h(floori(player.position.x / VS), floori(player.position.z / VS)) + 2) * VS
	rig.yaw = atan2(-away.x, -away.z) + PI
	rig.pitch = 0.18
	rig.dist = 14.0
	hud.show_hud(false)
	sky.time_of_day = 0.45
	await get_tree().create_timer(3.0).timeout
	print("[lighthouse] lantern voxel %d (LANTERN=%d), beam %s" % [world.get_voxel((lp as Vector3i).x, (lp as Vector3i).y, (lp as Vector3i).z), Palette.LANTERN, _beam != null])
	await _shot(dir, "lighthouse_day")
	sky.time_of_day = 0.92
	rig.dist = 22.0
	rig.pitch = 0.05
	await get_tree().create_timer(1.5).timeout
	print("[lighthouse] beam visible at night: %s" % [_beam != null and _beam.visible])
	await _shot(dir, "lighthouse_night")
	get_tree().quit()


## The lighthouse's night beam, once its lantern is actually in the world (a column the
## player had already built in keeps their voxels instead of the lighthouse).
func _tick_lighthouse() -> void:
	if _beam != null or world == null or world.gen == null or not world.ready_for_play:
		return
	var lp: Variant = world.gen.starter.get("lighthouse")
	if not (lp is Vector3i):
		return
	var c: Vector3i = lp
	if not world.store.is_column_generated(Vector2i(c.x >> 5, c.z >> 5)):
		return
	_beam = LighthouseBeam.new()
	add_child(_beam)
	_beam.setup(sky, (Vector3(c) + Vector3(0.5, 0.5, 0.5)) * VS)
	if _saved_lighthouse_fuel >= 0.0:
		_beam.fuel_sec = _saved_lighthouse_fuel
	if world.get_voxel(c.x, c.y, c.z) != Palette.LANTERN:
		_beam.set_process(false)   # no lighthouse here in this world
		_beam.visible = false
		print("[lighthouse] not built in this world (the site was already built on)")


var _near_lighthouse := false

func _tick_lighthouse_interaction() -> void:
	_near_lighthouse = false
	if _beam == null or player == null or not is_instance_valid(_beam):
		return
	var lp: Variant = world.gen.starter.get("lighthouse") if (world != null and world.gen != null) else null
	if not (lp is Vector3i):
		return
	var lantern_m := (Vector3(lp as Vector3i) + Vector3(0.5, 0.5, 0.5)) * VS
	var d_xz := Vector2(player.position.x - lantern_m.x, player.position.z - lantern_m.z).length()
	var d_y := absf(player.position.y - lantern_m.y)
	if d_xz <= 5.5 and d_y <= 16.0:
		_near_lighthouse = true
		if hud != null and player.hovered_entity == null:
			hud.set_prompt("F  Refill Lighthouse Oil (Fuel: %.1fh remaining)" % _beam.fuel_hours_left())


func _tick_atlas(delta: float) -> void:
	_tick_lighthouse()
	_tick_lighthouse_interaction()
	if world == null or world.gen == null:
		return
	if _atlas_gen != world.gen:
		_atlas_gen = world.gen
		var n: ArchipelagoGen = world.gen.native
		atlas.setup(world.gen.islands, seed_value, n.column_height, n.column_island, VoxelWorld.SEA_MID)
	hud.chart_islands = atlas.chart_labels() + (npc_villages.chart_labels() if npc_villages != null else []) \
			+ (creatures.camps.chart_labels() if creatures != null and creatures.camps != null else []) \
			+ (creatures.outposts.chart_labels() if creatures != null and creatures.outposts != null else []) \
			+ (creatures.hulk.chart_labels() if creatures != null and creatures.hulk != null else [])
	_atlas_t -= delta
	if _atlas_t > 0.0 or player.is_seated():
		return
	# Wait for this character's saved discoveries before announcing anything.
	if session != null and session._pending_profile != null:
		return
	_atlas_t = 0.4
	var ev := atlas.update(player.position)
	if ev.is_empty():
		return
	print("[atlas] landfall on %s (%s)%s" % [ev.name, ev.style, ", new" if ev.new else ""])
	if ev.new:
		hud.show_banner(ev.name, "New island discovered  ·  %s  ·  %d of %d charted" % [ev.style, atlas.discovered_count(), atlas.islands.size()])
	else:
		hud.show_banner(ev.name, ev.style)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	_tick_pad_view()
	if player == null:
		# 3D Animated Cinematic Menu Backdrop: slow orbit over waves and island
		if rig != null and rig.cam != null:
			_menu_cam_orbit += delta * 0.04
			var spawn_m: Vector3 = world.gen.spawn * VS if (world != null and world.gen != null) else Vector3(500, 9, 500)
			var center := Vector3(spawn_m.x, 9.0, spawn_m.z)
			var cam_pos := center + Vector3(cos(_menu_cam_orbit) * 22.0, 4.0 + sin(_menu_cam_orbit * 0.7) * 1.5, sin(_menu_cam_orbit) * 22.0)
			rig.cam.global_position = cam_pos
			rig.cam.look_at(center - Vector3(0, 1.0, 0))
			if world != null:
				world.focus_points = [center]
		return
	player.water_level = sky.water_level_m()
	if farm != null:
		farm.tick_all(delta, sky.water_level_vox, sky.is_day(), sky.is_raining())  # [weather] rain waters crops
	if village != null:
		village.tick_settlement(delta, sky.time_of_day)
	# Terrain streams around the player (or the free camera in scripted shots).
	world.focus_points = [player.position if rig.target != null else rig.cam.global_position]
	var host_like := not is_net or multiplayer.is_server()
	sky.time_scale = 40.0 if (host_like and Input.is_action_pressed("fast_time")) else 1.0
	var cam_under := world != null and world.is_water_at(rig.cam.global_position, sky.water_level_m() - 0.03)
	hud.update_hud(player, sky, _peers_text(), world, cam_under)
	_tick_atlas(delta)
	if build_menu_ui != null:
		build_menu_ui.update_for_player(player)
	if is_net and multiplayer.multiplayer_peer != null:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 0.05
			var flags := (1 if player.on_ground else 0) | (2 if player.swimming else 0)
			player_state.rpc(player.position, player.facing, player.horizontal_speed, flags, player.tool, player.swing_count)
		if multiplayer.is_server():
			_time_sync_t -= delta
			if _time_sync_t <= 0.0:
				_time_sync_t = 1.0
				time_sync.rpc(sky.time_of_day)


func _peers_text() -> String:
	if not is_net:
		return "Solo"
	var n := remotes.size() + 1
	return "%s  -  %d player%s" % ["Hosting co-op" if multiplayer.is_server() else "Co-op", n, "" if n == 1 else "s"]


## Pad View / Select (or the DualSense touchpad): tap = inventory, hold = quest log.
const PAD_HOLD_MS := 450
var _pad_view_down_ms := -1
var _pad_view_held := false


func _toggle_quest_log() -> void:
	if quest_log_ui != null and quest_log_ui.is_open():
		quest_log_ui.close()
	else:
		switch_page(&"quests")


func _toggle_inventory() -> void:
	if inventory_ui.is_open():
		inventory_ui.close()
	else:
		switch_page(&"pack")


func _toggle_crafting() -> void:
	if crafting_ui != null and crafting_ui.is_open():
		crafting_ui.close()
	else:
		switch_page(&"crafting")


## The journal pages (Pack / Crafting / Quests) share one slot on screen:
## opening one closes the others. Used by the hotkeys and the page tabs.
func switch_page(page: StringName) -> void:
	if build_menu_ui != null and build_menu_ui.is_expanded():
		build_menu_ui.close_catalogue()
	if page != &"quests" and quest_log_ui != null and quest_log_ui.is_open():
		quest_log_ui.close()
	if page != &"pack" and inventory_ui != null and inventory_ui.is_open():
		inventory_ui.close()
	if page != &"crafting" and crafting_ui != null and crafting_ui.is_open():
		crafting_ui.close()
	match page:
		&"pack":
			if not inventory_ui.is_open():
				inventory_ui.open()
		&"crafting":
			if crafting_ui != null and not crafting_ui.is_open():
				crafting_ui.open()
		&"quests":
			if quest_log_ui != null and not quest_log_ui.is_open():
				quest_log_ui.open()


func _tick_pad_view() -> void:
	if _pad_view_down_ms >= 0 and not _pad_view_held and Time.get_ticks_msec() - _pad_view_down_ms >= PAD_HOLD_MS:
		_pad_view_held = true
		if player != null and not settings_menu.is_open():
			_toggle_quest_log()


func _unhandled_input(e: InputEvent) -> void:
	if controller != null:
		controller.track_input_event(e)
	if _near_lighthouse and e.is_action_pressed("interact") and player != null and player.hovered_entity == null:
		var inv: Inventory = player.inventory
		if inv != null and inv.has_item(&"fish_oil", 1):
			inv.remove_item(&"fish_oil", 1)
			_beam.add_fuel(720.0)
			hud.show_toast("Refilled lighthouse with fish oil! Lantern burns bright (+24h).")
			CombatAudio.play_sound("oil_refuel", _beam.global_position)
		elif inv != null:
			hud.show_toast("Requires Refined Fish Oil to refuel the lighthouse lantern!")
		get_viewport().set_input_as_handled()
		return
	if e is InputEventJoypadButton and (e.button_index == JOY_BUTTON_BACK or e.button_index == JOY_BUTTON_TOUCHPAD):
		if e.pressed:
			_pad_view_down_ms = Time.get_ticks_msec()
			_pad_view_held = false
		else:
			if _pad_view_down_ms >= 0 and not _pad_view_held and player != null and not settings_menu.is_open():
				if quest_log_ui != null and quest_log_ui.is_open():
					quest_log_ui.close()   # a tap closes whatever page is open
				elif build_menu_ui != null and build_menu_ui.is_expanded():
					build_menu_ui.close_catalogue()
				else:
					_toggle_inventory()
			_pad_view_down_ms = -1
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("quest_log_toggle") and player != null and not settings_menu.is_open():
		_toggle_quest_log()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("inventory_toggle") and player != null and not settings_menu.is_open():
		_toggle_inventory()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("crafting_toggle") and player != null and not settings_menu.is_open():
		_toggle_crafting()
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("menu_toggle"):
		if quest_log_ui != null and quest_log_ui.is_open():
			quest_log_ui.close()
			return
		if inventory_ui != null and inventory_ui.is_open():
			inventory_ui.close()
			return
		if crafting_ui != null and crafting_ui.is_open():
			crafting_ui.close()
			return
		if build_menu_ui != null and build_menu_ui.is_expanded():
			build_menu_ui.close_catalogue()
			return
		if trade != null and trade.ui != null and trade.ui.is_open():
			trade.ui.close()
			return
		if npc_villages != null and npc_villages.dialogue != null and npc_villages.dialogue.is_open():
			npc_villages.dialogue.close()
			return
		if tutorial != null and tutorial.dialogue != null and tutorial.dialogue.is_open():
			tutorial.dialogue.close()
			return
		settings_menu.toggle()
	elif e is InputEventMouseButton and e.pressed and player != null and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
			and not is_any_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func is_any_menu_open() -> bool:
	if settings_menu != null and settings_menu.is_open():
		return true
	if quest_log_ui != null and quest_log_ui.is_open():
		return true
	if inventory_ui != null and inventory_ui.is_open():
		return true
	if crafting_ui != null and crafting_ui.is_open():
		return true
	if build_menu_ui != null and build_menu_ui.is_expanded():
		return true
	if trade != null and trade.ui != null and trade.ui.is_open():
		return true
	if npc_villages != null and npc_villages.dialogue != null and npc_villages.dialogue.is_open():
		return true
	if tutorial != null and tutorial.dialogue != null and tutorial.dialogue.is_open():
		return true
	if village_mgr != null and village_mgr.orders_ui != null and village_mgr.orders_ui.is_open():
		return true
	return false


func _on_dug(pos: Vector3, mat: int, count: int) -> void:
	if controller != null:
		controller.pulse_dig()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = clampi(6 + count / 3, 6, 40)
	p.lifetime = 0.9
	p.explosiveness = 0.95
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * VS * 0.45
	var m := StandardMaterial3D.new()
	m.albedo_color = Palette.COLORS[mat]
	bm.material = m
	p.mesh = bm
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)

	if _cmd_is_mine and player != null and player.inventory != null:
		var item: ItemDef = ItemDB.get_by_voxel_mat(mat)
		if item:
			spawn_item_drop(pos, item.id, maxi(1, count / 4))
		if false:
			pass
		if mat == Palette.TRUNK:
			spawn_item_drop(pos, &"driftwood", maxi(1, count / 10))
		elif mat == Palette.LEAVES or mat == Palette.LEAVES_DARK:
			if count >= 4 or randf() < 0.45:
				spawn_item_drop(pos, &"pine_sapling", 1)
		elif VoxelWorld.is_stone_mat(mat):
			var tool_tier := 1
			var active_def := player.get_active_item_def()
			if active_def != null:
				tool_tier = int(active_def.tool_data.get("tier", 1))
			if mat == Palette.COPPER_VEIN:
				spawn_item_drop(pos, &"copper_ore", maxi(1, (count + 1) / 2))
			elif mat == Palette.CALAMINE:
				spawn_item_drop(pos, &"calamine_ore", maxi(1, (count + 1) / 2))
			elif mat == Palette.IRON_VEIN:
				if tool_tier >= 2:
					spawn_item_drop(pos, &"sea_iron_ore", maxi(1, (count + 1) / 2))
				elif hud != null:
					hud.show_toast("Brine-iron is too hard for this pick. You need a better one.")
			elif VoxelWorld.layout < 2:
				# Classic worlds have no ore veins: plain stone still turns up ore now and then.
				if count >= 6 or randf() < 0.45:
					spawn_item_drop(pos, &"copper_ore", 1)
				if tool_tier >= 2 and (count >= 10 or randf() < 0.35):
					spawn_item_drop(pos, &"sea_iron_ore", 1)
			else:
				# The big archipelago keeps its ore in the cave veins; stone only rarely has a nugget.
				if randf() < 0.08:
					spawn_item_drop(pos, &"copper_ore", 1)
				if tool_tier >= 2 and randf() < 0.05:
					spawn_item_drop(pos, &"sea_iron_ore", 1)


func spawn_item_drop(drop_pos: Vector3, item_id: StringName, drop_count: int) -> DroppedItem:
	if drop_count <= 0 or item_id == &"":
		return null
	var chunks := mini(drop_count, 3)
	var per_chunk := drop_count / chunks
	var remainder := drop_count % chunks
	var first_drop: DroppedItem = null
	for i in chunks:
		var c := per_chunk + (1 if i < remainder else 0)
		if c > 0:
			var d := DroppedItem.spawn_drop(self, world, player, drop_pos, item_id, c)
			if first_drop == null:
				first_drop = d
	return first_drop


func _on_tree_felled(base_pos: Vector3, height_m: float, canopy_radius_m: float, is_pine: bool, trunk_voxels: int) -> void:
	var is_mine := _cmd_is_mine
	# Better hatchets split more of the trunk into usable logs (read now: the tree lands later).
	var axe_tier := 1
	var held: ItemDef = player.get_active_item_def() if is_mine and player != null else null
	if held != null and held.has_tag("axe"):
		axe_tier = int(held.tool_data.get("tier", 1))
	var fall_dir := Vector3(1.0, 0.0, 0.0)
	if player != null:
		var away := Vector3(base_pos.x - player.global_position.x, 0.0, base_pos.z - player.global_position.z)
		if away.length_squared() > 0.01:
			fall_dir = away.normalized()

	var pivot := Node3D.new()
	pivot.name = "FallingTree"
	add_child(pivot)
	pivot.global_position = base_pos
	pivot.rotation.y = atan2(-fall_dir.x, -fall_dir.z)

	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Palette.COLORS[Palette.LEAVES_DARK if is_pine else Palette.LEAVES]
	leaf_mat.roughness = 0.88

	var has_custom_grid := (world != null and world.last_felled_grid != null)
	if has_custom_grid:
		var g: Prefabs.Grid = world.last_felled_grid
		world.last_felled_grid = null
		var tree_mesh: ArrayMesh = Mesher.mesh_from_grid(g.data, g.sx, g.sy, g.sz, VS, world.terrain_mat, world.glow_mat)
		var t_mi := MeshInstance3D.new()
		t_mi.mesh = tree_mesh
		t_mi.position = world.last_felled_grid_offset * VS
		pivot.add_child(t_mi)
	else:
		var trunk_w := 3.0 * VS
		var trunk_h := maxf(1.8, height_m * 0.72)
		var trunk_mi := MeshInstance3D.new()
		var trunk_bm := BoxMesh.new()
		trunk_bm.size = Vector3(trunk_w, trunk_h, trunk_w)
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = Palette.COLORS[Palette.TRUNK]
		trunk_mat.roughness = 0.9
		trunk_bm.material = trunk_mat
		trunk_mi.mesh = trunk_bm
		trunk_mi.position = Vector3(0.0, trunk_h * 0.5, 0.0)
		pivot.add_child(trunk_mi)

		if is_pine:
			for tier in 3:
				var tier_r := canopy_radius_m * (1.0 - float(tier) * 0.24)
				var tier_h := height_m * 0.24
				var tier_mi := MeshInstance3D.new()
				var tier_bm := BoxMesh.new()
				tier_bm.size = Vector3(tier_r * 1.65, tier_h, tier_r * 1.65)
				tier_bm.material = leaf_mat
				tier_mi.mesh = tier_bm
				tier_mi.position = Vector3(0.0, trunk_h * 0.45 + float(tier) * (tier_h * 0.82), 0.0)
				pivot.add_child(tier_mi)
		else:
			var crown_mi := MeshInstance3D.new()
			var crown_bm := BoxMesh.new()
			crown_bm.size = Vector3(canopy_radius_m * 1.85, canopy_radius_m * 1.35, canopy_radius_m * 1.85)
			crown_bm.material = leaf_mat
			crown_mi.mesh = crown_bm
			crown_mi.position = Vector3(0.0, trunk_h + canopy_radius_m * 0.35, 0.0)
			pivot.add_child(crown_mi)

	var tw := create_tween()
	tw.tween_property(pivot, "rotation:x", -1.48, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		if not is_instance_valid(pivot):
			return
		# Spawn leaf/bark burst particles along the fallen tree
		var burst := CPUParticles3D.new()
		burst.one_shot = true
		burst.emitting = false
		burst.amount = 28
		burst.lifetime = 1.0
		burst.explosiveness = 0.92
		var lbm := BoxMesh.new()
		lbm.size = Vector3.ONE * VS * 0.65
		lbm.material = leaf_mat
		burst.mesh = lbm
		burst.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		burst.emission_box_extents = Vector3(0.6, 0.3, height_m * 0.45)
		burst.direction = Vector3.UP
		burst.spread = 65.0
		burst.initial_velocity_min = 1.8
		burst.initial_velocity_max = 4.2
		burst.gravity = Vector3(0.0, -12.0, 0.0)
		add_child(burst)
		burst.global_position = base_pos + fall_dir * (height_m * 0.5) + Vector3(0.0, 0.4, 0.0)
		burst.emitting = true
		get_tree().create_timer(1.4).timeout.connect(burst.queue_free)

		# Drop logs spaced along the fallen trunk
		if is_mine and player != null:
			var log_total := clampi(trunk_voxels / 14, 2, 6) + (axe_tier - 1)
			for i in log_total:
				var d := 0.8 + float(i) * ((height_m * 0.75) / float(maxi(1, log_total)))
				var log_pos := base_pos + fall_dir * d + Vector3(0.0, 0.45, 0.0)
				DroppedItem.spawn_drop(self, world, player, log_pos, &"pine_wood", 1)
			DroppedItem.spawn_drop(self, world, player, base_pos + fall_dir * (height_m * 0.65) + Vector3(0.0, 0.55, 0.0), &"pine_sapling", 2)
		pivot.queue_free()
	)


# ---------------------------------------------------------------- commands / network

var _cmd_is_mine := false  # true while applying a command this player issued


func _apply_cmd(cmd: Dictionary) -> void:
	_cmd_is_mine = not is_net or int(cmd.get("by", -1)) == multiplayer.get_unique_id()
	world.apply_command(cmd)
	_cmd_is_mine = false
	if village_mgr != null:
		village_mgr.on_world_edit(cmd)   # homes re-check, villagers re-route


func _valid(cmd: Dictionary) -> bool:
	if not cmd.has("t") or not cmd.has("p") or not (cmd.p is Vector3i):
		return false
	match cmd.t:
		"dig": return cmd.get("r", 0) is int and cmd.r >= 0 and cmd.r <= 5
		"flatten": return cmd.get("r", 0) is int and cmd.r >= 0 and cmd.r <= 8
		"place": return cmd.get("r", 0) is int and cmd.r >= 0 and cmd.r <= 5 and Palette.BUILDABLE.has(cmd.get("m", -1))
		"prefab": return cmd.get("id", -1) is int and cmd.id >= 0 and cmd.id < Prefabs.count() and cmd.get("r", 0) is int
		"grow_tree": return true
	return false


func _on_command_requested(cmd: Dictionary) -> void:
	if not is_net:
		_apply_cmd(cmd)
	elif multiplayer.is_server():
		_host_apply(cmd)
	else:
		req_command.rpc_id(1, cmd)


func _host_apply(cmd: Dictionary) -> void:
	if not _valid(cmd):
		return
	# Tag who issued it so only that player collects the dig rewards.
	var sender := multiplayer.get_remote_sender_id()
	cmd["by"] = sender if sender != 0 else multiplayer.get_unique_id()
	do_command.rpc(cmd)


@rpc("any_peer", "call_remote", "reliable")
func req_command(cmd: Dictionary) -> void:
	if multiplayer.is_server():
		_host_apply(cmd)


@rpc("authority", "call_local", "reliable")
func do_command(cmd: Dictionary) -> void:
	if world.ready_for_play:
		_apply_cmd(cmd)
	else:
		_pending_cmds.append(cmd)


@rpc("authority", "call_remote", "reliable")
func welcome(p_seed: int, edits: Array, tod: float, assigned_spawn_idx: int = -1, p_layout: int = 1) -> void:
	seed_value = p_seed
	world_layout = p_layout
	sky.time_of_day = tod
	_assigned_spawn_idx = assigned_spawn_idx
	_pending_cmds = edits + _pending_cmds
	_begin_world()


@rpc("authority", "call_remote", "unreliable")
func time_sync(tod: float) -> void:
	if absf(sky.time_of_day - tod) > 0.001:
		sky.time_of_day = tod


@rpc("any_peer", "call_remote", "unreliable_ordered")
func player_state(pos: Vector3, yaw: float, speed: float, flags: int, tool: int, swings: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if remotes.has(id):
		(remotes[id] as RemotePlayer).apply_state(pos, yaw, speed, flags, tool, swings)


func _on_peer_connected(id: int) -> void:
	var rp := RemotePlayer.new()
	rp.setup(id)
	add_child(rp)
	remotes[id] = rp
	if multiplayer.is_server():
		# New crew wash up together on the homestead beach (spread out in _begin_world).
		var spawn_idx := 0
		welcome.rpc_id(id, seed_value, [], sky.time_of_day, spawn_idx, VoxelWorld.layout)
		if hud != null and player != null:
			hud.show_toast("A friend has washed ashore by the old hut.")


func _on_peer_disconnected(id: int) -> void:
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)
		hud.show_toast("Player %d sailed away" % id)


func _on_connected() -> void:
	hud.show_menu(true, "Connected! Waiting for the host's world...")


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	is_net = false
	hud.show_menu(true, "Could not reach the host.")


func _on_server_disconnected() -> void:
	hud.show_toast("Host disconnected - you're on your own now")
	multiplayer.multiplayer_peer = null
	is_net = false
	for id in remotes:
		remotes[id].queue_free()
	remotes.clear()


# ---------------------------------------------------------------- automated screenshots (dev)

func _shot(dir: String, name: String) -> void:
	for i in 2:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("[shot] ", name, "  fps=", Engine.get_frames_per_second())


func _run_screenshots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	player.input_enabled = false
	hud.help.visible = true
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "01_spawn")
	hud.help.visible = false
	player.vitality.eat_food(&"samphire_bouillabaisse")
	player.vitality.eat_food(&"smoked_fish_ration")
	player.inventory.add_item(&"hydrographic_sea_chart", 1)
	player.inventory.equip_item_from_slot(0)
	rig.yaw = 0.0
	rig.pitch = -0.30
	rig.dist = 9.0
	for i in 6:
		await get_tree().process_frame
	await _shot(dir, "02_toward_hut")
	rig.dist = 16.0
	rig.pitch = -0.6
	rig.yaw = 0.8
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "03_overview")
	# Low tide, then high tide.
	sky.time_of_day = 0.30 + 0.25 / 2.0 * 0.0
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "04_morning_tide")
	sky.time_of_day = 0.76
	rig.yaw = PI
	rig.dist = 10.0
	rig.pitch = -0.25
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "05_dusk")
	sky.time_of_day = 0.9
	rig.yaw = 0.0
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "06_night_lamps")
	# Building: dig a hole and drop a prefab in front of the player.
	sky.time_of_day = 0.45
	rig.yaw = world.gen.spawn_yaw + 1.3
	rig.pitch = -0.45
	rig.dist = 6.0
	player.tool = 2
	player.prefab_id = 5
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "07_prefab_ghost")
	if not player.target.is_empty():
		_on_command_requested({"t": "prefab", "p": player.prefab_origin(), "r": 0, "id": 5})
	player.tool = 0
	player.brush = 3
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "08_prefab_placed")
	if not player.target.is_empty():
		var tc: Vector3i = player.target.cell
		for k in 4:
			_on_command_requested({"t": "dig", "p": tc - Vector3i(0, k * 2, 0), "r": 3})
			for i in 2:
				await get_tree().process_frame
	await _shot(dir, "09_dig")
	# Close-up of the character.
	rig.dist = 2.4
	rig.pitch = -0.15
	rig.yaw = player.facing + 0.6
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "10_character")
	# Horizon: from the player toward the nearest other island.
	sky.time_of_day = 0.42
	var home_c: Vector2 = world.gen.islands[0].center
	var near_isl: Vector2 = world.gen.islands[1].center
	var best_d := INF
	for isl: Dictionary in world.gen.islands.slice(1):
		var dd: float = (isl.center as Vector2).distance_to(Vector2(world.gen.spawn.x, world.gen.spawn.z))
		if dd < best_d:
			best_d = dd
			near_isl = isl.center
	var to := (near_isl - home_c).normalized()
	# Stand on the home island's shore that faces that island.
	var shore := home_c
	for step_i in range(0, 1400, 4):
		var q := home_c + to * step_i
		if world.gen.col_h(int(q.x), int(q.y)) > world.gen.sea_high:
			shore = q
		elif step_i > 200:
			break  # first open water past the home island's coast
	var shore_y := world.gen.col_h(int(shore.x), int(shore.y)) + 12
	rig.target = null
	hud.show_hud(false)
	rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.04, atan2(-to.x, -to.y), 0)),
			Vector3(shore.x, shore_y, shore.y) * VS + Vector3(to.x, 0, to.y) * 2.0)
	for i in 40:
		await get_tree().process_frame
	await _shot(dir, "11a_horizon")
	# Aerial views of the archipelago (streaming follows the free camera).
	rig.target = null
	hud.show_hud(false)
	var mid := Vector3(VoxelWorld.WX, 0, VoxelWorld.WZ) * VS * 0.5
	rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.75, 0.0, 0)), mid + Vector3(0, 420, 560))
	for i in 12:
		await get_tree().process_frame
	await _shot(dir, "11_aerial")
	rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.5, 0.0, 0)), Vector3(home_c.x, 0, home_c.y) * VS + Vector3(0, 90, 260))
	for i in 12:
		await get_tree().process_frame
	await _shot(dir, "11b_home_island")
	var sp := Vector3(world.gen.spawn)
	rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.6, 0.0, 0)), sp * VS + Vector3(0, 20, 26))
	for i in 4:
		await get_tree().process_frame
	await _shot(dir, "12_starter_area")
	# Prefab gallery on a flattened pad out over the sea.
	var g0 := Vector3i(40, 40, 30)
	for x in range(g0.x - 4, g0.x + 300):
		for z in range(g0.z - 16, g0.z + 16):
			for y in range(1, 80):
				world.set_voxel(x, y, z, Palette.GRASS if y == g0.y - 1 else (Palette.DIRT if y < g0.y - 1 else 0))
	var gx := g0.x + 10
	for id in Prefabs.count():
		var pf := Prefabs.rotated(id, 0)
		var sz: Vector3i = pf.size
		world.apply_prefab(id, Vector3i(gx + pf.anchor.x, g0.y + (pf.anchor.y as int), g0.z), 0, true)
		gx += sz.x + 6
	for i in 6:
		await get_tree().process_frame
	sky.time_of_day = 0.45
	for part in 3:
		var cx := (g0.x + 10 + part * 95 + 45) * VS
		rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.35, 0.0, 0)), Vector3(cx, (g0.y + 30) * VS, (g0.z - 75) * VS))
		rig.cam.rotation = Vector3(-0.35, PI, 0)
		for i in 3:
			await get_tree().process_frame
		await _shot(dir, "13_gallery_%d" % part)
	print("[shot] done, vertices=", world.stats_vertices)
	get_tree().quit()


func _run_bench() -> void:
	player.input_enabled = false
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	print("[bench] window ", get_window().size, " render scale %.2f" % get_viewport().scaling_3d_scale, "  viewport ", get_viewport().get_visible_rect().size, "  near verts ", world.stats_vertices, "  lod verts ", world.stats_lod_vertices)
	for i in 16:  # let pipelines finish compiling
		await RenderingServer.frame_post_draw
	var modes := ["full", "no_msaa", "no_shadows", "no_water", "no_lod", "no_terrain"]
	if _args.get("bench", "") == "detail":
		# Isolated costs (each mode toggles one thing, then restores it).
		modes = ["full", "no_fade", "no_lamps", "no_glow", "no_fog", "no_fxaa", "scale_0.75", "full"]
	for mode in modes:
		match mode:
			"full":
				settings.apply(self)
			"no_fade": world.terrain_mat.set_shader_parameter("fade_enabled", false); rig.foliage_fade = false
			"no_lamps":
				settings.apply(self)
				for l in get_tree().get_nodes_in_group("lamps"):
					l.visible = false
			"no_glow":
				for l in get_tree().get_nodes_in_group("lamps"):
					l.visible = true
				sky.glow_mode = 0
			"no_fog":
				sky.glow_mode = settings.glow
				sky.env.fog_enabled = false
			"no_fxaa":
				sky.env.fog_enabled = true
				get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
			"scale_0.75":
				settings.apply(self)
				get_viewport().scaling_3d_scale = 0.75
			"no_msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED
			"no_lod":
				for n in world._lod_nodes.values():
					n.visible = false
			"no_shadows": sky.sun.shadow_enabled = false
			"no_water": sky.water.visible = false
			"no_terrain":
				for n in world.nodes.values():
					if n != null: n.visible = false
		# Draw back-to-back so the (otherwise 1 fps, hidden-window) GPU stays clocked up.
		await RenderingServer.frame_post_draw
		var gpus := []
		var cpu := 0.0
		for f in 40:
			RenderingServer.force_draw(false)
			if f >= 10:
				gpus.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		gpus.sort()
		print("[bench] %s: gpu median %.2f ms (min %.2f, max %.2f), render-cpu %.2f ms" % [mode, gpus[15], gpus[0], gpus[29], cpu / 30.0])
	get_tree().quit()


func _region_checksum(c: Vector3i, r: int) -> int:
	var h := 17
	for y in range(c.y - r, c.y + r):
		for z in range(c.z - r, c.z + r):
			for x in range(c.x - r, c.x + r):
				h = (h * 31 + world.get_voxel(x, y, z)) % 1000000007
	return h


func _run_netcheck() -> void:
	player.input_enabled = false
	var c := Vector3i(world.gen.spawn) + Vector3i(0, 0, 8)
	var role := "host" if multiplayer.is_server() else "client"
	var before := _region_checksum(c, 14)
	if role == "client":
		await get_tree().create_timer(2.0).timeout
		_on_command_requested({"t": "prefab", "p": c, "r": 1, "id": 7})
		_on_command_requested({"t": "dig", "p": c + Vector3i(5, -1, 0), "r": 3})
		_on_command_requested({"t": "place", "p": c + Vector3i(-5, 2, 3), "r": 2, "m": Palette.ROOF_BLUE})
	await get_tree().create_timer(6.0 if role == "client" else 12.0).timeout
	print("[net] %s peers=%s remotes=%d edits_logged=%d checksum before=%d after=%d" % [
		role, multiplayer.get_peers(), remotes.size(), edit_log.size(), before, _region_checksum(c, 14)])
	if role == "client":
		var rp: RemotePlayer = remotes.get(1)
		print("[net] client sees host avatar at ", rp.position if rp else "none")
	get_tree().quit()
