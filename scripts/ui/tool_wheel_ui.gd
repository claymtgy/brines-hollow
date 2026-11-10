class_name ToolWheelUI
extends Control
## Radial Tool Wheel for Steam Deck and Gamepad quick-switching.
## Allows rapid 8-way directional selection of tools, weapons, hammer, and nautical charts.

signal tool_selected(tool_slot_index: int, tool_id: StringName)

const RADIUS_OUTER := 140.0
const RADIUS_INNER := 50.0
const WEDGE_COUNT := 8

const WHEEL_ITEMS: Array[Dictionary] = [
	{"index": 0, "name": "Pickaxe", "icon": "⛏", "tag": &"pickaxe", "item": &"driftwood_pickaxe", "tool_enum": ItemIcons.Tool.PICKAXE},
	{"index": 1, "name": "Axe", "icon": "🪓", "tag": &"axe", "item": &"stone_axe", "tool_enum": ItemIcons.Tool.AXE},
	{"index": 2, "name": "Shovel", "icon": "♠", "tag": &"shovel", "item": &"stone_shovel", "tool_enum": ItemIcons.Tool.SHOVEL},
	{"index": 3, "name": "Hoe", "icon": "⌉", "tag": &"hoe", "item": &"stone_hoe", "tool_enum": ItemIcons.Tool.HOE},
	{"index": 4, "name": "Fishing Rod", "icon": "🎣", "tag": &"fishing_rod", "item": &"whittle_rod", "tool_enum": ItemIcons.Tool.ROD},
	{"index": 5, "name": "Weapon", "icon": "⚔", "tag": &"weapon", "item": &"rusty_cutlass", "tool_enum": ItemIcons.Tool.CUTLASS},
	{"index": 6, "name": "Build Hammer", "icon": "🔨", "tag": &"hammer", "item": &"none", "tool_enum": ItemIcons.Tool.HAMMER},
	{"index": 7, "name": "Sea Chart", "icon": "🧭", "tag": &"chart", "item": &"none", "tool_enum": ItemIcons.Tool.BLUEPRINT}
]

var player: Player
var selected_wedge: int = -1
var is_wheel_open: bool = false
var _center: Vector2 = Vector2.ZERO


func _init() -> void:
	visible = false
	mouse_filter = MOUSE_FILTER_IGNORE


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)


func open_wheel() -> void:
	is_wheel_open = true
	visible = true
	selected_wedge = -1
	_center = size * 0.5
	queue_redraw()


func close_wheel() -> int:
	var chosen := selected_wedge
	is_wheel_open = false
	visible = false
	if chosen >= 0 and chosen < WEDGE_COUNT:
		_apply_selection(chosen)
	queue_redraw()
	return chosen


func select_direction(dir: Vector2) -> int:
	if dir.length_squared() < 0.15:
		return selected_wedge

	# Calculate angle: 0 is Right, PI/2 is Down, PI is Left, -PI/2 is Up
	var ang := dir.angle()
	# Rotate so top (Up, -PI/2) is centered on wedge 0
	var normalized_ang := fposmod(ang + PI * 0.5 + (TAU / WEDGE_COUNT * 0.5), TAU)
	var wedge := int(normalized_ang / (TAU / WEDGE_COUNT)) % WEDGE_COUNT
	if wedge != selected_wedge:
		selected_wedge = wedge
		CombatAudio.play_sound("click", Vector3.ZERO)
		queue_redraw()
	return selected_wedge


func _apply_selection(wedge_idx: int) -> void:
	if wedge_idx < 0 or wedge_idx >= WHEEL_ITEMS.size():
		return
	var item_info: Dictionary = WHEEL_ITEMS[wedge_idx]
	var tag: StringName = item_info["tag"]
	var item_id: StringName = item_info["item"]

	if player == null:
		tool_selected.emit(wedge_idx, item_id)
		return

	match tag:
		&"hammer":
			player.tool = 1
			if player.hud != null and player.hud.has_method("show_toast"):
				player.hud.show_toast("Equipped: Building Hammer")
		&"chart":
			player.tool = 2
			if player.hud != null and player.hud.has_method("show_toast"):
				player.hud.show_toast("Equipped: Nautical Sea Chart")
		_:
			# Search hotbar / inventory for an item matching tag
			var slot_found := _find_hotbar_item_with_tag(tag)
			if slot_found >= 0:
				player.inventory.set_active_hotbar_index(slot_found)
				player.tool = 0
			else:
				# Default fallback tool switch
				player.tool = 0
			if player.hud != null and player.hud.has_method("show_toast"):
				player.hud.show_toast("Equipped: %s" % item_info["name"])

	tool_selected.emit(wedge_idx, item_id)


func _find_hotbar_item_with_tag(tag: StringName) -> int:
	if player == null or player.inventory == null:
		return -1
	for i in mini(8, player.inventory.slots.size()):
		var slot: ItemSlot = player.inventory.slots[i]
		if slot != null and not slot.is_empty():
			var def := ItemDB.get_item(slot.item_id)
			if def != null and (def.tags.has(tag) or def.id == tag):
				return i
	return -1


func _draw() -> void:
	if not visible:
		return
	_center = size * 0.5

	# Draw darkened vignette backdrop
	draw_circle(_center, RADIUS_OUTER + 25.0, Color(0.04, 0.08, 0.12, 0.75))

	var wedge_angle := TAU / float(WEDGE_COUNT)
	for i in WEDGE_COUNT:
		var start_ang := -PI * 0.5 - (wedge_angle * 0.5) + float(i) * wedge_angle
		var end_ang := start_ang + wedge_angle
		var is_active := (i == selected_wedge)

		var fill_color := Color(0.85, 0.65, 0.25, 0.65) if is_active else Color(0.12, 0.18, 0.24, 0.55)
		var border_color := Color(1.0, 0.88, 0.55, 0.95) if is_active else Color(0.3, 0.4, 0.45, 0.4)

		# Draw outer arc / wedge sector
		var points := PackedVector2Array()
		var steps := 8
		for s in steps + 1:
			var a := lerpf(start_ang, end_ang, float(s) / float(steps))
			points.append(_center + Vector2(cos(a), sin(a)) * RADIUS_OUTER)
		for s in range(steps, -1, -1):
			var a := lerpf(start_ang, end_ang, float(s) / float(steps))
			points.append(_center + Vector2(cos(a), sin(a)) * RADIUS_INNER)
		points.append(points[0])

		draw_colored_polygon(points, fill_color)
		draw_polyline(points, border_color, 2.0 if is_active else 1.0)

		# Draw wedge icon & label in the center of the arc
		var mid_ang := (start_ang + end_ang) * 0.5
		var label_pos := _center + Vector2(cos(mid_ang), sin(mid_ang)) * ((RADIUS_INNER + RADIUS_OUTER) * 0.5)
		var info: Dictionary = WHEEL_ITEMS[i]
		if info.has("tool_enum"):
			var tex: Texture2D = ItemIcons.for_tool(int(info["tool_enum"]))
			if tex != null:
				draw_texture_rect(tex, Rect2(label_pos - Vector2(16, 22), Vector2(32, 32)), false)
		draw_string(ThemeDB.fallback_font, label_pos + Vector2(-36, 17), String(info["name"]), HORIZONTAL_ALIGNMENT_CENTER, 72, 11, Color(1, 1, 1, 0.95))

	# Draw inner brass compass rose ring
	draw_circle(_center, RADIUS_INNER, Color(0.18, 0.14, 0.1, 0.85))
	draw_arc(_center, RADIUS_INNER, 0, TAU, 32, Color(0.9, 0.75, 0.35, 0.8), 2.0)
