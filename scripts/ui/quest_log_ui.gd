class_name QuestLogUI
extends CanvasLayer
## Wayfarer's Journal — Quest Log.
## Full interactive log of active and completed quests across the archipelago.
## Toggled with J, L, or from the inventory screen.
## The Recipe Book tab lists every recipe by station: what you know, how the rest are found,
## and lets you copy a hard-won recipe onto a scroll to give or trade to another player.

enum Tab { ACTIVE, COMPLETED, RECIPES }

var main: Node
var player: Player

var _root: Control
var _modal_backdrop: Control
var _tab_buttons: Array[Button] = []
var _quest_list_container: VBoxContainer
var _details_vbox: VBoxContainer
var _hud_tracker_btn: Button
var _empty_label: Label

var current_tab: int = Tab.ACTIVE
var selected_quest_id: StringName = &""
var selected_station: StringName = &"none"
var _open: bool = false


func _ready() -> void:
	layer = 15
	_build()
	_root.visible = false


func setup(p_main: Node) -> void:
	main = p_main


func is_open() -> bool:
	return _open


func open() -> void:
	if main != null and main.get("player") != null:
		player = main.get("player")
	_open = true
	if _root != null:
		_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player != null:
		player.input_enabled = false
	refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	if _root != null:
		_root.visible = false
	if player != null:
		player.input_enabled = true
	var settings_open: bool = (main != null and main.get("settings_menu") != null and main.settings_menu.is_open())
	var inv_open: bool = (main != null and main.get("inventory_ui") != null and main.inventory_ui.is_open())
	if not settings_open and not inv_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _input(e: InputEvent) -> void:
	if not _open:
		return
	if e.is_action_pressed("menu_toggle") or e.is_action_pressed("inventory_toggle"):
		get_viewport().set_input_as_handled()
		close()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var kc: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		if kc == KEY_J or kc == KEY_L or kc == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			close()
			return


