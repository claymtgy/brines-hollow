class_name ItemSlot
extends RefCounted
## Represents a single inventory or storage container slot.

var item_id: StringName = &""
var count: int = 0
var custom_data: Dictionary = {}


func _init(p_id: StringName = &"", p_count: int = 0, p_data: Dictionary = {}) -> void:
	item_id = p_id
	count = p_count
	custom_data = p_data.duplicate(true)


func is_empty() -> bool:
	return item_id == &"" or count <= 0


func clear() -> void:
	item_id = &""
	count = 0
	custom_data.clear()


func can_stack_with(other_id: StringName, other_data: Dictionary = {}) -> bool:
	if is_empty():
		return true
	if item_id != other_id:
		return false
	# If either has unique durability/custom data, they cannot stack unless data matches
	return custom_data == other_data


func duplicate_slot() -> ItemSlot:
	return ItemSlot.new(item_id, count, custom_data)


func to_dict() -> Dictionary:
	if is_empty():
		return {}
	var d: Dictionary = {
		"id": String(item_id),
		"count": count
	}
	if not custom_data.is_empty():
		d["data"] = custom_data.duplicate(true)
	return d


static func from_dict(d: Dictionary) -> ItemSlot:
	if d.is_empty() or not d.has("id") or not d.has("count"):
		return ItemSlot.new()
	var slot := ItemSlot.new(
		StringName(d["id"]),
		int(d["count"]),
		d.get("data", {})
	)
	return slot
