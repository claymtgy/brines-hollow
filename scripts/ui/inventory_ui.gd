class_name InventoryUI
extends CanvasLayer
## The Pack page (I / Tab): gear on a live figure, stats, hotbar, backpack and item details.
## Crafting has its own page (CraftingUI, K); this page links to it. Chests have their
## own screen too (ChestUI): open(chest) hands over to it.
##
## Mouse:
##   Left-click       Pick up / place / swap / merge a stack
##   Shift + Click    Quick-move between Backpack and Hotbar
##   Right-click      Equip gear / eat food / move to hotbar / split a stack
##   Keys 1-8         Put the hovered (or selected) item on that hotbar slot
##   Q / Delete       Drop one (Shift: the whole stack)
## Pad: D-pad moves between slots, A = left-click, X = right-click, RB = Crafting page.

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
const GEAR_LEFT := [&"head", &"body", &"legs", &"boots"]
const GEAR_RIGHT := [&"main_hand", &"accessory", &"backpack", &"map"]
const STAT_ROWS := [
	["defense", "Defense"],
	["cold", "Cold protection"],
	["depth", "Safe dive depth"],
	["breath", "Extra breath"],
	["swim", "Swim speed"],
	["capacity", "Bag slots"],
]
const CATEGORY_NAMES := ["Material", "Food", "Tool", "Equipment", "Blueprint", "Special"]
const COL_UP := Color8(60, 125, 60)
const COL_DOWN := Color8(165, 60, 45)
const COL_MUTED := Color8(120, 92, 70)
const SLOT_PX := 44.0
const SLOT_PAD := 5.0

var main: Node
var player: Player
## The Chest screen, made the first time a chest is opened.
var chest_ui: ChestUI

var _held_slot_idx: int = -1
var _selected_slot_idx: int = 0
var _selected_equip: StringName = &""
var _hovered_slot_idx: int = -1
var _hovered_equip: StringName = &""
var _pad_input := false
var _built_capacity := -1

var _root: Control
var _title_label: Label
var _hotbar_row: HBoxContainer
var _bag_grid: GridContainer
var _bag_label: Label
var _slot_views: Array[ItemSlotView] = []      ## index = inventory slot index
var _equip_views: Dictionary = {}               ## slot name -> ItemSlotView
var _stat_values: Dictionary = {}               ## stat key -> Label
var _stat_deltas: Dictionary = {}               ## stat key -> Label
var _preview_vp: SubViewport
var _preview_model: CharacterModel
var _detail: VBoxContainer
var _right_sub_title: Label
var _craft_card: VBoxContainer
var _craft_card_lbl: Label
var _cursor_floater: Control
var _cursor_icon: TextureRect
var _cursor_count: Label
var _hover_panel: PanelContainer
var _hover_box: VBoxContainer


func _ready() -> void:
	layer = 16
	_build()
	visible = false


func setup(p_main: Node) -> void:
	main = p_main


## True while the Pack page or the Chest screen is up (they never show together).
func is_open() -> bool:
	return visible or is_chest_open()


func is_chest_open() -> bool:
	return chest_ui != null and chest_ui.is_open()


func toggle(container_entity: ChestEntity = null) -> void:
	if is_open():
		close()
	else:
		open(container_entity)


## Opens the Pack page, or the Chest screen when given a chest.
func open(container_entity: ChestEntity = null) -> void:
	if main != null and main.get("player") != null:
		player = main.player
	if player == null or player.inventory == null:
		return
	if container_entity != null:
		_open_chest(container_entity)
		return
	if is_chest_open():
		chest_ui.close()
	_held_slot_idx = -1
	_selected_equip = &""
	_selected_slot_idx = player.inventory.active_hotbar_index
	visible = true
	_bind_inventory_signals()
	_ensure_preview()
	if _preview_vp != null:
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	_focus_slot(_selected_slot_idx)


func _open_chest(c: ChestEntity) -> void:
	if visible:
		close()
	if chest_ui == null:
		chest_ui = ChestUI.new()
		chest_ui.name = "ChestUI"
		var host: Node = get_parent() if get_parent() != null else get_tree().root
		host.add_child(chest_ui)
		chest_ui.closed.connect(func() -> void: inventory_closed.emit())
	chest_ui.open(player, c, main)


