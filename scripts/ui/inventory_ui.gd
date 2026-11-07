class_name InventoryUI
extends CanvasLayer
## Full-screen Inventory, Hotbar Configuration, Equipment Paperdoll, Hand-Crafting & Container UI
## (inspired by Minecraft, Valheim, and Necesse).
##
## Controls:
##   I / Tab          Open / close inventory
##   Left-click       Pick up / place / swap / merge stack
##   Shift + Click    Quick-transfer between Backpack and Hotbar (or active Storage Container)
##   Keys 1-8         Assign hovered or selected inventory slot directly to Hotbar slot 1-8
##   Right-click      Equip gear / move tool to hotbar / eat food / split stack in half

signal inventory_closed

const EQUIP_SLOTS := [
	[&"head", "Head"],
	[&"body", "Body"],
	[&"legs", "Legs"],
	[&"boots", "Boots"],
	[&"backpack", "Backpack"],
	[&"main_hand", "Weapon"],
	[&"accessory", "Accessory"],
	[&"map", "Sea Chart"],
]

var main: Node
var player: Player
var active_container: ChestEntity = null
var active_station: StationEntity = null
var _station_tab: StringName = &"none"
var _station_tabs_box: HFlowContainer

var _root: Control
var _title_label: Label
var _equip_grid: GridContainer
var _stats_label: Label
var _hotbar_grid: GridContainer
var _backpack_label: Label
var _backpack_grid: GridContainer
var _inspect_icon: TextureRect
var _inspect_title: Label
var _inspect_desc: Label
var _inspect_actions: HBoxContainer
var _right_sub_title: Label
var _craft_list: VBoxContainer
var _container_scroll: ScrollContainer
var _container_grid: GridContainer
var _cursor_floater: Control
var _cursor_icon: TextureRect
var _cursor_count: Label
var _hover_panel: PanelContainer
var _hover_title: Label
var _hover_sub: Label

var _held_slot_idx: int = -1
var _selected_slot_idx: int = 0
var _hovered_slot_idx: int = -1
var _field_station: CraftingStation = CraftingStation.new(&"none", "Field Crafting")


func _ready() -> void:
	layer = 16
	_build()
	visible = false


func setup(p_main: Node) -> void:
	main = p_main


func is_open() -> bool:
	return visible


func toggle(container_entity: ChestEntity = null) -> void:
	if visible:
		close()
	else:
		open(container_entity)


func open(container_entity: ChestEntity = null) -> void:
	if main != null and main.player != null:
		player = main.player
	if player == null or player.inventory == null:
		return
	active_container = container_entity
	active_station = null
	var nearby := _get_nearby_stations()
	if not nearby.is_empty():
		active_station = nearby[0]
		_station_tab = active_station.station_tag
	else:
		_station_tab = &"none"
	_held_slot_idx = -1
	_selected_slot_idx = player.inventory.active_hotbar_index
	visible = true
	_bind_inventory_signals()
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false


func open_station(station_entity: StationEntity) -> void:
	if main != null and main.player != null:
		player = main.player
	if player == null or player.inventory == null:
		return
	active_container = null
	active_station = station_entity
	_station_tab = station_entity.station_tag if station_entity != null else &"none"
	_held_slot_idx = -1
	_selected_slot_idx = player.inventory.active_hotbar_index
	visible = true
	_bind_inventory_signals()
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false


func close() -> void:
	if not visible:
		return
	visible = false
	_held_slot_idx = -1
	active_container = null
	active_station = null
	if _cursor_floater != null:
		_cursor_floater.visible = false
	if _hover_panel != null:
		_hover_panel.visible = false
	if player != null:
		player.input_enabled = true
		player._sync_tool_from_hotbar()
	if main == null or (main.settings_menu == null or not main.settings_menu.is_open()):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	inventory_closed.emit()


func _bind_inventory_signals() -> void:
	if player == null or player.inventory == null:
		return
	var inv: Inventory = player.inventory
	if not inv.slot_changed.is_connected(_on_inv_changed):
		inv.slot_changed.connect(_on_inv_changed)
	if not inv.equipment_changed.is_connected(_on_equip_changed):
		inv.equipment_changed.connect(_on_equip_changed)
	if not inv.inventory_resized.is_connected(_on_inv_resized):
		inv.inventory_resized.connect(_on_inv_resized)


func _on_inv_changed(_idx: int, _slot: ItemSlot) -> void:
	if visible:
		refresh()


func _on_equip_changed(_slot_name: StringName, _slot: ItemSlot) -> void:
	if visible:
		refresh()


func _on_inv_resized(_new_cap: int) -> void:
	if visible:
		refresh()


