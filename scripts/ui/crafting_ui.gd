class_name CraftingUI
extends CanvasLayer
## Full-width Crafting screen (K, or by using a station).
##
##   Left    where you craft: By hand, each station (nearby ones lit), All
##   Middle  searchable recipe list; each row shows have/need per ingredient
##   Right   the chosen recipe: ingredients, station + fuel, Craft x1 / x5 / All
##
## Keyboard / pad: arrows or D-pad move, Enter / A crafts one, Esc / B closes,
## LB / RB jump to the Pack and Quests pages.

signal closed

const STATION_RANGE := 4.8
const LIST_REFRESH_SEC := 0.25
const COL_READY := Color8(70, 120, 70)
const COL_BLOCKED := Color8(150, 70, 55)
const COL_MUTED := Color8(120, 92, 70)
const ALL := &"all"
const HAND := &"none"

var main: Node
var player: Player

var _where: StringName = HAND
var _selected: StringName = &""
var _origin_station: StationEntity = null
var _search := ""
var _only_ready := false
var _refresh_t := 0.0
var _inv_snapshot := -1

var _root: Control
var _where_box: VBoxContainer
var _list: VBoxContainer
var _list_scroll: ScrollContainer
var _list_title: Label
var _list_count: Label
var _search_edit: LineEdit
var _ready_check: Button
var _detail: VBoxContainer
var _rows: Dictionary = {}           ## recipe id -> row PanelContainer


func _ready() -> void:
	layer = 16
	_build()
	visible = false


func setup(p_main: Node) -> void:
	main = p_main


func is_open() -> bool:
	return visible


## Opens the screen. Pass the station the player used to start on its recipes.
func open(station: StationEntity = null) -> void:
	if main != null and main.get("player") != null:
		player = main.player
	if player == null or player.inventory == null:
		return
	_origin_station = station
	if station != null:
		_where = station.station_tag
	else:
		var near := nearby_stations()
		_where = near[0].station_tag if not near.is_empty() and _where == HAND else _where
	_search = ""
	_search_edit.text = ""
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.input_enabled = false
	_rebuild_all()
	_focus_selected()


func close() -> void:
	if not visible:
		return
	visible = false
	_origin_station = null
	if player != null:
		player.input_enabled = true
	if main == null or not main.has_method("is_any_menu_open") or not main.is_any_menu_open():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func toggle(station: StationEntity = null) -> void:
	if visible:
		close()
	else:
		open(station)


# ------------------------------------------------------------------ queries

## Stations within reach, the one the player used first.
func nearby_stations() -> Array[StationEntity]:
	var out: Array[StationEntity] = []
	if _origin_station != null and is_instance_valid(_origin_station):
		out.append(_origin_station)
	if player != null and player.entities != null:
		for ent in player.entities.entities.values():
			if ent is StationEntity and is_instance_valid(ent) and not out.has(ent):
				if ent.global_position.distance_to(player.global_position) <= STATION_RANGE:
					out.append(ent)
	return out


func _station_for(tag: StringName) -> StationEntity:
	for st in nearby_stations():
		if st.station_tag == tag:
			return st
	return null


func _knows(r: RecipeDef) -> bool:
	return player == null or player.recipes == null or player.recipes.knows(r.id)


## How many times the bag holds enough for this recipe (capped at 99).
static func max_batches(r: RecipeDef, inv: Inventory) -> int:
	if inv == null:
		return 0
	if inv.get("creative_mode") == true:
		return 99
	var n := 99
	for inp: Dictionary in r.inputs:
		var need := maxi(1, int(inp.get("count", 1)))
		n = mini(n, inv.get_item_count(StringName(inp.get("item_id", &""))) / need)
	return n


## Why a recipe can't be made right now, or "" if it can.
func blocker(r: RecipeDef) -> String:
	var inv: Inventory = player.inventory
	if r.required_station != HAND:
		var st := _station_for(r.required_station)
		var sname: String = RecipeDB.STATION_NAMES.get(r.required_station, String(r.required_station).capitalize())
		if st == null:
			return "Needs a %s nearby" % sname
		if st.station.requires_fuel and not st.station.is_fueled():
			return "%s is out - add fuel" % sname
		if CraftingStation.is_timed(r) and st.station.queue_full():
			return "The %s is full - wait for a dish" % sname
	for inp: Dictionary in r.inputs:
		var iid := StringName(inp.get("item_id", &""))
		var short := int(inp.get("count", 1)) - inv.get_item_count(iid)
		if short > 0 and inv.get("creative_mode") != true:
			return "Need %d more %s" % [short, ItemSlotView.item_name(iid)]
	return ""


