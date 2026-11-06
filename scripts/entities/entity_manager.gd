class_name EntityManager
extends Node3D
## Central manager for all dynamic physical world entities (workstations, chests, beds, mirrors).
## Manages spatial indexing, proximity interaction checks, ticking, and persistence.

signal entity_spawned(entity: WorldEntity)
signal entity_removed(coord: Vector3i)

## Dictionary of Vector3i -> WorldEntity
var entities: Dictionary = {}


func spawn_entity(type: StringName, coord: Vector3i, rot: int = 0) -> WorldEntity:
	if entities.has(coord):
		remove_entity(coord)

	var ent: WorldEntity = null
	match type:
		&"workbench":
			ent = StationEntity.new(&"workbench", "Carpentry Workbench", coord)
		&"campfire":
			ent = StationEntity.new(&"campfire", "Campfire Skillet", coord)
		&"hearth_pot":
			ent = StationEntity.new(&"hearth_pot", "Hearth Stew Pot", coord)
		&"smokehouse":
			ent = StationEntity.new(&"smokehouse", "Fisher's Smokehouse", coord)
		&"saltery":
			ent = StationEntity.new(&"saltery", "Brine Saltery", coord)
		&"brewery":
			ent = StationEntity.new(&"brewery", "Coastal Teahouse", coord)
		&"chest", &"driftwood_chest":
			ent = ChestEntity.new("Driftwood Storage Chest", coord)
		&"bed", &"fisher_bed":
			ent = BedEntity.new(coord)
		&"mirror", &"barber_mirror":
			ent = MirrorEntity.new(coord)
		_:
			ent = WorldEntity.new(type, String(type).capitalize(), coord)

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
	var closest: WorldEntity = null
	var closest_dist: float = max_reach

	for ent: WorldEntity in entities.values():
		var d := player_pos.distance_to(ent.position)
		if d <= ent.interaction_radius and d < closest_dist:
			closest_dist = d
			closest = ent

	return closest


func tick(delta: float) -> void:
	for ent: WorldEntity in entities.values():
		ent.tick(delta)


func _process(delta: float) -> void:
	tick(delta)


func get_count() -> int:
	return entities.size()


func serialize() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for ent: WorldEntity in entities.values():
		list.append(ent.serialize())
	return list


func deserialize(data: Array) -> void:
	# Clear existing
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
