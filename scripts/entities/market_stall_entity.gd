class_name MarketStallEntity
extends WorldEntity
## A town market stall managed by the Town Purser.
## Automatically exports village surplus goods for Brass Guilders, depositing revenue into the Community Chest.

signal item_sold(item_id: StringName, count: int, revenue: int)
signal revenue_collected(amount: int)

const U := VoxelWorld.VS * 0.5

const COMMODITY_PRICES := {
	&"smoked_fish_ration": 4,
	&"aged_cheese": 8,
	&"vintage_ale": 7,
	&"sea_wool": 4,
	&"salt_milk": 3,
	&"sea_egg": 3,
	&"silver_mackerel": 2,
	&"tidepool_flounder": 3,
	&"shore_wheat": 2,
	&"tide_kale": 2,
	&"sea_salt": 3,
	&"sea_glass": 5,
	&"marsh_honey": 6,
	&"wood_plank": 2,
	&"cobblestone": 2,
	&"chitin_plate": 8
}

var container: StorageContainer
var assigned_purser_id: StringName = &""
var purser_name: String = "Town Purser"
var accumulated_brass: int = 0
var sales_timer: float = 0.0
const SALES_INTERVAL_SEC: float = 30.0


func _init(p_coord: Vector3i = Vector3i.ZERO) -> void:
	super._init(&"market_stall", "Village Market Stall", p_coord)
	entity_type = EntityType.CONTAINER
	size = Vector3(10, 8, 8) * U
	solid = true
	container = StorageContainer.new("Market Stall Inventory", 18)


## Stocks an item for sale in the market stall
func stock_item(item_id: StringName, count: int) -> int:
	var remainder := container.deposit(item_id, count)
	state_changed.emit()
	return count - remainder


## Assigns a drifter as the town purser
func assign_purser(drifter_id: StringName, name: String) -> void:
	assigned_purser_id = drifter_id
	purser_name = name
	state_changed.emit()


## Simulates sales ticks. Sells surplus goods for Brass Guilders.
## If community_chest is provided, revenue is deposited directly into the chest!
func tick_market(delta_sec: float, community_chest: ChestEntity = null) -> int:
	sales_timer += delta_sec
	if sales_timer < SALES_INTERVAL_SEC:
		return 0

	sales_timer = 0.0
	var total_earned := 0

	for slot in container.inventory.slots:
		if not slot.is_empty():
			var item_id := slot.item_id
			var price: int = COMMODITY_PRICES.get(item_id, 2)
			var sold := container.withdraw(item_id, 1)
			if sold > 0:
				var earned := price * sold
				total_earned += earned
				accumulated_brass += earned
				item_sold.emit(item_id, sold, earned)

				if community_chest != null:
					community_chest.deposit_supplies(&"brass_guilder", earned)

				state_changed.emit()
				break # Sell 1 item per sales interval

	return total_earned


## Collects all accumulated brass into the interacting player's inventory
func collect_brass(player: Player) -> int:
	if accumulated_brass <= 0:
		return 0
	var payout := accumulated_brass
	accumulated_brass = 0
	if player.inventory != null:
		player.inventory.add_item(&"brass_guilder", payout)
	revenue_collected.emit(payout)
	state_changed.emit()
	return payout


func _build_visuals() -> void:
	# Timber counter with striped canvas awning and display produce baskets
	var g := Prefabs.Grid.new(10, 8, 8)
	# Heavy timber counter base
	g.box(1, 0, 1, 8, 3, 6, Palette.DARK_WOOD)
	g.box(0, 3, 0, 9, 3, 7, Palette.PLANK) # Countertop
	# Awning support poles
	for x in [0, 9]:
		for z in [0, 7]:
			g.box(x, 3, z, x, 7, z, Palette.DARK_WOOD)
	# Striped awning roof (White & Blue)
	for x in 10:
		var col := Palette.WHITEWASH if (x / 2) % 2 == 0 else Palette.ROOF_BLUE
		g.box(x, 7, 0, x, 7, 7, col)
	# Display baskets on counter
	g.box(2, 4, 2, 4, 4, 3, Palette.FLOWER_Y)
	g.box(6, 4, 2, 7, 4, 3, Palette.ROOF_RED)
	_mesh_instance = _voxel_model(g)


func get_interaction_prompt(player: Player) -> String:
	var stock_count := 0
	for slot in container.inventory.slots:
		if not slot.is_empty():
			stock_count += slot.count
	var payout_text := ""
	if accumulated_brass > 0:
		payout_text = "    Shift+F Collect %d Brass" % accumulated_brass
	return "F Trade / Stock Market Stall · %d Items for Sale · Purser: %s%s" % [stock_count, purser_name, payout_text]


func client_interact(player: Player) -> void:
	interacted.emit(player)
	if Input.is_action_pressed("sprint") and accumulated_brass > 0:
		collect_brass(player)
		return
	# Deposit active item into market stall
	var active := player.inventory.get_active_item() if player.inventory != null else null
	if active != null and not active.is_empty():
		var deposited := stock_item(active.item_id, mini(active.count, 5))
		if deposited > 0:
			player.inventory.remove_item(active.item_id, deposited)


func serialize() -> Dictionary:
	return {
		"assigned_purser_id": String(assigned_purser_id),
		"purser_name": purser_name,
		"accumulated_brass": accumulated_brass,
		"inventory": container.serialize()
	}


func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	assigned_purser_id = StringName(data.get("assigned_purser_id", ""))
	purser_name = data.get("purser_name", "Town Purser")
	accumulated_brass = int(data.get("accumulated_brass", 0))
	if data.has("inventory"):
		container.deserialize(data["inventory"])
