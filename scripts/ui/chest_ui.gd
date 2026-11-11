class_name ChestUI
extends CanvasLayer
## The Chest screen: what's in a chest, crate or barrel on the left, your pack on the right.
## Opened by InventoryUI.open(chest), so every caller that opened the old Pack + chest view
## lands here instead.
##
## Mouse:
##   Click            Move the whole stack across
##   Right-click      Move one
##   Shift + Click    Move every stack of that kind across
## Pad: A = move stack, X = move one, Y = move all of that kind, B = close.
##
## Moves go through the chest's server actions (deposit / take_slot / sort), so two
## players can't duplicate items, and nothing is taken that wouldn't fit in your pack.

signal closed

const SLOT_PX := 44.0
const SLOT_PAD := 5.0
const COL_MUTED := Color8(120, 92, 70)
const HOVER_TINT := Color(1.1, 1.06, 0.95)
const MAX_DISTANCE := 8.0

var main: Node
var player: Player
var chest: ChestEntity

var _root: Control
var _title: Label
var _notes: Label
var _chest_label: Label
var _chest_grid: GridContainer
var _hotbar_row: HBoxContainer
var _bag_grid: GridContainer
var _bag_label: Label
var _chest_views: Array[ItemSlotView] = []
var _pack_views: Array[ItemSlotView] = []
var _built_chest_cap := -1
var _built_pack_cap := -1
var _hover_panel: PanelContainer
var _hover_box: VBoxContainer
var _hover_side := &""      ## &"chest" or &"pack"
var _hover_idx := -1
var _pad_input := false
var _dirty := false
var _opened_ms := 0


func _ready() -> void:
	layer = 16
	_build()
	visible = false


func is_open() -> bool:
	return visible


func open(p_player: Player, p_chest: ChestEntity, p_main: Node = null) -> void:
	if p_player == null or p_player.inventory == null or p_chest == null:
		return
	main = p_main
	player = p_player
	if chest != null and chest != p_chest:
		_unbind()
	chest = p_chest
	_bind()
	_built_chest_cap = -1
	visible = true
	_opened_ms = Time.get_ticks_msec()
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	_focus_first()


func close() -> void:
	if not visible:
		return
	visible = false
	_hide_hover()
	_unbind()
	chest = null
	if player != null:
		player.input_enabled = true
		player._sync_tool_from_hotbar()
	if main == null or not main.has_method("is_any_menu_open") or not main.is_any_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _bind() -> void:
	if chest != null and not chest.container.container_updated.is_connected(_mark_dirty):
		chest.container.container_updated.connect(_mark_dirty)
	if chest != null and not chest.state_changed.is_connected(_mark_dirty):
		chest.state_changed.connect(_mark_dirty)
	if not player.inventory.slot_changed.is_connected(_on_pack_changed):
		player.inventory.slot_changed.connect(_on_pack_changed)
	if not player.inventory.inventory_resized.is_connected(_on_pack_resized):
		player.inventory.inventory_resized.connect(_on_pack_resized)


func _unbind() -> void:
	if chest != null and is_instance_valid(chest):
		if chest.container.container_updated.is_connected(_mark_dirty):
			chest.container.container_updated.disconnect(_mark_dirty)
		if chest.state_changed.is_connected(_mark_dirty):
			chest.state_changed.disconnect(_mark_dirty)


func _mark_dirty() -> void:
	_dirty = true


func _on_pack_changed(_i: int, _s: ItemSlot) -> void:
	_dirty = true


