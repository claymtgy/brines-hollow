class_name CookOrdersUI
extends CanvasLayer
## "Pantry Orders": talk to the village cook to set how many of each meal the town keeps
## in store. The cook cooks on shift until every meal is at its number.
##
## Click - / + (Shift: by 1), or arrows: Up/Down pick a meal, Left/Right change it.
## Esc / F / B closes.

signal closed

const COL_OK := Color8(70, 120, 70)
const COL_SHORT := Color8(150, 70, 55)
const COL_MUTED := Color8(120, 92, 70)
const REFRESH_SEC := 0.5

var village: Node                  ## VillageManager
var cook_name := "The cook"
var _sel := 0
var _refresh_t := 0.0
var _items: Array[StringName] = []

var _root: Control
var _title: Label
var _where: Label
var _list: VBoxContainer
var _rows: Array[Dictionary] = []  ## {panel, status, stock, target}


func _ready() -> void:
	layer = 16
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open(p_village: Node, p_cook_name: String) -> void:
	village = p_village
	cook_name = p_cook_name
	_sel = 0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var p := _player()
	if p != null:
		p.input_enabled = false
	_rebuild()


func close() -> void:
	if not visible:
		return
	visible = false
	var p := _player()
	if p != null:
		p.input_enabled = true
	var m: Node = village.main if village != null else null
	if m == null or not m.has_method("is_any_menu_open") or not m.is_any_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _player() -> Player:
	if village != null and village.main != null and village.main.get("player") != null:
		return village.main.player
	return null


func _orders() -> CookOrders:
	return village.cook_orders() if village != null else null


func _book() -> RecipeBook:
	var p := _player()
	return p.recipes if p != null else null


# ------------------------------------------------------------------ build

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
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var page := PanelContainer.new()
	page.theme_type_variation = &"Parchment"
	page.custom_minimum_size = Vector2(760, 580)
	center.add_child(page)
	UiTheme.keep_on_screen(page)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	page.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	_title = _ink("Pantry Orders", 24, true)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var blurb := _ink("", 14, false, COL_MUTED)
	blurb.name = "Blurb"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(blurb)
	_where = _ink("", 14)
	_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_where)
	v.add_child(HSeparator.new())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	v.add_child(cols)
	var h1 := _ink("Meal", 13, true, COL_MUTED)
	h1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h1.custom_minimum_size.x = 60
	cols.add_child(h1)
	var h2 := _ink("In store", 13, true, COL_MUTED)
	h2.custom_minimum_size.x = 80
	h2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cols.add_child(h2)
	var h3 := _ink("Keep", 13, true, COL_MUTED)
	h3.custom_minimum_size.x = 150
	h3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cols.add_child(h3)
	var pad := Control.new()
	pad.custom_minimum_size.x = 12
	cols.add_child(pad)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	var foot := _ink("", 13, false, COL_MUTED)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.text = "- / +: change by %d (Shift: by 1)  ·  Up / Down: pick  ·  Left / Right: change  ·  Esc: close" % CookOrders.STEP
	v.add_child(foot)


