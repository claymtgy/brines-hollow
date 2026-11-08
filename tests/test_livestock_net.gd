extends SceneTree
## Livestock over a real (loopback ENet) co-op connection: the host streams animal poses,
## the client mirrors them, and a client's petting reaches the host.
##   godot --headless --path . -s tests/test_livestock_net.gd

var passed := 0
var total := 0
const PORT := 24599


class FakeMain:
	extends Node
	var is_net := true
	var remotes := {}
	var player = null
	var world = null
	var livestock_mgr: Node


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		print("  [FAIL] ", label)


func make_side(nm: String) -> FakeMain:
	var m := FakeMain.new()
	m.name = nm
	root.add_child(m)
	var api := SceneMultiplayer.new()
	set_multiplayer(api, m.get_path())
	var ls := LivestockManager.new()
	ls.main = m
	m.livestock_mgr = ls
	m.add_child(ls)   # named "Livestock" in _ready on both sides: same relative path
	return m


func pump(frames: int) -> void:
	for i in frames:
		await process_frame


func _initialize() -> void:
	ItemDB.init_db()
	await process_frame
	var host := make_side("Host")
	var client := make_side("Client")
	var hp := ENetMultiplayerPeer.new()
	check(hp.create_server(PORT, 4) == OK, "host listens")
	host.multiplayer.multiplayer_peer = hp
	var cp := ENetMultiplayerPeer.new()
	check(cp.create_client("127.0.0.1", PORT) == OK, "client connects")
	client.multiplayer.multiplayer_peer = cp
	var t := 0
	while cp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED and t < 300:
		await process_frame
		t += 1
	check(cp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "connection established")

	var hl: LivestockManager = host.livestock_mgr
	var cl: LivestockManager = client.livestock_mgr
	var goat: Node3D = hl.spawn_animal(&"salt_goat", Vector3(2, 0, 2), "Barnaby")
	var duck: Node3D = hl.spawn_animal(&"shore_duck", Vector3(6, 0, 2), "Pip")
	check(hl.is_authority() and not cl.is_authority(), "host simulates, client mirrors")
	await pump(30)
	check(cl.animals.size() == 2, "client sees both animals")
	var cg: Node3D = cl.get_animal_by_id(goat.animal_id)
	check(cg != null and cg.animal_name == "Barnaby", "with their names")

	# Move the goat on the host: the client's copy follows.
	goat.state = 0
	goat.state_t = 999.0
	goat.position = Vector3(5, 0, 7)
	goat.yaw = 2.0
	await pump(60)
	check(cg.position.distance_to(Vector3(5, 0, 7)) < 0.25, "client's goat walks to where the host's is (%s)" % cg.position)
	check(absf(angle_difference(cg.yaw, 2.0)) < 0.2, "and turns the same way")

	# A client pets the goat: the host's goat gets the change.
	cg.pet_cooldown = 45.0
	cg.happiness = 97.0
	cl.lv_interacted.rpc_id(1, cg.animal_id, cg.interact_state())
	await pump(20)
	check(goat.pet_cooldown > 40.0 and goat.happiness > 90.0, "a client's petting lands on the host")

	# A client holding wheat counts as a herder on the host.
	cl.lv_herding.rpc_id(1, true)
	await pump(20)
	var cid: int = cp.get_unique_id()
	check(hl._remote_herding.get(cid, false), "the host knows the client is holding herd bait")
	var stand_in := Node3D.new()
	root.add_child(stand_in)
	host.remotes[cid] = stand_in
	check(hl.herders().has(stand_in), "so the client's player is someone animals will follow")

	# The host loses an animal: it vanishes for the client too.
	var duck_id: int = duck.animal_id
	hl.remove_animal(duck)
	await pump(30)
	check(cl.get_animal_by_id(duck_id) == null and cl.animals.size() == 1, "removed animals disappear on the client")

	cp.close()
	hp.close()
	print("Livestock net suite: %d / %d tests passed!" % [passed, total])
	quit(0 if passed == total else 1)