func close() -> void:
	if is_chest_open():
		chest_ui.close()
	if not visible:
		return
	visible = false
	_held_slot_idx = -1
	if _cursor_floater != null:
		_cursor_floater.visible = false
	_hide_hover_label()
	if _preview_vp != null:
		_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if player != null:
		player.input_enabled = true
		player._sync_tool_from_hotbar()
	if main == null or not main.has_method("is_any_menu_open") or not main.is_any_menu_open():
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


func _go_page(page: StringName) -> void:
	if main != null and main.has_method("switch_page"):
		main.switch_page(page)


# -------------------------------------------------------------------------
# Input
# -------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or _cursor_floater == null:
		return
	var anchor := _pointer_pos()
	if _hover_panel.visible:
		var vp_sz := get_viewport().get_visible_rect().size
		var ps := _hover_panel.size
		_hover_panel.position = Vector2(
			clampf(anchor.x + 18.0, 8.0, maxf(8.0, vp_sz.x - ps.x - 8.0)),
			clampf(anchor.y + 18.0, 8.0, maxf(8.0, vp_sz.y - ps.y - 8.0)))
	if _held_slot_idx >= 0 and player != null and _held_slot_idx < player.inventory.capacity:
		var s: ItemSlot = player.inventory.slots[_held_slot_idx]
		if not s.is_empty():
			_cursor_floater.visible = true
			_cursor_floater.position = anchor + Vector2(14, 14)
			_cursor_icon.texture = ItemIcons.for_item(s.item_id)
			_cursor_count.text = str(s.count) if s.count > 1 else ""
			return
	if _held_slot_idx >= 0:
		_held_slot_idx = -1
		_refresh_slots()
	_cursor_floater.visible = false


## Mouse position, or the focused slot when playing on a pad.
func _pointer_pos() -> Vector2:
	if _pad_input:
		var f := get_viewport().gui_get_focus_owner()
		if f != null and _root.is_ancestor_of(f):
			return f.get_global_rect().get_center()
	return get_viewport().get_mouse_position()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		_pad_input = true
	elif e is InputEventMouseMotion or e is InputEventMouseButton:
		_pad_input = false
	if e.is_action_pressed("inventory_toggle") or e.is_action_pressed("menu_toggle") \
			or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B and _held_slot_idx < 0):
		get_viewport().set_input_as_handled()
		close()
		return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B:
		get_viewport().set_input_as_handled()   # B with a stack in hand: put it down
		_held_slot_idx = -1
		refresh()
		return
	if e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		get_viewport().set_input_as_handled()
		_go_page(&"crafting")
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if kc == KEY_Q or kc == KEY_DELETE:
			var target_slot: int = _held_slot_idx
			if target_slot < 0:
				target_slot = _hovered_slot_idx if _hovered_slot_idx >= 0 else _selected_slot_idx
			if target_slot >= 0 and player != null:
				var drop_cnt := -1 if Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_CTRL) else 1
				player.drop_item_from_inventory(target_slot, drop_cnt)
				if player.inventory.slots[target_slot].is_empty() and _held_slot_idx == target_slot:
					_held_slot_idx = -1
				refresh()
				get_viewport().set_input_as_handled()
				return
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


## Left-click (or pad A) on bag / hotbar slot `idx`.
func _slot_primary(idx: int, shift: bool) -> void:
	var inv: Inventory = player.inventory
	_selected_slot_idx = idx
	_selected_equip = &""
	if shift:
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


## Right-click (or pad X): equip / eat / to hotbar / split.
func _slot_secondary(idx: int) -> void:
	var inv: Inventory = player.inventory
	var slot: ItemSlot = inv.slots[idx]
	_selected_slot_idx = idx
	_selected_equip = &""
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
		elif def.category == ItemDef.Category.FOOD and player.vitality.is_full_of(def.id):
			_toast("Still full of %s. Try another dish." % def.name)
		elif def.category == ItemDef.Category.FOOD and player.vitality.can_eat_food(def.id):
			player.vitality.eat_food(def.id, inv)
			_toast("Ate %s" % def.name)
		elif idx >= Inventory.MAX_HOTBAR_SLOTS:
			inv.move_to_hotbar(idx)
			player._sync_tool_from_hotbar()
		elif slot.count > 1:
			for empty_i in range(Inventory.MAX_HOTBAR_SLOTS, inv.capacity):
				if inv.slots[empty_i].is_empty():
					inv.split_stack(idx, empty_i, maxi(1, slot.count / 2))
					break
	refresh()


