class_name CraftingUI
extends CanvasLayer
## Recipe window for a station (or hand crafting with Tab). Lists the recipes the player
## knows, shows ingredients (have / need), and how many are still undiscovered.

var main: Node
var station_ent: StationEntity = null      # null = hand crafting
var _hand := CraftingStation.new(&"none", "Hand Crafting", false)
var _root: Control
var _title: Label
var _list: VBoxContainer
var _footer: Label
var _open := false


func setup(p_main: Node) -> void:
	main = p_main
	layer = 18
	if not InputMap.has_action("craft_menu"):
		InputMap.add_action("craft_menu")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_TAB
		InputMap.action_add_event("craft_menu", k)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.prepare(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.10, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 520)
	center.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	_title = Label.new()
	_title.theme_type_variation = &"Header"
	_title.add_theme_font_size_override("font_size", 28)
	v.add_child(_title)
	var page := PanelContainer.new()
	page.theme_type_variation = &"Parchment"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(page)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	var foot := HBoxContainer.new()
	v.add_child(foot)
	_footer = Label.new()
	_footer.theme_type_variation = &"Small"
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD
	_footer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_footer)
	var close_b := Button.new()
	close_b.text = "Close"
	close_b.pressed.connect(close)
	foot.add_child(close_b)


func is_open() -> bool:
	return _open


func open(ent: StationEntity) -> void:
	station_ent = ent
	_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if main.player != null:
		main.player.input_enabled = false
	refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	_root.visible = false
	if main.player != null:
		main.player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(e: InputEvent) -> void:
	if not _open:
		if e.is_action_pressed("craft_menu") and main.player != null and main.player.input_enabled \
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			open(null)
			get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("craft_menu") or e.is_action_pressed("menu_toggle"):
		close()
		get_viewport().set_input_as_handled()


func _station() -> CraftingStation:
	return station_ent.station if station_ent != null else _hand


func refresh() -> void:
	if not _open:
		return
	var p: Player = main.player
	var st := _station()
	_title.text = station_ent.entity_name if station_ent != null else "Hand Crafting"
	for c in _list.get_children():
		c.queue_free()
	var book: RecipeBook = p.recipes
	var info := book.recipes_for(st.station_id)
	if st.is_active and st.active_recipe != null:
		var busy := Label.new()
		busy.theme_type_variation = &"InkLabel"
		busy.text = "Working on %s... (%ds left)" % [st.active_recipe.name, int(ceil(st.total_cook_time - st.cook_timer))]
		_list.add_child(busy)
	if station_ent != null and st.requires_fuel:
		var fuel := HBoxContainer.new()
		var fl := Label.new()
		fl.theme_type_variation = &"InkLabel"
		fl.text = "Fuel: %ds" % int(st.fuel_remaining_sec)
		fl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fuel.add_child(fl)
		var fb := Button.new()
		fb.text = "Add fuel"
		fb.pressed.connect(_add_fuel)
		fuel.add_child(fb)
		_list.add_child(fuel)
	for r: RecipeDef in info.known:
		_list.add_child(_recipe_row(r, p.inventory, st))
	if info.known.is_empty():
		var none := Label.new()
		none.theme_type_variation = &"InkLabel"
		none.text = "You don't know any recipes for this yet."
		_list.add_child(none)
	_footer.text = ("%d more recipe%s to discover here: find new ingredients, recruit drifters, finish quests, or buy recipe scrolls." % [
		info.hidden, "" if info.hidden == 1 else "s"]) if info.hidden > 0 else "You know every recipe here."


func _recipe_row(r: RecipeDef, inv: Inventory, st: CraftingStation) -> Control:
	var h := HBoxContainer.new()
	var slot := PanelContainer.new()
	slot.theme_type_variation = &"Slot"
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(UiTheme.icon(ItemIcons.for_item(r.output_item_id), 40))
	h.add_child(slot)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var nm := Label.new()
	nm.theme_type_variation = &"InkLabel"
	nm.add_theme_font_override("font", UiTheme.font(800))
	nm.text = r.name + (" x%d" % r.output_count if r.output_count > 1 else "")
	v.add_child(nm)
	var ing := HBoxContainer.new()
	ing.add_theme_constant_override("separation", 4)
	v.add_child(ing)
	for i in r.inputs:
		var id: StringName = i.get("item_id", &"")
		var need := int(i.get("count", 1))
		var have := inv.get_item_count(id)
		ing.add_child(UiTheme.icon(ItemIcons.for_item(id), 24))
		var l := Label.new()
		l.theme_type_variation = &"InkLabel"
		l.add_theme_font_size_override("font_size", 14)
		l.text = "%d/%d" % [mini(have, need), need]
		l.add_theme_color_override("font_color", Color8(66, 46, 34) if have >= need else Color8(170, 52, 40))
		ing.add_child(l)
	var b := Button.new()
	b.text = "Craft" if r.craft_time_sec <= 0.0 else "Craft (%ds)" % int(r.craft_time_sec)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = not r.can_craft_with(inv) or st.is_active or (st.requires_fuel and st.fuel_remaining_sec <= 0.0 and r.craft_time_sec > 0.0)
	b.pressed.connect(func() -> void: _craft(r))
	h.add_child(b)
	return h


func _craft(r: RecipeDef) -> void:
	var p: Player = main.player
	var st := _station()
	if station_ent == null:
		# Hand crafting is instant: consume and give.
		if not r.consume_ingredients(p.inventory):
			return
		p.inventory.add_item(r.output_item_id, r.output_count)
		main.hud.show_toast("Crafted %s" % r.name)
	else:
		if not st.craft_recipe(r.id, p.inventory):
			main.hud.show_toast("Can't craft that right now")
			return
		station_ent.recipe_crafted.emit(r.id, 1)
		if station_ent.manager != null:
			station_ent.manager.push_state(station_ent)
		main.hud.show_toast(("Started %s (%ds)" % [r.name, int(r.craft_time_sec)]) if r.craft_time_sec > 0.0 else "Crafted %s" % r.name)
	p.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, r.output_item_id)
	refresh()


func _add_fuel() -> void:
	var p: Player = main.player
	var st := _station()
	for fuel: StringName in CraftingStation.FUEL_BURN_TIMES.keys():
		if p.inventory.has_item(fuel, 1) and st.add_fuel_from_inventory(p.inventory, fuel, 1) > 0:
			if station_ent != null and station_ent.manager != null:
				station_ent.manager.push_state(station_ent)
			refresh()
			return
	main.hud.show_toast("You need driftwood or planks to burn")


func _process(_delta: float) -> void:
	if _open and station_ent != null and station_ent.station.is_active and Engine.get_process_frames() % 20 == 0:
		refresh()
