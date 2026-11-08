class_name TradeUI
extends CanvasLayer
## Merchant trade window: buy / sell lists priced in brass, plus export manifests.
## Opened by TradeManager; F, Esc or Close shuts it.

var trade: TradeManager
var _root: Control
var _title: Label
var _brass: Label
var _buy_list: VBoxContainer
var _sell_list: VBoxContainer
var _contract_list: VBoxContainer


func _ready() -> void:
	layer = 15
	_build()
	visible = false


func open() -> void:
	if trade.current() == null:
		return
	visible = true
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if trade.main.player != null:
		trade.main.player.input_enabled = false


func close() -> void:
	visible = false
	if trade.main.player != null:
		trade.main.player.input_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(e: InputEvent) -> void:
	if visible and (e.is_action_pressed("menu_toggle") or e.is_action_pressed("interact")):
		get_viewport().set_input_as_handled()
		close()


func _build() -> void:
	# Crafted look: a weathered-wood frame around a parchment ledger, brass fittings for
	# buttons, dark ink text. (No flat web panels / pill buttons.)
	_root = Control.new()
	UiTheme.prepare(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.10, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 520)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = &"Header"
	_title.add_theme_font_size_override("font_size", 30)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var coin := TextureRect.new()
	coin.texture = ItemIcons.for_item(&"brass_guilder")
	coin.custom_minimum_size = Vector2(36, 36)
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(coin)
	_brass = Label.new()
	_brass.theme_type_variation = &"Header"
	head.add_child(_brass)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	v.add_child(cols)
	_buy_list = _column(cols, "Buy from the merchant")
	_sell_list = _column(cols, "Sell your goods")
	_contract_list = _column(cols, "Export manifests")
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(foot)
	var close_b := Button.new()
	close_b.text = "Close (F)"
	close_b.pressed.connect(close)
	foot.add_child(close_b)


func _column(parent: Control, title: String) -> VBoxContainer:
	var page := PanelContainer.new()        # a parchment ledger page per column
	page.theme_type_variation = &"Parchment"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(page)
	var v := VBoxContainer.new()
	page.add_child(v)
	var l := Label.new()
	l.text = title
	l.theme_type_variation = &"InkLabel"
	l.add_theme_color_override("font_color", Color(0.48, 0.18, 0.12))   # ledger-ink red
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_font_override("font", UiTheme.font(800))
	v.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list


func refresh() -> void:
	if not visible or trade == null:
		return
	var m: MerchantBoat = trade.current()
	if m == null:
		close()
		return
	var inv: Inventory = trade.main.player.inventory
	_title.text = m.merchant_name
	_brass.text = "%d" % inv.get_item_count(&"brass_guilder")
	for list in [_buy_list, _sell_list, _contract_list]:
		for c in list.get_children():
			c.queue_free()
	for item: StringName in m.selling_prices:
		var have := m.stock.get_item_count(item)
		if have <= 0:
			continue
		var price: int = m.selling_prices[item]
		_row(_buy_list, "%s  x%d\n%d brass" % [TradeManager._item_name(item), have, price], "Buy",
				inv.get_item_count(&"brass_guilder") >= price, func() -> void: trade.request_buy(item, 1), item)
	for item: StringName in m.buying_prices:
		var n := inv.get_item_count(item)
		if n <= 0:
			continue
		var price: int = m.buying_prices[item]
		_row(_sell_list, "%s  x%d\n%d brass each" % [TradeManager._item_name(item), n, price], "Sell 1", true,
				func() -> void: trade.request_sell(item, 1), item)
		if n > 1:
			_row(_sell_list, "      all %d for %d" % [n, n * price], "Sell all", true,
					func() -> void: trade.request_sell(item, inv.get_item_count(item)))
	if _sell_list.get_child_count() == 0:
		_note(_sell_list, "Nothing they want. They buy fish, crops, salt, stone and driftwood.")
	for c: TradeContract in m.active_contracts:
		var need := []
		for it in c.required_items:
			need.append("%d %s" % [c.required_items[it], TradeManager._item_name(StringName(it))])
		var txt := "%s\nNeeds %s\nPays %d brass + %d scrip" % [c.title, ", ".join(need), c.payout_brass, c.payout_scrip]
		var cid := c.id
		_row(_contract_list, txt, "Shipped" if c.is_fulfilled else "Ship", not c.is_fulfilled and c.can_fulfill(inv),
				func() -> void: trade.request_fulfill(cid))
	if m.active_contracts.is_empty():
		_note(_contract_list, "No manifests on this ship. Trade galleons carry export orders.")


func _row(list: VBoxContainer, text: String, button: String, enabled: bool, cb: Callable, item: StringName = &"") -> void:
	var h := HBoxContainer.new()
	if item != &"":
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"Slot"
		var icon := TextureRect.new()
		icon.texture = ItemIcons.for_item(item)
		icon.custom_minimum_size = Vector2(36, 36)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.add_child(icon)
		slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(slot)
	var l := Label.new()
	l.theme_type_variation = &"InkLabel"
	l.custom_minimum_size = Vector2(90, 0)
	l.text = text
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item != &"":
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
	else:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
	h.add_child(l)
	var b := Button.new()
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(92, 0)
	b.text = button
	b.disabled = not enabled
	b.pressed.connect(cb)
	h.add_child(b)
	list.add_child(h)


func _note(list: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.theme_type_variation = &"InkLabel"
	l.add_theme_color_override("font_color", Color(0.42, 0.34, 0.26))
	list.add_child(l)
