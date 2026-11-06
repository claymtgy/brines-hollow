class_name Hud
extends CanvasLayer
## Menu, loading screen, hotbar, clock/tide readout, help, crosshair.

signal solo_pressed
signal host_pressed
signal join_pressed(ip: String)

const CREAM := Color(0.98, 0.94, 0.86)
const DIM := Color(0.85, 0.80, 0.72)

var menu: Control
var status_label: Label
var ip_edit: LineEdit
var loading: Control
var loading_label: Label
var loading_bar: ProgressBar
var hud_root: Control
var clock_label: Label
var tide_label: Label
var peers_label: Label
var slots: Array = []
var info_label: Label
var swatch: ColorRect
var help: PanelContainer
var fps_label: Label
var underwater: ColorRect
var toast: Label
var prompt: Label
var bottom_bar: VBoxContainer
var _toast_t := 0.0


class Crosshair:
	extends Control
	func _draw() -> void:
		var c := size * 0.5
		draw_circle(c, 3.2, Color(0, 0, 0, 0.35))
		draw_circle(c, 2.0, Color(1, 0.97, 0.9, 0.95))


func _ready() -> void:
	layer = 10
	var theme := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.11, 0.10, 0.74)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(12)
	sb.border_color = Color(0.95, 0.85, 0.65, 0.25)
	sb.set_border_width_all(1)
	theme.set_stylebox("panel", "PanelContainer", sb)
	theme.set_color("font_color", "Label", CREAM)
	theme.set_font_size("font_size", "Label", 16)
	var bn := StyleBoxFlat.new()
	bn.bg_color = Color(0.86, 0.55, 0.30)
	bn.set_corner_radius_all(8)
	bn.set_content_margin_all(10)
	var bh := bn.duplicate() as StyleBoxFlat
	bh.bg_color = Color(0.93, 0.64, 0.38)
	theme.set_stylebox("normal", "Button", bn)
	theme.set_stylebox("hover", "Button", bh)
	theme.set_stylebox("pressed", "Button", bh)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", Color(0.16, 0.10, 0.07))
	theme.set_color("font_hover_color", "Button", Color(0.12, 0.07, 0.05))
	theme.set_font_size("font_size", "Button", 18)

	underwater = ColorRect.new()
	underwater.color = Color(0.10, 0.42, 0.48, 0.38)
	underwater.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater.visible = false
	add_child(underwater)

	_build_hud(theme)
	_build_menu(theme)
	_build_loading(theme)


