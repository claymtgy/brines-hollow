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
var help_label: Label
var controller: ControllerManager
var fps_label: Label
var underwater: ColorRect
var toast: Label
var prompt: Label
var bottom_bar: VBoxContainer
var vitality_panel: PanelContainer
var health_bar: ProgressBar
var health_label: Label
var stamina_bar: ProgressBar
var stamina_label: Label
var breath_bar: ProgressBar
var stomach_label: Label
var rested_label: Label
var minimap: Minimap
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

	# Top-right: Diegetic Nautical Minimap (equipment-gated)
	minimap = Minimap.new()
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-210, 80)
	minimap.visible = false
	hud_root.add_child(minimap)

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
	const TOOL_LABELS := ["1  Pickaxe", "2  Hammer", "3  Blueprints", "4  Rod", "5  Farm"]
	for i in TOOL_LABELS.size():
		var p := PanelContainer.new()
		var l := Label.new()
		l.text = TOOL_LABELS[i]
		l.custom_minimum_size = Vector2(105, 0)
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
	help_label = Label.new()
	help_label.add_theme_font_size_override("font_size", 15)
	help.add_child(help_label)
	_update_help_text()

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

	_build_vitality_panel(theme)


func _build_vitality_panel(theme: Theme) -> void:
	vitality_panel = PanelContainer.new()
	vitality_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	vitality_panel.position = Vector2(16, -170)
	vitality_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_root.add_child(vitality_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	vitality_panel.add_child(v)

	# Health bar
	var hb_box := HBoxContainer.new()
	hb_box.add_theme_constant_override("separation", 6)
	v.add_child(hb_box)

	var h_icon := Label.new()
	h_icon.text = "♥"
	h_icon.add_theme_color_override("font_color", Color(0.95, 0.35, 0.35))
	h_icon.add_theme_font_size_override("font_size", 14)
	hb_box.add_child(h_icon)

	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(160, 12)
	health_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.18, 0.10, 0.10, 0.8)
	hp_bg.set_corner_radius_all(4)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.88, 0.25, 0.25)
	hp_fill.set_corner_radius_all(4)
	health_bar.add_theme_stylebox_override("background", hp_bg)
	health_bar.add_theme_stylebox_override("fill", hp_fill)
	hb_box.add_child(health_bar)

	health_label = Label.new()
	health_label.add_theme_font_size_override("font_size", 12)
	health_label.text = "25/25"
	hb_box.add_child(health_label)

	# Stamina bar
	var sb_box := HBoxContainer.new()
	sb_box.add_theme_constant_override("separation", 6)
	v.add_child(sb_box)

	var s_icon := Label.new()
	s_icon.text = "⚡"
	s_icon.add_theme_color_override("font_color", Color(0.95, 0.75, 0.25))
	s_icon.add_theme_font_size_override("font_size", 14)
	sb_box.add_child(s_icon)

	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(160, 12)
	stamina_bar.show_percentage = false
	var sta_bg := StyleBoxFlat.new()
	sta_bg.bg_color = Color(0.18, 0.16, 0.10, 0.8)
	sta_bg.set_corner_radius_all(4)
	var sta_fill := StyleBoxFlat.new()
	sta_fill.bg_color = Color(0.92, 0.72, 0.22)
	sta_fill.set_corner_radius_all(4)
	stamina_bar.add_theme_stylebox_override("background", sta_bg)
	stamina_bar.add_theme_stylebox_override("fill", sta_fill)
	sb_box.add_child(stamina_bar)

	stamina_label = Label.new()
	stamina_label.add_theme_font_size_override("font_size", 12)
	stamina_label.text = "50/50"
	sb_box.add_child(stamina_label)

	# Breath bar (visible underwater or when depleted)
	breath_bar = ProgressBar.new()
	breath_bar.custom_minimum_size = Vector2(160, 8)
	breath_bar.show_percentage = false
	var br_bg := StyleBoxFlat.new()
	br_bg.bg_color = Color(0.08, 0.15, 0.18, 0.8)
	br_bg.set_corner_radius_all(3)
	var br_fill := StyleBoxFlat.new()
	br_fill.bg_color = Color(0.28, 0.78, 0.88)
	br_fill.set_corner_radius_all(3)
	breath_bar.add_theme_stylebox_override("background", br_bg)
	breath_bar.add_theme_stylebox_override("fill", br_fill)
	breath_bar.visible = false
	v.add_child(breath_bar)

	# 3-Meal Satiety info
	stomach_label = Label.new()
	stomach_label.add_theme_font_size_override("font_size", 11)
	stomach_label.add_theme_color_override("font_color", DIM)
	v.add_child(stomach_label)

	# Rested buff indicator
	rested_label = Label.new()
	rested_label.add_theme_font_size_override("font_size", 11)
	rested_label.add_theme_color_override("font_color", Color(0.65, 0.90, 0.75))
	rested_label.text = "⚓ Sea-Breeze Rested (+50% Sta)"
	rested_label.visible = false
	v.add_child(rested_label)


