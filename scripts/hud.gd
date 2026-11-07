class_name Hud
extends CanvasLayer
## Main menu, loading screen and in-game HUD, all on the shared UiTheme
## (driftwood plaques, brass, parchment, pixel icons). Public API used elsewhere:
##   show_toast, set_prompt, show_menu, set_loading, show_hud, update_hud, set_controller,
##   help (Control), minimap, signals solo_pressed / host_pressed / join_pressed.

signal solo_pressed
signal host_pressed
signal join_pressed(ip: String)

const TOOL_ICONS := [ItemIcons.Tool.PICKAXE, ItemIcons.Tool.HAMMER, ItemIcons.Tool.BLUEPRINT,
	ItemIcons.Tool.ROD, ItemIcons.Tool.HOE]
const TOOL_NAMES := ["Pickaxe", "Hammer", "Blueprints", "Rod", "Farm"]

var controller: ControllerManager

# menu / loading
var menu: Control
var status_label: Label
var ip_edit: LineEdit
var loading: Control
var loading_label: Label
var loading_bar: ProgressBar

# hud
var hud_root: Control
var clock_label: Label
var phase_label: Label
var phase_icon: TextureRect
var tide_label: Label
var tide_icon: TextureRect
var weather_label: Label
var weather_icon: TextureRect
var weather_row: HBoxContainer
var peers_label: Label
var fps_label: Label
var underwater: ColorRect
var toast: PanelContainer
var toast_label: Label
var prompt_container: HBoxContainer
var help: PanelContainer
var minimap: Minimap
var chart_frame: PanelContainer
var bottom_bar: VBoxContainer
var slots: Array = []
var slot_keys: Array = []
var info_label: Label
var info_icon: TextureRect
var vitality_panel: PanelContainer
var health_bar: ProgressBar
var health_label: Label
var stamina_bar: ProgressBar
var stamina_label: Label
var breath_row: HBoxContainer
var breath_bar: ProgressBar
var stomach_label: Label
var rested_label: Label

var _toast_t := 0.0
var _prompt_text := "\u0001"
var _help_type := -2


func _ready() -> void:
	layer = 10
	underwater = ColorRect.new()
	underwater.color = Color(0.10, 0.42, 0.48, 0.38)
	underwater.set_anchors_preset(Control.PRESET_FULL_RECT)
	underwater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	underwater.visible = false
	add_child(underwater)
	_build_hud()
	_build_menu()
	_build_loading()
	_rebuild_help()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--uishot="):
			_menu_shot(a.trim_prefix("--uishot="))


## Dev: `--uishot=DIR` saves the main menu and loading screen, then quits.
func _menu_shot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("ui_main_menu.png"))
	show_menu(false)
	set_loading(true, "Laying down sand and stone...", 0.45)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join("ui_loading.png"))
	get_tree().quit()


func set_controller(cm: ControllerManager) -> void:
	controller = cm
	_rebuild_help()


func _pad() -> bool:
	return controller != null and controller.current_type != ControllerManager.Type.KEYBOARD_MOUSE


func _glyph(action: StringName, kb: String) -> String:
	return controller.get_glyph(action) if _pad() else kb


# ---------------------------------------------------------------- builders

func _root_control() -> Control:
	var c := Control.new()
	UiTheme.prepare(c)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(c)
	return c


