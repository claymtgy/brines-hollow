class_name ChestEntity
extends WorldEntity
## Physical 3D Storage Chest in the world.
## Wraps StorageContainer to provide persistent storage for items and fish.

signal container_accessed(player: Player)

var container: StorageContainer


func _init(
	p_name: String = "Driftwood Storage Chest",
	p_coord: Vector3i = Vector3i.ZERO,
	p_capacity: int = 18,
	p_tags: PackedStringArray = PackedStringArray()
) -> void:
	super._init(&"driftwood_chest", p_name, p_coord)
	entity_type = EntityType.CONTAINER
	container = StorageContainer.new(p_name, p_capacity, p_tags)


func _build_visuals() -> void:
	_mesh_instance = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.75, 0.50, 0.50)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.48, 0.36, 0.24) # Weathered driftwood chest
	_mesh_instance.mesh = box
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func get_interaction_prompt(player: Player) -> String:
	var item_cnt := 0
	for slot in container.inventory.slots:
		if not slot.is_empty():
			item_cnt += slot.count
	return "F  Open %s (%d items stored)" % [entity_name, item_cnt]


func interact(player: Player) -> void:
	super.interact(player)
	container_accessed.emit(player)
	# Fast deposit / take interaction: if player has items in active hotbar slot, deposit them
	var active_slot := player.inventory.get_active_item()
	if active_slot and not active_slot.is_empty():
		var deposit_id: StringName = active_slot.item_id
		var deposit_count: int = active_slot.count
		if container.can_accept_item(deposit_id):
			var remaining := container.inventory.add_item(deposit_id, deposit_count)
			var transferred := deposit_count - remaining
			if transferred > 0:
				player.inventory.remove_item(deposit_id, transferred)
				if player.hud:
					player.hud.show_toast("Stored %d %s in %s." % [transferred, deposit_id, entity_name])
				return

	# Otherwise, retrieve first available item from container
	for slot in container.inventory.slots:
		if not slot.is_empty():
			var item_id: StringName = slot.item_id
			var count: int = mini(slot.count, 5)
			var unadded := player.inventory.add_item(item_id, count)
			var taken := count - unadded
			if taken > 0:
				container.inventory.remove_item(item_id, taken)
				if player.hud:
					player.hud.show_toast("Retrieved %d %s from %s." % [taken, item_id, entity_name])
				return

	if player.hud:
		player.hud.show_toast("%s is currently empty." % entity_name)


func serialize() -> Dictionary:
	var d := super.serialize()
	d["items"] = container.inventory.serialize()
	return d


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	if data.has("items"):
		container.inventory.deserialize(data["items"])
