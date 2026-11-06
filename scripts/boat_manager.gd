class_name BoatManager
extends Node
## Owns every Boat: spawning, boarding (F), co-op sync, HUD prompts, dev checks.
## Lives at /root/Main/Boats on every peer so its RPCs line up.
##
## Authority: the host spawns boats and assigns seats. Each boat is simulated by its
## rower (seat 0) or, when nobody rows, by the host; that peer streams snapshots and
## everyone else interpolates. Receivers ignore snapshots from anyone else.

const SEND_RATE := 15.0
const BOARD_RANGE := 2.8

var main: Node
var boats := {}                 # id -> Boat
var _spawned := false
var _next_id := 1
var _send_t := 0.0
var _pending_exit: Variant = null

# Scripted input for dev checks: x = row, y = turn (+left), z = hard (0/1)
var debug_active := false
var debug_input := Vector3.ZERO


func _ready() -> void:
	if not InputMap.has_action("interact"):
		InputMap.add_action("interact")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event("interact", ev)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


var _last_net_id := 0


## Host left: we continue solo. Keep our own seat (as local id 1), drop everyone else,
## and don't spawn a second fleet.
func _on_server_disconnected() -> void:
	for b: Boat in boats.values():
		for i in b.occupants.size():
			b.occupants[i] = 1 if (b.occupants[i] == _last_net_id and _last_net_id != 0) else 0
		b._has_net = false
	_spawned = true
	_refresh_links()


func _is_host() -> bool:
	return not main.is_net or multiplayer.is_server()


func _local_id() -> int:
	return multiplayer.get_unique_id() if main.is_net and multiplayer.multiplayer_peer != null else 1


func _world_ready() -> bool:
	return main.world != null and main.world.ready_for_play


# ---------------------------------------------------------------- spawning

func _spawn_initial() -> void:
	_spawned = true
	var spots: Array = []
	var gen = main.world.gen
	if gen != null and "boat_spawns" in gen and gen.boat_spawns is Array and not gen.boat_spawns.is_empty():
		spots = gen.boat_spawns
	else:
		var s = _find_water_spawn()
		if s != null:
			spots = [s]
	for sp: Dictionary in spots:
		var bid := _next_id
		_next_id += 1
		_create(bid, sp.pos, sp.yaw)
		if main.is_net:
			spawn_boat.rpc(bid, sp.pos, sp.yaw)
	print("[boat] spawned %d boat(s)" % spots.size())


## Fallback until the world provides boat_spawns: nearest open water to the player spawn
## that stays > 0.6 m deep at low tide, bow pointing out to sea.
func _find_water_spawn() -> Variant:
	var w: VoxelWorld = main.world
	var vs := VoxelWorld.VS
	var low := (VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP) * vs
	var origin: Vector3 = w.gen.spawn * vs if w.gen != null else Vector3.ZERO
	for r in range(4, 120, 1):
		var steps := maxi(12, r * 2)
		for k in steps:
			var a := TAU * k / steps
			var p := origin + Vector3(cos(a), 0, sin(a)) * r
			if _deep_enough(p, low, vs) and _deep_enough(p + Vector3(1.8, 0, 0), low, vs) \
					and _deep_enough(p - Vector3(1.8, 0, 0), low, vs) and _deep_enough(p + Vector3(0, 0, 1.8), low, vs) \
					and _deep_enough(p - Vector3(0, 0, 1.8), low, vs):
				var away := Vector2(p.x - origin.x, p.z - origin.z)
				return {"pos": Vector3(p.x, main.sky.water_level_m(), p.z), "yaw": atan2(away.x, away.y)}
	return null


func _deep_enough(p: Vector3, low: float, vs: float) -> bool:
	var x := floori(p.x / vs)
	var z := floori(p.z / vs)
	for vy in range(floori((low - 0.65) / vs), floori((low + 1.6) / vs) + 1):
		var m: int = main.world.get_voxel(x, vy, z)
		if m != 0 and not Palette.is_foliage(m):
			return false
	return true


