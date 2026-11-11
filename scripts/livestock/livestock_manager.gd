class_name LivestockManager
extends Node3D
## Manages domestic livestock herds, co-op synchronization, daily simulation,
## feeding troughs, herding mechanics (whistle and crops), and player interactions.

const LivestockAnimalClass := preload("res://scripts/livestock/livestock_animal.gd")

const INTERACT_RANGE := 2.6
const WHISTLE_RANGE := 25.0

var main: Node
var animals: Array = []
var _next_id: int = 1
var _starter_spawned: bool = false
var _prompt_animal: Node3D = null

const NET_INTERVAL := 0.1
var _net_t: float = 0.0
var _remote_herding: Dictionary = {}   # peer id -> bool (host only)
var _my_herding_sent: bool = false


func _ready() -> void:
	name = "Livestock"
	if main != null:
		bind(main)


func bind(p_main: Node) -> void:
	main = p_main
	if main != null and main.get("session") != null:
		main.session.register_state(&"livestock", serialize, deserialize)
		if not main.session.world_ready.is_connected(_on_world_ready):
			main.session.world_ready.connect(_on_world_ready)


func _on_world_ready(_is_new: bool) -> void:
	var is_auth: bool = true
	if main != null and main.get("multiplayer") != null and main.get("is_net") != null and main.is_net:
		is_auth = main.multiplayer.is_server()
	if is_auth and not _starter_spawned:
		spawn_starter_livestock()


# ---------------------------------------------------------------- Spawning API

func spawn_animal(species: StringName, pos: Vector3, custom_name: String = "") -> Node3D:
	var a = LivestockAnimalClass.new(species, custom_name)
	a.animal_id = _next_id
	_next_id += 1
	a.position = pos
	add_child(a)
	animals.append(a)
	return a


func remove_animal(a: Node3D) -> void:
	var idx := animals.find(a)
	if idx >= 0:
		animals.remove_at(idx)
	if is_instance_valid(a):
		a.queue_free()


func get_animal_by_id(id: int) -> Node3D:
	for a in animals:
		if a.animal_id == id:
			return a
	return null


func get_closest_animal(pos: Vector3, max_dist: float = INTERACT_RANGE) -> Node3D:
	var best: Node3D = null
	var best_d: float = max_dist
	for a in animals:
		var d: float = a.position.distance_to(pos)
		if d < best_d:
			best = a
			best_d = d
	return best


func spawn_starter_livestock() -> void:
	if _starter_spawned:
		return
	_starter_spawned = true

	var spawn_pos := Vector3(8, 2, 4)
	if main != null and main.get("world") != null and main.world.get("gen") != null:
		spawn_pos = Vector3(main.world.gen.spawn) * VoxelWorld.VS   # gen.spawn is in voxels

	# Spawn starter pair of each domestic species in pasture near village (wild until tamed and named!)
	spawn_animal(&"salt_goat", spawn_pos + Vector3(6.0, 0.0, 3.0), "")
	spawn_animal(&"salt_goat", spawn_pos + Vector3(7.5, 0.0, 5.0), "")

	spawn_animal(&"shore_sheep", spawn_pos + Vector3(4.0, 0.0, 8.0), "")
	spawn_animal(&"shore_sheep", spawn_pos + Vector3(5.5, 0.0, 9.5), "")

	spawn_animal(&"shore_duck", spawn_pos + Vector3(-4.0, 0.0, 5.0), "")
	spawn_animal(&"shore_duck", spawn_pos + Vector3(-5.5, 0.0, 6.0), "")


# ---------------------------------------------------------------- Herding & Whistle

## Called when the player sounds the Shepherd's Whistle
func sound_whistle(origin: Vector3) -> int:
	CombatAudio.play_sound("animal_whistle", origin)
	var alerted := 0
	for a in animals:
		if a.position.distance_to(origin) <= WHISTLE_RANGE:
			a.state = LivestockAnimalClass.State.FOLLOW
			a.state_t = 16.0
			if main != null and main.get("player") != null:
				a.target_player = main.player
			a.pop_emote("♪", Color(0.4, 0.8, 1.0))
			alerted += 1
	return alerted


# ---------------------------------------------------------------- Processing & Interaction

func is_authority() -> bool:
	if main == null or main.get("is_net") == null or not main.is_net:
		return true
	return main.multiplayer.multiplayer_peer == null or main.multiplayer.is_server()


func _online() -> bool:
	return main != null and main.get("is_net") != null and main.is_net 			and main.multiplayer.multiplayer_peer != null 			and main.multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Players who are currently leading animals with wheat, kale or the whistle.
func herders() -> Array:
	var out: Array = []
	var p = main.get("player") if main != null else null
	if p != null and LivestockAnimalClass.holds_herd_bait(p):
		out.append(p)
	if main != null and main.get("remotes") != null:
		for id in main.remotes:
			if _remote_herding.get(id, false) and is_instance_valid(main.remotes[id]):
				out.append(main.remotes[id])
	return out