## Names of known recipes that take this item as an ingredient.
func used_in(item_id: StringName) -> Array[String]:
	var out: Array[String] = []
	for r in RecipeDB.get_all_recipes():
		if not _knows(r):
			continue
		for inp: Dictionary in r.inputs:
			if StringName(inp.get("item_id", &"")) == item_id:
				out.append(r.name)
				break
	return out


func _recipes_in_view() -> Array[RecipeDef]:
	var src: Array[RecipeDef] = RecipeDB.get_all_recipes() if (_where == ALL or _search != "") \
		else RecipeDB.get_station_exclusive_recipes(_where)
	if _search == "":
		return src
	var q := _search.to_lower()
	var out: Array[RecipeDef] = []
	for r in src:
		var hay := r.name.to_lower() + " " + ItemSlotView.item_name(r.output_item_id).to_lower()
		for inp: Dictionary in r.inputs:
			hay += " " + ItemSlotView.item_name(StringName(inp.get("item_id", &""))).to_lower()
		if q in hay:
			out.append(r)
	return out


# ------------------------------------------------------------------ crafting

## Crafts `times` batches. Returns how many were made.
func craft(r: RecipeDef, times: int = 1) -> int:
	if player == null or r == null or not _knows(r):
		return 0
	var inv: Inventory = player.inventory
	var st: StationEntity = null
	if r.required_station != HAND:
		st = _station_for(r.required_station)
		if st == null:
			return 0
	if st != null and CraftingStation.is_timed(r):
		return _start_cooking(r, st, times)
	var made := 0
	for i in maxi(1, times):
		if blocker(r) != "":
			break
		if not r.consume_ingredients(inv):
			break
		var left := inv.add_item(r.output_item_id, r.output_count)
		if left > 0:
			# Bag full: undo this batch exactly.
			inv.remove_item(r.output_item_id, r.output_count - left)
			if inv.get("creative_mode") != true:
				for inp: Dictionary in r.inputs:
					inv.add_item(StringName(inp["item_id"]), int(inp["count"]))
			_toast("Your bag is full.")
			break
		made += 1
		if st != null:
			if st.station.requires_fuel:
				st.station.fuel_remaining_sec = maxf(0.0, st.station.fuel_remaining_sec - maxf(3.0, r.craft_time_sec * 0.5))
				st._update_fire_visuals(0.0)
			st.recipe_crafted.emit(r.id, 1)
		player.quest_event(QuestDef.ObjectiveType.CRAFT_ITEM, r.output_item_id)
	if made > 0:
		var total := made * r.output_count
		_toast("Crafted %s%s" % [r.name, (" x%d" % total) if total > 1 else ""])
		if visible:
			_rebuild_all()
			_pulse_detail_icon()
	return made


## Pays for up to `times` dishes and puts them on the station. Returns how many were started.
func _start_cooking(r: RecipeDef, st: StationEntity, times: int) -> int:
	if blocker(r) != "":
		return 0
	var before := st.station.batch_remaining
	st.station.craft_recipe(r.id, player.inventory, mini(times, queue_room(st)))
	var started := st.station.batch_remaining - before
	if started <= 0:
		return 0
	st.recipe_crafted.emit(r.id, started)
	if st.manager != null:
		st.manager.push_state(st)
	var each := "%ds" % roundi(r.craft_time_sec)
	_toast("Cooking %s%s  (%s each, collect it from the %s)" % [r.name, (" x%d" % started) if started > 1 else "",
		each, st.entity_name])
	if visible:
		_rebuild_all()
		_pulse_detail_icon()
	return started


## Dishes this station can still take (the one cooking plus the queue).
static func queue_room(st: StationEntity) -> int:
	return CraftingStation.MAX_QUEUE + 1 - st.station.batch_remaining


func _toast(msg: String) -> void:
	if player != null and player.hud != null:
		player.hud.show_toast(msg)


# ------------------------------------------------------------------ input / tick