func _on_equip_clicked(slot_key: StringName, secondary: bool) -> void:
	if player == null or player.inventory == null:
		return
	var inv: Inventory = player.inventory
	# A held item that belongs in this slot goes on.
	if not secondary and _held_slot_idx >= 0 and _held_slot_idx < inv.capacity:
		var held: ItemSlot = inv.slots[_held_slot_idx]
		var def: ItemDef = ItemDB.get_item(held.item_id) if not held.is_empty() else null
		if def != null and (def.equip_slot == slot_key or (def.equip_slot == &"chest" and slot_key == &"body")):
			inv.equip_item_from_slot(_held_slot_idx)
			_held_slot_idx = -1
			_selected_equip = slot_key
			refresh()
			return
	var worn: ItemSlot = inv.equipment.get(slot_key, null)
	if secondary and worn != null and not worn.is_empty():
		if not inv.unequip_item(slot_key):
			_toast("No room in your bag.")
		refresh()
		return
	_selected_equip = slot_key
	_selected_slot_idx = -1
	refresh()


func _toast(msg: String) -> void:
	if player != null and player.hud != null:
		player.hud.show_toast(msg)


# -------------------------------------------------------------------------
# Build
# -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	UiTheme.prepare(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.10, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		# Clicking outside the window with a stack in hand drops it (right-click: one).
		if ev is InputEventMouseButton and ev.pressed and _held_slot_idx >= 0 and player != null:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				player.drop_item_from_inventory(_held_slot_idx, -1)
				_held_slot_idx = -1
				refresh()
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				player.drop_item_from_inventory(_held_slot_idx, 1)
				if player.inventory.slots[_held_slot_idx].is_empty():
					_held_slot_idx = -1
				refresh()
	)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(1180, 640)
	center.add_child(outer)
	UiTheme.keep_on_screen(outer)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	outer.add_child(v)

	# --- header: same tab strip as the Crafting and Quests pages
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	_title_label = Label.new()
	_title_label.text = "Pack"
	_title_label.theme_type_variation = &"Header"
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.clip_text = true
	head.add_child(_title_label)
	for t: Array in [["Pack (I)", &"pack"], ["Crafting (K)", &"crafting"], ["Quests (J)", &"quests"]]:
		var tb := Button.new()
		tb.text = t[0]
		tb.toggle_mode = true
		tb.button_pressed = t[1] == &"pack"
		tb.focus_mode = Control.FOCUS_NONE
		var page: StringName = t[1]
		tb.pressed.connect(func() -> void:
			tb.button_pressed = page == &"pack"
			if page != &"pack":
				_go_page(page)
		)
		head.add_child(tb)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)

	_build_gear(_page(cols, 312))
	_build_bag(_page(cols, 0, true))
	_build_right(_page(cols, 286))

	var foot := Label.new()
	foot.theme_type_variation = &"Small"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.text = "Click: pick up / place  ·  Shift+Click: quick move  ·  Right-click: use / equip  ·  1-8: to hotbar  ·  Q: drop"
	v.add_child(foot)

	# Stack following the cursor while you move it
	_cursor_floater = Control.new()
	_cursor_floater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_floater.visible = false
	_cursor_floater.z_index = 40
	_root.add_child(_cursor_floater)
	_cursor_icon = UiTheme.icon(null, 44)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_floater.add_child(_cursor_icon)
	_cursor_count = Label.new()
	_cursor_count.theme_type_variation = &"KeyLabel"
	_cursor_count.position = Vector2(24, 24)
	_cursor_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_floater.add_child(_cursor_count)

	# Hover card
	_hover_panel = PanelContainer.new()
	_hover_panel.theme_type_variation = &"Plaque"
	_hover_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.visible = false
	_hover_panel.z_index = 50
	_root.add_child(_hover_panel)
	_hover_box = VBoxContainer.new()
	_hover_box.add_theme_constant_override("separation", 1)
	_hover_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_panel.add_child(_hover_box)


func _page(parent: Control, width: float, expand := false) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Parchment"
	if width > 0.0:
		p.custom_minimum_size = Vector2(width, 0)
	if expand:
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v