func _process(_delta: float) -> void:
	if not visible or _cursor_floater == null:
		return
	if _hover_panel != null and _hover_panel.visible:
		var mp := get_viewport().get_mouse_position()
		var vp_sz := get_viewport().get_visible_rect().size
		var ps := _hover_panel.size
		_hover_panel.position = Vector2(
			clampf(mp.x + 18.0, 8.0, maxf(8.0, vp_sz.x - ps.x - 8.0)),
			clampf(mp.y + 18.0, 8.0, maxf(8.0, vp_sz.y - ps.y - 8.0))
		)
	if _held_slot_idx >= 0 and player != null and _held_slot_idx < player.inventory.capacity:
		var s: ItemSlot = player.inventory.slots[_held_slot_idx]
		if not s.is_empty():
			_cursor_floater.visible = true
			_cursor_floater.position = get_viewport().get_mouse_position() + Vector2(14, 14)
			_cursor_icon.texture = ItemIcons.for_item(s.item_id)
			_cursor_count.text = str(s.count) if s.count > 1 else ""
			return
	_held_slot_idx = -1
	_cursor_floater.visible = false


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("inventory_toggle") or e.is_action_pressed("menu_toggle"):
		get_viewport().set_input_as_handled()
		close()
		return
	# Number keys 1-8 assign hovered (or selected) slot directly to Hotbar 0-7
	if e is InputEventKey and e.pressed and not e.echo:
		var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if kc >= KEY_1 and kc <= KEY_8:
			var hb_idx: int = kc - KEY_1
			var src_idx: int = _hovered_slot_idx if _hovered_slot_idx >= 0 else (_held_slot_idx if _held_slot_idx >= 0 else _selected_slot_idx)
			if player != null and src_idx >= 0 and src_idx < player.inventory.capacity:
				player.inventory.swap_or_merge_slots(src_idx, hb_idx)
				player.select_hotbar_slot(hb_idx)
				_selected_slot_idx = hb_idx
				_held_slot_idx = -1
				refresh()
				get_viewport().set_input_as_handled()


# -------------------------------------------------------------------------
# UI Construction
# -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	UiTheme.prepare(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.10, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(1040, 610)
	center.add_child(outer)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 10)
	outer.add_child(main_v)

	# --- Top Header Bar
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	main_v.add_child(head)

	_title_label = Label.new()
	_title_label.text = "Inventory & Gear"
	_title_label.theme_type_variation = &"Header"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "Click: Move/Swap  ·  Shift+Click: Hotbar <-> Bag  ·  Keys 1-8: Assign Hotbar  ·  RMB: Equip/Use"
	hint_lbl.theme_type_variation = &"Small"
	hint_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint_lbl)

	var sort_btn := Button.new()
	sort_btn.text = "Sort Bag"
	sort_btn.pressed.connect(func() -> void:
		if player and player.inventory:
			player.inventory.quick_sort(true)
			refresh()
	)
	head.add_child(sort_btn)

	var close_btn := Button.new()
	close_btn.text = "Close (I)"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	# --- 3-Column Body
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	main_v.add_child(cols)

	# 1. Left Column: Equipment Paperdoll + Stats
	var left_page := PanelContainer.new()
	left_page.theme_type_variation = &"Parchment"
	left_page.custom_minimum_size = Vector2(235, 0)
	cols.add_child(left_page)
	var left_v := VBoxContainer.new()
	left_v.add_theme_constant_override("separation", 8)
	left_page.add_child(left_v)

	var eq_head := Label.new()
	eq_head.text = "Equipment"
	eq_head.theme_type_variation = &"InkLabel"
	eq_head.add_theme_font_override("font", UiTheme.font(800))
	eq_head.add_theme_font_size_override("font_size", 20)
	left_v.add_child(eq_head)

	_equip_grid = GridContainer.new()
	_equip_grid.columns = 2
	_equip_grid.add_theme_constant_override("h_separation", 8)
	_equip_grid.add_theme_constant_override("v_separation", 6)
	left_v.add_child(_equip_grid)

	left_v.add_child(HSeparator.new())

	var st_head := Label.new()
	st_head.text = "Mariners' Stats"
	st_head.theme_type_variation = &"InkLabel"
	st_head.add_theme_font_override("font", UiTheme.font(800))
	st_head.add_theme_font_size_override("font_size", 18)
	left_v.add_child(st_head)

	_stats_label = Label.new()
	_stats_label.theme_type_variation = &"InkLabel"
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_v.add_child(_stats_label)

	# 2. Center Column: Configurable Hotbar (0..7) + Backpack Grid (8..N)
	var center_page := PanelContainer.new()
	center_page.theme_type_variation = &"Parchment"
	center_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(center_page)
	var center_v := VBoxContainer.new()
	center_v.add_theme_constant_override("separation", 8)
	center_page.add_child(center_v)

	var hb_title := Label.new()
	hb_title.text = "Hotbar (Keys 1-8) — Put tools, weapons, blocks & items here"
	hb_title.theme_type_variation = &"InkLabel"
	hb_title.add_theme_font_override("font", UiTheme.font(800))
	hb_title.add_theme_font_size_override("font_size", 18)
	center_v.add_child(hb_title)

	_hotbar_grid = GridContainer.new()
	_hotbar_grid.columns = Inventory.MAX_HOTBAR_SLOTS
	_hotbar_grid.add_theme_constant_override("h_separation", 6)
	_hotbar_grid.add_theme_constant_override("v_separation", 6)
	center_v.add_child(_hotbar_grid)

	center_v.add_child(HSeparator.new())

	_backpack_label = Label.new()
	_backpack_label.text = "Backpack"
	_backpack_label.theme_type_variation = &"InkLabel"
	_backpack_label.add_theme_font_override("font", UiTheme.font(800))
	_backpack_label.add_theme_font_size_override("font_size", 18)
	center_v.add_child(_backpack_label)

	var bag_scroll := ScrollContainer.new()
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center_v.add_child(bag_scroll)

	_backpack_grid = GridContainer.new()
	_backpack_grid.columns = 8
	_backpack_grid.add_theme_constant_override("h_separation", 6)
	_backpack_grid.add_theme_constant_override("v_separation", 6)
	bag_scroll.add_child(_backpack_grid)

	# 3. Right Column: Selected Item Inspector + Field Crafting / Storage Container
	var right_page := PanelContainer.new()
	right_page.theme_type_variation = &"Parchment"
	right_page.custom_minimum_size = Vector2(275, 0)
	cols.add_child(right_page)
	var right_v := VBoxContainer.new()
	right_v.add_theme_constant_override("separation", 8)
	right_page.add_child(right_v)

	var insp_head := HBoxContainer.new()
	insp_head.add_theme_constant_override("separation", 8)
	right_v.add_child(insp_head)
	_inspect_icon = UiTheme.icon(null, 40)
	insp_head.add_child(_inspect_icon)
	_inspect_title = Label.new()
	_inspect_title.theme_type_variation = &"InkLabel"
	_inspect_title.add_theme_font_override("font", UiTheme.font(800))
	_inspect_title.add_theme_font_size_override("font_size", 18)
	_inspect_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	insp_head.add_child(_inspect_title)

	_inspect_desc = Label.new()
	_inspect_desc.theme_type_variation = &"InkLabel"
	_inspect_desc.add_theme_font_size_override("font_size", 14)
	_inspect_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_desc.custom_minimum_size = Vector2(0, 58)
	right_v.add_child(_inspect_desc)

	_inspect_actions = HBoxContainer.new()
	_inspect_actions.add_theme_constant_override("separation", 6)
	right_v.add_child(_inspect_actions)

	right_v.add_child(HSeparator.new())

	_right_sub_title = Label.new()
	_right_sub_title.text = "Hand Crafting"
	_right_sub_title.theme_type_variation = &"InkLabel"
	_right_sub_title.add_theme_font_override("font", UiTheme.font(800))
	_right_sub_title.add_theme_font_size_override("font_size", 18)
	right_v.add_child(_right_sub_title)

	_station_tabs_box = HFlowContainer.new()
	_station_tabs_box.add_theme_constant_override("h_separation", 4)
	_station_tabs_box.add_theme_constant_override("v_separation", 4)
	right_v.add_child(_station_tabs_box)

	var craft_scroll := ScrollContainer.new()
	craft_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	craft_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_v.add_child(craft_scroll)

	_craft_list = VBoxContainer.new()
	_craft_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_craft_list.add_theme_constant_override("separation", 6)
	craft_scroll.add_child(_craft_list)

	_container_scroll = ScrollContainer.new()
	_container_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_container_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_container_scroll.visible = false
	right_v.add_child(_container_scroll)

	_container_grid = GridContainer.new()
	_container_grid.columns = 4
	_container_grid.add_theme_constant_override("h_separation", 6)
	_container_grid.add_theme_constant_override("v_separation", 6)
	_container_scroll.add_child(_container_grid)

	# Floating cursor icon when dragging/moving a stack
	_cursor_floater = Control.new()
	_cursor_floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_floater.visible = false
	_root.add_child(_cursor_floater)
	_cursor_icon = UiTheme.icon(null, 44)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_floater.add_child(_cursor_icon)
	_cursor_count = Label.new()
	_cursor_count.theme_type_variation = &"KeyLabel"
	_cursor_count.position = Vector2(24, 24)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_floater.add_child(_cursor_count)

	# Floating hover tooltip label when hovering over any slot
	_hover_panel = PanelContainer.new()
	_hover_panel.theme_type_variation = &"Toast"
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.visible = false
	_hover_panel.z_index = 50
	_root.add_child(_hover_panel)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 2)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_child(hv)
	_hover_title = Label.new()
	_hover_title.add_theme_font_override("font", UiTheme.font(800))
	_hover_title.add_theme_font_size_override("font_size", 15)
	_hover_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_hover_title)
	_hover_sub = Label.new()
	_hover_sub.theme_type_variation = &"Small"
	_hover_sub.add_theme_font_size_override("font_size", 12)
	_hover_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hv.add_child(_hover_sub)