func _create(bid: int, pos: Vector3, yaw: float) -> Boat:
	if boats.has(bid):
		return boats[bid]
	var b := Boat.new()
	b.name = "Boat%d" % bid
	add_child(b)
	b.setup(bid, main.world, main.sky, pos, yaw)
	boats[bid] = b
	_next_id = maxi(_next_id, bid + 1)
	return b


@rpc("authority", "call_remote", "reliable")
func spawn_boat(bid: int, pos: Vector3, yaw: float) -> void:
	_create(bid, pos, yaw)


@rpc("authority", "call_remote", "reliable")
func sync_all(data: Array) -> void:
	for d: Array in data:
		var b := _create(d[0], d[1], d[2])
		b.occupants = (d[3] as Array).duplicate()
	_refresh_links()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var data := []
	for b: Boat in boats.values():
		data.append([b.id, b.position, b.yaw, b.occupants])
	sync_all.rpc_id(id, data)


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	for b: Boat in boats.values():
		var s := b.seat_of(id)
		if s >= 0:
			var occ: Array = b.occupants.duplicate()
			occ[s] = 0
			set_seats.rpc(b.id, occ)


# ---------------------------------------------------------------- seats

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("interact") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		interact()


## F: board the nearest boat, or step off the current one.
func interact() -> void:
	var p: Player = main.player
	if p == null or not _world_ready():
		return
	if p.is_seated():
		var spot = p.boat.find_exit_spot()
		if spot == null:
			main.hud.show_toast("Row closer to land or a dock to step off")
			return
		_pending_exit = spot
		if _is_host():
			_host_leave(_local_id(), p.boat.id)
		else:
			request_leave.rpc_id(1, p.boat.id)
		return
	var b := nearest_boardable(p.position)
	if b == null:
		return
	if _is_host():
		_host_seat(_local_id(), b.id, b.free_seat())
	else:
		request_seat.rpc_id(1, b.id, b.free_seat())


func nearest_boardable(pos: Vector3) -> Boat:
	var best: Boat = null
	var best_d := BOARD_RANGE
	for b: Boat in boats.values():
		if b.free_seat() < 0:
			continue
		var d := Vector2(pos.x - b.position.x, pos.z - b.position.z).length()
		if d < best_d and absf(pos.y - b.position.y) < 2.5:
			best = b
			best_d = d
	return best


@rpc("any_peer", "call_remote", "reliable")
func request_seat(bid: int, seat: int) -> void:
	if multiplayer.is_server():
		_host_seat(multiplayer.get_remote_sender_id(), bid, seat)


@rpc("any_peer", "call_remote", "reliable")
func request_leave(bid: int) -> void:
	if multiplayer.is_server():
		_host_leave(multiplayer.get_remote_sender_id(), bid)


func _host_seat(peer: int, bid: int, seat: int) -> void:
	var b: Boat = boats.get(bid)
	if b == null or seat < 0 or seat >= b.occupants.size() or b.occupants[seat] != 0:
		return
	for other: Boat in boats.values():
		if other.seat_of(peer) >= 0:
			return  # already seated somewhere
	# Range check against where the host last saw that player.
	var who: Node3D = main.player if peer == _local_id() else main.remotes.get(peer)
	if who != null and who.position.distance_to(b.position) > BOARD_RANGE + 3.0:
		return
	var occ: Array = b.occupants.duplicate()
	occ[seat] = peer
	_broadcast_seats(bid, occ)


func _host_leave(peer: int, bid: int) -> void:
	var b: Boat = boats.get(bid)
	if b == null:
		return
	var s := b.seat_of(peer)
	if s < 0:
		return
	var occ: Array = b.occupants.duplicate()
	occ[s] = 0
	_broadcast_seats(bid, occ)


func _broadcast_seats(bid: int, occ: Array) -> void:
	if main.is_net:
		set_seats.rpc(bid, occ)
	else:
		set_seats(bid, occ)


@rpc("authority", "call_local", "reliable")
func set_seats(bid: int, occ: Array) -> void:
	var b: Boat = boats.get(bid)
	if b == null:
		return
	b.occupants = occ.duplicate()
	_refresh_links()


