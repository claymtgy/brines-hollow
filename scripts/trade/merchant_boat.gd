class_name MerchantBoat
extends RefCounted
## Visiting merchant boat docked at village piers or beaches.
## Buys player surplus, sells rare wares, and offers export shipping contracts.

signal transaction_completed(item_id: StringName, count: int, is_sale: bool, total_brass: int)
signal contract_fulfilled(contract: TradeContract)

enum MerchantType {
	RAFT_PEDDLER,       ## Beach trader; basic seeds, cloth, crude tools
	TRADE_GALLEON,      ## Pier trader; rare blueprints, diving gear, bulk manifests
	SMUGGLER            ## Appears in thick fog; exotic curios and ancient relics
}

var merchant_name: String = "Raft Peddler Barnaby"
var type: MerchantType = MerchantType.RAFT_PEDDLER
var stock: Inventory
var buying_prices: Dictionary = {}      ## item_id -> unit price in brass
var selling_prices: Dictionary = {}     ## item_id -> unit price in brass
var active_contracts: Array[TradeContract] = []


func _init(p_name: String = "Raft Peddler Barnaby", p_type: MerchantType = MerchantType.RAFT_PEDDLER) -> void:
	merchant_name = p_name
	type = p_type
	stock = Inventory.new(16)
	ItemDB.init_db()
	_init_default_wares()


func _init_default_wares() -> void:
	# Define base purchase and sale rates
	buying_prices = {
		&"driftwood": 1,
		&"stone": 1,
		&"sea_salt": 3,
		&"silver_mackerel": 4,
		&"cliff_salmon": 8,
		&"smoked_fish_ration": 12,
		&"shore_wheat": 3,
		&"samphire": 4,
		&"tide_kale": 4,
		&"root_potato": 5,
		&"shore_crab": 6,
		&"chitin_plate": 20
	}

	selling_prices = {
		&"seed_shore_wheat": 2,
		&"seed_samphire": 3,
		&"seed_tide_kale": 3,
		&"seed_root_potato": 4,
		&"iron_ingot": 15,
		&"sea_brass_ingot": 25,
		&"backpack_driftwood": 80,
		&"diving_rebreather": 150,
		&"blueprint_dry_dock": 100,
		&"exotic_spice": 45,
		&"dye_indigo": 35,
		&"silk_bolt": 60,
		# Recipe scrolls (read on pickup -> learned; see RecipeBook)
		&"recipe_scroll_cook_glazed_crab": 30,
		&"recipe_scroll_place_barber_mirror": 24,
		&"recipe_scroll_cook_bouillabaisse": 36,
		&"recipe_scroll_brew_chicory_coffee": 28,
	}
	RecipeBook.register_scroll_items()

	# Stock initial merchandise
	match type:
		MerchantType.RAFT_PEDDLER:
			stock.add_item(&"seed_shore_wheat", 10)
			stock.add_item(&"seed_samphire", 5)
			stock.add_item(&"iron_ingot", 4)
			stock.add_item(&"recipe_scroll_cook_glazed_crab", 1)
			stock.add_item(&"recipe_scroll_place_barber_mirror", 1)
		MerchantType.TRADE_GALLEON:
			stock.add_item(&"sea_brass_ingot", 10)
			stock.add_item(&"backpack_driftwood", 1)
			stock.add_item(&"diving_rebreather", 1)
			stock.add_item(&"blueprint_dry_dock", 1)
			stock.add_item(&"exotic_spice", 10)
			stock.add_item(&"dye_indigo", 10)
			stock.add_item(&"silk_bolt", 5)
			stock.add_item(&"recipe_scroll_cook_bouillabaisse", 1)
			stock.add_item(&"recipe_scroll_brew_chicory_coffee", 1)
			# Add shipping manifests
			active_contracts.append(TradeContract.new(
				&"manifest_cured_fish", "Export: 10 Smoked Fish",
				{&"smoked_fish_ration": 10}, 140, 10
			))
			active_contracts.append(TradeContract.new(
				&"manifest_coastal_timber", "Export: 30 Wood Planks",
				{&"wood_plank": 30}, 90, 5
			))
			active_contracts.append(TradeContract.new(
				&"manifest_artisan_dairy", "Export: 4 Salt-Cured Goat Cheese & 4 Honey",
				{&"goat_cheese": 4, &"marsh_honey": 4}, 280, 20
			))
			active_contracts.append(TradeContract.new(
				&"manifest_borean_trophy", "Export: 2 Glacial Tusks & 2 Borean Fur",
				{&"glacial_tusk": 2, &"borean_fur": 2}, 500, 40
			))
			active_contracts.append(TradeContract.new(
				&"manifest_pearl_consignment", "Export: 2 Black Abyssal Pearls",
				{&"abyssal_pearl": 2}, 650, 50
			))


## Player buys an item from the merchant using Brass Guilders.
func buy_item(item_id: StringName, count: int, player_inv: Inventory) -> bool:
	if not stock.has_item(item_id, count) or not selling_prices.has(item_id):
		return false

	var unit_price: int = int(selling_prices[item_id])
	var total_cost: int = unit_price * count

	if not player_inv.has_item(&"brass_guilder", total_cost):
		return false

	# Deduct currency
	player_inv.remove_item(&"brass_guilder", total_cost)

	# Transfer item from merchant to player
	stock.remove_item(item_id, count)
	player_inv.add_item(item_id, count)

	transaction_completed.emit(item_id, count, false, total_cost)
	return true


## Player sells an item from their inventory to the merchant for Brass Guilders.
func sell_item(item_id: StringName, count: int, player_inv: Inventory) -> int:
	if not player_inv.has_item(item_id, count) or not buying_prices.has(item_id):
		return 0

	var unit_price: int = int(buying_prices[item_id])
	var total_payout: int = unit_price * count

	# Transfer items from player
	player_inv.remove_item(item_id, count)
	player_inv.add_item(&"brass_guilder", total_payout)

	transaction_completed.emit(item_id, count, true, total_payout)
	return total_payout


## Player completes an export shipping manifest.
func fulfill_contract(contract_id: StringName, player_inv: Inventory) -> bool:
	for c in active_contracts:
		if c.id == contract_id and not c.is_fulfilled:
			if c.fulfill(player_inv):
				contract_fulfilled.emit(c)
				return true
	return false