# -------------------------------------------------------------------------
# UI Construction
# -------------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	UiTheme.prepare(_root)
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	# Backdrop dim overlay
	_modal_backdrop = Control.new()
	_modal_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_modal_backdrop)

	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.08, 0.10, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close()
	)
	_modal_backdrop.add_child(dim)

	# Main Window Panel
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_modal_backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 580)
	UiTheme.keep_on_screen(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)

	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 10)
	panel.add_child(mv)

	# Header Bar
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	mv.add_child(head)

	head.add_child(UiTheme.icon(ItemIcons.for_tool(ItemIcons.Tool.BLUEPRINT), 36))

	var title_col := VBoxContainer.new()
	title_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_col.add_theme_constant_override("separation", 2)
	head.add_child(title_col)

	var title := Label.new()
	title.text = "Wayfarer's Journal — Quest Log"
	title.theme_type_variation = &"Header"
	title.add_theme_font_size_override("font_size", 24)
	title_col.add_child(title)

	var sub := Label.new()
	sub.text = "Chronicles, errands, and charters of the archipelago  ·  [J / Esc] Close"
	sub.theme_type_variation = &"Small"
	sub.add_theme_font_size_override("font_size", 14)
	title_col.add_child(sub)

	var close_btn := Button.new()
	close_btn.text = "Close (J / Esc)"
	close_btn.pressed.connect(close)
	head.add_child(close_btn)

	# Tabs & Tracker Toggle Row
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	mv.add_child(tab_row)

	var tab_defs := [
		[Tab.ACTIVE, "Active Quests"],
		[Tab.COMPLETED, "Completed Quests"],
		[Tab.RECIPES, "Recipe Book"],
	]
	for td in tab_defs:
		var t_idx: int = td[0]
		var btn := Button.new()
		btn.text = td[1]
		btn.pressed.connect(func() -> void:
			current_tab = t_idx
			selected_quest_id = &""
			refresh()
		)
		tab_row.add_child(btn)
		_tab_buttons.append(btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_row.add_child(spacer)

	_hud_tracker_btn = Button.new()
	_hud_tracker_btn.text = "Toggle HUD Tracker"
	_hud_tracker_btn.pressed.connect(func() -> void:
		if main != null and "tutorial" in main and main.tutorial != null:
			main.tutorial.toggle_tracker()
			_update_tracker_btn_text()
	)
	tab_row.add_child(_hud_tracker_btn)

	# Main 2-Column Body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	mv.add_child(body)

	# Left Column: Quest List
	var left_page := PanelContainer.new()
	left_page.theme_type_variation = &"Parchment"
	left_page.custom_minimum_size = Vector2(330, 0)
	left_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(left_page)

	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_page.add_child(list_scroll)

	_quest_list_container = VBoxContainer.new()
	_quest_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quest_list_container.add_theme_constant_override("separation", 6)
	list_scroll.add_child(_quest_list_container)

	_empty_label = Label.new()
	_empty_label.theme_type_variation = &"InkLabel"
	_empty_label.text = "No quests to display."
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_list_container.add_child(_empty_label)

	# Right Column: Quest Details
	var right_page := PanelContainer.new()
	right_page.theme_type_variation = &"Parchment"
	right_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(right_page)

	var details_scroll := ScrollContainer.new()
	details_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_page.add_child(details_scroll)

	_details_vbox = VBoxContainer.new()
	_details_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_vbox.add_theme_constant_override("separation", 10)
	details_scroll.add_child(_details_vbox)


# -------------------------------------------------------------------------
# Data & Refresh
# -------------------------------------------------------------------------

func _update_tracker_btn_text() -> void:
	if _hud_tracker_btn == null:
		return
	if main != null and "tutorial" in main and main.tutorial != null:
		var pinned: bool = main.tutorial.is_tracker_pinned()
		_hud_tracker_btn.text = "HUD Tracker: " + ("Pinned (Always On)" if pinned else "Auto-Fade")
	else:
		_hud_tracker_btn.text = "Toggle HUD Tracker"


func refresh() -> void:
	if main == null or main.get("quests") == null:
		return
	var qm: QuestManager = main.get("quests")

	_update_tracker_btn_text()

	for bi in _tab_buttons.size():
		var is_cur: bool = (bi == current_tab)
		_tab_buttons[bi].modulate = Color(1.0, 0.96, 0.80) if is_cur else Color(0.80, 0.78, 0.74)

	_tab_buttons[0].text = "Active Quests · %d" % qm.active_quests.size()
	_tab_buttons[1].text = "Completed Quests · %d" % qm.completed_quests.size()
	if _tab_buttons.size() > 2:
		var book := recipe_counts()
		_tab_buttons[2].text = "Recipe Book · %d / %d" % [book.x, book.y]
	if current_tab == Tab.RECIPES:
		_render_recipe_book()
		return

	# Fetch quests for current tab
	var quest_list: Array[QuestDef] = []
	if current_tab == Tab.ACTIVE:
		# Tutorial quests first, then other active quests
		for m in Tutorial.MISSIONS:
			if qm.active_quests.has(m.id):
				quest_list.append(qm.active_quests[m.id])
		for qd in qm.active_quests.values():
			if not quest_list.has(qd):
				quest_list.append(qd)
	else:
		# Completed quests
		for cid in qm.completed_quests:
			var def: QuestDef = qm.get_quest_def(cid)
			if def == null:
				# Reconstruct from tutorial missions or storyline if not cached
				def = _resolve_completed_def(cid)
			if def != null:
				quest_list.append(def)

	_tab_buttons[0].text = "Active Quests · %d" % qm.active_quests.size()
	_tab_buttons[1].text = "Completed Quests · %d" % qm.completed_quests.size()

	# Clear left list
	for c in _quest_list_container.get_children():
		c.queue_free()

	if quest_list.is_empty():
		var emp := Label.new()
		emp.theme_type_variation = &"InkLabel"
		emp.text = "No active quests at the moment.\nWren or village notice boards will offer new tasks." if current_tab == Tab.ACTIVE else "No completed quests yet."
		emp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_quest_list_container.add_child(emp)
		_render_details(null)
		return

	# Ensure selected quest is valid
	if selected_quest_id == &"" or not _has_quest(quest_list, selected_quest_id):
		selected_quest_id = quest_list[0].id

	var selected_qd: QuestDef = null
	for qd in quest_list:
		if qd.id == selected_quest_id:
			selected_qd = qd
			break
	if selected_qd == null:
		selected_qd = quest_list[0]
		selected_quest_id = selected_qd.id

	for qd in quest_list:
		var is_sel: bool = (qd.id == selected_quest_id)
		var card := _make_quest_list_card(qd, is_sel)
		_quest_list_container.add_child(card)

	_render_details(selected_qd)


# -------------------------------------------------------------------------
# Recipe Book
# -------------------------------------------------------------------------

## Known / total recipes for this player.
func recipe_counts() -> Vector2i:
	var all := RecipeDB.get_all_recipes()
	var known := 0
	for r: RecipeDef in all:
		if player == null or player.recipes == null or player.recipes.knows(r.id):
			known += 1
	return Vector2i(known, all.size())


func _station_order() -> Array:
	var out: Array = []
	for st: StringName in RecipeDB.STATION_NAMES:
		if not RecipeDB.get_station_exclusive_recipes(st).is_empty():
			out.append(st)
	for r: RecipeDef in RecipeDB.get_all_recipes():
		if not out.has(r.required_station):
			out.append(r.required_station)
	return out


func _station_label(st: StringName) -> String:
	return RecipeDB.STATION_NAMES.get(st, String(st).capitalize())


func _render_recipe_book() -> void:
	for c in _quest_list_container.get_children():
		c.queue_free()
	var stations := _station_order()
	if not stations.has(selected_station) and not stations.is_empty():
		selected_station = stations[0]
	for st: StringName in stations:
		var list := RecipeDB.get_station_exclusive_recipes(st)
		var known := 0
		for r: RecipeDef in list:
			if player == null or player.recipes == null or player.recipes.knows(r.id):
				known += 1
		var b := Button.new()
		b.text = "%s   %d / %d" % [_station_label(st), known, list.size()]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(300, 40)
		b.modulate = Color(1.0, 0.96, 0.80) if st == selected_station else Color(0.82, 0.80, 0.76)
		var s2: StringName = st
		b.pressed.connect(func() -> void:
			selected_station = s2
			refresh())
		_quest_list_container.add_child(b)
	_render_station_recipes(selected_station)


func _render_station_recipes(st: StringName) -> void:
	for c in _details_vbox.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = _station_label(st)
	title.theme_type_variation = &"InkLabel"
	title.add_theme_font_override("font", UiTheme.font(850))
	title.add_theme_font_size_override("font_size", 22)
	_details_vbox.add_child(title)
	var book: RecipeBook = player.recipes if player != null else null
	var hidden := 0
	for r: RecipeDef in RecipeDB.get_station_exclusive_recipes(st):
		var knows := book == null or book.knows(r.id)
		if not knows:
			hidden += 1
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_details_vbox.add_child(row)
		var lbl := Label.new()
		lbl.theme_type_variation = &"InkLabel"
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if knows:
			var parts: Array[String] = []
			for inp: Dictionary in r.inputs:
				var it: ItemDef = ItemDB.get_item(inp.item_id)
				parts.append("%d %s" % [int(inp.count), it.name if it != null else String(inp.item_id)])
			lbl.text = "%s
    %s" % [r.name, ", ".join(parts)]
		else:
			lbl.text = "??? · %s" % RecipeBook.source_of(r.id)
			lbl.modulate = Color(0.75, 0.72, 0.66)
		lbl.add_theme_font_size_override("font_size", 14)
		row.add_child(lbl)
		if knows and book != null and book.can_copy(r.id):
			var copy := Button.new()
			copy.text = "Copy to scroll"
			copy.tooltip_text = "Write recipe scroll · Costs 2 Shore Wheat"
			var rid: StringName = r.id
			copy.pressed.connect(func() -> void:
				if book.copy_scroll(rid, player.inventory):
					if main.get("hud") != null:
						main.hud.show_toast("Copied %s onto a scroll. Give it to a friend or sell it." % r.name)
				elif main.get("hud") != null:
					main.hud.show_toast("You need 2 Shore Wheat and a free inventory slot to write a scroll.")
				refresh())
			row.add_child(copy)
	if hidden > 0:
		var hint := Label.new()
		hint.theme_type_variation = &"Small"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = "%d still to find here. Scrolls you already know are kept, not read, so you can pass them on." % hidden
		_details_vbox.add_child(hint)


func _has_quest(list: Array[QuestDef], q_id: StringName) -> bool:
	for q in list:
		if q.id == q_id:
			return true
	return false


func _resolve_completed_def(id: StringName) -> QuestDef:
	# Check tutorial missions
	for i in Tutorial.MISSIONS.size():
		var m: Dictionary = Tutorial.MISSIONS[i]
		if m.id == id:
			var qd := QuestDef.new(m.id, m.title, Tutorial.NPC_NAME)
			for o: Array in m.objectives:
				var s := QuestDef.QuestStep.new(o[0], o[1], o[2], o[3])
				s.current_count = s.target_count
				s.is_completed = true
				qd.steps.append(s)
			var s_talk := QuestDef.QuestStep.new("Return to Wren", QuestDef.ObjectiveType.TALK_TO, Tutorial.NPC_ID, 1)
			s_talk.current_count = 1
			s_talk.is_completed = true
			qd.steps.append(s_talk)
			var items: Array = []
			for it: Array in m.rewards.get("items", []):
				items.append({"id": it[0], "count": it[1]})
			qd.rewards = {"brass_guilder": 0, "tide_scrip": 0, "items": items}
			return qd
	# Fallback dummy
	var fallback := QuestDef.new(id, String(id).capitalize(), "Wayfarer Notice")
	return fallback


func _make_quest_list_card(qd: QuestDef, is_selected: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"SlotSelected" if is_selected else &"Slot"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.custom_minimum_size = Vector2(300, 64)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 2)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cv)

	var t := Label.new()
	t.text = qd.title
	t.add_theme_font_override("font", UiTheme.font(800))
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", UiTheme.BRASS if is_selected else UiTheme.CREAM)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(t)

	var g := Label.new()
	g.text = "From: %s" % qd.giver_name
	g.theme_type_variation = &"Small"
	g.add_theme_font_size_override("font_size", 14)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(g)

	# Steps summary
	var done_steps := 0
	for s in qd.steps:
		if s.is_completed:
			done_steps += 1
	var status_lbl := Label.new()
	status_lbl.theme_type_variation = &"Small"
	status_lbl.add_theme_font_size_override("font_size", 14)
	var qm: QuestManager = main.get("quests") if main != null else null
	if qm != null and qm.paused_reward_quests.has(qd.id):
		status_lbl.text = "⏸ Rewards Paused · Inventory Full"
		status_lbl.add_theme_color_override("font_color", Color(1.0, 0.65, 0.38))
	elif current_tab == Tab.COMPLETED or qd.is_complete():
		status_lbl.text = "✓ Completed"
		status_lbl.add_theme_color_override("font_color", Color(0.68, 1.0, 0.74))
	else:
		status_lbl.text = "Objectives: %d/%d done" % [done_steps, qd.steps.size()]
		status_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(status_lbl)

	card.mouse_entered.connect(func() -> void:
		card.theme_type_variation = &"SlotSelected"
		card.self_modulate = Color(1.08, 1.04, 0.94)
	)
	card.mouse_exited.connect(func() -> void:
		card.theme_type_variation = &"SlotSelected" if (qd.id == selected_quest_id) else &"Slot"
		card.self_modulate = Color.WHITE
	)
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			selected_quest_id = qd.id
			refresh()
	)
	return card


