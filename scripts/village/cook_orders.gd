class_name CookOrders
extends RefCounted
## Standing meal orders for the village cook (a Smoker & Cook villager).
##
## The player sets how many of each meal the town should keep in store. While on shift,
## the cook takes ingredients from the town's stores (pantry barrels, the stockpile chest,
## the depot), cooks at the town's pots and fires, and puts the dishes back in store
## until every meal is at its target.

const MAX_TARGET := 60
const STEP := 5
const LOW_FUEL_SEC := 30.0      ## the cook feeds the fire below this

var targets: Dictionary = {}    ## meal item id -> how many to keep in store
## Station cell key -> {item id: count} the cook put on that fire and will collect.
var pending: Dictionary = {}


# ------------------------------------------------------------------ orders

func target(item_id: StringName) -> int:
	return int(targets.get(item_id, 0))


func set_target(item_id: StringName, n: int) -> void:
	n = clampi(n, 0, MAX_TARGET)
	if n <= 0:
		targets.erase(item_id)
	else:
		targets[item_id] = n


func has_orders() -> bool:
	return not targets.is_empty()


## Meals a cook can make: timed recipes at a cooking station that make food.
## With a recipe book, only the ones the town knows.
static func meal_recipes(book: RecipeBook = null) -> Array[RecipeDef]:
	var out: Array[RecipeDef] = []
	var seen := {}
	for r: RecipeDef in RecipeDB.get_all_recipes():
		if not CraftingStation.is_cooking_station(r.required_station) or not CraftingStation.is_timed(r):
			continue
		var it: ItemDef = ItemDB.get_item(r.output_item_id)
		if it == null or it.category != ItemDef.Category.FOOD or seen.has(r.output_item_id):
			continue
		if book != null and not book.knows(r.id):
			continue
		seen[r.output_item_id] = true
		out.append(r)
	return out


static func recipe_for(item_id: StringName, book: RecipeBook = null) -> RecipeDef:
	for r in meal_recipes(book):
		if r.output_item_id == item_id:
			return r
	return null


# ------------------------------------------------------------------ stores

static func count_in(stores: Array, item_id: StringName) -> int:
	var n := 0
	for inv: Inventory in stores:
		if inv != null:
			n += inv.get_item_count(item_id)
	return n


func pending_count(item_id: StringName) -> int:
	var n := 0
	for k: String in pending:
		n += int((pending[k] as Dictionary).get(item_id, 0))
	return n


## How many short of the target, counting dishes already on the fire.
func shortfall(item_id: StringName, stores: Array) -> int:
	return maxi(0, target(item_id) - count_in(stores, item_id) - pending_count(item_id))


## What's missing to cook one batch from the stores ("" when everything is there).
static func missing(r: RecipeDef, stores: Array) -> String:
	for inp: Dictionary in r.inputs:
		var id := StringName(inp.get("item_id", &""))
		var need := int(inp.get("count", 1))
		if count_in(stores, id) < need:
			return ItemSlotView.item_name(id)
	return ""


## Moves one batch of ingredients from the stores into `into`. All or nothing.
static func take_ingredients(r: RecipeDef, stores: Array, into: Inventory) -> bool:
	if missing(r, stores) != "":
		return false
	for inp: Dictionary in r.inputs:
		var id := StringName(inp.get("item_id", &""))
		var left := int(inp.get("count", 1))
		for inv: Inventory in stores:
			if left <= 0:
				break
			if inv != null:
				var got := inv.remove_item(id, mini(left, inv.get_item_count(id)))
				left -= got
				into.add_item(id, got)
	return true


## Puts items into the first store with room. Returns how many didn't fit.
static func store(stores: Array, item_id: StringName, count: int) -> int:
	var left := count
	for inv: Inventory in stores:
		if left <= 0:
			break
		if inv != null:
			left = inv.add_item(item_id, left)
	return left