func _process(delta: float) -> void:
	if not visible or player == null:
		return
	_refresh_t -= delta
	if _refresh_t > 0.0:
		return
	_refresh_t = LIST_REFRESH_SEC
	# Inventory or fuel can change under us (pickups, fire burning down): cheap re-check.
	if _snapshot() != _inv_snapshot:
		_rebuild_all()
	else:
		_update_fuel_bars()


func _snapshot() -> int:
	var h := 0
	for s: ItemSlot in player.inventory.slots:
		if not s.is_empty():
			h = hash([h, s.item_id, s.count])
	for st in nearby_stations():
		h = hash([h, st.station_tag, st.station.is_fueled(), st.station.batch_remaining,
			st.station.output_count(), st.station.is_paused()])
	return h


func _input(e: InputEvent) -> void:
	if not visible:
		return
	if _search_edit.has_focus() and e is InputEventKey:
		# Typing: letters belong to the search box. Esc / Enter hand focus back to the list.
		if e.pressed and (e.keycode == KEY_ESCAPE or e.keycode == KEY_ENTER or e.keycode == KEY_DOWN):
			get_viewport().set_input_as_handled()
			_search_edit.release_focus()
			_focus_selected()
		return
	if e.is_action_pressed("menu_toggle") or e.is_action_pressed("crafting_toggle") or e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
		return
	if e.is_action_pressed("inventory_toggle") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_LEFT_SHOULDER):
		get_viewport().set_input_as_handled()
		_go_page(&"pack")
		return
	if e.is_action_pressed("quest_log_toggle") or (e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_RIGHT_SHOULDER):
		get_viewport().set_input_as_handled()
		_go_page(&"quests")


