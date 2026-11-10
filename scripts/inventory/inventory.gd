class_name Inventory
extends RefCounted
## Player or Entity Inventory managing slots, hotbar, equipment, and stacking.

signal slot_changed(slot_idx: int, slot: ItemSlot)
signal equipment_changed(slot_name: StringName, slot: ItemSlot)
signal inventory_resized(new_capacity: int)
signal item_added(item_id: StringName, count: int)
signal item_removed(item_id: StringName, count: int)
signal active_hotbar_changed(index: int)

const DEFAULT_BASE_CAPACITY := 24
const MAX_HOTBAR_SLOTS := 8

var creative_mode: bool = false
var capacity: int = DEFAULT_BASE_CAPACITY
var slots: Array[ItemSlot] = []
var active_hotbar_index: int = 0
var equipment: Dictionary = {
	&"head": ItemSlot.new(),
	&"body": ItemSlot.new(),
	&"legs": ItemSlot.new(),
	&"boots": ItemSlot.new(),
	&"backpack": ItemSlot.new(),
	&"accessory": ItemSlot.new(),
	&"main_hand": ItemSlot.new(),
	&"map": ItemSlot.new()
}


func _init(p_capacity: int = DEFAULT_BASE_CAPACITY) -> void:
	capacity = max(MAX_HOTBAR_SLOTS, p_capacity)
	_init_slots()


func _init_slots() -> void:
	slots.clear()
	for i in capacity:
		slots.append(ItemSlot.new())


# -------------------------------------------------------------------------
# Item Addition & Removal
# -------------------------------------------------------------------------

## Adds count of item_id. Returns remainder count that could not fit (0 if all added).
func add_item(p_id: StringName, p_count: int, p_custom_data: Dictionary = {}) -> int:
	if p_count <= 0 or p_id == &"":
		return 0

	var def: ItemDef = ItemDB.get_item(p_id)
	var max_stk: int = def.max_stack if def else 999
	var remaining: int = p_count

	# 1. First pass: try stacking into existing non-full matching slots
	if max_stk > 1:
		for i in capacity:
			var slot: ItemSlot = slots[i]
			if not slot.is_empty() and slot.can_stack_with(p_id, p_custom_data):
				var space: int = max_stk - slot.count
				if space > 0:
					var to_add: int = min(remaining, space)
					slot.count += to_add
					remaining -= to_add
					slot_changed.emit(i, slot)
					if remaining <= 0:
						break

	# 2. Second pass: fill empty slots
	if remaining > 0:
		for i in capacity:
			var slot: ItemSlot = slots[i]
			if slot.is_empty():
				var to_add: int = min(remaining, max_stk)
				slot.item_id = p_id
				slot.count = to_add
				slot.custom_data = p_custom_data.duplicate(true)
				remaining -= to_add
				slot_changed.emit(i, slot)
				if remaining <= 0:
					break

	var added: int = p_count - remaining
	if added > 0:
		item_added.emit(p_id, added)
	return remaining


## Removes up to p_count of item_id across all inventory slots.
## Returns the count actually removed.
func remove_item(p_id: StringName, p_count: int) -> int:
	if p_count <= 0 or p_id == &"":
		return 0

	var needed: int = p_count
	# Search in reverse (take from non-hotbar/tail first)
	for i in range(capacity - 1, -1, -1):
		var slot: ItemSlot = slots[i]
		if not slot.is_empty() and slot.item_id == p_id:
			var take: int = min(needed, slot.count)
			slot.count -= take
			needed -= take
			if slot.count <= 0:
				slot.clear()
			slot_changed.emit(i, slot)
			if needed <= 0:
				break

	var removed: int = p_count - needed
	if removed > 0:
		item_removed.emit(p_id, removed)
	return removed


## Removes items specifically from `slot_idx`. If amount <= 0 or amount >= slot.count, clears the slot.
## Returns the actual number of items removed.
func remove_from_slot(slot_idx: int, amount: int = -1) -> int:
	if slot_idx < 0 or slot_idx >= capacity:
		return 0
	var slot: ItemSlot = slots[slot_idx]
	if slot.is_empty():
		return 0
	var p_id: StringName = slot.item_id
	var to_remove: int = slot.count if (amount <= 0 or amount >= slot.count) else amount
	slot.count -= to_remove
	if slot.count <= 0:
		slot.clear()
	slot_changed.emit(slot_idx, slot)
	item_removed.emit(p_id, to_remove)
	return to_remove


