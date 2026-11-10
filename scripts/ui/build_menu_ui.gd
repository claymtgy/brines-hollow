class_name BuildMenuUI
extends CanvasLayer
## Hammer Build Menu (Valheim / Necesse / Minecraft style).
## Appears automatically when the player has a Hammer equipped in their active hotbar slot:
##   * Compact HUD Build Banner above the hotbar showing current mode, piece/block, and material cost.
##   * Full Interactive Build Catalogue (toggled with B or RMB while holding a Hammer) with 3 tabs:
##       1. Fabricated Pieces (12 architectural voxel prefabs)
##       2. Individual Blocks (21 voxel block materials + brush size selector)
##       3. Workstations & Furniture (13 placeable entities)

enum Tab { PREFABS, BLOCKS, FURNITURE }

var main: Node
var player: Player

var _root: Control
var _compact_banner: PanelContainer
var _compact_mode_label: Label
var _compact_item_icon: TextureRect
var _compact_item_label: Label
var _compact_cost_label: Label

var _modal_backdrop: Control
var _tab_buttons: Array[Button] = []
var _brush_row: HBoxContainer
var _brush_buttons: Array[Button] = []
var _grid_scroll: ScrollContainer
var _items_grid: GridContainer
var _footer_label: Label

var current_tab: int = Tab.BLOCKS
var _expanded: bool = false


func _ready() -> void:
	layer = 14
	_build()
	_root.visible = false
	_modal_backdrop.visible = false


func setup(p_main: Node) -> void:
	main = p_main


func is_expanded() -> bool:
	return _expanded


func open_catalogue() -> void:
	if main != null and main.player != null:
		player = main.player
	if player == null or not player.is_hammer_equipped():
		return
	_expanded = true
	_root.visible = true
	_modal_backdrop.visible = true
	current_tab = player.hammer_build_mode
	refresh_catalogue()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false


func close_catalogue() -> void:
	if not _expanded:
		return
	_expanded = false
	_modal_backdrop.visible = false
	if player != null:
		player.input_enabled = true
	if main == null or ((main.settings_menu == null or not main.settings_menu.is_open()) and (main.get("inventory_ui") == null or not main.inventory_ui.is_open())):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle_catalogue() -> void:
	if _expanded:
		close_catalogue()
	else:
		open_catalogue()


func _input(e: InputEvent) -> void:
	if not _expanded:
		return
	if e.is_action_pressed("build_menu_toggle") or e.is_action_pressed("menu_toggle") or e.is_action_pressed("inventory_toggle"):
		get_viewport().set_input_as_handled()
		close_catalogue()


