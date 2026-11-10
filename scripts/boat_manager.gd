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
	_spawn_saved()


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


func _create(bid: int, pos: Vector3, yaw: float, kind := Boat.KIND_ROWBOAT) -> Boat:
	if boats.has(bid):
		return boats[bid]
	var b := Boat.new()
	b.name = "Boat%d" % bid
	add_child(b)
	b.setup(bid, main.world, main.sky, pos, yaw, kind)
	boats[bid] = b
	_next_id = maxi(_next_id, bid + 1)
	return b


@rpc("authority", "call_remote", "reliable")
func spawn_boat(bid: int, pos: Vector3, yaw: float, kind := 0) -> void:
	_create(bid, pos, yaw, kind)


# ---------------------------------------------------------------- launching a skiff

## Open water beside the player, deep enough at low tide for the skiff's hull and float.
func launch_spot(p: Player) -> Variant:
	var vs := VoxelWorld.VS
	var low := (VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP) * vs
	var water: float = main.sky.water_level_m()
	if p.position.y > water + 2.5:
		return null
	for r in [3.0, 4.0, 5.0, 6.5]:
		for k in 16:
			var a := TAU * k / 16.0
			var c: Vector3 = p.position + Vector3(cos(a), 0, sin(a)) * float(r)
			var yaw := atan2(c.x - p.position.x, c.z - p.position.z)
			var f := Vector3(sin(yaw), 0, cos(yaw))
			var s := Vector3(cos(yaw), 0, -sin(yaw))
			var ok := true
			for q: Vector3 in [c, c + f * 2.0, c - f * 2.0, c - s * 1.1, c + s * 0.5]:
				if not _deep_enough(q, minf(low, water - 0.3), vs):
					ok = false
					break
			if ok:
				return {"pos": Vector3(c.x, water, c.z), "yaw": yaw}
	return null


const KITS := {&"skiff_kit": Boat.KIND_SKIFF, &"barge_kit": Boat.KIND_BARGE, &"sloop_kit": Boat.KIND_SLOOP, &"schooner_kit": Boat.KIND_SCHOONER}
const KIT_HINT := {
	Boat.KIND_SKIFF: "Skiff launched. F to board, W to raise the sail.",
	Boat.KIND_BARGE: "Tide-Barge launched. F to board; Shift+F beside it to stow or take cargo.",
	Boat.KIND_SLOOP: "Coastal Sloop launched. F to board, W to raise the sail: she points higher than a skiff.",
	Boat.KIND_SCHOONER: "Ocean Schooner launched. 6 seats, twin gaff masts, and 36-slot hold. Ready for the deep sea!",
}


## The boat kind of the kit in the player's hand, or -1.
func held_kit() -> int:
	var p: Player = main.player
	if p == null or p.is_seated():
		return -1
	var slot: ItemSlot = p.inventory.get_active_item()
	if slot == null or slot.is_empty():
		return -1
	return int(KITS.get(slot.item_id, -1))


func holding_skiff_kit() -> bool:
	return held_kit() >= 0


func try_launch() -> bool:
	var kind := held_kit()
	if kind < 0:
		return false
	var sp: Variant = launch_spot(main.player)
	var nm := Boat.new()
	nm.kind = kind
	var label := nm.display_name()
	nm.free()
	if sp == null:
		main.hud.show_toast("Find open water (at least waist deep) to launch the %s" % label)
		return false
	main.player.inventory.remove_item(KITS.find_key(kind), 1)
	if _is_host():
		_host_launch(sp.pos, sp.yaw, kind)
	else:
		request_launch.rpc_id(1, sp.pos, sp.yaw, kind)
	main.hud.show_toast(KIT_HINT.get(kind, "Launched."))
	return true


@rpc("any_peer", "call_remote", "reliable")
func request_launch(pos: Vector3, yaw: float, kind := Boat.KIND_SKIFF) -> void:
	if multiplayer.is_server():
		_host_launch(pos, yaw, kind)


func _host_launch(pos: Vector3, yaw: float, kind := Boat.KIND_SKIFF) -> Boat:
	var bid := _next_id
	_next_id += 1
	var b := _create(bid, pos, yaw, kind)
	if main.is_net and multiplayer.multiplayer_peer != null:
		spawn_boat.rpc(bid, pos, yaw, kind)
	print("[boat] %s %d launched at (%.1f, %.1f)" % [b.display_name(), bid, pos.x, pos.z])
	return b


# ---------------------------------------------------------------- the barge's hold