func _on_pack_resized(_c: int) -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not visible:
		return
	if chest == null or not is_instance_valid(chest) or chest.is_queued_for_deletion():
		close()   # picked up or broken while open
		return
	if chest.is_inside_tree() and player.is_inside_tree() \
			and chest.global_position.distance_to(player.global_position) > MAX_DISTANCE:
		close()   # walked off (or got knocked away)
		return
	if _dirty:
		_dirty = false
		refresh()
	if _hover_panel.visible:
		var anchor := _pointer_pos()
		var vp := get_viewport().get_visible_rect().size
		var ps := _hover_panel.size
		_hover_panel.position = Vector2(
			clampf(anchor.x + 18.0, 8.0, maxf(8.0, vp.x - ps.x - 8.0)),
			clampf(anchor.y + 18.0, 8.0, maxf(8.0, vp.y - ps.y - 8.0)))


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
	var closing: bool = e.is_action_pressed("menu_toggle") or e.is_action_pressed("inventory_toggle") \
		or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B) \
		or (e.is_action_pressed("interact") and Time.get_ticks_msec() - _opened_ms > 200)
	if closing:
		get_viewport().set_input_as_handled()
		close()


# -------------------------------------------------------------------------
# Moves
# -------------------------------------------------------------------------

## Runs a chest action through the entity manager (server-checked), or directly when
## the chest isn't managed (tests, previews).
func _act(action: StringName, args: Dictionary) -> void:
	if chest.manager != null:
		chest.manager.request_action(chest, action, args)
	else:
		var res: Dictionary = chest.server_action(action, args, 0)
		for g: Array in res.get("grant", []):
			player.inventory.add_item(StringName(g[0]), int(g[1]))
	_dirty = true


## Take up to `n` (-1 = the whole stack) from chest slot `idx`, never more than fits.
func take(idx: int, n: int = -1) -> int:
	var cinv: Inventory = chest.container.inventory
	if idx < 0 or idx >= cinv.capacity or cinv.slots[idx].is_empty():
		return 0
	var s: ItemSlot = cinv.slots[idx]
	var want := s.count if n < 0 else mini(n, s.count)
	var amt := mini(want, player.inventory.room_for(s.item_id))
	if amt <= 0:
		_toast("No room in your pack.")
		return 0
	_act(&"take_slot", {"slot": idx, "n": amt})
	return amt


## Store up to `n` (-1 = the whole stack) from pack slot `idx`, never more than fits.
func store(idx: int, n: int = -1) -> int:
	var inv: Inventory = player.inventory
	if idx < 0 or idx >= inv.capacity or inv.slots[idx].is_empty():
		return 0
	var s: ItemSlot = inv.slots[idx]
	if not chest.container.can_accept_item(s.item_id):
		_toast(refusal_text(chest))
		return 0
	var want := s.count if n < 0 else mini(n, s.count)
	var amt := mini(want, chest.container.inventory.room_for(s.item_id))
	if amt <= 0:
		_toast("%s is full." % chest.entity_name)
		return 0
	var id := s.item_id
	var removed := inv.remove_from_slot(idx, amt)
	if removed > 0:
		_act(&"deposit", {"item": id, "n": removed, "quiet": true})
		if idx < Inventory.MAX_HOTBAR_SLOTS:
			player._sync_tool_from_hotbar()
	return removed


## Every stack of `item_id` from the chest.
func take_kind(item_id: StringName) -> void:
	var cinv: Inventory = chest.container.inventory
	for i in cinv.capacity:
		if cinv.slots[i].item_id == item_id and take(i) <= 0:
			break


## Every stack of `item_id` from the pack (the hotbar too: you asked for that kind).
func store_kind(item_id: StringName) -> void:
	var inv: Inventory = player.inventory
	for i in range(inv.capacity - 1, -1, -1):
		if inv.slots[i].item_id == item_id and store(i) <= 0:
			break


## Everything in the chest, as far as your pack has room.
func take_all() -> void:
	var cinv: Inventory = chest.container.inventory
	var got := 0
	var left := 0
	for i in cinv.capacity:
		if cinv.slots[i].is_empty():
			continue
		var before: int = cinv.slots[i].count
		var n := mini(before, player.inventory.room_for(cinv.slots[i].item_id))
		if n > 0:
			_act(&"take_slot", {"slot": i, "n": n})
			got += n
		left += before - n
	if left > 0:
		_toast("Your pack is full; %d left in the %s." % [left, _short_name()] if got > 0 else "No room in your pack.")