func _process(delta: float) -> void:
	if is_authority():
		for a in animals:
			a.simulate(delta, main)
		if _online():
			_net_t -= delta
			if _net_t <= 0.0:
				_net_t = NET_INTERVAL
				var packs: Array = []
				for a in animals:
					packs.append(a.net_pack())
				lv_snapshot.rpc(packs)
	else:
		for a in animals:
			a.net_update(delta)
		if _online():
			var herding: bool = main.get("player") != null and LivestockAnimalClass.holds_herd_bait(main.player)
			if herding != _my_herding_sent:
				_my_herding_sent = herding
				lv_herding.rpc_id(1, herding)

	# Check player proximity for HUD interaction prompt
	_update_prompt()


func _update_prompt() -> void:
	var p: Player = main.get("player") if main != null else null
	if p == null or p.is_seated() or (main.get("settings_menu") != null and main.settings_menu.is_open()):
		_prompt_animal = null
		return

	# If an entity, NPC, or boat is closer, let them claim the prompt
	if main.get("entities") != null and main.entities.get_closest_interactable(p.position) != null:
		_prompt_animal = null
		return
	if main.get("boats") != null and main.boats.nearest_boardable(p.position) != null:
		_prompt_animal = null
		return

	_prompt_animal = get_closest_animal(p.position, INTERACT_RANGE)
	if _prompt_animal == null:
		return

	if main.get("hud") != null:
		main.hud.set_prompt(_prompt_animal.get_interaction_prompt(p))


func _unhandled_input(e: InputEvent) -> void:
	if _prompt_animal == null or not e.is_action_pressed("interact"):
		return
	var p: Player = main.get("player") if main != null else null
	if p == null or not p.input_enabled:
		return

	# Entities or boats have priority if within range
	if main.get("entities") != null and main.entities.get_closest_interactable(p.position) != null:
		return
	if main.get("boats") != null and main.boats.nearest_boardable(p.position) != null:
		return

	get_viewport().set_input_as_handled()
	var res: Dictionary = _prompt_animal.interact(p)
	if res.get("ok", false) and not is_authority() and _online():
		# The item change happened in our own pack; tell the host what changed on the animal.
		lv_interacted.rpc_id(1, _prompt_animal.animal_id, _prompt_animal.interact_state())
	if res.get("ok", false):
		if main.get("hud") != null and res.has("msg"):
			main.hud.show_toast(res["msg"])


# ---------------------------------------------------------------- Co-op sync

## Host -> clients: every animal's pose and state. Adds and removes animals to match.
@rpc("authority", "call_remote", "unreliable_ordered")
func lv_snapshot(packs: Array) -> void:
	apply_snapshot(packs)


func apply_snapshot(packs: Array) -> void:
	var seen := {}
	for pk: Array in packs:
		var id: int = int(pk[0])
		seen[id] = true
		var a: Node3D = get_animal_by_id(id)
		if a == null:
			a = LivestockAnimalClass.new(StringName(pk[1]), String(pk[2]))
			a.animal_id = id
			a.position = pk[3]
			add_child(a)
			animals.append(a)
		a.net_apply(pk)
	for a in animals.duplicate():
		if not seen.has(a.animal_id):
			remove_animal(a)


## Client -> host: this player is (or stopped) holding herd bait.
@rpc("any_peer", "call_remote", "reliable")
func lv_herding(on: bool) -> void:
	_remote_herding[main.multiplayer.get_remote_sender_id()] = on


## Client -> host: a client sheared, milked, fed or petted an animal.
@rpc("any_peer", "call_remote", "reliable")
func lv_interacted(id: int, d: Dictionary) -> void:
	if not is_authority():
		return
	var a: Node3D = get_animal_by_id(id)
	if a != null:
		a.apply_interact_state(d)
		a.pop_emote("♥", Color(1.0, 0.35, 0.55))


# ---------------------------------------------------------------- Serialization

func serialize() -> Dictionary:
	var list: Array = []
	for a in animals:
		list.append(a.serialize())
	return {
		"starter": _starter_spawned,
		"next_id": _next_id,
		"animals": list,
	}


func deserialize(data: Dictionary) -> void:
	for a in animals:
		if is_instance_valid(a):
			a.queue_free()
	animals.clear()

	_starter_spawned = bool(data.get("starter", false))
	_next_id = int(data.get("next_id", 1))

	var list: Array = data.get("animals", [])
	for item: Dictionary in list:
		var sp: StringName = StringName(item.get("sp", &"salt_goat"))
		var nm: String = String(item.get("name", ""))
		var a: Node3D = spawn_animal(sp, Vector3.ZERO, nm)
		a.deserialize(item)
