class_name RecipeDef
extends Resource
## Data-driven recipe definition for Brine's Hollow crafting and culinary cooking.
## Defines input ingredients, station requirements, crafting time, and output yields.

enum Category {
	BASIC,          ## Hand-craftable anywhere in the field
	WORKBENCH,      ## Carpentry, tools, and construction furniture
	COOKING,        ## Hearth pots, cauldrons, and campfire skillets
	SMOKEHOUSE,     ## Curing and smoking seafood for long shelf-life
	SALTERY,        ## Brine preservation and pickling
	BREWING,        ## Herbal infusions, teas, and tonics
	FORGE           ## Smelting ores and forging maritime weapons/armor
}

@export var id: StringName = &""
@export var name: String = ""
@export var description: String = ""
@export var category: Category = Category.BASIC
@export var required_station: StringName = &"none" ## &"none", &"workbench", &"campfire", &"hearth_pot", &"smokehouse", &"saltery", &"brewery", &"forge"

## Array of ingredient dictionaries: [{"item_id": &"driftwood", "count": 2}]
@export var inputs: Array[Dictionary] = []

@export var output_item_id: StringName = &""
@export var output_count: int = 1
@export var craft_time_sec: float = 0.0            ## 0.0 = instant; > 0.0 = processing/cook timer
@export var tags: PackedStringArray = []


func _init(
	p_id: StringName = &"",
	p_name: String = "",
	p_category: Category = Category.BASIC,
	p_station: StringName = &"none",
	p_inputs: Array[Dictionary] = [],
	p_output_id: StringName = &"",
	p_output_count: int = 1,
	p_craft_time: float = 0.0,
	p_tags: PackedStringArray = PackedStringArray()
) -> void:
	id = p_id
	name = p_name
	category = p_category
	required_station = p_station
	inputs = p_inputs
	output_item_id = p_output_id
	output_count = p_output_count
	craft_time_sec = p_craft_time
	tags = p_tags


## Checks if the given inventory contains all required input ingredients.
func can_craft_with(inv: Inventory) -> bool:
	if inv == null:
		return false
	if inv.get("creative_mode") == true:
		return true
	for ingredient in inputs:
		var req_id: StringName = ingredient.get("item_id", &"")
		var req_count: int = int(ingredient.get("count", 1))
		if inv.get_item_count(req_id) < req_count:
			return false
	return true


## Consumes required ingredients from inventory. Returns true if successful.
func consume_ingredients(inv: Inventory) -> bool:
	if not can_craft_with(inv):
		return false
	if inv.get("creative_mode") == true:
		return true
	for ingredient in inputs:
		var req_id: StringName = ingredient.get("item_id", &"")
		var req_count: int = int(ingredient.get("count", 1))
		inv.remove_item(req_id, req_count)
	return true