func set_controller(cm: ControllerManager) -> void:
	controller = cm
	if controller:
		controller.controller_type_changed.connect(func(_type: ControllerManager.Type) -> void:
			_update_help_text()
		)
		_update_help_text()


func _update_help_text() -> void:
	if help_label == null:
		return
	if controller == null or controller.current_type == ControllerManager.Type.KEYBOARD_MOUSE:
		help_label.text = """CONTROLS  (F1 to hide)
WASD  move     Shift  sprint     Space  jump / swim up
Mouse  look    Wheel  zoom       V  swap shoulder
LMB  use tool  RMB  plant/alt    MMB  pick material
1-5  Pickaxe / Hammer / Blueprints / Rod / Farm
Q / E  previous / next material, prefab, or seed
Z / X  brush size     R  rotate prefab     G  grid snap
Hold T  fast-forward time (watch the tide)
F3  stats     Esc  free mouse"""
	elif controller.current_type == ControllerManager.Type.DUALSENSE:
		help_label.text = """CONTROLS (DUALSENSE)  (Touchpad / F1 to hide)
Left Stick  move           L3 / ○  sprint       ✕  jump / swim up
Right Stick  look          L1 / R1  cycle tool  R3  pick material
R2  use tool (dig/place/reel)  L2  plant seeds  □  board / interact
D-Pad L/R  cycle seed/prefab   D-Pad U/D  brush size
△  rotate prefab           Touchpad  grid snap  Options  menu"""
	else:
		help_label.text = """CONTROLS (XBOX)  (View / F1 to hide)
Left Stick  move           LS / B  sprint       A  jump / swim up
Right Stick  look          LB / RB  cycle tool  RS  pick material
RT  use tool (dig/place/reel)  LT  plant seeds  X  board / interact
D-Pad L/R  cycle seed/prefab   D-Pad U/D  brush size
Y  rotate prefab           View  grid snap      Menu  menu"""