func _ink(text: String, fsize: int = 14, bold := false, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", fsize)
	if bold:
		l.add_theme_font_override("font", UiTheme.font(800))
	if col.a > 0.0:
		l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_gear(col: VBoxContainer) -> void:
	col.add_child(_ink("Gear", 20, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	row.add_child(_gear_column(GEAR_LEFT))

	# Live figure wearing your gear (drag to turn).
	var vpc := SubViewportContainer.new()
	vpc.custom_minimum_size = Vector2(128, 250)
	vpc.stretch = true
	vpc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vpc.tooltip_text = "Drag to turn"
	vpc.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and _preview_model != null:
			_preview_model.rotation.y += ev.relative.x * 0.012
	)
	row.add_child(vpc)
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(128, 250)
	_preview_vp.own_world_3d = true
	_preview_vp.transparent_bg = true
	_preview_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vpc.add_child(_preview_vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.82, 3.8)
	cam.rotation = Vector3(-0.04, 0.0, 0.0)
	cam.fov = 36.0
	_preview_vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.6, 0.45, 0.0)
	sun.light_energy = 1.3
	_preview_vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.8, 0.72)
	env.environment.ambient_light_energy = 0.6
	_preview_vp.add_child(env)

	row.add_child(_gear_column(GEAR_RIGHT))

	col.add_child(HSeparator.new())
	col.add_child(_ink("Stats", 18, true))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 1)
	col.add_child(grid)
	for s: Array in STAT_ROWS:
		var name_l := _ink(s[1], 14, false, COL_MUTED)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_l)
		var val := _ink("", 14, true)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(val)
		var delta := _ink("", 14, true)
		delta.custom_minimum_size = Vector2(54, 0)
		grid.add_child(delta)
		_stat_values[s[0]] = val
		_stat_deltas[s[0]] = delta


func _gear_column(keys: Array) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 3)
	for k: StringName in keys:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 0)
		c.add_child(cell)
		var view := ItemSlotView.new(40).set_padding(SLOT_PAD)
		view.focus_mode = Control.FOCUS_ALL
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cell.add_child(view)
		var lbl := _ink(_equip_label(k), 12, false, COL_MUTED)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(lbl)
		_equip_views[k] = view
		view.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_on_equip_clicked(k, ev.button_index == MOUSE_BUTTON_RIGHT)
				view.accept_event()
			elif ev.is_action_pressed("ui_accept"):
				_on_equip_clicked(k, false)
				view.accept_event()
			elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_X:
				_on_equip_clicked(k, true)
				view.accept_event()
		)
		var enter := func() -> void:
			_hovered_equip = k
			_hovered_slot_idx = -1
			view.self_modulate = Color(1.1, 1.06, 0.95)
			var worn: ItemSlot = player.inventory.equipment.get(k, null) if player != null else null
			if worn != null and not worn.is_empty():
				_show_hover_label(worn.item_id, 1, _equip_label(k), true)
			else:
				_show_hover_text(_equip_label(k), "Empty - drop gear here or right-click it in your bag")
			_update_stats({})
		var leave := func() -> void:
			view.self_modulate = Color.WHITE
			if _hovered_equip == k:
				_hovered_equip = &""
				_hide_hover_label()
		view.mouse_entered.connect(enter)
		view.mouse_exited.connect(leave)
		view.focus_entered.connect(func() -> void:
			if _pad_input:
				enter.call())
		view.focus_exited.connect(leave)
	return c


static func _equip_label(k: StringName) -> String:
	for pair: Array in EQUIP_SLOTS:
		if pair[0] == k:
			return pair[1]
	return String(k).capitalize()


func _build_bag(col: VBoxContainer) -> void:
	col.add_child(_ink("Hotbar", 18, true))
	_hotbar_row = HBoxContainer.new()
	_hotbar_row.add_theme_constant_override("separation", 4)
	col.add_child(_hotbar_row)
	col.add_child(HSeparator.new())
	var bag_head := HBoxContainer.new()
	col.add_child(bag_head)
	_bag_label = _ink("Backpack", 18, true)
	_bag_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_head.add_child(_bag_label)
	var sort_btn := Button.new()
	sort_btn.text = "Sort"
	sort_btn.focus_mode = Control.FOCUS_NONE
	sort_btn.add_theme_font_size_override("font_size", 15)
	sort_btn.tooltip_text = "Sort the backpack (the hotbar stays as it is)"
	sort_btn.pressed.connect(func() -> void:
		if player and player.inventory:
			player.inventory.quick_sort(true)
			refresh()
	)
	bag_head.add_child(sort_btn)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	_bag_grid = GridContainer.new()
	_bag_grid.columns = Inventory.MAX_HOTBAR_SLOTS
	_bag_grid.add_theme_constant_override("h_separation", 4)
	_bag_grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(_bag_grid)


