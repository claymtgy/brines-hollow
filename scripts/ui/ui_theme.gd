class_name UiTheme
extends RefCounted
## The one theme for every screen: driftwood panels, brass trim, parchment, rope.
## Textures come from tools/gen_ui_assets.gd (pixel art drawn at 1x, stored at 3x).
## Usage:  root_control.theme = UiTheme.get_theme();  UiTheme.prepare(root_control)
## Variations: "Parchment" / "Plaque" / "Slot" / "SlotSelected" (PanelContainer),
##             "InkLabel" / "Header" / "Title" / "Small" (Label),
##             "HealthBar" / "StaminaBar" / "FoodBar" (ProgressBar)

const DIR := "res://assets/ui/"
const PX := 3   # screen pixels per art pixel in the stored textures

const CREAM := Color8(252, 242, 222)
const CREAM_DIM := Color8(214, 198, 170)
const INK := Color8(66, 46, 34)
const OUTLINE := Color8(30, 20, 15)
const BRASS := Color8(248, 214, 132)
const TEAL := Color8(150, 236, 220)
const HEALTH := Color8(222, 92, 78)
const STAMINA := Color8(240, 196, 70)
const FOOD := Color8(150, 196, 110)
const SELECTED_TINT := Color(1.3, 1.02, 0.55)

static var _theme: Theme
static var _font: FontFile
static var _fonts := {}


## Weighted cut of the bundled Adwaita Sans variable font (OFL-1.1).
static func font(weight: int = 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight]
	if _font == null:
		_font = load("res://assets/fonts/AdwaitaSans-Regular.ttf")
	var fv := FontVariation.new()
	fv.base_font = _font
	fv.variation_opentype = {"wght": weight}
	_fonts[weight] = fv
	return fv


## Pixel-art 9-slice: `m` = border in art pixels; content padding in screen pixels.
static func box(name: String, m: int, pad_x: float = -1.0, pad_y: float = -1.0, modulate := Color.WHITE) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(DIR + name + ".png")
	sb.texture_margin_left = m * PX
	sb.texture_margin_right = m * PX
	sb.texture_margin_top = m * PX
	sb.texture_margin_bottom = m * PX
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.content_margin_left = pad_x if pad_x >= 0.0 else m * PX
	sb.content_margin_right = pad_x if pad_x >= 0.0 else m * PX
	sb.content_margin_top = pad_y if pad_y >= 0.0 else m * PX
	sb.content_margin_bottom = pad_y if pad_y >= 0.0 else m * PX
	sb.modulate_color = modulate
	return sb


static func tex(name: String) -> Texture2D:
	return load(DIR + name + ".png")