## Checks whether inventory contains at least p_count of p_id.
func has_item(p_id: StringName, p_count: int = 1) -> bool:
	return get_item_count(p_id) >= p_count


## Checks whether inventory has room to fit at least p_count of p_id.
func has_space_for(p_id: StringName, p_count: int = 1, p_custom_data: Dictionary = {}) -> bool:
	if p_count <= 0 or p_id == &"":
		return true
	var def: ItemDef = ItemDB.get_item(p_id)
	var max_stk: int = def.max_stack if def else 999
	var remaining: int = p_count

	# 1. Existing non-full matching slots
	if max_stk > 1:
		for i in capacity:
			var slot: ItemSlot = slots[i]
			if not slot.is_empty() and slot.can_stack_with(p_id, p_custom_data):
				remaining -= (max_stk - slot.count)
				if remaining <= 0:
					return true

	# 2. Empty slots
	for i in capacity:
		var slot: ItemSlot = slots[i]
		if slot.is_empty():
			remaining -= max_stk
			if remaining <= 0:
				return true

	return remaining <= 0


## Simulates adding multiple items to determine if the inventory can fit all of them.
## items_to_check: Array of Dictionary {"id": StringName, "count": int}
func can_fit_items(items_to_check: Array) -> bool:
	if items_to_check.is_empty():
		return true
	var sim_slots: Array = []
	for s in slots:
		sim_slots.append({"id": s.item_id, "count": s.count})
	for it in items_to_check:
		var p_id: StringName = StringName(it.get("id", ""))
		var p_count: int = int(it.get("count", 1))
		if p_count <= 0 or p_id == &"":
			continue
		var def := ItemDB.get_item(p_id)
		var max_stk: int = def.max_stack if def != null else 999
		var rem := p_count
		# 1. Existing non-full matching slots
		if max_stk > 1:
			for s in sim_slots:
				if s.id == p_id and s.count < max_stk:
					var space: int = max_stk - s.count
					var put: int = mini(rem, space)
					s.count += put
					rem -= put
					if rem <= 0:
						break
		# 2. Empty slots
		if rem > 0:
			for s in sim_slots:
				if s.id == &"" or s.count <= 0:
					var put: int = mini(rem, max_stk)
					s.id = p_id
					s.count = put
					rem -= put
					if rem <= 0:
						break
		if rem > 0:
			return false
	return true


## Returns total quantity of p_id across all slots.
func get_item_count(p_id: StringName) -> int:
	var total: int = 0
	for slot in slots:
		if not slot.is_empty() and slot.item_id == p_id:
			total += slot.count
	return total


func count_item(p_id: StringName) -> int:
	return get_item_count(p_id)


# -------------------------------------------------------------------------
# Slot Manipulation & Quick Sort
# -------------------------------------------------------------------------

## Swaps slot A and slot B, or merges if stackable.
func swap_or_merge_slots(idx_a: int, idx_b: int) -> bool:
	if idx_a < 0 or idx_a >= capacity or idx_b < 0 or idx_b >= capacity:
		return false
	if idx_a == idx_b:
		return true

	var a: ItemSlot = slots[idx_a]
	var b: ItemSlot = slots[idx_b]

	# Both non-empty and matching: attempt stack merge into B
	if not a.is_empty() and not b.is_empty() and a.can_stack_with(b.item_id, b.custom_data):
		var def: ItemDef = ItemDB.get_item(b.item_id)
		var max_stk: int = def.max_stack if def else 999
		var space: int = max_stk - b.count
		if space > 0:
			var move_count: int = min(a.count, space)
			b.count += move_count
			a.count -= move_count
			if a.count <= 0:
				a.clear()
			slot_changed.emit(idx_a, a)
			slot_changed.emit(idx_b, b)
			return true

	# Standard swap
	var temp_id: StringName = a.item_id
	var temp_cnt: int = a.count
	var temp_data: Dictionary = a.custom_data

	a.item_id = b.item_id
	a.count = b.count
	a.custom_data = b.custom_data

	b.item_id = temp_id
	b.count = temp_cnt
	b.custom_data = temp_data

	slot_changed.emit(idx_a, a)
	slot_changed.emit(idx_b, b)
	return true


## Splits amount from from_idx into to_idx (must be empty).
func split_stack(from_idx: int, to_idx: int, amount: int) -> bool:
	if from_idx < 0 or from_idx >= capacity or to_idx < 0 or to_idx >= capacity:
		return false
	var src: ItemSlot = slots[from_idx]
	var dst: ItemSlot = slots[to_idx]
	if src.is_empty() or amount <= 0 or amount >= src.count:
		return false
	if not dst.is_empty():
		return false

	dst.item_id = src.item_id
	dst.count = amount
	dst.custom_data = src.custom_data.duplicate(true)
	src.count -= amount

	slot_changed.emit(from_idx, src)
	slot_changed.emit(to_idx, dst)
	return true