## Bring the local player and remote avatars in line with seat assignments.
func _refresh_links() -> void:
	var me := _local_id()
	var p: Player = main.player
	if p != null:
		var mine: Boat = null
		var my_seat := -1
		for b: Boat in boats.values():
			if b.seat_of(me) >= 0:
				mine = b
				my_seat = b.seat_of(me)
		if mine != null and (p.boat != mine or p.seat != my_seat):
			p.board(mine, my_seat)
		elif mine == null and p.is_seated():
			var b0: Boat = p.boat
			var spot: Vector3 = _pending_exit if _pending_exit != null else b0.position + Vector3(0, 0.3, 0)
			p.unboard(spot)
			_pending_exit = null
	for id in main.remotes:
		var rp: RemotePlayer = main.remotes[id]
		rp.seat_boat = null
		for b: Boat in boats.values():
			var s := b.seat_of(id)
			if s >= 0:
				rp.seat_boat = b
				rp.seat_index = s


# ---------------------------------------------------------------- simulation + sync

func _physics_process(delta: float) -> void:
	if not _world_ready():
		return
	if not _spawned and _is_host():
		_spawn_initial()
	var me := _local_id()
	if main.is_net:
		_last_net_id = me
	var p: Player = main.player
	for b: Boat in boats.values():
		if b.authority() != me:
			b.interpolate(delta)
			continue
		var f := 0.0
		var t := 0.0
		var hard := false
		if p != null and p.boat == b and p.seat == 0:
			if debug_active:
				f = debug_input.x
				t = debug_input.y
				hard = debug_input.z > 0.5
			elif p.input_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				f = Input.get_axis("move_back", "move_forward")
				t = Input.get_axis("move_right", "move_left")
				hard = Input.is_action_pressed("sprint")
		b.simulate(delta, f, t, hard)
	if main.is_net and multiplayer.multiplayer_peer != null:
		_send_t -= delta
		if _send_t <= 0.0:
			_send_t = 1.0 / SEND_RATE
			for b: Boat in boats.values():
				if b.authority() == me:
					boat_state.rpc(b.id, b.position, b.yaw, b.vel, b.row_phase, b.row_power)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func boat_state(bid: int, pos: Vector3, yaw: float, vel: Vector2, phase: float, power: float) -> void:
	var b: Boat = boats.get(bid)
	if b == null or multiplayer.get_remote_sender_id() != b.authority():
		return
	b.apply_snapshot(pos, yaw, vel, phase, power)


func _process(_delta: float) -> void:
	if not _world_ready() or main.player == null:
		return
	var p: Player = main.player
	var prompt := ""
	if p.is_seated():
		prompt = "F  Step off      W/S  row    A/D  turn    Shift  pull hard" if p.seat == 0 else "F  Step off      (riding as passenger)"
	else:
		var b := nearest_boardable(p.position)
		if b != null:
			prompt = "F  Board rowboat" if b.free_seat() == 0 else "F  Ride along"
	main.hud.set_prompt(prompt)
	# Remote avatars may have been created after a seat change.
	for id in main.remotes:
		var rp: RemotePlayer = main.remotes[id]
		if rp.seat_boat == null:
			for b: Boat in boats.values():
				if b.seat_of(id) >= 0:
					_refresh_links()
					return


# ---------------------------------------------------------------- dev checks

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _stat(b: Boat, label: String) -> void:
	print("[boat] %-14s pos=(%.2f, %.2f, %.2f) yaw=%.2f speed=%.2f grounded=%s seats=%s" % [
		label, b.position.x, b.position.y, b.position.z, b.yaw, b.vel.length(), b.grounded, b.occupants])


