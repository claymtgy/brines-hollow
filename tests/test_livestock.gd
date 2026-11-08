extends SceneTree
## Headless test suite for Livestock (pens, feed, yields, herding):
##   cmd /c "C:\Users\claym\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe --headless --path . -s tests/test_livestock.gd"

const LivestockAnimalClass := preload("res://scripts/livestock/livestock_animal.gd")
const LivestockManagerClass := preload("res://scripts/livestock/livestock_manager.gd")
const TroughEntityClass := preload("res://scripts/entities/trough_entity.gd")
const CoopEntityClass := preload("res://scripts/entities/coop_entity.gd")

var passed := 0
var total := 0


func check(cond: bool, label: String) -> void:
	total += 1
	if cond:
		passed += 1
		print("  [PASS] ", label)
	else:
		push_error("  [FAIL] " + label)
		print("  [FAIL] ", label)


class MockMain:
	extends Node
	var player = null
	var entities = null


func _initialize() -> void:
	print("==================================================")
	print("Running Livestock (Husbandry, Yields & Herding) Tests...")
	print("==================================================")

	ItemDB.init_db()
	RecipeDB.init_db()
	Placeables.register_builtin()

	# -------------------------------------------------------------------------
	# 1. Test ItemDB & RecipeDB Registrations
	# -------------------------------------------------------------------------
	print("\n--- 1. Testing Livestock Items & Recipes ---")
	check(ItemDB.has_item(&"salt_milk"), "Item salt_milk registered in ItemDB")
	check(ItemDB.has_item(&"sea_wool"), "Item sea_wool registered in ItemDB")
	check(ItemDB.has_item(&"sea_egg"), "Item sea_egg registered in ItemDB")
	check(ItemDB.has_item(&"down_feather"), "Item down_feather registered in ItemDB")
	check(ItemDB.has_item(&"goat_cheese"), "Item goat_cheese registered in ItemDB")
	check(ItemDB.has_item(&"shearing_shears"), "Item shearing_shears registered in ItemDB")
	check(ItemDB.has_item(&"wooden_bucket"), "Item wooden_bucket registered in ItemDB")
	check(ItemDB.has_item(&"animal_whistle"), "Item animal_whistle registered in ItemDB")
	check(ItemDB.has_item(&"feed_trough"), "Item feed_trough registered in ItemDB")
	check(ItemDB.has_item(&"poultry_coop"), "Item poultry_coop registered in ItemDB")

	var milk_item: ItemDef = ItemDB.get_item(&"salt_milk")
	check(milk_item != null and milk_item.food_data.has("hp_bonus") and milk_item.food_data["hp_bonus"] > 0, "salt_milk has valid food buff")
	var cheese_item: ItemDef = ItemDB.get_item(&"goat_cheese")
	check(cheese_item != null and cheese_item.food_data.has("regen_hp_sec") and cheese_item.food_data["regen_hp_sec"] > 0.0, "goat_cheese has health regeneration buff")

	check(RecipeDB.has_recipe(&"craft_shearing_shears"), "Recipe craft_shearing_shears registered")
	check(RecipeDB.has_recipe(&"craft_wooden_bucket"), "Recipe craft_wooden_bucket registered")
	check(RecipeDB.has_recipe(&"craft_animal_whistle"), "Recipe craft_animal_whistle registered")
	check(RecipeDB.has_recipe(&"craft_feed_trough"), "Recipe craft_feed_trough registered")
	check(RecipeDB.has_recipe(&"craft_poultry_coop"), "Recipe craft_poultry_coop registered")
	check(RecipeDB.has_recipe(&"cure_goat_cheese"), "Recipe cure_goat_cheese registered")

	# -------------------------------------------------------------------------
	# 2. Test TroughEntity (Feed, Water, Animal Consumption & Rain)
	# -------------------------------------------------------------------------
	print("\n--- 2. Testing TroughEntity ---")
	var trough = TroughEntityClass.new(Vector3i(10, 0, 10))
	check(trough.entity_id == &"feed_trough", "TroughEntity has correct entity_id")
	check(not trough.has_feed() and not trough.has_water(), "Trough starts empty of feed and water")

	# Add feed
	var feed_res: Dictionary = trough.server_action(&"add_feed", {"item": &"shore_wheat"})
	check(feed_res.get("ok", false) and trough.feed_count > 0, "Adding shore_wheat to trough succeeds")
	check(trough.has_feed(), "trough.has_feed() is true after stocking")

	# Add water
	var water_res: Dictionary = trough.server_action(&"add_water", {})
	check(water_res.get("ok", false) and trough.water_count > 0, "Adding water to trough succeeds")
	check(trough.has_water(), "trough.has_water() is true after filling")

	# Animals consume feed and water
	var prev_feed: int = trough.feed_count
	var prev_water: int = trough.water_count
	check(trough.consume_feed(), "consume_feed() consumes 1 feed")
	check(trough.feed_count == prev_feed - 1, "feed_count decremented correctly")
	check(trough.consume_water(), "consume_water() consumes 1 water")
	check(trough.water_count == prev_water - 1, "water_count decremented correctly")

	# Trough serialization round-trip
	var trough_data: Dictionary = trough.serialize()
	var trough2 = TroughEntityClass.new(Vector3i(10, 0, 10))
	trough2.deserialize(trough_data)
	check(trough2.feed_count == trough.feed_count and trough2.water_count == trough.water_count, "Trough state round-trips via serialize/deserialize")

	# -------------------------------------------------------------------------
	# 3. Test CoopEntity (Feed, Egg & Feather Production, Collection)
	# -------------------------------------------------------------------------
	print("\n--- 3. Testing CoopEntity ---")
	var coop = CoopEntityClass.new(Vector3i(-10, 0, 10))
	check(coop.entity_id == &"poultry_coop", "CoopEntity has correct entity_id")
	check(coop.feed_count > 0, "Coop starts with starter feed for poultry")
	check(coop.egg_count == 0 and coop.feather_count == 0, "Coop starts with 0 uncollected eggs/feathers")

	# Simulate time to produce eggs and feathers
	coop.server_tick(150.0)
	check(coop.egg_count > 0 or coop.feather_count > 0, "Coop server_tick produces eggs and down feathers when fed")

	# Collect yield
	var collect_res: Dictionary = coop.server_action(&"collect", {})
	check(collect_res.get("ok", false), "Coop collect action succeeds")
	check(coop.egg_count == 0 and coop.feather_count == 0, "Coop nest boxes cleared after collection")
	check(collect_res.get("grant", []).size() > 0, "Coop collection grants items")

	# Coop serialization round-trip
	coop.egg_count = 3
	coop.feather_count = 2
	var coop_data: Dictionary = coop.serialize()
	var coop2 = CoopEntityClass.new(Vector3i(-10, 0, 10))
	coop2.deserialize(coop_data)
	check(coop2.egg_count == 3 and coop2.feather_count == 2, "Coop egg/feather state survives serialize/deserialize")

	# -------------------------------------------------------------------------
	# 4. Test Salt-Goat (Needs, Petting, Hand-feeding, Milking)
	# -------------------------------------------------------------------------
	print("\n--- 4. Testing Salt-Goat ---")
	var goat = LivestockAnimalClass.new(&"salt_goat", "Barnaby")
	check(goat.species == &"salt_goat", "Goat has salt_goat species")
	check(goat.animal_name == "Barnaby", "Goat has custom name Barnaby")
	check(goat.visual_root != null, "Goat visual root generated")

	# Player mock with inventory
	var player := Player.new()
	player.inventory = Inventory.new(16)
	var inv: Inventory = player.inventory

	# Petting
	var prev_happy: float = goat.happiness
	check(goat.can_pet(), "Goat can be petted initially")
	var pet_res: Dictionary = goat.interact(player)
	check(pet_res.get("ok", false), "Petting goat succeeds")
	check(goat.happiness > prev_happy, "Petting goat increases happiness")
	check(not goat.can_pet(), "Petting places pet interaction on cooldown")

	# Hand-feeding
	inv.add_item(&"shore_wheat", 5)
	inv.set_active_hotbar_index(0) # active slot is shore_wheat
	goat.hunger = 40.0
	var prev_goat_hunger: float = goat.hunger
	var feed_res_goat: Dictionary = goat.interact(player)
	check(feed_res_goat.get("ok", false), "Hand-feeding goat with shore_wheat succeeds")
	check(goat.hunger > prev_goat_hunger, "Hand-feeding restored goat hunger")
	check(inv.get_item_count(&"shore_wheat") == 4, "Consumed 1 shore_wheat from player inventory")

	# Milking
	player.inventory = Inventory.new(16)
	inv = player.inventory
	inv.add_item(&"wooden_bucket", 1)
	inv.set_active_hotbar_index(0) # active slot is wooden_bucket
	goat.yield_timer = 0.0 # Ready to milk
	goat.hunger = 80.0
	goat.thirst = 80.0
	check(goat.is_milk_ready(), "Goat is_milk_ready() is true when hydrated, fed, and timer <= 0")

	var milk_res: Dictionary = goat.interact(player)
	check(milk_res.get("ok", false), "Milking goat with wooden_bucket succeeds")
	check(inv.get_item_count(&"salt_milk") == 1, "Player received 1 salt_milk in inventory")
	check(inv.get_item_count(&"wooden_bucket") == 0, "Wooden bucket converted to filled milk bucket")
	check(not goat.is_milk_ready(), "Goat is no longer milk ready (yield timer reset)")
	check(goat.yield_timer > 0.0, "Yield timer reset to full cooldown")

	# -------------------------------------------------------------------------
	# 5. Test Shore-Sheep (Wool Coat, Shearing, Wool Regrowth)
	# -------------------------------------------------------------------------
	print("\n--- 5. Testing Shore-Sheep ---")
	var sheep = LivestockAnimalClass.new(&"shore_sheep", "Daisy")
	check(sheep.species == &"shore_sheep", "Sheep has shore_sheep species")
	check(sheep.wool_grown, "Shore-Sheep starts with fully grown wool fleece")
	check(sheep.wool_mesh != null and sheep.wool_mesh.visible, "Sheep wool mesh is visible")
	check(sheep.is_shear_ready(), "is_shear_ready() is true when wool_grown")

	# Shearing with shears
	player.inventory = Inventory.new(16)
	inv = player.inventory
	inv.add_item(&"shearing_shears", 1)
	inv.set_active_hotbar_index(0) # active slot is shearing_shears

	var shear_res: Dictionary = sheep.interact(player)
	check(shear_res.get("ok", false), "Shearing sheep with shearing_shears succeeds")
	check(not sheep.wool_grown, "sheep.wool_grown is false after shearing")
	check(sheep.wool_mesh != null and not sheep.wool_mesh.visible, "Sheep wool mesh is hidden after shearing")
	check(inv.get_item_count(&"sea_wool") >= 2, "Player received sea_wool in inventory")
	check(inv.get_item_count(&"shearing_shears") == 1, "Shears are retained as reusable tool")

	# Wool regrowth simulation
	sheep.hunger = 90.0
	sheep.thirst = 90.0
	sheep.simulate(190.0, null)
	check(sheep.wool_grown, "Wool regrew after elapsed simulation time while fed")
	check(sheep.wool_mesh != null and sheep.wool_mesh.visible, "Wool mesh becomes visible again once regrown")

	# -------------------------------------------------------------------------
	# 6. Test Shore-Duck & Coop Integration
	# -------------------------------------------------------------------------
	print("\n--- 6. Testing Shore-Duck ---")
	var duck = LivestockAnimalClass.new(&"shore_duck", "Pip")
	check(duck.species == &"shore_duck", "Duck has shore_duck species")
	check(duck.wing_l != null and duck.wing_r != null, "Duck has articulated flapping wings")

	# -------------------------------------------------------------------------
	# 7. Test Herding Mechanics & Shepherd's Whistle
	# -------------------------------------------------------------------------
	print("\n--- 7. Testing Herding Mechanics & Shepherd's Whistle ---")
	var mgr = LivestockManagerClass.new()
	var main_mock := MockMain.new()
	main_mock.player = player
	mgr.main = main_mock

	var goat1 = mgr.spawn_animal(&"salt_goat", Vector3(5, 0, 0), "G1")
	var sheep1 = mgr.spawn_animal(&"shore_sheep", Vector3(10, 0, 0), "S1")
	var duck1 = mgr.spawn_animal(&"shore_duck", Vector3(15, 0, 0), "D1")

	# Sound Shepherd's Whistle at player position (0, 0, 0)
	player.position = Vector3.ZERO
	var alerted_count: int = mgr.sound_whistle(player.position)
	check(alerted_count == 3, "Sounding Shepherd's Whistle alerted all 3 livestock within 25m")
	check(goat1.state == LivestockAnimalClass.State.FOLLOW, "Goat entered FOLLOW state")
	check(sheep1.state == LivestockAnimalClass.State.FOLLOW, "Sheep entered FOLLOW state")
	check(duck1.state == LivestockAnimalClass.State.FOLLOW, "Duck entered FOLLOW state")

	# Holding shore_wheat also maintains herding
	player.inventory = Inventory.new(16)
	player.inventory.add_item(&"shore_wheat", 3)
	player.inventory.set_active_hotbar_index(0)
	goat1.simulate(0.5, main_mock)
	check(goat1.state == LivestockAnimalClass.State.FOLLOW, "Holding shore_wheat keeps livestock following player")

	# -------------------------------------------------------------------------
	# 8. Test LivestockManager Save & Load Round-Trip
	# -------------------------------------------------------------------------
	print("\n--- 8. Testing LivestockManager Save / Load ---")
	goat1.hunger = 72.0
	goat1.happiness = 88.0
	sheep1.wool_grown = false

	var mgr_saved: Dictionary = mgr.serialize()
	check(mgr_saved.has("animals") and mgr_saved["animals"].size() == 3, "Serialized manager contains 3 animals")

	var mgr2 = LivestockManagerClass.new()
	mgr2.main = main_mock
	mgr2.deserialize(mgr_saved)
	check(mgr2.animals.size() == 3, "Deserialized manager restored all 3 animals")

	var restored_goat = mgr2.animals[0]
	check(restored_goat.species == &"salt_goat", "Restored animal 1 has species salt_goat")
	check(is_equal_approx(restored_goat.hunger, 72.0), "Restored animal hunger preserved")
	check(is_equal_approx(restored_goat.happiness, 88.0), "Restored animal happiness preserved")
	check(not mgr2.animals[1].wool_grown, "Restored sheep shorn state preserved")

	print("==================================================")
	print("Tests finished: %d / %d passed" % [passed, total])
	print("==================================================")
	quit(0 if passed == total else 1)
