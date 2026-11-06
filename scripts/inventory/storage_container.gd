class_name StorageContainer
extends RefCounted
## Storage container (chests, watertight barrels, town supply depots).
## Supports tag filtering and optional freshness preservation.

signal container_updated

var name: String = "Storage Crate"
var inventory: Inventory
var allowed_tags: PackedStringArray = []
var preserves_freshness: bool = false


func _init(
	p_name: String = "Storage Crate",
	p_capacity: int = 18,
	p_tags: PackedStringArray = PackedStringArray(),
	p_preserves_freshness: bool = false
) -> void:
	name = p_name
	allowed_tags = p_tags
	preserves_freshness = p_preserves_freshness
	inventory = Inventory.new(p_capacity)
	inventory.slot_changed.connect(func(_idx, _slot): container_updated.emit())


func can_accept_item(item_id: StringName) -> bool:
	if allowed_tags.is_empty():
		return true

	var def: ItemDef = ItemDB.get_item(item_id)
	if not def:
		return false

	for tag in allowed_tags:
		if def.has_tag(tag):
			return true
	return false


## Deposits items into this container if filter allows.
## Returns remainder count that could not fit.
func deposit(item_id: StringName, count: int, custom_data: Dictionary = {}) -> int:
	if not can_accept_item(item_id):
		return count
	return inventory.add_item(item_id, count, custom_data)


## Withdraws items from this container. Returns amount successfully withdrawn.
func withdraw(item_id: StringName, count: int) -> int:
	return inventory.remove_item(item_id, count)


## Serializes container state
func serialize() -> Dictionary:
	return {
		"name": name,
		"allowed_tags": Array(allowed_tags),
		"preserves_freshness": preserves_freshness,
		"inventory": inventory.serialize()
	}


## Deserializes container state
func deserialize(data: Dictionary) -> bool:
	if not data.has("inventory"):
		return false
	name = data.get("name", "Storage Crate")
	allowed_tags = PackedStringArray(data.get("allowed_tags", []))
	preserves_freshness = data.get("preserves_freshness", false)
	return inventory.deserialize(data["inventory"])