## --boatcheck[=SHOT_DIR]: board, row, turn, run aground, step off. With --join it rows
## as a client; with --host it just reports what it sees.
func run_check(shot_dir: String) -> void:
	var p: Player = main.player
	p.input_enabled = false
	while boats.is_empty():
		await get_tree().process_frame
	var b: Boat = boats.values()[0]
	_stat(b, "spawn")
	if main.is_net and multiplayer.is_server():
		for i in 13:
			await _wait(2.0)
			_stat(b, "host sees t=%d" % ((i + 1) * 2))
		get_tree().quit()
		return
	if shot_dir != "":
		await _scale_shots(shot_dir, b)
	# Board.
	p.position = b.position + Vector3(1.2, 0.0, 0.0)
	await _wait(0.6)  # let the host see where we are before asking for a seat
	interact()
	await _wait(0.6)
	print("[boat] seated=", p.is_seated(), " seat=", p.seat)
	if not p.is_seated():
		print("[boat] FAIL could not board")
		get_tree().quit()
		return
	debug_active = true
	debug_input = Vector3(1, 0, 0)
	for i in 4:
		await _wait(1.0)
		_stat(b, "row %ds" % (i + 1))
	if shot_dir != "":
		await main._shot(shot_dir, "boat_rowing")
	debug_input = Vector3(0.5, 1.0, 0)
	await _wait(2.0)
	_stat(b, "turn left 2s")
	debug_input = Vector3(1, 0, 1)
	await _wait(2.0)
	_stat(b, "hard 2s")
	# Head for land and keep rowing: the boat must stop at the shore, not climb it.
	var land: Vector3 = main.world.gen.spawn * VoxelWorld.VS
	var to_land := Vector2(land.x - b.position.x, land.z - b.position.z)
	b.yaw = atan2(to_land.x, to_land.y)
	b.vel = Vector2.ZERO
	debug_input = Vector3(1, 0, 1)
	var last := b.position
	for i in 16:
		await _wait(1.0)
		if i % 4 == 3:
			_stat(b, "to land %ds" % (i + 1))
		if b.position.distance_to(last) < 0.05 and i > 2:
			break
		last = b.position
	_stat(b, "stopped")
	var ground_under: Dictionary = main.world.raycast(b.position + Vector3(0, 3, 0), Vector3.DOWN, 10.0)
	print("[boat] terrain under hull at y=%.2f, water=%.2f" % [
		(ground_under.cell.y + 1) * VoxelWorld.VS if not ground_under.is_empty() else -1.0, main.sky.water_level_m()])
	debug_input = Vector3.ZERO
	await _wait(0.5)
	if shot_dir != "":
		main.rig.yaw = b.yaw + PI + 0.7
		await _wait(0.5)
		await main._shot(shot_dir, "boat_at_shore")
	interact()
	await _wait(0.6)
	print("[boat] after step-off: seated=", p.is_seated(), " player=", p.position, " seats=", b.occupants)
	if main.is_net:
		await _wait(3.0)
	get_tree().quit()


## Visual scale check: character standing in a Door Wall and next to the boat.
func _scale_shots(dir: String, b: Boat) -> void:
	var p: Player = main.player
	var w: VoxelWorld = main.world
	var vs := VoxelWorld.VS
	var c := Vector3i((p.position / vs).floor())
	w.apply_prefab(2, c + Vector3i(0, 0, 1), 0, true)       # door wall just behind the player
	w.apply_prefab(7, c + Vector3i(9, 0, 3), 0, true)       # lamp post beside it
	p.facing = 0.0
	main.rig.yaw = 0.35
	main.rig.pitch = -0.12
	main.rig.dist = 4.5
	await _wait(1.0)
	await main._shot(dir, "scale_doorway")
	# Walk through the door: stand inside the opening.
	p.position = Vector3(c.x + 0.5, c.y, c.z + 1.5) * vs
	main.rig.yaw = 0.0
	await _wait(1.0)
	await main._shot(dir, "scale_in_door")
	# Next to the boat, seen from the side.
	p.position = b.position + Vector3(0, 0, 0)
	var spot = b.find_exit_spot()
	if spot != null:
		p.position = spot
	main.rig.yaw = b.yaw + PI * 0.5
	main.rig.pitch = -0.3
	main.rig.dist = 6.0
	await _wait(1.0)
	await main._shot(dir, "scale_boat")