func _build_right(col: VBoxContainer) -> void:
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	col.add_child(_detail)
	col.add_child(HSeparator.new())
	_right_sub_title = _ink("Crafting", 18, true)
	col.add_child(_right_sub_title)

	# Crafting has its own page; this card says what's ready and links there.
	_craft_card = VBoxContainer.new()
	_craft_card.add_theme_constant_override("separation", 8)
	_craft_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_craft_card)
	_craft_card_lbl = _ink("", 14)
	_craft_card_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_craft_card.add_child(_craft_card_lbl)
	var craft_btn := Button.new()
	craft_btn.text = "Open Crafting (K)"
	craft_btn.focus_mode = Control.FOCUS_NONE
	craft_btn.add_theme_font_size_override("font_size", 16)
	craft_btn.pressed.connect(func() -> void: _go_page(&"crafting"))
	_craft_card.add_child(craft_btn)


## Builds bag + hotbar slot views once per capacity.
func _build_slots(cap: int) -> void:
	for c in _hotbar_row.get_children():
		_hotbar_row.remove_child(c)
		c.queue_free()
	for c in _bag_grid.get_children():
		_bag_grid.remove_child(c)
		c.queue_free()
	_slot_views.clear()
	for i in cap:
		var view := ItemSlotView.new(SLOT_PX).set_padding(SLOT_PAD)
		view.focus_mode = Control.FOCUS_ALL
		view.mouse_filter = Control.MOUSE_FILTER_STOP
		if i < Inventory.MAX_HOTBAR_SLOTS:
			var key := Label.new()
			key.text = str(i + 1)
			key.theme_type_variation = &"KeyLabel"
			key.add_theme_font_size_override("font_size", 12)
			key.position = Vector2(-3, -5)
			key.mouse_filter = Control.MOUSE_FILTER_IGNORE
			view.get_child(0).add_child(key)
			_hotbar_row.add_child(view)
		else:
			_bag_grid.add_child(view)
		_slot_views.append(view)
		_wire_slot(view, i)
	_built_capacity = cap


func _wire_slot(view: ItemSlotView, idx: int) -> void:
	view.gui_input.connect(func(ev: InputEvent) -> void:
		if player == null:
			return
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				_slot_primary(idx, Input.is_key_pressed(KEY_SHIFT))
				view.accept_event()
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				_slot_secondary(idx)
				view.accept_event()
		elif ev.is_action_pressed("ui_accept"):
			_slot_primary(idx, false)
			view.accept_event()
		elif ev is InputEventJoypadButton and ev.pressed and ev.button_index == JOY_BUTTON_X:
			_slot_secondary(idx)
			view.accept_event()
	)
	var enter := func() -> void:
		_hovered_slot_idx = idx
		_hovered_equip = &""
		view.self_modulate = Color(1.1, 1.06, 0.95)
		if player == null or idx >= player.inventory.capacity:
			return
		var s: ItemSlot = player.inventory.slots[idx]
		if s.is_empty():
			_hide_hover_label()
			_update_stats({})
		else:
			_show_hover_label(s.item_id, s.count)
			_update_stats(player.inventory.preview_stats(s.item_id))
	var leave := func() -> void:
		view.self_modulate = Color.WHITE
		if _hovered_slot_idx == idx:
			_hovered_slot_idx = -1
			_hide_hover_label()
			_update_stats({})
	view.mouse_entered.connect(enter)
	view.mouse_exited.connect(leave)
	view.focus_entered.connect(func() -> void:
		if _pad_input:
			enter.call())
	view.focus_exited.connect(leave)


func _focus_slot(idx: int) -> void:
	await get_tree().process_frame
	if visible and idx >= 0 and idx < _slot_views.size():
		_slot_views[idx].grab_focus()


# -------------------------------------------------------------------------
# Refresh
# -------------------------------------------------------------------------

## Swim speed as a bonus over normal ("Normal", "+20%", "-10%").
static func swim_speed_text(mult: float) -> String:
	var bonus := roundi((mult - 1.0) * 100.0)
	return "Normal" if bonus == 0 else "%+d%%" % bonus


static func stat_text(key: String, v: float) -> String:
	match key:
		"cold":
			return "%d%%" % roundi(v * 100.0)
		"depth":
			return "%d m" % roundi(v)
		"breath":
			return "+%d s" % roundi(v)
		"swim":
			return swim_speed_text(v)
	return str(roundi(v))