func _go_page(page: StringName) -> void:
	if main != null and main.has_method("switch_page"):
		main.switch_page(page)


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

	var outer := PanelContainer.new()
	outer.custom_minimum_size = Vector2(1180, 640)
	center.add_child(outer)
	UiTheme.keep_on_screen(outer)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	outer.add_child(v)

	# --- header: title + page tabs
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	var title := Label.new()
	title.text = "Crafting"
	title.theme_type_variation = &"Header"
	title.add_theme_font_size_override("font_size", 28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for t: Array in [["Pack (I)", &"pack", false], ["Crafting (K)", &"crafting", true], ["Quests (J)", &"quests", false]]:
		var b := Button.new()
		b.text = t[0]
		b.toggle_mode = true
		b.button_pressed = t[2]
		b.focus_mode = Control.FOCUS_NONE
		var page: StringName = t[1]
		b.pressed.connect(func() -> void:
			b.button_pressed = page == &"crafting"
			if page != &"crafting":
				_go_page(page)
		)
		head.add_child(b)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)

	# --- left: where
	var left := _page(cols, 210)
	left.add_child(_ink("Where", 18, true))
	_where_box = VBoxContainer.new()
	_where_box.add_theme_constant_override("separation", 2)
	left.add_child(_where_box)

	# --- middle: search + list
	var mid := _page(cols, 0)
	(mid.get_parent() as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := HBoxContainer.new()
	mid.add_child(title_row)
	_list_title = _ink("", 20, true)
	_list_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_title.clip_text = true
	title_row.add_child(_list_title)
	_list_count = _ink("", 13, false, COL_MUTED)
	_list_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(_list_count)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	mid.add_child(bar)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search recipes or ingredients"
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.add_theme_font_size_override("font_size", 15)
	_search_edit.text_changed.connect(func(t: String) -> void:
		_search = t.strip_edges()
		_rebuild_all()
	)
	bar.add_child(_search_edit)
	_ready_check = Button.new()
	_ready_check.text = "Can make now"
	_ready_check.toggle_mode = true
	_ready_check.focus_mode = Control.FOCUS_NONE
	_ready_check.add_theme_font_size_override("font_size", 14)
	_ready_check.toggled.connect(func(on: bool) -> void:
		_only_ready = on
		_rebuild_all()
	)
	bar.add_child(_ready_check)

	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	mid.add_child(_list_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	_list_scroll.add_child(_list)

	# --- right: detail
	_detail = _page(cols, 330)

	var foot := Label.new()
	foot.theme_type_variation = &"Small"
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	foot.text = "Click / Enter: craft one  ·  Arrows: browse  ·  I: Pack  ·  J: Quests  ·  Esc: close"
	v.add_child(foot)


func _page(parent: Control, width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"Parchment"
	if width > 0.0:
		p.custom_minimum_size = Vector2(width, 0)
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	return v


## Light list-row styles drawn straight on the parchment (no heavy slot frames).
static func row_style(selected: bool, hover := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.INK, 0.16 if selected else (0.07 if hover else 0.0))
	sb.border_color = Color8(176, 120, 52) if selected else Color(UiTheme.INK, 0.0)
	sb.border_width_left = 4
	sb.corner_radius_top_left = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 10
	sb.content_margin_right = 18   # clear of the list's scrollbar
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


static func _style_row(p: PanelContainer, selected: bool) -> void:
	p.add_theme_stylebox_override("panel", row_style(selected))
	p.set_meta("selected", selected)


static func _hookup_hover(p: PanelContainer) -> void:
	p.mouse_entered.connect(func() -> void:
		if not p.get_meta("selected", false):
			p.add_theme_stylebox_override("panel", row_style(false, true)))
	p.mouse_exited.connect(func() -> void:
		p.add_theme_stylebox_override("panel", row_style(p.get_meta("selected", false))))


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

func _rebuild_all() -> void:
	if player == null:
		return
	var fo := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var list_had_focus := fo != null and _list.is_ancestor_of(fo)
	_inv_snapshot = _snapshot()
	_rebuild_where()
	_rebuild_list()
	_refresh_detail()
	if list_had_focus:
		_focus_selected()


## Removes children right away (not at end of frame) so the layout never doubles up.
static func _clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _rebuild_where() -> void:
	_clear(_where_box)
	var near: Dictionary = {}
	for st in nearby_stations():
		near[st.station_tag] = true
	var entries: Array = [[HAND, "By hand", true]]
	for tag: StringName in RecipeDB.STATION_NAMES:
		if tag != HAND:
			entries.append([tag, RecipeDB.STATION_NAMES[tag], near.has(tag)])
	entries.append([ALL, "Everything", true])
	for e: Array in entries:
		var tag: StringName = e[0]
		var known := 0
		var n_ready := 0
		var pool: Array[RecipeDef] = RecipeDB.get_all_recipes() if tag == ALL else RecipeDB.get_station_exclusive_recipes(tag)
		for r in pool:
			if _knows(r):
				known += 1
				if blocker(r) == "":
					n_ready += 1
		if known == 0 and tag != _where and not near.has(tag):
			continue   # nothing learned for a station you aren't standing at: keep the list short
		_where_box.add_child(_where_row(tag, e[1], e[2], known, n_ready))


## One entry in the "Where" list: name, "here" marker for stations in reach, ready count.
func _where_row(tag: StringName, label: String, reachable: bool, known: int, n_ready: int) -> PanelContainer:
	var p := PanelContainer.new()
	var sel := tag == _where and _search == ""
	_style_row(p, sel)
	_hookup_hover(p)
	p.focus_mode = Control.FOCUS_ALL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.tooltip_text = "%d known recipe%s, %d you can make now" % [known, "" if known == 1 else "s", n_ready]
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var name_l := _ink(label, 15, sel, Color(0, 0, 0, 0) if reachable else COL_MUTED)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(name_l)
	if tag != HAND and tag != ALL:
		var sub_text := "in reach" if reachable else "not nearby"
		var st_here := _station_for(tag) if reachable else null
		if st_here != null and st_here.station.output_count() > 0:
			sub_text = "%d ready to collect" % st_here.station.output_count()
		elif st_here != null and st_here.station.is_active:
			sub_text = "cooking..." if not st_here.station.is_paused() else "fire out, dish waiting"
		var sub := _ink(sub_text, 12, false, COL_READY if reachable else COL_MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(sub)
	if n_ready > 0:
		var badge := _ink(str(n_ready), 14, true, COL_READY)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.tooltip_text = "%d ready to make" % n_ready
		h.add_child(badge)
	var pick := func() -> void:
		if _where == tag and _search == "":
			return
		_where = tag
		_search = ""
		_search_edit.text = ""
		_selected = &""
		_rebuild_all()
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) \
				or ev.is_action_pressed("ui_accept"):
			pick.call()
			p.accept_event()
	)
	return p

func _rebuild_list() -> void:
	_clear(_list)
	_rows.clear()
	_live.clear()

	if _search != "":
		_list_title.text = "Results for \"%s\"" % _search
	else:
		_list_title.text = "Everything" if _where == ALL else String(RecipeDB.STATION_NAMES.get(_where, "Crafting"))

	var st := _station_for(_where) if _where != HAND and _where != ALL else null
	if st != null and st.station.requires_fuel:
		_list.add_child(_fuel_row(st))
	if st != null and st.is_cooking_station():
		_list.add_child(_cook_panel(st))
		_list.add_child(HSeparator.new())

	var shown: Array[RecipeDef] = []
	var locked: Array[RecipeDef] = []
	for r in _recipes_in_view():
		if not _knows(r):
			locked.append(r)
		elif not _only_ready or blocker(r) == "":
			shown.append(r)

	var n_ok := 0
	var ready_list: Array[RecipeDef] = []
	var blocked_list: Array[RecipeDef] = []
	for r in shown:
		if blocker(r) == "":
			n_ok += 1
			ready_list.append(r)
		else:
			blocked_list.append(r)
	# Mixed lists (Everything / search) put what you can make first; a single station keeps its order.
	if _where == ALL or _search != "":
		shown.clear()
		shown.append_array(ready_list)
		shown.append_array(blocked_list)
	var shown_ids := shown.map(func(x: RecipeDef) -> StringName: return x.id)
	if _selected == &"" or not shown_ids.has(_selected):
		_selected = shown[0].id if not shown.is_empty() else &""
	_list_count.text = "%d known  ·  %d ready" % [shown.size(), n_ok] if not _only_ready else "%d ready" % n_ok

	for r in shown:
		var row := _recipe_row(r)
		_list.add_child(row)
		_rows[r.id] = row

	if shown.is_empty():
		var msg := "Nothing you can make here right now." if _only_ready else "No recipes here yet."
		if _search != "":
			msg = "No known recipe matches."
		_list.add_child(_ink(msg, 15, false, COL_MUTED))

	# Undiscovered recipes: silhouettes with a hint, so there's something to chase.
	if not _only_ready and not locked.is_empty():
		_list.add_child(HSeparator.new())
		_list.add_child(_ink("Still to discover (%d)" % locked.size(), 15, true, COL_MUTED))
		for r in locked.slice(0, 6):
			_list.add_child(_locked_row(r))
		if locked.size() > 6:
			_list.add_child(_ink("...and %d more." % (locked.size() - 6), 13, false, COL_MUTED))



func _recipe_row(r: RecipeDef) -> PanelContainer:
	var inv: Inventory = player.inventory
	var why := blocker(r)
	var p := PanelContainer.new()
	_style_row(p, r.id == _selected)
	_hookup_hover(p)
	p.focus_mode = Control.FOCUS_ALL
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)

	var out := ItemSlotView.new(28).show_item(r.output_item_id, r.output_count)
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if why != "":
		out.modulate = Color(1, 1, 1, 0.55)
	h.add_child(out)

	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tv)
	var name_l := _ink(r.name + ((" x%d" % r.output_count) if r.output_count > 1 else ""), 16, true,
		Color(0, 0, 0, 0) if why == "" else COL_MUTED)
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(name_l)
	var status: Label
	if why == "":
		var n := max_batches(r, inv)
		var cook := ("  ·  cooks in %ds" % roundi(r.craft_time_sec)) if CraftingStation.is_timed(r) else ""
		status = _ink("Ready" + (("  ·  enough for %d" % n) if n > 1 else "") + cook, 13, false, COL_READY)
	else:
		status = _ink(why, 13, false, COL_BLOCKED)
	status.clip_text = true
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(status)

	# Ingredients: icon + needed amount, red when you're short.
	for inp: Dictionary in r.inputs:
		var iid := StringName(inp.get("item_id", &""))
		var need := int(inp.get("count", 1))
		var have := need if inv.get("creative_mode") == true else inv.get_item_count(iid)
		var ing := HBoxContainer.new()
		ing.add_theme_constant_override("separation", 2)
		ing.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ing.tooltip_text = "%s  -  have %d, need %d" % [ItemSlotView.item_name(iid), have, need]
		var ic := UiTheme.icon(ItemIcons.for_item(iid), 26)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if have < need:
			ic.modulate = Color(1, 1, 1, 0.5)
		ing.add_child(ic)
		var cl := _ink("%d" % need, 14, true, COL_READY if have >= need else COL_BLOCKED)
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ing.add_child(cl)
		h.add_child(ing)
	p.focus_entered.connect(func() -> void: _select(r.id))
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.double_click:
				craft(r, 1)
			else:
				p.grab_focus()
				_select(r.id)
			p.accept_event()
		elif ev.is_action_pressed("ui_accept"):
			craft(r, 1)
			p.accept_event()
	)
	return p