## Shift+F beside a barge: stow the active stack, or (empty-handed) take a stack out.
func hold_interact(b: Boat) -> void:
	var p: Player = main.player
	var slot: ItemSlot = p.inventory.get_active_item()
	if slot != null and not slot.is_empty():
		var id := slot.item_id
		var n := p.inventory.remove_item(id, slot.count)
		if n <= 0:
			return
		if _is_host():
			_host_hold(_local_id(), b.id, &"stow", id, n)
		else:
			request_hold.rpc_id(1, b.id, &"stow", id, n)
	elif _is_host():
		_host_hold(_local_id(), b.id, &"take", &"", 0)
	else:
		request_hold.rpc_id(1, b.id, &"take", &"", 0)


@rpc("any_peer", "call_remote", "reliable")
func request_hold(bid: int, op: StringName, item: StringName, n: int) -> void:
	if multiplayer.is_server():
		_host_hold(multiplayer.get_remote_sender_id(), bid, op, item, n)


func _host_hold(peer: int, bid: int, op: StringName, item: StringName, n: int) -> void:
	var b: Boat = boats.get(bid)
	var back: Array = []
	var toast := ""
	var h: Inventory = b.get_hold() if b != null else null
	if b == null or h == null:
		if op == &"stow":
			back = [[item, n]]
		_give(peer, back, "There's no hold here.")
		return
	var who: Node3D = main.player if peer == _local_id() else main.remotes.get(peer)
	if who != null and who.position.distance_to(b.position) > BOARD_RANGE + 3.0:
		if op == &"stow":
			_give(peer, [[item, n]], "")
		return
	if op == &"stow":
		var left := h.add_item(item, n)
		var it: ItemDef = ItemDB.get_item(item)
		toast = "Stowed %d %s in the boat's hold (%d/%d)" % [n - left, it.name if it != null else String(item), b.hold_used(), h.slots.size()]
		if left > 0:
			back = [[item, left]]
			toast += "  ·  the hold is full"
	else:
		for s: ItemSlot in h.slots:
			if not s.is_empty():
				var id: StringName = s.item_id
				var got := h.remove_item(id, s.count)
				back = [[id, got]]
				var it2: ItemDef = ItemDB.get_item(id)
				toast = "Took %d %s from the hold" % [got, it2.name if it2 != null else String(id)]
				break
		if back.is_empty():
			toast = "The hold is empty. Hold Shift and press F with a stack in hand to stow it."
	_give(peer, back, toast)
	_send_hold(b)


func _give(peer: int, items: Array, toast: String) -> void:
	if peer == _local_id() or not main.is_net:
		hold_give(items, toast)
	else:
		hold_give.rpc_id(peer, items, toast)


@rpc("authority", "call_remote", "reliable")
func hold_give(items: Array, toast: String) -> void:
	var p: Player = main.player
	if p == null:
		return
	for g: Array in items:
		var left := p.inventory.add_item(StringName(g[0]), int(g[1]))
		if left > 0:
			toast += "  (no room: %d dropped)" % left
	if toast != "":
		main.hud.show_toast(toast)


func _send_hold(b: Boat) -> void:
	if main.is_net and multiplayer.multiplayer_peer != null and b.hold != null:
		hold_sync.rpc(b.id, b.hold.serialize())


@rpc("authority", "call_remote", "reliable")
func hold_sync(bid: int, data: Variant) -> void:
	var b: Boat = boats.get(bid)
	if b != null and b.hold != null:
		b.hold.deserialize(data)


# ---------------------------------------------------------------- saving the fleet

var _saved_fleet: Array = []
var _fleet_registered := false


## Launched boats (skiffs, barges, sloops, and the barge's cargo) are kept with the world;
## the starting rowboats are always re-made where the world puts them.
func _save_fleet() -> Variant:
	var out: Array = []
	for b: Boat in boats.values():
		if b.kind == Boat.KIND_ROWBOAT:
			continue
		out.append({
			"kind": b.kind,
			"pos": b.position,
			"yaw": b.yaw,
			"hold": b.hold.serialize() if b.hold != null else null,
			"fixtures": b.serialize_fixtures()
		})
	return out


func _load_fleet(d: Variant) -> void:
	_saved_fleet = d if d is Array else []
	if _spawned and _is_host():
		_spawn_saved()


func _spawn_saved() -> void:
	for rec: Dictionary in _saved_fleet:
		var b := _host_launch(rec.get("pos", Vector3.ZERO), float(rec.get("yaw", 0.0)), int(rec.get("kind", Boat.KIND_SKIFF)))
		if b.hold != null and rec.get("hold") != null:
			b.hold.deserialize(rec.hold)
			_send_hold(b)
		if rec.has("fixtures") and b.has_method("deserialize_fixtures"):
			b.deserialize_fixtures(rec.fixtures)
			if _is_host() and main != null and main.is_net and multiplayer.multiplayer_peer != null:
				fixture_sync.rpc(b.id, rec.fixtures)
	if not _saved_fleet.is_empty():
		print("[boat] relaunched %d saved boat(s)" % _saved_fleet.size())
	_saved_fleet = []