## "+3", "-15%", "" when unchanged. Every stat here is better when higher.
static func stat_delta_text(key: String, before: float, after: float) -> String:
	var d := after - before
	match key:
		"cold", "swim":
			var pct := roundi(d * 100.0)
			return "" if pct == 0 else "%+d%%" % pct
		"depth":
			return "" if roundi(d) == 0 else "%+d m" % roundi(d)
		"breath":
			return "" if roundi(d) == 0 else "%+d s" % roundi(d)
	return "" if roundi(d) == 0 else "%+d" % roundi(d)


func refresh() -> void:
	if player == null or player.inventory == null:
		return
	var inv: Inventory = player.inventory
	if _built_capacity != inv.capacity:
		_build_slots(inv.capacity)
	_refresh_slots()
	_refresh_gear()
	var hover_preview: Dictionary = {}
	if _hovered_slot_idx >= 0 and _hovered_slot_idx < inv.capacity and not inv.slots[_hovered_slot_idx].is_empty():
		hover_preview = inv.preview_stats(inv.slots[_hovered_slot_idx].item_id)
	_update_stats(hover_preview)
	_refresh_detail()

	_refresh_craft_card(inv)


func _refresh_slots() -> void:
	if player == null:
		return
	var inv: Inventory = player.inventory
	var used := 0
	for i in mini(_slot_views.size(), inv.capacity):
		var s: ItemSlot = inv.slots[i]
		var view := _slot_views[i]
		view.show_item(s.item_id if not s.is_empty() else &"", s.count)
		view.tooltip_text = ""
		var sel := i == _held_slot_idx or i == _selected_slot_idx or (i < Inventory.MAX_HOTBAR_SLOTS and i == inv.active_hotbar_index)
		view.set_selected(sel)
		view.modulate = Color(1, 1, 1, 0.35) if i == _held_slot_idx else Color.WHITE
		if i >= Inventory.MAX_HOTBAR_SLOTS and not s.is_empty():
			used += 1
	_bag_label.text = "Backpack  ·  %d / %d" % [used, inv.capacity - Inventory.MAX_HOTBAR_SLOTS]


func _refresh_gear() -> void:
	var inv: Inventory = player.inventory
	for k: StringName in _equip_views:
		var view: ItemSlotView = _equip_views[k]
		var worn: ItemSlot = inv.equipment.get(k, null)
		var has := worn != null and not worn.is_empty()
		view.show_item(worn.item_id if has else &"", 1)
		view.tooltip_text = ""
		view.set_selected(k == _selected_equip)
		view.modulate = Color.WHITE if has else Color(1, 1, 1, 0.7)
	if _preview_model != null:
		_preview_model.apply_equipment(inv)


func _ensure_preview() -> void:
	if _preview_model != null or _preview_vp == null or player == null:
		if _preview_model != null and player != null and player.get("customizer") != null:
			_preview_model.apply_customizer(player.customizer)
		return
	_preview_model = CharacterModel.new()
	_preview_model.rotation.y = 0.45
	_preview_vp.add_child(_preview_model)
	var cust: CharacterCustomizer = player.get("customizer")
	_preview_model.setup(Palette.COAT_A, Palette.HAT_A, cust)


## Fills the stats table; `preview` (from Inventory.preview_stats) adds green/red changes.
func _update_stats(preview: Dictionary) -> void:
	if player == null or _stat_values.is_empty():
		return
	var now: Dictionary = player.inventory.gear_stats()
	var after: Dictionary = preview.get("after", {})
	for s: Array in STAT_ROWS:
		var key: String = s[0]
		(_stat_values[key] as Label).text = stat_text(key, float(now[key]))
		var dl: Label = _stat_deltas[key]
		dl.text = ""
		if not after.is_empty():
			var txt := stat_delta_text(key, float(now[key]), float(after[key]))
			dl.text = txt
			dl.add_theme_color_override("font_color", COL_UP if float(after[key]) > float(now[key]) else COL_DOWN)


## Lines comparing an item to what's worn in its slot: [[text, better?], ...].
func compare_lines(item_id: StringName) -> Array:
	var pv := player.inventory.preview_stats(item_id) if player != null else {}
	var out: Array = []
	if pv.is_empty():
		return out
	var before: Dictionary = pv["before"]
	var after: Dictionary = pv["after"]
	for s: Array in STAT_ROWS:
		var key: String = s[0]
		var txt := stat_delta_text(key, float(before[key]), float(after[key]))
		if txt != "":
			out.append(["%s %s" % [s[1], txt], float(after[key]) > float(before[key])])
	return out