func _locked_row(r: RecipeDef) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(ItemSlotView.new(30).show_unknown(r.output_item_id))
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	h.add_child(tv)
	tv.add_child(_ink("? ? ?", 14, true, COL_MUTED))
	var hint := RecipeBook.source_of(r.id)
	tv.add_child(_ink(hint if hint != "" else "Keep exploring.", 13, false, COL_MUTED))
	return h


func _fuel_row(st: StationEntity) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var lit := st.station.fuel_remaining_sec > 0.0
	h.add_child(_ink("Fire" if lit else "Fire out", 15, true, Color8(170, 80, 30) if lit else COL_BLOCKED))
	var bar := ProgressBar.new()
	bar.theme_type_variation = &"StaminaBar"
	bar.show_percentage = false
	bar.max_value = CraftingStation.MAX_FUEL_SEC
	bar.value = st.station.fuel_remaining_sec
	bar.custom_minimum_size = Vector2(160, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_live.append({"node": bar, "st": st, "kind": "fuel"})
	h.add_child(bar)
	var b := Button.new()
	b.text = "Add fuel"
	b.tooltip_text = "Burns one piece of wood, driftwood, planks or kelp from your bag"
	b.disabled = not CraftingStation.has_any_fuel(player.inventory) \
		or st.station.fuel_remaining_sec >= CraftingStation.MAX_FUEL_SEC - 1.0
	b.pressed.connect(func() -> void:
		st.recharge_fire(player)
		_rebuild_all()
	)
	h.add_child(b)
	return h


func _select(id: StringName) -> void:
	if _selected == id:
		return
	if _rows.has(_selected) and is_instance_valid(_rows[_selected]):
		_style_row(_rows[_selected], false)
	_selected = id
	if _rows.has(id):
		_style_row(_rows[id], true)
	_refresh_detail()


func _focus_selected() -> void:
	await get_tree().process_frame
	if _rows.has(_selected) and is_instance_valid(_rows[_selected]):
		(_rows[_selected] as Control).grab_focus()


# ------------------------------------------------------------------ detail

var _detail_icon: ItemSlotView


var _live: Array = []   ## {node, st, kind}: bars / labels that tick while the page is open


## Fuel and cooking bars move while the screen is open.
func _update_fuel_bars() -> void:
	for e: Dictionary in _live:
		var node: Control = e.node
		var st: StationEntity = e.st
		if not is_instance_valid(node) or not is_instance_valid(st):
			continue
		match e.kind:
			"fuel":
				(node as ProgressBar).value = st.station.fuel_remaining_sec
			"cook":
				(node as ProgressBar).value = st.station.cook_progress()
			"secs":
				(node as Label).text = "fire out" if st.station.is_paused() else "%ds" % ceili(st.station.seconds_left())


## What's cooking, what's next, and what's ready to take, for one station.
func _cook_panel(st: StationEntity) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var s := st.station

	var now := HBoxContainer.new()
	now.add_theme_constant_override("separation", 10)
	v.add_child(now)
	if s.is_active and s.active_recipe != null:
		now.add_child(ItemSlotView.new(28).show_item(s.active_recipe.output_item_id, s.active_recipe.output_count))
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 2)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		now.add_child(mv)
		mv.add_child(_ink("Cooking: %s" % s.active_recipe.name, 15, true))
		var bar := ProgressBar.new()
		bar.theme_type_variation = &"FoodBar"
		bar.show_percentage = false
		bar.max_value = 1.0
		bar.value = s.cook_progress()
		bar.custom_minimum_size = Vector2(120, 14)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.add_child(bar)
		_live.append({"node": bar, "st": st, "kind": "cook"})
		var secs := _ink("", 15, true, COL_BLOCKED if s.is_paused() else UiTheme.INK)
		secs.custom_minimum_size = Vector2(70, 0)
		secs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		secs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		secs.text = "fire out" if s.is_paused() else "%ds" % ceili(s.seconds_left())
		now.add_child(secs)
		_live.append({"node": secs, "st": st, "kind": "secs"})
	else:
		var idle := _ink("Nothing cooking. Pick a dish below and press Cook; it keeps going while you're away.", 14, false, COL_MUTED)
		idle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		idle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		now.add_child(idle)

	if not s.queue.is_empty():
		var qrow := HBoxContainer.new()
		qrow.add_theme_constant_override("separation", 4)
		v.add_child(qrow)
		qrow.add_child(_ink("Next (%d/%d):" % [s.queue.size(), CraftingStation.MAX_QUEUE], 13, false, COL_MUTED))
		for i in s.queue.size():
			var r := RecipeDB.get_recipe(s.queue[i])
			if r == null:
				continue
			var slot := ItemSlotView.new(24).show_item(r.output_item_id, r.output_count)
			slot.tooltip_text = "%s  -  click to take it off and get the ingredients back" % r.name
			slot.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var idx := i
			slot.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					if s.cancel_queued(idx, player.inventory):
						_toast("Took %s off the %s" % [r.name, st.entity_name])
						_rebuild_all()
			)
			qrow.add_child(slot)

	if s.output_count() > 0:
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 6)
		v.add_child(trow)
		trow.add_child(_ink("Ready:", 15, true, COL_READY))
		for item_id: StringName in s.output:
			trow.add_child(ItemSlotView.new(28).show_item(item_id, int(s.output[item_id])))
		var pad := Control.new()
		pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		trow.add_child(pad)
		var take := Button.new()
		take.text = "Take all"
		take.add_theme_font_size_override("font_size", 15)
		take.pressed.connect(func() -> void:
			st.collect_output(player)
			_rebuild_all()
		)
		trow.add_child(take)
	return v