func _render_details(qd: QuestDef) -> void:
	for c in _details_vbox.get_children():
		c.queue_free()

	if qd == null:
		var empty_lbl := Label.new()
		empty_lbl.theme_type_variation = &"InkLabel"
		empty_lbl.text = "Select a quest from the list to view its details."
		_details_vbox.add_child(empty_lbl)
		return

	var qm: QuestManager = main.get("quests") if main != null else null

	# Title & Giver Header
	var title_lbl := Label.new()
	title_lbl.text = qd.title
	title_lbl.theme_type_variation = &"InkLabel"
	title_lbl.add_theme_font_override("font", UiTheme.font(850))
	title_lbl.add_theme_font_size_override("font_size", 22)
	_details_vbox.add_child(title_lbl)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 14)
	_details_vbox.add_child(meta_row)

	var giver_lbl := Label.new()
	giver_lbl.theme_type_variation = &"InkLabel"
	giver_lbl.text = "Quest Giver: %s" % qd.giver_name
	giver_lbl.add_theme_font_size_override("font_size", 14)
	meta_row.add_child(giver_lbl)

	var status_badge := Label.new()
	status_badge.theme_type_variation = &"InkLabel"
	var is_paused := (qm != null and qm.paused_reward_quests.has(qd.id))
	if is_paused:
		status_badge.text = "Status: Rewards Paused · Inventory Full"
		status_badge.add_theme_color_override("font_color", Color(0.85, 0.42, 0.12))
	elif current_tab == Tab.COMPLETED or qd.is_complete():
		status_badge.text = "Status: Completed"
		status_badge.add_theme_color_override("font_color", Color(0.12, 0.48, 0.22))
	else:
		status_badge.text = "Status: In Progress"
		status_badge.add_theme_color_override("font_color", Color(0.48, 0.35, 0.12))
	status_badge.add_theme_font_size_override("font_size", 14)
	meta_row.add_child(status_badge)

	_details_vbox.add_child(HSeparator.new())

	# Story Lore / Description
	var lore_text := _get_lore_for_quest(qd)
	if lore_text != "":
		var story_lbl := Label.new()
		story_lbl.theme_type_variation = &"InkLabel"
		story_lbl.text = lore_text
		story_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		story_lbl.add_theme_font_size_override("font_size", 14)
		_details_vbox.add_child(story_lbl)
		_details_vbox.add_child(HSeparator.new())

	# Objectives Header
	var obj_head := Label.new()
	obj_head.theme_type_variation = &"InkLabel"
	obj_head.text = "Objectives:"
	obj_head.add_theme_font_override("font", UiTheme.font(800))
	obj_head.add_theme_font_size_override("font_size", 16)
	_details_vbox.add_child(obj_head)

	for s in qd.steps:
		var s_row := HBoxContainer.new()
		s_row.add_theme_constant_override("separation", 8)
		_details_vbox.add_child(s_row)

		var check_icon := Label.new()
		check_icon.theme_type_variation = &"InkLabel"
		check_icon.text = "  [✓]" if s.is_completed else "  [  ]"
		check_icon.add_theme_font_override("font", UiTheme.font(800))
		check_icon.add_theme_color_override("font_color", Color(0.15, 0.52, 0.25) if s.is_completed else UiTheme.INK)
		s_row.add_child(check_icon)

		var desc_lbl := Label.new()
		desc_lbl.theme_type_variation = &"InkLabel"
		desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var progress_str := (" (%d/%d)" % [s.current_count, s.target_count]) if s.target_count > 1 else ""
		desc_lbl.text = s.description + progress_str
		if s.is_completed:
			desc_lbl.add_theme_color_override("font_color", Color(0.25, 0.45, 0.28))
		s_row.add_child(desc_lbl)

	_details_vbox.add_child(HSeparator.new())

	# Rewards Section
	var r_head := Label.new()
	r_head.theme_type_variation = &"InkLabel"
	r_head.text = "Rewards:"
	r_head.add_theme_font_override("font", UiTheme.font(800))
	r_head.add_theme_font_size_override("font_size", 16)
	_details_vbox.add_child(r_head)

	var r_list := _get_reward_lines(qd)
	if r_list.is_empty():
		var no_r := Label.new()
		no_r.theme_type_variation = &"InkLabel"
		no_r.text = "  • Knowledge & gratitude"
		_details_vbox.add_child(no_r)
	else:
		for r_item in r_list:
			var r_row := HBoxContainer.new()
			r_row.add_theme_constant_override("separation", 8)
			_details_vbox.add_child(r_row)

			var bullet := Label.new()
			bullet.theme_type_variation = &"InkLabel"
			bullet.text = "  •"
			r_row.add_child(bullet)

			var r_lbl := Label.new()
			r_lbl.theme_type_variation = &"InkLabel"
			r_lbl.text = r_item
			r_row.add_child(r_lbl)

	if is_paused:
		_details_vbox.add_child(HSeparator.new())
		var claim_box := HBoxContainer.new()
		claim_box.add_theme_constant_override("separation", 8)
		_details_vbox.add_child(claim_box)

		var can_fit := (player != null and player.inventory != null and qm != null and qm.can_accept_rewards(player.inventory, qd))
		var claim_btn := Button.new()
		claim_btn.text = "Claim Rewards Now" if can_fit else "Inventory Full — Make Room in Bag to Claim"
		claim_btn.disabled = not can_fit
		claim_btn.pressed.connect(func() -> void:
			var qmgr: QuestManager = main.get("quests") if main != null else null
			if player != null and player.inventory != null and qmgr != null and qmgr.can_accept_rewards(player.inventory, qd):
				qmgr.paused_reward_quests.erase(qd.id)
				qmgr._complete_quest(qd.id, player.inventory)
				if player.hud != null:
					player.hud.show_toast("Claimed rewards for '%s'!" % qd.title)
				refresh()
		)
		claim_box.add_child(claim_btn)