func _label(text: String, variation: StringName = &"", size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != &"":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _panel(parent: Control, variation: StringName = &"Plaque") -> VBoxContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v


func _row(parent: Control, sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	parent.add_child(h)
	return h


func _bar(parent: Control, variation: StringName, width := 160) -> ProgressBar:
	var b := ProgressBar.new()
	b.theme_type_variation = variation
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, 22)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- main menu

func _build_menu() -> void:
	menu = _root_control()
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.10, 0.13, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)

	# The village name sign over the menu board.
	var sign := _panel(col, &"")
	var title := _label("Brine's Hollow", &"Title", 58)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_child(title)
	var sub := _label("a co-op coastal voxel game", &"Small", 17)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign.add_child(sub)

	var board := _panel(col, &"Parchment")
	board.add_theme_constant_override("separation", 12)
	board.custom_minimum_size = Vector2(430, 0)
	for spec in [["Play Solo", func() -> void: solo_pressed.emit()],
			["Host Co-op", func() -> void: host_pressed.emit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(0, 52)
		b.pressed.connect(spec[1])
		board.add_child(b)
	var join_row := _row(board)
	ip_edit = LineEdit.new()
	ip_edit.text = "127.0.0.1"
	ip_edit.placeholder_text = "server address"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_row.add_child(ip_edit)
	var jb := Button.new()
	jb.text = "Join"
	jb.custom_minimum_size = Vector2(110, 52)
	jb.pressed.connect(func() -> void: join_pressed.emit(ip_edit.text.strip_edges()))
	join_row.add_child(jb)
	board.add_child(HSeparator.new())
	var low := _row(board)
	for spec in [["Settings", _open_settings], ["Quit", func() -> void: get_tree().quit()]]:
		var b := Button.new()
		b.text = spec[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(spec[1])
		low.add_child(b)
	status_label = _label("", &"InkLabel", 16)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	board.add_child(status_label)


func _open_settings() -> void:
	var m := get_parent()
	if m != null and "settings_menu" in m and m.settings_menu != null:
		m.settings_menu.open_settings()


# ---------------------------------------------------------------- loading

func _build_loading() -> void:
	loading = _root_control()
	loading.mouse_filter = Control.MOUSE_FILTER_STOP
	loading.visible = false
	var bg := ColorRect.new()
	bg.color = Color8(24, 52, 62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	loading.add_child(center)
	var v := _panel(center, &"")
	v.custom_minimum_size = Vector2(460, 0)
	v.add_theme_constant_override("separation", 12)
	var t := _label("Washing ashore...", &"Header", 28)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	loading_label = _label("", &"Small", 16)
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(loading_label)
	loading_bar = _bar(v, &"StaminaBar", 420)
	loading_bar.max_value = 1.0


# ---------------------------------------------------------------- in-game HUD

func _build_hud() -> void:
	hud_root = _root_control()
	hud_root.visible = false

	var cross := TextureRect.new()
	cross.texture = UiTheme.tex("crosshair")
	cross.set_anchors_preset(Control.PRESET_CENTER)
	cross.offset_left = -16
	cross.offset_top = -16
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(cross)

	# --- top-left: chronometer, tide, weather
	var tl := MarginContainer.new()
	tl.position = Vector2(14, 12)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(tl)
	var clock := _panel(tl)
	var r1 := _row(clock)
	phase_icon = UiTheme.icon(ItemIcons.hud_icon("sun"), 36)
	r1.add_child(phase_icon)
	clock_label = _label("08:00", &"Header", 28)
	r1.add_child(clock_label)
	phase_label = _label("DAY", &"Small", 15)
	phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r1.add_child(phase_label)
	var r2 := _row(clock, 6)
	tide_icon = UiTheme.icon(ItemIcons.hud_icon("tide_up"), 26)
	r2.add_child(tide_icon)
	tide_label = _label("", &"Small", 16)
	r2.add_child(tide_label)
	weather_row = _row(clock, 6)
	weather_icon = UiTheme.icon(ItemIcons.hud_icon("clear"), 26)
	weather_row.add_child(weather_icon)
	weather_label = _label("", &"Small", 16)
	weather_row.add_child(weather_label)

	# --- top-right: crew, stats, sea chart
	var tr := VBoxContainer.new()
	tr.anchor_left = 1.0
	tr.anchor_right = 1.0
	tr.offset_left = -360
	tr.offset_right = -14
	tr.offset_top = 12
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(tr)
	var crew := _row(tr, 6)
	crew.alignment = BoxContainer.ALIGNMENT_END
	crew.add_child(UiTheme.icon(ItemIcons.hud_icon("crew"), 26))
	peers_label = _label("Solo", &"Small", 16)
	crew.add_child(peers_label)
	fps_label = _label("", &"Small", 14)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.visible = false
	tr.add_child(fps_label)
	chart_frame = PanelContainer.new()
	chart_frame.theme_type_variation = &"Plaque"
	chart_frame.size_flags_horizontal = Control.SIZE_SHRINK_END
	chart_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.add_child(chart_frame)
	minimap = Minimap.new()
	chart_frame.add_child(minimap)
	chart_frame.visible = false

	# --- toast banner (top centre)
	var toast_anchor := CenterContainer.new()
	toast_anchor.anchor_right = 1.0
	toast_anchor.offset_top = 80
	toast_anchor.offset_bottom = 140
	toast_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(toast_anchor)
	toast = PanelContainer.new()
	toast.theme_type_variation = &"Plaque"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_anchor.add_child(toast)
	toast_label = _label("", &"", 20)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(toast_label)
	toast.visible = false

	# --- interaction prompt (just under the crosshair)
	var prompt_anchor := CenterContainer.new()
	prompt_anchor.anchor_top = 0.5
	prompt_anchor.anchor_bottom = 0.5
	prompt_anchor.anchor_right = 1.0
	prompt_anchor.offset_top = 40
	prompt_anchor.offset_bottom = 100
	prompt_anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(prompt_anchor)
	prompt_container = HBoxContainer.new()
	prompt_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_anchor.add_child(prompt_container)

	# --- bottom-left: vitality
	var bl := VBoxContainer.new()
	bl.anchor_top = 1.0
	bl.anchor_bottom = 1.0
	bl.offset_left = 14
	bl.offset_bottom = -14
	bl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bl)
	var vit := _panel(bl)
	vitality_panel = vit.get_parent() as PanelContainer
	var hr := _row(vit, 6)
	hr.add_child(UiTheme.icon(ItemIcons.hud_icon("heart"), 26))
	health_bar = _bar(hr, &"HealthBar")
	health_label = _label("", &"Small", 15)
	health_label.custom_minimum_size = Vector2(58, 0)
	hr.add_child(health_label)
	var sr := _row(vit, 6)
	sr.add_child(UiTheme.icon(ItemIcons.hud_icon("stamina"), 26))
	stamina_bar = _bar(sr, &"StaminaBar")
	stamina_label = _label("", &"Small", 15)
	stamina_label.custom_minimum_size = Vector2(58, 0)
	sr.add_child(stamina_label)
	breath_row = _row(vit, 6)
	breath_row.add_child(UiTheme.icon(ItemIcons.hud_icon("breath"), 26))
	breath_bar = _bar(breath_row, &"HealthBar")
	breath_bar.add_theme_stylebox_override("fill", UiTheme.box("bar_fill", 2, 0, 0, Color8(150, 226, 240)))
	breath_row.visible = false
	var fr := _row(vit, 6)
	fr.add_child(UiTheme.icon(ItemIcons.hud_icon("food"), 26))
	stomach_label = _label("", &"Small", 14)
	fr.add_child(stomach_label)
	rested_label = _label("Rested", &"Small", 14)
	rested_label.add_theme_color_override("font_color", UiTheme.TEAL)
	rested_label.visible = false
	vit.add_child(rested_label)

	# --- bottom-centre: tool context plaque + hotbar
	bottom_bar = VBoxContainer.new()
	bottom_bar.anchor_top = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.offset_bottom = -12
	bottom_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_bar.alignment = BoxContainer.ALIGNMENT_END
	bottom_bar.add_theme_constant_override("separation", 6)
	bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(bottom_bar)
	var ctx := PanelContainer.new()
	ctx.theme_type_variation = &"Plaque"
	ctx.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ctx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom_bar.add_child(ctx)
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 8)
	ctx.add_child(ch)
	info_icon = UiTheme.icon(null, 28)
	ch.add_child(info_icon)
	info_label = _label("", &"Small", 16)
	info_label.add_theme_color_override("font_color", UiTheme.CREAM)
	info_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(info_label)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 4)
	bottom_bar.add_child(bar)
	for i in TOOL_ICONS.size():
		var slot := PanelContainer.new()
		slot.theme_type_variation = &"Slot"
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_child(slot)
		var stack := Control.new()
		stack.custom_minimum_size = Vector2(52, 52)
		stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(stack)
		var ic := UiTheme.icon(ItemIcons.for_tool(TOOL_ICONS[i]), 52)
		stack.add_child(ic)
		var key := _label(str(i + 1), &"KeyLabel", 14)
		key.position = Vector2(-4, -8)
		stack.add_child(key)
		slots.append(slot)
		slot_keys.append(key)

	# --- help sheet (F1), rebuilt when the input device changes
	help = PanelContainer.new()
	help.theme_type_variation = &"Parchment"
	help.anchor_top = 0.5
	help.anchor_bottom = 0.5
	help.offset_left = 14
	help.offset_top = -150
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(help)


func _rebuild_help() -> void:
	if help == null:
		return
	var t := controller.current_type if controller != null else -1
	if t == _help_type:
		return
	_help_type = t
	for c in help.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	help.add_child(v)
	var head := _label("Controls   (F1 hides)", &"InkLabel", 20)
	head.add_theme_font_override("font", UiTheme.font(800))
	v.add_child(head)
	var g := GridContainer.new()
	g.columns = 4 if get_viewport().get_visible_rect().size.x >= 1200 else 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var rows: Array
	if _pad():
		rows = [["L Stick", "move"], ["R Stick", "look"], [_glyph(&"jump", "Space"), "jump / swim up"],
			[_glyph(&"use", "LMB"), "use tool / swing"], [_glyph(&"alt_use", "RMB"), "plant / eat / parry"],
			[_glyph(&"interact", "F"), "interact (hold: pick up)"], ["LB / RB", "change tool"],
			["D-Pad", "cycle item / brush"], [_glyph(&"rotate", "R"), "rotate"], [_glyph(&"menu_toggle", "Esc"), "menu"]]
	else:
		rows = [["WASD", "move"], ["Mouse", "look"], ["Space", "jump / swim up"], ["Shift", "sprint"],
			["LMB", "use tool / swing"], ["RMB", "plant / eat / parry"], ["F", "interact (hold: pick up)"],
			["1-5", "tools"], ["Q / E", "cycle item"], ["Z / X", "brush size"], ["R / G", "rotate / snap"],
			["C", "dodge"], ["Ctrl", "sneak"], ["V", "swap shoulder"], ["T", "fast-forward time"],
			["F3", "stats"], ["Esc", "menu"]]
	for r: Array in rows:
		g.add_child(UiTheme.keycap(r[0]))
		g.add_child(_label(r[1], &"InkLabel", 14))
	for key in slot_keys:
		(key as Label).visible = not _pad()


# ---------------------------------------------------------------- public API

## Prompt text like "F  Board rowboat" or "F  Step off      W/S  row" renders as key caps.
func set_prompt(text: String) -> void:
	if text == _prompt_text:
		return
	_prompt_text = text
	for c in prompt_container.get_children():
		c.queue_free()
	if text == "":
		return
	var plaque := PanelContainer.new()
	plaque.theme_type_variation = &"Plaque"
	plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_container.add_child(plaque)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	plaque.add_child(row)
	var groups := text.split("    ", false)
	for gi in groups.size():
		var part := groups[gi].strip_edges()
		if part == "":
			continue
		var idx := part.find("  ")
		if idx > 0 and idx <= 12:
			row.add_child(UiTheme.keycap(part.substr(0, idx)))
			row.add_child(_label(part.substr(idx).strip_edges(), &"", 17))
		else:
			row.add_child(_label(part, &"", 17))
		if gi < groups.size() - 1:
			row.add_child(_label("·", &"Small", 17))


func show_toast(text: String) -> void:
	toast_label.text = text
	_toast_t = 3.2


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


func _set_icon(r: TextureRect, key: String) -> void:
	if r.get_meta("k", "") != key:
		r.set_meta("k", key)
		r.texture = ItemIcons.hud_icon(key)


func update_hud(player: Player, sky: SkyCycle, peers_text: String, world: VoxelWorld, cam_under: bool) -> void:
	_toast_t -= get_process_delta_time()
	toast.modulate.a = clampf(_toast_t * 1.5, 0.0, 1.0)
	toast.visible = _toast_t > 0.0
	bottom_bar.visible = not player.is_seated()
	underwater.visible = cam_under
	_rebuild_help()

	# --- chronometer
	var t := sky.time_of_day
	var mins := int(t * 24.0 * 60.0)
	clock_label.text = "%02d:%02d" % [mins / 60, mins % 60]
	var phase := "NIGHT" if (t < 0.22 or t > 0.82) else ("DAWN" if t < 0.30 else ("DAY" if t < 0.70 else "DUSK"))
	phase_label.text = phase + ("  >>" if sky.time_scale > 1.0 else "")
	_set_icon(phase_icon, "moon" if phase == "NIGHT" else ("dawn" if phase in ["DAWN", "DUSK"] else "sun"))
	var rel := (sky.water_level_vox - VoxelWorld.SEA_MID) * VoxelWorld.VS
	var rising := sky.tide_trend() > 0
	_set_icon(tide_icon, "tide_up" if rising else "tide_down")
	var state := "high tide" if rel > 0.9 else ("low tide" if rel < -0.9 else ("rising" if rising else "ebbing"))
	tide_label.text = "Tide %+.1f m  ·  %s" % [rel, state]
	weather_row.visible = sky.has_method("weather_label")
	if weather_row.visible:
		var w: String = sky.weather_label()
		weather_label.text = w
		var wl := w.to_lower()
		var wi := "moon" if phase == "NIGHT" else "clear"
		if "storm" in wl: wi = "storm"
		elif "rain" in wl: wi = "rain"
		elif "fog" in wl: wi = "fog"
		elif "overcast" in wl or "cloud" in wl: wi = "cloud"
		_set_icon(weather_icon, wi)
	peers_label.text = peers_text

	# --- vitality
	if player.vitality != null:
		var vit: VitalityController = player.vitality
		health_bar.max_value = vit.get_max_hp()
		health_bar.value = vit.current_hp
		health_label.text = "%d/%d" % [int(ceil(vit.current_hp)), int(round(health_bar.max_value))]
		stamina_bar.max_value = vit.get_max_stamina()
		stamina_bar.value = vit.current_stamina
		stamina_label.text = "%d/%d" % [int(ceil(vit.current_stamina)), int(round(stamina_bar.max_value))]
		stamina_bar.modulate = Color(0.62, 0.70, 0.80) if vit.is_exhausted else Color.WHITE
		var max_b: float = vit.get_max_breath()
		breath_row.visible = cam_under or vit.current_breath < max_b - 0.5
		breath_bar.max_value = max_b
		breath_bar.value = vit.current_breath
		var meals: Array = vit.get_active_meals()
		if meals.is_empty():
			stomach_label.text = "Hungry"
		else:
			var parts := []
			for m in meals:
				parts.append("%s %dm" % [m.name, int(ceil(m.remaining_sec / 60.0))])
			stomach_label.text = "  ·  ".join(parts)
		rested_label.visible = vit.is_rested

	# --- sea chart (only with a chart in the map slot)
	var map_tier := 0
	var map_name := ""
	if player.inventory and player.inventory.is_minimap_enabled():
		var map_def: ItemDef = player.inventory.get_equipped_map_def()
		if map_def:
			map_name = map_def.name
			map_tier = int({&"parchment_shore_chart": 1, &"hydrographic_sea_chart": 2,
				&"master_chronometer_chart": 3}.get(map_def.id, 1))
	chart_frame.visible = map_tier > 0
	if map_tier > 0:
		if not minimap._texture_generated and world != null and world.gen != null:
			minimap.bake_chart_texture(world)
		var lm_list: Array = []
		if world != null and world.gen != null:
			lm_list.assign(world.gen.starter_spawns)
		var boat_pos_list: Array[Vector3] = []
		if player.boat != null:
			boat_pos_list.append(player.boat.position)
		minimap.update_state(map_tier, map_name, player.position,
			player.rig.yaw if player.rig != null else player.facing,
			sky.water_level_vox * VoxelWorld.VS, lm_list, boat_pos_list)

	# --- hotbar + tool context
	for i in slots.size():
		(slots[i] as PanelContainer).theme_type_variation = &"SlotSelected" if i == player.tool else &"Slot"
	var size_btn := "D-Pad U/D" if _pad() else "Z/X"
	var cycle_btn := "D-Pad L/R" if _pad() else "Q/E"
	var use_btn := _glyph(&"use", "LMB")
	var alt_btn := _glyph(&"alt_use", "RMB")
	var r: int = Player.BRUSHES[player.brush]
	var icon: Texture2D = ItemIcons.for_tool(TOOL_ICONS[clampi(player.tool, 0, TOOL_ICONS.size() - 1)])
	var text := ""
	match player.tool:
		0:
			text = "Dig  ·  brush %d   (%s size)" % [r * 2 + 1, size_btn]
		1:
			icon = ItemIcons.for_material(player.current_material())
			text = "%s  ·  brush %d   (%s material, %s size, %s pick)" % [
				Palette.NAMES[player.current_material()], r * 2 + 1, cycle_btn, size_btn, _glyph(&"pick", "MMB")]
		2:
			var pf: Dictionary = Prefabs.all()[player.prefab_id]
			text = "%s   (%s change, %s rotate, snap %s)" % [pf.name, cycle_btn, _glyph(&"rotate", "R"), "on" if player.snap else "off"]
		3:
			text = _fishing_text(player, use_btn)
		4:
			text = "Farm  ·  %s till / harvest   %s plant / eat   %s seed" % [use_btn, alt_btn, cycle_btn]
	var place_text: String = player.placement.hud_text() if player.placement != null else ""
	if place_text != "":
		text = place_text
		icon = ItemIcons.for_tool(ItemIcons.Tool.BLUEPRINT)
	info_label.text = text
	info_icon.texture = icon

	if fps_label.visible:
		var p := player.position / VoxelWorld.VS
		fps_label.text = "%d fps  ·  %dk verts\nvoxel %d, %d, %d" % [
			Engine.get_frames_per_second(), world.stats_vertices / 1000, p.x, p.y, p.z]


func _fishing_text(player: Player, use_btn: String) -> String:
	if player.fishing == null:
		return "Fishing rod"
	match player.fishing.current_state:
		FishingController.State.IDLE:
			return "Fishing rod  ·  aim at water, hold %s to cast" % use_btn
		FishingController.State.CASTING:
			return "Casting...  power %.0f%%  (release %s)" % [player.fishing_cast_power * 100.0, use_btn]
		FishingController.State.WAITING_FOR_BITE:
			return "Bobber out %.1f m  ·  waiting for a bite" % player.fishing.line_distance
		FishingController.State.NIBBLING:
			return "Nibble...  get ready"
		FishingController.State.HOOK_WINDOW:
			return "BITE!  press %s to hook" % use_btn
		FishingController.State.REELING:
			return "Reeling  %.1f m  ·  tension %.0f%%  (pulse %s)" % [
				player.fishing.line_distance, player.fishing.line_tension * 100.0, use_btn]
		FishingController.State.CAUGHT:
			return "Landed it!  (%s to cast again)" % use_btn
		FishingController.State.LOST:
			return "It slipped away  (%s to recast)" % use_btn
	return "Fishing rod"