func _refresh_detail() -> void:
	_clear(_detail)
	_detail_icon = null
	var r: RecipeDef = RecipeDB.get_recipe(_selected) if _selected != &"" else null
	if r == null:
		_detail.add_child(_ink("Pick a recipe", 18, true))
		_detail.add_child(_ink("Choose one from the list to see what it needs.", 14, false, COL_MUTED))
		return
	var inv: Inventory = player.inventory
	var out_def: ItemDef = ItemDB.get_item(r.output_item_id)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	_detail_icon = ItemSlotView.new(56).show_item(r.output_item_id, r.output_count)
	head.add_child(_detail_icon)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_theme_constant_override("separation", 0)
	head.add_child(hv)
	var title := _ink(r.name, 20, true)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(title)
	var makes := "Makes %d" % r.output_count if r.output_count > 1 else "Makes 1"
	var held := inv.get_item_count(r.output_item_id)
	hv.add_child(_ink("%s  ·  you have %d" % [makes, held], 13, false, COL_MUTED))

	var desc := r.description if r.description != "" else (out_def.description if out_def != null else "")
	if desc != "":
		var d := _ink(desc, 14)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(d)

	_detail.add_child(HSeparator.new())
	_detail.add_child(_ink("Needs", 16, true))
	for inp: Dictionary in r.inputs:
		var iid := StringName(inp.get("item_id", &""))
		var need := int(inp.get("count", 1))
		var have := need if inv.get("creative_mode") == true else inv.get_item_count(iid)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.add_child(ItemSlotView.new(28).show_item(iid, 0))
		var nl := _ink(ItemSlotView.item_name(iid), 14)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(nl)
		var cl := _ink("%d / %d" % [have, need], 15, true, COL_READY if have >= need else COL_BLOCKED)
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cl)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.tooltip_text = ItemUses.summary(iid, _knows)   # hover an ingredient: what else it's for
		_detail.add_child(row)
	if r.required_station != HAND:
		var sname: String = RecipeDB.STATION_NAMES.get(r.required_station, String(r.required_station).capitalize())
		var here := _station_for(r.required_station) != null
		_detail.add_child(_ink("At a %s%s" % [sname, "  (here)" if here else "  (not nearby)"], 14, false,
			COL_READY if here else COL_BLOCKED))
	if CraftingStation.is_timed(r):
		var tl := _ink("Cooks in %ds. Leave it on and come back; it waits in the %s until you collect it." % [
			roundi(r.craft_time_sec), String(RecipeDB.STATION_NAMES.get(r.required_station, "station")).to_lower()],
			13, false, COL_MUTED)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(tl)

	_add_used_for(r.output_item_id)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.add_child(spacer)

	var why := blocker(r)
	if why != "":
		var wl := _ink(why, 14, true, COL_BLOCKED)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(wl)
	var n := max_batches(r, inv) if why == "" else 0
	var timed := CraftingStation.is_timed(r)
	var cook_st := _station_for(r.required_station) if timed else null
	if cook_st != null:
		n = mini(n, queue_room(cook_st))
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	_detail.add_child(btns)
	var specs: Array = [["Cook" if timed else "Craft", 1, true]]
	if n >= 5:
		specs.append(["x5", 5, true])
	specs.append(["All (%d)" % n if n > 1 else "All", n, n > 1])
	for s: Array in specs:
		var b := Button.new()
		b.text = s[0]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = why != "" or not s[2]
		var times: int = s[1]
		b.pressed.connect(func() -> void: craft(r, times))
		btns.add_child(b)