func _get_lore_for_quest(qd: QuestDef) -> String:
	# Check tutorial missions for Wren's dialogue
	for m in Tutorial.MISSIONS:
		if m.id == qd.id:
			if qd.is_complete():
				return m.intro + "\n\nWren: \"" + m.done + "\""
			return m.intro
	if qd.id == &"story_first_hearth":
		return "Elder Brenda of the settlement needs shelter built before the high tides and harsh weather sweep over the coastal flats."
	elif qd.id == &"story_tide_tackle":
		return "Old Man Corin watches the tides. Harvest salt and catch fresh mackerel to replenish the coastal stores."
	elif qd.id == &"chore_winter_kale":
		return "Town Cook Barnaby needs fresh Tide Kale harvested from shore plots for the communal kettle."
	return ""


func _get_reward_lines(qd: QuestDef) -> Array[String]:
	var out: Array[String] = []
	var brass: int = int(qd.rewards.get("brass_guilder", 0))
	if brass > 0:
		out.append("%d Brass Guilders" % brass)
	var scrip: int = int(qd.rewards.get("tide_scrip", 0))
	if scrip > 0:
		out.append("%d Tide Scrips" % scrip)

	var items: Array = qd.rewards.get("items", [])
	for it in items:
		if it is Dictionary:
			var id := StringName(it.get("id", ""))
			var cnt := int(it.get("count", 1))
			var def := ItemDB.get_item(id)
			var n := def.name if def != null else String(id)
			out.append("%d %s" % [cnt, n])
		elif it is Array and it.size() >= 2:
			var id := StringName(it[0])
			var cnt := int(it[1])
			var def := ItemDB.get_item(id)
			var n := def.name if def != null else String(id)
			out.append("%d %s" % [cnt, n])

	# Check tutorial recipes
	for m in Tutorial.MISSIONS:
		if m.id == qd.id:
			for rid in m.rewards.get("recipes", []):
				var r := RecipeDB.get_recipe(rid)
				var r_name := r.name if r != null else String(rid)
				out.append("Recipe: %s" % r_name)
	return out