## Call on every UI root: crisp pixel art at any UI scale.
static func prepare(root: Control) -> void:
	root.theme = get_theme()
	root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 18

	# --- panels
	t.set_stylebox("panel", "PanelContainer", box("panel_wood", 8, 26, 22))
	t.set_stylebox("panel", "Panel", box("panel_wood", 8))
	for v in ["Parchment", "Plaque", "Slot", "SlotSelected"]:
		t.set_type_variation(v, "PanelContainer")
	t.set_stylebox("panel", "Parchment", box("panel_parchment", 8, 28, 22))
	t.set_stylebox("panel", "Plaque", box("plaque", 6, 18, 12))
	t.set_stylebox("panel", "Slot", box("slot", 7, 10, 10))
	t.set_stylebox("panel", "SlotSelected", box("slot_selected", 7, 10, 10))

	# --- labels: cream with a dark outline reads on wood, water and sky alike
	for prop in [["font_color", CREAM], ["font_outline_color", OUTLINE], ["font_shadow_color", Color(0, 0, 0, 0.45)]]:
		t.set_color(prop[0], "Label", prop[1])
	t.set_constant("outline_size", "Label", 5)
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_type_variation("InkLabel", "Label")
	t.set_color("font_color", "InkLabel", INK)
	t.set_constant("outline_size", "InkLabel", 0)
	t.set_color("font_shadow_color", "InkLabel", Color(0, 0, 0, 0))
	t.set_type_variation("Header", "Label")
	t.set_font("font", "Header", font(800))
	t.set_font_size("font_size", "Header", 24)
	t.set_color("font_color", "Header", BRASS)
	t.set_constant("outline_size", "Header", 7)
	t.set_type_variation("Title", "Label")
	t.set_font("font", "Title", font(900))
	t.set_font_size("font_size", "Title", 48)
	t.set_color("font_color", "Title", BRASS)
	t.set_constant("outline_size", "Title", 12)
	t.set_constant("shadow_offset_y", "Title", 4)
	t.set_type_variation("Small", "Label")
	t.set_font_size("font_size", "Small", 15)
	t.set_color("font_color", "Small", CREAM_DIM)
	t.set_constant("outline_size", "Small", 4)

	# --- buttons (also the base look for OptionButton / MenuButton)
	for kind in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", kind, box("button", 7, 22, 10))
		t.set_stylebox("hover", kind, box("button_hover", 7, 22, 10))
		# Pressed doubles as "selected" for toggle buttons (page tabs, filters): a warm
		# brass tint and brass text so the current tab reads at a glance.
		t.set_stylebox("pressed", kind, box("button_pressed", 7, 22, 10, SELECTED_TINT))
		t.set_stylebox("hover_pressed", kind, box("button_pressed", 7, 22, 10, SELECTED_TINT.lightened(0.12)))
		t.set_stylebox("disabled", kind, box("button_disabled", 7, 22, 10))
		t.set_stylebox("focus", kind, box("focus", 7))
		t.set_font(&"font", kind, font(700))
		t.set_font_size("font_size", kind, 19)
		t.set_color("font_color", kind, CREAM)
		t.set_color("font_hover_color", kind, Color(1, 0.98, 0.9))
		t.set_color("font_pressed_color", kind, BRASS)
		t.set_color("font_hover_pressed_color", kind, Color(1, 0.9, 0.62))
		t.set_color("font_focus_color", kind, Color(1, 0.98, 0.9))
		t.set_color("font_disabled_color", kind, Color(0.8, 0.78, 0.74, 0.7))
		t.set_color("font_outline_color", kind, OUTLINE)
		t.set_constant("outline_size", kind, 5)
	t.set_icon("arrow", "OptionButton", tex("arrow_down"))
	t.set_constant("arrow_margin", "OptionButton", 10)

	# --- popups / dropdown lists on parchment
	t.set_stylebox("panel", "PopupMenu", box("panel_parchment", 8, 14, 12))
	t.set_stylebox("hover", "PopupMenu", box("well", 4, 8, 4))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", CREAM)
	t.set_font_size("font_size", "PopupMenu", 18)
	t.set_stylebox("panel", "PopupPanel", box("panel_parchment", 8, 14, 12))
	t.set_stylebox("panel", "TooltipPanel", box("panel_parchment", 8, 12, 8))
	t.set_color("font_color", "TooltipLabel", INK)

	# --- tabs: parchment tab for the open page, dark wood for the rest
	t.set_stylebox("tab_selected", "TabContainer", box("tab_selected", 6, 18, 8))
	t.set_stylebox("tab_unselected", "TabContainer", box("tab_unselected", 6, 18, 8))
	t.set_stylebox("tab_hovered", "TabContainer", box("tab_hover", 6, 18, 8))
	t.set_stylebox("tab_focus", "TabContainer", box("focus", 7))
	t.set_stylebox("panel", "TabContainer", box("plaque", 6, 22, 18))
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_unselected_color", "TabContainer", CREAM_DIM)
	t.set_color("font_hovered_color", "TabContainer", CREAM)
	t.set_color("font_outline_color", "TabContainer", OUTLINE)
	t.set_constant("outline_size", "TabContainer", 0)
	t.set_font(&"font", "TabContainer", font(800))
	t.set_font_size("font_size", "TabContainer", 19)

	# --- toggles, sliders, bars, text fields, scrollbars, separators
	for kind in ["CheckBox", "CheckButton"]:
		t.set_icon("checked", kind, tex("check_on"))
		t.set_icon("unchecked", kind, tex("check_off"))
		t.set_icon("checked_disabled", kind, tex("check_on"))
		t.set_icon("unchecked_disabled", kind, tex("check_off"))
		for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(st, kind, StyleBoxEmpty.new())
		t.set_stylebox("focus", kind, box("focus", 7))
		t.set_color("font_color", kind, CREAM)
	t.set_stylebox("slider", "HSlider", box("rope_track", 2, 0, 6))
	t.set_icon("grabber", "HSlider", tex("knob"))
	t.set_icon("grabber_highlight", "HSlider", tex("knob_hl"))
	t.set_stylebox("grabber_area", "HSlider", StyleBoxEmpty.new())
	t.set_stylebox("grabber_area_highlight", "HSlider", StyleBoxEmpty.new())
	t.set_stylebox("focus", "HSlider", box("focus", 7))
	t.set_stylebox("background", "ProgressBar", box("bar_bg", 3, 6, 6))
	t.set_stylebox("fill", "ProgressBar", box("bar_fill", 2, 0, 0, Color(0.7, 0.85, 0.95)))
	t.set_color("font_color", "ProgressBar", CREAM)
	for bar in [["HealthBar", HEALTH], ["StaminaBar", STAMINA], ["FoodBar", FOOD]]:
		t.set_type_variation(bar[0], "ProgressBar")
		t.set_stylebox("fill", bar[0], box("bar_fill", 2, 0, 0, bar[1]))
	t.set_stylebox("normal", "LineEdit", box("well", 4, 12, 8))
	t.set_stylebox("focus", "LineEdit", box("focus", 7))
	t.set_color("font_color", "LineEdit", CREAM)
	t.set_color("caret_color", "LineEdit", TEAL)
	t.set_stylebox("scroll", "VScrollBar", box("well", 4, 4, 4))
	t.set_stylebox("grabber", "VScrollBar", box("scroll_grabber", 2, 4, 4))
	t.set_stylebox("grabber_highlight", "VScrollBar", box("scroll_grabber", 2, 4, 4, Color(1.15, 1.1, 1.0)))
	t.set_stylebox("grabber_pressed", "VScrollBar", box("scroll_grabber", 2, 4, 4, Color(0.85, 0.8, 0.75)))
	var sep := box("rope_divider", 1, 0, 6)
	t.set_stylebox("separator", "HSeparator", sep)
	t.set_constant("separation", "HSeparator", 12)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 10)
	# key caps for prompts and the help sheet ("F", "LMB", "RT", ...)
	t.set_type_variation("KeyCap", "PanelContainer")
	t.set_stylebox("panel", "KeyCap", box("button", 7, 9, 2))
	t.set_type_variation("KeyLabel", "Label")
	t.set_font("font", "KeyLabel", font(800))
	t.set_font_size("font_size", "KeyLabel", 15)
	t.set_constant("outline_size", "KeyLabel", 4)
	_theme = t
	return t