func _show_hover_label(item_id: StringName, count: int, prefix: String = "") -> void:
	if _hover_panel == null:
		return
	if item_id == &"":
		_hover_panel.visible = false
		return
	var def: ItemDef = ItemDB.get_item(item_id)
	var title_txt := def.name if def != null else String(item_id)
	if count > 1:
		title_txt += " (x%d)" % count
	if prefix != "":
		title_txt = "%s: %s" % [prefix, title_txt]
	_hover_title.text = title_txt

	var sub_parts: Array[String] = []
	if def != null:
		var cat_names := ["Material", "Food", "Tool", "Equipment", "Blueprint", "Special"]
		var cat_str: String = cat_names[clampi(def.category, 0, cat_names.size() - 1)]
		var tier_val: int = int(def.tool_data.get("tier", 0))
		if tier_val > 0:
			sub_parts.append("Tier %d %s" % [tier_val, cat_str])
		else:
			sub_parts.append(cat_str)
		if def.has_tag("pickaxe"):
			sub_parts.append("Mines stone & ores")
		elif def.has_tag("axe"):
			sub_parts.append("Chops trees & timber")
		elif def.has_tag("shovel"):
			sub_parts.append("Excavates dirt, sand & gravel")
		elif def.has_tag("hammer"):
			sub_parts.append("Opens Build Menu (Prefabs & Blocks)")
		elif def.has_tag("hoe"):
			sub_parts.append("Tills soil & harvests crops")
		elif def.has_tag("fishing_rod"):
			sub_parts.append("Casts line into tidal waters")
		elif not def.weapon_data.is_empty():
			sub_parts.append("%d DMG" % int(def.weapon_data.get("damage", 10)))
		elif not def.armor_data.is_empty():
			sub_parts.append("+%d Defense" % int(def.armor_data.get("defense", 0)))
		elif not def.food_data.is_empty():
			sub_parts.append("+%d HP / +%d Stamina" % [int(def.food_data.get("hp_bonus", 0)), int(def.food_data.get("stamina_bonus", 0))])
		elif def.is_voxel():
			sub_parts.append("Placeable Block")
	_hover_sub.text = "  ·  ".join(sub_parts)
	_hover_sub.visible = not sub_parts.is_empty()
	_hover_panel.reset_size()
	_hover_panel.visible = true
	var mp := get_viewport().get_mouse_position()
	_hover_panel.position = mp + Vector2(18.0, 18.0)


