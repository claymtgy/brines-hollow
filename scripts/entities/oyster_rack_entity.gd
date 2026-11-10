class_name OysterRackEntity
extends WorldEntity
## Tidal Oyster Rack: intertidal aquaculture trestle placed in coastal shallows and tidal flats.
## Submerges at high tide to filter seawater, accumulating Brine Oysters, Hearty Clams, and rare Abyssal Pearls.

const U := VoxelWorld.VS * 0.5
const CYCLE_SUBMERGED_SEC := 12.0
const MAX_CAPACITY := 12

var harvest_stored: Dictionary = {
	&"brine_oyster": 0,
	&"hearty_clam": 0,
	&"abyssal_pearl": 0
}
var submerged_time: float = 0.0
var _nodule_group: Node3D
var _check_t: float = 0.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"oyster_rack", "Tidal Oyster Rack", p_coord)
	entity_type = EntityType.WORKSTATION
	item_id = &"oyster_rack"
	size = Vector3(8, 6, 8) * U


func _build_visuals() -> void:
	var root := Node3D.new()
	var g := Prefabs.Grid.new(8, 6, 8)

	# 4 Heavy wooden corner pilings/stilts
	g.box(0, 0, 0, 1, 5, 1, Palette.DARK_WOOD)
	g.box(6, 0, 0, 7, 5, 1, Palette.DARK_WOOD)
	g.box(0, 0, 6, 1, 5, 7, Palette.DARK_WOOD)
	g.box(6, 0, 6, 7, 5, 7, Palette.DARK_WOOD)

	# Slotted mesh cultivation trays (lower and upper tier)
	g.box(1, 2, 1, 6, 2, 6, Palette.PLANK)
	g.box(1, 4, 1, 6, 4, 6, Palette.PLANK)
	g.box(0, 5, 0, 7, 5, 7, Palette.STONE) # top retaining border

	var mi_frame := _voxel_model(g)
	mi_frame.position = Vector3(-4, 0, -4) * U
	root.add_child(mi_frame)

	_nodule_group = Node3D.new()
	_nodule_group.name = "Nodules"
	root.add_child(_nodule_group)

	_mesh_instance = root
	_update_nodule_visuals()


func _update_nodule_visuals() -> void:
	if _nodule_group == null:
		return
	for ch in _nodule_group.get_children():
		ch.queue_free()

	var total := get_total_harvest()
	if total <= 0:
		return

	var count_visuals := mini(total, 6)
	var nodule_mat := StandardMaterial3D.new()
	nodule_mat.albedo_color = Color(0.2, 0.22, 0.24) # dark oyster/clam shell grey

	for i in count_visuals:
		var nodule := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.09
		sph.height = 0.14
		nodule.mesh = sph
		nodule.material_override = nodule_mat
		var ang := float(i) * 1.05
		var r := 0.22
		nodule.position = Vector3(cos(ang) * r, 0.25 * (i % 2 + 1), sin(ang) * r)
		_nodule_group.add_child(nodule)


func get_total_harvest() -> int:
	var total := 0
	for k in harvest_stored:
		total += int(harvest_stored[k])
	return total


func is_submerged() -> bool:
	var em := EntityManager.current
	if em == null or em.main == null:
		return false
	var sky: SkyCycle = em.main.sky if "sky" in em.main else null
	if sky != null:
		return sky.water_level_m() > position.y
	return false


func _process(dt: float) -> void:
	_check_t -= dt
	if _check_t > 0.0:
		return
	_check_t = 1.0
	tick(1.0)


func tick(delta: float) -> void:
	if not is_submerged():
		return

	submerged_time += delta
	if submerged_time >= CYCLE_SUBMERGED_SEC:
		submerged_time = 0.0
		if get_total_harvest() < MAX_CAPACITY:
			_produce_seafood()


func _produce_seafood() -> void:
	if get_total_harvest() >= MAX_CAPACITY:
		return
	var roll := randf()
	if roll < 0.05:
		harvest_stored[&"abyssal_pearl"] = harvest_stored.get(&"abyssal_pearl", 0) + 1
	elif roll < 0.50:
		harvest_stored[&"brine_oyster"] = harvest_stored.get(&"brine_oyster", 0) + 1
	else:
		harvest_stored[&"hearty_clam"] = harvest_stored.get(&"hearty_clam", 0) + 1
	_update_nodule_visuals()


func get_interaction_prompt(_player: Player) -> String:
	var total := get_total_harvest()
	if total <= 0:
		if is_submerged():
			return "Tidal Oyster Rack · Submerged (filtering tide...)"
		return "Tidal Oyster Rack · Empty (awaits high tide)"
	return "Tidal Oyster Rack · %d shellfish ready  ·  F: Harvest" % total


func client_interact(player: Player) -> void:
	interacted.emit(player)
	var total := get_total_harvest()
	if total <= 0:
		if player.hud != null:
			player.hud.show_toast("The oyster trays are still cultivating.")
		return

	var harvested_names: Array[String] = []
	for item_id_key: StringName in harvest_stored.keys():
		var count: int = harvest_stored[item_id_key]
		if count > 0:
			player.inventory.add_item(item_id_key, count)
			var idef := ItemDB.get_item(item_id_key)
			var iname := idef.name if idef != null else String(item_id_key)
			harvested_names.append("%d %s" % [count, iname])
			harvest_stored[item_id_key] = 0

	CombatAudio.play_sound("pickup", position)
	_update_nodule_visuals()
	if player.hud != null:
		player.hud.show_toast("Harvested from Oyster Rack: " + ", ".join(harvested_names))


func serialize() -> Dictionary:
	var d := super.serialize()
	d["harvest_stored"] = harvest_stored.duplicate()
	d["submerged_time"] = submerged_time
	return d


func deserialize(d: Dictionary) -> void:
	super.deserialize(d)
	if d.has("harvest_stored") and d["harvest_stored"] is Dictionary:
		harvest_stored = d["harvest_stored"].duplicate()
	if d.has("submerged_time"):
		submerged_time = float(d["submerged_time"])
	_update_nodule_visuals()