func _build_menu(theme: Theme) -> void:
	menu = Control.new()
	menu.theme = theme
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(menu)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.14, 0.18, 0.35)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(380, 0)
	panel.add_child(v)
	var title := Label.new()
	title.text = "Brine's Hollow"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "a co-op coastal voxel prototype"
	sub.add_theme_color_override("font_color", DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(HSeparator.new())
	var solo := Button.new()
	solo.text = "Play Solo"
	solo.pressed.connect(func() -> void: solo_pressed.emit())
	v.add_child(solo)
	var host := Button.new()
	host.text = "Host Co-op (port 24565)"
	host.pressed.connect(func() -> void: host_pressed.emit())
	v.add_child(host)
	var h := HBoxContainer.new()
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ip_edit)
	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(func() -> void: join_pressed.emit(ip_edit.text.strip_edges()))
	h.add_child(join)
	v.add_child(h)
	status_label = Label.new()
	status_label.add_theme_color_override("font_color", DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	v.add_child(status_label)


func _build_loading(theme: Theme) -> void:
	loading = Control.new()
	loading.theme = theme
	loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.visible = false
	add_child(loading)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.17, 0.21)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(center)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(420, 0)
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)
	var t := Label.new()
	t.text = "Washing ashore at Brine's Hollow..."
	t.add_theme_font_size_override("font_size", 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	loading_label = Label.new()
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_color_override("font_color", DIM)
	v.add_child(loading_label)
	loading_bar = ProgressBar.new()
	loading_bar.max_value = 1.0
	loading_bar.show_percentage = false
	loading_bar.custom_minimum_size = Vector2(0, 10)
	v.add_child(loading_bar)


func _build_hud(theme: Theme) -> void:
	hud_root = Control.new()
	hud_root.theme = theme
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.visible = false
	add_child(hud_root)

	var ch := Crosshair.new()
	ch.set_anchors_preset(Control.PRESET_FULL_RECT)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(ch)

	# Top-left: clock + tide
	var tl := PanelContainer.new()
	tl.position = Vector2(16, 16)
	hud_root.add_child(tl)
	var tlv := VBoxContainer.new()
	tl.add_child(tlv)
	clock_label = Label.new()
	clock_label.add_theme_font_size_override("font_size", 20)
	tlv.add_child(clock_label)
	tide_label = Label.new()
	tlv.add_child(tide_label)

	# Top-right: co-op status
	peers_label = Label.new()
	peers_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	peers_label.position = Vector2(-320, 18)
	peers_label.size = Vector2(300, 30)
	peers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	peers_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	peers_label.add_theme_constant_override("outline_size", 6)
	hud_root.add_child(peers_label)

	fps_label = Label.new()
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.position = Vector2(-320, 46)
	fps_label.size = Vector2(300, 60)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	fps_label.add_theme_constant_override("outline_size", 6)
	fps_label.visible = false
	hud_root.add_child(fps_label)

	# Bottom: hotbar + info
	var bottom := VBoxContainer.new()
	bottom_bar = bottom
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y = -20
	bottom.alignment = BoxContainer.ALIGNMENT_END
	hud_root.add_child(bottom)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	bottom.add_child(bar)
	for i in 3:
		var p := PanelContainer.new()
		var l := Label.new()
		l.text = ["1  Pickaxe", "2  Hammer", "3  Blueprints"][i]
		l.custom_minimum_size = Vector2(130, 0)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.add_child(l)
		bar.add_child(p)
		slots.append(p)
	var ip := PanelContainer.new()
	ip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(ip)
	var ih := HBoxContainer.new()
	ih.add_theme_constant_override("separation", 10)
	ip.add_child(ih)
	swatch = ColorRect.new()
	swatch.custom_minimum_size = Vector2(22, 22)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ih.add_child(swatch)
	info_label = Label.new()
	ih.add_child(info_label)

	# Help panel
	help = PanelContainer.new()
	help.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	help.position = Vector2(16, -170)
	hud_root.add_child(help)
	var hl := Label.new()
	hl.add_theme_font_size_override("font_size", 15)
	hl.text = """CONTROLS  (F1 to hide)
WASD  move     Shift  sprint     Space  jump / swim up
Mouse  look    Wheel  zoom    V  swap shoulder
LMB  use tool  MMB  pick material
1 / 2 / 3  Pickaxe / Hammer / Blueprints
Q / E  previous / next material or prefab
Z / X  brush size     R  rotate prefab     G  grid snap
Hold T  fast-forward time (watch the tide)
F3  stats     Esc  free mouse"""
	help.add_child(hl)

	toast = Label.new()
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-300, 90)
	toast.size = Vector2(600, 30)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	toast.add_theme_constant_override("outline_size", 8)
	hud_root.add_child(toast)

	# Context prompt (e.g. "F  Board rowboat"), just below the crosshair.
	prompt = Label.new()
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.position = Vector2(-300, 40)
	prompt.size = Vector2(600, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	prompt.add_theme_constant_override("outline_size", 8)
	hud_root.add_child(prompt)


func set_prompt(text: String) -> void:
	if prompt != null and prompt.text != text:
		prompt.text = text


func show_toast(text: String) -> void:
	toast.text = text
	_toast_t = 3.0


func show_menu(on: bool, status := "") -> void:
	menu.visible = on
	status_label.text = status


func set_loading(on: bool, text := "", frac := 0.0) -> void:
	loading.visible = on
	loading_label.text = text
	loading_bar.value = frac


func show_hud(on: bool) -> void:
	hud_root.visible = on


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_F1:
			help.visible = not help.visible
		elif e.keycode == KEY_F3:
			fps_label.visible = not fps_label.visible


func update_hud(player: Player, sky: SkyCycle, peers_text: String, world: VoxelWorld, cam_under: bool) -> void:
	_toast_t -= get_process_delta_time()
	bottom_bar.visible = not player.is_seated()
	toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	underwater.visible = cam_under
	var mins := int(sky.time_of_day * 24.0 * 60.0)
	clock_label.text = "%02d:%02d  %s" % [mins / 60, mins % 60, _phase_name(sky.time_of_day)]
	var rel := (sky.water_level_vox - VoxelWorld.SEA_MID) * VoxelWorld.VS
	var trend := "rising" if sky.tide_trend() > 0 else "falling"
	var arrow := "^" if sky.tide_trend() > 0 else "v"
	var state := "high tide" if rel > 0.9 else ("low tide" if rel < -0.9 else trend)
	tide_label.text = "Tide %s %+.1f m  (%s)%s" % [arrow, rel, state, "   >> fast-forward" if sky.time_scale > 1.0 else ""]
	peers_label.text = peers_text
	for i in 3:
		(slots[i] as PanelContainer).self_modulate = Color(1.6, 1.25, 0.8, 1.0) if player.tool == i else Color(1, 1, 1, 0.75)
	var r: int = Player.BRUSHES[player.brush]
	match player.tool:
		0:
			swatch.visible = false
			info_label.text = "Dig brush %d   (Z/X size)" % (r * 2 + 1)
		1:
			swatch.visible = true
			swatch.color = Palette.COLORS[player.current_material()]
			info_label.text = "%s   brush %d   (Q/E material, Z/X size, MMB pick)" % [
				Palette.NAMES[player.current_material()], r * 2 + 1]
		2:
			swatch.visible = false
			var pf: Dictionary = Prefabs.all()[player.prefab_id]
			info_label.text = "%s   (Q/E change, R rotate, G snap: %s)" % [pf.name, "on" if player.snap else "off"]
	if fps_label.visible:
		var p := player.position / VoxelWorld.VS
		fps_label.text = "%d fps   %d k verts\nvoxel %d, %d, %d" % [
			Engine.get_frames_per_second(), world.stats_vertices / 1000, p.x, p.y, p.z]


func _phase_name(t: float) -> String:
	if t < 0.22 or t > 0.82: return "night"
	if t < 0.30: return "dawn"
	if t < 0.70: return "day"
	return "dusk"