## The meal this station should cook next, or null: the one furthest below its target
## that the stores have ingredients for.
func next_meal(station_tag: StringName, stores: Array, book: RecipeBook = null) -> RecipeDef:
	var best: RecipeDef = null
	var best_score := 0.0
	for item_id: StringName in targets:
		var short := shortfall(item_id, stores)
		if short <= 0:
			continue
		var r := recipe_for(item_id, book)
		if r == null or r.required_station != station_tag or missing(r, stores) != "":
			continue
		var score := float(short) / float(maxi(1, target(item_id)))
		if score > best_score:
			best_score = score
			best = r
	return best


## One line for the orders screen: how this meal is going.
func status(item_id: StringName, stores: Array, book: RecipeBook = null) -> String:
	if target(item_id) <= 0:
		return "Not ordered"
	var on_fire := pending_count(item_id)
	if count_in(stores, item_id) >= target(item_id):
		return "Stocked"
	if on_fire > 0:
		return "Cooking %d" % on_fire
	var r := recipe_for(item_id, book)
	if r == null:
		return "Recipe unknown"
	var m := missing(r, stores)
	if m != "":
		return "Needs %s in store" % m
	return "Waiting for the cook"


# ------------------------------------------------------------------ cooking

## The cook's turn at one station: collect what's done, feed the fire, start the next meal.
## Returns the recipe started, or null.
func work_station(st: CraftingStation, key: String, stores: Array, book: RecipeBook = null) -> RecipeDef:
	collect(st, key, stores)
	if st.requires_fuel and st.fuel_remaining_sec < LOW_FUEL_SEC:
		for inv: Inventory in stores:
			if inv != null and st.recharge_from_inventory(inv).get("recharged", false):
				break
	if st.is_active or st.queue_full() or not st.is_fueled():
		return null
	var r := next_meal(st.station_id, stores, book)
	if r == null:
		return null
	var hands := Inventory.new(8)
	if not take_ingredients(r, stores, hands):
		return null
	if not st.craft_recipe(r.id, hands, 1):
		for s: ItemSlot in hands.slots:   # give it all back
			if s != null and not s.is_empty():
				store(stores, s.item_id, s.count)
		return null
	var mine: Dictionary = pending.get(key, {})
	mine[r.output_item_id] = int(mine.get(r.output_item_id, 0)) + r.output_count
	pending[key] = mine
	return r


## Moves this cook's finished dishes from the station's tray into the stores
## (only the cook's own: a player's dish stays for them). Returns how many were stored.
func collect(st: CraftingStation, key: String, stores: Array) -> int:
	if not pending.has(key):
		return 0
	var mine: Dictionary = pending[key]
	var moved := 0
	for item_id: StringName in mine.keys():
		var n := mini(int(mine[item_id]), int(st.output.get(item_id, 0)))
		if n <= 0:
			continue
		var left := store(stores, item_id, n)
		var put := n - left
		moved += put
		st.output[item_id] = int(st.output[item_id]) - put
		if int(st.output[item_id]) <= 0:
			st.output.erase(item_id)
			st.output_batches.erase(item_id)
		mine[item_id] = int(mine[item_id]) - put
		if int(mine[item_id]) <= 0:
			mine.erase(item_id)
	# Nothing on the fire and nothing of ours left in the tray: forget the station.
	if mine.is_empty() or (not st.is_active and st.queue.is_empty() and _none_in_tray(st, mine)):
		pending.erase(key)
	return moved


static func _none_in_tray(st: CraftingStation, mine: Dictionary) -> bool:
	for item_id: StringName in mine:
		if int(st.output.get(item_id, 0)) > 0:
			return false
	return true


static func key_for(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]


# ------------------------------------------------------------------ save

func serialize() -> Dictionary:
	var t := {}
	for k: StringName in targets:
		t[String(k)] = int(targets[k])
	var p := {}
	for k: String in pending:
		var m := {}
		for id: StringName in pending[k]:
			m[String(id)] = int(pending[k][id])
		p[k] = m
	return {"targets": t, "pending": p}


func deserialize(d: Dictionary) -> void:
	targets.clear()
	pending.clear()
	var t: Dictionary = d.get("targets", {})
	for k in t:
		set_target(StringName(k), int(t[k]))
	var p: Dictionary = d.get("pending", {})
	for k in p:
		var m := {}
		for id in p[k]:
			m[StringName(id)] = int(p[k][id])
		pending[String(k)] = m