## Every backpack stack the chest takes. The hotbar stays as it is.
func store_all() -> void:
	_store_where(func(_id: StringName) -> bool: return true)


## Only what the chest already holds some of.
func store_matching() -> void:
	var have := {}
	for s: ItemSlot in chest.container.inventory.slots:
		if not s.is_empty():
			have[s.item_id] = true
	_store_where(func(id: StringName) -> bool: return have.has(id))


func _store_where(want: Callable) -> void:
	var inv: Inventory = player.inventory
	var moved := 0
	for i in range(Inventory.MAX_HOTBAR_SLOTS, inv.capacity):
		var s: ItemSlot = inv.slots[i]
		if s.is_empty() or not want.call(s.item_id) or not chest.container.can_accept_item(s.item_id):
			continue
		var n := mini(s.count, chest.container.inventory.room_for(s.item_id))
		if n <= 0:
			continue
		var id := s.item_id
		var removed := inv.remove_from_slot(i, n)
		if removed > 0:
			_act(&"deposit", {"item": id, "n": removed, "quiet": true})
			moved += removed
	if moved == 0:
		_toast("Nothing in your backpack to put in the %s." % _short_name())


func sort_chest() -> void:
	_act(&"sort", {})


func _toast(msg: String) -> void:
	if player != null and player.hud != null:
		player.hud.show_toast(msg)


func _short_name() -> String:
	match chest.style:
		&"barrel":
			return "barrel"
		&"crate":
			return "crate"
	return "chest"


static func refusal_text(c: ChestEntity) -> String:
	if not c.container.allowed_tags.is_empty():
		return "%s only holds %s." % [c.entity_name, " and ".join(Array(c.container.allowed_tags))]
	return "That won't go in %s." % c.entity_name


## One line on what makes this store special ("" for an ordinary chest).
static func notes_text(c: ChestEntity) -> String:
	var bits: Array[String] = []
	if not c.container.allowed_tags.is_empty():
		bits.append("Holds %s only" % " and ".join(Array(c.container.allowed_tags)))
	if c.container.preserves_freshness:
		bits.append("keeps your catch fresh")
	if c.sealed:
		bits.append("sealed: rats can't get in")
	elif c.style != &"barrel":
		bits.append("open: shore rats raid food left here")
	var s := ", ".join(bits)
	return s.left(1).to_upper() + s.substr(1) if s != "" else ""


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
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(1000, 560)
	center.add_child(outer)
	UiTheme.keep_on_screen(outer)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	outer.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 0)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_box)
	_title = Label.new()
	_title.theme_type_variation = &"Header"
	_title.add_theme_font_size_override("font_size", 28)
	_title.clip_text = true
	title_box.add_child(_title)
	_notes = Label.new()
	_notes.theme_type_variation = &"Small"
	_notes.add_theme_font_size_override("font_size", 14)
	title_box.add_child(_notes)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)

	# --- left: the chest
	var left := _page(cols)
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 6)
	left.add_child(lh)
	_chest_label = _ink("In the chest", 18, true)
	_chest_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(_chest_label)
	_button(lh, "Take all", "Take everything that fits in your pack", take_all)
	_button(lh, "Sort", "Stack and sort what's in here", sort_chest)
	_chest_grid = _grid(left)

	# --- right: your pack
	var right := _page(cols)
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 6)
	right.add_child(rh)
	var pack_lbl := _ink("Your pack", 18, true)
	pack_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(pack_lbl)
	_button(rh, "Add to stacks", "Store only what this already holds some of (backpack, not hotbar)", store_matching)
	_button(rh, "Store all", "Store your whole backpack; the hotbar stays with you", store_all)
	right.add_child(_ink("Hotbar", 14, true, COL_MUTED))
	_hotbar_row = HBoxContainer.new()
	_hotbar_row.add_theme_constant_override("separation", 4)
	right.add_child(_hotbar_row)
	_bag_label = _ink("Backpack", 14, true, COL_MUTED)
	right.add_child(_bag_label)
	_bag_grid = _grid(right)

	var foot := Label.new()
	foot.theme_type_variation = &"Small"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.text = "Click: move the stack  ·  Right-click: move one  ·  Shift+Click: move all of that kind  ·  F / Esc: close"
	v.add_child(foot)

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