func _ink(text: String, fsize: int = 14, bold := false, col := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"InkLabel"
	l.add_theme_font_size_override("font_size", fsize)
	if bold:
		l.add_theme_font_override("font", UiTheme.font(800))
	if col.a > 0.0:
		l.add_theme_color_override("font_color", col)
	return l


# ------------------------------------------------------------------ refresh

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_items.clear()
	_title.text = "%s's Pantry Orders" % cook_name
	(_root.find_child("Blurb", true, false) as Label).text = (
		"Set how many of each meal the town should keep in store. On shift, %s takes ingredients "
		+ "from the pantry barrels, stockpile chest and depot, cooks at the town's fires and pots, "
		+ "and puts the dishes back until each is at its number. 0 means don't cook it.") % cook_name
	var meals := CookOrders.meal_recipes(_book())
	if meals.is_empty():
		_list.add_child(_ink("You don't know any meals yet. Learn recipes and %s can cook them." % cook_name, 15, false, COL_MUTED))
	for r in meals:
		_items.append(r.output_item_id)
		_list.add_child(_row(r, _items.size() - 1))
	_sel = clampi(_sel, 0, maxi(0, _items.size() - 1))
	_refresh()


func _row(r: RecipeDef, i: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	CraftingUI._style_row(p, i == _sel)
	CraftingUI._hookup_hover(p)
	p.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_select(i))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	var icon := ItemSlotView.new(40).show_item(r.output_item_id, r.output_count)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(icon)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(names)
	var nm := _ink(ItemSlotView.item_name(r.output_item_id), 16, true)
	nm.clip_text = true
	names.add_child(nm)
	var st_name := StringName(r.required_station)
	var where := String(st_name).capitalize()
	if Placeables.BUILTIN.has(st_name):
		where = String(Placeables.BUILTIN[st_name][0])
	var sub := _ink("%s  ·  %d s  ·  makes %d" % [where, int(r.craft_time_sec), r.output_count], 12, false, COL_MUTED)
	sub.clip_text = true
	names.add_child(sub)
	var status := _ink("", 12)
	names.add_child(status)

	var stock := _ink("0", 18, true)
	stock.custom_minimum_size.x = 80
	stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(stock)

	var keep := HBoxContainer.new()
	keep.custom_minimum_size.x = 150
	keep.alignment = BoxContainer.ALIGNMENT_CENTER
	keep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(keep)
	var minus := Button.new()
	minus.text = "-"
	minus.custom_minimum_size = Vector2(34, 32)
	minus.focus_mode = Control.FOCUS_NONE
	minus.pressed.connect(func() -> void:
		_select(i)
		_bump(r.output_item_id, -(1 if Input.is_key_pressed(KEY_SHIFT) else CookOrders.STEP)))
	keep.add_child(minus)
	var target := _ink("0", 20, true)
	target.custom_minimum_size.x = 52
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.add_child(target)
	var plus := Button.new()
	plus.text = "+"
	plus.custom_minimum_size = Vector2(34, 32)
	plus.focus_mode = Control.FOCUS_NONE
	plus.pressed.connect(func() -> void:
		_select(i)
		_bump(r.output_item_id, 1 if Input.is_key_pressed(KEY_SHIFT) else CookOrders.STEP))
	keep.add_child(plus)
	_rows.append({"panel": p, "status": status, "stock": stock, "target": target})
	return p


func _refresh() -> void:
	var orders := _orders()
	if orders == null:
		return
	var stores: Array = village.town_stores() if village.has_method("town_stores") else []
	var stations: Array = village.town_cook_stations() if village.has_method("town_cook_stations") else []
	if stations.is_empty():
		_where.text = "There's no cooking fire or pot in town yet: build a Campfire or Hearth Stew Pot near the hearth."
		_where.add_theme_color_override("font_color", COL_SHORT)
	else:
		var names: Array[String] = []
		for st: StationEntity in stations:
			if not names.has(st.entity_name):
				names.append(st.entity_name)
		_where.text = "Cooks at: %s" % ", ".join(names)
		_where.add_theme_color_override("font_color", UiTheme.INK)
	var book := _book()
	for i in _rows.size():
		var id := _items[i]
		var row: Dictionary = _rows[i]
		var have := CookOrders.count_in(stores, id)
		var want := orders.target(id)
		(row.stock as Label).text = str(have)
		(row.target as Label).text = str(want) if want > 0 else "off"
		(row.target as Label).add_theme_color_override("font_color", UiTheme.INK if want > 0 else COL_MUTED)
		var s := orders.status(id, stores, book)
		var lbl: Label = row.status
		lbl.text = s
		var col := COL_MUTED
		if s == "Stocked":
			col = COL_OK
		elif s.begins_with("Needs") or s == "Recipe unknown":
			col = COL_SHORT
		elif s.begins_with("Cooking"):
			col = Color8(176, 120, 52)
		lbl.add_theme_color_override("font_color", col)
		(row.stock as Label).add_theme_color_override("font_color",
			COL_OK if want > 0 and have >= want else (COL_SHORT if want > 0 else UiTheme.INK))


func _select(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	_sel = i
	for k in _rows.size():
		CraftingUI._style_row(_rows[k].panel, k == _sel)
	var scroll := _list.get_parent() as ScrollContainer
	if scroll != null:
		scroll.ensure_control_visible(_rows[_sel].panel)


func _bump(item_id: StringName, by: int) -> void:
	var orders := _orders()
	if orders == null:
		return
	set_target(item_id, orders.target(item_id) + by)


func set_target(item_id: StringName, n: int) -> void:
	if village != null and village.has_method("set_cook_order"):
		village.set_cook_order(item_id, n)
	_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = REFRESH_SEC
		_refresh()


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu_toggle") or e.is_action_pressed("interact"):
		close()
		get_viewport().set_input_as_handled()
		return
	if _items.is_empty():
		return
	var step := 1 if Input.is_key_pressed(KEY_SHIFT) else CookOrders.STEP
	if e.is_action_pressed("ui_down"):
		_select(mini(_sel + 1, _items.size() - 1))
	elif e.is_action_pressed("ui_up"):
		_select(maxi(_sel - 1, 0))
	elif e.is_action_pressed("ui_right"):
		_bump(_items[_sel], step)
	elif e.is_action_pressed("ui_left"):
		_bump(_items[_sel], -step)
	else:
		return
	get_viewport().set_input_as_handled()