## Consolidates partial stacks and sorts non-hotbar inventory by category & ID.
## Preserves hotbar slots (0..MAX_HOTBAR_SLOTS - 1) if preserve_hotbar is true.
func quick_sort(preserve_hotbar: bool = true) -> void:
	var start_idx: int = MAX_HOTBAR_SLOTS if preserve_hotbar else 0

	# 1. Consolidate items
	var consolidated: Array[ItemSlot] = []
	for i in range(start_idx, capacity):
		var slot: ItemSlot = slots[i]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			var max_stk: int = def.max_stack if def else 999
			var merged := false
			if max_stk > 1:
				for existing in consolidated:
					if existing.can_stack_with(slot.item_id, slot.custom_data):
						var space: int = max_stk - existing.count
						if space > 0:
							var add_amt: int = min(slot.count, space)
							existing.count += add_amt
							slot.count -= add_amt
							if slot.count <= 0:
								merged = true
								break
			if not merged and slot.count > 0:
				consolidated.append(slot.duplicate_slot())
		slot.clear()

	# 2. Sort by Category, then by Name
	consolidated.sort_custom(func(a: ItemSlot, b: ItemSlot) -> bool:
		var def_a: ItemDef = ItemDB.get_item(a.item_id)
		var def_b: ItemDef = ItemDB.get_item(b.item_id)
		var cat_a: int = def_a.category if def_a else 99
		var cat_b: int = def_b.category if def_b else 99
		if cat_a != cat_b:
			return cat_a < cat_b
		var name_a: String = def_a.name if def_a else String(a.item_id)
		var name_b: String = def_b.name if def_b else String(b.item_id)
		return name_a < name_b
	)

	# 3. Write back into slots
	for i in consolidated.size():
		var slot_idx: int = start_idx + i
		if slot_idx < capacity:
			slots[slot_idx] = consolidated[i]

	for i in range(start_idx, capacity):
		slot_changed.emit(i, slots[i])


# -------------------------------------------------------------------------
# Hotbar & Equipment
# -------------------------------------------------------------------------

func get_active_item() -> ItemSlot:
	if active_hotbar_index < 0 or active_hotbar_index >= MAX_HOTBAR_SLOTS:
		return null
	return slots[active_hotbar_index]


func selected_item_id() -> StringName:
	var active := get_active_item()
	return active.item_id if (active != null and not active.is_empty()) else &""


func set_active_hotbar_index(index: int) -> void:
	var clamped := clampi(index, 0, MAX_HOTBAR_SLOTS - 1)
	if active_hotbar_index != clamped:
		active_hotbar_index = clamped
		active_hotbar_changed.emit(active_hotbar_index)
	else:
		active_hotbar_index = clamped


## Returns true if the active hotbar slot holds a building hammer.
func is_hammer_active() -> bool:
	var active := get_active_item()
	if active == null or active.is_empty():
		return false
	if active.item_id == &"builders_hammer":
		return true
	var def: ItemDef = ItemDB.get_item(active.item_id)
	return def != null and def.has_tag("hammer")


## Moves or swaps a slot from anywhere in the inventory into a hotbar slot (0..7).
## If hotbar_idx < 0, picks the first empty hotbar slot, or active_hotbar_index if full.
func move_to_hotbar(from_idx: int, hotbar_idx: int = -1) -> bool:
	if from_idx < 0 or from_idx >= capacity:
		return false
	var target_hb := hotbar_idx
	if target_hb < 0 or target_hb >= MAX_HOTBAR_SLOTS:
		target_hb = -1
		for i in MAX_HOTBAR_SLOTS:
			if slots[i].is_empty():
				target_hb = i
				break
		if target_hb < 0:
			target_hb = active_hotbar_index
	return swap_or_merge_slots(from_idx, target_hb)


