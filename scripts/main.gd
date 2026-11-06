extends Node3D
## Brine's Hollow prototype entry point.
## Co-op model: host-authoritative. Everyone generates the same world from the seed;
## edits are small commands relayed by the host (plus a log replayed for late joiners).
##
## Command line (after `--`):  --solo | --host | --join=IP   [--seed=N] [--time=0.5] [--shot=DIR]

const PORT := 24565
const VS := VoxelWorld.VS

var seed_value := 1106
var sky: SkyCycle
var world: VoxelWorld
var player: Player
var rig: CameraRig
var hud: Hud
var boats: BoatManager

var is_net := false
var edit_log: Array = []
var remotes := {}
var _pending_cmds: Array = []
var _send_t := 0.0
var _time_sync_t := 0.0
var _started := false
var _args := {}


func _ready() -> void:
	_setup_input()
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if _args.has("seed"):
		seed_value = int(_args.seed)

	sky = SkyCycle.new()
	add_child(sky)
	if _args.has("time"):
		sky.time_of_day = float(_args.time)
	world = VoxelWorld.new()
	if _args.has("radius"):
		world.mesh_radius = int(_args.radius)  # full-detail radius in chunk columns (Deck: 7)
	if _args.has("deck"):
		# Steam Deck preset (until the settings menu exists): smaller full-detail radius,
		# no MSAA, shorter single-split shadows.
		world.mesh_radius = 7
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		sky.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		sky.sun.directional_shadow_max_distance = 30.0
	add_child(world)
	world.loading_progress.connect(func(t: String, f: float) -> void: hud.set_loading(true, t, f))
	world.dug.connect(_on_dug)

	rig = CameraRig.new()
	add_child(rig)
	rig.world = world
	rig.cam.far = 1500.0  # archipelago: distant islands stay visible through the fog
	# Menu backdrop: look out over the sea.
	rig.cam.global_transform = Transform3D(Basis.from_euler(Vector3(-0.08, 0.6, 0)),
			Vector3(VoxelWorld.WX * VS * 0.5, 9, VoxelWorld.WZ * VS + 25))

	hud = Hud.new()
	add_child(hud)
	hud.solo_pressed.connect(start_solo)
	hud.host_pressed.connect(start_host)
	hud.join_pressed.connect(start_join)

	# Rowboats (spawning, boarding, co-op sync). Must exist on every peer before RPCs arrive.
	boats = BoatManager.new()
	boats.name = "Boats"
	boats.main = self
	add_child(boats)

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if _args.has("host"):
		start_host()
	elif _args.has("join"):
		start_join(_args.join if _args.join != "" else "127.0.0.1")
	elif _args.has("solo") or _args.has("shot") or _args.has("bench") or _args.has("boatcheck"):
		start_solo()
	else:
		hud.show_menu(true)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT],
		"tool_1": [KEY_1], "tool_2": [KEY_2], "tool_3": [KEY_3],
		"prev_item": [KEY_Q], "next_item": [KEY_E],
		"brush_down": [KEY_Z], "brush_up": [KEY_X],
		"rotate": [KEY_R], "snap": [KEY_G], "fast_time": [KEY_T], "swap_shoulder": [KEY_V],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for pair in [["use", MOUSE_BUTTON_LEFT], ["pick", MOUSE_BUTTON_MIDDLE]]:
		if not InputMap.has_action(pair[0]):
			InputMap.add_action(pair[0])
		var mb := InputEventMouseButton.new()
		mb.button_index = pair[1]
		InputMap.action_add_event(pair[0], mb)


# ---------------------------------------------------------------- session start

func start_solo() -> void:
	is_net = false
	_begin_world()


func start_host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 8)
	if err != OK:
		hud.show_menu(true, "Could not host on port %d (error %d)." % [PORT, err])
		return
	multiplayer.multiplayer_peer = peer
	is_net = true
	_begin_world()