## Short fact lines about an item (damage, defense, food...).
static func item_facts(def: ItemDef) -> Array[String]:
	var out: Array[String] = []
	if def == null:
		return out
	var tier := int(def.tool_data.get("tier", 0))
	if def.has_tag("pickaxe"):
		out.append("Mines stone and ores")
	elif def.has_tag("axe"):
		out.append("Fells trees, more logs per tree")
	elif def.has_tag("shovel"):
		out.append("Digs dirt, sand and gravel")
	elif def.has_tag("hammer"):
		out.append("Opens the build menu")
	elif def.has_tag("hoe"):
		out.append("Tills soil and harvests crops")
	elif def.has_tag("fishing_rod"):
		out.append("Cast into open water to fish")
	if tier > 0:
		out.append("Tier %d" % tier)
	if not def.weapon_data.is_empty():
		out.append("Damage %d  ·  reach %.1f m" % [int(def.weapon_data.get("damage", 10)),
			float(def.weapon_data.get("reach_m", def.weapon_data.get("reach", 2.0)))])
	var a := def.armor_data
	if a.has("defense"):
		out.append("Defense +%d" % int(a["defense"]))
	if a.has("cold_protection"):
		out.append("Cold protection +%d%%" % roundi(float(a["cold_protection"]) * 100.0))
	if a.has("max_safe_depth_m"):
		out.append("Safe to %d m deep" % roundi(float(a["max_safe_depth_m"])))
	if a.has("extra_breath_sec"):
		out.append("+%d s breath" % roundi(float(a["extra_breath_sec"])))
	if a.has("swim_speed_mult"):
		out.append("Swim speed %s" % swim_speed_text(float(a["swim_speed_mult"])))
	if def.equip_slot == &"backpack" and def.tool_data.has("capacity"):
		out.append("%d bag slots" % int(def.tool_data["capacity"]))
	if not def.food_data.is_empty():
		var hp := int(def.food_data.get("hp_bonus", 0))
		var st := int(def.food_data.get("stamina_bonus", 0))
		if hp > 0 or st > 0:
			out.append("+%d health, +%d stamina" % [hp, st])
	if def.is_voxel():
		out.append("Placeable block")
	return out


static func category_line(def: ItemDef) -> String:
	var cat: String = CATEGORY_NAMES[clampi(def.category, 0, CATEGORY_NAMES.size() - 1)]
	if def.equip_slot != &"":
		cat += "  ·  worn on %s" % _equip_label(&"body" if def.equip_slot == &"chest" else def.equip_slot).to_lower()
	return cat