func _hide_hover_label() -> void:
	if _hover_panel != null:
		_hover_panel.visible = false


# -------------------------------------------------------------------------
# Refresh & Slot Rendering
# -------------------------------------------------------------------------

func refresh() -> void:
	if player == null or player.inventory == null:
		return
	var inv: Inventory = player.inventory
	_title_label.text = ("Inventory  ·  %s" % active_container.entity_name) if active_container != null else "Inventory & Gear"

	# 1. Equipment slots
	for c in _equip_grid.get_children():
		c.queue_free()
	for pair: Array in EQUIP_SLOTS:
		var slot_key: StringName = pair[0]
		var slot_label: String = pair[1]
		var eq_slot: ItemSlot = inv.equipment.get(slot_key, ItemSlot.new())
		_equip_grid.add_child(_make_equip_cell(slot_key, slot_label, eq_slot))

	# 2. Character stats
	_stats_label.text = (
		"Defense: %d\n" % inv.get_total_defense() +
		"Cold Protection: %d%%\n" % int(round(inv.get_cold_protection() * 100.0)) +
		"Safe Dive Depth: %.0f m\n" % inv.get_max_safe_depth() +
		"Bonus Breath: +%.0f s\n" % inv.get_extra_breath() +
		"Swim Speed: %.0f%%\n" % int(round(inv.get_swim_speed_multiplier() * 100.0)) +
		"Capacity: %d slots" % inv.capacity
	)

	# 3. Hotbar (0..7)
	for c in _hotbar_grid.get_children():
		c.queue_free()
	for i in Inventory.MAX_HOTBAR_SLOTS:
		_hotbar_grid.add_child(_make_inv_slot(i, inv.slots[i], true))

	# 4. Backpack (8..capacity-1)
	for c in _backpack_grid.get_children():
		c.queue_free()
	var used_bag := 0
	for i in range(Inventory.MAX_HOTBAR_SLOTS, inv.capacity):
		if not inv.slots[i].is_empty():
			used_bag += 1
		_backpack_grid.add_child(_make_inv_slot(i, inv.slots[i], false))
	_backpack_label.text = "Backpack (%d / %d slots used)" % [used_bag, inv.capacity - Inventory.MAX_HOTBAR_SLOTS]

	# 5. Inspector
	_refresh_inspector(inv)

	# 6. Hand-crafting OR Container view
	var has_cont := active_container != null and is_instance_valid(active_container)
	_craft_list.get_parent().visible = not has_cont
	_container_scroll.visible = has_cont
	if has_cont:
		if _station_tabs_box != null:
			_station_tabs_box.visible = false
		_right_sub_title.text = active_container.entity_name
		_refresh_container()
	else:
		_right_sub_title.text = "Hand Crafting"
		_refresh_hand_crafting(inv)


func _make_inv_slot(idx: int, slot: ItemSlot, is_hotbar: bool) -> PanelContainer:
	var p := PanelContainer.new()
	var is_sel := (idx == _held_slot_idx) or (is_hotbar and idx == player.inventory.active_hotbar_index) or (idx == _selected_slot_idx)
	p.theme_type_variation = &"SlotSelected" if is_sel else &"Slot"
	p.custom_minimum_size = Vector2(56, 56)
	p.mouse_filter = Control.MOUSE_FILTER_STOP

	var box := Control.new()
	box.custom_minimum_size = Vector2(44, 44)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(box)

	if not slot.is_empty():
		var ic := UiTheme.icon(ItemIcons.for_item(slot.item_id), 42)
		ic.position = Vector2(1, 1)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(ic)
		var def: ItemDef = ItemDB.get_item(slot.item_id)
		p.tooltip_text = "%s (x%d)" % [def.name if def else String(slot.item_id), slot.count]
		if slot.count > 1:
			var cnt := Label.new()
			cnt.text = str(slot.count)
			cnt.theme_type_variation = &"KeyLabel"
			cnt.add_theme_font_size_override("font_size", 13)
			cnt.position = Vector2(20, 26)
			cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(cnt)
	else:
		p.tooltip_text = "Hotbar %d (Empty)" % (idx + 1) if is_hotbar else "Backpack Slot (Empty)"

	if is_hotbar:
		var key_lbl := Label.new()
		key_lbl.text = str(idx + 1)
		key_lbl.theme_type_variation = &"KeyLabel"
		key_lbl.add_theme_font_size_override("font_size", 12)
		key_lbl.position = Vector2(-4, -6)
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(key_lbl)

	p.mouse_entered.connect(func() -> void:
		_hovered_slot_idx = idx
		p.theme_type_variation = &"SlotSelected"
		p.self_modulate = Color(1.08, 1.04, 0.94)
		if not slot.is_empty():
			_show_hover_label(slot.item_id, slot.count)
		else:
			_hide_hover_label()
	)
	p.mouse_exited.connect(func() -> void:
		p.theme_type_variation = &"SlotSelected" if is_sel else &"Slot"
		p.self_modulate = Color.WHITE
		if _hovered_slot_idx == idx:
			_hovered_slot_idx = -1
			_hide_hover_label()
	)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		_on_slot_gui_input(ev, idx)
	)
	return p