# -------------------------------------------------------------------------
# UI Construction
# -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	UiTheme.prepare(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# 1. Compact HUD Build Banner (docked above the bottom hotbar when Hammer is equipped)
	var banner_anchor := CenterContainer.new()
	banner_anchor.anchor_top = 1.0
	banner_anchor.anchor_bottom = 1.0
	banner_anchor.anchor_right = 1.0
	banner_anchor.offset_top = -196
	banner_anchor.offset_bottom = -124
	banner_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(banner_anchor)

	_compact_banner = PanelContainer.new()
	_compact_banner.theme_type_variation = &"Plaque"
	_compact_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_anchor.add_child(_compact_banner)

	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 10)
	bh.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compact_banner.add_child(bh)

	var hammer_ic := UiTheme.icon(ItemIcons.for_tool(ItemIcons.Tool.HAMMER), 32)
	hammer_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh.add_child(hammer_ic)

	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 2)
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bh.add_child(bv)

	var top_r := HBoxContainer.new()
	top_r.add_theme_constant_override("separation", 8)
	top_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(top_r)

	_compact_mode_label = Label.new()
	_compact_mode_label.theme_type_variation = &"Header"
	_compact_mode_label.add_theme_font_size_override("font_size", 16)
	_compact_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_r.add_child(_compact_mode_label)

	_compact_item_icon = UiTheme.icon(null, 24)
	_compact_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_r.add_child(_compact_item_icon)

	_compact_item_label = Label.new()
	_compact_item_label.add_theme_font_size_override("font_size", 16)
	_compact_item_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_r.add_child(_compact_item_label)

	_compact_cost_label = Label.new()
	_compact_cost_label.theme_type_variation = &"Small"
	_compact_cost_label.add_theme_font_size_override("font_size", 14)
	_compact_cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bv.add_child(_compact_cost_label)

	# 2. Expanded Interactive Build Catalogue Modal (B / RMB)
	_modal_backdrop = Control.new()
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal_backdrop)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.10, 0.52)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 540)
	UiTheme.keep_on_screen(panel)
	center.add_child(panel)

	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	panel.add_child(mv)

	# Header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	mv.add_child(head)

	head.add_child(UiTheme.icon(ItemIcons.for_tool(ItemIcons.Tool.HAMMER), 36))
	var title := Label.new()
	title.text = "Builder's Hammer — Construction Catalogue"
	title.theme_type_variation = &"Header"
	title.add_theme_font_size_override("font_size", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Close (B / Esc)"
	close_btn.pressed.connect(close_catalogue)
	head.add_child(close_btn)

	# Category Tabs + Brush Selector Row
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	mv.add_child(tab_row)

	var tab_defs := [
		[Tab.PREFABS, "Fabricated Pieces (Prefabs)"],
		[Tab.BLOCKS, "Individual Blocks"],
		[Tab.FURNITURE, "Workstations & Furniture"],
	]
	for td: Array in tab_defs:
		var t_idx: int = td[0]
		var btn := Button.new()
		btn.text = td[1]
		btn.pressed.connect(func() -> void:
			current_tab = t_idx
			if player != null:
				player.set_hammer_build_mode(t_idx)
			refresh_catalogue()
		)
		tab_row.add_child(btn)
		_tab_buttons.append(btn)

	# Brush size buttons (visible when in Individual Blocks tab)
	_brush_row = HBoxContainer.new()
	_brush_row.add_theme_constant_override("separation", 4)
	_brush_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brush_row.alignment = BoxContainer.ALIGNMENT_END
	tab_row.add_child(_brush_row)

	var b_lbl := Label.new()
	b_lbl.text = "Block Size:"
	b_lbl.theme_type_variation = &"Small"
	_brush_row.add_child(b_lbl)

	var brush_labels := ["1x1 (Single)", "3x3", "5x5", "7x7", "11x11"]
	for bi in brush_labels.size():
		var b_btn := Button.new()
		b_btn.text = brush_labels[bi]
		b_btn.pressed.connect(func() -> void:
			if player != null:
				player.brush = bi
				player._on_brush_changed()
				refresh_catalogue()
		)
		_brush_row.add_child(b_btn)
		_brush_buttons.append(b_btn)

	# Parchment Scroll Grid
	var page := PanelContainer.new()
	page.theme_type_variation = &"Parchment"
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mv.add_child(page)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(_grid_scroll)

	_items_grid = GridContainer.new()
	_items_grid.columns = 3
	_items_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items_grid.add_theme_constant_override("h_separation", 10)
	_items_grid.add_theme_constant_override("v_separation", 8)
	_grid_scroll.add_child(_items_grid)

	# Footer
	_footer_label = Label.new()
	_footer_label.theme_type_variation = &"Small"
	_footer_label.text = "Click any piece or block to select it, then LMB in the world to build. R rotates pieces; G toggles grid snap."
	mv.add_child(_footer_label)


# -------------------------------------------------------------------------
# Per-Frame HUD Update & Catalogue Refresh
# -------------------------------------------------------------------------

func update_for_player(p: Player) -> void:
	player = p
	if player == null or not player.is_hammer_equipped() or player.is_seated():
		if _expanded:
			close_catalogue()
		_root.visible = false
		return

	_root.visible = true
	_compact_banner.visible = not _expanded
	_update_compact_banner()


## Is the compact hammer banner on screen? (the HUD then hides its own tool line)
func is_banner_visible() -> bool:
	return _root != null and _root.visible and _compact_banner != null and _compact_banner.visible


## Key hints in the banner, for whatever device the player is using right now.
func _keys(parts: Array) -> String:
	var c: ControllerManager = main.controller if main != null and main.get("controller") != null else null
	var pad := c != null and c.current_type != ControllerManager.Type.KEYBOARD_MOUSE
	var out := []
	for p: Array in parts:
		var k: String
		match p[0]:
			"menu": k = c.get_glyph(&"build_menu_toggle") if pad else "RMB/B"
			"cycle": k = "D-Pad L/R" if pad else "Q/E"
			"size": k = "D-Pad U/D" if pad else "Z/X"
			"rotate": k = c.get_glyph(&"rotate") if pad else "R"
			_: k = String(p[0])
		out.append("[%s] %s" % [k, p[1]])
	return "  ".join(out)


func _update_compact_banner() -> void:
	if player == null:
		return
	var inv: Inventory = player.inventory
	match player.hammer_build_mode:
		Tab.PREFABS:
			_compact_mode_label.text = "[Hammer: Fabricated Piece]"
			var pf: Dictionary = Prefabs.all()[clampi(player.prefab_id, 0, Prefabs.count() - 1)]
			_compact_item_icon.texture = ItemIcons.for_tool(ItemIcons.Tool.BLUEPRINT)
			_compact_item_label.text = "%s  (Snap: %s)" % [pf.name, "On" if player.snap else "Off"]
			var cost := BuildCosts.prefab_cost(player.prefab_id, player.prefab_rot)
			var ok := BuildCosts.can_afford(inv, cost)
			var cost_str := BuildCosts.describe(cost)
			_compact_cost_label.text = "%s  ·  %s" % [
				("Cost: %s (Ready)" % cost_str) if ok else ("Need: %s" % BuildCosts.describe_missing(inv, cost)),
				_keys([["menu", "Build Menu"], ["cycle", "Piece"], ["rotate", "Rotate"]])
			]
			_compact_cost_label.modulate = Color(0.68, 1.0, 0.72) if ok else Color(1.0, 0.62, 0.55)

		Tab.BLOCKS:
			_compact_mode_label.text = "[Hammer: Block]"
			var m: int = player.current_material()
			var r: int = Player.BRUSHES[clampi(player.brush, 0, Player.BRUSHES.size() - 1)]
			_compact_item_icon.texture = ItemIcons.for_material(m)
			var span := r * 2 + 1
			_compact_item_label.text = "%s  (%dx%dx%d)" % [Palette.NAMES[m], span, span, span]
			var item_id := BuildCosts.item_for(m)
			var def := ItemDB.get_item(item_id)
			var have := inv.get_item_count(item_id)
			var item_name := def.name if def != null else String(item_id)
			_compact_cost_label.text = "Uses %s (Have: %d)  ·  %s" % [item_name, have,
				_keys([["menu", "Build Menu"], ["cycle", "Block"], ["size", "Size"]])]
			_compact_cost_label.modulate = Color(0.68, 1.0, 0.72) if have > 0 else Color(1.0, 0.62, 0.55)

		Tab.FURNITURE:
			_compact_mode_label.text = "[Hammer: Furniture]"
			var types := Placeables.blueprint_types()
			var f_type: StringName = player.placement.entity_blueprint if player.placement != null and player.placement.entity_blueprint != &"" else (types[0] if not types.is_empty() else &"workbench")
			var def := ItemDB.get_item(f_type)
			_compact_item_icon.texture = ItemIcons.for_item(f_type)
			_compact_item_label.text = def.name if def != null else String(f_type)
			var cost := Placeables.build_cost(f_type)
			var ok := BuildCosts.can_afford(inv, cost)
			_compact_cost_label.text = "%s  ·  %s" % [
				("Cost: %s (Ready)" % BuildCosts.describe(cost)) if ok else ("Need: %s" % BuildCosts.describe_missing(inv, cost)),
				_keys([["menu", "Build Menu"], ["cycle", "Item"], ["rotate", "Rotate"]])
			]
			_compact_cost_label.modulate = Color(0.68, 1.0, 0.72) if ok else Color(1.0, 0.62, 0.55)


func refresh_catalogue() -> void:
	if player == null or player.inventory == null:
		return
	var inv: Inventory = player.inventory

	for i in _tab_buttons.size():
		_tab_buttons[i].modulate = Color(1.0, 0.96, 0.80) if i == current_tab else Color(0.82, 0.80, 0.76)

	_brush_row.visible = (current_tab == Tab.BLOCKS)
	for bi in _brush_buttons.size():
		_brush_buttons[bi].modulate = Color(0.75, 1.0, 0.82) if bi == player.brush else Color.WHITE

	for c in _items_grid.get_children():
		c.queue_free()

	match current_tab:
		Tab.PREFABS:
			_items_grid.columns = 3
			var prefabs := Prefabs.all()
			for id in prefabs.size():
				var pf: Dictionary = prefabs[id]
				var cost := BuildCosts.prefab_cost(id, player.prefab_rot)
				var ok := BuildCosts.can_afford(inv, cost)
				var is_sel := (player.hammer_build_mode == Tab.PREFABS and player.prefab_id == id)
				_items_grid.add_child(_make_catalogue_card(
					ItemIcons.for_tool(ItemIcons.Tool.BLUEPRINT),
					String(pf.name),
					"Cost: " + BuildCosts.describe(cost),
					"Materials available" if ok else ("Missing: " + BuildCosts.describe_missing(inv, cost)),
					ok,
					is_sel,
					func() -> void:
						player.select_hammer_prefab(id)
						close_catalogue()
				))

		Tab.BLOCKS:
			_items_grid.columns = 3
			for idx in Palette.BUILDABLE.size():
				var m: int = Palette.BUILDABLE[idx]
				var res_id := BuildCosts.item_for(m)
				var res_def := ItemDB.get_item(res_id)
				var res_name := res_def.name if res_def != null else String(res_id)
				var have := inv.get_item_count(res_id)
				var ok := have > 0
				var is_sel := (player.hammer_build_mode == Tab.BLOCKS and player.mat_index == idx)
				_items_grid.add_child(_make_catalogue_card(
					ItemIcons.for_material(m),
					Palette.NAMES[m],
					"Material: %s (1 per 4 blocks)" % res_name,
					"In Bag: %d %s" % [have, res_name],
					ok,
					is_sel,
					func() -> void:
						player.select_hammer_block(idx)
						close_catalogue()
				))

		Tab.FURNITURE:
			_items_grid.columns = 3
			var types := Placeables.blueprint_types()
			for t: StringName in types:
				var def := ItemDB.get_item(t)
				var label := def.name if def != null else String(t)
				var cost := Placeables.build_cost(t)
				var ok := BuildCosts.can_afford(inv, cost)
				var is_sel := (player.hammer_build_mode == Tab.FURNITURE and player.placement != null and player.placement.entity_blueprint == t)
				_items_grid.add_child(_make_catalogue_card(
					ItemIcons.for_item(t),
					label,
					"Cost: " + BuildCosts.describe(cost),
					"Materials available" if ok else ("Missing: " + BuildCosts.describe_missing(inv, cost)),
					ok,
					is_sel,
					func() -> void:
						player.select_hammer_furniture(t)
						close_catalogue()
				))


func _make_catalogue_card(
	icon_tex: Texture2D,
	title_text: String,
	cost_text: String,
	status_text: String,
	can_afford: bool,
	is_selected: bool,
	on_select: Callable
) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"SlotSelected" if is_selected else &"Slot"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(260, 82)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(h)

	var ic := UiTheme.icon(icon_tex, 42)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)

	var t := Label.new()
	t.text = title_text
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", UiTheme.BRASS if is_selected else UiTheme.CREAM)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)

	var c := Label.new()
	c.text = cost_text
	c.theme_type_variation = &"Small"
	c.add_theme_font_size_override("font_size", 14)
	c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(c)

	var st := Label.new()
	st.text = status_text
	st.theme_type_variation = &"Small"
	st.add_theme_font_size_override("font_size", 14)
	st.add_theme_color_override("font_color", Color(0.65, 0.98, 0.70) if can_afford else Color(1.0, 0.58, 0.52))
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(st)

	card.mouse_entered.connect(func() -> void:
		card.theme_type_variation = &"SlotSelected"
		card.self_modulate = Color(1.08, 1.04, 0.94)
	)
	card.mouse_exited.connect(func() -> void:
		card.theme_type_variation = &"SlotSelected" if is_selected else &"Slot"
		card.self_modulate = Color.WHITE
	)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			on_select.call()
	)
	return card