func set_prompt(text: String) -> void:
	var formatted := text
	if controller != null:
		formatted = controller.format_prompt_for_active_device(text)
	if prompt != null and prompt.text != formatted:
		prompt.text = formatted


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

	# Update Vitality UI
	if player.vitality != null and vitality_panel != null:
		var vit: VitalityController = player.vitality
		var max_h: float = vit.get_max_hp()
		var max_s: float = vit.get_max_stamina()
		var max_b: float = vit.get_max_breath()

		health_bar.max_value = max_h
		health_bar.value = vit.current_hp
		health_label.text = "%d/%d" % [int(ceil(vit.current_hp)), int(round(max_h))]

		stamina_bar.max_value = max_s
		stamina_bar.value = vit.current_stamina
		stamina_label.text = "%d/%d" % [int(ceil(vit.current_stamina)), int(round(max_s))]

		# Breath bar visibility: when submerged or breath depleted
		var show_breath: bool = cam_under or vit.current_breath < max_b - 0.5
		breath_bar.visible = show_breath
		if show_breath:
			breath_bar.max_value = max_b
			breath_bar.value = vit.current_breath

		# Satiety stomach readout
		var meals: Array[Dictionary] = vit.get_active_meals()
		if meals.is_empty():
			stomach_label.text = "Stomach empty (25 HP / 50 Sta)"
		else:
			var parts: Array[String] = []
			for m in meals:
				var mins_rem: int = int(ceil(m.remaining_sec / 60.0))
				parts.append("%s (%dm)" % [m.name, mins_rem])
			stomach_label.text = "• " + " | ".join(parts)

		rested_label.visible = vit.is_rested

	# Update Minimap (Equipment-gated by dedicated map slot)
	if minimap != null:
		var map_tier := 0
		var map_name := ""
		if player.inventory and player.inventory.is_minimap_enabled():
			var map_def: ItemDef = player.inventory.get_equipped_map_def()
			if map_def:
				map_name = map_def.name
				if map_def.id == &"parchment_shore_chart":
					map_tier = 1
				elif map_def.id == &"hydrographic_sea_chart":
					map_tier = 2
				elif map_def.id == &"master_chronometer_chart":
					map_tier = 3

		if map_tier > 0 and not minimap._texture_generated and world != null and world.gen != null:
			minimap.bake_chart_texture(world)

		var lm_list: Array[Dictionary] = []
		if world != null and world.gen != null:
			lm_list = world.gen.starter_spawns

		var boat_pos_list: Array[Vector3] = []
		if player.boat != null:
			boat_pos_list.append(player.boat.position)

		minimap.update_state(
			map_tier,
			map_name,
			player.position,
			player.rig.yaw if player.rig != null else player.facing,
			sky.water_level_vox * VoxelWorld.VS if sky != null else 0.0,
			lm_list,
			boat_pos_list
		)

	for i in slots.size():
		(slots[i] as PanelContainer).self_modulate = Color(1.6, 1.25, 0.8, 1.0) if player.tool == i else Color(1, 1, 1, 0.75)
	var is_gamepad := controller != null and controller.current_type != ControllerManager.Type.KEYBOARD_MOUSE
	var use_btn: String = controller.get_glyph(&"use") if is_gamepad else "LMB"
	var alt_btn: String = controller.get_glyph(&"alt_use") if is_gamepad else "RMB"
	var cycle_btn: String = "D-Pad L/R" if is_gamepad else "Q/E"
	var size_btn: String = "D-Pad U/D" if is_gamepad else "Z/X"
	var pick_btn: String = controller.get_glyph(&"pick") if is_gamepad else "MMB"
	var rot_btn: String = controller.get_glyph(&"rotate") if is_gamepad else "R"
	var snap_btn: String = controller.get_glyph(&"snap") if is_gamepad else "G"

	var r: int = Player.BRUSHES[player.brush]
	match player.tool:
		0:
			swatch.visible = false
			info_label.text = "Dig brush %d   (%s size)" % [r * 2 + 1, size_btn]
		1:
			swatch.visible = true
			swatch.color = Palette.COLORS[player.current_material()]
			info_label.text = "%s   brush %d   (%s mat, %s size, %s pick)" % [
				Palette.NAMES[player.current_material()], r * 2 + 1, cycle_btn, size_btn, pick_btn]
		2:
			swatch.visible = false
			var pf: Dictionary = Prefabs.all()[player.prefab_id]
			info_label.text = "%s   (%s change, %s rotate, %s snap: %s)" % [
				pf.name, cycle_btn, rot_btn, snap_btn, "on" if player.snap else "off"]
		3:
			swatch.visible = false
			if player.fishing:
				match player.fishing.current_state:
					FishingController.State.IDLE:
						info_label.text = "Fishing Rod   (Aim at sea, hold [%s] to cast)" % use_btn
					FishingController.State.CASTING:
						info_label.text = "Casting... Power %.0f%%   (Release %s)" % [player.fishing_cast_power * 100.0, use_btn]
					FishingController.State.WAITING_FOR_BITE:
						info_label.text = "Bobber floating at %.1f m... Waiting for bite" % player.fishing.line_distance
					FishingController.State.NIBBLING:
						info_label.text = ">> NIBBLE! <<   Get ready to strike!"
					FishingController.State.HOOK_WINDOW:
						info_label.text = ">>> BITE! CLICK [%s] TO HOOK! <<<" % use_btn
					FishingController.State.REELING:
						info_label.text = "Reeling! Distance: %.1f m   Tension: %.0f%%   (Hold/Pulse %s)" % [
							player.fishing.line_distance, player.fishing.line_tension * 100.0, use_btn]
					FishingController.State.CAUGHT:
						info_label.text = "Fish landed!   (%s to cast again)" % use_btn
					FishingController.State.LOST:
						info_label.text = "Fish got away!   (%s to recast)" % use_btn
			else:
				info_label.text = "Fishing Rod"
		4:
			swatch.visible = false
			info_label.text = "Farm Hoe: [%s] Till/Harvest   [%s] Plant Seeds   [%s] Select Seed" % [
				use_btn, alt_btn, cycle_btn]
	if fps_label.visible:
		var p := player.position / VoxelWorld.VS
		fps_label.text = "%d fps   %d k verts\nvoxel %d, %d, %d" % [
			Engine.get_frames_per_second(), world.stats_vertices / 1000, p.x, p.y, p.z]


func _phase_name(t: float) -> String:
	if t < 0.22 or t > 0.82: return "night"
	if t < 0.30: return "dawn"
	if t < 0.70: return "day"
	return "dusk"