func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _refresh_detail() -> void:
	_clear(_detail)
	var inv: Inventory = player.inventory
	var item_id: StringName = &""
	var count := 0
	var worn := false
	if _selected_equip != &"":
		var es: ItemSlot = inv.equipment.get(_selected_equip, null)
		if es != null and not es.is_empty():
			item_id = es.item_id
			count = 1
			worn = true
	elif _selected_slot_idx >= 0 and _selected_slot_idx < inv.capacity and not inv.slots[_selected_slot_idx].is_empty():
		item_id = inv.slots[_selected_slot_idx].item_id
		count = inv.slots[_selected_slot_idx].count
	if item_id == &"":
		_detail.add_child(_ink("Nothing selected", 18, true))
		var hint := _ink("Click an item to see what it does. Hover gear to compare it with what you're wearing.", 14, false, COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(hint)
		return
	var def: ItemDef = ItemDB.get_item(item_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_detail.add_child(head)
	var icon := ItemSlotView.new(44).set_padding(SLOT_PAD).show_item(item_id, count)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(icon)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var title := _ink(ItemSlotView.item_name(item_id), 18, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(title)
	if def != null:
		hv.add_child(_ink(("Worn  ·  " if worn else "") + category_line(def), 12, false, COL_MUTED))

	if def != null and def.description != "":
		var d := _ink(def.description, 13)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(d)
	var facts := item_facts(def)
	if not facts.is_empty():
		var fl := _ink("\n".join(facts), 13)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(fl)

	# Compared with what you wear now (skipped when the slot is empty: the facts above say it all).
	var vs: StringName = inv.preview_stats(item_id).get("worn", &"") if (not worn and def != null) else &""
	if vs != &"":
		var lines := compare_lines(item_id)
		_detail.add_child(_ink("Instead of your %s:" % ItemSlotView.item_name(vs), 13, true, COL_MUTED))
		if lines.is_empty():
			_detail.add_child(_ink("No change to your stats", 13, false, COL_MUTED))
		for ln: Array in lines:
			_detail.add_child(_ink(ln[0], 13, true, COL_UP if ln[1] else COL_DOWN))

	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 4)
	acts.add_theme_constant_override("v_separation", 4)
	_detail.add_child(acts)
	if worn:
		_action(acts, "Unequip", func() -> void:
			if not inv.unequip_item(_selected_equip):
				_toast("No room in your bag.")
			_selected_equip = &""
			refresh())
		return
	var idx := _selected_slot_idx
	if def != null and def.equip_slot != &"":
		_action(acts, "Equip", func() -> void:
			inv.equip_item_from_slot(idx)
			refresh())
	if def != null and def.category == ItemDef.Category.FOOD:
		var full: bool = player.vitality.is_full_of(def.id)
		var b := _action(acts, ("Full · %d min" % maxi(1, ceili(player.vitality.reeat_wait_sec(def.id) / 60.0))) if full else "Eat",
			func() -> void:
				if player.vitality.eat_food(def.id, inv):
					_toast("Ate %s" % def.name)
				refresh())
		b.disabled = not player.vitality.can_eat_food(def.id)
	if idx >= Inventory.MAX_HOTBAR_SLOTS:
		_action(acts, "To hotbar", func() -> void:
			inv.move_to_hotbar(idx)
			player._sync_tool_from_hotbar()
			refresh())
	else:
		_action(acts, "To bag", func() -> void:
			inv.quick_transfer_slot(idx)
			player._sync_tool_from_hotbar()
			refresh())
	_action(acts, "Drop 1", func() -> void:
		player.drop_item_from_inventory(idx, 1)
		refresh())
	if count > 1:
		_action(acts, "Drop all", func() -> void:
			player.drop_item_from_inventory(idx, -1)
			refresh())


func _action(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


## "N things you can make" summary that links to the Crafting page.
func _refresh_craft_card(inv: Inventory) -> void:
	var ready_n := 0
	var names: Array[String] = []
	for r: RecipeDef in RecipeDB.get_station_exclusive_recipes(&"none"):
		if (player.recipes == null or player.recipes.knows(r.id)) and r.can_craft_with(inv):
			ready_n += 1
			if names.size() < 3:
				names.append(r.name)
	if ready_n == 0:
		_craft_card_lbl.text = "Nothing to make by hand with what you're carrying. Stations like the workbench and campfire have more."
	else:
		_craft_card_lbl.text = "You can make %d thing%s by hand right now: %s%s" % [
			ready_n, "" if ready_n == 1 else "s", ", ".join(names), " and more." if ready_n > names.size() else "."]


# -------------------------------------------------------------------------
# Hover card
# -------------------------------------------------------------------------

func _show_hover_label(item_id: StringName, count: int, prefix: String = "", worn := false) -> void:
	if _hover_panel == null or item_id == &"":
		_hide_hover_label()
		return
	var def: ItemDef = ItemDB.get_item(item_id)
	var title := ItemSlotView.item_name(item_id) + ((" x%d" % count) if count > 1 else "")
	if prefix != "":
		title = "%s: %s" % [prefix, title]
	var sub := ""
	if def != null:
		var facts := item_facts(def)
		sub = category_line(def) + (("  ·  " + facts[0]) if not facts.is_empty() else "")
	_fill_hover(title, sub, [] if worn else compare_lines(item_id))


func _show_hover_text(title: String, sub: String) -> void:
	_fill_hover(title, sub, [])


func _fill_hover(title: String, sub: String, lines: Array) -> void:
	_clear(_hover_box)
	var t := Label.new()
	t.text = title
	t.add_theme_font_override("font", UiTheme.font(800))
	t.add_theme_font_size_override("font_size", 15)
	_hover_box.add_child(t)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.theme_type_variation = &"Small"
		s.add_theme_font_size_override("font_size", 13)
		_hover_box.add_child(s)
	for ln: Array in lines:
		var l := Label.new()
		l.text = ln[0]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color8(150, 226, 160) if ln[1] else Color8(240, 130, 110))
		_hover_box.add_child(l)
	_hover_panel.reset_size()
	_hover_panel.visible = true
	var anchor := _pointer_pos()
	_hover_panel.position = anchor + Vector2(18.0, 18.0)


func _hide_hover_label() -> void:
	if _hover_panel != null:
		_hover_panel.visible = false