@rpc("authority", "call_remote", "reliable")
func fixture_sync(bid: int, data: Variant) -> void:
	var b: Boat = boats.get(bid)
	if b != null and data is Array and b.has_method("deserialize_fixtures"):
		b.deserialize_fixtures(data)


@rpc("authority", "call_remote", "reliable")
func sync_all(data: Array) -> void:
	for d: Array in data:
		var b := _create(d[0], d[1], d[2], int(d[4]) if d.size() > 4 else 0)
		b.occupants = (d[3] as Array).duplicate()
	_refresh_links()


func _on_peer_connected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var data := []
	for b: Boat in boats.values():
		data.append([b.id, b.position, b.yaw, b.occupants, b.kind])
	sync_all.rpc_id(id, data)
	for b: Boat in boats.values():
		if b.hold != null:
			hold_sync.rpc_id(id, b.id, b.hold.serialize())


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
	var can_interact: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (main.controller != null and main.controller.current_type != ControllerManager.Type.KEYBOARD_MOUSE)
	if e.is_action_pressed("interact") and can_interact:
		if holding_skiff_kit() and nearest_boardable(main.player.position) == null and launch_spot(main.player) != null:
			get_viewport().set_input_as_handled()
			try_launch()
			return
		interact()


## F: board the nearest boat, or step off the current one.
func interact() -> void:
	var p: Player = main.player
	if p == null or not _world_ready():
		return
	if p.is_seated():
		if main.controller:
			main.controller.reset_triggers()
		var spot = p.boat.find_exit_spot()
		if spot == null:
			spot = p.boat.find_swim_exit_spot()   # no floor nearby: slip over the side
		if spot == null:
			main.hud.show_toast("No room to step off here")
			return
		_pending_exit = spot
		if _is_host():
			_host_leave(_local_id(), p.boat.id)
		else:
			request_leave.rpc_id(1, p.boat.id)
		return
	var b := nearest_boardable(p.position)
	var near_barge := _nearest_barge(p.position)
	if near_barge != null and Input.is_action_pressed("sprint"):
		hold_interact(near_barge)
		return
	if b == null:
		return
	if _is_host():
		_host_seat(_local_id(), b.id, b.free_seat())
	else:
		request_seat.rpc_id(1, b.id, b.free_seat())


func _nearest_barge(pos: Vector3) -> Boat:
	for b: Boat in boats.values():
		if b.get_hold() != null and Vector2(pos.x - b.position.x, pos.z - b.position.z).length() < BOARD_RANGE + 0.6 \
				and absf(pos.y - b.position.y) < 2.5:
			return b
	return null


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
	if not _fleet_registered and main.get("session") != null:
		_fleet_registered = true
		main.session.register_state(&"fleet", _save_fleet, _load_fleet)
	if not _world_ready():
		return
	if not _spawned and _is_host():
		_spawn_initial()
	var me := _local_id()
	if main.is_net:
		_last_net_id = me
	var p: Player = main.player
	for b: Boat in boats.values():
		b._local_auth = b.authority() == me
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
			elif p.input_enabled:
				var can_input: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (main.controller != null and main.controller.current_type != ControllerManager.Type.KEYBOARD_MOUSE)
				if can_input:
					f = Input.get_axis("move_back", "move_forward")
					t = Input.get_axis("move_right", "move_left")
					hard = Input.is_action_pressed("sprint")
					if absf(f) > 0.1 and main.controller:
						if b.row_power > 0.8 and sin(b.row_phase) > 0.9:
							main.controller.pulse_row()
						main.controller.apply_rowing(b.row_power, b.row_phase)
					elif main.controller:
						main.controller.reset_triggers()
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
		if p.boat.has_sail():
			var bt: Boat = p.boat
			var w := bt.wind_vec()
			var pos_name := Boat.point_of_sail(bt.forward2(), w)
			var status := "%s  %.1f m/s  ·  sail %d%%" % [pos_name, bt.vel.length(), int(bt.row_power * 100.0)]
			prompt = (status + "      W/S sail  A/D steer  Shift paddle  F step off") if p.seat == 0 				else (status + "      F  Step off")
		else:
			prompt = "F  Step off      W/S  row    A/D  turn    Shift  pull hard" if p.seat == 0 else "F  Step off      (riding as passenger)"
	else:
		var b := nearest_boardable(p.position)
		var kit := held_kit()
		if kit >= 0 and b == null and launch_spot(p) != null:
			prompt = "F  Launch %s" % ["rowboat", "skiff", "Tide-Barge", "Coastal Sloop"][kit]
		elif b != null:
			prompt = ("F  Board %s" % b.display_name()) if b.free_seat() == 0 else "F  Ride along"
			if b.hold != null:
				prompt += "      Shift+F  stow / take cargo (%d/%d)" % [b.hold_used(), Boat.HOLD_SLOTS]
		elif main.entities != null:
			var ent: WorldEntity = main.entities.get_closest_interactable(p.position)
			if ent != null:
				prompt = ent.get_interaction_prompt(p)
				if ent.item_id != &"":
					prompt += "      (hold F: pick up)"
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