const USED_FOR_LINES := 4
const USED_FOR_RECIPES := 5

## "Used for": eating, fuel, wearing, building... then the recipes that take it (click one
## to jump to it).
func _add_used_for(item_id: StringName) -> void:
	var uses := ItemUses.lines(item_id)
	var rec := ItemUses.recipes_using(item_id, _knows)
	var known: Array = rec.known
	var locked: int = rec.locked
	_detail.add_child(HSeparator.new())
	_detail.add_child(_ink("Used for", 16, true))
	if uses.is_empty() and known.is_empty() and locked == 0:
		_detail.add_child(_ink("Nothing else yet: it's a finished good.", 13, false, COL_MUTED))
		return
	for i in mini(uses.size(), USED_FOR_LINES):
		var l := _ink("•  " + uses[i], 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(l)
	if known.is_empty() and locked == 0:
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 4)
	flow.add_theme_constant_override("v_separation", 2)
	_detail.add_child(flow)
	flow.add_child(_ink("•  Makes:", 13))
	for i in mini(known.size(), USED_FOR_RECIPES):
		var r2: RecipeDef = known[i]
		var lb := LinkButton.new()
		lb.text = r2.name + ("," if i < mini(known.size(), USED_FOR_RECIPES) - 1 else "")
		lb.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
		lb.focus_mode = Control.FOCUS_NONE
		lb.add_theme_font_size_override("font_size", 13)
		lb.add_theme_color_override("font_color", Color8(40, 104, 112))
		lb.add_theme_color_override("font_hover_color", Color8(176, 120, 52))
		lb.tooltip_text = "Show the %s recipe" % r2.name
		var rid := r2.id
		lb.pressed.connect(func() -> void: show_recipe(rid))
		flow.add_child(lb)
	var extra := known.size() - USED_FOR_RECIPES
	var tail: Array[String] = []
	if extra > 0:
		tail.append("and %d more" % extra)
	if locked > 0:
		tail.append("%d not learned yet" % locked)
	if not tail.is_empty():
		flow.add_child(_ink("(%s)" % ", ".join(tail), 13, false, COL_MUTED))


## Jumps the page to a recipe: its station's list, selected and in view.
func show_recipe(id: StringName) -> void:
	var r := RecipeDB.get_recipe(id)
	if r == null:
		return
	_search = ""
	if _search_edit != null:
		_search_edit.text = ""
	_only_ready = false
	if _ready_check != null:
		_ready_check.button_pressed = false
	_where = r.required_station
	_selected = &""
	_rebuild_all()
	_select(id)
	_focus_selected()


func _pulse_detail_icon() -> void:
	if _detail_icon == null:
		return
	_detail_icon.pivot_offset = _detail_icon.size * 0.5
	var tw := _detail_icon.create_tween()
	_detail_icon.scale = Vector2(1.25, 1.25)
	tw.tween_property(_detail_icon, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
