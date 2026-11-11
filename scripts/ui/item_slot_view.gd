class_name ItemSlotView
extends PanelContainer
## One item square: icon, stack count in the corner, optional "have / need" badge.
## Shared by the Crafting screen (and, next, the Pack and Chest screens) so every
## grid in the game draws items the same way.

const COL_OK := Color8(150, 226, 160)
const COL_SHORT := Color8(240, 120, 100)

var item_id: StringName = &""
var count := 0
var _px := 44.0
var _icon: TextureRect
var _count_lbl: Label


func _init(p_px: float = 44.0) -> void:
	_px = p_px
	theme_type_variation = &"Slot"
	mouse_filter = Control.MOUSE_FILTER_PASS
	var box := Control.new()
	box.custom_minimum_size = Vector2(_px, _px)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_icon = UiTheme.icon(null, _px)
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_icon)
	_count_lbl = Label.new()
	_count_lbl.theme_type_variation = &"KeyLabel"
	_count_lbl.add_theme_font_size_override("font_size", 12 if _px < 40.0 else 13)
	_count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_count_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_count_lbl.position = Vector2(-8, 2)
	_count_lbl.size = Vector2(_px + 10, _px + 4)
	box.add_child(_count_lbl)


## Plain item with a stack count (count <= 1 hides the number).
func show_item(p_id: StringName, p_count: int = 1) -> ItemSlotView:
	item_id = p_id
	count = p_count
	_icon.texture = ItemIcons.for_item(p_id) if p_id != &"" else null
	_icon.modulate = Color.WHITE
	_count_lbl.text = str(p_count) if p_count > 1 else ""
	_count_lbl.remove_theme_color_override("font_color")
	tooltip_text = item_name(p_id)
	return self


## Ingredient view: shows "have/need", tinted red when short.
func show_need(p_id: StringName, have: int, need: int) -> ItemSlotView:
	show_item(p_id, 0)
	_count_lbl.text = "%d/%d" % [mini(have, 999), need]
	var ok := have >= need
	_count_lbl.add_theme_color_override("font_color", COL_OK if ok else COL_SHORT)
	_icon.modulate = Color.WHITE if ok else Color(1, 1, 1, 0.55)
	tooltip_text = "%s  -  have %d, need %d" % [item_name(p_id), have, need]
	return self


## Undiscovered item: dark silhouette.
func show_unknown(p_id: StringName) -> ItemSlotView:
	show_item(p_id, 0)
	_icon.modulate = Color(0.12, 0.09, 0.07, 0.75)
	tooltip_text = "Not yet discovered"
	return self


func set_selected(on: bool) -> void:
	theme_type_variation = &"SlotSelected" if on else &"Slot"
	_apply_padding()


var _pad := -1.0


## Tighter frame than the theme's default (for dense grids).
func set_padding(px: float) -> ItemSlotView:
	_pad = px
	_apply_padding()
	return self


func _apply_padding() -> void:
	if _pad < 0.0:
		return
	var base: StyleBox = UiTheme.get_theme().get_stylebox(&"panel", theme_type_variation)
	if base == null:
		return
	var sb: StyleBox = base.duplicate()
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sb.set_content_margin(side, _pad)
	add_theme_stylebox_override(&"panel", sb)


static func item_name(p_id: StringName) -> String:
	var d: ItemDef = ItemDB.get_item(p_id)
	return d.name if d != null else String(p_id).capitalize()