func _make_equip_cell(slot_key: StringName, label_text: String, slot: ItemSlot) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"SlotSelected" if not slot.is_empty() else &"Slot"
	p.custom_minimum_size = Vector2(96, 54)
	p.mouse_filter = Control.MOUSE_FILTER_STOP

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var ic := UiTheme.icon(ItemIcons.for_item(slot.item_id) if not slot.is_empty() else null, 34)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var cat := Label.new()
	cat.text = label_text
	cat.theme_type_variation = &"Small"
	cat.add_theme_font_size_override("font_size", 11)
	cat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cat)

	var item_lbl := Label.new()
	var def: ItemDef = ItemDB.get_item(slot.item_id) if not slot.is_empty() else null
	item_lbl.text = def.name if def != null else "Empty"
	item_lbl.add_theme_font_size_override("font_size", 11)
	item_lbl.clip_text = true
	item_lbl.custom_minimum_size = Vector2(44, 16)
	item_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(item_lbl)

	p.tooltip_text = ("%s: %s (Click to unequip)" % [label_text, def.name]) if def else ("%s Slot (Empty)" % label_text)
	p.mouse_entered.connect(func() -> void:
		p.theme_type_variation = &"SlotSelected"
		p.self_modulate = Color(1.08, 1.04, 0.94)
		if not slot.is_empty():
			_show_hover_label(slot.item_id, 1, label_text)
		else:
			_hide_hover_label()
	)
	p.mouse_exited.connect(func() -> void:
		p.theme_type_variation = &"SlotSelected" if not slot.is_empty() else &"Slot"
		p.self_modulate = Color.WHITE
		_hide_hover_label()
	)
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_on_equip_slot_clicked(slot_key)
	)
	return p


func _on_equip_slot_clicked(slot_key: StringName) -> void:
	if player == null or player.inventory == null:
		return
	var inv: Inventory = player.inventory
	# If holding an item on the cursor that equips to this slot, equip it
	if _held_slot_idx >= 0 and _held_slot_idx < inv.capacity:
		var held: ItemSlot = inv.slots[_held_slot_idx]
		if not held.is_empty():
			var def: ItemDef = ItemDB.get_item(held.item_id)
			if def != null and (def.equip_slot == slot_key or (def.equip_slot == &"chest" and slot_key == &"body")):
				inv.equip_item_from_slot(_held_slot_idx)
				_held_slot_idx = -1
				refresh()
				return
	# Otherwise unequip occupied slot back to inventory
	if inv.equipment.has(slot_key) and not (inv.equipment[slot_key] as ItemSlot).is_empty():
		inv.unequip_item(slot_key)
		refresh()


func _on_slot_gui_input(ev: InputEvent, idx: int) -> void:
	if not (ev is InputEventMouseButton) or not ev.pressed:
		return
	var mb := ev as InputEventMouseButton
	var inv: Inventory = player.inventory
	_selected_slot_idx = idx

	if mb.button_index == MOUSE_BUTTON_LEFT:
		if Input.is_key_pressed(KEY_SHIFT):
			# Shift-Click: transfer to/from open container, or between Hotbar (0..7) and Backpack (8..N)
			if active_container != null and is_instance_valid(active_container):
				_deposit_slot_to_container(idx)
			else:
				inv.quick_transfer_slot(idx)
			_held_slot_idx = -1
			player._sync_tool_from_hotbar()
			refresh()
			return

		if _held_slot_idx < 0:
			if not inv.slots[idx].is_empty():
				_held_slot_idx = idx
			if idx < Inventory.MAX_HOTBAR_SLOTS:
				player.select_hotbar_slot(idx)
		else:
			if _held_slot_idx != idx:
				inv.swap_or_merge_slots(_held_slot_idx, idx)
				if idx < Inventory.MAX_HOTBAR_SLOTS:
					player.select_hotbar_slot(idx)
				elif _held_slot_idx < Inventory.MAX_HOTBAR_SLOTS:
					player._sync_tool_from_hotbar()
			_held_slot_idx = -1
		refresh()

	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		var slot: ItemSlot = inv.slots[idx]
		# If holding a stack on cursor and right-clicking an empty slot -> split half
		if _held_slot_idx >= 0 and _held_slot_idx != idx and slot.is_empty():
			var src: ItemSlot = inv.slots[_held_slot_idx]
			if src.count > 1:
				inv.split_stack(_held_slot_idx, idx, maxi(1, src.count / 2))
				_held_slot_idx = -1
				refresh()
				return
		_held_slot_idx = -1
		if slot.is_empty():
			refresh()
			return
		var def: ItemDef = ItemDB.get_item(slot.item_id)
		if def != null:
			if def.equip_slot != &"":
				inv.equip_item_from_slot(idx)
			elif def.category == ItemDef.Category.FOOD and player.vitality.can_eat_food(def.id):
				player.vitality.eat_food(def.id, inv)
				if player.hud:
					player.hud.show_toast("Ate %s" % def.name)
			elif idx >= Inventory.MAX_HOTBAR_SLOTS:
				# Right-clicking a tool/item in the backpack moves it into the hotbar
				inv.move_to_hotbar(idx)
				player._sync_tool_from_hotbar()
			elif slot.count > 1:
				# Split stack into first empty slot
				for empty_i in range(Inventory.MAX_HOTBAR_SLOTS, inv.capacity):
					if inv.slots[empty_i].is_empty():
						inv.split_stack(idx, empty_i, maxi(1, slot.count / 2))
						break
		refresh()


