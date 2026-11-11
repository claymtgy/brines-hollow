class_name ItemUses
extends RefCounted
## What an item is good for, in plain words: eating, burning, wearing, placing, building,
## baiting, planting, selling, and which recipes take it. Shared by the screens that
## describe items (the Crafting page shows it under "Used for").


## Short lines like "Eat: +25 health, +25 stamina for 15 min". Recipes aren't included:
## see recipes_using().
static func lines(item_id: StringName) -> Array[String]:
	var out: Array[String] = []
	var def: ItemDef = ItemDB.get_item(item_id)
	if def == null:
		return out
	if not def.food_data.is_empty():
		var hp := int(def.food_data.get("hp_bonus", 0))
		var st := int(def.food_data.get("stamina_bonus", 0))
		var mins := roundi(float(def.food_data.get("duration_sec", 900.0)) / 60.0)
		var parts: Array[String] = []
		if hp > 0:
			parts.append("+%d health" % hp)
		if st > 0:
			parts.append("+%d stamina" % st)
		var extra := ""
		if def.food_data.get("cold_immunity", false):
			extra = ", keeps out the cold"
		elif float(def.food_data.get("swim_speed", 1.0)) > 1.0:
			extra = ", swim faster"
		out.append("Eat: %s for %d min%s" % [", ".join(parts) if not parts.is_empty() else "a light snack", mins, extra])
	elif def.category == ItemDef.Category.FOOD:
		out.append("Food: cook it into a meal")
	if CraftingStation.FUEL_BURN_TIMES.has(item_id):
		out.append("Fuel: burns %d s in a fire or smokehouse" % int(CraftingStation.FUEL_BURN_TIMES[item_id]))
	if item_id == &"fish_oil":
		out.append("Lamp oil: refills the lighthouse lamp for a day")
	if Placeables.is_bait(item_id):
		out.append("Bait: hook it on your rod for better bites")
	if def.has_tag("seed"):
		out.append("Plant it in a tilled farm plot")
	if def.equip_slot != &"":
		var slot := String(&"body" if def.equip_slot == &"chest" else def.equip_slot).capitalize()
		out.append("Wear it: %s slot" % slot)
	if not def.weapon_data.is_empty():
		out.append("Weapon: hold it in your hotbar to fight")
	elif def.category == ItemDef.Category.TOOL:
		out.append("Tool: hold it in your hotbar to use")
	if EntityManager.type_for_item(item_id) != &"" or def.has_tag("placeable"):
		out.append("Place it in the world (item tool, 5)")
	var blocks := building_blocks(item_id)
	if not blocks.is_empty():
		var shown := ", ".join(blocks.slice(0, 3)) + (" +%d" % (blocks.size() - 3) if blocks.size() > 3 else "")
		out.append("Building: pays for %s block%s" % [shown, "" if blocks.size() == 1 else "s"])
	if def.value_brass > 1:
		out.append("Trade: worth about %d Brass Guilders" % def.value_brass)
	return out


## Block names this item pays for when building (1 item per 4 blocks).
static func building_blocks(item_id: StringName) -> Array[String]:
	var out: Array[String] = []
	var def: ItemDef = ItemDB.get_item(item_id)
	if def != null and def.is_voxel():
		out.append(def.name)
	for m: int in BuildCosts.STAND_INS:
		if BuildCosts.STAND_INS[m] == item_id:
			var n: String = String(Palette.NAMES[m]) if m >= 0 and m < Palette.NAMES.size() else ""
			if n != "" and not out.has(n):
				out.append(n)
	return out


## Recipes that take this item: {"known": Array[RecipeDef], "locked": int}.
## `knows` is a Callable(RecipeDef) -> bool; empty = all known.
static func recipes_using(item_id: StringName, knows: Callable = Callable()) -> Dictionary:
	var known: Array[RecipeDef] = []
	var locked := 0
	for r: RecipeDef in RecipeDB.get_all_recipes():
		for inp: Dictionary in r.inputs:
			if StringName(inp.get("item_id", &"")) == item_id:
				if not knows.is_valid() or knows.call(r):
					known.append(r)
				else:
					locked += 1
				break
	return {"known": known, "locked": locked}


## One-paragraph summary, for tooltips.
static func summary(item_id: StringName, knows: Callable = Callable()) -> String:
	var all := lines(item_id)
	var rec := recipes_using(item_id, knows)
	var names: Array[String] = []
	for r: RecipeDef in rec.known:
		names.append(r.name)
	if not names.is_empty():
		all.append("Ingredient in %s" % _join_short(names, 4))
	if int(rec.locked) > 0:
		all.append("…and %d recipe%s you haven't learned" % [rec.locked, "" if rec.locked == 1 else "s"])
	if all.is_empty():
		return "%s: no other uses yet." % ItemSlotView.item_name(item_id)
	return "%s\n%s" % [ItemSlotView.item_name(item_id), "\n".join(all)]


static func _join_short(names: Array[String], n: int) -> String:
	if names.size() <= n:
		return ", ".join(names)
	return "%s and %d more" % [", ".join(names.slice(0, n)), names.size() - n]