func _page(parent: Control) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Parchment"
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v


func _grid(parent: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var g := GridContainer.new()
	g.columns = Inventory.MAX_HOTBAR_SLOTS
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	scroll.add_child(g)
	return g


func _button(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


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


func _make_view(side: StringName, idx: int) -> ItemSlotView:
	var view := ItemSlotView.new(SLOT_PX).set_padding(SLOT_PAD)
	view.focus_mode = Control.FOCUS_ALL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(func(ev: InputEvent) -> void:
		if chest == null or player == null:
			return
		var kind := -1   # 0 stack, 1 one, 2 all of that kind
		if ev is InputEventMouseButton and ev.pressed:
			if ev.button_index == MOUSE_BUTTON_LEFT:
				kind = 2 if Input.is_key_pressed(KEY_SHIFT) else 0
			elif ev.button_index == MOUSE_BUTTON_RIGHT:
				kind = 1
		elif ev.is_action_pressed("ui_accept"):
			kind = 0
		elif ev is InputEventJoypadButton and ev.pressed:
			if ev.button_index == JOY_BUTTON_X:
				kind = 1
			elif ev.button_index == JOY_BUTTON_Y:
				kind = 2
		if kind < 0:
			return
		view.accept_event()
		_click(side, idx, kind)
	)
	var enter := func() -> void:
		_hover_side = side
		_hover_idx = idx
		view.self_modulate = HOVER_TINT
		_show_hover(side, idx)
	var leave := func() -> void:
		view.self_modulate = Color.WHITE
		if _hover_side == side and _hover_idx == idx:
			_hover_side = &""
			_hover_idx = -1
			_hide_hover()
	view.mouse_entered.connect(enter)
	view.mouse_exited.connect(leave)
	view.focus_entered.connect(func() -> void:
		if _pad_input:
			enter.call())
	view.focus_exited.connect(leave)
	return view


## kind: 0 = whole stack, 1 = one, 2 = every stack of that kind.
func _click(side: StringName, idx: int, kind: int) -> void:
	if side == &"chest":
		var s: ItemSlot = chest.container.inventory.slots[idx]
		if s.is_empty():
			return
		if kind == 2:
			take_kind(s.item_id)
		else:
			take(idx, 1 if kind == 1 else -1)
	else:
		var s: ItemSlot = player.inventory.slots[idx]
		if s.is_empty():
			return
		if kind == 2:
			store_kind(s.item_id)
		else:
			store(idx, 1 if kind == 1 else -1)
	refresh()


# -------------------------------------------------------------------------
# Refresh
# -------------------------------------------------------------------------

func refresh() -> void:
	if chest == null or player == null or not is_instance_valid(chest):
		return
	var cinv: Inventory = chest.container.inventory
	var inv: Inventory = player.inventory
	_title.text = chest.entity_name
	var n := notes_text(chest)
	_notes.text = n
	_notes.visible = n != ""

	if _built_chest_cap != cinv.capacity:
		_rebuild(_chest_grid, _chest_views, &"chest", cinv.capacity)
		_chest_grid.columns = 6 if cinv.capacity <= 18 else Inventory.MAX_HOTBAR_SLOTS
		_built_chest_cap = cinv.capacity
	if _built_pack_cap != inv.capacity:
		for c in _hotbar_row.get_children():
			_hotbar_row.remove_child(c)
			c.queue_free()
		_rebuild(_bag_grid, _pack_views, &"pack", inv.capacity)
		# The first eight pack views live in the hotbar row.
		for i in mini(Inventory.MAX_HOTBAR_SLOTS, _pack_views.size()):
			var view := _pack_views[i]
			_bag_grid.remove_child(view)
			_hotbar_row.add_child(view)
			var key := Label.new()
			key.text = str(i + 1)
			key.theme_type_variation = &"KeyLabel"
			key.add_theme_font_size_override("font_size", 12)
			key.position = Vector2(-3, -5)
			key.mouse_filter = Control.MOUSE_FILTER_IGNORE
			view.get_child(0).add_child(key)
		_built_pack_cap = inv.capacity

	var used := 0
	for i in _chest_views.size():
		var s: ItemSlot = cinv.slots[i]
		_chest_views[i].show_item(s.item_id if not s.is_empty() else &"", s.count)
		_chest_views[i].tooltip_text = ""
		if not s.is_empty():
			used += 1
	_chest_label.text = "%s  ·  %d / %d" % [_short_name().capitalize(), used, cinv.capacity]

	var bag_used := 0
	for i in _pack_views.size():
		var s: ItemSlot = inv.slots[i]
		var view := _pack_views[i]
		view.show_item(s.item_id if not s.is_empty() else &"", s.count)
		view.tooltip_text = ""
		view.set_selected(i < Inventory.MAX_HOTBAR_SLOTS and i == inv.active_hotbar_index)
		# Things this store won't take are faded.
		view.modulate = Color(1, 1, 1, 0.38) if (not s.is_empty() and not chest.container.can_accept_item(s.item_id)) else Color.WHITE
		if i >= Inventory.MAX_HOTBAR_SLOTS and not s.is_empty():
			bag_used += 1
	_bag_label.text = "Backpack  ·  %d / %d" % [bag_used, inv.capacity - Inventory.MAX_HOTBAR_SLOTS]

	if _hover_idx >= 0:
		_show_hover(_hover_side, _hover_idx)


func _rebuild(grid: GridContainer, views: Array[ItemSlotView], side: StringName, cap: int) -> void:
	for c in grid.get_children():
		grid.remove_child(c)
		c.queue_free()
	views.clear()
	for i in cap:
		var view := _make_view(side, i)
		grid.add_child(view)
		views.append(view)


func _focus_first() -> void:
	await get_tree().process_frame
	if visible and not _chest_views.is_empty():
		_chest_views[0].grab_focus()


# -------------------------------------------------------------------------
# Hover card
# -------------------------------------------------------------------------

func _show_hover(side: StringName, idx: int) -> void:
	if chest == null or player == null:
		return
	var inv: Inventory = chest.container.inventory if side == &"chest" else player.inventory
	if idx < 0 or idx >= inv.capacity or inv.slots[idx].is_empty():
		_hide_hover()
		return
	var s: ItemSlot = inv.slots[idx]
	var def: ItemDef = ItemDB.get_item(s.item_id)
	for c in _hover_box.get_children():
		_hover_box.remove_child(c)
		c.queue_free()
	_hover_line(ItemSlotView.item_name(s.item_id) + ((" x%d" % s.count) if s.count > 1 else ""), 15, true)
	if def != null:
		var facts := InventoryUI.item_facts(def)
		_hover_line(InventoryUI.category_line(def) + (("  ·  " + facts[0]) if not facts.is_empty() else ""), 13, false, Color(0.85, 0.8, 0.7))
	var in_chest := chest.container.inventory.get_item_count(s.item_id)
	var carried := player.inventory.get_item_count(s.item_id)
	_hover_line("In the %s: %d   ·   Carrying: %d" % [_short_name(), in_chest, carried], 13)
	if side == &"pack" and not chest.container.can_accept_item(s.item_id):
		_hover_line(refusal_text(chest), 13, false, ItemSlotView.COL_SHORT)
	_hover_panel.reset_size()
	_hover_panel.visible = true


func _hover_line(t: String, fsize: int, bold := false, col := Color(0, 0, 0, 0)) -> void:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fsize)
	if bold:
		l.add_theme_font_override("font", UiTheme.font(800))
	if col.a > 0.0:
		l.add_theme_color_override("font_color", col)
	_hover_box.add_child(l)


func _hide_hover() -> void:
	if _hover_panel != null:
		_hover_panel.visible = false