## Keeps a centred modal panel on screen: if its laid-out size is bigger than the canvas
## (a 1280x720 / Steam Deck canvas with a wide page), the full-screen container that centres
## it is scaled down about the screen centre just enough to fit, with `margin` px to spare.
## Bigger screens stay 1:1. (Containers reset their children's scale, so the scale goes on
## the outermost container, whose parent is a plain Control.) Mouse input follows the scale.
static func keep_on_screen(panel: Control, margin := 12.0) -> void:
	var fit := func() -> void:
		if not panel.is_inside_tree():
			return
		var target: Control = panel
		while target.get_parent() is Container:
			target = target.get_parent() as Control
		if target == panel:
			return   # not centred by a container: nothing safe to scale
		var vp := target.get_viewport_rect().size
		var need := panel.get_combined_minimum_size()
		var k := minf(1.0, minf((vp.x - margin * 2.0) / maxf(need.x, 1.0), (vp.y - margin * 2.0) / maxf(need.y, 1.0)))
		if k >= 0.999:
			target.scale = Vector2.ONE
			return
		# An oversized child gets pinned to the container's top-left, so pick the pivot that
		# lands the panel's centre on the screen centre after scaling.
		var centre := panel.size * 0.5   # in the target's own (unscaled) coordinates
		var node: Control = panel
		while node != target:
			centre += node.position
			node = node.get_parent() as Control
		# The container grows to the oversized panel, so aim at the viewport centre, not its own.
		var screen := vp * 0.5 - target.position
		target.pivot_offset = (screen - centre * k) / (1.0 - k)
		target.scale = Vector2(k, k)
	panel.resized.connect(fit)
	panel.visibility_changed.connect(fit)
	var hook := func() -> void:
		var vp := panel.get_viewport()
		if vp != null and not vp.size_changed.is_connected(fit):
			vp.size_changed.connect(fit)
		fit.call_deferred()
	if panel.is_inside_tree():
		hook.call()
	else:
		panel.tree_entered.connect(hook, CONNECT_ONE_SHOT)


## A key-cap badge: [F]
static func keycap(text: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = &"KeyCap"
	var l := Label.new()
	l.theme_type_variation = &"KeyLabel"
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return p


## Icon sized for HUD rows (art is 48 px; shown at `px`).
static func icon(tex: Texture2D, px: float = 30.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r