func start_join(ip: String) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		hud.show_menu(true, "Could not start client (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer
	is_net = true
	hud.show_menu(true, "Connecting to %s..." % ip)


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
				while y > 0 and world.get_voxel(x, y, z) == 0:
					y -= 1
				if ground.has(world.get_voxel(x, y, z)) and y + 1 > VoxelWorld.SEA_MID + VoxelWorld.TIDE_AMP:
					return Vector3(x + 0.5, y + 1, z + 0.5)
	return Vector3(sp) + Vector3(0.5, 0, 0.5)


func _begin_world() -> void:
	if _started:
		return
	_started = true
	hud.show_menu(false)
	hud.set_loading(true, "Starting...", 0.0)
	await world.generate(seed_value)
	for cmd in _pending_cmds:
		world.apply_command(cmd)
	_pending_cmds.clear()

	player = Player.new()
	player.world = world
	player.rig = rig
	add_child(player)
	player.position = _find_clear_spawn(Vector3i(world.gen.spawn)) * VS
	player.command_requested.connect(_on_command_requested)
	rig.target = player
	# Start looking back at the starter hut, sea behind the camera.
	rig.yaw = world.gen.spawn_yaw
	hud.set_loading(false)
	hud.show_hud(true)
	hud.show_toast("Welcome to Brine's Hollow")
	if _args.has("boatcheck"):
		boats.run_check(_args.boatcheck)
	elif _args.has("netcheck"):
		_run_netcheck()
	elif _args.has("bench"):
		_run_bench()
	elif not _args.has("shot"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_run_screenshots(_args.shot)


# ---------------------------------------------------------------- per frame

func _process(delta: float) -> void:
	if player == null:
		return
	player.water_level = sky.water_level_m()
	# Terrain streams around the player (or the free camera in scripted shots).
	world.focus_points = [player.position if rig.target != null else rig.cam.global_position]
	var host_like := not is_net or multiplayer.is_server()
	sky.time_scale = 40.0 if (host_like and Input.is_action_pressed("fast_time")) else 1.0
	var cam_under := rig.cam.global_position.y < sky.water_level_m() - 0.03
	hud.update_hud(player, sky, _peers_text(), world, cam_under)
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


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseButton and e.pressed and player != null and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()


func _on_dug(pos: Vector3, mat: int, count: int) -> void:
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


# ---------------------------------------------------------------- commands / network

func _valid(cmd: Dictionary) -> bool:
	if not cmd.has("t") or not cmd.has("p") or not (cmd.p is Vector3i):
		return false
	match cmd.t:
		"dig": return cmd.get("r", 0) is int and cmd.r >= 0 and cmd.r <= 5
		"place": return cmd.get("r", 0) is int and cmd.r >= 0 and cmd.r <= 5 and Palette.BUILDABLE.has(cmd.get("m", -1))
		"prefab": return cmd.get("id", -1) is int and cmd.id >= 0 and cmd.id < Prefabs.count() and cmd.get("r", 0) is int
	return false


func _on_command_requested(cmd: Dictionary) -> void:
	if not is_net:
		world.apply_command(cmd)
	elif multiplayer.is_server():
		_host_apply(cmd)
	else:
		req_command.rpc_id(1, cmd)


func _host_apply(cmd: Dictionary) -> void:
	if not _valid(cmd):
		return
	edit_log.append(cmd)
	do_command.rpc(cmd)


@rpc("any_peer", "call_remote", "reliable")
func req_command(cmd: Dictionary) -> void:
	if multiplayer.is_server():
		_host_apply(cmd)


@rpc("authority", "call_local", "reliable")
func do_command(cmd: Dictionary) -> void:
	if world.ready_for_play:
		world.apply_command(cmd)
	else:
		_pending_cmds.append(cmd)


@rpc("authority", "call_remote", "reliable")
func welcome(p_seed: int, edits: Array, tod: float) -> void:
	seed_value = p_seed
	sky.time_of_day = tod
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
		welcome.rpc_id(id, seed_value, edit_log, sky.time_of_day)
		if hud != null and player != null:
			hud.show_toast("A friend washed ashore (player %d)" % id)


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
	rig.yaw = 0.0
	rig.pitch = -0.30
	rig.dist = 9.0
	for i in 4:
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
	print("[bench] viewport ", get_viewport().get_visible_rect().size, "  near verts ", world.stats_vertices, "  lod verts ", world.stats_lod_vertices)
	for i in 16:  # let pipelines finish compiling
		await RenderingServer.frame_post_draw
	var modes := ["full", "no_msaa", "no_shadows", "no_water", "no_lod", "no_terrain"]
	for mode in modes:
		match mode:
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