func _refresh_inspector(inv: Inventory) -> void:
	for c in _inspect_actions.get_children():
		c.queue_free()
	if _selected_slot_idx < 0 or _selected_slot_idx >= inv.capacity:
		_inspect_icon.texture = null
		_inspect_title.text = "Select an item"
		_inspect_desc.text = "Click any slot to inspect, move to hotbar, or equip."
		return
	var slot: ItemSlot = inv.slots[_selected_slot_idx]
	if slot.is_empty():
		_inspect_icon.texture = null
		_inspect_title.text = ("Hotbar Slot %d (Empty)" % (_selected_slot_idx + 1)) if _selected_slot_idx < Inventory.MAX_HOTBAR_SLOTS else "Empty Slot"
		_inspect_desc.text = "Click an item and click here, or press 1-8 while hovering an item to assign it to the hotbar."
		return

	var def: ItemDef = ItemDB.get_item(slot.item_id)
	_inspect_icon.texture = ItemIcons.for_item(slot.item_id)
	_inspect_title.text = "%s (x%d)" % [def.name if def else String(slot.item_id), slot.count]

	var lines: Array[String] = []
	if def != null:
		var cat_names := ["Material", "Food", "Tool / Weapon", "Equipment", "Blueprint", "Special"]
		lines.append("Category: %s" % cat_names[clampi(def.category, 0, cat_names.size() - 1)])
		if def.has_tag("hammer"):
			lines.append("Equippable in Hotbar: Unlocks the Hammer Build Menu (Prefabs, Furniture & Blocks).")
		elif def.has_tag("pickaxe"):
			lines.append("Harvest Tool: Excavates terrain voxels and ores.")
		elif def.has_tag("fishing_rod"):
			lines.append("Angling Tool: Cast into tidal waters to catch fish.")
		elif def.has_tag("hoe"):
			lines.append("Farming Tool: Tills soil, waters crops, and harvests plots.")
		elif not def.weapon_data.is_empty():
			lines.append("Damage: %d  ·  Reach: %.1fm" % [int(def.weapon_data.get("damage", 10)), float(def.weapon_data.get("reach_m", 2.0))])
		elif not def.armor_data.is_empty():
			lines.append("Slot: %s  ·  Defense: +%d" % [String(def.equip_slot).capitalize(), int(def.armor_data.get("defense", 0))])
		elif not def.food_data.is_empty():
			lines.append("Nourishment: +%d HP, +%d Stamina" % [int(def.food_data.get("hp_bonus", 0)), int(def.food_data.get("stamina_bonus", 0))])
		elif def.is_voxel():
			lines.append("Buildable Block: Place directly from hotbar or via Hammer.")
	_inspect_desc.text = "\n".join(lines)

	# Action buttons for selected slot
	if _selected_slot_idx >= Inventory.MAX_HOTBAR_SLOTS:
		var hb_btn := Button.new()
		hb_btn.text = "To Hotbar"
		hb_btn.pressed.connect(func() -> void:
			inv.move_to_hotbar(_selected_slot_idx)
			player._sync_tool_from_hotbar()
			refresh()
		)
		_inspect_actions.add_child(hb_btn)
	else:
		var bag_btn := Button.new()
		bag_btn.text = "To Bag"
		bag_btn.pressed.connect(func() -> void:
			inv.quick_transfer_slot(_selected_slot_idx)
			player._sync_tool_from_hotbar()
			refresh()
		)
		_inspect_actions.add_child(bag_btn)

	if def != null and def.equip_slot != &"":
		var eq_btn := Button.new()
		eq_btn.text = "Equip"
		eq_btn.pressed.connect(func() -> void:
			inv.equip_item_from_slot(_selected_slot_idx)
			refresh()
		)
		_inspect_actions.add_child(eq_btn)

	if def != null and def.category == ItemDef.Category.FOOD:
		var eat_btn := Button.new()
		eat_btn.text = "Eat"
		eat_btn.disabled = not player.vitality.can_eat_food(def.id)
		eat_btn.pressed.connect(func() -> void:
			if player.vitality.eat_food(def.id, inv):
				if player.hud:
					player.hud.show_toast("Ate %s" % def.name)
				refresh()
		)
		_inspect_actions.add_child(eat_btn)


func _get_nearby_stations() -> Array[StationEntity]:
	var out: Array[StationEntity] = []
	if active_station != null and is_instance_valid(active_station):
		out.append(active_station)
	if player != null and player.entities != null:
		for ent in player.entities.entities.values():
			if ent is StationEntity and is_instance_valid(ent) and not out.has(ent):
				if ent.global_position.distance_to(player.global_position) <= 4.8:
					out.append(ent)
	return out