## Shift-click quick transfer between hotbar (0..7) and backpack (8..capacity-1).
func quick_transfer_slot(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= capacity:
		return false
	var src: ItemSlot = slots[slot_idx]
	if src.is_empty():
		return false
	var range_start: int = MAX_HOTBAR_SLOTS if slot_idx < MAX_HOTBAR_SLOTS else 0
	var range_end: int = capacity if slot_idx < MAX_HOTBAR_SLOTS else MAX_HOTBAR_SLOTS
	var def: ItemDef = ItemDB.get_item(src.item_id)
	var max_stk: int = def.max_stack if def else 999
	var moved := false

	# 1. Try stacking into existing matching slots in target range
	if max_stk > 1:
		for i in range(range_start, range_end):
			var dst: ItemSlot = slots[i]
			if not dst.is_empty() and dst.can_stack_with(src.item_id, src.custom_data):
				var space: int = max_stk - dst.count
				if space > 0:
					var amt: int = mini(src.count, space)
					dst.count += amt
					src.count -= amt
					moved = true
					slot_changed.emit(i, dst)
					if src.count <= 0:
						src.clear()
						slot_changed.emit(slot_idx, src)
						return true

	# 2. Move remainder into first empty slot in target range
	if src.count > 0:
		for i in range(range_start, range_end):
			var dst: ItemSlot = slots[i]
			if dst.is_empty():
				dst.item_id = src.item_id
				dst.count = src.count
				dst.custom_data = src.custom_data.duplicate(true)
				src.clear()
				slot_changed.emit(slot_idx, src)
				slot_changed.emit(i, dst)
				return true

	if moved:
		slot_changed.emit(slot_idx, src)
	return moved


## Equips an item from inventory slot into the appropriate equipment slot.
func equip_item_from_slot(slot_idx: int) -> bool:
	if slot_idx < 0 or slot_idx >= capacity:
		return false
	var slot: ItemSlot = slots[slot_idx]
	if slot.is_empty():
		return false

	var def: ItemDef = ItemDB.get_item(slot.item_id)
	if not def or def.equip_slot == &"":
		return false

	var eq_slot_name: StringName = def.equip_slot
	if eq_slot_name == &"chest":
		eq_slot_name = &"body"
	if not equipment.has(eq_slot_name):
		return false

	var current_eq: ItemSlot = equipment[eq_slot_name]

	# Swap slot and equipped item
	var temp_id: StringName = current_eq.item_id
	var temp_cnt: int = current_eq.count
	var temp_data: Dictionary = current_eq.custom_data

	current_eq.item_id = slot.item_id
	current_eq.count = 1
	current_eq.custom_data = slot.custom_data.duplicate(true)

	if slot.count > 1:
		slot.count -= 1
		# If there was an old item equipped, attempt to add it back to inventory
		if temp_id != &"":
			add_item(temp_id, temp_cnt, temp_data)
	else:
		slot.item_id = temp_id
		slot.count = temp_cnt
		slot.custom_data = temp_data

	# Handle backpack capacity changes
	if eq_slot_name == &"backpack":
		var new_cap: int = def.tool_data.get("capacity", DEFAULT_BASE_CAPACITY)
		set_capacity(new_cap)

	slot_changed.emit(slot_idx, slot)
	equipment_changed.emit(eq_slot_name, current_eq)
	return true


func unequip_item(eq_slot_name: StringName) -> bool:
	if eq_slot_name == &"chest":
		eq_slot_name = &"body"
	if not equipment.has(eq_slot_name):
		return false
	var eq: ItemSlot = equipment[eq_slot_name]
	if eq.is_empty():
		return false

	var remainder: int = add_item(eq.item_id, eq.count, eq.custom_data)
	if remainder > 0:
		# Could not fit into inventory
		return false

	eq.clear()
	if eq_slot_name == &"backpack":
		set_capacity(DEFAULT_BASE_CAPACITY)

	equipment_changed.emit(eq_slot_name, eq)
	return true


# -------------------------------------------------------------------------
# Equipment Stat Calculations
# -------------------------------------------------------------------------

## Calculates cumulative defense across equipped items.
func get_total_defense() -> int:
	var total: int = 0
	for slot_name in equipment:
		var slot: ItemSlot = equipment[slot_name]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def:
				total += int(def.armor_data.get("defense", def.tool_data.get("defense", 0)))
	return total


## Calculates cumulative cold/storm protection (0.0 to 1.0).
func get_cold_protection() -> float:
	var total: float = 0.0
	for slot_name in equipment:
		var slot: ItemSlot = equipment[slot_name]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def:
				total += float(def.armor_data.get("cold_protection", 0.0))
	return clampf(total, 0.0, 1.0)


## Maximum safe diving depth before crushing pressure damage starts.
func get_max_safe_depth() -> float:
	var max_depth: float = 15.0 # Base safe depth in meters
	for slot_name in equipment:
		var slot: ItemSlot = equipment[slot_name]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def:
				var item_depth: float = float(def.armor_data.get("max_safe_depth_m", 0.0))
				if item_depth > max_depth:
					max_depth = item_depth
	return max_depth


## Cumulative extra underwater breathing time in seconds.
func get_extra_breath() -> float:
	var extra: float = 0.0
	for slot_name in equipment:
		var slot: ItemSlot = equipment[slot_name]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def:
				extra += float(def.armor_data.get("extra_breath_sec", def.tool_data.get("extra_breath_sec", 0.0)))
	return extra


## Swim speed multiplier (e.g. 1.25 with flippers, 0.35 with lead diving boots).
func get_swim_speed_multiplier() -> float:
	var mult: float = 1.0
	for slot_name in equipment:
		var slot: ItemSlot = equipment[slot_name]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def and def.armor_data.has("swim_speed_mult"):
				mult *= float(def.armor_data["swim_speed_mult"])
	return mult


## Buoyancy offset (< 0.0 causes player to sink like an anchor, > 0.0 floats up).
func get_buoyancy_offset() -> float:
	var offset: float = 0.0
	for slot_name in equipment:
		var slot: ItemSlot = equipment[slot_name]
		if not slot.is_empty():
			var def: ItemDef = ItemDB.get_item(slot.item_id)
			if def and def.armor_data.has("buoyancy_offset"):
				offset += float(def.armor_data["buoyancy_offset"])
	return offset


## Returns currently held weapon (either from active hotbar or main_hand slot).
func get_active_weapon() -> ItemDef:
	var active: ItemSlot = get_active_item()
	if active and not active.is_empty():
		var def: ItemDef = ItemDB.get_item(active.item_id)
		if def and (def.has_tag("weapon") or not def.weapon_data.is_empty()):
			return def
	var hand: ItemSlot = equipment.get(&"main_hand", null)
	if hand and not hand.is_empty():
		return ItemDB.get_item(hand.item_id)
	return null


## Returns true if a nautical map or sea chart is equipped in the map slot, enabling the HUD minimap.
func is_minimap_enabled() -> bool:
	var map_slot: ItemSlot = equipment.get(&"map", null)
	return map_slot != null and not map_slot.is_empty()


## Returns ItemDef of the equipped map/sea chart, or null if none equipped.
func get_equipped_map_def() -> ItemDef:
	var map_slot: ItemSlot = equipment.get(&"map", null)
	if map_slot and not map_slot.is_empty():
		return ItemDB.get_item(map_slot.item_id)
	return null


func set_capacity(new_capacity: int) -> void:
	var target_cap: int = max(MAX_HOTBAR_SLOTS, new_capacity)
	if target_cap == capacity:
		return

	if target_cap > capacity:
		while slots.size() < target_cap:
			slots.append(ItemSlot.new())
	else:
		# If shrinking, drop or shift items that would be cut off
		var cut_items: Array[ItemSlot] = []
		for i in range(target_cap, capacity):
			if not slots[i].is_empty():
				cut_items.append(slots[i].duplicate_slot())
		slots.resize(target_cap)
		capacity = target_cap
		# Attempt to fit cut items back into surviving space
		for it in cut_items:
			add_item(it.item_id, it.count, it.custom_data)

	capacity = target_cap
	inventory_resized.emit(capacity)


# -------------------------------------------------------------------------
# Serialization
# -------------------------------------------------------------------------

func serialize() -> Dictionary:
	var s_slots: Array = []
	for s in slots:
		s_slots.append(s.to_dict())

	var s_equip: Dictionary = {}
	for k in equipment:
		s_equip[String(k)] = equipment[k].to_dict()

	return {
		"capacity": capacity,
		"active_hotbar": active_hotbar_index,
		"slots": s_slots,
		"equipment": s_equip
	}


func deserialize(data: Dictionary) -> bool:
	if not data.has("capacity") or not data.has("slots"):
		return false

	capacity = int(data["capacity"])
	active_hotbar_index = int(data.get("active_hotbar", 0))

	_init_slots()
	var raw_slots: Array = data["slots"]
	for i in min(slots.size(), raw_slots.size()):
		slots[i] = ItemSlot.from_dict(raw_slots[i])

	if data.has("equipment"):
		var raw_eq: Dictionary = data["equipment"]
		for k in raw_eq:
			var slot_name := StringName(k)
			if equipment.has(slot_name):
				equipment[slot_name] = ItemSlot.from_dict(raw_eq[k])

	inventory_resized.emit(capacity)
	for i in capacity:
		slot_changed.emit(i, slots[i])
	return true