## --skiffcheck[=SHOT_DIR]: launch a skiff from a kit, sail it on each point of sail, and
## check it beats the rowboat on a reach and stalls head to wind.
func run_skiff_check(shot_dir: String) -> void:
	var p: Player = main.player
	p.input_enabled = false
	while boats.is_empty():
		await get_tree().process_frame
	var row: Boat = boats.values()[0]
	p.position = row.position
	p.inventory.add_item(&"skiff_kit", 1)
	await _wait(1.0)
	var before := boats.size()
	var sp: Variant = launch_spot(p)
	print("[skiff] launch spot: %s" % [sp])
	if sp == null or not try_launch():
		print("[skiff] FAIL no launch")
		get_tree().quit()
		return
	await _wait(0.5)
	var b: Boat = null
	for x: Boat in boats.values():
		if x.is_skiff():
			b = x
	print("[skiff] boats %d -> %d, kit left %d" % [before, boats.size(), p.inventory.get_item_count(&"skiff_kit")])
	p.position = b.position + Vector3(0, 0.5, 0)
	_host_seat(_local_id(), b.id, 0)
	await _wait(0.4)
	print("[skiff] seated=%s skiff=%s" % [p.is_seated(), p.is_seated() and p.boat.is_skiff()])
	# open water for the trial: a spot with 45 m of clear sea all round
	var water := b.water_y()
	var found := false
	for r in range(20, 600, 20):
		for k in 24:
			var a := TAU * k / 24.0
			var c := row.position + Vector3(cos(a), 0, sin(a)) * float(r)
			var clear := true
			for j in 16:
				var q := c + Vector3(cos(TAU * j / 16.0), 0, sin(TAU * j / 16.0)) * 60.0
				for ti in 16:
					var t := ti / 15.0
					var e: Vector3 = c.lerp(q, t) / VoxelWorld.VS
					if main.world.gen.col_h(int(e.x), int(e.z)) > VoxelWorld.SEA_MID - VoxelWorld.TIDE_AMP - 4:
						clear = false
						break
				if not clear:
					break
			if clear:
				b.position = Vector3(c.x, water, c.z)
				p.position = b.position + Vector3(0, 0.5, 0)
				found = true
				await _wait(3.0)   # let the sea floor stream in
				break
		if found:
			break
	print("[skiff] trial spot %s blocked=%d" % [b.position, b.blocked_count(b.position, b.yaw, b.water_y())])
	debug_active = true
	var w := b.wind_vec()
	print("[skiff] wind %s (strength %.2f)" % [w.normalized(), w.length()])
	var results := {}
	for leg: Array in [["beam reach", PI * 0.5], ["running", 0.0], ["in irons", PI]]:
		var wa := atan2(w.x, w.y)   # the bow, relative to where the wind blows towards
		b.yaw = wa + float(leg[1])
		b.position = Vector3(b.position.x, b.water_y(), b.position.z) if leg[0] == "beam reach" else b.get_meta("trial", b.position)
		b.set_meta("trial", b.position)
		b.vel = Vector2.ZERO
		b.yaw_vel = 0.0
		debug_input = Vector3(1, 0, 0)       # raise the sail and hold it
		for sec in 6:
			await _wait(1.0)
			print("[skiff]   %s t=%d speed %.2f sail %.2f blocked %d grounded %s eff %.2f" % [leg[0], sec + 1, b.vel.length(), b.row_power,
				b.blocked_count(b.position, b.yaw, b.water_y()), b.grounded, Boat.sail_efficiency(b.forward2(), b.wind_vec())])
		results[leg[0]] = b.vel.length()
		_stat(b, String(leg[0]))
		if shot_dir != "" and leg[0] == "beam reach":
			main.rig.yaw = b.yaw + PI * 0.7
			main.rig.pitch = -0.32
			main.rig.dist = 8.0
			main.rig.shoulder = -2.6
			main.hud.show_hud(false)
			await _wait(0.4)
			await main._shot(shot_dir, "skiff_reach")
			main.hud.show_hud(true)
	debug_input = Vector3(-1, 0, 0)
	await _wait(2.0)
	print("[skiff] sail lowered: %d%%" % int(b.row_power * 100.0))
	var pc = p.get("combat")
	if pc != null:
		p.inventory.add_item(&"silver_mackerel", 1)
		print("[skiff] gulls see fish while aboard: %s" % [pc.holding_fish()])
	print("[skiff] speeds: reach %.2f, run %.2f, irons %.2f m/s" % [results["beam reach"], results["running"], results["in irons"]])
	debug_active = false
	get_tree().quit()
