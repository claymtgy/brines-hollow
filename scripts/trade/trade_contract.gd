class_name TradeContract
extends Resource
## Shipping export manifest contract for visiting merchant galleons.

@export var id: StringName = &""
@export var title: String = ""
@export var required_items: Dictionary = {} ## item_id -> required_count
@export var payout_brass: int = 50
@export var payout_scrip: int = 5
@export var is_fulfilled: bool = false


func _init(
	p_id: StringName = &"",
	p_title: String = "",
	p_reqs: Dictionary = {},
	p_brass: int = 50,
	p_scrip: int = 5
) -> void:
	id = p_id
	title = p_title
	required_items = p_reqs.duplicate(true)
	payout_brass = p_brass
	payout_scrip = p_scrip
	is_fulfilled = false


func can_fulfill(inv: Inventory) -> bool:
	if is_fulfilled:
		return false
	for item_id in required_items:
		var needed: int = int(required_items[item_id])
		if not inv.has_item(StringName(item_id), needed):
			return false
	return true


func fulfill(inv: Inventory) -> bool:
	if not can_fulfill(inv):
		return false

	# Consume required goods from inventory
	for item_id in required_items:
		var needed: int = int(required_items[item_id])
		inv.remove_item(StringName(item_id), needed)

	# Payout currency rewards
	if payout_brass > 0:
		inv.add_item(&"brass_guilder", payout_brass)
	if payout_scrip > 0:
		inv.add_item(&"tide_scrip", payout_scrip)

	is_fulfilled = true
	return true


func serialize() -> Dictionary:
	return {
		"id": String(id),
		"title": title,
		"reqs": required_items.duplicate(true),
		"brass": payout_brass,
		"scrip": payout_scrip,
		"done": is_fulfilled
	}


static func deserialize(d: Dictionary) -> TradeContract:
	var c := TradeContract.new(
		StringName(d.get("id", "")),
		d.get("title", ""),
		d.get("reqs", {}),
		int(d.get("brass", 50)),
		int(d.get("scrip", 5))
	)
	c.is_fulfilled = bool(d.get("done", false))
	return c