func _refresh_hand_crafting(inv: Inventory) -> void:
	for c in _craft_list.get_children():
		c.queue_free()
	if _station_tabs_box != null:
		_station_tabs_box.visible = true
		for c in _station_tabs_box.get_children():
			c.queue_free()

	var nearby_stations := _get_nearby_stations()
	var nearby_tags: Dictionary = {&"none": true}
	for st: StationEntity in nearby_stations:
		nearby_tags[st.station_tag] = st

	# Station selector tabs: Hand Craft + any nearby stations + All Stations
	var tab_defs: Array = [[&"none", "Hand Craft"]]
	var seen_tags: Dictionary = {&"none": true}
	for st: StationEntity in nearby_stations:
		if not seen_tags.has(st.station_tag):
			seen_tags[st.station_tag] = true
			var sname: String = RecipeDB.STATION_NAMES.get(st.station_tag, st.entity_name)
			tab_defs.append([st.station_tag, sname])
	tab_defs.append([&"all", "All Stations"])

	if _station_tab != &"all" and not seen_tags.has(_station_tab):
		_station_tab = &"none"

	if _station_tabs_box != null:
		for pair: Array in tab_defs:
			var tag: StringName = pair[0]
			var label_txt: String = pair[1]
			var b := Button.new()
			b.text = label_txt
			b.toggle_mode = true
			b.button_pressed = (_station_tab == tag)
			b.add_theme_font_size_override("font_size", 11)
			b.pressed.connect(func() -> void:
				_station_tab = tag
				refresh()
			)
			_station_tabs_box.add_child(b)

	if _station_tab == &"all":
		_right_sub_title.text = "All Crafting Stations"
	else:
		_right_sub_title.text = String(RecipeDB.STATION_NAMES.get(_station_tab, "Crafting"))

	var recipes: Array[RecipeDef] = []
	if _station_tab == &"all":
		recipes = RecipeDB.get_all_recipes()
	else:
		recipes = RecipeDB.get_station_exclusive_recipes(_station_tab)

	# Recipe unlocks (RecipeBook): only show what this player has learned.
	var hidden_count := 0
	if player != null and player.recipes != null:
		var known_only: Array[RecipeDef] = []
		for rr: RecipeDef in recipes:
			if player.recipes.knows(rr.id):
				known_only.append(rr)
			else:
				hidden_count += 1
		recipes = known_only

	var active_st_ent: StationEntity = nearby_tags.get(_station_tab, null) if _station_tab != &"none" and _station_tab != &"all" else null
	if active_st_ent != null and active_st_ent.is_fire_station():
		var fuel_box := HBoxContainer.new()
		fuel_box.add_theme_constant_override("separation", 8)
		_craft_list.add_child(fuel_box)

		var fuel_lbl := Label.new()
		fuel_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var rem_sec := int(ceil(active_st_ent.station.fuel_remaining_sec))
		if rem_sec > 0:
			fuel_lbl.text = "Fire Lit: %ds / %ds charge" % [rem_sec, int(CraftingStation.MAX_FUEL_SEC)]
			fuel_lbl.add_theme_color_override("font_color", Color(0.85, 0.35, 0.08))
		else:
			fuel_lbl.text = "Fire Out — Recharge with wood to cook"
			fuel_lbl.add_theme_color_override("font_color", Color(0.65, 0.18, 0.15))
		fuel_lbl.add_theme_font_size_override("font_size", 12)
		fuel_box.add_child(fuel_lbl)

		var stoke_btn := Button.new()
		stoke_btn.text = "Recharge Fire (+Wood)"
		stoke_btn.disabled = not CraftingStation.has_any_fuel(inv) or active_st_ent.station.fuel_remaining_sec >= CraftingStation.MAX_FUEL_SEC - 1.0
		stoke_btn.pressed.connect(func() -> void:
			active_st_ent.recharge_fire(player)
			refresh()
		)
		fuel_box.add_child(stoke_btn)

		var sep := HSeparator.new()
		_craft_list.add_child(sep)

	for r: RecipeDef in recipes:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_craft_list.add_child(row)

		var ic := UiTheme.icon(ItemIcons.for_item(r.output_item_id), 32)
		row.add_child(ic)

		var info_v := VBoxContainer.new()
		info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_v.add_theme_constant_override("separation", 1)
		row.add_child(info_v)

		var title := Label.new()
		title.text = "%s%s" % [r.name, (" x%d" % r.output_count) if r.output_count > 1 else ""]
		title.theme_type_variation = &"InkLabel"
		title.add_theme_font_size_override("font_size", 14)
		info_v.add_child(title)

		var cost_parts: Array[String] = []
		for inp: Dictionary in r.inputs:
			var iid := StringName(inp["item_id"])
			var req := int(inp["count"])
			var idef := ItemDB.get_item(iid)
			cost_parts.append("%d %s" % [req, idef.name if idef else String(iid)])
		if _station_tab == &"all" and r.required_station != &"none":
			var req_st_name: String = RecipeDB.STATION_NAMES.get(r.required_station, String(r.required_station))
			cost_parts.append("[%s]" % req_st_name)
		var sub := Label.new()
		sub.text = ", ".join(cost_parts)
		sub.theme_type_variation = &"InkLabel"
		sub.add_theme_font_size_override("font_size", 11)
		info_v.add_child(sub)

		var st_for_rec: StationEntity = nearby_tags.get(r.required_station, null) if r.required_station != &"none" else null
		var station_available: bool = (r.required_station == &"none") or (st_for_rec != null)
		var fuel_ok: bool = (st_for_rec == null) or st_for_rec.station.is_fueled()
		var can_make := station_available and fuel_ok and r.can_craft_with(inv)
		var btn := Button.new()
		if not station_available:
			btn.text = "Need Station"
		elif not fuel_ok:
			btn.text = "Need Fuel"
		else:
			btn.text = "Craft"
		btn.disabled = not can_make
		btn.pressed.connect(func() -> void:
			_craft_station_recipe(r, inv, nearby_tags)
		)
		row.add_child(btn)

	if hidden_count > 0:
		var hint := Label.new()
		hint.theme_type_variation = &"InkLabel"
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color8(120, 92, 70))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD
		hint.text = "%d more recipe%s to discover: find new ingredients, recruit drifters, finish quests, or buy recipe scrolls." % [
			hidden_count, "" if hidden_count == 1 else "s"]
		_craft_list.add_child(hint)


func _craft_station_recipe(r: RecipeDef, inv: Inventory, nearby_tags: Dictionary) -> void:
	if r.required_station == &"none":
		if _field_station.craft_recipe(r.id, inv):
			if player.hud:
				player.hud.show_toast("Crafted %s!" % r.name)
			player.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, r.output_item_id)
			refresh()
		return
	var st_ent: StationEntity = nearby_tags.get(r.required_station, null)
	if st_ent == null:
		return
	if st_ent.station.requires_fuel and not st_ent.station.is_fueled():
		if player.hud:
			player.hud.show_toast("%s is out! Recharge the fire with wood first." % st_ent.entity_name)
		refresh()
		return
	# Consume inputs and deliver output directly for responsive UI crafting
	if not r.can_craft_with(inv):
		return
	for inp: Dictionary in r.inputs:
		inv.remove_item(StringName(inp["item_id"]), int(inp["count"]))
	inv.add_item(r.output_item_id, r.output_count)
	if st_ent.station.requires_fuel:
		st_ent.station.fuel_remaining_sec = maxf(0.0, st_ent.station.fuel_remaining_sec - minf(st_ent.station.fuel_remaining_sec, maxf(3.0, r.craft_time_sec * 0.5)))
		st_ent._update_fire_visuals(0.0)
	st_ent.recipe_crafted.emit(r.id, 1)
	player.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, r.output_item_id)
	if player.hud:
		player.hud.show_toast("Crafted %s at %s!" % [r.name, st_ent.entity_name])
	refresh()


func _refresh_container() -> void:
	for c in _container_grid.get_children():
		c.queue_free()
	if active_container == null or not is_instance_valid(active_container):
		return
	var cinv: Inventory = active_container.container.inventory
	for i in cinv.capacity:
		var slot: ItemSlot = cinv.slots[i]
		var p := PanelContainer.new()
		p.theme_type_variation = &"SlotSelected" if not slot.is_empty() else &"Slot"
		p.custom_minimum_size = Vector2(52, 52)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		var box := Control.new()
		box.custom_minimum_size = Vector2(40, 40)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(box)
		if not slot.is_empty():
			var ic := UiTheme.icon(ItemIcons.for_item(slot.item_id), 38)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(ic)
			if slot.count > 1:
				var cnt := Label.new()
				cnt.text = str(slot.count)
				cnt.theme_type_variation = &"KeyLabel"
				cnt.add_theme_font_size_override("font_size", 12)
				cnt.position = Vector2(18, 22)
				cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(cnt)
		p.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				_withdraw_from_container(i)
		)
		p.mouse_entered.connect(func() -> void:
			p.theme_type_variation = &"SlotSelected"
			p.self_modulate = Color(1.08, 1.04, 0.94)
			if not slot.is_empty():
				_show_hover_label(slot.item_id, slot.count)
			else:
				_hide_hover_label()
		)
		p.mouse_exited.connect(func() -> void:
			p.theme_type_variation = &"SlotSelected" if not slot.is_empty() else &"Slot"
			p.self_modulate = Color.WHITE
			_hide_hover_label()
		)
		_container_grid.add_child(p)


func _deposit_slot_to_container(slot_idx: int) -> void:
	if active_container == null or player == null:
		return
	var slot: ItemSlot = player.inventory.slots[slot_idx]
	if slot.is_empty() or not active_container.container.can_accept_item(slot.item_id):
		return
	var item_id := slot.item_id
	var count := slot.count
	if active_container.manager != null:
		var removed := player.inventory.remove_item(item_id, count)
		if removed > 0:
			active_container.manager.request_action(active_container, &"deposit", {"item": item_id, "n": removed})
	else:
		var rem := active_container.container.deposit(item_id, count)
		var transferred := count - rem
		if transferred > 0:
			player.inventory.remove_item(item_id, transferred)
	refresh()


func _withdraw_from_container(cont_slot_idx: int) -> void:
	if active_container == null or player == null:
		return
	var cslot: ItemSlot = active_container.container.inventory.slots[cont_slot_idx]
	if cslot.is_empty():
		return
	if active_container.manager != null:
		active_container.manager.request_action(active_container, &"take", {})
	else:
		var item_id := cslot.item_id
		var amt := cslot.count
		var rem := player.inventory.add_item(item_id, amt)
		var taken := amt - rem
		if taken > 0:
			active_container.container.withdraw(item_id, taken)
	refresh()
